#!/bin/bash
# scripts/monitor/monitor-scan.sh — Monitor Scan Orchestrator
# Usage: monitor-scan.sh <project_config_file_or_json> <output_dir>
#
# Reads project config → calls each adapter → heartbeat check →
# fallback to posture-check if timeout → aggregates monitor-result.json
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source shell config for path resolution
# shellcheck source=../lib/shell-config.sh
source "$PROJECT_ROOT/scripts/lib/shell-config.sh" 2>/dev/null || true

CONFIG_INPUT="$1"
OUTPUT_DIR="$2"

if [ -z "$CONFIG_INPUT" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: monitor-scan.sh <project_config_file_or_json> <output_dir>" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

# Read config — support both file path and inline JSON
if [ -f "$CONFIG_INPUT" ]; then
  PROJECT_CONFIG=$(cat "$CONFIG_INPUT")
else
  PROJECT_CONFIG="$CONFIG_INPUT"
fi

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
PROJECT_NAME=$(echo "$PROJECT_CONFIG" | jq -r '.name // "unknown"')

# Persistent state dir from config or default
PERSISTENT_BASE=$(cfg 'paths.projects' 'docs/projects' 2>/dev/null || echo "docs/projects")

# Check if monitor config exists
HAS_MONITOR=$(echo "$PROJECT_CONFIG" | jq -r '.monitor // empty')
if [ -z "$HAS_MONITOR" ]; then
  cat > "$OUTPUT_DIR/monitor-result.json" << EOF
{
  "status": "skipped",
  "reason": "No monitor configuration in project config",
  "timestamp": "$TIMESTAMP",
  "project": "$PROJECT_NAME",
  "summary": { "critical": 0, "high": 0, "medium": 0, "low": 0, "total": 0 },
  "adapter_results": [],
  "operational_readiness": "N/A"
}
EOF
  exit 0
fi

TIMEOUT_HOURS=$(echo "$PROJECT_CONFIG" | jq -r '.monitor.heartbeat_timeout_hours // 24')

# Heartbeat state is persistent per-project (survives across scans)
PERSISTENT_DIR="$PROJECT_ROOT/$PERSISTENT_BASE/$PROJECT_NAME"
PERSISTENT_HB="$PERSISTENT_DIR/heartbeat-state.json"
mkdir -p "$PERSISTENT_DIR"

# Read existing state or init fresh
if [ -f "$PERSISTENT_HB" ]; then
  cp "$PERSISTENT_HB" "$OUTPUT_DIR/heartbeat-state.json"
else
  "$SCRIPT_DIR/heartbeat.sh" init "$OUTPUT_DIR/heartbeat-state.json"
fi

# Process each adapter
echo "$PROJECT_CONFIG" | jq -c '.monitor.adapters[]? // empty' | while read -r adapter_config; do
  ADAPTER_TYPE=$(echo "$adapter_config" | jq -r '.type')
  ADAPTER_SCRIPT="$SCRIPT_DIR/adapters/${ADAPTER_TYPE}.sh"

  echo "  Running adapter: $ADAPTER_TYPE"

  if [ ! -x "$ADAPTER_SCRIPT" ]; then
    echo "  WARNING: Adapter script not found: $ADAPTER_SCRIPT" >&2
    "$SCRIPT_DIR/heartbeat.sh" fail "$OUTPUT_DIR/heartbeat-state.json" "$ADAPTER_TYPE"
    continue
  fi

  # Run adapter
  if "$ADAPTER_SCRIPT" "$adapter_config" "$OUTPUT_DIR" 2>/dev/null; then
    RESULT_FILE="$OUTPUT_DIR/${ADAPTER_TYPE}-result.json"
    if [ -f "$RESULT_FILE" ]; then
      LAST_EVENT=$(jq -r '.last_event_at // ""' "$RESULT_FILE" 2>/dev/null || true)
      if [ -n "$LAST_EVENT" ] && [ "$LAST_EVENT" != "null" ]; then
        "$SCRIPT_DIR/heartbeat.sh" update "$OUTPUT_DIR/heartbeat-state.json" "$ADAPTER_TYPE" "$LAST_EVENT"
      else
        "$SCRIPT_DIR/heartbeat.sh" update "$OUTPUT_DIR/heartbeat-state.json" "$ADAPTER_TYPE" "$TIMESTAMP"
      fi
    fi
  else
    echo "  Adapter $ADAPTER_TYPE failed" >&2
    "$SCRIPT_DIR/heartbeat.sh" fail "$OUTPUT_DIR/heartbeat-state.json" "$ADAPTER_TYPE"
  fi

  # Check heartbeat for this adapter
  HB_STATUS=$("$SCRIPT_DIR/heartbeat.sh" check "$OUTPUT_DIR/heartbeat-state.json" "$ADAPTER_TYPE" "$TIMEOUT_HOURS")
  if [ "$HB_STATUS" = "timeout" ] || [ "$HB_STATUS" = "unknown" ]; then
    echo "  Adapter $ADAPTER_TYPE: heartbeat $HB_STATUS — posture check needed"
    echo "true" > "$OUTPUT_DIR/.posture_needed"
  fi
done

# Posture check ALWAYS runs (governance checks are not conditional)
# Monitor-specific checks only run when adapters are in fallback
HAS_FALLBACK=false
[ -f "$OUTPUT_DIR/.posture_needed" ] && HAS_FALLBACK=true && rm -f "$OUTPUT_DIR/.posture_needed"
echo "  Running posture check (governance=always, monitor_fallback=$HAS_FALLBACK)..."
"$SCRIPT_DIR/posture-check.sh" "$PROJECT_CONFIG" "$OUTPUT_DIR" "$HAS_FALLBACK"

# Aggregate all adapter results + posture check
TOTAL_CRITICAL=0
TOTAL_HIGH=0
TOTAL_MEDIUM=0
TOTAL_LOW=0
ADAPTER_RESULTS="[]"

for result_file in "$OUTPUT_DIR"/*-result.json; do
  [ ! -f "$result_file" ] && continue
  [ "$(basename "$result_file")" = "monitor-result.json" ] && continue

  C=$(jq '.summary.critical // 0' "$result_file" 2>/dev/null || echo "0")
  H=$(jq '.summary.high // .summary.fail // 0' "$result_file" 2>/dev/null || echo "0")
  M=$(jq '.summary.medium // .summary.warn // 0' "$result_file" 2>/dev/null || echo "0")
  L=$(jq '.summary.low // 0' "$result_file" 2>/dev/null || echo "0")

  TOTAL_CRITICAL=$((TOTAL_CRITICAL + C))
  TOTAL_HIGH=$((TOTAL_HIGH + H))
  TOTAL_MEDIUM=$((TOTAL_MEDIUM + M))
  TOTAL_LOW=$((TOTAL_LOW + L))

  # Only include adapter results (not posture-check) in adapter_results array
  [ "$(basename "$result_file")" = "posture-check-result.json" ] && continue

  SOURCE=$(jq -r '.source // "unknown"' "$result_file" 2>/dev/null || echo "unknown")
  MODE=$(jq -r '.mode // "unknown"' "$result_file" 2>/dev/null || echo "unknown")
  STATUS=$(jq -r '.status // "unknown"' "$result_file" 2>/dev/null || echo "unknown")
  ADAPTER_RESULTS=$(echo "$ADAPTER_RESULTS" | jq --arg s "$SOURCE" --arg m "$MODE" --arg st "$STATUS" \
    --arg f "$(basename "$result_file")" \
    '. + [{"source": $s, "mode": $m, "status": $st, "result_file": $f}]')
done

TOTAL=$((TOTAL_CRITICAL + TOTAL_HIGH + TOTAL_MEDIUM + TOTAL_LOW))

# Determine operational readiness
ALIVE_COUNT=$(jq '[.adapters[] | select(.status == "alive")] | length' "$OUTPUT_DIR/heartbeat-state.json" 2>/dev/null || echo "0")
TOTAL_ADAPTERS=$(jq '.adapters | length' "$OUTPUT_DIR/heartbeat-state.json" 2>/dev/null || echo "0")

if [ "$TOTAL_ADAPTERS" -eq 0 ]; then
  OP_READINESS="N/A"
elif [ "$ALIVE_COUNT" -eq "$TOTAL_ADAPTERS" ]; then
  OP_READINESS="READY"
elif [ "$ALIVE_COUNT" -gt 0 ]; then
  OP_READINESS="PARTIAL"
else
  OP_READINESS="NOT READY"
fi

# Check posture check failures
POSTURE_FAIL=0
if [ -f "$OUTPUT_DIR/posture-check-result.json" ]; then
  POSTURE_FAIL=$(jq '.summary.fail // 0' "$OUTPUT_DIR/posture-check-result.json" 2>/dev/null || echo "0")
fi
if [ "$OP_READINESS" != "N/A" ] && [ "$POSTURE_FAIL" -gt 0 ] && [ "$ALIVE_COUNT" -eq 0 ]; then
  OP_READINESS="NOT READY"
fi

cat > "$OUTPUT_DIR/monitor-result.json" << EOF
{
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "project": "$PROJECT_NAME",
  "summary": {
    "critical": $TOTAL_CRITICAL,
    "high": $TOTAL_HIGH,
    "medium": $TOTAL_MEDIUM,
    "low": $TOTAL_LOW,
    "total": $TOTAL
  },
  "adapter_results": $ADAPTER_RESULTS,
  "operational_readiness": "$OP_READINESS",
  "heartbeat": {
    "alive": $ALIVE_COUNT,
    "total": $TOTAL_ADAPTERS
  }
}
EOF

# Write back heartbeat state to persistent location
cp "$OUTPUT_DIR/heartbeat-state.json" "$PERSISTENT_HB"

echo "  Monitor scan complete: C=$TOTAL_CRITICAL H=$TOTAL_HIGH M=$TOTAL_MEDIUM L=$TOTAL_LOW"
echo "  Operational Readiness: $OP_READINESS ($ALIVE_COUNT/$TOTAL_ADAPTERS adapters alive)"
