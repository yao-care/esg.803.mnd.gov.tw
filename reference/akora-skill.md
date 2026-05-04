---
name: akora
description: 從專案描述（標案公告、驗收條件等）自動建立 AKORA 知識體 repo。萃取領域、文件類型、驗收項目、術語，產出完整骨架並驗證。
---

# AKORA 知識體初始化

從專案描述自動建立 AKORA 知識體 repo。

## 流程總覽

```
1. 收集專案描述
2. 萃取結構化資訊
3. 向用戶確認（repo 名稱、文件類型、目錄結構）
4. Clone AKORA 模板
5. 產出所有檔案
6. 驗證
7. Commit 並報告
```

## Step 1 — 收集專案描述

向用戶詢問：

> 請貼上專案描述（標案公告、驗收條件、服務需求說明書等）。
> 我會從中萃取領域、文件類型、驗收項目，自動建立知識體 repo。

等待用戶貼入文字。文字可能是：
- 標案公告（含機關、案名、驗收條件）
- 服務需求說明書摘要
- 專案規格書
- 任何描述交付物的文字

## Step 2 — 萃取結構化資訊

從貼入的文字中萃取以下資訊：

### 2a. 基本資訊

| 欄位 | 萃取方式 |
|------|---------|
| **organization** | 從「機關」、「甲方」、「委託單位」等欄位萃取 |
| **organization_en** | 從中文名稱翻譯為英文 |
| **project_name** | 從「案名」、「標案名稱」等欄位萃取 |
| **domain** | 從案名和內容判斷領域（如永續發展、資安管理、品質管理） |

### 2b. 文件類型推斷

根據驗收條件中的關鍵詞推斷文件類型，指派 2-5 字母大寫代碼：

| 關鍵詞 | 類型 | 代碼 |
|--------|------|------|
| 報告書、報告 | 報告 | RPT |
| 計畫、方案、規劃 | 計畫 | PLN |
| 表單、申請單、紀錄表 | 表單 | FRM |
| 評估、診斷、檢核 | 評估 | ASM |
| 程序、流程、辦法 | 程序 | PRO |
| 政策、方針、規定 | 政策 | POL |
| 清冊、名冊、盤點 | 清冊 | REG |
| 指引、手冊、說明 | 指引 | GDL |

找不到匹配時，預設為 `DOC`（一般文件）。

**非政府採購領域：** 上述關鍵詞表針對政府標案/合規交付物設計。若萃取的領域明顯不同（如金融情報、產業分析、研究文獻），應根據該領域的慣例生成專屬類型代碼（如產業分析領域可能用 `WR`=週報、`CP`=產能價格、`FH`=財務健康等），而非全部回退到 `DOC`。

### 2c. 驗收項目萃取

從驗收條件、交付物清單、服務項目中萃取每個獨立交付物：

每個驗收項目產出：
- `id`：`{TYPE}-{NNN}`（如 `RPT-001`）
- `type`：文件類型代碼
- `title_zh`：中文標題
- `title_en`：英文標題（翻譯）
- `sections`：章節大綱（從細項萃取）

### 2d. 術語萃取

從文字中萃取專有術語、縮寫、英文簡稱：
- 格式：`{"縮寫": "全稱"}`
- 包含：英文縮寫（EMS、GHG）、中文簡稱（管審會）、專業術語

### 2e. Repo 名稱生成

從機關+案名生成英文 repo 名稱：
- 格式：`{機關英文縮寫}-{關鍵詞}-{年份}`
- 範例：`mohw-sustainability-2026`
- 全小寫、用 `-` 分隔、不超過 40 字元

### 2f. 外部資料來源判斷

判斷專案是否需要從外部 Git repos 拉取文件。線索包括：
- 專案描述提及「多個資料來源」、「跨 repo」、「外部文件」
- 列出的資料涵蓋多個產業/領域（各自有獨立 repo）
- 文件產出頻率暗示自動化收集（每日、每週、每月）

若判斷有外部來源，詢問用戶：

> 這個專案看起來需要從外部 Git repos 拉取文件。請提供：
> 1. 外部 repo 清單（格式：`owner/repo`）
> 2. 每個 repo 中文件所在路徑（如 `docs/`）
> 3. 是否需要 token（私有 repo 需要 `PAT_TOKEN`）

每個外部來源生成一筆 config entry：

```json
{
  "name": "{repo-短名}",
  "repo": "{owner/repo}",
  "path": "{文件路徑}",
  "ref": "main",
  "include": ["*"],
  "token_env": "PAT_TOKEN"
}
```

**備註：** AKORA 的 `external-fetcher.js` 使用 `findDocumentDirs()` 遞迴掃描 `path` 下所有層級的子目錄，自動找到包含 `merge.yaml` 的目錄。巢狀目錄結構（如 `docs/daily/{date}/{type}/merge.yaml`）可以正常運作，無需前置處理。

## Step 3 — 向用戶確認

向用戶展示萃取結果，格式如下：

