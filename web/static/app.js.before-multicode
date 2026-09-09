const modal = document.getElementById("assessmentModal");
const openButton = document.getElementById("openAssessment");
const closeButton = document.getElementById("closeModal");
const modalOverlay = document.getElementById("modalOverlay");

const tenantStep = document.getElementById("tenantStep");
const startingStep = document.getElementById("startingStep");
const authStep = document.getElementById("authStep");
const runningStep = document.getElementById("runningStep");
const completeStep = document.getElementById("completeStep");
const failedStep = document.getElementById("failedStep");

const tenantForm = document.getElementById("tenantForm");
const tenantInput = document.getElementById("tenantDomain");
const tenantError = document.getElementById("tenantError");

const deviceCode = document.getElementById("deviceCode");
const copyCode = document.getElementById("copyCode");
const microsoftLogin = document.getElementById("microsoftLogin");

const runningTenant = document.getElementById("runningTenant");
const completedTenant = document.getElementById("completedTenant");

const reportLink = document.getElementById("reportLink");
const excelLink = document.getElementById("excelLink");
const spLink = document.getElementById("spLink");
const csfLink = document.getElementById("csfLink");

const reportUrl = document.getElementById("reportUrl");
const outputFolder = document.getElementById("outputFolder");

const failureMessage = document.getElementById("failureMessage");
const tryAgain = document.getElementById("tryAgain");

let assessmentId = null;
let verificationUrl = null;
let pollTimer = null;
let currentTenant = null;


function showStep(step) {
    [
        tenantStep,
        startingStep,
        authStep,
        runningStep,
        completeStep,
        failedStep
    ].forEach(element => {
        element.classList.add("hidden");
    });

    step.classList.remove("hidden");
}


function openModal() {
    modal.classList.remove("hidden");
    document.body.style.overflow = "hidden";
}


function closeModal() {
    modal.classList.add("hidden");
    document.body.style.overflow = "";

    if (
        !assessmentId ||
        completeStep.classList.contains("hidden") === false
    ) {
        resetAssessment();
    }
}


function resetAssessment() {
    if (pollTimer) {
        clearTimeout(pollTimer);
    }

    assessmentId = null;
    verificationUrl = null;
    currentTenant = null;

    tenantInput.value = "";
    tenantError.textContent = "";

    showStep(tenantStep);
}


openButton.addEventListener("click", () => {
    resetAssessment();
    openModal();

    setTimeout(() => {
        tenantInput.focus();
    }, 100);
});


closeButton.addEventListener("click", closeModal);
modalOverlay.addEventListener("click", closeModal);


tenantForm.addEventListener("submit", async event => {
    event.preventDefault();

    tenantError.textContent = "";

    currentTenant = tenantInput.value.trim().toLowerCase();

    if (!currentTenant.endsWith(".onmicrosoft.com")) {
        tenantError.textContent =
            "Enter the primary onmicrosoft.com tenant domain.";
        return;
    }

    showStep(startingStep);

    try {
        const response = await fetch("/assessments", {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                tenant_domain: currentTenant
            })
        });

        const data = await response.json();

        if (!response.ok) {
            throw new Error(
                data.detail ||
                "Unable to start the assessment."
            );
        }

        assessmentId = data.assessment_id;

        pollAssessment();

    } catch (error) {
        showFailure(error.message);
    }
});


async function pollAssessment() {
    if (!assessmentId) {
        return;
    }

    try {
        const response = await fetch(
            `/assessments/${assessmentId}`
        );

        const data = await response.json();

        if (!response.ok) {
            throw new Error(
                data.detail ||
                "Unable to retrieve assessment status."
            );
        }

        handleAssessmentStatus(data);

    } catch (error) {
        showFailure(error.message);
    }
}


function handleAssessmentStatus(data) {

    if (
        data.status === "queued" ||
        data.status === "starting"
    ) {
        showStep(startingStep);
        schedulePoll();
        return;
    }


    if (data.status === "awaiting_authentication") {

        verificationUrl = data.verification_url;

        deviceCode.textContent =
            data.device_code || "Unavailable";

        showStep(authStep);
        schedulePoll();
        return;
    }


    if (data.status === "running") {

        runningTenant.textContent =
            `Tenant: ${data.tenant_domain}`;

        showStep(runningStep);
        schedulePoll();
        return;
    }


    if (data.status === "completed") {

        clearTimeout(pollTimer);

        completedTenant.textContent =
            `Tenant: ${data.tenant_domain}`;

        const absoluteReport =
            `${window.location.origin}${data.report_url}`;

        reportLink.href = data.report_url;
        reportUrl.textContent = absoluteReport;

        outputFolder.textContent =
            data.output_folder || "Not available";

        setDownloadLink(
            excelLink,
            data.downloads?.excel
        );

        setDownloadLink(
            spLink,
            data.downloads?.sp80053_csv
        );

        setDownloadLink(
            csfLink,
            data.downloads?.csf_csv
        );

        showStep(completeStep);
        return;
    }


    if (data.status === "failed") {
        showFailure(
            data.error ||
            "The assessment engine reported a failure."
        );
        return;
    }


    schedulePoll();
}


function schedulePoll() {
    clearTimeout(pollTimer);

    pollTimer = setTimeout(
        pollAssessment,
        2000
    );
}


function setDownloadLink(element, url) {

    if (!url) {
        element.style.display = "none";
        return;
    }

    element.style.display = "flex";
    element.href = url;
}


microsoftLogin.addEventListener("click", () => {

    if (!verificationUrl) {
        return;
    }

    window.open(
        verificationUrl,
        "_blank",
        "noopener,noreferrer"
    );
});


copyCode.addEventListener("click", async () => {

    try {
        await navigator.clipboard.writeText(
            deviceCode.textContent.trim()
        );

        const original = copyCode.textContent;

        copyCode.textContent = "Copied";

        setTimeout(() => {
            copyCode.textContent = original;
        }, 1500);

    } catch {
        copyCode.textContent = "Copy manually";
    }
});


function showFailure(message) {

    clearTimeout(pollTimer);

    failureMessage.textContent = message;

    showStep(failedStep);
}


tryAgain.addEventListener("click", () => {
    resetAssessment();
});


document.addEventListener("keydown", event => {

    if (
        event.key === "Escape" &&
        !modal.classList.contains("hidden")
    ) {
        closeModal();
    }
});
