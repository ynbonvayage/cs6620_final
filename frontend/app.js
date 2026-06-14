/**
 * SecureGate Dashboard — Frontend Application
 *
 * Connects to the Dashboard API (API Gateway + Lambda) to display
 * scan history from DynamoDB and full reports from S3.
 *
 * Configuration: Set API_BASE_URL to your API Gateway invoke URL.
 * After `terraform apply`, run:
 *   terraform output -raw lambda_function_url
 * and paste the value below (without trailing slash).
 */

// ─── Configuration ──────────────────────────────────────────────────────────
// Replace this with your API Gateway URL after deployment.
// Example: "https://abc123xyz.execute-api.us-east-1.amazonaws.com"
const API_BASE_URL = "https://2l8bpgmbji.execute-api.us-east-1.amazonaws.com";

// ─── DOM References ─────────────────────────────────────────────────────────
const $tbody             = document.getElementById("scans-tbody");
const $scanCount         = document.getElementById("scan-count");
const $statTotal         = document.getElementById("stat-total-value");
const $statHigh          = document.getElementById("stat-high-value");
const $statMedium        = document.getElementById("stat-medium-value");
const $statLow           = document.getElementById("stat-low-value");
const $modal             = document.getElementById("detail-modal");
const $modalTitle        = document.getElementById("modal-title");
const $modalBody         = document.getElementById("modal-body");
const $modalClose        = document.getElementById("modal-close");
const $connStatus        = document.getElementById("connection-status");
const $toastContainer    = document.getElementById("toast-container");

// Subscribe Modal DOM References
const $subscribeBtn      = document.getElementById("subscribe-btn");
const $subscribeModal    = document.getElementById("subscribe-modal");
const $subscribeClose    = document.getElementById("subscribe-modal-close");
const $subscribeForm     = document.getElementById("subscribe-form");
const $subSubmitBtn      = document.getElementById("sub-submit-btn");

// ─── State ──────────────────────────────────────────────────────────────────
let scans = [];
let currentRepo = "";

// ─── Init ───────────────────────────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
  if (!API_BASE_URL) {
    setConnectionStatus("error", "API URL not configured");
    showToast("Set API_BASE_URL in app.js to connect to your API Gateway.", "error");
    renderEmpty("API_BASE_URL not configured. Edit app.js and set your API Gateway URL.");
    return;
  }

  // Parse repo from URL parameter ?repo=xxx
  const urlParams = new URLSearchParams(window.location.search);
  const repoParam = urlParams.get("repo");
  if (repoParam) {
    currentRepo = repoParam.trim();
  }

  // Check if we have a repo to query, otherwise prompt user
  if (currentRepo) {
    loadScans();
  } else {
    setConnectionStatus("ok", "Connected");
    updateStats([]);
    renderEmpty("No repository specified. Please access this page using a URL link containing the '?repo=' parameter (e.g. from your PR comment).");
  }

  $modalClose.addEventListener("click", closeModal);
  $modal.addEventListener("click", (e) => {
    if (e.target === $modal) closeModal();
  });

  if ($subscribeBtn) {
    $subscribeBtn.addEventListener("click", openSubscribeModal);
  }
  if ($subscribeClose) {
    $subscribeClose.addEventListener("click", closeSubscribeModal);
  }
  if ($subscribeModal) {
    $subscribeModal.addEventListener("click", (e) => {
      if (e.target === $subscribeModal) closeSubscribeModal();
    });
  }

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      closeModal();
      closeSubscribeModal();
    }
  });

  if ($subscribeForm) {
    $subscribeForm.addEventListener("submit", handleSubscribeSubmit);
  }
});

// ─── API Calls ──────────────────────────────────────────────────────────────

async function loadScans() {
  if (!currentRepo) {
    updateStats([]);
    renderEmpty("No repository specified. Please access this page using a URL link containing the '?repo=' parameter (e.g. from your PR comment).");
    return;
  }

  setConnectionStatus("loading", "Loading…");
  renderLoading();

  try {
    const url = `${API_BASE_URL}/api/scans?repo=${encodeURIComponent(currentRepo)}`;

    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const data = await res.json();
    scans = data.scans || [];

    setConnectionStatus("ok", "Connected");
    updateStats(scans);
    renderScans(scans);
  } catch (err) {
    console.error("Failed to load scans:", err);
    setConnectionStatus("error", "Connection failed");
    showToast(`Failed to load scans: ${err.message}`, "error");
    renderEmpty("Failed to connect to API. Check your API_BASE_URL and network.");
  }
}

