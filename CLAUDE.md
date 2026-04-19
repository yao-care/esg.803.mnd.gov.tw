# AKORA

> **A**uditable · **K**nowledge Body · **O**rganizer · **R**etrieval · **A**gent
>
> 把散落的文件，升級為可稽核的 AI 知識體。
> Fork 即用的 Claude CLI 模板，為任何領域打造經驗證的知識助理。

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Mode Detection

每次進入本專案的新對話時，**先執行以下檢測**：

```bash
ls config.json 2>/dev/null && echo "MODE=normal" || echo "MODE=wizard"
```

- 若 `MODE=wizard` → 進入 **嚮導模式**（Section A）
- 若 `MODE=normal` → 進入 **正常模式**（Section B）

---

## Section A: 嚮導模式（Wizard Mode）

當 `config.json` 不存在時，**依序執行以下六個步驟**。每步完成才進入下一步，禁止跳步。

### Step 1 — 理解領域

向用戶提問：

> 請描述你的知識體——管理什麼內容？依循什麼標準或規範？目的是什麼？

等候用戶回答。根據回答判斷領域（例如：ISO 27001 資安管理、ISO 9001 品質管理、法規遵循、企業知識庫、研究文獻管理等）。

### Step 2 — 提議架構

根據領域，**運用你對該領域的知識**，向用戶提議以下項目。每個項目標記 ✅（推薦）或 ❓（可選）：

**2a. 文件類型（Document Types）**

列出該領域典型的文件類型。每個類型必須定義一個 **2-5 字母大寫代碼**（用作 document_id 前綴和 merge.yaml 的 `type:` 欄位）。例如 ISO 27001 會有 POL（政策）、PRO（程序書）、FRM（表單）等；ISO 9001 可能有 QM（品質手冊）、WI（作業指導書）、CAR（矯正措施報告）等。

每個類型一行，格式：`代碼 — 類型名稱（說明）`

```
✅ POL — 政策文件（組織層級的方針宣告）
✅ PRO — 程序書（具體作業流程）
✅ FRM — 表單（可填寫、提交、追蹤紀錄）
❓ GDL — 指引（非強制性參考）
```

**代碼規則：** 代碼將用於 document_id 命名（如 `POL-001`）和 merge.yaml 的 `type:` 欄位。其中表單類型代碼必須與 `config.json` 的 `domain.form_prefix` 一致（預設 `FRM`）。

**2b. 收集器（Collectors）**

根據領域判斷是否需要自動化資料收集。僅在確實適用時提議，例如：

- ISO 27001：安全掃描器（dependency-check, secret-scan, SAST）
- 企業情報：網頁爬蟲、API 資料拉取
- 法規遵循：法規更新監控

若領域不需要收集器，跳過此項。

**2c. 監控與演練（Monitoring & Exercises）**

根據領域判斷是否需要：

- 定期監控（heartbeat、態勢檢查）
- 定期演練（事件回應、紅隊測試、稽核模擬）

若領域不需要，跳過此項。

**讓用戶確認：** 列出所有提議後，請用戶逐項確認啟用或停用。

### Step 3 — 領域追問

根據 Step 2 用戶確認的選項，追問必要的設定資訊：

| 用戶啟用了 | 追問 |
|-----------|------|
| 收集器需要 Git 倉庫 | 請提供 repo URL（JSON 陣列格式） |
| 收集器需要網站 URL | 請提供目標 URL |
| 演練需要 LLM 端點 | 請提供 LLM API endpoint |
| 任何通知功能 | 請提供通知 email 收件者 |
| 組織資訊 | 請提供組織名稱（中/英文） |

收集所有必要資訊後才進入下一步。

### Step 4 — 設定目標

若 Step 3 收集到 repo URL 或 web URL，將其組織為 `config.json` 中的 `targets[]` 結構。格式參考 `config.example.json`。

若未收集到任何目標，`targets` 留空陣列。

### Step 5 — 產出檔案

根據 Step 1~4 收集到的所有資訊，**一次性產出以下所有檔案**。產出時參考 `reference/iso27001-example.md` 作為**格式範本**（僅參考格式結構，不照抄內容）：

