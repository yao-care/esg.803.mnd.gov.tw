'use strict';

/**
 * render.js — Collected Result HTML Renderer (stub)
 *
 * Minimal stub providing renderCollectedHtml for use by build.js.
 * The full implementation will be extracted in Task 6.
 */

/**
 * Render a collected result JSON as a standalone HTML document.
 *
 * @param {Object} json - Collected result object
 * @param {string} resultName - e.g. "vulnerability-result"
 * @param {string} displayName - e.g. "Vulnerability Scan"
 * @returns {string} Complete HTML document string
 */
function renderCollectedHtml(json, resultName, displayName) {
  const status = json.status || json.quality_gate || 'unknown';
  return `<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>${escapeHtml(displayName)}</title></head>
<body>
<h1>${escapeHtml(displayName)}</h1>
<p>Status: ${escapeHtml(String(status))}</p>
<pre>${escapeHtml(JSON.stringify(json, null, 2))}</pre>
</body></html>`;
}

function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

module.exports = { renderCollectedHtml };
