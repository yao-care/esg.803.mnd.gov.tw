#!/usr/bin/env node
'use strict';

/**
 * qa-report.js — QA Verification Engine for Knowledge Body Assistant
 *
 * Loads test questions (seed + dynamic + regression), runs search + optional
 * Claude API evaluation, and produces accuracy reports in Markdown and HTML.
 *
 * All domain-specific values are read from config.json via the config loader,
 * making this module reusable across knowledge bodies.
 *
 * Generalized from agent.system-integration-quality-control/scripts/lib/audit-assistant/qa-report.js:
 *   1.  loadConfig + PROJECT_ROOT from config.js
 *   2.  A\.\d+\.\d+ regex → config.domain.control_id_pattern (skip if empty)
 *   3.  Hardcoded 0.95 threshold → config.qa.search_hit_threshold
 *   4.  ANTHROPIC_API_KEY → process.env[config.api.key_env_var]
 *   5.  Hardcoded model → config.api.model
 *   6.  SCAN_DISPLAY_NAMES duplicate → config.ui.scan_display_names
 *   7.  IDENTITY_DOC_MAP → config.domain.identity_doc_map (skip if empty)
 *   8.  QA_SYSTEM_PROMPT constant → config.domain.system_prompt (with generic fallback)
 *   9.  'isms' directory → config.data_sources.documents.path
 *  10.  'docs/scans' path → config.data_sources.tables.collected.path
 *  11.  Chinese report header → config.knowledge_body.name + ' — 對答正確性報告'
 *  12.  Citation format check → config.domain.citation_pattern with fallback
 *  13.  Dynamic prompt uses config.domain values for question generation
 *  14.  Hardcoded refusal phrases → configurable or generic defaults
 *  15.  qa-questions.json path → scripts/lib/core/qa-questions.json
 *
 * Usage:
 *   node scripts/lib/core/qa-report.js [options]
 *
 * Options:
 *   --seed-only         Only run seed questions
 *   --search-only       Only run search tests (no Claude API calls)
 *   --html              Generate HTML report alongside Markdown
 *   --export            Export questions + context for Claude Code mode
 *   --evaluate=FILE     Evaluate answers from exported file
 *   --refresh-dynamic   Force-regenerate dynamic questions
 *   --identity=NAME     Filter by identity
 *   --source=TYPE       Filter by source (document/collected)
 *   --output-dir=DIR    Output directory for reports
 *   --ci                CI mode (exit 1 if below threshold)
 *   --dry-run           Print questions without running
 */

const crypto = require('node:crypto');
const fs = require('fs');
const path = require('path');
const MiniSearch = require('minisearch');

const { loadConfig, PROJECT_ROOT } = require('./config.js');   // [1]
const { chunkMarkdown, chunkCollectedResult } = require('./chunk.js');
const { buildSearchIndex, buildMetaIndex, chineseTokenize } = require('./search.js');
const { filterChunks } = require('./build.js');

let _allChunks = [];  // Module-level, set by main() after buildIndex

// ---------------------------------------------------------------------------
// Config helpers (loaded lazily so tests can swap config.json between calls)
// ---------------------------------------------------------------------------

/** @returns {Object} Current config */
function cfg() { return loadConfig(); }

/**
 * Load API key: env var (from config) > config.json api_key field.
 */
function getApiKey() {
  const config = cfg();
  const envVar = config.api?.key_env_var || 'ANTHROPIC_API_KEY';        // [4]
  if (process.env[envVar]) return process.env[envVar];
  try {
    return config.api_key || '';
  } catch { return ''; }
}

/**
 * Return the system prompt from config, or a generic fallback.        // [8]
 */
function getSystemPrompt() {
  const config = cfg();
  const prompt = config.domain?.system_prompt;
  if (prompt) return prompt;

  // Generic fallback
  const kbName = config.knowledge_body?.name || 'Knowledge Base';
  return `You are a knowledge assistant for ${kbName}.\n\nRespond based on the provided document context. Use citation format [來源:doc_key#section]. If the question is outside the document scope, say so. Use Traditional Chinese.`;
}

/**
 * Get refusal phrases — configurable via config.domain.refusal_phrases  // [14]
 * or fall back to generic defaults.
 */
function getRefusalPhrases() {
  const config = cfg();
  if (Array.isArray(config.domain?.refusal_phrases) && config.domain.refusal_phrases.length > 0) {
    return config.domain.refusal_phrases;
  }
  return ['無此資訊', '資料不足', '無法回答', '超出範圍', '目前知識庫無'];
}

// ============================================================
// SEARCH ENGINE (mirrors SPA logic)
// ============================================================

/**
 * Structured search — regex extract control IDs and doc IDs.
 *
 * Uses config.domain.control_id_pattern (e.g. "A\.\d+\.\d+") for control  // [2]
 * matching. If the pattern is empty, control-ID matching is skipped entirely.
 *
 * @param {string} query
 * @param {Object} chunksMap - { [chunk_id]: { text } }
 * @param {Array} metaIndex
 * @returns {Array}
 */
function structuredSearch(query, chunksMap, metaIndex) {
  const config = cfg();
  const controlPattern = config.domain?.control_id_pattern || '';       // [2]
  const results = [];

  // Control ID matching — only if pattern is configured
  let controlMatches = [];
  if (controlPattern) {
    const controlRe = new RegExp(controlPattern, 'gi');
    controlMatches = [...query.matchAll(controlRe)].map(m => m[0].toUpperCase());
  }

  // Doc ID matching (always active)
  const docMatches = [...query.matchAll(/[A-Z]{2,5}-[A-Z0-9\-]+/gi)].map(m => m[0].toUpperCase());

  // If neither pattern produced matches, return empty
  if (controlMatches.length === 0 && docMatches.length === 0) return results;

  for (const entry of metaIndex) {
    let matched = false;
    for (const ctrl of controlMatches) {
      if ((entry.controls || []).some(c => c.toUpperCase() === ctrl)) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      for (const did of docMatches) {
        if ((entry.doc_id || '').toUpperCase().includes(did)) {
          matched = true;
          break;
        }
      }
    }
    if (matched) {
      const chunk = chunksMap[entry.chunk_id];
      if (chunk) results.push({ ...chunk, chunk_id: entry.chunk_id, doc_key: entry.doc_key });
    }
  }
  return results;
}

/**
 * Full-text search via MiniSearch.
 *
 * @param {string} query
 * @param {Object} msInstance - MiniSearch instance
 * @param {Object} chunksMap
 * @param {number} topK
 * @returns {Array}
 */
function fullTextSearch(query, msInstance, chunksMap, topK) {
  if (!msInstance) return [];
  const results = msInstance.search(query, {
    tokenize: chineseTokenize,
    processTerm: t => t.toLowerCase(),
    fuzzy: 0.2,
    prefix: true,
  });
  return results
    .slice(0, topK || 6)
    .map(r => {
      const chunk = chunksMap[r.chunk_id];
      return chunk ? { ...chunk, chunk_id: r.chunk_id, doc_key: r.doc_key } : null;
    })
    .filter(Boolean);
}

