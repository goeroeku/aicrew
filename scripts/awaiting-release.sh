#!/usr/bin/env bash
# aicrew menunggu-rilis: issue yang syarat selesainya baru terpenuhi setelah alur terjadwal/dependabot ada di cabang bawaan (#32).
#   awaiting-release.sh --mark <issue> <pr>   komentar berpenanda memuat jalur berkas pemicu PR (scheduled-workflow.sh) + label (label.sh waiting); tanpa berkas pemicu: tidak melakukan apa pun
#   awaiting-release.sh --check <issue>           exit 0 'siap' bila semua jalur di komentar berpenanda ada di cabang bawaan; 1 = ada yang belum (jalurnya dicetak); 2 = tak bisa diperiksa
# "Ada" berarti berkas ada di cabang bawaan (bukan isinya sama). REST saja.
set -u
here="$(dirname "$0")"; source "$here/ghx.sh"; source "$here/lib/msg.sh"
marker='<!-- aicrew-menunggu-rilis -->'
mode="${1:-}"; issue="${2:?issue}"
cant() { echo "menunggu-rilis: $*" >&2; exit 2; }
repo="$(ghx_repo)" || cant "$(msg awaitrel.repo_unknown)"
case "$mode" in
  --mark|--tandai)
    pr="${3:?pr}"
    files="$(bash "$here/scheduled-workflow.sh" "$pr")" || cant "$(msg awaitrel.pr_files_unreadable "$pr")"
    [ -n "$files" ] || { echo "$(msg awaitrel.no_sched_workflow "$pr")"; exit 0; }
    body="$marker"$'\n'"$(msg awaitrel.comment_intro "$pr")"$'\n'"$(sed 's/^/- /' <<<"$files")"
    gh api -X POST "repos/$repo/issues/$issue/comments" -f body="$body" >/dev/null || cant "$(msg awaitrel.comment_write_failed)"
    gh api -X POST "repos/$repo/issues/$issue/labels" -f "labels[]=$(bash "$here/label.sh" waiting)" >/dev/null || cant "$(msg awaitrel.label_apply_failed)"
    echo "$(msg awaitrel.marked "$issue")" ;;
  --check|--cek)
    cj="$(gh api "repos/$repo/issues/$issue/comments" --paginate)" || cant "$(msg awaitrel.comments_unreadable "$issue")"
    paths="$(jq -rs --arg m "$marker" '[.[][]|select(.body|startswith($m))|.body]|join("\n")' <<<"$cj" | sed -n 's/^- //p')"
    [ -n "$paths" ] || cant "$(msg awaitrel.marker_missing "$issue")"
    dflt="$(gh api "repos/$repo" | jq -r '.default_branch // empty')" && [ -n "$dflt" ] || cant "$(msg awaitrel.default_branch_unreadable)"
    missing=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      q="$(jq -rn --arg p "$p" '$p|split("/")|map(@uri)|join("/")')"; rc=0
      e="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$q?ref=$dflt" 2>&1 >/dev/null)" || rc=$?
      if [ "$rc" != 0 ]; then grep -qE 'HTTP 404|Not Found' <<<"$e" && missing="$missing$p"$'\n' || cant "$(msg awaitrel.path_unreadable "$p" "$dflt")"; fi
    done <<<"$paths"
    if [ -z "$missing" ]; then echo siap; else printf '%s' "$missing"; exit 1; fi ;;
  *) echo "$(msg awaitrel.usage)" >&2; exit 64 ;;
esac
