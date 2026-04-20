#!/bin/bash
# check-retention.sh — scan reported records for expired retention
# Outputs warnings for records past their retained_until date
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

REPORTED_DIR="$PROJECT_ROOT/$REPORTED_PATH"
TODAY=$(date '+%Y-%m-%d')
EXPIRED=0
EXPIRING_SOON=0
WARN_DAYS=30

if [ ! -d "$REPORTED_DIR" ]; then
  echo "[retention] No reported directory found: $REPORTED_DIR"
  exit 0
fi

echo "[retention] Scanning $REPORTED_DIR for expired records (today: $TODAY)..."

for f in "$REPORTED_DIR"/*.json; do
  [ ! -f "$f" ] && continue

  RETAINED_UNTIL=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get('retained_until', ''))
" "$f" 2>/dev/null || true)

  [ -z "$RETAINED_UNTIL" ] && continue

  RECORD_ID=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get('record_id', ''))
" "$f" 2>/dev/null || true)

  if [[ "$RETAINED_UNTIL" < "$TODAY" ]]; then
    echo "  EXPIRED: $RECORD_ID (retained_until: $RETAINED_UNTIL)"
    EXPIRED=$((EXPIRED + 1))
  elif python3 -c "
from datetime import datetime, timedelta
import sys
retained = datetime.strptime(sys.argv[1], '%Y-%m-%d')
today = datetime.strptime(sys.argv[2], '%Y-%m-%d')
sys.exit(0 if (retained - today).days <= int(sys.argv[3]) else 1)
" "$RETAINED_UNTIL" "$TODAY" "$WARN_DAYS" 2>/dev/null; then
    echo "  EXPIRING SOON: $RECORD_ID (retained_until: $RETAINED_UNTIL, ${WARN_DAYS}d warning)"
    EXPIRING_SOON=$((EXPIRING_SOON + 1))
  fi
done

echo ""
echo "[retention] Summary: $EXPIRED expired, $EXPIRING_SOON expiring within ${WARN_DAYS} days"

if [ "$EXPIRED" -gt 0 ]; then
  echo "[retention] Action required: review expired records and decide on archival or deletion"
  exit 1
fi
