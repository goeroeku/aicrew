# "Selesai" harus berarti di tempat yang benar — desain

Status: draf untuk persetujuan owner. **[owner]** = disetujui owner ("saya setuju dengan saran anda") atas rancangan di percakapan; **[saya]** = keputusan penulis desain, boleh dikoreksi. Issue: #28 dan #32 (satu desain, karena akarnya sama).

## Maksud dan alasan
Orkestrator menilai sebuah issue selesai dari status `merged` pada PR-nya. Dua kejadian nyata di Nexora (2026-11-01) menunjukkan itu tidak cukup:
- **#28:** PR bertumpuk ter-merge ke cabang induk, bukan ke cabang integrasi. Statusnya `merged`, issue sempat ditutup dan kartu dipindah ke Done, padahal isinya belum terintegrasi. Orkestrator Nexora menangkapnya lewat `git merge-base --is-ancestor <ujung> origin/<integrasi>`; plugin belum punya pemeriksaan itu.
- **#32:** `vuln-scan.yml` (schedule + workflow_dispatch) dan `dependabot.yml` ter-merge ke integrasi, sedangkan cabang bawaan tertinggal 172 commit. GitHub hanya menjalankan `schedule`, memicu `workflow_dispatch`, dan membaca `dependabot.yml` dari cabang bawaan, jadi pemantauan CVE yang kodenya selesai tidak aktif sama sekali dan tidak ada yang tahu.

## Tujuan
- Label `di-integrasi`, penutupan issue, dan kartu Done hanya diberikan bila PR terbukti masuk cabang integrasi: `pulls/N .base.ref` sama dengan cabang integrasi, atau ujung PR adalah leluhur `origin/<integrasi>`. **[owner]**
- Satu pemeriksa bersama dipakai semua titik (`orchestrate`, `resume.sh`, `board.sh --sync`), bukan logika yang disalin. **[owner]**
- `pr-merge-check.sh` memperingatkan (`PERINGATAN`, tidak memblokir) bila PR menyentuh `.github/workflows/*` yang memuat `schedule:` atau `workflow_dispatch:`, atau `.github/dependabot.yml`/`.yaml`, dan cabang tujuan bukan cabang bawaan: "alur ini tidak aktif sampai ada di cabang bawaan". **[owner]**
- Issue yang syarat selesainya baru terpenuhi di cabang bawaan: tetap terbuka, diberi komentar dan label `menunggu-rilis`, kartu tidak dipindah ke Done. Ditutup hanya setelah file pemicunya terbukti ada di cabang bawaan. **[owner]**
- Skill `cve-audit` melaporkan alur terjadwal dan `dependabot.yml` yang ada di integrasi tetapi belum di cabang bawaan, sebagai satu baris di ringkasan (bukan issue baru). **[saya]**

## Non-tujuan
- Mengubah base PR bertumpuk secara otomatis (`PATCH pulls/N base`): mengubah PR orang lain diam-diam. Cukup diperingatkan; preflight sudah menyebut dampaknya. **[owner]**
- Memblokir merge PR ke integrasi karena #32; itu hanya peringatan. **[owner]**
- Backend selain GitHub, dan GraphQL (hanya `git` dan REST, agar tahan batas GraphQL). **[saya]**

## Anti-tujuan (gagal walau tampak jalan)
- Memberi `di-integrasi`, menutup issue, atau memindahkan kartu ke Done saat pemeriksaan tidak bisa dijalankan (REST gagal, cabang integrasi tak terambil). Gagal baca = tidak memberi apa pun dan dilaporkan (fail-closed). **[saya]**
- Peringatan palsu untuk PR yang memang ke cabang bawaan, atau untuk workflow tanpa `schedule:`/`workflow_dispatch:`.
- Issue berlabel `menunggu-rilis` yang tak pernah diperiksa ulang sehingga tak pernah ditutup. (Penutupan otomatis GitHub lewat `Closes` hanya terjadi pada merge ke cabang bawaan, jadi tidak perlu dicegah; itu justru bukti yang sah.)
- Perilaku proyek tanpa cabang integrasi (`Cabang integrasi:` kosong) berubah: tanpa integrasi, cabang tujuan = bawaan dan semuanya jalan seperti sekarang. **[saya]**

## Rancangan
**Pemeriksa bersama [saya].** Skrip kecil `scripts/terintegrasi.sh <pr>`: exit 0 bila `base.ref` = cabang integrasi (`workflow.sh`), atau ujung PR (`head.sha` PR yang merged) adalah leluhur `origin/<integrasi>` setelah `git fetch`; exit 1 dengan satu baris alasan ("ter-merge ke <base>, belum ke <integrasi>"); exit 2 bila tak bisa diperiksa. Dipanggil sebelum label `di-integrasi` di `orchestrate` (`selesaikan-merge` dan langkah setelah `--after`), di `resume.sh`, dan sebelum `board.sh --sync` menutup issue `di-integrasi` atau memindahkannya ke Done. Hasil bukan-0: tidak memberi apa pun, satu baris di ringkasan.
**Peringatan #32 di gerbang [saya].** Di `pr-merge-check.sh`, ambil daftar berkas PR (`pulls/N/files`, REST); untuk tiap berkas workflow, baca isinya pada `head.sha` dan cari `schedule:`/`workflow_dispatch:`; untuk `dependabot.yml|yaml` cukup namanya. Cabang bawaan dari `.default_branch`. Keluaran memuat nama berkas (bukan data sensitif) dan tidak mengubah kode keluar.
**`menunggu-rilis` [saya].** Saat orkestrator menyelesaikan PR yang memicu peringatan di atas ke cabang non-bawaan: komentar di issue memuat daftar berkas dan nomor PR, label `menunggu-rilis` (nama tetap, tidak dapat dikonfigurasi), tanpa Done. Setelah PR integrasi → bawaan ter-merge, langkah `selesaikan-merge`/`resume.sh` memeriksa lewat REST (`contents/<berkas>?ref=<bawaan>`) bahwa tiap berkas ada; bila ya, label dilepas dan issue ditutup; bila belum, tetap menunggu.
**Audit [saya].** `cve-audit.sh` membandingkan `actions/workflows` (cabang bawaan) dengan berkas workflow terjadwal di integrasi, dan mencetak "N alur terjadwal belum aktif (hanya di integrasi)" di ringkasan.
**Dokumen [saya].** `skills/orchestrate/SKILL.md` (langkah label dan `menunggu-rilis`), README satu paragraf, `templates/WORKFLOW.md` bila perlu. Rilis kandidat 0.10.0 (perilaku orkestrator berubah).

