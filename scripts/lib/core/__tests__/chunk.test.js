'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert');

const { parseYamlFrontmatter, stripFrontmatter, splitByH2, chunkMarkdown, chunkCollectedResult } = require('../chunk.js');

describe('chunk.js', () => {
  describe('parseYamlFrontmatter', () => {
    it('extracts YAML frontmatter from markdown', () => {
      const md = '---\ntitle: Test Doc\nversion: "1.0"\n---\n# Content';
      const meta = parseYamlFrontmatter(md);
      assert.strictEqual(meta.title, 'Test Doc');
      assert.strictEqual(meta.version, '1.0');
    });
  });

  describe('chunkMarkdown', () => {
    it('produces chunks with source_type "document"', () => {
      const md = '---\ntitle: Test\ndoc_id: DOC-01\n---\n## Section A\nContent A\n## Section B\nContent B';
      const chunks = chunkMarkdown(md, 'DOC-01', {});
      assert.ok(chunks.length >= 2);
      assert.strictEqual(chunks[0].source_type, 'document');
      assert.ok(chunks[0].chunk_id.startsWith('DOC-01#'));
    });
  });

  describe('chunkCollectedResult', () => {
    const json = {
      findings: [
        { id: 'F1', severity: 'high', description: 'Test finding' }
      ]
    };

    it('produces chunks with source_type "collected"', () => {
      const chunks = chunkCollectedResult(json, 'vulnerability', {});
      assert.ok(chunks.length >= 1);
      assert.strictEqual(chunks[0].source_type, 'collected');
    });

    it('has default group "collected"', () => {
      const chunks = chunkCollectedResult(json, 'vulnerability', {});
      assert.strictEqual(chunks[0].group, 'collected');
    });

    it('accepts custom group from config', () => {
      const chunks = chunkCollectedResult(json, 'vulnerability', { group: 'SCAN' });
      assert.strictEqual(chunks[0].group, 'SCAN');
    });
  });
});
