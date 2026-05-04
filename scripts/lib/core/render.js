'use strict';

/**
 * render.js — Collected Result HTML Renderer
 *
 * Generates standalone HTML pages from scan result JSON objects,
 * suitable for embedding in the assistant document viewer (iframe srcdoc).
 *
 * Generalized from agent.system-integration-quality-control/scripts/lib/audit-assistant/render.js:
 *   - STATUS_LABELS hardcoded map → accept from config parameter with defaults
 *   - CARD_MAP hardcoded object → accept from config parameter with defaults
 *   - lang="zh-TW" → accept locale from config parameter
 *   - All exported functions accept an optional config parameter
 *
 * Uses OKLCH design tokens with hex fallback matching templates/styles.css.
 */

// ---------------------------------------------------------------------------
// CSS (self-contained for iframe srcdoc)
// ---------------------------------------------------------------------------

const CSS = `
<style>
:root {
  --bg-base:     oklch(0.97 0.005 250);
  --bg-surface:  oklch(0.94 0.005 250);
  --bg-overlay:  oklch(0.90 0.008 250);
  --bg-hover:    oklch(0.92 0.005 250);
  --text-primary:   oklch(0.20 0.01 250);
  --text-secondary: oklch(0.45 0.01 250);
  --text-muted:     oklch(0.60 0.008 250);
  --color-critical: oklch(0.55 0.22 25);
  --color-high:     oklch(0.55 0.16 55);
  --color-medium:   oklch(0.52 0.14 80);
  --color-low:      oklch(0.52 0.13 240);
  --color-pass:     oklch(0.48 0.16 150);
  --color-fail:     oklch(0.55 0.22 25);
  --color-warn:     oklch(0.52 0.14 80);
  --color-info:     oklch(0.52 0.13 240);
  --border-subtle:  oklch(0.85 0.005 250);
  --text-xs:   1.125rem;
  --text-sm:   1.25rem;
  --text-base: 1.5rem;
  --text-lg:   1.75rem;
  --text-xl:   2rem;
  --text-2xl:  3rem;
}
@supports not (color: oklch(0 0 0)) {
  :root {
    --bg-base: #f5f6f8; --bg-surface: #ecedf0; --bg-overlay: #dfe0e5;
    --bg-hover: #e5e6ea; --text-primary: #1e2030; --text-secondary: #5e6070;
    --text-muted: #8a8c98; --color-critical: #c93135; --color-high: #b86a2a;
    --color-medium: #8a7020; --color-low: #2a6bb8; --color-pass: #1e8050;
    --color-fail: #c93135; --color-warn: #8a7020; --color-info: #2a6bb8;
    --border-subtle: #d5d6da;
  }
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--bg-base); color: var(--text-primary);
  padding: 2rem; line-height: 1.6; font-size: var(--text-sm);
}
h1 { font-size: var(--text-xl); font-weight: 700; margin-bottom: 0.5rem; }
.header { margin-bottom: 2rem; }
.meta { font-size: var(--text-xs); color: var(--text-muted); margin-top: 0.25rem; }
.badge {
  display: inline-block; padding: 0.125rem 0.625rem; border-radius: 0.25rem;
  font-size: var(--text-xs); font-weight: 700; text-transform: uppercase;
}
.badge-pass      { background: oklch(0.92 0.04 150); color: var(--color-pass); }
.badge-completed { background: oklch(0.92 0.04 150); color: var(--color-pass); }
.badge-fail      { background: oklch(0.92 0.06 25);  color: var(--color-fail); }
.badge-error     { background: oklch(0.92 0.06 25);  color: var(--color-fail); }
.badge-warn      { background: oklch(0.92 0.04 80);  color: var(--color-warn); }
.badge-skipped   { background: var(--bg-overlay);     color: var(--text-muted); }
@supports not (color: oklch(0 0 0)) {
  .badge-pass, .badge-completed { background: #e8f0e8; }
  .badge-fail, .badge-error     { background: #fce8e8; }
  .badge-warn                   { background: #fcf5e8; }
}
.cards {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 1rem; margin-bottom: 2rem;
}
.card {
  background: var(--bg-surface); border-radius: 0.5rem;
  padding: 1rem; text-align: center;
}
.card-value { font-size: var(--text-2xl); font-weight: 700; }
.card-label { font-size: var(--text-xs); color: var(--text-secondary); margin-top: 0.25rem; }
.card-critical .card-value { color: var(--color-critical); }
.card-high     .card-value { color: var(--color-high); }
.card-medium   .card-value { color: var(--color-medium); }
.card-low      .card-value { color: var(--color-low); }
.card-pass     .card-value { color: var(--color-pass); }
.card-fail     .card-value { color: var(--color-fail); }
.card-warn     .card-value { color: var(--color-warn); }
.card-total    .card-value { color: var(--text-primary); }
.section-title {
  font-size: var(--text-lg); font-weight: 700;
  margin-bottom: 1rem; margin-top: 2rem;
}
table {
  width: 100%; border-collapse: collapse; background: var(--bg-surface);
  border-radius: 0.5rem; overflow: hidden; font-size: var(--text-sm);
}
thead { background: var(--bg-overlay); }
th { padding: 0.75rem 1rem; font-weight: 600; text-align: left; }
td { padding: 0.5rem 1rem; }
tbody tr { border-top: 1px solid var(--border-subtle); }
tbody tr:hover { background: var(--bg-hover); }
.status-pass, .status-PASS { color: var(--color-pass); font-weight: 700; }
.status-fail, .status-FAIL { color: var(--color-fail); font-weight: 700; }
.status-warn, .status-WARN { color: var(--color-warn); font-weight: 700; }
.findings-list {
  font-size: var(--text-xs); color: var(--text-secondary);
  margin-top: 0.25rem; padding-left: 1rem;
}
.findings-list li { margin-bottom: 0.125rem; word-break: break-all; }
.kv-section { margin-bottom: 2rem; }
.kv-row {
  display: flex; padding: 0.5rem 0;
  border-bottom: 1px solid var(--border-subtle);
}
.kv-key {
  width: 200px; flex-shrink: 0; font-weight: 600;
  color: var(--text-secondary); font-size: var(--text-xs);
}
.kv-val { font-size: var(--text-sm); word-break: break-all; }
.qg-status {
  font-size: var(--text-2xl); font-weight: 700;
  text-align: center; padding: 1.5rem; border-radius: 0.5rem;
  margin-bottom: 2rem;
}
.qg-pass { background: oklch(0.92 0.04 150); color: var(--color-pass); }
.qg-fail { background: oklch(0.92 0.06 25);  color: var(--color-fail); }
@supports not (color: oklch(0 0 0)) {
  .qg-pass { background: #e8f0e8; }
  .qg-fail { background: #fce8e8; }
}
</style>`;

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

