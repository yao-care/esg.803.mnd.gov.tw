'use strict';

const fs = require('node:fs');
const path = require('node:path');

function escapeHtml(str) {
  if (str === null || str === undefined) return '';
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function generateFieldHtml(field) {
  const id = `field-${field.name}`;
  const req = field.required ? ' required' : '';
  const label = `<label for="${id}">${escapeHtml(field.name)}${field.required ? ' *' : ''}</label>`;

  switch (field.type) {
    case 'text':
    case 'email':
    case 'date':
    case 'number':
      return `<div class="form-field">${label}<input type="${field.type}" id="${id}" name="${escapeHtml(field.name)}"${req} onchange="autoSave()"></div>`;

    case 'datetime':
      return `<div class="form-field">${label}<input type="datetime-local" id="${id}" name="${escapeHtml(field.name)}"${req} onchange="autoSave()"></div>`;

    case 'textarea':
      return `<div class="form-field">${label}<textarea id="${id}" name="${escapeHtml(field.name)}" rows="4"${req} onchange="autoSave()"></textarea></div>`;

    case 'select': {
      const options = (field.options || [])
        .map(o => `<option value="${escapeHtml(o)}">${escapeHtml(o)}</option>`)
        .join('');
      return `<div class="form-field">${label}<select id="${id}" name="${escapeHtml(field.name)}"${req} onchange="autoSave()"><option value="">-- 請選擇 --</option>${options}</select></div>`;
    }

    case 'multiselect': {
      const checkboxes = (field.options || [])
        .map(o => `<label class="checkbox-label"><input type="checkbox" name="${escapeHtml(field.name)}" value="${escapeHtml(o)}" onchange="autoSave()"> ${escapeHtml(o)}</label>`)
        .join('');
      return `<div class="form-field">${label}<div class="checkbox-group">${checkboxes}</div></div>`;
    }

    default:
      return `<div class="form-field">${label}<input type="text" id="${id}" name="${escapeHtml(field.name)}" onchange="autoSave()"></div>`;
  }
}

function generateFormHtml(fields) {
  return `<form id="record-form">\n${fields.map(generateFieldHtml).join('\n')}\n</form>`;
}

function generateRecordsTable(records) {
  if (!records || records.length === 0) return '';

  const sorted = [...records].sort((a, b) =>
    (b.submitted_at || '').localeCompare(a.submitted_at || '')
  );

  const visibleCount = 20;
  const rows = sorted.map((r, i) => {
    const hidden = i >= visibleCount ? ' class="record-hidden" style="display:none"' : '';
    const date = r.submitted_at ? r.submitted_at.slice(0, 16).replace('T', ' ') : '';
    return `<tr${hidden}>
      <td><a href="../records/${escapeHtml(r.record_id)}/">${escapeHtml(r.record_id)}</a></td>
      <td>${escapeHtml(r.submitted_by?.name || '')}</td>
      <td>${escapeHtml(date)}</td>
      <td>${escapeHtml(r.status || '')}</td>
    </tr>`;
  }).join('\n');

  const showAllBtn = sorted.length > visibleCount
    ? `<button class="no-print" onclick="document.querySelectorAll('.record-hidden').forEach(r=>r.style.display='');this.style.display='none'">顯示全部 (${sorted.length} 筆)</button>`
    : '';

  return `<section id="records">
  <h2>歷次填報紀錄</h2>
  <table>
    <thead><tr><th>紀錄編號</th><th>提交者</th><th>提交時間</th><th>狀態</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>
  ${showAllBtn}
</section>`;
}

function generateSubmitJs() {
  return `
<script>
const FORM_CONFIG = window.__FORM_CONFIG__ || {};

function autoSave() {
  if (!FORM_CONFIG.document_id) return;
  const form = document.getElementById('record-form');
  if (!form) return;
  const data = {};
  for (const el of form.elements) {
    if (!el.name) continue;
    if (el.type === 'checkbox') {
      if (!data[el.name]) data[el.name] = [];
      if (el.checked) data[el.name].push(el.value);
    } else {
      data[el.name] = el.value;
    }
  }
  localStorage.setItem('akora-draft-' + FORM_CONFIG.document_id, JSON.stringify(data));
}

function restoreForm() {
  if (!FORM_CONFIG.document_id) return;
  const saved = localStorage.getItem('akora-draft-' + FORM_CONFIG.document_id);
  if (!saved) return;
  try {
    const data = JSON.parse(saved);
    const form = document.getElementById('record-form');
    if (!form) return;
    for (const [name, value] of Object.entries(data)) {
      if (Array.isArray(value)) {
        for (const cb of form.querySelectorAll('input[name="' + name + '"]')) {
          cb.checked = value.includes(cb.value);
        }
      } else {
        const el = form.querySelector('[name="' + name + '"]');
        if (el) el.value = value;
      }
    }
  } catch {}
}

async function submitForm() {
  if (!FORM_CONFIG.api_endpoint) {
    alert('API 尚未設定');
    return;
  }
  const form = document.getElementById('record-form');
  if (!form.checkValidity()) { form.reportValidity(); return; }

  const fields = {};
  for (const el of form.elements) {
    if (!el.name) continue;
    if (el.type === 'checkbox') {
      if (!fields[el.name]) fields[el.name] = [];
      if (el.checked) fields[el.name].push(el.value);
    } else {
      fields[el.name] = el.value;
    }
  }

  const idempotencyKey = localStorage.getItem('akora-idem-' + FORM_CONFIG.document_id)
    || crypto.randomUUID();
  localStorage.setItem('akora-idem-' + FORM_CONFIG.document_id, idempotencyKey);

  const submitBtn = document.getElementById('btn-submit');
  submitBtn.disabled = true;
  submitBtn.textContent = '提交中...';

  try {
    if (!navigator.onLine) { alert('需要網路連線才能提交，資料已暫存'); return; }
    const resp = await fetch(FORM_CONFIG.api_endpoint + '/submit', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': FORM_CONFIG.api_key || '',
        'X-Idempotency-Key': idempotencyKey,
      },
      body: JSON.stringify({
        document_id: FORM_CONFIG.document_id,
        submitted_by: {
          name: fields[FORM_CONFIG.submitter_field || '通報人'] || '',
          title: fields[FORM_CONFIG.submitter_title_field || ''] || '',
        },
        fields,
      }),
    });
    const result = await resp.json();
    if (resp.ok) {
      alert('提交成功！紀錄編號: ' + result.record_id);
      localStorage.removeItem('akora-draft-' + FORM_CONFIG.document_id);
      localStorage.removeItem('akora-idem-' + FORM_CONFIG.document_id);
    } else {
      alert('提交失敗: ' + (result.error || resp.status) + '\\n' + (result.details || []).join('\\n'));
    }
  } catch (err) {
    alert('提交失敗: ' + err.message + '\\n資料已暫存，請重試');
  } finally {
    submitBtn.disabled = false;
    submitBtn.textContent = '提交';
  }
}

document.addEventListener('DOMContentLoaded', restoreForm);
</script>`;
}

function parseYamlSimple(yamlContent) {
  const { execSync } = require('node:child_process');
  const os = require('node:os');
  const tmpFile = path.join(os.tmpdir(), `akora-form-yaml-parse-${process.pid}.py`);
  const py = [
    'import sys, json, yaml',
    'data = yaml.safe_load(sys.stdin.read())',
    "print(json.dumps({",
    "  'document_id': data.get('document_id', ''),",
    "  'fields': data.get('fields', []),",
    "  'approval_required': data.get('approval_required', False),",
    "  'retention_period_days': data.get('retention_period_days', None),",
    '}))',
  ].join('\n');
  fs.writeFileSync(tmpFile, py);
  try {
    const result = execSync(`python3 ${tmpFile}`, {
      input: yamlContent,
      encoding: 'utf8',
    });
    return JSON.parse(result);
  } finally {
    try { fs.unlinkSync(tmpFile); } catch (_) {}
  }
}

function postProcessForms(outputDir, knowledgeBaseDir, config, metadataFilename = 'merge.yaml') {
  const formsDir = path.join(outputDir, 'forms');
  if (!fs.existsSync(formsDir)) return 0;

  const reportedPath = config.data_sources?.tables?.reported?.path || 'data/reported';
  const reportedDir = path.join(knowledgeBaseDir, reportedPath);

  // Load all records for the records table
  let allRecords = [];
  if (fs.existsSync(reportedDir)) {
    allRecords = fs.readdirSync(reportedDir)
      .filter(f => f.endsWith('.json'))
      .map(f => {
        try { return JSON.parse(fs.readFileSync(path.join(reportedDir, f), 'utf8')); }
        catch { return null; }
      })
      .filter(r => r && r.record_id && r.fields);
  }

  const formFolders = fs.readdirSync(formsDir, { withFileTypes: true })
    .filter(d => d.isDirectory());

  let processed = 0;
  const knowledgeDir = path.join(knowledgeBaseDir, config.data_sources?.documents?.path || 'knowledge');

  for (const folder of formFolders) {
    const htmlPath = path.join(formsDir, folder.name, 'index.html');
    if (!fs.existsSync(htmlPath)) continue;

    // Find merge.yaml for this form folder
    const yamlPath = path.join(knowledgeDir, folder.name, metadataFilename);
    if (!fs.existsSync(yamlPath)) continue;

    const parsed = parseYamlSimple(fs.readFileSync(yamlPath, 'utf8'));
    if (!parsed.fields || parsed.fields.length === 0) continue;

    let html = fs.readFileSync(htmlPath, 'utf8');

    // 1. Generate form HTML and replace placeholder
    const formHtml = generateFormHtml(parsed.fields);
    html = html.replace('<!-- FILL_MODE_PLACEHOLDER -->', formHtml);

    // 2. Generate records table and replace placeholder
    const docRecords = allRecords.filter(r => r.document_id === parsed.document_id);
    const recordsHtml = generateRecordsTable(docRecords);
    html = html.replace('<!-- RECORDS_PLACEHOLDER -->', recordsHtml);

    // 3. Inject config and JS
    const formConfig = {
      api_endpoint: config.form_submission?.api_endpoint || '',
      document_id: parsed.document_id,
    };
    const configJs = `<script>window.__FORM_CONFIG__ = ${JSON.stringify(formConfig)};</script>`;
    html = html.replace('<!-- FORM_CONFIG_PLACEHOLDER -->', configJs + generateSubmitJs());

    fs.writeFileSync(htmlPath, html);
    processed++;
  }

  return processed;
}

module.exports = { postProcessForms, generateFormHtml, generateRecordsTable, generateFieldHtml, generateSubmitJs };
