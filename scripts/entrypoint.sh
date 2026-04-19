#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
export PROJECT_ROOT

source "$SCRIPT_DIR/lib/shell-config.sh"

# 參數解析（支援環境變數或 CLI 參數，向下相容 scan-style 呼叫）
REPOS_JSON="${REPOS_JSON:-$1}"
WEB_URL="${WEB_URL:-$2}"
SCAN_DEPTH="${SCAN_DEPTH:-${3:-standard}}"
SKIP_SETUP="${SKIP_SETUP:-false}"

# 從 config.json 讀取 targets（優先使用環境變數）
HAS_TARGETS=false
if [ -n "$REPOS_JSON" ] || [ -n "$WEB_URL" ]; then
  HAS_TARGETS=true
else
  TARGET_COUNT=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}', 'utf8'));
    const t = c.targets || [];
    process.stdout.write(String(t.length));
  " 2>/dev/null || echo "0")
  if [ "$TARGET_COUNT" -gt 0 ]; then
    HAS_TARGETS=true
  fi
fi

# 從 config.json 讀取 collectors
HAS_COLLECTORS=false
COLLECTOR_COUNT=$(node -e "
  const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}', 'utf8'));
  const col = c.collectors || [];
  process.stdout.write(String(col.length));
" 2>/dev/null || echo "0")
if [ "$COLLECTOR_COUNT" -gt 0 ]; then
  HAS_COLLECTORS=true
fi

# 顯示設定
echo "========================================"
echo "  Knowledge Body — $KB_NAME_EN"
echo "========================================"
echo ""
echo "SKIP_SETUP:    $SKIP_SETUP"
echo "HAS_TARGETS:   $HAS_TARGETS"
echo "HAS_COLLECTORS: $HAS_COLLECTORS"
if [ -n "$REPOS_JSON" ]; then
  echo "REPOS_JSON:    $REPOS_JSON"
fi
if [ -n "$WEB_URL" ]; then
  echo "WEB_URL:       $WEB_URL"
fi
if [ -n "$SCAN_DEPTH" ]; then
  echo "SCAN_DEPTH:    $SCAN_DEPTH"
fi
echo ""

# 安裝工具（可跳過）
if [ "$SKIP_SETUP" != "true" ]; then
  echo "Installing tools..."
  "$SCRIPT_DIR/setup-tools.sh"
else
  echo "Skipping tool setup (SKIP_SETUP=true)"
fi
echo ""

# Clone targets（如有設定）
if [ "$HAS_TARGETS" = "true" ]; then
  echo "Cloning / updating targets..."
  export REPOS_JSON WEB_URL SCAN_DEPTH
  "$SCRIPT_DIR/clone-targets.sh"
  echo ""
fi

# 執行 collectors（如有設定）
if [ "$HAS_COLLECTORS" = "true" ]; then
  COLLECTORS_SCRIPT="$SCRIPT_DIR/collectors/run-all.sh"
  if [ -f "$COLLECTORS_SCRIPT" ]; then
    echo "Running collectors..."
    "$COLLECTORS_SCRIPT"
    echo ""
  else
    echo "Warning: collectors defined in config but $COLLECTORS_SCRIPT not found, skipping." >&2
  fi
fi

# 建置助理
echo "Building assistant..."
npm --prefix "$PROJECT_ROOT" run build:assistant

echo ""
echo "========================================"
echo "  Build completed — $KB_NAME_EN"
echo "========================================"
