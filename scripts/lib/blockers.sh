#!/usr/bin/env bash
# aicrew blockers: blocker yang masih terbuka dari bagian "## Blocked by" di badan issue (dipakai autopilot.sh dan board.sh --sync-cards).
#   unsat_blockers <larik JSON issue terbuka {number,body}> <nomor>  -> satu nomor per baris
# "owner/repo#n" (lintas repo) diabaikan; blocker yang tidak ada di larik (ditutup, berlabel integrasi, atau epic yang sudah disaring pemanggil) terpenuhi.
unsat_blockers() {
  local nums b; nums=" $(jq -r '.[].number' <<<"$1" | tr '\n' ' ')"
  for b in $(jq -r --argjson n "$2" '.[]|select(.number==$n)|.body // ""' <<<"$1" | awk 'tolower($0) ~ /^##[ \t]+blocked by/{f=1;next} /^##/{f=0} f' | grep -oE '(^|[^A-Za-z0-9_./-])#[0-9]+' | grep -oE '[0-9]+' | sort -u); do
    [ "$b" != "$2" ] || continue
    case "$nums" in *" $b "*) echo "$b" ;; esac
  done
}
