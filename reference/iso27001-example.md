# ISO 27001 Reference Implementation Example

This file shows what a **complete ISO 27001 instance** looks like in this template.
It is a FORMAT reference for the wizard (`CLAUDE.md` Step 5) to follow when generating
content for any domain. **Do not copy the content** — use it to understand the structure,
naming conventions, and level of detail expected.

Source repository: `agent.system-integration-quality-control`
Organization: 藥提醒科技有限公司 (Yao Care Tech Co., Ltd.)

---

## 1. config.json — ISO 27001 ISMS Instance

```json
{
  "knowledge_body": {
    "name": "資訊安全管理系統",
    "name_en": "isms",
    "description": "ISO 27001 / CNS 27001 / SOC 2 合規管理文件與自動化安全掃描整合",
    "organization": "藥提醒科技有限公司"
  },
  "data_sources": {
    "documents": {
      "enabled": true,
      "path": "isms/",
      "types": ["POL", "PRO", "WKI", "STD", "GDL", "FRM", "REG", "PLN", "SOA", "MTX"]
    },
    "tables": {
      "collected": { "enabled": true,  "path": "data/collected/" },
      "reported":  { "enabled": true,  "path": "data/reported/"  }
    },
    "imports": {
      "enabled": false,
      "path": "imports/",
      "parsers": ["pdf", "office", "image"]
    }
  },
  "targets": [
    {
      "name": "yao.care--twtxgnn",
      "repos": ["https://github.com/yao-care/TwTxGNN"],
      "web_url": "https://twtxgnn.yao.care/",
      "llm_endpoint": "",
      "scan_depth_daily": "quick",
      "scan_depth_monthly": "deep",
      "notify_emails": ["lightman.chang@gmail.com"],
      "runtime": {
        "adapters": [],
        "heartbeat_timeout_hours": 24,
        "drill": {
          "frequency_months": 6,
          "notify_days_before": [30, 7, 1],
          "contacts": [],
          "last_drill_date": null,
          "next_drill_date": null
        },
        "backup": {
          "api_url": null,
          "credentials_env": null,
          "last_restore_test": null,
          "rto_hours": null,
          "rpo_hours": null
        },
        "redteam": {
          "enabled": false,
          "target_url": null,
          "llm_endpoint": null,
          "playbooks": ["web-app-attack"],
          "schedule_cron": "0 3 * * 1"
        }
      }
    }
  ],
  "collectors": [
    { "id": "vulnerability", "enabled": true,  "script": "collectors/vulnerability.sh" },
    { "id": "sast",          "enabled": true,  "script": "collectors/sast.sh"          },
    { "id": "sbom",          "enabled": true,  "script": "collectors/sbom.sh"          },
    { "id": "pentest",       "enabled": true,  "script": "collectors/pentest.sh"       },
    { "id": "ssdlc",         "enabled": true,  "script": "collectors/ssdlc.sh"         },
    { "id": "source-delivery","enabled": true, "script": "collectors/source-delivery.sh"},
    { "id": "crypto-audit",  "enabled": true,  "script": "collectors/crypto-audit.sh"  },
    { "id": "cve-report",    "enabled": true,  "script": "collectors/cve-report.sh"    },
    { "id": "ai-safety",     "enabled": false, "script": "collectors/ai-safety.sh"     },
    { "id": "ai-supply-chain","enabled": false,"script": "collectors/ai-supply-chain.sh"}
  ],
  "event_collectors": [
    {
      "id": "cve-alert",
      "enabled": true,
      "trigger": "repository_dispatch",
      "event_type": "cve-alert",
      "script": "collectors/cve-alert.sh"
    }
  ],
  "monitor": {
    "heartbeat": {
      "enabled": true,
      "timeout_hours": 24
    },
    "posture_check": {
      "enabled": true
    },
    "drills": {
      "enabled": true,
      "frequency_months": 6,
      "notify_days_before": [30, 7, 1],
      "contacts": []
    },
    "adapters": []
  },
  "exercises": {
    "redteam": {
      "enabled": false,
      "schedule": "0 3 * * 1",
      "playbooks": ["web-app-attack"]
    }
  },
  "notify": {
    "email": {
      "enabled": true,
      "recipients": ["lightman.chang@gmail.com"]
    }
  },
  "qa": {
    "search_hit_threshold": 0.95,
    "answer_rate_threshold": 0.98,
    "citation_accuracy_threshold": 0.98
  },
  "git": {
    "main_branch": "main",
    "publish_branch": "audit",
    "review_branch_prefix": "isms/review-"
  },
  "ui": {
    "locale": "zh-TW",
    "assistant_title": "AI 稽核助理",
    "welcome_message": "👋 你好！請輸入問題，我將根據 ISMS 文件回答，並附上文件來源。",
    "drill_welcome_message": "請選擇評鑑範圍並按「開始模擬評鑑」開始 ISO 27001 稽核模擬。",
    "doc_group_labels": {
      "01": "資訊安全手冊",
      "POL": "政策",
      "PRO": "程序",
      "WKI": "作業指引",
      "STD": "標準",
      "GDL": "指南",
      "FRM": "表單",
      "REG": "登錄冊",
      "PLN": "計畫",
      "SOA": "適用性聲明",
      "MTX": "矩陣"
    },
    "scan_display_names": {
      "sast-result":            "SAST 靜態分析",
      "vulnerability-result":   "弱點掃描",
      "pentest-result":         "滲透測試",
      "ssdlc-result":           "SSDLC 合規",
      "sbom-result":            "SBOM 軟體清單",
      "cve-report-result":      "CVE 月報",
      "source-delivery-result": "源碼交付",
      "crypto-audit-result":    "密碼學稽核",
      "ai-safety-result":       "AI 安全",
      "ai-supply-chain-result": "AI 供應鏈"
    },
    "status_labels": {
      "completed": "完成",
      "pass": "通過",
      "fail": "失敗",
      "warning": "警告",
      "error": "錯誤"
    }
  },
  "domain": {
    "control_id_pattern": "A\\.\\d+\\.\\d+",
    "control_name": "ISO 27001 Annex A",
    "identity_doc_map": {
      "稽核員":     ["07-內部稽核與管理審查程序", "PLN-內部稽核"],
      "開發者":     ["04-安全開發與源碼檢測管理程序", "WKI-源碼安全掃描"],
      "資安長":     ["01-資訊安全手冊", "03-適用性聲明"],
      "IT管理員":   ["05-弱點與滲透測試管理程序", "WKI-弱點掃描"],
      "供應商管理": ["11-採購與供應商管理程序", "FRM-供應商評估"]
    },
    "system_prompt": "你是一位 ISO 27001 資訊安全管理系統稽核助理。根據提供的 ISMS 文件內容回答問題，每個答案必須附上文件來源，格式為 [來源:文件名稱]。若文件中無相關資訊，明確說明「文件中未記載此資訊」。回答使用繁體中文。",
    "drill_system_prompt": "你是一位嚴格的 ISO 27001 認證稽核員，正在進行模擬評鑑。根據受評組織提供的 ISMS 文件，提出稽核問題並評估回答是否符合 ISO 27001:2022 要求。每個問題聚焦於一個具體的控制項或條款，並指出文件中的不符合事項。",
    "metadata_filename": "merge.yaml",
    "form_prefix": "FRM",
    "assessment_controls": [
      { "id": "A.5.1",  "name": "資訊安全政策" },
      { "id": "A.5.2",  "name": "資訊安全角色與責任" },
      { "id": "A.5.15", "name": "存取控制" },
      { "id": "A.5.23", "name": "雲端服務資訊安全" },
      { "id": "A.8.8",  "name": "技術弱點管理" },
      { "id": "A.8.25", "name": "安全開發生命週期" },
      { "id": "A.8.29", "name": "開發及驗收中的安全測試" }
    ],
    "assessment_controls_covered": ["A.5.1", "A.5.2", "A.5.15", "A.8.8", "A.8.25"],
    "citation_pattern": "\\[來源:[^\\]]+\\]"
  },
  "api": {
    "provider": "anthropic",
    "model": "claude-sonnet-4-20250514",
    "key_env_var": "ANTHROPIC_API_KEY"
  }
}
```

