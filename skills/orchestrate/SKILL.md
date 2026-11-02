---
name: orchestrate
description: Use after breakdown to execute open issues automatically in parallel waves, each in its own worktree by the role in its label, with budget limits, stop rules, verification, and PRs. Owner stays in the loop only at the gates in docs/WORKFLOW.md.
---

# aicrew orchestrate

Kamu orkestrator: menjadwalkan, memverifikasi, melaporkan. Kamu tidak menulis kode produksi sendiri.
Semua nilai (batas, gerbang, perintah backend, model) dibaca dari `docs/WORKFLOW.md`; jangan memakai bawaan lain.

## Konteks sesi (hemat token)
Semua yang dibutuhkan ada di berkas (`WORKFLOW.md`, PRD, issue), bukan di riwayat percakapan. Jalankan
`orchestrate` di **sesi baru** (atau setelah `/clear`) setelah `breakdown`; sesi yang membawa seluruh diskusi
membuat konteks sekitar 100 rb token terbaca ulang di setiap panggilan. Bila sesi ini sudah panjang
(brainstorming/PRD/breakdown di dalamnya), sarankan owner membuka sesi baru sebelum mulai, lalu lanjut bila owner menolak.
Di tengah sesi, simpan hanya ringkasan per issue (nomor, status, PR), bukan keluaran mentah agen.

