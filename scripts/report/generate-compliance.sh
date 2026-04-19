#!/bin/bash
set -e
# Compliance mapping report — reads scanner result.json files and maps to control framework
# Generates HTML to $SCAN_DIR/compliance/index.html

SCAN_DIR="$1"

if [ -z "$SCAN_DIR" ]; then
  echo "Usage: generate-compliance.sh <scan_directory>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/shell-config.sh"

SCAN_ID=$(basename "$SCAN_DIR")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Load OKLCH design-system styles
OKLCH_STYLES=""
if [ -f "$PROJECT_ROOT/templates/styles.css" ]; then
  OKLCH_STYLES=$(cat "$PROJECT_ROOT/templates/styles.css")
fi

# ============================================================
# Collect scanner results from project subdirectories
# Skip reserved directory names: pentest, seo, wp-security, compliance
# ============================================================

FIRST_PROJECT_DIR=""
for project_dir in "$SCAN_DIR"/*/; do
  [ ! -d "$project_dir" ] && continue
  dirname=$(basename "$project_dir")
  case "$dirname" in
    pentest|seo|wp-security|compliance) continue ;;
  esac
  FIRST_PROJECT_DIR="$project_dir"
  break
done

# --- SAST ---
SAST_STATUS="N/A"
SAST_CRITICAL=0; SAST_HIGH=0; SAST_MEDIUM=0; SAST_LOW=0; SAST_TOTAL=0

for project_dir in "$SCAN_DIR"/*/; do
  [ ! -d "$project_dir" ] && continue
  dirname=$(basename "$project_dir")
  case "$dirname" in pentest|seo|wp-security|compliance) continue ;; esac
  result_file="$project_dir/sast-result.json"
  if [ -f "$result_file" ]; then
    status=$(jq -r '.status // "skipped"' "$result_file" 2>/dev/null || echo "skipped")
    if [ "$status" = "completed" ]; then
      SAST_STATUS="completed"
      c=$(jq '.summary.critical // 0' "$result_file" 2>/dev/null || echo "0")
      h=$(jq '.summary.high // 0' "$result_file" 2>/dev/null || echo "0")
      m=$(jq '.summary.medium // 0' "$result_file" 2>/dev/null || echo "0")
      l=$(jq '.summary.low // 0' "$result_file" 2>/dev/null || echo "0")
      t=$(jq '.summary.total_findings // 0' "$result_file" 2>/dev/null || echo "0")
      SAST_CRITICAL=$((SAST_CRITICAL + c))
      SAST_HIGH=$((SAST_HIGH + h))
      SAST_MEDIUM=$((SAST_MEDIUM + m))
      SAST_LOW=$((SAST_LOW + l))
      SAST_TOTAL=$((SAST_TOTAL + t))
    fi
  fi
done

# --- Vulnerability ---
VULN_STATUS="N/A"
VULN_CRITICAL=0; VULN_HIGH=0; VULN_MEDIUM=0; VULN_LOW=0; VULN_TOTAL=0

