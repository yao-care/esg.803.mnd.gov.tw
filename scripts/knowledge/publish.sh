#!/bin/bash
# Publish: generate all HTML → optionally push to publish branch
# Usage: publish.sh [--local-only]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

MERGE="$SCRIPT_DIR/merge.sh"
DOCS_DIR="$PROJECT_ROOT/$DOCUMENTS_PATH"
OUTPUT="/tmp/knowledge-publish-$$"
LOCAL_ONLY=false
[ "$1" = "--local-only" ] && LOCAL_ONLY=true

mkdir -p "$OUTPUT/documents" "$OUTPUT/forms" "$OUTPUT/scans"

echo "========================================"
echo "  Knowledge Publish"
echo "========================================"
echo ""

TOTAL=0
SUCCESS=0
FAIL_LIST=""

for folder in "$DOCS_DIR"/*/; do
  [ ! -d "$folder" ] && continue
  [ ! -f "$folder/$METADATA_FILENAME" ] && continue

  bname=$(basename "$folder")
  doc_id=$(grep "^document_id:" "$folder/$METADATA_FILENAME" | sed 's/^document_id: *//')

  TOTAL=$((TOTAL+1))

  # form_prefix → forms/, others → documents/
  type_prefix=$(echo "$doc_id" | sed 's/-[0-9]*//')
  doc_type=$(grep "^type:" "$folder/$METADATA_FILENAME" 2>/dev/null | sed 's/^type: *//' || true)
  if [ "$type_prefix" = "$FORM_PREFIX" ] || [ "$doc_type" = "$FORM_PREFIX" ]; then
    out_dir="$OUTPUT/forms/$bname"
  else
    out_dir="$OUTPUT/documents/$bname"
  fi

  if "$MERGE" "$folder" "$out_dir" 2>/dev/null; then
    SUCCESS=$((SUCCESS+1))
  else
    echo "  FAIL: $bname ($doc_id)"
    FAIL_LIST="$FAIL_LIST $bname"
  fi
done

echo ""
echo "Generated: $SUCCESS / $TOTAL documents"
[ -n "$FAIL_LIST" ] && echo "Failed:$FAIL_LIST"

# Copy scan reports
if [ -d "$PROJECT_ROOT/$COLLECTED_PATH" ]; then
  cp -r "$PROJECT_ROOT/$COLLECTED_PATH"* "$OUTPUT/scans/" 2>/dev/null || true
  echo "Copied scan reports"
fi

# Copy project dashboards
if [ -d "$PROJECT_ROOT/$PROJECTS_PATH" ]; then
  mkdir -p "$OUTPUT/projects"
  cp -r "$PROJECT_ROOT/$PROJECTS_PATH"* "$OUTPUT/projects/" 2>/dev/null || true
fi

# Generate project dashboards
if [ -d "$PROJECT_ROOT/$PROJECTS_PATH" ]; then
  echo "Generating project dashboards..."
  for proj_dir in "$PROJECT_ROOT/$PROJECTS_PATH"*/; do
    [ ! -d "$proj_dir" ] && continue
    proj_name=$(basename "$proj_dir")
    mkdir -p "$OUTPUT/projects/$proj_name"
    "$SCRIPT_DIR/generate-project-dashboard.sh" "$proj_name" "$OUTPUT/projects/$proj_name" 2>/dev/null || echo "  WARN: dashboard for $proj_name failed"
  done
fi

# Copy styles
cp "$PROJECT_ROOT/templates/styles.css" "$OUTPUT/styles.css"

# Generate index
"$SCRIPT_DIR/generate-dashboard.sh" "$OUTPUT" "$DOCS_DIR"

echo ""
if [ "$LOCAL_ONLY" = true ]; then
  echo "Local output: $OUTPUT"
  echo "Open: open $OUTPUT/index.html"
  exit 0
fi

# Push to publish branch
echo "Pushing to $PUBLISH_BRANCH branch..."
CURRENT_BRANCH=$(git branch --show-current)

if ! git rev-parse --verify "$PUBLISH_BRANCH" >/dev/null 2>&1; then
  git checkout --orphan "$PUBLISH_BRANCH"
  git rm -rf . >/dev/null 2>&1 || true
  git commit --allow-empty -m "init: create $PUBLISH_BRANCH branch"
else
  git checkout "$PUBLISH_BRANCH"
fi

find . -maxdepth 1 -not -name '.git' -not -name '.' -exec rm -rf {} + 2>/dev/null || true
cp -r "$OUTPUT/"* .

git add -A
git commit -m "publish: knowledge documents $(date '+%Y-%m-%d %H:%M')" || echo "No changes"

git checkout "$CURRENT_BRANCH"
rm -rf "$OUTPUT"
echo "Published to $PUBLISH_BRANCH branch"
