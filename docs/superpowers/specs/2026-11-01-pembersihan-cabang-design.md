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
- `git worktree remove --force`, atau menghapus cabang tanpa bukti ter-merge (lihat "Keputusan tambahan": penghapusan cabang squash-merge memakai `git update-ref -d <ref> <sha>` yang hanya berhasil bila ujung cabang masih sama dengan yang dibuktikan, bukan `-D` buta).
- Penghapusan tanpa jejak: setiap aksi mencetak SHA ujung cabang supaya bisa dipulihkan (`git branch <nama> <sha>`).

## Rancangan
**`cleanup.sh [--apply] [--only orkestrator] [--issue <n>]` [saya].** Dilindungi (tidak pernah kandidat): cabang bawaan (`git symbolic-ref refs/remotes/origin/HEAD`, cadangan REST `.default_branch`), cabang integrasi (baris `Cabang integrasi:` lewat `workflow.sh`), dan cabang yang di-checkout di worktree mana pun. Nama lain (mis. cadangan manual seperti `history-full`) tidak dilindungi khusus: hanya dilaporkan bila terbukti ter-merge (lihat Kendala).
**Kandidat cabang** (lokal dan `origin/*`): terbukti ter-merge lewat salah satu bukti: (a) ujungnya leluhur dari `origin/<cabang bawaan>` atau `origin/<cabang integrasi>` (`git merge-base --is-ancestor`); (b) REST `GET repos/<r>/pulls?head=<owner>:<cabang>&state=all` memuat PR dengan `merged_at` terisi dan `head.sha` sama dengan ujung cabang (mendeteksi squash/rebase merge). Ada PR terbuka untuk head itu → bukan kandidat. Kolom keluaran TSV: `jenis  nama  sha  bukti  aksi` (jenis `cabang-lokal|cabang-remote|worktree`, bukti `leluhur|pr-merged|-`, aksi `hapus|lewati:<alasan>`).
**Kandidat worktree:** bukan worktree utama, bukan di bawah `~/orca/workspaces/`, `git status --porcelain` kosong, dan cabangnya kandidat. Bila bersih tetapi cabangnya bukan kandidat → `lewati:belum-ter-merge`.
**`--apply`:** `git worktree remove <path>` (tanpa force) lalu `git branch -d` (lokal) lalu `git push origin --delete` (remote; "sudah terhapus" diabaikan). `--only orkestrator` membatasi pada nama `^issue-[0-9]+$` (cabang) dan `<repo>-wt-[0-9]+` (worktree); `--issue <n>` pada satu issue.
**Opsi `WORKFLOW.md` [saya]:** `Bersihkan setelah merge: ya|laporkan|tidak` (bawaan `ya`, hanya berlaku untuk milik orkestrator). `orchestrate` langkah 8 setelah `--after` ok menjalankan `cleanup.sh --only orkestrator --issue <n>` dan menambahkan `--apply` bila `ya`; `laporkan` hanya mencetak; `tidak` melewati.
**Preflight [saya]:** selain `AWAS` setelan GitHub, satu baris `info` bila ada kandidat ("N cabang ter-merge belum dihapus; jalankan `scripts/cleanup.sh`").
**Tanpa GraphQL [saya]:** hanya `git` dan REST (`gh api`), agar tidak terganggu batas GraphQL.