---

## 2. `_meta/types/` — Document Type Definitions

Each file in `_meta/types/` defines the specification for one document type.
Three examples follow (POL, PRO, FRM). See the source repo for the full set
(GDL, MTX, PLN, REG, SOA, STD, WKI).

### `_meta/types/POL.md` — Policy Specification

```markdown
---
type: POL
meta_version: "1.0"
last_updated: "2026-04-15"
---
# POL 類型規範 / POL Type Specification

## 必要章節結構

政策文件（Policy）須依以下順序呈現 7 個章節，所有章節均為必要：

1. **【必要】目的與範圍** — 說明本政策的目的、適用對象、適用範圍及例外排除項
2. **【必要】政策聲明** — 使用 shall（應）語氣，明確列出所有強制要求；建議項使用 should（宜）
3. **【必要】角色與責任** — 列出各職位或角色對本政策的具體責任
4. **【必要】例外處理** — 說明例外申請程序、核准層級、紀錄要求
5. **【必要】違規處置** — 說明違反本政策的後果與懲處機制
6. **【必要】審查與修訂** — 定義審查頻率（至少每年一次）、觸發審查的條件、修訂程序
7. **【必要】相關文件** — 列出向下連結的 PRO 程序文件，以及引用的 STD/GDL 文件

## 語氣與用詞規範

- **shall（應）**：用於強制性要求
- **should（宜）**：用於建議性要求
- **may（得）**：用於許可性陳述
- 政策聲明段落中，每個強制要求句子必須含有「應」或 shall

## 必要元素

- **【必要】政策聲明用 shall 語氣**
- **【必要】7 段結構**
- **【必要】向下連結至 PRO 程序文件**
- **【必要】文件 frontmatter**：須含 document_id（格式 POL-NNN）、iso_27001_controls、owner、next_review_date、change_history

## 交叉引用規則

- **必須向下連結**至少一份 PRO（透過相關文件章節的 document_id 引用）
- **禁止向上引用**其他 POL

## 審查重點

- **P1 shall 語氣**
- **P2 7 段結構**
- **P3 向下連結**：相關文件章節列出至少一份 PRO 的 document_id

## 類型特定關鍵字

`shall`、`政策聲明`、`向下連結`
```

