#!/usr/bin/env bash
# aicrew worktree-for-issue: sebelum membuat worktree untuk issue N, daftar worktree dan cabang yang sudah ada (issue-N atau issue-N-<sufiks>)
# dan tolak (exit 1) bila salah satunya punya kerja belum aman (uncommitted atau unpushed). Satu issue = satu cabang kanonik issue-N (#78).
# Pakai: worktree-for-issue.sh <n>    Keluaran TSV: worktree|branch <cabang> <path|-> <clean|uncommitted|unpushed>, lalu "canonical issue-N".
# Tidak mengubah apa pun. exit 64 = argumen salah.
set -u
n="${1:-}"; [[ "$n" =~ ^[0-9]+$ ]] || { echo "pakai: worktree-for-issue.sh <issue-number>" >&2; exit 64; }
rx="^issue-$n(-[A-Za-z0-9._-]+)?\$"; bad=0; seen=" "
state() { # <cabang> <path|-> -> clean | uncommitted | unpushed
  if [ "$2" != - ] && [ -n "$(git -C "$2" status --porcelain 2>/dev/null)" ]; then echo uncommitted
  elif [ -n "$(git rev-list --max-count=1 "refs/heads/$1" --not --remotes 2>/dev/null)" ]; then echo unpushed   # commit yang belum ada di remote mana pun
  else echo clean; fi
}
report() { # <jenis> <cabang> <path>
  local st; st="$(state "$2" "$3")"; printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$st"
  [ "$st" = clean ] || { echo "worktree-for-issue: issue-$n punya kerja $st di $2 ($3); lanjutkan di sana, jangan buat worktree baru di sampingnya" >&2; bad=1; }
}
while IFS=$'\t' read -r p b; do
  [[ "$b" =~ $rx ]] || continue
  seen="$seen$b "; report worktree "$b" "$p"
done < <(git worktree list --porcelain | awk 'BEGIN{RS="";FS="\n"}{p="";b="";for(k=1;k<=NF;k++){if($k~/^worktree /)p=substr($k,10);else if($k~/^branch refs\/heads\//)b=substr($k,19)}if(b!="")printf "%s\t%s\n",p,b}')
while read -r b; do
  [[ "$b" =~ $rx ]] || continue
  case "$seen" in *" $b "*) continue ;; esac
  report branch "$b" -
done < <(git for-each-ref --format='%(refname:short)' refs/heads)
printf 'canonical\tissue-%s\n' "$n"
exit "$bad"
