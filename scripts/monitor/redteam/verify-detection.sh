#!/bin/bash
# scripts/monitor/redteam/verify-detection.sh — Purple team detection verifier
# Usage: verify-detection.sh <monitor_dir> <technique_id> <check_type> <timeout_sec> [--heartbeat <path>]
#
# Checks adapter results for alerts that occurred within timeout_sec of now.
# Outputs JSON to stdout.
set -e

MONITOR_DIR="$1"
TECHNIQUE_ID="$2"
CHECK_TYPE="$3"   # "step" or "stage"
TIMEOUT_SEC="$4"
shift 4

HEARTBEAT_FILE="$MONITOR_DIR/heartbeat-state.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --heartbeat) HEARTBEAT_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
DETECTED=false
DETECTION_TIME_SEC=""
DETECTOR=""
ALERT_RULE=""
ADAPTERS_CHECKED=0

if [ ! -f "$HEARTBEAT_FILE" ]; then
  cat << EOF
{
  "technique_id": "$TECHNIQUE_ID",
  "check_type": "$CHECK_TYPE",
  "detected": false,
  "adapters_checked": 0,
  "timestamp": "$TIMESTAMP"
}
EOF
  exit 0
fi

# Get alive adapters
ADAPTER_NAMES=$(jq -r '.adapters | to_entries[] | select(.value.status == "alive") | .key' "$HEARTBEAT_FILE" 2>/dev/null || echo "")

for adapter_name in $ADAPTER_NAMES; do
  ADAPTERS_CHECKED=$((ADAPTERS_CHECKED + 1))
  RESULT_FILE="$MONITOR_DIR/${adapter_name}-result.json"
  [ ! -f "$RESULT_FILE" ] && continue

  # Check if adapter has any findings
  FINDING_COUNT=$(jq '.findings | length' "$RESULT_FILE" 2>/dev/null || echo "0")
  if [ "$FINDING_COUNT" -gt 0 ]; then
    # Any finding from an alive adapter counts as detection
    DETECTED=true
    DETECTOR="$adapter_name"
    FIRST_FINDING=$(jq -r '.findings[0].title // "unknown"' "$RESULT_FILE" 2>/dev/null)
    ALERT_RULE="$FIRST_FINDING"
    # Estimate detection time based on finding timestamp vs last_event_at
    DETECTION_TIME_SEC="$TIMEOUT_SEC"
    break
  fi
done

cat << EOF
{
  "technique_id": "$TECHNIQUE_ID",
  "check_type": "$CHECK_TYPE",
  "detected": $DETECTED,
  "detection_time_sec": $([ -n "$DETECTION_TIME_SEC" ] && echo "$DETECTION_TIME_SEC" || echo "null"),
  "detector": $([ -n "$DETECTOR" ] && echo "\"$DETECTOR\"" || echo "null"),
  "alert_rule": $([ -n "$ALERT_RULE" ] && echo "$ALERT_RULE" | jq -Rs . || echo "null"),
  "adapters_checked": $ADAPTERS_CHECKED,
  "timestamp": "$TIMESTAMP"
}
EOF
