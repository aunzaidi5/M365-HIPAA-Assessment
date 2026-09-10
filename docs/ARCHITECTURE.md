# Architecture

## Purpose

M365 HIPAA Assessment is a Microsoft 365 technical security posture assessment wrapper built on top of [M365-Assess](https://github.com/Galvnyz/M365-Assess).

M365-Assess remains responsible for Microsoft 365 evidence collection and technical security checks. This project adds a dedicated HIPAA mapping, normalization, reporting, and local web experience on top of those findings.

The project does **not** determine, certify, or attest that an organization is HIPAA compliant. It produces Microsoft 365 technical evidence mapped to HIPAA Administrative Simplification requirements in 45 CFR Part 164.

## High-Level Architecture

```text
Browser
  |
  v
FastAPI local web application
  |
  v
Invoke-M365HipaaAssessment.ps1
  |
  v
M365-Assess 2.12.0
  |
  +--> Microsoft Graph / Entra ID
  +--> Exchange Online
  +--> Intune
  +--> Defender / Security workloads
  +--> Purview / Security & Compliance
  +--> Collaboration / Power BI / Hybrid / Inventory collectors
  |
  v
Raw M365-Assess assessment evidence
  |
  v
M365-Assess control registry + HIPAA framework mapping
  |
  v
Normalized HIPAA-mapped findings
  |
  +--> HIPAA-Assessment.html
  +--> HIPAA-Findings.csv
  +--> HIPAA-Reference-Summary.csv
  +--> HIPAA-Section-Summary.csv
  +--> assessment-metadata.json
```

## Main Components

### `Invoke-M365HipaaAssessment.ps1`

The PowerShell orchestration layer.

It can:

- launch a fresh M365-Assess collection
- reuse a previously completed M365-Assess evidence folder
- use the project-local M365-Assess module path
- locate the upstream M365-Assess control registry
- normalize and map collected findings to HIPAA references
- generate the HIPAA report package
- preserve tenant and assessment provenance

The default cloud assessment scope includes:

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

`ActiveDirectory`, `SOC2`, `ValueOpportunity`, and `All` remain available as explicit M365-Assess section values but are not part of the default HIPAA run.

### `Functions/Get-HipaaMappedFindings.ps1`

Reads M365-Assess result data and joins findings to the upstream control registry.

It normalizes finding data into fields used by the HIPAA reporting layer, including:

- Check ID and base Check ID
- Setting
- Category
- Status
- Risk severity
- Source
- HIPAA references
- HIPAA sections / safeguards
- Observed and expected values
- Evidence source and timestamp
- Collection method
- Confidence
- Limitations
- Remediation

A single Microsoft 365 finding can map to multiple granular HIPAA references.

### `Functions/Export-HipaaReferenceSummary.ps1`

Builds a summary grouped by granular HIPAA references such as:

```text
164.308(a)(3)(ii)(C)
164.312(a)(2)(i)
164.312(b)
```

The summary is evidence-oriented. It does not treat the HIPAA regulation as a simple checklist denominator.

### `Functions/Export-HipaaSectionSummary.ps1`

Builds an executive-level summary grouped by top-level HIPAA sections.

Examples include:

- §164.308 — Administrative Safeguards
- §164.310 — Physical Safeguards
- §164.312 — Technical Safeguards
- §164.314 — Organizational Requirements
- §164.316 — Policies and Documentation
- Privacy Rule sections
- Breach Notification Rule sections

A section with zero mapped automated checks is represented as an evidence gap rather than a pass or fail.

### `Functions/Export-HipaaHtmlReport.ps1`

Creates the self-contained interactive HTML assessment report.

The report includes:

- tenant and scope information
- generated timestamp
- finding totals
- failure and risk counts
- HIPAA references observed
- HIPAA sections represented
- mapped-check posture
- Security, Privacy, and Breach Notification section views
- searchable and filterable findings
- expandable finding details
- HIPAA regulatory mappings
- observed versus expected state
- remediation guidance
- assessment boundary disclaimer

## HIPAA Framework Source

The project does not invent its own HIPAA mappings.

HIPAA mappings are sourced from the HIPAA framework and control registry shipped with M365-Assess 2.12.0. The project uses the framework identifier:

```text
hipaa
```

The upstream mapping may associate one Microsoft 365 check with more than one HIPAA citation.

## Reporting Semantics

### Technical findings

The fundamental unit in the report is a Microsoft 365 technical finding. Findings preserve M365-Assess status values such as:

- Pass
- Fail
- Warning
- Review
- Info

### Mapped-check pass rate

The report's posture indicator is calculated as:

```text
Pass / (Pass + Fail + Warning)
```

`Review` and `Info` are excluded from that denominator.

This is a **mapped-check pass rate**, not a HIPAA compliance percentage.

### HIPAA reference coverage

HIPAA reference counts represent unique regulatory references observed in the mapped technical evidence. They are not a statement that every legal or operational requirement within those sections has been satisfied.

### Evidence gaps

A HIPAA section with no mapped automated Microsoft 365 checks means that the assessment did not establish technical evidence for that section. It does not mean the requirement passed or failed.

## Web Application

The local web interface is implemented with FastAPI, Jinja2, vanilla JavaScript, HTML, and CSS.

The browser starts an assessment through the FastAPI API and then polls the job status while the PowerShell process runs in a background thread.

Current routes include:

```text
GET  /
GET  /health
GET  /engine/status
POST /assessments
GET  /assessments/{assessment_id}
GET  /assessments/{assessment_id}/report
GET  /assessments/{assessment_id}/download/{artifact}
```

The web application keeps active job state in memory. For real assessment runs, start Uvicorn without `--reload`; restarting the application removes in-memory job state even though generated files remain on disk.

## Authentication Model

The application never asks the user to enter a Microsoft password into the local web interface.

Authentication is performed through Microsoft-provided authentication flows used by the underlying Microsoft 365 PowerShell workloads.

A broad assessment may require more than one authenticated workload session. Device-code prompts are surfaced in the local web interface and assessment progress is preserved while the user completes the sign-in.

Some workloads, notably Purview / Security & Compliance through `Connect-IPPSSession`, may fall back to a browser-based Microsoft sign-in because that workload does not support the same device-code path. After browser authentication completes, the assessment continues automatically.

## Assessment Data Flow

```text
1. User submits tenant primary onmicrosoft.com domain
2. FastAPI creates an in-memory assessment job
3. Background worker launches PowerShell
4. M365-Assess authenticates and collects workload evidence
5. PowerShell output is streamed into job state
6. Web UI reflects authentication and progress phases
7. M365-Assess output is mapped against HIPAA references
8. HIPAA summaries and HTML report are generated
9. FastAPI locates the completed package
10. Browser exposes the report and supporting downloads
```

## Output Layout

A web run is created under:

```text
M365-HIPAA-Assessment-Output/web-runs/{assessment_id}/
```

The HIPAA reporting layer creates a timestamped package containing:

```text
HIPAA_YYYYMMDD_HHMMSS/
├── HIPAA-Assessment.html
├── HIPAA-Findings.csv
├── HIPAA-Reference-Summary.csv
├── HIPAA-Section-Summary.csv
└── assessment-metadata.json
```

Raw M365-Assess evidence is retained under the assessment output folder for local evidence processing but is excluded from Git.

## Security Boundary

Microsoft 365 assessment output may contain sensitive security configuration information. Generated output, local PowerShell dependencies, virtual environments, and assessment logs are excluded from version control through `.gitignore`.

A technical Microsoft 365 scan cannot establish organization-wide HIPAA compliance on its own. A complete HIPAA program may require additional evidence covering policies, governance, workforce practices, physical safeguards, business associate arrangements, privacy operations, breach response, documentation, and systems outside Microsoft 365.