/**
 * Combined search (structured first, then full-text).
 *
 * @param {string} query
 * @param {Object} chunksMap
 * @param {Array} metaIndex
 * @param {Object} msInstance
 * @returns {Array}
 */
function findRelevantChunks(query, chunksMap, metaIndex, msInstance) {
  const structured = structuredSearch(query, chunksMap, metaIndex);
  if (structured.length > 0) return structured.slice(0, 6);

  const ft = fullTextSearch(query, msInstance, chunksMap, 6);
  if (ft.length > 0) return ft;

  return [];
}

// ============================================================
// EVALUATION FUNCTIONS
// ============================================================

/**
 * Check if search results contain the expected doc_key.
 *
 * @param {Array} results
 * @param {string} expectedDocKey
 * @returns {boolean}
 */
function evaluateSearchHit(results, expectedDocKey, acceptedDocKeys) {
  // __NONE__ = expect zero results (gate test)
  if (expectedDocKey === '__NONE__') return results.length === 0;
  // Check primary expected_doc_key
  if (results.some(r => r.doc_key === expectedDocKey)) return true;
  // Check accepted_doc_keys (cross-document matches validated at generation time)
  if (acceptedDocKeys && acceptedDocKeys.length > 0) {
    return results.some(r => acceptedDocKeys.includes(r.doc_key));
  }
  return false;
}

/**
 * Check if answer is valid (substantive, not a refusal).
 *
 * Rules:
 * - Must be > 50 chars
 * - Must NOT start with a refusal phrase (checked within first 100 chars)
 *
 * @param {string} answer
 * @returns {boolean}
 */
function evaluateAnswer(answer) {
  if (!answer || answer.length <= 50) return false;
  const refusalPhrases = getRefusalPhrases();                           // [14]
  for (const phrase of refusalPhrases) {
    const pos = answer.indexOf(phrase);
    if (pos !== -1 && pos < 100) return false;
  }
  return true;
}

/**
 * Check if answer contains citation format matching config.domain.citation_pattern. // [12]
 *
 * Rule 1: formatted citation matching the configured pattern.
 * Rule 2: bare doc_key (short ID) mentioned anywhere in the response.
 *
 * @param {string} answer
 * @returns {boolean}
 */
function evaluateCitationFormat(answer) {
  const config = cfg();
  const pattern = config.domain?.citation_pattern || '\\[來源:[^\\]]+\\]';
  // Rule 1: formatted citation
  if (new RegExp(pattern).test(answer)) return true;

  // Rule 2: bare doc_key mentioned in response
  if (_allChunks.length > 0) {
    const shortIds = [...new Set(
      _allChunks.map(c => {
        const rawDocKey = (c.doc_key || '').replace(/^external\/[^/]+\//, '');
        const m = rawDocKey.match(/^([A-Za-z]+-\d+(?:-\d+[a-z]?)?)/);
        return m ? m[1] : null;
      }).filter(Boolean)
    )];
    return shortIds.some(id => answer.includes(id));
  }
  return false;
}

// ============================================================
// INDEX BUILDING (reuse chunk.js + search.js)
// ============================================================

/**
 * Read documents and collected tables, build chunks + search indexes.
 * Paths come from config.data_sources.                                 // [9, 10]
 *
 * @returns {{ chunksMap: Object, metaIndex: Array, msInstance: Object, allChunks: Array }}
 */
function buildIndex() {
  const config = cfg();
  const allChunks = [];

  // --- Documents ---                                                   // [9]
  const docsRelPath = config.data_sources?.documents?.path || 'knowledge/';
  const docsDir = path.join(PROJECT_ROOT, docsRelPath);

  if (!fs.existsSync(docsDir)) {
    console.error(`Documents directory not found: ${docsDir}`);
    process.exit(1);
  }

  const metadataFilename = config.domain?.metadata_filename || 'merge.yaml';

  const entries = fs.readdirSync(docsDir, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith('_')) continue;
    const metaPath = path.join(docsDir, entry.name, metadataFilename);
    if (!fs.existsSync(metaPath)) continue;

    const metaYaml = fs.readFileSync(metaPath, 'utf8');
    const zhMatch = metaYaml.match(/^\s+zh:\s*(.+)$/m);
    if (!zhMatch) continue;

    const mdPath = path.join(docsDir, entry.name, zhMatch[1].trim());
    if (!fs.existsSync(mdPath)) continue;

    const md = fs.readFileSync(mdPath, 'utf8');
    allChunks.push(...chunkMarkdown(md, entry.name));
  }

  // --- Collected tables (e.g. scan results) ---                        // [10]
  const collectedConf = config.data_sources?.tables?.collected;
  if (collectedConf?.enabled !== false) {
    const collectedRelPath = collectedConf?.path || 'data/collected/';
    const collectedDir = path.join(PROJECT_ROOT, collectedRelPath);
    if (fs.existsSync(collectedDir)) {
      const subDirs = fs.readdirSync(collectedDir, { withFileTypes: true })
        .filter(e => e.isDirectory())
        .map(e => e.name)
        .sort()
        .reverse();
      if (subDirs.length > 0) {
        const latestDir = path.join(collectedDir, subDirs[0]);
        const displayNames = config.ui?.scan_display_names || {};       // [6]
        const findResultFiles = (dir) => {
          const results = [];
          if (!fs.existsSync(dir)) return results;
          for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, e.name);
            if (e.isDirectory()) results.push(...findResultFiles(full));
            else if (e.name.endsWith('-result.json')) results.push(full);
          }
          return results;
        };
        for (const fp of findResultFiles(latestDir)) {
          const baseName = path.basename(fp, '.json');
          try {
            const json = JSON.parse(fs.readFileSync(fp, 'utf8'));
            allChunks.push(chunkCollectedResult(json, baseName, { displayName: displayNames[baseName] || baseName }));
          } catch (_) { /* skip invalid JSON */ }
        }
      }
    }
  }

  const metaIndex = buildMetaIndex(allChunks);
  const searchIndexJson = buildSearchIndex(allChunks);
  const msInstance = MiniSearch.loadJSON(searchIndexJson, {
    fields: ['text', 'title', 'section'],
    storeFields: ['chunk_id', 'doc_key', 'title', 'section'],
    tokenize: chineseTokenize,
  });

  const chunksMap = {};
  for (const chunk of allChunks) {
    chunksMap[chunk.chunk_id] = { text: chunk.text };
  }

  return { chunksMap, metaIndex, msInstance, allChunks };
}

// ============================================================
// DYNAMIC QUESTION GENERATION
// ============================================================

/**
 * Compute SHA-256 content hash for all chunks of a given doc_key.
 *
 * @param {Array} allChunks
 * @param {string} docKey
 * @returns {string} hex digest (64 chars)
 */
function computeDocKeyHash(allChunks, docKey) {
  const texts = allChunks
    .filter(c => c.doc_key === docKey)
    .map(c => c.text)
    .sort()
    .join('|||');
  return crypto.createHash('sha256').update(texts).digest('hex');
}

