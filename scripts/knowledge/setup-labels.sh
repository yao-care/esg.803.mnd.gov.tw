#!/bin/bash
# Create GitHub Issue labels for finding tracking
# Usage: setup-labels.sh
# Requires: gh CLI authenticated
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
if [ -z "$REPO" ]; then
  echo "ERROR: Not in a GitHub repo or gh not authenticated" >&2
  exit 1
fi

echo "Setting up labels for $REPO"

create_label() {
  local name="$1" color="$2" desc="$3"
  if gh label create "$name" --color "$color" --description "$desc" 2>/dev/null; then
    echo "  Created: $name"
  else
    gh label edit "$name" --color "$color" --description "$desc" 2>/dev/null && echo "  Updated: $name" || echo "  Exists: $name"
  fi
}

echo ""
echo "Severity labels:"
create_label "critical" "c93135" "Critical severity finding"
create_label "high" "b86a2a" "High severity finding"
create_label "medium" "8a7020" "Medium severity finding"
create_label "low" "5e6070" "Low severity finding"

echo ""
echo "Scanner labels:"
create_label "sast" "2a6bb8" "Static Application Security Testing"
create_label "vuln" "2a6bb8" "Vulnerability scan"
create_label "crypto" "2a6bb8" "Cryptography audit"
create_label "pentest" "7b50a0" "Penetration test"
create_label "ai-safety" "2a6bb8" "AI Safety check"
create_label "ai-supply" "2a6bb8" "AI Supply Chain check"

echo ""
echo "Status labels:"
create_label "security" "c93135" "Security finding — tracked by knowledge management"

echo ""
echo "Done. Labels configured for finding tracking."
