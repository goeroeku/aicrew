# Catatan rilis: CHANGELOG.md dari badan PR — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, dipilih owner) atau superpowers:subagent-driven-development. Steps memakai checkbox (`- [ ]`).

**Goal:** `scripts/release-notes.sh` menyusun bagian `CHANGELOG.md` per versi dari baris bertanda di badan PR yang ter-merge sejak tag sebelumnya; gerbang, `release.yml`, templat, dan agen memakainya. Opt-in lewat `Catatan rilis:` di `WORKFLOW.md`.

**Architecture:** Satu skrip deterministik (REST + git) dengan tiga mode (cetak, `--tulis`, `--ekstrak`); pembaca opsi dan pengurai baris bertanda sebagai fungsi di dalamnya. Pemakai: `pr-merge-check.sh` (peringatan), `check-version.sh` (`::warning::`), `release.yml` (`--notes-file`), `release-report.sh` (draf di laporan).

**Tech Stack:** bash 3.2 (macOS) + Linux, `gh api` REST, `jq`, `git`; tes `bash tests/run.sh` dengan `gh` palsu (pola `MI` di bagian `3m`) dan repo git sementara.

**Spec:** `docs/superpowers/specs/2026-11-01-catatan-rilis-design.md` (bagian "Keputusan tambahan" mengikat).

