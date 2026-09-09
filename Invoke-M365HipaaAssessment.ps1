<#
.SYNOPSIS
    Runs M365-Assess and produces a HIPAA-mapped Microsoft 365 security
    posture assessment.

.DESCRIPTION
    Uses M365-Assess as the read-only Microsoft 365 collection engine and
    retains technical findings mapped by the M365-Assess registry to HIPAA
    Administrative Simplification requirements in 45 CFR Part 164.

    The assessment can include Microsoft 365 tenant configuration, Entra ID,
    Exchange Online, Intune, Defender/security, collaboration workloads,
    Power BI, hybrid configuration, licensing, and inventory evidence.

    This wrapper does not determine or certify organizational HIPAA
    compliance. It reports Microsoft 365 technical configuration findings
    that M365-Assess maps to HIPAA requirements.

.NOTES
    Requires PowerShell 7+ and M365-Assess.
    Optional: ImportExcel for future XLSX output.
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [ValidateSet('Tenant','Identity','Licensing','Email','Intune','Security','Collaboration',
                 'PowerBI','Hybrid','Inventory','ActiveDirectory','SOC2','ValueOpportunity','All')]
    [string[]]$Section = @(
        'Tenant',
        'Identity',
        'Licensing',
        'Email',
        'Intune',
        'Security',
        'Collaboration',
        'PowerBI',
        'Hybrid',
        'Inventory'
    ),

    [Parameter()]
    [string]$OutputFolder = '.\M365-HIPAA-Assessment-Output',

    [Parameter()]
    [switch]$UseDeviceCode,

    [Parameter()]
    [switch]$OpenReport,

    [Parameter()]
    [string]$ExistingAssessmentFolder,

    [Parameter()]
    [string]$M365AssessModulePath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
$configPath = Join-Path $scriptRoot 'config.json'

if (-not (Test-Path $configPath)) {
    throw "config.json was not found beside the script: $configPath"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

# Load local functions.
Get-ChildItem (Join-Path $scriptRoot 'Functions') -Filter '*.ps1' |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

# Resolve M365-Assess.
if ($M365AssessModulePath) {
    $manifest = if (Test-Path $M365AssessModulePath -PathType Leaf) {
        $M365AssessModulePath
    } else {
        Join-Path $M365AssessModulePath 'M365-Assess.psd1'
    }

    if (-not (Test-Path $manifest)) {
        throw "M365-Assess manifest not found at: $manifest"
    }

    Import-Module $manifest -Force
    $m365Module = Get-Module M365-Assess | Select-Object -First 1
}
else {
    $m365Module = Get-Module -ListAvailable -Name M365-Assess |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $m365Module) {
        throw @"
M365-Assess is not installed.

Install it first:
  Install-Module M365-Assess -Scope CurrentUser

Then rerun this script.
"@
    }

    $minimumVersion = [version]$config.m365AssessMinimumVersion
    if ($m365Module.Version -lt $minimumVersion) {
        Write-Warning "M365-Assess $($m365Module.Version) is installed; this wrapper was built for $minimumVersion or newer."
    }

    Import-Module $m365Module.Path -Force
    $m365Module = Get-Module M365-Assess | Select-Object -First 1
}

# Locate M365-Assess controls registry.
$controlsCandidates = @(
    (Join-Path $m365Module.ModuleBase 'controls'),
    (Join-Path $m365Module.ModuleBase 'src\M365-Assess\controls'),
    (Join-Path (Split-Path $m365Module.ModuleBase -Parent) 'controls')
)

$controlsPath = $controlsCandidates |
    Where-Object { Test-Path (Join-Path $_ 'registry.json') } |
    Select-Object -First 1

if (-not $controlsPath) {
    throw "Could not locate M365-Assess controls\registry.json under module base '$($m365Module.ModuleBase)'."
}

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$OutputFolder = (Resolve-Path $OutputFolder).Path

# Either reuse an existing M365-Assess folder, or perform a fresh assessment.
if ($ExistingAssessmentFolder) {
    if (-not (Test-Path $ExistingAssessmentFolder -PathType Container)) {
        throw "Existing assessment folder not found: $ExistingAssessmentFolder"
    }
    $assessmentFolder = (Resolve-Path $ExistingAssessmentFolder).Path
}
else {
    if (-not $TenantId) {
        throw "TenantId is required unless -ExistingAssessmentFolder is supplied."
    }

    # M365-Assess 2.12.0 can rename its assessment directory after authentication
    # when a GUID is supplied, while some collectors retain the original path.
    # v0.1 therefore requires the tenant's primary onmicrosoft.com domain for
    # fresh collection runs.
    if ($TenantId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw "For a fresh assessment, supply the tenant primary domain (for example, contoso.onmicrosoft.com) instead of the tenant GUID."
    }

    $rawRoot = Join-Path $OutputFolder 'Raw-M365-Assess'
    New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

    Write-Host ''
    Write-Host '=== Running M365-Assess collection ===' -ForegroundColor Cyan
    Write-Host "Tenant : $TenantId"
    Write-Host "Section: $($Section -join ', ')"
    Write-Host ''

    $started = Get-Date

    $invokeParams = @{
        TenantId     = $TenantId
        Section      = $Section
        OutputFolder = $rawRoot
    }

    if ($UseDeviceCode) {
        $invokeParams.UseDeviceCode = $true
    }

    Invoke-M365Assessment @invokeParams

    # M365-Assess creates a timestamped assessment directory under OutputFolder.
    $assessmentFolder = Get-ChildItem $rawRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $started.AddMinutes(-2) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $assessmentFolder) {
        $assessmentFolder = Get-ChildItem $rawRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
    }

    if (-not $assessmentFolder) {
        throw "M365-Assess finished, but no assessment directory was found under: $rawRoot"
    }

    $assessmentFolder = $assessmentFolder.FullName
}