for project_dir in "$SCAN_DIR"/*/; do
  [ ! -d "$project_dir" ] && continue
  dirname=$(basename "$project_dir")
  case "$dirname" in pentest|seo|wp-security|compliance) continue ;; esac
  result_file="$project_dir/vulnerability-result.json"
  if [ -f "$result_file" ]; then
    status=$(jq -r '.status // "skipped"' "$result_file" 2>/dev/null || echo "skipped")
    if [ "$status" = "completed" ]; then
      VULN_STATUS="completed"
      c=$(jq '.summary.critical // 0' "$result_file" 2>/dev/null || echo "0")
      h=$(jq '.summary.high // 0' "$result_file" 2>/dev/null || echo "0")
      m=$(jq '.summary.medium // 0' "$result_file" 2>/dev/null || echo "0")
      l=$(jq '.summary.low // 0' "$result_file" 2>/dev/null || echo "0")
      t=$(jq '.summary.total // 0' "$result_file" 2>/dev/null || echo "0")
      VULN_CRITICAL=$((VULN_CRITICAL + c))
      VULN_HIGH=$((VULN_HIGH + h))
      VULN_MEDIUM=$((VULN_MEDIUM + m))
      VULN_LOW=$((VULN_LOW + l))
      VULN_TOTAL=$((VULN_TOTAL + t))
    fi
  fi
done

# --- Pentest ---
PENTEST_STATUS="N/A"
PENTEST_CRITICAL=0; PENTEST_HIGH=0; PENTEST_MEDIUM=0; PENTEST_LOW=0; PENTEST_TOTAL=0

PENTEST_RESULT="$SCAN_DIR/pentest/pentest-result.json"
if [ -f "$PENTEST_RESULT" ]; then
  status=$(jq -r '.status // "skipped"' "$PENTEST_RESULT" 2>/dev/null || echo "skipped")
  if [ "$status" = "completed" ]; then
    PENTEST_STATUS="completed"
    PENTEST_CRITICAL=$(jq '.summary.critical // 0' "$PENTEST_RESULT" 2>/dev/null || echo "0")
    PENTEST_HIGH=$(jq '.summary.high // 0' "$PENTEST_RESULT" 2>/dev/null || echo "0")
    PENTEST_MEDIUM=$(jq '.summary.medium // 0' "$PENTEST_RESULT" 2>/dev/null || echo "0")
    PENTEST_LOW=$(jq '.summary.low // 0' "$PENTEST_RESULT" 2>/dev/null || echo "0")
    PENTEST_TOTAL=$(jq '.summary.total_findings // 0' "$PENTEST_RESULT" 2>/dev/null || echo "0")
  fi
fi

# --- SSDLC ---
SSDLC_STATUS="N/A"
SSDLC_PASS=0; SSDLC_FAIL=0; SSDLC_WARN=0; SSDLC_TOTAL=0

for project_dir in "$SCAN_DIR"/*/; do
  [ ! -d "$project_dir" ] && continue
  dirname=$(basename "$project_dir")
  case "$dirname" in pentest|seo|wp-security|compliance) continue ;; esac
  result_file="$project_dir/ssdlc-result.json"
  if [ -f "$result_file" ]; then
    status=$(jq -r '.status // "skipped"' "$result_file" 2>/dev/null || echo "skipped")
    if [ "$status" = "completed" ]; then
      SSDLC_STATUS="completed"
      p=$(jq '.summary.pass // 0' "$result_file" 2>/dev/null || echo "0")
      f=$(jq '.summary.fail // 0' "$result_file" 2>/dev/null || echo "0")
      w=$(jq '.summary.warn // 0' "$result_file" 2>/dev/null || echo "0")
      t=$(jq '.summary.total // 0' "$result_file" 2>/dev/null || echo "0")
      SSDLC_PASS=$((SSDLC_PASS + p))
      SSDLC_FAIL=$((SSDLC_FAIL + f))
      SSDLC_WARN=$((SSDLC_WARN + w))
      SSDLC_TOTAL=$((SSDLC_TOTAL + t))
    fi
  fi
done

# --- SBOM ---
SBOM_STATUS="N/A"
SBOM_TOTAL_COMPONENTS=0

