# Journey dan Epic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Lead dapat melihat progres per user journey (use case), bukan hanya daftar task kecil: PRD memuat Journeys dan NFR, breakdown membuat satu epic per journey.

**Architecture:** Tiga lapis: Journey (epic, dibaca lead) → FR/NFR (`R-ID`/`N-ID` di PRD) → issue kecil (dikerjakan agen). Epic adalah issue berlabel `epic` dengan daftar centang `- [ ] #n`; GitHub menghitung progresnya sendiri. Epic BUKAN pekerjaan: skrip yang menghitung issue terbuka harus mengabaikannya.

**Tech Stack:** bash, jq, gh (sudah ada). Tanpa dependensi baru.

**Spec:** percakapan dengan owner 2026-10-31 (keputusan: journey = epic; checklist, bukan sub-issue native; tanpa `journey-report.sh` dulu; seri `N` untuk NFR; rilis 0.5.0).

## Global Constraints
- Dokumen aicrew berbahasa Indonesia; templat issue (`ISSUE.md`, `EPIC.md`) berbahasa Inggris (bahasa artefak bawaan).
- Issue yang sudah ada (terutama `in-progress` atau ber-assignee) tidak pernah diedit; epic hanya merujuknya.
- Tes lebih dulu; `bash tests/run.sh` hijau penuh sebelum commit. Tanpa atribusi AI di commit/PR/berkas.
- Versi: `.claude-plugin/plugin.json` 0.4.1 → 0.5.0.

## Review Focus
- Epic terbuka tidak boleh membuat autopilot tak pernah exit 0 (`autopilot.sh:37`) maupun `waiting_on_owner` (`:28`) salah menghitung.
- Epic terbuka tidak boleh membuat `release-report.sh` selalu BELUM SIAP (`blocking`).
- Epic tidak boleh diambil orkestrator sebagai tugas (skill orchestrate) atau diklasifikasi `resume.sh`.
- Issue lama yang tak cocok dengan journey mana pun masuk grup "Unassigned", bukan dipaksakan.
- Satu FR boleh melayani lebih dari satu journey (muncul di dua epic tanpa duplikat issue).

---

### Task 1: Skrip mengabaikan epic

**Files:**
- Modify: `scripts/autopilot.sh:37`, `scripts/release-report.sh` (`blocking`, `needs`), `scripts/resume.sh:10`
- Test: `tests/run.sh` (bagian baru `# 4.`)

**Interfaces:**
- Produces: konvensi label `epic` = bukan pekerjaan; Task 2-3 memakai label ini.

- [ ] **Step 1: Tes gagal.** Di `tests/run.sh`, ulangi pola fake `gh` yang ada: (a) `release-report.sh --dry-run` dengan satu PR ter-merge, satu issue `di-integrasi` tertutup, dan satu issue `epic` terbuka → harapan: epic TIDAK muncul di alasan "issue terbuka belum di-integrasi" (`ok "release-report: epic terbuka bukan penghalang"`); (b) `autopilot.sh` dengan issue terbuka hanya berlabel `epic` → exit 0 ("semua issue selesai"); (c) `resume.sh` dengan epic berlabel `in-progress` → tidak dikeluarkan.
- [ ] **Step 2: Jalankan** `bash tests/run.sh`; harapan: tiga tes baru GAGAL.
- [ ] **Step 3: Implementasi.** Tambah `"epic"` ke filter pengecualian: `autopilot.sh` (jq `select` pada `open` ikut membuang label `epic`), `release-report.sh` (`blocking` dan `needs` membuang label `epic`), `resume.sh` (select membuang `epic`). Satu helper jq per berkas; jangan membuat berkas bersama.
- [ ] **Step 4: Jalankan** `bash tests/run.sh`; harapan: SEMUA LULUS.
- [ ] **Step 5: Commit** `Epic bukan pekerjaan: diabaikan autopilot, laporan rilis, resume`.

### Task 2: Templat PRD dan EPIC

**Files:**
- Modify: `templates/PRD.md`, `templates/WORKFLOW.md` (daftar label: tambah `epic`)
- Create: `templates/EPIC.md`
- Test: `tests/run.sh`

