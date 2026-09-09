function Export-NistComplianceMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter()]
        [object[]]$Nist80053Summary = @(),

        [Parameter()]
        [object[]]$NistCsfSummary = @(),

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$TenantLabel = 'Tenant',

        [Parameter()]
        [string]$SourceAssessmentFolder = ''
    )

    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Warning @"
ImportExcel is not installed, so XLSX output is being skipped.
Install it with:
  Install-Module ImportExcel -Scope CurrentUser
The CSV and HTML reports are still generated.
"@
        return $false
    }

    Import-Module ImportExcel -ErrorAction Stop

    if (Test-Path $Path) {
        Remove-Item $Path -Force
    }

    $matrix = $Findings |
        Select-Object CheckId, Setting, Category, Status, RiskSeverity, Source,
            Nist80053, NistCsf, ObservedValue, ExpectedValue, EvidenceSource,
            EvidenceTimestamp, CollectionMethod, Confidence, Limitations, Remediation

    $matrix |
        Export-Excel -Path $Path `
            -WorksheetName 'Findings' `
            -TableName 'NistFindings' `
            -AutoSize -FreezeTopRow -BoldTopRow

    @($Nist80053Summary) |
        Export-Excel -Path $Path `
            -WorksheetName '800-53 Summary' `
            -TableName 'Nist80053Summary' `
            -AutoSize -FreezeTopRow -BoldTopRow -Append

    @($NistCsfSummary) |
        Export-Excel -Path $Path `
            -WorksheetName 'CSF 2.0 Summary' `
            -TableName 'NistCsfSummary' `
            -AutoSize -FreezeTopRow -BoldTopRow -Append

    $metadata = @(
        [PSCustomObject]@{ Field = 'Tenant'; Value = $TenantLabel }
        [PSCustomObject]@{ Field = 'Generated'; Value = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss K') }
        [PSCustomObject]@{ Field = 'Source assessment folder'; Value = $SourceAssessmentFolder }
        [PSCustomObject]@{ Field = 'Framework 1'; Value = 'NIST SP 800-53 Rev. 5' }
        [PSCustomObject]@{ Field = 'Framework 2'; Value = 'NIST Cybersecurity Framework 2.0' }
        [PSCustomObject]@{ Field = 'Interpretation'; Value = 'Technical M365-Assess findings mapped to NIST references; not formal NIST compliance certification.' }
    )

    $metadata |
        Export-Excel -Path $Path `
            -WorksheetName 'Metadata' `
            -TableName 'AssessmentMetadata' `
            -AutoSize -BoldTopRow -Append

    return $true
}
