#!/bin/bash
# Create notification record after sending email
# Usage: create-notification-record.sh <project-name> <scan-id> <recipients> <subject> <quality-gate> <attachments>
set -e

PROJECT_NAME="$1"
SCAN_ID="$2"
RECIPIENTS="$3"
SUBJECT="$4"
QUALITY_GATE="$5"
ATTACHMENTS="$6"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

NOTIF_DIR="$PROJECT_ROOT/$PROJECTS_PATH/$PROJECT_NAME/notifications"

mkdir -p "$NOTIF_DIR"

RECORD_FILE="$NOTIF_DIR/$(date '+%Y-%m-%d')-scan-report.json"

# Read finding summary from quality-gate.json if available
SCAN_DIR="$PROJECT_ROOT/$COLLECTED_PATH/$SCAN_ID"
CRITICAL=0; HIGH=0; MEDIUM=0
if [ -f "$SCAN_DIR/quality-gate.json" ]; then
  CRITICAL=$(jq '.critical // 0' "$SCAN_DIR/quality-gate.json")
  HIGH=$(jq '.high // 0' "$SCAN_DIR/quality-gate.json")
fi

cat > "$RECORD_FILE" << EOF
{
  "type": "scan_report",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "scan_id": "$SCAN_ID",
  "project": "$PROJECT_NAME",
  "recipients": $(echo "$RECIPIENTS" | jq -R 'split(",")'),
  "subject": "$SUBJECT",
  "quality_gate": "$QUALITY_GATE",
  "findings_summary": {
    "critical": $CRITICAL,
    "high": $HIGH
  },
  "attachments": $(echo "$ATTACHMENTS" | jq -R 'split(",")' 2>/dev/null || echo "[]")
}
EOF

echo "Notification record: $RECORD_FILE"
