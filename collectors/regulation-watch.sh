#!/bin/bash
# regulation-watch.sh
# 法規異動監控骨架腳本（預設停用，config.json 中 enabled: false）
# 每週一執行（內建排程守衛）
# 監控 EPA / MOEA 相關法規頁面，偵測新發布或修正條文

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------- 排程守衛：僅在週一執行（date +%u：1=Monday）----------
DAY_OF_WEEK="$(date +%u)"
if [[ "$DAY_OF_WEEK" != "1" ]]; then
  echo "regulation-watch.sh: today is not Monday (weekday=$DAY_OF_WEEK). Skipping."
  exit 0
fi

echo "regulation-watch.sh: running weekly regulation watch check."
echo "NOTE: This is a skeleton script. Actual checks are marked with TODO."

# ---------- 監控目標 URL ----------
# TODO: 確認實際監控頁面後填入
EPA_URLS=(
  # "https://oaquery.epa.gov.tw/"        # 環境部法規查詢
  # "https://law.epa.gov.tw/law/"        # 環境部法令專區
)
MOEA_URLS=(
  # "https://law.moea.gov.tw/"           # 經濟部法規
)

CACHE_DIR="$PROJECT_DIR/data/regulation-watch"
mkdir -p "$CACHE_DIR"

# ---------- Step 1: 抓取目標頁面 ----------
# TODO: implement when real data flows in
# 使用 curl 抓取各 URL 內容，儲存為暫存檔
#
# for url in "${EPA_URLS[@]}" "${MOEA_URLS[@]}"; do
#   slug="$(echo "$url" | sed 's|[^a-zA-Z0-9]|_|g')"
#   curl -sSL "$url" -o "$CACHE_DIR/${slug}.new.html" 2>/dev/null
# done
echo "[Step 1] TODO: 抓取 EPA / MOEA 法規頁面內容"

# ---------- Step 2: 與上次快取比對 ----------
# TODO: implement when real data flows in
# 比對新舊快取差異（diff 或 hash 比較）
# 僅輸出有變動的 URL 及差異摘要
#
# for url in "${EPA_URLS[@]}" "${MOEA_URLS[@]}"; do
#   slug="$(echo "$url" | sed 's|[^a-zA-Z0-9]|_|g')"
#   OLD="$CACHE_DIR/${slug}.last.html"
#   NEW="$CACHE_DIR/${slug}.new.html"
#   if [[ -f "$OLD" ]]; then
#     DIFF="$(diff "$OLD" "$NEW")"
#     if [[ -n "$DIFF" ]]; then
#       echo "CHANGED: $url"
#       # TODO: 擷取新增條文標題或修正日期
#     fi
#   fi
#   cp "$NEW" "$OLD"
# done
echo "[Step 2] TODO: 與上次快取比對，輸出異動項目"

# ---------- Step 3: 輸出新增或修正條文 ----------
# TODO: implement when real data flows in
# 輸出格式：
# NEW_REG | 法規名稱 | 發布日期 | URL
# MOD_REG | 法規名稱 | 修正日期 | URL
echo "[Step 3] TODO: 輸出新增/修正法規清單"

# ---------- Step 4: 若有異動，寫入 data/reports/ 供後續審查 ----------
# TODO: implement when real data flows in
# REPORT_FILE="$PROJECT_DIR/data/reports/regulation-watch-$(date +%Y%m%d).txt"
# echo "$CHANGES" > "$REPORT_FILE"
echo "[Step 4] TODO: 將異動清單寫入 data/reports/"

echo "regulation-watch.sh: skeleton run complete. No real URLs configured."
exit 0
