function Get-HipaaMappedFindings {
    <#
    .SYNOPSIS
        Reads M365-Assess evidence and returns findings mapped to HIPAA.

    .DESCRIPTION
        Uses the native HIPAA mappings contained in the M365-Assess
        control registry.

        This function reports Microsoft 365 technical findings mapped
        to HIPAA requirements. It does not independently determine
        organizational HIPAA compliance.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AssessmentFolder,

        [Parameter(Mandatory)]
        [string]$ControlsPath
    )

    function Get-PropertyValue {
        param(
            [object]$Object,
            [string]$Name,
            [object]$Default = ''
        )

        if ($null -eq $Object) {
            return $Default
        }

        $property = $Object.PSObject.Properties[$Name]

        if ($null -eq $property -or $null -eq $property.Value) {
            return $Default
        }

        return $property.Value
    }

    function Get-HipaaControlIds {
        param(
            [object]$Mapping
        )

        if ($null -eq $Mapping) {
            return @()
        }

        $controls = @()

        foreach ($mappingItem in @($Mapping)) {

            $controlId = [string](
                Get-PropertyValue `
                    -Object $mappingItem `
                    -Name 'controlId' `
                    -Default ''
            )

            if ([string]::IsNullOrWhiteSpace($controlId)) {
                continue
            }

            foreach ($id in ($controlId -split ';')) {

                $cleanId = $id.Trim()

                if (-not [string]::IsNullOrWhiteSpace($cleanId)) {
                    $controls += $cleanId
                }
            }
        }

        return @(
            $controls |
                Sort-Object -Unique
        )
    }

    if (-not (Test-Path $AssessmentFolder -PathType Container)) {
        throw "Assessment folder not found: $AssessmentFolder"
    }

    #
    # Load M365-Assess registry
    #

    $registryPath = Join-Path $ControlsPath 'registry.json'

    if (-not (Test-Path $registryPath)) {
        throw "M365-Assess control registry not found: $registryPath"
    }

    $registryRaw = Get-Content $registryPath -Raw |
        ConvertFrom-Json

    $registry = @{}

    foreach ($check in @($registryRaw.checks)) {

        if ($check.checkId) {
            $registry[[string]$check.checkId] = $check
        }
    }

    #
    # Load HIPAA framework definition
    #

    $frameworkPath = Join-Path `
        (Join-Path $ControlsPath 'frameworks') `
        'hipaa.json'

    if (-not (Test-Path $frameworkPath)) {
        throw "HIPAA framework definition not found: $frameworkPath"
    }

    $hipaaFramework = Get-Content $frameworkPath -Raw |
        ConvertFrom-Json

    #
    # Build HIPAA safeguard / group lookup
    #

    $hipaaGroups = @{}

    foreach ($group in $hipaaFramework.groups.PSObject.Properties) {
        $hipaaGroups[$group.Name] = [string]$group.Value
    }

    #
    # Optional M365-Assess risk severity overlay
    #

    $riskSeverity = @{}

    $riskPath = Join-Path $ControlsPath 'risk-severity.json'

    if (Test-Path $riskPath) {

        $riskRaw = Get-Content $riskPath -Raw |
            ConvertFrom-Json

        if ($riskRaw.checks) {

            foreach ($property in $riskRaw.checks.PSObject.Properties) {
                $riskSeverity[$property.Name] = [string]$property.Value
            }
        }
    }

    #
    # Determine successfully completed evidence collectors
    #

    $summaryFile = Get-ChildItem `
        $AssessmentFolder `
        -Filter '_Assessment-Summary*.csv' `
        -File `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    $sources = @()

    if ($summaryFile) {

        foreach ($item in @(Import-Csv $summaryFile.FullName)) {

            $status = [string](
                Get-PropertyValue $item 'Status'
            )

            $fileName = [string](
                Get-PropertyValue $item 'FileName'
            )

            if (
                $status -ne 'Complete' -or
                [string]::IsNullOrWhiteSpace($fileName)
            ) {
                continue
            }

            $csvPath = Join-Path $AssessmentFolder $fileName

            if (-not (Test-Path $csvPath -PathType Leaf)) {
                continue
            }

            $collector = [string](
                Get-PropertyValue `
                    $item `
                    'Collector' `
                    ([IO.Path]::GetFileNameWithoutExtension($fileName))
            )

            $sources += [PSCustomObject]@{
                Path      = $csvPath
                Collector = $collector
            }
        }
    }

    #
    # Fallback if summary file is absent
    #

    if ($sources.Count -eq 0) {

        $sources = @(
            Get-ChildItem `
                $AssessmentFolder `
                -Filter '*.csv' `
                -File `
                -Recurse |

            Where-Object {
                $_.Name -notlike '_Assessment-Summary*'
            } |

            ForEach-Object {
                [PSCustomObject]@{
                    Path      = $_.FullName
                    Collector = $_.BaseName
                }
            }
        )
    }

    $result = [System.Collections.Generic.List[object]]::new()

    #
    # Process collected M365 evidence
    #

    foreach ($source in $sources) {

        $rows = @(Import-Csv $source.Path)

        if ($rows.Count -eq 0) {
            continue
        }

        $columnNames = @(
            $rows[0].PSObject.Properties.Name
        )

        if ($columnNames -notcontains 'CheckId') {
            continue
        }

        foreach ($row in $rows) {

            $checkId = [string](
                Get-PropertyValue $row 'CheckId'
            )

            if ([string]::IsNullOrWhiteSpace($checkId)) {
                continue
            }

            #
            # Child findings such as CHECK-001.1 inherit
            # framework mappings from CHECK-001.
            #

            $baseCheckId = $checkId -replace '\.\d+$', ''

            if (-not $registry.ContainsKey($baseCheckId)) {
                continue
            }

            $entry = $registry[$baseCheckId]

            $frameworks = Get-PropertyValue `
                $entry `
                'frameworks' `
                $null

            if ($null -eq $frameworks) {
                continue
            }

            #
            # Read native HIPAA mapping
            #

            $hipaaMap = Get-PropertyValue `
                $frameworks `
                'hipaa' `
                $null

            $hipaaControls = @(
                Get-HipaaControlIds -Mapping $hipaaMap
            )

            if ($hipaaControls.Count -eq 0) {
                continue
            }

            #
            # Determine HIPAA section and safeguard family.
            #
            # Example:
            #
            #   164.312(a)(2)(i)
            #          ↓
            #         312
            #          ↓
            #   Technical Safeguards
            #

            $sectionIds = @()

            foreach ($control in $hipaaControls) {

                if ($control -match '^164\.(\d{3})') {
                    $sectionIds += $Matches[1]
                }
            }

            $sectionIds = @(
                $sectionIds |
                    Sort-Object -Unique
            )

            $safeguards = @()

            foreach ($sectionId in $sectionIds) {

                if ($hipaaGroups.ContainsKey($sectionId)) {
                    $safeguards += $hipaaGroups[$sectionId]
                }
                else {
                    $safeguards += "HIPAA 164.$sectionId"
                }
            }

            #
            # Remediation
            #

            $rowRemediation = [string](
                Get-PropertyValue $row 'Remediation'
            )

            $registryRemediation = [string](
                Get-PropertyValue $entry 'remediation'
            )

            if (-not [string]::IsNullOrWhiteSpace($rowRemediation)) {
                $remediation = $rowRemediation
            }
            else {
                $remediation = $registryRemediation
            }

            #
            # Risk severity
            #

            if ($riskSeverity.ContainsKey($baseCheckId)) {
                $severity = $riskSeverity[$baseCheckId]
            }
            else {
                $severity = 'Medium'
            }

            #
            # Produce normalized HIPAA finding
            #

            $result.Add(
                [PSCustomObject][ordered]@{

                    CheckId           = $checkId

                    BaseCheckId       = $baseCheckId

                    Setting           = [string](
                        Get-PropertyValue $row 'Setting'
                    )

                    Category          = [string](
                        Get-PropertyValue `
                            $row `
                            'Category' `
                            (Get-PropertyValue $entry 'category')
                    )

                    Status            = [string](
                        Get-PropertyValue `
                            $row `
                            'Status' `
                            'Unknown'
                    )

                    RiskSeverity      = $severity

                    Source            = [string]$source.Collector

                    HipaaControls     = (
                        $hipaaControls -join '; '
                    )

                    HipaaSections     = (
                        @(
                            $sectionIds |
                                ForEach-Object {
                                    "164.$_"
                                }
                        ) -join '; '
                    )

                    HipaaSafeguards   = (
                        $safeguards -join '; '
                    )

                    ObservedValue     = [string](
                        Get-PropertyValue $row 'ObservedValue'
                    )

                    ExpectedValue     = [string](
                        Get-PropertyValue $row 'ExpectedValue'
                    )

                    EvidenceSource    = [string](
                        Get-PropertyValue $row 'EvidenceSource'
                    )

                    EvidenceTimestamp = [string](
                        Get-PropertyValue $row 'EvidenceTimestamp'
                    )

                    CollectionMethod  = [string](
                        Get-PropertyValue $row 'CollectionMethod'
                    )

                    Confidence        = [string](
                        Get-PropertyValue $row 'Confidence'
                    )

                    Limitations       = [string](
                        Get-PropertyValue $row 'Limitations'
                    )

                    Remediation       = $remediation
                }
            )
        }
    }

    #
    # Remove only exact duplicate evidence identities.
    #

    $result |
        Sort-Object CheckId, Setting, Source -Unique
}
