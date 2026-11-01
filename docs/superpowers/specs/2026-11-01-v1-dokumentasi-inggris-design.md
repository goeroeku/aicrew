# v1.0: permukaan publik berbahasa Inggris, CHANGELOG, kebijakan stabilitas — desain

Status: draf untuk persetujuan owner. **[owner]** = keputusan owner di issue #34 atau disetujui di percakapan ("saya ikut rekomendasi anda"); **[saya]** = keputusan penulis desain, boleh dikoreksi. Issue: #34 (mekanisme `CHANGELOG.md` sudah dibangun di #30).

## Maksud dan alasan
Repo publik, tetapi informasi publiknya berbahasa Indonesia dan `README.md` (180 baris) bercampur dengan catatan rilis: 9 paragraf bertanda versi (0.6.0 ... 0.12.0) yang sebenarnya riwayat perubahan. Tidak ada `CHANGELOG.md`; deskripsi rilis GitHub nyaris kosong. Ada 25 tag (v0.1.0 ... v0.12.0, 2026-10-28 sampai 2026-11-01) dan 33 PR ter-merge. v1.0 menandai bahwa permukaan publik siap dibaca pihak luar dan antarmuka stabil.

## Tujuan
- **Permukaan publik berbahasa Inggris saja**: `README.md`, `PRIVACY.md`, `CHANGELOG.md` (baru), deskripsi `plugin.json` dan `marketplace.json` (dua deskripsi), deskripsi repo GitHub. **[owner: saran saya disetujui]**
- `README.md` menjelaskan kemampuan **saat ini**, bukan sejarah: tanpa paragraf bertanda versi; isinya dibagi ke bagian yang sesuai (pemakaian) dan `CHANGELOG.md` (sejarah). **[owner]**
- `CHANGELOG.md`: Keep a Changelog + SemVer (Added, Changed, Fixed, Security) + bagian **Behavior changes** untuk perubahan bawaan; berisi **isi mundur 0.1.0 sampai 0.12.0**, satu bagian per tag, tanggal dari commit tag. **[owner]**
- Bagian "Stability" di README mendefinisikan antarmuka publik di bawah SemVer: flag dan kode keluar `scripts/*.sh` yang didokumentasikan di README, kunci `docs/WORKFLOW.md`, nama label bawaan, dan format `.aicrew/autopilot.json`. Hal lain (redaksi skill/agen, baris log, pesan) boleh berubah di rilis minor. Kunci dan label bawaan berbahasa Indonesia **stabil di 1.x**; alias Inggris boleh ditambahkan di 1.x (tidak melanggar). **[saya]**
- Metadata GitHub: deskripsi satu kalimat Inggris; topik sudah Inggris; `homepage` dikosongkan (`plugin.json` sudah menunjuk repo). Diterapkan lewat `gh api -X PATCH` hanya setelah owner menyetujui secara eksplisit. **[saya]**
- Kriteria "siap v1.0" **[saya]**: (a) permukaan publik Inggris; (b) `CHANGELOG.md` lengkap 0.1.0 sampai rilis terakhir; (c) bagian Stability ada; (d) tidak ada issue terbuka berlabel `bug`; (e) PR rilis menaikkan versi ke `1.0.0` dan memuat bagian `[1.0.0]` hasil `release-notes.sh`.

## Non-tujuan
- Menerjemahkan bahasa kerja plugin (skill, agen, templat, pesan skrip, kunci `WORKFLOW.md`, label bawaan). Itu pekerjaan terpisah dengan alias (issue baru, atas persetujuan owner). **[owner: saran saya disetujui]**
- Mengubah perilaku apa pun (hanya dokumen dan metadata, tanpa perubahan skrip). **[saya]**
- Dokumen internal `docs/superpowers/specs` dan `plans` tetap Indonesia. **[saya]**

## Anti-tujuan (gagal walau tampak jalan)
- README kehilangan informasi: setiap kemampuan dari 9 paragraf lama harus tetap ada di README (kemampuan saat ini) dan/atau `CHANGELOG.md` (sejarah). Setiap skrip yang kini disebut README tetap disebut.
- `CHANGELOG.md` mengarang sejarah: tiap entri harus dapat ditelusuri ke rentang tag, PR, atau paragraf README lama; yang tidak pasti ditandai, bukan ditebak.
- Tanggal bagian salah (harus dari commit tag) atau ada tag tanpa bagian.
- Teks Indonesia tersisa di permukaan publik (di luar blok kode/kutipan kunci `WORKFLOW.md`).
- Perubahan perilaku tak sengaja (tes lama tetap hijau; tidak ada perubahan di `scripts/`).

