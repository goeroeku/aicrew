#!/usr/bin/env bash
# aicrew blocked-mark: mark an issue as blocked ONCE (idempotent) so rounds stop retrying it and continue with other ready issues (#108).
#   blocked-mark.sh <issue-number> <reason>  -> label `blocked` plus one comment "blocked: <reason>"; already labelled = no-op.
# Mark the ISSUE (branch issue-<n>), not the PR. The owner (or the orchestrator, once the cause is gone) removes the label.
set -u
source "$(dirname "$0")/lib/msg.sh"
n="${1:-}"; shift || true; reason="$*"
case "$n" in ''|*[!0-9]*) echo "$(msg blocked.mark_usage)" >&2; exit 64 ;; esac
[ -n "$reason" ] || { echo "$(msg blocked.mark_usage)" >&2; exit 64; }
labels="$(gh issue view "$n" --json labels -q '.labels[].name')" || { echo "$(msg blocked.cannot_read "$n")" >&2; exit 1; }
if printf '%s\n' "$labels" | grep -qx blocked; then echo "$(msg blocked.already "$n")"; exit 0; fi
gh label create blocked --color B60205 --description "$(msg blocked.label_desc)" >/dev/null 2>&1 || true
gh issue edit "$n" --add-label blocked >/dev/null || exit 1
gh issue comment "$n" --body "blocked: $reason" >/dev/null || exit 1
echo "$(msg blocked.marked "$n")"