### `_meta/types/PRO.md` — Procedure Specification

```markdown
---
type: PRO
meta_version: "1.0"
last_updated: "2026-04-15"
---
# PRO 類型規範 / PRO Type Specification

## 必要章節結構

程序文件（Procedure）須依以下順序呈現 7 個章節：

1. **【必要】目的與範圍**
2. **【必要】相關文件** — 列出上位 POL（parent_policy）、引用的 STD/GDL/WKI/FRM
3. **【必要】角色與責任（RACI）** — 使用 RACI 矩陣
4. **【必要】程序步驟（含流程圖）** — 須包含 Mermaid 流程圖
5. **【必要】監控與量測（含 SLA）** — 所有 SLA 須含具體時限數字
6. **【必要】紀錄與保存** — 保存期限、儲存位置、銷毀方式
7. **【必要】附錄** — 相關 FRM 表單、WKI 操作說明

## 必要元素

- **【必要】parent_policy 引用**：標示為 `parent_policy`，格式 POL-NNN
- **【必要】RACI 矩陣**：Markdown 表格，涵蓋至少 3 個關鍵程序活動
- **【必要】SLA 數字（含時限）**：如「Critical 24 小時、High 7 個工作天」
- **【必要】Mermaid 流程圖**：含決策菱形節點

## 審查重點

- **PR1 parent_policy**
- **PR2 RACI**
- **PR3 SLA 數字**
- **PR4 工具對應**：若有 automation，對應 WKI 存在

## 類型特定關鍵字

`RACI`、`parent_policy`、`SLA`、`流程圖`
```

