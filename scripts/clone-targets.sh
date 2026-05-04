#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export PROJECT_ROOT

source "$SCRIPT_DIR/lib/shell-config.sh"

WORK_DIR="$PROJECT_ROOT/.work"
mkdir -p "$WORK_DIR"

# 建立 authenticated clone URL（支援 PAT_TOKEN）
make_clone_url() {
  local url="$1"
  if [ -n "$PAT_TOKEN" ]; then
    # 插入 token 到 https:// 之後
    echo "$url" | sed "s|https://|https://${PAT_TOKEN}@|"
  else
    echo "$url"
  fi
}

# 從環境變數或 config.json 收集所有 repo URLs
collect_urls() {
  # 1. 環境變數 REPOS_JSON（向下相容）
  if [ -n "$REPOS_JSON" ]; then
    echo "$REPOS_JSON" | node -e "
      const chunks = [];
      process.stdin.on('data', d => chunks.push(d));
      process.stdin.on('end', () => {
        try {
          const arr = JSON.parse(chunks.join(''));
          if (Array.isArray(arr)) arr.forEach(u => console.log(u));
        } catch(e) {}
      });
    " 2>/dev/null
  fi

  # 2. config.json targets[].repos[]
  node -e "
    const c = JSON.parse(require('fs').readFileSync('${CONFIG_FILE}', 'utf8'));
    const targets = c.targets || [];
    const filter = process.env.TARGET_FILTER || '';
    targets.forEach(t => {
      if (filter && t.name !== filter) return;
      const repos = t.repos || [];
      repos.forEach(r => console.log(r));
    });
  " 2>/dev/null
}

URLS=$(collect_urls | sort -u)

if [ -z "$URLS" ]; then
  echo "No target repos found (no REPOS_JSON and config.json targets[] is empty)."
  exit 0
fi

echo "Target work directory: $WORK_DIR"
echo ""

while IFS= read -r url; do
  [ -z "$url" ] && continue

  # 派生資料夾名稱（去掉 .git 後綴，取最後一段）
  repo_name=$(basename "$url" .git)
  dest="$WORK_DIR/$repo_name"

  if [ -d "$dest/.git" ]; then
    echo "Updating: $repo_name"
    git -C "$dest" pull --ff-only 2>&1 || {
      echo "  Warning: git pull failed for $repo_name, skipping update." >&2
    }
  else
    echo "Cloning: $url → $dest"
    clone_url=$(make_clone_url "$url")
    git clone "$clone_url" "$dest"
  fi
done <<< "$URLS"

echo ""
echo "All targets ready in $WORK_DIR"
