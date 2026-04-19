#!/bin/bash
# scripts/monitor/posture-check.sh — Governance + monitoring posture audit
# Usage: posture-check.sh <project_config_json> <output_dir> [has_fallback]
#
# Governance checks ALWAYS run (IR plan, drill, backup, contacts).
# Monitoring checks only run when has_fallback=true (EDR, log, SIEM rules).
# Output: <output_dir>/posture-check-result.json
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source shell config for path resolution
source "$PROJECT_ROOT/scripts/lib/shell-config.sh" 2>/dev/null || true

PROJECT_CONFIG="$1"
OUTPUT_DIR="$2"
HAS_FALLBACK="${3:-false}"

if [ -z "$PROJECT_CONFIG" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: posture-check.sh <project_config_json> <output_dir> [has_fallback]" >&2
  exit 1
fi
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
CHECKS="[]"
PASS=0
FAIL=0
WARN=0

# Helper: add a check result
add_check() {
  local name="$1" status="$2" detail="$3" control="$4"
  CHECKS=$(echo "$CHECKS" | jq --arg n "$name" --arg s "$status" --arg d "$detail" --arg c "$control" \
    '. + [{"name": $n, "status": $s, "detail": $d, "control": $c}]')
  case "$status" in
    pass) PASS=$((PASS + 1)) ;;
    fail) FAIL=$((FAIL + 1)) ;;
    warn) WARN=$((WARN + 1)) ;;
  esac
}

NOW_EPOCH=$(date -u '+%s')

# CHECK 1: IR Plan existence (A.5.24 / CIS 17)
DRILL_CONFIG=$(echo "$PROJECT_CONFIG" | jq -r '.monitor.drill // empty' 2>/dev/null)
if [ -n "$DRILL_CONFIG" ]; then
  LAST_DRILL=$(echo "$DRILL_CONFIG" | jq -r '.last_drill_date // "none"')
  if [ "$LAST_DRILL" = "none" ] || [ "$LAST_DRILL" = "null" ]; then
    add_check "IR Plan & Drill" "fail" "No drill record found" "A.5.24"
  else
    if date -jf '%Y-%m-%d' "$LAST_DRILL" '+%s' >/dev/null 2>&1; then
      DRILL_EPOCH=$(date -jf '%Y-%m-%d' "$LAST_DRILL" '+%s')
    else
      DRILL_EPOCH=$(date -d "$LAST_DRILL" '+%s' 2>/dev/null || echo "0")
    fi
    MONTHS_AGO=$(( (NOW_EPOCH - DRILL_EPOCH) / 86400 / 30 ))
    if [ "$MONTHS_AGO" -gt 12 ]; then
      add_check "IR Plan & Drill" "fail" "Last drill was ${MONTHS_AGO} months ago (>12 months)" "A.5.24"
    elif [ "$MONTHS_AGO" -gt 9 ]; then
      add_check "IR Plan & Drill" "warn" "Last drill was ${MONTHS_AGO} months ago (approaching 12-month limit)" "A.5.24"
    else
      add_check "IR Plan & Drill" "pass" "Last drill: $LAST_DRILL (${MONTHS_AGO} months ago)" "A.5.24"
    fi
  fi
else
  add_check "IR Plan & Drill" "fail" "No drill configuration found in project config" "A.5.24"
fi

# CHECK 2: Monitoring tool presence (A.8.16 / CIS 10, 13)
ADAPTERS=$(echo "$PROJECT_CONFIG" | jq -r '.monitor.adapters // []' 2>/dev/null)
ADAPTER_COUNT=$(echo "$ADAPTERS" | jq 'length')
if [ "$ADAPTER_COUNT" -eq 0 ]; then
  add_check "Monitoring Tools" "fail" "No monitor adapters configured" "A.8.16"
else
  add_check "Monitoring Tools" "pass" "${ADAPTER_COUNT} adapter(s) configured" "A.8.16"
fi

# CHECK 3: Heartbeat state — how many adapters are alive vs timeout
HEARTBEAT_FILE="$OUTPUT_DIR/heartbeat-state.json"
if [ -f "$HEARTBEAT_FILE" ]; then
  ALIVE_COUNT=$(jq '[.adapters[] | select(.status == "alive")] | length' "$HEARTBEAT_FILE" 2>/dev/null || echo "0")
  TIMEOUT_COUNT=$(jq '[.adapters[] | select(.status != "alive")] | length' "$HEARTBEAT_FILE" 2>/dev/null || echo "0")
  if [ "$TIMEOUT_COUNT" -gt 0 ] && [ "$ALIVE_COUNT" -eq 0 ]; then
    add_check "Monitoring Liveness" "fail" "All adapters in timeout (${TIMEOUT_COUNT} timeout, ${ALIVE_COUNT} alive)" "A.8.16"
  elif [ "$TIMEOUT_COUNT" -gt 0 ]; then
    add_check "Monitoring Liveness" "warn" "${TIMEOUT_COUNT} adapter(s) in timeout, ${ALIVE_COUNT} alive" "A.8.16"
  else
    add_check "Monitoring Liveness" "pass" "All ${ALIVE_COUNT} adapter(s) alive" "A.8.16"
  fi
