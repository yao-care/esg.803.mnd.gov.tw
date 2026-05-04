// scripts/lib/core/__tests__/record-renderer.test.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const fs = require('node:fs');

const { renderRecordHtml, renderRecords } = require('../record-renderer');

const FIXTURES = path.resolve(__dirname, '..', '..', '..', '..', 'tests', 'fixtures');
const TMP_OUTPUT = path.resolve(FIXTURES, '..', 'tmp-records-output');

describe('record-renderer', () => {
  const record = JSON.parse(
    fs.readFileSync(path.join(FIXTURES, 'reported', 'FRM-TEST-20260315-143022-a7f3.json'), 'utf8')
  );
  const meta = { title_zh: '測試表單', document_id: 'FRM-TEST' };

  describe('renderRecordHtml', () => {
    it('renders record to HTML string', () => {
      const html = renderRecordHtml(record, meta);
      assert.ok(html.includes('FRM-TEST-20260315-143022-a7f3'));
      assert.ok(html.includes('測試表單'));
      assert.ok(html.includes('測試員'));
      assert.ok(html.includes('類別A'));
    });

    it('renders status badge', () => {
      const html = renderRecordHtml(record, meta);
      assert.ok(html.includes('badge-submitted'));
    });

    it('renders audit trail', () => {
      const html = renderRecordHtml(record, meta);
      assert.ok(html.includes('submitted'));
      assert.ok(html.includes('2026-03-15'));
    });

    it('renders array field values joined', () => {
      const html = renderRecordHtml(record, meta);
      assert.ok(html.includes('範圍一'));
      assert.ok(html.includes('範圍二'));
    });
  });

  describe('renderRecords', () => {
    it('writes record HTML files to output directory', () => {
      fs.rmSync(TMP_OUTPUT, { recursive: true, force: true });
      fs.mkdirSync(TMP_OUTPUT, { recursive: true });

      const knowledgeDir = path.join(FIXTURES, 'knowledge');
      const reportedDir = path.join(FIXTURES, 'reported');
      const count = renderRecords(reportedDir, TMP_OUTPUT, knowledgeDir);

      assert.strictEqual(count, 1);
      const recordDir = path.join(TMP_OUTPUT, 'records', 'FRM-TEST-20260315-143022-a7f3');
      assert.ok(fs.existsSync(path.join(recordDir, 'index.html')));

      fs.rmSync(TMP_OUTPUT, { recursive: true, force: true });
    });
  });
});
