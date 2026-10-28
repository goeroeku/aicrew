#!/usr/bin/env bash
# aicrew autopilot: jalankan orkestrator berulang (sesi baru tiap putaran) sampai selesai, buntu, atau menunggu owner.
# Tahan limit token/mingguan: bila putaran berakhir karena limit, tidur lalu coba lagi. State ada di GitHub dan .aicrew/,
# jadi putaran baru melanjutkan (skill orchestrate: bagian Resume). Jalankan dari akar repo project. GitHub/gh saja.
#   autopilot.sh [--sleep DETIK=1800] [--max-rounds N=500] [--stuck N=3] [--max-total ITERASI] [--prompt TEKS]
#   (slash command plugin tidak tersedia di mode -p; prompt bawaan meminta pemakaian skill lewat Skill tool)
# Lingkungan: AICREW_CLAUDE (default claude), AICREW_PLUGIN_DIR (default: akar plugin ini; sesi -p tidak mewarisi plugin dari --plugin-dir sesi lain), AICREW_CLAUDE_ARGS (mis. --permission-mode ... --max-budget-usd ...),
#   AICREW_TG_TOKEN/AICREW_TG_CHAT (opsional, lewat notify.sh). Jangan memakai --dangerously-skip-permissions.
# Exit: 0 semua issue selesai, 1 error beruntun, 2 buntu (tanpa kemajuan), 3 hanya tersisa needs-principal, 4 batas total.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# jaga Mac tetap bangun selama loop
[ -z "${AICREW_CAFF:-}" ] && command -v caffeinate >/dev/null 2>&1 && AICREW_CAFF=1 exec caffeinate -i bash "$0" "$@"
sleep_s=1800; max_rounds=500; stuck_max=3; max_total=""; prompt="Gunakan skill aicrew:orchestrate (panggil lewat Skill tool) di repo ini sekarang dan ikuti sampai selesai atau sampai aturan berhenti. Mode tanpa pengawasan: jangan bertanya ke owner; tandai dan lanjut."
while [ $# -gt 0 ]; do case "$1" in
  --sleep) sleep_s="$2"; shift 2 ;; --max-rounds) max_rounds="$2"; shift 2 ;; --stuck) stuck_max="$2"; shift 2 ;;
  --max-total) max_total="$2"; shift 2 ;; --prompt) prompt="$2"; shift 2 ;; *) echo "argumen tak dikenal: $1" >&2; exit 64 ;; esac; done
claude="${AICREW_CLAUDE:-claude}"
g="$(git rev-parse --git-common-dir)" && d="$(cd "$g/.." && pwd)/.aicrew"; mkdir -p "$d"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$d/autopilot.log"; printf '%s\n' "$*" > "$d/autopilot.status"; }
note() { log "$*"; command -v jq >/dev/null && jq -n --arg m "$*" '{message:$m}' | bash "$here/notify.sh"; return 0; }
fingerprint() { { gh issue list --state all --limit 200 --json number,state,labels; gh pr list --state all --limit 200 --json number,state; } | shasum | cut -d' ' -f1; }

errs=0; same=0; was_limit=0; last="$(fingerprint)"
for ((i=1; i<=max_rounds; i++)); do
  # issue berlabel di-integrasi sudah selesai (menunggu merge ke main oleh owner): bukan pekerjaan tersisa
  open="$(gh issue list --state open --limit 200 --json number,labels | jq '[.[]|select(.labels|map(.name)|index("di-integrasi")|not)]')"
  n_open="$(jq length <<<"$open")"
  n_wait="$(jq '[.[]|select(.labels|map(.name)|index("needs-principal"))]|length' <<<"$open")"
  [ "$n_open" = 0 ] && { note "autopilot: semua issue selesai (putaran $((i-1)))"; exit 0; }
  [ "$n_open" = "$n_wait" ] && { note "autopilot: $n_open issue tersisa semuanya needs-principal; butuh keputusan owner"; exit 3; }
  if [ -n "$max_total" ]; then bash "$here/budget.sh" check 999999 999 "" "$max_total" >/dev/null; [ $? = 4 ] && { note "autopilot: batas total iterasi ($max_total) tercapai"; exit 4; }; fi

  bash "$here/budget.sh" newrun
  out="$d/round-$i.log"; log "putaran $i: $n_open issue terbuka ($n_wait needs-principal)"
  # shellcheck disable=SC2086
  "$claude" --plugin-dir "${AICREW_PLUGIN_DIR:-$here/..}" -p "$prompt" ${AICREW_CLAUDE_ARGS:-} </dev/null >"$out" 2>&1; rc=$?

  # limit: cari di ekor keluaran saja (laporan orkestrator bisa memuat kata "batas")
  if tail -n 20 "$out" | grep -qiE 'usage limit|rate.?limit|limit (reached|will reset)|resets? (at|in)'; then
    [ "$was_limit" = 0 ] && note "autopilot: kena limit, menunggu $((sleep_s/60)) menit lalu coba lagi"
    was_limit=1; sleep "$sleep_s"; continue
  fi
  [ "$was_limit" = 1 ] && note "autopilot: lanjut setelah limit" && was_limit=0
  if [ "$rc" != 0 ]; then
    errs=$((errs+1)); log "putaran $i: gagal rc=$rc ($errs berturut-turut), lihat $out"
    [ "$errs" -ge 3 ] && { note "autopilot: 3 putaran gagal beruntun (rc=$rc); berhenti, lihat $d"; exit 1; }
    sleep "${AICREW_ERR_SLEEP:-60}"; continue
  fi
  errs=0
  now="$(fingerprint)"
  if [ "$now" = "$last" ]; then same=$((same+1)); else same=0; last="$now"; fi
  [ "$same" -ge "$stuck_max" ] && { note "autopilot: buntu, $stuck_max putaran tanpa perubahan di issue/PR; berhenti"; exit 2; }
done
note "autopilot: batas putaran ($max_rounds) tercapai"; exit 1
