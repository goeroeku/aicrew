#!/usr/bin/env bash
# aicrew board: pindahkan kartu issue di GitHub Project. Pakai: board.sh <owner> <nomor-project> <issue> <nama-status>
# Contoh: board.sh goeroeku 2 3 "In review" (nama status tanpa beda huruf besar/kecil; bawaan GitHub: Backlog, Ready, In progress, In review, Done). Butuh scope gh 'project'. Kartu belum ada -> ditambahkan.
# --sync-cards [--dry-run]: pindahkan kartu task (Backlog/Ready/In progress/In review) dari label, PR, worktree, dan blocker; hanya maju, selisih saja (#69).
# --sync (board.sh <owner> <nomor> --sync): status + progres epic, issue yang ditutup tanpa PR dipindah ke Done bila "Done card: agent-after-merge", dan (opsional) menutup issue di-integrasi.
# Gagal tidak fatal bagi alur: label tetap sumber status; skrip ini hanya cermin kanban (exit != 0 = laporkan, lanjut).
set -euo pipefail
source "$(dirname "$0")/ghx.sh"  # cadangan REST saat GraphQL kena batas
source "$(dirname "$0")/lib/msg.sh"
ghx_require_github board.sh
# anak proses tidak boleh yatim (#154): penjaga (lib/guard.sh) berjalan di latar: induk dimatikan pemanggil (TERM/INT/timeout) -> keturunannya (gh/jq) ikut dimatikan; batas waktu internal
# AICREW_BOARD_TIMEOUT (bawaan 300 dtk, 0 = mati) menghentikan skrip sendiri. board.sh TIDAK memasang trap EXIT (bash menunda TERM selama perintah latar depan bila ada trap): berkas sementara
# dihapus penjaga setelah induk selesai (<= 0,5 dtk).
trap - EXIT
_bd="$(mktemp -d "${TMPDIR:-/tmp}/board.XXXXXX")"; plan="$_bd/plan"
bash "$(dirname "$0")/lib/guard.sh" "$$" "${AICREW_BOARD_TIMEOUT:-300}" "$_bd" "$GHX_STATE" >/dev/null 2>&1 &
if [ "$#" -lt 3 ] || { [ "$3" != "--sync" ] && [ "$3" != "--sync-cards" ] && [ "$#" -lt 4 ]; }; then   # --apply butuh berkas sebagai argumen ke-4
  echo "$(msg board.usage)" >&2; exit 64
fi
owner="$1"; num="$2"
if [ "$3" = "--sync-cards" ]; then   # status kartu task dari label/PR/worktree/blocker (#69); pemetaan di lib/card-status.sh
  [ -z "${4:-}" ] || [ "${4:-}" = "--dry-run" ] || { echo "board: argumen tak dikenal: $4" >&2; exit 64; }
  . "$(dirname "$0")/lib/card-sync.sh"; card_sync "$owner" "$num" "$([ "${4:-}" = "--dry-run" ] && echo 1 || echo 0)"; exit 0
