#!/usr/bin/env bash
# aicrew merge-pr: satu pintu merge untuk orkestrator (#159 tahap 3). Menggantikan `gh pr merge` mentah.
#   merge-pr.sh <pr> <cabang-tujuan> [--branch issue-N]
# 1. Jalankan gerbang `pr-merge-check.sh <pr> <tujuan> --auto`. Lolos -> `gh pr merge <pr> --merge --match-head-commit <sha>` lalu `--after`.
# 2. Gerbang menolak -> keluaran gerbang dicetak apa adanya. HANYA bila probe langsung (bukan berkas status atau env) membuktikan GraphQL DAN REST sama-sama habis,
#    dan --branch diberikan, dipakai jalur lokal `local-merge.sh` (L0/L1, tes dijalankan sendiri, fail-closed). Selain itu exit 1 seperti biasa.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib/msg.sh"; source "$here/ghx.sh"
pr="${1:-}"; dst="${2:-}"; shift 2 2>/dev/null || true; br=""
while [ $# -gt 0 ]; do case "$1" in --branch) br="${2:-}"; shift 2 ;; *) echo "usage: merge-pr.sh <pr> <dst-branch> [--branch issue-N]" >&2; exit 64 ;; esac; done
[[ "$pr" =~ ^[0-9]+$ ]] && [ -n "$dst" ] || { echo "usage: merge-pr.sh <pr> <dst-branch> [--branch issue-N]" >&2; exit 64; }
out="$(bash "$here/pr-merge-check.sh" "$pr" "$dst" --auto 2>&1)"; rc=$?
printf '%s\n' "$out"
if [ "$rc" = 0 ]; then
  sha="$(grep -E '^ok:' <<<"$out" | grep -Eo '[0-9a-f]{40}' | head -1)"
  [ -n "$sha" ] || { echo "GAGAL: $(msg mergepr.no_sha)"; exit 1; }
  gh pr merge "$pr" --merge --match-head-commit "$sha" || exit 1
  bash "$here/pr-merge-check.sh" "$pr" "$dst" --after
  exit $?
fi
# probe langsung: header respons GraphQL dan `gh api rate_limit` (REST core; tidak memakai kuota)
gh_h="$(_ghx_probe)"; g_rem="$(_ghx_hdr "$gh_h" x-ratelimit-remaining)"; g_rst="$(_ghx_hdr "$gh_h" x-ratelimit-reset)"
r_rem="$(gh api rate_limit --jq '.resources.core.remaining' 2>/dev/null)"; r_rst="$(gh api rate_limit --jq '.resources.core.reset' 2>/dev/null)"
if [ "$g_rem" = 0 ] && [ "$r_rem" = 0 ] && grep -Eq 'Penyebab: batas (GraphQL|REST) GitHub habis' <<<"$out"; then   # probe langsung DAN penolakan gerbang memang karena kuota (bukan alasan lain)
  [ -n "$br" ] || { echo "GAGAL: $(msg mergepr.need_branch)"; exit 1; }
  echo "$(msg mergepr.local_path)"
  export GHX_PERSIST=1
  [[ "$g_rst" =~ ^[0-9]+$ ]] || g_rst=$(( $(date +%s) + 60 )); [[ "$r_rst" =~ ^[0-9]+$ ]] || r_rst=$(( $(date +%s) + 60 ))
  _ghx_state_set graphql "$g_rst"; _ghx_state_set rest "$r_rst"   # supaya komentar jejak dapat diantre (ghx_queue) dan autopilot melihat jenjangnya
  bash "$here/local-merge.sh" "$pr" "$dst" "$br"
  exit $?
fi
exit "$rc"
