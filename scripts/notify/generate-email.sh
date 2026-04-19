#!/bin/bash
# 從掃描結果產生 HTML email 信件
# 使用 OKLCH 設計系統的 hex fallback 色彩（email client 不支援 CSS variables）
# 用法: generate-email.sh <scan_dir> <project_name> <scan_depth>
set -e

SCAN_DIR="$1"
PROJECT_NAME="$2"
SCAN_DEPTH="$3"

if [ -z "$SCAN_DIR" ] || [ -z "$PROJECT_NAME" ]; then
  echo "Usage: generate-email.sh <scan_dir> <project_name> <scan_depth>"
  exit 1
fi

# ── 讀取 config ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/shell-config.sh
source "${SCRIPT_DIR}/../lib/shell-config.sh"

# 寄件人署名（footer）
ORG_NAME="${KB_ORG:-$(cfg 'knowledge_body.organization' '')}"
ORG_NAME_EN="${KB_NAME_EN:-$(cfg 'knowledge_body.name_en' '')}"
CONTACT_EMAIL="$(cfg 'notify.email.from' '')"

SCAN_ID=$(basename "$SCAN_DIR")
DATE=$(date '+%Y/%m/%d')

# ── 色彩定義（hex fallback from styles.css）──
BG_BASE="#f5f6f8"
BG_SURFACE="#ecedf0"
BG_OVERLAY="#dfe0e5"
TEXT_PRIMARY="#1e2030"
TEXT_SECONDARY="#5e6070"
TEXT_MUTED="#8a8c98"
COLOR_CRITICAL="#c93135"
COLOR_HIGH="#b86a2a"
COLOR_MEDIUM="#8a7020"
COLOR_LOW="#2a6bb8"
COLOR_PASS="#1e8050"
COLOR_FAIL="#c93135"
COLOR_WARN="#8a7020"
COLOR_LINK="#1e5ab8"
BADGE_CRITICAL_BG="#fce8e8"
BADGE_PASS_BG="#e8fcf0"
BADGE_WARN_BG="#fcf5e8"

# ── 讀取掃描結果 ──
QG=$(jq -r '.quality_gate // "N/A"' "$SCAN_DIR/quality-gate.json" 2>/dev/null || echo "N/A")

SAST_TOTAL=0; VULN_C=0; VULN_H=0; VULN_M=0
SSDLC_PASS=0; SSDLC_TOTAL=0; SBOM_TOTAL=0
AI_SAFETY_PASS=0; AI_SAFETY_TOTAL=0
AI_SUPPLY_FAIL=0; AI_SUPPLY_WARN=0
CRYPTO_FAIL=0; CRYPTO_WARN=0
PENTEST_TOTAL=0; SEO_PASS=0; SEO_TOTAL=0

