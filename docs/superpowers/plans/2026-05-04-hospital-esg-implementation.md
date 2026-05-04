# Hospital ESG Knowledge Body — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an AKORA knowledge body template covering hospital ESG full scope (carbon inventory, environmental management, social, governance, construction, timeline control), ready to fork for Taichung and Kaohsiung military hospitals.

**Architecture:** AKORA wizard Step 5 output — config.json, _meta/ infrastructure, 36 knowledge documents, 3 collectors, 3 issue templates, 50 QA questions. Flat single-level directory under knowledge/. Content sourced from 4 existing GHG reports (PDF/DOCX) plus domain knowledge for skeleton documents.

**Tech Stack:** AKORA template engine (Node.js), Markdown, YAML, Bash shell scripts, GitHub Actions workflows.

**Spec:** `docs/superpowers/specs/2026-05-04-hospital-esg-knowledge-body-design.md`

**Source reports (read-only, for content extraction):**
- `/Users/lightman/Downloads/國軍臺中總醫院_ISO_14064-1溫室氣體盤查報.pdf` (台中 2023)
- `/Users/lightman/Downloads/2026-03-06_2025年國軍臺中總醫院溫盤報告書(final).docx` (台中 2025)
- `/Users/lightman/Downloads/2025國軍高雄總醫院溫盤報告書_v0319(final).docx` (高雄 2025)
- `/Users/lightman/Downloads/2024國軍高雄總醫院溫盤報告書_v0613（書審）.doc` (高雄 2024)

---

## Task 1: config.json + setup-org.sh

**Files:**
- Create: `config.json`
- Modify: (none — setup-org.sh already exists)

- [ ] **Step 1: Write config.json**

Copy the complete JSON from spec Section 11 verbatim into `config.json`. The `organization` field stays empty (filled during fork).

- [ ] **Step 2: Verify config loads**

Run: `node -e "const c = require('./config.json'); console.log(c.knowledge_body.name)"`
Expected: `醫院 ESG 管理系統`

- [ ] **Step 3: Run setup-org.sh**

Run: `bash scripts/setup-org.sh`
Expected: GitHub labels created (or skipped if no remote configured)

- [ ] **Step 4: Commit**

```bash
git add config.json
git commit -m "feat: add hospital ESG config.json (wizard Step 5)"
```

---

## Task 2: _meta/ Infrastructure — rule.md, writer.md, reviewer.md

**Files:**
- Modify: `_meta/rule.md`
- Modify: `_meta/writer.md`
- Modify: `_meta/reviewer.md`

**Context:** These files currently contain minimal stubs. Replace with full ESG-domain content per spec Section 5.1-5.3. Reference the ISO 27001 example at `reference/iso27001-example.md` Section 3 for format and depth expectations.

- [ ] **Step 1: Read existing _meta/ stubs**

Run: `cat _meta/rule.md _meta/writer.md _meta/reviewer.md`
Purpose: Understand what's there before overwriting.

- [ ] **Step 2: Write _meta/rule.md**

Replace with ESG domain meta-rule. Must include:
- 標記慣例 (【必要】/【建議】)
- rule.md 合格標準 (6 mandatory items)
- 閉環不變量 (4 invariants)
- ESG 領域術語規範 (排放量, 類別1/2, 組織邊界, 盤查, 查證)
- 交叉引用規則 (POL→PRO, PRO→FRM, RPT→MTX)

- [ ] **Step 3: Write _meta/writer.md**

Replace with ESG domain meta-writer. Must include:
- 讀取順序 (rule.md → types/{TYPE}.md → overrides/{DOC_ID}.md → merge.yaml)
- 產出流程 (Step 1: rule.md, Step 2: writer.md, Step 3: reviewer.md)
- 禁止事項 (no TBD/TODO, no duplicate reviewer.md)
- ESG 寫作風格 (ISO 14064-1 terminology, zh-TW)

- [ ] **Step 4: Write _meta/reviewer.md**

