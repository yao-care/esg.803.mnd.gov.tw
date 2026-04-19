#!/bin/bash
# scripts/monitor/redteam/redteam-run.sh — Purple Team Orchestrator
# Usage: redteam-run.sh <project_config_json> <output_dir>
#
# Reads playbook JSON → executes attack scripts per technique →
# verifies detection at step + stage level → outputs redteam-result.json
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$MONITOR_DIR/../.." && pwd)}"

# Source shell config for path resolution
source "$PROJECT_ROOT/scripts/lib/shell-config.sh" 2>/dev/null || true

CONFIG_INPUT="$1"
OUTPUT_DIR="$2"

if [ -z "$CONFIG_INPUT" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: redteam-run.sh <project_config_json> <output_dir>" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

# Read config
if [ -f "$CONFIG_INPUT" ]; then
  PROJECT_CONFIG=$(cat "$CONFIG_INPUT")
else
  PROJECT_CONFIG="$CONFIG_INPUT"
fi

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
PROJECT_NAME=$(echo "$PROJECT_CONFIG" | jq -r '.name // "unknown"')

# Check if redteam is enabled
REDTEAM_CONFIG=$(echo "$PROJECT_CONFIG" | jq -r '.monitor.redteam // empty' 2>/dev/null)
if [ -z "$REDTEAM_CONFIG" ]; then
  cat > "$OUTPUT_DIR/redteam-result.json" << EOF
{
  "source": "redteam",
  "status": "skipped",
  "reason": "No redteam configuration",
  "timestamp": "$TIMESTAMP",
  "summary": {"total_techniques": 0, "detected": 0, "undetected": 0, "detection_coverage_pct": 0, "critical": 0, "high": 0}
}
EOF
  exit 0
fi

ENABLED=$(echo "$REDTEAM_CONFIG" | jq -r '.enabled // false')
if [ "$ENABLED" != "true" ]; then
  cat > "$OUTPUT_DIR/redteam-result.json" << EOF
{
  "source": "redteam",
  "status": "skipped",
  "reason": "Redteam disabled",
  "timestamp": "$TIMESTAMP",
  "summary": {"total_techniques": 0, "detected": 0, "undetected": 0, "detection_coverage_pct": 0, "critical": 0, "high": 0}
}
EOF
  exit 0
fi

TARGET_URL=$(echo "$REDTEAM_CONFIG" | jq -r '.target_url // ""')
LLM_ENDPOINT_RT=$(echo "$REDTEAM_CONFIG" | jq -r '.llm_endpoint // ""')
PLAYBOOK_NAMES=$(echo "$REDTEAM_CONFIG" | jq -r '.playbooks[]? // empty')

[ -z "$TARGET_URL" ] && TARGET_URL=$(echo "$PROJECT_CONFIG" | jq -r '.web_url // ""')
[ -n "$LLM_ENDPOINT_RT" ] && export LLM_ENDPOINT="$LLM_ENDPOINT_RT"

# Heartbeat state for detection verification
PERSISTENT_BASE=$(cfg 'paths.projects' 'docs/projects' 2>/dev/null || echo "docs/projects")
PERSISTENT_HB="$PROJECT_ROOT/$PERSISTENT_BASE/$PROJECT_NAME/heartbeat-state.json"
MONITOR_OUTPUT="$OUTPUT_DIR/monitor"
mkdir -p "$MONITOR_OUTPUT"
[ -f "$PERSISTENT_HB" ] && cp "$PERSISTENT_HB" "$MONITOR_OUTPUT/heartbeat-state.json"

TOTAL_TECHNIQUES=0
TOTAL_DETECTED=0
STAGES="[]"
UNDETECTED="[]"
START_TIME=$(date -u '+%s')

for playbook_name in $PLAYBOOK_NAMES; do
  PLAYBOOK_FILE="$SCRIPT_DIR/playbooks/${playbook_name}.json"
  if [ ! -f "$PLAYBOOK_FILE" ]; then
    echo "WARNING: Playbook not found: $PLAYBOOK_FILE" >&2
    continue
  fi

  echo "Running playbook: $playbook_name"
  PLAYBOOK=$(cat "$PLAYBOOK_FILE")

  # Process each tactic (stage)
  echo "$PLAYBOOK" | jq -c '.mitre_tactics[]' | while read -r tactic; do
    TACTIC_ID=$(echo "$tactic" | jq -r '.id')
    TACTIC_NAME=$(echo "$tactic" | jq -r '.name')
    STAGE_TIMEOUT=$(echo "$tactic" | jq -r '.detect_timeout_sec // 60')
    STAGE_DIR="$OUTPUT_DIR/stages/${TACTIC_ID}"
    mkdir -p "$STAGE_DIR"

    echo "  Stage: $TACTIC_NAME ($TACTIC_ID)"

    STAGE_TECHNIQUES="[]"

    # Process each technique
    echo "$tactic" | jq -c '.techniques[]' | while read -r technique; do
      TECH_ID=$(echo "$technique" | jq -r '.id')
      TECH_NAME=$(echo "$technique" | jq -r '.name')
      ATTACK_SCRIPT=$(echo "$technique" | jq -r '.attack_script')
      ATTACK_ARGS=$(echo "$technique" | jq -r '.args // ""')
      STEP_TIMEOUT=$(echo "$technique" | jq -r '.detect_timeout_sec // 5')

      echo "    Technique: $TECH_NAME ($TECH_ID)"

      # Execute attack script
      ATTACK_PATH="$SCRIPT_DIR/attacks/$ATTACK_SCRIPT"
      TECH_DIR="$STAGE_DIR/$TECH_ID"
      mkdir -p "$TECH_DIR"

      if [ -x "$ATTACK_PATH" ]; then
        "$ATTACK_PATH" "$TARGET_URL" "$TECH_DIR" $ATTACK_ARGS 2>/dev/null || true
      else
        echo "    WARNING: Attack script not found: $ATTACK_PATH" >&2
      fi

      # Step-level detection check
      sleep "$STEP_TIMEOUT"

      # Run monitor adapters to refresh data for detection check
      if [ -f "$MONITOR_DIR/monitor-scan.sh" ] && [ -f "$PERSISTENT_HB" ]; then
        "$MONITOR_DIR/monitor-scan.sh" "$PROJECT_CONFIG" "$MONITOR_OUTPUT" 2>/dev/null || true
      fi

      STEP_DETECTION=$("$SCRIPT_DIR/verify-detection.sh" "$MONITOR_OUTPUT" "$TECH_ID" "step" "$STEP_TIMEOUT" 2>/dev/null || echo '{"detected":false,"adapters_checked":0}')
      STEP_DETECTED=$(echo "$STEP_DETECTION" | jq -r '.detected')
      echo "    Step detection: $STEP_DETECTED"

      # Write technique result
      cat > "$TECH_DIR/technique-result.json" << TECHEOF
{
  "id": "$TECH_ID",
  "name": "$TECH_NAME",
  "attack_script": "$ATTACK_SCRIPT",
  "step_detection": $STEP_DETECTION
}
TECHEOF
    done

    # Stage-level detection check
    echo "    Waiting ${STAGE_TIMEOUT}s for stage-level correlation..."
    sleep "$STAGE_TIMEOUT"

    if [ -f "$MONITOR_DIR/monitor-scan.sh" ] && [ -f "$PERSISTENT_HB" ]; then
      "$MONITOR_DIR/monitor-scan.sh" "$PROJECT_CONFIG" "$MONITOR_OUTPUT" 2>/dev/null || true
    fi

    STAGE_DETECTION=$("$SCRIPT_DIR/verify-detection.sh" "$MONITOR_OUTPUT" "$TACTIC_ID" "stage" "$STAGE_TIMEOUT" 2>/dev/null || echo '{"detected":false}')

    # Write stage result
    cat > "$STAGE_DIR/stage-result.json" << STGEOF
{
  "tactic_id": "$TACTIC_ID",
  "tactic_name": "$TACTIC_NAME",
  "stage_detection": $STAGE_DETECTION
}
STGEOF
  done
done

END_TIME=$(date -u '+%s')
DURATION=$((END_TIME - START_TIME))

# Aggregate all technique results
for tech_result in "$OUTPUT_DIR"/stages/*/*/technique-result.json; do
  [ ! -f "$tech_result" ] && continue
  TOTAL_TECHNIQUES=$((TOTAL_TECHNIQUES + 1))
  DETECTED=$(jq -r '.step_detection.detected' "$tech_result" 2>/dev/null || echo "false")
  if [ "$DETECTED" = "true" ]; then
    TOTAL_DETECTED=$((TOTAL_DETECTED + 1))
  else
    TECH_ID=$(jq -r '.id' "$tech_result")
    TECH_NAME=$(jq -r '.name' "$tech_result")
    UNDETECTED=$(echo "$UNDETECTED" | jq --arg id "$TECH_ID" --arg name "$TECH_NAME" \
      '. + [{"id": $id, "name": $name, "severity": "critical"}]')
  fi
done

# Aggregate stages
for stage_result in "$OUTPUT_DIR"/stages/*/stage-result.json; do
  [ ! -f "$stage_result" ] && continue
  STAGE_DATA=$(cat "$stage_result")
  STAGE_TECHS="[]"
  STAGE_ID=$(echo "$STAGE_DATA" | jq -r '.tactic_id')
  for tr in "$OUTPUT_DIR/stages/$STAGE_ID"/*/technique-result.json; do
    [ ! -f "$tr" ] && continue
    STAGE_TECHS=$(echo "$STAGE_TECHS" | jq --slurpfile t "$tr" '. + $t')
  done
  STAGES=$(echo "$STAGES" | jq --argjson sd "$STAGE_DATA" --argjson st "$STAGE_TECHS" \
    '. + [$sd + {"techniques": $st}]')
done

# Calculate coverage
if [ "$TOTAL_TECHNIQUES" -gt 0 ]; then
  COVERAGE_PCT=$(( TOTAL_DETECTED * 100 / TOTAL_TECHNIQUES ))
else
  COVERAGE_PCT=0
fi
UNDETECTED_COUNT=$(echo "$UNDETECTED" | jq 'length')

cat > "$OUTPUT_DIR/redteam-result.json" << EOF
{
  "source": "redteam",
  "mode": "purple-team",
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "project": "$PROJECT_NAME",
  "target_url": "$TARGET_URL",
  "duration_sec": $DURATION,
  "summary": {
    "total_techniques": $TOTAL_TECHNIQUES,
    "detected": $TOTAL_DETECTED,
    "undetected": $UNDETECTED_COUNT,
    "detection_coverage_pct": $COVERAGE_PCT,
    "critical": $UNDETECTED_COUNT,
    "high": 0
  },
  "stages": $STAGES,
  "undetected_techniques": $UNDETECTED
}
EOF

echo "Red team complete: $TOTAL_DETECTED/$TOTAL_TECHNIQUES detected ($COVERAGE_PCT% coverage)"
echo "Duration: ${DURATION}s"