fi
if [ "${3:-}" = "--sync" ]; then
  # status epic dari anaknya: sub-issue native bila ada, selain itu daftar centang "- [ ] #n" (kotak centang tidak pernah dicentang otomatis,
  # jadi status anak dibaca dari issue/board, bukan dari kotaknya). Ada anak berjalan atau sebagian sudah Done -> In progress; semua anak
  # selesai -> In review (siap ditutup owner) HANYA bila ada anak bukan-discovery dan epic tak berlabel belum-dipecah; selain itu Backlog.
  # Progres ("6/9 Done, 1 In progress") ditulis ke satu komentar epic bertanda. Epic yang belum ada di board ditambahkan.
  skipped=0; cards=1  # langkah yang butuh data khusus GraphQL, atau kartu yang ditolak REST (403/404), dilewati dan dihitung
  finish() { [ "$skipped" = 0 ] || echo "PERINGATAN: $skipped langkah dilewati (batas GraphQL), jalankan --sync lagi setelah reset" >&2; exit 0; }
  items="$(ghx_items "$owner" "$num")" || { r=$?; [ "$r" = 77 ] || exit "$r"; items='{"items":[]}'; cards=0; skipped=$((skipped+1)); }
  st_of() { jq -r --argjson n "$1" '.items[]|select(.content.number==$n and .content.type=="Issue")|.status // empty' <<<"$items" | head -1; }
  states="$(ghx_issues all - 200 number,state,labels)"
  repo="$(ghx_repo)"
  # WORKFLOW terbaru (bisa di cabang integrasi, bukan checkout aktif)
  wfc="$(bash "$(dirname "$0")/workflow.sh")"
  disc="$(bash "$(dirname "$0")/label.sh" discovery)"; nsl="$(bash "$(dirname "$0")/label.sh" notsplit --json)"
  while read -r e; do
    [ -n "$e" ] || continue
    en="$(jq .number <<<"$e")"; kids="$(gh api "repos/$repo/issues/$en/sub_issues" --jq '.[].number' 2>/dev/null || true)"
    [[ "$kids" =~ ^[0-9[:space:]]+$ ]] || kids=""
    [ -n "$kids" ] || kids="$(jq -r '.body // ""' <<<"$e" | grep -oE '^- \[[ xX]\] #[0-9]+' | grep -oE '[0-9]+$' || true)"
    [ -n "$kids" ] || continue
    total=0; done_n=0; active=0; real=0; unfinished=0
    for k in $kids; do
      ks="$(jq -r --argjson n "$k" '.[]|select(.number==$n)|.state' <<<"$states")"; ks_board="$(st_of "$k")"
      kl="$(jq -r --argjson n "$k" '.[]|select(.number==$n)|(.labels // [])|map(.name)|join(" ")' <<<"$states")"
      total=$((total+1))
      if [ "$ks" = CLOSED ] || [ "$ks_board" = Done ]; then done_n=$((done_n+1)); else unfinished=1; fi
      [ "$ks" = OPEN ] && case "$ks_board" in "In progress"|"In review") active=$((active+1)) ;; esac
      is_disc=0; for dl in $disc; do grep -qwF -- "$dl" <<<"$kl" && is_disc=1; done; [ "$is_disc" = 1 ] || real=1
    done
    notsplit=0; jq -e --argjson ls "$nsl" '(.labels // [])|map(.name) as $n|any($ls[]; . as $x|$n|index($x))' <<<"$e" >/dev/null 2>&1 && notsplit=1
    if [ "$unfinished" = 0 ] && [ "$real" = 1 ] && [ "$notsplit" = 0 ]; then want="In review"
    elif [ "$active" -gt 0 ] || [ "$done_n" -gt 0 ]; then want="In progress"; else want=Backlog; fi
    [ "$cards" = 0 ] || [ "$(st_of "$en")" = "$want" ] || bash "$0" "$owner" "$num" "$en" "$want" || true
    [ "$cards" = 1 ] || continue  # kartu ditolak: angka Done dari data kosong akan salah; jangan menimpa komentar progres
    prog="aicrew-progress: $done_n/$total Done"; [ "$active" -gt 0 ] && prog="$prog, $active In progress"
    [ "$want" = "In review" ] && prog="$prog; semua anak selesai, siap ditinjau pemilik untuk ditutup"
    cid="$(gh api "repos/$repo/issues/$en/comments" --jq '[.[]|select(.body|startswith("<!-- aicrew-progress -->"))][0]|"\(.id)\t\(.body)"' 2>/dev/null || true)"
    cbody="<!-- aicrew-progress -->"$'\n'"$prog"
    if [ -z "$cid" ] || [ "$cid" = "null"$'\t'"null" ]; then gh api -X POST "repos/$repo/issues/$en/comments" -f body="$cbody" >/dev/null 2>&1 || true
    elif [ "${cid#*$'\t'}" != "$cbody" ]; then gh api -X PATCH "repos/$repo/issues/comments/${cid%%$'\t'*}" -f body="$cbody" >/dev/null 2>&1 || true; fi
  done < <(ghx_issues open epic 100 number,body,labels | jq -c '.[]')
  # opsional: tutup issue anak yang sudah masuk cabang integrasi (GitHub hanya menutup issue lewat merge ke cabang bawaan,
  # jadi progres sub-issue tertahan 0%); WORKFLOW.md: "Close issues after integration merge: yes"
  if grep -qE '^[- ]*Close issues after integration merge: *yes' <<<"$wfc"; then
    wl="$(bash "$(dirname "$0")/label.sh" waiting --json)"
    for n in $(for il in $(bash "$(dirname "$0")/label.sh" integrated --all); do ghx_issues open "$il" 200 number,labels; done | jq -r --argjson w "$wl" '.[]|select((.labels|map(.name)|index("epic"))|not)|select(((.labels|map(.name)) as $n|any($w[]; . as $x|$n|index($x)))|not)|.number' | sort -un); do
      # hanya bila tepat satu PR merged dari issue-<n> dan terbukti masuk cabang integrasi (#28); selain itu tidak ditutup dan dilaporkan
      prs="$(gh api "repos/$repo/pulls?state=all&head=${repo%%/*}:issue-$n&per_page=100" 2>/dev/null | jq -r '[.[]|select(.merged_at!=null)|.number]|join(" ")' 2>/dev/null)" || prs=""
      case "$prs" in ""|*" "*) echo "$(msg board.not_closed_prs "$n" "$n" "${prs:-$(msg board.none)}")"; continue ;; esac
      if why="$(bash "$(dirname "$0")/integrated.sh" "$prs" 2>&1)"; then ghx_issue_close "$n" "Sudah masuk cabang integrasi; ditutup sesuai WORKFLOW.md." || true
      else echo "$(msg board.not_closed_why "$n" "$why")"; fi
    done
  fi
  # cerminkan issue yang ditutup TANPA PR ke Done, hanya bila WORKFLOW.md menulis "Done card: agent-after-merge"
  grep -qE '^[- ]*Done card: *agent-after-merge' <<<"$wfc" || { echo "$(msg board.done_not_agent)"; finish; }
  [ "$cards" = 1 ] || { skipped=$((skipped+1)); finish; }
  : > "$plan"
  done_items="$(ghx_items "$owner" "$num")" || { skipped=$((skipped+1)); finish; }
  done_n="$(jq -r '.items[]|select(.status=="Done" and .content.type=="Issue")|.content.number' <<<"$done_items")"
  # closedByPullRequestsReferences hanya ada di GraphQL: pada mode cadangan langkah ini dilewati (bukan ditebak)
  r=0; closed="$(ghx_gql gh issue list --state closed --limit 200 --json number,labels,closedByPullRequestsReferences)" || r=$?
  if [ "$r" = 75 ]; then skipped=$((skipped+1)); finish; elif [ "$r" != 0 ]; then exit "$r"; fi
  # issue ditutup lewat PR (ke cabang mana pun) hanya dicerminkan bila kartunya belum bernilai status (#111); kartu ber-status diurus alur merge
  nostat="$(jq -r '.items[]|select(.content.type=="Issue" and ((.status // "")==""))|.content.number' <<<"$done_items")"
  for n in $(jq -r --arg ns "$nostat" '.[]|select(((.closedByPullRequestsReferences|length)==0 or (.number as $x|$ns|split("\n")|index($x|tostring))!=null) and ((.labels // [])|map(.name)|index("epic")|not))|.number' <<<"$closed"); do
    grep -qx "$n" <<<"$done_n" || printf '%s\tDone\n' "$n" >> "$plan"   # dikumpulkan: satu proses --apply memindahkan semuanya (bukan satu proses board.sh per kartu, #154)
  done
  if [ -s "$plan" ]; then bash "$0" "$owner" "$num" --apply "$plan" || true; fi
  exit 0
fi
if [ "$3" = "--apply" ]; then   # mode batch (#154): board.sh <owner> <proj> --apply <berkas|->, satu baris "<issue><TAB><status>"; ambil field dan item SEKALI, ubah kartu satu per satu
  src="${4:?berkas rencana}"; [ "$src" = - ] || [ -r "$src" ] || { echo "$(msg board.plan_unreadable "$src")" >&2; exit 64; }
  field="$(ghx_status_field "$owner" "$num")"; [ -n "$field" ] || { echo "$(msg board.no_status_field "$num")" >&2; exit 1; }
  fid="$(jq -r .id <<<"$field")"; items="$(ghx_items "$owner" "$num")" || exit $?
  bad=0; moved=0
  if [ "$src" = - ]; then exec 3<&0; else exec 3< "$src"; fi
  while IFS=$'\t' read -r issue status <&3; do
    [ -n "$issue" ] && [ "${issue#\#}" = "$issue" ] || continue
    [[ "$issue" =~ ^[0-9]+$ ]] && [ -n "$status" ] || { echo "board: baris rencana tak valid: $issue" >&2; bad=$((bad+1)); continue; }
    oid="$(jq -r --arg s "$status" '.options[] | select(.name|ascii_downcase==($s|ascii_downcase)) | .id' <<<"$field")"
    [ -n "$oid" ] || { echo "$(msg board.status_missing_issue "$status" "$issue")" >&2; bad=$((bad+1)); continue; }
    item="$(jq -r --argjson n "$issue" '.items[] | select(.content.number==$n and .content.type=="Issue") | .id' <<<"$items" | head -1)"
    if [ -z "$item" ]; then
      item="$(ghx_card_add "$owner" "$num" "$issue")" || { echo "$(msg board.card_add_failed "$issue")" >&2; bad=$((bad+1)); continue; }
      items="$(jq -c --argjson n "$issue" --arg id "$item" '.items += [{id:$id,status:null,content:{number:$n,type:"Issue"}}]' <<<"$items")"
    fi
    if ghx_card_set "$owner" "$num" "$item" "$fid" "$oid"; then echo "board: #$issue -> $status"; moved=$((moved+1)); else echo "$(msg board.move_failed "$issue")" >&2; bad=$((bad+1)); fi
  done
  echo "$(msg board.apply_summary "$moved" "$bad")"; [ "$bad" = 0 ]; exit $?
fi
issue="${3:?nomor issue}"; status="${4:?status}"
field="$(ghx_status_field "$owner" "$num")"
[ -n "$field" ] || { echo "$(msg board.no_status_field "$num")" >&2; exit 1; }
fid="$(jq -r .id <<<"$field")"
oid="$(jq -r --arg s "$status" '.options[] | select(.name|ascii_downcase==($s|ascii_downcase)) | .id' <<<"$field")"
[ -n "$oid" ] || { echo "$(msg board.status_missing_choices "$status" "$(jq -r '[.options[].name]|join(", ")' <<<"$field")")" >&2; exit 1; }
item="$(ghx_items "$owner" "$num" | jq -r --argjson n "$issue" '.items[] | select(.content.number==$n and .content.type=="Issue") | .id' | head -1)"
[ -n "$item" ] || item="$(ghx_card_add "$owner" "$num" "$issue")"
ghx_card_set "$owner" "$num" "$item" "$fid" "$oid"
echo "board: #$issue -> $status"
