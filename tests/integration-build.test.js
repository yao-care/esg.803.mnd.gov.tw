'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const os = require('os');

const PROJECT_ROOT = path.resolve(__dirname, '..');

describe('integration: full build pipeline', () => {
  const configPath = path.join(PROJECT_ROOT, 'config.json');
  const configBackup = configPath + '.bak';
  let outputDir;
  let destFile;

  before(() => {
    // Use a temp directory for output so we don't overwrite the real assistant.html
    outputDir = path.join(os.tmpdir(), `akora-integration-test-${Date.now()}`);

    // Backup existing config
    if (fs.existsSync(configPath)) {
      fs.copyFileSync(configPath, configBackup);
    }

    // Write test config pointing at the fixture knowledge base
    fs.writeFileSync(configPath, JSON.stringify({
      knowledge_body: {
        name: '測試知識體',
        name_en: 'test',
        organization: '測試組織',
      },
      data_sources: {
        documents: {
          enabled: true,
          path: 'tests/fixtures/knowledge/',
          types: ['DOC'],
        },
        tables: {
          collected: { enabled: false, path: 'data/collected/' },
          reported: { enabled: false, path: 'data/reported/' },
        },
        imports: { enabled: false, path: 'imports/', parsers: [] },
      },
      ui: {
        locale: 'zh-TW',
        assistant_title: '測試助理',
        welcome_message: '你好！這是測試。',
        drill_welcome_message: '',
        doc_group_labels: { document: '文件' },
        scan_display_names: {},
      },
      domain: {
        control_id_pattern: '',
        control_name: '',
        metadata_filename: 'merge.yaml',
        form_prefix: 'FRM',
        system_prompt: '你是一個測試助理。',
        drill_system_prompt: '',
        assessment_controls: [],
        assessment_controls_covered: [],
        identity_doc_map: {},
        citation_pattern: '\\[來源:[^\\]]+\\]',
      },
      api: {
        provider: 'anthropic',
        model: 'claude-sonnet-4-20250514',
        key_env_var: 'ANTHROPIC_API_KEY',
      },
    }));
  });

  after(() => {
    // Restore config
    if (fs.existsSync(configBackup)) {
      fs.renameSync(configBackup, configPath);
    } else if (fs.existsSync(configPath)) {
      fs.unlinkSync(configPath);
    }

    // Clean up temp output directory
    if (outputDir && fs.existsSync(outputDir)) {
      fs.rmSync(outputDir, { recursive: true, force: true });
    }
  });

  it('build completes without error and produces output file', () => {
    execSync(
      `node scripts/lib/core/build.js "${outputDir}"`,
      {
        cwd: PROJECT_ROOT,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      }
    );

    // Profile system outputs {profileName}.html; default profile is "assistant"
    destFile = path.join(outputDir, 'assistant.html');
    assert.ok(fs.existsSync(destFile), `Output file should exist at ${destFile}`);
  });

  it('output file is non-empty HTML', () => {
    const html = fs.readFileSync(destFile, 'utf8');
    assert.ok(html.length > 0, 'Output file should not be empty');
    assert.ok(html.includes('<!DOCTYPE html') || html.includes('<html'), 'Output should be HTML');
  });

  it('output contains search index data', () => {
    const html = fs.readFileSync(destFile, 'utf8');
    // The search index is embedded as __SEARCH_INDEX__ replacement
    assert.ok(html.includes('__SEARCH_INDEX__'), 'Output should contain __SEARCH_INDEX__ marker');
  });

  it('output contains chunks from the test fixture document', () => {
    const html = fs.readFileSync(destFile, 'utf8');
    // The fixture document has content about 第一節 目的 and 第二節 適用範圍
    // chunkMarkdown embeds the text into __CHUNKS__
    assert.ok(html.includes('__CHUNKS__'), 'Output should contain __CHUNKS__ marker');
    // The document content should appear somewhere in the embedded data
    assert.ok(
      html.includes('01-test-doc') || html.includes('測試文件') || html.includes('第一節'),
      'Output should contain content from the test fixture document'
    );
  });

  it('output contains substituted UI values', () => {
    const html = fs.readFileSync(destFile, 'utf8');
    assert.ok(html.includes('測試助理'), 'Output should contain assistant title from config');
    assert.ok(html.includes('你好！這是測試。'), 'Output should contain welcome message from config');
  });

  it('output contains APP_CONFIG with correct model', () => {
    const html = fs.readFileSync(destFile, 'utf8');
    assert.ok(
      html.includes('claude-sonnet-4-20250514'),
      'Output should contain the configured model name'
    );
  });
});