for dir in "$SCAN_DIR"/*/; do
  [ ! -d "$dir" ] && continue
  name=$(basename "$dir")
  [ "$name" = "pentest" ] || [ "$name" = "seo" ] || [ "$name" = "wp-security" ] || [ "$name" = "compliance" ] && continue

  [ -f "$dir/sast-result.json" ] && SAST_TOTAL=$((SAST_TOTAL + $(jq '.summary.total_findings // 0' "$dir/sast-result.json" 2>/dev/null || echo 0)))
  [ -f "$dir/vulnerability-result.json" ] && {
    VULN_C=$((VULN_C + $(jq '.summary.critical // 0' "$dir/vulnerability-result.json" 2>/dev/null || echo 0)))
    VULN_H=$((VULN_H + $(jq '.summary.high // 0' "$dir/vulnerability-result.json" 2>/dev/null || echo 0)))
    VULN_M=$((VULN_M + $(jq '.summary.medium // 0' "$dir/vulnerability-result.json" 2>/dev/null || echo 0)))
  }
  [ -f "$dir/ssdlc-result.json" ] && {
    SSDLC_PASS=$((SSDLC_PASS + $(jq '.summary.pass // 0' "$dir/ssdlc-result.json" 2>/dev/null || echo 0)))
    SSDLC_TOTAL=$((SSDLC_TOTAL + $(jq '.summary.total // 0' "$dir/ssdlc-result.json" 2>/dev/null || echo 0)))
  }
  [ -f "$dir/sbom-result.json" ] && SBOM_TOTAL=$((SBOM_TOTAL + $(jq '.summary.total_components // 0' "$dir/sbom-result.json" 2>/dev/null || echo 0)))
  [ -f "$dir/ai-safety-result.json" ] && {
    AI_SAFETY_PASS=$((AI_SAFETY_PASS + $(jq '.summary.pass // 0' "$dir/ai-safety-result.json" 2>/dev/null || echo 0)))
    AI_SAFETY_TOTAL=$((AI_SAFETY_TOTAL + $(jq '.summary.total // 0' "$dir/ai-safety-result.json" 2>/dev/null || echo 0)))
  }
  [ -f "$dir/ai-supply-chain-result.json" ] && {
    AI_SUPPLY_FAIL=$((AI_SUPPLY_FAIL + $(jq '.summary.fail // 0' "$dir/ai-supply-chain-result.json" 2>/dev/null || echo 0)))
    AI_SUPPLY_WARN=$((AI_SUPPLY_WARN + $(jq '.summary.warn // 0' "$dir/ai-supply-chain-result.json" 2>/dev/null || echo 0)))
  }
  [ -f "$dir/crypto-audit-result.json" ] && {
    CRYPTO_FAIL=$((CRYPTO_FAIL + $(jq '.summary.fail // 0' "$dir/crypto-audit-result.json" 2>/dev/null || echo 0)))
    CRYPTO_WARN=$((CRYPTO_WARN + $(jq '.summary.warn // 0' "$dir/crypto-audit-result.json" 2>/dev/null || echo 0)))
  }
done

[ -f "$SCAN_DIR/pentest/pentest-result.json" ] && PENTEST_TOTAL=$(jq '.summary.total_findings // 0' "$SCAN_DIR/pentest/pentest-result.json" 2>/dev/null || echo 0)
[ -f "$SCAN_DIR/seo/seo-result.json" ] && {
  SEO_PASS=$(jq '.summary.pass // 0' "$SCAN_DIR/seo/seo-result.json" 2>/dev/null || echo 0)
  SEO_TOTAL=$(jq '.summary.total // 0' "$SCAN_DIR/seo/seo-result.json" 2>/dev/null || echo 0)
}

# Runtime monitoring metrics
RUNTIME_OP="N/A"
RUNTIME_C=0
RUNTIME_H=0
RUNTIME_HEARTBEAT=""
POSTURE_FAIL_COUNT=0

if [ -f "$SCAN_DIR/runtime/runtime-result.json" ]; then
  RUNTIME_OP=$(jq -r '.operational_readiness // "N/A"' "$SCAN_DIR/runtime/runtime-result.json" 2>/dev/null || echo "N/A")
  RUNTIME_C=$(jq '.summary.critical // 0' "$SCAN_DIR/runtime/runtime-result.json" 2>/dev/null || echo "0")
  RUNTIME_H=$(jq '.summary.high // 0' "$SCAN_DIR/runtime/runtime-result.json" 2>/dev/null || echo "0")
  HB_ALIVE=$(jq '.heartbeat.alive // 0' "$SCAN_DIR/runtime/runtime-result.json" 2>/dev/null || echo "0")
  HB_TOTAL=$(jq '.heartbeat.total // 0' "$SCAN_DIR/runtime/runtime-result.json" 2>/dev/null || echo "0")
  RUNTIME_HEARTBEAT="${HB_ALIVE}/${HB_TOTAL}"
fi

if [ -f "$SCAN_DIR/runtime/posture-check-result.json" ]; then
  POSTURE_FAIL_COUNT=$(jq '.summary.fail // 0' "$SCAN_DIR/runtime/posture-check-result.json" 2>/dev/null || echo "0")
fi

# ── 狀態 badge HTML 生成 ──
badge() {
  local status="$1"
  case "$status" in
    PASS) echo "<span style=\"background:${BADGE_PASS_BG};color:${COLOR_PASS};padding:2px 10px;border-radius:4px;font-weight:700;font-size:13px;\">PASS</span>" ;;
    FAIL) echo "<span style=\"background:${BADGE_CRITICAL_BG};color:${COLOR_FAIL};padding:2px 10px;border-radius:4px;font-weight:700;font-size:13px;\">FAIL</span>" ;;
    REVIEW) echo "<span style=\"background:${BADGE_WARN_BG};color:${COLOR_WARN};padding:2px 10px;border-radius:4px;font-weight:700;font-size:13px;\">REVIEW</span>" ;;
    INFO) echo "<span style=\"color:${TEXT_MUTED};font-size:13px;\">INFO</span>" ;;
  esac
}

# ── 計算每列狀態 ──
s_sast=$([ "$SAST_TOTAL" -eq 0 ] && echo "PASS" || echo "REVIEW")
s_vuln_c=$([ "$VULN_C" -eq 0 ] && echo "PASS" || echo "FAIL")
s_vuln_h=$([ "$VULN_H" -eq 0 ] && echo "PASS" || echo "FAIL")
s_ssdlc=$([ "$SSDLC_PASS" -eq "$SSDLC_TOTAL" ] && [ "$SSDLC_TOTAL" -gt 0 ] && echo "PASS" || echo "REVIEW")
s_ai_safety=$([ "$AI_SAFETY_PASS" -eq "$AI_SAFETY_TOTAL" ] && [ "$AI_SAFETY_TOTAL" -gt 0 ] && echo "PASS" || echo "REVIEW")
s_ai_supply=$([ "$AI_SUPPLY_FAIL" -eq 0 ] && echo "PASS" || echo "FAIL")
s_crypto=$([ "$CRYPTO_FAIL" -eq 0 ] && echo "PASS" || echo "FAIL")
s_pentest=$([ "$PENTEST_TOTAL" -eq 0 ] && echo "PASS" || echo "REVIEW")

# ── Quality Gate badge ──
if [ "$QG" = "PASS" ]; then
  QG_COLOR="$COLOR_PASS"
  QG_BG="$BADGE_PASS_BG"
else
  QG_COLOR="$COLOR_FAIL"
  QG_BG="$BADGE_CRITICAL_BG"
fi

# ── 找出專案子目錄名稱（用於附件名稱）──
PROJECT_SUBDIR=""
for dir in "$SCAN_DIR"/*/; do
  [ ! -d "$dir" ] && continue
  name=$(basename "$dir")
  # 排除已知的非專案目錄
  case "$name" in
    pentest|seo|wp-security|compliance|audit|cve-report-*) continue ;;
  esac
  # 必須有 summary.json 或 sast-result.json 才是專案目錄
  [ -f "$dir/summary.json" ] || [ -f "$dir/sast-result.json" ] || continue
  PROJECT_SUBDIR="$name"
  break