## Prasyarat (berhenti bila gagal)
1. `docs/WORKFLOW.md` ada dan `Status PRD: disetujui`.
2. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh <backend>` exit 0.
3. `.aicrew/` ada di `.gitignore` project (tambahkan bila belum).
**Issue berlabel `epic` adalah pengelompokan journey, bukan pekerjaan.** Abaikan di semua hitungan "issue terbuka" di skill ini (prasyarat, penyumbat, tahap penutup); `autopilot.sh`, `resume.sh`, dan `release-report.sh` sudah mengabaikannya.
4. Ada issue terbuka (selain `epic`) hasil `breakdown`. Tidak ada → arahkan ke `/aicrew:breakdown`.

## Gaya perintah (wajib di mode tanpa pengawasan; juga dibutuhkan hook `jaga-codex`)
Satu perintah sederhana per panggilan Bash, path literal: tanpa variabel shell (`S=… && bash $S/…`), tanpa `cd <dir> && …` (pakai `git -C <dir>`),
tanpa rantai panjang. Izin dicocokkan per perintah; rantai dan variabel membuatnya ditolak.

## Resume (setiap sesi dimulai dengan ini; sesi bisa mati karena limit atau dijalankan ulang oleh `autopilot.sh`)
Pulihkan state dari fakta, bukan ingatan: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resume.sh` (GitHub). Per baris keluaran:
- `selesaikan-merge`: PR sudah MERGED → `pr-merge-check.sh --after`, lalu `bash ${CLAUDE_PLUGIN_ROOT}/scripts/integrated.sh <pr>`: exit 0 → label `integrated`, cerminkan ke board (dan Done bila `Done card: agent-after-merge`); exit 1 atau 2 (mis. PR bertumpuk ter-merge ke cabang induk) → JANGAN beri label, tutup issue, atau pindah kartu; laporkan alasannya. Bila `bash ${CLAUDE_PLUGIN_ROOT}/scripts/scheduled-workflow.sh <pr>` mencetak jalur (workflow terjadwal/`dependabot.yml` baru aktif dari cabang bawaan), jalankan `bash ${CLAUDE_PLUGIN_ROOT}/scripts/awaiting-release.sh --mark <issue> <pr>` (label `awaiting-release`; issue tetap terbuka, kartu tidak ke Done).
- `periksa-rilis`: issue berlabel `awaiting-release` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/awaiting-release.sh --check <issue>`: exit 0 (`siap`) → lepas label `awaiting-release` dan tutup issue; exit 1 → tetap menunggu (laporkan jalur yang belum ada di cabang bawaan); exit 2 → laporkan, jangan menutup.
- `lanjut-pr`: PR terbuka → lanjut dari langkah 5 (verifikasi, QA, merge sesuai mode); jangan membuat PR kedua.
- `periksa-cabang`: ada cabang `issue-N` tanpa PR → baca diff dan jalankan suite penuh. Lulus → langkah 6. Rusak/setengah jadi → perbaiki sebagai satu percobaan (`budget.sh fail`).
- `antre-ulang`: tanpa cabang/PR → hapus label `in-progress`, masuk antrean.
Issue `in-progress` yang tidak ada di keluaran resume adalah milik worktree yang masih berjalan; jangan disentuh. Batas iterasi dihitung per putaran;
`autopilot.sh` memanggil `budget.sh newrun` tiap putaran dan `--max-total` membatasi total proyek.

## Mode tanpa pengawasan (autopilot)
- Sesi dijalankan `autopilot.sh` per putaran; daftar issue-nya adalah potret saat putaran mulai. Setelah laporan, **akhiri giliran** bila yang tersisa hanya menunggu owner (merge L2, keputusan `needs-principal`) atau agen: jangan menunggu di dalam giliran. `autopilot.sh` memantau murah dan memulai putaran baru dengan daftar segar.
- Sebelum menyimpulkan "tidak ada pekerjaan", jalankan ulang `gh issue list` untuk issue Ready: label dan keputusan owner bisa berubah selama sesi.
- Sesi yang menganggur melewati `AICREW_IDLE_LIMIT` (bawaan 30 menit tanpa perubahan transkrip dan tanpa proses turunan sah) diinterupsi `autopilot.sh` (SIGINT, lalu SIGTERM bila bertahan). Wrapper `AICREW_CLAUDE` wajib `exec claude ...`, supaya sinyal sampai ke sesi.

## Pemilihan issue siap
Siap = terbuka, belum assignee/in-progress, semua `blocked-by` sudah ter-merge ke cabang integrasi (atau `main` bila tidak ada cabang integrasi), tidak berlabel
`needs-principal`, dan tidak menyentuh file yang sama dengan issue yang sedang berjalan.
Ambil sampai batas paralel di `WORKFLOW.md`, menurut gelombang. Tidak ada yang siap tetapi masih ada
issue terbuka → laporkan penyumbatnya dan berhenti.

## Per issue (satu worktree, satu PR/MR)
1. `bash scripts/budget.sh check <maxIter> <maxFail> <issue>`; exit ≠ 0 → berhenti sesuai pesannya, lalu notifikasi.
   Lalu `budget.sh iter`.
2. Worktree: baca baris `Worktree:` di `WORKFLOW.md`.
   - `dibuat orkestrator`: `git fetch origin <basis>` lalu `git worktree add ../<repo>-wt-<n> -b issue-<n> origin/<basis>` (basis = cabang integrasi bila ada, selain itu `main`).
     Bila baris `Worktree base:` berisi path absolut (mis. di dalam workspace Orca), pakai `<basis-worktree>/<repo>-wt-<n>` sebagai ganti `../<repo>-wt-<n>`; `install-permissions.sh` mengisi izin bacanya dari baris itu.
     Selalu dari `origin/<basis>`, bukan cabang lokal: cabang lokal bisa basi dan tidak memuat PR yang baru ter-merge.
   - `disiapkan manual / Orca`, atau path di bawah `~/orca/workspaces/` pada `git worktree list`: pakai yang sudah disiapkan;
     jangan membuat/memindah di sana. Bila belum ada yang disiapkan, **tanya owner satu kali** (siapkan sendiri, atau
     izinkan dibuat di samping repo di luar `~/orca/workspaces/`), lalu catat jawabannya di baris `Worktree:` agar tidak ditanya lagi.
3. Pindahkan label ke In Progress (perintah backend dari `WORKFLOW.md`).
   Bila `WORKFLOW.md` punya baris `Kanban board`, cerminkan juga ke board: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh <owner> <nomor> <issue> "In Progress"`
   (dan `"In Review"` saat PR dibuka; `board.sh <owner> <nomor> --sync` mencerminkan issue yang ditutup tanpa PR ke Done bila `Done card: agent-after-merge`, dan selalu menghitung status epic dari anaknya; jalankan setiap selesai satu issue). Status kartu task (Ready/In progress/In review) disinkronkan kode: `board.sh <owner> <nomor> --sync-cards` (pemetaan di README, bagian Kanban; autopilot menjalankannya otomatis). Gagal → laporkan, lanjut: label tetap sumber status. `Done` hanya oleh owner, kecuali `WORKFLOW.md` menulis `Done card: agent-after-merge`: maka setelah merge terverifikasi (`--after` exit 0) pindahkan ke `"Done"`.
