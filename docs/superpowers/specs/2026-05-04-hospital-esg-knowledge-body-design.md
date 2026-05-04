# Military Hospital ESG Knowledge Body — Design Spec

> AKORA template for full-scope ESG management at military hospitals.
> Fork once per hospital (Taichung, Kaohsiung); each instance runs independently.

## 1. Background

### 1.1 Problem

Two military hospitals (Taichung and Kaohsiung) have completed ISO 14064-1 GHG inventory reports but lack a unified system to manage ESG across all dimensions — environmental, social, governance — plus hospital accreditation, construction projects, and timeline control.

Current state:
- **Carbon inventory**: 4 complete reports (Taichung 2023/2025, Kaohsiung 2024/2025), high quality, externally verified
- **Teaching hospital accreditation**: Separate AKORA instance exists (`TeachingHospitalAccreditation`), will NOT be merged — content copied as needed
- **Other ESG areas**: Standards and frameworks are publicly available; hospital-specific data requires institutional input

### 1.2 Goals

1. Provide an AI knowledge assistant that answers questions across all ESG dimensions
2. Track project milestones and deadlines (GHG verification, accreditation, construction)
3. Standardize data collection workflows across hospital departments
4. Serve as the single source of truth for ESG documentation

### 1.3 Constraints

- Template designed once, forked for each hospital — no cross-hospital data sharing
- Primary language: Traditional Chinese (zh-TW)
- Must work within AKORA template engine (build, QA, assistant.html)
- No external API dependencies for core functionality
- **Flat directory structure**: AKORA `readDocuments()` reads only one level under `knowledge/`; no nesting allowed

## 2. Document Type System

9 document types, each with a 2-3 letter code used in `document_id` and `merge.yaml` `type:` field:

| Code | Type | Description | RC-4 Keywords |
|------|------|-------------|---------------|
| POL | Policy | Hospital-level ESG policy declarations | shall, policy statement, downstream link |
| PRO | Procedure | Standard operating procedures | RACI, parent_policy, SLA, flowchart |
| RPT | Report | GHG reports, ESG annual reports, self-evaluation reports | data year, total emissions, boundary |
| STD | Standard | External standards and regulatory extracts | clause, requirement, compliance |
| PLN | Plan | Reduction action plans, construction ESG plans | action table, owner, deadline |
| MTX | Matrix | Emission source inventory, stakeholder matrix, timeline matrix | matrix, mapping, traceability |
| FRM | Form | Monthly data collection forms, verification checklists, incident forms | required field, approval section, instructions |
| REG | Record | Meeting minutes, verification records, audit logs | table format, update frequency |
| GDL | Guideline | Calculation methodology, refrigerant management guidelines | reference, formula, example |

`FRM` is the form prefix for the closed-loop form system (`config.json` → `domain.form_prefix: "FRM"`).

Document ID convention: descriptive suffixes (e.g., `RPT-GHG-2023`, `PRO-GHG-INV`, `MTX-EMISSION`) instead of numeric suffixes. This is the chosen convention for this domain.

## 3. Knowledge Directory Structure

**Flat single-level** under `knowledge/`, each folder = one document with `merge.yaml`. Visual grouping by ESG dimension achieved through `ui.doc_group_labels` in config.json.

