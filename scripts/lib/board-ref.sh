#!/usr/bin/env bash
# aicrew board-ref: baca "Kanban board: GitHub Project <owner>/<nomor>" dari teks WORKFLOW di stdin -> "<owner> <nomor>"; none/placeholder/tanpa baris = kosong (nonaktif).
board_ref() { sed -En 's/^[- ]*Kanban board: *GitHub Project +([A-Za-z0-9_.-]+)\/([0-9]+).*/\1 \2/p' | head -1; }
