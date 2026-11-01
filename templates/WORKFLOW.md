# WORKFLOW — {{nama project}}

Dibuat oleh `aicrew:kickoff`. Keputusan project ini; menimpa bawaan aicrew.

## Keputusan owner
- Profil: {{ringan | standar | penuh}}
- Backend: {{github | gitlab}} — repo: {{owner/nama}}
- Role aktif: {{daftar}}
- PRD: {{docs/PRD.md}} — Status PRD: {{disetujui | belum}}
- Kode ada: {{ya | tidak}} (ya → breakdown menjalankan audit status)
- Worktree: {{dibuat orkestrator di samping repo (../<repo>-wt-N) | disiapkan manual / Orca}}
- Basis worktree: {{path absolut, mis. di dalam workspace Orca | kosong = di samping repo}}. `install-permissions.sh` mengisi izin baca worktree dari sini.
- Board kanban: {{tidak ada | GitHub Project <owner>/<nomor>, status bawaan: Backlog, Ready, In progress, In review, Done}}
- Kartu Done: {{owner | agen-setelah-merge}}. Bawaan: owner. `agen-setelah-merge` (autopilot): orkestrator memindahkan kartu ke Done
  setelah merge terverifikasi (`pr-merge-check.sh --after`) pada mode merge `agen-setelah-QA`; berlaku hanya bila Board kanban aktif.
- needs-principal: {{owner | principal-auto}}. Bawaan: owner (semua tingkat dieskalasi ke owner). `principal-auto`: hanya TINGKAT 1 diputuskan
  agen `aicrew-principal` (butuh role principal aktif); tingkat 2 tetap owner. Keputusan otomatis diberi label `keputusan-otomatis` dan dimuat di laporan rilis.
