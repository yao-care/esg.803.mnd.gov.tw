#!/bin/bash
# deadline-check.sh
# 讀取 knowledge/MTX-TIMELINE/milestones.yaml，檢查各里程碑距今天數
# 用法：bash collectors/deadline-check.sh [--days N]
# 預設：--days 30

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

MILESTONES_FILE="$PROJECT_DIR/knowledge/MTX-TIMELINE/milestones.yaml"

# ---------- 參數解析 ----------
DAYS=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      DAYS="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      shift
      ;;
  esac
done

if [[ ! -f "$MILESTONES_FILE" ]]; then
  echo "ERROR: milestones file not found: $MILESTONES_FILE" >&2
  exit 0
fi

# ---------- 今天的日期（秒數，用於比較）----------
TODAY_STR="$(date +%Y-%m-%d)"
# macOS 相容：date -j -f "%Y-%m-%d"；GNU date：date -d
_to_epoch() {
  local d="$1"
  if date --version >/dev/null 2>&1; then
    # GNU date
    date -d "$d" +%s 2>/dev/null
  else
    # macOS BSD date
    date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null
  fi
}

TODAY_EPOCH="$(_to_epoch "$TODAY_STR")"
SECONDS_PER_DAY=86400

# ---------- 解析 YAML（純 grep/awk，不依賴 yq）----------
# milestones.yaml 格式：每個項目以 "  - id:" 開頭，
# 後續行以 "    key: value" 呈現，直到下一個 "  - id:"
#
# 策略：逐行掃描，收集 id / name / due_date，
#       遇到新 id 或 EOF 時處理前一筆。

process_milestone() {
  local id="$1"
  local name="$2"
  local due="$3"

  # 跳過空 id
  [[ -z "$id" ]] && return

  # due_date 為 null 或空時跳過
  if [[ -z "$due" || "$due" == "null" ]]; then
    return
  fi

  local due_epoch
  due_epoch="$(_to_epoch "$due")"
  if [[ -z "$due_epoch" ]]; then
    echo "WARN: cannot parse date '$due' for $id" >&2
    return
  fi

  local diff_sec=$(( due_epoch - TODAY_EPOCH ))
  local diff_days=$(( diff_sec / SECONDS_PER_DAY ))

  if [[ $diff_days -lt 0 ]]; then
    echo "OVERDUE  | $id | $name | due=$due | overdue by $(( -diff_days )) day(s)"
  elif [[ $diff_days -le $DAYS ]]; then
    echo "UPCOMING | $id | $name | due=$due | in $diff_days day(s)"
  else
    echo "OK       | $id | $name | due=$due | in $diff_days day(s)"
  fi
}

# 讀取並解析
cur_id=""
cur_name=""
cur_due=""

while IFS= read -r line; do
  # 新里程碑開始（以兩個空格 + "- id:" 識別）
  if [[ "$line" =~ ^[[:space:]]*-[[:space:]]id:[[:space:]]*(.+)$ ]]; then
    # 處理上一筆
    process_milestone "$cur_id" "$cur_name" "$cur_due"
    # 重置
    cur_id="${BASH_REMATCH[1]}"
    cur_name=""
    cur_due=""
    continue
  fi

  if [[ "$line" =~ ^[[:space:]]+name:[[:space:]]*(.+)$ ]]; then
    cur_name="${BASH_REMATCH[1]}"
    continue
  fi

  if [[ "$line" =~ ^[[:space:]]+due_date:[[:space:]]*(.+)$ ]]; then
    cur_due="${BASH_REMATCH[1]}"
    continue
  fi
done < "$MILESTONES_FILE"

# 處理最後一筆
process_milestone "$cur_id" "$cur_name" "$cur_due"

exit 0
