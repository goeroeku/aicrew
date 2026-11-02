# WORKFLOW — {{nama project}}

Dibuat oleh `aicrew:kickoff`. Keputusan project ini; menimpa bawaan aicrew.

## Keputusan owner
- Profile: {{light | standard | full}}
- Backend: {{github | gitlab}} — repo: {{owner/nama}}
- Active roles: {{daftar}}
- PRD: {{docs/PRD.md}} — Status PRD: {{disetujui | belum}}
- Existing code: {{yes | no}} (ya → breakdown menjalankan audit status)
- Worktree: {{dibuat orkestrator di samping repo (../<repo>-wt-N) | disiapkan manual / Orca}}
- Worktree base: {{path absolut, mis. di dalam workspace Orca | kosong = di samping repo}}. `install-permissions.sh` mengisi izin baca worktree dari sini.
- Kanban board: {{none | GitHub Project <owner>/<nomor>, status bawaan: Backlog, Ready, In progress, In review, Done}}
- Done card: {{owner | agent-after-merge}}. Bawaan: owner. `agent-after-merge` (autopilot): orkestrator memindahkan kartu ke Done
  setelah merge terverifikasi (`pr-merge-check.sh --after`) pada mode merge `agent-after-qa`; berlaku hanya bila Kanban board aktif.
- needs-principal: {{owner | principal-auto}}. Bawaan: owner (semua tingkat dieskalasi ke owner). `principal-auto`: hanya TINGKAT 1 diputuskan
  agen `aicrew-principal` (butuh role principal aktif); tingkat 2 tetap owner. Keputusan otomatis diberi label `auto-decision` dan dimuat di laporan rilis.
