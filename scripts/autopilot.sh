#!/usr/bin/env bash
# aicrew autopilot: jalankan orkestrator berulang (sesi baru tiap putaran) sampai selesai, buntu, atau menunggu owner.
# Tahan limit token/mingguan: bila putaran berakhir karena limit, tidur lalu coba lagi. State ada di GitHub dan .aicrew/,
# jadi putaran baru melanjutkan (skill orchestrate: bagian Resume). Jalankan dari akar repo project. GitHub/gh saja.
#   autopilot.sh [--sleep DETIK=1800] [--max-rounds N=500] [--stuck N=3] [--retry-stuck] [--max-total ITERASI] [--reset-total] [--idle-limit DETIK=1800] [--round-timeout DETIK=0] [--wait DETIK=600] [--wait-max DETIK=604800] [--prompt TEKS]
#   (slash command plugin tidak tersedia di mode -p; prompt bawaan meminta pemakaian skill lewat Skill tool)
# Lingkungan: AICREW_CLAUDE (default claude), AICREW_PLUGIN_DIR (default: akar plugin ini; sesi -p tidak mewarisi plugin dari --plugin-dir sesi lain), AICREW_CLAUDE_ARGS (mis. --permission-mode ... --max-budget-usd ...),
#   AICREW_TG_TOKEN/AICREW_TG_CHAT (opsional, lewat notify.sh). Jangan memakai --dangerously-skip-permissions.
# Watchdog idle (#48): AICREW_IDLE_LIMIT/--idle-limit (bawaan 1800 dtk; 0 = mati), AICREW_ROUND_TIMEOUT/--round-timeout (bawaan 0 = mati), AICREW_IDLE_POLL (30), AICREW_IDLE_IGNORE (pembantu yang tak dihitung sibuk),
#   AICREW_IDLE_GRACE (30) dan AICREW_TERM_GRACE (60): masa tenggang SIGINT -> SIGTERM, AICREW_TRANSCRIPT_DIR (menimpa ~/.claude/projects/<cwd>). Status kesehatan: .aicrew/autopilot.json. Wrapper AICREW_CLAUDE wajib `exec claude ...`.
# Exit: 0 semua issue selesai, 1 error beruntun, 2 buntu (tanpa kemajuan), 5 masih buntu (start ulang dengan keadaan issue/PR sama seperti saat berhenti buntu terakhir; tidak ada putaran dijalankan, --retry-stuck memaksa), 3 hanya tersisa menunggu owner (needs-principal, atau PR terbuka menunggu merge: dipantau murah lewat gh, tanpa claude,
#   sampai ada perubahan atau --wait-max), 4 batas total.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
# jaga Mac tetap bangun selama loop
[ -z "${AICREW_CAFF:-}" ] && command -v caffeinate >/dev/null 2>&1 && AICREW_CAFF=1 exec caffeinate -i bash "$0" "$@"
idle_limit="${AICREW_IDLE_LIMIT:-1800}"; round_timeout="${AICREW_ROUND_TIMEOUT:-0}"; poll="${AICREW_IDLE_POLL:-30}"; cur_round=0
sleep_s=1800; max_rounds=500; stuck_max=3; retry_stuck=0; max_total=""; reset_total=0; wait_s=600; wait_max=604800; prompt="Gunakan skill aicrew:orchestrate (panggil lewat Skill tool) di repo ini sekarang dan ikuti sampai selesai atau sampai aturan berhenti. Mode tanpa pengawasan: jangan bertanya ke owner; tandai dan lanjut."
while [ $# -gt 0 ]; do case "$1" in
  --sleep) sleep_s="$2"; shift 2 ;; --max-rounds) max_rounds="$2"; shift 2 ;; --stuck) stuck_max="$2"; shift 2 ;; --retry-stuck) retry_stuck=1; shift ;; --wait) wait_s="$2"; shift 2 ;; --wait-max) wait_max="$2"; shift 2 ;;
  --idle-limit) idle_limit="$2"; shift 2 ;; --round-timeout) round_timeout="$2"; shift 2 ;;
  --max-total) max_total="$2"; shift 2 ;; --reset-total) reset_total=1; shift ;; --prompt) prompt="$2"; shift 2 ;; *) echo "argumen tak dikenal: $1" >&2; exit 64 ;; esac; done
