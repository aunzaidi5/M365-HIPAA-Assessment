import os
import re
import subprocess
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel


app = FastAPI(
    title="M365 NIST Assessment",
    version="0.2.0"
)


PROJECT_ROOT = Path(__file__).resolve().parent.parent
TEMPLATES_DIR = PROJECT_ROOT / "web" / "templates"
STATIC_DIR = PROJECT_ROOT / "web" / "static"
ASSESSMENT_SCRIPT = PROJECT_ROOT / "Invoke-M365NistAssessment.ps1"
MODULE_PATH = PROJECT_ROOT / ".psmodules"
WEB_RUNS = PROJECT_ROOT / "output" / "web-runs"

WEB_RUNS.mkdir(parents=True, exist_ok=True)

app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

jobs = {}


DEVICE_CODE_PATTERN = re.compile(
    r"open the page\s+(https?://\S+)\s+and enter the code\s+([A-Z0-9]+)",
    re.IGNORECASE,
)


class AssessmentRequest(BaseModel):
    tenant_domain: str


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def powershell_environment():
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
    domain = domain.strip().lower()

    if not re.fullmatch(
        r"[a-z0-9][a-z0-9.-]*\.onmicrosoft\.com",
        domain
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
    reports = list(output_folder.rglob("NIST-Assessment.html"))

    if not reports:
        return {}

    report = max(
        reports,
        key=lambda p: p.stat().st_mtime
    )

    package_folder = report.parent

    artifact_names = {
        "report": "NIST-Assessment.html",
        "matrix": "NIST-Compliance-Matrix.xlsx",
        "findings": "NIST-Findings.csv",
        "sp80053": "NIST-SP800-53-Findings.csv",
        "sp80053_summary": "NIST-SP800-53-Family-Summary.csv",
        "csf": "NIST-CSF-2.0-Findings.csv",
        "csf_summary": "NIST-CSF-2.0-Function-Summary.csv",
        "metadata": "assessment-metadata.json",
    }

    artifacts = {}

    for key, filename in artifact_names.items():
        path = package_folder / filename

        if path.exists():
            artifacts[key] = str(path)

    return artifacts


def run_assessment(job_id: str, tenant_domain: str):
    job = jobs[job_id]
    output_folder = Path(job["output_folder"])

    command = [
        "pwsh",
        "-NoProfile",
        "-File",
        str(ASSESSMENT_SCRIPT),
        "-TenantId",
        tenant_domain,
        "-Section",
        "Identity",
        "-UseDeviceCode",
        "-OutputFolder",
        str(output_folder),
    ]

    job["status"] = "starting"
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
            job["logs"] = job["logs"][-100:]

            device_match = DEVICE_CODE_PATTERN.search(line)

            if device_match:
                job["verification_url"] = device_match.group(1)
                job["device_code"] = device_match.group(2)
                job["status"] = "awaiting_authentication"

            if (
                "required Graph scopes granted" in line
                or "Security Checks:" in line
                or "User Summary" in line
            ):
                job["status"] = "running"

        return_code = process.wait()
        job["return_code"] = return_code

        if return_code != 0:
            job["status"] = "failed"
            job["error"] = "Assessment process exited with an error."
            job["completed_at"] = utc_now()
            return

        artifacts = locate_artifacts(output_folder)

        if not artifacts.get("report"):
            job["status"] = "failed"
            job["error"] = (
                "Assessment process finished but "
                "NIST-Assessment.html was not found."
            )
            job["completed_at"] = utc_now()
            return

        job["artifacts"] = artifacts
        job["status"] = "completed"
        job["completed_at"] = utc_now()

    except Exception as exc:
        job["status"] = "failed"
        job["error"] = str(exc)
        job["completed_at"] = utc_now()


@app.get("/")
def root(request: Request):
    return templates.TemplateResponse(
        request,
        "index.html"
    )


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/engine/status")
def engine_status():
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
                "(Get-Module -ListAvailable M365-Assess | "
                "Sort-Object Version -Descending | "
                "Select-Object -First 1).Version.ToString()",
            ],
            capture_output=True,
            text=True,
            timeout=15,
            env=env,
        )

        return {
            "engine_ready": (
                ps_version.returncode == 0
                and ASSESSMENT_SCRIPT.exists()
                and bool(module_check.stdout.strip())
            ),
            "powershell": {
                "available": ps_version.returncode == 0,
                "version": ps_version.stdout.strip(),
            },
            "assessment_script": {
                "exists": ASSESSMENT_SCRIPT.exists(),
                "path": str(ASSESSMENT_SCRIPT),
            },
            "m365_assess": {
                "available": bool(module_check.stdout.strip()),
                "version": module_check.stdout.strip(),
            },
        }

    except Exception as exc:
        return {
            "engine_ready": False,
            "error": str(exc),
        }