- Risiko (`risk:*`, diberi breakdown): L0 = dokumen/tes/refactor tanpa efek perilaku; L1 = perilaku biasa; L2 = auth, uang, data pribadi, migrasi, infra, atau sulit dibalik.
- `epic` = satu issue per journey (daftar centang issue anak). Bukan pekerjaan: agen dan skrip melewatinya; owner menutupnya saat semua anak selesai.
- Integrated label: {{integrated (default) | nama lain}}. Auto-decision label: {{auto-decision (default) | nama lain}}. Dibaca oleh `scripts/label.sh`.
- Discovery label: {{discovery phase:discovery (default) | nama lain}}. Unsplit epic label: {{unsplit (default) | nama lain}}. Dibaca oleh `scripts/label.sh`; epic hanya mencapai In review bila ada anak bukan-discovery.
- Awaiting-release label: {{awaiting-release (default) | nama lain}}. Dipasang pada issue yang PR-nya menambah workflow terjadwal (`schedule`/`workflow_dispatch`) atau `dependabot.yml` ke cabang non-bawaan: GitHub baru mengaktifkannya dari cabang bawaan. Issue tetap terbuka sampai berkasnya ada di cabang bawaan. Dibaca oleh `scripts/label.sh`.
- No-parent label: {{no-parent (default) | nama lain}}. Issue terbuka berlabel ini sengaja di luar epic (mis. payung tindak lanjut) dan dilewati `epic-link.sh --check`.
- Close issues after integration merge: {{no (default) | yes}}. GitHub hanya menutup issue lewat merge ke cabang bawaan, sehingga progres sub-issue epic tertahan 0% selama integrasi belum ke `main`; `yes` = `board.sh --sync` menutup issue berlabel integrated (kecuali `epic`).
- Clean up after merge: {{yes (default) | report | no}}. Setelah merge terverifikasi, `scripts/cleanup.sh --after-merge` menghapus worktree `<repo>-wt-<n>` dan cabang `issue-<n>` (lokal dan remote) yang TERBUKTI ter-merge (leluhur cabang bawaan/integrasi, atau PR merged dengan ujung yang sama), tanpa `--force`, dan mencetak SHA ujung supaya dapat dipulihkan. `report` hanya mencetak; `no` melewati. Cabang bernama lain tidak pernah dihapus otomatis: jalankan `scripts/cleanup.sh` (laporan) lalu `--apply`. Baris yang hilang di pemasangan lama = `yes`. Perhatian: worktree `<repo>-wt-<n>` dihapus beserta file yang di-ignore di dalamnya (mis. `.env` lokal, `node_modules`); `git worktree remove` tanpa paksa hanya menolak perubahan yang belum ter-commit atau file untracked. Pilih `report` bila ada file semacam itu yang masih dibutuhkan.
- Release notes: {{CHANGELOG.md | external | none (bawaan)}}. `CHANGELOG.md` = `scripts/release-notes.sh` menyusun bagian per versi (Keep a Changelog) dari baris `Release note:` di badan PR, saat rilis; hanya baris bertanda yang masuk, dan Security hanya dari baris `Release note: Security - ...`. `external` (release-please, changesets, dll.) = aicrew tidak menyentuh berkasnya. `none` = tidak membuat apa pun. Disarankan `CHANGELOG.md` untuk proyek baru.
- CVE check: {{yes (default) | no}}. `yes`: PR yang menyentuh `package-lock.json`, `go.mod`, atau `requirements*.txt` diperiksa ke OSV oleh `scripts/pr-merge-check.sh` (hanya paket baru/berubah; HIGH, CRITICAL, atau tanpa peringkat memblokir kecuali waiver owner `(cve)`; OSV mati = tolak). `no` melewati pemeriksaan dengan satu peringatan. Audit seluruh repo: skill `cve-audit`. Yang dikirim ke OSV hanya ekosistem, nama paket, dan versi.
- Private packages: {{pola dipisah koma, mis. @perusahaan/*, git.perusahaan.com/tim | kosong}}. Paket yang cocok tidak pernah dikirim ke OSV dan dilaporkan "tidak diperiksa" (bukan aman). Sumber lain yang dibaca otomatis: `GOPRIVATE` (Go) dan scope `.npmrc` proyek yang dipetakan ke registry non-publik (npm). Pola dibaca dari cabang tujuan, jadi merge dulu PR yang hanya berisi baris ini.
- Artifact language (kode, komentar, commit, label, nama cabang/database): {{English (default) | other language, only at the owner's request}}
- Track `docs/` in git: {{yes | no (ignored, intentional)}}

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
`role:*`, `stack:*`, `phase:*`, `needs-principal`, `needs-security`, `needs-perf`, `auto-decision`, `risk:L0`, `risk:L1`, `risk:L2`, `epic`, `bug`, `enhancement`, `in-progress`, `in-review`, `integrated`
(GitLab: pakai scoped label `role::qa`, dst.)

## Gerbang persetujuan owner
1. PRD disetujui sebelum breakdown.
2. PR/MR pertama diperiksa owner (dilonggarkan setelah percaya).
3. Integration branch: {{name, e.g. feature-x-integration | none}}. Issue yang saling bergantung menumpuk di sini,
   bukan di `main`. Merge PR to integration branch: {{owner | agent-after-qa}}. Bawaan: owner (persetujuan manual).
   `agent-after-qa`: agen merge sendiri hanya bila suite penuh hijau, `aicrew-qa` lulus (dan `aicrew-security`
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

## Temporary grants
Izin sementara dari owner untuk gerbang `pr-merge-check.sh --auto`. Hanya satu jenis: `scope=merge; risk=L2`. Tulis hanya sebagai owner; teks bebas "izin sementara" tidak berlaku.
Bentuk satu baris (kolom 0, di bagian ini saja): `- Grant: scope=merge; risk=L2; branch=<cabang integrasi>; expires=<YYYY-MM-DDTHH:MM:SS+07:00 atau Z>; note=<teks, terakhir, tanpa titik koma>`.
Maksimum 7 hari dari saat dibaca; cabang bawaan tidak boleh; PR yang menyentuh berkas ini tidak di-merge otomatis. Contoh tidak sah (sengaja, tidak berlaku):
`- Grant: scope=merge; risk=L2; branch=integration; expires=EXAMPLE`

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