### `_meta/types/FRM.md` — Form Specification

```markdown
---
type: FRM
meta_version: "1.0"
last_updated: "2026-04-15"
---
# FRM 類型規範 / FRM Type Specification

## 必要章節結構

表單文件（Form）須依以下順序呈現 5 個章節：

1. **【必要】表單資訊（編號／版本／分類）** — document_id、版本、對應程序 PRO document_id、保存期限
2. **【必要】填寫說明** — 祈使句，逐一說明每個欄位；必填欄位標示 *
3. **【必要】表單欄位（含必填標示）** — Markdown 表格；欄位名稱、說明、格式/範例、必填/選填
4. **【必要】核准與簽核區段** — 核准者職位/角色、姓名、日期；至少一個核准層級
5. **【必要】附件與備註**

## 必要元素

- **【必要】必填欄位標示 \***
- **【必要】核准/簽核區段（含日期欄）**
- **【必要】填寫說明（每個欄位的填法）**
- **【必要】文件 frontmatter**：須含 document_id（格式 FRM-NNN）

## 審查重點

- **F1 必填標示 \***
- **F2 核准區段**：含核准者職位/角色欄、姓名欄、日期欄

## 類型特定關鍵字

`必填`、`核准區段`、`填寫說明`
```

---

## 3. `_meta/rule.md`, `writer.md`, `reviewer.md` — Meta Infrastructure

The `_meta/` directory contains three files that govern the closed-loop quality system
for generating and reviewing per-document `rule.md`, `writer.md`, and `reviewer.md`.

### `_meta/rule.md` (first 35 lines)

```markdown
# Meta-Rule：閉環檔案品質規範

## 標記慣例
- 必要條目使用 **【必要】** 前綴
- 建議條目使用 【建議】 前綴
- reviewer.md 的 checkbox 必須覆蓋所有【必要】條目

## rule.md 的合格標準
- **【必要】** 包含「必要章節結構」區段，列出該文件必須有的章節（有序）
- **【必要】** 包含「語氣與用詞規範」區段
- **【必要】** 包含「必要元素」區段（如 RACI、SLA、流程圖等，依類型而異）
- **【必要】** 包含「交叉引用規則」區段
- **【必要】** 包含「審查重點」區段（對應 reviewer.md 的檢查碼）
- **【必要】** 每個必要條目使用【必要】標記
- **【必要】** 不含「待補充」「TBD」「TODO」等佔位符

## 閉環不變量（Invariants）
1. rule.md【必要】數 ≤ reviewer.md checkbox 數
2. writer.md 章節結構 ⊇ rule.md 必要章節結構
3. 三份檔案不含「待補充」「TBD」「TODO」
4. 三份檔案的 document_id 與 merge.yaml 一致
```

### `_meta/writer.md` (first 35 lines)

```markdown
# Meta-Writer：AI Agent 內容產生指引

## 讀取順序
1. _meta/rule.md — 了解合格標準與標記慣例
2. _meta/types/{TYPE}.md — 取得類型規範模板
3. _meta/overrides/{DOC_ID}.md — 取得特殊規範（若存在）
4. 目標資料夾/merge.yaml — 取得元資料、引用、automation
5. 目標資料夾/CLAUDE.md — 取得資料夾指引
6. scripts/scanners/{script}.sh — 取得 scanner 上下文（若 automation 有指定）

## 產出流程
### Step 1: 產出 rule.md
- 以 types/{TYPE}.md 為基礎
- 合併 overrides/{DOC_ID}.md 的額外規範（若存在）
- 注入 merge.yaml 的 automation/scanner 上下文（若有）
- 所有必要條目使用【必要】標記

### Step 2: 從 rule.md 衍生 writer.md
- 將 rule.md「必要章節結構」轉化為寫作框架
- 從 types/{TYPE}.md 的「語氣與用詞規範」提取寫作風格指引

### Step 3: 從 rule.md 鏡像產出 reviewer.md
- 結構性檢查區段：繼承全域 G1-G6 規則
- 內容檢查區段：rule.md 每個【必要】→ 一個 checkbox
- 類型檢查區段：types/{TYPE}.md 的審查重點

## 禁止事項
- 不得產出含「待補充」「TBD」「TODO」的內容
- 不得產出與其他資料夾完全相同的 reviewer.md
```

