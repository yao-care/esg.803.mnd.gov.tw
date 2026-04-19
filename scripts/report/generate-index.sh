#!/bin/bash
# Generate index page for all scan results

SCAN_DIR="$1"

if [ -z "$SCAN_DIR" ]; then
  echo "Usage: generate-index.sh <scan_directory>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/shell-config.sh"
DOCS_DIR="$PROJECT_ROOT/docs"

SCAN_ID=$(basename "$SCAN_DIR")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Load OKLCH design-system styles
OKLCH_STYLES=""
if [ -f "$PROJECT_ROOT/templates/styles.css" ]; then
  OKLCH_STYLES=$(cat "$PROJECT_ROOT/templates/styles.css")
fi

# Read quality gate
QG_STATUS="N/A"
QG_CRITICAL=0; QG_HIGH=0
if [ -f "$SCAN_DIR/quality-gate.json" ]; then
  QG_STATUS=$(jq -r '.quality_gate // "N/A"' "$SCAN_DIR/quality-gate.json" 2>/dev/null || echo "N/A")
  QG_CRITICAL=$(jq '.critical // 0' "$SCAN_DIR/quality-gate.json" 2>/dev/null || echo "0")
  QG_HIGH=$(jq '.high // 0' "$SCAN_DIR/quality-gate.json" 2>/dev/null || echo "0")
fi

# Read operational readiness
OP_READINESS="N/A"
if [ -f "$SCAN_DIR/quality-gate.json" ]; then
  OP_READINESS=$(jq -r '.operational_readiness // "N/A"' "$SCAN_DIR/quality-gate.json" 2>/dev/null || echo "N/A")
fi

# Read metadata
WEB_URL=""
CUR_PROJECT_NAME=""
if [ -f "$SCAN_DIR/metadata.json" ]; then
  WEB_URL=$(jq -r '.web_url // ""' "$SCAN_DIR/metadata.json" 2>/dev/null || echo "")
  CUR_PROJECT_NAME=$(jq -r '.project_name // ""' "$SCAN_DIR/metadata.json" 2>/dev/null || echo "")
fi
if [ -z "$CUR_PROJECT_NAME" ]; then CUR_PROJECT_NAME="unknown"; fi

# Get pentest results
PENTEST_TOTAL=0
PENTEST_DIR="$SCAN_DIR/pentest"
if [ -f "$PENTEST_DIR/pentest-result.json" ]; then
  PENTEST_TOTAL=$(jq '.summary.total_findings // 0' "$PENTEST_DIR/pentest-result.json" 2>/dev/null || echo "0")
fi

echo "Generating scan index page..."

PROJECT_ROWS=""

