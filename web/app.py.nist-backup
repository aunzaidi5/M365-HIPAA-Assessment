import os
import json
import re
import subprocess
import time
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



INTERACTIVE_REPORT_MARKER = "m365-nist-interactive-v1"


def get_sections_run(output_folder: Path):
    """Read the actual M365-Assess scope from assessment provenance."""
    candidates = list(output_folder.rglob("_Assessment-Provenance.json"))

    if not candidates:
        return []

    provenance = max(candidates, key=lambda p: p.stat().st_mtime)

    try:
        data = json.loads(provenance.read_text(encoding="utf-8-sig"))
    except Exception:
        return []

    sections = data.get("sectionsRun") or []

    if isinstance(sections, str):
        sections = [sections]

    return [str(section).strip() for section in sections if str(section).strip()]


def enhance_nist_report(report_path: Path, sections_run=None):
    """
    Post-process the generated NIST report so every new web assessment gets
    the interactive dashboard automatically. This keeps the PowerShell
    generator untouched and enhances the final self-contained HTML artifact.
    """
    if not report_path.exists():
        return

    text = report_path.read_text(encoding="utf-8", errors="replace")

    # Keep the displayed scope aligned with the actual M365-Assess provenance.
    if sections_run:
        friendly_sections = []
        for section in sections_run:
            friendly_sections.append("Power BI" if section == "PowerBI" else section)

        scope_text = " · ".join(friendly_sections)

        text = re.sub(
            r"(<strong>\s*Scope:\s*</strong>\s*)([^<\r\n]+)",
            lambda match: match.group(1) + scope_text + " &nbsp; | &nbsp; ",
            text,
            count=1,
            flags=re.IGNORECASE,
        )

    # Do not inject the interactive assets twice.
    if INTERACTIVE_REPORT_MARKER in text:
        report_path.write_text(text, encoding="utf-8")
        return

    interactive_css = r"""
<style id="m365-nist-interactive-v1">
/* Interactive dashboard injected by the FastAPI web layer */
.nist-dashboard {
    display: grid;
    grid-template-columns: minmax(300px, 390px) 1fr;
    gap: 18px;
    margin: 22px 0;
}

.nist-score-panel {
    background: #fff;
    border: 1px solid #e4e7ec;
    border-radius: 16px;
    padding: 24px;
    display: flex;
    align-items: center;
    gap: 22px;
}

.nist-score-wheel {
    --score: 0;
    width: 168px;
    height: 168px;
    min-width: 168px;
    border-radius: 50%;
    display: grid;
    place-items: center;
    background: conic-gradient(
        #1570ef calc(var(--score) * 1%),
        #e9eef5 0
    );
    box-shadow: inset 0 0 0 1px rgba(21,112,239,.06);
}

.nist-score-inner {
    width: 126px;
    height: 126px;
    border-radius: 50%;
    background: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-direction: column;
    box-shadow: 0 8px 24px rgba(16,24,40,.08);
}

.nist-score-inner strong {
    font-size: 31px;
    line-height: 1;
    letter-spacing: -.04em;
    color: #101828;
}

.nist-score-inner span {
    margin-top: 7px;
    color: #667085;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: .08em;
    text-transform: uppercase;
    text-align: center;
}

.nist-score-copy h2 {
    margin: 0 0 8px;
    font-size: 20px;
}

.nist-score-copy p {
    margin: 0;
    color: #667085;
    font-size: 12px;
    line-height: 1.55;
}

.nist-score-help {
    margin-top: 13px;
    border: 0;
    background: #eff8ff;
    color: #175cd3;
    border-radius: 8px;
    padding: 8px 10px;
    font-size: 12px;
    font-weight: 700;
    cursor: pointer;
}

.nist-score-breakdown {
    margin-top: 12px;
    padding: 12px;
    border-radius: 9px;
    background: #f8fafc;
    font-size: 12px;
    line-height: 1.7;
    color: #344054;
}

.nist-metrics {
    display: grid;
    grid-template-columns: repeat(4, minmax(110px, 1fr));
    gap: 12px;
}

.nist-metric {
    background: #fff;
    border: 1px solid #e4e7ec;
    border-radius: 14px;
    padding: 17px;
}

.nist-metric-label {
    color: #667085;
    font-size: 12px;
}

.nist-metric-value {
    margin-top: 5px;
    font-size: 25px;
    font-weight: 760;
    color: #101828;
}

.nist-metric.pass .nist-metric-value { color: #067647; }
.nist-metric.fail .nist-metric-value { color: #b42318; }
.nist-metric.warning .nist-metric-value { color: #b54708; }
.nist-metric.review .nist-metric-value { color: #175cd3; }

.nist-findings-toolbar {
    display: flex;
    flex-wrap: wrap;
    gap: 9px;
    align-items: center;
    margin: 14px 0 16px;
}

.nist-filter-chip {
    border: 1px solid #d0d5dd;
    background: #fff;
    color: #344054;
    border-radius: 999px;
    padding: 8px 12px;
    font-size: 12px;
    font-weight: 700;
    cursor: pointer;
}

.nist-filter-chip.active {
    color: #fff;
    background: #175cd3;
    border-color: #175cd3;
}

.nist-findings-search,
.nist-risk-filter {
    border: 1px solid #d0d5dd;
    background: #fff;
    color: #101828;
    border-radius: 9px;
    padding: 9px 11px;
    font: inherit;
    font-size: 12px;
    min-height: 36px;
}

.nist-findings-search {
    flex: 1;
    min-width: 240px;
}

.nist-visible-count {
    margin-left: auto;
    color: #667085;
    font-size: 12px;
    font-weight: 650;
}

#nistInteractiveFindings th:nth-child(n+5),
#nistInteractiveFindings td:nth-child(n+5) {
    display: none;
}

#nistInteractiveFindings tbody tr.nist-finding-row {
    cursor: pointer;
    transition: background .15s ease;
}

#nistInteractiveFindings tbody tr.nist-finding-row:hover {
    background: #f8fbff;
}

#nistInteractiveFindings tbody tr.nist-finding-row td:nth-child(2)::after {
    content: "  ▾";
    color: #98a2b3;
    font-size: 11px;
}

#nistInteractiveFindings tbody tr.nist-finding-row.expanded td:nth-child(2)::after {
    content: "  ▴";
}

#nistInteractiveFindings tr.nist-detail-row td {
    display: table-cell !important;
    padding: 0;
    background: #fbfcfe;
}

.nist-detail-grid {
    padding: 18px 20px 20px;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 13px;
}

.nist-detail-block {
    border: 1px solid #e4e7ec;
    background: #fff;
    border-radius: 10px;
    padding: 13px;
}

.nist-detail-block.full {
    grid-column: 1 / -1;
}

.nist-detail-label {
    display: block;
    margin-bottom: 6px;
    color: #667085;
    font-size: 10px;
    font-weight: 800;
    letter-spacing: .08em;
    text-transform: uppercase;
}

.nist-detail-value {
    font-size: 12px;
    line-height: 1.6;
    color: #344054;
    overflow-wrap: anywhere;
}

.nist-empty {
    color: #98a2b3;
    font-style: italic;
}

@media (max-width: 900px) {
    .nist-dashboard { grid-template-columns: 1fr; }
    .nist-metrics { grid-template-columns: repeat(2, 1fr); }
}

@media (max-width: 600px) {
    .nist-score-panel {
        align-items: flex-start;
        flex-direction: column;
    }

    .nist-score-wheel {
        width: 150px;
        height: 150px;
        min-width: 150px;
    }

    .nist-score-inner {
        width: 112px;
        height: 112px;
    }

    .nist-detail-grid {
        grid-template-columns: 1fr;
    }

    .nist-detail-block.full {
        grid-column: auto;
    }
}
</style>
"""

    interactive_js = r"""
<script id="m365-nist-interactive-script">
document.addEventListener("DOMContentLoaded", () => {
    const normalize = value => (value || "").trim();
    const lower = value => normalize(value).toLowerCase();
    const esc = value => normalize(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;");

    /* ---------------- Dashboard / score wheel ---------------- */
    const cards = document.querySelector(".cards");

    if (cards && !document.getElementById("nistInteractiveDashboard")) {
        const values = {};

        cards.querySelectorAll(".card").forEach(card => {
            const label = normalize(card.querySelector(".label")?.textContent);
            const value = normalize(card.querySelector(".value")?.textContent);

            if (label) values[label] = value;
        });

        const rawScore =
            values["Mapped-check pass rate*"] ||
            values["Mapped-check pass rate"] ||
            "0%";

        const score = Math.max(
            0,
            Math.min(100, Number.parseFloat(rawScore) || 0)
        );

        const pass = values["Pass"] || "0";
        const fail = values["Fail"] || "0";
        const warning = values["Warning"] || "0";
        const review = values["Review"] || "0";
        const mapped = values["NIST-mapped findings"] || "0";
        const sp = values["Mapped to SP 800-53"] || "0";
        const csf = values["Mapped to CSF 2.0"] || "0";

        const dashboard = document.createElement("div");
        dashboard.id = "nistInteractiveDashboard";
        dashboard.className = "nist-dashboard";
        dashboard.innerHTML = `
            <div class="nist-score-panel">
                <div class="nist-score-wheel" id="nistOverallScoreWheel">
                    <div class="nist-score-inner">
                        <strong>${score.toFixed(1).replace(".0","")}%</strong>
                        <span>Mapped-check pass rate</span>
                    </div>
                </div>

                <div class="nist-score-copy">
                    <h2>Overall NIST posture view</h2>
                    <p>
                        Pass rate across applicable mapped technical checks.
                        This is a posture indicator, not a NIST compliance percentage.
                    </p>

                    <button class="nist-score-help" id="nistScoreHelp" type="button">
                        How is this calculated?
                    </button>

                    <div class="nist-score-breakdown" id="nistScoreBreakdown" hidden>
                        <strong>${pass}</strong> passed across the scored
                        Pass + Fail + Warning population. Review, Unknown and
                        Not Licensed states remain visible but are excluded from
                        the mapped-check pass-rate denominator.
                    </div>
                </div>
            </div>

            <div class="nist-metrics">
                <div class="nist-metric">
                    <div class="nist-metric-label">NIST-mapped findings</div>
                    <div class="nist-metric-value">${mapped}</div>
                </div>

                <div class="nist-metric pass">
                    <div class="nist-metric-label">Pass</div>
                    <div class="nist-metric-value">${pass}</div>
                </div>

                <div class="nist-metric fail">
                    <div class="nist-metric-label">Fail</div>
                    <div class="nist-metric-value">${fail}</div>
                </div>

                <div class="nist-metric warning">
                    <div class="nist-metric-label">Warning</div>
                    <div class="nist-metric-value">${warning}</div>
                </div>

                <div class="nist-metric review">
                    <div class="nist-metric-label">Review</div>
                    <div class="nist-metric-value">${review}</div>
                </div>

                <div class="nist-metric">
                    <div class="nist-metric-label">Mapped to SP 800-53</div>
                    <div class="nist-metric-value">${sp}</div>
                </div>

                <div class="nist-metric">
                    <div class="nist-metric-label">Mapped to CSF 2.0</div>
                    <div class="nist-metric-value">${csf}</div>
                </div>
            </div>
        `;

        cards.replaceWith(dashboard);

        const wheel = document.getElementById("nistOverallScoreWheel");
        requestAnimationFrame(() => {
            wheel?.style.setProperty("--score", String(score));
        });

        const scoreHelp = document.getElementById("nistScoreHelp");
        const breakdown = document.getElementById("nistScoreBreakdown");

        scoreHelp?.addEventListener("click", () => {
            breakdown.hidden = !breakdown.hidden;
            scoreHelp.textContent = breakdown.hidden
                ? "How is this calculated?"
                : "Hide calculation";
        });
    }

    /* ---------------- Detailed findings ---------------- */
    const detailedSection = Array.from(document.querySelectorAll("section"))
        .find(section =>
            lower(section.querySelector("h2")?.textContent)
                .includes("detailed nist findings")
        );

    const table = detailedSection?.querySelector("table");

    if (!table || !table.tBodies.length) return;

    table.id = "nistInteractiveFindings";

    const toolbar = document.createElement("div");
    toolbar.className = "nist-findings-toolbar";
    toolbar.innerHTML = `
        <button class="nist-filter-chip active" type="button" data-status="all">All</button>
        <button class="nist-filter-chip" type="button" data-status="fail">Fail</button>
        <button class="nist-filter-chip" type="button" data-status="warning">Warning</button>
        <button class="nist-filter-chip" type="button" data-status="review">Review</button>
        <button class="nist-filter-chip" type="button" data-status="pass">Pass</button>

        <select class="nist-risk-filter" id="nistRiskFilter">
            <option value="all">All risk levels</option>
            <option value="critical">Critical</option>
            <option value="high">High</option>
            <option value="medium">Medium</option>
            <option value="low">Low</option>
            <option value="info">Info</option>
        </select>

        <input
            class="nist-findings-search"
            id="nistFindingsSearch"
            type="search"
            placeholder="Search check ID, setting, NIST control or remediation..."
        />

        <span class="nist-visible-count" id="nistVisibleCount"></span>
    `;

    const hint = document.createElement("p");
    hint.className = "small";
    hint.textContent =
        "Click a finding to expand its NIST mappings, observed state, expected state and remediation.";

    table.parentElement?.before(toolbar, hint);

    const rows = [];

    Array.from(table.tBodies[0].rows).forEach(row => {
        const cells = Array.from(row.cells);

        if (cells.length < 9) return;

        const status = lower(row.querySelector(".status")?.textContent) || "other";
        const risk = lower(cells[3].textContent) || "unknown";
        const searchText = lower(cells.map(cell => cell.textContent).join(" "));

        row.classList.add("nist-finding-row");
        row.dataset.status = status;
        row.dataset.risk = risk;
        row.dataset.search = searchText;

        const values = {
            sp: normalize(cells[4].textContent),
            csf: normalize(cells[5].textContent),
            observed: normalize(cells[6].textContent),
            expected: normalize(cells[7].textContent),
            remediation: normalize(cells[8].textContent)
        };

        const display = value =>
            value
                ? esc(value)
                : '<span class="nist-empty">Not provided by the source check.</span>';

        const detail = document.createElement("tr");
        detail.className = "nist-detail-row";
        detail.hidden = true;

        const detailCell = document.createElement("td");
        detailCell.colSpan = cells.length;
        detailCell.innerHTML = `
            <div class="nist-detail-grid">
                <div class="nist-detail-block">
                    <span class="nist-detail-label">NIST SP 800-53 Rev. 5</span>
                    <div class="nist-detail-value">${display(values.sp)}</div>
                </div>

                <div class="nist-detail-block">
                    <span class="nist-detail-label">NIST CSF 2.0</span>
                    <div class="nist-detail-value">${display(values.csf)}</div>
                </div>

                <div class="nist-detail-block">
                    <span class="nist-detail-label">Observed</span>
                    <div class="nist-detail-value">${display(values.observed)}</div>
                </div>

                <div class="nist-detail-block">
                    <span class="nist-detail-label">Expected</span>
                    <div class="nist-detail-value">${display(values.expected)}</div>
                </div>

                <div class="nist-detail-block full">
                    <span class="nist-detail-label">Remediation</span>
                    <div class="nist-detail-value">${display(values.remediation)}</div>
                </div>
            </div>
        `;

        detail.appendChild(detailCell);
        row.after(detail);

        row.addEventListener("click", event => {
            if (event.target.closest("a,button,input,select")) return;

            const opening = detail.hidden;
            detail.hidden = !opening;
            row.classList.toggle("expanded", opening);
        });

        rows.push({ row, detail });
    });

    const chips = Array.from(
        detailedSection.querySelectorAll(".nist-filter-chip")
    );
    const search = document.getElementById("nistFindingsSearch");
    const riskFilter = document.getElementById("nistRiskFilter");
    const visibleCount = document.getElementById("nistVisibleCount");

    let activeStatus = "all";

    function applyFilters() {
        const query = lower(search?.value);
        const risk = riskFilter?.value || "all";
        let visible = 0;

        rows.forEach(({ row, detail }) => {
            const statusMatch =
                activeStatus === "all" ||
                row.dataset.status === activeStatus;

            const riskMatch =
                risk === "all" ||
                row.dataset.risk === risk;

            const textMatch =
                !query ||
                row.dataset.search.includes(query);

            const show = statusMatch && riskMatch && textMatch;

            row.hidden = !show;

            if (!show) {
                detail.hidden = true;
                row.classList.remove("expanded");
            }

            if (show) visible += 1;
        });

        if (visibleCount) {
            visibleCount.textContent =
                `${visible} finding${visible === 1 ? "" : "s"} shown`;
        }
    }

    chips.forEach(chip => {
        chip.addEventListener("click", () => {
            activeStatus = chip.dataset.status || "all";

            chips.forEach(item => {
                item.classList.toggle("active", item === chip);
            });

            applyFilters();
        });
    });

    search?.addEventListener("input", applyFilters);
    riskFilter?.addEventListener("change", applyFilters);

    applyFilters();
});
</script>
"""

    if "</head>" in text:
        text = text.replace("</head>", interactive_css + "\n</head>", 1)
    else:
        text = interactive_css + "\n" + text

    if "</body>" in text:
        text = text.replace("</body>", interactive_js + "\n</body>", 1)
    else:
        text += "\n" + interactive_js

    report_path.write_text(text, encoding="utf-8")