claude="${AICREW_CLAUDE:-claude}"; L_INT="$(bash "$here/label.sh" integrated --json)"
g="$(git rev-parse --git-common-dir)" && d="$(cd "$g/.." && pwd)/.aicrew"; mkdir -p "$d"; run="$(date +%Y%m%d-%H%M%S)"   # nama unik per jalan untuk arsip keluaran putaran (round-N.log ditimpa tiap jalan)
[ "$reset_total" = 1 ] && rm -f "$d/total"
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$d/autopilot.log"; printf '%s\n' "$*" > "$d/autopilot.status"; }
# status kesehatan (#48): .aicrew/autopilot.json {fase, putaran, idle_sejak_detik, detak}, ditulis atomik; baris pertama autopilot.status tidak berubah
set_phase() { command -v jq >/dev/null 2>&1 || return 0; local t="$d/autopilot.json.tmp.$$"
  jq -nc --arg f "$1" --argjson r "${2:-$cur_round}" --argjson i "${3:-0}" --argjson t "$(date +%s)" '{fase:$f,putaran:$r,idle_sejak_detik:$i,detak:$t}' > "$t" 2>/dev/null && mv "$t" "$d/autopilot.json"; return 0; }
note() { log "$*"; command -v jq >/dev/null && jq -n --arg m "$*" '{message:$m}' | bash "$here/notify.sh"; return 0; }
fingerprint() { { gh issue list --state all --limit 200 --json number,state,labels; gh pr list --state all --limit 200 --json number,state; } | shasum | cut -d' ' -f1; }