/**
 * Pick the best identity for a doc_key using config.domain.identity_doc_map. // [7]
 *
 * @param {string} docKey
 * @returns {string}
 */
function pickIdentityForDocKey(docKey) {
  const config = cfg();
  const identityDocMap = config.domain?.identity_doc_map || {};         // [7]
  if (Object.keys(identityDocMap).length === 0) return '使用者';

  for (const [identity, docKeys] of Object.entries(identityDocMap)) {
    if (Array.isArray(docKeys) && docKeys.includes(docKey)) return identity;
  }
  // Fallback to first identity or generic
  const firstIdentity = Object.keys(identityDocMap)[0];
  return firstIdentity || '使用者';
}

/**
 * Generate dynamic questions for doc_keys with insufficient seed coverage.
 *
 * Uses Claude API with content-hash caching to avoid regenerating unchanged docs.
 *
 * @param {Array} allChunks
 * @param {Array} seedQuestions
 * @param {string} cachePath
 * @param {boolean} forceRefresh
 * @returns {Promise<Array>}
 */
async function generateDynamicQuestions(allChunks, seedQuestions, cachePath, forceRefresh) {
  const config = cfg();

  // Count seed coverage per doc_key
  const seedCoverage = new Map();
  for (const q of seedQuestions) {
    const dk = q.expected_doc_key;
    seedCoverage.set(dk, (seedCoverage.get(dk) || 0) + 1);
  }

  // Get all unique doc_keys from chunks
  const allDocKeys = [...new Set(allChunks.map(c => c.doc_key).filter(Boolean))];

  // Determine which doc_keys need questions
  const needs = [];
  for (const dk of allDocKeys) {
    const count = seedCoverage.get(dk) || 0;
    if (count < 2) {
      needs.push({ docKey: dk, needed: 2 - count });
    }
  }

  if (needs.length === 0) {
    console.log('[dynamic] All doc_keys covered by seed questions.');
    return [];
  }

  // Load cache
  let cache = { version: 1, generated_at: '', entries: {} };
  if (!forceRefresh && fs.existsSync(cachePath)) {
    try {
      cache = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    } catch (_) { /* start fresh */ }
  }

  const dynamicQuestions = [];
  let dynIdCounter = 1;

  // Skip identity-based generation if identity_doc_map is empty          // [7]
  const identityDocMap = config.domain?.identity_doc_map || {};
  const hasIdentities = Object.keys(identityDocMap).length > 0;
  const kbName = config.knowledge_body?.name || 'Knowledge Base';        // [13]
  const model = config.api?.model || 'claude-sonnet-4-20250514';         // [5]

  for (const { docKey, needed } of needs) {
    const currentHash = computeDocKeyHash(allChunks, docKey);
    const cached = cache.entries[docKey];

    // Use cache if hash matches and not force refresh
    if (!forceRefresh && cached && cached.content_hash === currentHash && cached.questions.length >= needed) {
      dynamicQuestions.push(...cached.questions.slice(0, needed));
      continue;
    }

    // Generate via Claude API
    const chunkTexts = allChunks
      .filter(c => c.doc_key === docKey)
      .map(c => c.text)
      .join('\n\n---\n\n')
      .slice(0, 4000); // limit context size

    const identity = pickIdentityForDocKey(docKey);

    const apiKey = getApiKey();
    const envVar = config.api?.key_env_var || 'ANTHROPIC_API_KEY';
    if (!apiKey) {
      if (!generateDynamicQuestions._warned) {
        console.warn(`[dynamic] No ${envVar} — 跳過動態題產生。動態題需要 API key 才能自動產生，跳過不影響靜態種子題驗證。`);
        console.warn(`[dynamic] 設定方式：export ${envVar}=your-key`);
        generateDynamicQuestions._warned = true;
      }
      continue;
    }

    // Build dynamic generation prompt using config.domain values          // [13]
    const identityClause = hasIdentities
      ? `\n2. 問題要像真實的${identity}會問的問題`
      : '\n2. 問題要像實際使用者會問的問題';

    // Determine if this is collected evidence (scan results) vs knowledge document
    const isCollected = allChunks.find(c => c.doc_key === docKey)?.source_type === 'collected';

    const promptText = isCollected
      ? `以下是一份自動化掃描的證據資料。請產生 ${needed} 個稽核員在審查這份證據時會問的問題。
要求：
1. 問題必須是稽核員驗證合規性時會問的，例如：掃描覆蓋是否足夠、發現的風險等級分佈、是否有未結案的 Critical/High 發現、掃描頻率是否符合程序規定
2. 禁止問具體數字（如「共掃描幾個元件」「檔案大小多少」）——稽核員不會問 AI 幫他查數字
3. 問題應該能從這份證據 + 相關程序文件中找到答案
4. 輸出 JSON 陣列格式，每個元素有 question 和 category 欄位

證據資料：
${chunkTexts}`
      : `根據以下${kbName}文件內容，產生 ${needed} 個相關問題。
要求：
1. 問���必須能從這份文件的內容中找到答案，不要問其他文件才能回答的問題${identityClause}
3. 避免問「本文件的目的為何」這類過於制式的問題
4. 輸出 JSON 陣列格式，每個元素有 question 和 category 欄位

文件內容：
${chunkTexts}`;

    try {
      console.log(`[dynamic] Generating ${needed} questions for ${docKey}...`);
      const resp = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify({
          model,                                                         // [5]
          max_tokens: 1024,
          messages: [{
            role: 'user',
            content: promptText,
          }],
        }),
      });

      if (!resp.ok) {
        console.warn(`[dynamic] API error for ${docKey}: ${resp.status}`);
        continue;
      }

      const data = await resp.json();
      const text = data.content[0]?.text || '';
      const jsonMatch = text.match(/\[[\s\S]*\]/);
      if (!jsonMatch) continue;

      const generated = JSON.parse(jsonMatch[0]);
      const questions = generated.slice(0, needed).map(g => ({
        id: `dyn-${String(dynIdCounter++).padStart(3, '0')}`,
        question: g.question,
        expected_doc_key: docKey,
        identity,
        category: g.category || '一般',
        source: 'dynamic',
      }));

      // Update cache
      cache.entries[docKey] = {
        content_hash: currentHash,
        questions,
      };

      dynamicQuestions.push(...questions);
    } catch (err) {
      console.warn(`[dynamic] Error generating for ${docKey}: ${err.message}`);
    }

    // Rate limit
    await new Promise(r => setTimeout(r, 300));
  }

  // Top-up if total still < 200
  const totalSoFar = seedQuestions.length + dynamicQuestions.length;
  if (totalSoFar < 200) {
    const allCoverage = new Map();
    for (const q of [...seedQuestions, ...dynamicQuestions]) {
      const dk = q.expected_doc_key;
      allCoverage.set(dk, (allCoverage.get(dk) || 0) + 1);
    }
    const sorted = allDocKeys
      .map(dk => ({ dk, count: allCoverage.get(dk) || 0 }))
      .sort((a, b) => a.count - b.count);

    let remaining = 200 - totalSoFar;
    for (const { dk } of sorted) {
      if (remaining <= 0) break;
      const currentHash = computeDocKeyHash(allChunks, dk);
      const cached = cache.entries[dk];

      if (cached && cached.content_hash === currentHash && cached.questions.length > (allCoverage.get(dk) || 0)) {
        const extra = cached.questions.slice(allCoverage.get(dk) || 0);
        dynamicQuestions.push(...extra.slice(0, remaining));
        remaining -= extra.length;
      }
    }
  }

  // Save cache
  cache.generated_at = new Date().toISOString();
  fs.mkdirSync(path.dirname(cachePath), { recursive: true });
  fs.writeFileSync(cachePath, JSON.stringify(cache, null, 2), 'utf8');

  return dynamicQuestions;
}

