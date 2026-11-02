#!/usr/bin/env bash
# aicrew ci-classify: tell a CI infrastructure failure (billing, no runner) apart from a code failure. Usage:
#   ci-classify.sh [--json -]      check-runs JSON (REST commits/<sha>/check-runs) on stdin
# Prints one of: infrastructure | code | pending | none (no failed check, all completed).
# For infrastructure it also prints: owner-action: CI cannot start: <annotation>. Fix account/runner; waiting.
# A failed check is infrastructure when its text (output.title/summary/text, or an "annotations[].message" the caller merged in)
# matches a known account-level message, or when it has no runner (runner_id null/0 or runner_name empty, key must be present)
# and ran under 5 s. Any failed check that is not infrastructure makes the verdict code (mixed = code).
# Exit 0 = classified, 2 = input is not usable check-runs JSON (fail-closed: never infrastructure), 64 = bad argument.
set -u
case "${1:-}" in
  "" ) ;;
  --json ) [ "${2:-}" = "-" ] || { echo "usage: ci-classify.sh [--json -]" >&2; exit 64; } ;;
  * ) echo "usage: ci-classify.sh [--json -]" >&2; exit 64 ;;
esac
in="$(cat)"
printf '%s' "$in" | jq -e '.check_runs|type=="array"' >/dev/null 2>&1 || { echo "ci-classify: input is not check-runs JSON" >&2; exit 2; }
printf '%s' "$in" | jq -r '
  def txt: [.output.title?, .output.summary?, .output.text?, (.annotations[]?.message)] | map(select(type=="string" and . != "")) | join(" ");
  def secs: if .started_at and .completed_at then ((.completed_at|fromdateiso8601) - (.started_at|fromdateiso8601)) else null end;
  def norunner: ((has("runner_id") and (.runner_id == null or .runner_id == 0)) or (has("runner_name") and (.runner_name == null or .runner_name == "")));
  def infra: (txt | test("payments? (have |has )?failed|spending limit"; "i")) or (norunner and ((secs) as $s | $s != null and $s < 5));
  [.check_runs[] | select(.status == "completed" and (.conclusion | IN("failure","timed_out","startup_failure","cancelled")))] as $f
  | if ($f | map(select(infra | not)) | length) > 0 then "code"
    elif ($f | length) > 0 then "infrastructure", "owner-action: CI cannot start: \($f[0] | (txt | if . == "" then "job has no runner" else . end) | gsub("[\n\r]+"; " ") | sub("[. ]+$"; "")). Fix account/runner; waiting."
    elif ([.check_runs[] | select(.status != "completed")] | length) > 0 then "pending"
    else "none" end'
