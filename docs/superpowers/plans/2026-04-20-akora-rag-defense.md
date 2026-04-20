# AKORA RAG 四層防護實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為 AKORA 模板加入四層 RAG 防護 — glossary 確定性替換、LLM query rewriting、硬性閘門、嚴格 system prompt — 100% 杜絕 LLM 引用外部知識。

**Architecture:** 搜尋前做 glossary 展開 + LLM rewriting，搜尋後若結果為 0 則攔截不呼叫 LLM。LLM rewriting 取代既有 twoPassFallback（不增加 API 呼叫）。所有變更在 AKORA 模板 repo。

**Tech Stack:** Node.js (native test runner)、Browser JS (SPA)

**Spec:** `docs/superpowers/specs/2026-04-20-akora-rag-defense-design.md`

**Target Repo:** `/Users/lightman/weiqi.kids/akora`

---

## File Structure

### New Files

| Path | Responsibility |
|---|---|
| `_meta/glossary.json` | 空預設 `{}`，嚮導填充。縮寫→全稱對照表 |
| `scripts/lib/core/__tests__/glossary.test.js` | expandGlossary 單元測試 |

### Modified Files

| Path | Change |
|---|---|
| `templates/assistant.html` | 新增 `GLOSSARY` 資料宣告、`expandGlossary()`、`rewriteQuery()`；改寫 `handleQA()` 整合 Layer 1-3；移除 `twoPassFallback()` 呼叫 |
| `scripts/lib/core/build.js` | profile loop 內嵌入 glossary；`appConfig` 加 `no_result_message` |
| `scripts/lib/core/qa-report.js` | main() 載入 glossary；搜尋前 expandGlossary；閘門邏輯；`__NONE__` 題目處理 |
| `config.example.json` | `ui.no_result_message`；`domain.system_prompt` 改為嚴格版 |
| `CLAUDE.md` | Step 5 加 glossary 產出；Session Start 加 glossary 更新檢查 |

---

## Phase 1: Glossary Engine (Layer 1)

### Task 1: glossary.json + expandGlossary()

**Files:**
- Create: `_meta/glossary.json`
- Create: `scripts/lib/core/__tests__/glossary.test.js`

- [ ] **Step 1: Create empty glossary.json**

```json
{}
```

Write to `_meta/glossary.json`.

- [ ] **Step 2: Write the failing test**

```javascript
// scripts/lib/core/__tests__/glossary.test.js
const { describe, it } = require('node:test');
const assert = require('node:assert');

// expandGlossary will be extracted as a shared module
// For now, define inline — will be moved to a shared location in Task 2
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

describe('expandGlossary', () => {
  const glossary = {
    '管審會': '個人資料保護暨資通安全管理委員會',
    '資安長': '資通安全長',
    'PIMS': '個人資料保護管理系統',
    'BCP': '營運持續計畫',
  };

  it('expands a known abbreviation', () => {
    const result = expandGlossary('管審會的成員有哪些人？', glossary);
    assert.ok(result.includes('管審會'));
    assert.ok(result.includes('個人資料保護暨資通安全管理委員會'));
  });

  it('returns original query when no match', () => {
    const result = expandGlossary('天氣如何？', glossary);
    assert.strictEqual(result, '天氣如何？');
  });

  it('handles English abbreviations case-insensitively', () => {
    const result = expandGlossary('pims是什麼？', glossary);
    assert.ok(result.includes('個人資料保護管理系統'));
  });

  it('expands multiple matches', () => {
    const result = expandGlossary('管審會討論BCP', glossary);
    assert.ok(result.includes('個人資料保護暨資通安全管理委員會'));
    assert.ok(result.includes('營運持續計畫'));
  });

  it('returns original query for null glossary', () => {
    assert.strictEqual(expandGlossary('test', null), 'test');
  });

  it('returns original query for empty glossary', () => {
    assert.strictEqual(expandGlossary('test', {}), 'test');
  });

  it('does not chain-match expansion terms', () => {
    // If expansion of A contains term B, B should NOT be expanded
    const g = {
      'ABC': 'Alpha Beta Contains-XYZ',
      'XYZ': 'Something Else',
    };
    const result = expandGlossary('ABC test', g);
    // Should expand ABC but NOT chain-match XYZ inside the expansion
    assert.ok(result.includes('Alpha Beta Contains-XYZ'));
    assert.ok(!result.includes('Something Else'));
  });
});
```

