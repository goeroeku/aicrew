#!/usr/bin/env bash
# aicrew cleanup: laporkan cabang dan worktree yang TERBUKTI ter-merge dan aman dihapus. Pakai:
#   cleanup.sh [--no-fetch] [--only orkestrator] [--issue <n>]
# Keluaran TSV: jenis  nama  sha  bukti  aksi   (jenis cabang-lokal|cabang-remote|worktree; bukti leluhur|pr-merged|-; aksi hapus|lewati:<alasan>).
# Bukti ter-merge: (a) ujung cabang leluhur origin/<bawaan> atau origin/<integrasi>; (b) PR merged dengan head.sha sama dengan ujung (squash/rebase).
# Tidak pernah kandidat: cabang bawaan dan integrasi, cabang yang head atau base PR terbuka, cabang ter-checkout di worktree yang tidak ikut dihapus,
# worktree kotor/terkunci/terlepas/di ~/orca/workspaces/. Hanya git dan REST (gh api), tanpa GraphQL. GitHub saja (backend lain: keluar 0).
set -u
here="$(dirname "$0")"; source "$here/ghx.sh"
usage() { echo "pakai: cleanup.sh [--no-fetch] [--only orkestrator] [--issue <n>]" >&2; exit 64; }
only=""; issue=""; fetch=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-fetch) fetch=0 ;;
    --only) only="${2:-}"; [ "$only" = orkestrator ] || usage; shift ;;
    --issue) issue="${2:-}"; [[ "$issue" =~ ^[0-9]+$ ]] || usage; shift ;;
    *) usage ;;
  esac; shift
done
top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "cleanup: bukan repo git" >&2; exit 64; }; cd "$top"
tab="$(printf '\t')"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; reponame="${top##*/}"

wf="$(bash "$here/workflow.sh" 2>/dev/null)"
bk="$(sed -n 's/^[- ]*Backend: *\([A-Za-z]*\).*/\1/p' <<<"$wf" | head -1)"
[ -z "$bk" ] || [ "$bk" = github ] || { echo "cleanup: tidak didukung (bukan GitHub: $bk)" >&2; exit 0; }
repo="$(ghx_repo)" || { echo "cleanup: repo tak dapat ditentukan" >&2; exit 1; }; owner="${repo%%/*}"
havegh=0; command -v gh >/dev/null 2>&1 && havegh=1
[ "$fetch" = 0 ] || git fetch -q --prune origin 2>/dev/null || echo "cleanup: git fetch gagal; bukti bisa basi" >&2

