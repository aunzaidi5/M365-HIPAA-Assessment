import json
import os
import re
import subprocess
import threading
import time
import uuid

from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

app = FastAPI(
    title="M365 HIPAA Assessment",
    version="0.3.0",
)


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parent.parent

TEMPLATES_DIR = PROJECT_ROOT / "web" / "templates"
STATIC_DIR = PROJECT_ROOT / "web" / "static"

ASSESSMENT_SCRIPT = (
    PROJECT_ROOT / "Invoke-M365HipaaAssessment.ps1"
)

MODULE_PATH = PROJECT_ROOT / ".psmodules"

M365_ASSESS_MODULE_PATH = (
    MODULE_PATH /
    "M365-Assess" /
    "2.12.0"
)

WEB_RUNS = (
    PROJECT_ROOT /
    "M365-HIPAA-Assessment-Output" /
    "web-runs"
)

WEB_RUNS.mkdir(
    parents=True,
    exist_ok=True,
)


app.mount(
    "/static",
    StaticFiles(directory=str(STATIC_DIR)),
    name="static",
)

templates = Jinja2Templates(
    directory=str(TEMPLATES_DIR)
)


# ---------------------------------------------------------------------------
# In-memory assessment job state
#
# This is appropriate for the current local/demo application.
# If this becomes a multi-user production service, replace this with
# persistent job storage.
# ---------------------------------------------------------------------------

jobs = {}


# ---------------------------------------------------------------------------
# Microsoft device-code parsing
# ---------------------------------------------------------------------------

DEVICE_CODE_PATTERN = re.compile(
    r"open the page\s+(https?://\S+)"
    r"\s+and enter the code\s+([A-Z0-9-]+)",
    re.IGNORECASE,
)


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class AssessmentRequest(BaseModel):
    tenant_domain: str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def utc_now():
    return datetime.now(timezone.utc).isoformat()


def powershell_environment():
    """
    Ensure the bundled PowerShell modules are discoverable by pwsh.
    """

    env = os.environ.copy()

    if MODULE_PATH.exists():
        existing = env.get("PSModulePath", "")

        env["PSModulePath"] = (
            f"{MODULE_PATH}{os.pathsep}{existing}"
            if existing
            else str(MODULE_PATH)
        )

    return env


def validate_tenant_domain(domain: str):
    """
    The current workflow intentionally accepts the tenant's primary
    onmicrosoft.com domain.
    """

    domain = domain.strip().lower()

    if not re.fullmatch(
        r"[a-z0-9][a-z0-9.-]*\.onmicrosoft\.com",
        domain,
    ):
        raise HTTPException(
            status_code=400,
            detail=(
                "Enter the tenant primary onmicrosoft.com domain, "
                "for example contoso.onmicrosoft.com."
            ),
        )

    return domain


def locate_artifacts(output_folder: Path):
    """
    Locate the newest HIPAA assessment package created underneath
    a web assessment job folder.
    """

    reports = list(
        output_folder.rglob("HIPAA-Assessment.html")
    )

    if not reports:
        return {}

    report = max(
        reports,
        key=lambda path: path.stat().st_mtime,
    )

    package_folder = report.parent

    artifact_names = {
        "report": "HIPAA-Assessment.html",
        "findings": "HIPAA-Findings.csv",
        "reference_summary": "HIPAA-Reference-Summary.csv",
        "section_summary": "HIPAA-Section-Summary.csv",
        "metadata": "assessment-metadata.json",
    }

    artifacts = {
        "package_folder": str(package_folder)
    }

    for key, filename in artifact_names.items():
        path = package_folder / filename

        if path.exists():
            artifacts[key] = str(path)

    return artifacts


