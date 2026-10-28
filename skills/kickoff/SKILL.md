---
name: kickoff
description: Use at the start of a new project (or when adopting aicrew in an existing repo) to decide the working pattern and write docs/WORKFLOW.md. Asks the owner for repo/backend, profile (ringan/standar/penuh), roles, gates, and stop rules.
---

# aicrew kickoff

Tujuan: satu diskusi singkat dengan owner, hasilnya `docs/WORKFLOW.md` di repo project.
Bahasa dokumen: Indonesia. Jangan menulis kode project di skill ini.

## Aturan
- **Repo dan backend (GitHub/GitLab) adalah keputusan owner.** Tanyakan; jangan memilih sendiri. Cek `command -v gh glab` hanya untuk memberi tahu apa yang terpasang.
- Baca repo dulu bila sudah ada (ukuran, stack, tes) sebelum menyarankan profil.
- Satu pertanyaan per giliran. Beri rekomendasi, bukan daftar pilihan kosong.

## Mode audit (bila `docs/WORKFLOW.md` sudah ada)
Jangan menulis ulang. Bandingkan dengan `templates/WORKFLOW.md`: ukuran task, label, aturan berhenti,
batas, bukti selesai, perintah backend, PRD/Kode ada. Laporkan tabel *sesuai / kurang / bertentangan*
(dengan baris yang bersangkutan). Aturan lokal yang sengaja berbeda dihormati dan hanya dicatat.
Siapkan perubahan siap-terapkan (diff) dan minta persetujuan owner sekali sebelum menerapkannya.

## Langkah
0. **PRD yang sudah ada**: cari `PRD*`, `docs/`, `spec*`. Jika ada, minta owner mengonfirmasi lokasi dan
   apakah PRD itu sudah disetujui; catat keduanya di `WORKFLOW.md` (`PRD: <path>`, `Status PRD: disetujui|belum`).
   PRD berstatus `draf` (hasil jalur draf `prd`) → catat `Status PRD: belum`.
   Jalankan `git check-ignore -v docs`. Bila `docs/` di-ignore: tampilkan aturan dan berkasnya, lalu tanyakan owner
   (jangan ubah `.gitignore` sendiri): (a) tetap di-ignore (disengaja), atau (b) hanya `PRD.md` dan `WORKFLOW.md`
   yang dilacak. Catat jawabannya di `WORKFLOW.md`.
   Jangan mengubah PRD. Jika repo sudah berisi kode, catat `Kode ada: ya` (memicu audit status di breakdown).
1. **Konteks**: apa yang dibangun, siapa pengguna, risiko (auth, uang, data, migrasi?).
2. **Profil** (sarankan satu, owner memutuskan):
   - `ringan`: tanpa PRD; satu issue, satu role. Untuk skrip/perbaikan kecil.
   - `standar`: PRD + issue + role seperlunya; gerbang di PRD dan PR pertama.
   - `penuh`: semua role, reviewer PRD tanpa konteks, aturan berhenti ketat, fase paralel.
3. **Backend & repo**: GitHub atau GitLab, nama repo. Setelah owner memilih, jalankan
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh <backend>`; bila gagal (CLI belum terpasang/login),
   sampaikan apa yang kurang dan jangan lanjut ke tahap yang membutuhkannya. Tampilkan juga status Codex dan Telegram. Bila preflight mencetak `AWAS` (workflow jalan saat push ke main), catat di gerbang 4 `WORKFLOW.md` dan tanyakan owner. Tulis perintah backend di satu bagian `WORKFLOW.md` supaya mudah diganti.
4. **Role aktif**: pilih dari `agents/` (principal, senior-coder, qa, security, devops, ui-ux).
5. **Gerbang & aturan berhenti**: mulai dari bawaan di `templates/WORKFLOW.md`; owner boleh menimpa. Tanyakan juga apakah memakai board kanban (GitHub Project; perlu scope `gh` `project`: preflight menampilkan perintahnya). Bila ya dan belum ada board, buat dengan `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board-init.sh <owner> "<nama project>"` (cetak nomornya; catat di `WORKFLOW.md`); bila owner sudah punya, pakai nomornya sebagai argumen ketiga. Tanyakan juga siapa yang memindahkan kartu ke Done: `owner` (bawaan) atau `agen-setelah-merge` (autopilot, cocok dengan mode merge `agen-setelah-QA`). Tanyakan juga siapa yang memutuskan `needs-principal` tingkat 1: `owner` (bawaan) atau `principal-auto` (butuh role principal aktif; tingkat 2 tetap owner). Tanyakan mode merge ke cabang integrasi: `owner` (bawaan, manual) atau `agen-setelah-QA` (otomatis setelah QA lulus; rekomendasi: merge ke `main` tetap owner).
6. **Batas**: paralel maksimum, iterasi per sesi, gagal berturut-turut per issue.
7. Tulis `docs/WORKFLOW.md` dari `${CLAUDE_PLUGIN_ROOT}/templates/WORKFLOW.md`, isi nilainya, tunjukkan ke owner, minta persetujuan.

Selesai hanya bila `docs/WORKFLOW.md` ada dan disetujui owner.
