# Installation Guide

## Requirements

M365 NIST Assessment v0.1 requires:

- PowerShell 7+
- Access to a Microsoft 365 / Microsoft Entra tenant
- Internet access to Microsoft Graph and PowerShell Gallery
- M365-Assess 2.12.0
- ImportExcel

Validated v0.1 environment:

- macOS
- PowerShell 7.6.5
- M365-Assess 2.12.0
- Microsoft Entra ID
- Identity assessment scope

## Clone

Clone the repository and enter the project directory:

    git clone https://github.com/aunzaidi5/m365-nist-assessment.git
    cd m365-nist-assessment
    pwsh

## Create isolated PowerShell module directory

Run inside PowerShell:

    New-Item -ItemType Directory -Path .psmodules -Force | Out-Null

    $projectModules = (Resolve-Path .psmodules).Path
    $env:PSModulePath = "$projectModules$([IO.Path]::PathSeparator)$env:PSModulePath"

## Install M365-Assess

v0.1 was validated against M365-Assess 2.12.0:

    Save-Module `
        -Name M365-Assess `
        -RequiredVersion 2.12.0 `
        -Path $projectModules `
        -Repository PSGallery `
        -Force

## Install ImportExcel

    Save-Module `
        -Name ImportExcel `
        -Path $projectModules `
        -Repository PSGallery `
        -Force

Verify:

    Get-Module -ListAvailable M365-Assess |
        Select-Object Name,Version,ModuleBase

Expected M365-Assess version:

    2.12.0

## Dry run

Use the tenant's real primary Microsoft 365 domain:

    Invoke-M365Assessment `
        -TenantId 'yourtenant.onmicrosoft.com' `
        -Section Identity `
        -DryRun

Do not literally use yourtenant.onmicrosoft.com. Replace it with the real tenant domain.

A dry run makes no connection and collects no tenant data.

## Run the Microsoft 365 Identity collection

    Invoke-M365Assessment `
        -TenantId 'yourtenant.onmicrosoft.com' `
        -Section Identity `
        -UseDeviceCode `
        -OutputFolder './output/vanilla'

Authentication is handled by Microsoft's sign-in flow. This project does not collect Microsoft passwords.

### Tenant domain requirement

For fresh v0.1 assessments using M365-Assess 2.12.0, use the primary tenant domain instead of the tenant GUID.

During validation, GUID-based execution exposed an upstream output-folder rename issue after tenant discovery. Domain-based execution avoids that path change.

## Generate the NIST-only package

Locate the latest completed assessment:

    $assessment = Get-ChildItem ./output/vanilla -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

Generate the NIST reports:

    .\Invoke-M365NistAssessment.ps1 `
        -ExistingAssessmentFolder $assessment.FullName `
        -Section Identity `
        -OutputFolder './output/nist' `
        -OpenReport

Processing an existing assessment does not require another Microsoft login.

## Output

The generated package includes:

- NIST-Assessment.html
- NIST-Findings.csv
- NIST-SP800-53-Findings.csv
- NIST-SP800-53-Family-Summary.csv
- NIST-CSF-2.0-Findings.csv
- NIST-CSF-2.0-Function-Summary.csv
- NIST-Compliance-Matrix.xlsx
- assessment-metadata.json

## Assessment boundary

This tool reports Microsoft 365 technical findings mapped to NIST references.

It does not claim formal NIST certification, complete SP 800-53 control coverage, complete organizational CSF coverage, or NIST SP 800-207 compliance.
