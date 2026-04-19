#!/bin/bash
# merge.sh — knowledge document-to-HTML generator
#
# Reads a single knowledge document folder's metadata file + .md files,
# converts markdown to HTML via pandoc, applies the OKLCH template,
# handles references, injects git version info, and outputs index.html.
#
# Usage: merge.sh <folder-path> <output-dir> [--dry-run]
#
# Examples:
#   ./scripts/knowledge/merge.sh knowledge/05-vulnerability-management /tmp/merge-test
#   ./scripts/knowledge/merge.sh knowledge/POL-security /tmp/merge-test2 --dry-run
set -euo pipefail

# ── Resolve paths ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PARSE_YAML="$SCRIPT_DIR/parse-yaml.sh"
source "$SCRIPT_DIR/../lib/shell-config.sh"

# ── Validate arguments ──
if [ $# -lt 2 ]; then
  echo "Usage: merge.sh <folder-path> <output-dir> [--dry-run]" >&2
  exit 1
fi

FOLDER_PATH="$1"
OUTPUT_DIR="$2"
DRY_RUN=false
if [ "${3:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# Resolve folder to absolute path
if [[ "$FOLDER_PATH" != /* ]]; then
  FOLDER_PATH="$REPO_ROOT/$FOLDER_PATH"
fi

if [ ! -d "$FOLDER_PATH" ]; then
  echo "Error: folder not found: $FOLDER_PATH" >&2
  exit 1
fi

MERGE_YAML="$FOLDER_PATH/$METADATA_FILENAME"
if [ ! -f "$MERGE_YAML" ]; then
  echo "Error: $METADATA_FILENAME not found in $FOLDER_PATH" >&2
  exit 1
fi

if [ ! -f "$PARSE_YAML" ]; then
  echo "Error: parse-yaml.sh not found at $PARSE_YAML" >&2
  exit 1
fi

# ── Step 1: Parse metadata file ──
echo "[merge] Parsing $METADATA_FILENAME ..."
MERGE_JSON=$("$PARSE_YAML" "$MERGE_YAML")

DOCUMENT_ID=$(echo "$MERGE_JSON" | jq -r '.document_id // ""')
TITLE_ZH=$(echo "$MERGE_JSON" | jq -r '.title_zh // ""')
TITLE_EN=$(echo "$MERGE_JSON" | jq -r '.title_en // ""')
MAIN_ZH=$(echo "$MERGE_JSON" | jq -r '.main.zh // ""')
MAIN_EN=$(echo "$MERGE_JSON" | jq -r '.main.en // ""')

if [ -z "$DOCUMENT_ID" ] || [ -z "$TITLE_ZH" ] || [ -z "$MAIN_ZH" ]; then
  echo "Error: $METADATA_FILENAME missing required fields (document_id, title_zh, main.zh)" >&2
  exit 1
fi

echo "[merge] Document: $DOCUMENT_ID — $TITLE_ZH"

# ── Step 2: Read main zh-TW .md file and extract frontmatter ──
MAIN_ZH_PATH="$FOLDER_PATH/$MAIN_ZH"
if [ ! -f "$MAIN_ZH_PATH" ]; then
  echo "Error: main zh file not found: $MAIN_ZH_PATH" >&2
  exit 1
fi

# Extract frontmatter as JSON using python3
FRONTMATTER_JSON=$(python3 -c "
import yaml, json, sys

with open(sys.argv[1], 'r') as f:
    content = f.read()

# Extract YAML between first two --- lines
if content.startswith('---'):
    parts = content.split('---', 2)
    if len(parts) >= 3:
        fm = yaml.safe_load(parts[1])
        if fm:
            print(json.dumps(fm, ensure_ascii=False, default=str))
        else:
            print('{}')
    else:
        print('{}')
else:
    print('{}')
" "$MAIN_ZH_PATH")

VERSION=$(echo "$FRONTMATTER_JSON" | jq -r '.version // "1.0"')
STATUS=$(echo "$FRONTMATTER_JSON" | jq -r '.status // "draft"')
CLASSIFICATION=$(echo "$FRONTMATTER_JSON" | jq -r '.classification // "internal"')
OWNER=$(echo "$FRONTMATTER_JSON" | jq -r '.owner // ""')
APPROVED_BY=$(echo "$FRONTMATTER_JSON" | jq -r '.approved_by // ""')
EFFECTIVE_DATE=$(echo "$FRONTMATTER_JSON" | jq -r '.effective_date // ""')
NEXT_REVIEW_DATE=$(echo "$FRONTMATTER_JSON" | jq -r '.next_review_date // ""')

# Controls — join array into comma-separated string (supports 'controls' with fallback to 'iso_27001_controls')
ISO_CONTROLS=$(echo "$FRONTMATTER_JSON" | jq -r '
  if .controls then
    (.controls | if type == "array" then join(", ") else . end)
  elif .iso_27001_controls then
    (.iso_27001_controls | if type == "array" then join(", ") else . end)
  else
    ""
  end
')

# ── Step 3: Strip frontmatter and convert markdown to HTML ──
echo "[merge] Converting markdown to HTML ..."

# Strip YAML frontmatter (everything between first two --- lines)
MD_BODY=$(python3 -c "
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
if content.startswith('---'):
    parts = content.split('---', 2)
    if len(parts) >= 3:
        print(parts[2])
    else:
        print(content)
else:
    print(content)
" "$MAIN_ZH_PATH")

# Convert to HTML via pandoc, fallback to <pre> if unavailable
if command -v pandoc &>/dev/null; then
  CONTENT_ZH=$(echo "$MD_BODY" | pandoc -f markdown -t html)
else
  echo "[merge] Warning: pandoc not found, using raw text fallback"
  CONTENT_ZH="<pre>$(echo "$MD_BODY" | python3 -c "import sys,html; print(html.escape(sys.stdin.read()))")</pre>"
fi

# ── Step 4: Determine template ──
if [[ "$DOCUMENT_ID" == FRM-* ]]; then
  TEMPLATE_FILE="$REPO_ROOT/templates/form.html"
  echo "[merge] Using form template (FRM document)"
else
  TEMPLATE_FILE="$REPO_ROOT/templates/document.html"
  echo "[merge] Using document template"
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Error: template not found: $TEMPLATE_FILE" >&2
  exit 1
fi

# ── Step 5: Generate status badge HTML ──
case "$STATUS" in
  approved)
    STATUS_BADGE='<span class="badge" style="background: oklch(0.92 0.04 150); color: var(--color-pass);">Approved</span>'
    ;;
  draft)
    STATUS_BADGE='<span class="badge" style="background: oklch(0.92 0.04 80); color: var(--color-warn);">Draft</span>'
    ;;
  review)
    STATUS_BADGE='<span class="badge" style="background: oklch(0.92 0.03 240); color: var(--color-info);">Review</span>'
    ;;
  *)
    STATUS_BADGE='<span class="badge" style="background: var(--bg-overlay); color: var(--text-secondary);">'"$STATUS"'</span>'
    ;;
esac

# ── Step 6: Handle automation field (optional) ──
AUTOMATION_BADGE=""
AUTOMATION_JSON=$(echo "$MERGE_JSON" | jq -r '.automation // empty')
if [ -n "$AUTOMATION_JSON" ]; then
  AUTO_SCRIPT=$(echo "$MERGE_JSON" | jq -r '.automation.script // ""')
  AUTO_DESC_ZH=$(echo "$MERGE_JSON" | jq -r '.automation.description_zh // ""')
  if [ -n "$AUTO_SCRIPT" ]; then
    AUTOMATION_BADGE='<span class="automation-badge">&#9889; '"$AUTO_DESC_ZH"' ('"$AUTO_SCRIPT"')</span>'
  fi
fi

# ── Step 7: Handle automation_source field (optional) ──
AUTOMATION_SOURCE_HTML=""
AUTOMATION_SRC_JSON=$(echo "$MERGE_JSON" | jq -r '.automation_source // empty')
if [ -n "$AUTOMATION_SRC_JSON" ]; then
  WORKFLOW_FILE=$(echo "$MERGE_JSON" | jq -r '.automation_source.workflow // ""')
  WORKFLOW_PATH="$REPO_ROOT/$WORKFLOW_FILE"
  if [ -n "$WORKFLOW_FILE" ] && [ -f "$WORKFLOW_PATH" ]; then
    # Extract cron schedules from the workflow YAML
    CRON_LINES=$(python3 -c "
import yaml, sys
with open(sys.argv[1], 'r') as f:
    data = yaml.safe_load(f)
schedules = []
if data and isinstance(data, dict):
    on = data.get('on') or data.get(True)  # YAML parses 'on' as True
    if isinstance(on, dict):
        schedule = on.get('schedule', [])
        if isinstance(schedule, list):
            for s in schedule:
                if isinstance(s, dict) and 'cron' in s:
                    schedules.append(s['cron'])
for s in schedules:
    print(s)
" "$WORKFLOW_PATH" 2>/dev/null || true)

    SCHEDULE_INFO=""
    if [ -n "$CRON_LINES" ]; then
      SCHEDULE_INFO="<div style=\"margin-top: 0.5rem;\"><strong>排程:</strong> "
      while IFS= read -r cron_line; do
        SCHEDULE_INFO="${SCHEDULE_INFO}<code>${cron_line}</code> "
      done <<< "$CRON_LINES"
      SCHEDULE_INFO="${SCHEDULE_INFO}</div>"
    fi

    AUTOMATION_SOURCE_HTML='<div class="automation-source"><div class="automation-title">&#9889; 自動化來源</div><div>Workflow: <code>'"$WORKFLOW_FILE"'</code></div>'"$SCHEDULE_INFO"'</div>'
  fi
fi

# ── Step 8: Handle references ──
echo "[merge] Processing references ..."
REFERENCES_HTML=""
REF_COUNT=$(echo "$MERGE_JSON" | jq '.references | length')

if [ "$REF_COUNT" -gt 0 ]; then
  LINK_REFS=""
  EMBED_REFS=""

  for i in $(seq 0 $((REF_COUNT - 1))); do
    REF_DOC_ID=$(echo "$MERGE_JSON" | jq -r ".references[$i].document_id")
    REF_ROLE=$(echo "$MERGE_JSON" | jq -r ".references[$i].role")

    # Find the target folder by searching documents for matching document_id
    TARGET_FOLDER=""
    TARGET_TITLE_ZH=""
    TARGET_TITLE_EN=""
    TARGET_MAIN_ZH=""

    for merge_file in "$REPO_ROOT"/$DOCUMENTS_PATH/*/"$METADATA_FILENAME"; do
      CANDIDATE_JSON=$("$PARSE_YAML" "$merge_file" 2>/dev/null || true)
      CANDIDATE_ID=$(echo "$CANDIDATE_JSON" | jq -r '.document_id // ""' 2>/dev/null || true)
      if [ "$CANDIDATE_ID" = "$REF_DOC_ID" ]; then
        TARGET_FOLDER=$(dirname "$merge_file")
        TARGET_TITLE_ZH=$(echo "$CANDIDATE_JSON" | jq -r '.title_zh // ""')
        TARGET_TITLE_EN=$(echo "$CANDIDATE_JSON" | jq -r '.title_en // ""')
        TARGET_MAIN_ZH=$(echo "$CANDIDATE_JSON" | jq -r '.main.zh // ""')
        break
      fi
    done

    if [ -z "$TARGET_FOLDER" ]; then
      echo "[merge] Warning: reference $REF_DOC_ID not found, skipping"
      continue
    fi

    TARGET_FOLDER_NAME=$(basename "$TARGET_FOLDER")

    # Check if this is an embedded reference (附表*)
    if [[ "$REF_ROLE" == 附表* ]]; then
      # Embed: convert the referenced document's .md to HTML and include inline
      REF_MD_PATH="$TARGET_FOLDER/$TARGET_MAIN_ZH"
      if [ -f "$REF_MD_PATH" ]; then
        REF_MD_BODY=$(python3 -c "
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
if content.startswith('---'):
    parts = content.split('---', 2)
    if len(parts) >= 3:
        print(parts[2])
    else:
        print(content)
else:
    print(content)
" "$REF_MD_PATH")

        if command -v pandoc &>/dev/null; then
          REF_HTML=$(echo "$REF_MD_BODY" | pandoc -f markdown -t html)
        else
          REF_HTML="<pre>$(echo "$REF_MD_BODY" | python3 -c "import sys,html; print(html.escape(sys.stdin.read()))")</pre>"
        fi

        EMBED_REFS="${EMBED_REFS}<div class=\"section-block doc-content\" style=\"border-top: 2px solid var(--border-subtle); padding-top: 1.5rem; margin-top: 1.5rem;\"><div style=\"font-size: var(--text-xs); color: var(--text-muted); margin-bottom: 0.5rem;\">$REF_ROLE — $REF_DOC_ID $TARGET_TITLE_ZH</div>${REF_HTML}</div>"
      else
        echo "[merge] Warning: referenced file not found: $REF_MD_PATH"
      fi
    else
      # Link reference: generate a card linking to ../<folder-name>/index.html
      LINK_REFS="${LINK_REFS}<div class=\"ref-card\"><a class=\"ref-link\" href=\"../${TARGET_FOLDER_NAME}/index.html\">${REF_DOC_ID} ${TARGET_TITLE_ZH}</a><div class=\"ref-desc\">${REF_ROLE} — ${TARGET_TITLE_EN}</div></div>"
    fi
  done

  # Compose references HTML
  if [ -n "$LINK_REFS" ]; then
    REFERENCES_HTML="<div class=\"ref-section\">${LINK_REFS}</div>"
  fi
  if [ -n "$EMBED_REFS" ]; then
    REFERENCES_HTML="${REFERENCES_HTML}${EMBED_REFS}"
  fi
fi

if [ -z "$REFERENCES_HTML" ]; then
  REFERENCES_HTML='<div style="color: var(--text-muted); font-size: var(--text-sm);">（無參考文件）</div>'
fi

# ── Step 9: Git version history ──
echo "[merge] Collecting git version history ..."
VERSION_HISTORY=""
GIT_LOG=$(cd "$REPO_ROOT" && git log --format='%H|%ai|%s' -20 -- "$FOLDER_PATH" 2>/dev/null || true)

if [ -n "$GIT_LOG" ]; then
  while IFS='|' read -r hash date msg; do
    SHORT_HASH="${hash:0:7}"
    # Extract just the date portion (YYYY-MM-DD)
    DATE_ONLY="${date%% *}"

    # Escape HTML special chars in the commit message
    SAFE_MSG=$(python3 -c "import sys,html; print(html.escape(sys.argv[1]))" "$msg")

    if [[ "$DOCUMENT_ID" == FRM-* ]]; then
      # Form template uses table rows
      VERSION_HISTORY="${VERSION_HISTORY}<tr><td><code>${SHORT_HASH}</code></td><td>${DATE_ONLY}</td><td>git</td><td>${SAFE_MSG}</td></tr>"
    else
      # Document template uses div entries
      VERSION_HISTORY="${VERSION_HISTORY}<div class=\"version-history-entry\"><span class=\"version-history-date\">${DATE_ONLY}</span><span class=\"version-history-hash\">${SHORT_HASH}</span><span class=\"version-history-msg\">${SAFE_MSG}</span></div>"
    fi
  done <<< "$GIT_LOG"
fi

if [ -z "$VERSION_HISTORY" ]; then
  if [[ "$DOCUMENT_ID" == FRM-* ]]; then
    VERSION_HISTORY='<tr><td colspan="4" style="color: var(--text-muted);">（尚無版本紀錄）</td></tr>'
  else
    VERSION_HISTORY='<div class="version-history-entry"><span class="version-history-date">—</span><span class="version-history-hash">—</span><span class="version-history-msg">（尚無版本紀錄）</span></div>'
  fi
fi

# ── Step 10: Last modified date ──
LAST_MODIFIED=$(cd "$REPO_ROOT" && git log -1 --format='%ai' -- "$FOLDER_PATH" 2>/dev/null || true)
if [ -n "$LAST_MODIFIED" ]; then
  LAST_MODIFIED="${LAST_MODIFIED%% *}"
else
  LAST_MODIFIED="—"
fi

# ── Step 11: Generated timestamp ──
GENERATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

# ── Step 12: Read OKLCH styles ──
STYLES_FILE="$REPO_ROOT/templates/styles.css"
if [ -f "$STYLES_FILE" ]; then
  OKLCH_STYLES=$(cat "$STYLES_FILE")
else
  OKLCH_STYLES=""
fi

# ── Step 13: Dry run check ──
if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "[dry-run] Would generate: $OUTPUT_DIR/index.html"
  echo "[dry-run] Template: $TEMPLATE_FILE"
  echo "[dry-run] Document: $DOCUMENT_ID — $TITLE_ZH ($TITLE_EN)"
  echo "[dry-run] Version: $VERSION | Status: $STATUS | Classification: $CLASSIFICATION"
  echo "[dry-run] Owner: $OWNER | Approved by: $APPROVED_BY"
  echo "[dry-run] Effective: $EFFECTIVE_DATE | Next review: $NEXT_REVIEW_DATE"
  echo "[dry-run] ISO controls: $ISO_CONTROLS"
  echo "[dry-run] Last modified: $LAST_MODIFIED"
  echo "[dry-run] Git history entries: $(echo "$GIT_LOG" | grep -c '.' || echo 0)"
  echo "[dry-run] References: $REF_COUNT"
  echo "[dry-run] Automation badge: $([ -n "$AUTOMATION_BADGE" ] && echo 'yes' || echo 'no')"
  echo "[dry-run] Automation source: $([ -n "$AUTOMATION_SOURCE_HTML" ] && echo 'yes' || echo 'no')"
  exit 0
fi

# ── Step 14: Render template using python3 for reliable multiline replacement ──
echo "[merge] Rendering template ..."
mkdir -p "$OUTPUT_DIR"

export _MERGE_DOCUMENT_ID="$DOCUMENT_ID"
export _MERGE_TITLE_ZH="$TITLE_ZH"
export _MERGE_TITLE_EN="$TITLE_EN"
export _MERGE_VERSION="$VERSION"
export _MERGE_STATUS_BADGE="$STATUS_BADGE"
export _MERGE_AUTOMATION_BADGE="$AUTOMATION_BADGE"
export _MERGE_CLASSIFICATION="$CLASSIFICATION"
export _MERGE_OWNER="$OWNER"
export _MERGE_APPROVED_BY="$APPROVED_BY"
export _MERGE_EFFECTIVE_DATE="$EFFECTIVE_DATE"
export _MERGE_NEXT_REVIEW="$NEXT_REVIEW_DATE"
export _MERGE_LAST_MODIFIED="$LAST_MODIFIED"
export _MERGE_ISO_CONTROLS="$ISO_CONTROLS"
export _MERGE_OKLCH_STYLES="$OKLCH_STYLES"
export _MERGE_CONTENT_ZH="$CONTENT_ZH"
export _MERGE_REFERENCES_HTML="$REFERENCES_HTML"
export _MERGE_VERSION_HISTORY="$VERSION_HISTORY"
export _MERGE_AUTOMATION_SOURCE_HTML="$AUTOMATION_SOURCE_HTML"
export _MERGE_GENERATED_AT="$GENERATED_AT"

python3 -c "
import sys, os

# Read template
template_path = sys.argv[1]
output_path = sys.argv[2]

with open(template_path, 'r') as f:
    html = f.read()

# Read replacement values from environment
replacements = {
    '{{DOCUMENT_ID}}': os.environ['_MERGE_DOCUMENT_ID'],
    '{{TITLE_ZH}}': os.environ['_MERGE_TITLE_ZH'],
    '{{TITLE_EN}}': os.environ['_MERGE_TITLE_EN'],
    '{{VERSION}}': os.environ['_MERGE_VERSION'],
    '{{STATUS_BADGE}}': os.environ['_MERGE_STATUS_BADGE'],
    '{{AUTOMATION_BADGE}}': os.environ['_MERGE_AUTOMATION_BADGE'],
    '{{CLASSIFICATION}}': os.environ['_MERGE_CLASSIFICATION'],
    '{{OWNER}}': os.environ['_MERGE_OWNER'],
    '{{APPROVED_BY}}': os.environ['_MERGE_APPROVED_BY'],
    '{{EFFECTIVE_DATE}}': os.environ['_MERGE_EFFECTIVE_DATE'],
    '{{NEXT_REVIEW}}': os.environ['_MERGE_NEXT_REVIEW'],
    '{{LAST_MODIFIED}}': os.environ['_MERGE_LAST_MODIFIED'],
    '{{ISO_CONTROLS}}': os.environ['_MERGE_ISO_CONTROLS'],
    '{{OKLCH_STYLES}}': os.environ['_MERGE_OKLCH_STYLES'],
    '{{CONTENT_ZH}}': os.environ['_MERGE_CONTENT_ZH'],
    '{{REFERENCES_HTML}}': os.environ['_MERGE_REFERENCES_HTML'],
    '{{VERSION_HISTORY}}': os.environ['_MERGE_VERSION_HISTORY'],
    '{{AUTOMATION_SOURCE_HTML}}': os.environ['_MERGE_AUTOMATION_SOURCE_HTML'],
    '{{GENERATED_AT}}': os.environ['_MERGE_GENERATED_AT'],
}

for token, value in replacements.items():
    html = html.replace(token, value)

with open(output_path, 'w') as f:
    f.write(html)

print(f'[merge] Written: {output_path}')
" "$TEMPLATE_FILE" "$OUTPUT_DIR/index.html"

echo "[merge] Done: $DOCUMENT_ID → $OUTPUT_DIR/index.html"
