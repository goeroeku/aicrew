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

## Keputusan saya (owner menyerahkan desain)
1. **Skill, agen, template: hanya Inggris** (satu berkas, tanpa dua salinan). Skill tidak bisa berganti berkas saat berjalan, dan dua salinan akan menyimpang. Pengguna Indonesia tetap dijawab dalam bahasanya karena tiap skill/agen memuat satu aturan: "Reply in the language the user writes in; write issues, PRDs and comments in the language set by `Language:` in docs/WORKFLOW.md, or the user's language when it is absent."
2. **`Language:` di WORKFLOW.md** (`en` | `id`, ditanyakan kickoff, tulis sekali). Nilai tak dikenal = `en`. Env `AICREW_LANG` menang atas WORKFLOW.md. Tanpa keduanya, pesan skrip berbahasa Inggris.
3. **Katalog pesan dua bahasa untuk skrip**: `scripts/lib/msg.sh` dengan `msg <kunci> [argumen...]`, katalog `scripts/lib/msg/en.sh` dan `scripts/lib/msg/id.sh` berupa fungsi `case` per kunci (bash 3.2 macOS tidak punya array asosiatif). Kunci yang tak ada di `id.sh` jatuh ke `en.sh`; tak ada di keduanya mencetak kuncinya (gagal terlihat, tidak diam). Hanya teks yang dibaca manusia yang dikatalogkan; kolom TSV dan nilai mesin tidak.
4. **Tes lama tetap utuh**: `tests/run.sh` mendapat SATU baris awal `export AICREW_LANG=id` sehingga semua pernyataan teks Indonesia pada pesan skrip lama tetap lulus tanpa diubah. Tes baru memeriksa bawaan Inggris, paritas kunci `en.sh` dan `id.sh`, dan jatuh-ke-en. Tes yang memeriksa teks Indonesia di dalam skill/agen/template tidak bisa dipertahankan (isinya berubah): itu butuh satu persetujuan owner `test-change tests/run.sh` di PR yang menerjemahkan, dan setiap tes yang diubah diganti dengan pernyataan setara pada kata kunci Inggris (bukan dihapus).
5. **Alias usang**: tidak ada perubahan; nama lama tetap.

## Tahap (tiap tahap satu atau lebih PR, rilis tidak otomatis)
- **A. Agen dan template** (8 + 6 berkas): terjemahan Inggris, aturan bahasa di atas, tes yang menjaga kata kunci.
- **B. Skill** (5 berkas): terjemahan; kickoff menanyakan `Language:` dan menulisnya; `templates/WORKFLOW.md` memuat baris `Language:`.
- **C. Infrastruktur katalog**: `msg.sh`, `en.sh`/`id.sh` kosong-awal, pembaca bahasa, tes paritas, `export AICREW_LANG=id` di tes.
- **D. Migrasi pesan skrip** per kelompok (gerbang, autopilot/orkestrasi, pembersih/rilis, sisanya): tiap kelompok memindahkan pesan ke katalog dengan teks Indonesia persis yang lama di `id.sh` (tes lama lulus tanpa diubah) dan terjemahan di `en.sh`.
Urutan A, B boleh paralel dengan C; D setelah C.

## Kriteria selesai
- [ ] A dan B: tak ada teks Indonesia di luar blok kode pada skill/agen/template (tes memeriksa dengan daftar kata kunci Indonesia yang sudah ada di tes bahasa publik).
- [ ] `Language: id` / `AICREW_LANG=id` menghasilkan pesan Indonesia persis seperti sebelum perubahan (tes lama lulus tanpa diubah selain satu baris `export`).
- [ ] Tanpa keduanya, pesan skrip berbahasa Inggris (tes baru per kelompok).
- [ ] `en.sh` dan `id.sh` punya kunci yang sama (tes).
- [ ] README menjelaskan pilihan bahasa; skill tidak memuat kata pemicu Indonesia.
