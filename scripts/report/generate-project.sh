#!/bin/bash
# Generate detailed HTML report for a single project/target
# OKLCH light theme

PROJECT_NAME="$1"
REPO_URL="$2"
REPORT_DIR="$3"

if [ -z "$PROJECT_NAME" ] || [ -z "$REPO_URL" ] || [ -z "$REPORT_DIR" ]; then
  echo "Usage: generate-project.sh <project_name> <repo_url> <report_directory>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/shell-config.sh"

# Read OKLCH styles for inline injection
OKLCH_STYLES=""
if [ -f "$PROJECT_ROOT/templates/styles.css" ]; then
  OKLCH_STYLES=$(cat "$PROJECT_ROOT/templates/styles.css")
fi

# Read scan results
SAST_RESULT="$REPORT_DIR/sast-result.json"
VULN_RESULT="$REPORT_DIR/vulnerability-result.json"
SSDLC_RESULT="$REPORT_DIR/ssdlc-result.json"
SBOM_RESULT="$REPORT_DIR/sbom-result.json"
AI_SAFETY_RESULT="$REPORT_DIR/ai-safety-result.json"
AI_SUPPLY_RESULT="$REPORT_DIR/ai-supply-chain-result.json"

# Get summary values with defaults
SAST_TOTAL=0; SAST_CRITICAL=0; SAST_HIGH=0
VULN_TOTAL=0; VULN_CRITICAL=0; VULN_HIGH=0
SSDLC_PASS=0; SSDLC_FAIL=0; SSDLC_WARN=0; SSDLC_TOTAL=0
SBOM_TOTAL=0; SBOM_NODE=0; SBOM_PYTHON=0
AI_SAFETY_PASS=0; AI_SAFETY_TOTAL=0
AI_SUPPLY_PASS=0; AI_SUPPLY_TOTAL=0

if [ -f "$SAST_RESULT" ]; then
  SAST_TOTAL=$(jq '.summary.total_findings // 0' "$SAST_RESULT" 2>/dev/null || echo "0")
  SAST_CRITICAL=$(jq '.summary.critical // 0' "$SAST_RESULT" 2>/dev/null || echo "0")
  SAST_HIGH=$(jq '.summary.high // 0' "$SAST_RESULT" 2>/dev/null || echo "0")
fi

if [ -f "$VULN_RESULT" ]; then
  VULN_TOTAL=$(jq '.summary.total // 0' "$VULN_RESULT" 2>/dev/null || echo "0")
  VULN_CRITICAL=$(jq '.summary.critical // 0' "$VULN_RESULT" 2>/dev/null || echo "0")
  VULN_HIGH=$(jq '.summary.high // 0' "$VULN_RESULT" 2>/dev/null || echo "0")
fi

if [ -f "$SSDLC_RESULT" ]; then
  SSDLC_PASS=$(jq '.summary.pass // 0' "$SSDLC_RESULT" 2>/dev/null || echo "0")
  SSDLC_FAIL=$(jq '.summary.fail // 0' "$SSDLC_RESULT" 2>/dev/null || echo "0")
  SSDLC_WARN=$(jq '.summary.warn // 0' "$SSDLC_RESULT" 2>/dev/null || echo "0")
  SSDLC_TOTAL=$(jq '.summary.total // 0' "$SSDLC_RESULT" 2>/dev/null || echo "0")
fi

if [ -f "$SBOM_RESULT" ]; then
  SBOM_TOTAL=$(jq '.summary.total_components // 0' "$SBOM_RESULT" 2>/dev/null || echo "0")
  SBOM_NODE=$(jq '.summary.node_components // 0' "$SBOM_RESULT" 2>/dev/null || echo "0")
  SBOM_PYTHON=$(jq '.summary.python_components // 0' "$SBOM_RESULT" 2>/dev/null || echo "0")
fi

if [ -f "$AI_SAFETY_RESULT" ]; then
  AI_SAFETY_PASS=$(jq '.summary.pass // 0' "$AI_SAFETY_RESULT" 2>/dev/null || echo "0")
  AI_SAFETY_TOTAL=$(jq '.summary.total // 0' "$AI_SAFETY_RESULT" 2>/dev/null || echo "0")
fi

if [ -f "$AI_SUPPLY_RESULT" ]; then
  AI_SUPPLY_PASS=$(jq '.summary.pass // 0' "$AI_SUPPLY_RESULT" 2>/dev/null || echo "0")
  AI_SUPPLY_TOTAL=$(jq '.summary.total // 0' "$AI_SUPPLY_RESULT" 2>/dev/null || echo "0")
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Generate SSDLC table rows
SSDLC_ROWS=""
if [ -f "$SSDLC_RESULT" ]; then
  SSDLC_ROWS=$(jq -r '.checks[] | "<tr><td class=\"px-4 py-2\">\(.name)</td><td class=\"px-4 py-2 status-\(.status | ascii_downcase)\">\(.status)</td><td class=\"px-4 py-2 text-secondary\">\(.detail)</td></tr>"' "$SSDLC_RESULT" 2>/dev/null || echo "")
