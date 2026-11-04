#!/usr/bin/env bash
# aicrew autonomy: nyalakan/matikan izin sementara untuk sesi otonom (#116). Dijalankan oleh OWNER saja.
# Pakai:  autonomy.sh on <until> [--branch <cabang>] [--file <settings.json>]... | off | status
# Keluar: 0 sukses, 1 ditolak (argumen sah tapi tenggat/cabang/kunci), 2 lingkungan (jq hilang, tulis gagal, berkas rusak), 64 argumen salah.
# Keamanan: berkas status (.aicrew/autonomy.json) TIDAK dipercaya. off hanya menyentuh berkas settings*.json biasa (bukan symlink), hanya
# mencabut entri yang ada di AUTONOMY_ALLOW, dan hanya menghapus baris Grant yang persis bentuk buatan skrip ini di docs/WORKFLOW.md repo.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib/grants.sh"

AUTONOMY_ALLOW=(
  "Bash(gh pr merge:*)" "Bash(rtk gh pr merge:*)"
  "Bash(git merge:*)" "Bash(rtk git merge:*)"
  "Bash(git rebase:*)" "Bash(rtk git rebase:*)"
)
usage() { echo "pakai: autonomy.sh on <until> [--branch <cabang>] [--file <settings.json>]... | off | status" >&2; exit 64; }
die() { echo "autonomy: $2" >&2; exit "$1"; }

cmd="${1:-}"; case "$cmd" in on|off|status|_expire) shift ;; *) usage ;; esac
until_arg=""; branch_arg=""; file_args=()
if [ "$cmd" = on ]; then
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) [ $# -ge 2 ] && [ -n "$2" ] || usage; branch_arg="$2"; shift 2 ;;
      --file) [ $# -ge 2 ] && [ -n "$2" ] || usage; file_args+=("$2"); shift 2 ;;
      -*) usage ;;
      *) [ -z "$until_arg" ] || usage; until_arg="$1"; shift ;;
    esac
  done
  [ -n "$until_arg" ] || usage
