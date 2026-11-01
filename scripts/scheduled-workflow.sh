#!/usr/bin/env bash
# aicrew alur-terjadwal: berkas pada PR yang hanya aktif bila ada di cabang bawaan GitHub (#32). Pakai: scheduled-workflow.sh <pr> [<head-sha>]
# GitHub menjalankan schedule, memicu workflow_dispatch, dan membaca dependabot.yml hanya dari cabang bawaan.
# Cetak satu jalur per baris: .github/workflows/*.yml|yaml berisi schedule: atau workflow_dispatch: (pada head PR), dan .github/dependabot.yml|yaml.
# Berkas berstatus removed dilewati; renamed memakai nama barunya. REST saja.
# Kode keluar: 0 (daftar boleh kosong), 2 bila daftar berkas atau isi workflow tak terbaca.
set -u
here="$(dirname "$0")"; source "$here/ghx.sh"
pr="${1:?pr}"; head="${2:-}"
repo="$(ghx_repo)" || exit 2
fj="$(gh api "repos/$repo/pulls/$pr/files" --paginate)" || exit 2
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    .github/dependabot.yml|.github/dependabot.yaml) echo "$p" ;;
    *)
      if [ -z "$head" ]; then head="$(gh api "repos/$repo/pulls/$pr" | jq -r '.head.sha // empty')" && [ -n "$head" ] || exit 2; fi
      q="$(jq -rn --arg p "$p" '$p|split("/")|map(@uri)|join("/")')"
      body="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$q?ref=$head")" || exit 2
      grep -Eq '^[[:space:]]*(schedule|workflow_dispatch)[[:space:]]*:|^[[:space:]]*on:.*workflow_dispatch' <<<"$body" && echo "$p" ;;
  esac
done < <(jq -r '.[]|select(.status!="removed")|.filename' <<<"$fj" | grep -E '^\.github/(workflows/[^/]+\.ya?ml|dependabot\.ya?ml)$')
exit 0
