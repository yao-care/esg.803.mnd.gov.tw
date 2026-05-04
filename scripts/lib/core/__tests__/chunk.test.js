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

    it('adds overlap from previous chunk (#13)', () => {
      // Need enough content so the first chunk's text > overlapSize
      const longContent = 'This is a detailed paragraph about section A. '.repeat(10);
      const md = `---\ntitle: Test\n---\n## Section A\n${longContent}\n## Section B\nContent of section B is here.`;
      const chunks = chunkMarkdown(md, 'test', { chunk_overlap: 50 });
      assert.ok(chunks.length >= 2);
      // Second chunk should start with [...] overlap prefix
      assert.ok(chunks[1].text.startsWith('[...]'), 'Second chunk should have overlap prefix');
      // The overlap should contain text from the first chunk
      assert.ok(chunks[1].text.includes('section A'), 'Overlap should contain previous chunk content');
    });

    it('skips overlap when chunk_overlap is 0 (#13)', () => {
      const md = '---\ntitle: Test\n---\n## Section A\nContent A\n## Section B\nContent B';
      const chunks = chunkMarkdown(md, 'test', { chunk_overlap: 0 });
      assert.ok(chunks.length >= 2);
      // No chunk should start with [...]
      for (const c of chunks) {
        assert.ok(!c.text.startsWith('[...]'), 'No overlap when chunk_overlap is 0');
      }
    });

    it('does not add overlap when previous chunk text is shorter than overlapSize (#13)', () => {
      // Very short content so text length < overlapSize
      const md = '---\ntitle: T\n---\n## A\nHi\n## B\nBye';
      const chunks = chunkMarkdown(md, 'test', { chunk_overlap: 9999 });
      assert.ok(chunks.length >= 2);
      // prevText.length (very short) <= overlapSize → no overlap added
      assert.ok(!chunks[1].text.startsWith('[...]'), 'Should not add overlap when prev text is shorter than overlapSize');
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
