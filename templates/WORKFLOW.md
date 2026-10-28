# WORKFLOW — {{nama project}}

Dibuat oleh `aicrew:kickoff`. Keputusan project ini; menimpa bawaan aicrew.

## Keputusan owner
- Profil: {{ringan | standar | penuh}}
- Backend: {{github | gitlab}} — repo: {{owner/nama}}
- Role aktif: {{daftar}}
- PRD: {{docs/PRD.md}} — Status PRD: {{disetujui | belum}}
- Kode ada: {{ya | tidak}} (ya → breakdown menjalankan audit status)
- Worktree: {{dibuat orkestrator di samping repo (../<repo>-wt-N) | disiapkan manual / Orca}}
- Board kanban: {{tidak ada | GitHub Project <owner>/<nomor>, status bawaan: Backlog, Ready, In progress, In review, Done}}
- Kartu Done: {{owner | agen-setelah-merge}}. Bawaan: owner. `agen-setelah-merge` (autopilot): orkestrator memindahkan kartu ke Done
  setelah merge terverifikasi (`pr-merge-check.sh --after`) pada mode merge `agen-setelah-QA`; berlaku hanya bila Board kanban aktif.
- needs-principal: {{owner | principal-auto}}. Bawaan: owner (semua tingkat dieskalasi ke owner). `principal-auto`: hanya TINGKAT 1 diputuskan
  agen `aicrew-principal` (butuh role principal aktif); tingkat 2 tetap owner. Keputusan otomatis diberi label `keputusan-otomatis` dan dimuat di laporan rilis.
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
`role:*`, `stack:*`, `phase:*`, `needs-principal`, `keputusan-otomatis`, `bug`, `enhancement`, `in-progress`, `in-review`, `di-integrasi`
(GitLab: pakai scoped label `role::qa`, dst.)

## Gerbang persetujuan owner
1. PRD disetujui sebelum breakdown.
2. PR/MR pertama diperiksa owner (dilonggarkan setelah percaya).
3. Cabang integrasi: {{nama, mis. fitur-x-integrasi | tidak ada}}. Issue yang saling bergantung menumpuk di sini,
   bukan di `main`. Merge PR ke cabang integrasi: {{owner | agen-setelah-QA}}. Bawaan: owner (persetujuan manual).
   `agen-setelah-QA`: agen merge sendiri hanya bila suite penuh hijau, `aicrew-qa` lulus (dan `aicrew-security`
   untuk perubahan sensitif), tanpa `needs-principal`. Izin Bash terpasang di
   {{berkas settings, mis. `.claude/settings.local.json`: `Bash(gh pr merge:*)`}} (izin lewat chat tidak berlaku).
4. Merge cabang integrasi / PR ke `main` dan pindah ke Done: {{owner | aturan otomatis}}. Bawaan: owner.
   Merge ke `main` memicu: {{tidak ada | nama workflow (mis. deploy)}}.

## Daftar periksa rilis
Dijalankan pada tahap penutup, sebelum PR `integrasi → main` dibuka. Item boleh diganti per project; `release-report.sh` mencetaknya sebagai kotak kosong untuk diisi agen.
- Build bersih di salinan segar
- Aplikasi dijalankan lokal; smoke test lulus (UI: screenshot dibaca)
- aicrew-security: auth, input, rahasia, dependensi
- Tidak ada rahasia di repo
- Runbook singkat: cara jalan, konfigurasi, rollback
- Setiap kriteria PRD dicentang dengan perintah dan hasilnya

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
qa=haiku · security=sonnet · devops=sonnet · ui-ux=sonnet