**Interfaces:**
- Produces: bagian PRD `## Journeys` (kolom `ID | Journey | Kebutuhan (R-ID) | Selesai bila`), bagian `## Kebutuhan non-fungsional` (kolom `ID N1.. | Kebutuhan | Kriteria | Label`), dan `templates/EPIC.md` dengan judul `[J1] <journey>`, bagian `Journey`, `Requirements`, `Child issues` (daftar `- [ ] #n`), `Done when`.

- [ ] **Step 1: Tes gagal.** `grep -q '^## Journeys' templates/PRD.md`, `grep -q '^## Kebutuhan non-fungsional' templates/PRD.md`, `templates/EPIC.md` ada dan memuat `- [ ] #`, `epic` ada di daftar label `WORKFLOW.md`.
- [ ] **Step 2: Jalankan** suite; harapan: GAGAL.
- [ ] **Step 3: Tulis templat.** Tambahkan bagian PRD sebelum "Batasan"; ubah "Peta issue" menjadi `R-ID → #issue, gelombang, journey`. `EPIC.md` berbahasa Inggris, pendek (≤ 20 baris).
- [ ] **Step 4: Jalankan** suite; harapan: SEMUA LULUS.
- [ ] **Step 5: Commit** `Templat PRD: Journeys dan NFR; templat EPIC`.

### Task 3: Breakdown dan orchestrate memakai epic

**Files:**
- Modify: `skills/breakdown/SKILL.md` (langkah 3, 6, 8; audit 2b/2c), `skills/orchestrate/SKILL.md` (pemilihan issue), `README.md` (bagian baru "Journey dan epic")
- Test: `tests/run.sh`

**Interfaces:**
- Consumes: label `epic`, `templates/EPIC.md` (Task 2).

- [ ] **Step 1: Tes gagal.** `grep` bahwa breakdown menyebut `templates/EPIC.md`, `Unassigned`, dan "tidak pernah mengedit"; orchestrate menyebut bahwa label `epic` dilewati; README memuat "Journey".
- [ ] **Step 2: Jalankan** suite; harapan: GAGAL.
- [ ] **Step 3: Edit skill.** Breakdown: (a) bila PRD punya Journeys, setelah issue dibuat, buat satu epic per journey dari `EPIC.md` (label `epic`, daftar centang berisi issue anaknya; FR yang melayani dua journey muncul di dua epic, issue dibuat sekali); (b) proyek berjalan: issue lama hanya dirujuk di epic, yang tak cocok masuk epic `[J0] Unassigned`; issue `in-progress`/ber-assignee tidak diedit; (c) tampilkan rencana epic ke owner bersama tabel issue (persetujuan yang sama). Orchestrate: lewati issue berlabel `epic`; epic ditutup owner saat semua anak selesai. README: satu bagian pendek berisi hierarki Journey → FR → Issue.
- [ ] **Step 4: Jalankan** suite; harapan: SEMUA LULUS.
- [ ] **Step 5: Commit** `Breakdown membuat epic per journey; orchestrate melewatinya`.

### Task 4: Rilis 0.5.0

**Files:** Modify `.claude-plugin/plugin.json`

- [ ] **Step 1:** `jq '.version="0.5.0"'`; jalankan `bash tests/run.sh` (SEMUA LULUS) dan `bash scripts/check-version.sh v0.5.0` (ok).
- [ ] **Step 2:** Cabang `goeroeku/journey-epic`, push, buka PR, tunggu CI hijau. **Berhenti di sini dan minta persetujuan owner sebelum merge**: izin merge+rilis sebelumnya hanya untuk pekerjaan pilot dan 0.4.1.
- [ ] **Step 3 (setelah disetujui):** merge, verifikasi tag `v0.5.0` dan 3 aset; perbarui memori (rilis terakhir).

## Self-review
- Cakupan: journey→epic (T2-3), NFR (T2), orang lama/Unassigned (T3), bahaya epic terbuka (T1), rilis (T4). Tanpa `journey-report.sh` (keputusan).
- Konsistensi: label `epic` dan `templates/EPIC.md` dipakai sama di T1-T3.
- Proporsi: 4 tugas, tanpa skrip baru; sebagian besar perubahan dokumen dan filter jq.