```
knowledge/
├── RPT-GHG-2023/          E1 | GHG inventory report (base year)
├── RPT-GHG-2024/          E1 | GHG inventory report
├── RPT-GHG-2025/          E1 | GHG inventory report
├── PRO-GHG-INV/           E1 | GHG inventory procedure
├── PRO-GHG-VERIFY/        E1 | Internal verification procedure
├── MTX-EMISSION/           E1 | Emission source inventory matrix
├── GDL-CALC-METHOD/        E1 | Emission calculation methodology guide
├── FRM-DATA-FUEL/          E1 | Monthly fuel data collection form
├── FRM-DATA-ELEC/          E1 | Monthly electricity data collection form
├── FRM-DATA-REF/           E1 | Refrigerant refill record form
├── FRM-DATA-GAS/           E1 | Anesthetic/cylinder/extinguisher record form
│
├── PLN-ENERGY/             E2 | Energy conservation action plan
├── GDL-EQUIP/              E2 | Equipment energy efficiency guideline
├── FRM-ENERGY-MON/         E2 | Monthly energy monitoring form
│
├── PRO-WASTE/              E3 | Medical waste management procedure
├── STD-WASTE-REG/          E3 | Waste regulation summary
├── FRM-WASTE-MON/          E3 | Monthly waste disposal report form
│
├── PRO-WATER/              E4 | Water resource management procedure
├── FRM-WATER-MON/          E4 | Monthly water usage monitoring form
│
├── STD-ACCRED/             S1 | Accreditation criteria summary
├── RPT-SELF-EVAL/          S1 | Self-evaluation report skeleton
│
├── PRO-OHS/                S2 | Occupational health and safety procedure
├── FRM-INCIDENT/           S2 | Incident report form
├── REG-OHS-COMMITTEE/      S2 | OHS committee meeting record
│
├── RPT-COMMUNITY/          S3 | Community healthcare service report
├── FRM-SATISFACTION/       S3 | Patient satisfaction survey form
│
├── POL-ESG/                G1 | ESG policy declaration
├── PRO-ESG-COMMITTEE/      G1 | ESG committee operating procedure
├── MTX-STAKEHOLDER/        G1 | Stakeholder identification matrix
├── MTX-RISK-CLIMATE/       G1 | Climate risk assessment (TCFD)
│
├── PLN-CONSTRUCTION/       G2 | Construction ESG planning document
├── FRM-MILESTONE/          G2 | Construction milestone tracking form
├── GDL-GREEN-BUILD/        G2 | Green building design guideline
│
├── PLN-ANNUAL/             G3 | Annual ESG work plan
├── MTX-TIMELINE/           G3 | Master timeline matrix
└── FRM-PROGRESS/           G3 | Progress tracking form
```

Total: 36 document slots across 10 sub-dimensions (E1-E4, S1-S3, G1-G3).

## 4. Content Strategy Per Dimension

### 4.1 E1 Carbon Inventory (richest content)

Source: 4 PDF/DOCX reports converted to Markdown, split by chapter.

Each `RPT-GHG-YYYY` contains:
- Chapter 1: Hospital intro and organizational structure
- Chapter 2: Organizational and reporting boundary
- Chapter 3: Base year setting
- Chapter 4: Emission data (Category 1 + Category 2)
- Chapter 5: Data quality management (calculation methods, emission factors, uncertainty)
- Chapter 6: Verification
- Chapter 7: Report management

Supporting documents built from report content:
- `PRO-GHG-INV`: Extract the inventory procedure from report descriptions
- `PRO-GHG-VERIFY`: Extract verification procedure (internal + external)
- `MTX-EMISSION`: Build emission source matrix from boundary tables (Table 2-1 equivalent)
- `GDL-CALC-METHOD`: Extract calculation formulas and emission factor tables
- `FRM-DATA-*`: Design monthly collection forms based on data sources described in reports

### 4.2 E2-E4 Environmental Management (skeleton + public standards)

Build from:
- Energy Bureau guidelines, EPA waste management regulations (public)
- Hospital-specific data structure defined in FRM templates (to be filled by hospital staff)

### 4.3 S1 Hospital Accreditation (reference copy)

Copy relevant sections from `TeachingHospitalAccreditation` knowledge body.
Keep minimal — just enough for cross-reference in ESG context.

### 4.4 S2-S3 Social (skeleton)

Build procedure skeletons from regulatory frameworks (Occupational Safety and Health Act, etc.).
Content to be filled by hospital staff.

### 4.5 G1 ESG Governance (framework-based)

Build from TCFD/TNFD public frameworks. ESG policy declaration is a skeleton for hospital to customize.

### 4.6 G2 Construction Management (skeleton)

Pure skeleton. Hospital provides project-specific content.

### 4.7 G3 Timeline Control (mechanism)

`MTX-TIMELINE` folder contains a `milestones.yaml` data file listing all milestones with due dates, owners, and status. The `deadline-check.sh` collector reads this file daily. Session Start Checklist reports upcoming deadlines.

## 5. `_meta/` Infrastructure

### 5.1 `_meta/rule.md`

Adapted from the AKORA meta-rule template for ESG domain:

- **Mandatory marker**: 【必要】for required items, 【建議】for recommended
- **Section structure requirements**: per document type
- **Terminology conventions**: ESG domain terms (排放量, 類別1, 組織邊界, 盤查, 查證)
- **Cross-reference rules**: POL → PRO, PRO → FRM, RPT → MTX
- **Invariants**: rule.md required count <= reviewer.md checkbox count; no TBD/TODO