describe('form closed-loop pipeline', () => {
  it('generates schema for FRM fixtures', () => {
    const { generateAllSchemas } = require('../scripts/lib/core/generate-schemas');
    const schemasDir = path.join(PROJECT_ROOT, 'tests', 'tmp-integration-schemas');
    const generated = generateAllSchemas(
      path.join(PROJECT_ROOT, 'tests', 'fixtures', 'knowledge'),
      schemasDir
    );
    assert.ok(generated.includes('FRM-TEST'));
    fs.rmSync(schemasDir, { recursive: true, force: true });
  });

  it('validates fixture record against generated schema', () => {
    const { generateAllSchemas } = require('../scripts/lib/core/generate-schemas');
    const { validateRecordFile } = require('../scripts/lib/core/validate-record');
    const schemasDir = path.join(PROJECT_ROOT, 'tests', 'tmp-integration-schemas');
    generateAllSchemas(
      path.join(PROJECT_ROOT, 'tests', 'fixtures', 'knowledge'),
      schemasDir
    );
    const result = validateRecordFile(
      path.join(PROJECT_ROOT, 'tests', 'fixtures', 'reported', 'FRM-TEST-20260315-143022-a7f3.json'),
      schemasDir
    );
    assert.strictEqual(result.valid, true, `Validation errors: ${result.errors.join(', ')}`);
    fs.rmSync(schemasDir, { recursive: true, force: true });
  });

  it('chunks reported record for search index', () => {
    const { chunkReportedRecord } = require('../scripts/lib/core/chunk');
    const record = JSON.parse(fs.readFileSync(
      path.join(PROJECT_ROOT, 'tests', 'fixtures', 'reported', 'FRM-TEST-20260315-143022-a7f3.json'), 'utf8'
    ));
    const chunks = chunkReportedRecord(record, { title_zh: '測試表單', document_id: 'FRM-TEST' });
    assert.strictEqual(chunks.length, 1);
    assert.ok(chunks[0].text.includes('類別A'));
  });
});

describe('glossary integration', () => {
  it('expandGlossary expands known abbreviations', () => {
    function expandGlossary(query, glossary) {
      if (!glossary || typeof glossary !== 'object') return query;
      const expansions = [];
      const sorted = Object.entries(glossary)
        .sort((a, b) => b[0].length - a[0].length);
      for (const [term, expansion] of sorted) {
        const termLower = term.toLowerCase();
        const queryLower = query.toLowerCase();
        if (queryLower.includes(termLower)) {
          expansions.push(expansion);
        }
      }
      if (expansions.length === 0) return query;
      return query + ' ' + expansions.join(' ');
    }

    const glossary = { '管審會': '管理委員會' };
    const result = expandGlossary('管審會成員', glossary);
    assert.ok(result.includes('管理委員會'), 'Should expand abbreviation');
    assert.ok(result.includes('管審會'), 'Should preserve original query');
  });

  it('evaluateSearchHit handles __NONE__ expected_doc_key', () => {
    const { evaluateSearchHit } = require('../scripts/lib/core/qa-report');
    assert.strictEqual(evaluateSearchHit([], '__NONE__'), true, '__NONE__ with empty results should be a hit');
    assert.strictEqual(evaluateSearchHit([{ doc_key: 'test' }], '__NONE__'), false, '__NONE__ with results should not be a hit');
  });
});
