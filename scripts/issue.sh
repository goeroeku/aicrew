#!/usr/bin/env bash
# aicrew issue: CLI isu lokal untuk `Quota mode: local` (#159 tahap 4). Skill breakdown/prd/orchestrate memakainya MENGGANTIKAN `gh issue ...` pada mode itu.
#   issue.sh create --title T [--body B | --body-file F] [--label L]... [--parent N]   -> mencetak nomor isu
#   issue.sh list [--state open|closed|all] [--label L] [--limit N]                    -> larik JSON bentuk `gh issue list --json number,title,body,state,labels`
#   issue.sh view N                                                                     -> objek JSON + komentar
#   issue.sh comment N --body B | --body-file F
#   issue.sh label N [--add L]... [--remove L]...
#   issue.sh edit N --body B | --body-file F
#   issue.sh close N [--comment C]       issue.sh reopen N
# Hanya untuk mode lokal (WORKFLOW.md `Quota mode: local` atau AICREW_QUOTA_MODE=local); selain itu exit 2.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib/msg.sh"; source "$here/ghx.sh"
ghx_local || { echo "$(msg backend.local_only)" >&2; exit 2; }
cmd="${1:-}"; shift || true
die() { echo "issue.sh: $*" >&2; exit 64; }
body_arg() {   # --body B | --body-file F (dari argumen sisa) -> $BODY, $HAVE_BODY
  BODY=""; HAVE_BODY=0
  while [ $# -gt 0 ]; do case "$1" in
    --body) BODY="${2-}"; HAVE_BODY=1; shift $(( $# < 2 ? $# : 2 )) ;;
    --body-file) [ -r "${2-}" ] || die "berkas tak terbaca: ${2-}"; BODY="$(cat "$2")"; HAVE_BODY=1; shift $(( $# < 2 ? $# : 2 )) ;;
    *) shift ;; esac; done
}
case "$cmd" in
  create)
    title=""; labels=(); parent=""; rest=("$@")
    while [ $# -gt 0 ]; do case "$1" in
      --title) title="${2-}"; shift $(( $# < 2 ? $# : 2 )) ;; --label) labels+=("${2-}"); shift $(( $# < 2 ? $# : 2 )) ;; --parent) parent="${2-}"; shift $(( $# < 2 ? $# : 2 )) ;; *) shift ;; esac; done
    [ -n "$title" ] || die "create butuh --title"
    [ -z "$parent" ] || { [[ "$parent" =~ ^[0-9]+$ ]] && ls_view "$parent" >/dev/null 2>&1; } || die "--parent harus nomor isu yang ada"
    body_arg "${rest[@]}"
    n="$(ls_create "$title" "$BODY" "${labels[@]+"${labels[@]}"}")" || exit 1
    [ -z "$parent" ] || ls_set_parent "$n" "$parent" || exit 1
    echo "$n" ;;
  list)
    st=open; lab=-; lim=1000
    while [ $# -gt 0 ]; do case "$1" in
      --state) st="${2-}"; shift $(( $# < 2 ? $# : 2 )) ;; --label) lab="${2-}"; shift $(( $# < 2 ? $# : 2 )) ;; --limit) lim="${2-}"; shift $(( $# < 2 ? $# : 2 )) ;; *) shift ;; esac; done
    case "$st" in open|closed|all) ;; *) die "--state: open|closed|all" ;; esac
    [[ "$lim" =~ ^[0-9]+$ ]] || die "--limit harus angka"
    ls_list "$st" "$lab" "$lim" ;;
  view) [ -n "${1:-}" ] || die "view butuh nomor"; ls_view "$1" || { echo "issue.sh: isu #$1 tidak ada" >&2; exit 1; } ;;
  comment) n="${1:-}"; shift || true; body_arg "$@"; { [ "$HAVE_BODY" = 1 ] && [ -n "$BODY" ]; } || die "comment butuh --body tidak kosong"; ls_comment "$n" "$BODY" || exit 1 ;;
  label) n="${1:-}"; shift || true
    while [ $# -gt 0 ]; do case "$1" in
      --add) ls_label_add "$n" "${2-}" || exit 1; shift $(( $# < 2 ? $# : 2 )) ;; --remove) ls_label_remove "$n" "${2-}" || exit 1; shift $(( $# < 2 ? $# : 2 )) ;; *) die "label: --add L | --remove L" ;; esac; done ;;
  edit) n="${1:-}"; shift || true; body_arg "$@"; [ "$HAVE_BODY" = 1 ] || die "edit butuh --body"; ls_set_body "$n" "$BODY" || exit 1 ;;
  close) n="${1:-}"; shift || true; c=""
    while [ $# -gt 0 ]; do case "$1" in --comment) c="${2-}"; shift $(( $# < 2 ? $# : 2 )) ;; *) shift ;; esac; done
    ls_close "$n" "$c" || exit 1 ;;
  reopen) ls_reopen "${1:-}" || exit 1 ;;
  *) die "pakai: create|list|view|comment|label|edit|close|reopen" ;;
esac