for project_dir in "$SCAN_DIR"/*/; do
  [ ! -d "$project_dir" ] && continue
  dirname=$(basename "$project_dir")
  case "$dirname" in pentest|seo|wp-security|compliance) continue ;; esac
  result_file="$project_dir/sbom-result.json"
  if [ -f "$result_file" ]; then
    status=$(jq -r '.status // "skipped"' "$result_file" 2>/dev/null || echo "skipped")
    if [ "$status" = "completed" ]; then
      SBOM_STATUS="completed"
      t=$(jq '.summary.total_components // 0' "$result_file" 2>/dev/null || echo "0")
      SBOM_TOTAL_COMPONENTS=$((SBOM_TOTAL_COMPONENTS + t))
    fi
  fi
done

# --- Quality Gate ---
QG_STATUS="N/A"
QG_VALUE="N/A"
QG_CRITICAL=0; QG_HIGH=0

if [ -f "$SCAN_DIR/quality-gate.json" ]; then
  QG_STATUS="completed"
  QG_VALUE=$(jq -r '.quality_gate // "N/A"' "$SCAN_DIR/quality-gate.json" 2>/dev/null || echo "N/A")
  QG_CRITICAL=$(jq '.critical // 0' "$SCAN_DIR/quality-gate.json" 2>/dev/null || echo "0")
  QG_HIGH=$(jq '.high // 0' "$SCAN_DIR/quality-gate.json" 2>/dev/null || echo "0")
fi

# ============================================================
# Determine per-row status
# PASS: scan complete, no Critical/High
# PARTIAL: scan complete, has Medium/Low
# FAIL: scan complete, has Critical or High
# N/A: result.json absent or scan skipped
# ============================================================

determine_status_by_severity() {
  local scanner_status="$1" critical="$2" high="$3" medium="$4" low="$5"
  if [ "$scanner_status" = "N/A" ]; then echo "N/A"
  elif [ "$critical" -gt 0 ] || [ "$high" -gt 0 ]; then echo "FAIL"
  elif [ "$medium" -gt 0 ] || [ "$low" -gt 0 ]; then echo "PARTIAL"
  else echo "PASS"; fi
}

determine_status_by_fail() {
  local scanner_status="$1" fail_count="$2"
  if [ "$scanner_status" = "N/A" ]; then echo "N/A"
  elif [ "$fail_count" -gt 0 ]; then echo "FAIL"
  else echo "PASS"; fi
}

ROW1_STATUS=$(determine_status_by_severity "$SAST_STATUS" "$SAST_CRITICAL" "$SAST_HIGH" "$SAST_MEDIUM" "$SAST_LOW")
ROW1_FINDINGS="C:${SAST_CRITICAL} H:${SAST_HIGH} M:${SAST_MEDIUM} L:${SAST_LOW}"

ROW2_STATUS=$(determine_status_by_severity "$VULN_STATUS" "$VULN_CRITICAL" "$VULN_HIGH" "$VULN_MEDIUM" "$VULN_LOW")
ROW2_FINDINGS="C:${VULN_CRITICAL} H:${VULN_HIGH} M:${VULN_MEDIUM} L:${VULN_LOW}"

ROW3_STATUS=$(determine_status_by_severity "$PENTEST_STATUS" "$PENTEST_CRITICAL" "$PENTEST_HIGH" "$PENTEST_MEDIUM" "$PENTEST_LOW")
ROW3_FINDINGS="C:${PENTEST_CRITICAL} H:${PENTEST_HIGH} M:${PENTEST_MEDIUM} L:${PENTEST_LOW}"

ROW4_STATUS=$(determine_status_by_fail "$SSDLC_STATUS" "$SSDLC_FAIL")
ROW4_FINDINGS="Pass:${SSDLC_PASS} Fail:${SSDLC_FAIL} Warn:${SSDLC_WARN}"

if [ "$SBOM_STATUS" = "N/A" ]; then ROW5_STATUS="N/A"; else ROW5_STATUS="PASS"; fi
ROW5_FINDINGS="Components: ${SBOM_TOTAL_COMPONENTS}"

if [ "$QG_STATUS" = "N/A" ]; then ROW6_STATUS="N/A"
elif [ "$QG_VALUE" = "PASS" ]; then ROW6_STATUS="PASS"
else ROW6_STATUS="FAIL"; fi
ROW6_FINDINGS="Gate: ${QG_VALUE} (C:${QG_CRITICAL} H:${QG_HIGH})"

# Summary cards
CARD_PASS=0; CARD_PARTIAL=0; CARD_FAIL=0; CARD_NA=0
for row_status in "$ROW1_STATUS" "$ROW2_STATUS" "$ROW3_STATUS" "$ROW4_STATUS" "$ROW5_STATUS" "$ROW6_STATUS"; do
  case "$row_status" in
    PASS)    CARD_PASS=$((CARD_PASS + 1)) ;;
    PARTIAL) CARD_PARTIAL=$((CARD_PARTIAL + 1)) ;;
    FAIL)    CARD_FAIL=$((CARD_FAIL + 1)) ;;
    N/A)     CARD_NA=$((CARD_NA + 1)) ;;
  esac
done

# status → badge HTML
status_badge() {
  local status="$1"
  case "$status" in
    PASS)    echo '<span class="badge badge-low">PASS</span>' ;;
    PARTIAL) echo '<span class="badge badge-medium">PARTIAL</span>' ;;
    FAIL)    echo '<span class="badge badge-critical">FAIL</span>' ;;
    N/A)     echo '<span class="text-muted">N/A</span>' ;;
  esac
}

FIRST_PROJECT_NAME=""
if [ -n "$FIRST_PROJECT_DIR" ]; then
  FIRST_PROJECT_NAME=$(basename "$FIRST_PROJECT_DIR")
fi

# ============================================================
# Generate HTML report
# ============================================================
mkdir -p "$SCAN_DIR/compliance"

cat > "$SCAN_DIR/compliance/index.html" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
HTMLHEAD

cat >> "$SCAN_DIR/compliance/index.html" << EOF
  <title>${KB_NAME_EN} Compliance Report - $SCAN_ID</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <style>
$OKLCH_STYLES
  </style>
</head>
<body class="min-h-screen">
  <div class="container mx-auto px-4 py-8 max-w-7xl">

    <header class="mb-8">
      <h1 class="fs-3xl font-bold mb-2">${KB_NAME_EN} Compliance Report</h1>
      <p class="text-secondary">Scan ID: <span class="font-mono">$SCAN_ID</span></p>
      <p class="text-muted fs-sm">產生時間: $TIMESTAMP</p>
    </header>

    <div class="grid grid-cols-4 gap-4 mb-8">
      <div class="card"><p class="card-value text-pass">$CARD_PASS</p><p class="card-label">PASS</p></div>
      <div class="card"><p class="card-value text-warn">$CARD_PARTIAL</p><p class="card-label">PARTIAL</p></div>
      <div class="card"><p class="card-value text-fail">$CARD_FAIL</p><p class="card-label">FAIL</p></div>
      <div class="card"><p class="card-value text-muted">$CARD_NA</p><p class="card-label">N/A</p></div>
    </div>

    <section class="mb-8">
      <h2 class="fs-xl font-bold mb-4 pb-2" style="border-bottom: 1px solid var(--border-subtle);">Scanner Compliance Mapping</h2>
      <div class="table-container">
        <table class="w-full">
          <thead>
            <tr>
              <th class="px-4 py-3 text-left">Scanner</th>
              <th class="px-4 py-3 text-left">Description</th>
              <th class="px-4 py-3 text-left">Status</th>
              <th class="px-4 py-3 text-left">Findings</th>
              <th class="px-4 py-3 text-left">Link</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td class="px-4 py-2 fs-sm">sast.sh</td>
              <td class="px-4 py-2">Secure Coding</td>
              <td class="px-4 py-2">$(status_badge "$ROW1_STATUS")</td>
              <td class="px-4 py-2 fs-sm text-secondary">$ROW1_FINDINGS</td>
              <td class="px-4 py-2 fs-sm">$([ -n "$FIRST_PROJECT_NAME" ] && echo "<a href=\"../$FIRST_PROJECT_NAME/#sast\" class=\"text-link hover:underline\">Detail</a>" || echo "<span class=\"text-muted\">-</span>")</td>
            </tr>
            <tr>
              <td class="px-4 py-2 fs-sm">vulnerability.sh</td>
              <td class="px-4 py-2">Vulnerability Management</td>
              <td class="px-4 py-2">$(status_badge "$ROW2_STATUS")</td>
              <td class="px-4 py-2 fs-sm text-secondary">$ROW2_FINDINGS</td>
              <td class="px-4 py-2 fs-sm">$([ -n "$FIRST_PROJECT_NAME" ] && echo "<a href=\"../$FIRST_PROJECT_NAME/#vulnerability\" class=\"text-link hover:underline\">Detail</a>" || echo "<span class=\"text-muted\">-</span>")</td>
            </tr>
            <tr>
              <td class="px-4 py-2 fs-sm">pentest.sh</td>
              <td class="px-4 py-2">Penetration Testing</td>
              <td class="px-4 py-2">$(status_badge "$ROW3_STATUS")</td>
              <td class="px-4 py-2 fs-sm text-secondary">$ROW3_FINDINGS</td>
              <td class="px-4 py-2 fs-sm"><a href="../pentest/" class="text-link hover:underline">Detail</a></td>
            </tr>
            <tr>
              <td class="px-4 py-2 fs-sm">ssdlc.sh</td>
              <td class="px-4 py-2">SSDLC</td>
              <td class="px-4 py-2">$(status_badge "$ROW4_STATUS")</td>
              <td class="px-4 py-2 fs-sm text-secondary">$ROW4_FINDINGS</td>
              <td class="px-4 py-2 fs-sm">$([ -n "$FIRST_PROJECT_NAME" ] && echo "<a href=\"../$FIRST_PROJECT_NAME/#ssdlc\" class=\"text-link hover:underline\">Detail</a>" || echo "<span class=\"text-muted\">-</span>")</td>
            </tr>
            <tr>
              <td class="px-4 py-2 fs-sm">sbom.sh</td>
              <td class="px-4 py-2">SBOM</td>
              <td class="px-4 py-2">$(status_badge "$ROW5_STATUS")</td>
              <td class="px-4 py-2 fs-sm text-secondary">$ROW5_FINDINGS</td>
              <td class="px-4 py-2 fs-sm">$([ -n "$FIRST_PROJECT_NAME" ] && echo "<a href=\"../$FIRST_PROJECT_NAME/#sbom\" class=\"text-link hover:underline\">Detail</a>" || echo "<span class=\"text-muted\">-</span>")</td>
            </tr>
            <tr>
              <td class="px-4 py-2 fs-sm">quality-gate.json</td>
              <td class="px-4 py-2">Quality Gate</td>
              <td class="px-4 py-2">$(status_badge "$ROW6_STATUS")</td>
              <td class="px-4 py-2 fs-sm text-secondary">$ROW6_FINDINGS</td>
              <td class="px-4 py-2 fs-sm"><a href="../" class="text-link hover:underline">Detail</a></td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <div class="mt-8">
      <a href="../" class="text-link hover:underline">&larr; 返回掃描報告</a>
    </div>
  </div>
</body>
</html>
EOF

echo "  Compliance report generated: $SCAN_DIR/compliance/index.html"
