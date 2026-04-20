# AKORA RAG 四層防護設計

## 1. 問題陳述

AKORA 知識助理在搜尋無結果時，LLM 會使用訓練知識自由發揮（例如引用 ISO 標準通則、給出一般性建議），違反「僅根據文件回答」的原則。此外，使用者常用縮寫或俗稱查詢（如「管審會」），但文件中使用全稱（如「個人資料保護暨資通安全管理委員會」），導致搜尋失敗。

## 2. 設計目標

- 100% 杜絕 LLM 引用外部知識
- 提升搜尋召回率（縮寫、俗稱、同義詞）
- 所有機制在 AKORA 模板層實作，下游實例透過 config 配置
- 嚮導建立專案時自動產出初始 glossary

## 3. 架構總覽

```
用戶查詢
  │
  ├─ Layer 1: Glossary 確定性替換（SPA + qa-report.js）
  │   零成本、零延遲、確定性
  │
  ├─ Layer 2: LLM Query Rewriting（僅 SPA）
  │   ~100 tokens、處理未知表達
  │   取代既有 twoPassFallback，不增加 API 呼叫次數
  │
  ├─ Layer 3: 硬性閘門（SPA + qa-report.js）
  │   搜尋結果數 = 0 → 固定回覆、不呼叫 LLM
  │
  └─ Layer 4: 嚴格 System Prompt（SPA + qa-report.js）
      僅根據參考資料回答、禁止外部知識
```

四層各自獨立，任一層故障不影響其他層的防護效果。

### 3.1 與既有搜尋三階段的關係

現有 `findRelevantChunks()` 有三個搜尋階段：

1. **Structured search** — 正則比對 control ID / doc ID
2. **Full-text search** — MiniSearch 全文搜尋
3. **Two-pass fallback** — 呼叫 Claude 從 META_INDEX 選取 chunk_id

本設計對第三階段（twoPassFallback）做以下調整：

- **SPA**：Layer 2（LLM Query Rewriting）**取代** twoPassFallback。原因：兩者都呼叫 Claude，但 rewriting 在搜尋前進行（改善搜尋詞），效果優於 twoPassFallback（從索引中猜測 chunk）。取代後不增加 API 呼叫次數。
- **qa-report.js**：維持現狀（不呼叫 twoPassFallback，也不呼叫 LLM rewriting）。`--search-only` 模式完全不需要 API key。

## 4. Layer 1 — Glossary 確定性替換

### 4.1 資料格式

檔案路徑：`scripts/lib/core/glossary.json`（與 `qa-questions.json` 同層）

```json
{
  "管審會": "個人資料保護暨資通安全管理委員會",
  "資安長": "資通安全長",
  "PIMS": "個人資料保護管理系統",
  "BCP": "營運持續計畫"
}
```

鍵為縮寫/俗稱，值為文件中使用的全稱。一對一映射，不支援一對多（一個縮寫只對應一個展開）。

### 4.2 替換邏輯

