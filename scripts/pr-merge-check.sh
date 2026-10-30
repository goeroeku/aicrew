#!/usr/bin/env bash
# aicrew pr-merge-check: cegah merge PR bertumpuk tersasar (GitHub/gh saja).
#   pr-merge-check.sh <pr> <cabang-tujuan>          sebelum merge: exit 1 bila basis PR != tujuan, atau PR/issue yang ditutupnya
#                                                   berlabel needs-security/needs-perf tanpa laporan lulus untuk head PR (perf: boleh waiver owner)
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
  fail() { echo "GAGAL: $*"; exit 1; }
  body="$(gh pr view "$pr" --json body -q .body)" || fail "badan PR #$pr tak terbaca"
  grep -Eiq '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]+ *(,|&|and|dan) *#?[0-9]' <<<"$body" \
    && echo "PERINGATAN: satu kata kunci hanya menutup satu issue; tulis satu 'Closes #n' per baris"
  [ "$base" = "$dst" ] || fail "basis $base != $dst; jalankan: gh pr edit $pr --base $dst"

  # gerbang label: needs-security / needs-perf (label PR + semua issue pada baris berkata-kunci) wajib punya laporan lulus untuk head PR
  head="$(gh pr view "$pr" --json headRefOid -q .headRefOid)" && [ -n "$head" ] || fail "head PR #$pr tak terbaca"
  labels="$(gh pr view "$pr" --json labels -q '.labels[].name')" || fail "label PR #$pr tak terbaca"
  for n in $(grep -Ei '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]' <<<"$body" | grep -Eo '#[0-9]+' | tr -d '#'); do
    l="$(gh issue view "$n" --json labels -q '.labels[].name')" || fail "label issue #$n tak terbaca"
    labels="$labels"$'\n'"$l"
  done
  comments="$(gh pr view "$pr" --json comments)" || fail "komentar PR #$pr tak terbaca"
  sha_ok() { [ "${#1}" -ge 7 ] && case "$head" in "$1"*) return 0 ;; esac; return 1; }
  # verdict_ok <awalan> <wajib-angka-dan-tuning:0|1>: satu komentar harus memuat vonis lulus, Commit = head, (perf) Angka berdigit dan Tuning
  verdict_ok() {
    while IFS= read -r cj; do
      b="$(jq -r .body <<<"$cj")"
      grep -q "^$1 lulus" <<<"$b" || continue
      sha_ok "$(sed -n 's/^Commit: *\([0-9a-f]*\).*/\1/p' <<<"$b" | head -1)" || continue
      [ "$2" = 0 ] || { grep -Eq '^Angka sebelum/sesudah:.*[0-9]' <<<"$b" && grep -Eq '^Tuning: *[^ ]' <<<"$b"; } || continue
      return 0
    done < <(jq -c '.comments[]' <<<"$comments")
    return 1
  }
  # waiver_ok: komentar owner `Pengecualian disetujui owner: <alasan> (Commit: <sha>)` untuk head PR (hanya gerbang perf)
  waiver_ok() {
    while IFS= read -r cj; do
      sha_ok "$(jq -r .body <<<"$cj" | sed -n 's/^Pengecualian disetujui owner: .* (Commit: *\([0-9a-f]*\)).*/\1/p' | head -1)" && return 0
    done < <(jq -c '.comments[]' <<<"$comments")
    return 1
  }
  if grep -qx needs-security <<<"$labels" && ! verdict_ok "Laporan security:" 0; then
    fail "needs-security: butuh komentar 'Laporan security: lulus' dengan 'Commit: <sha head>' dari aicrew-security"
  fi
  if grep -qx needs-perf <<<"$labels" && ! verdict_ok "Laporan perf:" 1 && ! waiver_ok; then
    fail "needs-perf: butuh 'Laporan perf: lulus' dengan Angka sebelum/sesudah (berdigit), Tuning, dan 'Commit: <sha head>' dari aicrew-perf, atau waiver owner untuk head"
  fi
fi
