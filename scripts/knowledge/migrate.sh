#!/bin/bash
# Knowledge documents migration: type-based → document-based folder structure
# Usage: scripts/knowledge/migrate.sh [--dry-run]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

MAPPING="$SCRIPT_DIR/migration-mapping.json"
DOCS_DIR="$PROJECT_ROOT/$DOCUMENTS_PATH"
DRY_RUN=false

[ "$1" = "--dry-run" ] && DRY_RUN=true

if [ ! -f "$MAPPING" ]; then
  echo "ERROR: migration-mapping.json not found"
  exit 1
fi

TOTAL=$(jq length "$MAPPING")
echo "Knowledge migration: $TOTAL documents to migrate"
echo "Dry run: $DRY_RUN"
echo ""

MOVED=0
ERRORS=0

for i in $(seq 0 $((TOTAL - 1))); do
  entry=$(jq -c ".[$i]" "$MAPPING")
  doc_id=$(echo "$entry" | jq -r '.doc_id')
  old_zh=$(echo "$entry" | jq -r '.old_zh')
  old_en=$(echo "$entry" | jq -r '.old_en')
  new_folder=$(echo "$entry" | jq -r '.new_folder')
  new_zh=$(echo "$entry" | jq -r '.new_zh')
  new_en=$(echo "$entry" | jq -r '.new_en')

  target_dir="$DOCS_DIR/$new_folder"

  echo "[$((i+1))/$TOTAL] $doc_id → $new_folder/"

  if [ "$DRY_RUN" = true ]; then
    echo "  mkdir -p $target_dir"
    [ -f "$PROJECT_ROOT/$old_zh" ] && echo "  git mv $old_zh → $DOCUMENTS_PATH$new_folder/$new_zh"
    [ "$old_en" != "null" ] && [ -f "$PROJECT_ROOT/$old_en" ] && echo "  git mv $old_en → $DOCUMENTS_PATH$new_folder/$new_en"
    continue
  fi

  # Create target directory
  mkdir -p "$target_dir"

  # Move zh-TW file
  if [ -f "$PROJECT_ROOT/$old_zh" ]; then
    git mv "$PROJECT_ROOT/$old_zh" "$target_dir/$new_zh"
    MOVED=$((MOVED+1))
  else
    echo "  WARNING: $old_zh not found"
    ERRORS=$((ERRORS+1))
  fi

  # Move en file (if exists)
  if [ "$old_en" != "null" ]; then
    if [ -f "$PROJECT_ROOT/$old_en" ]; then
      git mv "$PROJECT_ROOT/$old_en" "$target_dir/$new_en"
      MOVED=$((MOVED+1))
    else
      echo "  WARNING: $old_en not found"
      ERRORS=$((ERRORS+1))
    fi
  fi
done

echo ""
echo "Migration complete: $MOVED files moved, $ERRORS errors"

# Remove old empty directories
if [ "$DRY_RUN" = false ]; then
  echo ""
  echo "Cleaning up old directories..."
  for d in policies procedures work-instructions standards guidelines forms registers plans soa matrices; do
    if [ -d "$DOCS_DIR/$d" ]; then
      # Remove CLAUDE.md files from old directories
      find "$DOCS_DIR/$d" -name "CLAUDE.md" -exec git rm {} \; 2>/dev/null || true
      # Remove empty directories
      find "$DOCS_DIR/$d" -type d -empty -delete 2>/dev/null || true
      # If directory still has remaining files, warn
      if [ -d "$DOCS_DIR/$d" ]; then
        remaining=$(find "$DOCS_DIR/$d" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ "$remaining" -gt 0 ]; then
          echo "  WARNING: $d still has $remaining files"
        else
          rmdir "$DOCS_DIR/$d"/*/ 2>/dev/null || true
          rmdir "$DOCS_DIR/$d" 2>/dev/null || echo "  Could not remove $d"
        fi
      fi
    fi
  done
fi