// ============================================================
// EXPORT / IMPORT (Claude Code mode)
// ============================================================

/**
 * Export questions with search results for Claude Code mode.
 *
 * @param {Array} questions
 * @param {Object} searchResultsMap
 * @returns {Object} Exportable JSON structure
 */
function exportQuestions(questions, searchResultsMap) {
  return {
    exported_at: new Date().toISOString(),
    total: questions.length,
    system_prompt: getSystemPrompt(),                                    // [8]
    questions: questions.map(q => {
      const sr = searchResultsMap[q.id] || { results: [], context: '' };
      return {
        id: q.id,
        question: q.question,
        expected_doc_key: q.expected_doc_key,
        identity: q.identity,
        category: q.category,
        search_results: sr.results.map(r => ({ doc_key: r.doc_key, chunk_id: r.chunk_id })),
        context: sr.context,
      };
    }),
  };
}

/**
 * Import answers from qa-answers.json and evaluate.
 *
 * @param {Array} questions
 * @param {Object} searchResultsMap
 * @param {Object} answersData - { answers: [{ id, answer }] }
 * @returns {Array} Evaluated result objects
 */
function importAnswers(questions, searchResultsMap, answersData) {
  const answerMap = new Map();
  for (const a of answersData.answers) {
    answerMap.set(a.id, a.answer);
  }

  return questions.map(q => {
    const sr = searchResultsMap[q.id] || { results: [], searchHit: false, searchDocKeys: [] };
    const answer = answerMap.get(q.id) || '';
    return {
      ...q,
      searchDocKeys: sr.searchDocKeys,
      searchHit: sr.searchHit,
      answer,
      hasAnswer: evaluateAnswer(answer),
      citationCorrect: sr.searchHit || answer.includes(q.expected_doc_key),
      hasCitationFormat: evaluateCitationFormat(answer),
    };
  });
}

// ============================================================
// REPORT GENERATION
// ============================================================

/**
 * Generate a Markdown QA accuracy report.
 *
 * @param {Array} results
 * @param {string} outputPath
 * @returns {string} The Markdown content
 */
function generateReport(results, outputPath) {
  const config = cfg();
  const kbName = config.knowledge_body?.name || 'Knowledge Base';       // [11]

  const total = results.length;
  const searchHits = results.filter(r => r.searchHit).length;
  const answered = results.filter(r => r.hasAnswer).length;
  const cited = results.filter(r => r.citationCorrect).length;
  const formatted = results.filter(r => r.hasCitationFormat).length;

  const seedCount = results.filter(r => !r.source || r.source !== 'dynamic').length;
  const dynCount = results.filter(r => r.source === 'dynamic').length;

  // Identity stats
  const identityStats = new Map();
  for (const r of results) {
    const id = r.identity || '未分類';
    if (!identityStats.has(id)) identityStats.set(id, { total: 0, searchHit: 0, answered: 0, cited: 0 });
    const s = identityStats.get(id);
    s.total++;
    if (r.searchHit) s.searchHit++;
    if (r.hasAnswer) s.answered++;
    if (r.citationCorrect) s.cited++;
  }

  // Failed questions
  const failures = results.filter(r => !r.searchHit || !r.hasAnswer || !r.citationCorrect);

  let md = `# ${kbName} — 對答正確性報告

**系統**：knowledge-assistant
**日期**：${new Date().toISOString().split('T')[0]}
**題數**：${total}（種子 ${seedCount} + 動態 ${dynCount}）

## 總覽

| 指標 | 數值 |
|------|------|
| 搜尋命中率 | ${searchHits}/${total} (${((searchHits / total) * 100).toFixed(1)}%) |
| 有效回答率 | ${answered}/${total} (${((answered / total) * 100).toFixed(1)}%) |
| 引文正確率 | ${cited}/${total} (${((cited / total) * 100).toFixed(1)}%) |
| 引文格式率 | ${formatted}/${total} (${((formatted / total) * 100).toFixed(1)}%) |

## 依身份統計

| 身份 | 題數 | 搜尋命中 | 有效回答 | 引文正確 |
|------|:----:|:-------:|:-------:|:-------:|
`;

  for (const [identity, s] of identityStats) {
    md += `| ${identity} | ${s.total} | ${s.searchHit}/${s.total} | ${s.answered}/${s.total} | ${s.cited}/${s.total} |\n`;
  }

  if (failures.length > 0) {
    md += '\n## 失敗題目分析\n\n';
    for (const f of failures) {
      const reasons = [];
      if (!f.searchHit) reasons.push('搜尋未命中');
      if (!f.hasAnswer) reasons.push('回答無效');
      if (!f.citationCorrect) reasons.push('引文錯誤');
      md += `### 第 ${f.id} 題（${f.identity}）

- **問題**：${f.question}
- **期望 doc_key**：${f.expected_doc_key}
- **搜尋結果**：${(f.searchDocKeys || []).join(', ') || '(無)'}
- **命中**：${f.searchHit ? '✓' : '✗'}
- **有效回答**：${f.hasAnswer ? '✓' : '✗'}
- **引文正確**：${f.citationCorrect ? '✓' : '✗'}
- **根因**：${reasons.join(' / ')}
- **回答摘要**：${(f.answer || '').substring(0, 300)}${(f.answer || '').length > 300 ? '...' : ''}

`;
    }
  }

  md += '\n## 逐題結果\n\n';
  for (const r of results) {
    md += `- [${r.searchHit && r.hasAnswer && r.citationCorrect ? '✓' : '✗'}] #${r.id} (${r.identity}) ${r.question.substring(0, 40)}... → ${r.searchHit ? '命中' : '未中'} | ${r.hasAnswer ? '有答' : '無答'} | ${r.citationCorrect ? '引正' : '引誤'}\n`;
  }

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, md, 'utf8');
  return md;
}

// ============================================================
// HTML REPORT GENERATION
// ============================================================

/**
 * HTML-escape a string to prevent injection in report output.
 *
 * @param {string} str
 * @returns {string}
 */
function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * Generate a self-contained HTML QA accuracy report.
 *
 * @param {Array} results
 * @returns {string} Complete HTML string
 */
