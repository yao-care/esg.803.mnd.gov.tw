'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..', '..');

describe('qa-report.js', () => {
  const configPath = path.join(PROJECT_ROOT, 'config.json');
  const backupPath = configPath + '.bak';

  before(() => {
    if (fs.existsSync(configPath)) {
      fs.renameSync(configPath, backupPath);
    }
    fs.writeFileSync(configPath, JSON.stringify({
      knowledge_body: { name: 'Test KB', name_en: 'test' },
      data_sources: {
        documents: { enabled: true, path: 'knowledge/' },
        tables: {
          collected: { enabled: false, path: 'data/collected/' },
          reported: { enabled: false }
        },
        imports: { enabled: false }
      },
      qa: {
        search_hit_threshold: 0.95,
        answer_rate_threshold: 0.98,
        citation_accuracy_threshold: 0.98
      },
      domain: {
        control_id_pattern: '',
        identity_doc_map: {},
        system_prompt: 'You are a test assistant.',
        citation_pattern: '\\[來源:[^\\]]+\\]'
      },
      api: { provider: 'anthropic', model: 'claude-sonnet-4-20250514', key_env_var: 'ANTHROPIC_API_KEY' },
      ui: { scan_display_names: {} }
    }));
  });

  after(() => {
    if (fs.existsSync(backupPath)) {
      fs.renameSync(backupPath, configPath);
    } else if (fs.existsSync(configPath)) {
      fs.unlinkSync(configPath);
    }
  });

  it('module loads without error', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const mod = require('../qa-report.js');
    assert.ok(mod);
  });

  it('reads thresholds from config', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    delete require.cache[require.resolve('../config.js')];
    const { loadConfig } = require('../config.js');
    const config = loadConfig();
    assert.strictEqual(config.qa.search_hit_threshold, 0.95);
    assert.strictEqual(config.qa.answer_rate_threshold, 0.98);
  });

  it('exports all expected functions', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const mod = require('../qa-report.js');
    const expected = [
      'structuredSearch',
      'fullTextSearch',
      'findRelevantChunks',
      'evaluateAnswer',
      'evaluateSearchHit',
      'evaluateCitationFormat',
      'computeDocKeyHash',
      'buildIndex',
      'generateDynamicQuestions',
      'generateReport',
      'generateHtmlReport',
      'exportQuestions',
      'importAnswers',
    ];
    for (const fn of expected) {
      assert.ok(typeof mod[fn] === 'function', `Should export ${fn}`);
    }
  });

  it('evaluateAnswer rejects short answers', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { evaluateAnswer } = require('../qa-report.js');
    assert.strictEqual(evaluateAnswer('too short'), false);
    assert.strictEqual(evaluateAnswer(''), false);
    assert.strictEqual(evaluateAnswer(null), false);
  });

  it('evaluateAnswer accepts valid answers', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { evaluateAnswer } = require('../qa-report.js');
    const valid = 'This is a substantive answer with enough content to pass the length check for the QA verification system.';
    assert.strictEqual(evaluateAnswer(valid), true);
  });

  it('evaluateAnswer rejects refusal phrases in first 100 chars', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { evaluateAnswer } = require('../qa-report.js');
    const refusal = '無法回答此問題，因為目前文件中沒有相關資料可以參考，請洽詢相關人員進行確認。這是一段很長的補充說明文字。';
    assert.strictEqual(evaluateAnswer(refusal), false);
  });

  it('evaluateCitationFormat matches configurable citation pattern', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { evaluateCitationFormat } = require('../qa-report.js');
    assert.strictEqual(evaluateCitationFormat('根據 [來源:test-doc#section] 的規定'), true);
    assert.strictEqual(evaluateCitationFormat('沒有引文的回答'), false);
  });

  it('evaluateSearchHit checks for expected doc_key', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { evaluateSearchHit } = require('../qa-report.js');
    const results = [{ doc_key: 'doc-a' }, { doc_key: 'doc-b' }];
    assert.strictEqual(evaluateSearchHit(results, 'doc-a'), true);
    assert.strictEqual(evaluateSearchHit(results, 'doc-c'), false);
  });

  it('structuredSearch skips when control_id_pattern is empty', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { structuredSearch } = require('../qa-report.js');
    const chunksMap = { 'c1': { text: 'test' } };
    const metaIndex = [{ chunk_id: 'c1', doc_key: 'doc-a', controls: ['A.5.1'], doc_id: 'DOC-01' }];
    // With empty control_id_pattern (from config), structured search should return empty
    const results = structuredSearch('What about A.5.1?', chunksMap, metaIndex);
    assert.strictEqual(results.length, 0);
  });

  it('generateReport produces markdown with config-based title', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { generateReport } = require('../qa-report.js');
    const tmpDir = path.join(PROJECT_ROOT, 'tests', 'fixtures', 'qa-tmp');
    fs.mkdirSync(tmpDir, { recursive: true });
    const outputPath = path.join(tmpDir, 'test-report.md');
    const results = [
      { id: '1', question: 'Test?', expected_doc_key: 'doc-a', identity: 'tester',
        searchDocKeys: ['doc-a'], searchHit: true, answer: 'Yes', hasAnswer: true,
        citationCorrect: true, hasCitationFormat: true, source: 'seed' },
    ];
    const md = generateReport(results, outputPath);
    assert.ok(md.includes('Test KB'), 'Report title should include KB name from config');
    assert.ok(fs.existsSync(outputPath), 'Report file should be created');

    // Clean up
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('generateHtmlReport produces valid HTML', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { generateHtmlReport } = require('../qa-report.js');
    const results = [
      { id: '1', question: 'Test?', expected_doc_key: 'doc-a', identity: 'tester',
        searchDocKeys: ['doc-a'], searchHit: true, answer: 'Yes', hasAnswer: true,
        citationCorrect: true, hasCitationFormat: true, source: 'seed' },
    ];
    const html = generateHtmlReport(results);
    assert.ok(html.includes('<!DOCTYPE html>'), 'Should be valid HTML');
    assert.ok(html.includes('Test KB'), 'Should include KB name from config');
  });

  it('computeDocKeyHash returns consistent hashes', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { computeDocKeyHash } = require('../qa-report.js');
    const chunks = [
      { doc_key: 'doc-a', text: 'hello' },
      { doc_key: 'doc-a', text: 'world' },
      { doc_key: 'doc-b', text: 'other' },
    ];
    const hash1 = computeDocKeyHash(chunks, 'doc-a');
    const hash2 = computeDocKeyHash(chunks, 'doc-a');
    assert.strictEqual(hash1, hash2, 'Same input should produce same hash');
    assert.strictEqual(hash1.length, 64, 'Should be a SHA-256 hex digest');

    const hash3 = computeDocKeyHash(chunks, 'doc-b');
    assert.notStrictEqual(hash1, hash3, 'Different doc_keys should produce different hashes');
  });

  it('getSystemPrompt returns config value or fallback', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const mod = require('../qa-report.js');
    assert.ok(typeof mod.getSystemPrompt === 'function', 'Should export getSystemPrompt');
    const prompt = mod.getSystemPrompt();
    assert.strictEqual(prompt, 'You are a test assistant.');
  });

  it('exportQuestions produces exportable JSON structure', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { exportQuestions } = require('../qa-report.js');
    const questions = [
      { id: '1', question: 'Test?', expected_doc_key: 'doc-a', identity: 'tester', category: 'test' },
    ];
    const searchResultsMap = {
      '1': { results: [{ doc_key: 'doc-a', chunk_id: 'c1' }], context: 'Some context' },
    };
    const exported = exportQuestions(questions, searchResultsMap);
    assert.strictEqual(exported.total, 1);
    assert.ok(exported.system_prompt, 'Should include system prompt');
    assert.ok(exported.questions[0].context, 'Should include context');
  });

  it('importAnswers evaluates answers correctly', () => {
    delete require.cache[require.resolve('../qa-report.js')];
    const { importAnswers } = require('../qa-report.js');
    const questions = [
      { id: '1', question: 'Test?', expected_doc_key: 'doc-a', identity: 'tester', category: 'test' },
    ];
    const searchResultsMap = {
      '1': { results: [], searchHit: true, searchDocKeys: ['doc-a'] },
    };
    const answersData = {
      answers: [{ id: '1', answer: 'A valid substantive answer that is long enough to pass the minimum length requirement for QA verification.' }],
    };
    const evaluated = importAnswers(questions, searchResultsMap, answersData);
    assert.strictEqual(evaluated.length, 1);
    assert.strictEqual(evaluated[0].searchHit, true);
    assert.strictEqual(evaluated[0].hasAnswer, true);
  });
});