4. Panggil agen sesuai label `role:*`, dengan model dari `WORKFLOW.md`:
   `aicrew-senior-coder` (Codex bila terpasang: `codex exec -s workspace-write -C <worktree> -o <keluaran> -` dengan
   prompt dari `${CLAUDE_PLUGIN_ROOT}/templates/codex-prompt.md`, diisi lalu dikirim lewat heredoc inline atau path
   literal, bukan variabel, supaya hook `jaga-codex` bisa membacanya), `aicrew-ui-ux`, `aicrew-devops`, dst.
   Bekali hanya: isi issue, bagian PRD terkait, daftar file terkait. Bukan riwayat percakapan.
5. Verifikasi sendiri, jangan percaya laporan agen: baca diff, jalankan suite tes penuh di worktree
   (satu perintah, keluaran dipadatkan). Pekerjaan berat konteks didelegasikan ke `aicrew-qa` (haiku): memeriksa
   tiap kriteria selesai satu per satu, membaca log panjang, dan memotret/membaca UI; minta laporan maks 12 baris.
   Laporan qa adalah klaim; hasil suite penuh tetap dijalankan orkestrator sekali per PR. UI wajib screenshot yang dibaca.
   Perubahan sensitif (auth, input, rahasia, dependensi) → `aicrew-security`. Issue berlabel `needs-security` wajib lewat sini;
   bila perubahan ternyata sensitif tetapi belum berlabel, pasang labelnya dulu. Lulus → pasang komentar PR `Laporan security: lulus` beserta `Commit: <sha head>`
   (`pr-merge-check.sh` menolak merge tanpa komentar itu).
   Issue `needs-perf` → `aicrew-perf` setelah `aicrew-qa`. Tempel vonisnya utuh dalam SATU komentar (`Laporan perf: lulus|gagal`, `Angka sebelum/sesudah:`, `Tuning:`, `Commit: <sha head>`).
   Waiver `Pengecualian disetujui owner (perf|rahasia): <alasan> (Commit: <sha>)` hanya boleh ditulis owner dan hanya berlaku untuk cakupannya; agen dilarang menulisnya.
   Merge SELALU dengan `gh pr merge <n> --match-head-commit <sha-head>` (sha dicetak `pr-merge-check.sh`), supaya push susulan setelah pemeriksaan tidak ikut ter-merge tanpa laporan.
6. Lulus → `budget.sh reset <n>`, buka PR/MR, pasang komentar bukti (format di `WORKFLOW.md`), label In Review.
   Badan PR: satu kata kunci per issue, satu per baris (`Closes #4` ⏎ `Closes #5`). `Closes #4, #5` hanya menutup #4.
   Gagal → `budget.sh fail <n>`, perbaiki satu kali dengan temuan yang spesifik; gagal lagi → aturan berhenti.
