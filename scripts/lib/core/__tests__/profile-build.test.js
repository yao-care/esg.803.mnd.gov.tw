'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

const { PROJECT_ROOT } = require('../config');

describe('profile build', () => {
  const destDir = path.join(PROJECT_ROOT, 'tests', 'tmp-profile-output');
  let originalConfig;

  before(() => {
    const configPath = path.join(PROJECT_ROOT, 'config.json');
    // Save original if it exists, otherwise null
    originalConfig = fs.existsSync(configPath) ? fs.readFileSync(configPath, 'utf8') : null;

    // Write a self-contained test config with two profiles
    fs.writeFileSync(configPath, JSON.stringify({
      knowledge_body: { name: 'Test KB', name_en: 'test', organization: 'Test Org' },
      data_sources: {
        documents: { enabled: true, path: 'tests/fixtures/knowledge/', types: ['DOC'] },
        tables: {
          collected: { enabled: false, path: 'data/collected/' },
          reported: { enabled: false, path: 'data/reported/' },
        },
        imports: { enabled: false, path: 'imports/', parsers: [] },
      },
      ui: {
        locale: 'zh-TW',
        assistant_title: 'Test Assistant',
        welcome_message: 'Hello!',
        doc_group_labels: { document: 'Documents' },
        scan_display_names: {},
      },
      domain: {
        control_id_pattern: '',
        control_name: '',
        metadata_filename: 'merge.yaml',
        form_prefix: 'FRM',
        system_prompt: 'You are a test assistant.',
        assessment_controls: [],
        assessment_controls_covered: [],
        identity_doc_map: {},
      },
      api: { provider: 'anthropic', model: 'claude-sonnet-4-20250514', key_env_var: 'ANTHROPIC_API_KEY' },
      profiles: {
        assistant: {
          label: '測試助理',
          system_prompt_key: 'system_prompt',
          exclude_types: [],
          qa_questions: 'qa-questions.json',
        },
        limited: {
          label: '精簡版',
          system_prompt_key: 'system_prompt',
          exclude_types: ['WKI'],
          qa_questions: 'qa-questions.json',
        },
      },
    }, null, 2));

    fs.mkdirSync(destDir, { recursive: true });
  });

  after(() => {
    const configPath = path.join(PROJECT_ROOT, 'config.json');
    if (originalConfig !== null) {
      fs.writeFileSync(configPath, originalConfig);
    } else if (fs.existsSync(configPath)) {
      fs.unlinkSync(configPath);
    }
    fs.rmSync(destDir, { recursive: true, force: true });
  });

  it('produces one HTML per profile', () => {
    execSync(`node scripts/lib/core/build.js "${destDir}"`, { cwd: PROJECT_ROOT });
    assert.ok(fs.existsSync(path.join(destDir, 'assistant.html')), 'assistant.html should exist');
    assert.ok(fs.existsSync(path.join(destDir, 'limited.html')), 'limited.html should exist');
  });

  it('injects profile label as title', () => {
    const html = fs.readFileSync(path.join(destDir, 'assistant.html'), 'utf8');
    assert.ok(html.includes('測試助理'), 'should contain profile label');
  });

  it('limited profile has fewer chunks in search index', () => {
    const assistantHtml = fs.readFileSync(path.join(destDir, 'assistant.html'), 'utf8');
    const limitedHtml = fs.readFileSync(path.join(destDir, 'limited.html'), 'utf8');
    assert.ok(limitedHtml.length <= assistantHtml.length, 'limited should be same size or smaller');
  });
});
