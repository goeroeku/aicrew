#!/usr/bin/env bash
# aicrew resume: klasifikasikan issue yang ditinggal sesi sebelumnya (limit/mati) dari FAKTA, bukan ingatan. GitHub/gh saja.
# Keluaran per issue (TSV): <issue> <aksi> <detail> <aksi-lama>. Kolom 4 = nama lama aksi (alias usang, tersedia sepanjang 1.x; boleh diabaikan). Aksi:
#   finish-merge   PR sudah MERGED tapi label/kartu belum diperbarui -> pr-merge-check --after, label di-integrasi, kartu
#   continue-pr    PR terbuka -> lanjut verifikasi/QA/merge sesuai mode
#   check-branch   ada cabang issue-N tanpa PR -> baca diff, jalankan suite penuh, lanjut atau perbaiki (hitung satu percobaan)
#   requeue        tidak ada jejak kerja -> hapus label in-progress, masukkan antrean
#   check-release  issue berlabel menunggu-rilis -> awaiting-release.sh --check <issue>; siap -> lepas label, tutup issue (alur terjadwal baru aktif di cabang bawaan, #32)
# Tidak mengubah apa pun; orkestrator yang bertindak.
set -u
act() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }   # alias-usang: argumen ke-4 adalah nama lama aksi
for n in $(gh issue list --state open --json number,labels \
    -q '.[] | select(.labels|map(.name)|((index("in-progress") or index("in-review")) and (index("epic")|not))) | .number'); do
  read -r pr st < <(gh pr list --head "issue-$n" --state all --json number,state -q '.[0] | "\(.number) \(.state)"' 2>/dev/null || echo "- -")
  if [ "${st:--}" = MERGED ]; then act "$n" finish-merge "PR #$pr" selesaikan-merge   # alias-usang
  elif [ "${st:--}" = OPEN ]; then act "$n" continue-pr "PR #$pr" lanjut-pr   # alias-usang
  elif git show-ref --verify --quiet "refs/heads/issue-$n" || git show-ref --verify --quiet "refs/remotes/origin/issue-$n"; then
    act "$n" check-branch "issue-$n tanpa PR" periksa-cabang   # alias-usang
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
