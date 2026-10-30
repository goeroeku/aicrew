# Gerbang kapasitas dan keamanan untuk aicrew — desain

Status: draf untuk persetujuan owner. Tanda **[owner]** = diputuskan owner dalam percakapan; **[saya]** = keputusan penulis desain, boleh dikoreksi.

## Maksud dan alasan
Kasus mailora (sesi `6f1c6151…`): kode lolos tes dan review, tetapi produksi macet karena I/O Postgres. Akar masalahnya bukan satu bug,
melainkan tiga hal yang tidak pernah diperiksa oleh alur aicrew saat ini:
1. **Anggaran I/O per satuan kerja.** ±36 commit DB per email; `send_attempt` 8 indeks (tanpa HOT update); polling token tiap 2–5 ms; heartbeat menulis ±249 update/detik.
2. **Config bawaan yang tak pernah diukur.** `shared_buffers` 128 MB bawaan; `/dev/shm` 64 MB padahal `shared_buffers` 2 GB; Redis `save 60 10000` menulis RDB 630 MB tiap ±2,7 menit; `mem_limit`/`pids_limit` belum diukur.
3. **Batas perangkat keras tak tercatat.** Disk virtual mentok ±800–850 IOPS tulis; baru ketahuan setelah blast 519 ribu penerima berjalan (restart aplikasi 27×, baris `ambiguous` bertambah).
Secara terpisah, owner ingin keamanan **dimaksimalkan dan di-hardening**, bukan hanya gerbang minimum. Gerbang `needs-security` yang sudah ada (belum di-commit di branch `goeroeku/security-gate`) menjadi dasar.

## Tujuan
- Perubahan yang menyentuh jalur tulis DB, antrean/worker, cron, atau config infra tidak bisa di-merge tanpa **angka** I/O dan pemeriksaan config. **[owner: gerbang menahan merge]**
- Batas perangkat keras host (IOPS, RAM, tier disk, opsi mount) tercatat di `WORKFLOW.md`; "tidak diketahui" dinyatakan eksplisit, bukan diam-diam diasumsikan.
- Security punya dua tingkat: **baseline** untuk semua PR (dicek mesin) dan **ketat** untuk `needs-security` (dicek `aicrew-security` + hardening). **[saya]**
- Sebelum rilis, `release-report.sh` mencetak item perf dan security sebagai kotak kosong yang wajib diisi dengan bukti.
- **Empat artefak bukti selalu ada [owner]:** performa (baris `Angka sebelum/sesudah`), security (`Laporan security`), tuning (baris `Tuning:` berisi config=nilai, alasan, cara rollback, atau `tidak ada`), dan jejak audit (bagian laporan rilis + log audit pada aplikasi yang dibangun). Hilang satu = gerbang menolak.

## Bukan tujuan
- Tidak mengubah server, produksi, atau biaya; aturan `aicrew-devops` (`needs-principal` + konfirmasi owner) tetap.
- Tidak memasang APM/monitoring, tidak mengakses panel penyedia cloud, tidak men-tuning otomatis.
- Tidak menulis ulang role yang ada; tidak menaikkan versi; tidak commit (keputusan owner).

## Anti-tujuan (gagal walau secara teknis jalan)
- Gerbang yang memicu pada hampir semua PR (label hanya untuk cakupan sensitif) sehingga diabaikan.
- Gerbang yang bisa dilewati dengan teks kosong atau klaim tanpa angka.
- Gerbang yang fail-open: label/komentar tak terbaca harus berarti **tolak**.
- Klaim "optimal" tanpa pengukuran, atau saat batas host "tidak diketahui".

## Rancangan

