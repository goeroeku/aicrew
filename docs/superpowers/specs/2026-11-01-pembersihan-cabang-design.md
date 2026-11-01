# Pembersihan cabang dan worktree tak terpakai — desain

Status: draf untuk persetujuan owner. **[owner]** = disetujui owner ("sudah sesuai") atas usulan di percakapan; **[saya]** = keputusan penulis desain, boleh dikoreksi. Issue: #21.

## Maksud dan alasan
Cabang dan worktree menumpuk dan tidak ada yang membersihkannya. Bukti 2026-11-01: 13 cabang remote dan 10 lokal sudah ter-merge tetapi masih ada (dihapus manual); setelan GitHub `delete_branch_on_merge=false` pada repo ini (pemilik punya izin admin); satu-satunya pembersihan di plugin adalah `skills/orchestrate/SKILL.md` langkah 8 yang menghapus worktree issue (instruksi untuk agen, bukan skrip). Tidak ada penghapusan cabang, deteksi yatim, maupun rekomendasi.

## Tujuan
- `scripts/preflight.sh` memberi `AWAS` bila `delete_branch_on_merge` bernilai false, beserta perintah perbaikannya; plugin tidak mengubah setelan itu sendiri (milik owner repo). **[owner]**
- `scripts/cleanup.sh`: bawaan hanya **melaporkan** kandidat dengan bukti; `--apply` yang menghapus. **[owner]**
- Penghapusan otomatis hanya untuk artefak milik orkestrator (cabang `issue-<n>`, worktree `<repo>-wt-<n>`) setelah merge terverifikasi (`--after` ok); bawaan `ya`, dapat diubah. Cabang lain tidak pernah dihapus otomatis. **[owner]**

## Non-tujuan
- GitLab (tahap 1 hanya GitHub), `git gc`/prune objek, remote selain `origin`. **[owner]**
- Mengubah setelan repo GitHub. **[saya]**

## Anti-tujuan (gagal walau tampak jalan)
- Menghapus commit yang tidak ada di tempat lain (cabang yang ujungnya belum ter-merge, atau punya commit setelah PR-nya di-merge).
- Menghapus cabang yang PR-nya masih terbuka, cabang yang sedang di-checkout di worktree mana pun, `main`/cabang bawaan, cabang integrasi, atau apa pun di `~/orca/workspaces/` (wilayah Orca).
- `git worktree remove --force` atau `git branch -D`.
- Penghapusan tanpa jejak: setiap aksi mencetak SHA ujung cabang supaya bisa dipulihkan (`git branch <nama> <sha>`).

## Rancangan
**`cleanup.sh [--apply] [--only orkestrator] [--issue <n>]` [saya].** Dilindungi (tidak pernah kandidat): cabang bawaan (`git symbolic-ref refs/remotes/origin/HEAD`, cadangan REST `.default_branch`), cabang integrasi (baris `Cabang integrasi:` lewat `workflow.sh`), dan cabang yang di-checkout di worktree mana pun. Nama lain (mis. cadangan manual seperti `history-full`) tidak dilindungi khusus: hanya dilaporkan bila terbukti ter-merge (lihat Kendala).
**Kandidat cabang** (lokal dan `origin/*`): terbukti ter-merge lewat salah satu bukti: (a) ujungnya leluhur dari `origin/<cabang bawaan>` atau `origin/<cabang integrasi>` (`git merge-base --is-ancestor`); (b) REST `GET repos/<r>/pulls?head=<owner>:<cabang>&state=all` memuat PR dengan `merged_at` terisi dan `head.sha` sama dengan ujung cabang (mendeteksi squash/rebase merge). Ada PR terbuka untuk head itu → bukan kandidat. Kolom keluaran TSV: `jenis  nama  sha  bukti  aksi` (jenis `cabang-lokal|cabang-remote|worktree`, bukti `leluhur|pr-merged|-`, aksi `hapus|lewati:<alasan>`).
**Kandidat worktree:** bukan worktree utama, bukan di bawah `~/orca/workspaces/`, `git status --porcelain` kosong, dan cabangnya kandidat. Bila bersih tetapi cabangnya bukan kandidat → `lewati:belum-ter-merge`.
**`--apply`:** `git worktree remove <path>` (tanpa force) lalu `git branch -d` (lokal) lalu `git push origin --delete` (remote; "sudah terhapus" diabaikan). `--only orkestrator` membatasi pada nama `^issue-[0-9]+$` (cabang) dan `<repo>-wt-[0-9]+` (worktree); `--issue <n>` pada satu issue.
**Opsi `WORKFLOW.md` [saya]:** `Bersihkan setelah merge: ya|laporkan|tidak` (bawaan `ya`, hanya berlaku untuk milik orkestrator). `orchestrate` langkah 8 setelah `--after` ok menjalankan `cleanup.sh --only orkestrator --issue <n>` dan menambahkan `--apply` bila `ya`; `laporkan` hanya mencetak; `tidak` melewati.
**Preflight [saya]:** selain `AWAS` setelan GitHub, satu baris `info` bila ada kandidat ("N cabang ter-merge belum dihapus; jalankan `scripts/cleanup.sh`").
**Tanpa GraphQL [saya]:** hanya `git` dan REST (`gh api`), agar tidak terganggu batas GraphQL.

## Kendala
- Tes tanpa jaringan: repo git sementara dengan remote bare lokal; `gh` palsu untuk REST (daftar PR, setelan repo).
- Cabang yang namanya tak dikenal (mis. cadangan manual) hanya dilaporkan bila terbukti ter-merge; plugin tidak punya daftar nama dilindungi selain yang disebut di atas. **[saya]**
- Bahasa artefak repo: Indonesia. Jalan di macOS (bash 3.2) dan Linux CI.

## Kriteria selesai
- Tes merah dulu untuk: cabang ter-merge (leluhur) menjadi kandidat; squash-merge terdeteksi lewat PR merged; ujung berbeda dari `head.sha` PR bukan kandidat; PR terbuka bukan kandidat; cabang bawaan, integrasi, dan yang di-checkout dilindungi; worktree kotor dilewati; `--apply` menghapus dan mencetak SHA; `--only orkestrator` tidak menyentuh cabang lain; opsi `WORKFLOW.md`; peringatan setelan GitHub di preflight. `bash tests/run.sh` → `SEMUA LULUS`.
- README dan skill `orchestrate` diperbarui; rilis lewat alur rilis (owner menyetujui sebelum merge).

## Diserahkan ke builder
Nama fungsi dan struktur berkas, format teks laporan, penyusunan fixture repo sementara, dan penanganan nama cabang dengan `/` pada kueri REST.
