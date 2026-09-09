(() => {
    "use strict";

    const modal = document.getElementById("assessmentModal");
    const openAssessment = document.getElementById("openAssessment");
    const closeModal = document.getElementById("closeModal");
    const modalOverlay = document.getElementById("modalOverlay");

    const tenantStep = document.getElementById("tenantStep");
    const startingStep = document.getElementById("startingStep");
    const authStep = document.getElementById("authStep");
    const runningStep = document.getElementById("runningStep");
    const completeStep = document.getElementById("completeStep");
    const failedStep = document.getElementById("failedStep");

    const tenantForm = document.getElementById("tenantForm");
    const tenantDomain = document.getElementById("tenantDomain");
    const tenantError = document.getElementById("tenantError");

    const deviceCode = document.getElementById("deviceCode");
    const copyCode = document.getElementById("copyCode");
    const microsoftLogin = document.getElementById("microsoftLogin");

    const runningTenant = document.getElementById("runningTenant");
    const completedTenant = document.getElementById("completedTenant");

    const failureMessage = document.getElementById("failureMessage");
    const tryAgain = document.getElementById("tryAgain");

    const reportLink = document.getElementById("reportLink");

    const findingsLink =
        document.getElementById("findingsLink");

    const referenceLink =
        document.getElementById("referenceLink");

    const sectionLink =
        document.getElementById("sectionLink");

    const metadataLink =
        document.getElementById("metadataLink");

    const reportUrl =
        document.getElementById("reportUrl");

    const outputFolder =
        document.getElementById("outputFolder");

    const steps = [
        tenantStep,
        startingStep,
        authStep,
        runningStep,
        completeStep,
        failedStep
    ];

    let assessmentId = null;
    let pollTimer = null;
    let verificationUrl = null;
    let lastStatus = null;


    /*
     * Progress stages returned by the HIPAA FastAPI backend.
     */

    const phaseOrder = [
        "authentication",
        "collecting",
        "evaluating",
        "mapping",
        "building"
    ];


    /*
     * Modal / step helpers
     */

    function showStep(step) {
        steps.forEach(item => {
            if (!item) {
                return;
            }

            item.classList.toggle(
                "hidden",
                item !== step
            );
        });
    }


    function openAssessmentModal() {
        modal.classList.remove("hidden");

        document.body.style.overflow =
            "hidden";

        resetAssessment();

        setTimeout(() => {
            tenantDomain.focus();
        }, 100);
    }


    function closeAssessmentModal() {
        modal.classList.add("hidden");

        document.body.style.overflow =
            "";

        stopPolling();
    }


    function resetAssessment() {
        stopPolling();

        assessmentId = null;
        verificationUrl = null;
        lastStatus = null;

        tenantError.textContent = "";

        deviceCode.textContent =
            "---------";

        failureMessage.textContent =
            "Review the assessment engine output and try again.";

        reportLink.href = "#";

        [
            findingsLink,
            referenceLink,
            sectionLink,
            metadataLink
        ].forEach(link => {

            if (!link) {
                return;
            }

            link.href = "#";
            link.hidden = false;
        });

        reportUrl.textContent = "";
        outputFolder.textContent = "";

        updateProgress(
            "authentication",
            false
        );

        showStep(tenantStep);
    }


    /*
     * Polling helpers
     */

    function stopPolling() {
        if (!pollTimer) {
            return;
        }

        clearTimeout(pollTimer);

        pollTimer = null;
    }


    function schedulePoll(delay = 1200) {
        stopPolling();

        pollTimer = window.setTimeout(
            pollAssessment,
            delay
        );
    }


    /*
     * Progress display
     */

    function updateProgress(
        phase,
        running = true
    ) {
        const items = Array.from(
            document.querySelectorAll(
                ".progress-item[data-phase]"
            )
        );

        if (!running) {
            items.forEach(item => {
                item.classList.remove(
                    "active"
                );
            });

            return;
        }

        let phaseIndex =
            phaseOrder.indexOf(phase);

        if (phaseIndex < 0) {

            if (phase === "completed") {
                phaseIndex =
                    phaseOrder.length - 1;
            }
            else {
                phaseIndex = 1;
            }
        }

        items.forEach(item => {

            const itemIndex =
                phaseOrder.indexOf(
                    item.dataset.phase
                );

            item.classList.toggle(
                "active",
                itemIndex <= phaseIndex
            );
        });
    }


    /*
     * Downloads
     */

    function setDownloadLink(
        element,
        url
    ) {
        if (!element) {
            return;
        }

        if (!url) {
            element.href = "#";
            element.hidden = true;
            return;
        }

        element.href = url;
        element.hidden = false;
    }


    /*
     * Start assessment
     */

    async function startAssessment(event) {
        event.preventDefault();

        const domain =
            tenantDomain.value
                .trim()
                .toLowerCase();

        if (!domain) {
            tenantError.textContent =
                "Enter the tenant primary onmicrosoft.com domain.";

            return;
        }

        if (
            !domain.endsWith(
                ".onmicrosoft.com"
            )
        ) {
            tenantError.textContent =
                "Enter the primary onmicrosoft.com tenant domain.";

            return;
        }

        tenantError.textContent = "";

        showStep(startingStep);

        try {
            const response =
                await fetch(
                    "/assessments",
                    {
                        method: "POST",

                        headers: {
                            "Content-Type":
                                "application/json"
                        },

                        body: JSON.stringify({
                            tenant_domain:
                                domain
                        })
                    }
                );

            const data =
                await response.json();

            if (!response.ok) {
                throw new Error(
                    data?.detail ||
                    "The assessment could not be started."
                );
            }

            assessmentId =
                data.assessment_id;

            runningTenant.textContent =
                domain;

            completedTenant.textContent =
                domain;

            schedulePoll(500);
        }
        catch (error) {
            showStep(tenantStep);

            tenantError.textContent =
                error.message ||
                "The assessment could not be started.";
        }
    }


    /*
     * Poll HIPAA assessment job
     */

    async function pollAssessment() {

        if (!assessmentId) {
            return;
        }

        try {
            const response =
                await fetch(
                    `/assessments/${encodeURIComponent(
                        assessmentId
                    )}`,
                    {
                        cache: "no-store"
                    }
                );

            const data =
                await response.json();

            if (!response.ok) {
                throw new Error(
                    data?.detail ||
                    "Unable to retrieve assessment status."
                );
            }

            const status =
                data.status;

            const phase =
                data.phase || "";

            lastStatus = status;


            /*
             * Preparing / waiting for device-code generation
             */

            if (
                status === "queued" ||
                status === "starting" ||
                status ===
                    "preparing_authentication"
            ) {
                showStep(startingStep);

                schedulePoll();

                return;
            }


            /*
             * Microsoft device-code authentication
             */

            if (
                status ===
                "awaiting_authentication"
            ) {
                verificationUrl =
                    data.verification_url ||
                    null;

                deviceCode.textContent =
                    data.device_code ||
                    "---------";

                showStep(authStep);

                schedulePoll();

                return;
            }


            /*
             * M365 collection / evaluation / HIPAA mapping
             */

            if (status === "running") {

                runningTenant.textContent =
                    `Assessing ${
                        data.tenant_domain || ""
                    }`;

                showStep(runningStep);

                updateProgress(
                    phase,
                    true
                );

                schedulePoll();

                return;
            }


            /*
             * Assessment complete
             */

            if (
                status === "completed"
            ) {
                stopPolling();

                updateProgress(
                    "completed",
                    true
                );

                const downloads =
                    data.downloads || {};


                /*
                 * Main HTML report
                 */

                reportLink.href =
                    data.report_url || "#";


                /*
                 * HIPAA package downloads
                 */

                setDownloadLink(
                    findingsLink,
                    downloads.findings_csv
                );

                setDownloadLink(
                    referenceLink,
                    downloads.reference_summary_csv
                );

                setDownloadLink(
                    sectionLink,
                    downloads.section_summary_csv
                );

                setDownloadLink(
                    metadataLink,
                    downloads.metadata_json
                );


                /*
                 * Technical output information
                 */

                reportUrl.textContent =
                    data.report_url
                        ? (
                            window.location.origin +
                            data.report_url
                        )
                        : "Not available";

                outputFolder.textContent =
                    data.output_folder ||
                    "Not available";


                completedTenant.textContent =
                    `${
                        data.tenant_domain ||
                        "Microsoft 365 tenant"
                    } · assessment completed`;


                /*
                 * Briefly show all progress stages complete,
                 * then display the results.
                 */

                showStep(runningStep);

                updateProgress(
                    "completed",
                    true
                );

                setTimeout(() => {
                    showStep(
                        completeStep
                    );
                }, 700);

                return;
            }


            /*
             * Assessment failed
             */

            if (status === "failed") {
                stopPolling();

                const logs =
                    Array.isArray(
                        data.recent_logs
                    )
                        ? data.recent_logs
                            .slice(-4)
                            .join("\n")
                        : "";

                failureMessage.textContent =
                    data.error ||
                    logs ||
                    "The assessment process stopped unexpectedly.";

                showStep(failedStep);

                return;
            }


            /*
             * Unknown/transitional state
             */

            schedulePoll();
        }
        catch (error) {
            stopPolling();

            failureMessage.textContent =
                error.message ||
                "Unable to retrieve assessment status.";

            showStep(failedStep);
        }
    }


    /*
     * Main event listeners
     */

    openAssessment.addEventListener(
        "click",
        openAssessmentModal
    );


    closeModal.addEventListener(
        "click",
        closeAssessmentModal
    );


    modalOverlay.addEventListener(
        "click",
        closeAssessmentModal
    );


    tenantForm.addEventListener(
        "submit",
        startAssessment
    );


    /*
     * Device-code copy
     */

    copyCode.addEventListener(
        "click",
        async () => {

            const code =
                deviceCode.textContent
                    .trim();

            if (
                !code ||
                code === "---------"
            ) {
                return;
            }

            try {
                await navigator.clipboard
                    .writeText(code);

                const original =
                    copyCode.textContent;

                copyCode.textContent =
                    "Copied";

                setTimeout(() => {
                    copyCode.textContent =
                        original;
                }, 1200);
            }
            catch {
                copyCode.textContent =
                    "Copy manually";

                setTimeout(() => {
                    copyCode.textContent =
                        "Copy code";
                }, 1500);
            }
        }
    );


    /*
     * Open Microsoft authentication
     */

    microsoftLogin.addEventListener(
        "click",
        () => {

            if (!verificationUrl) {
                return;
            }

            window.open(
                verificationUrl,
                "_blank",
                "noopener,noreferrer"
            );
        }
    );


    /*
     * Retry after failure
     */

    tryAgain.addEventListener(
        "click",
        () => {

            resetAssessment();

            tenantDomain.focus();
        }
    );


    /*
     * Escape closes modal
     */

    document.addEventListener(
        "keydown",
        event => {

            if (
                event.key === "Escape" &&
                !modal.classList.contains(
                    "hidden"
                )
            ) {
                closeAssessmentModal();
            }
        }
    );

})();