---
name: breakdown
description: Use after the PRD is approved to split it into small issues with labels, dependencies, and parallel waves, then create them on the project's backend (GitHub/GitLab) per docs/WORKFLOW.md.
---

# aicrew breakdown

Masukan: PRD (path dan `Status PRD` dibaca dari `docs/WORKFLOW.md`, bawaan `docs/PRD.md`) dan `docs/WORKFLOW.md`.
Jika salah satu tidak ada, berhenti dan arahkan ke `/aicrew:kickoff` atau minta PRD.
Jangan memecah PRD yang belum disetujui; bila `Status PRD` tidak tercatat, tanya owner.

## Langkah
1. Baca kedua berkas. Ambil ukuran task, label, perintah backend, dan batas dari `WORKFLOW.md`.
2. Profil `penuh`: kirim PRD ke satu reviewer tanpa konteks (subagen read-only, hanya PRD + kode)
   untuk mencari ambigu/kontradiksi/yang hilang. Temuan serius → owner, sebelum lanjut.
2b. **Audit status — hanya bila repo sudah berisi kode** (`Kode ada: ya` atau ada source di repo;
   project baru melewati langkah ini). Subagen read-only (sonnet) menandai tiap kebutuhan PRD:
   `sudah ada | sebagian | belum`, dengan bukti `file:baris`, maks 12 baris per laporan. Klaim subagen
   diverifikasi dengan membaca kode sebelum dipakai. Tampilkan tabel ke owner dan minta persetujuan;
   hanya `sebagian` dan `belum` yang dipecah jadi issue. PRD tidak diubah; ambigu → daftar pertanyaan owner.
2c. **Audit issue yang sudah ada** (bila backend sudah punya issue terbuka). Baca issue terbuka lewat
   perintah backend dan periksa dengan daftar yang sama seperti issue baru: kriteria selesai bisa dicek
   mesin, ≤ 5 file, label `role/stack/phase`, `blocked-by` jelas. Tandai tiap issue: `standar | perlu
   diperbaiki (apa yang kurang) | duplikat`. Cocokkan juga dengan hasil audit status PRD. Jangan
   membuat issue untuk kebutuhan yang sudah punya issue. Siapkan perubahan siap-terapkan (label,
   kriteria yang ditulis ulang, penutupan duplikat) dan minta persetujuan owner sekali; mengubah issue
   itu tindakan keluar dan issue lama mungkin sedang dikerjakan orang lain, jadi lewati yang berlabel
   in-progress atau punya assignee kecuali owner menyebutnya.
3. Pecah PRD menjadi epic → issue. Tiap issue wajib memakai `${CLAUDE_PLUGIN_ROOT}/templates/ISSUE.md`.
   Tolak/pecah ulang issue yang melanggar ukuran (≤ 5 file, ≤ ±200 baris diff) atau tidak punya
   kriteria selesai yang bisa dicek mesin. Tidak bisa ditulis → tandai `needs-principal` atau tanya owner.
4. Cari **kode yang sudah ada** yang relevan (LSP/grep) dan cantumkan di "File terkait" supaya agen
   memakai ulang, bukan membuat ganda.
5. Isi `Blocked by` dan daftar file yang disentuh. Hitung gelombang (wave):
   issue tanpa blocker dan tanpa tumpang tindih file → satu gelombang, boleh paralel (maks sesuai
   `WORKFLOW.md`). Tumpang tindih file atau saling bergantung → gelombang berikutnya.
   Jika hampir semuanya saling bergantung, katakan terus terang: sekuensial lebih murah.
   Ada rantai `blocked-by`: usulkan **cabang integrasi** untuk fitur ini (aturan merge di `WORKFLOW.md`),
   supaya rantai tidak macet menunggu merge ke `main`.
6. Beri label `role:*`, `stack:*`, `phase:*` (+ `needs-principal` bila perlu). Issue yang menyentuh auth/otorisasi, input di batas
   kepercayaan, rahasia, dependensi baru, uang, atau data pribadi diberi `needs-security`: penandaan ini keputusan breakdown, bukan tebakan saat eksekusi.
   Issue yang menyentuh jalur tulis DB, antrean/worker/polling, cron, atau config infra (Postgres, Redis, limit container) diberi `needs-perf` dengan alasan yang sama.
   Beri juga satu label risiko per issue: `risk:L0` (dokumen, tes, refactor tanpa efek perilaku), `risk:L1` (perilaku biasa, bawaan bila ragu antara L0/L1),
   `risk:L2` (auth, uang, data pribadi, migrasi, infra, atau sulit dibalik). L2 tidak pernah di-merge otomatis (`pr-merge-check.sh --auto` menolaknya) dan sebaiknya juga `needs-principal`/`needs-security` bila relevan.
   Issue yang membaca repo/direktori lain (discovery) wajib memuat bagian "Security" dari `templates/ISSUE.md` apa adanya.
   Judul dan isi issue memakai bahasa artefak di `WORKFLOW.md` (bawaan Inggris).
7. **Tampilkan rencana dulu** (tabel: no, judul, role, wave, blocked-by, file) dan minta persetujuan
   owner. Membuat issue di backend itu tindakan keluar: jangan dijalankan sebelum disetujui.
8. Setelah disetujui: buat label yang belum ada, buat issue lewat perintah backend di `WORKFLOW.md`,
   isi `blocked-by` pada isi issue. Catat nomor issue ke tabel gelombang di akhir PRD (satu blok,
   jangan membuat berkas baru).

## Epic per journey (bila PRD punya bagian Journeys)
Lead membaca journey, agen mengerjakan issue kecil. Hierarkinya: Journey (epic) → kebutuhan (R-ID/N-ID) → issue.
- Setelah issue dibuat, buat satu epic per journey dari `${CLAUDE_PLUGIN_ROOT}/templates/EPIC.md` (label `epic`, judul `[J1] ...`). Daftar centang `- [ ] #n` berisi issue anaknya;
  GitHub menghitung progresnya sendiri. Kebutuhan yang melayani dua journey muncul di dua epic; issue-nya tetap dibuat sekali.
- Taruh tiap epic di board (bila ada): `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh <owner> <nomor> <epic> Backlog`. Statusnya selanjutnya dihitung dari anak oleh `board.sh <owner> <nomor> --sync` (anak berjalan = In progress, semua anak selesai = In review, siap ditutup owner; owner yang menutup = Done).
- Catat `J-ID → #epic` di "Peta issue" PRD. Rencana epic ditampilkan bersama tabel issue di langkah 7 (satu persetujuan).
- **Proyek yang sudah berjalan**: membuat epic tidak mengedit issue yang sudah ada: issue lama hanya dirujuk dari epic (perubahan lain pada issue lama hanya lewat audit 2c dengan persetujuan owner; yang berlabel in-progress atau ber-assignee dilewati).
  Issue yang tidak cocok dengan journey mana pun dikumpulkan di epic `[J0] Unassigned`, tidak dipaksakan masuk journey.
- NFR (`N-ID`) yang berlabel `needs-security`/`needs-perf` mengikuti aturan label biasa di langkah 6.
- Epic bukan pekerjaan: orkestrator, autopilot, resume, dan laporan rilis melewatinya. Owner menutup epic saat semua anak selesai.

## Laporan akhir
Jumlah issue, per gelombang, yang `needs-principal`, dan asumsi yang dibuat. Maks 12 baris.
Akhiri dengan saran: jalankan `/aicrew:orchestrate` di **sesi baru** (semua konteks sudah ada di berkas),
supaya konteks diskusi tidak terbaca ulang di setiap panggilan eksekusi.