- Risiko (`risk:*`, diberi breakdown): L0 = dokumen/tes/refactor tanpa efek perilaku; L1 = perilaku biasa; L2 = auth, uang, data pribadi, migrasi, infra, atau sulit dibalik.
- `epic` = satu issue per journey (daftar centang issue anak). Bukan pekerjaan: agen dan skrip melewatinya; owner menutupnya saat semua anak selesai.
- Label integrasi: {{di-integrasi (bawaan) | nama lain}}. Label keputusan otomatis: {{keputusan-otomatis (bawaan) | nama lain}}. Dibaca oleh `scripts/label.sh`.
- Label discovery: {{discovery phase:discovery (bawaan) | nama lain}}. Label epic belum dipecah: {{belum-dipecah (bawaan) | nama lain}}. Dibaca oleh `scripts/label.sh`; epic hanya mencapai In review bila ada anak bukan-discovery.
- Label menunggu rilis: {{menunggu-rilis (bawaan) | nama lain}}. Dipasang pada issue yang PR-nya menambah workflow terjadwal (`schedule`/`workflow_dispatch`) atau `dependabot.yml` ke cabang non-bawaan: GitHub baru mengaktifkannya dari cabang bawaan. Issue tetap terbuka sampai berkasnya ada di cabang bawaan. Dibaca oleh `scripts/label.sh`.
- Label tanpa induk: {{tanpa-induk (bawaan) | nama lain}}. Issue terbuka berlabel ini sengaja di luar epic (mis. payung tindak lanjut) dan dilewati `epic-link.sh --check`.
- Tutup issue setelah merge integrasi: {{tidak (bawaan) | ya}}. GitHub hanya menutup issue lewat merge ke cabang bawaan, sehingga progres sub-issue epic tertahan 0% selama integrasi belum ke `main`; `ya` = `board.sh --sync` menutup issue berlabel di-integrasi (kecuali `epic`).
- Bersihkan setelah merge: {{ya (bawaan) | laporkan | tidak}}. Setelah merge terverifikasi, `scripts/cleanup.sh --setelah-merge` menghapus worktree `<repo>-wt-<n>` dan cabang `issue-<n>` (lokal dan remote) yang TERBUKTI ter-merge (leluhur cabang bawaan/integrasi, atau PR merged dengan ujung yang sama), tanpa `--force`, dan mencetak SHA ujung supaya dapat dipulihkan. `laporkan` hanya mencetak; `tidak` melewati. Cabang bernama lain tidak pernah dihapus otomatis: jalankan `scripts/cleanup.sh` (laporan) lalu `--apply`. Baris yang hilang di pemasangan lama = `ya`.
- Pemeriksaan CVE: {{ya (bawaan) | tidak}}. `ya`: PR yang menyentuh `package-lock.json`, `go.mod`, atau `requirements*.txt` diperiksa ke OSV oleh `scripts/pr-merge-check.sh` (hanya paket baru/berubah; HIGH, CRITICAL, atau tanpa peringkat memblokir kecuali waiver owner `(cve)`; OSV mati = tolak). `tidak` melewati pemeriksaan dengan satu peringatan. Audit seluruh repo: skill `cve-audit`. Yang dikirim ke OSV hanya ekosistem, nama paket, dan versi.
- Paket privat: {{pola dipisah koma, mis. @perusahaan/*, git.perusahaan.com/tim | kosong}}. Paket yang cocok tidak pernah dikirim ke OSV dan dilaporkan "tidak diperiksa" (bukan aman). Sumber lain yang dibaca otomatis: `GOPRIVATE` (Go) dan scope `.npmrc` proyek yang dipetakan ke registry non-publik (npm). Pola dibaca dari cabang tujuan, jadi merge dulu PR yang hanya berisi baris ini.
- Bahasa artefak (kode, komentar, commit, label): {{Inggris (bawaan) | bahasa lain, hanya atas permintaan owner}}
- Berkas `docs/` dilacak git: {{ya | tidak (di-ignore, disengaja)}}

## Perintah backend (satu tempat, mudah diganti)
| Aksi | Perintah |
|---|---|
| Buat issue | {{gh issue create | glab issue create}} |
| Ubah label | {{gh issue edit | glab issue update}} |
| Buka PR/MR | {{gh pr create | glab mr create}} |
| Komentar bukti | {{gh pr comment | glab mr note}} |

## Ukuran task
- Satu task = satu hasil yang bisa diamati; ≤ 5 file, ≤ ±200 baris diff.
- Wajib ada kriteria selesai yang bisa dicek mesin. Tanpa itu, kembali ke breakdown.
- Tulis apa dan kenapa, bukan bagaimana (kecuali task berisiko).

## Label
`role:*`, `stack:*`, `phase:*`, `needs-principal`, `needs-security`, `needs-perf`, `keputusan-otomatis`, `risk:L0`, `risk:L1`, `risk:L2`, `epic`, `bug`, `enhancement`, `in-progress`, `in-review`, `di-integrasi`
(GitLab: pakai scoped label `role::qa`, dst.)

## Gerbang persetujuan owner
1. PRD disetujui sebelum breakdown.
2. PR/MR pertama diperiksa owner (dilonggarkan setelah percaya).
3. Cabang integrasi: {{nama, mis. fitur-x-integrasi | tidak ada}}. Issue yang saling bergantung menumpuk di sini,
   bukan di `main`. Merge PR ke cabang integrasi: {{owner | agen-setelah-QA}}. Bawaan: owner (persetujuan manual).
   `agen-setelah-QA`: agen merge sendiri hanya bila suite penuh hijau, `aicrew-qa` lulus (dan `aicrew-security`
   untuk perubahan sensitif, yaitu berlabel `needs-security`; `aicrew-perf` untuk `needs-perf`), tanpa `needs-principal` dan tanpa `risk:L2` (L2 selalu owner; `pr-merge-check.sh --auto` menolaknya). Izin Bash terpasang di
   {{berkas settings, mis. `.claude/settings.local.json`: `Bash(gh pr merge:*)`}} (izin lewat chat tidak berlaku).
4. Merge cabang integrasi / PR ke `main` dan pindah ke Done: {{owner | aturan otomatis}}. Bawaan: owner.
   Merge ke `main` memicu: {{tidak ada | nama workflow (mis. deploy)}}.

## Daftar periksa rilis
Dijalankan pada tahap penutup, sebelum PR `integrasi → main` dibuka. Item boleh diganti per project; `release-report.sh` mencetaknya sebagai kotak kosong untuk diisi agen.
- Build bersih di salinan segar
- Aplikasi dijalankan lokal; smoke test lulus (UI: screenshot dibaca)
- aicrew-security: auth, input, rahasia, dependensi; hardening dan log audit untuk `needs-security`
- aicrew-perf: anggaran I/O, config default, uji beban di server nyata (angka, bukan perkiraan)
- Tidak ada rahasia di repo
- Runbook singkat: cara jalan, konfigurasi, rollback
- Setiap kriteria PRD dicentang dengan perintah dan hasilnya

## Batas perangkat keras
Diisi saat kickoff. "tidak diketahui" = belum diukur; `aicrew-perf` tidak boleh menyatakan klaim kapasitas `lulus` bila batas yang relevan tidak diketahui.
- IOPS disk (tulis/baca): {{angka | tidak diketahui}}
- RAM host dan batas container: {{angka | tidak diketahui}}
- Tier/jenis volume dan opsi mount (mis. `discard`): {{nilai | tidak diketahui}}
- Batas lain (koneksi DB, bandwidth, CPU): {{nilai | tidak diketahui}}

## Aturan berhenti (agen menandai issue, lanjut ke task lain, owner dikabari)
- Label `needs-principal` (dua tingkat): (1) keputusan desain di dalam batas PRD (skema data, bentuk API internal,
  ambang) → principal memutuskan hanya bila `needs-principal: principal-auto`, selain itu owner; owner meninjau di PR/laporan rilis; (2) bertentangan dengan PRD/non-tujuan, auth, uang, data
  pribadi, atau sulit dibalik → eskalasi ke owner, jangan diputuskan sendiri. Ragu → eskalasi.
- Dua kali gagal pada issue yang sama.
- Persyaratan ambigu atau bertentangan.
- Perlu mengubah tes yang ada atau menambah dependensi.
- Batas iterasi/biaya tercapai.

## Batas
- Paralel maksimum: {{3}}
- Iterasi per sesi: {{20}}
- Gagal berturut-turut per issue: 2

## Bukti selesai (komentar di PR/MR)
Kriteria selesai (centang) · tes: perintah + hasil · perubahan utama `file:baris` ·
screenshot (UI) · yang dilewati / tidak terverifikasi.

## Notifikasi (opsional)
Telegram: set `AICREW_TG_TOKEN` dan `AICREW_TG_CHAT` (ID chat owner saja) di lingkungan shell, jangan di berkas repo.
Satu arah (keluar); kendali dari HP lewat Remote Control, bukan bot.

## Model per role
principal=opus (hanya `needs-principal`) · senior-coder=codex jika ada, else sonnet ·
qa=haiku · security=sonnet · perf=sonnet · devops=sonnet · ui-ux=sonnet
