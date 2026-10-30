# Tugas — issue #{{n}}
Kerjakan HANYA issue ini, di worktree saat ini. Jangan commit. Jangan mengubah tes yang ada atau menambah
dependensi; bila perlu, berhenti dan laporkan alasannya.

## Bahasa
Bahasa artefak: Inggris, kecuali `docs/WORKFLOW.md` menyebut bahasa lain atas permintaan owner. Berlaku untuk nama fungsi/variabel/berkas/tabel/kolom, komentar, pesan commit, judul PR, label, dan pesan error. Teks yang dilihat pengguna akhir mengikuti audiens di PRD; pengenalnya tetap Inggris. Bahasa diskusi dengan owner bebas.

## Isi issue
{{tempel isi issue}}

## Bagian PRD terkait
{{kutipan}}

## File terkait
{{path:baris}}

## Verifikasi (wajib)
Jalankan SUITE TES PENUH proyek ({{perintah tes lengkap}}), bukan subset, lalu laporkan perintah dan hasilnya
apa adanya, termasuk yang gagal. Port lokal/Playwright diblokir sandbox: tulis berkas tesnya saja, orkestrator
yang menjalankannya.

## Laporan (maks 12 baris)
Path berkas yang diubah · hasil suite · yang dilewati.
