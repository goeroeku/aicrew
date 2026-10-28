#!/usr/bin/env bash
# aicrew pr-merge-check: cegah merge PR bertumpuk tersasar (GitHub/gh saja).
#   pr-merge-check.sh <pr> <cabang-tujuan>          sebelum merge: exit 1 bila basis PR != tujuan
#   pr-merge-check.sh <pr> <cabang-tujuan> --after  setelah merge: exit 1 bila commit merge tak ada di origin/<tujuan>
set -u
pr="${1:?pr}"; dst="${2:?cabang-tujuan}"
if [ "${3:-}" = "--after" ]; then
  read -r st oid < <(gh pr view "$pr" --json state,mergeCommit -q '[.state, .mergeCommit.oid // "-"] | @tsv')
  [ "$st" = MERGED ] || { echo "GAGAL: PR #$pr belum MERGED ($st)"; exit 1; }
  git fetch -q origin "$dst" && git merge-base --is-ancestor "$oid" "origin/$dst" \
    && echo "ok: PR #$pr ($oid) ada di $dst" || { echo "GAGAL: PR #$pr ter-merge tetapi $oid tidak ada di $dst"; exit 1; }
else
  base=$(gh pr view "$pr" --json baseRefName -q .baseRefName)
  echo "PR #$pr basis: $base"
  gh pr view "$pr" --json body -q .body | grep -Eiq '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]+ *(,|&|and|dan) *#?[0-9]' \
    && echo "PERINGATAN: satu kata kunci hanya menutup satu issue; tulis satu 'Closes #n' per baris"
  [ "$base" = "$dst" ] || { echo "GAGAL: basis $base != $dst; jalankan: gh pr edit $pr --base $dst"; exit 1; }
fi