```
## 萃取結果

**組織：** {organization}
**案名：** {project_name}
**領域：** {domain}
**Repo 名稱：** {repo_name}（可修改）

### 文件類型

| 代碼 | 類型 | 說明 |
|------|------|------|
| RPT | 報告 | 溫室氣體盤查報告等 |
| PLN | 計畫 | 節能計畫等 |
（列出全部萃取的類型）

### 知識體目錄結構

knowledge/
├── RPT-001/ — 溫室氣體盤查報告書
│   章節：政府機關簡介、盤查邊界設定、排放源鑑別
├── ASM-001/ — 節能診斷與評估報告
│   章節：設備盤點、照明密度分析、空調最佳化
（列出全部驗收項目）

### 外部資料來源（若有）

| 來源 | Repo | 路徑 | Token |
|------|------|------|-------|
| memory-intel | weiqi-kids/memory-intel | docs/ | PAT_TOKEN |
（列出全部外部來源）

確認以上內容？可以修改 repo 名稱、調整類型代碼、增刪項目、修改外部來源。
```

等待用戶確認或修改。**不要跳過此步驟。**

**邊界情況：**
- 若用戶要求刪除所有萃取的文件類型或驗收項目 → 詢問用戶是否要重新貼入專案描述，或手動指定文件類型
- 若用戶全面否決萃取結果 → 回到 Step 1 重新收集

## Step 4 — Clone AKORA 模板

```bash
git clone https://github.com/weiqi-kids/akora.git {repo_name}
cd {repo_name}
npm install
```

確認 clone 成功且 `npm install` 無錯誤。

**錯誤處理：**
- `git clone` 失敗 → 檢查網路連線和 GitHub 可用性，提示用戶確認能否存取 `github.com`
- `npm install` 失敗 → 檢查 Node.js 版本（需 >= 18），嘗試刪除 `node_modules` 後重新安裝
- 目標目錄已存在 → 詢問用戶是否刪除後重建，或使用不同名稱

## Step 5 — 產出所有檔案

在新 repo 中產出以下檔案。**參考 `reference/iso27001-example.md` 作為格式範本**（僅參考格式結構，不照抄內容）。

### 5a. config.json

**做法：** 讀取 `config.example.json` 的完整內容作為基礎，然後覆寫以下欄位。**保留所有未列出的欄位**（`targets`、`collectors`、`event_collectors`、`monitor`、`exercises`、`notify`、`qa`、`git`、`api`、`form_submission`、`profiles` 等）的預設值，確保未來新增欄位不會遺漏。

**必須覆寫的欄位：**

```json
{
  "knowledge_body": {
    "name": "{project_name}",
    "name_en": "{project_name_en}",
    "description": "{從專案描述生成的一句話說明}",
    "organization": "{organization}"
  },
  "data_sources": {
    "documents": {
      "enabled": true,
      "path": "knowledge/",
      "types": ["{萃取的類型代碼陣列}"]
    },
    "external": [
      "{Step 2f 萃取的外部來源陣列，無則留空陣列}"
    ]
  },
  "domain": {
    "form_prefix": "{萃取的表單類型代碼，預設 FRM}",
    "metadata_filename": "merge.yaml",
    "system_prompt": "{嚴格版 prompt — 見下方模板}",
    "citation_pattern": "\\[來源:[^\\]]+\\]"
  },
  "ui": {
    "assistant_title": "{領域}知識助理",
    "welcome_message": "你好！請輸入問題，我將根據{knowledge_body.name}的文件回答。",
    "doc_group_labels": {"{每個萃取的類型代碼}": "{類型中文名}"},
    "no_result_message": "根據目前{knowledge_body.name}的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢承辦人員。"
  }
}
```

**保留預設值的欄位：** `data_sources.tables`、`data_sources.imports`、`targets`、`collectors`、`event_collectors`、`monitor`、`exercises`、`notify`、`qa`、`git`、`api`、`form_submission`、`profiles`，以及 `domain` 中的 `control_id_pattern`（留空字串）、`control_name`（留空字串）、`identity_doc_map`（留空物件）、`drill_system_prompt`（留空字串）、`assessment_controls`（留空陣列）、`assessment_controls_covered`（留空陣列）。

若 Step 2f 有外部來源，`external` 陣列格式：
```json
{
  "name": "memory-intel",
  "repo": "weiqi-kids/memory-intel",
  "path": "docs",
  "ref": "main",
  "include": ["*"],
  "token_env": "PAT_TOKEN"
}
```

**system_prompt 模板：**

```
你是{project_name}知識助理。嚴格根據下方參考資料回答問題。

回答規則：
1. 僅使用參考資料中的內容回答，不得引用外部知識、標準通則、一般建議或自行推測
2. 若參考資料不包含答案，直接回覆「文件中未查到相關資訊」，不要提供任何替代建議
3. 每個回答必須引用來源文件
4. 不得使用 emoji

引用格式規定：
- 引用文件時使用 [來源:文件編號#章節] 格式
- 冒號必須使用半形 :（不是：）
- 章節使用數字格式（如 #2. 作業流程）

範例問答：

使用者：{從萃取的驗收項目中取一個範例問題}
助理：根據文件規定，{簡短範例回答}

[來源:{第一個文件的 document_id}#1. {第一個章節名}]
```

