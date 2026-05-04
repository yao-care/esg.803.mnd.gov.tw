#!/bin/bash
# scripts/monitor/redteam/attacks/recon.sh — Reconnaissance phase
# Usage: recon.sh <target_url> <output_dir> [extra_args]
set -e

TARGET_URL="$1"
OUTPUT_DIR="$2"
shift 2
EXTRA_ARGS="$*"

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
FINDINGS="[]"

# 1. HTTP fingerprinting
echo "  [recon] HTTP fingerprinting: $TARGET_URL"
HTTP_HEADERS=$(curl -sI -o /dev/null -w '%{http_code}|%{content_type}|%{redirect_url}' \
  --max-time 10 "$TARGET_URL" 2>/dev/null || echo "000||")
HTTP_CODE=$(echo "$HTTP_HEADERS" | cut -d'|' -f1)
SERVER_HEADER=$(curl -sI --max-time 10 "$TARGET_URL" 2>/dev/null | grep -i '^server:' | head -1 || echo "")

# 2. Technology detection via response headers
TECH_HEADERS=$(curl -sI --max-time 10 "$TARGET_URL" 2>/dev/null | grep -iE '^(x-powered-by|x-generator|x-aspnet|x-drupal):' || echo "")

# 3. Nuclei technology detection (if available)
NUCLEI_RESULTS="[]"
if command -v nuclei &>/dev/null; then
  echo "  [recon] Running Nuclei tech detection..."
  NUCLEI_RAW=$(nuclei -u "$TARGET_URL" -t technologies/ -jsonl -silent 2>/dev/null || echo "")
  if [ -n "$NUCLEI_RAW" ]; then
    NUCLEI_RESULTS=$(echo "$NUCLEI_RAW" | jq -s '[.[] | {
      name: .info.name,
      severity: (.info.severity // "info"),
      matched: .matched_at
    }]' 2>/dev/null || echo "[]")
  fi
fi

# 4. Common path probing
PATHS_FOUND="[]"
for path in /robots.txt /sitemap.xml /.env /wp-login.php /api/ /swagger/ /graphql; do
  CODE=$(curl -so /dev/null -w '%{http_code}' --max-time 5 "${TARGET_URL}${path}" 2>/dev/null || echo "000")
  if [ "$CODE" != "000" ] && [ "$CODE" != "404" ]; then
    PATHS_FOUND=$(echo "$PATHS_FOUND" | jq --arg p "$path" --arg c "$CODE" '. + [{"path": $p, "status": ($c | tonumber)}]')
  fi
done

cat > "$OUTPUT_DIR/recon-result.json" << EOF
{
  "technique": "T1595",
  "phase": "recon",
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "target": "$TARGET_URL",
  "http_code": $HTTP_CODE,
  "server_header": $(echo "$SERVER_HEADER" | jq -Rs .),
  "tech_headers": $(echo "$TECH_HEADERS" | jq -Rs .),
  "nuclei_findings": $NUCLEI_RESULTS,
  "paths_found": $PATHS_FOUND,
  "summary": {
    "paths_discovered": $(echo "$PATHS_FOUND" | jq 'length'),
    "nuclei_findings": $(echo "$NUCLEI_RESULTS" | jq 'length')
  }
}
EOF
