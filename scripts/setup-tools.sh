#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export PROJECT_ROOT

source "$SCRIPT_DIR/lib/shell-config.sh"

echo "Installing Node dependencies..."
npm --prefix "$PROJECT_ROOT" ci

# Additional tool setup is added here by the wizard when collectors require
# specific CLI tools (e.g., trivy, semgrep, nikto).

echo ""
echo "Setup complete."