/**
 * Default status badge label map.
 * Keys are lowercase status strings; values are display labels.
 * Can be overridden via config.render.status_labels.
 */
const DEFAULT_STATUS_LABELS = {
  completed: 'Completed',
  pass:      'Pass',
  fail:      'Fail',
  error:     'Error',
  warn:      'Warn',
  skipped:   'Skipped',
};

/**
 * Default card map: maps summary keys → { cls, label }.
 * Can be overridden via config.render.card_map.
 */
const DEFAULT_CARD_MAP = {
  critical:          { cls: 'card-critical', label: 'Critical' },
  high:              { cls: 'card-high',     label: 'High' },
  medium:            { cls: 'card-medium',   label: 'Medium' },
  low:               { cls: 'card-low',      label: 'Low' },
  pass:              { cls: 'card-pass',     label: 'Pass' },
  fail:              { cls: 'card-fail',     label: 'Fail' },
  warn:              { cls: 'card-warn',     label: 'Warn' },
  total:             { cls: 'card-total',    label: 'Total' },
  total_findings:    { cls: 'card-total',    label: 'Total Findings' },
  total_components:  { cls: 'card-total',    label: 'Total Components' },
  errors:            { cls: 'card-warn',     label: 'Errors' },
  node_components:   { cls: 'card-total',    label: 'Node Components' },
  python_components: { cls: 'card-total',    label: 'Python Components' },
};

