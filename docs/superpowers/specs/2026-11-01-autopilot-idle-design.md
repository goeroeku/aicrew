# Autopilot: sesi yang menganggur di dalam putaran (#48) dan menunggu owner (#17) — desain

Status: draf untuk persetujuan owner. **[owner]** = keputusan owner atau disetujui di percakapan ("saya ikut saran anda": watchdog bawaan **aktif**, 30 menit); **[saya]** = keputusan penulis desain, boleh dikoreksi. Issue: #48, #17. Bahan lapangan: dua stall Nexora (2026-11-01) dan watchdog lokal mereka (komentar di #48).

## Maksud dan alasan
Antar putaran, `autopilot.sh` sehat: `waiting_on_owner`, `--wait`, `--wait-max`, `--stuck`. Di dalam satu putaran tidak ada batas: panggilan `claude -p` (autopilot.sh:65) tanpa batas waktu dan tanpa deteksi idle. Dua kejadian nyata: sesi menulis "menunggu owner / agen" lalu tetap hidup (CPU ~0,1%) 1 jam 21 menit dan sekitar 16 menit, memakai daftar issue basi, sementara issue Ready lain menunggu. Pemantau antar-putaran dan sidik jari tidak sempat berjalan. Pemilik tidak bisa membedakan "menunggu" dari "macet" (`autopilot.status` tetap "putaran 1: 8 issue terbuka").
#17 (kode keluar 3 pada putaran pertama yang tak berubah) **sebagian sudah terpenuhi** di kode: `waiting_on_owner` memantau murah lewat `gh` setelah satu putaran tak berubah, dan PR terbuka (termasuk L2) dihitung menunggu. Celah tersisa: issue dengan `blocked-by` yang belum selesai belum dikenali sebagai menunggu.

## Tujuan
- Putaran yang idle diakhiri otomatis tanpa menyentuh pekerjaan yang sah; `autopilot.sh` lalu memulai putaran berikut dengan daftar issue segar. **[owner]**
- **Bawaan aktif, batas idle 30 menit.** **[owner]**
- Idle hanya bila SEMUA berlaku selama batas: (1) tidak ada berkas berubah di direktori transkrip sesi (termasuk transkrip subagen); (2) tidak ada proses turunan sesi selain pembantu MCP/LSP. Sinyal CPU sengaja tidak dipakai: `%cpu` di `ps` adalah rata-rata sepanjang umur proses (tidak instan), dan CPU rendah juga terjadi pada agen dalam-proses yang menunggu model. **[saya, dari bukti Nexora dan pemeriksaan builder]**
- Batas keras opsional `--round-timeout` (bawaan mati). **[saya]**
- Visibilitas: owner bisa membedakan menunggu dari macet. **[owner]**
- #17: `blocked-by` yang belum selesai ikut dihitung "menunggu". Semantik kode keluar tidak berubah (2 buntu, 3 menunggu owner). **[saya]**
- Skill `orchestrate`, mode tanpa pengawasan: akhiri giliran setelah laporan bila hanya menunggu owner; muat ulang daftar issue sebelum menyimpulkan "tidak ada pekerjaan". **[saya]**

## Non-tujuan
- Eskalasi ke SIGKILL. SIGTERM setelah SIGINT tidak bergeming 90 detik diizinkan (lihat Keputusan tambahan). **[owner]**
- Menyentuh sesi lain selain anak `claude` langsung dari `autopilot.sh` ini; mengubah kode keluar; deteksi limit (0.8.2) tetap.
- Mengubah perilaku saat tidur karena limit atau saat `waiting_on_owner` (bukan putaran claude).

## Anti-tujuan (gagal walau tampak jalan)
- Menginterupsi sesi yang sedang bekerja (QA/security agen, tes, build docker): false positive.
- Watchdog yang tidak menemukan direktori transkrip atau proses sesi **mengambil tindakan** (harus tidak melakukan apa pun dan mencatat; fail-safe, bukan fail-kill).
- Menginterupsi proses yang bukan anak `claude -p` dari autopilot ini.
- Putaran berulang diinterupsi tanpa batas (tiga putaran berturut-turut diakhiri idle tanpa perubahan harus berhenti dengan pesan jelas, lewat mekanisme `--stuck`).
- Perilaku lama berubah untuk putaran sehat (kode keluar, deteksi limit, arsip log).

