# Bahasa Inggris sebagai bawaan, Indonesia sebagai pilihan (#64)

## Masalah
Nama teknis sudah Inggris (#55, 1.1.0), tetapi isi skill, agen, template, dan pesan skrip masih Indonesia. Pengguna dunia (mayoritas Inggris) mendapat dokumen dan pesan yang tidak bisa dibaca; pengguna Indonesia harus tetap nyaman.

## Ukuran (dihitung di origin/main)
Skill 5 berkas (~370 baris), agen 8 (~150), template 6 teks (~270), skrip 44 berkas dengan sekitar 190 baris pesan. `tests/run.sh` 3000+ baris, sebagian memeriksa teks Indonesia pada pesan dan pada skill/template.

## Tujuan
- Bawaan Inggris untuk skill, agen, template, dan pesan skrip.
- Indonesia tetap tersedia untuk pesan skrip (`Language: id` di `docs/WORKFLOW.md`, atau env `AICREW_LANG=id`).
- Masukan pengguna dalam bahasa apa pun dipahami; skill tidak memuat kata pemicu Indonesia sebagai perintah.

## Bukan tujuan
- Komentar kode di dalam skrip dan nama berkas spesifikasi lama di `docs/superpowers/` (pengembang-menghadap; dicatat sebagai pekerjaan lepas bila diminta).
- Mengubah nama teknis, kunci WORKFLOW, label, kolom TSV, atau kode keluar.
- Menerjemahkan isi issue/PRD proyek pengguna yang sudah ada.

## Kontrak mesin berbahasa Indonesia (tidak diterjemahkan)
Skrip dan tes membaca balik token berikut lewat grep; terjemahan akan memutus gerbang merge. Token ini TETAP APA ADANYA di semua bahasa, ditulis di dalam blok/kode-span pada skill, agen, dan template, dengan satu kalimat Inggris yang menyatakan bahwa token harus dipakai persis:
- vonis agen: `Laporan qa|security|perf: lulus|gagal`, `Commit:`, `Angka sebelum/sesudah:`, `Tuning:`, `Pengecualian disetujui owner (<cakupan>): ... (Commit: <sha>)`, `Decision applied:`, `owner-action:`, `blocked:`, `blocked-by-permission:` (`pr-merge-check.sh:169-174`, `release-report.sh:36`).
- heading dibaca skrip: `## Daftar periksa rilis` (`release-report.sh:68-69`, `templates/WORKFLOW.md:60`), `## Temporary grants`.
- penanda lintas-skrip: stderr `tidak lengkap` dan `dilewati (privat):` dari `cve-check.sh` (dibaca `cve-audit.sh:32`, `pr-merge-check.sh:287-289`), prefiks `GAGAL:` / `PERINGATAN:` (93 pemakaian di 11 berkas, 43 di tes), baris `board:` dari `board.sh` (dibaca `autopilot.sh:84`).
Tahap D memulai tiap kelompok dengan audit: pesan yang di-grep skrip lain atau tes lama sebagai kontrak TIDAK dikatalogkan (tetap literal dengan komentar `# machine contract`). Mengganti kontrak ini dengan alias Inggris di parser adalah pekerjaan lepas terpisah, bukan bagian #64.

## Keputusan saya (owner menyerahkan desain)
1. **Skill, agen, template: hanya Inggris** (satu berkas, tanpa dua salinan). Skill tidak bisa berganti berkas saat berjalan, dan dua salinan akan menyimpang. Pengguna Indonesia tetap dijawab dalam bahasanya karena tiap skill/agen memuat satu aturan: "Reply in the language the user writes in; write issues, PRDs and comments in the language set by `Language:` in docs/WORKFLOW.md, or the user's language when it is absent."
2. **`Language:` di WORKFLOW.md** (`en` | `id`, ditanyakan kickoff, tulis sekali; kunci baru, dipetakan di `wf-normalize.sh`). Nilai tak dikenal = `en`. Urutan baca: env `AICREW_LANG`, lalu `AICREW_ENV_FILE` (berkas env yang sudah dibaca autostart/launchd), lalu `Language:` di `docs/WORKFLOW.md` repo (dicari dari `git rev-parse --show-toplevel`; skrip terjadwal sudah `cd` ke repo), lalu `en`. Berbeda dari `Artifact language:` yang sudah ada (bahasa kode, commit, label; bawaan English): `Language:` adalah bahasa untuk manusia (keluaran skrip, jawaban agen, komentar dan dokumen yang ditulis agen). Aturan bahasa yang sudah ada di `agents/*.md` (mis. senior-coder) disatukan ke dua kunci itu pada Tahap A.
3. **Katalog pesan dua bahasa untuk skrip**: `scripts/lib/msg.sh` dengan `msg <kunci> [argumen...]`, katalog `scripts/lib/msg/en.sh` dan `scripts/lib/msg/id.sh` berupa fungsi `case` per kunci (bash 3.2 macOS tidak punya array asosiatif). Kunci yang tak ada di `id.sh` jatuh ke `en.sh`; tak ada di keduanya mencetak kuncinya (gagal terlihat, tidak diam). `msg` HANYA memformat ke stdout dengan `printf` (argumen banyak, tanpa subshell mahal); pemanggil memilih `>&2`, prefiks (`GAGAL:`, `PERINGATAN:`, `autonomy:`) dan kode keluar. Pesan yang dirakit di dalam `jq` menerima teks dari `msg` lewat `--arg`. Hanya teks untuk manusia yang dikatalogkan; kolom TSV, nilai mesin, dan kontrak mesin di atas tidak. Berkas log/status (`autopilot.log`, ringkasan owner) ditulis dalam bahasa terpilih saat penulisan; kunci JSON tetap Inggris.
4. **Tes lama sebisanya utuh**: `tests/run.sh` mendapat SATU baris awal `export AICREW_LANG=id` sehingga pernyataan teks Indonesia pada pesan skrip lama tetap lulus tanpa diubah. Pengecualian yang diketahui: tes yang memakai `env -i` (notify, `tests/run.sh:350,409`) membuang env; dua baris itu diubah (mengirim `AICREW_LANG=id` lewat `env -i`) dengan persetujuan owner di PR Tahap D yang memigrasikan `notify.sh`. Tes baru memeriksa bawaan Inggris, paritas kunci `en.sh` dan `id.sh`, dan jatuh-ke-en. Tes yang memeriksa teks Indonesia di dalam skill/agen/template tidak bisa dipertahankan (isinya berubah; contoh `tests/run.sh:366,374,378,553,710-711,1168,1171,1176`). Aturan: PR tiap tahap A/B memulai dengan skrip yang mendaftar semua baris tes yang cocok dengan berkas yang diterjemahkan; daftar itu ditulis di badan PR, owner memberi satu persetujuan `test-change tests/run.sh` yang menyebut daftar itu, dan tiap tes yang diubah diganti dengan pernyataan setara pada kata kunci Inggris atau pada token mesin (bukan dihapus).
5. **Alias usang**: tidak ada perubahan; nama lama tetap.

## Tahap (tiap tahap satu atau lebih PR, rilis tidak otomatis)
- **A. Agen dan template** (8 + 6 berkas): terjemahan Inggris, aturan bahasa di atas, tes yang menjaga kata kunci.
- **B. Skill** (5 berkas): terjemahan; kickoff menanyakan `Language:` dan menulisnya; `templates/WORKFLOW.md` memuat baris `Language:`.
- **C. Infrastruktur katalog**: `msg.sh`, `en.sh`/`id.sh` kosong-awal, pembaca bahasa, tes paritas, `export AICREW_LANG=id` di tes.
- **D. Migrasi pesan skrip** per kelompok (gerbang, autopilot/orkestrasi, pembersih/rilis, sisanya): tiap kelompok memindahkan pesan ke katalog dengan teks Indonesia persis yang lama di `id.sh` (tes lama lulus tanpa diubah) dan terjemahan di `en.sh`.
Urutan A, B boleh paralel dengan C; D setelah C.

## Kriteria selesai
- [ ] A dan B: tak ada teks Indonesia di luar blok/kode-span pada skill/agen/template; tes memakai `IDN` dan `strip_code` yang sudah dipakai tes bahasa publik (`tests/run.sh` sekitar baris 1817-1830, `idn_hits`), diperluas ke berkas-berkas itu, dan token kontrak mesin hanya boleh muncul di dalam kode.
- [ ] Token kontrak mesin di atas tidak berubah (tes lama gerbang, vonis, rilis, cve lulus tanpa diubah).
- [ ] `Language: id` / `AICREW_LANG=id` menghasilkan pesan Indonesia persis seperti sebelum perubahan (tes lama lulus tanpa diubah selain satu baris `export`).
- [ ] Tanpa keduanya, pesan skrip berbahasa Inggris (tes baru per kelompok).
- [ ] `en.sh` dan `id.sh` punya kunci yang sama (tes).
- [ ] README menjelaskan pilihan bahasa; skill tidak memuat kata pemicu Indonesia.
