# aicrew

Plugin Claude Code untuk alur kerja project dari ide sampai calon rilis: **kickoff → PRD → breakdown ke issue → eksekusi paralel oleh role**
(principal, senior-coder, qa, security, devops, ui-ux), masing-masing dengan model yang sesuai bobot tugasnya. Dokumen dan skill berbahasa Indonesia.

Prinsip: **setiap gerbang bawaannya manual (owner memutuskan)**, dengan opsi yang bisa diset ke otomatis di `docs/WORKFLOW.md` project Anda.

## Prasyarat
- Claude Code, `git`, `jq`, dan `gh` (sudah login; backend GitHub). GitLab (`glab`) hanya sebagian didukung.
- Opsional: `codex` (senior-coder mengerjakan kode lewat Codex; tanpanya dipakai subagen Claude), scope `gh` `project` (kanban), `caffeinate` (macOS, menahan Mac tetap bangun saat autopilot).

## Pasang dan coba
```
claude --plugin-dir /path/ke/aicrew        # dimuat untuk satu sesi
```
Lalu di project Anda: `/aicrew:kickoff` (tulis `docs/WORKFLOW.md`), `/aicrew:prd`, `/aicrew:breakdown`, `/aicrew:orchestrate`.
Lewat marketplace: `claude plugin marketplace add <akun>/aicrew` lalu pasang plugin `aicrew` (jalur ini belum diuji dari repo GitHub).

## Opsi otomatis (semuanya bawaan manual)
| Gerbang | Bawaan | Opsi |
|---|---|---|
| Merge PR ke cabang integrasi | owner | `agen-setelah-QA` (suite hijau + QA lulus + tanpa `needs-principal`) |
| Kartu Done di board | owner | `agen-setelah-merge` |
| `needs-principal` tingkat 1 (keputusan desain dalam batas PRD) | owner | `principal-auto` (dicatat sebagai `keputusan-otomatis`) |
| `needs-principal` tingkat 2 (bertentangan PRD, auth/uang/data pribadi, sulit dibalik) | owner | tidak ada opsi otomatis |
| Merge ke `main` | owner | belum ada opsi otomatis |

## Autopilot (berhari-hari, tahan limit)
`bash scripts/autopilot.sh [--sleep 1800] [--max-total N]` dari akar repo project: menjalankan `claude -p` dengan skill orchestrate secara berulang
(sesi baru tiap putaran; state ada di GitHub dan `.aicrew/`), tidur lalu mencoba lagi saat kena limit, dan berhenti saat selesai (exit 0),
error beruntun (1), buntu (2), hanya `needs-principal` yang tersisa (3), atau batas total (4). Log: `.aicrew/autopilot.log`.

Sesi `-p` tidak bisa meminta persetujuan, jadi izin tool harus dipasang lebih dulu. Daftar minimal: `templates/autopilot-permissions.json`;
pasang ke `.claude/settings.local.json` project dengan `bash scripts/install-permissions.sh` (menggabungkan, tidak menimpa; mengisi path milik Anda).
Jangan memakai `--dangerously-skip-permissions`. Argumen tambahan lewat `AICREW_CLAUDE_ARGS` (mis. `--max-budget-usd 3`).
Pola pesan limit adalah dugaan yang belum diuji dengan limit sungguhan; bila meleset, putaran dihitung sebagai error dan autopilot berhenti dengan aman setelah 3 kali.

## Calon rilis
`bash scripts/release-report.sh --test-cmd "<perintah tes penuh>" --dry-run` menulis `.aicrew/release-report.md`: vonis fakta SIAP/BELUM SIAP
(suite di salinan segar, PR tanpa bukti, issue belum di-integrasi, `needs-principal`). `--buka-pr` (tanpa `--dry-run`) membuka PR integrasi → main bila SIAP. Tidak pernah merge.

## Kanban (opsional)
`scripts/board-init.sh` membuat GitHub Project, menautkannya ke repo, dan menyeragamkan status; `scripts/board.sh` menggeser kartu. Perlu scope `gh` `project`.

## Peringatan
Plugin ini menjalankan kode, membuat worktree, `git push`, membuka dan (bila Anda mengizinkan) me-merge PR atas nama Anda, dan dapat berjalan tanpa pengawasan.
Tinjau daftar izin sebelum memasangnya, mulai dari project kecil, dan pasang batas biaya. Diberikan apa adanya, tanpa jaminan (lihat `LICENSE`).

## Tes
`bash tests/run.sh` (offline; butuh bash dan jq). Dijalankan juga di GitHub Actions.

## Lisensi dan kredit
MIT. Hak cipta (c) 2026 goeroeku. Salinan atau turunan wajib mempertahankan pernyataan hak cipta dan teks lisensi (`LICENSE`).