fi

# Generate SAST findings
SAST_CONTENT=""
if [ -f "$REPORT_DIR/semgrep-report.json" ]; then
  SAST_CONTENT=$(jq -r '.results[:20][] | "[\(.extra.severity // "INFO")] \(.path):\(.start.line)\n  \(.extra.message // "No message")\n"' "$REPORT_DIR/semgrep-report.json" 2>/dev/null || echo "No findings")
fi

# Generate vulnerability content
VULN_CONTENT=""
if [ -f "$REPORT_DIR/trivy-report.txt" ]; then
  VULN_CONTENT=$(head -100 "$REPORT_DIR/trivy-report.txt" 2>/dev/null || echo "No report")
fi

# Generate AI Safety table rows
AI_SAFETY_ROWS=""
if [ -f "$AI_SAFETY_RESULT" ]; then
  AI_SAFETY_STATUS_VAL=$(jq -r '.status' "$AI_SAFETY_RESULT" 2>/dev/null || echo "skipped")
  if [ "$AI_SAFETY_STATUS_VAL" != "skipped" ]; then
    AI_SAFETY_ROWS=$(jq -r '.checks[]? | "<tr><td class=\"px-4 py-2\">\(.name)</td><td class=\"px-4 py-2 status-\(.status | ascii_downcase)\">\(.status)</td><td class=\"px-4 py-2 text-secondary\">\(.detail // "-")</td><td class=\"px-4 py-2 text-muted fs-xs\">\(.owasp_llm // "-")</td><td class=\"px-4 py-2 text-muted fs-xs\">\(.nist_ai_rmf // "-")</td></tr>"' "$AI_SAFETY_RESULT" 2>/dev/null || echo "")
  fi
fi

# Generate AI Supply Chain table rows
AI_SUPPLY_ROWS=""
if [ -f "$AI_SUPPLY_RESULT" ]; then
  AI_SUPPLY_STATUS_VAL=$(jq -r '.status' "$AI_SUPPLY_RESULT" 2>/dev/null || echo "skipped")
  if [ "$AI_SUPPLY_STATUS_VAL" != "skipped" ]; then
    AI_SUPPLY_ROWS=$(jq -r '.checks[]? | "<tr><td class=\"px-4 py-2\">\(.name)</td><td class=\"px-4 py-2 status-\(.status | ascii_downcase)\">\(.status)</td><td class=\"px-4 py-2 text-secondary\">\(.detail // "-")</td></tr>"' "$AI_SUPPLY_RESULT" 2>/dev/null || echo "")
  fi
fi

# Generate HTML report
cat > "$REPORT_DIR/index.html" << 'CSSEOF'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
CSSEOF

cat >> "$REPORT_DIR/index.html" << EOF
  <title>$PROJECT_NAME - 掃描報告</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <style>
$OKLCH_STYLES
  </style>
</head>
<body class="min-h-screen">
  <div class="container mx-auto px-4 py-8 max-w-6xl">
    <header class="mb-8">
      <h1 class="fs-3xl font-bold mb-2">$PROJECT_NAME</h1>
      <p class="text-secondary">
        <a href="$REPO_URL" target="_blank">$REPO_URL</a>
      </p>
      <p class="text-muted fs-xs mt-1">掃描時間: $TIMESTAMP</p>
    </header>

    <!-- Summary Cards -->
    <div class="grid grid-cols-5 gap-4 mb-8">
      <div class="card">
        <p class="card-value text-pass">$SSDLC_PASS/$SSDLC_TOTAL</p>
        <p class="card-label">SSDLC</p>
      </div>
      <div class="card">
        <p class="card-value text-warn">$SAST_TOTAL</p>
        <p class="card-label">SAST</p>
      </div>
      <div class="card">
        <p class="card-value text-critical">$VULN_CRITICAL</p>
        <p class="card-label">Critical</p>
      </div>
      <div class="card">
        <p class="card-value text-high">$VULN_HIGH</p>
        <p class="card-label">High</p>
      </div>
      <div class="card">
        <p class="card-value text-cyan">$SBOM_TOTAL</p>
        <p class="card-label">SBOM</p>
      </div>
    </div>

    <!-- SSDLC Section -->
    <section id="ssdlc" class="mb-8">
      <h2 class="fs-xl font-bold mb-4" style="border-bottom: 1px solid var(--border-subtle); padding-bottom: 0.5rem;">SSDLC 安全開發生命週期檢核</h2>
      <div class="table-container">
        <table>
          <thead>
            <tr><th>檢核項目</th><th>狀態</th><th>說明</th></tr>
          </thead>
          <tbody>
