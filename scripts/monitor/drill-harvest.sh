#!/bin/bash
# scripts/monitor/drill-harvest.sh — Parse drill Issue into drill-result.json
# Usage:
#   drill-harvest.sh --issue <number>                          # live: fetch from GitHub
#   drill-harvest.sh --from-file <json> --output <path> --project <name>  # test: parse local file
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source shell config for path resolution
source "$PROJECT_ROOT/scripts/lib/shell-config.sh" 2>/dev/null || true

# Parse arguments
ISSUE_NUMBER=""
FROM_FILE=""
OUTPUT_FILE=""
PROJECT_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --issue) ISSUE_NUMBER="$2"; shift 2 ;;
    --from-file) FROM_FILE="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --project) PROJECT_NAME="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Fetch issue data
if [ -n "$FROM_FILE" ]; then
  ISSUE_DATA=$(cat "$FROM_FILE")
elif [ -n "$ISSUE_NUMBER" ]; then
  ISSUE_DATA=$(gh issue view "$ISSUE_NUMBER" --json number,title,closedAt,labels,body,comments)
else
  echo "Usage: drill-harvest.sh --issue <number> | --from-file <json> --output <path> --project <name>" >&2
  exit 1
fi

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TITLE=$(echo "$ISSUE_DATA" | jq -r '.title // ""')
CLOSED_AT=$(echo "$ISSUE_DATA" | jq -r '.closedAt // ""')
ISSUE_NUM=$(echo "$ISSUE_DATA" | jq -r '.number // 0')

# Extract drill type from title: [演練] <type> — <project> (<date>)
DRILL_TYPE=$(echo "$TITLE" | sed -n 's/.*\[演練\] \([^ ]*\) —.*/\1/p')
SCHEDULED_DATE=$(echo "$TITLE" | sed -n 's/.* (\([0-9-]*\)).*/\1/p')

# Parse step comments (skip bot confirmation comments)
STEPS=$(echo "$ISSUE_DATA" | jq -c '[
  .comments[]
  | select(.body | test("\\*\\*步驟\\*\\*:"))
  | {
      reporter: .author.login,
      reported_at: .createdAt,
      step_text: (.body | capture("\\*\\*步驟\\*\\*: (?<num>[^ ]+) — (?<title>.*)") // {num: "?", title: "?"}),
      result: (.body | capture("\\*\\*結果\\*\\*: (?<text>[^\\n]*)") | .text // ""),
      has_attachment: (.body | test("\\*\\*附件\\*\\*:.*[^ ]"))
    }
  | {
      step: .step_text.num,
      title: .step_text.title,
      reporter: .reporter,
      reported_at: .reported_at,
      result: .result,
      has_attachment: .has_attachment
    }
]')

STEP_COUNT=$(echo "$STEPS" | jq 'length')

# Calculate response times between consecutive steps
STEPS_WITH_TIMING=$(echo "$STEPS" | jq '
  [ range(length) as $i |
    .[$i] + (
      if $i > 0 then
        { "response_time_min":
          ((((.[$i].reported_at | fromdateiso8601) - (.[$i-1].reported_at | fromdateiso8601)) / 60) | floor)
        }
      else
        { "response_time_min": 0 }
      end
    )
  ]
')

# Determine status
STATUS="completed"
if [ "$STEP_COUNT" -eq 0 ]; then
  STATUS="incomplete"
fi

# Output path
if [ -z "$OUTPUT_FILE" ]; then
  OUTPUT_FILE="drill-result.json"
fi

cat > "$OUTPUT_FILE" << EOF
{
  "type": "${DRILL_TYPE:-unknown}",
  "project": "${PROJECT_NAME:-unknown}",
  "status": "$STATUS",
  "scheduled_date": "$SCHEDULED_DATE",
  "completed_date": "$CLOSED_AT",
  "harvest_timestamp": "$TIMESTAMP",
  "summary": {
    "total_steps": $STEP_COUNT,
    "completed": $STEP_COUNT
  },
  "steps": $STEPS_WITH_TIMING,
  "issue_number": $ISSUE_NUM
}
EOF

# Write back to projects config: update last_drill_date + next_drill_date
# Skip in --from-file mode (test/offline mode) to avoid polluting tracked config
PROJECTS_CONFIG_REL=$(cfg 'paths.projects_config' 'configs/projects.json' 2>/dev/null || echo "configs/projects.json")
PROJECTS_FILE="$PROJECT_ROOT/$PROJECTS_CONFIG_REL"

if [ -n "$FROM_FILE" ]; then
  # Test mode: skip projects config writeback
  :
elif [ -f "$PROJECTS_FILE" ] && [ -n "$PROJECT_NAME" ] && [ "$STATUS" = "completed" ]; then
  # Extract close date (YYYY-MM-DD)
  CLOSE_DATE=$(echo "$CLOSED_AT" | cut -dT -f1)
  [ -z "$CLOSE_DATE" ] && CLOSE_DATE=$(date -u '+%Y-%m-%d')

  # Calculate next_drill_date = close_date + frequency_months
  FREQ_MONTHS=$(jq -r --arg name "$PROJECT_NAME" \
    '.[] | select(.name == $name) | .monitor.drill.frequency_months // 6' "$PROJECTS_FILE" 2>/dev/null || echo "6")

  # Cross-platform date arithmetic
  if date -jf '%Y-%m-%d' "$CLOSE_DATE" '+%s' >/dev/null 2>&1; then
    NEXT_DATE=$(date -jf '%Y-%m-%d' -v+${FREQ_MONTHS}m "$CLOSE_DATE" '+%Y-%m-%d')
  else
    NEXT_DATE=$(date -d "$CLOSE_DATE + $FREQ_MONTHS months" '+%Y-%m-%d' 2>/dev/null || echo "$CLOSE_DATE")
  fi

  # Update projects config
  UPDATED=$(jq --arg name "$PROJECT_NAME" --arg last "$CLOSE_DATE" --arg next "$NEXT_DATE" \
    '[ .[] | if .name == $name then .monitor.drill.last_drill_date = $last | .monitor.drill.next_drill_date = $next else . end ]' \
    "$PROJECTS_FILE")
  echo "$UPDATED" > "$PROJECTS_FILE"

  echo "Updated $PROJECTS_CONFIG_REL: last_drill_date=$CLOSE_DATE, next_drill_date=$NEXT_DATE"
fi
