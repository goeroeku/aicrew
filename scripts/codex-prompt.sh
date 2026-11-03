#!/usr/bin/env bash
# Build a self-contained Codex prompt from an issue (body, acceptance criteria, owner comments),
# so Codex needs no gh call. Usage: codex-prompt.sh <issue-number>
set -o pipefail
n="${1:-}"
case "$n" in ''|*[!0-9]*) echo "usage: codex-prompt.sh <issue-number>" >&2; exit 2;; esac
json="$(gh issue view "$n" --json title,body,comments 2>&1)" || { echo "codex-prompt: cannot read issue #$n: $json" >&2; exit 1; }
printf '%s' "$json" | jq -r --arg n "$n" '
  "# Issue #\($n): \(.title)\n\n## Issue body (includes acceptance criteria)\n\n\(.body // "")\n\n## Owner comments\n\n" +
  (([.comments[]? | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR") | .body] | join("\n\n---\n\n")) // "")' \
  || { echo "codex-prompt: cannot parse issue #$n" >&2; exit 1; }