## Keputusan tambahan (hasil pemeriksaan builder; semuanya **[saya]**, owner boleh membalik)
- **Bukti terintegrasi.** Lolos bila PR `merged_at` terisi **dan** salah satu: `base.ref` = integrasi; `merge_commit_sha` PR leluhur `origin/<integrasi>`; atau `head.sha` PR leluhur `origin/<integrasi>`. Kasus yang tak terdeteksi: PR bertumpuk di-squash ke induk, lalu induk di-squash ke integrasi (tidak ada SHA yang menjadi leluhur). Hasilnya ditolak fail-closed dengan pesan jelas; owner memberi label manual. Biayanya: label manual pada kasus langka itu.
- **`--after` tidak diubah.** Pemeriksa baru hanya membandingkan cabang tujuan PR dengan integrasi; keberadaan commit merge di cabang tujuan tetap tugas `--after`.
- **`resume.sh` tetap hanya-baca.** Pemeriksa dipanggil orkestrator di langkah `selesaikan-merge`; `resume.sh` hanya mengeluarkan aksi baru `periksa-rilis` untuk issue berlabel `menunggu-rilis`. `resume.sh` dan pemeriksa memakai `gh api` (REST), bukan `gh pr`, supaya tahan batas GraphQL; 403/429 -> exit 2.
- **Siklus `menunggu-rilis`.** `di-integrasi` tetap dipasang (memang sudah di integrasi) bersama `menunggu-rilis`. `board.sh --sync` tidak menutup issue yang berlabel `menunggu-rilis`. Setiap putaran, orkestrator memeriksa issue berlabel itu: semua berkas pemicu (dari komentar issue) ada di cabang bawaan -> label dilepas dan issue ditutup. "Ada" berarti berkas ada di `contents?ref=<bawaan>`; versi lama yang hanya diubah di integrasi lolos (batas yang diketahui; builder boleh memperketat dengan blob sha bila murah).
- **`board.sh --sync`.** Nomor PR dicari lewat REST (head `issue-<n>`); tanpa PR atau lebih dari satu PR merged -> issue tidak ditutup dan dilaporkan.
- **Nama cabang integrasi.** Dibaca seperti `workflow.sh`/`label.sh` (env atau baris `Cabang integrasi:`). Bila `WORKFLOW.md` tak terbaca atau namanya kosong padahal PR berbasis cabang selain bawaan, pemeriksa exit 2 (bukan "tanpa integrasi").
- **Daftar berkas pemicu #32** dipisah jadi skrip kecil yang dipakai gerbang, orkestrator, dan audit (bukan parsing keluaran gerbang). Berkas `removed` dilewati, `renamed` memakai nama baru, dan daftar berkas PR diambil walau diff tidak menyentuh manifest. `cve_fetch` dipindah agar bisa dipakai bersama.
- **Audit.** Memakai `git fetch` dan `git ls-tree origin/<integrasi>` (bukan `git ls-files` checkout) dan menambah satu baris ke keluaran yang ada; mencakup `dependabot.yml`.
- **Nama label.** `menunggu-rilis` dapat dikonfigurasi lewat `label.sh` (`Label menunggu rilis:`), sama seperti label lain.

## Kendala
- Tes tanpa jaringan: repo git sementara dengan remote bare lokal, `gh` palsu untuk REST (`pulls/N`, `pulls/N/files`, `contents`). Bash 3.2 (macOS) dan Linux CI; artefak berbahasa Indonesia.

## Kriteria selesai
- Tes merah dulu: PR merged ke cabang induk tidak diberi `di-integrasi`, tidak ditutup, kartu tidak ke Done; PR merged ke integrasi (langsung atau lewat leluhur) tetap diberi; REST gagal = tidak ada yang diberikan; PR ke integrasi yang menambah workflow terjadwal atau `dependabot.yml` menghasilkan peringatan, PR ke cabang bawaan tidak, workflow tanpa pemicu terjadwal tidak; `menunggu-rilis` dilepas dan issue ditutup hanya setelah berkas ada di cabang bawaan; audit melaporkan jumlah alur belum aktif. `bash tests/run.sh` → `SEMUA LULUS`.

## Diserahkan ke builder
Nama dan argumen pemeriksa, format komentar `menunggu-rilis`, cara mengurai daftar berkas dari komentar, penyusunan fixture, dan penanganan nama cabang berisi `/`.