## Rancangan
**Watchdog di dalam `autopilot.sh` [saya].** `claude` tetap dijalankan di latar depan (bukan `&`): perintah asinkron dari shell non-interaktif mengabaikan SIGINT (aturan POSIX), dan inilah yang membuat tiruan uji Nexora tidak merespons. Pemantau berupa subshell latar yang berjalan selama putaran: tiap 30 detik (`AICREW_IDLE_POLL`) ia mencari anak langsung `claude` dari `$$` (`pgrep -P`), menghitung `idle_sejak` dari dua sinyal, dan bila `idle_sejak >= idle_limit` mengirim `kill -INT` ke pid itu saja; ia dimatikan segera setelah putaran selesai. Sinyal: mtime terbaru di direktori transkrip (`~/.claude/projects/<cwd dengan karakter non-alfanumerik jadi '-'>/`, termasuk subdirektori subagen; dapat ditimpa `AICREW_TRANSCRIPT_DIR` untuk tes); proses turunan rekursif kecuali yang namanya (`comm`) cocok `AICREW_IDLE_IGNORE` (bawaan: `codebase-memory|gopls|mcp|typescript-language-server|tsserver`).
**Opsi [owner+saya].** `--idle-limit DETIK` / `AICREW_IDLE_LIMIT` (bawaan 1800, 0 = mati), `--round-timeout DETIK` / `AICREW_ROUND_TIMEOUT` (bawaan 0 = mati). Nama selaras dengan Nexora (mereka beralih ke opsi bawaan setelah rilis).
**Pencatatan [saya].** Saat menginterupsi: `putaran N: idle X menit; diinterupsi (SIGINT)`; bila sesi masih hidup 30 detik kemudian: dicatat, tanpa eskalasi. Putaran yang berakhir karena interupsi diperlakukan seperti putaran biasa (rc dicatat, batas dicek, sidik jari dibandingkan), sehingga `--stuck` berhenti setelah tiga putaran idle tanpa perubahan.
**Status [saya].** Baris pertama `autopilot.status` tidak berubah (kompatibel); berkas baru `.aicrew/autopilot.json` memuat `{fase, putaran, idle_sejak_detik, detak}` dengan fase `putaran|menunggu-owner|tidur-limit|idle-diinterupsi|selesai`, diperbarui tiap tick pemantau dan tiap perubahan fase. Nomor issue yang sedang dikerjakan diserahkan ke builder bila murah didapat (tanpa panggilan `gh` tambahan tiap tick).
**`orchestrate` [saya].** Satu butir di bagian mode tanpa pengawasan: akhiri giliran setelah laporan bila yang tersisa hanya menunggu owner atau agen; sebelum menulis "tidak ada pekerjaan", jalankan ulang `gh issue list` untuk issue Ready.
**#17 [saya].** Perluas `waiting_on_owner` agar issue dengan `blocked-by` yang belum selesai dihitung menunggu; kriteria selesai #17 disesuaikan dengan kenyataan kode.
**Dokumen [saya].** Komentar kepala `autopilot.sh`, README satu kalimat, `skills/orchestrate/SKILL.md`. Rilis kandidat 0.12.0 (perilaku bawaan baru: watchdog aktif).