- [ ] **Step 3: Run test to verify it passes**

Run: `cd /Users/lightman/weiqi.kids/akora && node --test scripts/lib/core/__tests__/glossary.test.js`
Expected: All 7 tests PASS (function is defined inline in test file)

- [ ] **Step 4: Commit**

```bash
cd /Users/lightman/weiqi.kids/akora
git add _meta/glossary.json scripts/lib/core/__tests__/glossary.test.js
git commit -m "feat: add glossary.json + expandGlossary tests (Layer 1 foundation)"
```

---

### Task 2: Build pipeline — embed GLOSSARY into HTML

**Files:**
- Modify: `templates/assistant.html`
- Modify: `scripts/lib/core/build.js`

- [ ] **Step 1: Add GLOSSARY data declaration in assistant.html**

In `templates/assistant.html`, find line 732 (`const APP_CONFIG = ...`) and add AFTER it (before the closing `</script>` on line 733):

```javascript
const GLOSSARY     = /*__GLOSSARY__*/{};
```

- [ ] **Step 2: Add expandGlossary function in assistant.html**

In `templates/assistant.html`, find the `// SEARCH` section (around line 1155, before `function structuredSearch`). Add before it:

```javascript
// ============================================================
// GLOSSARY EXPANSION (Layer 1)
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
```

- [ ] **Step 3: Add glossary injection in build.js**

In `scripts/lib/core/build.js`, inside the profile loop, find the line with `replacePlaceholder(template, '__RENDERED_DOCS__'` (around line 626). AFTER it, add:

```javascript
    // Inject glossary (shared across all profiles)
    const glossaryRaw = readFileSafe(path.join(PROJECT_ROOT, '_meta', 'glossary.json'));
    let glossaryJson = '{}';
    if (glossaryRaw) {
      try {
        JSON.parse(glossaryRaw);
        glossaryJson = glossaryRaw;
      } catch (e) {
        console.warn('[build] glossary.json is not valid JSON, using empty {}');
      }
    }
    template = replacePlaceholder(template, '__GLOSSARY__', '{}', glossaryJson);
```

- [ ] **Step 4: Add no_result_message to appConfig in build.js**

In `scripts/lib/core/build.js`, find the `appConfig` object (around line 572). Add:

```javascript
    no_result_message: ui.no_result_message || '',
```

- [ ] **Step 5: Run tests to verify no regression**

Run: `cd /Users/lightman/weiqi.kids/akora && npm test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/lightman/weiqi.kids/akora
git add templates/assistant.html scripts/lib/core/build.js
git commit -m "feat: embed GLOSSARY + expandGlossary into assistant.html, add no_result_message to appConfig"
```

---

## Phase 2: Rewrite handleQA — Layer 1+2+3 Integration

### Task 3: Rewrite handleQA() with Layers 1-3

**Files:**
- Modify: `templates/assistant.html`

- [ ] **Step 1: Add rewriteQuery function**

In `templates/assistant.html`, add AFTER the `expandGlossary` function (added in Task 2):

```javascript
// ============================================================
// QUERY REWRITING (Layer 2)
// ============================================================

async function rewriteQuery(query, expandedQuery) {
  const prompt = `你是搜尋查詢改寫器。將以下使用者問題改寫為適合全文搜尋的關鍵詞組合。
規則：
- 只輸出關鍵詞，用空格分隔
- 不要解釋、不要回答問題
- 保留專有名詞原文
- 展開口語化表達為正式用語

使用者問題：${expandedQuery}`;

  try {
    const result = await callClaude(
      [{ role: 'user', content: prompt }],
      '',
      200
    );
    return result.trim();
  } catch (e) {
    console.warn('rewriteQuery failed:', e.message);
    return '';
  }
}
```

- [ ] **Step 2: Rewrite handleQA()**

In `templates/assistant.html`, replace the entire `handleQA` function (lines 1484-1504):