done

# ── badge 小標籤（用在附件名稱旁）──
att_badge() {
  echo "<br><span style=\"display:inline-block;margin-top:4px;background:${BG_OVERLAY};color:${COLOR_LINK};padding:2px 8px;border-radius:4px;font-size:12px;border:1px solid #c0c2ca;\">📎 $1</span>"
}

# ── 工作事項 HTML（按收件人分組，附件 inline）──
ACTIONS=""

# === 開發團隊 Dev Team ===
DEV_ITEMS=""
DEV_N=0

# 從 result.json 提取具體失敗項目的 helper
extract_failures() {
  local json_file="$1" status_field="$2"
  [ ! -f "$json_file" ] && return
  jq -r ".checks[]? | select(.status != \"pass\") | \"<div style=\\\"margin:2px 0 2px 12px;font-size:12px;\\\"><span style=\\\"color:${COLOR_FAIL};\\\">[\" + (.status | ascii_upcase) + \"]</span> \" + (.detail // .name) + \"</div>\"" "$json_file" 2>/dev/null || true
}

# 找專案目錄下的 result 檔案
PROJ_DIR=""
[ -n "$PROJECT_SUBDIR" ] && PROJ_DIR="$SCAN_DIR/$PROJECT_SUBDIR"

if [ "$VULN_C" -gt 0 ]; then
  DEV_N=$((DEV_N+1))
  DEV_ITEMS="${DEV_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_CRITICAL};font-weight:700;width:30px;vertical-align:top;\">${DEV_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">發現 ${VULN_C} 項 Critical 弱點<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">${VULN_C} critical vulnerabilities found.</span>$(att_badge "${PROJECT_SUBDIR}-report.html")</td></tr>"