### 5.2 `_meta/writer.md`

Reading order:
1. `_meta/rule.md` — quality standards
2. `_meta/types/{TYPE}.md` — type specification
3. `_meta/overrides/{DOC_ID}.md` — document-specific overrides (if exists)
4. Target folder `merge.yaml` — metadata

Production flow: rule.md → writer.md → reviewer.md (closed-loop triad per document).

### 5.3 `_meta/reviewer.md`

Stub detection rules (RC-2/3/4) with ESG type-specific keywords as defined in Section 2's "RC-4 Keywords" column.

### 5.4 `_meta/types/*.md` — One per document type

9 type specification files:

**`_meta/types/RPT.md`** (critical — GHG reports are the richest content):
- Required sections: purpose, organizational boundary, reporting boundary, emission data, data quality, verification, report management
- Required elements: data year, base year reference, total emissions figure, Category 1/2 breakdown
- Terminology: shall use ISO 14064-1 terminology
- Review checkpoints: R1 boundary completeness, R2 emission data consistency, R3 uncertainty analysis present

**`_meta/types/FRM.md`** (critical — monthly data collection forms):
- Required sections: form info, instructions, form fields (with required/optional markers), approval section, attachments
- Required elements: required field markers (*), approval/sign-off section with date
- Review checkpoints: F1 required field markers, F2 approval section present

**`_meta/types/MTX.md`**:
- Required sections: matrix purpose, row/column definitions, data sources, update frequency
- Required elements: table format, traceability to source documents
- Review checkpoints: M1 table format, M2 source traceability

**`_meta/types/POL.md`**: 7-section structure (purpose, policy statement, roles, exceptions, violations, review, related docs). Shall/should/may terminology.

**`_meta/types/PRO.md`**: 7-section structure (purpose, related docs, RACI, procedure steps with flowchart, monitoring/SLA, records, appendix). Parent_policy reference required.

**`_meta/types/PLN.md`**: Action table with owner, deadline, status. Timeline or Gantt reference.

**`_meta/types/STD.md`**: Clause extraction from external standards. Source attribution required.

**`_meta/types/REG.md`**: Table format records. Update frequency stated. Log format.

**`_meta/types/GDL.md`**: Reference-based guidance. Formulas, examples, step-by-step instructions.

### 5.5 `_meta/glossary.json`

Produced by scanning all `knowledge/` documents and extracting:
- Abbreviations: GHG, CO2e, tCO2e, GWP, IPCC, AR5/AR6, TCFD, SBTi, ESG
- Domain terms: 類別1/類別2, 排放係數, 逸散源, 移動源, 固定源, 營運控制法, 組織邊界
- Refrigerant codes: R-32, R-134a, R-410A, HFCs, PFCs, SF6
- Hospital terms: 碳盤查小組, 醫務企劃管理室, 行政組, 醫勤組

Format: `{"abbreviation": "full name", ...}`

## 6. Collectors

| ID | Script | Schedule | Purpose |
|----|--------|----------|---------|
| `deadline-check` | `collectors/deadline-check.sh` | Daily | Scan `MTX-TIMELINE/milestones.yaml` for upcoming/overdue milestones |
| `emission-calc` | `collectors/emission-calc.sh` | Monthly | Read FRM monthly data, calculate emissions using GDL-CALC-METHOD factors |
| `regulation-watch` | `collectors/regulation-watch.sh` | Weekly | Monitor EPA/MOEA regulation updates (skeleton, needs RSS/API config) |

## 7. Timeline Control Integration

### 7.1 MTX-TIMELINE Structure

`merge.yaml` (standard metadata only — no `fields` key, which is FRM-only):
```yaml
document_id: MTX-TIMELINE
type: MTX
title_zh: 關鍵時程總表
title_en: Master Timeline Matrix
main:
  zh: 關鍵時程總表.md
```

`milestones.yaml` (separate data file, read by `deadline-check.sh`):
```yaml
milestones:
  - id: GHG-DATA-CLOSE
    name: 溫盤數據截止
    category: E1-碳盤查
    due_date: 2027-01-15
    status: pending
    owner: 醫務企劃管理室
  - id: GHG-S1
    name: 溫盤 S1 查證
    category: E1-碳盤查
    due_date: 2027-01-31
    status: pending
    owner: 醫務企劃管理室
  - id: GHG-S2
    name: 溫盤 S2 查證
    category: E1-碳盤查
    due_date: 2027-02-28
    status: pending
    owner: 醫務企劃管理室
  - id: GHG-FINAL
    name: 溫盤報告定版
    category: E1-碳盤查
    due_date: 2027-03-15
    status: pending
    owner: 醫務企劃管理室
  - id: ACCRED-SUBMIT
    name: 評鑑資料送件
    category: S1-醫院評鑑
    due_date: null
    status: pending
    owner: 醫教部
```

