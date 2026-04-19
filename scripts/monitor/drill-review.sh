#!/bin/bash
# scripts/monitor/drill-review.sh — AI review of drill comments
# Usage: drill-review.sh <issue_number> <comment_id> <comment_body> <comment_author>
#
# Phase 1: Rule-based format checks
# Phase 2: LLM content review (requires claude CLI)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

ISSUE_NUMBER="$1"
COMMENT_ID="$2"
COMMENT_BODY="$3"
COMMENT_AUTHOR="$4"

if [ -z "$ISSUE_NUMBER" ] || [ -z "$COMMENT_BODY" ]; then
  echo "Usage: drill-review.sh <issue_number> <comment_id> <comment_body> <comment_author>" >&2
  exit 1
fi

ISSUES=()
SUGGESTIONS=()
PASS=true

# === Phase 1: Format Checks (rule-based) ===

# Check 1: Has step number
if ! echo "$COMMENT_BODY" | grep -q '^\*\*步驟\*\*:'; then
  ISSUES+=("請標明這是哪個步驟的回報（格式：**步驟**: N — 步驟名稱）")
  PASS=false
fi

# Check 2: Has result field
if echo "$COMMENT_BODY" | grep -q '^\*\*步驟\*\*:' && ! echo "$COMMENT_BODY" | grep -q '^\*\*結果\*\*:'; then
  ISSUES+=("請填寫執行結果（格式：**結果**: 描述執行情況）")
  PASS=false
fi

# Check 3: Result not empty
RESULT_TEXT=$(echo "$COMMENT_BODY" | sed -n 's/^\*\*結果\*\*: *//p')
if [ -n "$RESULT_TEXT" ] && [ "${#RESULT_TEXT}" -lt 10 ]; then
  ISSUES+=("結果描述過於簡略（${#RESULT_TEXT} 字），請補充具體執行情況")
  PASS=false
fi

# Check 4: Step requires attachment but none found
STEP_NUM=$(echo "$COMMENT_BODY" | sed -n 's/^\*\*步驟\*\*: *\([^ ]*\).*/\1/p')
# Get issue body to check if this step needs attachment
if command -v gh &>/dev/null && [ -n "$STEP_NUM" ]; then
  ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --json body -q '.body' 2>/dev/null || echo "")
  NEEDS_ATTACH=$(echo "$ISSUE_BODY" | grep -c "| *${STEP_NUM} .*是" 2>/dev/null || echo "0")
  HAS_ATTACH=$(echo "$COMMENT_BODY" | grep -c -E '!\[|\.png|\.jpg|\.pdf|\.zip' 2>/dev/null || echo "0")
  if [ "$NEEDS_ATTACH" -gt 0 ] && [ "$HAS_ATTACH" -eq 0 ]; then
    ISSUES+=("此步驟需要附件佐證（截圖/文件），請補上傳")
    PASS=false
  fi
fi

# === Phase 2: LLM Content Review ===
if [ "$PASS" = "true" ] && command -v claude &>/dev/null; then
  AI_RESULT=$(claude -p "$(cat << PROMPT
你是 ISMS 演練審核員。請審核以下演練步驟回報，輸出 JSON：

【回報內容】
${COMMENT_BODY}

請檢查：
1. 回報內容是否與步驟要求吻合（有沒有答非所問）
2. 時序是否合理
3. 是否有遺漏關鍵資訊（影響範圍、受影響系統、通知對象等）

僅輸出 JSON，不要其他文字：
{"pass": true/false, "issues": ["問題"], "suggestions": ["建議"]}
PROMPT
)" 2>/dev/null || echo '{"pass": true, "issues": [], "suggestions": []}')

  AI_PASS=$(echo "$AI_RESULT" | jq -r '.pass // true' 2>/dev/null || echo "true")
  if [ "$AI_PASS" = "false" ]; then
    PASS=false
    while IFS= read -r issue; do
      ISSUES+=("$issue")
    done < <(echo "$AI_RESULT" | jq -r '.issues[]?' 2>/dev/null)
    while IFS= read -r suggestion; do
      SUGGESTIONS+=("$suggestion")
    done < <(echo "$AI_RESULT" | jq -r '.suggestions[]?' 2>/dev/null)
  fi
fi

# === Output Result ===
if [ "$PASS" = "true" ]; then
  REPLY="✅ 步驟 ${STEP_NUM} 回報已確認（$(date -u '+%Y-%m-%dT%H:%M:%SZ') by @${COMMENT_AUTHOR}）"
  if [ ${#SUGGESTIONS[@]} -gt 0 ]; then
    REPLY="${REPLY}\n\n📝 建議："
    for s in "${SUGGESTIONS[@]}"; do
      REPLY="${REPLY}\n- ${s}"
    done
  fi
else
  REPLY="⚠️ AI 審核發現以下問題：\n"
  for i in "${!ISSUES[@]}"; do
    REPLY="${REPLY}\n$((i+1)). ${ISSUES[$i]}"
  done
  if [ ${#SUGGESTIONS[@]} -gt 0 ]; then
    REPLY="${REPLY}\n\n📝 建議補充："
    for s in "${SUGGESTIONS[@]}"; do
      REPLY="${REPLY}\n- ${s}"
    done
  fi
  REPLY="${REPLY}\n\n請修正後重新回報此步驟。"
fi

# Post reply as Issue comment
if command -v gh &>/dev/null; then
  echo -e "$REPLY" | gh issue comment "$ISSUE_NUMBER" --body-file - 2>/dev/null || echo "$REPLY"

  # If passed, update Issue body: change step status ⏳ → ✅
  if [ "$PASS" = "true" ] && [ -n "$STEP_NUM" ]; then
    CURRENT_BODY=$(gh issue view "$ISSUE_NUMBER" --json body -q '.body' 2>/dev/null || echo "")
    if [ -n "$CURRENT_BODY" ]; then
      UPDATED_BODY=$(echo "$CURRENT_BODY" | sed "s/| ${STEP_NUM} |\\(.*\\)| ⏳ |/| ${STEP_NUM} |\\1| ✅ |/")
      gh issue edit "$ISSUE_NUMBER" --body "$UPDATED_BODY" 2>/dev/null || true
    fi
  fi
else
  echo -e "$REPLY"
fi

# Exit with status
[ "$PASS" = "true" ] && exit 0 || exit 1
