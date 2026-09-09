function Export-Nist80053Report {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [string]$OutputFolder
    )

    $familyNames = [ordered]@{
        AC = 'Access Control'
        AT = 'Awareness and Training'
        AU = 'Audit and Accountability'
        CA = 'Assessment, Authorization and Monitoring'
        CM = 'Configuration Management'
        CP = 'Contingency Planning'
        IA = 'Identification and Authentication'
        IR = 'Incident Response'
        MA = 'Maintenance'
        MP = 'Media Protection'
        PE = 'Physical and Environmental Protection'
        PL = 'Planning'
        PM = 'Program Management'
        PS = 'Personnel Security'
        PT = 'PII Processing and Transparency'
        RA = 'Risk Assessment'
        SA = 'System and Services Acquisition'
        SC = 'System and Communications Protection'
        SI = 'System and Information Integrity'
        SR = 'Supply Chain Risk Management'
    }

    $mapped = @($Findings | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Nist80053) })

    $findingsPath = Join-Path $OutputFolder 'NIST-SP800-53-Findings.csv'
    $mapped |
        Sort-Object CheckId, Setting |
        Export-Csv -Path $findingsPath -NoTypeInformation -Encoding utf8

    $familyControls = @{}
    $familyFindingKeys = @{}

    foreach ($finding in $mapped) {
        $controls = [regex]::Matches(
            [string]$finding.Nist80053,
            '\b(AC|AT|AU|CA|CM|CP|IA|IR|MA|MP|PE|PL|PM|PS|PT|RA|SA|SC|SI|SR)-\d+(?:\(\d+\))?\b',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        foreach ($match in $controls) {
            $controlId = $match.Value.ToUpperInvariant()
            $family = $match.Groups[1].Value.ToUpperInvariant()

            if (-not $familyControls.ContainsKey($family)) {
                $familyControls[$family] = [System.Collections.Generic.HashSet[string]]::new()
                $familyFindingKeys[$family] = [System.Collections.Generic.HashSet[string]]::new()
            }

            [void]$familyControls[$family].Add($controlId)
            [void]$familyFindingKeys[$family].Add("$($finding.CheckId)|$($finding.Setting)|$($finding.Source)")
        }
    }

    $summary = foreach ($family in $familyNames.Keys) {
        if (-not $familyFindingKeys.ContainsKey($family)) { continue }

        $familyFindings = @($mapped | Where-Object {
            $_.Nist80053 -match "(?i)\b$family-\d+"
        })

        [PSCustomObject][ordered]@{
            Family             = $family
            FamilyName         = $familyNames[$family]
            UniqueControlsSeen = $familyControls[$family].Count
            MappedFindings     = $familyFindingKeys[$family].Count
            Pass               = @($familyFindings | Where-Object Status -eq 'Pass').Count
            Fail               = @($familyFindings | Where-Object Status -eq 'Fail').Count
            Warning            = @($familyFindings | Where-Object Status -eq 'Warning').Count
            Review             = @($familyFindings | Where-Object Status -eq 'Review').Count
            Other              = @($familyFindings | Where-Object { $_.Status -notin @('Pass','Fail','Warning','Review') }).Count
        }
    }

    $summaryPath = Join-Path $OutputFolder 'NIST-SP800-53-Family-Summary.csv'
    @($summary) | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding utf8

    [PSCustomObject]@{
        FindingsPath = $findingsPath
        SummaryPath  = $summaryPath
        Summary      = @($summary)
    }
}
