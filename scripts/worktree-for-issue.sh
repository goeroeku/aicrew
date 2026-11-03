#!/usr/bin/env bash
# aicrew worktree-for-issue: sebelum membuat worktree untuk issue N, daftar worktree dan cabang yang sudah ada (issue-N atau issue-N-<sufiks>)
# dan tolak (exit 1) bila salah satunya punya kerja belum aman (uncommitted atau unpushed). Satu issue = satu cabang kanonik issue-N (#78).
# Pakai: worktree-for-issue.sh <n>    Keluaran TSV: worktree|branch <cabang> <path|-> <clean|uncommitted|unpushed>, lalu "canonical issue-N".
# Tanpa --ensure tidak mengubah apa pun. exit 64 = argumen salah.
# --ensure <path> <basis>: menyiapkan worktree kanonik issue-N dan mencetak "ensure<TAB>create|continue|reuse|reset<TAB><path>":
#   reuse = issue-N sudah ter-checkout (kerja belum aman dilanjutkan di sana); reset = bersih, tanpa commit sendiri, tertinggal -> digeser ke origin/<basis> otomatis;
#   continue = cabang issue-N punya commit sendiri (lokal atau origin) -> dilanjutkan dari commit itu; create = baru dari origin/<basis>.
#   exit 1 = ada worktree/cabang BERSUFIKS dengan kerja belum aman (tidak membuat apa pun); exit 2 = origin/<basis> atau git worktree gagal.
set -u
n="${1:-}"; [[ "$n" =~ ^[0-9]+$ ]] || { echo "pakai: worktree-for-issue.sh <issue-number> [--ensure <path> <basis>]" >&2; exit 64; }
ens=0; if [ "${2:-}" = --ensure ]; then ens=1; epath="${3:-}"; ebase="${4:-}"; [ -n "$epath" ] && [ -n "$ebase" ] || { echo "pakai: ... --ensure <path> <basis>" >&2; exit 64; }; fi
canon="issue-$n"
rx="^issue-$n(-[A-Za-z0-9._-]+)?\$"; bad=0; seen=" "; cpath=""
state() { # <cabang> <path|-> -> clean | uncommitted | unpushed
  if [ "$2" != - ] && [ -n "$(git -C "$2" status --porcelain 2>/dev/null)" ]; then echo uncommitted
  elif [ -n "$(git rev-list --max-count=1 "refs/heads/$1" --not --remotes 2>/dev/null)" ]; then echo unpushed   # commit yang belum ada di remote mana pun
  else echo clean; fi
}
report() { # <jenis> <cabang> <path>
  local st; st="$(state "$2" "$3")"
  [ "$ens" = 1 ] && [ "$2" = "$canon" ] && { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$st"; [ "$1" = worktree ] && cpath="$3"; return; }   # kanonik dilanjutkan, bukan ditolak
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$st"
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
[ "$ens" = 1 ] || exit "$bad"
[ "$bad" = 0 ] || exit 1
git rev-parse -q --verify "origin/$ebase" >/dev/null || { echo "worktree-for-issue: origin/$ebase tidak ada" >&2; exit 2; }
anc() { git merge-base --is-ancestor "$1" "origin/$ebase"; }   # tanpa commit sendiri = leluhur basis
done_() { printf 'ensure\t%s\t%s\n' "$1" "$2"; exit 0; }
if [ -n "$cpath" ]; then
  h="$(git -C "$cpath" rev-parse HEAD)"
  if [ -z "$(git -C "$cpath" status --porcelain)" ] && anc "$h" && [ "$h" != "$(git rev-parse "origin/$ebase")" ]; then
    git -C "$cpath" checkout -q -B "$canon" "origin/$ebase" || exit 2; done_ reset "$cpath"
  fi
  done_ reuse "$cpath"
fi
if git show-ref -q --verify "refs/heads/$canon"; then
  if anc "$canon"; then git worktree add -q -B "$canon" "$epath" "origin/$ebase" || exit 2; done_ reset "$epath"
  else git worktree add -q "$epath" "$canon" || exit 2; done_ continue "$epath"; fi
fi
if git show-ref -q --verify "refs/remotes/origin/$canon" && ! anc "origin/$canon"; then
  git worktree add -q -b "$canon" "$epath" "origin/$canon" || exit 2; done_ continue "$epath"
fi
git worktree add -q -b "$canon" "$epath" "origin/$ebase" || exit 2; done_ create "$epath"
