#!/usr/bin/env bash
# aicrew resume: klasifikasikan issue yang ditinggal sesi sebelumnya (limit/mati) dari FAKTA, bukan ingatan. GitHub/gh saja.
# Keluaran per issue (TSV): <issue> <aksi> <detail>. Aksi:
#   selesaikan-merge  PR sudah MERGED tapi label/kartu belum diperbarui -> pr-merge-check --after, label di-integrasi, kartu
#   lanjut-pr         PR terbuka -> lanjut verifikasi/QA/merge sesuai mode
#   periksa-cabang    ada cabang issue-N tanpa PR -> baca diff, jalankan suite penuh, lanjut atau perbaiki (hitung satu percobaan)
#   antre-ulang       tidak ada jejak kerja -> hapus label in-progress, masukkan antrean
#   periksa-rilis     issue berlabel menunggu-rilis -> awaiting-release.sh --check <issue>; siap -> lepas label, tutup issue (alur terjadwal baru aktif di cabang bawaan, #32)
# Tidak mengubah apa pun; orkestrator yang bertindak.
set -u
for n in $(gh issue list --state open --json number,labels \
    -q '.[] | select(.labels|map(.name)|((index("in-progress") or index("in-review")) and (index("epic")|not))) | .number'); do
  read -r pr st < <(gh pr list --head "issue-$n" --state all --json number,state -q '.[0] | "\(.number) \(.state)"' 2>/dev/null || echo "- -")
  if [ "${st:--}" = MERGED ]; then printf '%s\tselesaikan-merge\tPR #%s\n' "$n" "$pr"
  elif [ "${st:--}" = OPEN ]; then printf '%s\tlanjut-pr\tPR #%s\n' "$n" "$pr"
  elif git show-ref --verify --quiet "refs/heads/issue-$n" || git show-ref --verify --quiet "refs/remotes/origin/issue-$n"; then
    printf '%s\tperiksa-cabang\tissue-%s tanpa PR\n' "$n" "$n"
  else printf '%s\tantre-ulang\ttanpa cabang atau PR\n' "$n"; fi
done
# issue yang menunggu rilis ke cabang bawaan (REST; PR dikecualikan)
source "$(dirname "$0")/ghx.sh"
if repo="$(ghx_repo 2>/dev/null)" && [ -n "$repo" ]; then
  for wl in $(bash "$(dirname "$0")/label.sh" waiting --all); do
    gh api "repos/$repo/issues?state=open&labels=$wl&per_page=100" 2>/dev/null \
      | jq -r '.[]|select(.pull_request==null)|"\(.number)\tperiksa-rilis\tmenunggu rilis ke cabang bawaan"' 2>/dev/null || true
  done | sort -u
fi
