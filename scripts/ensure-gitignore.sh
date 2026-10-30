#!/usr/bin/env bash
# aicrew ensure-gitignore: pastikan .aicrew/ dan .claude/settings.local.json ada di .gitignore (idempoten). Pakai: ensure-gitignore.sh [dir=.]
f="${1:-.}/.gitignore"; touch "$f"
for e in .aicrew/ .claude/settings.local.json; do
  grep -qxF "$e" "$f" || { [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ] && echo >> "$f"; echo "$e" >> "$f"; echo "gitignore: +$e"; }
done
exit 0
