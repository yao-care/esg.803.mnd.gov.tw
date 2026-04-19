'use strict';

const fs = require('node:fs');
const path = require('node:path');

const TEMPLATE_PATH = path.resolve(__dirname, '..', '..', '..', 'templates', 'record.html');

function loadTemplate() {
  return fs.readFileSync(TEMPLATE_PATH, 'utf8');
}

function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function renderFieldValue(value) {
  if (Array.isArray(value)) return escapeHtml(value.join(', '));
  return escapeHtml(value);
}

function renderFieldsRows(fields) {
  return Object.entries(fields)
    .map(([key, val]) => `<tr><th>${escapeHtml(key)}</th><td>${renderFieldValue(val)}</td></tr>`)
    .join('\n');
}

function renderAuditTrail(trail) {
  if (!trail || trail.length === 0) return '<p>無審計記錄</p>';
  return trail.map(entry =>
    `<div class="audit-entry">
      <strong>${escapeHtml(entry.action)}</strong> — ${escapeHtml(entry.by || '')}
      <br><small>${escapeHtml(entry.at || '')} via ${escapeHtml(entry.source || '')}</small>
      ${entry.pr ? `<br><small>PR: ${escapeHtml(entry.pr)}</small>` : ''}
    </div>`
  ).join('\n');
}

function loadOklchStyles() {
  const stylesPath = path.resolve(__dirname, '..', '..', '..', 'templates', 'styles.css');
  if (fs.existsSync(stylesPath)) return fs.readFileSync(stylesPath, 'utf8');
  return '';
}

function renderRecordHtml(record, meta) {
  let template = loadTemplate();
  const oklch = loadOklchStyles();

  const replacements = {
    '{{OKLCH_STYLES}}': oklch,
    '{{RECORD_ID}}': escapeHtml(record.record_id),
    '{{FORM_TITLE}}': escapeHtml(meta.title_zh || record.document_id),
    '{{STATUS}}': escapeHtml(record.status || 'submitted'),
    '{{SUBMITTER_NAME}}': escapeHtml(record.submitted_by?.name || ''),
    '{{SUBMITTER_TITLE}}': escapeHtml(record.submitted_by?.title || ''),
    '{{SUBMITTED_AT}}': escapeHtml(record.submitted_at || ''),
    '{{SOURCE}}': escapeHtml(record.submitted_by?.source || ''),
    '{{CLASSIFICATION}}': escapeHtml(record.classification || ''),
    '{{RETAINED_UNTIL}}': escapeHtml(record.retained_until || '不限期'),
    '{{FIELDS_ROWS}}': renderFieldsRows(record.fields || {}),
    '{{AUDIT_TRAIL_HTML}}': renderAuditTrail(record.audit_trail),
    '{{BACK_LINK}}': `../../forms/`,
  };

  for (const [token, value] of Object.entries(replacements)) {
    template = template.split(token).join(value);
  }

  return template;
}

function loadMeta(knowledgeDir, documentId, metadataFilename = 'merge.yaml') {
  const folders = fs.readdirSync(knowledgeDir, { withFileTypes: true })
    .filter(d => d.isDirectory());

  for (const folder of folders) {
    const yamlPath = path.join(knowledgeDir, folder.name, metadataFilename);
    if (!fs.existsSync(yamlPath)) continue;
    const content = fs.readFileSync(yamlPath, 'utf8');
    const idMatch = content.match(/^document_id:\s*(.+)$/m);
    const titleMatch = content.match(/^title_zh:\s*(.+)$/m);
    if (idMatch && idMatch[1].trim() === documentId) {
      return {
        document_id: documentId,
        title_zh: titleMatch ? titleMatch[1].trim() : documentId,
        folder: folder.name,
      };
    }
  }
  return { document_id: documentId, title_zh: documentId, folder: '' };
}

function renderRecords(reportedDir, outputDir, knowledgeDir, metadataFilename = 'merge.yaml') {
  if (!fs.existsSync(reportedDir)) return 0;

  const files = fs.readdirSync(reportedDir).filter(f => f.endsWith('.json'));
  const recordsDir = path.join(outputDir, 'records');
  let count = 0;

  for (const file of files) {
    const filePath = path.join(reportedDir, file);
    let record;
    try {
      record = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch { continue; }

    // Only process form records (have record_id + fields)
    if (!record.record_id || !record.fields) continue;

    const meta = loadMeta(knowledgeDir, record.document_id, metadataFilename);
    const html = renderRecordHtml(record, meta);

    const dir = path.join(recordsDir, record.record_id);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'index.html'), html);
    count++;
  }

  return count;
}

module.exports = { renderRecordHtml, renderRecords, renderFieldsRows, renderAuditTrail };
