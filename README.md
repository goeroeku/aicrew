# aiCrew

<p align="center"><img src="assets/banner.png" alt="aiCrew, bagian dari AICosystem: alur kerja project dari ide sampai calon rilis" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="Lisensi: MIT" src="https://img.shields.io/badge/lisensi-MIT-38bdf8?style=flat-square"></a>
  <a href="https://github.com/goeroeku/aicrew/actions/workflows/tests.yml"><img alt="Tes" src="https://github.com/goeroeku/aicrew/actions/workflows/tests.yml/badge.svg?branch=main"></a>
  <img alt="Claude Code plugin" src="https://img.shields.io/badge/Claude%20Code-plugin-a78bfa?style=flat-square">
  <img alt="AICosystem" src="https://img.shields.io/badge/AIC-osystem-0ea5e9?style=flat-square">
  <img alt="Gerbang default manual" src="https://img.shields.io/badge/gerbang-default%20manual-34d399?style=flat-square">
</p>

> [!NOTE]
> **aiCrew** adalah bagian dari **AICosystem**.

Plugin Claude Code untuk alur kerja project dari ide sampai calon rilis: **kickoff → PRD → breakdown ke issue → eksekusi paralel oleh role**
(principal, senior-coder, qa, security, devops, ui-ux), masing-masing dengan model yang sesuai bobot tugasnya. Dokumen dan skill berbahasa Indonesia.

Prinsip: **setiap gerbang bawaannya manual (owner memutuskan)**, dengan opsi yang bisa diset ke otomatis di `docs/WORKFLOW.md` project Anda.

## 🧭 Alur

```mermaid
flowchart TD
  A["kickoff<br/>docs/WORKFLOW.md"] --> B["prd"]
  B --> C["breakdown<br/>issue, label, gelombang"]
  C --> D["orchestrate<br/>worktree per issue"]
  D --> E{"QA lulus?"}
  E -- tidak --> D
  E -- ya --> F["merge ke cabang integrasi<br/>kartu Done"]
  F --> G["calon rilis<br/>release-report"]
  G --> H["PR integrasi ke main<br/>owner yang merge"]
  classDef biru fill:#0c4a6e,stroke:#38bdf8,color:#e0f2fe
  classDef cerah fill:#0369a1,stroke:#7dd3fc,color:#f0f9ff
  classDef ungu fill:#6d28d9,stroke:#c4b5fd,color:#f5f3ff
  classDef hijau fill:#047857,stroke:#6ee7b7,color:#ecfdf5
  class A,B,C biru
  class D cerah
  class E ungu
  class F,G hijau
  class H cerah
```

Contoh keluaran nyata (dipotong) dari project uji `aicrew-uji`. Log autopilot untuk satu issue yang selesai sendiri:
```
2026-10-28 11:50:55 putaran 1: 1 issue terbuka (0 needs-principal)
2026-10-28 11:53:22 autopilot: semua issue selesai (putaran 1)
```
Laporan calon rilis (`release-report.sh`):
```
# Laporan calon rilis: uji-integrasi -> main
**Vonis fakta: SIAP**
## Suite penuh (salinan segar uji-integrasi)
`node --test` -> exit 0: ℹ tests 14 ℹ pass 14 ℹ fail 0
## PR ter-merge ke uji-integrasi
- #17 Tes regresi: pesan kesalahan CLI untuk operasi tak dikenal
- #15 README: bagian Batasan
```

## 📦 Prasyarat
- Claude Code, `git`, `jq`, dan `gh` (sudah login; backend GitHub). GitLab (`glab`) hanya sebagian didukung.
- Opsional: `codex` (senior-coder mengerjakan kode lewat Codex; tanpanya dipakai subagen Claude), scope `gh` `project` (kanban), `caffeinate` (macOS, menahan Mac tetap bangun saat autopilot).

## 🚀 Pasang dan coba
Tanpa clone atau fork (Claude Code mengunduh repo ini sendiri sebagai marketplace):
```
claude plugin marketplace add goeroeku/aicrew
claude plugin install aicrew@aicrew
```
Di dalam sesi Claude Code bentuknya `/plugin marketplace add goeroeku/aicrew` lalu `/plugin install aicrew@aicrew`. Bila SSH ke GitHub belum diatur,
pakai URL penuh: `claude plugin marketplace add https://github.com/goeroeku/aicrew.git`. Terpasang: 4 skill, 7 agen, 1 hook; beban tetap sekitar 380 token per sesi.
Mencoba dari salinan lokal tanpa memasang: `claude --plugin-dir /path/ke/aicrew`.

**Unduh tanpa marketplace:** setiap rilis (tag `vX.Y.Z`) di halaman Releases berisi `aicrew-X.Y.Z.zip`, `.tar.gz`, dan `SHA256SUMS`. Verifikasi lalu pakai:
```
shasum -a 256 -c SHA256SUMS
unzip aicrew-X.Y.Z.zip
claude --plugin-dir ./aicrew-X.Y.Z
```

