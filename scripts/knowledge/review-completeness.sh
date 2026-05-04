#!/bin/bash
# review-completeness.sh — Extract actionable gap list from audit-result.json
# Usage: ./scripts/knowledge/review-completeness.sh <audit-result.json> [output.json]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

AUDIT_JSON="${1:?Usage: review-completeness.sh <audit-result.json> [output.json]}"
OUTPUT="${2:-completeness-report.json}"

if [ ! -f "$AUDIT_JSON" ]; then
  echo "ERROR: $AUDIT_JSON not found" >&2
  exit 1
fi

jq '{
  status: "completed",
  timestamp: .timestamp,
  summary: {
    total_checks: [.checks[] | select(.id | startswith("RC-") or startswith("META-"))] | length,
    pass: [.checks[] | select((.id | startswith("RC-") or startswith("META-")) and .status == "pass")] | length,
    gaps: [.checks[] | select((.id | startswith("RC-") or startswith("META-")) and .status != "pass")] | length
  },
  action_items: [.checks[] | select((.id | startswith("RC-") or startswith("META-")) and .status != "pass") | {
    id: .id,
    name: .name,
    status: .status,
    detail: .detail,
    ref: .ref
  }]
}' "$AUDIT_JSON" > "$OUTPUT"

GAPS=$(jq '.summary.gaps' "$OUTPUT")
PASS=$(jq '.summary.pass' "$OUTPUT")
TOTAL=$(jq '.summary.total_checks' "$OUTPUT")
echo "Completeness: $PASS/$TOTAL pass, $GAPS gaps"
if [ "$GAPS" -eq 0 ]; then
  echo "Closed loop: COMPLETE"
else
  echo "Closed loop: INCOMPLETE — $GAPS items need AI completion"
fi
