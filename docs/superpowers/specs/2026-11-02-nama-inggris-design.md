# Nama teknis berbahasa Inggris (issue #55)

## Maksud

aiCrew adalah plugin; permukaan teknisnya harus Inggris: nama skrip, opsi baris perintah, kunci dan nilai di
`docs/WORKFLOW.md`, nama label bawaan. Teks percakapan, pesan skrip, laporan, dan isi skill/agen/templat boleh tetap
Bahasa Indonesia (bahasa kerja), tetapi setiap perintah teknis di dalamnya ditulis dalam Inggris.
Arahan owner: "perintah2 nya harus inggris, tapi report chat / interaksi dengan user boleh Indonesia".

## Tujuan / bukan tujuan

Tujuan: nama kanonik Inggris di semua permukaan teknis; pemasangan lama tetap jalan; rilis 1.1.0 (tambahan, kompatibel).
Bukan tujuan: menerjemahkan pesan skrip, prosa skill/agen/templat, atau riwayat docs/superpowers.
Anti-tujuan: merusak WORKFLOW.md, label, atau perintah yang sudah dipakai proyek (mis. Nexora, pin 0.1.1).

## Keputusan (usulan saya, owner bisa menimpa)

1. **Kompatibel mundur.** Nama Indonesia tetap diterima sebagai alias usang; nama Inggris jadi kanonik di dokumentasi,
   templat, dan contoh. Penghapusan alias = rilis mayor, bukan bagian ini. Alias usang tidak memunculkan peringatan
   baru di keluaran skrip (menghindari kebisingan); kebijakan dicatat di README bagian Stability.
2. **Kunci WORKFLOW.md dinormalkan di satu tempat:** `scripts/workflow.sh` memetakan kunci dan nilai alias ke bentuk
   Inggris sebelum dibaca skrip lain. Skrip lain hanya mengenal bentuk Inggris (hapus regex Indonesia dari skrip).
3. **Skrip berganti nama** dengan pembungkus lama (`exec` ke nama baru) agar izin, skill, dan pemanggil lama tetap jalan.
4. **Opsi**: nama Inggris kanonik; nama Indonesia diterima sebagai alias di parser opsi yang sama.
5. **Label bawaan**: nama Inggris kanonik untuk proyek baru. Proyek lama yang tidak menulis barisnya dan sudah punya
   issue berlabel nama lama tetap dikenali: pembaca label menerima nama lama maupun baru sebagai "sama" (satu daftar alias).
6. Versi 1.1.0. CHANGELOG memuat `Changed` dan `Behavior change` untuk nama kanonik baru.

## Tabel pemetaan

Skrip: `alur-terjadwal.sh` → `scheduled-workflow.sh`; `menunggu-rilis.sh` → `awaiting-release.sh`; `terintegrasi.sh` → `integrated.sh`.

Opsi: `--versi` → `--version`; `--sejak` → `--since`; `--tanggal` → `--date`; `--tulis` → `--write`; `--ekstrak` → `--extract`;
`--buka-pr` → `--open-pr`; `--cek` → `--check`; `--hitung` → `--count`; `--parse-badan` → `--parse-body`;
`--setelah-merge` → `--after-merge`; `--tandai` → `--mark`.
(`--check` sudah dipakai di `epic-link.sh`; `resume.sh`/`awaiting-release.sh` memakai `--cek`: alias `--cek` tetap.)

Kunci: Profil→Profile; Role aktif→Active roles; Kode ada→Existing code; Basis worktree→Worktree base; Board kanban→Kanban board;
Kartu Done→Done card; Label integrasi→Integrated label; Label keputusan otomatis→Auto-decision label; Label discovery→Discovery label;
Label epic belum dipecah→Unsplit epic label; Label menunggu rilis→Awaiting-release label; Label tanpa induk→No-parent label;
Tutup issue setelah merge integrasi→Close issues after integration merge; Bersihkan setelah merge→Clean up after merge;
Pemeriksaan CVE→CVE check; Paket privat→Private packages; Cabang integrasi→Integration branch; Bahasa artefak→Artifact language;
"Berkas docs/ dilacak git"→Track docs/ in git; Catatan rilis→Release notes (sudah Inggris sejak 0.11.1).

Nilai: ringan/standar/penuh→light/standard/full; ya/tidak→yes/no; laporkan→report; "tidak ada"→none;
agen-setelah-QA→agent-after-qa; agen-setelah-merge→agent-after-merge (`owner`, `principal-auto` tetap).

Label: di-integrasi→integrated; keputusan-otomatis→auto-decision; belum-dipecah→unsplit; menunggu-rilis→awaiting-release;
tanpa-induk→no-parent. (`discovery phase:discovery`, `needs-*`, `risk:*`, `epic` sudah Inggris.)

## Kriteria selesai (dapat diperiksa mesin)

- Tes: tiap alias lama dan nama baru menghasilkan perilaku sama (satu tes per kelompok: skrip, opsi, kunci, nilai, label).
- Tes penjaga: tidak ada kunci/opsi/nama skrip Indonesia dari tabel di templat, README, SKILL.md, agen (kecuali bagian "alias usang").
- `bash tests/run.sh` hijau; CI hijau. WORKFLOW.md lama (semua kunci Indonesia) lolos tanpa perubahan di `workflow.sh` dan skrip pembaca.
- README: Configuration table memakai kunci Inggris; bagian Stability menyatakan kebijakan alias.

## Putusan setelah builder-check (terverifikasi di kode)

- Empat skrip membaca WORKFLOW.md tanpa `workflow.sh`: `install-permissions.sh:16`, `cve-private.sh:14`, `pr-merge-check.sh:87-137` (berkas via REST), `release-report.sh:14`; `workflow.sh:6` membaca kunci dari berkas lokal mentah. Maka keputusan 2 diganti:
  pemeta alias satu-satunya adalah fungsi `scripts/lib/workflow-normalize.sh` (di-source, atau `workflow.sh --normalize` membaca stdin); `workflow.sh` memakainya, dan keempat skrip itu memanggilnya sebelum `sed`/`grep`.
- Pemeta nilai hanya menyentuh token pertama setelah kunci (bukan prosa); `ya`/`tidak` dipetakan hanya untuk kunci yang bernilai ya/tidak.
- Bentuk kanonik nilai mode huruf kecil: `agent-after-qa`, `agent-after-merge`; JSON izin (`autopilot-permissions.json:87`) memakai kunci itu, dan nilai dinormalkan sebelum `jq`.
- Tabel kunci ditambah `Merge PR ke cabang integrasi` → `Merge PR to integration branch`.
- Label: `label.sh <nama> --all` mencetak kanonik dan alias; resume/board/autopilot/cleanup mencocokkan salah satunya.
- Pesan skrip yang mengutip kunci/opsi (`cve-check.sh:68`, `pr-merge-check.sh:139`, `board.sh:66`) menyebut bentuk Inggris (perintah teknis di dalam pesan = Inggris).
- Tes lama yang mengunci nama Indonesia (≈69 baris skrip/opsi, ≈55 baris label) dibiarkan sebagai tes alias; tes baru untuk nama Inggris; tes penjaga di commit terakhir.
- `Cabang integrasi: tidak ada` → `none` dicatat, tanpa konflik fungsional dengan `Release notes: none`.

## Diserahkan ke pembangun

Struktur pemetaan di `workflow.sh`, cara berbagi daftar alias antar skrip, urutan commit, dan isi pembungkus skrip lama.
