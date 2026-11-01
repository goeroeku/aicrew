# Cadangan REST saat GraphQL kena batas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `board.sh` dan `epic-link.sh` tetap bekerja saat GraphQL GitHub terblokir (lewat REST), dan `pr-merge-check.sh` tetap fail-closed tetapi menjelaskan penyebab serta jam reset.

**Architecture:** Satu pustaka `scripts/ghx.sh` (di-`source`) membungkus tiap operasi GitHub yang dipakai dua skrip itu. Setiap pembungkus menjalankan panggilan `gh` yang sama seperti sekarang; bila gagal karena batas, ia masuk "mode cadangan" (`GHX_REST=1`, diekspor) dan mengulang sekali lewat REST. Tanpa loop.

**Tech Stack:** bash, `gh`, `jq`; tes deterministik `tests/run.sh` dengan `gh` palsu (tanpa jaringan).

**Spec:** `docs/superpowers/specs/2026-11-01-cadangan-rest-graphql-design.md` (issue #16). Cabang kerja: lanjutkan `goeroeku/desain-cadangan-rest`; PR akhir memuat `Closes #16`.

## Global Constraints
- `pr-merge-check.sh` tidak dipindah ke REST; tetap menolak saat tidak yakin. `board-init.sh` tidak disentuh.
- Panggilan jalur GraphQL harus **identik** dengan yang sekarang (urutan opsi `--state S [--label L] --limit N --json F`), supaya `gh` palsu di tes yang ada tetap cocok.
- Mode cadangan: tanpa loop ulang; satu baris pengumuman di stderr `mode cadangan REST: batas GraphQL ...`; `GHX_REST` dan `GHX_ANNOUNCED` diekspor agar anak proses (`bash "$0" ...` di `board.sh`) mewarisinya.
- Pemicu batas: teks `rate limit`, `RATE_LIMIT`, `graphql_rate_limit`, atau `unknown owner type` (tanpa beda huruf besar-kecil).
- Waktu reset dibaca dari header `X-Ratelimit-Reset` hasil `gh api graphql -i`, bukan `gh api rate_limit`; tanpa header, pesan tetap tampil tanpa jam. Format UTC `HH:MM:SS`, jalan di macOS (`date -r`) dan Linux CI (`date -d @`).
- Daftar issue REST mengikuti `--limit` (200 untuk `--check`); kartu project dibaca semua halaman. Buang entri bergaris `pull_request`.
- Nama kolom/opsi Project v2 bisa string (project user) atau `{"html","raw"}` (org): selalu normalkan ke `.raw` bila objek. Pencocokan nama Status tetap tanpa beda huruf besar-kecil.
- `--sync` pada mode cadangan: langkah yang butuh data khusus GraphQL (`closedByPullRequestsReferences`, `board.sh:55`) dilewati; keluar kode 0 dengan `PERINGATAN: N langkah dilewati (batas GraphQL), jalankan --sync lagi setelah reset`.
- Endpoint kartu butuh scope `project` seperti sekarang. Bila REST kartu menjawab 403/404, operasi kartu dilewati dengan `PERINGATAN` (dihitung sebagai langkah dilewati) dan operasi issue tetap jalan; `board <owner> <n> <issue> <status>` (satu kartu) keluar non-0 dengan pesan yang sama.
- Bahasa komentar, pesan, dan commit: Indonesia. Tanpa atribusi AI.

## Review Focus
- Badan issue kosong (`body: null` di REST) harus jadi `""`, bukan teks `null` (regex centang epic membacanya). → tes Task 2.
- `set_body` dengan badan berisi tanda kutip, `$`, dan baris baru harus tersimpan utuh. → tes Task 2.
- >100 issue dengan PR bercampur: hasil tanpa PR dan tepat `limit`. → tes Task 2.
- Kegagalan non-batas (mis. 404) tidak boleh ditelan menjadi fallback REST. → tes Task 1.
- 422 "Content already exists" = sukses, tetapi 422 lain harus muncul sebagai galat. → tes Task 4.
- Header reset hilang atau tak terbaca: pesan `pr-merge-check.sh` tetap tampil tanpa jam, gerbang tetap menolak. → tes Task 6.
- Anak proses `bash "$0"` mewarisi mode cadangan (tidak mencoba GraphQL lagi). → tes Task 5.

---

### Task 1: Inti `scripts/ghx.sh` (deteksi batas, mode cadangan, repo, pemilik)
**Files:** Create `scripts/ghx.sh`; Test `tests/run.sh` (bagian baru `# 3i` sebelum baris akhir `[ "$fails" = 0 ]`, dengan `gh` palsu `$tmp/rl/bin/gh` yang menulis `$*` ke `$FAKE/calls` dan, bila `GHX_SIM=1`, membuat `issue|project|repo|pr` gagal dengan stderr `GraphQL: API rate limit already exceeded for user ID 1`, sedangkan `api users/o` → `{"type":"User"}`, `api graphql -i` → header `X-Ratelimit-Remaining: 0` dan `X-Ratelimit-Reset: 1793490517`).
**Interfaces — Produces:**
- `ghx_is_limit <teks>` → exit 0 bila teks pemicu batas.
- `ghx_reset_time` → cetak `HH:MM:SS` UTC, atau kosong.
- `ghx_enter_rest` → set+ekspor `GHX_REST=1`; cetak pengumuman ke stderr sekali (`GHX_ANNOUNCED`).
- `ghx_gql <perintah gh...>` → exit 0 + stdout bila sukses; exit 75 bila gagal karena batas (sudah memanggil `ghx_enter_rest`); selain itu teruskan stderr dan exit code aslinya.
- `ghx_repo` → `owner/repo` dari `$GH_REPO`, lalu `git remote get-url origin` (bentuk `git@github.com:o/r.git` dan `https://github.com/o/r[.git]`), lalu `gh repo view --json nameWithOwner -q .nameWithOwner`.
- `ghx_owner_base <owner>` → `orgs/<owner>` atau `users/<owner>` dari `gh api users/<owner> -q .type`.
- `ghx_explain_limit` → bila probe `gh api graphql -i` menunjukkan `Remaining: 0`, cetak `Penyebab: batas GraphQL GitHub habis; reset HH:MM:SS UTC. Tunggu lalu ulangi; gerbang tidak dilewati.` (tanpa `reset ...` bila jam tak terbaca); selain itu tidak mencetak apa pun.

- [ ] **Step 1: Tes merah** (nama → harapan): `ghx_is_limit: 4 teks pemicu` → 0 dan `404 Not Found` → 1; `ghx_repo: GH_REPO menang`; `ghx_repo: remote ssh dan https` → `a/b` keduanya; `ghx_repo: tanpa remote → gh repo view`; `ghx_gql: sukses meneruskan stdout`; `ghx_gql: batas → exit 75, GHX_REST=1, satu baris pengumuman`; `ghx_gql: 404 → exit asli, GHX_REST tidak diset` (Review Focus); `ghx_reset_time: epoch 1793490517 → 23:48:37`; `ghx_owner_base: User → users/o`, `Organization → orgs/o`.
- [ ] **Step 2:** `bash tests/run.sh` → tes baru GAGAL.
- [ ] **Step 3:** Implementasi semua fungsi di atas di `scripts/ghx.sh`; komentar kepala berbahasa Indonesia yang menyebut cara pakai dan bahwa REST dicoba satu kali.
- [ ] **Step 4:** `bash tests/run.sh` → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `Pustaka ghx: deteksi batas GraphQL, mode cadangan, repo dan pemilik tanpa GraphQL`.

### Task 2: Operasi issue (`ghx_issues`, body, edit, tutup)
**Files:** Modify `scripts/ghx.sh`; Test `tests/run.sh` (`# 3i`).
**Interfaces — Consumes:** Task 1. **Produces:**
- `ghx_issues <state:open|closed|all> <label|-> <limit> <json-fields>` → larik JSON. Jalur GraphQL: `gh issue list --state S [--label L] --limit N --json F`. Jalur REST: `repos/<ghx_repo>/issues?state=S&per_page=100[&labels=L]`, tanpa entri `pull_request`, tepat `limit`, bentuk `{number,title,body(""-bukan-null),labels[{name}],state(HURUF BESAR)}`.
- `ghx_issue_body <n>` → badan issue (`""` bila kosong).
- `ghx_issue_set_body <n> <teks>` → REST: `PATCH ... -f body=<teks>` (jangan interpolasi ke JSON).
- `ghx_issue_close <n> <komentar>` → GraphQL `gh issue close "$n" --comment ...`; REST: POST komentar lalu `PATCH -f state=closed -f state_reason=completed`.

- [ ] **Step 1: Tes merah:** `ghx_issues: tanpa batas = panggilan identik 'issue list --state open --label epic --limit 100 --json number,body'`; `ghx_issues: batas → REST, state OPEN huruf besar, tanpa PR, tepat limit` (fake REST: 150 entri campuran, 30 PR, limit 100); `ghx_issues: setelah batas, panggilan berikutnya tidak memanggil 'issue list'`; `ghx_issue_body: body null → ""`; `ghx_issue_set_body: badan dengan "kutip", $HOME, dan baris baru terkirim utuh`; `ghx_issue_close: REST = POST komentar lalu PATCH closed`; `ghx_issues: REST juga gagal → exit non-0 dan pesan, tanpa loop` (hitung panggilan `api` = 1).
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasi (jalur REST dengan `gh api --paginate` per halaman, berhenti saat `limit` terkumpul). **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `Pustaka ghx: operasi issue dengan cadangan REST`.

### Task 3: `epic-link.sh` memakai pustaka
**Files:** Modify `scripts/epic-link.sh:8,10,17,29,38,40,41,43` (ganti `gh repo view`→`ghx_repo`, `gh issue list`→`ghx_issues`, `gh issue view/edit`→`ghx_issue_body/ghx_issue_set_body`; tambahkan `source "$(dirname "$0")/ghx.sh"` setelah `set -euo pipefail`); Test `tests/run.sh`.
**Interfaces — Consumes:** Task 2.
- [ ] **Step 1: Tes merah:** `epic-link --check: GraphQL diblokir → daftar yatim lewat REST, exit 3` (fake REST: epic #1, issue #2 tanpa induk); `epic-link <epic> <anak>: GraphQL diblokir → daftar centang terpasang lewat REST` (assert PATCH body memuat `- [ ] #<anak>` dan keluaran `epic-link: #<anak> -> epic #<epic>`).
- [ ] **Step 2:** suite → GAGAL (hanya tes baru). **Step 3:** ubah skrip; pesan 200-issue (`:17`) tetap sama. **Step 4:** suite → `SEMUA LULUS` (tes epic lama tetap hijau tanpa mengubah `gh` palsunya).
- [ ] **Step 5:** Commit `epic-link: cadangan REST saat GraphQL kena batas`.

### Task 4: Operasi project (kartu)
**Files:** Modify `scripts/ghx.sh`; Test `tests/run.sh`.
**Interfaces — Consumes:** Task 1. **Produces:**
- `ghx_items <owner> <num>` → `{"items":[{"id","status","content":{"number","type"}}]}` (bentuk `gh project item-list --format json`). REST: Status dibaca lewat `GET <base>/projectsV2/<num>/items?per_page=100&fields=<id kolom Status>` (`--paginate`); `status` = `.fields[]|select(.id==<fid>)|.value.name.raw`; `type` dari `content_type`.
- `ghx_status_field <owner> <num>` → JSON `{"id","options":[{"id","name"}]}` untuk kolom Status (nama dinormalkan ke string; `id` kolom bertipe asli mode berjalan: string di GraphQL, angka di REST, dan `ghx_card_set` menerima keduanya); kosong bila tak ada.
- `ghx_card_add <owner> <num> <issue>` → cetak id kartu. REST: `POST <base>/projectsV2/<num>/items -f type=Issue -F id=<id NUMERIK issue>`; 422 berisi `Content already exists` → cari id kartu dari `ghx_items` (sukses); 422 lain → galat.
- `ghx_card_set <owner> <num> <item> <fid> <oid>` → GraphQL: `gh project view` (ambil id project) lalu `gh project item-edit --id ... --project-id ... --field-id ... --single-select-option-id ...`; REST: `PATCH <base>/projectsV2/<num>/items/<item> --input` dengan `{"fields":[{"id":<fid angka>,"value":"<oid>"}]}`.

- [ ] **Step 1: Tes merah:** `ghx_items: REST user (nama kolom string) → status "In review"`; `ghx_items: REST org (nama {raw}) → status sama`; `ghx_status_field: opsi dinormalkan`; `ghx_card_add: 422 already exists → sukses, id dari daftar`; `ghx_card_add: 422 lain → exit non-0` (Review Focus); `ghx_card_add: POST memakai id numerik, bukan nomor`; `ghx_card_set: PATCH body persis {"fields":[{"id":434173140,"value":"df73e18b"}]}`. Bentuk respons fake diambil dari respons nyata yang diverifikasi 2026-11-01 (`fields` item hanya memuat Title bila `fields=` tak diberikan).
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasi. **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `Pustaka ghx: operasi kartu project dengan cadangan REST`.

### Task 5: `board.sh` memakai pustaka dan melewati langkah khusus GraphQL
**Files:** Modify `scripts/board.sh:13,15,16,44,48,49,54,55,61-73`; Test `tests/run.sh`.
**Interfaces — Consumes:** Task 2 dan 4.
Penggantian: `gh project item-list`→`ghx_items`; `gh issue list`→`ghx_issues` (state/label/limit/json sama); `gh repo view`→`ghx_repo`; `gh issue close`→`ghx_issue_close`; blok `:62-73`→`ghx_status_field` + `ghx_card_add` (bila kartu belum ada) + `ghx_card_set`, dengan pesan galat `:64,:67` dan keluaran `board: #$issue -> $status` tidak berubah. Langkah `:55` memanggil `ghx_gql gh issue list --state closed ... closedByPullRequestsReferences` langsung; exit 75 atau `GHX_REST=1` → langkah dilewati, `skipped=1`. Di akhir `--sync`: `[ "$skipped" = 0 ] || echo "PERINGATAN: $skipped langkah dilewati (batas GraphQL), jalankan --sync lagi setelah reset" >&2`; exit 0.

- [ ] **Step 1: Tes merah** (fake mode `GHX_SIM=1`, WORKFLOW `Kartu Done: agen-setelah-merge`): `board --sync: batas → exit 0, status epic dipindah lewat PATCH REST`; `board --sync: batas → stderr memuat "PERINGATAN: 1 langkah dilewati (batas GraphQL)"`; `board --sync: tanpa batas → tidak ada PERINGATAN`; `board <owner> <n> <issue> Done: batas → POST item lalu PATCH`; `board --sync: anak proses tidak memanggil 'issue list' lagi setelah batas` (hitung panggilan, Review Focus); `board --sync: REST kartu 404 → langkah kartu dilewati dengan PERINGATAN, tutup issue di-integrasi tetap jalan, exit 0`; `board <owner> <n> <issue> Done: REST kartu 403 → exit non-0 dengan pesan scope project`.
- [ ] **Step 2:** suite → GAGAL (hanya tes baru). **Step 3:** ubah skrip. **Step 4:** suite → `SEMUA LULUS` (tes 3g, 4c lama tetap hijau).
- [ ] **Step 5:** Commit `board: cadangan REST dan peringatan langkah yang dilewati`.

### Task 6: `pr-merge-check.sh` menjelaskan penyebab (tetap fail-closed)
**Files:** Modify `scripts/pr-merge-check.sh` (`source ghx.sh`; fungsi `fail()` di `:17` memanggil `ghx_explain_limit` sebelum `exit 1`); Test `tests/run.sh`.
**Interfaces — Consumes:** Task 1.
- [ ] **Step 1: Tes merah:** `pr-merge-check: GraphQL habis → exit 1, keluaran memuat "GAGAL" dan "batas GraphQL" dan "23:48:37"`; `pr-merge-check: header reset hilang → exit 1, pesan batas tanpa jam`; `pr-merge-check: kegagalan biasa (basis salah) → tanpa baris "Penyebab"` (probe tidak mencetak bila `Remaining` bukan 0).
- [ ] **Step 2:** suite → GAGAL. **Step 3:** ubah `fail()` (hanya jalur gagal yang memanggil probe). **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `pr-merge-check: jelaskan batas GraphQL dan jam reset saat menolak`.

### Task 7: Dokumen dan rilis 0.6.4
**Files:** Modify `README.md` (satu paragraf dekat `README.md:127` tentang `board.sh`: mode cadangan REST dan perilaku `PERINGATAN`), `.claude-plugin/plugin.json` (`version` → `0.6.4`).
- [ ] **Step 1:** Tes: `grep -q 'mode cadangan REST' README.md` ditambahkan di `tests/run.sh`; suite → GAGAL, tulis paragraf, suite → `SEMUA LULUS`.
- [ ] **Step 2:** `bash scripts/check-version.sh v0.6.4` → `ok`; verifikasi akhir sendiri: `bash tests/run.sh` → `SEMUA LULUS`, `git status -sb` bersih.
- [ ] **Step 3:** Commit `Rilis 0.6.4: cadangan REST saat GraphQL kena batas`; push; buka PR (REST bila GraphQL habis) dengan `Closes #16`; tunggu CI hijau. **Berhenti di sini dan minta persetujuan owner sebelum merge** (rilis otomatis saat versi naik).
- [ ] **Step 4 (setelah disetujui):** jalankan `pr-merge-check.sh <pr> main`, merge dengan `--match-head-commit`, verifikasi tag `v0.6.4` dan aset rilis, jalankan `--after`; perbarui memori distribusi (rilis terakhir).