| 檔案 | 說明 |
|------|------|
| `config.json` | 完整設定檔，填入所有用戶確認的設定值 |
| `_meta/rule.md` | 該領域的基礎設施規則（命名慣例、目錄結構、版本管理） |
| `_meta/writer.md` | 該領域的文件撰寫指引（用語、格式、必要章節） |
| `_meta/reviewer.md` | 該領域的文件審查標準（合規檢查點、常見缺失） |
| `_meta/types/*.md` | 每個文件類型一個檔案（定義 YAML schema、必要欄位、範本） |
| `collectors/*.sh` | 每個收集器一個骨架腳本（含 `#!/bin/bash`、參數解析、TODO 標記） |
| `.github/ISSUE_TEMPLATE/*.yml` | 若需要手動表單（例如事件通報、變更申請），產出 GitHub Issue 模板 |
| `.github/workflows/*.yml` | 根據 config 中啟用的功能，客製化現有 workflow 的 cron 排程 |
| `knowledge/` | 依文件類型建立子目錄，每個目錄放一份骨架 merge.yaml（**必須含 `type:` 欄位**）和 .md 文件 |
| `scripts/lib/core/qa-questions.json` | 20~50 題領域專屬的種子題目（涵蓋各文件類型，用於 QA 驗證） |

**骨架 merge.yaml 範例（每個 knowledge/ 子目錄必須包含）：**

```yaml
document_id: POL-001
type: POL          # ← 必填！對應 Step 2a 定義的類型代碼
title_zh: 資訊安全政策
title_en: Information Security Policy
main:
  zh: 資訊安全政策.md
```

FRM 類型還需額外包含 `fields:` 定義（用於表單閉環系統）。

產出完成後執行：

```bash
bash scripts/setup-org.sh
```

### Step 6 — 驗證

產出完成後，執行以下驗證：

```bash
# 驗證助理建置
npm run build:assistant

# 驗證搜尋功能
npm run qa-report -- --search-only
```

兩項皆通過後，向用戶報告：

> 嚮導完成！已產出所有檔案並通過驗證。下次開啟對話將進入正常模式。

若驗證失敗，分析錯誤原因並修正後重新驗證。

---

## Section B: 正常模式（Normal Mode）

### Session Start Checklist

每次進入正常模式時，**主動執行以下檢查並向用戶報告結果**：

```bash
# 1. 本月 QA 報告是否已產生
MONTH=$(date +%Y%m)
ls data/reports/assistant-report-${MONTH}*.md 2>/dev/null && echo "QA_REPORT=exists" || echo "QA_REPORT=missing"

# 2. CI 最近狀態
gh run list --limit 5 2>/dev/null

# 3. 未推送 commit
git log --oneline origin/main..HEAD 2>/dev/null

# 4. 文件審查到期（30 天內）
grep -rh "^next_review_date:" knowledge/*/merge.yaml 2>/dev/null | head -20

# 5. 動態題快取是否需要更新（檢查 knowledge/ 最新修改時間 vs cache 時間）
stat -f '%m' scripts/lib/core/qa-dynamic-cache.json 2>/dev/null
```

根據結果，推薦行動：

| 狀況 | 推薦動作 |
|------|---------|
| 本月 QA 報告不存在 | `npm run qa-report -- --html`（API 模式）或 `--export` → Claude Code 模式 |
| CI 有失敗的 workflow | `gh run view <ID>` 調查根因 |
| 有未推送的 commit | `git push origin main` |
| 文件 30 天內到期 | 列出到期文件，提醒審查 |
| knowledge/ 有變更但動態題 cache 未更新 | `npm run qa-report -- --refresh-dynamic` |
| 全部正常 | 報告「系統狀態正常，無待處理事項」 |

---

## Project Overview

（嚮導完成後自動填入）

Primary language is **Traditional Chinese (zh-TW)** for UI text and comments.

## 常用指令

### 建置與驗證

```bash
# 建置知識助理 HTML
npm run build:assistant

# QA 驗證（API 模式，需要 API key）
npm run qa-report -- --html

# QA 驗證 — 僅搜尋（免費，無需 API key）
npm run qa-report -- --search-only

# QA 驗證 — CI 模式（搜尋命中率 < 95% 時 exit 1）
npm run qa-report -- --search-only --ci

# QA 驗證（指定 profile）
npm run qa-report -- --profile assistant --html

# 分塊品質稽核
npm run chunk-audit

# 驗證提交紀錄
npm run validate-records

# 產出表單 JSON Schema
npm run generate-schemas
```

### 收集與掃描

```bash
# 完整執行（安裝工具 + 克隆目標 + 執行收集器 + 產出報告）
./scripts/entrypoint.sh

# 跳過工具安裝
SKIP_SETUP=true ./scripts/entrypoint.sh

# 僅執行收集器
bash collectors/run-all.sh
```

