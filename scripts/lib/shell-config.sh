#!/bin/bash
# Shell config utility — reads config.json values via Node.js
# Usage: source scripts/lib/shell-config.sh
#        cfg '.knowledge_body.name_en'
#        cfg '.data_sources.documents.path' 'knowledge/'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CONFIG_FILE="${PROJECT_ROOT}/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.json not found at $CONFIG_FILE" >&2
  echo "Run the CLAUDE.md wizard to initialize." >&2
  exit 1
fi

# Read a config value by JSON path
# $1: dot-separated path (e.g., 'knowledge_body.name_en')
# $2: default value (optional)
cfg() {
  local jpath="$1"
  local default="${2:-}"
  local value
  value=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}', 'utf8'));
    const v = '${jpath}'.split('.').filter(Boolean).reduce((o, k) => o && o[k], c);
    process.stdout.write(v === undefined || v === null ? '' : String(v));
  " 2>/dev/null)
  echo "${value:-$default}"
}

# Read a config array as newline-separated JSON objects
cfg_array() {
  local jpath="$1"
  node -e "
    const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}', 'utf8'));
    const v = '${jpath}'.split('.').filter(Boolean).reduce((o, k) => o && o[k], c);
    if (Array.isArray(v)) v.forEach(i => console.log(typeof i === 'object' ? JSON.stringify(i) : i));
  " 2>/dev/null
}

# Read a config boolean
cfg_bool() {
  local jpath="$1"
  local val
  val=$(cfg "$jpath" "false")
  [ "$val" = "true" ]
}

# Count grep matches without failing on zero matches
count_matches() { grep -c "$1" "$2" 2>/dev/null || true; }

# Safely extract an integer from a string (strips non-digits, defaults to 0)
safe_int() {
  local num=$(echo "$1" | head -1 | tr -cd '0-9' | head -c 10)
  echo "${num:-0}"
}

# Common config values (pre-loaded for convenience)
KB_NAME_EN=$(cfg 'knowledge_body.name_en' 'unknown')
KB_NAME=$(cfg 'knowledge_body.name' '')
KB_ORG=$(cfg 'knowledge_body.organization' '')
DOCUMENTS_PATH=$(cfg 'data_sources.documents.path' 'knowledge/')
COLLECTED_PATH=$(cfg 'data_sources.tables.collected.path' 'data/collected/')
REPORTED_PATH=$(cfg 'data_sources.tables.reported.path' 'data/reported/')
PROJECTS_PATH=$(cfg 'paths.projects' 'docs/projects')
METADATA_FILENAME=$(cfg 'domain.metadata_filename' 'merge.yaml')
FORM_PREFIX=$(cfg 'domain.form_prefix' 'FRM')
MAIN_BRANCH=$(cfg 'git.main_branch' 'main')
PUBLISH_BRANCH=$(cfg 'git.publish_branch' 'audit')
REVIEW_PREFIX=$(cfg 'git.review_branch_prefix' 'review-')
