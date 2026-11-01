#!/usr/bin/env bash
# aicrew pr-merge-check: cegah merge PR bertumpuk tersasar (GitHub/gh saja).
#   pr-merge-check.sh <pr> <cabang-tujuan>          sebelum merge: exit 1 bila basis PR != tujuan, atau PR/issue yang ditutupnya
#                                                   berlabel needs-security/needs-perf tanpa laporan lulus untuk head PR (waiver owner bercakupan perf atau rahasia)
#   pr-merge-check.sh <pr> <cabang-tujuan> --auto   seperti mode pertama, dan menolak PR/issue berlabel risk:L2 (auto-merge tidak boleh)
#   pr-merge-check.sh <pr> <cabang-tujuan> --after  setelah merge: exit 1 bila commit merge tak ada di origin/<tujuan>
set -u
source "$(dirname "$0")/ghx.sh"  # hanya ghx_explain_limit: gerbang TIDAK pindah ke REST (closingIssuesReferences tak ada di REST)
pr="${1:?pr}"; dst="${2:?cabang-tujuan}"
if [ "${3:-}" = "--after" ]; then
  read -r st oid < <(gh pr view "$pr" --json state,mergeCommit -q '[.state, .mergeCommit.oid // "-"] | @tsv')
  [ "$st" = MERGED ] || { echo "GAGAL: PR #$pr belum MERGED ($st)"; exit 1; }
  git fetch -q origin "$dst" && git merge-base --is-ancestor "$oid" "origin/$dst" \
    && echo "ok: PR #$pr ($oid) ada di $dst" || { echo "GAGAL: PR #$pr ter-merge tetapi $oid tidak ada di $dst"; exit 1; }
else
  base=$(gh pr view "$pr" --json baseRefName -q .baseRefName)
  echo "PR #$pr basis: $base"
  fail() { echo "GAGAL: $*"; ghx_explain_limit; exit 1; }  # fail-closed; bila penyebabnya batas GraphQL, jelaskan dan beri jam reset
  body="$(gh pr view "$pr" --json body -q .body)" || fail "badan PR #$pr tak terbaca"
  grep -Eiq '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]+ *(,|&|and|dan) *#?[0-9]' <<<"$body" \
    && echo "PERINGATAN: satu kata kunci hanya menutup satu issue; tulis satu 'Closes #n' per baris"
  [ "$base" = "$dst" ] || fail "basis $base != $dst; jalankan: gh pr edit $pr --base $dst"

  # gerbang label: needs-security / needs-perf (label PR + semua issue pada baris berkata-kunci) wajib punya laporan lulus untuk head PR
  head="$(gh pr view "$pr" --json headRefOid -q .headRefOid)" && [ -n "$head" ] || fail "head PR #$pr tak terbaca"
  labels="$(gh pr view "$pr" --json labels -q '.labels[].name')" || fail "label PR #$pr tak terbaca"
  closing="$(gh pr view "$pr" --json closingIssuesReferences -q '.closingIssuesReferences[].number')" || fail "closingIssuesReferences PR #$pr tak terbaca"
  # issue yang diperiksa = daftar resmi GitHub (URL, owner/repo#n, sidebar Development) ∪ semua #n pada baris berkata-kunci
  for n in $( { grep -Ei '(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]' <<<"$body" | grep -Eo '#[0-9]+' | tr -d '#'; echo "$closing"; } | sort -un); do
    l="$(gh issue view "$n" --json labels -q '.labels[].name')" || fail "label issue #$n tak terbaca"
    labels="$labels"$'\n'"$l"
  done
  if [ "${3:-}" = "--auto" ] && grep -qix "risk:L2" <<<"$labels"; then fail "risk:L2: auto-merge ditolak; minta owner merge"; fi
  comments="$(gh pr view "$pr" --json comments)" || fail "komentar PR #$pr tak terbaca"
  sha_ok() { [ "${#1}" -ge 7 ] && case "$head" in "$1"*) return 0 ;; esac; return 1; }
  # verdict_ok <awalan> <wajib-angka-dan-tuning:0|1>: vonis TERAKHIR untuk head menang. lulus = satu komentar memuat vonis lulus (tanpa gagal),
  # Commit = head, dan (perf) Angka berdigit + Tuning; gagal, atau lulus tak lengkap, membuat hasil gagal sampai ada lulus lengkap berikutnya
  verdict_ok() {
    res=1
    while IFS= read -r cj; do
      b="$(jq -r .body <<<"$cj")"
      grep -Eq "^$1 (lulus|gagal)" <<<"$b" || continue
      sha_ok "$(sed -n 's/^Commit: *\([0-9a-f]*\).*/\1/p' <<<"$b" | head -1)" || continue
      if grep -q "^$1 gagal" <<<"$b"; then res=1; continue; fi
      if [ "$2" != 0 ] && ! { grep -Eq '^Angka sebelum/sesudah:.*[0-9]' <<<"$b" && grep -Eq '^Tuning: *[^ ]' <<<"$b"; }; then res=1; continue; fi
      res=0
    done < <(jq -c '.comments[]' <<<"$comments")
    return $res
  }
  # waiver_ok <perf|rahasia>: komentar owner `Pengecualian disetujui owner (<cakupan>): <alasan> (Commit: <sha>)` untuk head PR; satu waiver hanya berlaku untuk cakupannya
  waiver_ok() {
    while IFS= read -r cj; do
      sha_ok "$(jq -r .body <<<"$cj" | sed -nE "s/^Pengecualian disetujui owner \($1\): .*[^ ].* \(Commit: *([0-9a-f]*)\).*/\1/p" | head -1)" && return 0
    done < <(jq -c '.comments[]' <<<"$comments")
    return 1
  }
  if grep -qix needs-security <<<"$labels" && ! verdict_ok "Laporan security:" 0; then
    fail "needs-security: butuh komentar 'Laporan security: lulus' dengan 'Commit: <sha head>' dari aicrew-security"
  fi
  if grep -qix needs-perf <<<"$labels" && ! verdict_ok "Laporan perf:" 1 && ! waiver_ok perf; then
    fail "needs-perf: butuh 'Laporan perf: lulus' dengan Angka sebelum/sesudah (berdigit), Tuning, dan 'Commit: <sha head>' dari aicrew-perf, atau waiver owner untuk head"
  fi
  # baseline: rahasia memblokir (kecuali waiver owner untuk head), sisanya hanya peringatan; diff tak terbaca = tolak
  diff="$(gh pr diff "$pr")" || fail "diff PR #$pr tak terbaca"
  bf="$(mktemp)"; trap 'rm -f "$bf"' EXIT; printf '%s\n' "$body" > "$bf"
  grep -qix needs-perf <<<"$labels" && perfl=1 || perfl=0
  scan="$(printf '%s\n' "$diff" | bash "$(dirname "$0")/baseline-scan.sh" --body "$bf" --perf-labeled "$perfl")"; rc=$?
  [ -z "$scan" ] || echo "$scan"
  [ "$rc" = 0 ] || waiver_ok rahasia || fail "baseline-scan menemukan rahasia pada diff; perbaiki, atau waiver owner (rahasia) untuk head PR"
  echo "ok: gerbang lolos untuk head $head. Merge dengan: gh pr merge $pr --match-head-commit $head"
fi
