function Export-HipaaHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [object[]]$SectionSummary,

        [Parameter(Mandatory)]
        [object[]]$ReferenceSummary,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$TenantLabel,

        [Parameter()]
        [string[]]$Sections = @(),

        [Parameter()]
        [string]$SourceAssessmentFolder = ''
    )

    function ConvertTo-HtmlSafe {
        param([object]$Value)

        if ($null -eq $Value) {
            return ''
        }

        return [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }

    function Get-StatusClass {
        param([string]$Status)

        switch -Regex ($Status) {
            '^(?i)pass$'    { return 'pass' }
            '^(?i)fail$'    { return 'fail' }
            '^(?i)warning$' { return 'warning' }
            '^(?i)review$'  { return 'review' }
            '^(?i)info$'    { return 'info' }
            default         { return 'other' }
        }
    }

    function Get-RiskClass {
        param([string]$Risk)

        switch -Regex ($Risk) {
            '^(?i)critical$' { return 'critical' }
            '^(?i)high$'     { return 'high' }
            '^(?i)medium$'   { return 'medium' }
            '^(?i)low$'      { return 'low' }
            default          { return 'info' }
        }
    }

    $total = @($Findings).Count
    $passes = @($Findings | Where-Object Status -Match '^(?i)Pass$').Count
    $fails = @($Findings | Where-Object Status -Match '^(?i)Fail$').Count
    $warnings = @($Findings | Where-Object Status -Match '^(?i)Warning$').Count
    $reviews = @($Findings | Where-Object Status -Match '^(?i)Review$').Count
    $infos = @($Findings | Where-Object Status -Match '^(?i)Info$').Count

    $critical = @(
        $Findings |
            Where-Object RiskSeverity -Match '^(?i)Critical$'
    ).Count

    $referenceCount = @($ReferenceSummary).Count

    $representedSections = @(
        $SectionSummary |
            Where-Object { [int]$_.MappedChecks -gt 0 }
    ).Count

    $denominator = $passes + $fails + $warnings

    $postureRate = if ($denominator -gt 0) {
        [math]::Round(($passes / $denominator) * 100, 1)
    }
    else {
        0
    }

    $scopeText = if ($Sections.Count -gt 0) {
        $Sections -join ' · '
    }
    else {
        'Microsoft 365'
    }

    #
    # HIPAA section cards
    #

    $sectionCards = foreach ($section in $SectionSummary) {

        $mapped = [int]$section.MappedChecks
        $covered = [int]$section.CoveredReferences

        $statusText = if ($mapped -eq 0) {
            'No automated evidence'
        }
        else {
            "$mapped mapped checks"
        }

        $rateText = if ($mapped -eq 0) {
            '—'
        }
        elseif ($null -eq $section.MappedCheckPassRate -or
                [string]::IsNullOrWhiteSpace([string]$section.MappedCheckPassRate)) {
            '—'
        }
        else {
            "$($section.MappedCheckPassRate)%"
        }

@"
<div class="section-card" data-subpart="$(ConvertTo-HtmlSafe $section.Subpart)">
    <div class="section-card-top">
        <span class="section-id">§$(ConvertTo-HtmlSafe $section.HipaaSection)</span>
        <span class="section-rate">$rateText</span>
    </div>

    <h3>$(ConvertTo-HtmlSafe $section.Label)</h3>

    <p>$(ConvertTo-HtmlSafe $section.Description)</p>

    <div class="section-stats">
        <span>$statusText</span>
        <span>$covered covered references</span>
    </div>

    <div class="mini-status">
        <span class="pass">Pass $($section.Pass)</span>
        <span class="fail">Fail $($section.Fail)</span>
        <span class="warning">Warning $($section.Warning)</span>
        <span class="review">Review $($section.Review)</span>
    </div>
</div>
"@
    }

    #
    # Detailed finding rows
    #

    $findingRows = foreach ($finding in $Findings) {

        $statusClass = Get-StatusClass $finding.Status
        $riskClass = Get-RiskClass $finding.RiskSeverity

        $searchText = @(
            $finding.CheckId,
            $finding.Setting,
            $finding.Category,
            $finding.Status,
            $finding.RiskSeverity,
            $finding.HipaaControls,
            $finding.HipaaSafeguards,
            $finding.Source,
            $finding.Remediation
        ) -join ' '

        $safeSearch = ConvertTo-HtmlSafe $searchText

@"
<details class="finding-card"
    data-status="$statusClass"
    data-risk="$riskClass"
    data-search="$safeSearch">

    <summary>
        <div class="finding-main">
            <div class="finding-badges">
                <span class="badge status-$statusClass">$(ConvertTo-HtmlSafe $finding.Status)</span>
                <span class="badge risk-$riskClass">$(ConvertTo-HtmlSafe $finding.RiskSeverity)</span>
            </div>

            <div class="finding-copy">
                <strong>$(ConvertTo-HtmlSafe $finding.Setting)</strong>
                <span>$(ConvertTo-HtmlSafe $finding.CheckId) · $(ConvertTo-HtmlSafe $finding.Category)</span>
            </div>
        </div>

        <div class="finding-mapping">
            $(ConvertTo-HtmlSafe $finding.HipaaControls)
        </div>
    </summary>

    <div class="finding-detail">

        <div class="detail-grid">
            <div class="detail-block">
                <span class="detail-label">HIPAA references</span>
                <strong>$(ConvertTo-HtmlSafe $finding.HipaaControls)</strong>
            </div>

            <div class="detail-block">
                <span class="detail-label">HIPAA safeguards</span>
                <strong>$(ConvertTo-HtmlSafe $finding.HipaaSafeguards)</strong>
            </div>

            <div class="detail-block">
                <span class="detail-label">Evidence source</span>
                <strong>$(ConvertTo-HtmlSafe $finding.Source)</strong>
            </div>

            <div class="detail-block">
                <span class="detail-label">Confidence</span>
                <strong>$(ConvertTo-HtmlSafe $finding.Confidence)</strong>
            </div>
        </div>

        <div class="evidence-grid">
            <div class="evidence-box">
                <span>Observed state</span>
                <p>$(ConvertTo-HtmlSafe $finding.ObservedValue)</p>
            </div>

            <div class="evidence-box">
                <span>Expected state</span>
                <p>$(ConvertTo-HtmlSafe $finding.ExpectedValue)</p>
            </div>
        </div>

        <div class="remediation-box">
            <span>Recommended remediation</span>
            <p>$(ConvertTo-HtmlSafe $finding.Remediation)</p>
        </div>

        $(if (-not [string]::IsNullOrWhiteSpace([string]$finding.Limitations)) {
@"
        <div class="limitations-box">
            <span>Assessment limitation</span>
            <p>$(ConvertTo-HtmlSafe $finding.Limitations)</p>
        </div>
"@
        })
    </div>
</details>
"@
    }

    $generated = Get-Date -Format 'MMMM d, yyyy HH:mm'

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>HIPAA Microsoft 365 Assessment - $(ConvertTo-HtmlSafe $TenantLabel)</title>

<style>
:root {
    --navy: #071d3e;
    --blue: #1167d8;
    --bright: #2388ff;
    --green: #16803c;
    --red: #c4320a;
    --orange: #b54708;
    --purple: #6941c6;
    --text: #10213b;
    --muted: #667085;
    --border: #e4e7ec;
    --bg: #f6f8fb;
    --white: #fff;
}

* { box-sizing: border-box; }

body {
    margin: 0;
    background: var(--bg);
    color: var(--text);
    font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

.shell {
    width: min(1280px, calc(100% - 40px));
    margin: auto;
}

.hero {
    background:
        radial-gradient(circle at 90% 10%, rgba(35,136,255,.25), transparent 35%),
        linear-gradient(120deg, #061a36, #0b3978);
    color: white;
    padding: 54px 0 46px;
}

.eyebrow {
    font-size: 12px;
    font-weight: 800;
    letter-spacing: .16em;
    color: #91caff;
}

.hero h1 {
    margin: 10px 0 14px;
    font-size: clamp(36px, 5vw, 60px);
    letter-spacing: -.04em;
}

.hero p {
    max-width: 760px;
    margin: 0;
    line-height: 1.65;
    color: rgba(255,255,255,.75);
}

.meta {
    display: flex;
    gap: 22px;
    flex-wrap: wrap;
    margin-top: 26px;
    font-size: 13px;
    color: rgba(255,255,255,.72);
}

.warning-banner {
    margin-top: 24px;
    border: 1px solid rgba(255,255,255,.16);
    background: rgba(255,255,255,.08);
    padding: 13px 16px;
    border-radius: 10px;
    font-size: 13px;
    line-height: 1.55;
}

main {
    padding: 30px 0 70px;
}

.metric-grid {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 14px;
}

.metric {
    background: white;
    border: 1px solid var(--border);
    border-radius: 14px;
    padding: 19px;
}

.metric span {
    display: block;
    color: var(--muted);
    font-size: 12px;
    font-weight: 700;
    margin-bottom: 8px;
}

.metric strong {
    font-size: 32px;
}

.posture-panel {
    margin-top: 16px;
    background: white;
    border: 1px solid var(--border);
    border-radius: 16px;
    padding: 22px;
    display: flex;
    gap: 24px;
    align-items: center;
}

.score {
    width: 126px;
    height: 126px;
    flex: 0 0 126px;
    border-radius: 50%;
    display: grid;
    place-items: center;
    background:
        conic-gradient(
            var(--blue) 0 $postureRate%,
            #e8edf4 $postureRate% 100%
        );
}

.score-inner {
    width: 94px;
    height: 94px;
    border-radius: 50%;
    background: white;
    display: grid;
    place-content: center;
    text-align: center;
}

.score-inner strong {
    font-size: 25px;
}

.score-inner span {
    color: var(--muted);
    font-size: 10px;
}

.posture-copy h2 {
    margin: 0 0 8px;
}

.posture-copy p {
    margin: 0;
    color: var(--muted);
    line-height: 1.6;
}

.section-title {
    margin: 38px 0 15px;
}

.section-title span {
    color: var(--blue);
    font-size: 11px;
    letter-spacing: .15em;
    font-weight: 800;
}

.section-title h2 {
    margin: 5px 0;
}

.section-title p {
    margin: 0;
    color: var(--muted);
}

.rule-heading {
    margin: 26px 0 10px;
    color: var(--muted);
    font-size: 12px;
    font-weight: 800;
    letter-spacing: .13em;
    text-transform: uppercase;
}

.section-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
}

.section-card {
    background: white;
    border: 1px solid var(--border);
    border-radius: 13px;
    padding: 18px;
}

.section-card-top {
    display: flex;
    justify-content: space-between;
    gap: 12px;
}

.section-id {
    font-weight: 800;
    color: var(--blue);
}

.section-rate {
    font-size: 20px;
    font-weight: 800;
}

.section-card h3 {
    margin: 11px 0 7px;
}

.section-card p {
    margin: 0;
    color: var(--muted);
    line-height: 1.5;
    font-size: 13px;
}

.section-stats,
.mini-status {
    display: flex;
    flex-wrap: wrap;
    gap: 9px;
    margin-top: 13px;
    font-size: 11px;
}

.section-stats span {
    background: #f2f4f7;
    padding: 6px 8px;
    border-radius: 6px;
}

.mini-status span {
    font-weight: 700;
}

.pass { color: var(--green); }
.fail { color: var(--red); }
.warning { color: var(--orange); }
.review { color: var(--purple); }

.finding-tools {
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
    margin-bottom: 14px;
}

.finding-tools input,
.finding-tools select {
    border: 1px solid var(--border);
    border-radius: 9px;
    padding: 11px 12px;
    background: white;
    color: var(--text);
}

.finding-tools input {
    flex: 1;
    min-width: 260px;
}

.finding-card {
    background: white;
    border: 1px solid var(--border);
    border-radius: 11px;
    margin-bottom: 9px;
    overflow: hidden;
}

.finding-card summary {
    cursor: pointer;
    list-style: none;
    padding: 15px;
    display: grid;
    grid-template-columns: 1fr minmax(220px, 34%);
    gap: 16px;
    align-items: center;
}

.finding-card summary::-webkit-details-marker {
    display: none;
}

.finding-main {
    display: flex;
    gap: 13px;
    align-items: center;
}

.finding-badges {
    display: flex;
    gap: 5px;
    flex-wrap: wrap;
    min-width: 130px;
}

.badge {
    border-radius: 999px;
    padding: 5px 8px;
    font-size: 10px;
    font-weight: 800;
    text-transform: uppercase;
}

.status-pass { background: #ecfdf3; color: #027a48; }
.status-fail { background: #fef3f2; color: #b42318; }
.status-warning { background: #fffaeb; color: #b54708; }
.status-review { background: #f4f3ff; color: #5925dc; }
.status-info { background: #eff8ff; color: #175cd3; }

.risk-critical { background: #fff1f3; color: #c01048; }
.risk-high { background: #fff6ed; color: #c4320a; }
.risk-medium { background: #f9f5ff; color: #6941c6; }
.risk-low { background: #f0f9ff; color: #026aa2; }
.risk-info { background: #f2f4f7; color: #475467; }

.finding-copy {
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.finding-copy span,
.finding-mapping {
    font-size: 12px;
    color: var(--muted);
}

.finding-mapping {
    text-align: right;
}

.finding-detail {
    border-top: 1px solid var(--border);
    padding: 18px;
    background: #fbfcfe;
}

.detail-grid,
.evidence-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
}

.detail-block,
.evidence-box,
.remediation-box,
.limitations-box {
    border: 1px solid var(--border);
    background: white;
    border-radius: 9px;
    padding: 13px;
}

.detail-label,
.evidence-box span,
.remediation-box span,
.limitations-box span {
    display: block;
    color: var(--muted);
    font-size: 10px;
    font-weight: 800;
    letter-spacing: .08em;
    text-transform: uppercase;
    margin-bottom: 6px;
}

.evidence-grid,
.remediation-box,
.limitations-box {
    margin-top: 12px;
}

.evidence-box p,
.remediation-box p,
.limitations-box p {
    margin: 0;
    line-height: 1.55;
}

.hidden-by-filter {
    display: none;
}

footer {
    border-top: 1px solid var(--border);
    background: white;
    padding: 24px 0;
    color: var(--muted);
    font-size: 12px;
}

@media (max-width: 900px) {
    .metric-grid {
        grid-template-columns: repeat(2, 1fr);
    }

    .section-grid,
    .detail-grid,
    .evidence-grid {
        grid-template-columns: 1fr;
    }

    .finding-card summary {
        grid-template-columns: 1fr;
    }

    .finding-mapping {
        text-align: left;
    }
}

@media (max-width: 600px) {
    .metric-grid {
        grid-template-columns: 1fr;
    }

    .posture-panel {
        align-items: flex-start;
        flex-direction: column;
    }
}
</style>
</head>

<body>

<section class="hero">
    <div class="shell">

        <div class="eyebrow">
            MICROSOFT 365 · HIPAA-MAPPED SECURITY ASSESSMENT
        </div>

        <h1>HIPAA Microsoft 365 posture</h1>

        <p>
            Technical Microsoft 365 findings mapped to HIPAA
            Administrative Simplification requirements across the
            Security, Privacy and Breach Notification Rules.
        </p>

        <div class="meta">
            <span><strong>Tenant:</strong> $(ConvertTo-HtmlSafe $TenantLabel)</span>
            <span><strong>Scope:</strong> $(ConvertTo-HtmlSafe $scopeText)</span>
            <span><strong>Generated:</strong> $(ConvertTo-HtmlSafe $generated)</span>
        </div>

        <div class="warning-banner">
            This is a technical Microsoft 365 posture assessment.
            It does not constitute a legal determination, audit opinion,
            certification or formal determination of organizational HIPAA compliance.
        </div>

    </div>
</section>

<main>
<div class="shell">

    <div class="metric-grid">

        <div class="metric">
            <span>HIPAA-mapped findings</span>
            <strong>$total</strong>
        </div>

        <div class="metric">
            <span>Failing findings</span>
            <strong>$fails</strong>
        </div>

        <div class="metric">
            <span>Critical risk</span>
            <strong>$critical</strong>
        </div>

        <div class="metric">
            <span>HIPAA references observed</span>
            <strong>$referenceCount</strong>
        </div>

        <div class="metric">
            <span>Sections represented</span>
            <strong>$representedSections / $(@($SectionSummary).Count)</strong>
        </div>

    </div>

    <div class="posture-panel">

        <div class="score">
            <div class="score-inner">
                <strong>$postureRate%</strong>
                <span>MAPPED-CHECK PASS RATE</span>
            </div>
        </div>

        <div class="posture-copy">
            <h2>Microsoft 365 mapped-check posture</h2>

            <p>
                Pass / (Pass + Fail + Warning) across HIPAA-mapped
                technical findings. Review and Info findings are excluded
                from this indicator. This is not a HIPAA compliance percentage.
            </p>

            <div class="mini-status">
                <span class="pass">Pass $passes</span>
                <span class="fail">Fail $fails</span>
                <span class="warning">Warning $warnings</span>
                <span class="review">Review $reviews</span>
                <span>Info $infos</span>
            </div>
        </div>

    </div>

    <div class="section-title">
        <span>HIPAA FRAMEWORK VIEW</span>
        <h2>Coverage by rule and safeguard</h2>
        <p>
            Sections with zero mapped checks indicate that this automated
            Microsoft 365 assessment did not establish technical evidence
            for that part of HIPAA.
        </p>
    </div>

    <div class="rule-heading">Security Rule · Subpart C</div>
    <div class="section-grid">
        $(
            ($SectionSummary |
                Where-Object Subpart -Match '^C') |
                ForEach-Object {
                    $index = [array]::IndexOf(@($SectionSummary), $_)
                    $sectionCards[$index]
                }
        )
    </div>

    <div class="rule-heading">Breach Notification Rule · Subpart D</div>
    <div class="section-grid">
        $(
            ($SectionSummary |
                Where-Object Subpart -Match '^D') |
                ForEach-Object {
                    $index = [array]::IndexOf(@($SectionSummary), $_)
                    $sectionCards[$index]
                }
        )
    </div>

    <div class="rule-heading">Privacy Rule · Subpart E</div>
    <div class="section-grid">
        $(
            ($SectionSummary |
                Where-Object Subpart -Match '^E') |
                ForEach-Object {
                    $index = [array]::IndexOf(@($SectionSummary), $_)
                    $sectionCards[$index]
                }
        )
    </div>

    <div class="section-title">
        <span>DETAILED FINDINGS</span>
        <h2>Microsoft 365 evidence and remediation</h2>
        <p>
            Search or filter the HIPAA-mapped technical findings.
            Open any finding to inspect its regulatory references and remediation.
        </p>
    </div>

    <div class="finding-tools">

        <input
            id="searchInput"
            type="search"
            placeholder="Search finding, service, HIPAA reference or remediation..."
        >

        <select id="statusFilter">
            <option value="">All statuses</option>
            <option value="fail">Fail</option>
            <option value="warning">Warning</option>
            <option value="review">Review</option>
            <option value="pass">Pass</option>
            <option value="info">Info</option>
        </select>

        <select id="riskFilter">
            <option value="">All risk levels</option>
            <option value="critical">Critical</option>
            <option value="high">High</option>
            <option value="medium">Medium</option>
            <option value="low">Low</option>
            <option value="info">Info</option>
        </select>

    </div>

    <div id="findingList">
        $($findingRows -join "`n")
    </div>

</div>
</main>

<footer>
    <div class="shell">
        M365 HIPAA Assessment · Powered by M365-Assess ·
        Technical configuration mapping only
    </div>
</footer>

<script>
(function () {

    const search = document.getElementById('searchInput');
    const status = document.getElementById('statusFilter');
    const risk = document.getElementById('riskFilter');

    const cards = Array.from(
        document.querySelectorAll('.finding-card')
    );

    function applyFilters() {

        const term = search.value.trim().toLowerCase();
        const statusValue = status.value;
        const riskValue = risk.value;

        cards.forEach(function (card) {

            const haystack =
                (card.dataset.search || '').toLowerCase();

            const searchMatch =
                !term || haystack.includes(term);

            const statusMatch =
                !statusValue ||
                card.dataset.status === statusValue;

            const riskMatch =
                !riskValue ||
                card.dataset.risk === riskValue;

            card.classList.toggle(
                'hidden-by-filter',
                !(searchMatch && statusMatch && riskMatch)
            );
        });
    }

    search.addEventListener('input', applyFilters);
    status.addEventListener('change', applyFilters);
    risk.addEventListener('change', applyFilters);

})();
</script>

</body>
</html>
"@

    $directory = Split-Path -Parent $Path

    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item `
            -ItemType Directory `
            -Path $directory `
            -Force |
            Out-Null
    }

    Set-Content `
        -Path $Path `
        -Value $html `
        -Encoding utf8

    return $Path
}