def="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; def="${def#origin/}"
[ -n "$def" ] || def="$(gh api "repos/$repo" 2>/dev/null | jq -r '.default_branch // empty' 2>/dev/null)"
integ="$(sed -n 's/^[- ]*.*Cabang integrasi: *\([A-Za-z0-9._\/-]*\).*/\1/p' <<<"$wf" | head -1 | sed 's/[.,;:]*$//')"
git show-ref --verify --quiet "refs/remotes/origin/${integ:-_}" || integ=""
bases=""; for b in "$def" "$integ"; do [ -z "$b" ] || git show-ref --verify --quiet "refs/remotes/origin/$b" && bases="$bases $b"; done
is_protected() { [ "$1" = "$def" ] || { [ -n "$integ" ] && [ "$1" = "$integ" ]; }; }

openok=0; openj="$(gh api "repos/$repo/pulls?state=open&per_page=100" --paginate 2>/dev/null)" && openok=1
open_heads="$(jq -r '.[].head.ref' <<<"$openj" 2>/dev/null)"; open_bases="$(jq -r '.[].base.ref' <<<"$openj" 2>/dev/null)"
inlist() { [ -n "$2" ] && grep -qxF -- "$1" <<<"$2"; }

evidence() { # <nama> <ujung> -> leluhur | pr-merged | -
  local b q
  for b in $bases; do git merge-base --is-ancestor "$2" "origin/$b" 2>/dev/null && { echo leluhur; return; }; done
  if [ "$havegh" = 1 ]; then
    q="$(jq -rn --arg h "$owner:$1" '$h|@uri')"
    gh api "repos/$repo/pulls?head=$q&state=all&per_page=100" 2>/dev/null | jq -e --arg s "$2" 'any(.[]; .merged_at != null and .head.sha == $s)' >/dev/null 2>&1 && { echo pr-merged; return; }
  fi
  echo -
}
reason() { # <jenis> <nama> <bukti> -> alasan melewati sebelum pemeriksaan checkout, atau kosong
  if [ "$openok" = 1 ] && inlist "$2" "$open_heads"; then echo pr-terbuka; return; fi
  if [ "$openok" = 1 ] && inlist "$2" "$open_bases"; then echo base-pr-terbuka; return; fi
  [ "$3" != "-" ] || { echo belum-ter-merge; return; }
  [ "$1" = cabang-remote ] && [ "$openok" = 0 ] && { echo pr-tak-terbaca; return; }
  echo ""
}
owned() { # <jenis> <nama>: milik orkestrator (dan sesuai --issue)
  local n="$2" rx
  if [ "$1" = worktree ]; then rx="^${reponame}-wt-${issue:-[0-9]+}\$"; else rx="^issue-${issue:-[0-9]+}\$"; fi
  [[ "$n" =~ $rx ]]
}
want() { [ -z "$only$issue" ] || owned "$1" "$2"; }

# 1. cabang lokal dan remote: bukti dan alasan awal
: > "$T/loc"; : > "$T/rem"
while IFS="$tab" read -r n tip; do
  is_protected "$n" && continue; want cabang-lokal "$n" || continue
  ev="$(evidence "$n" "$tip")"; printf '%s\t%s\t%s\t%s\n' "$n" "$tip" "$ev" "$(reason cabang-lokal "$n" "$ev")" >> "$T/loc"
done < <(git for-each-ref --format='%(refname:short)%09%(objectname)' refs/heads)
while IFS="$tab" read -r n tip; do
  n="${n#refs/remotes/origin/}"; [ "$n" != HEAD ] || continue; is_protected "$n" && continue; want cabang-remote "$n" || continue
  ev="$(evidence "$n" "$tip")"; printf '%s\t%s\t%s\t%s\n' "$n" "$tip" "$ev" "$(reason cabang-remote "$n" "$ev")" >> "$T/rem"
done < <(git for-each-ref --format='%(refname)%09%(objectname)' refs/remotes/origin)   # nama lengkap: short dari origin/HEAD menjadi "origin"

# 2. worktree: keputusan dulu (menentukan cabang mana yang tetap ter-checkout)
: > "$T/wt"; : > "$T/surv"; i=0
while IFS="$tab" read -r p b h l; do
  i=$((i+1)); nm="${p##*/}"
  if [ "$i" = 1 ]; then echo "$b" >> "$T/surv"; continue; fi          # worktree utama tidak pernah dihapus
  if ! want worktree "$nm"; then echo "$b" >> "$T/surv"; continue; fi   # di luar cakupan: cabangnya tetap ter-checkout
  ev="-"; case "$p" in
    */orca/workspaces/*) act="lewati:orca" ;;
    *) if [ "$l" = 1 ]; then act="lewati:terkunci"
       elif [ "$b" = "-" ]; then act="lewati:tanpa-cabang"
       elif [ -n "$(git -C "$p" status --porcelain 2>/dev/null)" ]; then act="lewati:kotor"
       else
         lr="$(awk -F'\t' -v n="$b" '$1==n{print $3 "\t" $4; found=1} END{if(!found)print "-\tdilindungi"}' "$T/loc")"
         if [ "${lr#*$tab}" = "" ]; then act="hapus"; ev="${lr%%$tab*}"; else act="lewati:${lr#*$tab}"; fi
       fi ;;
  esac
  [ "$act" = hapus ] || echo "$b" >> "$T/surv"
  printf 'worktree\t%s\t%s\t%s\t%s\t%s\n' "$nm" "$h" "$ev" "$act" "$p" >> "$T/wt"
done < <(git worktree list --porcelain | awk 'BEGIN{RS="";FS="\n"}{p="";b="-";h="";l=0;for(k=1;k<=NF;k++){if($k~/^worktree /)p=substr($k,10);else if($k~/^HEAD /)h=substr($k,6);else if($k~/^branch refs\/heads\//)b=substr($k,19);else if($k~/^locked/)l=1}printf "%s\t%s\t%s\t%d\n",p,b,h,l}')

# 3. keluaran final
: > "$T/out"
while IFS="$tab" read -r n tip ev r; do
  if [ -n "$r" ]; then act="lewati:$r"; elif inlist "$n" "$(cat "$T/surv")"; then act="lewati:checkout"; else act="hapus"; fi
  printf 'cabang-lokal\t%s\t%s\t%s\t%s\n' "$n" "$tip" "$ev" "$act" >> "$T/out"
done < "$T/loc"
while IFS="$tab" read -r n tip ev r; do
  if [ -n "$r" ]; then act="lewati:$r"; else act="hapus"; fi
  printf 'cabang-remote\t%s\t%s\t%s\t%s\n' "$n" "$tip" "$ev" "$act" >> "$T/out"
done < "$T/rem"
cut -f1-5 "$T/wt" >> "$T/out"
cat "$T/out"
echo "cleanup: $(grep -c "${tab}hapus\$" "$T/out") kandidat hapus, $(grep -c "${tab}lewati:" "$T/out") dilewati (mode laporan)" >&2
exit 0