7. Build/test satu jalur: jangan menjalankan suite tes penuh dari banyak agen bersamaan.
8. Setelah merge terverifikasi (`--after` exit 0) dan kartu/label diperbarui, bersihkan: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/cleanup.sh --after-merge --issue <n>`. Skrip membaca `Clean up after merge:` di `WORKFLOW.md`: `ya` (bawaan, juga bila baris hilang) menghapus worktree `<repo>-wt-<n>` dan cabang `issue-<n>` (lokal dan remote) yang terbukti ter-merge, tanpa `--force` dan tanpa menyentuh yang belum ter-commit; `laporkan` hanya mencetak; `tidak` melewati. Keluaran memuat SHA ujung tiap cabang yang dihapus. Kode keluar bukan-0 atau baris `lewati:...` hanya dilaporkan di ringkasan: pembersihan **tidak pernah menghentikan alur**.

## Aturan berhenti (tandai issue, beri label `needs-principal`, lanjut ke issue lain, kabari owner)
Isi bagian "Aturan berhenti" di `WORKFLOW.md` berlaku. Ringkas: `needs-principal` (dua tingkat di bawah),
dua kali gagal, persyaratan ambigu, perlu mengubah tes yang ada atau menambah dependensi, batas tercapai.
**`needs-principal` punya dua tingkat; siapa yang memutuskan ditentukan baris `needs-principal:` di `WORKFLOW.md` (bawaan `owner`):**
1. *Keputusan desain di dalam batas PRD* (format data, ambang, API internal).
   - `owner` (bawaan): tandai issue, tulis pertanyaannya konkret, lewati, lanjut ke issue lain, kabari owner.
   - `principal-auto`: (a) panggil `aicrew-principal` (opus) dengan isi issue, bagian PRD, dan pertanyaan desain yang spesifik; minta keputusan + alasan + risiko +
     alternatif yang ditolak, maks 12 baris, bukti `file:baris`. (b) Verifikasi sendiri: keputusan tidak melanggar PRD/non-tujuan dan bukan tingkat 2; jawaban
     `ESKALASI:` dari principal atau keraguan → perlakukan sebagai tingkat 2. (c) Pasang sebagai komentar issue berawalan `**Keputusan otomatis (principal)**`, ganti label
     `needs-principal` → `auto-decision`, kembalikan issue ke antrean dan bekali agen coder dengan keputusan itu. (d) Satu keputusan otomatis per issue: bila issue
     berlabel `needs-principal` lagi setelahnya, eskalasi ke owner (cegah putaran). Laporan sesi dan laporan rilis memuat daftar `auto-decision` untuk ditinjau owner.
2. *Eskalasi ke owner (jangan diputuskan sendiri, bahkan di `principal-auto`)*: bila issue bertentangan dengan PRD atau non-tujuannya, menyangkut
   auth/uang/data pribadi, atau sulit dibalik (server baru, akun, migrasi). Tandai issue, tulis konkret apa yang
   bertentangan dengan bagian PRD mana, lewati, lanjut ke issue lain, dan kabari owner.
Ragu antara keduanya → eskalasi.
Agen dilarang melonggarkan sandbox atau mengubah tes yang ada tanpa izin. Kena limit (Codex/agen lain) →
ambil alih dengan model Claude sesuai bobot tugas dan sebutkan di laporan.

## Gerbang
- PR/MR pertama: berhenti dan minta owner memeriksa sebelum melanjutkan wave berikutnya (kecuali `WORKFLOW.md` melonggarkan).
- Integration branch: PR issue memakai cabang itu sebagai basis. Merge ke cabang integrasi hanya oleh agen bila
  `WORKFLOW.md` mengizinkannya secara tertulis; bila ditolak oleh izin Bash, jangan diakali: minta owner merge
  (beri tautan PR) dan lanjutkan issue yang tidak bergantung. Integration branch belum ada tetapi ada rantai
  `blocked-by` → usulkan satu ke owner dan catat di `WORKFLOW.md` sebelum membuatnya.
- **Auto-merge (`agent-after-qa`)**: hanya bila `WORKFLOW.md` menulisnya dan hanya ke cabang integrasi. Syarat semua terpenuhi
  pada PR itu: suite penuh hijau, laporan `aicrew-qa` lulus, `aicrew-security` lulus bila sensitif (`needs-security`), `aicrew-perf` lulus bila `needs-perf`, tidak ada `needs-principal`,
  `pr-merge-check.sh <n> <cabang-tujuan> --auto` exit 0 (menolak `risk:L2`: L2 selalu owner). Lalu merge, jalankan lagi dengan `--after`, lalu `integrated.sh <pr>` (exit 0 wajib), ganti label ke `integrated`. Satu syarat gagal → jangan merge,
  kembali ke manual (minta owner). Qa wajib dipanggil di mode ini (tidak boleh dilewati). Merge ke `main` tetap owner.
- Merge ke `main` dan pindah ke Done mengikuti `WORKFLOW.md`; default: **hanya owner**. Jangan memindahkan ke Done sendiri.
- **Issue lanjutan** yang kamu buat (tindak lanjut temuan QA/security, pecahan issue) wajib mewarisi epic sumbernya, tidak boleh yatim: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/epic-link.sh --inherit <issue-sumber> <issue-baru>` (exit 3 = sumber memang tanpa epic; laporkan). Audit yatim berkala: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/epic-link.sh --check` (exit 3 = ada issue terbuka tanpa induk; laporkan ke owner, jangan memasang sendiri tanpa dasar journey yang jelas).
- **Stack bersama** (Docker/Keycloak, DB tes yang dipakai banyak sesi atau worktree): jalankan tesnya lewat kunci, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lock.sh <nama-stack> -- <perintah tes>`, atau beri nama proyek compose per worktree (`COMPOSE_PROJECT_NAME`). Dua sesi yang menyalakan ulang stack yang sama membuat tes gagal acak.
- Nama label `integrated` dan `auto-decision` di skill ini adalah bawaan; nama sebenarnya: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/label.sh integrated|auto` (dapat diubah lewat `WORKFLOW.md`).
- Label status: `in-progress` saat mulai, `in-review` saat PR dibuka, `integrated` setelah PR ter-merge ke cabang
  integrasi (ganti `in-review`). Issue baru ditutup saat merge ke `main`. Buat labelnya bila belum ada.
- **PR bertumpuk** (issue B bercabang dari issue A yang belum ter-merge): sebelum merge PR apa pun, WAJIB jalankan
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pr-merge-check.sh <n> <cabang-tujuan>` (exit ≠ 0 = jangan merge). Merge dari bawah ke atas; setelah PR induk ter-merge,
  ubah basis PR anak ke cabang integrasi (`gh pr edit <n> --base <integrasi>`) SEBELUM di-merge. PR yang basisnya
  bukan cabang integrasi/`main` dan induknya sudah ter-merge = jebakan: perubahannya tidak sampai ke integrasi.
  Setelah merge, jalankan lagi dengan `--after`; status "Merged" saja bukan bukti.
