#!/bin/bash
# Build assistant HTML from rendered knowledge documents + scan results
# Usage: build-assistant.sh <output-dir> <documents-dir>
set -e

OUTPUT_DIR="$1"
DOCUMENTS_DIR="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/shell-config.sh"

# Ensure dependencies
if [ ! -d "$PROJECT_ROOT/node_modules/minisearch" ]; then
  echo "Installing MiniSearch..."
  cd "$PROJECT_ROOT" && npm ci --production && cd -
fi

echo "Building assistant..."
node "$PROJECT_ROOT/scripts/lib/core/build.js" "$OUTPUT_DIR" "$DOCUMENTS_DIR"
