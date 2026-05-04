// scripts/lib/core/__tests__/form-processor.test.js
const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const fs = require('node:fs');

const { postProcessForms, generateFormHtml, generateRecordsTable } = require('../form-processor');

const FIXTURES = path.resolve(__dirname, '..', '..', '..', '..', 'tests', 'fixtures');

describe('form-processor', () => {
  describe('generateFormHtml', () => {
    const fields = [
      { name: '類別', type: 'select', required: true, options: ['A', 'B'] },
      { name: '說明', type: 'textarea', required: true },
      { name: '範圍', type: 'multiselect', options: ['X', 'Y', 'Z'] },
      { name: '日期', type: 'date', required: true },
      { name: '數量', type: 'number' },
      { name: '信箱', type: 'email' },
      { name: '姓名', type: 'text', required: true },
    ];

    it('generates select element for select type', () => {
      const html = generateFormHtml(fields);
      assert.ok(html.includes('<select'));
      assert.ok(html.includes('<option value="A">A</option>'));
    });

    it('generates textarea for textarea type', () => {
      const html = generateFormHtml(fields);
      assert.ok(html.includes('<textarea'));
    });

    it('generates checkbox group for multiselect', () => {
      const html = generateFormHtml(fields);
      assert.ok(html.includes('type="checkbox"'));
      assert.ok(html.includes('value="X"'));
    });

    it('marks required fields', () => {
      const html = generateFormHtml(fields);
      assert.ok(html.includes('required'));
    });

    it('generates date input for date type', () => {
      const html = generateFormHtml(fields);
      assert.ok(html.includes('type="date"'));
    });

    it('generates number input for number type', () => {
      const html = generateFormHtml(fields);
      assert.ok(html.includes('type="number"'));
    });
  });

  describe('generateRecordsTable', () => {
    it('generates table from records', () => {
      const records = [
        {
          record_id: 'FRM-TEST-20260315-143022-a7f3',
          submitted_by: { name: '測試員' },
          submitted_at: '2026-03-15T14:30:22+08:00',
          status: 'submitted',
        },
      ];
      const html = generateRecordsTable(records);
      assert.ok(html.includes('FRM-TEST-20260315-143022-a7f3'));
      assert.ok(html.includes('測試員'));
      assert.ok(html.includes('歷次填報紀錄'));
    });

    it('returns empty string for no records', () => {
      const html = generateRecordsTable([]);
      assert.strictEqual(html, '');
    });
  });

  describe('postProcessForms', () => {
    const tmpOutput = path.resolve(FIXTURES, '..', 'tmp-form-output');
    const formsDir = path.join(tmpOutput, 'forms', 'FRM-TEST');

    before(() => {
      // Simulate merge.sh output: create a form HTML with placeholders
      fs.mkdirSync(formsDir, { recursive: true });
      fs.writeFileSync(path.join(formsDir, 'index.html'), `
<!DOCTYPE html><html><body>
<div id="view-mode">Static content</div>
<div id="fill-mode" style="display:none"><!-- FILL_MODE_PLACEHOLDER --></div>
<!-- RECORDS_PLACEHOLDER -->
<!-- FORM_CONFIG_PLACEHOLDER -->
</body></html>`);
    });

    after(() => {
      fs.rmSync(tmpOutput, { recursive: true, force: true });
    });

    it('replaces FILL_MODE_PLACEHOLDER with form HTML', () => {
      const config = { form_submission: { api_endpoint: 'https://test.example.com' } };
      postProcessForms(tmpOutput, FIXTURES, config);
      const html = fs.readFileSync(path.join(formsDir, 'index.html'), 'utf8');
      assert.ok(!html.includes('<!-- FILL_MODE_PLACEHOLDER -->'));
      assert.ok(html.includes('<form'));
      assert.ok(html.includes('<select')); // from FRM-TEST fields
    });

    it('injects FORM_CONFIG', () => {
      const html = fs.readFileSync(path.join(formsDir, 'index.html'), 'utf8');
      assert.ok(html.includes('FORM_CONFIG'));
      assert.ok(html.includes('https://test.example.com'));
    });
  });
});
