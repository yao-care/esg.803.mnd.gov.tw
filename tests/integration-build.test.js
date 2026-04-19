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
  let destFile;

  before(() => {
    // Use a temp file for output so we don't overwrite the real assistant.html
    destFile = path.join(os.tmpdir(), `assistant-integration-test-${Date.now()}.html`);

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

    // Clean up temp output file
    if (destFile && fs.existsSync(destFile)) {
      fs.unlinkSync(destFile);
    }
  });

  it('build completes without error and produces output file', () => {
    const result = execSync(
      `node scripts/lib/core/build.js "${PROJECT_ROOT}" "${destFile}"`,
      {
        cwd: PROJECT_ROOT,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      }
    );

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