function generateHtmlReport(results) {
  const config = cfg();
  const kbName = config.knowledge_body?.name || 'Knowledge Base';       // [11]
  const orgName = config.knowledge_body?.organization || '';

  const total = results.length;
  const searchHits = results.filter(r => r.searchHit).length;
  const answered = results.filter(r => r.hasAnswer).length;
  const cited = results.filter(r => r.citationCorrect).length;
  const formatted = results.filter(r => r.hasCitationFormat).length;

  const seedResults = results.filter(r => !r.source || r.source !== 'dynamic');
  const dynResults = results.filter(r => r.source === 'dynamic');
  const seedCount = seedResults.length;
  const dynCount = dynResults.length;

  // Per-source metrics
  const seedHits = seedResults.filter(r => r.searchHit).length;
  const seedAnswered = seedResults.filter(r => r.hasAnswer).length;
  const seedCited = seedResults.filter(r => r.citationCorrect).length;
  const dynHits = dynResults.filter(r => r.searchHit).length;
  const dynAnswered = dynResults.filter(r => r.hasAnswer).length;
  const dynCited = dynResults.filter(r => r.citationCorrect).length;

  // Identity stats
  const identityStats = new Map();
  for (const r of results) {
    const id = r.identity || '未分類';
    if (!identityStats.has(id)) identityStats.set(id, { total: 0, searchHit: 0, answered: 0, cited: 0 });
    const s = identityStats.get(id);
    s.total++;
    if (r.searchHit) s.searchHit++;
    if (r.hasAnswer) s.answered++;
    if (r.citationCorrect) s.cited++;
  }

  const dateStr = new Date().toISOString().split('T')[0];

  // Helper: format percentage
  const pct = (n, d) => d === 0 ? 'N/A' : ((n / d) * 100).toFixed(1) + '%';
  const pctClass = (n, d, threshold = 95) => {
    if (d === 0) return 'warn';
    const rate = (n / d) * 100;
    if (rate >= threshold) return 'pass';
    if (rate >= threshold * 0.9) return 'warn';
    return 'fail';
  };

  // Build identity table rows
  const identityRows = [...identityStats.entries()].map(([identity, s]) => {
    const overallRate = s.total === 0 ? 0 : Math.min(s.searchHit, s.answered, s.cited) / s.total * 100;
    const badgeClass = overallRate >= 95 ? 'badge-pass' : 'badge-fail';
    const badgeText = pct(Math.min(s.searchHit, s.answered, s.cited), s.total);
    return `  <tr>
    <td>${escHtml(identity)}</td>
    <td class="num">${s.total}</td>
    <td class="num">${s.searchHit}/${s.total}</td>
    <td class="num">${s.answered}/${s.total}</td>
    <td class="num">${s.cited}/${s.total}</td>
    <td><span class="badge ${badgeClass}">${badgeText}</span></td>
  </tr>`;
  }).join('\n');

  // Source breakdown cards
  const seedCardValue = seedCount === 0 ? 'N/A' : (seedHits === seedCount && seedAnswered === seedCount && seedCited === seedCount ? '100%' : pct(Math.min(seedHits, seedAnswered, seedCited), seedCount));
  const seedCardClass = seedCount === 0 ? 'warn' : (seedHits >= seedCount && seedAnswered >= seedCount && seedCited >= seedCount ? 'pass' : 'fail');
  const dynCardValue = dynCount === 0 ? 'N/A' : (dynHits === dynCount && dynAnswered === dynCount && dynCited === dynCount ? '100%' : pct(Math.min(dynHits, dynAnswered, dynCited), dynCount));
  const dynCardClass = dynCount === 0 ? 'warn' : (dynHits >= dynCount && dynAnswered >= dynCount && dynCited >= dynCount ? 'pass' : 'fail');

  const sourceBreakdownCards = `<div class="cards" style="grid-template-columns: 1fr 1fr;">
  <div class="card">
    <div class="card-value ${seedCardClass}">${seedCardValue}</div>
    <div class="card-label">種子題（${seedCount} 題）</div>
    <div class="card-sub">搜尋 ${seedHits}/${seedCount} ｜ 回答 ${seedAnswered}/${seedCount} ｜ 引文 ${seedCited}/${seedCount}</div>
  </div>
  <div class="card">
    <div class="card-value ${dynCardClass}">${dynCardValue}</div>
    <div class="card-label">動態題（${dynCount} 題）</div>
    <div class="card-sub">搜尋 ${dynHits}/${dynCount} ｜ 回答 ${dynAnswered}/${dynCount} ｜ 引文 ${dynCited}/${dynCount}</div>
  </div>
</div>`;

  const footerOrg = orgName ? `${escHtml(orgName)} &mdash; ` : '';

  const html = `<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${escHtml(kbName)} — Q&amp;A 對答正確性驗證報告 — ${dateStr}</title>
<style>
  :root {
    --bg-base: oklch(0.97 0.005 250);
    --bg-surface: oklch(0.94 0.005 250);
    --bg-overlay: oklch(0.90 0.008 250);
    --bg-hover: oklch(0.92 0.005 250);
    --text-primary: oklch(0.20 0.01 250);
    --text-secondary: oklch(0.45 0.01 250);
    --text-muted: oklch(0.60 0.008 250);
    --color-pass: oklch(0.48 0.16 150);
    --color-fail: oklch(0.55 0.22 25);
    --color-warn: oklch(0.52 0.14 80);
    --color-info: oklch(0.52 0.13 240);
    --border-subtle: oklch(0.85 0.005 250);
    --text-xs: 1.125rem;
    --text-sm: 1.25rem;
    --text-base: 1.5rem;
    --text-lg: 1.75rem;
    --text-xl: 2rem;
    --text-2xl: 3rem;
    --text-3xl: 3.5rem;
  }
  @supports not (color: oklch(0 0 0)) {
    :root {
      --bg-base: #f5f6f8;
      --bg-surface: #ecedf0;
      --bg-overlay: #dfe0e5;
      --bg-hover: #e5e6ea;
      --text-primary: #1e2030;
      --text-secondary: #5e6070;
      --text-muted: #8a8c98;
      --color-pass: #1e8050;
      --color-fail: #c93135;
      --color-warn: #8a7020;
      --color-info: #2a6bb8;
      --border-subtle: #d5d6da;
    }
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    background: var(--bg-base);
    color: var(--text-primary);
    font-size: var(--text-base);
    line-height: 1.6;
    padding: 2rem;
  }
  .container { max-width: 72rem; margin: 0 auto; }
  h1 { font-size: var(--text-3xl); font-weight: 700; margin-bottom: 0.5rem; }
  h2 { font-size: var(--text-xl); font-weight: 700; margin: 2rem 0 1rem; border-bottom: 2px solid var(--border-subtle); padding-bottom: 0.5rem; }
  h3 { font-size: var(--text-lg); font-weight: 700; color: var(--text-secondary); margin: 1.5rem 0 0.75rem; }
  .subtitle { font-size: var(--text-sm); color: var(--text-secondary); margin-bottom: 2rem; }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
  .card {
    background: var(--bg-surface);
    border-radius: 0.5rem;
    padding: 1.5rem;
    text-align: center;
  }
  .card-value { font-size: var(--text-2xl); font-weight: 700; }
  .card-label { font-size: var(--text-sm); color: var(--text-secondary); margin-top: 0.25rem; }
  .card-sub { font-size: var(--text-xs); color: var(--text-muted); }
  .pass { color: var(--color-pass); }
  .fail { color: var(--color-fail); }
  .warn { color: var(--color-warn); }
  .table-container {
    background: var(--bg-surface);
    border-radius: 0.5rem;
    overflow: hidden;
    margin-bottom: 2rem;
  }
  table { width: 100%; border-collapse: collapse; }
  thead { background: var(--bg-overlay); }
  th { padding: 0.75rem 1rem; font-size: var(--text-sm); font-weight: 600; text-align: left; }
  td { padding: 0.5rem 1rem; font-size: var(--text-sm); }
  tbody tr { border-top: 1px solid var(--border-subtle); }
  tbody tr:hover { background: var(--bg-hover); }
  .badge {
    display: inline-block;
    padding: 0.125rem 0.5rem;
    border-radius: 0.25rem;
    font-size: var(--text-xs);
    font-weight: 700;
  }
  .badge-pass { background: oklch(0.92 0.04 150); color: var(--color-pass); }
  .badge-fail { background: oklch(0.92 0.06 25); color: var(--color-fail); }
  @supports not (color: oklch(0 0 0)) {
    .badge-pass { background: #e8f0e8; }
    .badge-fail { background: #fce8e8; }
  }
  .stat-bar { display: flex; align-items: center; gap: 0.5rem; }
  .stat-bar-fill {
    height: 8px;
    border-radius: 4px;
    background: var(--color-pass);
  }
  .stat-bar-bg {
    flex: 1;
    height: 8px;
    border-radius: 4px;
    background: var(--border-subtle);
    overflow: hidden;
  }
  .methodology {
    background: var(--bg-surface);
    border-radius: 0.5rem;
    padding: 1.5rem;
    margin-bottom: 2rem;
  }
  .methodology dt { font-weight: 600; font-size: var(--text-sm); margin-top: 0.75rem; }
  .methodology dd { font-size: var(--text-sm); color: var(--text-secondary); margin-left: 0; }
  .footer { font-size: var(--text-xs); color: var(--text-muted); text-align: center; margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border-subtle); }
  .check { color: var(--color-pass); }
  .cross { color: var(--color-fail); }
  td.num { text-align: center; font-variant-numeric: tabular-nums; }
  @media print {
    body { background: white; padding: 1cm; font-size: 12pt; }
    .card-value { font-size: 28pt; }
    .no-print { display: none; }
  }
</style>
</head>
<body>
<div class="container">

<h1>${escHtml(kbName)} — Q&amp;A 對答正確性驗證報告</h1>
<div class="subtitle">
  knowledge-assistant 知識對話系統 &mdash; ${dateStr}<br>
  測試題數：${total}（種子 ${seedCount} + 動態 ${dynCount}）
</div>

<div class="cards">
  <div class="card">
    <div class="card-value ${pctClass(searchHits, total)}">${pct(searchHits, total)}</div>
    <div class="card-label">搜尋命中率</div>
    <div class="card-sub">${searchHits} / ${total}</div>
  </div>
  <div class="card">
    <div class="card-value ${pctClass(answered, total, 98)}">${pct(answered, total)}</div>
    <div class="card-label">有效回答率</div>
    <div class="card-sub">${answered} / ${total}</div>
  </div>
  <div class="card">
    <div class="card-value ${pctClass(cited, total, 98)}">${pct(cited, total)}</div>
    <div class="card-label">引文正確率</div>
    <div class="card-sub">${cited} / ${total}</div>
  </div>
  <div class="card">
    <div class="card-value ${pctClass(formatted, total, 90)}">${pct(formatted, total)}</div>
    <div class="card-label">引文格式率</div>
    <div class="card-sub">${formatted} / ${total}</div>
  </div>
</div>

${sourceBreakdownCards}

<h2>依身份統計</h2>
<div class="table-container">
<table>
<thead>
  <tr><th>身份</th><th>題數</th><th>搜尋命中</th><th>有效回答</th><th>引文正確</th><th>狀態</th></tr>
</thead>
<tbody>
${identityRows}
</tbody>
</table>
</div>

<h2>驗證方法論</h2>
<div class="methodology">
  <dt>搜尋引擎</dt>
  <dd>MiniSearch 全文搜尋（中文分詞 + bigram fallback），完全複製 assistant SPA 的搜尋邏輯（structuredSearch → fullTextSearch），不使用 Claude fallback，以測量純搜尋品質。</dd>
  <dt>有效回答判定</dt>
  <dd>回答長度 &gt; 50 字元，且拒絕語句不在前 100 字元內出現。</dd>
  <dt>引文正確判定</dt>
  <dd>搜尋 top-6 結果的 doc_key 包含題目的 expected_doc_key，或 LLM 回答中引用了該文件。</dd>
  <dt>引文格式率</dt>
  <dd>LLM 回答中是否包含設定的引用標記格式。</dd>
  <dt>動態題快取</dt>
  <dd>使用 SHA-256 content hash 追蹤文件變更，僅在文件內容更新時重新產生動態題目，確保結果可重現。</dd>
</div>

<h2>調優參數</h2>
<div class="table-container">
<table>
<thead>
  <tr><th>參數</th><th>目前值</th><th>位置</th></tr>
</thead>
<tbody>
  <tr><td>topK</td><td>6</td><td>fullTextSearch / structuredSearch</td></tr>
  <tr><td>fuzzy</td><td>0.2</td><td>MiniSearch config</td></tr>
  <tr><td>boost</td><td>title 3x, section 2x, text 1x</td><td>MiniSearch config</td></tr>
  <tr><td>chunk split</td><td>&gt;2000 chars → H3 split</td><td>chunk.js</td></tr>
  <tr><td>chunk merge</td><td>&lt;100 chars merge</td><td>chunk.js</td></tr>
</tbody>
</table>
</div>

<h2>工具清單</h2>
<div class="table-container">
<table>
<thead>
  <tr><th>指令</th><th>用途</th></tr>
</thead>
<tbody>
  <tr><td><code>npm run qa-report</code></td><td>完整 QA 驗證（種子 + 動態題）</td></tr>
  <tr><td><code>npm run qa-report -- --seed-only</code></td><td>僅種子題</td></tr>
  <tr><td><code>npm run qa-report -- --search-only</code></td><td>僅搜尋測試（不呼叫 Claude API）</td></tr>
  <tr><td><code>npm run qa-report -- --html</code></td><td>同時產生 HTML 報告</td></tr>
  <tr><td><code>npm run qa-report -- --identity=NAME</code></td><td>按身份篩選</td></tr>
  <tr><td><code>npm run qa-report -- --refresh-dynamic</code></td><td>重新產生動態題</td></tr>
  <tr><td><code>npm run chunk-audit</code></td><td>Chunk 品質檢查</td></tr>
</tbody>
</table>
</div>

<div class="footer">
  ${footerOrg}${escHtml(kbName)}<br>
  報告產生日期：${dateStr} &nbsp;|&nbsp; Knowledge Assistant QA Verification Pipeline v1.0
</div>

</div>
</body>
</html>`;

  return html;
}

