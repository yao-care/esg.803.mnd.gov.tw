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
  ├─ Layer 1: Glossary 確定性替換
  │   零成本、零延遲、確定性
  │
  ├─ Layer 2: LLM Query Rewriting
  │   ~100 tokens、處理未知表達
  │
  ├─ Layer 3: 硬性閘門
  │   搜尋結果數 = 0 → 固定回覆、不呼叫 LLM
  │
  └─ Layer 4: 嚴格 System Prompt
      僅根據參考資料回答、禁止外部知識
```

四層各自獨立，任一層故障不影響其他層的防護效果。

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
  let expanded = query;
  // 按鍵長度降序排列，避免短詞先匹配導致長詞被截斷
  const sorted = Object.entries(glossary)
    .sort((a, b) => b[0].length - a[0].length);
  for (const [term, expansion] of sorted) {
    // 全域替換，保留原始查詢詞（附加展開詞）
    if (expanded.includes(term)) {
      expanded = expanded + ' ' + expansion;
    }
  }
  return expanded;
}
```

設計決策：**附加**展開詞而非替換原始詞。原因：
- 使用者用「管審會」查詢，搜尋索引中可能同時有縮寫和全稱
- 附加方式讓 MiniSearch 同時匹配兩者，提升召回率
- 替換方式會丟失原始詞的匹配機會

### 4.3 執行時機

- **SPA（assistant.html）**：`handleSend()` 中，搜尋前
- **QA 驗證（qa-report.js）**：`findRelevantChunks()` 前

兩處使用同一份 glossary 資料，確保 QA 測試結果與實際使用一致。

### 4.4 Build 時嵌入

`build.js` 在組裝 HTML 時，將 glossary.json 讀取並嵌入為 `__GLOSSARY__` placeholder：

```javascript
const glossary = readFileSafe(path.join(PROJECT_ROOT, 'scripts', 'lib', 'core', 'glossary.json'));
template = replacePlaceholder(template, '__GLOSSARY__', '{}', glossary || '{}');
```

`assistant.html` 中：
```javascript
const GLOSSARY = /*__GLOSSARY__*/{};
```

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

### 5.2 呼叫流程

```javascript
async function rewriteQuery(query, expandedQuery) {
  const prompt = `你是搜尋查詢改寫器。將以下使用者問題改寫為適合全文搜尋的關鍵詞組合。
規則：
- 只輸出關鍵詞，用空格分隔
- 不要解釋、不要回答問題
- 保留專有名詞原文
- 展開口語化表達為正式用語

使用者問題：${expandedQuery}`;

  const result = await callClaude(
    [{ role: 'user', content: prompt }],
    '',  // 無 system prompt
    200  // max_tokens
  );
  return result.trim();
}
```

### 5.3 搜尋流程整合

```javascript
// 在 handleQA() 或 findRelevantChunks() 的呼叫端
const expandedQuery = expandGlossary(userQuery, GLOSSARY);
const rewrittenQuery = await rewriteQuery(userQuery, expandedQuery);
const searchQuery = expandedQuery + ' ' + rewrittenQuery;
const results = findRelevantChunks(searchQuery, ...);
```

### 5.4 成本控制

- Input ~50 tokens（prompt + 查詢）
- Output ~30 tokens（關鍵詞）
- 使用與回答相同的 model（不需要切換模型）
- 不快取（每次查詢內容不同）

## 6. Layer 3 — 硬性閘門

### 6.1 觸發條件

MiniSearch 搜尋結果數 = 0（包含三段搜尋全部無結果：structured search、full-text、two-pass fallback）。

### 6.2 行為

```javascript
if (results.length === 0) {
  // 不呼叫 LLM，直接顯示固定訊息
  const noResultMsg = config.ui?.no_result_message
    || '根據目前知識庫的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢承辦人員。';
  appendMessage('assistant', noResultMsg);
  return;
}
```

### 6.3 設定

`config.json` 新增：

```json
{
  "ui": {
    "no_result_message": "根據目前知識庫的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢承辦人員。"
  }
}
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

此為 `config.example.json` 的預設值。已部署的實例需自行更新 `config.json` 中的 `domain.system_prompt`。嚮導新建的專案會自動使用新版 prompt。

## 8. 異動檔案

### 新增

| 路徑 | 說明 |
|------|------|
| `scripts/lib/core/glossary.json` | 空預設 `{}`，嚮導填充 |

### 修改

| 路徑 | 變更 |
|------|------|
| `templates/assistant.html` | Layer 1: `expandGlossary()` + `__GLOSSARY__` 嵌入 |
| | Layer 2: `rewriteQuery()` 呼叫 |
| | Layer 3: 結果為 0 時攔截，顯示 `no_result_message` |
| `scripts/lib/core/build.js` | 讀取 glossary.json 並嵌入 HTML |
| `scripts/lib/core/qa-report.js` | `findRelevantChunks` 前加 glossary 替換 |
| `config.example.json` | 新增 `ui.no_result_message`；改寫 `domain.system_prompt` |
| `CLAUDE.md` | Step 5: glossary 產出步驟；Session Start: glossary 更新檢查 |

## 9. QA 驗證

### 9.1 Glossary 效果驗證

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

### 9.2 閘門效果驗證

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

`expected_doc_key: "__NONE__"` 表示預期搜尋不命中。驗證 LLM 未被呼叫或回覆為固定訊息。

## 10. 不在範圍

- Admin UI 管理 glossary（由下游專案自行決定是否實作後端管理介面）
- Glossary 自動學習（從使用者查詢中自動發現新縮寫）
- 分數閾值閘門（見 6.4 說明）
- Self-Check 機制（前四層已充分覆蓋）
