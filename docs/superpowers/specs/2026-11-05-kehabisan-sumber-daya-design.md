# Pemeriksaan kehabisan sumber daya dan crash sebelum produksi (#71)

## Masalah
Owner mengalami masalah I/O Postgres yang tidak tertangkap di pengembangan dan baru muncul di produksi. aiCrew sudah punya `needs-perf` dan agen `aicrew-perf` (anggaran I/O, inventaris konfigurasi, angka sebelum/sesudah), tetapi tidak memeriksa pekerjaan tak terbatas dari input kecil (CWE-400/770), tidak menjalankan beban lokal terhadap anggaran, tidak punya aturan artefak crash, dan PRD/breakdown tidak meminta batas per endpoint.

## Jawaban owner atas pertanyaan terbuka
Yang dimaksud adalah proses yang membuat aplikasi crash atau menghabiskan sumber daya (CPU, memori, I/O, koneksi) sampai aplikasi atau server berhenti. Aturan higiene crash dump (core/heap dump berisi rahasia) dicatat tetapi sekunder; dump database tidak termasuk.

## Tujuan
- Pekerjaan yang memproses input tak terbatas ditandai `needs-perf` dan `needs-security` pada breakdown, bukan ditebak saat eksekusi.
- Tiap endpoint atau job di PRD menyatakan batasnya (ukuran, waktu, laju, memori), dan kriteria selesai issue menguji batas itu.
- `aicrew-perf` menjalankan langkah beban lokal berbatas dengan anggaran tertulis dan melaporkan p95, memori puncak, dan I/O.
- `aicrew-security` memeriksa kehabisan sumber daya dan higiene artefak crash.
- Laporan kandidat rilis memuat hasil beban terakhir dan batas perangkat keras.

## Bukan tujuan
- Mengubah kontrak mesin (`Laporan perf: lulus|gagal`, `Angka sebelum/sesudah:`, `Tuning:`, `Commit:`) atau gerbang `pr-merge-check.sh`. Isi baris `Angka sebelum/sesudah:` tetap harus berdigit; gerbang tidak menilai kualitas angka (batas yang sama seperti sekarang).
- Alat beban sendiri (k6/wrk/pgbench dipilih per stack oleh agen), pengujian pada server nyata (tetap butuh izin owner), DDoS, dump database.
- Penegakan oleh mesin atas batas per endpoint (tahap ini tindakan agen dan teks, bukan gerbang).

## Rancangan (hanya teks dan tes; tanpa skrip baru)
1. **`templates/PRD.md`**: bagian baru `## Abuse cases and limits` setelah Non-functional requirements: tabel `| Endpoint/job | Max size | Max time | Max rate | Max memory | Behavior at the limit |`; aturan: setiap endpoint atau job yang menerima input luar punya satu baris; "none" harus beralasan.
2. **`skills/breakdown/SKILL.md`** (langkah 6 dan bagian NFR): `needs-perf` juga untuk isu yang menyentuh kelas input tak terbatas: badan request/unggahan, arsip (decompression bomb), regex pada input pengguna (ReDoS), kueri tanpa limit/paginasi, loop/rekursi yang dikendalikan input, parser, cache tanpa batas, kolam koneksi; `needs-security` bila di batas kepercayaan. Kriteria selesai isu seperti itu wajib memuat uji pada batas dari tabel `Abuse cases and limits` (input tepat di batas lolos, di atas batas ditolak atau dibatasi tanpa crash).
3. **`agents/perf.md`**: langkah "Load smoke" untuk isu kelas di atas: jalankan beban LOKAL dengan alat yang cocok stack (mis. k6, wrk, hey, pgbench), anggaran tertulis (p95, memori puncak, I/O) diambil dari PRD atau ditetapkan agen dan dicatat, lapor satu baris `Load smoke: <perintah> | budget <...> | p95 <n> | peak mem <n> | io <n>` SEBELUM empat baris vonis; tanpa angka = `gagal`; tidak pernah ke server nyata tanpa izin owner; kalimat tegas bahwa angka lokal tidak menggantikan ukur di perangkat keras nyata.
4. **`agents/security.md`**: daftar periksa kehabisan sumber daya (batas ukuran/waktu/laju, ReDoS, bom dekompresi, kueri tanpa limit, kolam koneksi, rekursi) dan higiene artefak crash: core/heap/memory dump tidak diaktifkan di produksi secara bawaan (mis. `ulimit -c 0`, `fs.suid_dumpable=0`, `core_pattern` terkontrol; JVM `HeapDumpOnOutOfMemoryError` ke jalur terlindungi; Node `--heapsnapshot-signal` tidak aktif), tidak masuk repo (`.gitignore` untuk `core.*`, `*.hprof`, `*.dmp`) dan tidak diunggah sebagai artefak CI atau lampiran issue.
5. **`templates/WORKFLOW.md`** `## Daftar periksa rilis` (judul tetap persis): ganti butir perf dengan butir yang memuat hasil `Load smoke:` terbaru dan batas perangkat keras; tambah butir artefak crash.
6. **Tes**: pernyataan baru atas keberadaan tiap teks di atas (tanpa mengubah tes lama; teks lama yang diuji tetap ada), termasuk bahwa token vonis perf tidak berubah dan bahwa `Load smoke:` ada tepat satu kali sebelum token vonis di `agents/perf.md`.

## Kriteria selesai
- [ ] PRD template punya bagian batas per endpoint/job; breakdown mengharuskan uji batas di kriteria selesai.
- [ ] Breakdown memetakan kelas input tak terbatas ke `needs-perf` dan `needs-security`.
- [ ] Agen perf punya langkah Load smoke berbatas (lokal, anggaran, p95/memori/I/O, larangan server nyata, catatan angka lokal).
- [ ] Agen security punya daftar kehabisan sumber daya dan higiene artefak crash.
- [ ] Daftar periksa rilis memuat hasil beban terakhir dan batas perangkat keras; judul `## Daftar periksa rilis` tidak berubah.
- [ ] Tes lama gerbang/vonis/rilis lulus tanpa diubah; tes baru mengunci teksnya.

## Keputusan saya (owner menyerahkan desain)
Teks dan tes saja, tanpa skrip atau perubahan gerbang; `Load smoke:` baris tambahan sebelum vonis, tidak dipaksa gerbang; alat beban dipilih agen per stack; penegakan mesin atas batas per endpoint ditunda (catatan: bisa jadi issue lanjutan bila owner mau).
