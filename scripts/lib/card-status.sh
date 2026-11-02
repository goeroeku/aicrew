#!/usr/bin/env bash
# aicrew card-status: pemetaan murni keadaan issue -> status kartu kanban (#69). Label tetap sumber kebenaran; papan hanya cermin.
#   card_status <labels (spasi)> <jumlah blocker terbuka> <none|draft|open|multi-merged> <worktree aktif 0|1> <status kartu | "" tanpa status | - tanpa kartu> <label integrated (spasi)>
# Keluaran: status tujuan, atau skip:<integrated|multi-merged-pr|needs-principal|no-card>. Kartu hanya maju (Backlog/Ready < In progress < In review < Done);
# Backlog <-> Ready dua arah. Status yang sudah lebih maju dikembalikan apa adanya (tanpa perubahan).
card_status() {
  local lb=" $1 " bl="$2" pr="$3" wt="$4" cur="$5" il="$6" want x
  [ "$cur" != - ] || { echo skip:no-card; return 0; }
  for x in $il; do case "$lb" in *" $x "*) echo skip:integrated; return 0 ;; esac; done
  [ "$pr" != multi-merged ] || { echo skip:multi-merged-pr; return 0; }
  if [ "$pr" = open ]; then want="In review"
  elif [ "$pr" = draft ] || [ "$wt" = 1 ] || [[ "$lb" == *" in-progress "* ]]; then want="In progress"
  elif [ "$bl" -gt 0 ]; then want=Backlog
  elif [[ "$lb" == *" needs-principal "* ]]; then echo skip:needs-principal; return 0
  else want=Ready; fi
  _cs_rank() { case "$1" in "In progress") echo 1 ;; "In review") echo 2 ;; Done) echo 3 ;; *) echo 0 ;; esac; }
  if [ "$(_cs_rank "$want")" -ge "$(_cs_rank "$cur")" ]; then echo "$want"; else echo "$cur"; fi
}
