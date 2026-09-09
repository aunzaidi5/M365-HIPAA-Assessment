function Export-NistCsfReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [string]$OutputFolder
    )

    $functionNames = [ordered]@{
        GV = 'Govern'
        ID = 'Identify'
        PR = 'Protect'
        DE = 'Detect'
        RS = 'Respond'
        RC = 'Recover'
    }

    $mapped = @($Findings | Where-Object { -not [string]::IsNullOrWhiteSpace($_.NistCsf) })

    $findingsPath = Join-Path $OutputFolder 'NIST-CSF-2.0-Findings.csv'
    $mapped |
        Sort-Object CheckId, Setting |
        Export-Csv -Path $findingsPath -NoTypeInformation -Encoding utf8

    $functionControls = @{}
    $functionFindingKeys = @{}

    foreach ($finding in $mapped) {
        $controls = [regex]::Matches(
            [string]$finding.NistCsf,
            '\b(GV|ID|PR|DE|RS|RC)\.[A-Z]{2}-\d+\b',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        foreach ($match in $controls) {
            $controlId = $match.Value.ToUpperInvariant()
            $function = $match.Groups[1].Value.ToUpperInvariant()

            if (-not $functionControls.ContainsKey($function)) {
                $functionControls[$function] = [System.Collections.Generic.HashSet[string]]::new()
                $functionFindingKeys[$function] = [System.Collections.Generic.HashSet[string]]::new()
            }

            [void]$functionControls[$function].Add($controlId)
            [void]$functionFindingKeys[$function].Add("$($finding.CheckId)|$($finding.Setting)|$($finding.Source)")
        }
    }

    $summary = foreach ($function in $functionNames.Keys) {
        if (-not $functionFindingKeys.ContainsKey($function)) { continue }

        $functionFindings = @($mapped | Where-Object {
            $_.NistCsf -match "(?i)\b$function\."
        })

        [PSCustomObject][ordered]@{
            Function                 = $function
            FunctionName             = $functionNames[$function]
            UniqueSubcategoriesSeen  = $functionControls[$function].Count
            MappedFindings           = $functionFindingKeys[$function].Count
            Pass                     = @($functionFindings | Where-Object Status -eq 'Pass').Count
            Fail                     = @($functionFindings | Where-Object Status -eq 'Fail').Count
            Warning                  = @($functionFindings | Where-Object Status -eq 'Warning').Count
            Review                   = @($functionFindings | Where-Object Status -eq 'Review').Count
            Other                    = @($functionFindings | Where-Object { $_.Status -notin @('Pass','Fail','Warning','Review') }).Count
        }
    }

    $summaryPath = Join-Path $OutputFolder 'NIST-CSF-2.0-Function-Summary.csv'
    @($summary) | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding utf8

    [PSCustomObject]@{
        FindingsPath = $findingsPath
        SummaryPath  = $summaryPath
        Summary      = @($summary)
    }
}
