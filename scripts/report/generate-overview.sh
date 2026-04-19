#!/bin/bash
set -e
# Knowledge Body Audit Overview Report — from audit-result.json
# Uses OKLCH design-system styles, consistent with other reports.
#
# Usage: generate-overview.sh <scan_directory>
#   expects audit-result.json in $SCAN_DIR/audit/

SCAN_DIR="$1"

if [ -z "$SCAN_DIR" ]; then
  echo "Usage: generate-overview.sh <scan_directory>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/shell-config.sh"

SCAN_ID=$(basename "$SCAN_DIR")
AUDIT_DIR="$SCAN_DIR/audit"
RESULT_FILE="$AUDIT_DIR/audit-result.json"

if [ ! -f "$RESULT_FILE" ]; then
  echo "ERROR: $RESULT_FILE not found"
  exit 1
fi

mkdir -p "$AUDIT_DIR"

# Load OKLCH design-system styles
OKLCH_STYLES=""
if [ -f "$PROJECT_ROOT/templates/styles.css" ]; then
  OKLCH_STYLES=$(cat "$PROJECT_ROOT/templates/styles.css")
fi

# Read summary data
TIMESTAMP=$(jq -r '.timestamp // "unknown"' "$RESULT_FILE")
PASS_COUNT=$(jq '.summary.pass // 0' "$RESULT_FILE")
FAIL_COUNT=$(jq '.summary.fail // 0' "$RESULT_FILE")
WARN_COUNT=$(jq '.summary.warn // 0' "$RESULT_FILE")
TOTAL_COUNT=$(jq '.summary.total // 0' "$RESULT_FILE")
KB_FILES=$(jq '.summary.kb_files // .summary.isms_files // 0' "$RESULT_FILE")

# Build check rows and non-conformity items
CHECKS_ROWS=""
NONCONFORMITY_ITEMS=""

check_count=$(jq '.checks | length' "$RESULT_FILE")
i=0
while [ "$i" -lt "$check_count" ]; do
  cid=$(jq -r ".checks[$i].id" "$RESULT_FILE")
  cname=$(jq -r ".checks[$i].name" "$RESULT_FILE")
  cstatus=$(jq -r ".checks[$i].status" "$RESULT_FILE")
  cdetail=$(jq -r ".checks[$i].detail" "$RESULT_FILE")
  cref=$(jq -r ".checks[$i].ref" "$RESULT_FILE")

  case "$cstatus" in
    pass) badge_style="background:oklch(0.92 0.04 150);color:var(--color-pass);" badge_text="PASS" ;;
    fail) badge_style="background:oklch(0.92 0.06 25);color:var(--color-fail);" badge_text="FAIL" ;;
    *)    badge_style="background:oklch(0.92 0.04 80);color:var(--color-warn);" badge_text="WARN" ;;
  esac

  CHECKS_ROWS="$CHECKS_ROWS
      <tr>
        <td><strong>$cid</strong></td>
        <td>$cname</td>
        <td><span class=\"badge\" style=\"$badge_style\">$badge_text</span></td>
        <td>$cdetail</td>
        <td style=\"font-size:var(--text-xs);color:var(--text-muted)\">$cref</td>
      </tr>"

  if [ "$cstatus" = "fail" ]; then
    action="Review the check detail and correct the non-conformity per the referenced standard."
    NONCONFORMITY_ITEMS="$NONCONFORMITY_ITEMS
      <tr>
        <td><strong>$cid</strong></td>
        <td>$cname</td>
        <td>$cdetail</td>
        <td>$action</td>
      </tr>"
  fi

  i=$((i+1))
done

# Non-conformity section
NONCONFORMITY_SECTION=""
if [ -n "$NONCONFORMITY_ITEMS" ]; then
  NONCONFORMITY_SECTION="
    <section style=\"margin-top:2rem\">
      <h2 style=\"font-size:var(--text-xl);color:var(--color-fail)\">Non-Conformities / 不符合項</h2>
      <p style=\"color:var(--text-secondary);font-size:var(--text-sm)\">
        以下項目未通過自動化驗證，需進行矯正措施。
      </p>
      <div class=\"table-container\" style=\"margin-top:1rem\">
        <table>
          <thead>
            <tr><th>ID</th><th>Check</th><th>Detail</th><th>Suggested Corrective Action</th></tr>
          </thead>
          <tbody>$NONCONFORMITY_ITEMS
          </tbody>
        </table>
      </div>
    </section>"
fi

# Generate HTML
cat > "$AUDIT_DIR/index.html" << EOFHTML
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${KB_NAME_EN} Audit Overview — $SCAN_ID</title>
  <style>
$OKLCH_STYLES

    .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
    .header { margin-bottom: 2rem; }
    .header h1 { font-size: var(--text-3xl); margin: 0; }
    .header .subtitle { font-size: var(--text-sm); color: var(--text-secondary); margin-top: 0.25rem; }
    .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; margin: 1.5rem 0; }
    .badge { display: inline-block; padding: 0.125rem 0.5rem; border-radius: 0.25rem; font-size: var(--text-xs); font-weight: 700; }
    section { margin-top: 1.5rem; }
    section h2 { font-size: var(--text-xl); margin-bottom: 0.75rem; }
    .footer { margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid var(--border-subtle); font-size: var(--text-xs); color: var(--text-muted); }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>${KB_NAME_EN} Audit Overview</h1>
      <div class="subtitle">${KB_NAME} &mdash; 自動化文件稽核報告</div>
      <div class="subtitle">Scan: $SCAN_ID &nbsp;|&nbsp; Timestamp: $TIMESTAMP</div>
    </div>

    <!-- Summary Cards -->
    <div class="summary-grid">
      <div class="card">
        <div class="card-value" style="color:var(--color-pass)">$PASS_COUNT</div>
        <div class="card-label">PASS</div>
      </div>
      <div class="card">
        <div class="card-value" style="color:var(--color-fail)">$FAIL_COUNT</div>
        <div class="card-label">FAIL</div>
      </div>
      <div class="card">
        <div class="card-value" style="color:var(--color-warn)">$WARN_COUNT</div>
        <div class="card-label">WARN</div>
      </div>
      <div class="card">
        <div class="card-value" style="color:var(--text-secondary)">$TOTAL_COUNT</div>
        <div class="card-label">Total Checks</div>
      </div>
      <div class="card">
        <div class="card-value" style="color:var(--color-info)">$KB_FILES</div>
        <div class="card-label">KB Files</div>
      </div>
    </div>

    <!-- Checks Table -->
    <section>
      <h2>Audit Checks / 稽核檢查項</h2>
      <div class="table-container">
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Name</th>
              <th>Status</th>
              <th>Detail</th>
              <th>Source Reference</th>
            </tr>
          </thead>
          <tbody>$CHECKS_ROWS
          </tbody>
        </table>
      </div>
    </section>

    <!-- Non-Conformities -->
$NONCONFORMITY_SECTION

    <!-- Footer -->
    <div class="footer">
      <p>
        <a href="../index.html">&larr; Back to Scan Index</a>
      </p>
      <p>Generated by knowledge-audit &mdash; ${KB_NAME_EN}</p>
    </div>
  </div>
</body>
</html>
EOFHTML

echo "Audit overview HTML report generated: $AUDIT_DIR/index.html"
