#!/usr/bin/env bash
# generate-merge-yaml.sh — generates metadata file for every document folder
# Usage: ./scripts/knowledge/generate-merge-yaml.sh
# Skips folders that already have the metadata file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

DOCS_DIR="$PROJECT_ROOT/$DOCUMENTS_PATH"

generated=0
skipped=0
errors=0

for dir in "$DOCS_DIR"/*/; do
  [ -d "$dir" ] || continue

  folder=$(basename "$dir")

  # Skip non-document directories
  case "$folder" in
    scripts|templates) continue ;;
  esac

  # Skip if metadata file already exists
  if [ -f "$dir/$METADATA_FILENAME" ]; then
    echo "SKIP (already exists): $folder/$METADATA_FILENAME"
    skipped=$((skipped + 1))
    continue
  fi

  # Find zh-TW markdown file (exclude .en.md and scaffolding files)
  zh_file=""
  while IFS= read -r f; do
    zh_file="$f"
    break
  done < <(find "$dir" -maxdepth 1 -name "*.md" \
    ! -name "*.en.md" \
    ! -name "CLAUDE.md" \
    ! -name "rule.md" \
    ! -name "writer.md" \
    ! -name "reviewer.md" \
    2>/dev/null)

  if [ -z "$zh_file" ]; then
    echo "WARN: no zh-TW .md file found in $folder — skipping"
    errors=$((errors + 1))
    continue
  fi

  # Extract frontmatter fields
  document_id=$(grep -m1 '^document_id:' "$zh_file" | sed 's/^document_id:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r')
  title_zh=$(grep -m1 '^title_zh:' "$zh_file" | sed 's/^title_zh:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r')
  title_en=$(grep -m1 '^title_en:' "$zh_file" | sed 's/^title_en:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r')

  if [ -z "$document_id" ] || [ -z "$title_zh" ] || [ -z "$title_en" ]; then
    echo "WARN: missing frontmatter in $folder/$( basename "$zh_file") — doc_id='$document_id' title_zh='$title_zh' title_en='$title_en'"
    errors=$((errors + 1))
    continue
  fi

  zh_basename=$(basename "$zh_file")

  # Find en markdown file
  en_file=""
  while IFS= read -r f; do
    en_file="$f"
    break
  done < <(find "$dir" -maxdepth 1 -name "*.en.md" 2>/dev/null)

  if [ -n "$en_file" ]; then
    en_basename=$(basename "$en_file")
    en_line="  en: $en_basename"
  else
    en_line="  en: \"\""
  fi

  # Write metadata file
  cat > "$dir/$METADATA_FILENAME" <<EOF
document_id: $document_id
title_zh: $title_zh
title_en: $title_en
main:
  zh: $zh_basename
$en_line
references: []
EOF

  echo "GENERATED: $folder/$METADATA_FILENAME (document_id=$document_id)"
  generated=$((generated + 1))
done

echo ""
echo "============================="
echo "Generated : $generated"
echo "Skipped   : $skipped"
echo "Errors    : $errors"
echo "============================="
