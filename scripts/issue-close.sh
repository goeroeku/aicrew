#!/usr/bin/env bash
# aicrew issue-close: tutup satu issue lewat REST dengan jalur perintah tetap (#155), supaya owner dapat memberi izin tanpa aturan `gh api` yang lebar.
#   issue-close.sh <n> [--comment <teks>]
# Menolak (exit 1): issue epic/needs-principal/owner-hold, issue terkunci, PR, dan issue yang tak terbaca (gagal tertutup). Sudah tertutup = tidak melakukan apa-apa (exit 0).
# Mode lokal: lewat store (aturan penolakan sama). Kuota REST habis: penutupan diantre (backend-sync.sh) bila status bertahan aktif.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; source "$here/ghx.sh"; source "$here/lib/msg.sh"
n="${1:-}"; shift || true; c=""
[[ "$n" =~ ^[0-9]+$ ]] || { echo "$(msg issueclose.usage)" >&2; exit 64; }
while [ $# -gt 0 ]; do case "$1" in --comment) c="${2-}"; shift $(( $# < 2 ? $# : 2 )) ;; *) echo "$(msg issueclose.usage)" >&2; exit 64 ;; esac; done
protected='epic|needs-principal|owner-hold'
if ghx_local; then
  rec="$(ls_view "$n" 2>/dev/null)" || { echo "GAGAL: $(msg issueclose.unreadable "$n")" >&2; exit 1; }
  jq -e '.state=="CLOSED"' <<<"$rec" >/dev/null 2>&1 && { echo "$(msg issueclose.already "$n")"; exit 0; }
  hold="$(jq -r '[.labels[]?.name]|.[]' <<<"$rec" | grep -ixE "$protected" | paste -sd, -)"
  [ -z "$hold" ] || { echo "GAGAL: $(msg issueclose.protected "$n" "$hold")" >&2; exit 1; }
  ls_close "$n" "$c" || exit 1; echo "$(msg issueclose.closed "$n")"; exit 0
fi
repo="$(ghx_repo)" || { echo "GAGAL: $(msg issueclose.no_repo)" >&2; exit 1; }
j="$(gh api "repos/$repo/issues/$n")" && jq -e 'type=="object"' <<<"$j" >/dev/null 2>&1 || { echo "GAGAL: $(msg issueclose.unreadable "$n")" >&2; exit 1; }
jq -e 'has("pull_request")' <<<"$j" >/dev/null 2>&1 && { echo "GAGAL: $(msg issueclose.is_pr "$n")" >&2; exit 1; }
[ "$(jq -r '.state' <<<"$j")" != closed ] || { echo "$(msg issueclose.already "$n")"; exit 0; }
[ "$(jq -r '.locked // false' <<<"$j")" != true ] || { echo "GAGAL: $(msg issueclose.locked "$n")" >&2; exit 1; }
hold="$(jq -r '[.labels[]?.name]|.[]' <<<"$j" | grep -ixE "$protected" | paste -sd, -)"
[ -z "$hold" ] || { echo "GAGAL: $(msg issueclose.protected "$n" "$hold")" >&2; exit 1; }
close_cmd() { [ -z "$c" ] || gh api -X POST "repos/$repo/issues/$n/comments" -f body="$c" >/dev/null || return 1
  gh api -X PATCH "repos/$repo/issues/$n" -f state=closed -f state_reason=completed >/dev/null; }
ghx_rest_write issue_close n="$n" comment="$c" -- close_cmd || { echo "GAGAL: $(msg issueclose.failed "$n")" >&2; exit 1; }
echo "$(msg issueclose.closed "$n")"