@app.post("/assessments")
def create_assessment(request: AssessmentRequest):
    tenant_domain = validate_tenant_domain(
        request.tenant_domain
    )

    job_id = uuid.uuid4().hex[:12]

    output_folder = WEB_RUNS / job_id
    output_folder.mkdir(
        parents=True,
        exist_ok=True
    )

    jobs[job_id] = {
        "id": job_id,
        "tenant_domain": tenant_domain,
        "status": "queued",
        "created_at": utc_now(),
        "started_at": None,
        "completed_at": None,
        "verification_url": None,
        "device_code": None,
        "output_folder": str(output_folder),
        "artifacts": {},
        "logs": [],
        "error": None,
    }

    worker = threading.Thread(
        target=run_assessment,
        args=(job_id, tenant_domain),
        daemon=True,
    )

    worker.start()

    return {
        "assessment_id": job_id,
        "status": "queued",
        "status_url": f"/assessments/{job_id}",
    }


@app.get("/assessments/{job_id}")
def assessment_status(job_id: str):
    job = jobs.get(job_id)

    if not job:
        raise HTTPException(
            status_code=404,
            detail="Assessment not found.",
        )

    response = {
        "assessment_id": job["id"],
        "tenant_domain": job["tenant_domain"],
        "status": job["status"],
        "created_at": job["created_at"],
        "started_at": job["started_at"],
        "completed_at": job["completed_at"],
        "verification_url": job["verification_url"],
        "device_code": job["device_code"],
        "error": job["error"],
        "recent_logs": job["logs"][-20:],
    }

    if job["status"] == "completed":
        response["report_url"] = (
            f"/assessments/{job_id}/report"
        )

        response["downloads"] = {
            "excel": (
                f"/assessments/{job_id}/download/matrix"
                if job["artifacts"].get("matrix")
                else None
            ),
            "findings_csv": (
                f"/assessments/{job_id}/download/findings"
                if job["artifacts"].get("findings")
                else None
            ),
            "sp80053_csv": (
                f"/assessments/{job_id}/download/sp80053"
                if job["artifacts"].get("sp80053")
                else None
            ),
            "csf_csv": (
                f"/assessments/{job_id}/download/csf"
                if job["artifacts"].get("csf")
                else None
            ),
        }

        response["output_folder"] = job["output_folder"]

    return response


@app.get("/assessments/{job_id}/report")
def open_report(job_id: str):
    job = jobs.get(job_id)

    if not job:
        raise HTTPException(
            status_code=404,
            detail="Assessment not found.",
        )

    report_path = job["artifacts"].get("report")

    if not report_path:
        raise HTTPException(
            status_code=404,
            detail="Report is not available.",
        )

    return FileResponse(
        report_path,
        media_type="text/html",
    )


@app.get("/assessments/{job_id}/download/{artifact}")
def download_artifact(job_id: str, artifact: str):
    job = jobs.get(job_id)

    if not job:
        raise HTTPException(
            status_code=404,
            detail="Assessment not found.",
        )

    allowed = {
        "matrix",
        "findings",
        "sp80053",
        "sp80053_summary",
        "csf",
        "csf_summary",
        "metadata",
    }

    if artifact not in allowed:
        raise HTTPException(
            status_code=400,
            detail="Unknown artifact.",
        )

    path = job["artifacts"].get(artifact)

    if not path:
        raise HTTPException(
            status_code=404,
            detail="Requested artifact is not available.",
        )

    return FileResponse(
        path,
        filename=Path(path).name,
    )
