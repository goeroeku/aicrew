#!/usr/bin/env bash
# aicrew grants: izin sementara terstruktur di docs/WORKFLOW.md (#61). Di-source oleh pr-merge-check.sh (--auto). Gagal tertutup: apa pun yang tak jelas = bukan izin.
#   grant_epoch <ISO8601 dengan zona>                       -> epoch detik UTC; exit 1 bila format/rentang tidak sah
#   grant_allows <risk> <cabang> <teks-WORKFLOW> <now-epoch> [cabang bawaan (spasi)]  -> exit 0 + mencetak baris izin yang berlaku; selain itu exit 1
# Format (bagian "## Temporary grants", kolom 0): - Grant: scope=merge; risk=L2; branch=<cabang>; expires=YYYY-MM-DDTHH:MM:SS(Z|+HH:MM); note=<teks, terakhir, tanpa ';'>
# Waktu "sekarang" hanya lewat parameter (tidak pernah dari lingkungan). Maksimum 7 hari ke depan. Cabang bawaan tidak boleh diberi izin. Perbandingan cabang persis (bukan pola).
grant_epoch() {
  local re='^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(Z|[+-][0-9]{2}:[0-9]{2})$'
  [[ "$1" =~ $re ]] || return 1
  local y=$((10#${BASH_REMATCH[1]})) mo=$((10#${BASH_REMATCH[2]})) d=$((10#${BASH_REMATCH[3]})) h=$((10#${BASH_REMATCH[4]})) mi=$((10#${BASH_REMATCH[5]})) se=$((10#${BASH_REMATCH[6]})) tz="${BASH_REMATCH[7]}"
  local off=0 dim th tm yy era yoe mp doy doe days
  [ "$y" -ge 1970 ] && [ "$y" -le 2100 ] && [ "$mo" -ge 1 ] && [ "$mo" -le 12 ] && [ "$h" -le 23 ] && [ "$mi" -le 59 ] && [ "$se" -le 59 ] || return 1
  case $mo in 1|3|5|7|8|10|12) dim=31 ;; 4|6|9|11) dim=30 ;; *) if [ $((y%4)) = 0 ] && { [ $((y%100)) != 0 ] || [ $((y%400)) = 0 ]; }; then dim=29; else dim=28; fi ;; esac
  [ "$d" -ge 1 ] && [ "$d" -le "$dim" ] || return 1
  if [ "$tz" != Z ]; then
    th=$((10#${tz:1:2})); tm=$((10#${tz:4:2}))
    [ "$th" -le 14 ] && [ "$tm" -le 59 ] && { [ "$th" -lt 14 ] || [ "$tm" = 0 ]; } || return 1
    off=$((th*3600+tm*60)); [ "${tz:0:1}" = - ] && off=$((-off))
  fi
  yy=$y; [ "$mo" -le 2 ] && yy=$((yy-1))
  era=$((yy/400)); yoe=$((yy-era*400))
  if [ "$mo" -gt 2 ]; then mp=$((mo-3)); else mp=$((mo+9)); fi
  doy=$(((153*mp+2)/5+d-1)); doe=$((yoe*365+yoe/4-yoe/100+doy)); days=$((era*146097+doe-719468))
  echo $((days*86400+h*3600+mi*60+se-off))
}
# baris "- Grant: " (kolom 0) di bagian "## Temporary grants" persis; blok kode, komentar HTML, dan bagian lain diabaikan
grants_lines() {
  printf '%s\n' "$1" | awk '
    BEGIN { sec = 0; fence = 0; com = 0 }
    { line = $0
      if (com) { if (line ~ /-->/) com = 0; next }
      if (line ~ /^ ? ? ?(```|~~~)/) { fence = !fence; next }
      if (fence) next
      if (line ~ /<!--/) { if (line !~ /-->/) com = 1; next }
      if (line ~ /^#[#]? /) { sec = (line == "## Temporary grants"); next }
      if (sec && line ~ /^- Grant: /) print line
    }'
}
# satu baris -> "<risk>\t<cabang>\t<epoch>"; exit 1 + PERINGATAN di stderr bila tidak sah
grant_parse() {
  local l="${1#- Grant: }" parts p i=0 k v seen=" " note=0 scope="" risk="" branch="" exp="" ep
  case "$1" in *[[:cntrl:]]*) echo "PERINGATAN: baris izin berkarakter kontrol diabaikan: $1" >&2; return 1 ;; esac
  IFS=';' read -ra parts <<<"$l"
  for p in "${parts[@]}"; do
    [ "$i" = 0 ] || p="${p# }"
    i=$((i+1))
    [[ "$p" =~ ^([a-z]+)=(.+)$ ]] || { echo "PERINGATAN: baris izin tidak sah (bagian '$p'): $1" >&2; return 1; }
    k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
    case "$seen" in *" $k "*) echo "PERINGATAN: baris izin memuat kunci ganda '$k': $1" >&2; return 1 ;; esac
    [ "$note" = 0 ] || { echo "PERINGATAN: 'note' harus bagian terakhir: $1" >&2; return 1; }
    case "$v" in " "*|*" ") echo "PERINGATAN: nilai '$k' berspasi di tepi: $1" >&2; return 1 ;; esac
    seen="$seen$k "
    case "$k" in scope) scope="$v" ;; risk) risk="$v" ;; branch) branch="$v" ;; expires) exp="$v" ;; note) note=1 ;;
      *) echo "PERINGATAN: kunci izin tak dikenal '$k' (baris tidak berlaku): $1" >&2; return 1 ;; esac
  done
  [ "$scope" = merge ] && [ "$risk" = L2 ] || { echo "PERINGATAN: hanya scope=merge dan risk=L2 didukung: $1" >&2; return 1; }
  [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "PERINGATAN: branch tidak sah: $1" >&2; return 1; }
  ep="$(grant_epoch "$exp")" || { echo "PERINGATAN: expires tidak sah (butuh YYYY-MM-DDTHH:MM:SS dengan Z atau +HH:MM): $1" >&2; return 1; }
  printf '%s\t%s\t%s\n' "$risk" "$branch" "$ep"
}
grant_allows() {
  local risk="$1" br="$2" text="$3" now="$4" defs="${5:-main master}" line pr r b e x
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pr="$(grant_parse "$line")" || continue
    IFS=$'\t' read -r r b e <<<"$pr"
    [ "$r" = "$risk" ] && [ "$b" = "$br" ] || continue
    for x in $defs; do [ "$b" != "$x" ] || continue 2; done
    [ "$e" -gt "$now" ] && [ $((e-now)) -le 604800 ] || continue
    printf '%s\n' "$line"; return 0
  done < <(grants_lines "$text")
  return 1
}