### A. Perf (baru) **[owner: pola sama dengan needs-security]**
- Label `needs-perf`, ditetapkan saat `breakdown` untuk issue yang menyentuh: tulis DB, antrean/worker/polling, cron, config infra (Postgres, Redis, Docker/limit container). **[saya: cakupan]**
- Role `aicrew-perf` (read-only, sonnet, laporan ≤ 12 temuan, `file:baris`). Membawa resep ukur baca-saja dari kasus mailora (host, container, Postgres, Redis; tidak dijalankan di server nyata tanpa izin owner). Memeriksa: (1) anggaran I/O per satuan kerja — commit/fsync per unit, jumlah indeks pada tabel yang sering di-update, interval polling, frekuensi heartbeat; (2) inventaris config default dan konsistensinya (mis. `shared_buffers` vs `/dev/shm`, `save` Redis, `max_connections`, `mem_limit`, `pids_limit`); (3) angka sebelum/sesudah dari ukur lokal.
- Vonis: baris `Laporan perf: lulus|gagal`, wajib disertai baris `Angka sebelum/sesudah:` berisi angka. Tanpa angka = `gagal`. Wajib juga baris `Tuning:` (isi boleh `tidak ada`). **[saya]**
- `pr-merge-check.sh` menolak merge PR/issue `needs-perf` tanpa komentar `Laporan perf: lulus` (pola sama dengan gerbang security yang sudah ada).
- Orkestrator mengirim issue `needs-perf` ke `aicrew-perf` setelah `aicrew-qa`; syarat auto-merge (`agen-setelah-QA`) ikut mencantumkannya.

### B. Fakta host
- Bagian baru `## Batas perangkat keras` di `templates/WORKFLOW.md`: IOPS disk (angka atau "tidak diketahui"), RAM, tier volume, opsi mount (`discard`), batas container. `kickoff` menanyakannya.
- Bila ada issue `needs-perf` dan batas relevan "tidak diketahui", `aicrew-perf` tidak boleh menyatakan `lulus` untuk klaim kapasitas; ia mencatatnya sebagai syarat yang harus diisi owner. **[saya]**

### C. Security dua tingkat **[saya]**
- **Baseline (semua PR, mesin, tanpa jaringan):** pindai diff untuk rahasia (pola kunci/token, `.env`); tandai `|| true` atau pembungkaman error pada jalur durabilitas/keamanan (`sync`, `fsync`, auth, verifikasi); dependensi baru wajib disebut di badan PR. Pemeriksaan berupa skrip deterministik dengan tes di `tests/run.sh`.
- **Ketat (`needs-security`, `aicrew-security`):** daftar periksa diperluas dari auth/otorisasi/input/rahasia/dependensi ke hardening: container (non-root, `read_only`, `cap_drop`, tanpa `privileged`, `mem_limit`/`pids_limit`), port yang terbuka, TLS, log tanpa data pribadi, rate limit, durabilitas (urutan `fsync` + `mv`), backup yang pernah diuji restore, pin versi dependensi/image, **log audit** (aksi sensitif tercatat: siapa, apa, kapan, hasil; tanpa data pribadi; tidak bisa diubah oleh aplikasi yang sama).
- Gerbang `needs-security` yang sudah ada tetap; tidak ada pelonggaran.

### D. Rilis
- `release-report.sh` mencetak item perf (uji beban di server nyata, bukan hanya lokal) dan item hardening security sebagai kotak kosong, dan memvonis fakta: ada/tidaknya komentar `Laporan perf|security: lulus` pada PR ter-merge yang berlabel. Menambah bagian **Jejak audit**: tiap PR berlabel dengan sha, vonis, baris `Tuning:`, dan waiver.

## Kendala
- Bash + `gh` saja (seperti skrip yang ada); tes deterministik tanpa jaringan di `tests/run.sh` dengan `gh` palsu; suite penuh harus hijau.
- Dokumen dan prompt role berbahasa Indonesia, mengikuti berkas yang ada. Tanpa atribusi AI. Satu kata kunci penutup per baris pada PR.
- Jangan membuat berkas dokumen baru di luar kebutuhan (hanya dokumen desain ini).

## Diserahkan ke pembangun
Regex dan ambang pemindaian rahasia; kata-kata tepat prompt `aicrew-perf`; letak inventaris config (prompt role atau template); penamaan item di `release-report.sh`; urutan pengerjaan dan pemecahan menjadi PR kecil.

