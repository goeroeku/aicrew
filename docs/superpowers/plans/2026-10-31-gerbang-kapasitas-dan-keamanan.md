# Gerbang kapasitas dan keamanan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Perubahan sensitif (`needs-security`, `needs-perf`) tidak bisa di-merge tanpa laporan role yang terikat ke head PR, dan rilis memvonis fakta yang sama.

**Architecture:** `pr-merge-check.sh` (sebelum merge) menjalankan dua gerbang berlabel dengan fungsi yang sama dan memanggil `baseline-scan.sh` (skrip baru, deterministik) untuk diff. `release-report.sh` memakai aturan label yang sama dari JSON `gh`. Role `aicrew-perf` baru + dokumen/template menjelaskan alurnya.

**Tech Stack:** bash, `gh`, `jq`; tes offline `bash tests/run.sh` dengan `gh` palsu.

**Spec:** `docs/superpowers/specs/2026-10-31-gerbang-kapasitas-dan-keamanan-design.md`

## Global Constraints
- Bash + `gh` saja; tes deterministik tanpa jaringan di `tests/run.sh`; suite penuh hijau sebelum tiap commit.
- Dokumen/prompt role berbahasa Indonesia; pesan commit Indonesia, tanpa atribusi AI (hook `guard-attribution.sh` aktif).
- Gerbang fail-closed: label/komentar/diff tak terbaca = exit 1.
- Commit boleh di branch `goeroeku/security-gate`, satu commit per task. **Dilarang push dan membuka PR** tanpa perintah owner. Versi plugin tidak dinaikkan.
- Format baris laporan (persis): `Laporan perf: lulus|gagal`, `Laporan security: lulus|gagal`, `Angka sebelum/sesudah: …` (wajib ada digit), `Tuning: <config=nilai, alasan, rollback | tidak ada>` (wajib ada), `Commit: <sha>`, waiver `Pengecualian disetujui owner: <alasan> (Commit: <sha>)`. Cocokkan di **awal baris** (`^`), bukan dalam kutipan `>`.

## Review Focus
- `Closes #1, #2` dengan #2 sensitif: gerbang memeriksa semua `#n` pada baris berkata-kunci, bukan hanya yang pertama (tes di Task 2).
- Laporan `lulus` untuk commit lama (head PR sudah maju): ditolak.
- `Angka sebelum/sesudah: n/a` tanpa digit, atau `> Laporan perf: lulus` dalam kutipan: ditolak.
- `gh pr diff` atau pembacaan label gagal: tolak, bukan lolos.
- Positif palsu pemindai rahasia pada fixture: hanya lolos dengan waiver owner yang `Commit:`-nya cocok head.

## Struktur berkas
- Ubah `scripts/pr-merge-check.sh` (gerbang), `scripts/release-report.sh` (vonis rilis), `tests/run.sh`.
- Baru `scripts/baseline-scan.sh`, `agents/perf.md`.
- Ubah dokumen: `agents/security.md`, `skills/{breakdown,orchestrate,kickoff}/SKILL.md`, `templates/WORKFLOW.md`, `README.md`, `.claude-plugin/plugin.json` (deskripsi).

### Task 1: Commit dasar `needs-security` dan spec
**Files:** semua perubahan yang sudah ada di worktree (belum di-commit) + dua dokumen di `docs/superpowers/`.
- [x] Jalankan `bash tests/run.sh` → `SEMUA LULUS`.
- [x] `git add -A && git commit -m "Gerbang needs-security, desain dan rencana gerbang kapasitas"`; `git status -sb` bersih.

### Task 2: Gerbang berlabel generik, terikat commit, dengan waiver
**Files:** Modify `scripts/pr-merge-check.sh`; Test `tests/run.sh` (blok 2a).
**Interfaces:** Produces (di dalam skrip) `gate <label> <verdict-prefix> <perlu-angka:0|1>` → exit 0 lolos; mencetak `GAGAL: …` dan exit 1 bila gagal. Memakai `gh pr view <pr> --json headRefOid -q .headRefOid`, label PR + semua `#n` pada baris berkata-kunci (`close|fix|resolve`) di badan PR, komentar PR.
Fake `gh` di tes harus menambah cabang `*headRefOid*) echo "${HEAD:-abc123}"`.
- [x] Tes (nama → harapan), semua dengan `HEAD=abc123`:
  - `perf: label tanpa laporan` → 1; `perf: lulus tanpa Angka` → 1; `perf: tanpa baris Tuning` → 1; `perf: Angka n/a (tanpa digit)` → 1; `perf: Commit lama (def456)` → 1; `perf: laporan lengkap` (`Laporan perf: lulus⏎Angka sebelum/sesudah: 120/45 fsync/s⏎Tuning: tidak ada⏎Commit: abc123`) → 0.
  - `security: Commit lama` → 1; `security: lulus + Commit abc123` → 0 (tes security 2a yang ada diperbarui menambah baris `Commit:`).
  - `Closes #1, #2` dengan #2 `needs-perf` tanpa laporan → 1.
  - `> Laporan perf: lulus` (kutipan) → 1.
  - Waiver `Pengecualian disetujui owner: fixture (Commit: abc123)` → 0 untuk perf; waiver dengan sha lama → 1; waiver tidak menolong `security`.
  - Label tak terbaca (fake `gh` exit 1 pada `issue view`) → 1.