## Rancangan
**README [saya].** Kerangka Inggris: apa dan mengapa (satu paragraf); alur (diagram yang ada, diterjemahkan); prasyarat; instalasi dan mulai cepat; konfigurasi (`docs/WORKFLOW.md`: tabel kunci -> arti; kunci tetap Indonesia dengan catatan "by design di 1.x"); otomasi (opsi otomatis, autopilot dengan watchdog idle, calon rilis); journey dan epic; kanban; Orca dan label; pemeriksaan CVE dan paket privat; pembersihan cabang; catatan rilis (`CHANGELOG.md` dari badan PR); mode cadangan REST; notifikasi dan data yang dikirim (tautan `PRIVACY.md`); Stability; peringatan; tes; lisensi dan kredit. Target sekitar 150 baris atau kurang; rincian panjang dipindah ke CHANGELOG atau kepala skrip.
**PRIVACY.md [saya].** Terjemahan setia ke Inggris; tidak ada perubahan makna; tanggal "Last updated" diperbarui.
**CHANGELOG.md [saya].** Disusun oleh agen dari: rentang commit antar tag (`git log vA..vB`), PR ter-merge dalam rentang itu, paragraf README bertanda versi (dipindah, bukan ditulis ulang dari nol), memori rilis. Kategori Keep a Changelog; **Behavior changes** untuk perubahan bawaan yang diketahui: 0.8.0 `Bersihkan setelah merge` bawaan `ya`; 0.9.0 paket privat dilewati dari OSV; 0.10.0 `board.sh --sync` hanya menutup issue dengan bukti PR dan `di-integrasi` hanya setelah `terintegrasi.sh`; 0.11.1 kunci catatan rilis Inggris (kunci 0.11.0 dihapus); 0.12.0 watchdog idle bawaan aktif 30 menit. Tanpa bagian `[Unreleased]` dan tanpa blok tautan perbandingan di dasar berkas (lihat Keputusan tambahan).
**Metadata [saya].** `plugin.json.description` dan `marketplace.json` (dua deskripsi) Inggris; deskripsi repo: "aiCrew: a Claude Code plugin that runs a project workflow from idea to release candidate (kickoff, PRD, issues, parallel execution, autopilot). Part of AICosystem."
**Tes [saya].** Pola deterministik di `tests/run.sh`: (1) tiap tag `vX.Y.Z` yang ada punya `## [X.Y.Z]` di `CHANGELOG.md` dan sebaliknya; (2) README tanpa judul/paragraf bertanda versi `(0.x.y)`; (3) heuristik bahasa: `README.md`, `PRIVACY.md`, `CHANGELOG.md`, deskripsi `plugin.json`/`marketplace.json` tanpa kata fungsi Indonesia (` yang `, ` dan `, ` untuk `, ` dengan `, ` tidak `, ` atau `) di luar blok kode dan kode inline; (4) setiap skrip yang disebut README sebelum perubahan masih disebut (daftar tetap di tes); (5) bagian Stability ada; (6) `plugin.json` versi `1.0.0` dan bagian `[1.0.0]` ada.
**Rilis [saya].** Satu PR "Release 1.0.0" berisi semuanya; badan PR memuat baris `Release note:` (dogfooding #30); `release-notes.sh --versi 1.0.0 --tulis` dijalankan sebelum merge. Metadata GitHub diubah setelah merge, atas persetujuan eksplisit. Alias Inggris untuk kunci/label dicatat sebagai issue baru (atas persetujuan owner) dan tidak menghalangi 1.0.

## Keputusan tambahan (hasil pemeriksaan builder; semuanya **[saya]**)
Catatan: reviewer hanya memeriksa sisi kode (tidak bisa membaca spec karena berkasnya di cabang `desain-v1` dan ia tanpa shell); kontradiksi di dalam spec saya periksa sendiri.
- **Tanpa `[Unreleased]` dan tanpa blok tautan perbandingan** (`[0.12.0]: https://...`) di `CHANGELOG.md`. `release-notes.sh --tulis` menyisipkan bagian baru di atas heading `## [` pertama dan mengganti bagian versi sampai heading berikutnya atau akhir berkas, sehingga `[Unreleased]` akan berada di bawah bagian baru dan blok tautan akan ikut terhapus/terbawa ke bagian terakhir. Tanpa perubahan skrip di rilis ini; format heading persis `## [X.Y.Z] - YYYY-MM-DD`.
- **Bagian `[1.0.0]` wajib hasil `release-notes.sh --versi 1.0.0 --tulis`** (bukan ditulis tangan) dari badan PR rilis (baris `Release note:`); `release.yml` memakai `--ekstrak` dan hanya bekerja bila heading persis `## [1.0.0]`.
- **Tes lama yang mengunci teks README/PRIVACY Indonesia (sekitar 20 baris `grep`, mis. 'Catatan rilis (0.11.0; ...)', 'Watchdog idle (0.12.0)', 'Integrasi terverifikasi (0.10.0)', 'Paket privat:', 'Satu-satunya jaringan keluar', 'Pemeriksaan CVE:', 'mode cadangan REST', 'Bersihkan setelah merge', 'Konsep (0.6.1)') diubah di PR yang sama**: kunci teks/kata kunci diganti padanan Inggris yang menjaga maknanya; tes yang mengunci judul bertanda versi dipindah menjadi pemeriksaan CHANGELOG. Kutipan kunci `WORKFLOW.md` (`Cabang integrasi:`, `Tutup issue setelah merge integrasi`, dst.) tetap Indonesia karena di-parse skrip.
- **Heuristik bahasa**: berlaku hanya pada berkas publik yang terdaftar (README, PRIVACY, CHANGELOG, deskripsi `plugin.json`/`marketplace.json`, teks `userConfig` di `plugin.json`), di luar blok kode berpagar dan kode inline; kata fungsi Indonesia: ` yang `, ` dan `, ` untuk `, ` dengan `, ` tidak `, ` atau `, ` bila `, ` dari `, ` ini `, ` adalah `; ditambah daftar kata judul Indonesia (`Kebijakan`, `Peringatan`, `Prasyarat`, `Pasang`, `Alur`, `Lisensi`, `Tes`, `Opsi`) agar judul seperti `# Kebijakan privasi aiCrew` tertangkap.
- **Permukaan publik tambahan** yang diterjemahkan: teks `userConfig` (title/description) di `plugin.json` (tampil ke pengguna). `templates/*` (termasuk `pull_request_template.md`), skill, agen, dan pesan skrip adalah bahasa kerja plugin (di luar cakupan); bahasa tiap templat diverifikasi builder.
- **Isi mundur tidak boleh mengarang**: tag awal (0.1.0 sampai sekitar 0.3.0) tanpa PR disusun dari rentang commit dan paragraf README lama; entri yang tidak pasti dihilangkan atau ditandai, bukan ditebak; `(#N)` hanya untuk PR nyata (efek samping benar: PR lama itu tidak muncul lagi di jendela rilis berikutnya karena dedupe). Hasilnya ditinjau owner di PR; `release-notes.sh` tidak dipakai untuk isi mundur (butuh `--sejak` dan baris bertanda yang belum ada).
- **Versi**: PR ini adalah PR rilis 1.0.0: `plugin.json` -> `1.0.0` dan pin versi di tes dinaikkan; merge = rilis 1.0.0 (persetujuan eksplisit owner).
- **Metadata GitHub**: `gh api -X PATCH repos/goeroeku/aicrew` memerlukan hak admin repo (token `gh` owner; bukan token Actions). Bila ditolak, owner menjalankannya manual; perintah disiapkan di PR.

## Kendala
- Tanpa perubahan di `scripts/` dan `skills/`; tes lama tetap hijau. Bash 3.2 dan Linux untuk tes baru. Artefak internal (spesifikasi, plan, ledger) tetap Indonesia.

## Kriteria selesai
- Tes merah dulu untuk pola 1 sampai 6 di atas, lalu hijau; `bash tests/run.sh` -> `SEMUA LULUS`. Owner meninjau README dan CHANGELOG sebelum merge; rilis lewat alur rilis (owner menyetujui sebelum merge).

## Diserahkan ke builder
Pembagian isi README antar bagian, urutan kerja penyusunan CHANGELOG (per rentang tag), pemisahan blok kode untuk heuristik bahasa, penanganan tag sebelum ada PR (0.1.0 sampai ~0.3.0 berupa commit langsung), dan redaksi bagian Stability.