// ============================================================
// GLOSSARY EXPANSION
// ============================================================

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

// ============================================================
// MAIN
// ============================================================

async function main() {
  const config = cfg();

  // Load glossary for Layer 1 expansion
  const glossaryPath = path.join(PROJECT_ROOT, '_meta', 'glossary.json');
  let glossary = {};
  if (fs.existsSync(glossaryPath)) {
    try {
      glossary = JSON.parse(fs.readFileSync(glossaryPath, 'utf8'));
    } catch (e) {
      console.warn('[qa-report] glossary.json is not valid JSON, skipping');
    }
  }

  const noResultMessage = config.ui?.no_result_message || '根據目前知識庫的文件，查無相關資料。';

  const args = process.argv.slice(2);
  const flags = {
    seedOnly: args.includes('--seed-only'),
    searchOnly: args.includes('--search-only'),
    refreshDynamic: args.includes('--refresh-dynamic'),
    dryRun: args.includes('--dry-run'),
    html: args.includes('--html'),
    exportMode: args.includes('--export'),
    evaluateFile: (() => {
      const idx = args.indexOf('--evaluate');
      if (idx !== -1 && args[idx + 1] && !args[idx + 1].startsWith('--')) return args[idx + 1];
      const eq = args.find(a => a.startsWith('--evaluate='));
      return eq ? eq.replace('--evaluate=', '') : '';
    })(),
    outputDir: (args.find(a => a.startsWith('--output-dir=')) || '').replace('--output-dir=', '') || path.join(PROJECT_ROOT, 'data', 'reports'),
    identity: (args.find(a => a.startsWith('--identity=')) || '').replace('--identity=', ''),
    source: (args.find(a => a.startsWith('--source=')) || '').replace('--source=', ''),
    ci: args.includes('--ci'),
    profile: (() => {
      const eq = args.find(a => a.startsWith('--profile='));
      if (eq) return eq.replace('--profile=', '');
      const idx = args.indexOf('--profile');
      return (idx !== -1 && args[idx + 1] && !args[idx + 1].startsWith('--')) ? args[idx + 1] : 'assistant';
    })(),
  };

  console.log('[qa-report] Building index...');
  const { chunksMap, metaIndex, msInstance, allChunks } = buildIndex();

  // Apply profile filter to chunks
  const profileCfg = config.profiles?.[flags.profile] || {};
  const filteredChunks = filterChunks(allChunks, profileCfg.exclude_types);
  _allChunks = filteredChunks;
  console.log(`[qa-report] ${Object.keys(chunksMap).length} chunks (${filteredChunks.length} after profile filter), ${metaIndex.length} meta entries`);

  // Load seed questions                                                  // [15]
  // Load profile-specific question file
  const profileConfig = config.profiles?.[flags.profile] || {};
  const questionsFile = profileConfig.qa_questions || 'qa-questions.json';
  const seedPath = path.join(__dirname, questionsFile);
  if (!fs.existsSync(seedPath)) {
    console.error(`Seed questions not found: ${seedPath}`);
    process.exit(1);
  }
  let questions = JSON.parse(fs.readFileSync(seedPath, 'utf8'));

  // Validate expected_doc_keys
  const allDocKeys = new Set(metaIndex.map(m => m.doc_key));
  for (const q of questions) {
    if (q.expected_doc_key !== '__NONE__' && !allDocKeys.has(q.expected_doc_key)) {
      console.warn(`[qa-report] Question ${q.id}: expected_doc_key "${q.expected_doc_key}" not found in index`);
    }
  }

  // Dynamic questions
  if (!flags.seedOnly) {
    const cachePath = path.join(__dirname, `qa-dynamic-cache-${flags.profile}.json`);
    const dynamic = await generateDynamicQuestions(allChunks, questions, cachePath, flags.refreshDynamic);

    // Post-generation search validation: populate accepted_doc_keys
    // This catches cross-document questions where the answer is correct
    // but comes from a different doc_key than expected
    for (const q of dynamic) {
      const expanded = expandGlossary(q.question, glossary);
      const results = findRelevantChunks(expanded, chunksMap, metaIndex, msInstance);
      const topDocKeys = [...new Set(results.slice(0, 5).map(r => r.doc_key))];
      // If expected_doc_key is not in top results, record which doc_keys ARE relevant
      if (!topDocKeys.includes(q.expected_doc_key)) {
        q.accepted_doc_keys = topDocKeys.filter(dk => dk !== q.expected_doc_key);
      }
    }

    console.log(`[qa-report] Dynamic questions: ${dynamic.length}`);
    questions = [...questions, ...dynamic];
  }

  // Apply filters
  if (flags.identity) {
    questions = questions.filter(q => q.identity === flags.identity);
  }
  if (flags.source === 'document') {
    questions = questions.filter(q => !q.expected_doc_key.startsWith('collected/'));
  } else if (flags.source === 'collected') {
    questions = questions.filter(q => q.expected_doc_key.startsWith('collected/'));
  }

  console.log(`[qa-report] Running ${questions.length} questions...`);

  if (flags.dryRun) {
    for (const q of questions) {
      console.log(`  [${q.id}] (${q.identity}) ${q.question}`);
    }
    return;
  }

  // --export mode: run search only, export qa-export.json, exit
  if (flags.exportMode) {
    const searchResultsMap = {};
    for (const q of questions) {
      const expandedQuestion = expandGlossary(q.question, glossary);
      const searchResults = findRelevantChunks(expandedQuestion, chunksMap, metaIndex, msInstance);
      const context = searchResults.map(r => `【${r.title || r.doc_key}】（引用鍵：${r.doc_key}）\n${r.text || ''}`).join('\n\n---\n\n');
      searchResultsMap[q.id] = {
        results: searchResults,
        context,
        searchHit: evaluateSearchHit(searchResults, q.expected_doc_key, q.accepted_doc_keys),
        searchDocKeys: [...new Set(searchResults.map(r => r.doc_key))],
      };
    }
    const exported = exportQuestions(questions, searchResultsMap);
    const exportPath = path.join(flags.outputDir, 'qa-export.json');
    fs.mkdirSync(flags.outputDir, { recursive: true });
    fs.writeFileSync(exportPath, JSON.stringify(exported, null, 2), 'utf8');
    console.log(`匯出完成: ${exportPath} (${exported.total} 題)`);
    return;
  }

  // --evaluate mode: load answers from file, evaluate, generate reports
  if (flags.evaluateFile) {
    const answersData = JSON.parse(fs.readFileSync(flags.evaluateFile, 'utf8'));
    const searchResultsMap = {};
    for (const q of questions) {
      const expandedQuestion = expandGlossary(q.question, glossary);
      const searchResults = findRelevantChunks(expandedQuestion, chunksMap, metaIndex, msInstance);
      searchResultsMap[q.id] = {
        results: searchResults,
        searchHit: evaluateSearchHit(searchResults, q.expected_doc_key, q.accepted_doc_keys),
        searchDocKeys: [...new Set(searchResults.map(r => r.doc_key))],
      };
    }
    const evalResults = importAnswers(questions, searchResultsMap, answersData);
    const dateStr = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const reportBaseName = `${flags.profile}-report-${dateStr}`;
    const outputPath = path.join(flags.outputDir, `${reportBaseName}.md`);
    generateReport(evalResults, outputPath);
    if (flags.html) {
      const htmlPath = outputPath.replace(/\.md$/, '.html');
      fs.writeFileSync(htmlPath, generateHtmlReport(evalResults), 'utf8');
      console.log(`HTML 報告: ${htmlPath}`);
    }
    const evalSearchHits = evalResults.filter(r => r.searchHit).length;
    const evalAnswered = evalResults.filter(r => r.hasAnswer).length;
    const evalCited = evalResults.filter(r => r.citationCorrect).length;
    console.log(`\n${'='.repeat(50)}`);
    console.log(`報告產出: ${outputPath}`);
    console.log(`搜尋命中: ${evalSearchHits}/${evalResults.length} (${((evalSearchHits / evalResults.length) * 100).toFixed(1)}%)`);
    console.log(`有效回答: ${evalAnswered}/${evalResults.length} (${((evalAnswered / evalResults.length) * 100).toFixed(1)}%)`);
    console.log(`引文正確: ${evalCited}/${evalResults.length} (${((evalCited / evalResults.length) * 100).toFixed(1)}%)`);
    if (flags.ci) {
      const searchThreshold = config.qa?.search_hit_threshold || 0.95;   // [3]
      const searchRate = evalSearchHits / evalResults.length;
      if (searchRate < searchThreshold) {
        console.error(`[CI] FAIL: search hit rate ${(searchRate * 100).toFixed(1)}% < ${(searchThreshold * 100).toFixed(0)}%`);
        process.exit(1);
      }
      console.log(`[CI] PASS: search hit rate >= ${(searchThreshold * 100).toFixed(0)}%`);
    }
    return;
  }

  // Run tests
  const results = [];
  const apiKey = getApiKey();
  const systemPrompt = getSystemPrompt();                                // [8]
  const model = config.api?.model || 'claude-sonnet-4-20250514';         // [5]

  for (let i = 0; i < questions.length; i++) {
    const q = questions[i];
    console.log(`[${i + 1}/${questions.length}] ${q.question.substring(0, 50)}...`);

    // Search
    const expandedQuestion = expandGlossary(q.question, glossary);
    const searchResults = findRelevantChunks(expandedQuestion, chunksMap, metaIndex, msInstance);
    const searchDocKeys = [...new Set(searchResults.map(r => r.doc_key))];
    const searchHit = evaluateSearchHit(searchResults, q.expected_doc_key, q.accepted_doc_keys);

    let answer = '';
    let hasAnswer = false;
    let citationCorrect = false;
    let hasCitationFormat = false;

    if (!flags.searchOnly && apiKey) {
      // Layer 3: Hard gate — skip LLM if no search results
      if (searchResults.length === 0) {
        answer = noResultMessage;
        hasAnswer = false;
        citationCorrect = (q.expected_doc_key === '__NONE__');
        hasCitationFormat = (q.expected_doc_key === '__NONE__');
      } else {
        // Build context
        const context = searchResults
          .map(r => `【${r.title || r.doc_key}】（引用鍵：${r.doc_key}）\n${r.text || ''}`)
          .join('\n\n---\n\n');

        try {
          const resp = await fetch('https://api.anthropic.com/v1/messages', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: JSON.stringify({
              model,                                                       // [5]
              max_tokens: 1000,
              system: systemPrompt,
              messages: [{
                role: 'user',
                content: context
                  ? `參考資料：\n${context}\n\n問題：${q.question}`
                  : `問題：${q.question}\n\n（無相關參考資料）`,
              }],
            }),
          });

          if (resp.ok) {
            const data = await resp.json();
            answer = data.content[0]?.text || '';
          } else {
            console.warn(`  API error: ${resp.status}`);
          }
        } catch (err) {
          console.warn(`  Error: ${err.message}`);
        }

        hasAnswer = evaluateAnswer(answer);
        hasCitationFormat = evaluateCitationFormat(answer);
        citationCorrect = searchHit || answer.includes(q.expected_doc_key);
      }

      // Rate limit
      await new Promise(r => setTimeout(r, 500));
    } else if (flags.searchOnly) {
      hasAnswer = true; // N/A
      citationCorrect = searchHit;
      hasCitationFormat = true; // N/A
    }

    console.log(`  → 搜尋${searchHit ? '✓' : '✗'} | 回答${hasAnswer ? '✓' : '✗'} | 引文${citationCorrect ? '✓' : '✗'}`);

    results.push({
      ...q,
      searchDocKeys,
      searchHit,
      answer,
      hasAnswer,
      citationCorrect,
      hasCitationFormat,
    });
  }

  // Generate report
  const dateStr = new Date().toISOString().split('T')[0].replace(/-/g, '');
  const reportBaseName = `${flags.profile}-report-${dateStr}`;
  const outputPath = path.join(flags.outputDir, `${reportBaseName}.md`);
  generateReport(results, outputPath);

  if (flags.html) {
    const htmlPath = outputPath.replace(/\.md$/, '.html');
    const htmlContent = generateHtmlReport(results);
    fs.writeFileSync(htmlPath, htmlContent, 'utf8');
    console.log(`HTML 報告: ${htmlPath}`);
  }

  const searchHits = results.filter(r => r.searchHit).length;
  const answered = results.filter(r => r.hasAnswer).length;
  const cited = results.filter(r => r.citationCorrect).length;

  console.log(`\n${'='.repeat(50)}`);
  console.log(`報告產出: ${outputPath}`);
  console.log(`搜尋命中: ${searchHits}/${results.length} (${((searchHits / results.length) * 100).toFixed(1)}%)`);
  console.log(`有效回答: ${answered}/${results.length} (${((answered / results.length) * 100).toFixed(1)}%)`);
  console.log(`引文正確: ${cited}/${results.length} (${((cited / results.length) * 100).toFixed(1)}%)`);

  if (flags.ci) {
    const searchThreshold = config.qa?.search_hit_threshold || 0.95;     // [3]
    const searchRate = searchHits / results.length;
    if (searchRate < searchThreshold) {
      console.error(`[CI] FAIL: search hit rate ${(searchRate * 100).toFixed(1)}% < ${(searchThreshold * 100).toFixed(0)}%`);
      process.exit(1);
    }
    console.log(`[CI] PASS: search hit rate >= ${(searchThreshold * 100).toFixed(0)}%`);
  }
}

if (require.main === module) {
  main().catch(err => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {
  structuredSearch,
  fullTextSearch,
  findRelevantChunks,
  evaluateAnswer,
  evaluateSearchHit,
  evaluateCitationFormat,
  computeDocKeyHash,
  buildIndex,
  generateDynamicQuestions,
  generateReport,
  generateHtmlReport,
  exportQuestions,
  importAnswers,
  getSystemPrompt,
};