### `_meta/reviewer.md` (first 35 lines)

```markdown
# Meta-Reviewer：閉環完備性判斷標準

## stub 判定（用於 audit.sh RC-2, RC-3, RC-4）

### rule.md stub 判定 (RC-2)
下列任一為 true → stub：
- 含「待補充」「TBD」「TODO」「FIXME」
- 不含任何「【必要】」標記

### writer.md stub 判定 (RC-3)
下列任一為 true → stub：
- 含「待補充」「TBD」「TODO」「FIXME」
- 不含「rule.md」引用（代表未連結到規範來源）

### reviewer.md stub 判定 (RC-4)
下列任一為 true → stub：
- 含「待補充」「TBD」「TODO」「FIXME」
- checkbox 數量 ≤ 10（通用模板的 checkbox 數）
- 不含類型特定關鍵字（見下方）

## 類型特定關鍵字（用於 RC-4 差異化判定）
| 類型 | 必含關鍵字（至少一個）|
|------|---------------------|
| POL  | shall、政策聲明、向下連結 |
| PRO  | RACI、parent_policy、SLA、流程圖 |
| WKI  | parent_procedure、可執行指令、預期輸出 |
| FRM  | 必填、核准區段、填寫說明 |
| REG  | 表格格式、更新頻率 |
| PLN  | 行動表格、負責人、期限 |
| SOA  | 93、控制項、排除理由 |
| MTX  | 掃描器、SOA、追溯 |
```

---

## 4. `knowledge/` (or domain root) — Document Folder Structure

In the ISO 27001 instance, documents live under `isms/` using a **document-based**
architecture (one folder per document). Two naming patterns coexist:

```
isms/
├── _meta/                          ← Infrastructure: type specs, rule/writer/reviewer
│   ├── types/
│   │   ├── POL.md
│   │   ├── PRO.md
│   │   ├── FRM.md
│   │   └── ...（GDL, MTX, PLN, REG, SOA, STD, WKI）
│   ├── rule.md
│   ├── writer.md
│   └── reviewer.md
│
├── 01-資訊安全手冊/                 ← Core 12 documents: {序號}-{中文名}/
├── 02-風險管理程序/
├── 03-適用性聲明/
├── 04-安全開發與源碼檢測管理程序/
├── 05-弱點與滲透測試管理程序/
├── 06-變更管理程序/
├── 07-內部稽核與管理審查程序/
├── 08-不符合與矯正措施程序/
├── 09-文件管制程序/
├── 10-教育訓練程序/
├── 11-採購與供應商管理程序/
├── 12-資訊安全事件管理程序/
│
├── POL-存取控制/                   ← Appendix documents: {TYPE}-{中文名}/
├── POL-密碼學/
├── POL-資產管理/
├── POL-資訊安全/
├── POL-供應商管理/
├── PRO-人員安全/
├── WKI-弱點掃描/
├── WKI-源碼安全掃描/
├── WKI-軟體物料清單/
├── WKI-滲透測試/
├── WKI-源碼安全掃描/
├── WKI-完整掃描/
├── WKI-AI對答品質驗證/
├── WKI-CVE月報/
├── WKI-AI供應鏈/
├── WKI-AI安全檢查/
├── WKI-密碼學稽核/
├── WKI-安全開發生命週期檢查/
├── WKI-原始碼交付/
├── STD-安全編碼/
├── STD-密碼學/
├── STD-日誌記錄/
├── STD-AI與LLM安全/
├── GDL-AI與LLM開發/
├── GDL-雲端服務安全/
├── GDL-第三方評估/
├── FRM-事件報告/
├── FRM-例外申請/
├── FRM-供應商評估/
├── FRM-存取申請/
├── FRM-變更申請/
├── FRM-風險評估/
├── REG-資產清冊/
├── REG-法規要求/
├── REG-風險登錄冊/
├── PLN-內部稽核/
├── PLN-安全訓練/
├── PLN-持續改善/
├── PLN-營運持續/
├── PLN-風險處理/
├── SOA-（適用性聲明）/
├── MTX-控制項對照/
├── MTX-ISO與SOC2對照/
└── MTX-ISO與ASVS對照/
```

