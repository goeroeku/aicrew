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
die() { echo "autostart: $*" >&2; exit "${2:-1}"; }
cmd="${1:-}"; [ $# -ge 1 ] && shift
repo_arg="${1:-}"; [ $# -ge 1 ] && shift
[ -n "$cmd" ] && [ -n "$repo_arg" ] || die "pakai: autostart.sh install|uninstall|status|resume|run <repo> [opsi]" 64
repo="$(cd "$repo_arg" 2>/dev/null && pwd)" || die "folder tidak ada: $repo_arg"
label="com.aicrew.$(basename "$repo" | tr -c 'A-Za-z0-9._-' '-')-$(printf '%s' "$repo" | shasum | cut -c1-8)"
ldir="${AICREW_LAUNCH_DIR:-$HOME/Library/LaunchAgents}"; plist="$ldir/$label.plist"; dom="gui/$(id -u)"
g="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" && d="$(cd "$repo" && cd "$g/.." && pwd)/.aicrew" || d="$repo/.aicrew"
lc() { [ -n "${AICREW_NO_LAUNCHCTL:-}" ] && return 0; launchctl "$@"; }
x() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }

case "$cmd" in
install)
  interval=900; maxtotal=""; dry=0
  while [ $# -gt 0 ]; do case "$1" in
    --max-total) maxtotal="${2:-}"; shift 2 ;; --interval) interval="${2:-}"; shift 2 ;; --dry-run) dry=1; shift ;; *) die "argumen tak dikenal: $1" 64 ;; esac; done
  [ "$maxtotal" -gt 0 ] 2>/dev/null || die "install: --max-total N (bilangan > 0) wajib, sebagai batas biaya loop tanpa pengawasan" 64
  [ "$interval" -ge 60 ] 2>/dev/null || die "install: --interval minimal 60 detik" 64
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "install: $repo bukan repo git"
  grep -q 'Bash(gh issue:\*)' "$repo/.claude/settings.local.json" 2>/dev/null \
    || die "install: izin autopilot belum terpasang di $repo/.claude/settings.local.json; jalankan dulu (di folder project): bash $here/install-permissions.sh"
  for b in claude gh jq git; do command -v "$b" >/dev/null 2>&1 || die "install: '$b' tidak ditemukan di PATH"; done
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
  if command -v plutil >/dev/null 2>&1; then plutil -lint "$plist" >/dev/null || { rm -f "$plist"; die "install: plist tidak valid"; }; fi
  lc bootout "$dom/$label" >/dev/null 2>&1; lc bootstrap "$dom" "$plist" || die "install: launchctl bootstrap gagal (plist di $plist)"
  echo "autostart: terpasang $label (tiap $((interval/60)) menit dan saat login; --max-total $maxtotal). Rem: touch $d/PAUSE. Lepas: autostart.sh uninstall $repo" ;;
uninstall)
  lc bootout "$dom/$label" >/dev/null 2>&1; rm -f "$plist"; echo "autostart: dicopot $label (state di $d dibiarkan)" ;;
status)
  echo "label: $label"
  [ -f "$plist" ] && echo "terpasang: ya ($plist)" || echo "terpasang: tidak"
  if [ -z "${AICREW_NO_LAUNCHCTL:-}" ]; then launchctl print "$dom/$label" >/dev/null 2>&1 && echo "dimuat di launchd: ya" || echo "dimuat di launchd: tidak"; fi
  [ -f "$d/halted" ] && echo "halted: ya ($(cat "$d/halted")); periksa lalu: autostart.sh resume $repo" || echo "halted: tidak"
  [ -f "$d/PAUSE" ] && echo "PAUSE: ya" || echo "PAUSE: tidak"
  [ -f "$d/autostart.lock" ] && echo "kunci: pid $(cat "$d/autostart.lock")" || echo "kunci: tidak ada"
  [ -f "$d/autostart.log" ] && { echo "log terakhir:"; tail -n 5 "$d/autostart.log"; } ;;
resume)
  rm -f "$d/halted" "$d/stuck"; echo "autostart: halted dan penanda buntu dihapus; tick berikutnya menjalankan autopilot lagi" ;;
run)
  cd "$repo" || exit 0; mkdir -p "$d"
  log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$d/autostart.log"; }
  [ -f "$d/PAUSE" ] && { log "PAUSE: dilewati"; exit 0; }
  [ -f "$d/halted" ] && exit 0
  envf="${AICREW_ENV_FILE:-$HOME/.config/aicrew/env}"; [ -f "$envf" ] && { set -a; . "$envf"; set +a; }
  [ -n "${AICREW_MAX_TOTAL:-}" ] || { log "AICREW_MAX_TOTAL kosong: ditolak (tanpa batas biaya)"; exit 64; }
  gh auth status >/dev/null 2>&1 || { log "gh/jaringan tidak tersedia: dilewati"; exit 0; }
  lock="$d/autostart.lock"
  if ! ( set -o noclobber; echo $$ > "$lock" ) 2>/dev/null; then
    pid="$(cat "$lock" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q autostart.sh; then log "autopilot lain berjalan (pid $pid): dilewati"; exit 0; fi
    rm -f "$lock"; ( set -o noclobber; echo $$ > "$lock" ) 2>/dev/null || { log "gagal mengambil kunci"; exit 0; }
  fi
  trap 'rm -f "$lock"' EXIT
  log "mulai autopilot (--max-total $AICREW_MAX_TOTAL)"
  bash "${AICREW_AUTOPILOT:-$here/autopilot.sh}" --max-total "$AICREW_MAX_TOTAL"; rc=$?
  log "autopilot selesai rc=$rc"
  case $rc in 0|3|4|6) ;; *)
    printf '%s rc=%s\n' "$(date '+%F %T')" "$rc" > "$d/halted"
    command -v jq >/dev/null && jq -n --arg m "autostart $(basename "$repo"): berhenti (rc=$rc), tidak dijalankan lagi otomatis. Periksa $d/autopilot.log lalu: autostart.sh resume $repo" '{message:$m}' | bash "$here/notify.sh" ;;
  esac
  exit 0 ;;
*) die "perintah tak dikenal: $cmd" 64 ;;
esac
