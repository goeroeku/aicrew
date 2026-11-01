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

## Keputusan tambahan (hasil pemeriksaan builder; semuanya **[saya]**)
- **Sumber pola tak terbaca di gerbang = fail-closed.** `docs/WORKFLOW.md` atau `.npmrc` pada cabang tujuan yang gagal dibaca selain 404 (`pr-merge-check.sh:87` kini meneruskan ke pemeriksaan) menolak PR yang menyentuh manifest, karena kalau diteruskan nama privat bisa terkirim. 404 = tidak ada berkas = tanpa pola dari sumber itu.
- **PR pembuka (menambah pola sekaligus dependensi privat).** Gerbang memakai pola cabang tujuan, jadi pola yang baru ditambah PR itu belum berlaku. Urutan migrasi yang benar: **merge dulu PR yang hanya memuat pola** (tidak menyentuh manifest, jadi tidak ada pemeriksaan CVE dan tidak ada yang terkirim), baru PR yang menambah dependensi privat. Gerbang memperingatkan (`PERINGATAN`, tidak memblokir) bila PR menyentuh manifest dan sekaligus menambah baris `Paket privat:` atau scope `.npmrc` yang belum ada di cabang tujuan: "pola baru baru berlaku setelah di-merge; paket yang cocok pada PR ini tetap dikirim".
- **`.npmrc` ke proxy.** Hanya pemetaan scope yang dibaca; host dinormalisasi (tanpa skema dan `/` akhir, huruf kecil); `registry.npmjs.org` dan `registry.yarnpkg.com` dianggap publik. Scope publik yang sengaja dipetakan ke proxy (mis. `@types`) ikut dilewati; dampaknya dilaporkan lewat jumlah paket yang tak diperiksa, dan README menyarankan menghapus pemetaan scope publik dari `.npmrc` bila ingin tetap diperiksa. Pemetaan `registry=` global tidak pernah dipakai.
- **Pola Go.** Semantik awalan modul berlaku untuk entri Go dari SEMUA sumber (pola `git.corp.com/team` cocok dengan `git.corp.com/team/x`), bukan hanya GOPRIVATE.
- **`.npmrc` di monorepo.** Untuk tiap lockfile, gerbang membaca `.npmrc` di direktori lockfile itu dan di akar repo (digabung, tanpa duplikat); audit membaca berkas yang sama dari disk.
- **Normalisasi.** Pola dinormalisasi seperti nama untuk entri PyPI (huruf kecil, `.` dan `_` menjadi `-`); npm dan Go dicocokkan apa adanya.
- **Pelaporan "tidak diperiksa".** Bila semua paket yang berubah privat, gerbang tetap lolos dengan `PERINGATAN` jumlah. `cve-audit.sh` tidak lagi menulis "tidak ada kerentanan diketahui" tanpa catatan: dengan paket yang dilewati kalimatnya "... untuk <berkas> (N paket privat tidak diperiksa)", dan bila semuanya dilewati "semua dependensi dilewati (privat); tidak ada yang diperiksa".
- **GOPRIVATE di mesin gerbang.** Bantuan, bukan sumber utama: untuk gerbang, utamakan baris `Paket privat:` (ikut repo, tidak bergantung mesin). Tidak ada peringatan khusus bila GOPRIVATE kosong (akan bising untuk semua repo Go publik); README dan `PRIVACY.md` menyebut hal ini.

## Kendala
- Tes tanpa jaringan: `curl` palsu mencatat badan permintaan; fixture lockfile campuran privat dan publik.
- Jalan di macOS (bash 3.2) dan Linux CI; bahasa artefak Indonesia.

## Kriteria selesai
- Tes merah dulu: nama yang dilewati tidak pernah ada di badan permintaan `curl` (termasuk kueri basis dan `prefetch`); tiap sumber (WORKFLOW, GOPRIVATE dengan awalan modul, `.npmrc` scope non-publik) bekerja, `.npmrc` scope ke `registry.npmjs.org` tidak membuat apa pun privat; baris `.npmrc` ber-token tidak pernah tampil; pola `*` diabaikan dengan peringatan; PR yang menambah pola di cabangnya sendiri tidak berpengaruh di gerbang; gerbang mencetak jumlah tanpa nama; `cve-audit` melaporkan jumlah; `bash tests/run.sh` -> `SEMUA LULUS`.
- `PRIVACY.md`, templat WORKFLOW, README diperbarui; rilis lewat alur rilis (kandidat 0.9.0, owner menyetujui sebelum merge).

## Diserahkan ke builder
Bentuk pengumpul pola (skrip atau fungsi), format `--private`, implementasi pencocokan awalan modul Go, dan penyusunan fixture.