Each folder contains:

```
07-內部稽核與管理審查程序/
├── CLAUDE.md         ← Per-folder AI agent guidance (inherits isms/CLAUDE.md)
├── rule.md           ← Writing + review shared spec for this document
├── writer.md         ← Agent instructions for writing
├── reviewer.md       ← Agent instructions for reviewing
├── merge.yaml        ← Document metadata and reference declarations
├── 內部稽核與管理審查程序.md      ← zh-TW document
└── 內部稽核與管理審查程序.en.md   ← English document
```

### `merge.yaml` example

```yaml
document_id: PRO-006
title_zh: 採購與供應商管理程序
title_en: Supplier Management Procedure
main:
  zh: 採購與供應商管理程序.md
  en: Supplier-Management.en.md
references:
  - document_id: REG-003
    role: 附表A
  - document_id: FRM-004
    role: 附表B
  - document_id: POL-005
    role: 上位政策
automation:
  script: scripts/scanners/sast.sh
  description_zh: 由 Semgrep 自動執行
  description_en: Automated via Semgrep
automation_source:
  workflow: .github/workflows/scan-projects.yml
  extract:
    - field: schedule
    - field: scan_depth
```

### YAML Frontmatter example (inside a `.md` document)

```yaml
---
document_id: POL-002
title_zh: 存取控制政策
title_en: Access Control Policy
version: "1.0"
status: draft
classification: internal
iso_27001_controls: ["A.5.15", "A.8.3", "A.8.4", "A.8.5"]
soc2_criteria: ["CC6.1", "CC6.2", "CC6.3"]
owner: "[資訊安全長]"
approved_by: "[最高管理階層]"
effective_date: "2026-05-01"
next_review_date: "[審查日期]"
change_history:
  - version: "1.0"
    date: "2026-04-13"
    author: "[作者]"
    description: "初版建立"
---
```

---

## 5. `scripts/lib/core/qa-questions.json` — Seed QA Questions

Five example entries from the ISO 27001 ISMS instance. Each question maps to a
specific document (`expected_doc_key`), an identity persona, and a category.

```json
[
  {
    "id": 1,
    "question": "內部稽核計畫中，年度稽核排程涵蓋哪些月份與範圍？",
    "expected_doc_key": "PLN-內部稽核",
    "identity": "稽核員",
    "category": "稽核管理"
  },
  {
    "id": 2,
    "question": "稽核員執行稽核前，應至少提前多久通知受稽核單位？",
    "expected_doc_key": "07-內部稽核與管理審查程序",
    "identity": "稽核員",
    "category": "稽核管理"
  },
  {
    "id": 3,
    "question": "稽核發現分為哪三個等級？各自的矯正時限為何？",
    "expected_doc_key": "07-內部稽核與管理審查程序",
    "identity": "稽核員",
    "category": "稽核管理"
  },
  {
    "id": 4,
    "question": "不符合項分類中，Critical 弱點（CVSS ≥ 9.0）屬於哪一類不符合？其矯正措施計畫須在識別後幾小時內提出？",
    "expected_doc_key": "08-不符合與矯正措施程序",
    "identity": "稽核員",
    "category": "矯正措施"
  },
  {
    "id": 5,
    "question": "適用性聲明中，ISO 27001 附錄 A 共 93 項控制項，有幾項被判定為不適用？不適用的原因為何？",
    "expected_doc_key": "03-適用性聲明",
    "identity": "稽核員",
    "category": "合規管理"
  }
]
```

