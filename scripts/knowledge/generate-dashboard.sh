#!/bin/bash
# Generate knowledge document listing index.html
# Usage: generate-dashboard.sh <output-dir> <documents-dir>
set -e

OUTPUT_DIR="$1"
DOCS_DIR="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

OKLCH_STYLES=$(cat "$PROJECT_ROOT/templates/styles.css")

CORE_ROWS=""
APPENDIX_ROWS=""

for folder in "$DOCS_DIR"/*/; do
  [ ! -d "$folder" ] && continue
  [ ! -f "$folder/$METADATA_FILENAME" ] && continue

  bname=$(basename "$folder")
  doc_id=$(grep "^document_id:" "$folder/$METADATA_FILENAME" | sed 's/^document_id: *//')
  title_zh=$(grep "^title_zh:" "$folder/$METADATA_FILENAME" | sed 's/^title_zh: *//')
  title_en=$(grep "^title_en:" "$folder/$METADATA_FILENAME" | sed 's/^title_en: *//')

  type_prefix=$(echo "$doc_id" | sed 's/-[0-9]*//')
  is_core=false
  [[ "$bname" =~ ^[0-9]{2}- ]] && is_core=true

  # Get version/status from main .md
  main_zh=$(grep "^  zh:" "$folder/$METADATA_FILENAME" | sed 's/^  zh: *//')
  version="—"; status="—"
  if [ -f "$folder/$main_zh" ]; then
    version=$(grep "^version:" "$folder/$main_zh" | head -1 | sed 's/^version: *//; s/"//g')
    status=$(grep "^status:" "$folder/$main_zh" | head -1 | sed 's/^status: *//')
  fi

  last_mod=$(git log -1 --format='%ai' -- "$folder" 2>/dev/null | cut -d' ' -f1 || echo "—")

  case "$status" in
    approved) badge='<span style="background:#e8fcf0;color:#1e8050;padding:2px 8px;border-radius:4px;font-size:14px;font-weight:700;">APPROVED</span>' ;;
    draft)    badge='<span style="background:#fcf5e8;color:#8a7020;padding:2px 8px;border-radius:4px;font-size:14px;font-weight:700;">DRAFT</span>' ;;
    review)   badge='<span style="background:#e8f0fc;color:#2a6bb8;padding:2px 8px;border-radius:4px;font-size:14px;font-weight:700;">REVIEW</span>' ;;
    *)        badge="<span style=\"font-size:14px;\">$status</span>" ;;
  esac

  link_dir="documents"
  [ "$type_prefix" = "FRM" ] && link_dir="forms"

  row="<tr style=\"border-bottom:1px solid #dfe0e5;\"><td style=\"padding:10px 14px;\"><a href=\"$link_dir/$bname/index.html\" style=\"color:#2a6bb8;text-decoration:none;font-weight:600;\">$doc_id</a></td><td style=\"padding:10px 14px;\">$title_zh<br><span style=\"color:#8a8c98;font-size:14px;\">$title_en</span></td><td style=\"padding:10px 14px;text-align:center;\">v$version</td><td style=\"padding:10px 14px;text-align:center;\">$badge</td><td style=\"padding:10px 14px;text-align:center;color:#8a8c98;\">$last_mod</td></tr>"

  if [ "$is_core" = true ]; then
    CORE_ROWS="$CORE_ROWS$row"
  else
    APPENDIX_ROWS="$APPENDIX_ROWS$row"
  fi
done

TABLE_HEAD='<tr style="background:#dfe0e5;"><th style="padding:10px 14px;text-align:left;font-size:14px;font-weight:600;">ID</th><th style="padding:10px 14px;text-align:left;font-size:14px;font-weight:600;">文件名稱 Document</th><th style="padding:10px 14px;text-align:center;font-size:14px;font-weight:600;">版本</th><th style="padding:10px 14px;text-align:center;font-size:14px;font-weight:600;">狀態</th><th style="padding:10px 14px;text-align:center;font-size:14px;font-weight:600;">最後修改</th></tr>'

cat > "$OUTPUT_DIR/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${KB_NAME_EN} — 文件總覽</title>
<link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
<style>$OKLCH_STYLES</style>
</head>
<body style="background:#f5f6f8;color:#1e2030;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
<div style="max-width:1100px;margin:0 auto;padding:2rem;">

<div style="margin-bottom:2rem;">
  <div style="font-size:14px;color:#8a8c98;">${KB_ORG}</div>
  <h1 style="font-size:48px;font-weight:700;margin:0.25rem 0;">${KB_NAME_EN} 文件總覽</h1>
  <p style="font-size:20px;color:#5e6070;">${KB_NAME} — Document Library</p>
</div>

<h2 style="font-size:28px;font-weight:700;margin-bottom:1rem;border-bottom:2px solid #dfe0e5;padding-bottom:0.5rem;">核心文件 Core Documents</h2>
<table style="width:100%;border-collapse:collapse;margin-bottom:2rem;background:#ecedf0;border-radius:8px;overflow:hidden;">
$TABLE_HEAD
$CORE_ROWS
</table>

<h2 style="font-size:28px;font-weight:700;margin-bottom:1rem;border-bottom:2px solid #dfe0e5;padding-bottom:0.5rem;">附屬文件 Supporting Documents</h2>
<table style="width:100%;border-collapse:collapse;margin-bottom:2rem;background:#ecedf0;border-radius:8px;overflow:hidden;">
$TABLE_HEAD
$APPENDIX_ROWS
</table>

<div style="margin-top:2rem;padding:1.5rem;background:#ecedf0;border-radius:8px;text-align:center;">
  <a href="assistant.html" target="_blank" style="font-size:24px;font-weight:700;color:#1e5ab8;text-decoration:none;">$(cfg 'ui.assistant_title' 'AI 知識助理')</a>
  <p style="margin-top:0.5rem;font-size:16px;color:#5e6070;">AI 輔助的 Q&amp;A 與模擬評鑑演練</p>
</div>

<footer style="margin-top:3rem;padding-top:1rem;border-top:1px solid #dfe0e5;font-size:14px;color:#8a8c98;">
  ${KB_ORG} · 產出時間 Generated: $(date -u '+%Y-%m-%d %H:%M UTC')
</footer>
</div>
</body>
</html>
HTMLEOF

echo "Generated: $OUTPUT_DIR/index.html (document listing)"
