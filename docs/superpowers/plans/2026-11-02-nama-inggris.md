# Nama teknis berbahasa Inggris Implementation Plan

> **For agentic workers:** inline execution (superpowers:executing-plans). Steps use `- [ ]`.

**Goal:** nama teknis Inggris kanonik (skrip, opsi, kunci/nilai WORKFLOW, label) dengan alias Indonesia yang tetap berfungsi; rilis 1.1.0.
**Architecture:** satu pemeta alias `scripts/lib/wf-normalize.sh` (fungsi `wf_normalize`, stdin→stdout) dipakai `workflow.sh` dan skrip yang membaca WORKFLOW.md langsung; konsumen hanya mengenal kunci/nilai Inggris. Opsi: parser menerima nama baru dan lama. Skrip berganti nama dengan pembungkus lama. `label.sh <nama> --all` mencetak kanonik+alias.
**Tech Stack:** Bash 3.2/Linux, `bash tests/run.sh`.
**Spec:** docs/superpowers/specs/2026-11-02-nama-inggris-design.md

## Global Constraints
- Tabel pemetaan di spec berlaku verbatim (skrip, opsi, kunci, nilai, label). Nilai kanonik huruf kecil: `agent-after-qa`, `agent-after-merge`.
- WORKFLOW.md lama (semua kunci Indonesia) harus lolos tanpa perubahan. Pemeta nilai hanya menyentuh token pertama setelah kunci.
- Tidak ada AI attribution di commit; tes ada di `tests/run.sh` (bagian baru `3s`); suite penuh hijau sebelum tiap commit.

## Review Focus
- Kunci Indonesia di tengah baris (mis. `Label integrasi: x. Label keputusan otomatis: y.`) tetap terbaca.
- WORKFLOW.md campuran (sebagian kunci Inggris, sebagian Indonesia) dan berkas dari REST (pr-merge-check) ikut dinormalkan.
- Izin/pemanggil lama: `bash scripts/terintegrasi.sh 5` masih jalan lewat pembungkus; `--versi` lama masih jalan.
- Label lama di issue (`di-integrasi`) tetap dikenali oleh cleanup/board/resume/autopilot.

### Task 1: Pemeta alias
**Files:** Create `scripts/lib/wf-normalize.sh`; Test `tests/run.sh` (bagian 3s)
**Produces:** `wf_normalize` (fungsi, baca stdin, tulis stdout); `bash scripts/lib/wf-normalize.sh` langsung = filter stdin.
- [ ] Tes (merah dulu): kunci tiap baris tabel → bentuk Inggris; kunci di tengah baris; nilai token pertama (`Clean up after merge: ya`→`yes`, `laporkan`→`report`, `agen-setelah-QA`→`agent-after-qa`, `Integration branch: tidak ada`→`none`); prosa "ya, tetapi" setelah nilai tidak berubah; baris tanpa kunci tak berubah; input Inggris idempoten.
- [ ] Implementasi: `sed -E` dengan tabel s///; kunci tanpa jangkar (frasa + `:`), nilai dengan `(Key: *)lama\b` untuk kunci bernilai ya/tidak/mode/profil saja.
- [ ] Jalankan: `bash tests/run.sh` → SEMUA LULUS.

### Task 2: Pembaca WORKFLOW memakai pemeta
**Files:** Modify `scripts/workflow.sh` (normalkan keluaran; baca Cabang integrasi dari berkas lokal setelah normalisasi), `install-permissions.sh:16`, `cve-private.sh:14`, `pr-merge-check.sh:87-137`, `release-report.sh:14`; konsumen via workflow.sh: `cleanup.sh`, `board.sh`, `terintegrasi.sh`, `label.sh`, `cve-audit.sh`, `release-notes.sh`, `check-version.sh`, `cve-check.sh` (regex jadi kunci/nilai Inggris).
- [ ] Tes merah: untuk tiap konsumen, WORKFLOW.md Indonesia lama DAN versi Inggris memberi hasil sama (satu tes per skrip; pakai tes yang sudah ada sebagai kasus alias).
- [ ] Ganti regex Indonesia → Inggris di konsumen; keempat skrip langsung memanggil `wf_normalize` pada berkas/REST sebelum `sed`/`grep`.
- [ ] Nilai: cleanup (`yes|report|no`), Done card, Close issues, CVE check, Profile, mode merge → bentuk Inggris; `autopilot-permissions.json` kunci `agent-after-qa`.
- [ ] Suite penuh hijau; commit.