## Keputusan tambahan (hasil pemeriksaan builder)
Catatan: klaim builder tentang perilaku proses (SIGINT, kode keluar) berasal dari pengetahuan bash/ps dan wajib diverifikasi dengan percobaan kecil saat implementasi; data lapangan Nexora (dua kali Ctrl-C ke sesi `claude`) menunjukkan `rc=0` dan `autopilot.sh` melanjutkan.
**Dijawab owner ("saya ikut rekomendasi anda").**
- **Eskalasi bila sesi bertahan 30 detik setelah SIGINT [owner].** Draf awal: hanya dicatat; builder menunjukkan `wait` di latar depan lalu menggantung selamanya, persis masalah #48. Diputuskan: setelah 60 detik lagi kirim **SIGTERM** (tidak pernah SIGKILL), dicatat; sesi yang mengabaikan SIGINT sudah macet dan telah idle 30 menit, jadi risikonya kecil. Ini menggantikan butir Non-tujuan "tanpa eskalasi" di atas untuk SIGTERM; SIGKILL tetap tidak dipakai.
**Keputusan saya [saya].**
- **Sinyal CPU dihapus** (lihat Tujuan). Sisa dua sinyal.
- **Penanda interupsi.** Pemantau menulis berkas penanda (`.aicrew/idle-interrupt`) sebelum `kill -INT`, karena subshell tidak dapat mengubah variabel induk. Setelah `claude` kembali, bila penanda ada: putaran diperlakukan sebagai putaran normal, `rc` dinormalkan (130 atau 0), deteksi limit dan jalur gagal (`errs`, `AICREW_ERR_SLEEP`) dilewati, sidik jari dibandingkan seperti biasa, sehingga tiga putaran idle tanpa perubahan berhenti lewat `--stuck` (kode 2). Penanda dihapus tiap awal putaran.
- **Ctrl-C pemilik tetap menghentikan autopilot.** `trap` INT di `autopilot.sh` memeriksa penanda: ada = interupsi dari pemantau (lanjut); tidak ada = Ctrl-C pemilik (matikan pemantau dan `claude`, keluar 130). Jangan `trap ''` (ignore diwarisi anak, `claude` jadi kebal SIGINT). `trap` EXIT/TERM mematikan pemantau agar tidak yatim. Tes: SIGINT ke autopilot tanpa penanda menghentikannya.
- **Sasaran** adalah satu-satunya anak langsung `$$` selain subshell pemantau (tanpa mencocokkan nama `claude`); pemantau memverifikasi pid itu masih anak `$$` sebelum mengirim sinyal. Subshell pemantau mengenali dirinya lewat `sh -c 'echo $PPID'` (bash 3.2 tidak punya `BASHPID`). `AICREW_CLAUDE` yang berupa wrapper wajib `exec claude ...` (didokumentasikan); wrapper tanpa `exec` membuat sasaran salah.
- **Waktu idle** = waktu sejak `max(mtime terbaru direktori transkrip, awal putaran)` (sesi baru tidak langsung idle oleh mtime basi), diukur portabel dengan berkas penanda waktu yang di-`touch` tiap tick dan `find DIR -type f -newer`. Direktori transkrip tak ditemukan = tidak ada tindakan, dicatat sekali. Pemetaan cwd ke nama direktori (`pwd -P`, karakter non-alfanumerik jadi `-`) diverifikasi dengan percobaan nyata saat implementasi. Sesi interaktif owner di cwd yang sama ikut menunda watchdog (aman); dicatat di dokumentasi.
- **Pemantau tidak aktif saat tidur** (`sleep "$sleep_s"`, `AICREW_ERR_SLEEP`, `waiting_on_owner`); fase `tidur-limit`/`menunggu-owner` ditulis oleh jalur itu, bukan pemantau. `autopilot.json` ditulis atomik (tmp lalu `mv`).
- **`blocked-by`** dibaca dari bagian `## Blocked by` di badan issue (`templates/ISSUE.md`); `body` ditambahkan ke satu `gh issue list --json` yang ada (tanpa panggilan per issue); `#n` dicocokkan dengan batas kata; "none" dan blocker lintas repo diabaikan. Blocker terpenuhi bila ditutup atau berlabel integrasi (sudah dikecualikan dari `$open`).
- **Arti "menunggu" untuk #17.** Issue menunggu bila `needs-principal`, punya PR terbuka, atau semua blocker yang belum terpenuhi sendiri menunggu (dihitung berulang sampai tetap). Blocker yang berupa pekerjaan Ready berarti BUKAN menunggu owner (putaran tetap berjalan). `waiting_on_owner` tetap baru aktif setelah satu putaran tak berubah (`same >= 1`); itulah yang dimaksud "putaran pertama" di #17, kriterianya disesuaikan.
- **`orchestrate`.** Tidak ada bagian mode tanpa pengawasan yang berdiri sendiri; tambahkan subbagian pendek `## Mode tanpa pengawasan (autopilot)` setelah Resume dengan dua butir di atas.
- **Tes.** Sesi palsu "idle" memakai `exec sleep N` (sleep bukan anak dari skrip); "aktif" menyentuh berkas di `AICREW_TRANSCRIPT_DIR` tiap detik; "punya anak non-pembantu" memakai `sleep N &; wait`; "bertahan setelah SIGINT" memakai `trap '' INT`. Assertion berbasis ada/tidak baris `idle` di log. Ada tes jalur `caffeinate` untuk idle, atau dinyatakan tidak dicakup. Opsi baru diurai di loop argumen.
- **Minor (ditunda):** sidik jari memuat label, jadi perubahan label lain di tengah putaran memengaruhi hitungan `--stuck`.

## Kendala
- Tes tanpa jaringan dan tanpa `claude` asli: `AICREW_CLAUDE` menunjuk sesi palsu (berkas skrip) yang menganggur / aktif / punya anak proses; waktu tes pendek lewat `AICREW_IDLE_LIMIT=2`, `AICREW_IDLE_POLL=1`. Jebakan uji dari Nexora: mulai autopilot palsu lewat `perl -e '$SIG{INT}="DEFAULT"; exec @ARGV'` bila perlu; macOS tanpa `timeout` (pakai pid latar dan `kill`).
- Bash 3.2 (macOS) dan Linux; `ps -o %cpu=` portabel; artefak berbahasa Indonesia (kunci opsi CLI/env mengikuti aturan bahasa artefak: Inggris).

## Kriteria selesai
- Tes merah dulu: sesi idle melewati batas diinterupsi dan putaran berikut dimulai (log memuat `idle`); sesi yang berkas transkripnya berubah, atau punya anak proses non-pembantu, tidak diinterupsi; direktori transkrip tak ditemukan = tidak ada tindakan; `--idle-limit 0` mematikan; tiga putaran idle tanpa perubahan berhenti (kode 2); `--round-timeout` menginterupsi sesi yang aktif; `autopilot.json` memuat fase dan detak; `waiting_on_owner` menghitung `blocked-by` yang belum selesai; kode keluar lama tak berubah; `bash tests/run.sh` -> `SEMUA LULUS`.
- README, `orchestrate`, komentar kepala diperbarui; rilis lewat alur rilis (owner menyetujui sebelum merge).

## Diserahkan ke builder
Cara memilih anak `claude` bila `caffeinate` membungkus, pemetaan cwd ke direktori transkrip, penyusunan sesi palsu, bentuk `autopilot.json`, penentuan `blocked-by` dari badan issue/label, dan redaksi pesan log.
