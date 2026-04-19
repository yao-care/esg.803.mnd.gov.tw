#!/bin/bash
# scripts/monitor/heartbeat.sh — Heartbeat Controller
# Usage:
#   heartbeat.sh init   <state_file>
#   heartbeat.sh update <state_file> <adapter_name> <timestamp>
#   heartbeat.sh fail   <state_file> <adapter_name>
#   heartbeat.sh check  <state_file> <adapter_name> <timeout_hours>
#
# Timeout default sourced from config.monitor.heartbeat_timeout_hours if available.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source shell config for timeout default (non-fatal)
source "$PROJECT_ROOT/scripts/lib/shell-config.sh" 2>/dev/null || true

ACTION="$1"
STATE_FILE="$2"

case "$ACTION" in
  init)
    cat > "$STATE_FILE" << 'EOF'
{"adapters":{}}
EOF
    ;;

  update)
    ADAPTER="$3"
    TIMESTAMP="$4"
    if [ ! -f "$STATE_FILE" ]; then
      echo '{"adapters":{}}' > "$STATE_FILE"
    fi
    UPDATED=$(jq --arg a "$ADAPTER" --arg ts "$TIMESTAMP" \
      '.adapters[$a] = {
        "last_success_at": $ts,
        "status": "alive",
        "consecutive_failures": 0
      }' "$STATE_FILE")
    echo "$UPDATED" > "$STATE_FILE"
    ;;

  fail)
    ADAPTER="$3"
    if [ ! -f "$STATE_FILE" ]; then
      echo "Error: state file not found: $STATE_FILE" >&2
      exit 1
    fi
    EXISTING=$(jq --arg a "$ADAPTER" '.adapters[$a] // null' "$STATE_FILE")
    if [ "$EXISTING" = "null" ]; then
      UPDATED=$(jq --arg a "$ADAPTER" \
        '.adapters[$a] = {
          "last_success_at": null,
          "status": "failing",
          "consecutive_failures": 1
        }' "$STATE_FILE")
    else
      UPDATED=$(jq --arg a "$ADAPTER" \
        '.adapters[$a].consecutive_failures = (.adapters[$a].consecutive_failures + 1) |
         .adapters[$a].status = "failing"' "$STATE_FILE")
    fi
    echo "$UPDATED" > "$STATE_FILE"
    ;;

  check)
    ADAPTER="$3"
    # Use provided timeout or fall back to config value, then to 24
    TIMEOUT_HOURS="${4:-$(cfg 'monitor.heartbeat_timeout_hours' '24' 2>/dev/null || echo '24')}"
    if [ ! -f "$STATE_FILE" ]; then
      echo "unknown"
      exit 0
    fi
    LAST_SUCCESS=$(jq -r --arg a "$ADAPTER" '.adapters[$a].last_success_at // "null"' "$STATE_FILE")
    if [ "$LAST_SUCCESS" = "null" ]; then
      echo "unknown"
      exit 0
    fi
    NOW_EPOCH=$(date -u '+%s')
    # macOS date -jf vs GNU date -d
    if date -jf '%Y-%m-%dT%H:%M:%SZ' "$LAST_SUCCESS" '+%s' >/dev/null 2>&1; then
      LAST_EPOCH=$(date -jf '%Y-%m-%dT%H:%M:%SZ' "$LAST_SUCCESS" '+%s')
    else
      LAST_EPOCH=$(date -d "$LAST_SUCCESS" '+%s' 2>/dev/null || echo "0")
    fi
    DIFF_HOURS=$(( (NOW_EPOCH - LAST_EPOCH) / 3600 ))
    if [ "$DIFF_HOURS" -ge "$TIMEOUT_HOURS" ]; then
      echo "timeout"
    else
      echo "alive"
    fi
    ;;

  *)
    echo "Usage: heartbeat.sh {init|update|fail|check} <args...>" >&2
    exit 1
    ;;
esac