## Global Constraints
- Hanya `git` dan `gh api` REST. Gagal baca / batas laju / tag sebelumnya tak ada tanpa `--sejak` = exit 2 dan **tidak menulis apa pun**.
- Opsi sah: `CHANGELOG.md | dikelola alat lain | tidak ada`; baris hilang, placeholder `{{...}}`, atau nilai lain = `tidak ada` (skrip tidak membuat/mengubah berkas, `--ekstrak` tetap bekerja bila berkas ada).
- Kategori sah: Added, Changed, Fixed, Security (tak peka huruf besar-kecil) diikuti ` - `; penanda internal tepat `Catatan rilis: -`; `Perubahan perilaku: <teks>` boleh berulang. Judul bagian selalu Inggris: `### Added|Changed|Fixed|Security`, `### Behavior changes`.
- Baris dibaca dari badan PR setelah membuang `\r`, melewati blok kode berpagar (```) dan komentar HTML (`<!-- -->`, juga multi-baris); diawali `Catatan rilis:`/`Perubahan perilaku:` di kolom 0 (boleh `- ` di depan).
- Artefak berbahasa Indonesia; dilarang atribusi AI; tanpa `--force`. Rilis kandidat 0.11.0 (`plugin.json` + tes pin versi).

## Review Focus
- Jalankan ulang `--tulis` untuk versi yang sudah ada/sudah bertag: bagian tidak berganda dan tidak menjadi kosong.
- Rilis pertama tanpa tag sebelumnya; PR squash/rebase/merge-commit; lebih dari 100 PR ter-merge (halaman kedua).
- Teks Security hanya dari baris `Security -`; judul issue `CVE: ...` dan label tidak pernah masuk.
- Proyek opt-out atau tanpa baris: tidak ada `CHANGELOG.md` dibuat atau diubah.
- Badan PR berisi CRLF, contoh di komentar HTML/blok kode, dan typo kategori.

---

### Task 1: `scripts/release-notes.sh` — mode cetak

**Files:** Create `scripts/release-notes.sh`; Modify `tests/run.sh` (bagian baru `3n-1`, memakai fixture `MI` bagian `3m` bila masih dalam cakupan, selain itu fixture sendiri).

**Interfaces:**
- Produces: `release-notes.sh --versi X.Y.Z [--sejak REF] [--tanggal YYYY-MM-DD]` -> stdout bagian `## [X.Y.Z] - <tanggal UTC>` (hanya bagian terisi, entri `- <teks> (#<PR>)` urut nomor PR); stderr `PERINGATAN: PR #n tanpa baris Catatan rilis` / `... kategori tak dikenal` / `PR #n berlabel needs-security tanpa baris Security`; exit 0, 2 (tak bisa disusun), 64 (argumen). Fungsi `catatan_opsi` (cetak token opsi dari `workflow.sh`) dan `catatan_baris <badan>` (cetak `kategori<TAB>teks` per entri, `BEHAVIOR<TAB>teks`, atau `INTERNAL`) di dalam skrip.
- Consumes: `ghx_repo` (`scripts/ghx.sh`), `scripts/workflow.sh`, `GH_REPO`.

- [ ] **Step 1: tes merah** — repo git sementara + remote bare, tag `v0.1.0` dan `v0.2.0`, PR palsu via `gh` palsu (`pulls?state=closed&per_page=100&page=N`, file per halaman): (a) hanya PR dengan `merge_commit_sha` bukan leluhur tag sebelumnya dan leluhur `origin/<basis>` masuk; (b) urutan bagian Added, Changed, Fixed, Security, Behavior changes dan urut nomor PR; (c) `Catatan rilis: -` tanpa peringatan dan tanpa entri; (d) PR tanpa baris -> `PERINGATAN: PR #n`; (e) kategori tak dikenal (`Secuirty - x`) -> peringatan, entri tidak ditulis; (f) CRLF dibuang; contoh di komentar HTML dan blok kode diabaikan; (g) judul issue `CVE: x` / label `needs-security` tanpa baris `Security -` tidak menghasilkan entri Security; (h) halaman kedua PR (101+) terbaca; (i) tanpa tag sebelumnya dan tanpa `--sejak` -> exit 2; `--sejak <ref>` menggantikannya; (j) `--versi` yang sudah bertag memakai tag di bawahnya (jalankan ulang -> keluaran sama); (k) REST gagal -> exit 2, stdout kosong; (l) opsi `tidak ada`/`dikelola alat lain`/baris hilang/placeholder -> stdout kosong, exit 0.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL (skrip belum ada).
- [ ] **Step 3: implement** — tag sebelumnya: `git tag -l` yang cocok `^v[0-9]+\.[0-9]+\.[0-9]+$`, urut `sort -t. -k1.2,1n -k2,2n -k3,3n` (tanpa `sort -V`), ambil yang tertinggi di bawah `--versi`; `git fetch -q --tags origin` dan cabang basis (bawaan dari REST `repos/<r>.default_branch`, integrasi dari `Cabang integrasi:`); PR dari halaman `pulls?state=closed&per_page=100&page=N` sampai halaman kosong, hanya `merged_at` terisi dan `base.ref` di basis; label dibaca dari objek PR.
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `release-notes.sh: susun bagian catatan rilis dari baris bertanda di badan PR (#30)`.

### Task 2: `--tulis` dan `--ekstrak`

**Files:** Modify `scripts/release-notes.sh`, `tests/run.sh` (`3n-2`).

**Interfaces:** `--tulis`: hanya bila `catatan_opsi` = `CHANGELOG.md`, selain itu exit 0 tanpa menyentuh berkas. Menyisipkan bagian di atas bagian `## [` pertama (membuat berkas dengan kerangka header Keep a Changelog bila belum ada); mengganti bagian `## [X.Y.Z]` yang sama sampai bagian berikutnya atau akhir berkas. `--ekstrak`: cetak bagian `## [X.Y.Z]` dari `CHANGELOG.md`; exit 1 bila tak ada. Consumes Task 1.

- [ ] **Step 1: tes merah** — berkas belum ada -> dibuat dengan header + bagian; `--tulis` dua kali -> satu bagian (idempoten); bagian lama versi lain tidak berubah; menimpa bagian versi yang sama; opsi `tidak ada` -> berkas tidak dibuat; `--tulis` saat REST gagal -> berkas tidak berubah; `--ekstrak 0.2.0` mencetak hanya bagian itu, versi tak ada -> exit 1.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL.
- [ ] **Step 3: implement** dengan `awk` (bukan `sed -i`, agar BSD/GNU sama).
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `release-notes.sh: --tulis idempoten dan --ekstrak (#30)`.

### Task 3: gerbang, `check-version.sh`, `release.yml`

**Files:** Modify `scripts/pr-merge-check.sh` (setelah blok alur terjadwal, sebelum `echo "ok: gerbang lolos…"`), `scripts/check-version.sh`, `.github/workflows/release.yml`, `tests/run.sh` (`3n-3`).

**Interfaces:** gerbang: bila `docs/WORKFLOW.md` di `$dst` (REST `contents`, 404/galat = tanpa peringatan) bernilai `Catatan rilis: CHANGELOG.md` dan `$body` tak memuat baris `Catatan rilis:` -> `PERINGATAN: PR tanpa baris 'Catatan rilis:' (…)`, tidak memblokir. `check-version.sh`: opsi lokal = `CHANGELOG.md` dan `CHANGELOG.md` tanpa `## [<versi>]` -> `::warning::` ke stdout, exit tetap 0. `release.yml`: `--ekstrak` ke `notes.md`; bila berhasil dan tak kosong `gh release create … --notes-file notes.md`, selain itu `--generate-notes`.

- [ ] **Step 1: tes merah** — gerbang (pakai harness `GE` bagian `3j-4`): opsi CHANGELOG.md + badan tanpa baris -> PERINGATAN; dengan baris atau `Catatan rilis: -` -> tanpa; opsi lain/WORKFLOW 404 -> tanpa; `check-version.sh` (repo sementara) -> `::warning::` hanya bila bagian versi hilang; `grep` `release.yml` memuat `--ekstrak`, `--notes-file`, dan `--generate-notes`.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL.
- [ ] **Step 3: implement** per Interfaces.
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Gerbang, check-version, release.yml: pakai catatan rilis (#30)`.

### Task 4: agen, templat, kickoff, laporan rilis, dogfooding, rilis 0.11.0

**Files:** Modify `agents/senior-coder.md` (aturan baris `Catatan rilis:`/`Perubahan perilaku:`; PR rilis dan PR `CHANGELOG.md` menulis `Catatan rilis: -`), `templates/WORKFLOW.md` (baris opsi), `skills/kickoff/SKILL.md` (tanya dan rekomendasikan `CHANGELOG.md` untuk proyek baru; mode audit menyarankan baris yang hilang), `scripts/release-report.sh` (bagian "Catatan rilis (draf)" dari `release-notes.sh`, tanpa menulis berkas), `README.md` (satu paragraf), `.claude-plugin/plugin.json` -> `0.11.0`, `tests/run.sh` (`3n-4`, pin versi). Create `templates/pull_request_template.md` (contoh baris di komentar HTML), `docs/WORKFLOW.md` (minimal, satu baris `- Catatan rilis: CHANGELOG.md`).

- [ ] **Step 1: tes merah** — pin `plugin.json versi 0.11.0`; `grep` kata kunci: `Catatan rilis:` dan `Perubahan perilaku:` di `senior-coder.md`; `Catatan rilis` di templat WORKFLOW dan `kickoff`; `pull_request_template.md` ada dan memuat `<!--`; `docs/WORKFLOW.md` memuat `Catatan rilis: CHANGELOG.md`; `release-report.sh` (harness `RR` yang ada) memuat bagian draf bila opsi CHANGELOG.md dan tidak bila tidak.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL.
- [ ] **Step 3:** ubah berkas di atas (redaksi singkat, selaras gaya; draf di `release-report.sh` hanya mencetak, tidak push).
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Rilis 0.11.0: catatan rilis dari badan PR (#30)`.
