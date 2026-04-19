#!/bin/bash
# scripts/monitor/adapters/syslog-file.sh — Read local syslog/log file
# Usage: syslog-file.sh <config_json> <output_dir>
#
# Config JSON must contain:
#   { "type": "syslog-file", "log_path": "/var/log/syslog", "lookback_hours": 24 }
#
# Output: <output_dir>/syslog-file-result.json
set -e

CONFIG_JSON="$1"
OUTPUT_DIR="$2"

if [ -z "$CONFIG_JSON" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: syslog-file.sh <config_json> <output_dir>" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

LOG_PATH=$(echo "$CONFIG_JSON" | jq -r '.log_path // ""')
LOOKBACK_HOURS=$(echo "$CONFIG_JSON" | jq -r '.lookback_hours // 24')

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Check if log file exists
if [ -z "$LOG_PATH" ] || [ ! -f "$LOG_PATH" ]; then
  cat > "$OUTPUT_DIR/syslog-file-result.json" << EOF
{
  "source": "syslog-file",
  "mode": "continuous",
  "status": "error",
  "error": "Log file not found: $LOG_PATH",
  "timestamp": "$TIMESTAMP",
  "last_event_at": null,
  "summary": { "critical": 0, "high": 0, "medium": 0, "low": 0, "total": 0 },
  "findings": []
}
EOF
  exit 1
fi

# Get last modification time of log file
if stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$LOG_PATH" >/dev/null 2>&1; then
  LAST_MOD=$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$LOG_PATH")
else
  LAST_MOD=$(stat -c '%y' "$LOG_PATH" 2>/dev/null | sed 's/ /T/;s/\..*/Z/' || echo "$TIMESTAMP")
fi

# Count recent log entries and scan for severity keywords
TOTAL_LINES=$(wc -l < "$LOG_PATH" | tr -d ' ')
CRITICAL=$(grep -i -E 'critical|emergency|fatal' "$LOG_PATH" 2>/dev/null | wc -l | tr -d ' ')
HIGH=$(grep -i -E 'error|alert' "$LOG_PATH" 2>/dev/null | wc -l | tr -d ' ')
MEDIUM=$(grep -i -E 'warning|warn' "$LOG_PATH" 2>/dev/null | wc -l | tr -d ' ')
LOW=$(grep -i -E 'notice|info' "$LOG_PATH" 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW))

# Extract recent critical/high findings (last 20)
FINDINGS="[]"
if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
  FINDINGS=$(grep -i -E 'critical|emergency|fatal|error|alert' "$LOG_PATH" 2>/dev/null \
    | tail -20 \
    | jq -R -s 'split("\n") | map(select(length > 0)) | map({
        "severity": (if test("(?i)critical|emergency|fatal") then "critical" else "high" end),
        "title": (. | .[0:120]),
        "description": .,
        "first_seen": null,
        "resource": "syslog"
      })' 2>/dev/null || echo "[]")
fi

cat > "$OUTPUT_DIR/syslog-file-result.json" << EOF
{
  "source": "syslog-file",
  "mode": "continuous",
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "last_event_at": "$LAST_MOD",
  "log_path": "$LOG_PATH",
  "total_lines": $TOTAL_LINES,
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
