# Pemeriksaan CVE dependensi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PR yang memasukkan atau menaikkan dependensi diperiksa kerentanannya ke OSV, dan seluruh repo bisa diaudit dengan saran update (`patch|minor|major|tanpa-perbaikan`).

**Architecture:** `scripts/cve-check.sh` (parser lockfile, kueri OSV, pengelompokan alias, severity, target versi, paparan baru) dipanggil oleh gerbang `pr-merge-check.sh` hanya bila diff menyentuh manifest, dan oleh `scripts/cve-audit.sh` yang membuat issue lewat REST. `baseline-scan.sh` tidak diubah (tetap tanpa jaringan).

**Tech Stack:** bash, `curl`, `jq`, `sort -V`; tes deterministik `tests/run.sh` dengan `curl` dan `gh` palsu.

**Spec:** `docs/superpowers/specs/2026-11-01-pemeriksaan-cve-design.md` (issue #22). Cabang kerja: lanjutkan `goeroeku/desain-cve`; PR akhir memuat `Closes #22`.

## Global Constraints
- Ekosistem tahap 1: npm (`package-lock.json`, kunci `packages`), Go (`go.mod`), PyPI (`requirements*.txt`, hanya `nama==versi`). Bentuk lain dilewati dengan catatan `tidak lengkap: ...` di stderr.
- Hanya ekosistem, nama paket, dan versi yang dikirim ke `${OSV_API:-https://api.osv.dev}` lewat `POST /v1/query`; tanpa token. `curl -sS -m 25 --retry 1`.
- Severity: `database_specific.severity` (`LOW|MODERATE|HIGH|CRITICAL`); rekaman tanpa severity memakai severity kembaran yang beralias sama; tanpa kembaran → `UNKNOWN`. **`UNKNOWN` diperlakukan seperti HIGH (memblokir).**
- Memblokir = `paparan=baru` DAN `lingkup=prod` DAN severity ∈ {HIGH, CRITICAL, UNKNOWN}. Selain itu hanya peringatan. `dev` = npm `dev:true` atau berkas `requirements*dev*`; Go `// indirect` dihitung `prod`.
- Kode keluar `cve-check.sh`: 0 tak ada yang memblokir; 1 ada yang memblokir; 2 OSV tak terjangkau; 64 salah pakai.
- Gerbang tetap fail-closed: manifest tersentuh + OSV mati → tolak. Waiver `Pengecualian disetujui owner (cve): <alasan> (Commit: <sha>)` memakai `waiver_ok` yang ada. Opt-out: baris `Pemeriksaan CVE: tidak` di `WORKFLOW.md` → lewati dengan satu baris `PERINGATAN: pemeriksaan CVE dimatikan di WORKFLOW.md`.
- Isi berkas gerbang lewat REST: `gh api -H 'Accept: application/vnd.github.raw' repos/<r>/contents/<path>?ref=<sha|cabang>`; head = `$head`, basis = cabang tujuan `$dst`. 404 pada head → lewati berkas; 404 pada basis → semua paket dianggap baru.
- Laporan tidak pernah menulis "bebas CVE": tulis "tidak ada kerentanan diketahui di OSV per `<tanggal>` untuk `<berkas>`".
- Bahasa komentar, pesan, dan commit: Indonesia. Tanpa atribusi AI. Jalan di macOS (bash 3.2) dan Linux CI.

## Review Focus
- Nama berskop dan berjalur (`@scope/pkg`, `golang.org/x/net`) di badan JSON, URL, dan nama berkas fixture. → tes Task 2.
- Pasangan (ekosistem, nama, versi) kembar hanya sekali dikueri (lockfile besar). → tes Task 2.
- Perbandingan `4.17.9` vs `4.17.21` dan pra-rilis (`1.0.0-rc.1`) pada pemilihan versi perbaikan. → tes Task 3.
- Paket yang naik dari versi rentan ke versi yang kerentanannya himpunan-bagian: bukan blokir. → tes Task 3.
- Berkas manifest dihapus/diganti nama pada PR; nama berkas bersepasi. → tes Task 4.
- `next_page_token` OSV: digabung dan loop dibatasi (maks 20 halaman). → tes Task 2.

---

### Task 1: `cve-check.sh --list` (parser lockfile)
**Files:** Create `scripts/cve-check.sh`; Test `tests/run.sh` (bagian baru `# 3j`, dengan fixture di `$tmp/cve/`).
**Interfaces — Produces:** `cve-check.sh --list <berkas>` → stdout TSV `ekosistem  nama  versi  lingkup`, urut nama; stderr `tidak lengkap: <alasan>` per kelompok yang dilewati; exit 0; berkas bernama lain → exit 64. Normalisasi: Go tanpa awalan `v`; PyPI huruf kecil dengan `.` dan `_` → `-`.
- [ ] **Step 1: Tes merah:** `--list package-lock.json: nama dari kunci node_modules terdalam (@scope/pkg, nested), dev:true -> dev`; `--list package-lock.json lockfileVersion 1 -> kosong + 'tidak lengkap'`; `--list go.mod: blok require dan baris tunggal, awalan v dibuang, // indirect tetap prod`; `--list requirements.txt: nama==versi, extras dan --hash dibuang, >= dan -r dilewati dengan hitungan`; `--list requirements-dev.txt -> lingkup dev`; `--list Gemfile -> exit 64`.
- [ ] **Step 2:** `bash tests/run.sh` → tes baru GAGAL. **Step 3:** implementasikan mode `--list` (jq untuk npm; sed/awk untuk go.mod dan requirements). **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `cve-check: pengurai lockfile npm, Go, dan PyPI`.

### Task 2: Kueri OSV, pengelompokan alias, severity, kode keluar
**Files:** Modify `scripts/cve-check.sh`; Test `tests/run.sh` (`# 3j`): `curl` palsu `$tmp/cve/bin/curl` yang membaca `-d`, menjawab `$CVE_FIX/<ekosistem>_<nama dengan / dan @ → _>@<versi>.json` bila ada, selain itu `{}`; `CVE_DOWN=1` → exit 7; hitung panggilan di `$CVE_FIX/calls`.
**Interfaces — Consumes:** Task 1. **Produces:** `cve-check.sh <berkas>` (semua dependensi, `paparan=baru`) → TSV 9 kolom `paket  versi  id  alias  severity  lingkup  target  saran  paparan`, satu baris per kelompok kerentanan (rekaman beralias sama digabung; `id` = GHSA bila ada, alias = ID CVE dipisah koma); `target` dan `saran` diisi `-` sampai Task 3.
- [ ] **Step 1: Tes merah:** `bersih (vulns tidak ada) -> exit 0, tanpa keluaran`; `HIGH prod -> exit 1 dan baris 9 kolom persis`; `GO- tanpa severity memakai severity kembaran GHSA, satu baris`; `tanpa kembaran -> UNKNOWN dan exit 1`; `MODERATE prod -> exit 0 dengan baris`; `HIGH dev -> exit 0`; `OSV mati -> exit 2 dan pesan 'OSV tidak terjangkau'`; `next_page_token: dua halaman digabung`; `pasangan kembar dikueri sekali` (hitung `calls`); `@scope/pkg dan golang.org/x/net: badan JSON dan nama fixture benar`.
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasikan `osv_query` (gabung halaman, batas 20) dan pengelompokan dengan jq. **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `cve-check: kueri OSV, severity lewat kembaran alias, kode keluar`.

### Task 3: Target versi, saran, dan paparan baru (`--base`)
**Files:** Modify `scripts/cve-check.sh`; Test `tests/run.sh`.
**Interfaces — Consumes:** Task 2. **Produces:** `cve-check.sh <head> [--base <berkas-basis>]`. Target per paket = yang terbesar di antara tiap kelompok dari versi perbaikan terkecil ≥ versi terpasang (hanya `affected` dengan nama dan ekosistem yang sama); `saran` = `major` bila komponen pertama beda, `minor` bila kedua beda, selain itu `patch`; kelompok tanpa perbaikan: target `-`, saran `tanpa-perbaikan`. Perbandingan versi `sort -V` (awalan `v` dibuang). Dengan `--base`: pasangan identik di basis dikeluarkan; paket yang versinya berubah dikueri juga di versi basis, kelompok beralias sama → `paparan=lama`, selain itu `baru`; paket baru → semua `baru`.
- [ ] **Step 1: Tes merah:** `saran patch/minor/major` (4.17.15→4.17.21 = patch, 1.2.0→1.3.1 = minor, 1.2.0→2.0.0 = major); `dua kerentanan (4.17.19 dan 4.17.21) -> target 4.17.21 di kedua baris`; `4.17.9 vs 4.17.21 dan pra-rilis rc dibandingkan benar`; `tanpa versi perbaikan -> tanpa-perbaikan`; `--base: pasangan sama dikeluarkan`; `--base: naik ke versi yang kerentanannya himpunan-bagian -> paparan=lama, exit 0`; `--base: kerentanan baru di versi head -> paparan=baru, exit 1`; `--base: paket baru -> semua baru`.
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasikan. **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `cve-check: target versi, saran patch/minor/major, dan paparan baru`.

### Task 4: Gerbang PR
**Files:** Modify `scripts/pr-merge-check.sh` (setelah blok baseline, sebelum `echo "ok: gerbang lolos`); Test `tests/run.sh` (bagian 2; perluas `gh` palsu dengan cabang `"api "*"/contents/"*` sebelum `*labels*` yang membaca `$CF/<ref>/<path>` atau `HTTP 404`, dan `GH_REPO=o/r` pada tes; `curl` palsu dari Task 2 di PATH).
**Interfaces — Consumes:** Task 3; `waiver_ok` dan `fail` yang ada.
Perilaku: baca baris `Pemeriksaan CVE:` dari `bash workflow.sh`; daftar berkas dari header `diff --git` yang bernama `package-lock.json|go.mod|requirements*.txt`; per berkas ambil head dan basis lewat REST, jalankan `cve-check.sh <head> --base <basis>`; exit 1 atau 2 → `fail` kecuali `waiver_ok cve`; baris peringatan dicetak `PERINGATAN: cve ...`.
- [ ] **Step 1: Tes merah:** `PR menyentuh go.mod + kerentanan baru HIGH -> exit 1, pesan memuat 'cve'`; `sama + waiver (cve) -> exit 0`; `waiver (perf) tidak menutup cve`; `OSV mati + manifest -> exit 1`; `OSV mati + waiver cve -> exit 0`; `tanpa manifest di diff -> curl tidak dipanggil (0)`; `MODERATE saja -> exit 0 dengan PERINGATAN`; `Pemeriksaan CVE: tidak -> exit 0, PERINGATAN dimatikan, curl 0`; `berkas dihapus di head (404) -> dilewati, exit 0`.
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasikan. **Step 4:** suite → `SEMUA LULUS` (tes `pr-merge` lama tetap hijau).
- [ ] **Step 5:** Commit `pr-merge-check: gerbang CVE untuk paket baru atau berubah`.

### Task 5: Audit seluruh repo (`cve-audit.sh`) dan skill
**Files:** Create `scripts/cve-audit.sh`, `skills/cve-audit/SKILL.md`; Modify `agents/security.md` (satu baris merujuk `cve-check.sh`), `templates/WORKFLOW.md` (baris `Pemeriksaan CVE: {{ya (bawaan) | tidak}}`); Test `tests/run.sh`.
**Interfaces — Consumes:** Task 3; `ghx_repo`, `ghx_issues` dari `scripts/ghx.sh`. **Produces:** `cve-audit.sh [--dry-run] [<berkas>...]` (tanpa argumen: berkas dikenali dari `git ls-files`); per paket rentan satu issue lewat `gh api -X POST repos/<r>/issues -f title= -f body= -f labels[]=`: judul `CVE: <paket> <versi> -> <target> (<saran>)`; label `needs-security`, ditambah `needs-principal` bila saran `major` atau `tanpa-perbaikan`; dilewati bila ada issue terbuka berjudul berawalan `CVE: <paket> `; badan memuat tabel temuan, tanggal, dan sumber OSV. Tanpa temuan: cetak `tidak ada kerentanan diketahui di OSV per <tanggal> untuk <berkas>` dan tidak membuat apa pun.
- [ ] **Step 1: Tes merah:** `audit: dua temuan satu paket -> satu issue`; `audit: saran major -> label needs-principal`; `audit: saran patch -> hanya needs-security`; `audit: issue terbuka berawalan sama -> dilewati`; `audit: --dry-run tidak memanggil POST`; `audit: bersih -> kalimat per tanggal, tanpa POST`; `skill cve-audit menyebut cve-audit.sh dan dry-run`; `templates/WORKFLOW.md memuat 'Pemeriksaan CVE:'`; `agents/security.md menyebut cve-check.sh`.
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasikan skrip dan skill tipis (frontmatter `name: cve-audit`, `description` berawalan "Use ..."), serta dua baris dokumen. **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `Audit CVE seluruh repo: cve-audit.sh dan skill`.

### Task 6: Privasi, dokumen, dan rilis 0.7.0
**Files:** Modify `PRIVACY.md` (ganti "satu-satunya jaringan keluar adalah Telegram" menjadi dua: Telegram dan OSV; sebut apa yang dikirim), `README.md` (satu bagian: `cve-check.sh`, gerbang, opt-out, waiver `cve`, `cve-audit`, penjadwalan lewat `/schedule`), `.claude-plugin/plugin.json` (`version` → `0.7.0`, fitur baru); Test `tests/run.sh`.
- [ ] **Step 1: Tes merah:** `PRIVACY.md menyebut api.osv.dev dan tidak lagi berkata 'satu-satunya'`; `README menyebut cve-check.sh, waiver (cve) dan Pemeriksaan CVE`.
- [ ] **Step 2:** suite → GAGAL; tulis dokumen; suite → `SEMUA LULUS`. **Step 3:** `bash scripts/check-version.sh v0.7.0` → `ok`; `git status -sb` bersih.
- [ ] **Step 4:** Commit `Rilis 0.7.0: pemeriksaan CVE dependensi dengan saran update`; push; buka PR (REST bila GraphQL habis) dengan `Closes #22`; tunggu CI hijau. **Berhenti dan minta persetujuan owner sebelum merge** (versi naik → rilis otomatis).
- [ ] **Step 5 (setelah disetujui):** `pr-merge-check.sh <pr> main`; merge dengan `--match-head-commit`; verifikasi tag `v0.7.0` dan aset; `--after`; perbarui memori distribusi.
