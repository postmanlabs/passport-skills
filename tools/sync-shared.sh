#!/usr/bin/env bash
# Copy shared/* into every skill's references/ folder. Each skill ships its own
# copy because installers copy one skill folder and symlinks break (AGENTS.md).
# --check: fail if any copy differs from shared/ (used by CI).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-sync}
status=0
for skill in "$root"/skills/*/; do
  for src in "$root"/shared/*; do
    dest="$skill/references/$(basename "$src")"
    if [ "$mode" = --check ]; then
      cmp -s "$src" "$dest" || { echo "out of date: ${dest#"$root"/} (run tools/sync-shared.sh)"; status=1; }
    else
      mkdir -p "$skill/references"
      cp "$src" "$dest"
    fi
  done
done
exit $status