for project_dir in "$SCAN_DIR"/*/; do
  if [ -d "$project_dir" ] && [ "$(basename "$project_dir")" != "pentest" ] && [ "$(basename "$project_dir")" != "seo" ] && [ "$(basename "$project_dir")" != "runtime" ]; then
    project_name=$(basename "$project_dir")
    summary_file="$project_dir/summary.json"

    if [ -f "$summary_file" ]; then
      REPO_URL=$(jq -r '.repo_url // ""' "$summary_file" 2>/dev/null || echo "")
      SSDLC_PASS=$(jq '.ssdlc.pass // 0' "$summary_file" 2>/dev/null || echo "0")
      SSDLC_TOTAL=$(jq '.ssdlc.total // 0' "$summary_file" 2>/dev/null || echo "0")
      SAST_TOTAL=$(jq '.sast.total // 0' "$summary_file" 2>/dev/null || echo "0")
      VULN_CRITICAL=$(jq '.vulnerability.critical // 0' "$summary_file" 2>/dev/null || echo "0")
      VULN_HIGH=$(jq '.vulnerability.high // 0' "$summary_file" 2>/dev/null || echo "0")

      LINKS="<a href=\"$REPO_URL\" class=\"text-link hover:underline\" target=\"_blank\">repo</a>"
      if [ -n "$WEB_URL" ]; then
        LINKS="$LINKS / <a href=\"$WEB_URL\" class=\"text-link hover:underline\" target=\"_blank\">web</a>"
      fi

      PROJECT_ROWS="$PROJECT_ROWS
      <tr>
        <td class=\"px-3 py-3 font-medium\">$project_name</td>
        <td class=\"px-3 py-3\">$LINKS</td>
        <td class=\"px-3 py-3 font-mono fs-sm\">$TIMESTAMP</td>
        <td class=\"px-3 py-3\"><a href=\"$project_name/#ssdlc\" class=\"hover:underline\">$SSDLC_PASS/$SSDLC_TOTAL</a></td>
        <td class=\"px-3 py-3\"><a href=\"$project_name/#sast\" class=\"hover:underline text-medium\">$SAST_TOTAL</a></td>
        <td class=\"px-3 py-3\"><a href=\"$project_name/#vulnerability\" class=\"hover:underline\"><span class=\"text-critical\">$VULN_CRITICAL</span>/<span class=\"text-high\">$VULN_HIGH</span></a></td>
        <td class=\"px-3 py-3\"><a href=\"pentest/\" class=\"hover:underline text-purple\">$PENTEST_TOTAL</a></td>
      </tr>"
    fi
  fi
done

# Web-only scan: add a row when no repo projects exist
if [ -z "$PROJECT_ROWS" ] && [ -n "$WEB_URL" ]; then
  PROJECT_ROWS="
      <tr>
        <td class=\"px-3 py-3 font-medium\">$CUR_PROJECT_NAME</td>
        <td class=\"px-3 py-3\"><a href=\"$WEB_URL\" class=\"text-link hover:underline\" target=\"_blank\">$WEB_URL</a></td>
        <td class=\"px-3 py-3 font-mono fs-sm\">$TIMESTAMP</td>
        <td class=\"px-3 py-3 text-muted\">-</td>
        <td class=\"px-3 py-3 text-muted\">-</td>
        <td class=\"px-3 py-3 text-muted\">-</td>
        <td class=\"px-3 py-3\"><a href=\"pentest/\" class=\"hover:underline text-purple\">$PENTEST_TOTAL</a></td>
      </tr>"
fi

# Generate scan index HTML
cat > "$SCAN_DIR/index.html" << EOF
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${KB_NAME_EN} 掃描報告 - $SCAN_ID</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <style>
$OKLCH_STYLES
  </style>
</head>
<body class="min-h-screen">
  <div class="container mx-auto px-4 py-8 max-w-7xl">
    <header class="mb-8">
      <h1 class="fs-3xl font-bold mb-2">${KB_ORG} 掃描報告</h1>
      <p class="text-secondary">專案: <span class="font-mono">$CUR_PROJECT_NAME</span> (<a href="../../projects/$CUR_PROJECT_NAME/" class="text-link hover:underline">歷史紀錄</a>)</p>
      <p class="text-secondary">Scan ID: <span class="font-mono">$SCAN_ID</span></p>
      <p class="text-muted fs-sm">掃描時間: $TIMESTAMP</p>
    </header>

    <div class="grid grid-cols-4 gap-4 mb-6">
      <div class="card">
        <p class="card-value $([ "$QG_STATUS" = "PASS" ] && echo "qg-pass" || echo "qg-fail")">$QG_STATUS</p>
        <p class="card-label">Quality Gate</p>
      </div>
      <div class="card">
        <p class="card-value text-critical">$QG_CRITICAL</p>
        <p class="card-label">Critical</p>
      </div>
      <div class="card">
        <p class="card-value text-high">$QG_HIGH</p>
        <p class="card-label">High</p>
      </div>
      <div class="card">
        <p class="card-value $([ "$OP_READINESS" = "READY" ] && echo "qg-pass" || ([ "$OP_READINESS" = "N/A" ] && echo "text-muted" || echo "qg-fail"))">$OP_READINESS</p>
        <p class="card-label">Operational Readiness</p>
      </div>
    </div>

    <div class="table-container">
      <table class="w-full">
        <thead>
          <tr>
            <th class="px-3 py-3 text-left">專案</th>
            <th class="px-3 py-3 text-left">連結</th>
            <th class="px-3 py-3 text-left">時間</th>
            <th class="px-3 py-3 text-left">SSDLC</th>
            <th class="px-3 py-3 text-left">SAST</th>
            <th class="px-3 py-3 text-left">弱點</th>
            <th class="px-3 py-3 text-left">滲透</th>
          </tr>
        </thead>
        <tbody>
$PROJECT_ROWS
        </tbody>
      </table>
    </div>

    <div class="mt-8">
      <a href="../../projects/$CUR_PROJECT_NAME/" class="text-link hover:underline">&larr; 返回專案歷史</a> | <a href="../../" class="text-link hover:underline">首頁</a>
    </div>
  </div>
</body>
</html>
EOF

# Generate pentest index if exists
if [ -d "$PENTEST_DIR" ] && [ -f "$PENTEST_DIR/pentest-result.json" ]; then
  PENTEST_CRITICAL=$(jq '.summary.critical // 0' "$PENTEST_DIR/pentest-result.json" 2>/dev/null || echo "0")
  PENTEST_HIGH=$(jq '.summary.high // 0' "$PENTEST_DIR/pentest-result.json" 2>/dev/null || echo "0")
  PENTEST_MEDIUM=$(jq '.summary.medium // 0' "$PENTEST_DIR/pentest-result.json" 2>/dev/null || echo "0")

  NUCLEI_CONTENT=""
  if [ -f "$PENTEST_DIR/nuclei-report.txt" ]; then
    NUCLEI_CONTENT=$(cat "$PENTEST_DIR/nuclei-report.txt" 2>/dev/null || echo "No findings")
  fi

  cat > "$PENTEST_DIR/index.html" << EOF
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>滲透測試報告</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <style>
$OKLCH_STYLES
  </style>
</head>
<body class="min-h-screen">
  <div class="container mx-auto px-4 py-8 max-w-6xl">
    <header class="mb-8">
      <h1 class="fs-3xl font-bold mb-2">滲透測試報告</h1>
      <p class="text-secondary">目標: <a href="$WEB_URL" class="text-link hover:underline" target="_blank">$WEB_URL</a></p>
      <p class="text-muted fs-sm">掃描時間: $TIMESTAMP</p>
    </header>

    <div class="grid grid-cols-4 gap-4 mb-8">
      <div class="card"><p class="card-value text-purple">$PENTEST_TOTAL</p><p class="card-label">總發現</p></div>
      <div class="card"><p class="card-value text-critical">$PENTEST_CRITICAL</p><p class="card-label">Critical</p></div>
      <div class="card"><p class="card-value text-high">$PENTEST_HIGH</p><p class="card-label">High</p></div>
      <div class="card"><p class="card-value text-medium">$PENTEST_MEDIUM</p><p class="card-label">Medium</p></div>
    </div>

    <section class="mb-8">
      <h2 class="fs-xl font-bold mb-4 pb-2" style="border-bottom: 1px solid var(--border-subtle);">Nuclei 掃描結果</h2>
      <div class="bg-surface rounded-lg p-4">
        <pre><code>$NUCLEI_CONTENT</code></pre>
      </div>
    </section>

    <div class="mt-8">
      <a href="../" class="text-link hover:underline">&larr; 返回報告列表</a>
    </div>
  </div>
</body>
</html>
EOF
fi

# ===========================================
#  Generate per-project history page
# ===========================================
echo "Updating project history page..."

PROJ_DIR="$DOCS_DIR/projects/$CUR_PROJECT_NAME"
mkdir -p "$PROJ_DIR"

PROJ_SCAN_ROWS=""
PROJ_SCAN_COUNT=0

for scan_path in $(ls -dt "$DOCS_DIR/scans"/*/ 2>/dev/null); do
  [ ! -f "$scan_path/metadata.json" ] && continue
  spname=$(jq -r '.project_name // "unknown"' "$scan_path/metadata.json" 2>/dev/null || echo "unknown")
  if [ -z "$spname" ]; then spname="unknown"; fi
  [ "$spname" != "$CUR_PROJECT_NAME" ] && continue

  scan_name=$(basename "$scan_path")
  scan_date=$(echo "$scan_name" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
  PROJ_SCAN_COUNT=$((PROJ_SCAN_COUNT + 1))

  SSDLC_S="-"; SAST_S="-"; VULN_S="-"
  for subdir in "$scan_path"/*/; do
    subname=$(basename "$subdir")
    [ "$subname" = "pentest" ] || [ "$subname" = "seo" ] || [ "$subname" = "runtime" ] && continue
    if [ -f "$subdir/summary.json" ]; then
      sp=$(jq '.ssdlc.pass // 0' "$subdir/summary.json" 2>/dev/null || echo 0)
      st=$(jq '.ssdlc.total // 0' "$subdir/summary.json" 2>/dev/null || echo 0)
      SSDLC_S="$sp/$st"
      SAST_S=$(jq '.sast.total // 0' "$subdir/summary.json" 2>/dev/null || echo 0)
      vc=$(jq '.vulnerability.critical // 0' "$subdir/summary.json" 2>/dev/null || echo 0)
      vh=$(jq '.vulnerability.high // 0' "$subdir/summary.json" 2>/dev/null || echo 0)
      VULN_S="${vc}C/${vh}H"
      break
    fi
  done

  PROJ_SCAN_ROWS="$PROJ_SCAN_ROWS
          <tr>
            <td class=\"px-6 py-3 font-mono\"><a href=\"../../scans/$scan_name/\" class=\"text-link hover:underline\">$scan_name</a></td>
            <td class=\"px-6 py-3\">$scan_date</td>
            <td class=\"px-6 py-3\">$SSDLC_S</td>
            <td class=\"px-6 py-3\">$SAST_S</td>
            <td class=\"px-6 py-3\">$VULN_S</td>
          </tr>"
done

cat > "$PROJ_DIR/index.html" << EOF
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$CUR_PROJECT_NAME - 掃描歷史</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <style>
$OKLCH_STYLES
  </style>
</head>
<body class="min-h-screen">
  <div class="container mx-auto px-4 py-8 max-w-5xl">
    <header class="mb-8">
      <h1 class="fs-3xl font-bold">$CUR_PROJECT_NAME</h1>
      <p class="text-secondary mt-2">掃描歷史紀錄 (共 $PROJ_SCAN_COUNT 次)</p>
    </header>

    <div class="table-container">
      <table class="w-full">
        <thead>
          <tr>
            <th class="px-6 py-3 text-left">掃描 ID</th>
            <th class="px-6 py-3 text-left">時間</th>
            <th class="px-6 py-3 text-left">SSDLC</th>
            <th class="px-6 py-3 text-left">SAST</th>
            <th class="px-6 py-3 text-left">弱點</th>
          </tr>
        </thead>
        <tbody>
$PROJ_SCAN_ROWS
        </tbody>
      </table>
    </div>

    <div class="mt-8">
      <a href="../../" class="text-link hover:underline">&larr; 首頁</a>
    </div>

    <footer class="mt-8 text-center text-muted fs-sm">
      <p>Powered by ${KB_NAME_EN}</p>
    </footer>
  </div>
</body>
</html>
EOF

echo "Project page generated: $PROJ_DIR/index.html"

# ===========================================
#  Generate compliance mapping report
# ===========================================
if [ -f "$SCRIPT_DIR/generate-compliance.sh" ]; then
  echo "Generating compliance report..."
  "$SCRIPT_DIR/generate-compliance.sh" "$SCAN_DIR" || echo "Compliance report generation failed"
fi

# ===========================================
#  Generate docs/index.html (landing page, only if missing)
# ===========================================
if [ ! -f "$DOCS_DIR/index.html" ]; then
  echo "Generating landing page..."
  cp "$PROJECT_ROOT/templates/landing.html" "$DOCS_DIR/index.html"
fi

echo "Index pages generated successfully!"