async function loadReport(scanId) {
  openModal(`Report — ${scanId.substring(0, 8)}…`);
  $modalBody.innerHTML="" + `<div class="loading-spinner"></div><span style="margin-left:8px;color:var(--text-muted)">Loading full report from S3…</span>`;

  try {
    const res = await fetch(`${API_BASE_URL}/api/reports/${scanId}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const data = await res.json();
    renderReport(data.report);
  } catch (err) {
    console.error("Failed to load report:", err);
    $modalBody.innerHTML="" + `<div class="empty-state"><p>Failed to load report: ${escapeHtml(err.message)}</p></div>`;
    showToast(`Failed to load report: ${err.message}`, "error");
  }
}

// ─── Rendering ──────────────────────────────────────────────────────────────

function renderLoading() {
  $tbody.innerHTML="" + `
    <tr class="loading-row">
      <td colspan="10">
        <div class="loading-spinner"></div>
        <span>Loading scans…</span>
      </td>
    </tr>`;
}

function renderEmpty(message) {
  $scanCount.textContent = "";
  $tbody.innerHTML="" + `
    <tr>
      <td colspan="10" class="empty-state">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
          <polyline points="14 2 14 8 20 8"/>
        </svg>
        <p>${message}</p>
      </td>
    </tr>`;
}

function renderScans(items) {
  if (!items.length) {
    renderEmpty("No scans found. Run a SAST scan to see results here.");
    return;
  }

  $scanCount.textContent = `${items.length} scan${items.length !== 1 ? "s" : ""}`;

  $tbody.innerHTML="" + items.map((scan) => {
    const hasHigh = (scan.high || 0) > 0;
    const statusClass = hasHigh ? "status-fail" : "status-pass";
    const statusText = hasHigh ? "FAIL" : "PASS";
    const date = formatDate(scan.created_at);

    return `
      <tr>
        <td>
          <span class="status-indicator ${statusClass}">
            <span class="dot-status"></span>
            ${statusText}
          </span>
        </td>
        <td><span class="scan-id" title="${escapeHtml(scan.scan_id)}">${(scan.scan_id || "").substring(0, 8)}…</span></td>
        <td>${escapeHtml(scan.repo || "—")}</td>
        <td>${escapeHtml(scan.filename || "—")}</td>
        <td>${severityBadge("high", scan.high)}</td>
        <td>${severityBadge("medium", scan.medium)}</td>
        <td>${severityBadge("low", scan.low)}</td>
        <td><strong>${scan.total || 0}</strong></td>
        <td style="color:var(--text-muted);font-size:0.78rem;white-space:nowrap">${date}</td>
        <td>
          <button class="btn btn-sm btn-ghost" onclick="loadReport('${escapeHtml(scan.scan_id)}')">
            View Report
          </button>
        </td>
      </tr>`;
  }).join("");
}

function renderReport(report) {
  if (!report) {
    $modalBody.innerHTML="" + `<div class="empty-state"><p>Report data is empty.</p></div>`;
    return;
  }

  const summary = report.summary || {};
  const vulns = report.vulnerabilities || [];

  let html = `
    <div class="report-meta">
      <div class="report-meta-item">
        <span class="meta-label">Scan ID</span>
        <span class="meta-value">${escapeHtml(report.scanId || "—")}</span>
      </div>
      <div class="report-meta-item">
        <span class="meta-label">Repository</span>
        <span class="meta-value">${escapeHtml(report.repo || "—")}</span>
      </div>
      <div class="report-meta-item">
        <span class="meta-label">Filename</span>
        <span class="meta-value">${escapeHtml(report.filename || "—")}</span>
      </div>
      <div class="report-meta-item">
        <span class="meta-label">Scanned At</span>
        <span class="meta-value">${formatDate(report.createdAt)}</span>
      </div>
      <div class="report-meta-item">
        <span class="meta-label">HIGH</span>
        <span class="meta-value" style="color:var(--severity-high)">${summary.high || 0}</span>
      </div>
      <div class="report-meta-item">
        <span class="meta-label">MEDIUM</span>
        <span class="meta-value" style="color:var(--severity-medium)">${summary.medium || 0}</span>
      </div>
      <div class="report-meta-item">
        <span class="meta-label">LOW</span>
        <span class="meta-value" style="color:var(--severity-low)">${summary.low || 0}</span>
      </div>
      <div class="report-meta-item">
        <span class="meta-label">Total</span>
        <span class="meta-value">${summary.totalVulnerabilities || 0}</span>
      </div>
    </div>`;

  if (vulns.length === 0) {
    html += `<div class="empty-state"><p>No vulnerabilities found in this scan. 🎉</p></div>`;
  } else {
    html += `<h3 style="font-size:0.9rem;font-weight:700;margin-bottom:var(--space-md);color:var(--text-secondary)">Vulnerabilities (${vulns.length})</h3>`;
    html += `<div class="vuln-list">`;
    vulns.forEach((v) => {
      const sev = (v.severity || "low").toLowerCase();
      html += `
        <div class="vuln-card vuln-${sev}">
          <div class="vuln-card-header">
            ${severityBadge(sev, 1, true)}
            <span class="vuln-type">${escapeHtml(v.type || v.rule || "Unknown")}</span>
          </div>
          <div class="vuln-card-body">
            <p>${escapeHtml(v.message || v.description || "No description available.")}</p>
            ${v.line ? `<p class="vuln-location">Line ${v.line}${v.column ? `, Column ${v.column}` : ""}</p>` : ""}
            ${v.evidence ? `<p style="margin-top:4px">Evidence: <code>${escapeHtml(v.evidence)}</code></p>` : ""}
          </div>
        </div>`;
    });
    html += `</div>`;
  }

  $modalBody.innerHTML="" + html;
}

// ─── Stats ──────────────────────────────────────────────────────────────────

function updateStats(items) {
  const totals = items.reduce((acc, s) => {
    acc.high += s.high || 0;
    acc.medium += s.medium || 0;
    acc.low += s.low || 0;
    return acc;
  }, { high: 0, medium: 0, low: 0 });

  animateCounter($statTotal, items.length);
  animateCounter($statHigh, totals.high);
  animateCounter($statMedium, totals.medium);
  animateCounter($statLow, totals.low);
}

function animateCounter(el, target) {
  const duration = 600;
  const start = parseInt(el.textContent) || 0;
  if (start === target) { el.textContent = target; return; }

  const startTime = performance.now();
  const step = (now) => {
    const progress = Math.min((now - startTime) / duration, 1);
    const eased = 1 - Math.pow(1 - progress, 3); // ease-out cubic
    el.textContent = Math.round(start + (target - start) * eased);
    if (progress < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

// ─── Modal ──────────────────────────────────────────────────────────────────

function openModal(title) {
  $modalTitle.textContent = title;
  $modal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeModal() {
  $modal.hidden = true;
  document.body.style.overflow = "";
}

// ─── Subscribe Modal ────────────────────────────────────────────────────────

function openSubscribeModal() {
  if ($subscribeModal) {
    $subscribeModal.hidden = false;
    document.body.style.overflow = "hidden";
  }
}

function closeSubscribeModal() {
  if ($subscribeModal) {
    $subscribeModal.hidden = true;
    document.body.style.overflow = "";
  }
}

async function handleSubscribeSubmit(e) {
  e.preventDefault();
  const githubUsername = document.getElementById("sub-github-username").value.trim();
  const email = document.getElementById("sub-email").value.trim();

  if (!githubUsername || !email) return;

  $subSubmitBtn.disabled = true;
  $subSubmitBtn.textContent = "Subscribing...";

  try {
    const res = await fetch(`${API_BASE_URL}/api/subscribe`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ githubUsername, email }),
    });

    const data = await res.json();
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);

    showToast("Verification email sent! Please check your mailbox to confirm.", "success");
    $subscribeForm.reset();
    closeSubscribeModal();
  } catch (err) {
    console.error("Subscription failed:", err);
    showToast(`Subscription failed: ${err.message}`, "error");
  } finally {
    $subSubmitBtn.disabled = false;
    $subSubmitBtn.textContent = "Subscribe";
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function severityBadge(level, count, labelOnly = false) {
  const n = count || 0;
  if (n === 0 && !labelOnly) {
    return `<span class="severity-badge severity-zero">0</span>`;
  }
  const cls = `severity-${level}`;
  const text = labelOnly ? level.toUpperCase() : n;
  return `<span class="severity-badge ${cls}">${text}</span>`;
}

function formatDate(iso) {
  if (!iso) return "—";
  try {
    const d = new Date(iso);
    return d.toLocaleString("en-US", {
      month: "short", day: "numeric", year: "numeric",
      hour: "2-digit", minute: "2-digit", hour12: false,
    });
  } catch {
    return iso;
  }
}

function escapeHtml(str) {
  if (!str) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function setConnectionStatus(state, text) {
  $connStatus.className = `status-dot status-${state}`;
  $connStatus.querySelector(".status-text").textContent = text;
}

function showToast(message, type = "success") {
  const toast = document.createElement("div");
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  $toastContainer.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = "0";
    toast.style.transform = "translateX(40px)";
    toast.style.transition = "all 0.3s ease";
    setTimeout(() => toast.remove(), 300);
  }, 4000);
}