fi
if [ "$VULN_H" -gt 0 ]; then
  DEV_N=$((DEV_N+1))
  DEV_ITEMS="${DEV_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_HIGH};font-weight:700;width:30px;vertical-align:top;\">${DEV_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">發現 ${VULN_H} 項 High 弱點<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">${VULN_H} high vulnerabilities found.</span>$(att_badge "${PROJECT_SUBDIR}-report.html")</td></tr>"
fi
if [ "$SAST_TOTAL" -gt 0 ]; then
  DEV_N=$((DEV_N+1))
  DEV_ITEMS="${DEV_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_WARN};font-weight:700;width:30px;vertical-align:top;\">${DEV_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">源碼掃描發現 ${SAST_TOTAL} 項問題<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">${SAST_TOTAL} SAST findings.</span>$(att_badge "${PROJECT_SUBDIR}-report.html")</td></tr>"
fi
if [ "$CRYPTO_FAIL" -gt 0 ] && [ -n "$PROJ_DIR" ]; then
  CRYPTO_DETAILS=$(extract_failures "$PROJ_DIR/crypto-audit-result.json")
  DEV_N=$((DEV_N+1))
  DEV_ITEMS="${DEV_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_FAIL};font-weight:700;width:30px;vertical-align:top;\">${DEV_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">密碼學稽核發現 ${CRYPTO_FAIL} 項失敗：${CRYPTO_DETAILS}$(att_badge "${PROJECT_SUBDIR}-report.html")</td></tr>"
fi
if [ "$AI_SUPPLY_FAIL" -gt 0 ] && [ -n "$PROJ_DIR" ]; then
  AIS_DETAILS=$(extract_failures "$PROJ_DIR/ai-supply-chain-result.json")
  DEV_N=$((DEV_N+1))
  DEV_ITEMS="${DEV_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_FAIL};font-weight:700;width:30px;vertical-align:top;\">${DEV_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">AI 供應鏈發現 ${AI_SUPPLY_FAIL} 項風險：${AIS_DETAILS}$(att_badge "${PROJECT_SUBDIR}-report.html")</td></tr>"
fi
if [ "$AI_SAFETY_PASS" -lt "$AI_SAFETY_TOTAL" ] && [ "$AI_SAFETY_TOTAL" -gt 0 ] && [ -n "$PROJ_DIR" ]; then
  AI_MISSING=$((AI_SAFETY_TOTAL - AI_SAFETY_PASS))
  AIS_DETAILS=$(extract_failures "$PROJ_DIR/ai-safety-result.json")
  DEV_N=$((DEV_N+1))
  DEV_ITEMS="${DEV_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_WARN};font-weight:700;width:30px;vertical-align:top;\">${DEV_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">AI 安全檢查 ${AI_MISSING} 項未通過（OWASP LLM Top 10）：${AIS_DETAILS}$(att_badge "${PROJECT_SUBDIR}-report.html")</td></tr>"
fi

if [ "$DEV_N" -gt 0 ]; then
  ACTIONS="${ACTIONS}<tr><td colspan=\"2\" style=\"padding:10px 12px;background:${BG_OVERLAY};font-weight:700;\">請開發團隊 Dev Team</td></tr>${DEV_ITEMS}"
fi

# === 專案負責人 Project Lead ===
PL_ITEMS=""
PL_N=0

