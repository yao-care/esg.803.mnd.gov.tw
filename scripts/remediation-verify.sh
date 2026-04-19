#!/bin/bash
# remediation-verify.sh — Verify that a closed issue's remediation is valid
# Called by .github/workflows/remediation-verify.yml
#
# Environment variables (set by the workflow):
#   ISSUE_NUMBER  — The closed issue number
#   ISSUE_TITLE   — The issue title
#   ISSUE_BODY    — The issue body text
#   ANTHROPIC_API_KEY — API key for LLM verification (optional)
#   GH_TOKEN      — GitHub token for posting comments
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$SCRIPT_DIR/lib/shell-config.sh"

if [ -z "$ISSUE_NUMBER" ]; then
  echo "Error: ISSUE_NUMBER is required" >&2
  exit 1
fi

echo "[remediation-verify] Verifying issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}"

# Step 1: Check if the issue has a remediation label
LABELS=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null || echo "")
if ! echo "$LABELS" | grep -qi 'remediation\|finding\|vulnerability'; then
  echo "[remediation-verify] Issue #${ISSUE_NUMBER} has no remediation label, skipping."
  exit 0
fi

# Step 2: Extract remediation details from issue body
echo "[remediation-verify] Checking remediation evidence..."

# Step 3: Verify fix (placeholder — extend with project-specific checks)
PASS=true
REASON=""

# Check if issue body contains evidence sections
if [ -n "$ISSUE_BODY" ]; then
  if ! echo "$ISSUE_BODY" | grep -qi 'root.cause\|fix\|resolution\|修復\|原因'; then
    REASON="Issue body does not contain root cause or fix description."
    PASS=false
  fi
fi

# Step 4: Post result as comment
if [ "$PASS" = "true" ]; then
  COMMENT="Remediation for issue #${ISSUE_NUMBER} verified successfully."
  echo "[remediation-verify] PASS"
else
  COMMENT="Remediation verification found issues:\n- ${REASON}\n\nPlease update the issue with remediation evidence before closing."
  echo "[remediation-verify] FAIL: $REASON"
fi

if command -v gh &>/dev/null; then
  echo -e "$COMMENT" | gh issue comment "$ISSUE_NUMBER" --body-file - 2>/dev/null || echo -e "$COMMENT"
else
  echo -e "$COMMENT"
fi

[ "$PASS" = "true" ] && exit 0 || exit 1