elif [ "$cmd" = _expire ]; then [ $# -eq 1 ] || usage; cd "$1" 2>/dev/null || exit 0
else [ $# -eq 0 ] || usage; fi

command -v jq >/dev/null 2>&1 || die 2 "jq tidak terpasang"
top="$(git rev-parse --show-toplevel 2>/dev/null)" || die 2 "bukan repo git"
sdir="$top/.aicrew"; sf="$sdir/autonomy.json"; lock="$sdir/autonomy.lock"; wf="$top/docs/WORKFLOW.md"
allow_json="$(printf '%s\n' "${AUTONOMY_ALLOW[@]}" | jq -R . | jq -sc .)"
LINE_RX='^- Grant: scope=merge; risk=L2; branch=[A-Za-z0-9][A-Za-z0-9._/-]*; expires=[0-9TZ:+-]+; note=autonomy\.sh$'

# helper tulis aman: tidak mengikuti symlink, nama sementara acak, atomik
keepmode() { [ ! -e "$1" ] || chmod "$(stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1")" "$2" 2>/dev/null; return 0; }   # mktemp membuat 0600: pertahankan mode berkas asal
okfile() { [ ! -L "$1" ] && { [ ! -e "$1" ] || [ -f "$1" ]; }; }
jedit() { local f="$1" t; shift; okfile "$f" || return 2; t="$(mktemp "$f.XXXXXX")" || return 2; if jq "$@" "$f" > "$t"; then keepmode "$f" "$t"; mv "$t" "$f"; else rm -f "$t"; return 2; fi; }
settings_name() { case "${1##*/}" in settings.json|settings.local.json) return 0 ;; esac; return 1; }

acquire_lock() {
  mkdir -p "$sdir" 2>/dev/null || die 2 "gagal membuat $sdir"
  if ! mkdir "$lock" 2>/dev/null; then
    local lp; lp="$(cat "$lock/pid" 2>/dev/null)"; [ -n "$lp" ] || { sleep 1; lp="$(cat "$lock/pid" 2>/dev/null)"; [ -n "$lp" ] || lp=0; }   # pid belum/tak pernah ditulis: tunggu sebentar, lalu anggap basi
    if [[ "$lp" =~ ^[0-9]+$ ]] && { [ "$lp" = 0 ] || ! kill -0 "$lp" 2>/dev/null; }; then rm -rf "$lock"; mkdir "$lock" 2>/dev/null || die 1 "sedang terkunci"   # kunci basi (proses mati)
    else die 1 "sedang terkunci ($lock)"; fi
  fi
  echo $$ > "$lock/pid"; trap 'rm -rf "$lock"' EXIT
}
helper_alive() { local pid="$1"; [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && case "$(ps -p "$pid" -o command= 2>/dev/null)" in *"autonomy.sh _expire $top") return 0 ;; esac; return 1; }
kill_helper() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" != "$$" ] && helper_alive "$1" && kill "$1" 2>/dev/null; return 0; }

# WORKFLOW: sisipkan/hapus tepat satu baris Grant buatan skrip ini (ENVIRON, bukan -v: tanpa interpretasi backslash)
wf_add() { # <baris>; mencetak "created" bila bagian dibuat
  local t; okfile "$wf" || return 2; mkdir -p "$(dirname "$wf")"; [ -e "$wf" ] || : > "$wf"
  t="$(mktemp "$wf.XXXXXX")" || return 2
  if grep -qx '## Temporary grants' "$wf"; then
    GL="$1" awk '{ print } !d && $0 == "## Temporary grants" { print ENVIRON["GL"]; d = 1 }' "$wf" > "$t" && keepmode "$wf" "$t" && mv "$t" "$wf" && echo present
  else
    { cat "$wf"; [ -z "$(tail -c1 "$wf")" ] || echo; echo "## Temporary grants"; printf '%s\n' "$1"; } > "$t" && keepmode "$wf" "$t" && mv "$t" "$wf" && echo created
  fi || { rm -f "$t"; return 2; }
}
wf_del() { # <baris> <created_section>
  local t; [ -f "$wf" ] && okfile "$wf" || return 0; [[ "$1" =~ $LINE_RX ]] || return 0
  t="$(mktemp "$wf.XXXXXX")" || return 2
  GL="$1" CS="$2" awk '
    { l[++n] = $0 }
    END { for (i = 1; i <= n; i++) if (l[i] == ENVIRON["GL"]) { l[i] = "\001"; break }
      m = n; if (ENVIRON["CS"] == "true") { for (i = 1; i <= n; i++) if (l[i] == "## Temporary grants") { ok = 1; for (j = i + 1; j <= n; j++) if (l[j] != "\001" && l[j] !~ /^[ \t]*$/) ok = 0; if (ok) m = i - 1; break } }
      for (i = 1; i <= m; i++) if (l[i] != "\001") print l[i] }' "$wf" > "$t" && keepmode "$wf" "$t" && mv "$t" "$wf" || { rm -f "$t"; return 2; }
}

do_off() {
  [ -f "$sf" ] && [ ! -L "$sf" ] && jq -e 'type == "object"' "$sf" >/dev/null 2>&1 || { [ -e "$sf" ] && die 2 "berkas status rusak: $sf"; return 0; }
  local fo p cr rem rc=0
  kill_helper "$(jq -r '.helper_pid // empty' "$sf")"
  while IFS= read -r fo; do
    p="$(jq -r '.path // empty' <<<"$fo")"; cr="$(jq -r '.created // false' <<<"$fo")"
    settings_name "$p" && [ -f "$p" ] && [ ! -L "$p" ] || continue
    jq -e 'type == "object"' "$p" >/dev/null 2>&1 || { echo "autonomy: PERINGATAN JSON rusak di $p; periksa dan cabut entri $(printf '%s ' "${AUTONOMY_ALLOW[@]}") secara manual" >&2; continue; }
    rem="$(jq -c --argjson a "$allow_json" '[(.added_allow // [])[] | select(. as $x | $a | index($x))]' <<<"$fo")"
    jedit "$p" --argjson rem "$rem" 'if (.permissions.allow | type) == "array" then .permissions.allow -= $rem else . end' || { echo "autonomy: gagal menulis $p" >&2; rc=2; continue; }
    if [ "$cr" = true ] && jq -e '((.permissions.allow // []) | length == 0) and ((.permissions.deny // []) | length == 0) and ((.permissions // {}) | del(.allow, .deny) | length == 0) and (del(.permissions) | length == 0)' "$p" >/dev/null 2>&1; then rm -f "$p"; fi
    [ -L "$p.bak-autonomy" ] || { [ "$(jq -r 'if .bak == false then "false" else "true" end' <<<"$fo")" = true ] && rm -f "$p.bak-autonomy"; }
  done < <(jq -c '.files[]?' "$sf")
  wf_del "$(jq -r '.workflow.line // empty' "$sf")" "$(jq -r '.workflow.created_section // false' "$sf")" || rc=2
  [ "$rc" = 0 ] && rm -f "$sf"
  return "$rc"
}

case "$cmd" in
  on)
    until_epoch="$(grant_epoch "$until_arg")" || die 1 "format until tidak sah: $until_arg"
    now="$(date +%s)"; { [ "$until_epoch" -gt "$now" ] && [ $((until_epoch - now)) -le 604800 ]; } || die 1 "tenggat harus di masa depan dan paling lama 7 hari: $until_arg"
    branch="$branch_arg"
    if [ -z "$branch" ] && [ -f "$wf" ]; then
      norm="$({ bash "$here/lib/wf-normalize.sh" < "$wf"; } 2>/dev/null)"
      case "$(grep -i 'Integration branch:' <<<"$norm" | head -1)" in *"{{"*) ;; *) branch="$(sed -n 's/^[- ]*.*Integration branch: *\([A-Za-z0-9._\/-]*\).*/\1/p' <<<"$norm" | head -1 | sed 's/[.,;:]*$//')" ;; esac
    fi
    def="$(git -C "$top" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; def="${def#origin/}"; lb="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]')"
    case "$lb" in ""|none|tidak|main|master|trunk) die 1 "cabang integrasi tidak sah atau cabang bawaan ditolak: '$branch'" ;; esac
    { [ -z "$def" ] || [ "$branch" != "$def" ]; } && [[ "$branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] && [[ "$branch" != *..* ]] && [[ "$branch" != */ ]] && [[ "$branch" != *//* ]] || die 1 "cabang integrasi tidak sah atau cabang bawaan ditolak: '$branch'"
    targets=("$top/.claude/settings.local.json"); for fa in ${file_args[@]+"${file_args[@]}"}; do case "$fa" in /*) targets+=("$fa") ;; *) targets+=("$PWD/$fa") ;; esac; done
    for f in "${targets[@]}"; do   # validasi SEMUA sebelum menulis apa pun
      settings_name "$f" || die 1 "berkas harus bernama settings.json atau settings.local.json: $f"
      okfile "$f" || die 2 "bukan berkas biasa (symlink?): $f"
      [ ! -e "$f" ] || jq -e 'type == "object"' "$f" >/dev/null 2>&1 || die 2 "JSON rusak di $f"
      okfile "$f.bak-autonomy" || die 2 "symlink di $f.bak-autonomy"
    done
    okfile "$wf" || die 2 "bukan berkas biasa (symlink?): $wf"
    acquire_lock
    do_off || exit $?     # on = cabut yang lama lalu pasang baru: idempoten, tanpa penggabungan status
    gline="- Grant: scope=merge; risk=L2; branch=$branch; expires=$until_arg; note=autonomy.sh"
    [[ "$gline" =~ $LINE_RX ]] || die 1 "tenggat tidak dapat ditulis sebagai baris Grant: $until_arg"
    files_json="[]"; done_t=()
    undo_targets() { local e f c b; for e in ${done_t[@]+"${done_t[@]}"}; do IFS='|' read -r f c b <<<"$e"; [ "$b" = true ] && rm -f "$f.bak-autonomy"; [ "$c" = true ] && rm -f "$f"; done; die "$1" "$2"; }   # gagal sebelum status ada: batalkan yang sudah dibuat
    for f in "${targets[@]}"; do
      mkdir -p "$(dirname "$f")" 2>/dev/null || undo_targets 2 "gagal membuat direktori untuk $f"
      cr=false; bk=true; [ -e "$f.bak-autonomy" ] && bk=false
      [ -e "$f" ] || { cr=true; echo '{}' > "$f" || undo_targets 2 "gagal menulis $f"; }
      [ "$bk" = false ] || cp "$f" "$f.bak-autonomy" || undo_targets 2 "gagal menulis cadangan $f.bak-autonomy"
      done_t+=("$f|$cr|$bk")
      add="$(jq -nc --argjson a "$allow_json" --argjson cur "$(jq -c '.permissions.allow // []' "$f")" '[$a[] | select(. as $x | ($cur | index($x)) | not)]')"
      files_json="$(jq -c --arg p "$f" --argjson c "$cr" --argjson bk "$bk" --argjson a "$add" '. + [{path:$p, created:$c, bak:$bk, added_allow:$a}]' <<<"$files_json")"
    done
    state="$(jq -n --arg u "$until_arg" --argjson ue "$until_epoch" --arg br "$branch" --argjson fl "$files_json" --arg gl "$gline" '{until:$u, until_epoch:$ue, branch:$br, files:$fl, workflow:{line:$gl, created_section:false}, helper_pid:null}')"
    tmp="$(mktemp "$sf.XXXXXX")" || die 2 "gagal menulis $sf"; printf '%s\n' "$state" > "$tmp" && mv "$tmp" "$sf"   # status ditulis DULU: kegagalan di bawah bisa dicabut
    fail() { echo "autonomy: $1" >&2; do_off; exit 2; }
    while IFS= read -r fo; do
      p="$(jq -r .path <<<"$fo")"; add="$(jq -c .added_allow <<<"$fo")"
      jedit "$p" --argjson add "$add" '.permissions = ((.permissions // {}) | .allow = ((.allow // []) + $add))' || fail "gagal menulis $p"
    done < <(jq -c '.files[]' "$sf")
    cs="$(wf_add "$gline")" || fail "gagal menulis $wf"
    jedit "$sf" --argjson cs "$([ "$cs" = created ] && echo true || echo false)" '.workflow.created_section = $cs' || fail "gagal menulis $sf"
    bash "$here/autonomy.sh" _expire "$top" </dev/null >/dev/null 2>&1 &
    hp=$!; disown "$hp" 2>/dev/null
    jedit "$sf" --argjson hp "$hp" '.helper_pid = $hp' || { kill "$hp" 2>/dev/null; fail "gagal menulis $sf"; }
    echo "PERINGATAN: Grant risk=L2 ditambahkan ke docs/WORKFLOW.md (pengecualian sementara #61 untuk 'L2 selalu owner' pada cabang $branch sampai $until_arg)."
    echo "autonomy: aktif sampai $until_arg (cabang $branch, pid $hp)" ;;
  off)
    acquire_lock
    [ -f "$sf" ] || { echo "autonomy: mati"; exit 0; }
    do_off || exit $?
    echo "autonomy: dicabut" ;;
  status)
    ap="$(pgrep -f 'scripts/autopilot\.sh' 2>/dev/null | grep -vxF -e "$$" -e "${PPID:-0}" | tr '\n' ' ' | sed 's/ *$//')"
    if [ ! -f "$sf" ]; then echo "autonomy: mati"
    else
      jq -e 'type == "object"' "$sf" >/dev/null 2>&1 || die 2 "berkas status rusak: $sf"
      u="$(jq -r '.until // ""' "$sf")"; ue="$(jq -r '.until_epoch // 0' "$sf")"; hp="$(jq -r '.helper_pid // ""' "$sf")"; gl="$(jq -r '.workflow.line // ""' "$sf")"
      x=""; [[ "$ue" =~ ^[0-9]+$ ]] && [ "$(date +%s)" -ge "$ue" ] && x=" — KEDALUWARSA, jalankan: autonomy.sh off"
      echo "autonomy: aktif sampai $u (cabang $(jq -r '.branch // ""' "$sf"))$x"
      jq -r '.files[]? | "berkas: \(.path) (\((.added_allow // []) | length) entri: \((.added_allow // []) | join(", ")))"' "$sf"
      if [ -n "$gl" ] && grep -qxF -- "$gl" "$wf" 2>/dev/null; then echo "workflow: ada ($gl)"; else echo "workflow: tidak ada"; fi
      if helper_alive "$hp"; then echo "helper: hidup (pid $hp)"; else echo "helper: mati${hp:+ (pid $hp)}"; fi
    fi
    echo "autopilot.sh${ap:+ (mungkin milik repo lain)}: ${ap:-tidak ada}" ;;
  _expire)
    poll="${AUTONOMY_POLL:-30}"; [[ "$poll" =~ ^[1-9][0-9]*$ ]] || poll=30
    while :; do
      sleep "$poll"; [ -f "$sf" ] || exit 0
      exp="$(jq -r '.until_epoch // empty' "$sf" 2>/dev/null)"; [[ "$exp" =~ ^[0-9]+$ ]] || exit 0
      if [ "$(date +%s)" -ge "$exp" ]; then bash "$here/autonomy.sh" off >/dev/null 2>&1; fi   # kunci terpegang/gagal: ulangi di putaran berikut, jangan menyerah
    done ;;
esac