```javascript
function expandGlossary(query, glossary) {
  if (!glossary || typeof glossary !== 'object') return query;
  const expansions = [];
  // 按鍵長度降序排列，避免短詞先匹配導致長詞被截斷
  const sorted = Object.entries(glossary)
    .sort((a, b) => b[0].length - a[0].length);
  for (const [term, expansion] of sorted) {
    // 僅比對原始查詢（不比對已附加的展開詞），避免連鎖誤匹配
    // 英文縮寫使用不區分大小寫的比對
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

**邊界情況處理：**
- **空 glossary**：`glossary` 為 null、undefined 或空物件時直接回傳原始 query
- **連鎖誤匹配**：只比對原始 `query`（不比對已附加的展開詞），避免展開詞中的子字串觸發二次匹配
- **英文大小寫**：`"pims"` 查詢能匹配 `"PIMS"` 鍵

設計決策：**附加**展開詞而非替換原始詞。原因：
- 使用者用「管審會」查詢，搜尋索引中可能同時有縮寫和全稱
- 附加方式讓 MiniSearch 同時匹配兩者，提升召回率
- 替換方式會丟失原始詞的匹配機會

### 4.3 執行時機

- **SPA（assistant.html）**：`handleQA()` 中，呼叫 `findRelevantChunks()` 之前。具體位置：在 `const chunks = await findRelevantChunks(query)` 之前，將 `query` 替換為 `expandGlossary(query, GLOSSARY)` 的結果。
- **QA 驗證（qa-report.js）**：在 main loop 中每道題目呼叫 `findRelevantChunks()` 之前，先做 `expandGlossary(q.question, glossary)`。glossary 從 `scripts/lib/core/glossary.json` 直接讀取（`JSON.parse(readFileSafe(...))`），不依賴 build。
- **`--search-only` 模式**：Layer 1 是純字串操作，完全可用，不需要 API key。

兩處使用同一份 glossary 資料，確保 QA 測試結果與實際使用一致。

### 4.4 Build 時嵌入

`build.js` 在 profile loop 中（Step 6 — Assemble HTML from template，位於現有 `replacePlaceholder` 區段，約 build.js:620 行之後），新增 glossary 嵌入：

```javascript
// 在 replacePlaceholder(__RENDERED_DOCS__) 之後
const glossaryRaw = readFileSafe(path.join(PROJECT_ROOT, 'scripts', 'lib', 'core', 'glossary.json'));
let glossaryJson = '{}';
if (glossaryRaw) {
  try {
    JSON.parse(glossaryRaw); // 驗證 JSON 格式正確
    glossaryJson = glossaryRaw;
  } catch (e) {
    console.warn('[build] glossary.json is not valid JSON, using empty {}');
  }
}
template = replacePlaceholder(template, '__GLOSSARY__', '{}', glossaryJson);
```

`assistant.html` 的 data 區段（在 `const APP_CONFIG = ...` 之後）新增：
```javascript
const GLOSSARY     = /*__GLOSSARY__*/{};
```

注意：glossary 對所有 profile 相同（不受 `exclude_types` 影響），因為縮寫對照表的用途是查詢展開，與文件可見性無關。

### 4.5 嚮導自動產出

嚮導 Step 5 產出 `glossary.json` 的流程：

1. 掃描所有 `knowledge/` 文件的 markdown 內容
2. 呼叫 LLM，prompt：

```
以下是一組文件內容。請從中擷取所有縮寫、俗稱、簡稱、英文縮寫及其對應的全稱。
輸出 JSON 格式：{"縮寫": "全稱", ...}
只輸出 JSON，不要解釋。