def update_job_phase_from_log(job, line: str):
    """
    Best-effort progress state derived from actual PowerShell/M365-Assess
    console output.
    """

    value = line.lower()

    # Final packaging / report generation
    if any(
        token in value
        for token in (
            "hipaa package complete",
            "hipaa-assessment.html",
            "html report",
            "assessment-metadata.json",
            "building assessment package",
            "writing report",
            "exporting report",
            "report generated",
        )
    ):
        job["phase"] = "building"
        return

    # HIPAA mapping layer
    if any(
        token in value
        for token in (
            "building hipaa-mapped findings",
            "hipaa-mapped findings",
            "mapping hipaa",
            "hipaa reference summary",
            "hipaa section summary",
        )
    ):
        job["phase"] = "mapping"
        return

    # M365 control evaluation
    if any(
        token in value
        for token in (
            "evaluating",
            "evaluation",
            "security checks:",
            "checks complete",
            "assessment checks",
        )
    ):
        job["phase"] = "evaluating"
        return

    # M365 evidence collection
    if any(
        token in value
        for token in (
            "collecting",
            "collector",
            "required graph scopes granted",
            "user summary",
        )
    ):
        job["phase"] = "collecting"


# ---------------------------------------------------------------------------
# Assessment worker
# ---------------------------------------------------------------------------