**Design principles for seed questions:**
- Cover all document types (PRO, POL, WKI, STD, REG, PLN, SOA, MTX)
- Include at least 2-3 identity personas (e.g., 稽核員, 開發者, IT管理員)
- Each category should have 3-5 questions minimum
- Questions should be specific enough to test search retrieval (not generic)
- At least one question per category should reference a specific number (SLA, threshold, count)

---

## 6. Audit Branch (`publish_branch`) — Output Structure

The `audit` branch is force-pushed by CI after each successful build. It contains
the fully rendered HTML output for auditors.

```
audit/                              ← Root of publish_branch
├── index.html                      ← Document index (all ISMS docs, grouped by type)
├── audit-assistant.html            ← AI audit assistant SPA (search + Q&A)
├── styles.css                      ← Shared design system CSS
├── documents/                      ← Rendered ISMS management documents
│   ├── 01-資訊安全手冊/
│   │   └── index.html
│   ├── 02-風險管理程序/
│   │   └── index.html
│   ├── ...（all 12 core + all appendix documents）
│   ├── POL-存取控制/
│   │   └── index.html
│   ├── MTX-控制項對照/
│   │   └── index.html
│   └── ...
├── forms/                          ← Rendered FRM form documents
│   ├── FRM-事件報告/
│   │   └── index.html
│   └── ...
├── scans/                          ← Scan results per scan run
│   └── 20260414-103043/
│       ├── index.html              ← Scan summary dashboard
│       ├── metadata.json
│       ├── quality-gate.json
│       ├── TwTxGNN/                ← Per-repo scan results
│       │   ├── sast-result.json
│       │   ├── vulnerability-result.json
│       │   ├── sbom-result.json
│       │   ├── crypto-audit-result.json
│       │   └── ...
│       ├── pentest/
│       │   └── index.html
│       ├── compliance/
│       │   └── index.html
│       └── seo/
│           └── index.html
└── projects/                       ← Per-project scan history
    └── yao.care--twtxgnn/
        └── ...
```

**Key files:**

| File | Purpose |
|------|---------|
| `index.html` | Landing page for auditors — lists all documents by type with status badges |
| `audit-assistant.html` | AI assistant SPA — keyword search + LLM Q&A with citations |
| `documents/*/index.html` | Each ISMS document rendered to standalone HTML (Mermaid diagrams rendered) |
| `forms/*/index.html` | Each FRM form rendered to printable HTML |
| `scans/*/index.html` | Security scan dashboard — severity counts, CVSS breakdown, trends |

**Delivery to auditors:** Package as a GitHub Release ZIP attachment (tag: `audit-YYYYMMDD`).
Open `index.html` after unzipping — no server required, all assets are self-contained.

---

## 7. Key Naming Conventions Summary

| Item | Pattern | Example |
|------|---------|---------|
| Core document folder | `{序號}-{中文名}/` | `07-內部稽核與管理審查程序/` |
| Appendix document folder | `{TYPE}-{中文名}/` | `POL-存取控制/`, `WKI-源碼安全掃描/` |
| Document ID | `{TYPE}-{NNN}` | `POL-002`, `PRO-006`, `FRM-003` |
| zh-TW document | `{中文名}.md` | `存取控制政策.md` |
| English document | `{EnglishName}.en.md` | `Access-Control-Policy.en.md` |
| Scan run directory | `YYYYMMDD-HHMMSS/` | `20260414-103043/` |
| Target name | `{org}--{project}` | `yao.care--twtxgnn` (use `--` not `/`) |
| Review branch | `{prefix}YYYYMMDD` | `isms/review-20260415` |
| Release tag | `audit-YYYYMMDD` | `audit-20260419` |
| ISO control ID | `A.{x}.{y}` | `A.8.8`, `A.5.15` |