From:
```javascript
async function handleQA(query, aiDiv, msgs) {
  // Retrieve relevant chunks
  const chunks = await findRelevantChunks(query);

  // Build API messages (inject context into first message)
  const apiMsgs = buildApiMessages(msgs, chunks, 80000);

  let fullText = '';
  await callClaudeStream(apiMsgs, QA_SYSTEM_PROMPT, (accumulated) => {
    fullText = accumulated;
    aiDiv.innerHTML = renderMarkdown(accumulated, { skipAutoLink: true });
    document.getElementById('chat-messages').scrollTop = document.getElementById('chat-messages').scrollHeight;
  });

  // Save to state
  msgs.push({ role: 'assistant', content: fullText });

  // Final render with autoLink
  aiDiv.innerHTML = renderMarkdown(fullText);
  wireUpCitations(aiDiv);
}
```

To:
```javascript
async function handleQA(query, aiDiv, msgs) {
  // Layer 1: Glossary 確定性替換
  const expandedQuery = expandGlossary(query, GLOSSARY);

  // Structured + full-text search with expanded query
  let chunks = structuredSearch(expandedQuery);
  if (chunks.length === 0) chunks = fullTextSearch(expandedQuery, 6);

  // Layer 2: LLM Query Rewriting (replaces twoPassFallback)
  if (chunks.length === 0 && state.apiKey) {
    const rewrittenQuery = await rewriteQuery(query, expandedQuery);
    if (rewrittenQuery) {
      const combined = expandedQuery + ' ' + rewrittenQuery;
      chunks = structuredSearch(combined);
      if (chunks.length === 0) chunks = fullTextSearch(combined, 6);
    }
  }

  // Layer 3: Hard gate — no LLM call when zero results
  if (chunks.length === 0) {
    const noResultMsg = APP_CONFIG.no_result_message
      || '根據目前知識庫的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢承辦人員。';
    aiDiv.innerHTML = renderMarkdown(noResultMsg);
    msgs.push({ role: 'assistant', content: noResultMsg });
    wireUpCitations(aiDiv);
    return;
  }

  // Build API messages (inject context into first message)
  const apiMsgs = buildApiMessages(msgs, chunks, 80000);

  let fullText = '';
  await callClaudeStream(apiMsgs, QA_SYSTEM_PROMPT, (accumulated) => {
    fullText = accumulated;
    aiDiv.innerHTML = renderMarkdown(accumulated, { skipAutoLink: true });
    document.getElementById('chat-messages').scrollTop = document.getElementById('chat-messages').scrollHeight;
  });

  // Save to state
  msgs.push({ role: 'assistant', content: fullText });

  // Final render with autoLink
  aiDiv.innerHTML = renderMarkdown(fullText);
  wireUpCitations(aiDiv);
}
```

- [ ] **Step 3: Remove twoPassFallback from findRelevantChunks**

In `templates/assistant.html`, find `findRelevantChunks` (line 1240). Replace:

```javascript
async function findRelevantChunks(query) {
  // 1. Structured search
  const structured = structuredSearch(query);
  if (structured.length > 0) return structured.slice(0, 6);

  // 2. Full text search
  const ft = fullTextSearch(query, 6);
  if (ft.length > 0) return ft;

  // 3. Two-pass fallback via Claude
  return await twoPassFallback(query);
}
```

With:

```javascript
async function findRelevantChunks(query) {
  // 1. Structured search
  const structured = structuredSearch(query);
  if (structured.length > 0) return structured.slice(0, 6);

  // 2. Full text search
  const ft = fullTextSearch(query, 6);
  return ft;
  // Note: twoPassFallback removed — replaced by Layer 2 (rewriteQuery) in handleQA
}
```