def run_assessment(job_id: str, tenant_domain: str):
    job = jobs[job_id]

    output_folder = Path(
        job["output_folder"]
    )

    command = [
        "pwsh",
        "-NoProfile",
        "-File",
        str(ASSESSMENT_SCRIPT),
        "-TenantId",
        tenant_domain,
        "-UseDeviceCode",
        "-OutputFolder",
        str(output_folder),
        "-M365AssessModulePath",
        str(M365_ASSESS_MODULE_PATH),
    ]

    job["status"] = "starting"
    job["phase"] = "starting"
    job["started_at"] = utc_now()

    try:
        process = subprocess.Popen(
            command,
            cwd=str(PROJECT_ROOT),
            env=powershell_environment(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        job["process_id"] = process.pid

        assert process.stdout is not None

        for raw_line in process.stdout:
            line = raw_line.rstrip()

            if not line:
                continue

            job["logs"].append(line)

            # Keep the in-memory log reasonably bounded.
            job["logs"] = job["logs"][-150:]

            update_job_phase_from_log(
                job,
                line,
            )

            # ---------------------------------------------------------------
            # Device-code authentication
            #
            # M365-Assess can occasionally emit more than one code while
            # initializing Graph modules. We retain the existing protection
            # that waits for a code to remain stable before exposing it to
            # the browser.
            # ---------------------------------------------------------------

            device_match = DEVICE_CODE_PATTERN.search(
                line
            )

            if device_match:
                new_url = device_match.group(1)
                new_code = device_match.group(2)

                if new_code != job.get("pending_device_code"):
                    # Remember where the assessment was before this
                    # additional Microsoft service requested authentication.
                    current_phase = job.get("phase")

                    if current_phase not in (
                        None,
                        "queued",
                        "starting",
                        "authentication",
                    ):
                        job["resume_phase"] = current_phase

                    job["pending_verification_url"] = new_url
                    job["pending_device_code"] = new_code
                    job["auth_code_updated_at"] = time.monotonic()

                    # Hide an older code from the browser.
                    job["verification_url"] = None
                    job["device_code"] = None

                    job["status"] = "preparing_authentication"
                    job["phase"] = "authentication"

            else:
                #
                # A device-code authentication call blocks PowerShell until
                # authentication succeeds. Therefore, once PowerShell starts
                # producing normal output again after an authentication prompt,
                # that authentication has completed.
                #
                if job.get("status") in (
                    "preparing_authentication",
                    "awaiting_authentication",
                ):
                    value = line.lower()

                    auth_prompt_noise = (
                        "open the page",
                        "enter the code",
                        "device code",
                        "devicelogin",
                    )

                    if not any(
                        token in value
                        for token in auth_prompt_noise
                    ):
                        job["status"] = "running"
                        job["phase"] = job.pop(
                            "resume_phase",
                            "collecting",
                        )

                        job["verification_url"] = None
                        job["device_code"] = None
                        job["pending_verification_url"] = None
                        job["pending_device_code"] = None
                        job["auth_code_updated_at"] = None
        


            # Once Graph scopes/check output begins, authentication has
            # succeeded and actual assessment execution is underway.
            if (
                "required Graph scopes granted" in line
                or "Security Checks:" in line
                or "User Summary" in line
            ):
                job["status"] = "running"

                if job.get("phase") in (
                    None,
                    "starting",
                    "authentication",
                ):
                    job["phase"] = "collecting"

        return_code = process.wait()

        job["return_code"] = return_code



        if return_code != 0:
            job["status"] = "failed"

            job["error"] = (
                "Assessment process exited with an error."
            )

            job["completed_at"] = utc_now()

            return

        # ------------------------------------------------------------------
        # Assessment completed successfully. Locate the generated HIPAA
        # package.
        # ------------------------------------------------------------------

        artifacts = locate_artifacts(
            output_folder
        )

        if not artifacts.get("report"):
            job["status"] = "failed"

            job["error"] = (
                "Assessment process finished but "
                "HIPAA-Assessment.html was not found."
            )

            job["completed_at"] = utc_now()

            return

        job["artifacts"] = artifacts

        job["phase"] = "completed"
        job["status"] = "completed"
        job["completed_at"] = utc_now()

    except Exception as exc:
        job["status"] = "failed"
        job["error"] = str(exc)
        job["completed_at"] = utc_now()


# ---------------------------------------------------------------------------
# Web routes
# ---------------------------------------------------------------------------

@app.get("/")
def root(request: Request):
    return templates.TemplateResponse(
        request,
        "index.html",
    )


@app.get("/health")
def health():
    return {
        "status": "healthy",
        "application": "M365 HIPAA Assessment",
    }


@app.get("/engine/status")
def engine_status():
    """
    Confirm that the local assessment dependencies are available.
    """

    env = powershell_environment()

    try:
        ps_version = subprocess.run(
            [
                "pwsh",
                "-NoProfile",
                "-Command",
                "$PSVersionTable.PSVersion.ToString()",
            ],
            capture_output=True,
            text=True,
            timeout=15,
            env=env,
        )

        module_check = subprocess.run(
            [
                "pwsh",
                "-NoProfile",
                "-Command",
                (
                    "(Get-Module -ListAvailable M365-Assess | "
                    "Sort-Object Version -Descending | "
                    "Select-Object -First 1).Version.ToString()"
                ),
            ],
            capture_output=True,
            text=True,
            timeout=15,
            env=env,
        )

        powershell_available = (
            ps_version.returncode == 0
        )

        m365_assess_available = bool(
            module_check.stdout.strip()
        )

        return {
            "engine_ready": (
                powershell_available
                and ASSESSMENT_SCRIPT.exists()
                and M365_ASSESS_MODULE_PATH.exists()
                and m365_assess_available
            ),
            "powershell": {
                "available": powershell_available,
                "version": ps_version.stdout.strip(),
            },
            "assessment_script": {
                "exists": ASSESSMENT_SCRIPT.exists(),
                "path": str(ASSESSMENT_SCRIPT),
            },
            "m365_assess": {
                "available": m365_assess_available,
                "version": module_check.stdout.strip(),
                "module_path": str(
                    M365_ASSESS_MODULE_PATH
                ),
                "module_path_exists": (
                    M365_ASSESS_MODULE_PATH.exists()
                ),
            },
            "framework": {
                "id": "hipaa",
                "label": "HIPAA",
            },
        }

    except Exception as exc:
        return {
            "engine_ready": False,
            "error": str(exc),
        }


# ---------------------------------------------------------------------------
# Assessment API
# ---------------------------------------------------------------------------

@app.post("/assessments")
def create_assessment(
    request: AssessmentRequest,
):
    tenant_domain = validate_tenant_domain(
        request.tenant_domain
    )

    job_id = uuid.uuid4().hex[:12]

    output_folder = (
        WEB_RUNS /
        job_id
    )

    output_folder.mkdir(
        parents=True,
        exist_ok=True,
    )

    jobs[job_id] = {
        "id": job_id,
        "tenant_domain": tenant_domain,

        "status": "queued",
        "phase": "queued",

        "created_at": utc_now(),
        "started_at": None,
        "completed_at": None,

        "verification_url": None,
        "device_code": None,

        "pending_verification_url": None,
        "pending_device_code": None,
        "auth_code_updated_at": None,

        "output_folder": str(
            output_folder
        ),

        "artifacts": {},
        "logs": [],

        "error": None,
    }

    worker = threading.Thread(
        target=run_assessment,
        args=(
            job_id,
            tenant_domain,
        ),
        daemon=True,
    )

    worker.start()

    return {
        "assessment_id": job_id,
        "status": "queued",
        "status_url": (
            f"/assessments/{job_id}"
        ),
    }


@app.get("/assessments/{job_id}")
def assessment_status(job_id: str):
    job = jobs.get(job_id)

    if not job:
        raise HTTPException(
            status_code=404,
            detail="Assessment not found.",
        )

    # ----------------------------------------------------------------------
    # Only expose a device code after it has remained unchanged for
    # fifteen seconds. This prevents the browser from showing an initial
    # code that M365-Assess immediately replaces.
    # ----------------------------------------------------------------------

    if (
        job["status"]
        == "preparing_authentication"
        and job.get("pending_device_code")
        and job.get("auth_code_updated_at")
        is not None
    ):
        age = (
            time.monotonic()
            - job["auth_code_updated_at"]
        )

        if age >= 15:
            job["verification_url"] = (
                job[
                    "pending_verification_url"
                ]
            )

            job["device_code"] = (
                job[
                    "pending_device_code"
                ]
            )

            job["status"] = (
                "awaiting_authentication"
            )

    response = {
        "assessment_id": job["id"],
        "tenant_domain": job["tenant_domain"],

        "status": job["status"],
        "phase": job.get("phase"),

        "created_at": job["created_at"],
        "started_at": job["started_at"],
        "completed_at": job["completed_at"],

        "verification_url": (
            job["verification_url"]
        ),

        "device_code": (
            job["device_code"]
        ),

        "error": job["error"],

        "recent_logs": (
            job["logs"][-20:]
        ),
    }

    if job["status"] == "completed":
        response["report_url"] = (
            f"/assessments/{job_id}/report"
        )

        response["downloads"] = {
            "findings_csv": (
                f"/assessments/{job_id}/download/findings"
                if job["artifacts"].get(
                    "findings"
                )
                else None
            ),

            "reference_summary_csv": (
                f"/assessments/{job_id}/download/reference_summary"
                if job["artifacts"].get(
                    "reference_summary"
                )
                else None
            ),

            "section_summary_csv": (
                f"/assessments/{job_id}/download/section_summary"
                if job["artifacts"].get(
                    "section_summary"
                )
                else None
            ),

            "metadata_json": (
                f"/assessments/{job_id}/download/metadata"
                if job["artifacts"].get(
                    "metadata"
                )
                else None
            ),

            # Temporary compatibility with the copied NIST frontend.
            # These can disappear once index.html is converted.
            "excel": None,
            "sp80053_csv": None,
            "csf_csv": None,
        }

        response["output_folder"] = (
            job["artifacts"].get(
                "package_folder",
                job["output_folder"],
            )
        )

    return response


# ---------------------------------------------------------------------------
# Generated HTML report
# ---------------------------------------------------------------------------

@app.get(
    "/assessments/{job_id}/report"
)
def open_report(job_id: str):
    job = jobs.get(job_id)

    if not job:
        raise HTTPException(
            status_code=404,
            detail="Assessment not found.",
        )

    report_path = (
        job["artifacts"].get(
            "report"
        )
    )

    if not report_path:
        raise HTTPException(
            status_code=404,
            detail="Report is not available.",
        )

    return FileResponse(
        report_path,
        media_type="text/html",
    )


# ---------------------------------------------------------------------------
# Download artifacts
# ---------------------------------------------------------------------------

@app.get(
    "/assessments/{job_id}/download/{artifact}"
)
def download_artifact(
    job_id: str,
    artifact: str,
):
    job = jobs.get(job_id)

    if not job:
        raise HTTPException(
            status_code=404,
            detail="Assessment not found.",
        )

    allowed = {
        "findings",
        "reference_summary",
        "section_summary",
        "metadata",
    }

    if artifact not in allowed:
        raise HTTPException(
            status_code=400,
            detail="Unknown artifact.",
        )

    path = job["artifacts"].get(
        artifact
    )

    if not path:
        raise HTTPException(
            status_code=404,
            detail=(
                "Requested artifact "
                "is not available."
            ),
        )

    return FileResponse(
        path,
        filename=Path(path).name,
    )
