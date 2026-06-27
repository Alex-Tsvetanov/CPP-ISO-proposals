#!/usr/bin/env bash
# Shallow-clone every repository listed in repos.txt into repos/.
# Re-running updates existing clones instead of failing.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repos_dir="$here/repos"
list="$here/repos.txt"
mkdir -p "$repos_dir"

while IFS= read -r line; do
  line="${line%%#*}"; line="$(echo "$line" | xargs || true)"   # strip comments/space
  [ -z "$line" ] && continue
  url="$(echo "$line" | awk '{print $1}')"
  name="$(basename "$url" .git)"
  dest="$repos_dir/$name"
  if [ -d "$dest/.git" ]; then
    echo ">> updating $name"
    git -C "$dest" fetch --depth 1 origin && git -C "$dest" reset --hard origin/HEAD || true
  else
    echo ">> cloning $name"
    git clone --depth 1 "$url" "$dest"
  fi
done < "$list"

echo "Done. Cloned repos:"; ls -1 "$repos_dir"