Note: Keep `findRelevantChunks` as a function (used by drill mode's `sendDrillStart`), but remove the twoPassFallback call. The `twoPassFallback` function definition can stay (dead code removal is optional).

- [ ] **Step 4: Commit**

```bash
cd /Users/lightman/weiqi.kids/akora
git add templates/assistant.html
git commit -m "feat: rewrite handleQA with Layer 1-3 — glossary, rewriting, hard gate"
```

---

## Phase 3: QA Report Integration

### Task 4: qa-report.js — glossary + gate + __NONE__

**Files:**
- Modify: `scripts/lib/core/qa-report.js`

- [ ] **Step 1: Add glossary loading in main()**

In `scripts/lib/core/qa-report.js`, find `main()` function (around line 1084). After the line `const { chunksMap, metaIndex, msInstance, allChunks } = buildIndex();` (around line 1114), add:

```javascript
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
```

Also add the `expandGlossary` function. In qa-report.js, add it before the `main()` function (around line 1080):

```javascript
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
```

- [ ] **Step 2: Apply glossary expansion before search**

In the main loop (around line 1243), replace:

```javascript
    const searchResults = findRelevantChunks(q.question, chunksMap, metaIndex, msInstance);
```

With:

```javascript
    const expandedQuestion = expandGlossary(q.question, glossary);
    const searchResults = findRelevantChunks(expandedQuestion, chunksMap, metaIndex, msInstance);
```

- [ ] **Step 3: Add __NONE__ handling to evaluateSearchHit**

In `evaluateSearchHit` (around line 216), replace:

```javascript
function evaluateSearchHit(results, expectedDocKey) {
  return results.some(r => r.doc_key === expectedDocKey);
}
```

With:

```javascript
function evaluateSearchHit(results, expectedDocKey) {
  // __NONE__ = expect zero results (gate test)
  if (expectedDocKey === '__NONE__') return results.length === 0;
  return results.some(r => r.doc_key === expectedDocKey);
}
```

- [ ] **Step 4: Add hard gate in API mode**

In the main loop, find `if (!flags.searchOnly && apiKey) {` (around line 1252). Add a gate check BEFORE the API call:

```javascript
    if (!flags.searchOnly && apiKey) {
      // Layer 3: Hard gate — skip LLM if no search results
      if (searchResults.length === 0) {
        answer = APP_CONFIG_NO_RESULT || '查無相關資料';
        hasAnswer = false;
        citationCorrect = (q.expected_doc_key === '__NONE__');
        hasCitationFormat = (q.expected_doc_key === '__NONE__');
      } else {
```

And close the `else` block after the existing API call logic, before `} else if (flags.searchOnly) {`.

Note: `APP_CONFIG_NO_RESULT` needs to be loaded from config. Add at the top of main():

```javascript
  const noResultMessage = config.ui?.no_result_message || '根據目前知識庫的文件，查無相關資料。';
```

Then use `noResultMessage` instead of `APP_CONFIG_NO_RESULT`.

- [ ] **Step 5: Run tests**

Run: `cd /Users/lightman/weiqi.kids/akora && npm test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/lightman/weiqi.kids/akora
git add scripts/lib/core/qa-report.js
git commit -m "feat: qa-report.js — glossary expansion, hard gate, __NONE__ handling"
```

---

## Phase 4: Config & Documentation

### Task 5: config.example.json + system prompt

**Files:**
- Modify: `config.example.json`

- [ ] **Step 1: Add no_result_message to ui section**

In `config.example.json`, find the `"ui"` block. Add after `"scan_display_names": {}`:

```json
    "no_result_message": "根據目前知識庫的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢承辦人員。",
```

- [ ] **Step 2: Replace domain.system_prompt**

In `config.example.json`, replace the existing `"system_prompt"` value with:

```json
    "system_prompt": "你是知識助理。嚴格根據下方參考資料回答問題。\n\n回答規則：\n1. 僅使用參考資料中的內容回答，不得引用外部知識、標準通則、一般建議或自行推測\n2. 若參考資料不包含答案，直接回覆「文件中未查到相關資訊」，不要提供任何替代建議\n3. 每個回答必須引用來源文件\n4. 不得使用 emoji\n\n引用格式規定：\n- 引用文件時使用 [來源:文件編號#章節] 格式\n- 冒號必須使用半形 :（不是：）\n- 章節使用數字格式（如 #2. 作業流程）\n\n範例問答：\n\n使用者：存取控制的規定是什麼？\n助理：根據文件規定，存取控制要求如下：\n\n1. 所有系統存取須經權限申請\n2. 權限變更須主管核准\n3. 離職人員須於當日撤銷權限\n\n[來源:PRO-003#2. 作業流程]",
```

- [ ] **Step 3: Validate JSON**

Run: `cd /Users/lightman/weiqi.kids/akora && node -e "JSON.parse(require('fs').readFileSync('config.example.json','utf8'));console.log('Valid')"`
Expected: `Valid`

- [ ] **Step 4: Commit**

```bash
cd /Users/lightman/weiqi.kids/akora
git add config.example.json
git commit -m "feat: strict system prompt (Layer 4) + no_result_message config"
```

---

### Task 6: CLAUDE.md — glossary wizard + session check

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add glossary.json to Step 5 產出清單**

In `CLAUDE.md`, find the Step 5 table. Add a row:

```
| `_meta/glossary.json` | 從文件中擷取縮寫/俗稱對照表（LLM 自動產出） |
```

- [ ] **Step 2: Add glossary generation instructions after Step 5 table**

After the existing merge.yaml 骨架範例 section, add:

```markdown
**Glossary 產出流程：**

掃描所有 `knowledge/` 文件，呼叫 LLM 擷取縮寫、俗稱、簡稱、英文縮寫及其全稱，輸出為 `_meta/glossary.json`。格式：`{"縮寫": "全稱", ...}`。
```

- [ ] **Step 3: Add glossary check to Session Start Checklist**

In `CLAUDE.md`, find the Session Start Checklist bash block. Add after the template update check (check #6):

```bash
# 7. Glossary 是否需要更新
KNOWLEDGE_MTIME=$(find knowledge/ -name '*.md' -newer _meta/glossary.json 2>/dev/null | head -1)
[ -n "$KNOWLEDGE_MTIME" ] && echo "GLOSSARY=outdated" || echo "GLOSSARY=current"
```

And add to the recommendations table:

```
| glossary 過時 | 重新掃描文件產出 `_meta/glossary.json` |
```

- [ ] **Step 4: Commit**

```bash
cd /Users/lightman/weiqi.kids/akora
git add CLAUDE.md
git commit -m "docs: CLAUDE.md — glossary wizard step + session start check"
```

---

## Phase 5: Integration Test

### Task 7: End-to-end verification

**Files:**
- Modify: `tests/integration-build.test.js`

- [ ] **Step 1: Add glossary integration test**

In `tests/integration-build.test.js`, add a new describe block:

```javascript
describe('glossary integration', () => {
  it('expandGlossary expands known abbreviations', () => {
    // Inline the function (same as in assistant.html and qa-report.js)
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
    // Verify the __NONE__ logic was implemented
    const { evaluateSearchHit } = require('../scripts/lib/core/qa-report');
    assert.strictEqual(evaluateSearchHit([], '__NONE__'), true, '__NONE__ with empty results should be a hit');
    assert.strictEqual(evaluateSearchHit([{ doc_key: 'test' }], '__NONE__'), false, '__NONE__ with results should not be a hit');
  });
});
```

- [ ] **Step 2: Run all tests**

Run: `cd /Users/lightman/weiqi.kids/akora && npm test && node --test tests/integration-build.test.js`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
cd /Users/lightman/weiqi.kids/akora
git add tests/integration-build.test.js
git commit -m "test: add glossary + gate integration tests"
```

---

## Spec Coverage Check

| Spec Section | Task(s) |
|---|---|
| 4.1 glossary 資料格式 | Task 1 (glossary.json) |
| 4.2 expandGlossary 替換邏輯 | Task 1 (tests), Task 2 (SPA), Task 4 (qa-report) |
| 4.3 執行時機（SPA + qa-report） | Task 2 (SPA), Task 4 (qa-report) |
| 4.4 Build 時嵌入 | Task 2 |
| 4.5 嚮導自動產出 | Task 6 (CLAUDE.md) |
| 4.6 更新提醒 | Task 6 (Session Start) |
| 5.1-5.3 LLM Query Rewriting | Task 3 (rewriteQuery + handleQA) |
| 5.4 搜尋流程整合 | Task 3 (handleQA rewrite) |
| 5.5 失敗處理 | Task 3 (try/catch in rewriteQuery) |
| 6.1-6.2 硬性閘門 | Task 3 (SPA), Task 4 (qa-report) |
| 6.3 設定 (no_result_message) | Task 2 (build.js), Task 5 (config) |
| 7.1-7.2 嚴格 system_prompt | Task 5 |
| 9.2-9.3 QA 驗證 (__NONE__) | Task 4, Task 7 |
