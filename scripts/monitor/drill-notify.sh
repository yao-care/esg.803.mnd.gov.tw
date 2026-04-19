#!/bin/bash
# scripts/monitor/drill-notify.sh — Drill scheduling & notification
# Usage: drill-notify.sh <projects_json_file>
#
# Checks each project's next_drill_date and:
# - Creates GitHub Issue when drill is 7 days away
# - Sends email notifications at configured intervals
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source shell config for path resolution
source "$PROJECT_ROOT/scripts/lib/shell-config.sh" 2>/dev/null || true

# Default projects file path from config or fallback
PROJECTS_FILE_DEFAULT=$(cfg 'paths.projects_config' 'configs/projects.json' 2>/dev/null || echo "configs/projects.json")
PROJECTS_FILE="${1:-$PROJECT_ROOT/$PROJECTS_FILE_DEFAULT}"

if [ ! -f "$PROJECTS_FILE" ]; then
  echo "Error: Projects file not found: $PROJECTS_FILE" >&2
  exit 1
fi

TODAY=$(date -u '+%Y-%m-%d')
NOW_EPOCH=$(date -u '+%s')

# Parse date to epoch (cross-platform)
date_to_epoch() {
  local dt="$1"
  if date -jf '%Y-%m-%d' "$dt" '+%s' >/dev/null 2>&1; then
    date -jf '%Y-%m-%d' "$dt" '+%s'
  else
    date -d "$dt" '+%s' 2>/dev/null || echo "0"
  fi
}

days_until() {
  local target_epoch
  target_epoch=$(date_to_epoch "$1")
  echo $(( (target_epoch - NOW_EPOCH) / 86400 ))
}

jq -c '.[]' "$PROJECTS_FILE" | while read -r project; do
  NAME=$(echo "$project" | jq -r '.name')
  NEXT_DRILL=$(echo "$project" | jq -r '.monitor.drill.next_drill_date // empty' 2>/dev/null)

  [ -z "$NEXT_DRILL" ] && continue

  DAYS_LEFT=$(days_until "$NEXT_DRILL")
  NOTIFY_DAYS=$(echo "$project" | jq -r '.monitor.drill.notify_days_before // [30,7,1] | .[]' 2>/dev/null)
  DRILL_TYPE=$(echo "$project" | jq -r '.monitor.drill.type // "incident-response"' 2>/dev/null)

  for notify_day in $NOTIFY_DAYS; do
    if [ "$DAYS_LEFT" -eq "$notify_day" ]; then
      echo "[$NAME] Drill in $DAYS_LEFT days ($NEXT_DRILL)"

      # At 7 days: create GitHub Issue
      if [ "$notify_day" -eq 7 ]; then
        TEMPLATE_FILE="$SCRIPT_DIR/drills/${DRILL_TYPE}.md"
        if [ ! -f "$TEMPLATE_FILE" ]; then
          echo "  WARNING: Template not found: $TEMPLATE_FILE" >&2
          continue
        fi

        # Build Issue body from template
        CONTACTS=$(echo "$project" | jq -r '.monitor.drill.contacts[]? | "- @" + .name + " (" + .role + ")"' 2>/dev/null)

        # Parse template to build step table
        STEPS=""
        STEP_NUM=0
        while IFS='|' read -r _ num step role timeslot attachment _; do
          num=$(echo "$num" | xargs)
          step=$(echo "$step" | xargs)
          role=$(echo "$role" | xargs)
          [ -z "$num" ] || [ "$num" = "#" ] && continue
          STEP_NUM=$((STEP_NUM + 1))
          STEPS="${STEPS}| ${num} | ${step} | ${role} | ${timeslot:-—} | ⏳ |\n"
        done < <(grep '^|' "$TEMPLATE_FILE" | grep -v '^| #\|^|---')

        ISSUE_BODY="# [演練] $(head -1 "$TEMPLATE_FILE" | sed 's/^# //') — ${NAME} (${NEXT_DRILL})

**類型**: ${DRILL_TYPE}
**參與人員**:
${CONTACTS}

## 演練步驟

| # | 步驟 | 負責人 | 時間窗 | 狀態 |
|---|------|--------|--------|------|
$(echo -e "$STEPS")

---
👇 請依步驟編號逐一以 comment 回報，格式：

\`\`\`
**步驟**: <編號> — <步驟名稱>
**結果**: （描述執行情況）
**附件**: （截圖或文件，直接拖曳上傳）
\`\`\`"

        ISSUE_TITLE="[演練] ${DRILL_TYPE} — ${NAME} (${NEXT_DRILL})"

        # Create issue with label
        if command -v gh &>/dev/null; then
          gh issue create \
            --title "$ISSUE_TITLE" \
            --body "$ISSUE_BODY" \
            --label "drill" 2>/dev/null && echo "  Created GitHub Issue" || echo "  Failed to create Issue"
        else
          echo "  gh CLI not available — skipping Issue creation"
        fi
      fi

      # Send notification email
      EMAILS=$(echo "$project" | jq -r '.monitor.drill.contacts[]?.email // empty' 2>/dev/null | paste -sd ',' -)
      if [ -n "$EMAILS" ]; then
        DRILL_TYPE=$(echo "$project" | jq -r '.monitor.drill.type // "incident-response"' 2>/dev/null)
        SUBJECT="[演練通知] ${DRILL_TYPE} — ${NAME} (${NEXT_DRILL}) — ${DAYS_LEFT} 天後"

        # Generate simple HTML email body
        EMAIL_BODY="<html><body>
<h2>演練預告通知</h2>
<p>專案：<strong>${NAME}</strong></p>
<p>演練類型：<strong>${DRILL_TYPE}</strong></p>
<p>預定日期：<strong>${NEXT_DRILL}</strong>（${DAYS_LEFT} 天後）</p>
<p>請依照演練步驟文件做好前置準備。</p>
</body></html>"

        # Send via notify/send-email.py
        SEND_SCRIPT="$PROJECT_ROOT/scripts/notify/send-email.py"
        if [ -f "$SEND_SCRIPT" ]; then
          echo "$EMAIL_BODY" | python3 "$SEND_SCRIPT" \
            --to "$EMAILS" \
            --subject "$SUBJECT" \
            --body-file - 2>/dev/null && echo "  Sent notification to: $EMAILS" || echo "  Failed to send email"
        else
          echo "  send-email.py not found — skipping email"
        fi
      fi
    fi
  done
done
