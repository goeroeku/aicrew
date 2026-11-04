#!/usr/bin/env bash
# aicrew budget: penghitung deterministik untuk batas loop. State di .aicrew/ (jangan di-commit).
#   budget.sh iter                       tambah hitungan iterasi, cetak nilainya
#   budget.sh fail <issue>               tambah hitungan gagal untuk issue
#   budget.sh reset <issue>              nolkan gagal issue (setelah berhasil)
#   budget.sh newrun                     nolkan hitungan iterasi PUTARAN ini (total proyek tetap); dipanggil autopilot tiap putaran
#   budget.sh check <maxIter> <maxFail> [issue] [maxTotal]   exit 2 = batas iterasi putaran, 3 = batas gagal, 4 = batas total proyek, 0 = boleh lanjut
set -u
source "$(dirname "$0")/lib/msg.sh"
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
    [ "$(num $d/iter)" -ge "$mi" ] && { echo "$(msg budget.max_iter "$mi")"; exit 2; }
    if [ -n "${4:-}" ] && [ "$(num "$d/fail-$4")" -ge "$mf" ]; then echo "$(msg budget.max_fail "$4" "$mf")"; exit 3; fi
    [ -n "${5:-}" ] && [ "$(num $d/total)" -ge "$5" ] && { echo "$(msg budget.max_total "$(num $d/total)" "$5")"; exit 4; }
    echo "$(msg budget.continue)" ;;
  *) echo "$(msg budget.usage)" >&2; exit 64 ;;
esac