# semua issue terbuka hanya menunggu manusia: needs-principal, atau punya PR terbuka (cabang issue-N, konvensi yang sama dengan resume.sh)
has_open_pr() { [ "$(gh pr list --head "issue-$1" --state open --json number,state -q '[.[]|select(.state=="OPEN")]|length' 2>/dev/null)" -ge 1 ] 2>/dev/null; }
is_principal() { jq -e --argjson n "$2" '.[]|select(.number==$n)|.labels|map(.name)|index("needs-principal")' <<<"$1" >/dev/null 2>&1; }
. "$here/lib/blockers.sh"; . "$here/lib/board-ref.sh"   # unsat_blockers, board_ref
# cerminan kanban (#69): papan aktif ("Kanban board: GitHub Project o/n") -> --sync lalu --sync-cards, sekali per iterasi; tidak pernah fatal; AICREW_BOARD_SYNC=0 mematikan.
# Baris log sengaja tidak lewat log(): autopilot.status tetap berisi keadaan putaran.
board_sync() {
  [ "${AICREW_BOARD_SYNC:-1}" != 0 ] || return 0
  local o nm b="${AICREW_BOARD_SH:-$here/board.sh}" out
  read -r o nm < <(bash "$here/workflow.sh" 2>/dev/null | board_ref) || true; [ -n "${nm:-}" ] || return 0
  bash "$b" "$o" "$nm" --sync >/dev/null 2>&1 || printf '%s board: --sync gagal (diabaikan)\n' "$(date '+%F %T')" | tee -a "$d/autopilot.log"
  out="$(bash "$b" "$o" "$nm" --sync-cards 2>&1)" || out="$out"$'\n'"board: --sync-cards gagal (diabaikan)"
  out="$(grep '^board:' <<<"$out" | tail -1)"; [ -z "$out" ] || printf '%s %s\n' "$(date '+%F %T')" "$out" | tee -a "$d/autopilot.log"
  return 0
}
# semua issue terbuka hanya menunggu manusia (#17): needs-principal, PR terbuka, atau semua blocker yang masih terbuka sendiri menunggu (dihitung berulang sampai tetap).
# Hemat kuota GraphQL: issue tanpa blocker terbuka yang bukan needs-principal harus punya PR, selain itu langsung "bukan menunggu" (berhenti di sana, seperti semula); PR issue terblokir dicek belakangan.
waiting_on_owner() {
  local open="$1" n b w="" bl="" ch all nums
  nums=" $(jq -r '.[].number' <<<"$open" | tr '\n' ' ')"
  for n in $nums; do
    if [ -n "$(unsat_blockers "$open" "$n")" ]; then if is_principal "$open" "$n"; then w="$w $n"; else bl="$bl $n"; fi; continue; fi
    if is_principal "$open" "$n" || has_open_pr "$n"; then w="$w $n"; else return 1; fi
  done
  fix() { ch=1; while [ "$ch" = 1 ]; do ch=0
      for n in $bl; do
        case " $w " in *" $n "*) continue ;; esac
        all=1; for b in $(unsat_blockers "$open" "$n"); do case " $w " in *" $b "*) ;; *) all=0 ;; esac; done
        [ "$all" = 0 ] || { w="$w $n"; ch=1; }
      done
    done; }
  fix
  for n in $bl; do case " $w " in *" $n "*) continue ;; esac; if has_open_pr "$n"; then w="$w $n"; else return 1; fi; done
  fix
  for n in $nums; do case " $w " in *" $n "*) ;; *) return 1 ;; esac; done
  return 0
}
# watchdog idle (#48): subshell latar selama satu putaran; claude tetap di latar depan (perintah asinkron dari shell non-interaktif mengabaikan SIGINT).
# Idle = tidak ada berkas berubah di direktori transkrip sesi DAN tidak ada proses turunan selain pembantu (AICREW_IDLE_IGNORE) selama --idle-limit detik.
# Sasaran = satu-satunya anak langsung autopilot ini selain subshell pemantau (wrapper AICREW_CLAUDE wajib `exec claude ...`). Tidak ada sinyal/direktori = tidak ada tindakan.
idle_ignore="${AICREW_IDLE_IGNORE:-codebase-memory|gopls|mcp|typescript-language-server|tsserver}"
descendants() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do echo "$c"; descendants "$c"; done; }
# sleep dibungkus { ...; } 2>/dev/null: stop_watch membunuh sleep yang sedang berjalan; tanpa ini shell mencetak "Terminated: 15 sleep" tiap putaran (#63)
watch_round() { # <awal-epoch> <induk-pid>
  local start="$1" parent="$2" me tdir mark last now target c nm busy idle_ok=1 reason=""
  me="$(sh -c 'echo $PPID')"   # pid subshell ini ($BASHPID tidak ada di bash 3.2)
  tdir="${AICREW_TRANSCRIPT_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')}"
  mark="$d/idle-mark"; touch "$mark"; last="$start"
  case " ${AICREW_CLAUDE_ARGS:-} " in *" --no-session-persistence "*) idle_ok=0; log "putaran $cur_round: --no-session-persistence di AICREW_CLAUDE_ARGS (transkrip tidak ditulis); watchdog idle tidak aktif untuk putaran ini, --round-timeout tetap berlaku" ;; esac
  [ -d "$tdir" ] || { idle_ok=0; log "putaran $cur_round: direktori transkrip tidak ditemukan ($tdir); watchdog idle tidak aktif untuk putaran ini"; }
  while :; do
    { sleep "$poll"; } 2>/dev/null; kill -0 "$parent" 2>/dev/null || return 0; now="$(date +%s)"   # induk mati (mis. SIGTERM) -> pemantau berhenti sendiri
    target="$(pgrep -P "$parent" 2>/dev/null | grep -vx "$me" | head -1)"; [ -n "$target" ] || continue
    if [ "$round_timeout" -gt 0 ] 2>/dev/null && [ $((now-start)) -ge "$round_timeout" ]; then reason="batas waktu putaran ($((now-start)) detik)"
    elif [ "$idle_ok" = 1 ] && [ "$idle_limit" -gt 0 ] 2>/dev/null; then
      if [ -n "$(find "$tdir" -type f -newer "$mark" 2>/dev/null | head -1)" ]; then touch "$mark"; last="$now"; fi
      busy=0
      for c in $(descendants "$target"); do nm="$(basename "$(ps -o comm= -p "$c" 2>/dev/null)" 2>/dev/null)"; [ -n "$nm" ] || continue; printf '%s' "$nm" | grep -Eq "$idle_ignore" || busy=1; done
      [ "$busy" = 0 ] || last="$now"
      set_phase putaran "$cur_round" "$((now-last))"
      [ $((now-last)) -ge "$idle_limit" ] && reason="idle $(((now-last)/60)) menit"
    fi
    [ -n "$reason" ] || continue
    pgrep -P "$parent" 2>/dev/null | grep -vx "$me" | grep -qx "$target" || continue   # pid masih anak langsung autopilot ini
    : > "$d/idle-interrupt"; set_phase idle-diinterupsi "$cur_round" "$((now-last))"
    log "putaran $cur_round: $reason; diinterupsi (SIGINT)"; kill -INT "$target" 2>/dev/null
    # eskalasi: sesi yang mengabaikan SIGINT sudah macet (menggantung = masalah #48). Dicatat setelah AICREW_IDLE_GRACE (30 dtk), SIGTERM setelah AICREW_TERM_GRACE (60 dtk) lagi; tidak pernah SIGKILL
    ig="${AICREW_IDLE_GRACE:-30}"; tg="${AICREW_TERM_GRACE:-60}"; { sleep "$ig"; } 2>/dev/null
    if pgrep -P "$parent" 2>/dev/null | grep -vx "$me" | grep -qx "$target"; then
      log "putaran $cur_round: sesi masih hidup $ig detik setelah SIGINT; menunggu $tg detik lagi"; { sleep "$tg"; } 2>/dev/null
      if pgrep -P "$parent" 2>/dev/null | grep -vx "$me" | grep -qx "$target"; then log "putaran $cur_round: sesi tidak berakhir; dikirim SIGTERM"; kill -TERM "$target" 2>/dev/null; fi
    fi
    return 0
  done
}
wpid=""
stop_watch() { [ -z "$wpid" ] || { pkill -P "$wpid" 2>/dev/null; kill "$wpid" 2>/dev/null; { wait "$wpid"; } 2>/dev/null; wpid=""; }; return 0; }
trap 'stop_watch; rm -f "$d/idle-interrupt"' EXIT
# INT dari pemantau (penanda ada) = putaran idle diakhiri, autopilot lanjut; selain itu Ctrl-C pemilik: matikan pemantau dan sesi, keluar 130
trap 'if [ -f "$d/idle-interrupt" ]; then :; else stop_watch; pkill -INT -P $$ 2>/dev/null; exit 130; fi' INT
rm -f "$d/idle-interrupt"   # penanda basi dari proses yang mati tidak boleh menelan Ctrl-C
errs=0; same=0; was_limit=0; last="$(fingerprint)"
# sidik jari akhir putaran terakhir tersimpan: setelah restart (laptop mati) tanpa perubahan, langsung menunggu, tidak membakar putaran claude
[ "$(cat "$d/last-round-fp" 2>/dev/null)" = "$last" ] && same=1
# buntu berulang (#56): sidik jari saat berhenti buntu disimpan di $d/stuck. Start ulang (supervisor/loop luar) dengan keadaan sama = langsung exit 5 tanpa putaran claude;
# keadaan berubah atau --retry-stuck menghapus penanda.
if [ "$retry_stuck" = 1 ]; then rm -f "$d/stuck"
elif [ -f "$d/stuck" ]; then
  if [ "$(cat "$d/stuck")" = "$last" ]; then
    set_phase stuck 0; log "autopilot: masih buntu: keadaan issue/PR sama seperti saat berhenti buntu terakhir; tidak ada putaran dijalankan (ubah sesuatu, atau pakai --retry-stuck)"; exit 5
  else rm -f "$d/stuck"; fi
