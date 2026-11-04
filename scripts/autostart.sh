#!/usr/bin/env bash
# aicrew autostart: jalankan autopilot.sh otomatis lewat LaunchAgent macOS, supaya pekerjaan lanjut sendiri setelah laptop mati/tidur lalu hidup lagi.
# Opt-in per project. State tetap di GitHub dan .aicrew/ (autopilot melanjutkan lewat resume.sh); skrip ini hanya memastikan autopilot hidup lagi.
#   autostart.sh install <repo> --max-total N [--interval DETIK=900] [--dry-run]   N wajib: batas biaya untuk loop tanpa pengawasan
#   autostart.sh uninstall <repo>      copot agent (state .aicrew/ dibiarkan)
#   autostart.sh status <repo>         terpasang? dimuat? halted/PAUSE? kunci? log terakhir
#   autostart.sh resume <repo>         hapus .aicrew/halted setelah Anda memeriksa penyebab berhenti
#   autostart.sh run <repo>            dipanggil launchd tiap tick (bukan untuk dipakai langsung)
# Pengaman run: .aicrew/PAUSE = lewati; .aicrew/halted (autopilot berhenti karena exit selain 0/3/4) = tidak jalan sampai resume; kunci PID anti-ganda
# (tahan reboot: PID mati atau bukan autostart dianggap basi); tanpa gh/jaringan = lewati; rahasia Telegram dari ~/.config/aicrew/env, bukan plist.
# Lingkungan (untuk tes): AICREW_LAUNCH_DIR, AICREW_NO_LAUNCHCTL, AICREW_AUTOPILOT, AICREW_ENV_FILE.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$0")/lib/msg.sh"
die() { echo "autostart: $*" >&2; exit "${2:-1}"; }
cmd="${1:-}"; [ $# -ge 1 ] && shift
repo_arg="${1:-}"; [ $# -ge 1 ] && shift
[ -n "$cmd" ] && [ -n "$repo_arg" ] || die "$(msg autostart.usage)" 64
repo="$(cd "$repo_arg" 2>/dev/null && pwd)" || die "$(msg autostart.dir_missing "$repo_arg")"
label="com.aicrew.$(basename "$repo" | tr -c 'A-Za-z0-9._-' '-')-$(printf '%s' "$repo" | shasum | cut -c1-8)"
ldir="${AICREW_LAUNCH_DIR:-$HOME/Library/LaunchAgents}"; plist="$ldir/$label.plist"; dom="gui/$(id -u)"
g="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" && d="$(cd "$repo" && cd "$g/.." && pwd)/.aicrew" || d="$repo/.aicrew"
lc() { [ -n "${AICREW_NO_LAUNCHCTL:-}" ] && return 0; launchctl "$@"; }
x() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

case "$cmd" in
install)
  interval=900; maxtotal=""; dry=0
  while [ $# -gt 0 ]; do case "$1" in
    --max-total) maxtotal="${2:-}"; shift 2 ;; --interval) interval="${2:-}"; shift 2 ;; --dry-run) dry=1; shift ;; *) die "$(msg autostart.unknown_arg "$1")" 64 ;; esac; done
  [ "$maxtotal" -gt 0 ] 2>/dev/null || die "$(msg autostart.max_total_required)" 64
  [ "$interval" -ge 60 ] 2>/dev/null || die "$(msg autostart.interval_min)" 64
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "$(msg autostart.not_git_repo "$repo")"
  grep -q 'Bash(gh issue:\*)' "$repo/.claude/settings.local.json" 2>/dev/null \
    || die "$(msg autostart.permissions_missing "$repo" "$here")"
  for b in claude gh jq git; do command -v "$b" >/dev/null 2>&1 || die "$(msg autostart.bin_missing "$b")"; done
  path="$(for b in claude gh jq git; do dirname "$(command -v "$b")"; done | awk '!s[$0]++' | tr '\n' ':')/usr/bin:/bin:/usr/sbin:/sbin"
  # folder plugin ditentukan saat dijalankan (versi bisa berganti karena auto-update); path saat pasang hanya cadangan
  read -r -d '' snippet <<'EOS'
r="$(jq -r '.plugins["aicrew@aicrew"][0].installPath // empty' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)"; [ -f "$r/scripts/autostart.sh" ] || r="@HERE@"; exec bash "$r/scripts/autostart.sh" run "$1"
EOS
  snippet="${snippet//@HERE@/$(dirname "$here")}"
  xml="$(cat <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>-c</string><string>$(printf '%s' "$snippet" | x)</string><string>aicrew-autostart</string><string>$(printf '%s' "$repo" | x)</string></array>
  <key>WorkingDirectory</key><string>$(printf '%s' "$repo" | x)</string>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>$interval</integer>
  <key>ThrottleInterval</key><integer>60</integer>
  <key>StandardOutPath</key><string>$(printf '%s' "$repo" | x)/.aicrew/launchd.log</string>
  <key>StandardErrorPath</key><string>$(printf '%s' "$repo" | x)/.aicrew/launchd.log</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$(printf '%s' "$path" | x)</string><key>AICREW_MAX_TOTAL</key><string>$maxtotal</string></dict>
