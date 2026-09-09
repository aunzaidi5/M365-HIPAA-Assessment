# Architecture

## Design Principle

M365 NIST Assessment does not replace the M365-Assess collection engine.

M365-Assess remains responsible for read-only Microsoft 365 evidence collection and technical security checks.

This project adds a dedicated NIST filtering and reporting layer on top of those findings.

## High-Level Architecture

    Microsoft 365 / Entra
            |
            v
       M365-Assess
            |
            v
    Technical findings
            |
            v
    controls/registry.json
            |
            +----------------------+
            |                      |
            v                      v
    NIST SP 800-53          NIST CSF 2.0
            |                      |
            +----------+-----------+
                       |
                       v
             Custom NIST reports

## Main Components

### Invoke-M365NistAssessment.ps1

Main orchestration script.

It can:

- launch a fresh M365-Assess assessment
- process an existing assessment folder
- locate the M365-Assess control registry
- generate the NIST-only reporting package
- preserve assessment provenance

### Get-NistMappedFindings.ps1

Reads M365-Assess collector CSV files and matches each finding to the upstream control registry.

It normalizes child CheckIds such as:

    ENTRA-AUTHMETHOD-001.1
    ENTRA-AUTHMETHOD-001.2

and associates findings with their corresponding framework mappings.

Only findings mapped to either NIST framework are retained.

### Export-Nist80053Report.ps1

Creates the NIST SP 800-53 focused outputs.

It:

- extracts SP 800-53 control references
- groups findings by control family
- counts unique controls observed
- summarizes finding status by family

### Export-NistCsfReport.ps1

Creates the NIST CSF 2.0 focused outputs.

It:

- extracts CSF 2.0 subcategory references
- groups findings by CSF function
- summarizes mapped findings and statuses

### Export-NistComplianceMatrix.ps1

Creates the XLSX reporting package containing NIST-oriented assessment data.

ImportExcel is used for workbook generation.

On some non-Windows platforms, ImportExcel may display harmless warnings about automatic column sizing.

### Export-NistHtmlReport.ps1

Creates the custom HTML report.

The report includes:

- tenant identity
- assessment scope
- NIST-mapped finding totals
- Pass / Fail / Warning / Review counts
- mapped-check pass rate
- SP 800-53 family summary
- CSF 2.0 function summary
- detailed mapped findings
- remediation guidance
- assessment boundary notice

## Framework Source

The project does not invent its own NIST control mappings.

Mappings are sourced from the M365-Assess control registry.

The relevant framework IDs are:

    nist-800-53
    nist-csf

Other M365-Assess framework mappings are intentionally excluded from the custom NIST reporting package.

## NIST SP 800-53 Rev. 5

Findings may map to control families including:

- AC — Access Control
- AT — Awareness and Training
- AU — Audit and Accountability
- CM — Configuration Management
- IA — Identification and Authentication
- IR — Incident Response
- MP — Media Protection
- PL — Planning
- PM — Program Management
- PS — Personnel Security
- SA — System and Services Acquisition
- SC — System and Communications Protection
- SI — System and Information Integrity

Only control families represented by collected findings appear in an assessment report.

## NIST CSF 2.0

Mapped findings are grouped into the six CSF functions:

- GV — Govern
- ID — Identify
- PR — Protect
- DE — Detect
- RS — Respond
- RC — Recover

An Identity-only Microsoft 365 scan may not generate mappings for every CSF function.

## Assessment Boundary

A technical Microsoft 365 scan cannot establish organization-wide NIST compliance on its own.

Controls may require evidence from:

- policies
- governance documentation
- architecture
- interviews
- operating procedures
- incident response processes
- physical controls
- non-Microsoft platforms
- business processes

For this reason, the tool reports mapped technical findings rather than claiming formal framework compliance.

## NIST SP 800-207

NIST SP 800-207 Zero Trust Architecture is intentionally not treated as an automated compliance checklist in v0.1.

A Zero Trust architecture assessment requires broader evidence around:

- identity
- devices
- applications
- workloads
- networks
- policy enforcement
- telemetry
- trust decisions
- architecture

That assessment should be performed separately from the automated Microsoft 365 technical findings.

## Current v0.1 Flow

    Tenant
      |
      v
    Microsoft authentication
      |
      v
    M365-Assess Identity collection
      |
      v
    101 Identity security checks
      |
      v
    NIST mapping lookup
      |
      v
    NIST SP 800-53 + CSF 2.0 filtering
      |
      v
    HTML / CSV / XLSX reporting

## Future Web Layer

The planned web interface will remain separate from the validated CLI engine.

Planned architecture:

    Browser
       |
       v
    Local web application
       |
       v
    PowerShell assessment engine
       |
       v
    M365-Assess
       |
       v
    NIST reporting layer

This separation means the CLI assessment workflow remains usable even if the web interface is unavailable.
