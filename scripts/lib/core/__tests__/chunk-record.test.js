// scripts/lib/core/__tests__/chunk-record.test.js
const { describe, it } = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const fs = require('node:fs');

const { chunkReportedRecord } = require('../chunk');

const FIXTURES = path.resolve(__dirname, '..', '..', '..', '..', 'tests', 'fixtures');

describe('chunkReportedRecord', () => {
  const record = JSON.parse(
    fs.readFileSync(path.join(FIXTURES, 'reported', 'FRM-TEST-20260315-143022-a7f3.json'), 'utf8')
  );
  const meta = { title_zh: '測試表單', document_id: 'FRM-TEST' };

  it('returns a single chunk', () => {
    const chunks = chunkReportedRecord(record, meta);
    assert.strictEqual(chunks.length, 1);
  });

  it('chunk has correct identifiers', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    assert.strictEqual(chunk.chunk_id, 'reported/FRM-TEST-20260315-143022-a7f3');
    assert.strictEqual(chunk.doc_key, 'reported/FRM-TEST-20260315-143022-a7f3');
    assert.strictEqual(chunk.doc_id, 'FRM-TEST');
    assert.strictEqual(chunk.source_type, 'reported');
  });

  it('chunk text contains field values', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    assert.ok(chunk.text.includes('類別: 類別A'));
    assert.ok(chunk.text.includes('說明: 這是一筆測試紀錄'));
    assert.ok(chunk.text.includes('通報人: 測試員'));
  });

  it('chunk text contains metadata', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    assert.ok(chunk.text.includes('測試表單'));
    assert.ok(chunk.text.includes('2026-03-15'));
    assert.ok(chunk.text.includes('測試員'));
  });

  it('chunk title is the form title', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    assert.strictEqual(chunk.title, '測試表單');
  });

  it('chunk has group extracted from document_id prefix', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    assert.strictEqual(chunk.group, 'FRM');
  });

  it('chunk group falls back to "reported" when no prefix', () => {
    const noPrefixRecord = { ...record, document_id: 'noprefixid' };
    const [chunk] = chunkReportedRecord(noPrefixRecord, { title_zh: 'test', document_id: 'noprefixid' });
    assert.strictEqual(chunk.group, 'reported');
  });

  it('annotates array fields with [多選] type hint (#14)', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    assert.ok(chunk.text.includes('影響範圍 [多選]: 範圍一, 範圍二'), 'Array fields should have [多選] annotation');
  });

  it('annotates date fields with [日期] type hint (#14)', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    assert.ok(chunk.text.includes('日期 [日期]: 2026-03-15'), 'Date fields should have [日期] annotation');
  });

  it('annotates number fields with [數值] type hint (#14)', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    assert.ok(chunk.text.includes('數量 [數值]: 5'), 'Number fields should have [數值] annotation');
  });

  it('plain text fields have no type annotation (#14)', () => {
    const [chunk] = chunkReportedRecord(record, meta);
    // "說明" is plain text, should NOT have a type hint bracket
    assert.ok(chunk.text.includes('說明: 這是一筆測試紀錄'), 'Plain text fields should have no type annotation');
    // "通報人" is plain text
    assert.ok(chunk.text.includes('通報人: 測試員'), 'Plain text fields should have no type annotation');
  });
});
