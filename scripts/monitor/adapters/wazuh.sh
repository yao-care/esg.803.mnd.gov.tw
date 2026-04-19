#!/bin/bash
# scripts/monitor/adapters/wazuh.sh — Wazuh SIEM adapter
# Usage: wazuh.sh <config_json> <output_dir>
#
# Config: { "type": "wazuh", "api_url": "https://wazuh:55000", "credentials_env": "WAZUH_TOKEN" }
set -e

CONFIG_JSON="$1"
OUTPUT_DIR="$2"

if [ -z "$CONFIG_JSON" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: wazuh.sh <config_json> <output_dir>" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

API_URL=$(echo "$CONFIG_JSON" | jq -r '.api_url // ""')
CRED_ENV=$(echo "$CONFIG_JSON" | jq -r '.credentials_env // ""')
LOOKBACK_HOURS=$(echo "$CONFIG_JSON" | jq -r '.lookback_hours // 24')
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if [ -z "$API_URL" ]; then
  cat > "$OUTPUT_DIR/wazuh-result.json" << EOF
{"source":"wazuh","mode":"continuous","status":"error","error":"No api_url configured","timestamp":"$TIMESTAMP","last_event_at":null,"summary":{"critical":0,"high":0,"medium":0,"low":0,"total":0},"findings":[]}
EOF
  exit 1
fi

# Get token
TOKEN=""
if [ -n "$CRED_ENV" ]; then
  TOKEN="${!CRED_ENV}"
fi

if [ -z "$TOKEN" ]; then
  cat > "$OUTPUT_DIR/wazuh-result.json" << EOF
{"source":"wazuh","mode":"continuous","status":"error","error":"Credentials env var $CRED_ENV is empty","timestamp":"$TIMESTAMP","last_event_at":null,"summary":{"critical":0,"high":0,"medium":0,"low":0,"total":0},"findings":[]}
EOF
  exit 1
fi

# Query Wazuh alerts API
ALERTS=$(curl -sk -H "Authorization: Bearer $TOKEN" \
  "${API_URL}/alerts?limit=500&sort=-timestamp&q=timestamp>${LOOKBACK_HOURS}h" 2>/dev/null || echo "")

if [ -z "$ALERTS" ] || ! echo "$ALERTS" | jq -e '.data' >/dev/null 2>&1; then
  cat > "$OUTPUT_DIR/wazuh-result.json" << EOF
{"source":"wazuh","mode":"continuous","status":"error","error":"Failed to query Wazuh API at $API_URL","timestamp":"$TIMESTAMP","last_event_at":null,"summary":{"critical":0,"high":0,"medium":0,"low":0,"total":0},"findings":[]}
EOF
  exit 1
fi

TOTAL=$(echo "$ALERTS" | jq '.data.total_affected_items // 0')
CRITICAL=$(echo "$ALERTS" | jq '[.data.affected_items[]? | select(.rule.level >= 12)] | length')
HIGH=$(echo "$ALERTS" | jq '[.data.affected_items[]? | select(.rule.level >= 8 and .rule.level < 12)] | length')
MEDIUM=$(echo "$ALERTS" | jq '[.data.affected_items[]? | select(.rule.level >= 4 and .rule.level < 8)] | length')
LOW=$(echo "$ALERTS" | jq '[.data.affected_items[]? | select(.rule.level < 4)] | length')

LAST_EVENT=$(echo "$ALERTS" | jq -r '.data.affected_items[0]?.timestamp // ""' 2>/dev/null)

FINDINGS=$(echo "$ALERTS" | jq '[.data.affected_items[:20]? // [] | .[] | {
  severity: (if .rule.level >= 12 then "critical" elif .rule.level >= 8 then "high" elif .rule.level >= 4 then "medium" else "low" end),
  title: .rule.description,
  description: (.full_log // .rule.description),
  first_seen: .timestamp,
  resource: (.agent.name // "unknown")
}]' 2>/dev/null || echo "[]")

cat > "$OUTPUT_DIR/wazuh-result.json" << EOF
{
  "source": "wazuh",
  "mode": "continuous",
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "last_event_at": $([ -n "$LAST_EVENT" ] && echo "\"$LAST_EVENT\"" || echo "\"$TIMESTAMP\""),
  "api_url": "$API_URL",
  "summary": {
    "critical": $CRITICAL,
    "high": $HIGH,
    "medium": $MEDIUM,
    "low": $LOW,
    "total": $TOTAL
  },
  "findings": $FINDINGS
}
EOF
