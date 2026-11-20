#!/usr/bin/env bash
# aicrew backend-sync: kuras outbox (operasi tulis GitHub yang diantre saat GraphQL dan REST habis, #159 tahap 2). Tidak pernah fatal; exit 0.
#   backend-sync.sh [--status]     --status hanya mencetak jumlah operasi tertunda
# Satu berkas per operasi: <repo>/.aicrew/backend/outbox/<epoch>-<id>.json {id,op,args,ts,tries}. Diklaim dengan mv atomik (dua sinkron paralel tidak saling menimpa).
# Idempoten: tiap operasi memeriksa keadaan jauh dulu (label/komentar bermarka aicrew-op:<id>/penutupan), jadi menerapkan ulang aman.
# Konflik = keadaan jauh berubah dari yang diasumsikan (isu sudah tertutup untuk operasi non-penutupan): tindakan pemilik menang, operasi dilewati,
# dicatat di .aicrew/backend/conflicts.log dan notify.sh dipanggil. Anggaran per panggilan: AICREW_SYNC_BUDGET (bawaan 100), jeda AICREW_SYNC_PAUSE (bawaan 1 dtk).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
export GHX_PERSIST=1 GHX_NOQUEUE=1   # sinkron tidak boleh mengantre ulang dirinya sendiri
source "$here/lib/msg.sh"
source "$here/ghx.sh"
d="$(_ghx_dir)" || exit 0
ob="$d/outbox"; mkdir -p "$ob" "$d/outbox.bad" 2>/dev/null || exit 0
pending() { find "$ob" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
[ "${1:-}" != --status ] || { pending; exit 0; }

notify() { command -v jq >/dev/null && jq -n --arg m "$*" '{message:$m}' | bash "$here/notify.sh" >/dev/null 2>&1; return 0; }
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$d/sync.log"; }

# pulihkan klaim yatim (proses sinkron mati di tengah): *.json.work.<pid> dengan pid mati kembali jadi *.json
for w in "$ob"/*.json.work.[0-9]*; do [ -e "$w" ] || continue
  pid="${w##*.}"; kill -0 "$pid" 2>/dev/null || mv "$w" "${w%.work.*}" 2>/dev/null
done

[ "$(pending)" != 0 ] || exit 0
[ "$(ghx_tier)" != local ] || { echo "$(msg backend.sync_still_local "$(pending)")"; exit 0; }
repo="$(ghx_repo 2>/dev/null)" && [ -n "$repo" ] || { echo "$(msg backend.sync_no_repo)" >&2; exit 0; }

ef="$(mktemp "${TMPDIR:-/tmp}/bsync.err.XXXXXX")"; trap 'rm -f "$ef"' EXIT
# g <gh args>: stdout dari gh; 0 sukses, 11 batas, 12 tak ada (404/410), 1 lain
g() { local out rc=0 e; out="$(gh "$@" 2>"$ef")" || rc=$?
  if [ "$rc" != 0 ]; then e="$(cat "$ef")"
    if ghx_is_limit "$e"; then
      local reset; reset="$(gh api rate_limit --jq '.resources.core.reset' 2>/dev/null)"; [[ "$reset" =~ ^[0-9]+$ ]] || reset=$(( $(date +%s) + 60 ))
      _ghx_state_set rest "$reset"; return 11
    fi
    grep -qE 'HTTP 404|HTTP 410|Not Found' <<<"$e" && return 12
    printf '%s\n' "$e" >&2; return 1
  fi
  printf '%s' "$out"; return 0; }

# aplikasi per operasi -> 0 selesai, 10 konflik (pesan di $conflict), 11 batas, 12 tak ada, 1 gagal lain
conflict=""
issue_state() { g api "repos/$repo/issues/$1" --jq '[.state, ([.labels[].name]|join(","))]|@tsv'; }
marker_present() { local out rc=0   # $2 sudah divalidasi hex (apply); semua halaman komentar
  out="$(g api --paginate "repos/$repo/issues/$1/comments" --jq ".[]|select(.body|contains(\"aicrew-op:$2\"))|.id")" || rc=$?
  [ "$rc" = 0 ] || return $(( rc == 1 ? 2 : rc ))   # 0 ada, 1 tidak ada, 2 gagal membaca, 11/12 seperti g
  [ -n "$out" ]; }
apply() { local op="$1" j="$2" id n label body st labs rc=0
  id="$(jq -r '.id // empty' <<<"$j")"; n="$(jq -r '.args.n // empty' <<<"$j")"
  # berkas outbox dapat ditulis agen: validasi ketat sebelum apa pun masuk URL atau filter (12 = tak valid -> outbox.bad)
  [[ "$id" =~ ^[0-9a-f]{16}$ ]] || return 12
  case "$op" in
    card_set|card_add) for k in owner num item field option; do v="$(jq -r --arg k "$k" '.args[$k] // empty' <<<"$j")"
      [ "$k" = item ] && [ "$op" = card_add ] && continue; [ "$k" = field ] && [ "$op" = card_add ] && continue; [ "$k" = option ] && [ "$op" = card_add ] && continue
      [[ "$v" =~ ^[A-Za-z0-9._-]+$ ]] || return 12; done; [[ "$n" =~ ^[0-9]*$ ]] || return 12 ;;
    label_add|label_remove) [[ "$n" =~ ^[0-9]+$ ]] || return 12
      label="$(jq -r '.args.label // empty' <<<"$j")"; [[ "$label" =~ ^[A-Za-z0-9._:\ -]+$ ]] || return 12 ;;
    comment|issue_body|issue_close) [[ "$n" =~ ^[0-9]+$ ]] || return 12 ;;
  esac
  case "$op" in
    label_add|label_remove|comment|issue_body)
      st="$(issue_state "$n")" || return $?; labs="${st#*$'\t'}"; st="${st%%$'\t'*}"
      [ -n "$st" ] || return 1 ;;
  esac
  case "$op" in
    label_add)
      case ",$labs," in *",$label,"*) return 0 ;; esac   # sudah ada: selesai, walau isu tertutup
      [ "$st" != closed ] || { conflict="issue #$n closed upstream"; return 10; }
      g api -X POST "repos/$repo/issues/$n/labels" -f "labels[]=$label" >/dev/null ;;
    label_remove)
      case ",$labs," in *",$label,"*) g api -X DELETE "repos/$repo/issues/$n/labels/$(jq -rn --arg l "$label" '$l|@uri')" >/dev/null ;; *) return 0 ;; esac ;;
    comment) marker_present "$n" "$id" || rc=$?; [ "$rc" = 0 ] && return 0; [ "$rc" = 1 ] || return "$rc"; rc=0
      [ "$st" != closed ] || { conflict="issue #$n closed upstream"; return 10; }
      body="$(jq -r .args.body <<<"$j")"$'\n\n'"<!-- aicrew-op:$id -->"
      g api -X POST "repos/$repo/issues/$n/comments" -f body="$body" >/dev/null ;;
    issue_body) [ "$st" != closed ] || { conflict="issue #$n closed upstream"; return 10; }
      body="$(jq -r .args.body <<<"$j")"; g api -X PATCH "repos/$repo/issues/$n" -f body="$body" >/dev/null ;;
    issue_close)
      st="$(issue_state "$n")" || return $?; st="${st%%$'\t'*}"; [ -n "$st" ] || return 1
      [ "$st" != closed ] || return 0
      body="$(jq -r '.args.comment // empty' <<<"$j")"
      if [ -n "$body" ]; then marker_present "$n" "$id" || rc=$?; [ "$rc" = 0 ] || [ "$rc" = 1 ] || return "$rc"
        [ "$rc" = 0 ] || g api -X POST "repos/$repo/issues/$n/comments" -f body="$body"$'\n\n'"<!-- aicrew-op:$id -->" >/dev/null || return $?; fi
      g api -X PATCH "repos/$repo/issues/$n" -f state=closed -f state_reason=completed >/dev/null ;;
    card_add) ghx_card_add "$(jq -r .args.owner <<<"$j")" "$(jq -r .args.num <<<"$j")" "$n" >/dev/null ;;
    card_set) ghx_card_set "$(jq -r .args.owner <<<"$j")" "$(jq -r .args.num <<<"$j")" "$(jq -r .args.item <<<"$j")" "$(jq -r .args.field <<<"$j")" "$(jq -r .args.option <<<"$j")" ;;
    *) conflict="unknown op '$op'"; return 10 ;;
  esac
}

budget="${AICREW_SYNC_BUDGET:-100}"; pause="${AICREW_SYNC_PAUSE:-1}"; done_n=0; conf_n=0; fail_n=0; stopped=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$done_n" -lt "$budget" ] || break
  w="$f.work.$$"; mv "$f" "$w" 2>/dev/null || continue   # klaim atomik; sinkron lain yang menang -> lewati
  j="$(cat "$w")"; op="$(jq -r .op <<<"$j" 2>/dev/null)"
  if [ -z "$op" ] || [ "$op" = null ]; then mv "$w" "$d/outbox.bad/$(basename "$f")"; log "bad json $(basename "$f")"; fail_n=$((fail_n+1)); continue; fi
  conflict=""; rc=0; apply "$op" "$j" 2>>"$d/sync.err" || rc=$?
  case "$rc" in
    0) rm -f "$w"; done_n=$((done_n+1)); log "ok $op $(jq -c .args <<<"$j")" ;;
    10) rm -f "$w"; conf_n=$((conf_n+1)); printf '%s %s %s\n' "$(date '+%F %T')" "$op" "$conflict ($(jq -c .args <<<"$j"))" >> "$d/conflicts.log"
        notify "$(msg backend.sync_conflict "$op" "$(jq -r '.args.n // "-"' <<<"$j")" "$conflict")" ;;
    11) mv "$w" "$f"; stopped=1; log "limit during $op"; break ;;
    *) tries=$(( $(jq -r '.tries // 0' <<<"$j") + 1 ))
       if [ "$rc" = 12 ] || [ "$tries" -ge 5 ]; then mv "$w" "$d/outbox.bad/$(basename "$f")"; fail_n=$((fail_n+1)); log "bad $op after $tries tries (rc=$rc)"; notify "$(msg backend.sync_bad "$op" "$tries" "rc=$rc")"
       else jq -c --argjson t "$tries" '.tries=$t' <<<"$j" > "$ob/.tries.$$" && mv "$ob/.tries.$$" "$f" && rm -f "$w"; fail_n=$((fail_n+1)); fi ;;
  esac
  [ "$pause" = 0 ] || sleep "$pause"
done < <(find "$ob" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
if [ "$stopped" = 1 ]; then echo "$(msg backend.sync_limit "$(pending)")"
else echo "$(msg backend.sync_summary "$done_n" "$conf_n" "$fail_n" "$(pending)")"; fi
exit 0