if [ "$SSDLC_PASS" -lt "$SSDLC_TOTAL" ] && [ "$SSDLC_TOTAL" -gt 0 ] && [ -n "$PROJ_DIR" ]; then
  SSDLC_DETAILS=$(extract_failures "$PROJ_DIR/ssdlc-result.json")
  PL_N=$((PL_N+1))
  PL_ITEMS="${PL_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_WARN};font-weight:700;width:30px;vertical-align:top;\">${PL_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">SSDLC 檢核發現以下缺失：${SSDLC_DETAILS}$(att_badge "${PROJECT_SUBDIR}-report.html")</td></tr>"
fi

if [ "$PL_N" -gt 0 ]; then
  ACTIONS="${ACTIONS}<tr><td colspan=\"2\" style=\"padding:10px 12px;background:${BG_OVERLAY};font-weight:700;\">請專案負責人 Project Lead</td></tr>${PL_ITEMS}"
fi

# === 資訊安全官 ISO ===
ISO_ITEMS=""
ISO_N=0

if [ "$PENTEST_TOTAL" -gt 0 ]; then
  ISO_N=$((ISO_N+1))
  ISO_ITEMS="${ISO_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_WARN};font-weight:700;width:30px;vertical-align:top;\">${ISO_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">滲透測試發現 ${PENTEST_TOTAL} 項問題<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">${PENTEST_TOTAL} pentest findings.</span>$(att_badge "pentest-report.html")</td></tr>"
fi

# Runtime monitoring alerts → ISO
if [ "$RUNTIME_C" -gt 0 ]; then
  ISO_N=$((ISO_N+1))
  ISO_ITEMS="${ISO_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_CRITICAL};font-weight:700;width:30px;vertical-align:top;\">${ISO_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">Runtime 監控發現 ${RUNTIME_C} 項 Critical 事件<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">${RUNTIME_C} critical runtime events detected.</span>$(att_badge "runtime/")</td></tr>"
fi
if [ "$RUNTIME_H" -gt 0 ]; then
  ISO_N=$((ISO_N+1))
  ISO_ITEMS="${ISO_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_HIGH};font-weight:700;width:30px;vertical-align:top;\">${ISO_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">Runtime 監控發現 ${RUNTIME_H} 項 High 事件<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">${RUNTIME_H} high runtime events detected.</span>$(att_badge "runtime/")</td></tr>"
fi
if [ "$RUNTIME_OP" = "NOT READY" ]; then
  ISO_N=$((ISO_N+1))
  ISO_ITEMS="${ISO_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_FAIL};font-weight:700;width:30px;vertical-align:top;\">${ISO_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">營運整備狀態: NOT READY（監控心跳: ${RUNTIME_HEARTBEAT}）<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">Operational readiness gate failed. Heartbeat: ${RUNTIME_HEARTBEAT}.</span>$(att_badge "runtime/")</td></tr>"
fi
if [ "$POSTURE_FAIL_COUNT" -gt 0 ]; then
  POSTURE_DETAILS=$(extract_failures "$SCAN_DIR/runtime/posture-check-result.json")
  ISO_N=$((ISO_N+1))
  ISO_ITEMS="${ISO_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_WARN};font-weight:700;width:30px;vertical-align:top;\">${ISO_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">安全姿態稽核 ${POSTURE_FAIL_COUNT} 項缺口：${POSTURE_DETAILS}$(att_badge "runtime/")</td></tr>"
fi

# 合規報告一律給資安官
ISO_N=$((ISO_N+1))
ISO_ITEMS="${ISO_ITEMS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_LOW};font-weight:700;width:30px;vertical-align:top;\">${ISO_N}.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">合規對照報告<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">Compliance mapping report.</span>$(att_badge "compliance-report.html")</td></tr>"

if [ "$ISO_N" -gt 0 ]; then
  ACTIONS="${ACTIONS}<tr><td colspan=\"2\" style=\"padding:10px 12px;background:${BG_OVERLAY};font-weight:700;\">請資訊安全官 Information Security Officer</td></tr>${ISO_ITEMS}"