Lalu di project Anda: `/aicrew:kickoff` (tulis `docs/WORKFLOW.md`), `/aicrew:prd`, `/aicrew:breakdown`, `/aicrew:orchestrate`.

## 🎛️ Opsi otomatis (semuanya bawaan manual)
| Gerbang | Bawaan | Opsi |
|---|---|---|
| Merge PR ke cabang integrasi | owner | `agen-setelah-QA` (suite hijau + QA lulus + tanpa `needs-principal`) |
| Kartu Done di board | owner | `agen-setelah-merge` |
| `needs-principal` tingkat 1 (keputusan desain dalam batas PRD) | owner | `principal-auto` (dicatat sebagai `keputusan-otomatis`) |
| `needs-principal` tingkat 2 (bertentangan PRD, auth/uang/data pribadi, sulit dibalik) | owner | tidak ada opsi otomatis |
| Merge ke `main` | owner | belum ada opsi otomatis |

## 🤖 Autopilot (berhari-hari, tahan limit)
`bash scripts/autopilot.sh [--sleep 1800] [--max-total N]` dari akar repo project: menjalankan `claude -p` dengan skill orchestrate secara berulang
(sesi baru tiap putaran; state ada di GitHub dan `.aicrew/`), tidur lalu mencoba lagi saat kena limit, dan berhenti saat selesai (exit 0),
error beruntun (1), buntu (2), hanya `needs-principal` yang tersisa (3), atau batas total (4). Log: `.aicrew/autopilot.log`.

> [!IMPORTANT]
> Sesi `-p` tidak bisa meminta persetujuan, jadi izin tool harus dipasang lebih dulu. Daftar minimal: `templates/autopilot-permissions.json`;
> pasang ke `.claude/settings.local.json` project dengan `bash scripts/install-permissions.sh` (menggabungkan, tidak menimpa; mengisi path milik Anda).
> Jangan memakai `--dangerously-skip-permissions`. Argumen tambahan lewat `AICREW_CLAUDE_ARGS` (mis. `--max-budget-usd 3`).
> Pola pesan limit adalah dugaan yang belum diuji dengan limit sungguhan; bila meleset, putaran dihitung sebagai error dan autopilot berhenti dengan aman setelah 3 kali.

## 📋 Calon rilis
`bash scripts/release-report.sh --test-cmd "<perintah tes penuh>" --dry-run` menulis `.aicrew/release-report.md`: vonis fakta SIAP/BELUM SIAP
(suite di salinan segar, PR tanpa bukti, issue belum di-integrasi, `needs-principal`). `--buka-pr` (tanpa `--dry-run`) membuka PR integrasi → main bila SIAP. Tidak pernah merge.

## 🗂️ Kanban (opsional)
`scripts/board-init.sh` membuat GitHub Project, menautkannya ke repo, dan menyeragamkan status; `scripts/board.sh` menggeser kartu. Perlu scope `gh` `project`.

## 🔔 Notifikasi dan data yang dikirim (opsional)
Secara bawaan plugin ini **tidak mengirim data apa pun ke luar mesin Anda**. Satu-satunya jaringan keluar adalah hook `Notification` (`scripts/notify.sh`),
dan hanya aktif bila **Anda sendiri** mengisi token bot dan chat ID Telegram milik Anda: lewat pengaturan plugin (`tg_token`, `tg_chat`; token disimpan di penyimpanan aman Claude Code) atau variabel lingkungan `AICREW_TG_TOKEN` dan `AICREW_TG_CHAT`. Jangan simpan token di berkas repo.
Bila aktif, ia mengirim ke `api.telegram.org` satu pesan berisi teks notifikasi (mis. "issue #N butuh keputusan") dan nama folder project. Tidak ada isi kode, issue, atau percakapan.
Selain itu, skrip memanggil `gh` dan `git` atas nama Anda ke repositori project Anda sendiri. Rincian: [`PRIVACY.md`](PRIVACY.md).

## ⚠️ Peringatan

> [!WARNING]
> Plugin ini menjalankan kode, membuat worktree, `git push`, membuka dan (bila Anda mengizinkan) me-merge PR atas nama Anda, dan dapat berjalan tanpa pengawasan.
> Tinjau daftar izin sebelum memasangnya, mulai dari project kecil, dan pasang batas biaya. Diberikan apa adanya, tanpa jaminan (lihat `LICENSE`).

## 🧪 Tes
`bash tests/run.sh` (offline; butuh bash dan jq). Dijalankan juga di GitHub Actions.

## 📄 Lisensi dan kredit
Berlisensi **MIT**: bebas dipakai, diubah, dan dibagikan. Hak cipta (c) 2026 goeroeku. aiCrew adalah bagian dari AICosystem. Salinan atau turunan wajib mempertahankan pernyataan hak cipta dan teks lisensi ([`LICENSE`](LICENSE)).