else
  add_check "Monitoring Liveness" "warn" "No heartbeat state file — first run?" "A.8.16"
fi

# CHECK 4: Drill contacts defined (A.5.26)
CONTACTS=$(echo "$PROJECT_CONFIG" | jq -r '.monitor.drill.contacts // []' 2>/dev/null)
CONTACT_COUNT=$(echo "$CONTACTS" | jq 'length')
if [ "$CONTACT_COUNT" -eq 0 ]; then
  add_check "IR Contacts" "fail" "No drill contacts defined" "A.5.26"
else
  HAS_ISO=$(echo "$CONTACTS" | jq '[.[] | select(.role == "ISO")] | length')
  if [ "$HAS_ISO" -eq 0 ]; then
    add_check "IR Contacts" "warn" "${CONTACT_COUNT} contact(s) but no ISO role defined" "A.5.26"
  else
    add_check "IR Contacts" "pass" "${CONTACT_COUNT} contact(s) with ISO role" "A.5.26"
  fi
fi

# CHECK 5: Backup status (A.5.29)
BACKUP_CONFIG=$(echo "$PROJECT_CONFIG" | jq -r '.monitor.backup // empty' 2>/dev/null)
if [ -n "$BACKUP_CONFIG" ]; then
  LAST_RESTORE=$(echo "$BACKUP_CONFIG" | jq -r '.last_restore_test // "none"')
  if [ "$LAST_RESTORE" = "none" ] || [ "$LAST_RESTORE" = "null" ]; then
    add_check "Backup Restore Test" "fail" "No restore test record found" "A.5.29"
  else
    if date -jf '%Y-%m-%d' "$LAST_RESTORE" '+%s' >/dev/null 2>&1; then
      RESTORE_EPOCH=$(date -jf '%Y-%m-%d' "$LAST_RESTORE" '+%s')
    else
      RESTORE_EPOCH=$(date -d "$LAST_RESTORE" '+%s' 2>/dev/null || echo "0")
    fi
    RESTORE_MONTHS=$(( (NOW_EPOCH - RESTORE_EPOCH) / 86400 / 30 ))
    if [ "$RESTORE_MONTHS" -gt 12 ]; then
      add_check "Backup Restore Test" "fail" "Last restore test was ${RESTORE_MONTHS} months ago (>12 months)" "A.5.29"
    else
      add_check "Backup Restore Test" "pass" "Last restore test: $LAST_RESTORE (${RESTORE_MONTHS} months ago)" "A.5.29"
    fi
  fi
else
  add_check "Backup Restore Test" "fail" "No backup configuration found" "A.5.29"
fi

# CHECK 6: DR Plan — RTO/RPO defined (A.5.30)
if [ -n "$BACKUP_CONFIG" ]; then
  RTO=$(echo "$BACKUP_CONFIG" | jq -r '.rto_hours // "null"')
  RPO=$(echo "$BACKUP_CONFIG" | jq -r '.rpo_hours // "null"')
  if [ "$RTO" != "null" ] && [ "$RPO" != "null" ]; then
    add_check "DR Plan (RTO/RPO)" "pass" "RTO=${RTO}h, RPO=${RPO}h defined" "A.5.30"
  else
    add_check "DR Plan (RTO/RPO)" "warn" "RTO or RPO not fully defined" "A.5.30"
  fi
else
  add_check "DR Plan (RTO/RPO)" "fail" "No backup/DR configuration found" "A.5.30"
fi

# === Monitoring checks (only when adapters are in fallback) ===
if [ "$HAS_FALLBACK" = "true" ]; then
  # CHECK M1: EDR deployment (A.8.16 / CIS 10)
  add_check "EDR Deployment" "warn" "Adapter(s) in fallback — manual verification needed" "A.8.16"

  # CHECK M2: Log collection (A.8.15 / CIS 8)
  add_check "Log Collection" "warn" "Adapter(s) in fallback — log pipeline may be interrupted" "A.8.15"
fi

# Determine overall severity for quality gate
TOTAL=$((PASS + FAIL + WARN))
CRITICAL_COUNT=0
HIGH_COUNT=$FAIL

cat > "$OUTPUT_DIR/posture-check-result.json" << EOF
{
  "source": "posture-check",
  "mode": "fallback",
  "status": "completed",
  "timestamp": "$TIMESTAMP",
  "summary": {
    "pass": $PASS,
    "fail": $FAIL,
    "warn": $WARN,
    "total": $TOTAL,
    "critical": $CRITICAL_COUNT,
    "high": $HIGH_COUNT
  },
  "checks": $CHECKS
}
EOF
