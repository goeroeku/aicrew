#!/usr/bin/env bash
# aicrew label-remove: cabut satu label dari satu issue lewat REST dengan jalur perintah tetap (#155).
#   label-remove.sh <n> <label>
# Tidak pernah mencabut owner-hold; menolak issue epic/needs-principal/owner-hold, issue terkunci, PR, dan issue yang tak terbaca. Label yang tak ada = tidak melakukan apa-apa (exit 0).
set -u
here="$(cd "$(dirname "$0")" && pwd)"; source "$here/ghx.sh"; source "$here/lib/msg.sh"
n="${1:-}"; label="${2:-}"
[[ "$n" =~ ^[0-9]+$ ]] && [[ "$label" =~ ^[A-Za-z0-9._:\ -]+$ ]] && [ "$label" != - ] && [ "$#" -eq 2 ] || { echo "$(msg labelremove.usage)" >&2; exit 64; }
protected='epic|needs-principal|owner-hold'
grep -ixqE 'owner-hold' <<<"$label" && { echo "GAGAL: $(msg labelremove.never_hold)" >&2; exit 1; }
if ghx_local; then
  rec="$(ls_view "$n" 2>/dev/null)" || { echo "GAGAL: $(msg issueclose.unreadable "$n")" >&2; exit 1; }
  labels="$(jq -r '[.labels[]?.name]|.[]' <<<"$rec")"
else
  repo="$(ghx_repo)" || { echo "GAGAL: $(msg issueclose.no_repo)" >&2; exit 1; }
  j="$(gh api "repos/$repo/issues/$n")" && jq -e 'type=="object"' <<<"$j" >/dev/null 2>&1 || { echo "GAGAL: $(msg issueclose.unreadable "$n")" >&2; exit 1; }
  jq -e 'has("pull_request")' <<<"$j" >/dev/null 2>&1 && { echo "GAGAL: $(msg issueclose.is_pr "$n")" >&2; exit 1; }
  [ "$(jq -r '.locked // false' <<<"$j")" != true ] || { echo "GAGAL: $(msg issueclose.locked "$n")" >&2; exit 1; }
  labels="$(jq -r '[.labels[]?.name]|.[]' <<<"$j")"
fi
hold="$(grep -ixE "$protected" <<<"$labels" | paste -sd, -)"
[ -z "$hold" ] || { echo "GAGAL: $(msg issueclose.protected "$n" "$hold")" >&2; exit 1; }
grep -ixqF -- "$label" <<<"$labels" || { echo "$(msg labelremove.absent "$n" "$label")"; exit 0; }
ghx_label_remove "$n" "$label" || { echo "GAGAL: $(msg issueclose.failed "$n")" >&2; exit 1; }
echo "$(msg labelremove.removed "$label" "$n")"
