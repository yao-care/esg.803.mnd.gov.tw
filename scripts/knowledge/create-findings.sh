#!/bin/bash
# Create finding records from scan results
# Usage: create-findings.sh <scan-dir> <project-name>
# Output: docs/projects/<project-name>/findings/<finding-id>.json
set -e

SCAN_DIR="$1"
PROJECT_NAME="$2"

if [ -z "$SCAN_DIR" ] || [ -z "$PROJECT_NAME" ]; then
  echo "Usage: create-findings.sh <scan-dir> <project-name>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

FINDINGS_DIR="$PROJECT_ROOT/docs/projects/$PROJECT_NAME/findings"
SCAN_ID=$(basename "$SCAN_DIR")
YEAR_MONTH=$(echo "$SCAN_ID" | cut -c1-6 | sed 's/\(....\)\(..\)/\1-\2/')
CREATED=0

mkdir -p "$FINDINGS_DIR"

# Helper: create a finding JSON
create_finding() {
  local scanner="$1" severity="$2" description="$3" detail="$4"

  # Generate sequence number
  local prefix="${YEAR_MONTH}-${scanner}"
  local seq=1
  while [ -f "$FINDINGS_DIR/${prefix}-$(printf '%03d' $seq).json" ]; do
    seq=$((seq+1))
  done
  local finding_id="${prefix}-$(printf '%03d' $seq)"

  cat > "$FINDINGS_DIR/$finding_id.json" << FJEOF
{
  "id": "$finding_id",
  "severity": "$severity",
  "scanner": "$scanner",
  "description": "$description",
  "detail": $(echo "$detail" | jq -R . 2>/dev/null || echo "\"$detail\""),
  "first_seen": "$SCAN_ID",
  "status": "discovered",
  "project": "$PROJECT_NAME",
  "github_issue": null,
  "history": [
    {
      "date": "$(date -u '+%Y-%m-%d')",
      "action": "discovered",
      "scan_id": "$SCAN_ID"
    }
  ]
}
FJEOF

  CREATED=$((CREATED+1))
  echo "  Created: $finding_id ($severity) $description"
}

echo "Creating findings from scan: $SCAN_ID"

# Find the project subdirectory in the scan
# Structure: docs/scans/<scan-id>/<project-subdir>/
for project_dir in "$SCAN_DIR"/*/; do
  [ ! -d "$project_dir" ] && continue
  subname=$(basename "$project_dir")
  case "$subname" in pentest|seo|wp-security|compliance|audit) continue ;; esac
  [ ! -f "$project_dir/sast-result.json" ] && [ ! -f "$project_dir/vulnerability-result.json" ] && continue

  # SAST findings (critical only for now)
  if [ -f "$project_dir/sast-result.json" ]; then
    SAST_C=$(jq '.summary.critical // 0' "$project_dir/sast-result.json" 2>/dev/null || echo 0)
    SAST_H=$(jq '.summary.high // 0' "$project_dir/sast-result.json" 2>/dev/null || echo 0)
    if [ "$SAST_C" -gt 0 ] || [ "$SAST_H" -gt 0 ]; then
      # Extract individual findings if available
      if jq -e '.findings[]' "$project_dir/sast-result.json" >/dev/null 2>&1; then
        jq -c '.findings[] | select(.severity == "critical" or .severity == "high")' "$project_dir/sast-result.json" 2>/dev/null | while read -r f; do
          sev=$(echo "$f" | jq -r '.severity')
          desc=$(echo "$f" | jq -r '.rule_id // .check_id // "SAST finding"')
          file=$(echo "$f" | jq -r '.path // .file // "unknown"')
          create_finding "SAST" "$sev" "$desc" "File: $file"
        done
      else
        # No detailed findings, create summary entries
        [ "$SAST_C" -gt 0 ] && create_finding "SAST" "critical" "SAST: $SAST_C critical findings" "See sast-result.json for details"
        [ "$SAST_H" -gt 0 ] && create_finding "SAST" "high" "SAST: $SAST_H high findings" "See sast-result.json for details"
      fi
    fi
  fi

  # Vulnerability findings
  if [ -f "$project_dir/vulnerability-result.json" ]; then
    VULN_C=$(jq '.summary.critical // 0' "$project_dir/vulnerability-result.json" 2>/dev/null || echo 0)
    VULN_H=$(jq '.summary.high // 0' "$project_dir/vulnerability-result.json" 2>/dev/null || echo 0)
    [ "$VULN_C" -gt 0 ] && create_finding "VULN" "critical" "Vulnerability: $VULN_C critical" "See vulnerability-result.json"
    [ "$VULN_H" -gt 0 ] && create_finding "VULN" "high" "Vulnerability: $VULN_H high" "See vulnerability-result.json"
  fi

  # Crypto audit failures
  if [ -f "$project_dir/crypto-audit-result.json" ]; then
    CRYPTO_F=$(jq '.summary.fail // 0' "$project_dir/crypto-audit-result.json" 2>/dev/null || echo 0)
    [ "$CRYPTO_F" -gt 0 ] && create_finding "CRYPTO" "high" "Crypto audit: $CRYPTO_F failures" "See crypto-audit-result.json"
  fi

  # AI Safety failures
  if [ -f "$project_dir/ai-safety-result.json" ]; then
    AI_F=$(jq '.summary.fail // 0' "$project_dir/ai-safety-result.json" 2>/dev/null || echo 0)
    [ "$AI_F" -gt 0 ] && create_finding "AI-SAFETY" "high" "AI Safety: $AI_F failures" "See ai-safety-result.json"
  fi

  # AI Supply Chain failures
  if [ -f "$project_dir/ai-supply-chain-result.json" ]; then
    AIS_F=$(jq '.summary.fail // 0' "$project_dir/ai-supply-chain-result.json" 2>/dev/null || echo 0)
    [ "$AIS_F" -gt 0 ] && create_finding "AI-SUPPLY" "high" "AI Supply Chain: $AIS_F failures" "See ai-supply-chain-result.json"
  fi
done

# Pentest findings
if [ -f "$SCAN_DIR/pentest/pentest-result.json" ]; then
  PT_C=$(jq '.summary.critical // 0' "$SCAN_DIR/pentest/pentest-result.json" 2>/dev/null || echo 0)
  PT_H=$(jq '.summary.high // 0' "$SCAN_DIR/pentest/pentest-result.json" 2>/dev/null || echo 0)
  [ "$PT_C" -gt 0 ] && create_finding "PENTEST" "critical" "Pentest: $PT_C critical" "See pentest-result.json"
  [ "$PT_H" -gt 0 ] && create_finding "PENTEST" "high" "Pentest: $PT_H high" "See pentest-result.json"
fi

echo ""
echo "Created $CREATED findings for $PROJECT_NAME"
