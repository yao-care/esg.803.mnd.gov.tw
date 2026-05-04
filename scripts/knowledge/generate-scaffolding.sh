#!/usr/bin/env bash
# generate-scaffolding.sh — generates CLAUDE.md, rule.md, writer.md, reviewer.md
# for every document folder under the documents path that has a metadata file.
# Skips any file that already exists.
# Usage: ./scripts/knowledge/generate-scaffolding.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

DOCS_DIR="$PROJECT_ROOT/$DOCUMENTS_PATH"

generated=0
skipped=0
NEW_FOLDERS=""

for merge_yaml in "$DOCS_DIR"/*/"$METADATA_FILENAME"; do
  [ -f "$merge_yaml" ] || continue
  dir=$(dirname "$merge_yaml")
  folder=$(basename "$dir")
  [ "$folder" = "_meta" ] && continue
  folder_had_new=0

  # Read fields from metadata file
  doc_id=$(grep -m1 '^document_id:' "$merge_yaml" | sed 's/^document_id:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r')
  title_zh=$(grep -m1 '^title_zh:' "$merge_yaml" | sed 's/^title_zh:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r')
  title_en=$(grep -m1 '^title_en:' "$merge_yaml" | sed 's/^title_en:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '\r')

  # Determine type prefix from document_id (e.g. POL-001 → POL)
  type_prefix=$(echo "$doc_id" | sed 's/-.*//')

  # ── CLAUDE.md ──────────────────────────────────────────────
  claude_file="$dir/CLAUDE.md"
  if [ -f "$claude_file" ]; then
    echo "SKIP (exists): $folder/CLAUDE.md"
    skipped=$((skipped + 1))
  else
    cat > "$claude_file" <<EOF
# CLAUDE.md — ${title_zh} / ${title_en}

> 繼承上層 CLAUDE.md 的通用規則。本檔案定義此資料夾的特殊規則。

## 文件資訊
- Document ID: ${doc_id}
- Type: ${type_prefix}

## Agent 工作原則
- **寫文件**: 讀本檔案 → rule.md + writer.md → 用獨立 agent 執行
- **審文件**: 讀本檔案 → rule.md + reviewer.md → 用獨立 agent 執行
EOF
    echo "GENERATED: $folder/CLAUDE.md"
    generated=$((generated + 1))
    folder_had_new=1
  fi

  # ── rule.md ────────────────────────────────────────────────
  rule_file="$dir/rule.md"
  if [ -f "$rule_file" ]; then
    echo "SKIP (exists): $folder/rule.md"
    skipped=$((skipped + 1))
  else
    cat > "$rule_file" <<EOF
# ${title_zh} — 規則定義 / ${title_en} — Rules
## 對應標準
Document ID: ${doc_id}
（待補充：此文件對應的標準控制項要求、必要章節結構）
## 必要內容
（待補充）
## 交叉引用
（待補充）
EOF
    echo "GENERATED: $folder/rule.md"
    generated=$((generated + 1))
    folder_had_new=1
  fi

  # ── writer.md ──────────────────────────────────────────────
  writer_file="$dir/writer.md"
  if [ -f "$writer_file" ]; then
    echo "SKIP (exists): $folder/writer.md"
    skipped=$((skipped + 1))
  else
    cat > "$writer_file" <<EOF
# ${title_zh} — 寫作指南 / ${title_en} — Writing Guide
## 語氣與風格
- 使用正式但清晰的語氣
- zh-TW 版本依相關標準用語
- en 版本依對應國際標準用語
## 結構要求
- 文件資訊表格
- 目的/範圍/內容章節（依 rule.md）
- 相關文件引用（使用 document_id）
## 注意事項
- 引用其他文件時使用 document_id，不使用檔案路徑
- 保持 zh-TW 和 en 版本的章節結構一致
EOF
    echo "GENERATED: $folder/writer.md"
    generated=$((generated + 1))
    folder_had_new=1
  fi

  # ── reviewer.md ────────────────────────────────────────────
  reviewer_file="$dir/reviewer.md"
  if [ -f "$reviewer_file" ]; then
    echo "SKIP (exists): $folder/reviewer.md"
    skipped=$((skipped + 1))
  else
    cat > "$reviewer_file" <<EOF
# ${title_zh} — 審查清單 / ${title_en} — Review Checklist
## 結構性檢查
- [ ] Frontmatter 完整
- [ ] document_id 正確: ${doc_id}
- [ ] zh-TW 與 en 版本結構一致
- [ ] 交叉引用使用 document_id
- [ ] 無殘留 TBD / TODO / FIXME
## 內容檢查
- [ ] 符合 rule.md 定義的必要章節
- [ ] 標準控制項對應正確
## 合規性檢查
- [ ] 組織名稱、核准人已填入
- [ ] change_history 記錄完整
EOF
    echo "GENERATED: $folder/reviewer.md"
    generated=$((generated + 1))
    folder_had_new=1
  fi

  if [ "$folder_had_new" -eq 1 ]; then
    NEW_FOLDERS="$NEW_FOLDERS $folder|$doc_id|$type_prefix"
  fi

done

# Output pending-scaffolding.json
PENDING_FILE="$PROJECT_ROOT/pending-scaffolding.json"

if [ -n "$NEW_FOLDERS" ]; then
  STUBS_JSON="["
  first=1
  for entry in $NEW_FOLDERS; do
    f_name=$(echo "$entry" | cut -d'|' -f1)
    f_id=$(echo "$entry" | cut -d'|' -f2)
    f_type=$(echo "$entry" | cut -d'|' -f3)
    [ "$first" -eq 0 ] && STUBS_JSON="$STUBS_JSON,"
    STUBS_JSON="$STUBS_JSON{\"folder\":\"$f_name\",\"document_id\":\"$f_id\",\"type\":\"$f_type\"}"
    first=0
  done
  STUBS_JSON="$STUBS_JSON]"

  cat > "$PENDING_FILE" << EOFPENDING
{
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "new_stubs": $STUBS_JSON,
  "total_new": $(echo "$NEW_FOLDERS" | wc -w | tr -d ' '),
  "message": "Run audit.sh + review-completeness.sh to trigger AI completion."
}
EOFPENDING
  echo ""
  echo "Pending scaffolding written to: $PENDING_FILE"
fi

echo ""
echo "============================="
echo "Generated : $generated"
echo "Skipped   : $skipped"
echo "============================="
