function Export-HipaaSectionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [string]$ControlsPath,

        [Parameter(Mandatory)]
        [string]$OutputFolder
    )

    $frameworkPath = Join-Path `
        (Join-Path $ControlsPath 'frameworks') `
        'hipaa.json'

    if (-not (Test-Path $frameworkPath)) {
        throw "HIPAA framework definition not found: $frameworkPath"
    }

    $framework = Get-Content $frameworkPath -Raw |
        ConvertFrom-Json

    #
    # Build HIPAA section metadata from the official
    # M365-Assess framework definition.
    #

    $sections = [ordered]@{}

    foreach ($property in $framework.scoring.criteria.PSObject.Properties) {

        # Normalise:
        # §164.308 -> 164.308
        $key = ([string]$property.Name) -replace '^§', ''

        $sections[$key] = [PSCustomObject]@{
            Key         = $key
            Label       = [string]$property.Value.label
            Description = [string]$property.Value.description
            Subpart     = [string]$property.Value.subpart
        }
    }

    $summary = foreach ($sectionKey in $sections.Keys) {

        $info = $sections[$sectionKey]

        #
        # Find all M365 findings mapped to this HIPAA section.
        #

        $sectionFindings = @(
            $Findings |
                Where-Object {
                    @(
                        ([string]$_.HipaaSections -split ';') |
                            ForEach-Object {
                                $_.Trim() -replace '^§', ''
                            }
                    ) -contains $sectionKey
                }
        )

        #
        # Native M365-Assess semantics:
        # status counts use unique CheckId values.
        #

        $scored = @(
            $sectionFindings |
                Where-Object {
                    $_.Status -notmatch '^(?i)Info$'
                } |
                Select-Object CheckId -Unique
        )

        $passed = @(
            $sectionFindings |
                Where-Object {
                    $_.Status -match '^(?i)Pass$'
                } |
                Select-Object CheckId -Unique
        )

        $failed = @(
            $sectionFindings |
                Where-Object {
                    $_.Status -match '^(?i)Fail$'
                } |
                Select-Object CheckId -Unique
        )

        $warning = @(
            $sectionFindings |
                Where-Object {
                    $_.Status -match '^(?i)Warning$'
                } |
                Select-Object CheckId -Unique
        )

        $review = @(
            $sectionFindings |
                Where-Object {
                    $_.Status -match '^(?i)Review$'
                } |
                Select-Object CheckId -Unique
        )

        #
        # Native HIPAA criteria-coverage semantics:
        # Covered = unique granular HIPAA references.
        #

        $coveredReferences = @(
            foreach ($finding in $sectionFindings) {

                foreach ($reference in (
                    [string]$finding.HipaaControls -split ';'
                )) {

                    $reference = $reference.Trim() -replace '^§', ''

                    if (
                        -not [string]::IsNullOrWhiteSpace($reference) -and
                        $reference.StartsWith($sectionKey)
                    ) {
                        $reference
                    }
                }
            }

        ) | Sort-Object -Unique

        $other = (
            $scored.Count -
            $passed.Count -
            $failed.Count -
            $warning.Count -
            $review.Count
        )

        if ($other -lt 0) {
            $other = 0
        }

        #
        # This is a posture indicator only.
        # It is NOT a HIPAA compliance percentage.
        #

        $passRateDenominator = (
            $passed.Count +
            $failed.Count +
            $warning.Count
        )

        $mappedCheckPassRate = if ($passRateDenominator -gt 0) {
            [math]::Round(
                ($passed.Count / $passRateDenominator) * 100,
                1
            )
        }
        else {
            $null
        }

        [PSCustomObject][ordered]@{
            HipaaSection        = $sectionKey
            Label               = $info.Label
            Subpart             = $info.Subpart
            Description         = $info.Description

            MappedChecks        = $scored.Count
            CoveredReferences   = @($coveredReferences).Count

            Pass                = $passed.Count
            Fail                = $failed.Count
            Warning             = $warning.Count
            Review              = $review.Count
            Other               = $other

            MappedCheckPassRate = $mappedCheckPassRate
        }
    }

    $summaryPath = Join-Path `
        $OutputFolder `
        'HIPAA-Section-Summary.csv'

    @($summary) |
        Export-Csv `
            -Path $summaryPath `
            -NoTypeInformation `
            -Encoding utf8

    return [PSCustomObject]@{
        Summary     = @($summary)
        SummaryPath = $summaryPath
    }
}