# Resolve a clean tenant label.
# Prefer M365-Assess provenance when re-processing an existing assessment.
$tenantLabel = $null

$provenanceFile = Get-ChildItem $assessmentFolder `
    -Filter '_Assessment-Provenance.json' `
    -File `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($provenanceFile) {
    try {
        $provenance = Get-Content $provenanceFile.FullName -Raw | ConvertFrom-Json

        if ($provenance.tenantPrimaryDomain) {
            $tenantLabel = [string]$provenance.tenantPrimaryDomain
        }
        elseif ($provenance.tenantDisplayName) {
            $tenantLabel = [string]$provenance.tenantDisplayName
        }
    }
    catch {
        Write-Verbose "Could not read tenant identity from provenance: $($_.Exception.Message)"
    }
}

if (-not $tenantLabel) {
    $tenantLabel = if ($TenantId) {
        $TenantId
    }
    else {
        Split-Path $assessmentFolder -Leaf
    }
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$reportFolder = Join-Path $OutputFolder "HIPAA_$stamp"

New-Item `
    -ItemType Directory `
    -Path $reportFolder `
    -Force |
    Out-Null

Write-Host ''
Write-Host '=== Building HIPAA-mapped findings ===' -ForegroundColor Cyan

$findings = @(
    Get-HipaaMappedFindings `
        -AssessmentFolder $assessmentFolder `
        -ControlsPath $controlsPath
)

if ($findings.Count -eq 0) {
    throw "No M365-Assess findings mapped to HIPAA were found."
}

#
# Detailed HIPAA findings
#

$allFindingsCsv = Join-Path `
    $reportFolder `
    'HIPAA-Findings.csv'

$findings |
    Sort-Object CheckId, Setting |
    Export-Csv `
        -Path $allFindingsCsv `
        -NoTypeInformation `
        -Encoding utf8

#
# HIPAA reference and section summaries
#

$hipaaReferenceSummary = Export-HipaaReferenceSummary `
    -Findings $findings `
    -OutputFolder $reportFolder

$hipaaSectionSummary = Export-HipaaSectionSummary `
    -Findings $findings `
    -ControlsPath $controlsPath `
    -OutputFolder $reportFolder

#
# Interactive standalone HTML report
#

$htmlPath = Join-Path `
    $reportFolder `
    'HIPAA-Assessment.html'

Export-HipaaHtmlReport `
    -Findings $findings `
    -SectionSummary $hipaaSectionSummary.Summary `
    -ReferenceSummary $hipaaReferenceSummary.Summary `
    -Path $htmlPath `
    -TenantLabel $tenantLabel `
    -Sections $Section `
    -SourceAssessmentFolder $assessmentFolder |
    Out-Null


#
# Assessment metadata / provenance
#

[PSCustomObject][ordered]@{
    GeneratedAt             = (Get-Date).ToString('o')
    Tenant                  = $tenantLabel
    Sections                = ($Section -join ', ')
    M365AssessVersion       = [string]$m365Module.Version
    M365AssessModuleBase    = $m365Module.ModuleBase
    SourceAssessmentFolder  = $assessmentFolder
    HipaaFrameworkId        = $config.frameworks.hipaa
    FindingCount            = $findings.Count
    HipaaReferencesObserved = @(
        $hipaaReferenceSummary.Summary
    ).Count

    HipaaSectionsRepresented = @(
        $hipaaSectionSummary.Summary |
            Where-Object { $_.MappedChecks -gt 0 }
    ).Count
    FormalComplianceClaim   = 'No - mapped Microsoft 365 technical findings only'
} |
    ConvertTo-Json -Depth 5 |
    Set-Content `
        -Path (Join-Path $reportFolder 'assessment-metadata.json') `
        -Encoding utf8

Write-Host ''
Write-Host '=== HIPAA package complete ===' -ForegroundColor Green
Write-Host "Output folder       : $reportFolder"
Write-Host "HTML report         : $htmlPath"
Write-Host "HIPAA findings      : $allFindingsCsv"
Write-Host "HIPAA reference summary: $($hipaaReferenceSummary.SummaryPath)"
Write-Host "HIPAA section summary  : $($hipaaSectionSummary.SummaryPath)"
Write-Host ''
Write-Host 'Important: this report contains Microsoft 365 technical findings mapped to HIPAA requirements. It is not a formal determination of organizational HIPAA compliance.' -ForegroundColor Yellow

[PSCustomObject]@{
    OutputFolder        = $reportFolder
    HtmlReport          = $htmlPath
    FindingsCsv         = $allFindingsCsv
    ReferenceSummaryCsv = $hipaaReferenceSummary.SummaryPath
    SectionSummaryCsv   = $hipaaSectionSummary.SummaryPath
    FindingCount        = $findings.Count
    HipaaReferenceCount = @($hipaaReferenceSummary.Summary).Count
    HipaaSectionCount   = @(
        $hipaaSectionSummary.Summary |
            Where-Object { $_.MappedChecks -gt 0 }
    ).Count
}