## Keputusan tambahan (hasil pemeriksaan builder; semuanya **[saya]**, kecuali ditandai)
- **Cabang yang di-checkout di worktree:** dilindungi hanya bila worktree-nya TIDAK ikut dihapus dalam proses yang sama (worktree utama, Orca, kotor, atau cabangnya bukan kandidat). Algoritma: tentukan dulu worktree yang akan dihapus (bersih, bukan utama/Orca, cabangnya kandidat); cabang yang ter-checkout di worktree lain tetap dilindungi; urutan aksi: hapus worktree, lalu hapus cabang.
- **PR bertumpuk:** cabang yang menjadi `base` PR terbuka juga dilindungi (menghapusnya menutup PR itu). Satu kueri `GET repos/<r>/pulls?state=open&per_page=100` (paginasi) dipakai untuk memeriksa `head` dan `base` sekaligus.
- **Kesegaran bukti:** `cleanup.sh` menjalankan `git fetch --prune origin` dulu (hanya memperbarui ref `origin/*`, tidak menyentuh cabang lokal atau berkas kerja, jadi mode laporan tetap aman). Opsi `--no-fetch` untuk offline dan untuk preflight.
- **Cabang lokal:** tiap ref dievaluasi dari ujungnya sendiri. Leluhur dari `origin/<basis>` → hapus dengan `git branch -d`. Terbukti lewat PR merged dengan `head.sha` sama dengan ujung lokal → hapus dengan `git update-ref -d refs/heads/<nama> <sha>` (menolak bila ujung sudah berubah; `-d` biasa menolak cabang squash-merge). Ujung lokal yang menyimpang dari ujung PR (commit tambahan) → `lewati:belum-ter-merge`. Cabang lokal tanpa pasangan remote dievaluasi sama; gagal menghapus dilaporkan `lewati:<alasan>`, tidak menghentikan proses.
- **Preflight:** hanya bukti offline (ancestry, tanpa fetch, tanpa REST) dan hanya bila ada remote; mencetak "setidaknya N cabang ter-merge belum dihapus". Bukti `pr-merged` hanya dihitung oleh `cleanup.sh` penuh.
- **Pemasangan lama tanpa baris opsi:** baris `Bersihkan setelah merge` yang hilang diperlakukan sebagai bawaan `ya` untuk milik orkestrator **[owner: bawaan `ya`]**; templat memuat baris itu secara eksplisit, dan catatan rilis menyebut perubahan perilaku ini.
- **Izin:** `scripts/*` dan `git branch|worktree|push` sudah ada di `templates/autopilot-permissions.json`; tambahkan `Bash(git update-ref:*)`. Worktree yang disiapkan manual/Orca dan tidak bernama `<repo>-wt-<n>` dilewati oleh `--only orkestrator`.
- **Backend non-GitHub:** bila `Backend:` di `WORKFLOW.md` bukan `github`, `cleanup.sh` keluar 0 dengan pesan "tidak didukung (bukan GitHub)". Langkah 8 `orchestrate` memperlakukan kode keluar bukan-0 dari `cleanup.sh` hanya sebagai laporan, tidak pernah menghentikan alur.

## Kendala
- Tes tanpa jaringan: repo git sementara dengan remote bare lokal; `gh` palsu untuk REST (daftar PR, setelan repo).
- Cabang yang namanya tak dikenal (mis. cadangan manual) hanya dilaporkan bila terbukti ter-merge; plugin tidak punya daftar nama dilindungi selain yang disebut di atas. **[saya]**
- Bahasa artefak repo: Indonesia. Jalan di macOS (bash 3.2) dan Linux CI.

## Kriteria selesai
- Tes merah dulu untuk: cabang ter-merge (leluhur) menjadi kandidat; squash-merge terdeteksi lewat PR merged; ujung berbeda dari `head.sha` PR bukan kandidat; PR terbuka bukan kandidat; cabang bawaan, integrasi, dan yang di-checkout dilindungi; worktree kotor dilewati; `--apply` menghapus dan mencetak SHA; `--only orkestrator` tidak menyentuh cabang lain; opsi `WORKFLOW.md`; peringatan setelan GitHub di preflight. `bash tests/run.sh` → `SEMUA LULUS`.
- README dan skill `orchestrate` diperbarui; rilis lewat alur rilis (owner menyetujui sebelum merge).

## Diserahkan ke builder
Nama fungsi dan struktur berkas, format teks laporan, penyusunan fixture repo sementara, dan penanganan nama cabang dengan `/` pada kueri REST.
