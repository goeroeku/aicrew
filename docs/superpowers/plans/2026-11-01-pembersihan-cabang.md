# Pembersihan cabang dan worktree tak terpakai Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cabang dan worktree yang terbukti ter-merge dilaporkan oleh `scripts/cleanup.sh` dan, untuk milik orkestrator (`issue-<n>`, `<repo>-wt-<n>`), dihapus otomatis setelah merge terverifikasi; preflight memberi peringatan setelan GitHub.

**Architecture:** Satu skrip `cleanup.sh` (git + REST, tanpa GraphQL) yang menghitung kandidat dari bukti (leluhur atau PR merged dengan `head.sha` sama), lalu melaporkan (bawaan) atau menghapus (`--apply`). `orchestrate` langkah 8 memanggil `--setelah-merge`; preflight hanya memakai bukti offline.

**Tech Stack:** bash, `git`, `gh api`, `jq`; tes deterministik `tests/run.sh` dengan repo git sementara + remote bare lokal dan `gh` palsu (REST).

**Spec:** `docs/superpowers/specs/2026-11-01-pembersihan-cabang-design.md` (issue #21). Cabang kerja: lanjutkan `goeroeku/desain-pembersihan`; PR akhir memuat `Closes #21`.

## Global Constraints
- Bawaan hanya **melaporkan**; `--apply` yang menghapus. Tanpa `git worktree remove --force`. Penghapusan cabang: `git branch -d` bila ujungnya leluhur `origin/<basis>`; bila terbukti lewat PR merged, `git update-ref -d refs/heads/<nama> <sha>` (hanya berhasil bila ujung masih `<sha>`). Remote: `git push origin --delete`; "remote ref does not exist" diabaikan.
- Tidak pernah kandidat: cabang bawaan (`git symbolic-ref refs/remotes/origin/HEAD`, cadangan REST `.default_branch`), cabang integrasi (`Cabang integrasi:` lewat `workflow.sh`), cabang ter-checkout di worktree yang TIDAK ikut dihapus, cabang yang `head` atau `base` PR terbuka, apa pun di `~/orca/workspaces/`, worktree kotor atau terkunci atau tanpa cabang.
- Bukti ter-merge: (a) ujung leluhur `origin/<bawaan>` atau `origin/<integrasi>`; (b) `GET repos/<r>/pulls?head=<owner>:<cabang>&state=all` memuat PR `merged_at` terisi dan `head.sha` = ujung (cabang di `<owner>` repo yang sama). Ujung menyimpang dari `head.sha` → `lewati:belum-ter-merge`.
- `git fetch --prune origin` dulu; `--no-fetch` melewatinya. Daftar PR terbuka dibaca sekali (`pulls?state=open&per_page=100`, paginasi); tak terbaca → kandidat remote `lewati:pr-tak-terbaca`.
- Keluaran TSV `jenis  nama  sha  bukti  aksi`; jenis `cabang-lokal|cabang-remote|worktree`, bukti `leluhur|pr-merged|-`, aksi `hapus` (laporan) | `dihapus` (apply) | `lewati:<alasan>`. Setiap aksi hapus mencetak SHA ujung. Kode keluar: 0, 1 bila ada hapus yang gagal, 64 salah pakai; `Backend:` bukan github → keluar 0 dengan pesan "tidak didukung (bukan GitHub)".
- Opsi `WORKFLOW.md`: `Bersihkan setelah merge: ya|laporkan|tidak`; baris hilang = `ya`; berlaku hanya untuk milik orkestrator (`^issue-[0-9]+$`, `<repo>-wt-[0-9]+`).
- Bahasa komentar, pesan, dan commit: Indonesia. Tanpa atribusi AI. Jalan di macOS (bash 3.2) dan Linux CI.

## Review Focus
- Nama cabang berisi `/` (`fitur/x`) pada ref, jalur worktree, dan kueri `head=<owner>:fitur/x`. → tes Task 1.
- Worktree terkunci (`git worktree lock`) dan HEAD terlepas (detached): dilewati. → tes Task 1.
- Cabang squash-merge dengan commit tambahan setelah PR: tidak dihapus. → tes Task 1 dan 2.
- Cabang remote sudah dihapus GitHub saat `--apply` (idempoten, bukan galat). → tes Task 2.
- Cabang bawaan bukan `main` (`master`/`develop`) dikenali dari `origin/HEAD`. → tes Task 1.
- Tumpukan PR: cabang yang menjadi `base` PR terbuka tidak dihapus. → tes Task 1.

---

### Task 1: `cleanup.sh` laporan (kandidat dan perlindungan)
**Files:** Create `scripts/cleanup.sh`; Test `tests/run.sh` (bagian baru `# 3k`: fungsi `MK` membuat repo sementara `$tmp/cl/w` dengan remote bare `$tmp/cl/remote.git`, cabang bawaan `main`, `docs/WORKFLOW.md` berisi `Cabang integrasi: integ`; `gh` palsu `$tmp/cl/bin/gh` untuk `api repos/o/r` (`default_branch`, `delete_branch_on_merge`), `api repos/o/r/pulls?state=open...` (berkas `$CL/open.json`), `api repos/o/r/pulls?head=o:<cabang>&state=all...` (berkas `$CL/pr-<cabang dengan / → _>.json` atau `[]`); `GH_REPO=o/r`).
**Interfaces — Produces:** `cleanup.sh [--no-fetch] [--only orkestrator] [--issue <n>]` (tanpa `--apply`) → TSV sesuai Global Constraints.
- [ ] **Step 1: Tes merah** pada fixture satu repo: `issue-1` merge-commit (leluhur) → `hapus`/`leluhur` untuk lokal dan remote; `issue-2` belum ter-merge → `lewati:belum-ter-merge`; `issue-3` squash (tidak leluhur) + PR merged `head.sha`=ujung → `hapus`/`pr-merged`; `issue-4` seperti 3 tetapi ujung lokal punya commit tambahan → `lewati:belum-ter-merge`; `fitur/x` leluhur dengan PR terbuka (head) → `lewati:pr-terbuka` dan kueri `head=o:fitur/x` dipakai; `stack-base` leluhur dan `base` PR terbuka → `lewati:base-pr-terbuka`; `integ` dan `main` → dilindungi (tidak tampil sebagai kandidat); bawaan `develop` (set `origin/HEAD`) dilindungi; worktree `issue-5` bersih+ter-merge → `worktree`/`hapus`; `issue-6` kotor → `lewati:kotor` dan cabangnya `lewati:checkout`; worktree terkunci → `lewati:terkunci`; worktree HEAD terlepas → `lewati:tanpa-cabang`; worktree di bawah `.../orca/workspaces/...` → `lewati:orca`; `--only orkestrator` hanya memuat nama `issue-<n>`/`<repo>-wt-<n>`; daftar PR terbuka tak terbaca → remote `lewati:pr-tak-terbaca`; `Backend: gitlab` di WORKFLOW → exit 0 + "tidak didukung".
- [ ] **Step 2:** `bash tests/run.sh` → tes baru GAGAL. **Step 3:** implementasikan. **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `cleanup: laporan kandidat cabang dan worktree ter-merge`.

### Task 2: `--apply`
**Files:** Modify `scripts/cleanup.sh`; Test `tests/run.sh`.
**Interfaces — Consumes:** Task 1. **Produces:** `--apply` menjalankan urutan: `git worktree remove <path>` (tanpa force), lalu cabang lokal (`-d` bila `leluhur`; `update-ref -d <ref> <sha>` bila `pr-merged`), lalu `git push origin --delete <nama>`; cetak `dihapus` dan SHA tiap aksi; satu kegagalan dicetak `lewati:gagal:<pesan>` dan kode keluar akhir 1, proses lanjut.
- [ ] **Step 1: Tes merah:** `apply: issue-1 hilang lokal dan remote, SHA dicetak dan dapat dipulihkan (git branch pulih <sha>)`; `apply: issue-3 (squash) terhapus lewat update-ref padahal git branch -d menolak`; `apply: issue-4, issue-2, fitur/x, stack-base, integ, main tetap ada`; `apply: worktree issue-5 dan cabangnya terhapus dalam satu putaran`; `apply: worktree kotor tetap ada`; `apply: cabang remote yang sudah dihapus GitHub -> bukan galat, exit 0`; `apply: kedua kali dijalankan -> tidak ada kandidat, exit 0`; `--issue 1: hanya issue-1`; `--only orkestrator: cabang ter-merge bernama bebas tidak disentuh`.
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasikan. **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `cleanup: --apply dengan bukti dan SHA yang dicetak`.

### Task 3: `--setelah-merge`, opsi WORKFLOW, orchestrate, izin
**Files:** Modify `scripts/cleanup.sh`, `skills/orchestrate/SKILL.md` (langkah 8, `:76`), `templates/WORKFLOW.md` (baris `Bersihkan setelah merge:` dekat `Tutup issue setelah merge integrasi`), `templates/autopilot-permissions.json` (tambah `Bash(git update-ref:*)`); Test `tests/run.sh`.
**Interfaces — Consumes:** Task 2. **Produces:** `cleanup.sh --setelah-merge --issue <n>` = `--only orkestrator --issue <n>` ditambah `--apply` bila opsi `ya` atau hilang; `laporkan` hanya mencetak; `tidak` keluar 0 tanpa keluaran; kode keluar bukan-0 tidak pernah menghentikan alur pemanggil (skill menulisnya demikian).
- [ ] **Step 1: Tes merah:** `setelah-merge: opsi ya -> terhapus`; `opsi hilang -> terhapus (bawaan ya)`; `opsi laporkan -> tidak ada yang terhapus, ada laporan`; `opsi tidak -> tak ada keluaran dan tak terhapus`; `templat WORKFLOW memuat 'Bersihkan setelah merge:'`; `orchestrate langkah 8 menyebut cleanup.sh --setelah-merge dan 'tidak pernah menghentikan'`; `autopilot-permissions.json memuat 'git update-ref'`; tes `install-permissions` yang ada tetap hijau (jumlah aturan dihitung dari templat).
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasikan dan ubah dokumen. **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `Pembersihan setelah merge: opsi WORKFLOW, langkah 8 orchestrate, izin update-ref`.

### Task 4: Preflight
**Files:** Modify `scripts/preflight.sh` (cabang `github)`); Test `tests/run.sh` (`gh` palsu: `api repos/o/r` → `delete_branch_on_merge` true/false).
**Interfaces — Consumes:** Task 1 (fungsi hitung kandidat offline: ancestry saja, tanpa fetch dan tanpa REST). **Produces:** baris `AWAS` bila `delete_branch_on_merge` false dengan perintah `gh api -X PATCH repos/<r> -F delete_branch_on_merge=true`; baris `ok` bila true; baris `info` "setidaknya N cabang ter-merge belum dihapus; jalankan scripts/cleanup.sh" bila N>0 dan ada remote.
- [ ] **Step 1: Tes merah:** `preflight: setelan false -> AWAS beserta perintah PATCH`; `preflight: setelan true -> ok`; `preflight: ada 2 cabang ter-merge -> info setidaknya 2`; `preflight: tanpa remote -> tanpa baris info`; `preflight: tidak memanggil REST selain repos/<r>` (hitung panggilan `pulls` = 0).
- [ ] **Step 2:** suite → GAGAL. **Step 3:** implementasikan. **Step 4:** suite → `SEMUA LULUS`.
- [ ] **Step 5:** Commit `preflight: peringatan setelan hapus-cabang-saat-merge dan jumlah cabang ter-merge`.

### Task 5: Dokumen dan rilis 0.8.0
**Files:** Modify `README.md` (satu bagian: `cleanup.sh`, opsi `Bersihkan setelah merge`, perubahan perilaku bawaan `ya`, GitLab belum didukung), `.claude-plugin/plugin.json` (`version` → `0.8.0`, perilaku bawaan baru); Test `tests/run.sh`.
- [ ] **Step 1: Tes merah:** `README menyebut cleanup.sh, 'Bersihkan setelah merge' dan 'bawaan ya'`. **Step 2:** tulis dokumen; suite → `SEMUA LULUS`; `bash scripts/check-version.sh v0.8.0` → `ok`; `git status -sb` bersih.
- [ ] **Step 3:** Commit `Rilis 0.8.0: pembersihan cabang dan worktree ter-merge`; push; buka PR (REST) dengan `Closes #21` dan catatan perubahan bawaan; tunggu CI hijau. **Berhenti dan minta persetujuan owner sebelum merge** (versi naik → rilis otomatis).
- [ ] **Step 4 (setelah disetujui):** `pr-merge-check.sh <pr> main`; merge dengan `--match-head-commit`; verifikasi tag `v0.8.0` dan aset; `--after`; perbarui memori distribusi; hapus cabang kerja.
