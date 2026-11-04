#!/usr/bin/env bash
# aicrew resume: klasifikasikan issue yang ditinggal sesi sebelumnya (limit/mati) dari FAKTA, bukan ingatan. GitHub/gh saja.
# Cabang/PR dicari lewat nomor issue: issue-N atau issue-N-<sufiks> (#78).
# Keluaran per issue (TSV): <issue> <aksi> <detail> <aksi-lama>. Kolom 4 = nama lama aksi (alias usang, tersedia sepanjang 1.x; boleh diabaikan). Aksi:
#   finish-merge   PR sudah MERGED tapi label/kartu belum diperbarui -> pr-merge-check --after, label di-integrasi, kartu
#   continue-pr    PR terbuka -> lanjut verifikasi/QA/merge sesuai mode
#   check-branch   ada cabang issue-N tanpa PR -> baca diff, jalankan suite penuh, lanjut atau perbaiki (hitung satu percobaan)
#   requeue        tidak ada jejak kerja -> hapus label in-progress, masukkan antrean
#   check-release  issue berlabel menunggu-rilis -> awaiting-release.sh --check <issue>; siap -> lepas label, tutup issue (alur terjadwal baru aktif di cabang bawaan, #32)
# Tidak mengubah apa pun; orkestrator yang bertindak.
set -u
act() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }   # alias-usang: argumen ke-4 adalah nama lama aksi
source "$(dirname "$0")/ghx.sh"
source "$(dirname "$0")/lib/msg.sh"
# GraphQL (gh issue list / gh pr list) habis: jalur REST (gh api) dengan bentuk data sama; gagal keduanya = galat, bukan "tidak ada issue" (#113)
rest=0; pj="[]"; readfail=""
resume_fail() { readfail=1; [ -t 2 ] || [ -n "${AICREW_VERBOSE:-}" ] && echo "resume: $1" >&2; ij="[]"; }   # sem: bisu bila stderr bukan terminal (keluaran TSV dibaca mesin), kecuali AICREW_VERBOSE
ij="$(gh issue list --state open --limit 200 --json number,labels 2>/dev/null)" || {
  repo="$(ghx_repo 2>/dev/null)"; [ -n "$repo" ] || resume_fail "$(msg resume.issues_repo_unknown)"
  if [ -z "$readfail" ]; then
  raw="$(gh api "repos/$repo/issues?state=open&per_page=100" --paginate --jq '.[]|select(.pull_request==null)|{number,labels:[.labels[]|{name}]}' 2>/dev/null)" || resume_fail "$(msg resume.issues_unreadable)"
  [ -n "$readfail" ] || ij="$(jq -s . <<<"$raw")"
  raw="$(gh api "repos/$repo/pulls?state=all&per_page=100" --paginate --jq '.[]|{number,state:(if .merged_at then "MERGED" elif .state=="open" then "OPEN" else "CLOSED" end),headRefName:.head.ref}' 2>/dev/null)" || resume_fail "$(msg resume.prs_unreadable)"
  [ -n "$readfail" ] || { pj="$(jq -s . <<<"$raw")"; rest=1; }
  fi
}
for n in $(jq -r '.[] | select(.labels|map(.name)|((index("in-progress") or index("in-review")) and (index("epic")|not))) | .number' <<<"$ij"); do
  pr=-; st=-
  if [ "$rest" = 1 ]; then   # OPEN diutamakan atas MERGED, sama dengan jalur GraphQL (#78)
    read -r pr st < <(jq -r --arg n "$n" '[.[]|select((.headRefName//"")|test("^issue-"+$n+"(-|$)"))] | (map(select(.state=="OPEN")) + map(select(.state=="MERGED"))) | .[0] | select(.!=null) | "\(.number) \(.state)"' <<<"$pj") || true
  else
  read -r pr st < <(gh pr list --head "issue-$n" --state all --json number,state -q '.[0] | "\(.number) \(.state)"' 2>/dev/null || echo "- -")
  if [ "${st:--}" != MERGED ] && [ "${st:--}" != OPEN ]; then   # tak ada PR di issue-N: cari lewat nomor issue (issue-N-<sufiks>), OPEN diutamakan atas MERGED (#78)
    read -r pr st < <(gh pr list --state all --limit 200 --json number,state,headRefName -q '[.[]|select((.headRefName//"")|test("^issue-'"$n"'(-|$)"))] | (map(select(.state=="OPEN")) + map(select(.state=="MERGED"))) | .[0] | select(.!=null) | "\(.number) \(.state)"' 2>/dev/null || true)
  fi
  fi
  br="$(git for-each-ref --format='%(refname:short)' "refs/heads/issue-$n" "refs/heads/issue-$n-*" "refs/remotes/origin/issue-$n" "refs/remotes/origin/issue-$n-*" 2>/dev/null | head -1)"
  if [ "${st:--}" = MERGED ]; then act "$n" finish-merge "PR #$pr" selesaikan-merge   # alias-usang
  elif [ "${st:--}" = OPEN ]; then act "$n" continue-pr "PR #$pr" lanjut-pr   # alias-usang
  elif [ -n "$br" ]; then
    act "$n" check-branch "${br#origin/} tanpa PR" periksa-cabang   # alias-usang
  else act "$n" requeue "tanpa cabang atau PR" antre-ulang; fi   # alias-usang
done
# issue yang menunggu rilis ke cabang bawaan (REST; PR dikecualikan)
source "$(dirname "$0")/ghx.sh"
if repo="$(ghx_repo 2>/dev/null)" && [ -n "$repo" ]; then
  for wl in $(bash "$(dirname "$0")/label.sh" waiting --all); do
    gh api "repos/$repo/issues?state=open&labels=$wl&per_page=100" 2>/dev/null \
      | jq -r '.[]|select(.pull_request==null)|"\(.number)\tcheck-release\tmenunggu rilis ke cabang bawaan\tperiksa-rilis"' 2>/dev/null || true   # alias-usang
  done | sort -u
fi
[ -z "$readfail" ] || exit 1
