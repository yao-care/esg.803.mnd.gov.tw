#!/bin/bash
# Knowledge Body Document Audit — automated document compliance checks
# Each check is tagged with its source rule for annual audit verification.
set -e

OUTPUT_DIR="${1:-.}"
mkdir -p "$OUTPUT_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"
KB_DIR="$PROJECT_ROOT/$DOCUMENTS_PATH"

PASS=0
FAIL=0
WARN=0
CHECKS_JSON=""

add_check() {
  local id="$1" name="$2" status="$3" detail="$4" ref="$5"
  if [ "$status" = "pass" ]; then PASS=$((PASS+1))
  elif [ "$status" = "fail" ]; then FAIL=$((FAIL+1))
  else WARN=$((WARN+1)); fi

  # Build JSON (escape quotes in detail)
  detail=$(echo "$detail" | sed 's/"/\\"/g' | head -1)
  [ -n "$CHECKS_JSON" ] && CHECKS_JSON="$CHECKS_JSON,"
  CHECKS_JSON="$CHECKS_JSON
    {\"id\": \"$id\", \"name\": \"$name\", \"status\": \"$status\", \"detail\": \"$detail\", \"ref\": \"$ref\"}"
}

echo "========================================"
echo "  ${KB_NAME_EN} Document Audit"
echo "========================================"
echo ""

# --- G1. Frontmatter completeness ---
echo "[G1] Checking frontmatter..."
MISSING_FM=0
while IFS= read -r f; do
  if ! head -1 "$f" | grep -q "^---"; then
    MISSING_FM=$((MISSING_FM+1))
    echo "  FAIL: $f"
  fi
done < <(find "$KB_DIR" -name "*.md" \
  -not -path "*/_meta/*" \
  -not -name "CLAUDE.md" -not -name "README.md" -not -name "REVIEWER.md" \
  -not -name "rule.md" -not -name "writer.md" -not -name "reviewer.md")
add_check "G1" "Frontmatter completeness" \
  "$([ "$MISSING_FM" -eq 0 ] && echo pass || echo fail)" \
  "$MISSING_FM files without frontmatter" \
  "knowledge/CLAUDE.md G1"

# --- G2. Bilingual parity (if applicable) ---
echo "[G2] Checking bilingual parity..."
G2_FAIL=0
while IFS= read -r d; do
  folder_name="$(basename "$d")"
  zh_count=$(find "$d" -maxdepth 1 -name "*.md" \
    -not -name "*.en.md" \
    -not -name "CLAUDE.md" -not -name "rule.md" \
    -not -name "writer.md" -not -name "reviewer.md" 2>/dev/null | wc -l | tr -d ' ')
  en_count=$(find "$d" -maxdepth 1 -name "*.en.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$zh_count" != "$en_count" ]; then
    G2_FAIL=$((G2_FAIL+1))
    echo "  FAIL: $folder_name zh=$zh_count en=$en_count"
  fi
done < <(find "$KB_DIR" -mindepth 1 -maxdepth 1 -type d -not -path "*/_meta")
add_check "G2" "Bilingual parity" \
  "$([ "$G2_FAIL" -eq 0 ] && echo pass || echo fail)" \
  "$G2_FAIL directories with mismatch" \
  "knowledge/CLAUDE.md G2"

# --- G3. Document ID uniqueness ---
echo "[G3] Checking document ID uniqueness..."
DUPES=$(find "$KB_DIR" -name "*.md" \
  -not -path "*/_meta/*" \
  -not -name "CLAUDE.md" -not -name "README.md" -not -name "REVIEWER.md" \
  -not -name "rule.md" -not -name "writer.md" -not -name "reviewer.md" \
  -exec sh -c 'head -20 "$1" | grep "^document_id:"' _ {} \; 2>/dev/null \
  | sort | uniq -c | awk '$1 > 2' | wc -l | tr -d ' ')
add_check "G3" "Document ID uniqueness" \
  "$([ "$DUPES" -eq 0 ] && echo pass || echo fail)" \
  "$DUPES duplicate IDs (>2 occurrences)" \
  "knowledge/CLAUDE.md G3"

# --- G5. No stale placeholders ---
echo "[G5] Checking stale placeholders..."
STALE=$(grep -ri "TBD\|TODO\|\[待補\]\|FIXME" "$KB_DIR" --include="*.md" \
  --exclude-dir=_meta \
  | grep -v "CLAUDE.md" | grep -v "REVIEWER.md" \
  | grep -v "rule.md" | grep -v "writer.md" | grep -v "reviewer.md" \
  | wc -l | tr -d ' ')
add_check "G5" "No stale placeholders" \
  "$([ "$STALE" -eq 0 ] && echo pass || echo warn)" \
  "$STALE occurrences found" \
  "knowledge/CLAUDE.md G5"

# --- G6. Mermaid diagrams only ---
echo "[G6] Checking diagram format (Mermaid only)..."
ASCII_DIAGRAMS=0
while IFS= read -r f; do
  if grep -Pq '^\+[-=]+\+' "$f" 2>/dev/null; then
    ASCII_DIAGRAMS=$((ASCII_DIAGRAMS+1))
    echo "  WARN: ASCII diagram in $f"
  fi
done < <(find "$KB_DIR" -name "*.md" \
  -not -path "*/_meta/*" \
  -not -name "CLAUDE.md" -not -name "README.md" -not -name "REVIEWER.md" \
  -not -name "rule.md" -not -name "writer.md" -not -name "reviewer.md")
add_check "G6" "Diagrams use Mermaid (no ASCII)" \
  "$([ "$ASCII_DIAGRAMS" -eq 0 ] && echo pass || echo warn)" \
  "$ASCII_DIAGRAMS files with ASCII diagrams" \
  "knowledge/CLAUDE.md G6"

# --- MERGE1. merge.yaml validity ---
echo "[MERGE1] Checking ${METADATA_FILENAME} validity..."
MERGE_FAIL=0
while IFS= read -r d; do
  folder_name="$(basename "$d")"
  has_content=$(find "$d" -maxdepth 1 -name "*.md" \
    -not -name "CLAUDE.md" -not -name "rule.md" \
    -not -name "writer.md" -not -name "reviewer.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$has_content" -gt 0 ]; then
    if [ ! -f "$d/${METADATA_FILENAME}" ]; then
      MERGE_FAIL=$((MERGE_FAIL+1))
      echo "  FAIL: $folder_name — ${METADATA_FILENAME} missing"
    else
      missing_fields=""
      grep -q "^document_id:" "$d/${METADATA_FILENAME}" || missing_fields="$missing_fields document_id"
      grep -q "^title_zh:" "$d/${METADATA_FILENAME}" || missing_fields="$missing_fields title_zh"
      grep -q "^title_en:" "$d/${METADATA_FILENAME}" || missing_fields="$missing_fields title_en"
      if [ -n "$missing_fields" ]; then
        MERGE_FAIL=$((MERGE_FAIL+1))
        echo "  FAIL: $folder_name — missing fields:$missing_fields"
      fi
    fi
  fi
done < <(find "$KB_DIR" -mindepth 1 -maxdepth 1 -type d -not -path "*/_meta")
add_check "MERGE1" "${METADATA_FILENAME} validity" \
  "$([ "$MERGE_FAIL" -eq 0 ] && echo pass || echo fail)" \
  "$MERGE_FAIL folders with missing or invalid ${METADATA_FILENAME}" \
  "knowledge/CLAUDE.md"

# --- META-1. _meta/types/ templates ---
echo "[META-1] Checking _meta/types/..."
META1_MISSING=0
META1_LIST=""
if [ -d "$KB_DIR/_meta/types" ]; then
  EXPECTED_TYPES=$(ls "$KB_DIR/_meta/types/"*.md 2>/dev/null | xargs -I{} basename {} .md | tr '\n' ' ')
  for t in $EXPECTED_TYPES; do
    if [ ! -f "$KB_DIR/_meta/types/$t.md" ]; then
      META1_MISSING=$((META1_MISSING+1))
      META1_LIST="$META1_LIST $t"
    fi
  done
fi
add_check "META-1" "Meta type templates" \
  "$([ "$META1_MISSING" -eq 0 ] && echo pass || echo fail)" \
  "$META1_MISSING missing:$META1_LIST" \
  "_meta/types/"

# --- META-3. _meta/ root files ---
echo "[META-3] Checking _meta/ root files..."
META3_MISSING=0
META3_LIST=""
for f in rule.md writer.md reviewer.md; do
  if [ ! -f "$KB_DIR/_meta/$f" ]; then
    META3_MISSING=$((META3_MISSING+1))
    META3_LIST="$META3_LIST $f"
  fi
done
add_check "META-3" "Meta root files" \
  "$([ "$META3_MISSING" -eq 0 ] && echo pass || echo fail)" \
  "$META3_MISSING of 3 missing:$META3_LIST" \
  "_meta/"

# --- RC-1. rule.md exists ---
echo "[RC-1] Checking rule.md exists..."
RC1_MISSING=0
while IFS= read -r d; do
  folder_name="$(basename "$d")"
  [ "$folder_name" = "_meta" ] && continue
  if [ ! -f "$d/rule.md" ]; then
    RC1_MISSING=$((RC1_MISSING+1))
  fi
done < <(find "$KB_DIR" -mindepth 1 -maxdepth 1 -type d)
add_check "RC-1" "rule.md exists" \
  "$([ "$RC1_MISSING" -eq 0 ] && echo pass || echo fail)" \
  "$RC1_MISSING folders missing rule.md" \
  "_meta/reviewer.md"

# --- RC-2. rule.md non-stub ---
echo "[RC-2] Checking rule.md non-stub..."
RC2_STUB=0; RC2_TOTAL=0
while IFS= read -r d; do
  folder_name="$(basename "$d")"
  [ "$folder_name" = "_meta" ] && continue
  [ ! -f "$d/rule.md" ] && continue
  RC2_TOTAL=$((RC2_TOTAL+1))
  IS_STUB=0
  grep -qi '待補充\|TBD\|TODO\|FIXME' "$d/rule.md" 2>/dev/null && IS_STUB=1
  if [ "$IS_STUB" -eq 0 ]; then
    grep -q '【必要】' "$d/rule.md" 2>/dev/null || IS_STUB=1
  fi
  [ "$IS_STUB" -eq 1 ] && RC2_STUB=$((RC2_STUB+1))
done < <(find "$KB_DIR" -mindepth 1 -maxdepth 1 -type d)
add_check "RC-2" "rule.md non-stub" \
  "$([ "$RC2_STUB" -eq 0 ] && echo pass || echo warn)" \
  "$RC2_STUB of $RC2_TOTAL folders have stub rule.md" \
  "_meta/reviewer.md"

# --- RC-3. writer.md non-stub ---
echo "[RC-3] Checking writer.md non-stub..."
RC3_STUB=0; RC3_TOTAL=0
while IFS= read -r d; do
  folder_name="$(basename "$d")"
  [ "$folder_name" = "_meta" ] && continue
  [ ! -f "$d/writer.md" ] && continue
  RC3_TOTAL=$((RC3_TOTAL+1))
  IS_STUB=0
  grep -qi '待補充\|TBD\|TODO\|FIXME' "$d/writer.md" 2>/dev/null && IS_STUB=1
  if [ "$IS_STUB" -eq 0 ]; then
    grep -qi 'rule\.md' "$d/writer.md" 2>/dev/null || IS_STUB=1
  fi
  [ "$IS_STUB" -eq 1 ] && RC3_STUB=$((RC3_STUB+1))
done < <(find "$KB_DIR" -mindepth 1 -maxdepth 1 -type d)
add_check "RC-3" "writer.md non-stub" \
  "$([ "$RC3_STUB" -eq 0 ] && echo pass || echo warn)" \
  "$RC3_STUB of $RC3_TOTAL folders have stub writer.md" \
  "_meta/reviewer.md"

# --- RC-5. reviewer.md aligned with rule.md ---
echo "[RC-5] Checking reviewer.md alignment..."
RC5_MISALIGNED=0; RC5_TOTAL=0
while IFS= read -r d; do
  folder_name="$(basename "$d")"
  [ "$folder_name" = "_meta" ] && continue
  [ ! -f "$d/rule.md" ] || [ ! -f "$d/reviewer.md" ] && continue
  RULE_COUNT=$(grep -c '【必要】' "$d/rule.md" 2>/dev/null | tr -d ' \n' || true)
  RULE_COUNT="${RULE_COUNT:-0}"
  [ "$RULE_COUNT" -eq 0 ] && continue
  RC5_TOTAL=$((RC5_TOTAL+1))
  CB_COUNT=$(grep -c '^\- \[ \]' "$d/reviewer.md" 2>/dev/null | tr -d ' \n' || true)
  CB_COUNT="${CB_COUNT:-0}"
  if [ "$CB_COUNT" -lt "$RULE_COUNT" ]; then
    RC5_MISALIGNED=$((RC5_MISALIGNED+1))
  fi
done < <(find "$KB_DIR" -mindepth 1 -maxdepth 1 -type d)
add_check "RC-5" "reviewer.md aligned with rule.md" \
  "$([ "$RC5_MISALIGNED" -eq 0 ] && echo pass || echo warn)" \
  "$RC5_MISALIGNED of $RC5_TOTAL folders misaligned" \
  "_meta/reviewer.md"

# --- RC-7. Document content compliant ---
echo "[RC-7] Checking document content compliance..."
RC7_NONCOMPLIANT=0; RC7_TOTAL=0
while IFS= read -r d; do
  folder_name="$(basename "$d")"
  [ "$folder_name" = "_meta" ] && continue
  [ ! -f "$d/rule.md" ] || [ ! -f "$d/${METADATA_FILENAME}" ] && continue
  MAIN_ZH=$(grep -A1 '^main:' "$d/${METADATA_FILENAME}" | grep 'zh:' | sed 's/.*zh:[[:space:]]*//' | tr -d "\"'" | tr -d '\r')
  [ -z "$MAIN_ZH" ] && continue
  MAIN_DOC="$d/$MAIN_ZH"
  [ ! -f "$MAIN_DOC" ] && continue
  STATUS=$(head -20 "$MAIN_DOC" | grep "^status:" | sed 's/^status:[[:space:]]*//' | tr -d "\"'" | tr -d '\r')
  case "$STATUS" in
    review|approved) ;;
    *) continue ;;
  esac
  RC7_TOTAL=$((RC7_TOTAL+1))
  RULE_SECTIONS=$(grep '^[0-9]' "$d/rule.md" 2>/dev/null | grep '【必要】' || true)
  [ -z "$RULE_SECTIONS" ] && continue
  MISSING_SECTIONS=0
  while IFS= read -r req; do
    SECTION_NAME=$(echo "$req" | sed 's/.*【必要】[[:space:]]*//' | tr -d '*' | sed 's/[[:space:]]*[—:：（].*//')
    [ -z "$SECTION_NAME" ] && continue
    FOUND=1
    for kw in $SECTION_NAME; do
      [ ${#kw} -le 1 ] && continue
      grep -qi "$kw" "$MAIN_DOC" 2>/dev/null || { FOUND=0; break; }
    done
    [ "$FOUND" -eq 0 ] && MISSING_SECTIONS=$((MISSING_SECTIONS+1))
  done <<< "$RULE_SECTIONS"
  [ "$MISSING_SECTIONS" -gt 0 ] && RC7_NONCOMPLIANT=$((RC7_NONCOMPLIANT+1))
done < <(find "$KB_DIR" -mindepth 1 -maxdepth 1 -type d)
add_check "RC-7" "Document content compliant" \
  "$([ "$RC7_NONCOMPLIANT" -eq 0 ] && echo pass || echo warn)" \
  "$RC7_NONCOMPLIANT of $RC7_TOTAL review/approved docs non-compliant" \
  "_meta/reviewer.md"

# --- Pipeline integrity ---
echo "[PIPE] Checking script syntax..."
PIPE_FAIL=0
for s in scripts/collectors/*.sh scripts/report/*.sh scripts/review/*.sh scripts/entrypoint.sh; do
  if [ -f "$PROJECT_ROOT/$s" ]; then
    if ! bash -n "$PROJECT_ROOT/$s" 2>/dev/null; then
      PIPE_FAIL=$((PIPE_FAIL+1))
      echo "  FAIL: $s"
    fi
  fi
done
add_check "PIPE" "Script syntax validation" \
  "$([ "$PIPE_FAIL" -eq 0 ] && echo pass || echo fail)" \
  "$PIPE_FAIL scripts with syntax errors" \
  "pipeline integration"

# --- File counts ---
TOTAL_FILES=$(find "$KB_DIR" -name "*.md" \
  -not -path "*/_meta/*" \
  -not -name "CLAUDE.md" -not -name "README.md" -not -name "REVIEWER.md" \
  -not -name "rule.md" -not -name "writer.md" -not -name "reviewer.md" \
  | wc -l | tr -d ' ')

# --- Output JSON ---
TOTAL=$((PASS+FAIL+WARN))
cat > "$OUTPUT_DIR/audit-result.json" << EOFRESULT
{
  "status": "completed",
  "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "tool": "knowledge-audit",
  "knowledge_body": "${KB_NAME_EN}",
  "summary": {
    "pass": $PASS,
    "fail": $FAIL,
    "warn": $WARN,
    "total": $TOTAL,
    "kb_files": $TOTAL_FILES
  },
  "checks": [$CHECKS_JSON
  ]
}
EOFRESULT

echo ""
echo "========================================"
echo "  Audit Results"
echo "========================================"
echo "PASS: $PASS  FAIL: $FAIL  WARN: $WARN  Total: $TOTAL"
echo "KB files: $TOTAL_FILES"
echo "Report: $OUTPUT_DIR/audit-result.json"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Non-conformities found. See audit-result.json for details."
fi

# Trigger completeness review if available
if [ -f "$PROJECT_ROOT/scripts/knowledge/review-completeness.sh" ]; then
  echo ""
  echo "Running completeness review..."
  "$PROJECT_ROOT/scripts/knowledge/review-completeness.sh" "$OUTPUT_DIR" || true
fi
