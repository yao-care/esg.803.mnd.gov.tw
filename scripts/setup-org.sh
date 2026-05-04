#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export PROJECT_ROOT

source "$SCRIPT_DIR/lib/shell-config.sh"

if command -v gh &>/dev/null; then
  LABELS_SCRIPT="$SCRIPT_DIR/knowledge/setup-labels.sh"
  if [ -f "$LABELS_SCRIPT" ]; then
    echo "Setting up GitHub labels..."
    "$LABELS_SCRIPT"
  else
    echo "Warning: $LABELS_SCRIPT not found, skipping label setup." >&2
  fi
else
  echo "gh CLI not found — skipping GitHub org setup."
fi