def update_job_phase_from_log(job, line: str):
    """Best-effort progress phase based on real assessment output."""
    value = line.lower()

    if any(token in value for token in (
        "building assessment package",
        "generating nist",
        "nist-assessment.html",
        "writing report",
        "exporting report",
        "report generated",
    )):
        job["phase"] = "building"
        return

    if "nist" in value and any(token in value for token in (
        "map",
        "mapping",
        "compliance matrix",
        "sp 800-53",
        "csf",
    )):
        job["phase"] = "mapping"
        return

    if any(token in value for token in (
        "evaluating",
        "evaluation",
        "security checks:",
        "checks complete",
        "assessment checks",
    )):
        job["phase"] = "evaluating"
        return

    if any(token in value for token in (
        "collecting",
        "collector",
        "required graph scopes granted",
        "user summary",
    )):
        job["phase"] = "collecting"


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
        "-UseDeviceCode",
        "-OutputFolder",
        str(output_folder),
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
            job["logs"] = job["logs"][-100:]

            update_job_phase_from_log(job, line)

            device_match = DEVICE_CODE_PATTERN.search(line)

            if device_match:
                new_url = device_match.group(1)
                new_code = device_match.group(2)

                # M365-Assess can emit more than one device code.
                # Do not expose a code immediately. Keep the newest code
                # pending until it has remained unchanged for a few seconds.
                if new_code != job.get("pending_device_code"):
                    job["pending_verification_url"] = new_url
                    job["pending_device_code"] = new_code
                    job["auth_code_updated_at"] = time.monotonic()

                    # Hide any older code from the browser.
                    job["verification_url"] = None
                    job["device_code"] = None
                    job["status"] = "preparing_authentication"
                    job["phase"] = "authentication"

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

        job["phase"] = "building"

        sections_run = get_sections_run(output_folder)

        enhance_nist_report(
            Path(artifacts["report"]),
            sections_run=sections_run,
        )

        job["artifacts"] = artifacts
        job["phase"] = "completed"
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
        "phase": "queued",
        "created_at": utc_now(),
        "started_at": None,
        "completed_at": None,
        "verification_url": None,
        "device_code": None,
        "pending_verification_url": None,
        "pending_device_code": None,
        "auth_code_updated_at": None,
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

    # Only expose the newest device code after it has remained
    # unchanged for fifteen seconds. This prevents the browser from showing
    # an initial code that M365-Assess immediately replaces.
    if (
        job["status"] == "preparing_authentication"
        and job.get("pending_device_code")
        and job.get("auth_code_updated_at") is not None
    ):
        age = time.monotonic() - job["auth_code_updated_at"]

        if age >= 15:
            job["verification_url"] = job["pending_verification_url"]
            job["device_code"] = job["pending_device_code"]
            job["status"] = "awaiting_authentication"

    response = {
        "assessment_id": job["id"],
        "tenant_domain": job["tenant_domain"],
        "status": job["status"],
        "phase": job.get("phase"),
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
