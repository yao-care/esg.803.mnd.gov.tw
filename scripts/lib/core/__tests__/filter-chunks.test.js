'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert');
const { chunkMarkdown } = require('../chunk');

describe('chunk group extraction', () => {
  it('extracts group from frontmatter type field', () => {
    const md = `---\ndocument_id: POL-001\ntitle_zh: Test\ntype: POL\n---\n# Content`;
    const chunks = chunkMarkdown(md, 'POL-001');
    assert.strictEqual(chunks[0].group, 'POL');
  });

  it('falls back to frontmatter group field', () => {
    const md = `---\ndocument_id: DOC-001\ntitle_zh: Test\ngroup: CUSTOM\n---\n# Content`;
    const chunks = chunkMarkdown(md, 'DOC-001');
    assert.strictEqual(chunks[0].group, 'CUSTOM');
  });

  it('falls back to document_id prefix', () => {
    const md = `---\ndocument_id: FRM-001\ntitle_zh: Test\n---\n# Content`;
    const chunks = chunkMarkdown(md, 'FRM-001');
    assert.strictEqual(chunks[0].group, 'FRM');
  });

  it('returns empty string when no group info', () => {
    const md = `---\ntitle_zh: Test\n---\n# Content`;
    const chunks = chunkMarkdown(md, 'test');
    assert.strictEqual(chunks[0].group, '');
  });

  it('type takes priority over group', () => {
    const md = `---\ndocument_id: X-001\ntitle_zh: Test\ntype: WKI\ngroup: OTHER\n---\n# Content`;
    const chunks = chunkMarkdown(md, 'X-001');
    assert.strictEqual(chunks[0].group, 'WKI');
  });
});

describe('filterChunks', () => {
  const { filterChunks } = require('../build');

  const chunks = [
    { group: 'POL', doc_key: 'POL-001' },
    { group: 'WKI', doc_key: 'WKI-001' },
    { group: 'FRM', doc_key: 'FRM-001' },
    { group: '', doc_key: 'misc' },
  ];

  it('returns all chunks when excludeTypes is empty', () => {
    assert.strictEqual(filterChunks(chunks, []).length, 4);
  });

  it('excludes specified types', () => {
    const result = filterChunks(chunks, ['WKI']);
    assert.strictEqual(result.length, 3);
    assert.ok(!result.some(c => c.group === 'WKI'));
  });

  it('excludes multiple types', () => {
    const result = filterChunks(chunks, ['WKI', 'FRM']);
    assert.strictEqual(result.length, 2);
  });

  it('returns all when excludeTypes is null', () => {
    assert.strictEqual(filterChunks(chunks, null).length, 4);
  });
});
