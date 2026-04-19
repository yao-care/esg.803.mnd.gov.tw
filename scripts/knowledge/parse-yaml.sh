#!/bin/bash
# Parse YAML file to JSON using python3
# Usage: parse-yaml.sh <file.yaml>
# Output: JSON to stdout
set -e

if [ -z "$1" ] || [ ! -f "$1" ]; then
  echo "Usage: parse-yaml.sh <file.yaml>" >&2
  exit 1
fi

python3 -c "
import yaml, json, sys
with open(sys.argv[1], 'r') as f:
    data = yaml.safe_load(f)
print(json.dumps(data, ensure_ascii=False))
" "$1"
