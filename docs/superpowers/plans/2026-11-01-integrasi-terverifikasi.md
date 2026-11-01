# Integrasi terverifikasi dan alur terjadwal menunggu rilis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, dipilih owner) atau superpowers:subagent-driven-development. Steps memakai checkbox (`- [ ]`).

**Goal:** Label `di-integrasi`, penutupan issue, dan kartu Done hanya setelah PR terbukti masuk cabang integrasi (#28); PR yang menambah alur terjadwal/dependabot ke cabang non-bawaan diperingatkan dan issue-nya menunggu rilis (#32).

**Architecture:** Tiga skrip kecil hanya-REST/git (`terintegrasi.sh`, `alur-terjadwal.sh`, `menunggu-rilis.sh`) dipakai bersama oleh `pr-merge-check.sh`, `resume.sh`, `board.sh`, `cve-audit.sh`, dan skill `orchestrate`. Semua gagal-tertutup (exit 2 = tak bisa diperiksa).

**Tech Stack:** bash 3.2 (macOS) + Linux, `gh api` (REST), `jq`, `git`; tes `bash tests/run.sh` dengan `gh` palsu dan repo git sementara.

**Spec:** `docs/superpowers/specs/2026-11-01-integrasi-terverifikasi-design.md` (bagian "Keputusan tambahan" mengikat).

## Global Constraints
- Hanya `git` dan `gh api` REST; tanpa `gh pr`/`gh issue` (GraphQL). 403/429 → exit 2.
- Artefak berbahasa Indonesia. Dilarang atribusi AI di commit/berkas. Tanpa `--force`.
- Tanpa cabang integrasi (baris `Cabang integrasi:` tidak ada, `WORKFLOW.md` terbaca): perilaku lama tak berubah.
- Label `menunggu-rilis` dapat dikonfigurasi lewat `label.sh` (`Label menunggu rilis:`).
- Versi rilis kandidat `0.10.0` (`.claude-plugin/plugin.json` + tes pin versi di `tests/run.sh`).

## Review Focus
- PR merge-commit, squash, dan rebase ke integrasi (SHA ujung vs `merge_commit_sha`) — terdeteksi benar.
- PR ditutup tanpa merge (`merged_at` kosong) dengan `base.ref` = integrasi — harus ditolak.
- `WORKFLOW.md` tak terbaca / nama integrasi kosong — exit 2, bukan "tanpa integrasi".
- Berkas workflow `removed`/`renamed` pada PR; workflow tanpa `schedule:`/`workflow_dispatch:` — tanpa peringatan palsu.
- Issue tanpa PR atau dengan lebih dari satu PR merged di `board.sh --sync` — tidak ditutup, dilaporkan.

---

### Task 1: `scripts/terintegrasi.sh` (pemeriksa bersama, #28)

**Files:** Create `scripts/terintegrasi.sh`; Modify `tests/run.sh` (bagian baru `3m-1`).

**Interfaces:**
- Produces: `terintegrasi.sh <pr>` → exit 0 (terintegrasi, atau proyek tanpa integrasi; stdout satu baris), exit 1 (stdout: `ter-merge ke <base>, belum ke <integrasi>` atau `PR belum merged`), exit 2 (tak bisa diperiksa; stderr alasan).
- Consumes: `ghx_repo` dari `scripts/ghx.sh`; `scripts/workflow.sh` (isi WORKFLOW) dan pola pembacaan `Cabang integrasi:` seperti `workflow.sh:5`.

- [ ] **Step 1: tes merah** (`3m-1`, `gh` palsu menjawab `repos/*/pulls/N` dengan JSON dari berkas; repo git sementara + remote bare): `ok` untuk: (a) `base.ref`=integrasi & `merged_at` terisi → 0; (b) base=induk, `merge_commit_sha` leluhur `origin/<integrasi>` → 0; (c) base=induk, `head.sha` leluhur → 0; (d) base=induk, tak satu pun leluhur → 1 dan pesan memuat induk dan integrasi; (e) `merged_at` kosong, base=integrasi → 1; (f) `WORKFLOW.md` kosong/tak terbaca padahal base ≠ bawaan → 2; (g) tanpa baris `Cabang integrasi:` (WORKFLOW terbaca) → 0; (h) REST gagal → 2.
- [ ] **Step 2:** jalankan `bash tests/run.sh`; Expected: kedelapan tes baru GAGAL (skrip belum ada).
- [ ] **Step 3: implement** `scripts/terintegrasi.sh`: ambil `pulls/<pr>` (`base.ref`, `merged_at`, `merge_commit_sha`, `head.sha`); `git fetch -q origin <integrasi>`; urutan keputusan seperti spec ("Bukti terintegrasi"). Nama integrasi dari `workflow.sh`.
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Integrasi terverifikasi: terintegrasi.sh memeriksa PR masuk cabang integrasi (#28)`.

### Task 2: `scripts/alur-terjadwal.sh` + peringatan di gerbang (#32)

**Files:** Create `scripts/alur-terjadwal.sh`; Modify `scripts/pr-merge-check.sh` (setelah blok baseline/CVE, sebelum `echo "ok: gerbang lolos…"`); Modify `tests/run.sh` (`3m-2`).

**Interfaces:**
- Produces: `alur-terjadwal.sh <pr>` → stdout satu jalur per baris (berkas pemicu: `.github/workflows/*.y(a)ml` berisi `schedule:` atau `workflow_dispatch:` pada `head.sha`, atau `.github/dependabot.y(a)ml`); status `removed` dilewati, `renamed` memakai nama baru; exit 0 (daftar boleh kosong), 2 bila REST gagal.
- Consumes: `repos/<r>/pulls/N/files`, `contents/<path>?ref=<head>` (pola `cve_fetch` di `pr-merge-check.sh:81`; salin sebagai fungsi lokal, bukan pindah).

- [ ] **Step 1: tes merah** (`3m-2`): PR ke `integrasi` yang menambah workflow ber-`schedule:` → gerbang mencetak baris `PERINGATAN: alur terjadwal …` dan tetap `ok: gerbang lolos`; sama tetapi cabang tujuan = cabang bawaan → tanpa peringatan; workflow tanpa pemicu terjadwal → tanpa peringatan; `dependabot.yml` → peringatan; berkas `removed` → tanpa peringatan; daftar berkas tak terbaca → `GAGAL`? **Tidak**: peringatan bukan penghalang; REST gagal mencetak `PERINGATAN: alur terjadwal tidak dapat diperiksa` dan lanjut.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL.
- [ ] **Step 3: implement** skrip dan panggilannya di gerbang. Cabang bawaan dari `gh api repos/<r> --jq .default_branch`; peringatan hanya bila `$dst` ≠ bawaan.
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Gerbang: peringatan alur terjadwal/dependabot di cabang non-bawaan (#32)`.

### Task 3: `menunggu-rilis`, `resume.sh`, `board.sh`, `label.sh`

**Files:** Create `scripts/menunggu-rilis.sh`; Modify `scripts/label.sh` (kunci `waiting`, default `menunggu-rilis`, baris `Label menunggu rilis`), `scripts/resume.sh`, `scripts/board.sh` (blok `board.sh:50-57` penutupan issue), `tests/run.sh` (`3m-3`).

**Interfaces:**
- Produces: `menunggu-rilis.sh --tandai <issue> <pr>` (REST: komentar berpenanda `<!-- aicrew-menunggu-rilis -->` memuat `- <path>` per berkas dari `alur-terjadwal.sh <pr>`, plus label `label.sh waiting`; tanpa berkas pemicu → tidak melakukan apa pun, exit 0); `menunggu-rilis.sh --cek <issue>` → exit 0 bila semua berkas di komentar ada di `contents?ref=<bawaan>` (stdout `siap`), 1 bila ada yang belum (stdout daftar yang belum), 2 bila tak terbaca. `resume.sh` mengeluarkan baris `<issue>\tperiksa-rilis\t<detail>` untuk issue terbuka berlabel waiting. `board.sh --sync` menutup issue `di-integrasi` hanya bila: tidak berlabel waiting, tepat satu PR merged dengan head `issue-<n>` (REST), dan `terintegrasi.sh <pr>` exit 0; selain itu tidak menutup dan mencetak satu baris alasan.
- Consumes: Task 1 (`terintegrasi.sh`), Task 2 (`alur-terjadwal.sh`).

- [ ] **Step 1: tes merah** (`3m-3`): `label.sh waiting` → `menunggu-rilis`, dapat diganti lewat WORKFLOW/env; `--tandai` memasang label dan komentar berisi daftar; `--cek` 0/1/2; `resume.sh` mengeluarkan `periksa-rilis`; `board.sh --sync` (opsi `Tutup issue setelah merge integrasi: ya`): issue dengan PR ke induk **tidak** ditutup, issue berlabel waiting tidak ditutup, tanpa PR atau 2 PR merged tidak ditutup, PR terintegrasi ditutup.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL.
- [ ] **Step 3: implement** per Interfaces; `resume.sh` tetap hanya-baca (hanya mencetak).
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `menunggu-rilis: label, penanda, pemeriksaan ulang, resume dan board.sh memakai terintegrasi (#28, #32)`.

### Task 4: `cve-audit.sh` melaporkan alur belum aktif

**Files:** Modify `scripts/cve-audit.sh`; Modify `tests/run.sh` (`3m-4`).

**Interfaces:** Consumes `workflow.sh` (nama integrasi). Produces satu baris `N alur terjadwal belum aktif (hanya di integrasi)` di keluaran, tanpa mengubah kode keluar atau membuat issue; tanpa integrasi atau `N=0` → tanpa baris.

- [ ] **Step 1: tes merah** (`3m-4`): repo sementara dengan integrasi memuat `.github/workflows/v.yml` (`schedule:`) dan `dependabot.yml`, cabang bawaan tidak → baris `2 alur terjadwal belum aktif`; sudah ada di bawaan → tanpa baris; tanpa integrasi → tanpa baris.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: GAGAL.
- [ ] **Step 3: implement** dengan `git fetch` + `git ls-tree -r origin/<integrasi>` vs `origin/<bawaan>` (bukan `git ls-files`); dijalankan sebelum jalur "tidak ada manifest" yang keluar dini (`cve-audit.sh:12`).
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `cve-audit: laporkan alur terjadwal yang hanya ada di integrasi (#32)`.

### Task 5: Skill, dokumen, rilis 0.10.0

**Files:** Modify `skills/orchestrate/SKILL.md` (langkah `selesaikan-merge` dan label `di-integrasi`: panggil `terintegrasi.sh` dulu; aksi `periksa-rilis`; tandai `menunggu-rilis` bila `alur-terjadwal.sh` tak kosong), `README.md` (satu paragraf pendek), `templates/WORKFLOW.md` (baris `Label menunggu rilis`), `.claude-plugin/plugin.json` → `0.10.0`, `tests/run.sh` (pin versi + pemeriksaan kata kunci skill).

- [ ] **Step 1: tes merah:** pin `plugin.json versi 0.10.0`; `grep` SKILL.md memuat `terintegrasi.sh`, `periksa-rilis`, `menunggu-rilis`; templat memuat `Label menunggu rilis`.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: GAGAL.
- [ ] **Step 3:** ubah berkas di atas (redaksi singkat, selaras gaya).
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Rilis 0.10.0: integrasi terverifikasi dan alur terjadwal menunggu rilis (#28, #32)`.
