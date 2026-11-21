#!/usr/bin/env bash
# aicrew tick-status: satu perintah baca-saja untuk siklus orkestrator (#157). Hanya REST (tanpa GraphQL), jadi tetap jalan saat kuota GraphQL habis.
#   tick-status.sh [--header] [--gate <cabang-tujuan>]
# Satu baris TSV per PR terbuka dari cabang issue-<n> (urut nomor PR), kolom tetap:
#   pr  issue  head7  ci  qa  security  perf  executor  gate
#   ci        : none (semua check selesai, tanpa gagal) | pending | code | infrastructure | no-checks | ? (tak terbaca)   (ci-classify.sh)
#   qa/security/perf : lulus | gagal untuk SHA head ini; stale = ada vonis tetapi untuk head lama; - = belum ada. Hanya komentar OWNER/MEMBER/COLLABORATOR yang dihitung (sama dengan gerbang).
#   executor  : running | dead bila .aicrew/executors/issue-<n>.pid (atau .aicrew/executor-<n>.pid) ada; - bila tidak ada berkas
#   gate      : - (bawaan; murah) atau, dengan --gate <tujuan>, hasil `pr-merge-check.sh <pr> <tujuan> --auto` ('ok' atau 'GAGAL' + alasan singkat)
# Mode lokal (Quota mode: local): PR dari cabang issue-<n>, vonis dari komentar isu lokal, ci '-'.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; source "$here/ghx.sh"; source "$here/lib/msg.sh"
hdr=0; gate=""
while [ $# -gt 0 ]; do case "$1" in --header) hdr=1; shift ;; --gate) gate="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;; *) echo "$(msg tick.usage)" >&2; exit 64 ;; esac; done
[ -z "$gate" ] || [[ "$gate" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] || { echo "$(msg tick.usage)" >&2; exit 64; }
command -v jq >/dev/null 2>&1 || { echo "tick-status: jq required" >&2; exit 1; }
g="$(git rev-parse --git-common-dir 2>/dev/null)" && root="$(cd "$g/.." && pwd)" || root="."
[ "$hdr" = 0 ] || printf 'pr\tissue\thead7\tci\tqa\tsecurity\tperf\texecutor\tgate\n'
# verdict <comentarios-json-larik[{body,authorAssociation}]> <awalan> <sha-head> -> lulus|gagal|stale|-
verdict() {
  local last="-" seen=0 cj b cs
  while IFS= read -r cj; do
    b="$(jq -r '.body // ""' <<<"$cj")"
    grep -Eiq "^$2 (lulus|gagal)([^[:alnum:]_]|$)" <<<"$b" || continue
    cs="$(sed -nE 's/^[Cc][Oo][Mm][Mm][Ii][Tt]: *([0-9a-fA-F]+).*/\1/p' <<<"$b" | head -1)"
    [ -n "$cs" ] || cs="$(grep -Ei "^$2 (lulus|gagal)([^[:alnum:]_]|$)" <<<"$b" | head -1 | sed -nE 's/.*[Cc][Oo][Mm][Mm][Ii][Tt]: *([0-9a-fA-F]+).*/\1/p')"
    seen=1; cs="$(tr 'A-F' 'a-f' <<<"$cs")"
    if [ "${#cs}" -ge 7 ] && case "$3" in "$cs"*) true ;; *) false ;; esac; then   # vonis TERAKHIR untuk head ini menang (sama dengan gerbang)
      if grep -Eiq "^$2 gagal([^[:alnum:]_]|$)" <<<"$b"; then last=gagal; else last=lulus; fi
    fi
  done < <(jq -c '.[]? | select(.authorAssociation | IN("OWNER","MEMBER","COLLABORATOR"))' <<<"$1" 2>/dev/null)
  [ "$last" != "-" ] || { [ "$seen" = 1 ] && last=stale; }
  echo "$last"
}
exec_state() {   # <issue>
  local f p; for f in "$root/.aicrew/executors/issue-$1.pid" "$root/.aicrew/executor-$1.pid"; do
    [ -f "$f" ] || continue; p="$(tr -dc '0-9' < "$f")"; if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then echo running; else echo dead; fi; return
  done; echo "-"
}
if ghx_local; then
  prs="$(ghx_prs open 200 x)" || prs='[]'
  while IFS=$'\t' read -r num br sha; do
    [[ "$br" =~ ^issue-([0-9]+)$ ]] || continue; is="${BASH_REMATCH[1]}"
    cm="$(ls_comments "$num" 2>/dev/null | jq -c '[.[]?|{body,authorAssociation:"OWNER"}]')"
    printf '%s\t%s\t%s\t-\t%s\t%s\t%s\t%s\t-\n' "$num" "$is" "${sha:0:7}" "$(verdict "$cm" 'Laporan qa:' "$sha")" "$(verdict "$cm" 'Laporan security:' "$sha")" "$(verdict "$cm" 'Laporan perf:' "$sha")" "$(exec_state "$is")"
  done < <(jq -r 'sort_by(.number)|.[]?|[.number,.headRefName,.headRefOid]|@tsv' <<<"$prs")
  exit 0
fi
repo="$(ghx_repo)" || { echo "tick-status: repo unknown" >&2; exit 1; }
prs="$(gh api "repos/$repo/pulls?state=open&per_page=100" --paginate 2>/dev/null | jq -cs 'add // []')" || { echo "tick-status: cannot read PRs" >&2; exit 1; }
jq -e 'type=="array"' <<<"$prs" >/dev/null 2>&1 || { echo "tick-status: cannot read PRs" >&2; exit 1; }
while IFS=$'\t' read -r num br sha cross; do
  [[ "$br" =~ ^issue-([0-9]+)$ ]] || continue; is="${BASH_REMATCH[1]}"; [ "$cross" = false ] || continue
  cr="$(gh api "repos/$repo/commits/$sha/check-runs?per_page=100" --paginate --jq '.check_runs[]' 2>/dev/null | jq -s '{check_runs: .}' 2>/dev/null)"
  if [ -z "$cr" ] || ! jq -e '.check_runs|type=="array"' <<<"$cr" >/dev/null 2>&1; then ci='?'
  elif [ "$(jq '.check_runs|length' <<<"$cr")" = 0 ]; then ci=no-checks
  else ci="$(bash "$here/ci-classify.sh" <<<"$cr" 2>/dev/null | head -1)"; [ -n "$ci" ] || ci='?'; fi
  cm="$(gh api "repos/$repo/issues/$num/comments?per_page=100" --paginate 2>/dev/null | jq -cs '[.[][]?|{body:(.body // ""),authorAssociation:.author_association}]' 2>/dev/null)" || cm='[]'
  [ -n "$cm" ] || cm='[]'
  gv="-"; if [ -n "$gate" ]; then out="$(bash "$here/pr-merge-check.sh" "$num" "$gate" --auto 2>&1 | tail -1)"; case "$out" in ok:*) gv=ok ;; *) gv="$(printf '%s' "$out" | cut -c1-60 | tr '\t' ' ')" ;; esac; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$num" "$is" "${sha:0:7}" "$ci" "$(verdict "$cm" 'Laporan qa:' "$sha")" "$(verdict "$cm" 'Laporan security:' "$sha")" "$(verdict "$cm" 'Laporan perf:' "$sha")" "$(exec_state "$is")" "$gv"
done < <(jq -r 'sort_by(.number)|.[]?|[.number,(.head.ref // ""),(.head.sha // ""),((.head.repo.full_name // "") != (.base.repo.full_name // ""))]|@tsv' <<<"$prs")
