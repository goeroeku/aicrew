# v1.0: permukaan publik Inggris, CHANGELOG, Stability — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, dipilih owner). Steps memakai checkbox (`- [ ]`).

**Goal:** README, PRIVACY, CHANGELOG (isi mundur 0.1.0-0.12.0), deskripsi plugin/marketplace berbahasa Inggris, bagian Stability, lalu rilis 1.0.0.

**Architecture:** Dua PR. **PR A (isi)**: README/PRIVACY/CHANGELOG/metadata + tes pola; badan PR memuat baris `Release note:`. **PR B (rilis 1.0.0)**, setelah PR A ter-merge: `release-notes.sh --versi 1.0.0 --tulis` (hanya melihat PR yang sudah ter-merge, jadi PR A harus masuk dulu) + naik versi + tes pin. Metadata repo GitHub diubah owner/dengan persetujuan setelah PR B.

**Tech Stack:** Markdown, bash 3.2/Linux, `git log`/`gh api` untuk bahan CHANGELOG; tes `bash tests/run.sh`.

**Spec:** `docs/superpowers/specs/2026-11-01-v1-dokumentasi-inggris-design.md` (bagian "Keputusan tambahan" mengikat).

## Global Constraints
- Tanpa perubahan di `scripts/`, `skills/`, `agents/`, `templates/` (kecuali tes di `tests/run.sh`). Hanya dokumen dan metadata.
- Heading CHANGELOG persis `## [X.Y.Z] - YYYY-MM-DD` (tanggal = `git log -1 --format=%cs vX.Y.Z`), tanpa `[Unreleased]` dan tanpa blok tautan perbandingan. Isi mundur tidak mengarang: tiap entri dapat ditelusuri ke rentang tag, PR, atau paragraf README lama.
- Heuristik bahasa hanya pada berkas publik terdaftar, di luar blok kode berpagar dan kode inline. Kutipan kunci `WORKFLOW.md` tetap Indonesia.
- Daftar skrip yang kini disebut README (dibekukan di tes): `scripts/autopilot.sh` `scripts/autostart.sh` `scripts/board-init.sh` `scripts/board.sh` `scripts/cleanup.sh` `scripts/cve-audit.sh` `scripts/cve-check.sh` `scripts/epic-link.sh` `scripts/ghx.sh` `scripts/lock.sh` `scripts/notify.sh` `scripts/preflight.sh` `scripts/release-report.sh` `scripts/release-notes.sh` (verifikasi daftar persisnya di Task 1) — semuanya tetap disebut.
- Artefak internal (spec/plan/ledger) tetap Indonesia; dilarang atribusi AI; tanpa `--force`.

## Review Focus
- README tidak kehilangan kemampuan: tiap skrip yang disebut sebelum tetap disebut; kemampuan tiap paragraf bertanda versi ada di README (saat ini) dan/atau CHANGELOG.
- CHANGELOG: satu bagian per tag (25), tanggal benar, tanpa entri karangan, Behavior changes lengkap (0.8.0, 0.9.0, 0.10.0, 0.11.1, 0.12.0).
- Tes lama yang mengunci teks Indonesia (~20 grep) diubah ke padanan Inggris tanpa melemahkan maknanya.
- Tidak ada teks Indonesia tersisa di berkas publik (README, PRIVACY, CHANGELOG, `plugin.json` termasuk `userConfig`, `marketplace.json`).
- PR B: `[1.0.0]` hasil `--tulis` (bukan tangan), heading persis, `check-version.sh` tanpa peringatan.

---

### Task 1: tes pola (merah dulu)

**Files:** Modify `tests/run.sh` (bagian baru `3q`).
**Interfaces:** Produces fungsi tes `PUB_FILES` (README.md PRIVACY.md CHANGELOG.md), `strip_code` (buang blok berpagar dan kode inline), `idn_hits <berkas>` (jumlah kata fungsi/judul Indonesia di luar kode).

- [ ] **Step 1: tulis tes** — (a) tiap `git tag -l 'v[0-9]*'` bentuk `vX.Y.Z` punya `## [X.Y.Z] - YYYY-MM-DD` di `CHANGELOG.md`, dan tiap heading punya tag atau versi `plugin.json`; (b) README tanpa judul/paragraf tebal bertanda versi `(0.x.y)`; (c) `idn_hits` = 0 untuk tiap berkas publik dan teks `plugin.json` (description, `userConfig` title/description) dan `marketplace.json`; (d) tiap skrip dalam daftar beku disebut README; (e) README memuat judul `Stability`; (f) tidak ada `## [Unreleased]` dan tidak ada baris tautan `^\[[0-9].*\]: http` di CHANGELOG. Tes lama tidak diubah di langkah ini.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL (CHANGELOG belum ada, README Indonesia).
- [ ] **Step 3: commit tes** `Tes pola v1.0: CHANGELOG, bahasa publik, Stability (#34)`.