- [x] Jalankan `bash tests/run.sh` → tes baru GAGAL (merah).
- [x] Refaktor blok security yang ada menjadi `gate`, tambahkan gerbang perf (`needs-perf`, angka wajib), waiver (hanya perf), cek `Commit:` = head. Jalankan suite → hijau.
- [x] Perbarui `agents/security.md` (baris vonis + `Commit: <sha>`). Commit: `Gerbang perf, laporan terikat commit, dan waiver owner`.

### Task 3: Pemindai baseline `baseline-scan.sh`
**Files:** Create `scripts/baseline-scan.sh`; Modify `scripts/pr-merge-check.sh`; Test `tests/run.sh` (blok baru 2e).
**Interfaces:** `baseline-scan.sh --body <berkas> --perf-labeled <0|1> < diff` → baris `BLOK: …` (rahasia) dan `PERINGATAN: …`; exit 1 bila ada `BLOK`. Hanya baris tambahan diff (`^+`, bukan `+++`).
- [x] Tes (diff mini sebagai stdin): kunci `AKIA` + 16 karakter → `BLOK` exit 1; kunci privat berformat PEM → 1; kredensial literal bernilai ≥12 karakter → 1; berkas `+++ b/.env` → 1; baris yang dihapus (`-`) berisi rahasia → 0; `sync || true` pada berkas tambahan → exit 0 + `PERINGATAN`; tambahan `go.mod`/`package.json`/`FROM`/`image:` dengan nama paket tak disebut di `--body` → `PERINGATAN` (disebut → tanpa); diff menyentuh `migrations/`, `Dockerfile`, `docker-compose`, `redis.conf`, `postgresql.conf` dengan `--perf-labeled 0` → `PERINGATAN` perlu `needs-perf`; `--perf-labeled 1` → tanpa peringatan itu.
- [x] Jalankan suite → merah; implementasikan skrip; suite → hijau.
- [x] Di `pr-merge-check.sh` (pra-merge): `gh pr diff` → `baseline-scan.sh`; `BLOK` tanpa waiver cocok-head → exit 1; `gh pr diff` gagal → exit 1; peringatan hanya dicetak. Tes: diff berahasia tanpa/dengan waiver; `gh pr diff` gagal → 1. Commit: `Pemindai baseline: rahasia, dependensi baru, peringatan jalur`.

### Task 4: Role `aicrew-perf` dan dokumen alur
**Files:** Create `agents/perf.md`; Modify `agents/security.md`, `skills/breakdown/SKILL.md`, `skills/orchestrate/SKILL.md`, `skills/kickoff/SKILL.md`, `templates/WORKFLOW.md`, `README.md`, `.claude-plugin/plugin.json`; Test `tests/run.sh` (blok 3).
- [x] Tes konsistensi: `agents/perf.md` berfrontmatter (`name: aicrew-perf`, model sonnet, tools tanpa Edit/Write); `needs-perf` ada di `templates/WORKFLOW.md`, `skills/breakdown`, `skills/orchestrate`, `agents/perf.md`; `Batas perangkat keras` ada di template dan `skills/kickoff`; `aicrew-perf` ada di README dan daftar role kickoff; aturan "tanpa atribusi AI" ada di `agents/perf.md` (blok tes atribusi yang ada diperluas).
- [x] Tulis `agents/perf.md` (tiga pemeriksaan dan format vonis sesuai spec bagian A; klaim tanpa angka = `gagal`; batas host "tidak diketahui" → `gagal` dengan alasan; baris `Angka sebelum/sesudah:`, `Tuning:` dan `Commit:` wajib). Perluas daftar hardening ketat di `agents/security.md` sesuai spec bagian C, termasuk **log audit**; tambahkan tes konsistensi bahwa `log audit` ada di `agents/security.md` dan `Tuning:` ada di `agents/perf.md`.
- [x] `breakdown` langkah 6: aturan penandaan `needs-perf`. `orchestrate`: kirim ke `aicrew-perf` setelah qa, tempel vonis verbatim, syarat auto-merge ikut; larangan agen menulis waiver. `kickoff`: tanyakan batas perangkat keras. Template: label, bagian `## Batas perangkat keras`, model per role.
- [x] Suite hijau. Commit: `Role aicrew-perf, bagian Batas perangkat keras, dan alur needs-perf`.

### Task 5: Vonis rilis
**Files:** Modify `scripts/release-report.sh`; Test `tests/run.sh` (blok 2d).
**Interfaces:** kueri PR menambah `body,labels`; label sensitif PR = label PR ∪ label issue yang ditutup badan PR (dari `issues` JSON yang sudah dibaca).
- [x] Tes (pakai pola `rr` yang ada): PR ter-merge dengan issue `needs-perf` tanpa komentar `Laporan perf: lulus` → exit 1 (alasan disebut); dengan komentar → 0; sama untuk `needs-security`; bagian "Jejak audit" pada laporan memuat tiap PR berlabel (sha, vonis, baris `Tuning:`) dan komentar waiver; kueri `gh` gagal → exit 1.
- [x] Merah → implementasi (alasan baru di `reasons`, bagian Jejak audit di keluaran, item daftar periksa bawaan: uji beban di server nyata dan hardening security) → hijau. Commit: `Vonis rilis memeriksa laporan perf dan security`.

## Pemeriksaan akhir
- [x] `bash tests/run.sh` → `SEMUA LULUS`; `git status -sb` bersih; `git log --oneline main..HEAD` menunjukkan 5 commit tanpa atribusi AI. Laporkan hasil apa adanya.