## Keputusan tambahan setelah pemeriksaan pembangun **[saya, semua boleh dikoreksi]**
- **Baseline memblokir** untuk temuan rahasia; **hanya memperingatkan** untuk `|| true` pada jalur durabilitas/keamanan (terlalu banyak positif palsu untuk memblokir). Berjalan sebagai skrip terpisah yang dipanggil `pr-merge-check.sh`, bukan di dalamnya.
- **Gerbang perf memeriksa isi:** komentar wajib memuat `Laporan perf: lulus` **dan** baris `Angka sebelum/sesudah:` yang memuat minimal satu angka. Sekadar kata "lulus" ditolak.
- **Tanpa "sebelum"** (jalur tulis baru, antrean/cron baru): boleh `lulus` dengan `sebelum: tidak ada (baru)` dan angka "sesudah". Perubahan config murni wajib dua angka.
- **Batas host "tidak diketahui"** untuk klaim kapasitas: vonis `gagal` dengan alasan "isi Batas perangkat keras di WORKFLOW.md"; setelah owner mengisi, laporan dijalankan ulang.
- **Basah/basi:** baris laporan memuat `Commit: <sha>`; gerbang menolak bila bukan head PR saat ini (komit baru = laporan ulang).
- **Pemetaan label:** keduanya (security dan perf) dibaca dari label PR **dan** issue yang ditutup; label tak terbaca = tolak. `release-report.sh` memakai aturan yang sama dan menambah `labels` pada kueri PR.
- **Pemberi komentar:** orkestrator menempel vonis `aicrew-perf`/`aicrew-security` apa adanya (verbatim).
- **Peringatan jalur:** `pr-merge-check.sh` memperingatkan (tidak memblokir) bila diff menyentuh migrasi, `Dockerfile`/compose, config Redis/Postgres, atau berkas antrean/cron tetapi tanpa `needs-perf`.
- **Deteksi dependensi baru:** `package.json`, `go.mod`, `requirements*.txt`, `Cargo.toml`, `Gemfile`, `composer.json`, `FROM` di `Dockerfile`, `image:` di compose. "Disebut" = nama paket/image muncul di badan PR.
- **Rilis:** PR ter-merge berlabel `needs-perf`/`needs-security` tanpa komentar `lulus` membuat vonis **BELUM SIAP**.

## Keputusan owner atas dua pertanyaan terakhir **[owner: "ikut rekomendasi", rekomendasinya dari saya]**
1. **Pengecualian (waiver) ada, tetapi sempit.** Hanya owner yang boleh menulisnya, dalam bentuk komentar PR
   `Pengecualian disetujui owner (perf|rahasia): <alasan> (Commit: <sha>)` (cakupan wajib; satu waiver tidak menutup cakupan lain, hasil review). Terikat ke head PR (komit baru = batal), wajib beralasan, dan
   dicetak di bagian tersendiri pada laporan rilis supaya tidak tersembunyi. Berlaku untuk gerbang perf dan temuan pemindai rahasia;
   tidak berlaku untuk label yang tak terbaca (fail-closed tetap). Agen dilarang menulis komentar ini (aturan tertulis di prompt role;
   skrip tidak bisa membedakan penulis, lihat Risiko).
2. **Commit diizinkan** di branch `goeroeku/security-gate` setelah dokumen ini disetujui, satu commit per irisan kecil, pesan dalam bahasa
   Indonesia mengikuti riwayat repo, tanpa atribusi AI. **Push dan pembukaan PR tetap menunggu perintah owner.**

## Menunggu jawaban owner
Tidak ada. Menunggu persetujuan dokumen ini secara keseluruhan.

## Risiko yang diketahui (belum diputuskan)
- Komentar `Laporan … lulus` bisa ditulis siapa pun yang punya akses PR; skrip hanya memeriksa kehadirannya.
- `needs-perf` bergantung pada ketepatan penandaan di `breakdown`; penandaan yang terlewat tidak tertangkap oleh gerbang.
