#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/scripts/lib/shell-config.sh"

COLLECT_DEPTH="${COLLECT_DEPTH:-standard}"
COLLECTOR_FILTER="${1:-}"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
OUTPUT_BASE="${PROJECT_ROOT}/${COLLECTED_PATH}${TIMESTAMP}"

mkdir -p "$OUTPUT_BASE"

echo "========================================"
echo "  Running collectors (depth: $COLLECT_DEPTH)"
echo "========================================"

# Read collectors from config.json, perform topological sort via Node.js
SORTED_COLLECTORS=$(node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
  const collectors = config.collectors || [];

  if (collectors.length === 0) {
    process.exit(0);
  }

  // Topological sort (depth-first)
  const resolved = [];
  const seen = new Set();

  function resolve(name) {
    if (seen.has(name)) return;
    seen.add(name);
    const c = collectors.find(x => x.name === name);
    if (!c) return;
    (c.depends_on || []).forEach(dep => resolve(dep));
    resolved.push(JSON.stringify(c));
  }

  collectors.forEach(c => resolve(c.name));
  resolved.forEach(c => console.log(c));
" 2>/dev/null)

if [ -z "$SORTED_COLLECTORS" ]; then
  echo "No collectors configured."
  # Write metadata even when no collectors run
  cat > "$OUTPUT_BASE/metadata.json" << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "depth": "$COLLECT_DEPTH",
  "output_dir": "$OUTPUT_BASE",
  "collectors_run": []
}
EOF
  exit 0
fi

COLLECTORS_RUN=()

while IFS= read -r collector_json; do
  [ -z "$collector_json" ] && continue

  name=$(echo "$collector_json" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).name||'')" 2>/dev/null)
  script=$(echo "$collector_json" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).script||'')" 2>/dev/null)

  # Apply optional collector name filter ($1 argument)
  if [ -n "$COLLECTOR_FILTER" ] && [ "$name" != "$COLLECTOR_FILTER" ]; then
    continue
  fi

  echo ""
  echo "--- Running: $name ---"

  SCRIPT_PATH="${PROJECT_ROOT}/${script}"
  if [ ! -f "$SCRIPT_PATH" ]; then
    echo "  WARNING: Script not found: $script — skipping"
    continue
  fi

  export COLLECT_DEPTH
  export OUTPUT_DIR="$OUTPUT_BASE"
  export PROJECT_ROOT

  if bash "$SCRIPT_PATH" 2>&1; then
    echo "  OK: $name completed"
    COLLECTORS_RUN+=("$name")
  else
    echo "  WARNING: $name failed (continuing...)"
  fi
done <<< "$SORTED_COLLECTORS"

echo ""
echo "========================================"
echo "  Collection complete: $OUTPUT_BASE"
echo "========================================"

# Build JSON array of collectors run
COLLECTORS_JSON="["
FIRST=1
for c in "${COLLECTORS_RUN[@]}"; do
  if [ "$FIRST" = "1" ]; then
    COLLECTORS_JSON="${COLLECTORS_JSON}\"${c}\""
    FIRST=0
  else
    COLLECTORS_JSON="${COLLECTORS_JSON},\"${c}\""
  fi
done
COLLECTORS_JSON="${COLLECTORS_JSON}]"

# Write metadata.json to output directory
cat > "$OUTPUT_BASE/metadata.json" << EOF
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "depth": "$COLLECT_DEPTH",
  "output_dir": "$OUTPUT_BASE",
  "collectors_run": ${COLLECTORS_JSON}
}
EOF
