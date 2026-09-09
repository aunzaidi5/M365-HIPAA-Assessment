function Export-HipaaReferenceSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [string]$OutputFolder
    )

    $expanded = foreach ($finding in $Findings) {

        $controls = @(
            ([string]$finding.HipaaControls -split ';') |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )

        foreach ($control in $controls) {

            $section = ''

            if ($control -match '^164\.(\d{3})') {
                $section = "164.$($Matches[1])"
            }

            [PSCustomObject]@{
                HipaaControl   = $control
                HipaaSection   = $section
                CheckId        = $finding.CheckId
                Status         = $finding.Status
                RiskSeverity   = $finding.RiskSeverity
                Setting        = $finding.Setting
                Source         = $finding.Source
            }
        }
    }

    $summary = foreach ($group in ($expanded | Group-Object HipaaControl)) {

        $items = @($group.Group)

        $pass    = @($items | Where-Object { $_.Status -eq 'PASS' }).Count
        $fail    = @($items | Where-Object { $_.Status -eq 'FAIL' }).Count
        $warning = @($items | Where-Object { $_.Status -eq 'WARNING' }).Count
        $review  = @($items | Where-Object { $_.Status -eq 'REVIEW' }).Count

        $evaluated = $pass + $fail + $warning

        $mappedCheckPassRate = if ($evaluated -gt 0) {
            [math]::Round(($pass / $evaluated) * 100, 1)
        }
        else {
            $null
        }

        [PSCustomObject][ordered]@{
            HipaaControl        = $group.Name
            HipaaSection        = ($items | Select-Object -First 1).HipaaSection
            MappedFindings      = $items.Count
            Pass                = $pass
            Fail                = $fail
            Warning             = $warning
            Review              = $review
            MappedCheckPassRate = $mappedCheckPassRate
        }
    }

    $summary = @(
        $summary |
            Sort-Object HipaaSection, HipaaControl
    )

    $summaryPath = Join-Path $OutputFolder 'HIPAA-Reference-Summary.csv'

    $summary |
        Export-Csv `
            -Path $summaryPath `
            -NoTypeInformation `
            -Encoding utf8

    return [PSCustomObject]@{
        Summary     = $summary
        SummaryPath = $summaryPath
    }
}
