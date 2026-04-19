#!/bin/bash
# scripts/monitor/redteam/attacks/initial-access.sh — Initial Access phase
# Usage: initial-access.sh <target_url> <output_dir> [--mode phishing-sim]
set -e

TARGET_URL="$1"
OUTPUT_DIR="$2"
shift 2
MODE="exploit"
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
FINDINGS="[]"
TOTAL=0

if [ "$MODE" = "exploit" ]; then
  # 1. SQL injection probes (safe — error-based detection only)
  echo "  [initial-access] SQLi probes on $TARGET_URL"
  for payload in "'" "1+OR+1=1" "1'+AND+'1'='1" "admin'--"; do
    ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$payload'))" 2>/dev/null || echo "$payload")
    RESPONSE=$(curl -s --max-time 10 "${TARGET_URL}?id=${ENCODED}" 2>/dev/null || echo "")
    if echo "$RESPONSE" | grep -qi -E 'sql|syntax|mysql|postgresql|oracle|sqlite|error in.*query'; then
      FINDINGS=$(echo "$FINDINGS" | jq --arg p "$payload" \
        '. + [{"type": "sqli", "severity": "high", "payload": $p, "evidence": "SQL error in response"}]')
      TOTAL=$((TOTAL + 1))
    fi
  done

  # 2. XSS probes (reflected — safe, detection only)
  echo "  [initial-access] XSS probes..."
  XSS_PAYLOAD='<script>alert(1)</script>'
  ENCODED_XSS=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$XSS_PAYLOAD'))" 2>/dev/null || echo "$XSS_PAYLOAD")
  RESPONSE=$(curl -s --max-time 10 "${TARGET_URL}?q=${ENCODED_XSS}" 2>/dev/null || echo "")
  if echo "$RESPONSE" | grep -q '<script>alert(1)</script>'; then
    FINDINGS=$(echo "$FINDINGS" | jq '. + [{"type": "xss", "severity": "high", "payload": "<script>alert(1)</script>", "evidence": "Reflected XSS"}]')
    TOTAL=$((TOTAL + 1))
  fi

  # 3. Nuclei vulnerability scan (if available)
  if command -v nuclei &>/dev/null; then
    echo "  [initial-access] Running Nuclei CVE templates..."
    NUCLEI_RAW=$(nuclei -u "$TARGET_URL" -t cves/ -severity critical,high -jsonl -silent 2>/dev/null | head -20 || echo "")
    if [ -n "$NUCLEI_RAW" ]; then
      NUCLEI_FINDINGS=$(echo "$NUCLEI_RAW" | jq -s 'length')
      TOTAL=$((TOTAL + NUCLEI_FINDINGS))
      FINDINGS=$(echo "$NUCLEI_RAW" | jq -s --argjson existing "$FINDINGS" \
        '$existing + [.[] | {"type": "nuclei-cve", "severity": .info.severity, "payload": .template_id, "evidence": .matched_at}]')
    fi
  fi
fi

CRITICAL=$(echo "$FINDINGS" | jq '[.[] | select(.severity == "critical")] | length')
HIGH=$(echo "$FINDINGS" | jq '[.[] | select(.severity == "high")] | length')

cat > "$OUTPUT_DIR/initial-access-result.json" << EOF
{
  "technique": "T1190",
  "phase": "initial-access",
  "mode": "$MODE",
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "target": "$TARGET_URL",
  "summary": {
    "total": $TOTAL,
    "critical": $CRITICAL,
    "high": $HIGH
  },
  "findings": $FINDINGS
}
EOF