### Task 2: `CHANGELOG.md` isi mundur

**Files:** Create `CHANGELOG.md`.
- [ ] **Step 1:** untuk tiap rentang tag (`v0.1.0`, lalu `vA..vB`): kumpulkan `git log --format='%h %cs %s' vA..vB`, PR ter-merge dalam rentang (`gh api repos/goeroeku/aicrew/pulls?state=closed&per_page=100`, `merge_commit_sha` leluhur vB bukan vA), paragraf README bertanda versi, dan memori rilis; tulis bagian Inggris (Added/Changed/Fixed/Security + Behavior changes) dengan header Keep a Changelog; entri tak pasti dihilangkan.
- [ ] **Step 2:** tinjau diri: 25 bagian, tanggal dari commit tag, Behavior changes 0.8.0/0.9.0/0.10.0/0.11.1/0.12.0.
- [ ] **Step 3:** `bash tests/run.sh`; Expected: tes (a) dan (f) LULUS.
- [ ] **Step 4: commit** `CHANGELOG.md: isi mundur 0.1.0 sampai 0.12.0 (#34)`.

### Task 3: README Inggris + tes lama

**Files:** Modify `README.md`, `tests/run.sh` (≈20 grep README/PRIVACY).
- [ ] **Step 1:** tulis ulang README dalam bahasa Inggris dengan kerangka dari spec (tanpa paragraf bertanda versi; kemampuan saat ini; konfigurasi dengan tabel kunci; Stability). Tabel kunci `WORKFLOW.md` mengutip kunci Indonesia dalam kode.
- [ ] **Step 2:** perbarui tes lama yang mengunci teks README/PRIVACY ke padanan Inggris (daftar: grep pada README/PRIVACY yang gagal); jalankan `bash tests/run.sh` dan perbaiki sampai hanya perubahan sah.
- [ ] **Step 3:** `bash tests/run.sh`; Expected: tes (b), (d), (e) LULUS dan tak ada regresi.
- [ ] **Step 4: commit** `README.md: bahasa Inggris, kemampuan saat ini, bagian Stability (#34)`.

### Task 4: PRIVACY, plugin.json, marketplace.json

**Files:** Modify `PRIVACY.md`, `.claude-plugin/plugin.json` (description, `userConfig` title/description), `.claude-plugin/marketplace.json` (dua deskripsi), `tests/run.sh` bila ada kunci teks.
- [ ] **Step 1:** terjemahan setia `PRIVACY.md` (tanggal "Last updated" 2026-11-01 atau hari pengerjaan); terjemahkan deskripsi dan `userConfig`; jangan ubah struktur/kunci JSON.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes (c) LULUS, tak ada regresi; JSON valid (`jq .`).
- [ ] **Step 3: commit** `PRIVACY.md dan metadata plugin: bahasa Inggris (#34)`.

### Task 5: review akhir dan PR A

- [ ] Review akhir (sonnet) atas seluruh cabang, fokus Review Focus; perbaiki Critical/Important dengan tes merah dulu; push; buka PR A dengan badan memuat `Closes #34`? **Tidak** (issue ditutup oleh PR B) dan baris `Release note: Changed - Public documentation (README, PRIVACY, plugin metadata) is now in English; add CHANGELOG.md with history 0.1.0-0.12.0` serta `Release note: Added - Stability policy section in README`. Tunggu CI; minta persetujuan merge.

### Task 6 (PR B, setelah PR A ter-merge): rilis 1.0.0

**Files:** Modify `CHANGELOG.md` (lewat skrip), `.claude-plugin/plugin.json` -> `1.0.0`, `tests/run.sh` (pin versi + bagian `[1.0.0]`).
- [ ] **Step 1: tes merah:** pin `"version": "1.0.0"`; `CHANGELOG.md` memuat `## [1.0.0] - ` sebagai heading pertama.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: GAGAL.
- [ ] **Step 3:** `bash scripts/release-notes.sh --versi 1.0.0 --tulis`; naikkan `plugin.json`; `Closes #34` di badan PR; baris `Release note: -` (PR rilis).
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`; `check-version.sh v1.0.0` tanpa `::warning::`.
- [ ] **Step 5: commit** `Rilis 1.0.0 (#34)`; PR; CI; persetujuan merge; verifikasi tag `v1.0.0` dan aset; usul perubahan metadata repo (persetujuan eksplisit).
