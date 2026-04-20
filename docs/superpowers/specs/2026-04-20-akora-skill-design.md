# AKORA Skill 設計

## 1. 問題陳述

使用者收到標案公告或專案描述後，需要手動 fork AKORA 模板、進入 repo、跑嚮導、逐步回答問題。流程繁瑣且容易遺漏。需要一個 Claude Code skill，讓使用者在任意 session 貼入專案描述，自動完成從 clone 到驗證的全部流程。

## 2. 設計目標

- 在任意 Claude Code session 中輸入 `/akora` 即可啟動
- 從專案描述（標案公告、驗收條件等）自動萃取領域、文件類型、驗收項目、細項
- 一次性產出完整 repo（config.json + _meta + knowledge + qa-questions + glossary）
- 萃取深度到細項級別（章節大綱預填進 .md 檔案）
- 產出後自動驗證（build + search-only QA）

## 3. 使用流程

```
用戶在任意 session 輸入 /akora
  │
  ├─ 1. Skill 載入，詢問：「請貼上專案描述」
  │
  ├─ 2. 萃取（LLM 分析貼入的文字）
  │   ├─ 機關/組織名稱（中/英文）
  │   ├─ 案名
  │   ├─ 領域判定（如：永續發展、資安管理、品質管理）
  │   ├─ 文件類型 + 2-5字母大寫代碼
  │   ├─ 驗收項目 → 對應到 knowledge/ 目錄
  │   └─ 每個驗收項目的細項 → .md 章節大綱
  │
  ├─ 3. 向用戶確認
  │   ├─ 提議 repo 名稱（如 mohw-sustainability-2026），用戶可修改
  │   ├─ 列出萃取的文件類型和代碼
  │   ├─ 列出將建立的 knowledge/ 目錄結構
  │   └─ 用戶確認或調整後才繼續
  │
  ├─ 4. git clone https://github.com/weiqi-kids/akora.git {repo名}
  │
  ├─ 5. cd 到新 repo，一次性產出所有檔案
  │   ├─ config.json
  │   ├─ _meta/rule.md, writer.md, reviewer.md
  │   ├─ _meta/types/*.md
  │   ├─ _meta/glossary.json
  │   ├─ knowledge/*/merge.yaml + {title}.md
  │   ├─ scripts/lib/core/qa-questions.json
  │   └─ 其他（collectors, workflows, issue templates — 依需求）
  │
  ├─ 6. npm install && npm run build:assistant
  │
  ├─ 7. npm run qa-report -- --search-only
  │
  ├─ 8. git add -A && git commit -m "init: {案名} 知識體初始化"
  │
  └─ 9. 報告完成，提示下一步
```

## 4. 萃取邏輯

### 4.1 從專案描述萃取的資訊

| 欄位 | 萃取來源 | 範例 |
|------|---------|------|
| organization | 「機關」欄位 | 衛生福利部 |
| organization_en | 從中文翻譯 | Ministry of Health and Welfare |
| project_name | 「案名」欄位 | 115年度「本部永續發展成果委託專業服務」|
| repo_name | 從機關+案名生成英文 | mohw-sustainability-2026 |
| domain | 從案名和內容判斷 | 永續發展與碳管理 |
| document_types | 從驗收條件推斷 | RPT(報告)、PLN(計畫)、FRM(表單)、ASM(評估) |
| deliverables | 從驗收條件結構化萃取 | 見 4.2 |
| glossary | 從文字中的專有術語萃取 | EMS→能源管理系統, 近零碳→1+級能效 |

### 4.2 驗收項目萃取格式

從範例中的結構：

```
一、溫室氣體盤查
  1. 完成盤查報告書
    - 政府機關簡介
    - 盤查邊界設定
    - 排放源鑑別
    - 排放量計算
  2. 完成登錄並公開排放量
  3. 協助規劃公開揭露

二、深度節能
  1. 節能診斷與評估
  2. 訂定節能計畫與目標
  3. 盤點設備
  4. 規劃降低屆齡設備
```

萃取為結構化資料：

```json
[
  {
    "id": "RPT-001",
    "type": "RPT",
    "title_zh": "溫室氣體盤查報告書",
    "sections": [
      "1. 政府機關簡介",
      "2. 盤查邊界設定（範疇含本部及所屬三級機關）",
      "3. 排放源鑑別",
      "4. 排放量計算",
      "5. 登錄與公開揭露"
    ]
  },
  {
    "id": "ASM-001",
    "type": "ASM",
    "title_zh": "節能診斷與評估報告",
    "sections": [
      "1. 設備盤點",
      "2. 照明密度分析",
      "3. 空調最佳化分析",
      "4. 具體改善建議"
    ]
  }
]
```

### 4.3 文件類型推斷規則

Skill 根據驗收條件的動詞和名詞推斷類型：

| 關鍵詞 | 推斷類型 | 代碼 |
|--------|---------|------|
| 報告書、報告 | 報告 | RPT |
| 計畫、方案、規劃 | 計畫 | PLN |
| 表單、申請單、紀錄表 | 表單 | FRM |
| 評估、診斷、檢核 | 評估 | ASM |
| 程序、流程、辦法 | 程序 | PRO |
| 政策、方針、規定 | 政策 | POL |
| 清冊、名冊、盤點 | 清冊 | REG |
| 指引、手冊、說明 | 指引 | GDL |

若找不到匹配，預設為 `DOC`（一般文件）。

用戶在確認步驟可以調整代碼和類型。

## 5. 產出檔案

### 5.1 config.json

根據萃取結果填入：

