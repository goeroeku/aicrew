#!/usr/bin/env bash
# aicrew menunggu-rilis: issue yang syarat selesainya baru terpenuhi setelah alur terjadwal/dependabot ada di cabang bawaan (#32).
#   menunggu-rilis.sh --tandai <issue> <pr>   komentar berpenanda memuat jalur berkas pemicu PR (alur-terjadwal.sh) + label (label.sh waiting); tanpa berkas pemicu: tidak melakukan apa pun
#   menunggu-rilis.sh --cek <issue>           exit 0 'siap' bila semua jalur di komentar berpenanda ada di cabang bawaan; 1 = ada yang belum (jalurnya dicetak); 2 = tak bisa diperiksa
# "Ada" berarti berkas ada di cabang bawaan (bukan isinya sama). REST saja.
set -u
here="$(dirname "$0")"; source "$here/ghx.sh"
marker='<!-- aicrew-menunggu-rilis -->'
mode="${1:-}"; issue="${2:?issue}"
cant() { echo "menunggu-rilis: $*" >&2; exit 2; }
repo="$(ghx_repo)" || cant "repo tak dapat ditentukan"
case "$mode" in
  --tandai)
    pr="${3:?pr}"
    files="$(bash "$here/alur-terjadwal.sh" "$pr")" || cant "berkas PR #$pr tak terbaca"
    [ -n "$files" ] || { echo "tidak ada alur terjadwal pada PR #$pr"; exit 0; }
    body="$marker"$'\n'"Menunggu rilis ke cabang bawaan (PR #$pr). Alur berikut baru aktif setelah ada di cabang bawaan:"$'\n'"$(sed 's/^/- /' <<<"$files")"
    gh api -X POST "repos/$repo/issues/$issue/comments" -f body="$body" >/dev/null || cant "komentar gagal ditulis"
    gh api -X POST "repos/$repo/issues/$issue/labels" -f "labels[]=$(bash "$here/label.sh" waiting)" >/dev/null || cant "label gagal dipasang"
    echo "issue #$issue menunggu rilis" ;;
  --cek)
    cj="$(gh api "repos/$repo/issues/$issue/comments" --paginate)" || cant "komentar issue #$issue tak terbaca"
    paths="$(jq -rs --arg m "$marker" '[.[][]|select(.body|startswith($m))|.body]|join("\n")' <<<"$cj" | sed -n 's/^- //p')"
    [ -n "$paths" ] || cant "komentar berpenanda tidak ditemukan pada issue #$issue"
    dflt="$(gh api "repos/$repo" | jq -r '.default_branch // empty')" && [ -n "$dflt" ] || cant "cabang bawaan tak terbaca"
    missing=""
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      q="$(jq -rn --arg p "$p" '$p|split("/")|map(@uri)|join("/")')"; rc=0
      e="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$q?ref=$dflt" 2>&1 >/dev/null)" || rc=$?
      if [ "$rc" != 0 ]; then grep -qE 'HTTP 404|Not Found' <<<"$e" && missing="$missing$p"$'\n' || cant "$p tak terbaca di $dflt (REST)"; fi
    done <<<"$paths"
    if [ -z "$missing" ]; then echo siap; else printf '%s' "$missing"; exit 1; fi ;;
  *) echo "pakai: menunggu-rilis.sh --tandai <issue> <pr> | --cek <issue>" >&2; exit 64 ;;
esac
