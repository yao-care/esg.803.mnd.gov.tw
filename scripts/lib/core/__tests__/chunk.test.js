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

    it('respects custom chunk_threshold', () => {
      // Create a section with 500 chars + H3 subsections
      const longContent = 'x'.repeat(500);
      const md = `---\ntitle: Test\n---\n## Big Section\n${longContent}\n### Sub A\nSub content A\n### Sub B\nSub content B`;
      // Default threshold 2000: section < 2000 → no H3 split → 1 chunk
      const defaultChunks = chunkMarkdown(md, 'test', {});
      assert.strictEqual(defaultChunks.length, 1);
      // Low threshold 100: section > 100 → split by H3 → multiple chunks
      const customChunks = chunkMarkdown(md, 'test', { chunk_threshold: 100 });
      assert.ok(customChunks.length > 1);
    });

    it('splits oversized chunks at paragraph boundaries (#12)', () => {
      // Build a section with no H3 headings but multiple paragraphs, each ~60 chars
      const para = 'Lorem ipsum dolor sit amet, paragraph content here abcdef.';
      // 5 paragraphs joined by double newline (~300 chars total)
      const content = [para, para, para, para, para].join('\n\n');
      const md = `---\ntitle: Test\n---\n## Big Section\n${content}`;
      // threshold 120: section > 120, no H3 → paragraph split kicks in
      const chunks = chunkMarkdown(md, 'test', { chunk_threshold: 120, chunk_overlap: 0 });
      assert.ok(chunks.length > 1, `Expected >1 chunks, got ${chunks.length}`);
      // Each chunk's text should contain paragraph content
      for (const c of chunks) {
        assert.ok(c.text.includes('Lorem ipsum'), 'Each chunk should have paragraph content');
      }
      // Continuation chunks should have "(cont.)" in section name
      const contChunks = chunks.filter(c => c.section.includes('(cont.)'));
      assert.ok(contChunks.length > 0, 'Should have continuation chunks');
    });

    it('does not split when content is under threshold (#12)', () => {
      const md = '---\ntitle: Test\n---\n## Section\nShort content.';
      const chunks = chunkMarkdown(md, 'test', { chunk_threshold: 2000, chunk_overlap: 0 });
      assert.strictEqual(chunks.length, 1);
      assert.ok(!chunks[0].section.includes('(cont.)'));
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