### 5b. _meta/ 檔案

產出以下檔案，內容**根據萃取的領域生成**（不是照抄 ISO 27001 範例）：

| 檔案 | 說明 |
|------|------|
| `_meta/rule.md` | 該領域的命名慣例、目錄結構、版本管理規則 |
| `_meta/writer.md` | 該領域的文件撰寫指引（用語、格式、必要章節） |
| `_meta/reviewer.md` | 該領域的文件審查標準（合規檢查點、常見缺失） |
| `_meta/types/{CODE}.md` | 每個文件類型一個檔案（必要章節、必要元素、審查重點） |
| `_meta/glossary.json` | 從專案描述萃取的術語對照表 |

### 5c. knowledge/ 目錄

每個驗收項目一個子目錄：

**merge.yaml 格式（每個子目錄必須有）：**

```yaml
document_id: {TYPE}-{NNN}
type: {TYPE}
title_zh: {中文標題}
title_en: {英文標題}
main:
  zh: {中文標題}.md
```

FRM 類型額外包含 `fields:` 定義。

**.md 格式（章節大綱預填）：**

```markdown
---
document_id: {TYPE}-{NNN}
title_zh: {中文標題}
version: "0.1"
status: draft
classification: internal
owner: ""
effective_date: ""
next_review_date: ""
change_history:
  - version: "0.1"
    date: "{今天日期 YYYY-MM-DD}"
    author: "AKORA Skill"
    description: "初始骨架"
---

# {中文標題}

## 1. {第一個章節}

{從驗收條件萃取的內容提示}

（待填寫）

## 2. {第二個章節}

{從驗收條件萃取的內容提示}

（待填寫）

（依序產出全部章節，不省略）
```

### 5d. qa-questions.json

每個驗收項目至少產出一題，**總數至少 20 題**（與 CLAUDE.md 嚮導的 20~50 題門檻一致）。若驗收項目不足 20 個，則為較重要的項目多產幾題（不同角度的問題）。放在 `scripts/lib/core/qa-questions.json`：

```json
[
  {
    "id": "q001",
    "question": "{用自然語言問一個能在該文件中找到答案的問題}",
    "expected_doc_key": "{對應的 knowledge/ 子目錄名}",
    "identity": "general",
    "category": "deliverable"
  }
]
```

**重要：**
- 本地文件：`expected_doc_key` 是 knowledge/ 下的**子目錄名**（如 `RPT-001`），不是 document_id。
- 外部來源文件：`expected_doc_key` 必須使用 `external/{source_name}/{document_id}` 格式（如 `external/memory-intel/CP-MEM-LIVE`），對應 `external-fetcher.js` 的 `buildExternalDocKey()` 產出格式。

### 5e. 其他檔案（依需求）

根據萃取的領域和用戶確認的設定，判斷是否需要產出以下檔案。若領域不需要（例如純文件知識體不需要收集器），則跳過。

| 檔案 | 條件 | 說明 |
|------|------|------|
| `collectors/*.sh` | 領域需要自動化資料收集時 | 每個收集器一個骨架腳本（含 `#!/bin/bash`、參數解析、TODO 標記） |
| `.github/ISSUE_TEMPLATE/*.yml` | 領域需要手動表單（如事件通報、變更申請）時 | GitHub Issue 模板 |
| `.github/workflows/*.yml` | config 中啟用了收集器、監控或演練時 | 客製化現有 workflow 的 cron 排程 |

若產出了收集器，同步更新 `config.json` 的 `collectors` 陣列。

### 5f. 執行 setup-org.sh 與設定 remote

```bash
bash scripts/setup-org.sh

# origin 目前指向 AKORA 模板 repo（clone 來源）
# 重新命名為 template，之後用戶建立自己的 repo 時再設定 origin
git remote rename origin template
```

## Step 6 — 驗證

```bash
npm run build:assistant
npm run qa-report -- --search-only
```

兩項皆必須通過。若失敗：
- `build:assistant` 失敗 → 檢查 config.json 格式、knowledge/ 目錄結構
- `qa-report` 搜尋命中率低 → 檢查 qa-questions.json 的 expected_doc_key 是否對應正確的子目錄名

修正後重新驗證，直到通過。

## Step 7 — Commit 並報告

```bash
# 初始化 commit 使用 git add -A（因為所有檔案都是新產出的，不含敏感檔案）
git add -A
git commit -m "init: {案名} 知識體初始化"
```

向用戶報告：

```
知識體建立完成！

Repo: {repo_name}/
文件數: {N} 份
類型: {類型列表}
QA 種子題: {M} 題

下一步：
1. cd {repo_name} 開啟新的 Claude Code session
2. 系統會進入正常模式，可以開始填寫文件內容
3. 填寫後執行 npm run build:assistant 重新建置
4. 執行 npm run qa-report -- --html 產出品質報告
```