$SSDLC_ROWS
          </tbody>
        </table>
      </div>
    </section>

    <!-- SAST Section -->
    <section id="sast" class="mb-8">
      <h2 class="fs-xl font-bold mb-4" style="border-bottom: 1px solid var(--border-subtle); padding-bottom: 0.5rem;">SAST 源碼掃描 (Semgrep)</h2>
      <div class="bg-surface p-4 rounded-lg">
        <p class="mb-2">發現 <span class="text-warn font-bold">$SAST_TOTAL</span> 個問題</p>
        <pre><code>$SAST_CONTENT</code></pre>
      </div>
    </section>

    <!-- Vulnerability Section -->
    <section id="vulnerability" class="mb-8">
      <h2 class="fs-xl font-bold mb-4" style="border-bottom: 1px solid var(--border-subtle); padding-bottom: 0.5rem;">弱點掃描 (Trivy)</h2>
      <div class="bg-surface p-4 rounded-lg">
        <p class="mb-2">
          Critical: <span class="text-critical font-bold">$VULN_CRITICAL</span> |
          High: <span class="text-high font-bold">$VULN_HIGH</span> |
          Total: <span class="text-warn font-bold">$VULN_TOTAL</span>
        </p>
        <pre><code>$VULN_CONTENT</code></pre>
      </div>
    </section>

    <!-- SBOM Section -->
    <section id="sbom" class="mb-8">
      <h2 class="fs-xl font-bold mb-4" style="border-bottom: 1px solid var(--border-subtle); padding-bottom: 0.5rem;">SBOM 軟體物料清單</h2>
      <div class="grid grid-cols-3 gap-4">
        <div class="card"><p class="card-value text-info">$SBOM_TOTAL</p><p class="card-label">Total Components</p></div>
        <div class="card"><p class="card-value text-pass">$SBOM_NODE</p><p class="card-label">Node.js</p></div>
        <div class="card"><p class="card-value text-medium">$SBOM_PYTHON</p><p class="card-label">Python</p></div>
      </div>
    </section>
EOF

if [ -n "$AI_SAFETY_ROWS" ]; then
cat >> "$REPORT_DIR/index.html" << EOF
    <!-- AI Safety Section -->
    <section id="ai-safety" class="mb-8">
      <h2 class="fs-xl font-bold mb-4" style="border-bottom: 1px solid var(--border-subtle); padding-bottom: 0.5rem;">AI/LLM 安全檢查</h2>
      <div class="grid grid-cols-2 gap-4 mb-4">
        <div class="card"><p class="card-value text-pass">$AI_SAFETY_PASS/$AI_SAFETY_TOTAL</p><p class="card-label">AI Safety</p></div>
        <div class="card"><p class="card-value text-pass">$AI_SUPPLY_PASS/$AI_SUPPLY_TOTAL</p><p class="card-label">AI Supply Chain</p></div>
      </div>
      <div class="table-container">
        <table>
          <thead>
            <tr><th>檢查項目</th><th>狀態</th><th>說明</th><th>OWASP LLM</th><th>NIST AI RMF</th></tr>
          </thead>
          <tbody>
$AI_SAFETY_ROWS
          </tbody>
        </table>
      </div>
    </section>
EOF
fi

if [ -n "$AI_SUPPLY_ROWS" ]; then
cat >> "$REPORT_DIR/index.html" << EOF
    <!-- AI Supply Chain Section -->
    <section id="ai-supply-chain" class="mb-8">
      <h2 class="fs-xl font-bold mb-4" style="border-bottom: 1px solid var(--border-subtle); padding-bottom: 0.5rem;">AI 模型供應鏈風險</h2>
      <div class="table-container">
        <table>
          <thead><tr><th>檢查項目</th><th>狀態</th><th>說明</th></tr></thead>
          <tbody>
$AI_SUPPLY_ROWS
          </tbody>
        </table>
      </div>
    </section>
EOF
fi

cat >> "$REPORT_DIR/index.html" << EOF
    <div class="mt-8">
      <a href="../">&larr; 返回報告列表</a>
    </div>
  </div>
</body>
</html>
EOF

# Save summary for index generation
cat > "$REPORT_DIR/summary.json" << EOF
{
  "project_name": "$PROJECT_NAME",
  "repo_url": "$REPO_URL",
  "timestamp": "$TIMESTAMP",
  "ssdlc": { "pass": $SSDLC_PASS, "total": $SSDLC_TOTAL },
  "sast": { "total": $SAST_TOTAL },
  "vulnerability": { "critical": $VULN_CRITICAL, "high": $VULN_HIGH, "total": $VULN_TOTAL },
  "sbom": { "total": $SBOM_TOTAL },
  "ai_safety": { "pass": $AI_SAFETY_PASS, "total": $AI_SAFETY_TOTAL }
}
EOF

echo "  Project report generated: $REPORT_DIR/index.html"