### Task 3: Label
**Files:** Modify `scripts/label.sh`, pembaca label di `cleanup.sh`, `board.sh`, `resume.sh`, `autopilot.sh`, `release-report.sh`.
**Produces:** `label.sh <nama>` mencetak kanonik Inggris (bawaan `integrated`, `auto-decision`, `unsplit`, `awaiting-release`, `no-parent`; env/WORKFLOW menimpa); `label.sh <nama> --all` mencetak satu per baris: nilai efektif lalu alias lama.
- [ ] Tes merah: bawaan Inggris; WORKFLOW lama dengan `Label integrasi: di-integrasi` → efektif tetap `di-integrasi`; `--all` memuat keduanya; issue berlabel nama lama tetap dikenali di cleanup/board.
- [ ] Implementasi + pemanggil mencocokkan salah satu dari `--all`; templat WORKFLOW dan daftar label di template memakai nama baru. Suite hijau; commit.

### Task 4: Opsi baris perintah
**Files:** Modify `release-notes.sh`, `check-version.sh`, `release-report.sh`, `cleanup.sh`, `preflight.sh`, `resume.sh`, `pr-merge-check.sh`, `menunggu-rilis.sh`.
- [ ] Tes merah per skrip: opsi Inggris dan lama menghasilkan keluaran sama (`--version/--versi`, `--since/--sejak`, `--date/--tanggal`, `--write/--tulis`, `--extract/--ekstrak`, `--open-pr/--buka-pr`, `--check/--cek`, `--count/--hitung`, `--parse-body/--parse-badan`, `--after-merge/--setelah-merge`, `--mark/--tandai`).
- [ ] Parser `case` menerima `--baru|--lama)`; pesan pemakaian menyebut bentuk Inggris. Suite hijau; commit.

### Task 5: Nama skrip
**Files:** `git mv` `alur-terjadwal.sh`→`scheduled-workflow.sh`, `menunggu-rilis.sh`→`awaiting-release.sh`, `terintegrasi.sh`→`integrated.sh`; buat pembungkus tiga nama lama (`exec bash "$(dirname "$0")/<baru>" "$@"`, komentar "deprecated alias").
- [ ] Tes merah: tiap nama lama dan baru berjalan dengan keluaran/exit sama; tes lama yang memanggil nama lama dibiarkan.
- [ ] Perbarui pemanggil (`skills/*`, `board.sh`, dll.) ke nama baru. Suite hijau; commit.

### Task 6: Dokumentasi dan tes penjaga
**Files:** Modify `templates/WORKFLOW.md` (kunci/nilai/label Inggris, prosa tetap Indonesia), `docs/WORKFLOW.md`, `README.md` (Configuration table, bagian Stability: kebijakan alias), `skills/*/SKILL.md`, `agents/*.md`, pesan skrip yang mengutip kunci/opsi (`cve-check.sh:68`, `pr-merge-check.sh:139`, `board.sh:66`).
- [ ] Tes penjaga merah: tak ada kunci/opsi/nama skrip/label Indonesia dari tabel di templat, README, SKILL.md, agen, kecuali di bagian "Deprecated aliases" README dan di `scripts/lib/wf-normalize.sh` serta pembungkus.
- [ ] Perbarui berkas sampai tes hijau. Suite hijau; commit.

### Task 7: Rilis 1.1.0 (PR terpisah, setelah PR isi ter-merge atas izin owner)
- [ ] PR isi: badan memuat `Release note: Changed - ...` dan `Behavior change: ...`; CI, gerbang, minta izin merge.
- [ ] PR rilis: `plugin.json` 1.1.0, `release-notes.sh --version 1.1.0 --write`, tes versi; minta izin merge.