// Preferred card ordering (matches key order in DEFAULT_CARD_MAP)
const CARD_ORDER = [
  'critical', 'high', 'medium', 'low',
  'pass', 'fail', 'warn',
  'total', 'total_findings', 'total_components', 'errors',
  'node_components', 'python_components',
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function esc(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * Resolve effective render config from an optional config object.
 * Merges caller-provided overrides on top of defaults.
 *
 * @param {Object} [config] - Full config object (may include config.render)
 * @returns {{ locale: string, statusLabels: Object, cardMap: Object }}
 */
function resolveRenderConfig(config) {
  const renderCfg = (config && config.render) || {};
  const uiCfg = (config && config.ui) || {};

  const locale = renderCfg.locale || uiCfg.locale || 'en';

  const statusLabels = renderCfg.status_labels
    ? Object.assign({}, DEFAULT_STATUS_LABELS, renderCfg.status_labels)
    : DEFAULT_STATUS_LABELS;

  const cardMap = renderCfg.card_map
    ? Object.assign({}, DEFAULT_CARD_MAP, renderCfg.card_map)
    : DEFAULT_CARD_MAP;

  return { locale, statusLabels, cardMap };
}

function makeStatusBadge(statusLabels) {
  return function statusBadge(status) {
    const s = String(status || '').toLowerCase();
    const cls = s === 'completed' ? 'badge-completed'
      : s === 'pass'    ? 'badge-pass'
      : s === 'fail'    ? 'badge-fail'
      : s === 'error'   ? 'badge-error'
      : s === 'warn'    ? 'badge-warn'
      : s === 'skipped' ? 'badge-skipped'
      : 'badge-skipped';
    const label = statusLabels[s] !== undefined ? statusLabels[s] : status;
    return `<span class="badge ${cls}">${esc(label)}</span>`;
  };
}

function statusClass(status) {
  return `status-${esc(String(status || '').toLowerCase())}`;
}

// ---------------------------------------------------------------------------
// Section Renderers
// ---------------------------------------------------------------------------

function renderSummaryCards(summary, cardMap) {
  if (!summary || typeof summary !== 'object') return '';

  const effectiveCardMap = cardMap || DEFAULT_CARD_MAP;

  // Sort keys by preferred order, put unknowns at end
  const keys = Object.keys(summary)
    .filter(k => typeof summary[k] === 'number')
    .sort((a, b) => {
      const ia = CARD_ORDER.indexOf(a);
      const ib = CARD_ORDER.indexOf(b);
      return (ia === -1 ? 999 : ia) - (ib === -1 ? 999 : ib);
    });

  if (keys.length === 0) return '';

  const cards = keys.map(k => {
    const info = effectiveCardMap[k] || { cls: 'card-total', label: k };
    return `<div class="card ${info.cls}">
      <div class="card-value">${summary[k]}</div>
      <div class="card-label">${esc(info.label)}</div>
    </div>`;
  }).join('\n');

  return `<div class="cards">${cards}</div>`;
}

function renderChecksTable(checks) {
  if (!Array.isArray(checks) || checks.length === 0) return '';

  // Core columns always present
  const coreKeys = new Set(['name', 'status', 'detail', 'findings']);
  const hasFindings = checks.some(c => c.findings && c.findings.length > 0);

  // Dynamically detect extra columns (compliance frameworks, etc.)
  // by scanning all check objects for keys not in the core set.
  const extraCols = [];
  const seenExtra = new Set();
  for (const c of checks) {
    for (const key of Object.keys(c)) {
      if (!coreKeys.has(key) && !seenExtra.has(key) && typeof c[key] === 'string') {
        seenExtra.add(key);
        extraCols.push(key);
      }
    }
  }

  let head = '<th>Check</th><th>Status</th><th>Detail</th>';
  for (const col of extraCols) {
    head += `<th>${esc(col)}</th>`;
  }

  const rows = checks.map(c => {
    const sc = statusClass(c.status);
    let row = `<td>${esc(c.name)}</td>`;
    row += `<td class="${sc}">${esc(String(c.status || '').toUpperCase())}</td>`;
    row += `<td>${esc(c.detail || '')}`;
    if (hasFindings && c.findings && c.findings.length > 0) {
      row += `<ul class="findings-list">`;
      for (const f of c.findings) {
        row += `<li>${esc(f)}</li>`;
      }
      row += `</ul>`;
    }
    row += `</td>`;
    for (const col of extraCols) {
      row += `<td>${esc(c[col] || '')}</td>`;
    }
    return `<tr>${row}</tr>`;
  }).join('\n');

  return `<div class="section-title">Checks</div>
<table><thead><tr>${head}</tr></thead><tbody>${rows}</tbody></table>`;
}

function renderKeyValue(obj, excludeKeys) {
  const exclude = new Set(excludeKeys || []);
  const entries = Object.entries(obj).filter(([k]) => !exclude.has(k));
  if (entries.length === 0) return '';

  const rows = entries.map(([k, v]) => {
    let display;
    if (v === null || v === undefined) {
      display = '—';
    } else if (typeof v === 'object') {
      display = esc(JSON.stringify(v, null, 2));
    } else {
      display = esc(String(v));
    }
    return `<div class="kv-row"><div class="kv-key">${esc(k)}</div><div class="kv-val">${display}</div></div>`;
  }).join('\n');

  return `<div class="kv-section">${rows}</div>`;
}

function renderQualityGate(json) {
  const status = json.quality_gate || 'UNKNOWN';
  const cls = status === 'PASS' ? 'qg-pass' : 'qg-fail';
  return `<div class="qg-status ${cls}">${esc(status)}</div>`;
}

// ---------------------------------------------------------------------------
// Main renderer
// ---------------------------------------------------------------------------

/**
 * Render a scan/collected result JSON as a standalone HTML document.
 *
 * @param {Object} json         - Scan result object
 * @param {string} resultName   - e.g. "ai-safety-result"
 * @param {string} displayName  - e.g. "AI Safety"
 * @param {Object} [config]     - Optional config object. Supports:
 *   config.ui.locale               - HTML lang attribute (default: 'en')
 *   config.render.locale           - Overrides ui.locale for render
 *   config.render.status_labels    - Map of status key → display label
 *   config.render.card_map         - Map of summary key → { cls, label }
 * @returns {string} Complete HTML document string
 */
function renderScanHtml(json, resultName, displayName, config) {
  const { locale, statusLabels, cardMap } = resolveRenderConfig(config);
  const statusBadge = makeStatusBadge(statusLabels);
  const isQualityGate = resultName === 'quality-gate';

  // Header
  let html = `<!DOCTYPE html>
<html lang="${esc(locale)}">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(displayName)}</title>${CSS}</head>
<body>
<div class="header">
  <h1>${esc(displayName)} ${statusBadge(isQualityGate ? json.quality_gate : json.status)}</h1>
  <div class="meta">`;

  if (json.timestamp) html += `Timestamp: ${esc(json.timestamp)}`;
  if (json.tool)      html += ` | Tool: ${esc(json.tool)}`;
  if (json.target)    html += ` | Target: ${esc(json.target)}`;
  if (json.url)       html += ` | URL: ${esc(json.url)}`;

  html += `</div></div>`;

  // Quality gate special rendering
  if (isQualityGate) {
    html += renderQualityGate(json);
    html += renderSummaryCards({ critical: json.critical, high: json.high, fail: json.fail }, cardMap);
    html += `</body></html>`;
    return html;
  }

  // Skipped / error — show reason and stop
  if (json.status === 'skipped' || json.status === 'error') {
    if (json.reason) {
      html += `<div class="kv-section"><div class="kv-row"><div class="kv-key">Reason</div><div class="kv-val">${esc(json.reason)}</div></div></div>`;
    }
    html += `</body></html>`;
    return html;
  }

  // Summary cards
  html += renderSummaryCards(json.summary, cardMap);

  // Tools info (if present as object)
  if (json.tools && typeof json.tools === 'object') {
    html += `<div class="section-title">Tools</div>`;
    html += renderKeyValue(json.tools);
  }

  // Checks table
  html += renderChecksTable(json.checks);

  // Checkov sub-section
  if (json.checkov && typeof json.checkov === 'object') {
    html += `<div class="section-title">Checkov</div>`;
    html += renderSummaryCards(json.checkov, cardMap);
  }

  // AI-BOM sub-section
  if (json.ai_bom && typeof json.ai_bom === 'object') {
    const pkgCount = Array.isArray(json.ai_bom.packages) ? json.ai_bom.packages.length : 0;
    const cfgCount = Array.isArray(json.ai_bom.model_configs) ? json.ai_bom.model_configs.length : 0;
    html += `<div class="section-title">AI-BOM</div>`;
    html += renderSummaryCards({ packages: pkgCount, model_configs: cfgCount }, cardMap);
  }

  // Source delivery special fields
  if (json.summary && json.summary.sha256) {
    const s = json.summary;
    html += `<div class="section-title">Delivery Details</div>`;
    html += renderKeyValue({
      filename:     s.filename,
      version:      s.version,
      archive_size: s.archive_size ? `${(s.archive_size / 1024 / 1024).toFixed(2)} MB` : '—',
      sha256:       s.sha256,
      leaked_files: s.leaked_files,
    });
  }

  html += `</body></html>`;
  return html;
}

/**
 * Alias for renderScanHtml, matching the interface expected by build.js.
 *
 * @param {Object} json         - Collected/scan result object
 * @param {string} resultName   - e.g. "sast-result"
 * @param {string} displayName  - e.g. "SAST Scan"
 * @param {Object} [config]     - Optional config (same as renderScanHtml)
 * @returns {string} Complete HTML document string
 */
function renderCollectedHtml(json, resultName, displayName, config) {
  return renderScanHtml(json, resultName, displayName, config);
}

module.exports = { renderScanHtml, renderCollectedHtml };
