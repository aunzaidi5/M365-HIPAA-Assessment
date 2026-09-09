# M365 HIPAA Assessment

A Microsoft 365 security posture assessment tool that collects tenant configuration evidence with **M365-Assess**, maps technical findings to **HIPAA Administrative Simplification requirements**, and produces an interactive HTML report plus supporting CSV/JSON evidence.

> **Important:** This project provides a technical Microsoft 365 posture assessment mapped to HIPAA requirements. It does **not** provide a legal opinion, certification, audit attestation, or formal determination of organizational HIPAA compliance.

## What it does

The tool runs a broad Microsoft 365 assessment across supported cloud workloads, normalizes M365-Assess findings, maps them to HIPAA references from the M365-Assess control registry, and produces a self-contained report package.

The default assessment scope includes:

- Tenant
- Identity
- Licensing
- Email
- Intune
- Security
- Collaboration
- Power BI
- Hybrid
- Inventory

The HIPAA framework view covers the Security, Privacy, and Breach Notification Rules represented in the M365-Assess HIPAA framework.

## Assessment flow

```text
Microsoft 365 tenant
        |
        v
Microsoft authentication
        |
        v
M365-Assess evidence collection
        |
        v
Microsoft 365 control evaluation
        |
        v
HIPAA registry mapping
        |
        v
Normalized HIPAA findings
        |
        +--> HIPAA-Assessment.html
        +--> HIPAA-Findings.csv
        +--> HIPAA-Reference-Summary.csv
        +--> HIPAA-Section-Summary.csv
        +--> assessment-metadata.json
```

A full Microsoft 365 run can request more than one Microsoft authentication session because separate workloads or PowerShell modules may require their own authenticated session. The web interface preserves assessment progress and resumes automatically after each required sign-in.

## Reporting model

The project intentionally separates **technical posture** from **formal compliance**.

### Findings

`HIPAA-Findings.csv` contains the normalized Microsoft 365 technical findings used by the report, including:

- Check ID
- Setting
- Category
- Status
- Risk severity
- Source
- HIPAA references
- HIPAA section / safeguard
- Observed and expected values
- Evidence metadata
- Limitations
- Remediation

### HIPAA reference summary

`HIPAA-Reference-Summary.csv` groups findings against granular HIPAA regulatory references such as:

```text
164.308(a)(3)(ii)(C)
164.312(a)(2)(i)
164.312(b)
```

A single Microsoft 365 check can map to more than one HIPAA reference.

### HIPAA section summary

`HIPAA-Section-Summary.csv` provides an executive-level view of top-level HIPAA sections such as:

- §164.308 — Administrative Safeguards
- §164.310 — Physical Safeguards
- §164.312 — Technical Safeguards
- §164.314 — Organizational Requirements
- §164.316 — Policies and Documentation
- Privacy Rule sections
- Breach Notification Rule sections

A section with zero mapped checks means that the automated Microsoft 365 assessment did **not establish technical evidence for that section**. It does not mean the section passed or failed.

### Mapped-check pass rate

The report uses a technical posture indicator:

```text
Pass / (Pass + Fail + Warning)
```

`Review` and `Info` findings are excluded from that denominator.

This value is labeled as a **mapped-check pass rate** and must not be interpreted as a HIPAA compliance percentage.

## Project structure

```text
M365-HIPAA-Assessment/
|
+-- Invoke-M365HipaaAssessment.ps1
+-- config.json
|
+-- Functions/
|   +-- Get-HipaaMappedFindings.ps1
|   +-- Export-HipaaReferenceSummary.ps1
|   +-- Export-HipaaSectionSummary.ps1
|   +-- Export-HipaaHtmlReport.ps1
|
+-- web/
|   +-- app.py
|   +-- templates/
|   |   +-- index.html
|   +-- static/
|       +-- app.js
|       +-- styles.css
|
+-- .gitignore
+-- README.md
```

Generated assessment results and local PowerShell dependencies are intentionally excluded from Git.

## Requirements

- macOS, Linux, or Windows with PowerShell 7
- Python 3
- Microsoft 365 tenant access with permissions required by the selected M365-Assess collectors
- M365-Assess **2.12.0**
- FastAPI / Uvicorn for the optional web interface

The current web application expects the local M365-Assess module at:

```text
.psmodules/M365-Assess/2.12.0
```

## Setup

Clone the repository:

```bash
git clone https://github.com/aunzaidi5/M365-HIPAA-Assessment.git
cd M365-HIPAA-Assessment
```

Create a Python virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

Install the web dependencies:

```bash
pip install fastapi uvicorn jinja2 pydantic
```

Download M365-Assess 2.12.0 into the project-local module directory:

```bash
pwsh -NoProfile -Command '
New-Item -ItemType Directory -Path "./.psmodules" -Force | Out-Null
Save-Module -Name M365-Assess -RequiredVersion 2.12.0 -Path "./.psmodules" -Force
'
```

Confirm the assessment engine is available:

```bash
pwsh -NoProfile -Command '
$localModules = (Resolve-Path "./.psmodules").Path
$env:PSModulePath = "$localModules$([IO.Path]::PathSeparator)$env:PSModulePath"

Import-Module "./.psmodules/M365-Assess/2.12.0/M365-Assess.psd1" -Force

Get-Command Invoke-M365Assessment
'
```

## Run the web interface

Start the HIPAA application:

```bash
uvicorn web.app:app --host 127.0.0.1 --port 8001
```

Open:

```text
http://127.0.0.1:8001
```

Enter the tenant's primary `onmicrosoft.com` domain, for example:

```text
contoso.onmicrosoft.com
```

Follow the Microsoft device-code authentication prompts. Additional authentication requests can occur when the assessment reaches Microsoft 365 workloads that require separate authenticated sessions.

For real assessment runs, running Uvicorn **without `--reload`** is recommended because job state is currently maintained in memory.

## Run from PowerShell

A direct CLI assessment can also be started without the FastAPI frontend:

```powershell
$localModules = (Resolve-Path "./.psmodules").Path
$env:PSModulePath = "$localModules$([IO.Path]::PathSeparator)$env:PSModulePath"

./Invoke-M365HipaaAssessment.ps1 `
    -TenantId "contoso.onmicrosoft.com" `
    -UseDeviceCode `
    -OutputFolder "./M365-HIPAA-Assessment-Output" `
    -M365AssessModulePath "./.psmodules/M365-Assess/2.12.0"
```

The wrapper uses the project's default Microsoft 365 assessment scope unless `-Section` is supplied explicitly.

## Reuse an existing M365-Assess collection

For development and report testing, an existing raw M365-Assess assessment can be reused to avoid another full tenant collection:

```powershell
./Invoke-M365HipaaAssessment.ps1 `
    -ExistingAssessmentFolder "/path/to/Assessment_YYYYMMDD_HHMMSS_tenant" `
    -OutputFolder "./M365-HIPAA-Assessment-Output" `
    -M365AssessModulePath "./.psmodules/M365-Assess/2.12.0"
```

The existing assessment folder must contain the collector evidence CSV files with `CheckId` data. A folder containing only the M365-Assess summary/report files is not sufficient for HIPAA mapping.

## Output package

Each successful run creates a timestamped package:

```text
HIPAA_YYYYMMDD_HHMMSS/
|
+-- HIPAA-Assessment.html
+-- HIPAA-Findings.csv
+-- HIPAA-Reference-Summary.csv
+-- HIPAA-Section-Summary.csv
+-- assessment-metadata.json
```

### `HIPAA-Assessment.html`

Self-contained interactive report containing:

- Executive metrics
- Mapped-check posture indicator
- HIPAA rule and safeguard section cards
- Status and risk filtering
- Searchable findings
- Expandable regulatory mappings
- Remediation guidance

### `assessment-metadata.json`

Records assessment provenance such as:

- Tenant
- Generated timestamp
- Sections run
- M365-Assess version
- Source assessment folder
- HIPAA framework identifier
- Finding count
- HIPAA reference count
- HIPAA sections represented

## Web API

The FastAPI layer exposes:

```text
GET  /health
GET  /engine/status
POST /assessments
GET  /assessments/{assessment_id}
GET  /assessments/{assessment_id}/report
GET  /assessments/{assessment_id}/download/{artifact}
```

Assessment execution happens in a background worker while the browser polls the status endpoint.

## Security notes

- The application does not ask the user to enter a Microsoft password into the local web interface.
- Authentication is performed through Microsoft's device-code / workload authentication flows.
- Assessment output can contain tenant security configuration information and should be handled as sensitive data.
- Generated assessment output is excluded from Git through `.gitignore`.
- `.psmodules/`, `.venv/`, and local generated output should not be committed.

Before making the repository public, review the full Git history and confirm that no tenant exports, credentials, tokens, assessment packages, or customer-sensitive information have ever been committed.

## Current status

The current version has been validated end-to-end with:

```text
Tenant authentication
        ->
Microsoft 365 evidence collection
        ->
additional workload authentication when required
        ->
control evaluation
        ->
HIPAA mapping
        ->
interactive report generation
        ->
CSV / JSON evidence downloads
```

Current development priorities include:

- Improved multi-workload authentication messaging
- Report usability and regulatory-reference presentation
- Priority finding summaries
- Clearer evidence-gap presentation
- Additional packaging and documentation polish

## Built with

- [M365-Assess](https://github.com/Galvnyz/M365-Assess)
- PowerShell
- Microsoft Graph / Microsoft 365 PowerShell workloads
- FastAPI
- Python
- Vanilla JavaScript / HTML / CSS

## Disclaimer

This project maps automated Microsoft 365 technical findings to HIPAA requirements for security posture analysis.

It does **not** evaluate every administrative, physical, contractual, operational, privacy, breach-response, workforce, or legal requirement that may apply to a covered entity or business associate.

Use the results as technical evidence and remediation guidance within a broader HIPAA governance, risk, and compliance program.