Replace with ESG domain meta-reviewer. Must include:
- stub 判定 (RC-2, RC-3, RC-4 rules)
- 類型特定關鍵字 table for all 9 types (from spec Section 2 "RC-4 Keywords" column):
  - POL: shall, 政策聲明, 向下連結
  - PRO: RACI, parent_policy, SLA, 流程圖
  - RPT: 數據年度, 總排放量, 邊界
  - STD: 條款, 要求, 合規
  - PLN: 行動表格, 負責人, 期限
  - MTX: 矩陣, 對照, 追溯
  - FRM: 必填, 核准區段, 填寫說明
  - REG: 表格格式, 更新頻率
  - GDL: 參考, 公式, 範例

- [ ] **Step 5: Commit**

```bash
git add _meta/rule.md _meta/writer.md _meta/reviewer.md
git commit -m "feat: ESG domain _meta/ infrastructure (rule, writer, reviewer)"
```

---

## Task 3: _meta/types/*.md — 9 Type Definitions

**Files:**
- Create: `_meta/types/POL.md`
- Create: `_meta/types/PRO.md`
- Create: `_meta/types/RPT.md`
- Create: `_meta/types/STD.md`
- Create: `_meta/types/PLN.md`
- Create: `_meta/types/MTX.md`
- Create: `_meta/types/FRM.md`
- Create: `_meta/types/REG.md`
- Create: `_meta/types/GDL.md`

**Context:** Reference `reference/iso27001-example.md` Section 2 for format. Each file follows the pattern: YAML frontmatter (type, meta_version, last_updated) → 必要章節結構 → 語氣與用詞規範 → 必要元素 → 交叉引用規則 → 審查重點 → 類型特定關鍵字.

- [ ] **Step 1: Write RPT.md (critical — GHG reports)**

Per spec Section 5.4. Required sections: purpose, organizational boundary, reporting boundary, emission data, data quality, verification, report management. Required elements: data year, base year reference, total emissions, Category 1/2 breakdown. Review checkpoints: R1 boundary, R2 emission data, R3 uncertainty.

- [ ] **Step 2: Write FRM.md (critical — monthly forms)**

Per spec Section 5.4. 5-section structure: form info, instructions, form fields with required markers, approval section, attachments. Review checkpoints: F1 required markers, F2 approval section.

- [ ] **Step 3: Write MTX.md**

Per spec Section 5.4. Required: matrix purpose, row/column definitions, data sources, update frequency. Review: M1 table format, M2 traceability.

- [ ] **Step 4: Write POL.md**

7-section structure per spec. Shall/should/may terminology. Downstream link to PRO required.

- [ ] **Step 5: Write PRO.md**

7-section structure per spec. RACI matrix, parent_policy reference, Mermaid flowchart, SLA required.

- [ ] **Step 6: Write PLN.md, STD.md, REG.md, GDL.md**

Remaining 4 types per spec Section 5.4 definitions.

- [ ] **Step 7: Commit**

```bash
git add _meta/types/
git commit -m "feat: 9 ESG document type definitions (_meta/types/)"
```

---

## Task 4: E1 Carbon Inventory — Convert GHG Reports to Markdown

**Files:**
- Create: `knowledge/RPT-GHG-2023/merge.yaml` + `溫室氣體盤查報告書2023.md`
- Create: `knowledge/RPT-GHG-2025/merge.yaml` + `溫室氣體盤查報告書2025.md`

**Context:** Convert the Taichung hospital GHG reports (台中 2023 PDF + 台中 2025 DOCX) to Markdown. Each report has 7 chapters. Tables must be preserved as Markdown tables. The template will be forked — use Taichung data as the default, Kaohsiung fork replaces later.

Note: RPT-GHG-2024 is Kaohsiung-only and will be added during the Kaohsiung fork. The template includes RPT-GHG-2023 and RPT-GHG-2025 (Taichung).

- [ ] **Step 1: Read 台中 2023 PDF**