</dict>
</plist>
PL
)"
  [ "$dry" = 1 ] && { printf '%s\n' "$xml"; exit 0; }
  mkdir -p "$ldir" "$d"; printf '%s\n' "$xml" > "$plist.tmp" && mv "$plist.tmp" "$plist"
  if command -v plutil >/dev/null 2>&1; then plutil -lint "$plist" >/dev/null || { rm -f "$plist"; die "$(msg autostart.invalid_plist)"; }; fi
  lc bootout "$dom/$label" >/dev/null 2>&1; lc bootstrap "$dom" "$plist" || die "$(msg autostart.bootstrap_failed "$plist")"
  echo "$(msg autostart.installed "$label" "$((interval/60))" "$maxtotal" "$d" "$repo")" ;;
uninstall)
  lc bootout "$dom/$label" >/dev/null 2>&1; rm -f "$plist"; echo "$(msg autostart.uninstalled "$label" "$d")" ;;
status)
  echo "$(msg autostart.status_label "$label")"
  [ -f "$plist" ] && echo "$(msg autostart.status_installed_yes "$plist")" || echo "$(msg autostart.status_installed_no)"
  if [ -z "${AICREW_NO_LAUNCHCTL:-}" ]; then launchctl print "$dom/$label" >/dev/null 2>&1 && echo "$(msg autostart.status_loaded_yes)" || echo "$(msg autostart.status_loaded_no)"; fi
  [ -f "$d/halted" ] && echo "$(msg autostart.status_halted_yes "$(cat "$d/halted")" "$repo")" || echo "$(msg autostart.status_halted_no)"
  [ -f "$d/PAUSE" ] && echo "$(msg autostart.status_pause_yes)" || echo "$(msg autostart.status_pause_no)"
  [ -f "$d/autostart.lock" ] && echo "$(msg autostart.status_lock_pid "$(cat "$d/autostart.lock")")" || echo "$(msg autostart.status_lock_none)"
  [ -f "$d/autostart.log" ] && { echo "$(msg autostart.status_last_log)"; tail -n 5 "$d/autostart.log"; } ;;
resume)
  rm -f "$d/halted" "$d/stuck" "$d/stuck-logged"; echo "$(msg autostart.resumed)" ;;
run)
  cd "$repo" || exit 0; mkdir -p "$d"
  log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$d/autostart.log"; }
  [ -f "$d/PAUSE" ] && { log "$(msg autostart.pause_skipped)"; exit 0; }
  [ -f "$d/halted" ] && exit 0
  envf="${AICREW_ENV_FILE:-$HOME/.config/aicrew/env}"; [ -f "$envf" ] && { set -a; . "$envf"; set +a; }
  [ -n "${AICREW_MAX_TOTAL:-}" ] || { log "$(msg autostart.max_total_empty)"; exit 64; }
  gh auth status >/dev/null 2>&1 || { log "$(msg autostart.gh_unavailable)"; exit 0; }
  lock="$d/autostart.lock"
  if ! ( set -o noclobber; echo $$ > "$lock" ) 2>/dev/null; then
    pid="$(cat "$lock" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q autostart.sh; then log "$(msg autostart.already_running "$pid")"; exit 0; fi
    rm -f "$lock"; ( set -o noclobber; echo $$ > "$lock" ) 2>/dev/null || { log "$(msg autostart.lock_failed)"; exit 0; }
  fi
  trap 'rm -f "$lock"' EXIT
  log "$(msg autostart.starting "$AICREW_MAX_TOTAL")"
  bash "${AICREW_AUTOPILOT:-$here/autopilot.sh}" --max-total "$AICREW_MAX_TOTAL"; rc=$?
  log "$(msg autostart.finished "$rc")"
  case $rc in 0|3|4|6) ;; *)
    printf '%s rc=%s\n' "$(date '+%F %T')" "$rc" > "$d/halted"
    command -v jq >/dev/null && jq -n --arg m "$(msg autostart.halted_notify "$(basename "$repo")" "$rc" "$d" "$repo")" '{message:$m}' | bash "$here/notify.sh" ;;
  esac
  exit 0 ;;
*) die "$(msg autostart.unknown_cmd "$cmd")" 64 ;;
esac
