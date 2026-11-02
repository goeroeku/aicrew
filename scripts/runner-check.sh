#!/usr/bin/env bash
# aicrew runner-check: print the tools this machine is missing before a CI job runs on it. Usage:
#   runner-check.sh [<test-log>...]     run from the repo root
# Tools come from two sources: names in "<tool> not installed" / "<tool> tidak terpasang" lines of the given test logs,
# and known tools used in .github/workflows/*.y*ml (lines other than "uses:"). Missing ones (command -v) are printed one per line.
# Exit 0 = nothing missing, 1 = something missing, 64 = bad argument or unreadable log.
set -u
KNOWN='yq jq make docker curl unzip git gcc cc'
for a in "$@"; do
  case "$a" in -*) echo "usage: runner-check.sh [<test-log>...]" >&2; exit 64 ;; esac
  [ -r "$a" ] || { echo "runner-check: cannot read $a" >&2; exit 64; }
done
want="$(
  [ $# -eq 0 ] || sed -nE 's/.*[[:space:]:]([A-Za-z0-9._+-]+) (not installed|tidak terpasang).*/\1/p; s/^([A-Za-z0-9._+-]+) (not installed|tidak terpasang).*/\1/p' "$@"
  for f in .github/workflows/*.y*ml; do
    [ -r "$f" ] || continue
    grep -vE '^[[:space:]-]*uses:' "$f" | grep -owE "$(echo "$KNOWN" | tr ' ' '|')"
  done
)"
missing=""
for t in $(echo "$want" | sort -u); do command -v "$t" >/dev/null 2>&1 || missing="$missing$t"$'\n'; done
printf '%s' "$missing"
[ -z "$missing" ]