### 文件管理

```bash
# 文件審查
bash scripts/review/audit.sh

# 文件完整性檢查
bash scripts/knowledge/review-completeness.sh

# 初始化 GitHub 組織設定（labels 等）
bash scripts/setup-org.sh
```

### 監控與演練

```bash
# 運行時監控
bash scripts/monitor/heartbeat.sh
bash scripts/monitor/posture-check.sh

# 演練排程檢查
bash scripts/monitor/drill-monitor.sh
```

## QA Verification (AI Q&A Accuracy)

兩種執行模式，驗證知識助理的對答品質：

**API Mode**（CI 或手動，需要 API key）：
```bash
npm run qa-report -- --html          # 完整測試 + HTML 報告
npm run qa-report -- --search-only   # 搜尋回歸測試（免費，無需 API）
npm run qa-report -- --search-only --ci  # CI 模式（< 95% 則 exit 1）
```

**Claude Code Mode**（手動，無需 API key）：
```bash
npm run qa-report -- --export        # 匯出題目 + 上下文
# Claude Code 子代理回答 → qa-answers.json
npm run qa-report -- --evaluate qa-answers.json --html
```

**每月報告流程**：操作者每月初手動執行並 commit 報告。CI 在每月 1 日自動補產（若當月報告不存在）。避免重複 API 費用。

**門檻值**：搜尋命中率 >= 95%（CI 門檻）、回答率 >= 98%、引用準確率 >= 98%。

## 引文系統維護

引文系統由三層防護構成（rule/parser/QA），修改任一層時需注意：

1. 修改 system_prompt 時：保留尾端的 few-shot 範例
2. 修改 templates/assistant.html 時：不可移除 normalizeCitations、parseCitations、autoLinkDocKeys 任何一個函式
3. 新增文件類型時：確認 doc_key 格式能被 autoLinkDocKeys 的正則匹配

## Git Branch Policy

### 允許存在的分支 / Allowed Branches

| Branch | Purpose | Lifecycle |
|--------|---------|-----------|
| `main` | 開發主線 | 永久 |
| `audit` | CI 產生的文件 HTML 渲染版（publish branch） | 永久，由 CI force-push |
| `review-*` | 文件內容修正 PR | merge 後立即刪除 |

### PR 分支清理 / PR Branch Cleanup

PR merge 後，**必須立即刪除** remote 和 local 分支：

```bash
# merge PR 後
git push origin --delete <branch-name>
git branch -D <branch-name> 2>/dev/null
git remote prune origin
```

### 稽核包發行 / Audit Package Release

稽核包以 **GitHub Release** 方式發行：

```bash
# 1. 從 audit branch 匯出 zip
TMPDIR=$(mktemp -d)
git worktree add "$TMPDIR/audit" origin/audit
cd "$TMPDIR/audit"
zip -r /tmp/Documents-$(date +%Y%m%d).zip . -x '.git/*'
cd -
git worktree remove "$TMPDIR/audit"

# 2. 建立 release（tag 格式: audit-YYYYMMDD）
gh release create "audit-$(date +%Y%m%d)" /tmp/Documents-$(date +%Y%m%d).zip \
  --title "Audit Package $(date +%Y-%m-%d)" \
  --notes "稽核包內容：解壓後開啟 index.html"
```

## Key Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `REPOS_JSON` | 依 config 設定 | JSON array of target repo URLs |
| `WEB_URL` | 依 config 設定 | Target URL for web-based collectors |
| `PROJECT_NAME` | No | Groups history. Use `client--project` format. Do NOT use `/`. |
| `SCAN_DEPTH` | No | `quick` / `standard` (default) / `deep` |
| `PAT_TOKEN` | No | GitHub PAT for private repos |
| `SKIP_SETUP` | No | Set `true` to skip tool installation |
| `LLM_ENDPOINT` | No | LLM API endpoint for exercises |

## GitHub Actions

| Workflow | 說明 |
|----------|------|
| `collect.yml` | 定期資料收集（排程依 config 設定） |
| `monitor.yml` | 運行時監控 + 態勢檢查 |
| `drill-monitor.yml` | 演練排程檢查 |
| `exercises.yml` | 定期演練 |
| `review.yml` | 文件稽核 |
| `publish.yml` | 文件變更時自動渲染 + 部署至 audit branch |
| `qa-report.yml` | 每月 AI 對答品質驗證報告 |
| `remediation-verify.yml` | Issue 關閉時自動驗證修補 |
