#!/bin/bash
# scripts/monitor/redteam/attacks/lateral.sh — Lateral Movement simulation
# Usage: lateral.sh <target_url> <output_dir> [extra_args]
set -e

TARGET_URL="$1"
OUTPUT_DIR="$2"
shift 2

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
FINDINGS="[]"

# 1. API endpoint enumeration
echo "  [lateral] API endpoint enumeration on $TARGET_URL"
API_PATHS=("/api" "/api/v1" "/api/v2" "/api/users" "/api/admin" "/api/config"
           "/api/health" "/api/status" "/api/docs" "/api/swagger.json"
           "/graphql" "/internal" "/admin" "/management" "/actuator")

ACCESSIBLE=0
for path in "${API_PATHS[@]}"; do
  CODE=$(curl -so /dev/null -w '%{http_code}' --max-time 5 "${TARGET_URL}${path}" 2>/dev/null || echo "000")
  if [ "$CODE" != "000" ] && [ "$CODE" != "404" ] && [ "$CODE" != "403" ]; then
    FINDINGS=$(echo "$FINDINGS" | jq --arg p "$path" --arg c "$CODE" \
      '. + [{"type": "api-endpoint", "severity": "medium", "path": $p, "status": ($c | tonumber)}]')
    ACCESSIBLE=$((ACCESSIBLE + 1))
  fi
done

# 2. CORS misconfiguration check
echo "  [lateral] CORS misconfiguration check..."
CORS_HEADER=$(curl -sI -H "Origin: https://evil.com" --max-time 10 "$TARGET_URL" 2>/dev/null \
  | grep -i 'access-control-allow-origin' || echo "")
if echo "$CORS_HEADER" | grep -qi "evil.com\|\*"; then
  FINDINGS=$(echo "$FINDINGS" | jq --arg h "$CORS_HEADER" \
    '. + [{"type": "cors-misconfig", "severity": "high", "evidence": $h}]')
fi

TOTAL=$(echo "$FINDINGS" | jq 'length')

cat > "$OUTPUT_DIR/lateral-result.json" << EOF
{
  "technique": "T1021",
  "phase": "lateral",
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "target": "$TARGET_URL",
  "summary": {
    "total": $TOTAL,
    "api_endpoints_accessible": $ACCESSIBLE
  },
  "findings": $FINDINGS
}
EOF