fi
for ((i=1; i<=max_rounds; i++)); do
  cur_round=$i
  # issue berlabel integrasi ($L_INT, bawaan integrated; nama lama di-integrasi tetap dikenali) sudah selesai (menunggu merge ke main oleh owner): bukan pekerjaan tersisa
  open="$(gh issue list --state open --limit 200 --json number,labels,body | jq --argjson ls "$L_INT" '[.[]|select((.labels|map(.name)) as $n|(any($ls[]; . as $x|$n|index($x)) or ($n|index("epic")))|not)]')"  # epic = pengelompokan journey, bukan pekerjaan
  n_open="$(jq length <<<"$open")"
  board_sync
  n_wait="$(jq '[.[]|select(.labels|map(.name)|index("needs-principal"))]|length' <<<"$open")"
  [ "$n_open" = 0 ] && { set_phase selesai "$((i-1))"; note "autopilot: semua issue selesai (putaran $((i-1)))"; exit 0; }
  [ "$n_open" = "$n_wait" ] && {
    m="autopilot: $n_open issue tersisa semuanya needs-principal; butuh keputusan owner"; set_phase menunggu-owner
    if [ "$(cat "$d/principal-note" 2>/dev/null)" = "$m" ]; then log "$m"; else note "$m"; printf '%s' "$m" > "$d/principal-note"; fi  # satu notifikasi per keadaan, tidak tiap tick autostart
    exit 3; }
  if [ -n "$max_total" ]; then msg="$(bash "$here/budget.sh" check 999999 999 "" "$max_total")"; [ $? = 4 ] && { note "autopilot: $msg; total kumulatif antar-jalan, nolkan dengan --reset-total atau hapus .aicrew/total"; exit 4; }; fi

  # menunggu owner: sudah ada putaran tanpa perubahan dan semua issue tersisa hanya menunggu manusia -> pantau murah lewat gh (tanpa claude)
  if [ "$same" -ge 1 ] && waiting_on_owner "$open"; then
    wf="$d/waiting-since"; set_phase menunggu-owner
    [ -f "$wf" ] || { date +%s > "$wf"; note "autopilot: menunggu owner ($n_open issue: needs-principal atau PR terbuka menunggu merge); cek tiap $((wait_s/60)) menit, batas $((wait_max/86400)) hari"; }
    since="$(cat "$wf")"
    while :; do
      if [ $(( $(date +%s) - since )) -ge "$wait_max" ]; then
        [ -f "$wf.timeout" ] || { : > "$wf.timeout"; note "autopilot: menunggu owner melewati batas $((wait_max/86400)) hari; berhenti"; }
        exit 3
      fi
      sleep "$wait_s"; now="$(fingerprint)"; [ "$now" != "$last" ] && break
    done
    rm -f "$wf" "$wf.timeout"; last="$now"; same=0; log "autopilot: ada perubahan saat menunggu (mis. merge oleh owner); lanjut putaran"; continue
  fi
  rm -f "$d/principal-note"
  bash "$here/budget.sh" newrun
  out="$d/round-$i.log"; log "putaran $i: $n_open issue terbuka ($n_wait needs-principal)"; set_phase putaran "$i"
  rm -f "$d/idle-interrupt"; rstart="$(date +%s)"
  if [ "$idle_limit" -gt 0 ] 2>/dev/null || [ "$round_timeout" -gt 0 ] 2>/dev/null; then watch_round "$rstart" "$$" & wpid=$!; fi
  # shellcheck disable=SC2086
  "$claude" --plugin-dir "${AICREW_PLUGIN_DIR:-$here/..}" -p "$prompt" ${AICREW_CLAUDE_ARGS:-} </dev/null >"$out" 2>&1; rc=$?
  stop_watch
  interrupted=0; if [ -f "$d/idle-interrupt" ]; then interrupted=1; rm -f "$d/idle-interrupt"; fi   # dibaca sekali lalu dihapus (trap INT sudah selesai memeriksanya)

  # rc tiap putaran dicatat; keluaran yang bergejala (menyebut limit, atau rc != 0) diarsipkan (20 terakhir) supaya limit sungguhan terekam utuh
  printf '%s putaran %s: rc=%s\n' "$(date '+%F %T')" "$i" "$rc" | tee -a "$d/autopilot.log"
  likely=0; tail -n 20 "$out" | grep -qiE 'usage limit|rate.?limit|limit (reached|will reset)|resets? (at|in)' && likely=1
  # putaran yang diakhiri watchdog idle (penanda ada): rc dinormalkan, bukan limit dan bukan gagal; sidik jari dibandingkan seperti biasa (--stuck menghentikan bila berulang)
  if [ "$interrupted" = 1 ]; then rc=0; likely=0; log "putaran $i: diakhiri watchdog idle (rc dinormalkan); daftar issue dimuat ulang di putaran berikut"; fi
  if [ "$likely" = 1 ] || [ "$rc" != 0 ]; then
    mkdir -p "$d/archive"; cp "$out" "$d/archive/round-$run-$i-rc$rc.log"
    ls -1t "$d/archive" | tail -n +21 | while read -r af; do rm -f "$d/archive/$af"; done
  fi
  # limit = teks limit di ekor DAN (rc != 0, atau keluaran pendek <= 3 baris). Laporan orkestrator yang normal panjang dan rc=0 bisa memuat kalimat
  # seperti "No agent hit a usage limit" (kejadian nyata, #24): itu bukan limit. Keluaran pendek dengan rc=0 tetap dianggap limit karena ada laporan
  # bahwa galat API (rate limit) bisa berakhir rc=0.
  # ponytail: heuristik panjang; ganti dengan --output-format json dan is_error bila perlu pasti.
  if [ "$likely" = 1 ] && { [ "$rc" != 0 ] || [ "$(grep -c . "$out")" -le 3 ]; }; then
    [ "$was_limit" = 0 ] && note "autopilot: kena limit, menunggu $((sleep_s/60)) menit lalu coba lagi"
    was_limit=1; set_phase tidur-limit "$i"; sleep "$sleep_s"; continue
  fi
  [ "$likely" = 0 ] || [ "$rc" != 0 ] || log "putaran $i: keluaran menyebut kata limit tetapi rc=0 dan laporan panjang ($(grep -c . "$out") baris); dianggap normal (bukan limit)"
  [ "$was_limit" = 1 ] && note "autopilot: lanjut setelah limit" && was_limit=0
  if [ "$rc" != 0 ]; then
    errs=$((errs+1)); log "putaran $i: gagal rc=$rc ($errs berturut-turut), lihat $out"
    [ "$errs" -ge 3 ] && { note "autopilot: 3 putaran gagal beruntun (rc=$rc); berhenti, lihat $d"; exit 1; }
    sleep "${AICREW_ERR_SLEEP:-60}"; continue
  fi
  errs=0
  now="$(fingerprint)"; printf '%s' "$now" > "$d/last-round-fp"
  if [ "$now" = "$last" ]; then same=$((same+1)); else same=0; last="$now"; fi
  [ "$same" -ge "$stuck_max" ] && { printf '%s' "$now" > "$d/stuck"; set_phase stuck "$i"; note "autopilot: buntu, $stuck_max putaran tanpa perubahan di issue/PR; berhenti"; exit 2; }
done
note "autopilot: batas putaran ($max_rounds) tercapai"; exit 1