### 7.2 Session Start Integration

Normal mode Session Start Checklist adds:

```bash
# 8. Upcoming deadlines (next 30 days)
bash collectors/deadline-check.sh --days 30 2>/dev/null
```

Reports overdue and upcoming milestones alongside existing QA/CI/glossary checks.

## 8. QA Seed Questions

~50 questions in `scripts/lib/core/qa-questions.json`. Each entry has: `id`, `question`, `expected_doc_key`, `identity`, `category`.

### 8.1 Identity Personas

| Persona | Description | Key documents |
|---------|-------------|---------------|
| 碳盤查管理員 | Carbon inventory staff | RPT-GHG-*, PRO-GHG-*, MTX-EMISSION, GDL-CALC-METHOD |
| ESG委員會 | ESG committee members | POL-ESG, PRO-ESG-COMMITTEE, MTX-STAKEHOLDER, PLN-ANNUAL |
| 設施管理員 | Facility/equipment manager | FRM-DATA-*, PLN-ENERGY, GDL-EQUIP, PLN-CONSTRUCTION |
| 環安衛人員 | OHS and environmental staff | PRO-OHS, PRO-WASTE, PRO-WATER, FRM-INCIDENT |

### 8.2 Example Entries

```json
[
  {
    "id": 1,
    "question": "哪些建築物納入溫室氣體盤查邊界？",
    "expected_doc_key": "RPT-GHG-2025",
    "identity": "碳盤查管理員",
    "category": "E1-碳盤查"
  },
  {
    "id": 2,
    "question": "冷媒逸散量的計算公式是什麼？",
    "expected_doc_key": "GDL-CALC-METHOD",
    "identity": "碳盤查管理員",
    "category": "E1-碳盤查"
  },
  {
    "id": 3,
    "question": "2025 年類別 2 間接排放佔總排放量的比例？",
    "expected_doc_key": "RPT-GHG-2025",
    "identity": "碳盤查管理員",
    "category": "E1-碳盤查"
  },
  {
    "id": 4,
    "question": "柴油的 CO2 排放係數是多少？引用來源為何？",
    "expected_doc_key": "GDL-CALC-METHOD",
    "identity": "碳盤查管理員",
    "category": "E1-碳盤查"
  },
  {
    "id": 5,
    "question": "ESG 委員會的成員組成與各單位執掌？",
    "expected_doc_key": "PRO-ESG-COMMITTEE",
    "identity": "ESG委員會",
    "category": "G1-ESG治理"
  },
  {
    "id": 6,
    "question": "職災事件通報流程是什麼？",
    "expected_doc_key": "PRO-OHS",
    "identity": "環安衛人員",
    "category": "S2-職業安全"
  },
  {
    "id": 7,
    "question": "溫盤 S1 查證的預定日期是什麼時候？",
    "expected_doc_key": "MTX-TIMELINE",
    "identity": "ESG委員會",
    "category": "G3-時程管制"
  },
  {
    "id": 8,
    "question": "醫療廢棄物的分類標準是什麼？",
    "expected_doc_key": "PRO-WASTE",
    "identity": "環安衛人員",
    "category": "E3-廢棄物"
  },
  {
    "id": 9,
    "question": "新建大樓的 ESG 規劃要點有哪些？",
    "expected_doc_key": "PLN-CONSTRUCTION",
    "identity": "設施管理員",
    "category": "G2-建案管理"
  },
  {
    "id": 10,
    "question": "利害關係人鑑別採用哪些評分準則？",
    "expected_doc_key": "MTX-STAKEHOLDER",
    "identity": "ESG委員會",
    "category": "G1-ESG治理"
  }
]
```

Full 50 questions to be generated during wizard Step 5, covering all 10 sub-dimensions with at least 3 questions each.

## 9. GitHub Issue Templates

The following FRM documents also produce `.github/ISSUE_TEMPLATE/*.yml` for data collection via GitHub Issues:

| Template | Source FRM | Purpose |
|----------|-----------|---------|
| `incident-report.yml` | FRM-INCIDENT | Staff reports OHS incidents |
| `progress-update.yml` | FRM-PROGRESS | Monthly ESG progress update |
| `satisfaction-survey.yml` | FRM-SATISFACTION | Patient satisfaction data entry |

Each template mirrors the FRM's field definitions, with appropriate GitHub Issue form components (dropdown, input, textarea, checkboxes).

## 10. GitHub Actions Workflow Customization

Based on the AKORA template's 10 workflows:

| Workflow | Status | Customization |
|----------|--------|---------------|
| `collect.yml` | Active | Cron: `0 6 * * *` (daily 06:00 UTC for deadline-check). `emission-calc` and `regulation-watch` use internal schedule guards. |
| `publish.yml` | Active | Default (trigger on knowledge/ changes) |
| `qa-report.yml` | Active | Default (monthly 1st) |
| `review.yml` | Active | Default |
| `record-status.yml` | Active | Default |
| `remediation-verify.yml` | Active | Default |
| `monitor.yml` | Inactive | No runtime targets to monitor |
| `drill-monitor.yml` | Inactive | No drills configured |
| `exercises.yml` | Inactive | No exercises configured |

## 11. config.json — Complete

```json
{
  "knowledge_body": {
    "name": "醫院 ESG 管理系統",
    "name_en": "hospital-esg",
    "description": "軍醫院 ESG 全構面管理：碳盤查、能源、廢棄物、評鑑、職安、治理、建案、時程管制",
    "organization": ""
  },
  "data_sources": {
    "documents": {
      "enabled": true,
      "path": "knowledge/",
      "types": ["POL", "PRO", "RPT", "STD", "PLN", "MTX", "FRM", "REG", "GDL"]
    },
    "tables": {
      "collected": { "enabled": false, "path": "data/collected/" },
      "reported": { "enabled": false, "path": "data/reported/" }
    },
    "external": [],
    "imports": {
      "enabled": true,
      "path": "imports/",
      "parsers": ["pdf", "office"]
    }
  },
  "targets": [],
  "collectors": [
    { "id": "deadline-check", "enabled": true, "script": "collectors/deadline-check.sh" },
    { "id": "emission-calc", "enabled": true, "script": "collectors/emission-calc.sh" },
    { "id": "regulation-watch", "enabled": false, "script": "collectors/regulation-watch.sh" }
  ],
  "event_collectors": [],
  "monitor": {
    "heartbeat": { "enabled": false, "timeout_hours": 24 },
    "posture_check": { "enabled": false },
    "drills": {
      "enabled": false,
      "frequency_months": 6,
      "notify_days_before": [30, 7, 1],
      "contacts": []
    },
    "adapters": []
  },
  "exercises": {
    "enabled": false,
    "schedule": "",
    "playbooks": []
  },
  "notify": {
    "email": {
      "enabled": false,
      "recipients": []
    }
  },
  "chunk_threshold": 2000,
  "chunk_overlap": 200,
  "search_boost": {
    "local": 1.0,
    "external": 1.0
  },
  "qa": {
    "search_hit_threshold": 0.95,
    "answer_rate_threshold": 0.98,
    "citation_accuracy_threshold": 0.98
  },
  "git": {
    "main_branch": "main",
    "publish_branch": "audit",
    "review_branch_prefix": "esg/review-"
  },
  "ui": {
    "locale": "zh-TW",
    "assistant_title": "ESG 管理助理",
    "welcome_message": "你好！我是醫院 ESG 管理助理。請輸入問題，我將根據 ESG 文件回答，並附上文件來源。",
    "drill_welcome_message": "",
    "doc_group_labels": {
      "POL": "政策",
      "PRO": "程序",
      "RPT": "報告",
      "STD": "標準",
      "PLN": "計畫",
      "MTX": "矩陣",
      "FRM": "表單",
      "REG": "紀錄",
      "GDL": "指引"
    },
    "scan_display_names": {},
    "no_result_message": "根據目前知識庫的文件，查無相關資料。建議嘗試不同關鍵詞描述，或洽詢 ESG 委員會承辦人員。",
    "status_labels": {
      "completed": "完成",
      "pass": "通過",
      "fail": "失敗",
      "warning": "警告",
      "error": "錯誤"
    }
  },
  "domain": {
    "control_id_pattern": "",
    "control_name": "",
    "identity_doc_map": {
      "碳盤查管理員": ["RPT-GHG-2023", "RPT-GHG-2024", "RPT-GHG-2025", "PRO-GHG-INV", "PRO-GHG-VERIFY", "MTX-EMISSION", "GDL-CALC-METHOD"],
      "ESG委員會": ["POL-ESG", "PRO-ESG-COMMITTEE", "MTX-STAKEHOLDER", "MTX-RISK-CLIMATE", "PLN-ANNUAL", "MTX-TIMELINE"],
      "設施管理員": ["PLN-ENERGY", "GDL-EQUIP", "PLN-CONSTRUCTION", "GDL-GREEN-BUILD", "FRM-MILESTONE"],
      "環安衛人員": ["PRO-OHS", "PRO-WASTE", "PRO-WATER", "FRM-INCIDENT", "STD-WASTE-REG"]
    },
    "system_prompt": "你是醫院 ESG 管理助理。嚴格根據下方參考資料回答問題。\n\n回答規則：\n1. 僅使用參考資料中的內容回答，不得引用外部知識、標準通則、一般建議或自行推測\n2. 若參考資料不包含答案，直接回覆「文件中未查到相關資訊」，不要提供任何替代建議\n3. 每個回答必須引用來源文件\n4. 不得使用 emoji\n\n引用格式規定：\n- 引用文件時使用 [來源:文件編號#章節] 格式\n- 冒號必須使用半形 :（不是：）\n- 章節使用數字格式（如 #2. 盤查邊界）\n\n範例問答：\n\n使用者：2025 年總排放量是多少？\n助理：根據報告，2025 年國軍臺中總醫院類別 1 與類別 2 之加總溫室氣體排放量為 3,284.073 tCO2e，其中：\n\n1. 類別 1 直接排放：289.7477 tCO2e（8.82%）\n2. 類別 2 間接排放（外購電力）：2,994.3253 tCO2e（91.18%）\n\n[來源:RPT-GHG-2025#3. 溫室氣體排放量]",
    "drill_system_prompt": "",
    "metadata_filename": "merge.yaml",
    "form_prefix": "FRM",
    "assessment_controls": [],
    "assessment_controls_covered": [],
    "citation_pattern": "\\[來源:[^\\]]+\\]"
  },
  "api": {
    "provider": "anthropic",
    "model": "claude-sonnet-4-20250514",
    "key_env_var": "ANTHROPIC_API_KEY"
  },
  "form_submission": {
    "repo": ""
  },
  "profiles": {
    "assistant": {
      "label": "ESG 管理助理",
      "system_prompt_key": "system_prompt",
      "exclude_types": [],
      "exclude_sources": [],
      "qa_questions": "qa-questions.json"
    }
  }
}
```