文件內容：
{所有文件拼接，每份用 --- 分隔}
```

3. 解析 LLM 回傳的 JSON，寫入 `glossary.json`

### 4.6 更新提醒

Session Start Checklist 新增檢查：

```bash
# 7. Glossary 是否需要更新
KNOWLEDGE_MTIME=$(find knowledge/ -name '*.md' -newer scripts/lib/core/glossary.json 2>/dev/null | head -1)
[ -n "$KNOWLEDGE_MTIME" ] && echo "GLOSSARY=outdated" || echo "GLOSSARY=current"
```

| 狀況 | 推薦動作 |
|------|---------|
| GLOSSARY=outdated | 重新掃描文件產出 glossary.json |

## 5. Layer 2 — LLM Query Rewriting

### 5.1 目的

處理 glossary 未收錄的模糊表達、口語化提問、跨概念查詢。

**適用範圍：僅 SPA（assistant.html）。** qa-report.js 不使用此層（`--search-only` 模式不呼叫 API）。

### 5.2 與 twoPassFallback 的關係

現有 `findRelevantChunks()` 的第三階段 `twoPassFallback()` 在 structured + full-text 搜尋全部失敗後呼叫 Claude 從 META_INDEX 選取 chunk_id。Layer 2 (query rewriting) **取代** twoPassFallback，原因：

1. **效果更好**：rewriting 在搜尋前改善查詢詞，讓 structured/full-text 搜尋有機會命中；twoPassFallback 在搜尋後從索引猜測，繞過了搜尋引擎。
2. **不增加 API 呼叫**：取代而非新增，每次查詢仍然最多呼叫 Claude 一次（rewriting 或回答，但不是兩次搜尋相關呼叫）。
3. **順序一致**：rewriting 後的查詢仍然經過 structured + full-text 兩階段搜尋，結果品質更可預測。

實作時移除 `findRelevantChunks()` 中的 `twoPassFallback()` 呼叫。

### 5.3 呼叫流程

```javascript
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
      '',  // 無 system prompt
      200  // max_tokens
    );
    return result.trim();
  } catch (e) {
    console.warn('rewriteQuery failed:', e.message);
    return '';  // 失敗時回傳空字串，不影響後續搜尋
  }
}
```

### 5.4 搜尋流程整合

修改 `handleQA()`（assistant.html 約 line 1484）：

```javascript
async function handleQA(query, aiDiv, msgs) {
  // Layer 1: Glossary 確定性替換
  const expandedQuery = expandGlossary(query, GLOSSARY);

  // 先用展開後的查詢搜尋（structured + full-text）
  let chunks = structuredSearch(expandedQuery);
  if (chunks.length === 0) chunks = fullTextSearch(expandedQuery, 6);

  // 若仍無結果，Layer 2: LLM Query Rewriting（取代原 twoPassFallback）
  if (chunks.length === 0 && state.apiKey) {
    const rewrittenQuery = await rewriteQuery(query, expandedQuery);
    if (rewrittenQuery) {
      const combined = expandedQuery + ' ' + rewrittenQuery;
      chunks = fullTextSearch(combined, 6);
    }
  }

  // Layer 3: 硬性閘門
  if (chunks.length === 0) {
    const noResultMsg = APP_CONFIG.no_result_message
      || '根據目前知識庫的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢承辦人員。';
    appendMessage('ai', renderMarkdown(noResultMsg));
    msgs.push({ role: 'assistant', content: noResultMsg });
    return;
  }

  // 以下為既有的 LLM 回答流程（不變）
  const apiMsgs = buildApiMessages(msgs, chunks, 80000);
  // ...
}
```

注意：原 `findRelevantChunks()` 函式在 handleQA 中不再使用（改為直接呼叫 structuredSearch + fullTextSearch），但仍保留供 drill mode 的 `sendDrillStart()` 使用（drill mode 不需要 glossary 展開和 query rewriting）。

### 5.5 失敗處理

若 `rewriteQuery()` 發生 API 錯誤或逾時：
- `try/catch` 捕獲錯誤，回傳空字串
- 搜尋流程繼續使用 Layer 1 的展開結果
- 使用者無感知（不顯示錯誤訊息）

### 5.6 成本控制

- Input ~50 tokens（prompt + 查詢）
- Output ~30 tokens（關鍵詞）
- **僅在 structured + full-text 都無結果時才觸發**，多數查詢不會呼叫
- 使用與回答相同的 model（不需要切換模型）
- 不快取（每次查詢內容不同）

## 6. Layer 3 — 硬性閘門

### 6.1 觸發條件

搜尋結果數 = 0，在以下所有搜尋階段完成後判定：

- **SPA**：structured search + full-text search + Layer 2 rewriting 重搜（共三次嘗試）全部無結果
- **qa-report.js**：structured search + full-text search（兩次嘗試）全部無結果

### 6.2 行為

**SPA 端**（已整合到 Section 5.4 的 `handleQA()` 流程中）：

```javascript
// Layer 3: 硬性閘門（在 handleQA 中，所有搜尋嘗試之後）
if (chunks.length === 0) {
  const noResultMsg = APP_CONFIG.no_result_message
    || '根據目前知識庫的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢承辦人員。';
  appendMessage('ai', renderMarkdown(noResultMsg));
  msgs.push({ role: 'assistant', content: noResultMsg });
  return;  // 不呼叫 LLM
}
```

**qa-report.js 端**：在 API mode 的 main loop 中，若搜尋結果為空且非 `--search-only` 模式，跳過 Claude API 呼叫，直接記錄固定訊息作為回答。

### 6.3 設定

`config.example.json` 的 `ui` 區段新增：

```json
{
  "ui": {
    "no_result_message": "根據目前知識庫的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢承辦人員。"
  }
}
```

`build.js` 的 `substitutePlaceholders()` 需新增將 `ui.no_result_message` 嵌入 `APP_CONFIG`，或在 `appConfig` 物件中加入此欄位：

```javascript
const appConfig = {
  // ...existing fields...
  no_result_message: ui.no_result_message || '',
};
```

### 6.4 不使用分數閾值的原因

MiniSearch 的 score 沒有標準化（值域隨文件數量和內容變化），不同知識庫之間不可移植。強制設定閾值會導致：
- 小型知識庫（<50 文件）：分數偏低，閾值過濾掉正確結果
- 大型知識庫（>500 文件）：分數偏高，閾值形同虛設

結果數 = 0 是唯一在所有知識庫中一致的判定條件。

## 7. Layer 4 — 嚴格 System Prompt

### 7.1 改寫原則

| 移除 | 新增 |
|------|------|
| 「盡力回答」 | 「僅根據下方參考資料回答」 |
| 「即使資料不完全覆蓋」 | 「若參考資料不包含答案，回覆『文件中未查到相關資訊』」 |
| （無） | 「不得引用外部知識、標準通則、一般建議或自行推測」 |
| （無） | 「不得使用 emoji」 |

### 7.2 config.example.json 預設 system_prompt

```
你是知識助理。嚴格根據下方參考資料回答問題。

回答規則：
1. 僅使用參考資料中的內容回答，不得引用外部知識、標準通則、一般建議或自行推測
2. 若參考資料不包含答案，直接回覆「文件中未查到相關資訊」，不要提供任何替代建議
3. 每個回答必須引用來源文件
4. 不得使用 emoji

