# Usage Guide

## Purpose

M365 HIPAA Assessment runs Microsoft 365 technical security checks through M365-Assess and maps the resulting findings to HIPAA Administrative Simplification requirements in 45 CFR Part 164.

It is designed to answer questions such as:

- What Microsoft 365 security findings were observed?
- Which findings map to HIPAA Security, Privacy, or Breach Notification requirements?
- Which mapped technical checks passed, failed, require warning, or require review?
- Which HIPAA sections have automated Microsoft 365 evidence represented?
- What remediation guidance is associated with a finding?

It is **not** a HIPAA certification or an organization-wide compliance determination.

## Default Assessment Scope

A fresh assessment uses the following Microsoft 365 sections by default:

```text
Tenant
Identity
Licensing
Email
Intune
Security
Collaboration
PowerBI
Hybrid
Inventory
```

Additional M365-Assess section values remain available through the PowerShell wrapper when explicitly supplied.

## Run Through the Web Interface

Start the application from the project root:

```bash
source .venv/bin/activate
uvicorn web.app:app --host 127.0.0.1 --port 8001
```

Open:

```text
http://127.0.0.1:8001
```

Select **Assess Your Tenant**, then enter the tenant's primary `onmicrosoft.com` domain:

```text
contoso.onmicrosoft.com
```

The local web application does not ask for your Microsoft password. Authentication is completed through Microsoft's sign-in experience.

## Authentication During a Full Run

A broad Microsoft 365 assessment can require multiple authenticated workload sessions.

The normal flow is:

```text
Start assessment
    |
    v
Microsoft authentication
    |
    v
Collect / evaluate Microsoft 365 evidence
    |
    +--> additional workload authentication if required
    |
    v
HIPAA mapping
    |
    v
Report generation
```

When a new device-code session is required, the web interface displays the new Microsoft authentication request and preserves the current assessment progress.

Some workloads behave differently. Purview / Security & Compliance can use `Connect-IPPSSession`, which may open a Microsoft browser sign-in automatically because that workload does not support the same device-code path. Complete the sign-in in the browser and return to the assessment; processing continues automatically.

## Progress Phases

The web application shows the assessment moving through these phases:

```text
Microsoft authentication connected
Collecting Microsoft 365 evidence
Evaluating Microsoft 365 controls
Mapping findings to HIPAA requirements
Building HIPAA assessment package
```

The progress display is derived from the PowerShell / M365-Assess process output and is intended as a best-effort indication of the current stage.

## Run Directly From PowerShell

The web interface is optional. The assessment can be run directly through the wrapper:

```powershell
$localModules = (Resolve-Path "./.psmodules").Path
$env:PSModulePath = "$localModules$([IO.Path]::PathSeparator)$env:PSModulePath"

./Invoke-M365HipaaAssessment.ps1 `
    -TenantId "contoso.onmicrosoft.com" `
    -UseDeviceCode `
    -OutputFolder "./M365-HIPAA-Assessment-Output" `
    -M365AssessModulePath "./.psmodules/M365-Assess/2.12.0"
```

To run a specific scope instead of the default scope, supply `-Section` explicitly. For example:

```powershell
./Invoke-M365HipaaAssessment.ps1 `
    -TenantId "contoso.onmicrosoft.com" `
    -Section Identity,Security,Email `
    -UseDeviceCode `
    -OutputFolder "./M365-HIPAA-Assessment-Output" `
    -M365AssessModulePath "./.psmodules/M365-Assess/2.12.0"
```

## Reuse Existing M365-Assess Evidence

During report development or mapping review, an existing completed M365-Assess evidence folder can be processed without collecting the tenant again:

```powershell
./Invoke-M365HipaaAssessment.ps1 `
    -ExistingAssessmentFolder "/path/to/Assessment_YYYYMMDD_HHMMSS_tenant" `
    -OutputFolder "./M365-HIPAA-Assessment-Output" `
    -M365AssessModulePath "./.psmodules/M365-Assess/2.12.0"
```

