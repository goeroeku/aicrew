#!/usr/bin/env bash
# aicrew blocked-mark: mark an issue as blocked ONCE (idempotent) so rounds stop retrying it and continue with other ready issues (#108).
#   blocked-mark.sh <issue-number> <reason>  -> label `blocked` plus one comment "blocked: <reason>"; already labelled = no-op.
# Mark the ISSUE (branch issue-<n>), not the PR. The owner (or the orchestrator, once the cause is gone) removes the label.
set -u
source "$(dirname "$0")/lib/msg.sh"
source "$(dirname "$0")/ghx.sh"
n="${1:-}"; shift || true; reason="$*"
case "$n" in ''|*[!0-9]*) echo "$(msg blocked.mark_usage)" >&2; exit 64 ;; esac
[ -n "$reason" ] || { echo "$(msg blocked.mark_usage)" >&2; exit 64; }
rc=0; labels="$(ghx_gql gh issue view "$n" --json labels -q '.labels[].name')" || rc=$?
if [ "$rc" = 75 ]; then rc=0; labels="$(gh api "repos/$(ghx_repo)/issues/$n" --jq '.labels[].name')" || rc=$?; fi
if [ "$rc" != 0 ]; then   # tak terbaca; bila kuota GitHub habis, antre kedua penanda (sinkron memeriksa idempoten) alih-alih gagal (#159)
  if ghx_queue label_add n="$n" label=blocked 2>/dev/null; then ghx_queue comment n="$n" body="blocked: $reason" 2>/dev/null; echo "$(msg blocked.marked "$n")"; exit 0; fi
  echo "$(msg blocked.cannot_read "$n")" >&2; exit 1
fi
if printf '%s\n' "$labels" | grep -qx blocked; then echo "$(msg blocked.already "$n")"; exit 0; fi
gh label create blocked --color B60205 --description "$(msg blocked.label_desc)" >/dev/null 2>&1 || true
ghx_label_add "$n" blocked >/dev/null || exit 1
ghx_comment "$n" "blocked: $reason" >/dev/null || exit 1
echo "$(msg blocked.marked "$n")"