fi

# === 管理代表 Management ===
ACTIONS="${ACTIONS}<tr><td colspan=\"2\" style=\"padding:10px 12px;background:${BG_OVERLAY};font-weight:700;\">請管理代表 Management Representative</td></tr>"
ACTIONS="${ACTIONS}<tr><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;color:${COLOR_LOW};font-weight:700;width:30px;vertical-align:top;\">1.</td><td style=\"padding:6px 12px;border-bottom:1px solid #dfe0e5;\">確認掃描總覽，掌握整體安全狀態$(att_badge "scan-report.html")<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">Review scan overview for overall security posture.</span></td></tr>"

# === 無工作事項的情況 ===
if [ "$DEV_N" -eq 0 ] && [ "$PL_N" -eq 0 ] && [ "$PENTEST_TOTAL" -eq 0 ]; then
  # 只有管理代表和資安官的例行事項，在前面加一行提示
  ACTIONS="<tr><td colspan=\"2\" style=\"padding:10px 12px;color:${COLOR_PASS};font-weight:600;\">本次掃描未發現需立即處理的安全問題。以下為例行分派事項。<br><span style=\"color:${TEXT_MUTED};font-size:12px;\">No critical issues found. Routine distribution below.</span></td></tr>${ACTIONS}"
fi

# ── 輸出 HTML ──
cat << HTMLEOF
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:${BG_BASE};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:${TEXT_PRIMARY};">
<table width="100%" cellpadding="0" cellspacing="0" style="max-width:680px;margin:0 auto;padding:24px;">
<tr><td>

<!-- Header -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
<tr>
<td style="font-size:24px;font-weight:700;color:${TEXT_PRIMARY};padding-bottom:8px;">
  安全掃描報告 Security Scan Report
</td>
</tr>
<tr>
<td style="font-size:14px;color:${TEXT_SECONDARY};padding-bottom:4px;">
  專案 Project: <strong>${PROJECT_NAME}</strong>
</td>
</tr>
<tr>
<td style="font-size:14px;color:${TEXT_MUTED};">
  ${DATE} &nbsp;|&nbsp; Scan ID: ${SCAN_ID} &nbsp;|&nbsp; Depth: ${SCAN_DEPTH}
</td>
</tr>
</table>

<!-- Quality Gate Card -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:24px;">
<tr>
<td align="center" style="background:${QG_BG};border-radius:8px;padding:20px;">
  <div style="font-size:14px;color:${TEXT_SECONDARY};margin-bottom:4px;">Quality Gate 品質門檻</div>
  <div style="font-size:36px;font-weight:700;color:${QG_COLOR};">${QG}</div>
</td>
</tr>
</table>

<!-- Section 1: Scan Results -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:8px;">
<tr><td style="font-size:18px;font-weight:700;color:${TEXT_PRIMARY};padding-bottom:12px;border-bottom:2px solid ${BG_OVERLAY};">
  一、掃描結果 Scan Results
</td></tr>
</table>