引用格式：
- 使用 [來源:文件編號#章節] 格式
- 冒號使用半形 :
- 章節使用數字格式（如 #2. 作業流程）

範例：
使用者：存取控制的規定是什麼？
助理：根據文件規定，存取控制要求如下：

1. 所有系統存取須經權限申請
2. 權限變更須主管核准
3. 離職人員須於當日撤銷權限

[來源:PRO-003#2. 作業流程]
```

### 7.3 向後相容

此為 `config.example.json` 的預設值。

- **新專案**：嚮導自動使用新版 prompt，無需手動處理。
- **已部署實例**：需手動更新 `config.json` 中的 `domain.system_prompt`。關鍵差異：
  1. 新增「不得引用外部知識」限制（原 prompt 無此條款）
  2. 新增「若參考資料不包含答案，直接回覆固定語句」（原 prompt 無明確拒答指令）
  3. 新增「不得使用 emoji」
- **檢測方式**：Session Start Checklist 可新增檢查 `domain.system_prompt` 是否包含「不得引用外部知識」字樣，若不包含則提醒更新。

## 8. 異動檔案

### 新增

| 路徑 | 說明 |
|------|------|
| `scripts/lib/core/glossary.json` | 空預設 `{}`，嚮導填充 |

### 修改

| 路徑 | 變更摘要 |
|------|---------|
| `templates/assistant.html` | (1) data 區段新增 `const GLOSSARY` 宣告 |
| | (2) 新增 `expandGlossary()` 函式 |
| | (3) 新增 `rewriteQuery()` 函式 |
| | (4) 改寫 `handleQA()`：整合 Layer 1~3（glossary 展開、rewrite、硬性閘門） |
| | (5) 移除 `findRelevantChunks()` 中的 `twoPassFallback()` 呼叫（以 Layer 2 取代） |
| `scripts/lib/core/build.js` | (1) profile loop 內新增 glossary.json 讀取 + JSON 驗證 + `replacePlaceholder` |
| | (2) `appConfig` 物件新增 `no_result_message` 欄位 |
| `scripts/lib/core/qa-report.js` | (1) main() 開頭載入 glossary.json |
| | (2) main loop 中 `findRelevantChunks()` 前加 `expandGlossary()` |
| | (3) API mode 中搜尋結果為空時跳過 Claude 呼叫（Layer 3） |
| `config.example.json` | (1) `ui` 新增 `no_result_message` 欄位 |
| | (2) `domain.system_prompt` 改為嚴格版本 |
| `CLAUDE.md` | (1) Step 5 產出清單新增 `glossary.json` |
| | (2) Session Start Checklist 新增 glossary 更新檢查 |

## 9. QA 驗證

### 9.1 各層在 qa-report.js 的覆蓋情況

| Layer | `--search-only` | API mode |
|-------|:---------------:|:--------:|
| Layer 1 (Glossary) | 有效 | 有效 |
| Layer 2 (LLM Rewriting) | 不適用（不呼叫 API） | 不適用（僅 SPA） |
| Layer 3 (Hard Gate) | 透過 `__NONE__` 題目驗證 | 搜尋結果為空時跳過 Claude 呼叫 |
| Layer 4 (System Prompt) | 不適用（不呼叫 API） | 有效 |

### 9.2 Glossary 效果驗證

在 `qa-questions.json` 中加入使用縮寫/俗稱的測試題目：

```json
{
  "id": "glossary-001",
  "question": "管審會的成員有哪些人？",
  "expected_doc_key": "ISMS-201",
  "identity": "general",
  "category": "glossary"
}
```

`--search-only` 模式即可驗證搜尋是否命中。

### 9.3 閘門效果驗證

加入無法匹配的題目，驗證不會產出外部知識：

```json
{
  "id": "gate-001",
  "question": "今天天氣如何？",
  "expected_doc_key": "__NONE__",
  "identity": "general",
  "category": "gate"
}
```

`expected_doc_key: "__NONE__"` 表示預期搜尋不命中。qa-report.js 需新增處理邏輯：

- **`--search-only` 模式**：`expected_doc_key` 為 `__NONE__` 的題目，searchHit 判定為「搜尋結果為空即命中」（反向邏輯）。
- **API mode**：searchResults 為空時不呼叫 Claude，驗證回答內容為固定訊息或空。

### 9.4 回歸驗證

實作完成後，執行完整 QA 驗證確認無回歸：

```bash
npm run qa-report -- --search-only --ci   # 搜尋命中率 >= 95%
npm run qa-report -- --html               # 完整 API 測試（含 Layer 4 驗證）
```

## 10. 不在範圍

- Admin UI 管理 glossary（由下游專案自行決定是否實作後端管理介面）
- Glossary 自動學習（從使用者查詢中自動發現新縮寫）
- 分數閾值閘門（見 6.4 說明）
- Self-Check 機制（前四層已充分覆蓋）
