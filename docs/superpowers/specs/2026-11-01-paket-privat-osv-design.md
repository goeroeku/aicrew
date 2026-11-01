# Paket privat tidak dikirim ke OSV — desain

Status: draf untuk persetujuan owner. **[owner]** = disetujui owner ("sesuai") atas rancangan di percakapan; **[saya]** = keputusan penulis desain, boleh dikoreksi. Issue: #25.

## Maksud dan alasan
`cve-check.sh` mengirim semua dependensi di lockfile ke `api.osv.dev`, termasuk nama paket privat. Pemakai dengan repo privat (Nexora: `go.mod` memuat nama modul privat) menahan pembaruan karena itu. Satu-satunya jalan keluar sekarang adalah mematikan seluruh pemeriksaan (`Pemeriksaan CVE: tidak`), padahal mereka tetap ingin memeriksa dependensi publik. `PRIVACY.md` sudah menyebut bahwa nama privat ikut terkirim.

Fakta yang membentuk desain: banyak organisasi memakai proxy (mis. Artifactory) untuk `npmjs`, sehingga URL `resolved` di `package-lock.json` semuanya mengarah ke registry internal; menebak "privat" dari URL itu akan mematikan pemeriksaan untuk semua paket tanpa disadari.

## Tujuan
- Paket yang dinyatakan privat oleh pemiliknya **tidak pernah** dikirim ke OSV; pemeriksaan paket publik tetap jalan. **[owner]**
- Sumber "privat" hanya pernyataan eksplisit pemilik, tanpa tebakan: **[owner]**
  1. baris `Paket privat: <pola>, <pola>` di `WORKFLOW.md` (glob pada nama paket, semua ekosistem);
  2. Go: `GOPRIVATE` (variabel lingkungan, atau `go env GOPRIVATE`);
  3. npm: scope yang dipetakan ke registry non-publik di `.npmrc` proyek (`@acme:registry=<URL bukan registry.npmjs.org>` -> pola `@acme/*`).
- Paket yang dilewati dilaporkan jujur ("tidak diperiksa"), tidak pernah dianggap aman. **[owner]**
- Pola dibaca dari **cabang tujuan** pada gerbang (bukan dari PR), supaya PR tidak bisa mematikan pemeriksaan dengan menambah pola. **[owner]**

## Non-tujuan
- Menebak dari URL `resolved`, dari visibilitas repo, atau dari registry global (`registry=`). **[owner]**
- Deteksi otomatis untuk PyPI (tidak ada sumber yang andal); hanya daftar eksplisit. **[owner]**
- Membaca `~/.npmrc` pengguna: berisi token. Hanya `.npmrc` proyek. **[saya]**

## Anti-tujuan (gagal walau tampak jalan)
- Nama paket yang dilewati muncul di badan permintaan ke OSV (sekecil apa pun, termasuk paket privat yang ikut dalam kueri versi basis).
- Pola `*` (atau pola yang cocok semuanya) mematikan pemeriksaan secara diam-diam.
- Paket yang dilewati terlihat seperti lolos (tanpa jejak di gerbang/audit).
- Isi `.npmrc` selain pemetaan scope ke registry (token, `_authToken`) terbaca, dicetak, atau dikirim.
- Nama paket privat bocor ke keluaran gerbang yang bisa masuk komentar/log publik.

## Rancangan
**Pola [saya].** Satu fungsi di `cve-check.sh` menerima daftar pola (opsi `--private <berkas>`, satu pola per baris, atau env `CVE_PRIVATE` dipisah koma) dan membuang dependensi yang namanya cocok (`case` glob) **sebelum** kueri apa pun, termasuk `prefetch` dan kueri versi basis. Pola Go (GOPRIVATE) hanya berlaku untuk entri ekosistem Go dan memakai semantik awalan modul (pola dicocokkan ke tiap awalan jalur: `a`, `a/b`, `a/b/c`; `*` yang melintasi `/` dibolehkan karena keliru ke arah lebih banyak yang dilewati = lebih privat). Pola `@scope/*` dari `.npmrc` hanya untuk npm. Pola `WORKFLOW.md` untuk semua ekosistem.
**Pengumpul pola [saya].** Skrip kecil `cve-private.sh` (atau fungsi) yang menghasilkan daftar pola gabungan dari tiga sumber di atas; parameter menentukan asal berkas: lokal (audit: `workflow.sh` + `.npmrc` di akar repo) atau REST pada cabang tujuan (gerbang: `docs/WORKFLOW.md` yang sudah diambil untuk opt-out, dan `.npmrc` lewat `cve_fetch`). `GOPRIVATE` selalu dari mesin yang menjalankan (bukan dari repo).
**`.npmrc` [saya].** Hanya baris berpola `^@scope:registry=<URL>`; host selain `registry.npmjs.org` -> privat. Baris lain tidak pernah dibaca atau dicetak.
**Pola `*` [saya].** Pola yang hanya `*` (atau `**`) diabaikan dengan `PERINGATAN: pola '*' mematikan pemeriksaan; pakai "Pemeriksaan CVE: tidak"`.
**Pelaporan [saya].** `cve-check.sh` mencetak ke stderr `dilewati (privat): <nama>@<versi>` per paket (hanya terlihat saat dijalankan langsung). Gerbang mengubahnya menjadi `PERINGATAN: cve (<berkas>) N paket privat tidak diperiksa` **tanpa nama** (agar tak bocor ke log/komentar); `cve-audit.sh` menulis jumlah di ringkasan dan label issue tidak memuat nama paket yang dilewati.
**Dokumen [saya].** `templates/WORKFLOW.md` memuat baris `Paket privat:`; `PRIVACY.md` menjelaskan sumber, bahwa paket yang dilewati tidak diperiksa, dan bahwa `~/.npmrc` tidak dibaca; README satu paragraf pendek.

## Kendala
- Tes tanpa jaringan: `curl` palsu mencatat badan permintaan; fixture lockfile campuran privat dan publik.
- Jalan di macOS (bash 3.2) dan Linux CI; bahasa artefak Indonesia.

## Kriteria selesai
- Tes merah dulu: nama yang dilewati tidak pernah ada di badan permintaan `curl` (termasuk kueri basis dan `prefetch`); tiap sumber (WORKFLOW, GOPRIVATE dengan awalan modul, `.npmrc` scope non-publik) bekerja, `.npmrc` scope ke `registry.npmjs.org` tidak membuat apa pun privat; baris `.npmrc` ber-token tidak pernah tampil; pola `*` diabaikan dengan peringatan; PR yang menambah pola di cabangnya sendiri tidak berpengaruh di gerbang; gerbang mencetak jumlah tanpa nama; `cve-audit` melaporkan jumlah; `bash tests/run.sh` -> `SEMUA LULUS`.
- `PRIVACY.md`, templat WORKFLOW, README diperbarui; rilis lewat alur rilis (kandidat 0.9.0, owner menyetujui sebelum merge).

## Diserahkan ke builder
Bentuk pengumpul pola (skrip atau fungsi), format `--private`, implementasi pencocokan awalan modul Go, dan penyusunan fixture.
