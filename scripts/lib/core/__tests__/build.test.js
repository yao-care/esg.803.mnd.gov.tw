'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..', '..');

describe('build.js', () => {
  const configPath = path.join(PROJECT_ROOT, 'config.json');
  const knowledgeDir = path.join(PROJECT_ROOT, 'tests', 'fixtures', 'knowledge');
  const testDocDir = path.join(knowledgeDir, '01-test-doc');

  before(() => {
    fs.mkdirSync(testDocDir, { recursive: true });
    fs.writeFileSync(configPath, JSON.stringify({
      knowledge_body: { name: 'Test KB', name_en: 'test', organization: 'Test Org' },
      data_sources: {
        documents: { enabled: true, path: 'tests/fixtures/knowledge/', types: ['DOC'] },
        tables: {
          collected: { enabled: false, path: 'data/collected/' },
          reported: { enabled: false, path: 'data/reported/' }
        },
        imports: { enabled: false, path: 'imports/', parsers: [] }
      },
      ui: {
        locale: 'zh-TW',
        assistant_title: 'Test Assistant',
        welcome_message: 'Hello!',
        doc_group_labels: { document: 'Documents' },
        scan_display_names: {}
      },
      domain: {
        control_id_pattern: '',
        control_name: '',
        metadata_filename: 'merge.yaml',
        form_prefix: 'FRM',
        system_prompt: 'You are a test assistant.',
        assessment_controls: [],
        assessment_controls_covered: [],
        identity_doc_map: {}
      },
      api: { provider: 'anthropic', model: 'claude-sonnet-4-20250514', key_env_var: 'ANTHROPIC_API_KEY' }
    }));

    // Create test document with merge.yaml
    fs.writeFileSync(path.join(testDocDir, 'merge.yaml'), 'title: Test Document\nversion: "1.0"\nlanguages:\n  zh: content.md\n');
    fs.writeFileSync(path.join(testDocDir, 'content.md'), '---\ntitle: Test Document\ndoc_id: DOC-01\nversion: "1.0"\n---\n\n## Section 1\n\nTest content here.\n\n## Section 2\n\nMore test content.\n');
  });

  after(() => {
    fs.rmSync(path.join(PROJECT_ROOT, 'tests', 'fixtures'), { recursive: true, force: true });
    if (fs.existsSync(configPath)) fs.unlinkSync(configPath);
  });

  it('readDocuments returns chunks from configured path', () => {
    delete require.cache[require.resolve('../build.js')];
    const build = require('../build.js');
    // readDocuments should be exported
    assert.ok(typeof build.readDocuments === 'function', 'readDocuments should be exported');
    const result = build.readDocuments(path.join(PROJECT_ROOT, 'tests', 'fixtures', 'knowledge'));
    assert.ok(result.chunks.length > 0, 'Should produce chunks');
    assert.strictEqual(result.chunks[0].source_type, 'document');
  });

  it('readDocuments uses custom metadataFilename', () => {
    // Create a document with a custom metadata filename
    const customDir = path.join(PROJECT_ROOT, 'tests', 'fixtures', 'knowledge', '02-custom');
    fs.mkdirSync(customDir, { recursive: true });
    fs.writeFileSync(path.join(customDir, 'meta.yaml'), 'title: Custom\nlanguages:\n  zh: doc.md\n');
    fs.writeFileSync(path.join(customDir, 'doc.md'), '---\ntitle: Custom Doc\ndoc_id: CUS-01\n---\n\n## Part 1\n\nCustom content.\n');

    delete require.cache[require.resolve('../build.js')];
    const build = require('../build.js');
    const result = build.readDocuments(
      path.join(PROJECT_ROOT, 'tests', 'fixtures', 'knowledge'),
      { metadataFilename: 'meta.yaml' }
    );
    // Should find both the default merge.yaml doc and the meta.yaml doc
    const customChunks = result.chunks.filter(c => c.doc_key === '02-custom');
    assert.ok(customChunks.length > 0, 'Should find docs using custom metadata filename');

    // Clean up
    fs.rmSync(customDir, { recursive: true, force: true });
  });

  it('readDocuments skips directories starting with _', () => {
    const metaDir = path.join(PROJECT_ROOT, 'tests', 'fixtures', 'knowledge', '_meta');
    fs.mkdirSync(metaDir, { recursive: true });
    fs.writeFileSync(path.join(metaDir, 'merge.yaml'), 'title: Meta\nlanguages:\n  zh: m.md\n');
    fs.writeFileSync(path.join(metaDir, 'm.md'), '---\ntitle: Meta\n---\n## X\nContent\n');

    delete require.cache[require.resolve('../build.js')];
    const build = require('../build.js');
    const result = build.readDocuments(path.join(PROJECT_ROOT, 'tests', 'fixtures', 'knowledge'));
    const metaChunks = result.chunks.filter(c => c.doc_key === '_meta');
    assert.strictEqual(metaChunks.length, 0, 'Should skip _meta directory');

    fs.rmSync(metaDir, { recursive: true, force: true });
  });

  it('replacePlaceholder replaces marker+default pattern', () => {
    delete require.cache[require.resolve('../build.js')];
    const build = require('../build.js');
    const template = 'const data = /*__CHUNKS__*/{}; done;';
    const result = build.replacePlaceholder(template, '__CHUNKS__', '{}', '{"a":1}');
    assert.strictEqual(result, 'const data = /*__CHUNKS__*/{"a":1}; done;');
  });

  it('substitutePlaceholders replaces UI/domain tokens', () => {
    delete require.cache[require.resolve('../build.js')];
    const build = require('../build.js');
    const html = '<title>__ASSISTANT_TITLE__</title><h1>__KB_NAME__</h1><org>__ORGANIZATION__</org>';
    const config = {
      ui: { assistant_title: 'My Assistant', doc_group_labels: {} },
      knowledge_body: { name: 'My KB', organization: 'My Org' },
      domain: {},
    };
    const result = build.substitutePlaceholders(html, config);
    assert.ok(result.includes('My Assistant'), 'Should substitute assistant title');
    assert.ok(result.includes('My KB'), 'Should substitute KB name');
    assert.ok(result.includes('My Org'), 'Should substitute organization');
  });

  it('readCollectedTables reads JSON from latest subdirectory', () => {
    const collectedDir = path.join(PROJECT_ROOT, 'tests', 'fixtures', 'collected');
    const scanDir = path.join(collectedDir, '20260101-120000');
    fs.mkdirSync(scanDir, { recursive: true });
    fs.writeFileSync(path.join(scanDir, 'test-result.json'), JSON.stringify({
      tool: 'test-scanner',
      status: 'pass',
      timestamp: '2026-01-01T12:00:00Z',
      summary: { pass: 5, fail: 0 }
    }));

    delete require.cache[require.resolve('../build.js')];
    const build = require('../build.js');
    const renderedDocs = {};
    const chunks = build.readCollectedTables(collectedDir, renderedDocs, { 'test-result': 'Test Scanner' });
    assert.ok(chunks.length > 0, 'Should produce collected chunks');
    assert.strictEqual(chunks[0].source_type, 'collected');
    assert.ok(renderedDocs['collected/test-result'], 'Should produce rendered HTML');

    fs.rmSync(collectedDir, { recursive: true, force: true });
  });

  it('readReportedTables reads flat JSON files', () => {
    const reportedDir = path.join(PROJECT_ROOT, 'tests', 'fixtures', 'reported');
    fs.mkdirSync(reportedDir, { recursive: true });
    fs.writeFileSync(path.join(reportedDir, 'incident-log.json'), JSON.stringify({
      tool: 'manual',
      status: 'completed',
      entries: [{ date: '2026-01-01', description: 'Test incident' }]
    }));

    delete require.cache[require.resolve('../build.js')];
    const build = require('../build.js');
    const renderedDocs = {};
    const chunks = build.readReportedTables(reportedDir, renderedDocs);
    assert.ok(chunks.length > 0, 'Should produce reported chunks');
    assert.strictEqual(chunks[0].source_type, 'reported');
    assert.strictEqual(chunks[0].type, 'reported');
    assert.ok(renderedDocs['reported/incident-log'], 'Should produce rendered HTML');

    fs.rmSync(reportedDir, { recursive: true, force: true });
  });

  it('exports all expected functions', () => {
    delete require.cache[require.resolve('../build.js')];
    const build = require('../build.js');
    const expected = ['readDocuments', 'readCollectedTables', 'readReportedTables',
                      'replacePlaceholder', 'substitutePlaceholders', 'build',
                      'findFiles', 'readFileSafe', 'extractZhPath', 'extractDocumentId'];
    for (const fn of expected) {
      assert.ok(typeof build[fn] === 'function', `Should export ${fn}`);
    }
  });
});