`organization` left blank — filled during fork (e.g., "國軍臺中總醫院" or "國軍高雄總醫院").
`imports.enabled: true` — used for initial one-time conversion of PDF/DOCX GHG reports to Markdown.

## 12. Fork and Deployment Flow

1. Complete this AKORA template with all skeletons and shared content
2. Run wizard verification on template: `npm run build:assistant` and `npm run qa-report -- --search-only` (both must pass)
3. Fork to `hospital-esg-taichung` repo
   - Set `organization` to "國軍臺中總醫院"
   - Import Taichung GHG reports (2023, 2025)
   - Copy relevant accreditation sections from `TeachingHospitalAccreditation`
   - Customize boundary definitions (exclude 中清分院, include 護理之家/居家護理所)
4. Fork to `hospital-esg-kaohsiung` repo
   - Set `organization` to "國軍高雄總醫院"
   - Import Kaohsiung GHG reports (2024, 2025)
   - Customize boundary definitions (exclude 屏東分院/鳳山, include 蘭園康復之家)
   - Add Kaohsiung-specific sources (天然氣, LPG, SF6 斷路器)
5. Each instance runs `npm run build:assistant` and `npm run qa-report` independently

## 13. Out of Scope

- Cross-hospital comparison dashboards (would require a separate aggregation layer)
- Real-time IoT data integration (smart meters, etc.)
- Automated external verification submission
- TeachingHospitalAccreditation merge (stays independent)
- ESG rating/scoring system (GRI reporting template deferred to future phase)
- Drill/exercise system (no simulation exercises for ESG domain)
