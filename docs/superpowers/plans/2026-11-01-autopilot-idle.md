# Autopilot idle watchdog dan menunggu owner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, dipilih owner) atau superpowers:subagent-driven-development. Steps memakai checkbox (`- [ ]`).

**Goal:** `autopilot.sh` mengakhiri putaran `claude -p` yang idle (bawaan aktif, 30 menit) tanpa menyentuh pekerjaan sah, memberi status kesehatan, dan menghitung `blocked-by` sebagai "menunggu owner" (#48, #17).

**Architecture:** `claude` dijalankan di latar depan; subshell pemantau (berjalan selama putaran) menilai dua sinyal (mtime transkrip, proses turunan non-pembantu), menulis penanda lalu `kill -INT` pada satu anak langsung `$$`, dan mengeskalasi ke SIGTERM. `trap` INT/EXIT/TERM menjaga Ctrl-C pemilik tetap menghentikan autopilot dan pemantau tidak yatim. Status ditulis atomik ke `.aicrew/autopilot.json`.

**Tech Stack:** bash 3.2 (macOS) + Linux, `ps`/`pgrep`/`find -newer`, `jq`, `gh`; tes `bash tests/run.sh` dengan `claude`/`gh` palsu (bagian `2b`).

**Spec:** `docs/superpowers/specs/2026-11-01-autopilot-idle-design.md` (bagian "Keputusan tambahan" mengikat).

## Global Constraints
- Opsi dan env (nama Inggris): `--idle-limit DETIK`/`AICREW_IDLE_LIMIT` (bawaan 1800, 0 mati), `--round-timeout DETIK`/`AICREW_ROUND_TIMEOUT` (bawaan 0 mati), `AICREW_IDLE_POLL` (bawaan 30), `AICREW_IDLE_IGNORE` (bawaan `codebase-memory|gopls|mcp|typescript-language-server|tsserver`, dicocokkan pada `comm`), `AICREW_TRANSCRIPT_DIR` (menimpa pemetaan cwd).
- Fail-safe: pemantau tidak menemukan sasaran/direktori transkrip = tidak ada tindakan. Sasaran = satu-satunya anak langsung `$$` selain subshell pemantau; pid diverifikasi masih anak `$$` sebelum tiap sinyal. Tidak pernah SIGKILL. SIGINT, lalu SIGTERM setelah 60 detik lagi bila sesi masih hidup (30 detik setelah SIGINT dicatat, 60 detik berikutnya SIGTERM).
- Putaran yang berakhir karena interupsi pemantau (penanda `.aicrew/idle-interrupt` ada): `rc` dinormalkan, jalur limit/gagal dilewati, sidik jari dibandingkan seperti biasa (→ `--stuck` kode 2). Ctrl-C pemilik (tanpa penanda): matikan pemantau dan `claude`, keluar 130.
- Tanpa `trap ''` untuk INT. Pemantau tidak aktif saat `sleep` limit/error dan saat `waiting_on_owner`. Kode keluar lama tak berubah. Rilis kandidat 0.12.0.
- Artefak berbahasa Indonesia, opsi/env/nama berkas baru berbahasa Inggris; dilarang atribusi AI; tanpa `--force`.

## Review Focus
- Ctrl-C pemilik (SIGINT ke autopilot tanpa penanda) menghentikan autopilot dan tidak meninggalkan `claude` atau pemantau yatim.
- Sesi aktif (transkrip berubah) atau punya anak non-pembantu tidak pernah diinterupsi; sesi baru tidak langsung idle oleh mtime basi.
- Putaran yang diinterupsi tidak masuk jalur gagal/limit dan tidak membakar `errs`.
- Pid dipakai ulang / sasaran salah (wrapper `AICREW_CLAUDE`) tidak menerima sinyal.
- `blocked-by`: `#1` vs `#12`, "none", blocker lintas repo, rantai yang berujung needs-principal vs pekerjaan Ready.

---

### Task 1: opsi, status `autopilot.json`, spike perilaku proses

**Files:** Modify `scripts/autopilot.sh` (parsing argumen baris 16-18; fungsi `log`/fase), `tests/run.sh` (`3p-1`).

**Interfaces:**
- Produces: variabel `idle_limit`, `round_timeout`, `poll`; fungsi `set_phase <fase> [extra-jq]` yang menulis `.aicrew/autopilot.json` atomik (tmp lalu `mv`) berisi `{fase, putaran, idle_sejak_detik, detak}`; fase `putaran|menunggu-owner|tidur-limit|idle-diinterupsi|selesai`. Baris pertama `autopilot.status` tidak berubah.

- [ ] **Step 0: spike (catat hasilnya di ledger, tanpa commit):** (a) bash 3.2 non-interaktif: anak latar depan dibunuh `kill -INT <pid-anak>` — apakah induk ikut keluar tanpa `trap`, dan apakah `trap 'cek' INT` yang memeriksa berkas penanda menjaganya hidup; (b) `rc` yang terlihat (130/0) untuk sesi palsu `exec sleep`; (c) `pgrep -P`, `ps -o comm=`, `find DIR -type f -newer MARKER` di macOS; (d) `sh -c 'echo $PPID'` dari subshell mengembalikan pid subshell itu.
- [ ] **Step 1: tes merah** — `--idle-limit 5 --round-timeout 9` diterima (bukan exit 64); `AICREW_IDLE_LIMIT`/`AICREW_ROUND_TIMEOUT` dibaca; setelah satu putaran `.aicrew/autopilot.json` valid dengan `fase` dan `detak` (angka); akhir sukses `fase` = `selesai`; `autopilot.status` baris pertama tetap `putaran N: ...`.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL.
- [ ] **Step 3: implement** parsing, `set_phase`, panggilan di titik fase (awal putaran, tidur limit, menunggu owner, selesai).
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Autopilot: opsi idle/round-timeout dan status autopilot.json (#48)`.

### Task 2: watchdog idle (SIGINT, penanda, trap, normalisasi rc)

**Files:** Modify `scripts/autopilot.sh` (sekitar panggilan `"$claude" ... -p`, baris ~65-93), `tests/run.sh` (`3p-2`; tambah mode `idle`, `active`, `child`, `ignore` ke `claude` palsu bagian `2b`).

**Interfaces:**
- Consumes: Task 1 (`idle_limit`, `poll`, `set_phase`).
- Produces: fungsi `watch_round <waktu-mulai>` (subshell latar) dan `trap` INT/EXIT/TERM; penanda `.aicrew/idle-interrupt` (dihapus tiap awal putaran); log `putaran N: idle X menit; diinterupsi (SIGINT)`.

- [ ] **Step 1: tes merah** (sesi palsu; `AICREW_IDLE_LIMIT=2`, `AICREW_IDLE_POLL=1`, `AICREW_TRANSCRIPT_DIR=<tmp>`): (a) `idle` (`exec sleep 600`) -> diinterupsi, log memuat `idle`, putaran berikutnya berjalan (jumlah panggilan `claude` naik), exit akhir 0 saat issue selesai; (b) `active` (menyentuh berkas transkrip tiap detik selama 6 detik lalu `close`) -> tidak ada baris `idle`; (c) `child` (`sleep 600 &` lalu `wait`, anak bukan pembantu) -> tidak diinterupsi sebelum selesai; anak bernama cocok `AICREW_IDLE_IGNORE` -> dianggap idle; (d) `--idle-limit 0` -> tidak pernah diinterupsi; (e) direktori transkrip tak ada -> tidak ada tindakan, satu baris log; (f) tiga putaran idle tanpa perubahan -> exit 2 (`--stuck`), bukan exit 1; `errs` tidak naik; (g) putaran yang diinterupsi tidak memicu jalur limit walau keluarannya memuat kata limit; (h) Ctrl-C: `kill -INT` ke `autopilot.sh` tanpa penanda -> autopilot keluar 130 dan sesi palsu mati; (i) autopilot selesai/mati -> tidak ada proses pemantau yatim.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: tes baru GAGAL.
- [ ] **Step 3: implement** per spec: `claude` di latar depan; `watch_round` sebagai subshell latar yang menghitung `idle_sejak = now - max(mtime terbaru transkrip, awal putaran)` (berkas penanda waktu + `find -newer`), memeriksa turunan rekursif selain `AICREW_IDLE_IGNORE`, menulis penanda lalu `kill -INT`; `trap` INT memeriksa penanda; EXIT/TERM mematikan pemantau; setelah `claude` kembali, normalisasi rc bila penanda ada.
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Autopilot: watchdog idle menginterupsi putaran claude yang menganggur (#48)`.

### Task 3: eskalasi SIGTERM, `--round-timeout`, jalur `caffeinate`

**Files:** Modify `scripts/autopilot.sh`, `tests/run.sh` (`3p-3`).

**Interfaces:** Consumes Task 2. `watch_round` menambah: setelah SIGINT, tunggu 30 detik (log bila sesi masih hidup) lalu 60 detik, kirim SIGTERM (dicatat); `--round-timeout` > 0 menginterupsi sesi yang aktif setelah N detik dengan jalur sinyal yang sama.

- [ ] **Step 1: tes merah** — `ignore` (`trap '' INT`, tidur) -> SIGINT tak menembus, SIGTERM datang (waktu pendek lewat `AICREW_IDLE_GRACE` dan `AICREW_TERM_GRACE`, bawaan 30/60) dan putaran berikut dimulai; tidak pernah SIGKILL; `--round-timeout 3` menginterupsi sesi `active`; jalur tanpa `AICREW_CAFF` (via `caffeinate` bila ada) menjalankan satu skenario idle dengan hasil sama.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: GAGAL.
- [ ] **Step 3: implement.**
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Autopilot: eskalasi SIGTERM dan --round-timeout (#48)`.

### Task 4: `blocked-by` di `waiting_on_owner` (#17)

**Files:** Modify `scripts/autopilot.sh` (`gh issue list --json` tambah `body`; `waiting_on_owner`), `tests/run.sh` (`3p-4`).

**Interfaces:** `waiting_on_owner` menghitung issue menunggu bila `needs-principal`, punya PR terbuka, atau semua blocker belum-terpenuhi (bagian `## Blocked by` di badan, `#n` dengan batas kata) sendiri menunggu (iterasi sampai tetap); blocker yang ditutup atau berlabel integrasi terpenuhi; "none" dan blocker lintas repo diabaikan; blocker berupa pekerjaan Ready = bukan menunggu.

- [ ] **Step 1: tes merah** — rantai A (blocked-by #B) dengan B `needs-principal` -> menunggu (exit 3 pada putaran kedua, `claude` tidak dipanggil lagi); B Ready -> putaran berjalan; `#1` vs `#12` tidak keliru; "none"; blocker lintas repo; blocker `di-integrasi` -> terpenuhi; kasus buntu sungguhan tetap exit 2.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: GAGAL.
- [ ] **Step 3: implement.**
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Autopilot: blocked-by dihitung sebagai menunggu owner (#17)`.

### Task 5: `orchestrate`, README, komentar kepala, rilis 0.12.0

**Files:** Modify `skills/orchestrate/SKILL.md` (subbagian `## Mode tanpa pengawasan (autopilot)` setelah Resume: akhiri giliran setelah laporan bila hanya menunggu owner/agen; jalankan ulang `gh issue list` sebelum menyimpulkan "tidak ada pekerjaan"; wrapper `AICREW_CLAUDE` wajib `exec`), `README.md` (satu paragraf), komentar kepala `scripts/autopilot.sh`, `.claude-plugin/plugin.json` -> `0.12.0`, `tests/run.sh` (`3p-5`, pin versi).

- [ ] **Step 1: tes merah** — pin `plugin.json versi 0.12.0`; `grep` SKILL.md memuat `Mode tanpa pengawasan`, `exec`; README memuat `--idle-limit`; komentar kepala autopilot memuat `--idle-limit` dan `--round-timeout`.
- [ ] **Step 2:** `bash tests/run.sh`; Expected: GAGAL.
- [ ] **Step 3:** ubah berkas di atas.
- [ ] **Step 4:** `bash tests/run.sh`; Expected: `SEMUA LULUS`.
- [ ] **Step 5: commit** `Rilis 0.12.0: watchdog idle autopilot dan blocked-by menunggu owner (#48, #17)`.