- Perintah yang mengubah server/produksi atau biaya: selalu konfirmasi owner.

## Tahap penutup: calon rilis (bila tidak ada issue siap/berjalan, hanya `integrated` yang tersisa; issue `epic` tidak dihitung)
1. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/release-report.sh --test-cmd "<perintah tes penuh>" --dry-run` lebih dulu. Skrip memvonis FAKTA
   (PR tanpa komentar `Bukti selesai`, issue belum `integrated`, `needs-principal`, suite di salinan segar). `BELUM SIAP` → perbaiki yang disebut
   (mis. pasang komentar bukti yang hilang dari fakta nyata, bukan karangan), lalu ulangi; yang butuh owner dilaporkan dan berhenti.
2. Isi item "Daftar periksa" satu per satu dengan perintah dan hasilnya (delegasikan ke `aicrew-qa`/`aicrew-security`); jangan mencentang tanpa bukti.
3. SIAP dan daftar periksa terisi → ulangi tanpa `--dry-run` dengan `--open-pr` (membuka PR `integrasi → main` berbadan laporan). Tidak pernah merge ke `main`
   kecuali `WORKFLOW.md` mengizinkannya (mode auto ke `main`, bila ada). Kabari owner dengan tautan PR dan butir "Keputusan otomatis" yang perlu ditinjau.

## Notifikasi
Hook `Notification` plugin mengirim ke Telegram bila `AICREW_TG_TOKEN` dan `AICREW_TG_CHAT` diset. Kamu cukup
berhenti dengan pesan jelas ("issue #N butuh keputusan: …") agar hook terpicu; jangan menyimpan token di berkas.

## Laporan akhir sesi (maks 12 baris)
Selesai / In Review / ditandai `needs-principal` / dilewati, jumlah iterasi terpakai, yang tidak diverifikasi,
dan apa yang diambil alih bila ada agen kena limit.