Read `/Users/lightman/Downloads/國軍臺中總醫院_ISO_14064-1溫室氣體盤查報.pdf` (all 18 pages). Extract text content chapter by chapter.

- [ ] **Step 2: Create RPT-GHG-2023 folder and merge.yaml**

```yaml
document_id: RPT-GHG-2023
type: RPT
title_zh: 2023年溫室氣體盤查報告書
title_en: 2023 GHG Inventory Report
main:
  zh: 溫室氣體盤查報告書2023.md
status: active
owner: 醫務企劃管理室
effective_date: 2025-02-17
next_review_date: 2026-02-17
```

- [ ] **Step 3: Write 溫室氣體盤查報告書2023.md**

Convert PDF content to Markdown preserving: chapter headings (## 第一章, ## 第二章...), all tables (Markdown table format), emission data numbers, emission factor tables, uncertainty analysis. Include YAML frontmatter with document_id, title, version.

- [ ] **Step 4: Read 台中 2025 DOCX**

Run: `textutil -convert txt -stdout '/Users/lightman/Downloads/2026-03-06_2025年國軍臺中總醫院溫盤報告書(final).docx'`
Extract full text content.

- [ ] **Step 5: Create RPT-GHG-2025 folder and merge.yaml**

```yaml
document_id: RPT-GHG-2025
type: RPT
title_zh: 2025年溫室氣體盤查報告書
title_en: 2025 GHG Inventory Report
main:
  zh: 溫室氣體盤查報告書2025.md
status: active
owner: 醫務企劃管理室
effective_date: 2026-03-06
next_review_date: 2027-03-06
```

- [ ] **Step 6: Write 溫室氣體盤查報告書2025.md**

Same conversion approach as Step 3 for the 2025 report.

- [ ] **Step 7: Commit**

```bash
git add knowledge/RPT-GHG-2023/ knowledge/RPT-GHG-2025/
git commit -m "feat: E1 GHG inventory reports (台中 2023, 2025) converted to Markdown"
```

---

## Task 5: E1 Carbon Inventory — Supporting Documents

**Files:**
- Create: `knowledge/PRO-GHG-INV/` (merge.yaml + .md)
- Create: `knowledge/PRO-GHG-VERIFY/` (merge.yaml + .md)
- Create: `knowledge/MTX-EMISSION/` (merge.yaml + .md)
- Create: `knowledge/GDL-CALC-METHOD/` (merge.yaml + .md)
- Create: `knowledge/FRM-DATA-FUEL/` (merge.yaml + .md)
- Create: `knowledge/FRM-DATA-ELEC/` (merge.yaml + .md)
- Create: `knowledge/FRM-DATA-REF/` (merge.yaml + .md)
- Create: `knowledge/FRM-DATA-GAS/` (merge.yaml + .md)

**Context:** Extract content from the GHG reports in Task 4 to build these supporting documents. Per spec Section 4.1.

- [ ] **Step 1: Create PRO-GHG-INV (盤查程序書)**

Extract inventory procedure from report Chapter 1 (推動組織 + 業務執掌) and Chapter 5 (數據蒐集流程). Structure per PRO type spec: purpose, RACI from 碳盤查小組業務執掌表, procedure steps, SLA (annual cycle deadlines).

- [ ] **Step 2: Create PRO-GHG-VERIFY (查證程序書)**

Extract from report Chapter 6 (內部/外部查證). Include internal verification procedure, external verification engagement, S1/S2 stage process.

- [ ] **Step 3: Create MTX-EMISSION (排放源清冊)**

Extract emission source inventory from report Table 2-1 (報告邊界調查表). Build as a matrix: emission source × category × GHG type × quantification method.

- [ ] **Step 4: Create GDL-CALC-METHOD (計算方法指引)**

Extract from report Chapter 5: CO2e formula, emission factor tables (Table 5-1, 5-2), GWP values (AR5), uncertainty calculation method. Include all factor values with units and sources.

- [ ] **Step 5: Create FRM-DATA-FUEL (油料月報表)**

Design monthly data collection form for fuel (柴油, 汽油, 尿素). Fields: month, fuel type, equipment, purchase volume (L), receipt reference. Include `fields:` definition in merge.yaml for form system.

- [ ] **Step 6: Create FRM-DATA-ELEC (電力月報表)**

Monthly electricity form. Fields: month, meter number, kWh reading, billing period, utility bill reference.

- [ ] **Step 7: Create FRM-DATA-REF (冷媒紀錄表)**

Refrigerant refill record. Fields: date, equipment type, equipment ID, refrigerant type (R-32/R-134a/R-410A etc.), refill amount (kg), new/maintenance, technician.

- [ ] **Step 8: Create FRM-DATA-GAS (氣體/滅火器紀錄表)**

Combined form for: anesthetic gas (Sevoflurane/Isoflurane purchase), CO2 cylinders (type, count, fill amount), fire extinguishers (type, count, CO2 fill). Fields per category.

- [ ] **Step 9: Commit**

```bash
git add knowledge/PRO-GHG-INV/ knowledge/PRO-GHG-VERIFY/ knowledge/MTX-EMISSION/ knowledge/GDL-CALC-METHOD/ knowledge/FRM-DATA-FUEL/ knowledge/FRM-DATA-ELEC/ knowledge/FRM-DATA-REF/ knowledge/FRM-DATA-GAS/
git commit -m "feat: E1 supporting documents (procedures, matrix, guideline, forms)"
```

---

## Task 6: E2-E4 Environmental Skeleton Documents

**Files:**
- Create: `knowledge/PLN-ENERGY/` (merge.yaml + .md)
- Create: `knowledge/GDL-EQUIP/` (merge.yaml + .md)
- Create: `knowledge/FRM-ENERGY-MON/` (merge.yaml + .md)
- Create: `knowledge/PRO-WASTE/` (merge.yaml + .md)
- Create: `knowledge/STD-WASTE-REG/` (merge.yaml + .md)
- Create: `knowledge/FRM-WASTE-MON/` (merge.yaml + .md)
- Create: `knowledge/PRO-WATER/` (merge.yaml + .md)
- Create: `knowledge/FRM-WATER-MON/` (merge.yaml + .md)

**Context:** These are skeleton documents with structure from public standards. Hospital-specific data to be filled later. Each must have proper merge.yaml with `type:` field and a .md file with at minimum the required chapter structure per its type spec.

- [ ] **Step 1: Create E2 documents (PLN-ENERGY, GDL-EQUIP, FRM-ENERGY-MON)**

PLN-ENERGY: Energy conservation plan skeleton — action table with categories (lighting, HVAC, equipment), target reduction %, timeline. Reference: hospital electricity is 83-92% of emissions.

GDL-EQUIP: Equipment energy efficiency guideline — LED replacement, inverter AC, high-efficiency chiller selection criteria.

FRM-ENERGY-MON: Monthly energy monitoring form — kWh by zone, comparison vs previous month/year.

- [ ] **Step 2: Create E3 documents (PRO-WASTE, STD-WASTE-REG, FRM-WASTE-MON)**

PRO-WASTE: Medical waste management procedure — classification (一般/感染性/有害), collection, storage, transport, disposal. Reference: 事業廢棄物貯存清除處理方法.

STD-WASTE-REG: Regulatory summary — key clauses from Waste Disposal Act and medical waste regulations.

FRM-WASTE-MON: Monthly waste report form — waste type, weight (kg), disposal contractor, manifest number.

- [ ] **Step 3: Create E4 documents (PRO-WATER, FRM-WATER-MON)**

PRO-WATER: Water management procedure — usage tracking, recycled water, rainwater harvesting potential.

FRM-WATER-MON: Monthly water form — meter reading, usage (cubic meters), comparison.

- [ ] **Step 4: Commit**

```bash
git add knowledge/PLN-ENERGY/ knowledge/GDL-EQUIP/ knowledge/FRM-ENERGY-MON/ knowledge/PRO-WASTE/ knowledge/STD-WASTE-REG/ knowledge/FRM-WASTE-MON/ knowledge/PRO-WATER/ knowledge/FRM-WATER-MON/
git commit -m "feat: E2-E4 environmental skeleton documents (energy, waste, water)"
```

---

## Task 7: S1-S3 Social Skeleton Documents

**Files:**
- Create: `knowledge/STD-ACCRED/` (merge.yaml + .md)
- Create: `knowledge/RPT-SELF-EVAL/` (merge.yaml + .md)
- Create: `knowledge/PRO-OHS/` (merge.yaml + .md)
- Create: `knowledge/FRM-INCIDENT/` (merge.yaml + .md, with `fields:` for form system)
- Create: `knowledge/REG-OHS-COMMITTEE/` (merge.yaml + .md)
- Create: `knowledge/RPT-COMMUNITY/` (merge.yaml + .md)
- Create: `knowledge/FRM-SATISFACTION/` (merge.yaml + .md, with `fields:`)

**Context:** S1 accreditation content is minimal (detailed content stays in TeachingHospitalAccreditation). S2/S3 are skeleton procedures from regulatory frameworks.

- [ ] **Step 1: Create S1 documents (STD-ACCRED, RPT-SELF-EVAL)**

STD-ACCRED: Hospital accreditation criteria summary — list chapter titles and key evaluation items. Keep brief; reference TeachingHospitalAccreditation for detail.

RPT-SELF-EVAL: Self-evaluation report skeleton — section headers matching accreditation criteria, placeholder for hospital to fill.

- [ ] **Step 2: Create S2 documents (PRO-OHS, FRM-INCIDENT, REG-OHS-COMMITTEE)**

PRO-OHS: OHS procedure — hazard identification, incident reporting flow, PPE requirements, training. Reference: 職業安全衛生法.

FRM-INCIDENT: Incident report form with `fields:` definition — date, location, type (dropdown: 針扎/跌倒/化學暴露/其他), description, injury severity, immediate action, reporter.

REG-OHS-COMMITTEE: Committee meeting record template — date, attendees, agenda, decisions, action items.

- [ ] **Step 3: Create S3 documents (RPT-COMMUNITY, FRM-SATISFACTION)**

RPT-COMMUNITY: Community healthcare report skeleton — service categories, outreach events, beneficiary counts.

FRM-SATISFACTION: Patient satisfaction survey form with `fields:` — overall rating (1-5), cleanliness, staff attitude, wait time, open comments.

- [ ] **Step 4: Commit**

```bash
git add knowledge/STD-ACCRED/ knowledge/RPT-SELF-EVAL/ knowledge/PRO-OHS/ knowledge/FRM-INCIDENT/ knowledge/REG-OHS-COMMITTEE/ knowledge/RPT-COMMUNITY/ knowledge/FRM-SATISFACTION/
git commit -m "feat: S1-S3 social skeleton documents (accreditation, OHS, community)"
```

---

## Task 8: G1-G3 Governance, Construction, Timeline Documents

**Files:**
- Create: `knowledge/POL-ESG/` (merge.yaml + .md)
- Create: `knowledge/PRO-ESG-COMMITTEE/` (merge.yaml + .md)
- Create: `knowledge/MTX-STAKEHOLDER/` (merge.yaml + .md)
- Create: `knowledge/MTX-RISK-CLIMATE/` (merge.yaml + .md)
- Create: `knowledge/PLN-CONSTRUCTION/` (merge.yaml + .md)
- Create: `knowledge/FRM-MILESTONE/` (merge.yaml + .md, with `fields:`)
- Create: `knowledge/GDL-GREEN-BUILD/` (merge.yaml + .md)
- Create: `knowledge/PLN-ANNUAL/` (merge.yaml + .md)
- Create: `knowledge/MTX-TIMELINE/` (merge.yaml + .md + `milestones.yaml`)
- Create: `knowledge/FRM-PROGRESS/` (merge.yaml + .md, with `fields:`)

- [ ] **Step 1: Create G1 documents (POL-ESG, PRO-ESG-COMMITTEE, MTX-STAKEHOLDER, MTX-RISK-CLIMATE)**

POL-ESG: ESG policy declaration — 7-section POL structure. Policy statement covering E/S/G commitments. Downstream links to PRO-ESG-COMMITTEE.

PRO-ESG-COMMITTEE: ESG committee procedure — committee composition (based on 碳盤查小組 structure, expanded), meeting frequency, decision-making process, RACI matrix.

MTX-STAKEHOLDER: Stakeholder matrix — rows: 國防部軍醫局/環境部/衛福部/病患/員工/社區/供應商. Columns: 關注議題/溝通方式/頻率/回應機制.

MTX-RISK-CLIMATE: TCFD climate risk assessment — physical risks (extreme weather, flooding) and transition risks (carbon pricing, regulation changes) for hospital operations.

- [ ] **Step 2: Create G2 documents (PLN-CONSTRUCTION, FRM-MILESTONE, GDL-GREEN-BUILD)**

PLN-CONSTRUCTION: Construction ESG planning skeleton — green building targets, energy efficiency specs, waste management during construction, ESG boundary impact assessment.

FRM-MILESTONE: Construction milestone form with `fields:` — milestone name, planned date, actual date, status (dropdown: 未開始/進行中/完成/延遲), notes.

GDL-GREEN-BUILD: Green building guideline — EEWH certification levels, energy performance requirements, indoor air quality, water efficiency.

- [ ] **Step 3: Create G3 documents (PLN-ANNUAL, MTX-TIMELINE, FRM-PROGRESS)**

PLN-ANNUAL: Annual ESG work plan skeleton — action items by quarter, owner, KPI, budget.

MTX-TIMELINE: Create merge.yaml (type: MTX), main .md file (master timeline table), AND `milestones.yaml` data file per spec Section 7.1.

FRM-PROGRESS: Monthly progress form with `fields:` — reporting month, dimension (E1-G3 dropdown), task, status, completion %, notes.

- [ ] **Step 4: Commit**

```bash
git add knowledge/POL-ESG/ knowledge/PRO-ESG-COMMITTEE/ knowledge/MTX-STAKEHOLDER/ knowledge/MTX-RISK-CLIMATE/ knowledge/PLN-CONSTRUCTION/ knowledge/FRM-MILESTONE/ knowledge/GDL-GREEN-BUILD/ knowledge/PLN-ANNUAL/ knowledge/MTX-TIMELINE/ knowledge/FRM-PROGRESS/
git commit -m "feat: G1-G3 governance, construction, timeline documents"
```

---

## Task 9: Collectors

**Files:**
- Create: `collectors/deadline-check.sh`
- Create: `collectors/emission-calc.sh`
- Create: `collectors/regulation-watch.sh`

- [ ] **Step 1: Write deadline-check.sh**

Shell script that:
1. Reads `knowledge/MTX-TIMELINE/milestones.yaml`
2. Accepts `--days N` argument (default 30)
3. Compares each milestone's `due_date` to today
4. Outputs: OVERDUE items (red), upcoming within N days (yellow), on-track (green)
5. Exit 0 always (informational, not a gate)

Requires: `yq` or basic `grep`/`awk` YAML parsing (keep it simple, no heavy deps).

- [ ] **Step 2: Write emission-calc.sh**

Skeleton script with TODO markers for:
1. Read FRM monthly data files
2. Apply emission factors from GDL-CALC-METHOD
3. Output calculated emissions summary
4. Internal schedule guard: only run if current day is 1st of month

This is a skeleton — actual calculation logic to be implemented when real data flows in.

- [ ] **Step 3: Write regulation-watch.sh**

Skeleton script (disabled by default in config):
1. Check EPA/MOEA RSS feeds or URLs for updates
2. Output new regulations since last check
3. Internal schedule guard: weekly

- [ ] **Step 4: Commit**

```bash
git add collectors/deadline-check.sh collectors/emission-calc.sh collectors/regulation-watch.sh
git commit -m "feat: 3 ESG collectors (deadline, emission-calc, regulation-watch)"
```

---

## Task 10: GitHub Issue Templates

**Files:**
- Create: `.github/ISSUE_TEMPLATE/incident-report.yml`
- Create: `.github/ISSUE_TEMPLATE/progress-update.yml`
- Create: `.github/ISSUE_TEMPLATE/satisfaction-survey.yml`

- [ ] **Step 1: Write incident-report.yml**

GitHub Issue form template mirroring FRM-INCIDENT fields:
- name: "職災/異常事件通報"
- description: "通報職業安全衛生事件"
- Fields: date (input), location (input), incident type (dropdown: 針扎/跌倒/化學暴露/其他), description (textarea), severity (dropdown: 輕微/中度/嚴重), immediate action (textarea), reporter name (input)
- Labels: `incident`, `S2-職業安全`

- [ ] **Step 2: Write progress-update.yml**

GitHub Issue form mirroring FRM-PROGRESS fields:
- name: "ESG 月度進度回報"
- description: "每月各構面進度更新"
- Fields: reporting month (input), dimension (dropdown: E1-碳盤查/E2-能源管理/.../G3-時程管制), task description (textarea), status (dropdown: 未開始/進行中/完成/延遲), completion % (input), notes (textarea)
- Labels: `progress`, `monthly`

- [ ] **Step 3: Write satisfaction-survey.yml**

GitHub Issue form mirroring FRM-SATISFACTION fields:
- name: "病患滿意度調查"
- description: "病患滿意度資料登錄"
- Fields: survey date (input), overall rating (dropdown: 1-5), cleanliness (dropdown: 1-5), staff attitude (dropdown: 1-5), wait time (dropdown: 1-5), comments (textarea)
- Labels: `survey`, `S3-社會參與`

- [ ] **Step 4: Commit**

```bash
git add .github/ISSUE_TEMPLATE/
git commit -m "feat: 3 GitHub Issue Templates (incident, progress, satisfaction)"
```

---

## Task 11: QA Seed Questions

**Files:**
- Modify: `scripts/lib/core/qa-questions.json`

**Context:** Currently empty `[]`. Populate with ~50 questions per spec Section 8. Must cover all 10 sub-dimensions (E1-E4, S1-S3, G1-G3), all 4 identity personas, all 9 document types. Each question must have: id, question, expected_doc_key, identity, category.

- [ ] **Step 1: Write 50 QA questions**

Distribution target:
- E1-碳盤查: 15 questions (boundary, calculation, data, factors, verification, base year, uncertainty)
- E2-能源管理: 4 questions
- E3-廢棄物: 3 questions
- E4-水資源: 3 questions
- S1-醫院評鑑: 3 questions
- S2-職業安全: 4 questions
- S3-社會參與: 3 questions
- G1-ESG治理: 5 questions
- G2-建案管理: 4 questions
- G3-時程管制: 6 questions

Use the 10 example entries from spec Section 8.2 as the first 10, then generate 40 more following the same pattern. Each question must reference a specific `expected_doc_key` that exists in the knowledge/ directory.

- [ ] **Step 2: Validate JSON**

Run: `node -e "const q = require('./scripts/lib/core/qa-questions.json'); console.log(q.length + ' questions loaded')"`
Expected: `50 questions loaded`

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/core/qa-questions.json
git commit -m "feat: 50 ESG seed QA questions"
```

---

## Task 12: _meta/glossary.json

**Files:**
- Modify: `_meta/glossary.json`

**Context:** Currently empty `{}`. Scan all knowledge/ .md files and extract abbreviations, domain terms, refrigerant codes, hospital organizational terms per spec Section 5.5.

- [ ] **Step 1: Scan knowledge/ documents and build glossary**

Scan all `knowledge/*/*.md` files. Extract:
- Abbreviations and their full forms: GHG/溫室氣體, CO2e/二氧化碳當量, tCO2e/公噸二氧化碳當量, GWP/全球暖化潛勢, IPCC/政府間氣候變化專門委員會, AR5/第五次評估報告, TCFD/氣候相關財務揭露, ESG/環境社會治理, SBTi/科學基礎減量目標, OHS/職業安全衛生, RACI/負責當責諮詢知會
- Domain terms: 類別1/直接排放, 類別2/間接排放(輸入能源), 排放係數/emission factor, 逸散源/fugitive source, 營運控制法/operational control approach
- Refrigerant codes: R-32, R-134a, R-410A, HFC-32, SF6
- Hospital terms: 碳盤查小組, 醫務企劃管理室, 行政組, 醫勤組, 民眾診療服務處

Write to `_meta/glossary.json` as `{"key": "full name", ...}`.

- [ ] **Step 2: Commit**

```bash
git add _meta/glossary.json
git commit -m "feat: ESG domain glossary (abbreviations, terms, refrigerant codes)"
```

---

## Task 13: Workflow Customization

**Files:**
- Modify: `.github/workflows/collect.yml` (cron schedule only)

**Context:** Per spec Section 10, only `collect.yml` needs cron change. All other workflows keep defaults or are already inactive via config guard.

- [ ] **Step 1: Read current collect.yml cron**

Read `.github/workflows/collect.yml` to find the current cron schedule line.

- [ ] **Step 2: Update cron to daily 06:00 UTC**

Change the cron schedule to `0 6 * * *` (daily at 06:00 UTC = 14:00 Taiwan time).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/collect.yml
git commit -m "ci: set collect.yml cron to daily 06:00 UTC for deadline-check"
```

---

## Task 14: Build Verification (Wizard Step 6)

**Files:** (none — verification only)

- [ ] **Step 1: Run build**

Run: `npm run build:assistant`
Expected: Build completes with no errors. Outputs assistant.html containing all 36 documents.

- [ ] **Step 2: Verify document count**

Run: `node -e "const fs = require('fs'); const html = fs.readFileSync('assistant.html','utf8'); const m = html.match(/data-doc-id/g); console.log((m?m.length:0) + ' documents in assistant.html')"`
Expected: 36 documents (may vary if some are empty, but should be close).

- [ ] **Step 3: Run QA search-only**

Run: `npm run qa-report -- --search-only`
Expected: Search hit rate reported. May not reach 95% threshold on first pass (skeleton documents have minimal content). Note the hit rate for iteration.

- [ ] **Step 4: If QA < 95%, iterate on content**

Review which questions miss their expected documents. Add keywords or section content to those documents to improve search retrieval. Re-run until search hit rate >= 95% or document a plan for content improvement.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: hospital ESG knowledge body — wizard complete, build verified"
```

---

## Task Dependency Graph

```
Task 1 (config.json)
  ├── Task 2 (_meta/ infra)
  │     └── Task 3 (_meta/types/)
  │           ├── Task 4 (E1 reports)
  │           │     └── Task 5 (E1 supporting)
  │           ├── Task 6 (E2-E4 skeletons)
  │           ├── Task 7 (S1-S3 skeletons)
  │           └── Task 8 (G1-G3 skeletons)
  ├── Task 9 (collectors) — independent of Tasks 4-8
  ├── Task 10 (issue templates) — independent of Tasks 4-8
  └── Task 13 (workflow) — independent

Tasks 4-8 (all documents) → Task 11 (QA questions)
Tasks 4-8 (all documents) → Task 12 (glossary)
All tasks → Task 14 (verification)
```

**Parallelization opportunities:**
- Tasks 6, 7, 8 can run in parallel (independent document groups)
- Tasks 9, 10, 13 can run in parallel with Tasks 4-8
- Task 11 and 12 can run in parallel (both read documents, neither modifies them)
