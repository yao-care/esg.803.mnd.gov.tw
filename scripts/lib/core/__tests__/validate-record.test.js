// scripts/lib/core/__tests__/validate-record.test.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const { validateRecord, validateRecordFile } = require('../validate-record');

const FIXTURES = path.resolve(__dirname, '..', '..', '..', '..', 'tests', 'fixtures');

describe('validate-record', () => {
  const schemasDir = path.join(FIXTURES, '..', 'tmp-schemas');

  // Generate schemas first (depends on Task 2)
  const { generateAllSchemas } = require('../generate-schemas');
  generateAllSchemas(path.join(FIXTURES, 'knowledge'), schemasDir);

  it('validates a correct record', () => {
    const record = JSON.parse(
      require('node:fs').readFileSync(
        path.join(FIXTURES, 'reported', 'FRM-TEST-20260315-143022-a7f3.json'), 'utf8'
      )
    );
    const result = validateRecord(record, schemasDir);
    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.errors.length, 0);
  });

  it('rejects missing required field', () => {
    const record = {
      record_id: 'FRM-TEST-20260315-143022-b8c4',
      document_id: 'FRM-TEST',
      submitted_at: '2026-03-15T14:30:22+08:00',
      submitted_by: { name: 'Test', source: 'ci' },
      status: 'submitted',
      fields: { '類別': '類別A' }, // missing 說明, 日期, 通報人
      audit_trail: [],
    };
    const result = validateRecord(record, schemasDir);
    assert.strictEqual(result.valid, false);
    assert.ok(result.errors.some(e => e.includes('說明')));
  });

  it('rejects select value not in options', () => {
    const record = {
      record_id: 'FRM-TEST-20260315-143022-c9d5',
      document_id: 'FRM-TEST',
      submitted_at: '2026-03-15T14:30:22+08:00',
      submitted_by: { name: 'Test', source: 'ci' },
      status: 'submitted',
      fields: {
        '類別': '不存在的類別',
        '說明': 'test',
        '日期': '2026-03-15',
        '通報人': 'Test',
      },
      audit_trail: [],
    };
    const result = validateRecord(record, schemasDir);
    assert.strictEqual(result.valid, false);
    assert.ok(result.errors.some(e => e.includes('類別')));
  });

  it('rejects invalid record_id format', () => {
    const record = {
      record_id: 'BAD-FORMAT',
      document_id: 'FRM-TEST',
      submitted_at: '2026-03-15T14:30:22+08:00',
      submitted_by: { name: 'Test', source: 'ci' },
      status: 'submitted',
      fields: { '類別': '類別A', '說明': 'x', '日期': '2026-03-15', '通報人': 'T' },
      audit_trail: [],
    };
    const result = validateRecord(record, schemasDir);
    assert.strictEqual(result.valid, false);
    assert.ok(result.errors.some(e => e.includes('record_id')));
  });

  it('validates record from file path', () => {
    const filePath = path.join(FIXTURES, 'reported', 'FRM-TEST-20260315-143022-a7f3.json');
    const result = validateRecordFile(filePath, schemasDir);
    assert.strictEqual(result.valid, true);
  });
});
