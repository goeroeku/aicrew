# Paket privat tidak dikirim ke OSV Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paket yang dinyatakan privat oleh pemiliknya tidak pernah dikirim ke `api.osv.dev`; pemeriksaan paket publik tetap jalan dan yang dilewati dilaporkan jujur.

**Architecture:** `cve-check.sh` menerima daftar pola (`--private <berkas>` / env `CVE_PRIVATE`) dan membuang entri yang cocok dari daftar dependensi head DAN basis sebelum kueri apa pun. Skrip baru `cve-private.sh` mengumpulkan pola dari tiga sumber eksplisit (baris `Paket privat:` di WORKFLOW, `GOPRIVATE`, scope `.npmrc` non-publik). Gerbang (`pr-merge-check.sh`) membaca sumber dari cabang tujuan lewat REST, fail-closed; `cve-audit.sh` membaca dari disk.

**Tech Stack:** bash 3.2/Linux, `jq`, `gh api`; tes `tests/run.sh` (curl/gh palsu).

**Spec:** `docs/superpowers/specs/2026-11-01-paket-privat-osv-design.md` (issue #25). Cabang kerja: lanjutkan `goeroeku/desain-paket-privat`; PR akhir memuat `Closes #25`.

## Global Constraints
- Nama yang cocok pola tidak boleh muncul di badan permintaan `curl` mana pun (head, basis, `prefetch`).
- Sumber "privat" hanya: baris `Paket privat: <pola>, <pola>` di `docs/WORKFLOW.md` (semua ekosistem); `GOPRIVATE` dari env atau `go env GOPRIVATE` (hanya Go); baris `.npmrc` proyek `@scope:registry=<URL>` yang host-nya bukan `registry.npmjs.org` / `registry.yarnpkg.com` -> `@scope/*` (hanya npm). Tidak ada tebakan dari URL `resolved`, `registry=` global, PyPI otomatis, atau `~/.npmrc`.
- Baris `.npmrc` selain pemetaan scope (token, `_authToken`) tidak pernah dibaca, dicetak, atau dikirim.
- Entri Go: semantik awalan modul untuk SEMUA sumber (cocokkan pola ke `a`, `a/b`, `a/b/c`; `git.corp.com/team` tidak cocok `git.corp.com/teamx`). Entri PyPI: nama dan pola dinormalisasi (huruf kecil, `.`/`_` -> `-`). npm: apa adanya.
- Pola `*` atau `**` saja diabaikan dengan `PERINGATAN: pola '*' mematikan pemeriksaan; pakai "Pemeriksaan CVE: tidak"`.
- Gerbang: pola dari CABANG TUJUAN (bukan PR); sumber gagal dibaca selain 404 = `GAGAL` (fail-closed); keluaran gerbang hanya jumlah (`PERINGATAN: cve (<berkas>) N paket privat tidak diperiksa`), tanpa nama.
- Bahasa komentar, pesan, commit: Indonesia. Tanpa atribusi AI. Bash 3.2 (macOS) dan Linux CI.

## Review Focus
- Paket privat ikut kueri versi basis atau `prefetch` (kebocoran lewat jalur sampingan). -> tes Task 1 (curl palsu mencatat badan; nama tidak ada).
- Token `.npmrc` (`//host/:_authToken=...`) muncul di keluaran/stderr/berkas pola. -> tes Task 2.
- Pola `*` atau baris `Paket privat:` kosong mematikan pemeriksaan diam-diam. -> tes Task 1 dan 2.
- PR menambah pola di cabangnya sendiri lalu paket cocok tetap dikirim tanpa peringatan. -> tes Task 3.
- WORKFLOW/`.npmrc` cabang tujuan error 500 membuat gerbang meneruskan nama privat. -> tes Task 3.

---

### Task 1: Penyaring pola di `cve-check.sh`

**Files:**
- Modify: `scripts/cve-check.sh` (fungsi baru + `check()` + penanganan argumen)
- Test: `tests/run.sh` (bagian baru `3l-1`, setelah `3j-7`)

**Interfaces:**
- Produces: format berkas pola = satu baris per pola, `<eko>\t<pola>` dengan eko `*|npm|Go|PyPI`; baris tanpa tab = eko `*`. Opsi `cve-check.sh <berkas> [--base <b>] [--private <berkas-pola>]` (urutan opsi bebas setelah berkas); env `CVE_PRIVATE` = pola dipisah koma (eko `*`), digabung dengan berkas. Stderr: satu baris `dilewati (privat): <nama>@<versi>` per entri HEAD yang dilewati (entri basis dilewati tanpa laporan). `--list` tetap tanpa penyaringan.
- Fungsi `private_drop <berkas-pola>`: stdin TSV (`eko nama versi lingkup`) -> stdout entri yang tersisa; menulis laporan stderr. Dipanggil di `check()` untuk `deps` dan `bdeps` sebelum `changed`/`prefetch` dihitung (laporan hanya untuk head).

- [ ] **Step 1: Tulis tes merah** di `tests/run.sh` bagian `3l-1` (pakai `FX`, `CK`, `LOCK` yang sudah ada). Nama tes dan asersi:
  - `cve privat: npm @acme/x dilewati` — lockfile berisi `@acme/x` dan `lodash`; berkas pola `npm\t@acme/*`; `$CVE_FIX/calls` tidak memuat `@acme/x` (grep -c = 0) tetapi memuat `lodash`; stderr memuat tepat 1 baris `dilewati (privat): @acme/x@`.
  - `cve privat: kueri basis tidak membocorkan` — `--base` berisi `@acme/x@1.0.0`, head `@acme/x@2.0.0`; `calls` tanpa `@acme/x`.
  - `cve privat: Go awalan modul` — go.mod berisi `git.corp.com/team/x` dan `git.corp.com/teamx/y`; pola `Go\tgit.corp.com/team`; hanya `.../team/x` dilewati (`calls` memuat `teamx/y`, tidak memuat `team/x`).
  - `cve privat: pola eko lain tidak berlaku` — pola `Go\t@acme/*` tidak melewati npm `@acme/x` (calls memuatnya).
  - `cve privat: PyPI dinormalisasi` — requirements `Internal_Lib==1.0`, pola `Internal.Lib` -> dilewati.
  - `cve privat: CVE_PRIVATE env koma` — `CVE_PRIVATE='a,@acme/*'` melewati `@acme/x`.
  - `cve privat: pola * diabaikan` — pola `*` -> `lodash` tetap dikueri, stderr memuat tepat 1 baris `PERINGATAN: pola '*' mematikan pemeriksaan`; sama untuk `**`.
  - `cve privat: kode keluar tidak berubah` — semua entri dilewati -> exit 0 tanpa keluaran; paket publik HIGH di lockfile yang sama -> exit 1.
- [ ] **Step 2: Jalankan** `bash tests/run.sh 2>&1 | tail -30`. Expected: tes baru GAGAL (opsi `--private` tidak dikenal -> exit 64), tes lama tetap ok.
- [ ] **Step 3: Implementasi** `private_drop` dan opsi `--private` di `scripts/cve-check.sh`: gabung `CVE_PRIVATE` + isi berkas ke satu berkas pola sementara di `$T`; buang pola `*`/`**` dengan peringatan; cocokkan memakai `case "$nama" in $pola)` (Go: loop awalan jalur; PyPI: normalisasi keduanya). Panggil di `check()` tepat setelah `list_deps` head dan basis. Perluas `case` argumen (`''|-*`, `*)`) agar `--private <berkas>` boleh di posisi mana pun setelah berkas, tanpa menggeser kode keluar 64 untuk salah pakai.
- [ ] **Step 4: Jalankan** `bash tests/run.sh 2>&1 | tail -5`. Expected: `SEMUA LULUS`.
- [ ] **Step 5: Commit** `git commit -m "Paket privat: cve-check membuang entri bertepatan pola sebelum kueri (#25)"`.

### Task 2: Pengumpul pola `cve-private.sh`

**Files:**
- Create: `scripts/cve-private.sh`
- Test: `tests/run.sh` (bagian `3l-2`)

**Interfaces:**
- Produces: `cve-private.sh [--workflow <berkas>] [--npmrc <berkas>]... [--goprivate]` -> stdout format berkas pola Task 1 (terurut, tanpa duplikat); selalu exit 0; berkas yang tak ada diabaikan.
  - `--workflow`: baris `^[- ]*Paket privat: *(.*)` (di mana saja dalam baris butir), dipisah koma, spasi dipangkas, satu titik penutup dibuang; pola kosong dibuang; eko `*`.
  - `--npmrc`: hanya baris `^[[:space:]]*(@scope):registry[[:space:]]*=[[:space:]]*<URL>`; host = tanpa tanda kutip, skema, jalur, port-tetap-boleh, huruf kecil; host `registry.npmjs.org` / `registry.yarnpkg.com` dilewati; selain itu `npm\t@scope/*`. Baris lain tidak diproses sama sekali.
  - `--goprivate`: `${GOPRIVATE:-$(go env GOPRIVATE 2>/dev/null)}` dipisah koma -> `Go\t<pola>`.

- [ ] **Step 1: Tulis tes merah** `3l-2`:
  - `cve-private: baris Paket privat dari WORKFLOW` — `- Paket privat: @acme/*, git.corp.com/team, internal-lib.` -> tiga baris (`*\t@acme/*`, ...), titik penutup dibuang; baris `Paket privat:` kosong -> keluaran kosong.
  - `cve-private: .npmrc scope ke proxy -> npm @scope/*` dan `scope ke registry.npmjs.org (dengan https dan / akhir, huruf besar) -> kosong`.
  - `cve-private: token .npmrc tidak pernah tampil` — `.npmrc` berisi `//corp.example/:_authToken=SECRET123`, `registry=https://proxy.example/`, `@acme:registry=https://corp.example/`; keluaran tidak memuat `SECRET123`, `proxy.example` maupun `_authToken`; hanya `npm\t@acme/*`.
  - `cve-private: GOPRIVATE env` -> `Go\tgit.corp.com/*` per pola; env kosong dan tanpa `go` -> kosong.
  - `cve-private: berkas tak ada -> kosong, exit 0` dan `dua sumber digabung tanpa duplikat`.
- [ ] **Step 2: Jalankan** `bash tests/run.sh 2>&1 | tail -20`. Expected: tes `3l-2` GAGAL (skrip tak ada).
- [ ] **Step 3: Implementasi** `scripts/cve-private.sh` (bash, `set -u`), keluaran lewat `LC_ALL=C sort -u`.
- [ ] **Step 4: Jalankan** `bash tests/run.sh 2>&1 | tail -5`. Expected: `SEMUA LULUS`.
- [ ] **Step 5: Commit** `git commit -m "Paket privat: cve-private.sh mengumpulkan pola dari WORKFLOW, GOPRIVATE, .npmrc (#25)"`.

### Task 3: Gerbang `pr-merge-check.sh`

**Files:**
- Modify: `scripts/pr-merge-check.sh` (blok CVE, sekitar baris 70-105)
- Test: `tests/run.sh` (bagian `3l-3`, memakai `GE`, `DGO`, `CF`, `FX` dari `3j-4`)

**Interfaces:**
- Consumes: `cve-private.sh` (Task 2) dan `--private` (Task 1); `cve_fetch <ref> <path> <keluaran>` (rc 0 / 4 = 404 / 1 galat lain) yang sudah ada.
- Produces: per manifest, berkas pola dari cabang tujuan `$dst`: `docs/WORKFLOW.md` (sudah diambil ke `$cdir/wf`), `.npmrc` di direktori manifest dan di akar repo, serta `--goprivate`. Pesan: `PERINGATAN: cve (<berkas>) N paket privat tidak diperiksa`, `PERINGATAN: cve (<berkas>) pola privat baru baru berlaku setelah di-merge; paket yang cocok pada PR ini tetap dikirim`, `GAGAL: cve: <sumber> tak terbaca di cabang tujuan (REST)`.

- [ ] **Step 1: Tulis tes merah** `3l-3` (go.mod `git.corp.com/team/x v1.0.0` di head; `FX Go git.corp.com/team/x 1.0.0` HIGH):
  - `gerbang privat: pola WORKFLOW cabang tujuan -> lolos, curl tidak memuat nama, PERINGATAN 1 paket tanpa nama` — `$CF/main/docs/WORKFLOW.md` berisi `- Paket privat: git.corp.com/team`; keluaran tidak memuat `git.corp.com`; exit 0.
  - `gerbang privat: pola hanya di PR (head), tidak di cabang tujuan -> tetap BLOK dan PERINGATAN pola baru` — WORKFLOW berpola ada di `$CF/abc1234567/docs/WORKFLOW.md` saja; exit 1; `grep -c 'pola privat baru'` = 1.
  - `gerbang privat: .npmrc cabang tujuan (direktori manifest dan akar)` — package-lock di `web/` dengan `@acme/x`; `.npmrc` di `$CF/main/web/.npmrc` lalu terpisah di `$CF/main/.npmrc` -> keduanya bekerja; keluaran tanpa token dari `.npmrc`.
  - `gerbang privat: WORKFLOW tak terbaca (500) -> GAGAL cve fail-closed` (`CF_ERR=1` untuk path WORKFLOW saja; perluas `gh` palsu agar `CF_ERR_PATH` membatasi galat ke satu path) dan `.npmrc` 500 -> GAGAL; 404 pada keduanya -> jalan normal tanpa pola.
  - `gerbang privat: opt-out WORKFLOW 'Pemeriksaan CVE: tidak' tetap menang` (regresi) dan `waiver cve tetap menutup`.
  - `gerbang privat: semua paket yang berubah privat -> exit 0, PERINGATAN jumlah`.
- [ ] **Step 2: Jalankan** `bash tests/run.sh 2>&1 | tail -20`. Expected: tes `3l-3` GAGAL (nama terkirim / BLOK).
- [ ] **Step 3: Implementasi** di blok CVE: setelah opt-out dicek, jika `fr` (WORKFLOW cabang tujuan) bukan 0 atau 4 -> `fail`. Per manifest: ambil `.npmrc` dari `dirname(mp)` dan akar dari `$dst` (404 = lewati, galat lain -> `fail`); panggil `cve-private.sh --workflow "$cdir/wf" --npmrc ... --goprivate > "$cdir/$ci/pat"`; teruskan `--private "$cdir/$ci/pat"` ke `cve-check.sh`. Ganti penerusan stderr: hitung baris `^dilewati (privat):`, cetak PERINGATAN jumlah (tanpa nama), buang baris itu dari stderr yang diteruskan. Peringatan pola baru: ambil WORKFLOW dan `.npmrc` dari `$head` (kegagalan di sini diabaikan), hitung pola dengan `cve-private.sh` tanpa `--goprivate`, bandingkan dengan pola cabang tujuan (`comm -13`); ada selisih -> PERINGATAN.
- [ ] **Step 4: Jalankan** `bash tests/run.sh 2>&1 | tail -5`. Expected: `SEMUA LULUS`.
- [ ] **Step 5: Commit** `git commit -m "Paket privat: gerbang CVE memakai pola cabang tujuan, fail-closed, laporan tanpa nama (#25)"`.

### Task 4: `cve-audit.sh`, dokumen, versi

**Files:**
- Modify: `scripts/cve-audit.sh`, `skills/cve-audit/SKILL.md`, `templates/WORKFLOW.md:25`, `PRIVACY.md:14-18`, `README.md:138`, `.claude-plugin/plugin.json` (0.9.0)
- Test: `tests/run.sh` (bagian `3l-4`)

**Interfaces:**
- Consumes: `cve-private.sh`, `--private` (Task 1-2); `workflow.sh` untuk isi WORKFLOW terbaru.
- Produces: audit menulis `tidak ada kerentanan diketahui di OSV per <tanggal> untuk <berkas> (N paket privat tidak diperiksa)` atau, bila semua entri (`cve-check.sh --list`) dilewati, `semua dependensi dilewati (privat); tidak ada yang diperiksa untuk <berkas>`; nama paket yang dilewati tidak masuk judul/badan issue.

- [ ] **Step 1: Tulis tes merah** `3l-4`: audit (`--dry-run`, repo sementara dengan `docs/WORKFLOW.md` berisi `Paket privat:`, curl palsu) -> `calls` tanpa nama privat; keluaran memuat `(1 paket privat tidak diperiksa)`; semua dilewati -> kalimat `semua dependensi dilewati (privat)`; `.npmrc` di direktori lockfile dan akar dibaca; tes dokumen: `PRIVACY.md`, `templates/WORKFLOW.md`, `README.md`, `skills/cve-audit/SKILL.md` memuat `Paket privat:`; `PRIVACY.md` memuat `~/.npmrc`; `plugin.json` versi `0.9.0`.
- [ ] **Step 2: Jalankan** `bash tests/run.sh 2>&1 | tail -20`. Expected: tes `3l-4` GAGAL.
- [ ] **Step 3: Implementasi** `cve-audit.sh`: per berkas, tulis pola (`workflow.sh` + `cve-private.sh --npmrc <dir-berkas>/.npmrc --npmrc ./.npmrc --goprivate`) ke berkas sementara, teruskan `--private`, tangkap stderr, hitung `dilewati (privat)` (nama tidak diteruskan ke judul/badan), pakai kalimat di Interfaces. Dokumen: templat WORKFLOW memuat baris `- Paket privat: {{pola dipisah koma, mis. @perusahaan/*, git.perusahaan.com/tim | kosong}}`; `PRIVACY.md` mengganti butir nama privat (sumber pola, bahwa paket dilewati tidak diperiksa, `~/.npmrc` tidak dibaca, GOPRIVATE hanya bantuan, scope publik di proxy ikut dilewati); README satu kalimat pendek ke paragraf CVE (tanpa paragraf per versi baru); SKILL `cve-audit` menyebut pola. Naikkan `plugin.json` ke `0.9.0`.
- [ ] **Step 4: Jalankan** `bash tests/run.sh 2>&1 | tail -5`. Expected: `SEMUA LULUS`.
- [ ] **Step 5: Commit** `git commit -m "Rilis 0.9.0: paket privat tidak dikirim ke OSV (#25)"`.