<table width="100%" cellpadding="0" cellspacing="0" style="background:${BG_SURFACE};border-radius:8px;margin-bottom:24px;">
<tr style="background:${BG_OVERLAY};">
  <th style="padding:10px 12px;text-align:left;font-size:13px;font-weight:600;">Scan Item</th>
  <th style="padding:10px 12px;text-align:left;font-size:13px;font-weight:600;">掃描項目</th>
  <th style="padding:10px 12px;text-align:center;font-size:13px;font-weight:600;">Value</th>
  <th style="padding:10px 12px;text-align:center;font-size:13px;font-weight:600;">Normal</th>
  <th style="padding:10px 12px;text-align:center;font-size:13px;font-weight:600;">Status</th>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">SAST Findings</td>
  <td style="padding:8px 12px;font-size:14px;">源碼安全發現</td>
  <td style="padding:8px 12px;text-align:center;font-weight:700;">${SAST_TOTAL}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">0</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "$s_sast")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">Vulnerability Critical</td>
  <td style="padding:8px 12px;font-size:14px;">嚴重弱點</td>
  <td style="padding:8px 12px;text-align:center;font-weight:700;color:${COLOR_CRITICAL};">${VULN_C}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">0</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "$s_vuln_c")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">Vulnerability High</td>
  <td style="padding:8px 12px;font-size:14px;">高風險弱點</td>
  <td style="padding:8px 12px;text-align:center;font-weight:700;color:${COLOR_HIGH};">${VULN_H}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">0</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "$s_vuln_h")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">Vulnerability Medium</td>
  <td style="padding:8px 12px;font-size:14px;">中風險弱點</td>
  <td style="padding:8px 12px;text-align:center;">${VULN_M}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">—</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "INFO")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">SSDLC Compliance</td>
  <td style="padding:8px 12px;font-size:14px;">安全開發合規</td>
  <td style="padding:8px 12px;text-align:center;font-weight:700;">${SSDLC_PASS}/${SSDLC_TOTAL}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">100%</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "$s_ssdlc")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">SBOM Components</td>
  <td style="padding:8px 12px;font-size:14px;">軟體物料清單</td>
  <td style="padding:8px 12px;text-align:center;">${SBOM_TOTAL}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">—</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "INFO")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">AI Safety</td>
  <td style="padding:8px 12px;font-size:14px;">AI 安全檢查</td>
  <td style="padding:8px 12px;text-align:center;font-weight:700;">${AI_SAFETY_PASS}/${AI_SAFETY_TOTAL}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">100%</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "$s_ai_safety")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">AI Supply Chain</td>
  <td style="padding:8px 12px;font-size:14px;">AI 供應鏈</td>
  <td style="padding:8px 12px;text-align:center;font-weight:700;">${AI_SUPPLY_FAIL}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">0</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "$s_ai_supply")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">Crypto Audit</td>
  <td style="padding:8px 12px;font-size:14px;">密碼學稽核</td>
  <td style="padding:8px 12px;text-align:center;font-weight:700;">${CRYPTO_FAIL}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">0</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "$s_crypto")</td>
</tr>
<tr style="border-bottom:1px solid #dfe0e5;">
  <td style="padding:8px 12px;font-size:14px;">Pentest Findings</td>
  <td style="padding:8px 12px;font-size:14px;">滲透測試</td>
  <td style="padding:8px 12px;text-align:center;font-weight:700;">${PENTEST_TOTAL}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">0</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "$s_pentest")</td>
</tr>
<tr>
  <td style="padding:8px 12px;font-size:14px;">SEO Score</td>
  <td style="padding:8px 12px;font-size:14px;">搜尋優化</td>
  <td style="padding:8px 12px;text-align:center;">${SEO_PASS}/${SEO_TOTAL}</td>
  <td style="padding:8px 12px;text-align:center;color:${TEXT_MUTED};">—</td>
  <td style="padding:8px 12px;text-align:center;">$(badge "INFO")</td>
</tr>
</table>

<!-- Section 2: Action Items -->
<table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:8px;">
<tr><td style="font-size:18px;font-weight:700;color:${TEXT_PRIMARY};padding-bottom:12px;border-bottom:2px solid ${BG_OVERLAY};">
  二、接下來的工作事項 Action Items
</td></tr>
</table>

<table width="100%" cellpadding="0" cellspacing="0" style="background:${BG_SURFACE};border-radius:8px;margin-bottom:24px;">
${ACTIONS}
</table>

<!-- Footer -->
<table width="100%" cellpadding="0" cellspacing="0" style="border-top:2px solid ${BG_OVERLAY};padding-top:16px;">
<tr><td style="font-size:13px;color:${TEXT_MUTED};line-height:1.6;">
  ${ORG_NAME}$([ -n "$ORG_NAME_EN" ] && echo " ${ORG_NAME_EN}")<br>
  ${CONTACT_EMAIL}
</td></tr>
</table>

</td></tr>
</table>
</body>
</html>
HTMLEOF
