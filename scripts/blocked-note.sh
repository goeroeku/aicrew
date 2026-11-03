#!/usr/bin/env bash
# aicrew blocked-note: say once that a permission denial blocked a PR. Usage: blocked-note.sh <pr> <command>
# Posts ONE comment "blocked-by-permission: <command>" (idempotent per command) and prints the settings rule to add.
[ $# -eq 2 ] || { echo "usage: blocked-note.sh <pr> <command>" >&2; exit 64; }
set -euo pipefail
source "$(dirname "$0")/ghx.sh"
pr="$1"; cmd="$2"; line="blocked-by-permission: $cmd"; repo="$(ghx_repo)"
if ! gh api "repos/$repo/issues/$pr/comments" --paginate | jq -e --arg l "$line" 'any(.[]; .body == $l)' >/dev/null; then
  gh api "repos/$repo/issues/$pr/comments" -f "body=$line" >/dev/null
fi
echo "Add to permissions.allow in .claude/settings.local.json: \"Bash($cmd:*)\""
