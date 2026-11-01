# Sinkronisasi kartu kanban oleh kode (issue #69)

## Maksud

Papan kanban harus mencerminkan keadaan kerja tanpa bergantung pada model. Sekarang `autopilot.sh` tidak memanggil `board.sh` sama sekali
(terverifikasi: 0 referensi); pemindahan kartu hanya instruksi di skill `orchestrate`. `board.sh --sync` hanya mengurus epic, menutup issue
`integrated`, dan memindahkan issue yang tertutup ke Done. Akibatnya kartu task tidak pernah ke Ready, In progress, atau In review; hanya epic yang bergerak
(laporan dari run Nexora, 2026-11-02; Nexora memakai pemantau sementara `board-watch.sh` dengan pemetaan yang sama sebagai acuan).

## Tujuan / bukan tujuan

Tujuan: satu pemetaan tertulis dan teruji (label, PR, worktree, blocker → status kartu) di kode; autopilot memanggilnya otomatis; dilewati dengan alasan, bukan menebak.
Bukan tujuan: membuat papan (sudah `board-init.sh`), logika epic (sudah ada di `board.sh --sync`), nama status kustom, GitLab.
Anti-tujuan: papan menjadi sumber kebenaran (label tetap sumber), kartu mundur diam-diam, atau panggilan GraphQL yang menghabiskan batas.

## Pemetaan (usulan; label tetap sumber kebenaran)

Urutan evaluasi per issue terbuka bukan-epic, berkartu di papan. Hasil = status tujuan atau `skip:<alasan>`.

| Syarat | Status tujuan |
|---|---|
| berlabel `integrated` (nama dari `label.sh integrated --all`) | skip:integrated |
| lebih dari satu PR merged dari `issue-<n>` | skip:multi-merged-pr |
| PR terbuka bukan draft dari cabang `issue-<n>` | In review |
| label `in-progress`, atau worktree `<repo>-wt-<n>` aktif, atau PR draft dari `issue-<n>` | In progress |
| ada blocker terbuka (bagian "Blocked by" di badan issue) | Backlog |
| tanpa blocker terbuka dan tanpa `needs-principal` | Ready |
| lainnya (mis. `needs-principal`) | skip:needs-principal |

Aturan arah: kartu hanya maju (Backlog/Ready → In progress → In review). Pengecualian: Backlog ↔ Ready boleh dua arah (blocker muncul/selesai).
Kartu yang sudah di In progress atau In review tidak dimundurkan ke Ready/Backlog oleh sinkronisasi (kemunduran ditangani manusia atau label).
Issue tertutup tetap ditangani `board.sh --sync` yang ada (Done).

## Perilaku

- Perintah baru: `board.sh <owner> <proj> --sync-cards [--dry-run]`; `--dry-run` hanya mencetak perubahan (`#n: Backlog -> Ready`).
- Pemetaan sebagai fungsi murni `card_status` di `scripts/lib/card-status.sh` (masukan: label, jumlah blocker terbuka, status PR, worktree aktif, status kartu saat ini; keluaran: status atau `skip:<alasan>`); teruji tabel.
- Pengumpulan data lewat REST/`ghx.sh` (issue terbuka, PR terbuka, issue tertutup untuk blocker, `git worktree list`); satu pembacaan papan; hanya kartu yang berubah ditulis (selisih).
- Pemeriksaan batas: `gh api rate_limit` graphql sisa < `AICREW_BOARD_MIN_GRAPHQL` (bawaan 1500) → lewati dengan satu baris log, bukan gagal.
- Autopilot: setelah tiap putaran (dan sebelum menunggu owner), bila `WORKFLOW.md` punya `Kanban board: GitHub Project <owner>/<nomor>`, panggil `--sync` lalu `--sync-cards`; tidak fatal (exit != 0 hanya dicatat). Satu baris log per sinkronisasi:
  `board: 3 kartu diubah, 2 dilewati (integrated 1, needs-principal 1), graphql sisa 4200`. Nonaktif dengan `AICREW_BOARD_SYNC=0`.
- Tanpa `Kanban board` aktif: tidak melakukan apa pun.
- Wilayah baru di `docs/WORKFLOW.md`/README: pemetaan ini didokumentasikan satu tempat (README bagian kanban); `skills/orchestrate` merujuknya, tidak mengulangnya.

## Kriteria selesai (teruji)

- Tabel `card_status`: setiap baris pemetaan, aturan arah, draft vs non-draft, multi-merged-pr, alias label lama (`di-integrasi`).
- `--sync-cards --dry-run` dengan `gh` palsu: keluaran selisih tepat; tanpa selisih = nol penulisan.
- Batas GraphQL rendah → dilewati dengan satu baris log, exit 0.
- Autopilot dengan papan aktif memanggil sinkronisasi sekali per putaran; dengan `AICREW_BOARD_SYNC=0` tidak.
- `bash tests/run.sh` hijau; CI hijau.

## Diserahkan ke pembangun

Struktur fungsi, format keluaran dry-run yang tepat, cara membaca "Blocked by" (acuan Nexora: bagian `## Blocked by` di badan issue, nomor `#n`), dan penamaan variabel lingkungan.