The existing folder must contain the collector evidence used for HIPAA mapping. A folder containing only a previously generated summary or HTML report is not sufficient.

## Output Package

A successful run produces a timestamped HIPAA package:

```text
HIPAA_YYYYMMDD_HHMMSS/
├── HIPAA-Assessment.html
├── HIPAA-Findings.csv
├── HIPAA-Reference-Summary.csv
├── HIPAA-Section-Summary.csv
└── assessment-metadata.json
```

### `HIPAA-Assessment.html`

The main interactive report.

It includes:

- executive metrics
- mapped-check posture
- finding status and risk views
- HIPAA rule / section summaries
- searchable findings
- filtering
- expandable evidence and remediation details
- regulatory reference mappings
- assessment boundary language

### `HIPAA-Findings.csv`

The normalized technical finding dataset used by the reporting layer.

Typical fields include:

- CheckId
- BaseCheckId
- Setting
- Category
- Status
- RiskSeverity
- Source
- HipaaControls
- HipaaSections
- HipaaSafeguards
- ObservedValue
- ExpectedValue
- EvidenceSource
- EvidenceTimestamp
- CollectionMethod
- Confidence
- Limitations
- Remediation

### `HIPAA-Reference-Summary.csv`

Groups observed findings against granular HIPAA references.

A single Microsoft 365 technical finding may appear against more than one HIPAA reference when the upstream registry maps it to multiple requirements.

### `HIPAA-Section-Summary.csv`

Summarizes findings by top-level HIPAA section.

A section with no mapped automated checks represents **no automated evidence established by this assessment**. It must not be interpreted as either a pass or a failure.

### `assessment-metadata.json`

Records assessment provenance such as:

- tenant
- generated timestamp
- selected sections
- M365-Assess version
- source assessment folder
- framework identifier
- finding count
- HIPAA references observed
- HIPAA sections represented

## Finding Statuses

The HIPAA reporting layer preserves M365-Assess technical finding statuses:

```text
Pass
Fail
Warning
Review
Info
```

These statuses describe Microsoft 365 technical checks. They are not legal conclusions about a HIPAA requirement.

## Mapped-Check Pass Rate

The report calculates the technical posture indicator as:

```text
Pass / (Pass + Fail + Warning)
```

`Review` and `Info` are excluded from the denominator.

This metric is intentionally described as a **mapped-check pass rate**. It is not a HIPAA compliance percentage.

## HIPAA Coverage Interpretation

The assessment can map technical Microsoft 365 evidence to requirements represented across the HIPAA Security Rule, Privacy Rule, and Breach Notification Rule.

The presence of a mapping means that a Microsoft 365 technical finding is relevant to that HIPAA reference. It does not mean the full legal, procedural, physical, contractual, or organizational requirement has been evaluated.

Likewise, the absence of automated evidence does not automatically indicate non-compliance. Some HIPAA requirements require evidence outside Microsoft 365 configuration, such as policies, workforce procedures, physical safeguards, contracts, documentation, interviews, incident response processes, or systems outside the assessed tenant.

## Web API

The FastAPI application exposes:

```text
GET  /health
GET  /engine/status
POST /assessments
GET  /assessments/{assessment_id}
GET  /assessments/{assessment_id}/report
GET  /assessments/{assessment_id}/download/{artifact}
```

The browser uses these routes to start an assessment, poll progress, open the generated HTML report, and download supporting evidence files.

## Sensitive Data Handling

Assessment output can contain tenant security configuration information and should be treated as sensitive.

Do not commit:

- raw assessment output
- generated HIPAA report packages
- tenant exports
- tokens
- credentials
- customer-sensitive evidence

The repository `.gitignore` excludes the standard local dependency and output paths used by this project.

## Assessment Boundary

M365 HIPAA Assessment provides technical Microsoft 365 evidence mapped to HIPAA requirements.

A complete HIPAA assessment may require additional administrative, physical, operational, contractual, privacy, breach-response, workforce, policy, and legal evidence. Use this project as a technical posture and remediation aid within a broader governance, risk, and compliance process.
