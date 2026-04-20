# AKORA Skill 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `/akora` Claude Code skill，讓使用者在任意 session 貼入專案描述後，自動萃取、clone、產出完整知識體 repo。

**Architecture:** 單一 skill 檔案 `~/.claude/skills/akora.md`，包含完整的萃取邏輯、產出規格、驗證步驟。Skill 載入後 Claude 依指令逐步執行。

**Tech Stack:** Claude Code Skill（Markdown 格式）、Bash、Node.js

**Spec:** `docs/superpowers/specs/2026-04-20-akora-skill-design.md`

**Target:** `~/.claude/skills/akora.md`

---

## File Structure

### New Files

| Path | Responsibility |
|---|---|
| `~/.claude/skills/akora.md` | `/akora` skill — 從專案描述自動建立 AKORA 知識體 |

---

### Task 1: 建立 `/akora` Skill 檔案

**Files:**
- Create: `~/.claude/skills/akora.md`

- [ ] **Step 1: 建立 skill 檔案**

建立 `~/.claude/skills/akora.md`，完整內容如下：

```markdown
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
| ... | ... | ... |

### 知識體目錄結構

knowledge/
├── RPT-001/ — 溫室氣體盤查報告書
│   章節：政府機關簡介、盤查邊界設定、排放源鑑別...
├── ASM-001/ — 節能診斷與評估報告
│   章節：設備盤點、照明密度分析、空調最佳化...
└── ...

確認以上內容？可以修改 repo 名稱、調整類型代碼、增刪項目。
```

等待用戶確認或修改。**不要跳過此步驟。**

## Step 4 — Clone AKORA 模板

```bash
git clone https://github.com/weiqi-kids/akora.git {repo_name}
cd {repo_name}
npm install
```

確認 clone 成功且 `npm install` 無錯誤。

## Step 5 — 產出所有檔案

在新 repo 中產出以下檔案。**參考 `reference/iso27001-example.md` 作為格式範本**（僅參考格式結構，不照抄內容）。

### 5a. config.json

以 `config.example.json` 為基礎，填入萃取的值：

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
    "tables": {
      "collected": { "enabled": false, "path": "data/collected/" },
      "reported": { "enabled": false, "path": "data/reported/" }
    },
    "external": [],
    "imports": { "enabled": false, "path": "imports/", "parsers": ["pdf", "office", "image"] }
  },
  "domain": {
    "form_prefix": "FRM",
    "metadata_filename": "merge.yaml",
    "system_prompt": "{嚴格版 prompt — 見下方模板}",
    "citation_pattern": "\\[來源:[^\\]]+\\]"
  }
}
```

其餘欄位（targets, collectors, monitor, exercises, notify, qa, git, ui, api, form_submission, profiles）沿用 config.example.json 的預設值。

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

...（依此類推）
```

### 5d. qa-questions.json

每個驗收項目至少產出一題，放在 `scripts/lib/core/qa-questions.json`：

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

**重要：** `expected_doc_key` 是 knowledge/ 下的**子目錄名**（如 `RPT-001`），不是 document_id。

### 5e. 執行 setup-org.sh

```bash
bash scripts/setup-org.sh
git remote add template https://github.com/weiqi-kids/akora.git
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
```

- [ ] **Step 2: 驗證 skill 檔案存在且可讀**

Run: `cat ~/.claude/skills/akora.md | head -5`
Expected:
```
---
name: akora
description: ...
---
```

- [ ] **Step 3: Commit skill 檔案到 AKORA repo（供參考）**

將 skill 檔案的副本存入 AKORA repo 供參考：

```bash
cp ~/.claude/skills/akora.md /Users/lightman/weiqi.kids/akora/reference/akora-skill.md
cd /Users/lightman/weiqi.kids/akora
git add reference/akora-skill.md
git commit -m "docs: add /akora skill reference copy"
```

---

## Spec Coverage Check

| Spec Section | Covered by |
|---|---|
| 3. 使用流程 (9 步) | Skill Step 1-7 |
| 4.1 萃取資訊 | Skill Step 2a |
| 4.2 驗收項目格式 | Skill Step 2c |
| 4.3 類型推斷規則 | Skill Step 2b |
| 5.1 config.json | Skill Step 5a |
| 5.2 _meta/ 檔案 | Skill Step 5b |
| 5.3 knowledge/ 結構 | Skill Step 5c |
| 5.4 qa-questions.json | Skill Step 5d |
| 5.5 glossary.json | Skill Step 5b |
| 6. Skill 檔案格式 | Task 1 (frontmatter + markdown) |
| 7. 與嚮導關係 | Skill 產出 config.json → 嚮導不觸發 |
