#!/bin/bash
# run-all.sh — Iterate over exercise playbook scripts and run them
# Usage: run-all.sh
#
# Discovers all *.sh scripts in the exercises/ directory (excluding this file)
# and executes each one sequentially.
#
# Environment variables:
#   EXERCISE_TARGET — Optional target filter passed to each playbook
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
source "$PROJECT_ROOT/scripts/lib/shell-config.sh"

echo "[exercises] Starting exercise run at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"

TOTAL=0
PASSED=0
FAILED=0

for script in "$SCRIPT_DIR"/*.sh; do
  [ ! -f "$script" ] && continue
  [ "$(basename "$script")" = "run-all.sh" ] && continue

  TOTAL=$((TOTAL + 1))
  PLAYBOOK=$(basename "$script" .sh)
  echo ""
  echo "[exercises] Running playbook: $PLAYBOOK"
  echo "───────────────────────────────────────"

  if bash "$script"; then
    echo "[exercises] $PLAYBOOK: PASS"
    PASSED=$((PASSED + 1))
  else
    echo "[exercises] $PLAYBOOK: FAIL (exit $?)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "[exercises] Summary: $TOTAL total, $PASSED passed, $FAILED failed"

if [ "$TOTAL" -eq 0 ]; then
  echo "[exercises] No playbook scripts found in $SCRIPT_DIR"
fi

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
