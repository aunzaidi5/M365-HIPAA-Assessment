# Installation Guide

## Requirements

M365 HIPAA Assessment requires:

- PowerShell 7+
- Python 3
- Internet access to Microsoft authentication and Microsoft 365 services
- access to a Microsoft 365 tenant with permissions required by the selected M365-Assess collectors
- M365-Assess 2.12.0

The local web interface uses:

- FastAPI
- Uvicorn
- Jinja2
- python-multipart

## Clone the Repository

```bash
git clone https://github.com/aunzaidi5/M365-HIPAA-Assessment.git
cd M365-HIPAA-Assessment
```

## Create a Python Virtual Environment

On macOS or Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

On Windows PowerShell:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
```

## Install Web Dependencies

```bash
pip install -r requirements.txt
```

The current `requirements.txt` contains the dependencies required by the FastAPI frontend.

## Install M365-Assess Locally

The project is designed to use a project-local copy of M365-Assess 2.12.0 under `.psmodules/`.

From the project root:

```bash
pwsh -NoProfile -Command '
New-Item -ItemType Directory -Path "./.psmodules" -Force | Out-Null
Save-Module -Name M365-Assess -RequiredVersion 2.12.0 -Path "./.psmodules" -Force
'
```

The expected module location is:

```text
.psmodules/M365-Assess/2.12.0
```

`.psmodules/` is excluded from Git.

## Verify PowerShell and M365-Assess

Check PowerShell:

```bash
pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
```

Verify that the project-local module can be imported:

```bash
pwsh -NoProfile -Command '
$localModules = (Resolve-Path "./.psmodules").Path
$env:PSModulePath = "$localModules$([IO.Path]::PathSeparator)$env:PSModulePath"
Import-Module "./.psmodules/M365-Assess/2.12.0/M365-Assess.psd1" -Force
Get-Command Invoke-M365Assessment
'
```

## Verify the Python Application

With the virtual environment active:

```bash
python -m py_compile web/app.py
```

If Node.js is installed, the frontend JavaScript can also be syntax-checked:

```bash
node --check web/static/app.js
```

No output from these commands indicates a successful syntax check.

## Start the Web Interface

Run Uvicorn from the project root:

```bash
uvicorn web.app:app --host 127.0.0.1 --port 8001
```

Then open:

```text
http://127.0.0.1:8001
```

For actual assessment runs, do **not** use `--reload`. Active assessment job state is currently stored in memory, so a reload or application restart can remove the browser-visible job state while the underlying files remain on disk.

## Check Engine Status

With the web application running, open:

```text
http://127.0.0.1:8001/engine/status
```

A ready environment should report that:

- PowerShell is available
- the HIPAA wrapper script exists
- M365-Assess is available
- the expected local M365-Assess module path exists
- the HIPAA framework is configured

## Tenant Domain Requirement

For fresh assessments, use the tenant's primary `onmicrosoft.com` domain, for example:

```text
contoso.onmicrosoft.com
```

The current wrapper intentionally rejects a tenant GUID for fresh runs because M365-Assess 2.12.0 can rename the assessment directory after tenant discovery while some collectors retain the original path.

## Microsoft 365 Permissions

M365 HIPAA Assessment uses M365-Assess as its collector. Required permissions therefore depend on the workloads and checks being collected.

The default assessment scope includes Tenant, Identity, Licensing, Email, Intune, Security, Collaboration, Power BI, Hybrid, and Inventory. A tenant administrator may be prompted to authenticate more than once because separate Microsoft 365 workloads or PowerShell modules can require separate authenticated sessions.

Some Security & Compliance / Purview operations can open a Microsoft browser sign-in directly rather than using the device-code screen shown by the local web application.

## Generated Data

Assessment output is written beneath:

```text
M365-HIPAA-Assessment-Output/
```

This directory is excluded from Git because assessment data can contain security-sensitive tenant information.

The following local paths are also excluded from source control:

```text
.venv/
.psmodules/
M365-HIPAA-Assessment-Output/
M365-Assessment/
output/
```

## Troubleshooting

### `pwsh` not found

Install PowerShell 7 and confirm that `pwsh` is available on your shell path.

### M365-Assess not found

Confirm that this path exists:

```text
.psmodules/M365-Assess/2.12.0/M365-Assess.psd1
```

Then rerun the import verification command above.

### Web application starts but engine is not ready

Check:

```text
http://127.0.0.1:8001/engine/status
```

The response identifies whether the missing dependency is PowerShell, the wrapper script, or M365-Assess.

### Assessment appears to pause during authentication

A broad Microsoft 365 assessment can require multiple workload sessions. Complete each Microsoft sign-in request using the intended tenant administrator account. Device-code authentication is shown in the assessment modal; browser-based Purview authentication may appear in a separate browser tab.

### Browser loses a running assessment after Uvicorn restarts

Current job state is in memory. Restarting the FastAPI process removes that job record. Generated assessment files may still exist on disk, but the existing assessment URL will no longer be associated with the previous in-memory job.

## Security Note

Do not commit assessment output, raw tenant exports, access tokens, credentials, or customer-sensitive evidence to Git.

This project performs technical Microsoft 365 posture assessment and HIPAA mapping. It does not provide a legal opinion, HIPAA certification, audit attestation, or formal determination of compliance.
