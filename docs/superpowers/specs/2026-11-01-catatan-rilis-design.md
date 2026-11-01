# Catatan rilis: CHANGELOG.md dari badan PR — desain

Status: draf untuk persetujuan owner. **[owner]** = keputusan owner di issue #30 atau disetujui di percakapan ("setuju dengan usulan anda"); **[saya]** = keputusan penulis desain, boleh dikoreksi. Issue: #30 (dan jalur yang sama untuk #34).

## Maksud dan alasan
Tidak ada `CHANGELOG.md`; deskripsi rilis GitHub dibuat otomatis dari judul PR sehingga nyaris kosong (v0.8.0: 214 karakter); `release-report.sh` hanya mendaftar judul PR ter-merge; tidak ada template badan PR dan tidak ada aturan catatan rilis di `templates/WORKFLOW.md`. Pelajaran 0.8.0: bawaan yang mengubah perilaku pemasangan lama tidak tercatat di tempat yang dibaca pemakai.

## Tujuan
- Berkas khusus `CHANGELOG.md` (bukan README), format Keep a Changelog + SemVer (Added, Changed, Fixed, Security) ditambah bagian Behavior changes untuk perubahan perilaku bawaan. **[owner]**
- Disusun saat rilis dari badan PR, bukan diedit di tiap PR (issue paralel di worktree terpisah akan konflik di bagian atas berkas). **[owner]**
- Opt-in: proyek yang `WORKFLOW.md`-nya belum punya aturan tidak mendapat berkas apa pun. `kickoff` merekomendasikan `CHANGELOG.md` untuk proyek baru. Adopsi baru mulai dari rilis berikutnya, tanpa isi mundur (isi mundur aicrew 0.1.0-0.8.2 ada di #34). **[owner]**
- aicrew memakai mekanisme yang sama untuk dirinya sendiri. **[owner]**
- Deskripsi rilis GitHub dan entri `CHANGELOG.md` berasal dari satu sumber. **[owner]**
- Kategori lewat awalan di baris bertanda `Catatan rilis: <Kategori> - <teks>` (Added, Changed, Fixed, Security); perubahan perilaku lewat baris `Perubahan perilaku: <teks>`. **[owner: setuju usulan]**
- Bagian Security hanya dari baris `Security -` buatan penulis PR; tidak pernah dari judul issue `CVE: <paket> ...` atau label (judul itu memuat nama paket; catatan rilis bisa publik, lihat #25). PR berlabel `needs-security` tanpa baris `Security -` hanya diperingatkan. **[owner: setuju usulan]**
- Aturan yang sama untuk proyek tanpa cabang integrasi: PR rilis (PR yang menaikkan versi, atau PR integrasi -> `main`) memuat entri hasil `release-notes.sh`. **[owner: setuju usulan]**

## Non-tujuan
- Catatan yang ditulis model; mengambil isi dari badan PR penuh, komentar, atau issue (hanya baris bertanda). **[owner]**
- Menyentuh berkas alat lain (`release-please`, `changesets`, dll.). **[owner]**
- Isi mundur 0.1.0-0.8.2 (itu #34). **[owner]**

## Anti-tujuan (gagal walau tampak jalan)
- Proyek opt-out atau tanpa baris `Catatan rilis:` mendapat `CHANGELOG.md` baru atau berubah.
- Nama paket/hal internal bocor ke catatan publik lewat sumber otomatis (judul issue, badan PR penuh).
- Menjalankan ulang menggandakan entri versi yang sama, atau mencampur PR yang sudah masuk rilis sebelumnya.
- Rilis GitHub dan `CHANGELOG.md` berbeda isi untuk versi yang sama.
- Satu PR tanpa baris bertanda membuat entri kosong atau mematahkan rilis (hanya `PERINGATAN`). **[owner]**

## Rancangan
**Opsi `WORKFLOW.md` [owner].** `Catatan rilis: CHANGELOG.md | rilis GitHub saja | dikelola alat lain | tidak ada`. Baris hilang = `tidak ada` (tidak melakukan apa pun). `dikelola alat lain`: tidak menyentuh berkas apa pun. `rilis GitHub saja`: deskripsi rilis dari baris bertanda, tanpa berkas. Dibaca lewat `workflow.sh` (cabang tujuan untuk gerbang).
**Baris bertanda [owner+saya].** Di badan PR, satu baris per entri: `Catatan rilis: Added - ...` (kategori tidak peka huruf besar-kecil; awalan tak dikenal atau tak ada = `Changed`); `Catatan rilis: -` menandai PR internal tanpa entri (tanpa peringatan); `Perubahan perilaku: ...` boleh berulang. `agents/senior-coder.md` memuat aturannya dan `templates/pull_request_template.md` (baru) memuat kerangkanya. **[saya]**
**`scripts/release-notes.sh` [saya].** REST + git saja, deterministik. `release-notes.sh --versi X.Y.Z [--sejak <tag>] [--tulis]` mencetak bagian `## [X.Y.Z] - <tanggal>` dengan `### Added|Changed|Fixed|Security` dan `### Behavior changes` (hanya bagian yang terisi), tiap entri `- <teks> (#<PR>)`, urut nomor PR. Jendela: PR yang `merged_at` > tanggal commit tag rilis terakhir (atau `--sejak`) dan basisnya cabang bawaan atau cabang integrasi. `--tulis` menyisipkan bagian itu di atas `CHANGELOG.md` (membuat kerangka header bila belum ada; mengganti bagian versi yang sama bila ada) hanya bila opsi = `CHANGELOG.md`. `--ekstrak X.Y.Z` mencetak bagian versi itu dari `CHANGELOG.md`. PR tanpa baris bertanda dan PR `needs-security` tanpa baris Security dilaporkan ke stderr sebagai `PERINGATAN: PR #n ...` (hanya nomor).
**Gerbang [owner].** `pr-merge-check.sh` memperingatkan (tidak memblokir) PR tanpa baris `Catatan rilis:` bila opsi (dibaca dari cabang tujuan) adalah `CHANGELOG.md` atau `rilis GitHub saja`.
**Rilis [saya].** `release-report.sh` menyertakan draf bagian versi di laporan dan badan PR integrasi; menulis `CHANGELOG.md` ke cabang integrasi adalah langkah agen lewat PR biasa (skrip tidak push ke integrasi). `release.yml`: bila `CHANGELOG.md` memuat bagian versi, `gh release create --notes-file` (hasil `--ekstrak`); selain itu `--generate-notes` seperti sekarang. `check-version.sh` memberi `::warning::` bila opsi = `CHANGELOG.md` dan bagian versi tak ada (tidak menggagalkan rilis).
**Bahasa [saya].** Judul bagian Keep a Changelog selalu Inggris; teks entri apa adanya dari penulis PR. Bahasa artefak proyek menentukan bahasa yang diminta dari penulis PR.
**Dokumen [saya].** `templates/WORKFLOW.md` (baris opsi), `skills/kickoff/SKILL.md` (tanya dan rekomendasikan), mode audit menyarankan baris yang hilang, README satu paragraf pendek. aicrew sendiri: baris `Catatan rilis: CHANGELOG.md` ditambahkan ke `docs/WORKFLOW.md`-nya. Rilis kandidat 0.11.0 (fitur baru, opt-in).

## Keputusan tambahan (hasil pemeriksaan builder)
**Menunggu jawaban owner (2 butir).** Sampai dijawab, bagian ini yang berlaku sebagai usulan:
- **O1. Opsi `rilis GitHub saja`.** Tidak ada pelaksananya: satu-satunya pembuat rilis GitHub adalah `release.yml`, khusus aicrew (`plugin.json`); plugin tidak mengirim workflow rilis ke proyek pemakai. Usulan saya: **hapus opsi itu**, sisa `CHANGELOG.md | dikelola alat lain | tidak ada`. Alternatif: sediakan templat workflow rilis (pekerjaan tambahan yang tidak diminta).
- **O2. Kategori ketat.** Draf awal: awalan tak dikenal = `Changed`. Builder: typo `Secuirty - ...` lalu terbit publik sebagai `Changed` tanpa peringatan. Usulan saya: kategori sah hanya bila kata pertama salah satu dari Added, Changed, Fixed, Security (tak peka huruf besar-kecil) diikuti ` - `; selain itu entri **tidak ditulis** dan dilaporkan `PERINGATAN: PR #n kategori tak dikenal`. Penanda internal tepat `Catatan rilis: -` (tanpa teks).
**Keputusan saya [saya].**
- **`docs/WORKFLOW.md` aicrew belum ada** (`docs/` hanya `superpowers/`); aicrew berjalan sebagai proyek tanpa integrasi. Dogfooding membuat berkas minimal itu berisi baris `Catatan rilis: CHANGELOG.md`; skrip lain memakai bawaan untuk baris yang hilang, jadi perilaku lain tidak berubah.
- **Jendela berdasarkan keturunan commit, bukan tanggal.** Tag sebelumnya = tag `vX.Y.Z` (urutan semver) tertinggi di bawah `--versi` (atau yang tertinggi bila versi belum bertag); PR masuk bila `merge_commit_sha`-nya leluhur ref basis (`origin/<bawaan>` atau `origin/<integrasi>`) dan bukan leluhur tag sebelumnya. Aman untuk merge-commit, squash, dan rebase, dan idempoten bila dijalankan lagi setelah tag ada. Tanpa tag sebelumnya dan tanpa `--sejak <ref>`: exit 2 dengan petunjuk (rilis pertama proyek adopsi dimulai dari `--sejak`).
- **Sumber PR lewat REST bernomor halaman** (`pulls?state=closed&per_page=100` sampai habis, hanya yang `merged_at` terisi); gagal baca atau batas laju = exit 2 dan **tidak menulis apa pun** (tidak pernah `CHANGELOG.md` parsial).
- **Pengurai badan PR.** Buang `\r`; abaikan baris di dalam blok kode berpagar dan komentar HTML (templat menaruh contoh di komentar HTML); baris harus diawali `Catatan rilis:` atau `Perubahan perilaku:` di kolom 0 (boleh didahului `- `); satu baris per entri.
- **PR rilis dan PR `CHANGELOG.md` menulis `Catatan rilis: -`** (aturan di `senior-coder.md` dan templat); tidak ada pengecualian berdasarkan judul atau berkas. Penulisan `CHANGELOG.md` ke integrasi lewat PR biasa, agar tidak berputar dengan `release-report.sh`.
- **Membaca opsi.** Gerbang membaca `docs/WORKFLOW.md` cabang tujuan lewat REST (pola `cve_fetch` di `pr-merge-check.sh`); `release.yml`/`check-version.sh` memakai berkas lokal (checkout `main`). Nilai di luar daftar sah, termasuk placeholder `{{...}}` yang belum diisi, = `tidak ada`.
- **`--ekstrak` exit 1 bila bagian versi tak ada**, supaya `release.yml` jatuh ke `--generate-notes`. `release-notes.sh` menjalankan `git fetch --tags`.
- **Tanggal bagian** = tanggal UTC saat `--tulis`, dapat ditimpa `--tanggal YYYY-MM-DD`.
- **Non-tujuan tambahan:** PR yang di-merge ke basis selain bawaan/integrasi (mis. PR bertumpuk ke cabang induk) tidak masuk catatan; itu sengaja.

## Kendala
- Tes tanpa jaringan: `gh` palsu REST (daftar PR ter-merge dengan badan, tanggal tag), repo git sementara. Bash 3.2 dan Linux CI; artefak berbahasa Indonesia, kecuali isi `CHANGELOG.md` mengikuti penulis PR.

## Kriteria selesai
- Tes merah dulu: entri disusun dari PR fixture (baris bertanda, Behavior changes, urutan, jendela tag); PR tanpa baris bertanda -> `PERINGATAN`; `Catatan rilis: -` tanpa peringatan; opsi `tidak ada`/`dikelola alat lain`/baris hilang tidak membuat atau mengubah berkas; `--tulis` idempoten; Security hanya dari baris `Security -` (judul issue CVE tidak pernah masuk); gerbang memperingatkan PR tanpa baris; `release.yml` memakai catatan dari `CHANGELOG.md` bila ada. `bash tests/run.sh` -> `SEMUA LULUS`.
- README, `kickoff`, `senior-coder.md`, templat diperbarui; rilis lewat alur rilis (owner menyetujui sebelum merge).

## Diserahkan ke builder
Bentuk argumen dan format keluaran `release-notes.sh`, pembacaan tanggal tag, penyusunan fixture, penanganan nama cabang berisi `/`, dan redaksi templat PR.