```json
{
  "knowledge_body": {
    "name": "{案名}",
    "name_en": "{英文案名}",
    "description": "{從專案描述生成}",
    "organization": "{機關名}"
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
    "system_prompt": "{嚴格版 prompt，包含領域特定引導}"
  }
}
```

其餘欄位沿用 config.example.json 的預設值。

### 5.2 _meta/ 檔案

根據領域生成：

- `rule.md` — 該領域的命名慣例、目錄結構、版本管理規則
- `writer.md` — 文件撰寫指引（用語、格式、必要章節）
- `reviewer.md` — 文件審查標準（合規檢查點、常見缺失）
- `types/*.md` — 每個文件類型一個檔案（必要章節、必要元素、審查重點）
- `glossary.json` — 從專案描述萃取的術語對照表

### 5.3 knowledge/ 目錄結構

每個驗收項目建立一個子目錄：

```
knowledge/
├── RPT-001/
│   ├── merge.yaml
│   └── 溫室氣體盤查報告書.md
├── ASM-001/
│   ├── merge.yaml
│   └── 節能診斷與評估報告.md
├── PLN-001/
│   ├── merge.yaml
│   └── 節能計畫.md
└── ASM-002/
    ├── merge.yaml
    └── 建築能效評估報告.md
```

**merge.yaml 範例：**

```yaml
document_id: RPT-001
type: RPT
title_zh: 溫室氣體盤查報告書
title_en: Greenhouse Gas Inventory Report
main:
  zh: 溫室氣體盤查報告書.md
```

**.md 範例（章節大綱預填）：**

```markdown
---
document_id: RPT-001
title_zh: 溫室氣體盤查報告書
version: "0.1"
status: draft
classification: internal
owner: ""
effective_date: ""
next_review_date: ""
change_history:
  - version: "0.1"
    date: "2026-04-20"
    author: "AKORA Wizard"
    description: "初始骨架"
---

# 溫室氣體盤查報告書

## 1. 政府機關簡介

（待填寫）

## 2. 盤查邊界設定

範疇含本部及所屬三級機關。

（待填寫：組織邊界、營運邊界、範疇一/二/三）

## 3. 排放源鑑別

（待填寫：各類排放源清單）

## 4. 排放量計算

（待填寫：計算方法、排放係數、計算結果）

## 5. 登錄與公開揭露

- 116/5/30 前於 ghgregistry.moenv.gov.tw 完成登錄
- 協助規劃於其他平台公開揭露

（待填寫：揭露計畫與時程）
```

### 5.4 qa-questions.json

每個驗收項目至少一題，涵蓋搜尋命中驗證：

```json
[
  {
    "id": "q001",
    "question": "溫室氣體盤查的範疇包含哪些機關？",
    "expected_doc_key": "RPT-001",
    "identity": "general",
    "category": "deliverable"
  },
  {
    "id": "q002",
    "question": "節能診斷評估包含哪些設備類型？",
    "expected_doc_key": "ASM-001",
    "identity": "general",
    "category": "deliverable"
  }
]
```

### 5.5 glossary.json

從專案描述中的專有術語萃取：

```json
{
  "EMS": "能源管理系統",
  "近零碳": "近零碳建築（1+級能效）",
  "ESCO": "能源技術服務業",
  "GHG": "溫室氣體",
  "碳盤查": "溫室氣體排放量盤查"
}
```

## 6. Skill 檔案格式

### 6.1 位置

`~/.claude/skills/akora.md`（單檔）

### 6.2 結構

```markdown
---
name: akora
description: 從專案描述自動建立 AKORA 知識體 repo。萃取驗收項目、產出文件骨架、建置並驗證。
---

# AKORA 知識體初始化

## 觸發條件

用戶輸入 /akora 或描述需要建立新的知識體專案。

## 流程

[完整的 9 步指令，包含每步的具體 prompt 和判斷邏輯]
```

### 6.3 Skill 內容重點

Skill 內容必須包含：

1. **萃取 prompt** — 告訴 Claude 如何從任意格式的專案描述中萃取結構化資訊
2. **類型推斷規則** — 關鍵詞→文件類型代碼的映射表
3. **確認互動格式** — 如何向用戶展示萃取結果、讓用戶確認或修改
4. **產出指令** — 每個檔案的完整規格（參考 AKORA CLAUDE.md Step 5 和 reference/iso27001-example.md）
5. **驗證步驟** — npm install + build + qa-report
6. **CLAUDE.md 嚮導關係** — Skill 產出 config.json 後，CLAUDE.md 進入正常模式，嚮導不再觸發

## 7. 與 CLAUDE.md 嚮導的關係

| 面向 | CLAUDE.md 嚮導 | /akora skill |
|------|----------------|--------------|
| 觸發 | 進入 repo 時自動（config.json 不存在） | 任意 session 手動 `/akora` |
| 輸入 | 互動問答（多輪對話） | 一次性貼入專案描述 |
| 萃取 | 無（用戶自己回答） | 自動從文字萃取 |
| 深度 | 骨架（空 .md） | 細項級別（章節大綱預填） |
| 適用 | 已有 repo、手動初次設定 | 從零開始、有現成專案描述 |

兩者不衝突。Skill 是嚮導的加速版。Skill 產出 config.json 後，未來進入 repo 的 session 會進入正常模式。

## 8. 不在範圍

- 自動建立 GitHub repo（用戶自行 `gh repo create` 或手動建立）
- 自動上傳標案附件（PDF 等）到 knowledge/
- 追蹤標案進度或截止日
- 與其他系統（procurement-filter 等）整合
