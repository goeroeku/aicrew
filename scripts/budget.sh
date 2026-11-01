#!/usr/bin/env bash
# aicrew budget: penghitung deterministik untuk batas loop. State di .aicrew/ (jangan di-commit).
#   budget.sh iter                       tambah hitungan iterasi, cetak nilainya
#   budget.sh fail <issue>               tambah hitungan gagal untuk issue
#   budget.sh reset <issue>              nolkan gagal issue (setelah berhasil)
#   budget.sh newrun                     nolkan hitungan iterasi PUTARAN ini (total proyek tetap); dipanggil autopilot tiap putaran
#   budget.sh check <maxIter> <maxFail> [issue] [maxTotal]   exit 2 = batas iterasi putaran, 3 = batas gagal, 4 = batas total proyek, 0 = boleh lanjut
set -u
# state di repo utama, bukan cwd: worktree berbagi hitungan yang sama
g="$(git rev-parse --git-common-dir 2>/dev/null)" && d="$(cd "$g/.." && pwd)/.aicrew" || d=".aicrew"; mkdir -p "$d"
num() { [ -f "$1" ] && cat "$1" || echo 0; }
case "${1:-}" in
  iter)  n=$(( $(num $d/iter) + 1 )); echo "$n" > $d/iter; echo $(( $(num $d/total) + 1 )) > $d/total; echo "$n" ;;
  newrun) echo 0 > $d/iter ;;
  fail)  f="$d/fail-${2:?issue}"; n=$(( $(num "$f") + 1 )); echo "$n" > "$f"; echo "$n" ;;
  reset) rm -f "$d/fail-${2:?issue}" ;;
  check)
    mi="${2:?maxIter}"; mf="${3:?maxFail}"
    [ "$(num $d/iter)" -ge "$mi" ] && { echo "STOP: batas iterasi ($mi) tercapai"; exit 2; }
    if [ -n "${4:-}" ] && [ "$(num "$d/fail-$4")" -ge "$mf" ]; then echo "STOP: issue $4 gagal $mf kali"; exit 3; fi
    [ -n "${5:-}" ] && [ "$(num $d/total)" -ge "$5" ] && { echo "STOP: total $(num $d/total) >= $5 (--max-total)"; exit 4; }
    echo "lanjut" ;;
  *) echo "pakai: budget.sh iter|newrun|fail N|reset N|check maxIter maxFail [N] [maxTotal]" >&2; exit 64 ;;
esac
