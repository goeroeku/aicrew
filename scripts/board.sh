#!/usr/bin/env bash
# aicrew board: pindahkan kartu issue di GitHub Project. Pakai: board.sh <owner> <nomor-project> <issue> <nama-status>
# Contoh: board.sh goeroeku 2 3 "In review" (nama status tanpa beda huruf besar/kecil; bawaan GitHub: Backlog, Ready, In progress, In review, Done). Butuh scope gh 'project'. Kartu belum ada -> ditambahkan.
# --sync (board.sh <owner> <nomor> --sync): status + progres epic, issue yang ditutup tanpa PR dipindah ke Done bila "Kartu Done: agen-setelah-merge", dan (opsional) menutup issue di-integrasi.
# Gagal tidak fatal bagi alur: label tetap sumber status; skrip ini hanya cermin kanban (exit != 0 = laporkan, lanjut).
set -euo pipefail
source "$(dirname "$0")/ghx.sh"  # cadangan REST saat GraphQL kena batas
owner="${1:?owner}"; num="${2:?nomor project}"
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
  disc="$(bash "$(dirname "$0")/label.sh" discovery)"; nsl="$(bash "$(dirname "$0")/label.sh" notsplit)"
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
    notsplit=0; jq -e --arg l "$nsl" '(.labels // [])|map(.name)|index($l)' <<<"$e" >/dev/null 2>&1 && notsplit=1
    if [ "$unfinished" = 0 ] && [ "$real" = 1 ] && [ "$notsplit" = 0 ]; then want="In review"
    elif [ "$active" -gt 0 ] || [ "$done_n" -gt 0 ]; then want="In progress"; else want=Backlog; fi
    [ "$cards" = 0 ] || [ "$(st_of "$en")" = "$want" ] || bash "$0" "$owner" "$num" "$en" "$want" || true
    prog="aicrew-progress: $done_n/$total Done"; [ "$active" -gt 0 ] && prog="$prog, $active In progress"
    cid="$(gh api "repos/$repo/issues/$en/comments" --jq '[.[]|select(.body|startswith("<!-- aicrew-progress -->"))][0]|"\(.id)\t\(.body)"' 2>/dev/null || true)"
    cbody="<!-- aicrew-progress -->"$'\n'"$prog"
    if [ -z "$cid" ] || [ "$cid" = "null"$'\t'"null" ]; then gh api -X POST "repos/$repo/issues/$en/comments" -f body="$cbody" >/dev/null 2>&1 || true
    elif [ "${cid#*$'\t'}" != "$cbody" ]; then gh api -X PATCH "repos/$repo/issues/comments/${cid%%$'\t'*}" -f body="$cbody" >/dev/null 2>&1 || true; fi
  done < <(ghx_issues open epic 100 number,body,labels | jq -c '.[]')
  # opsional: tutup issue anak yang sudah masuk cabang integrasi (GitHub hanya menutup issue lewat merge ke cabang bawaan,
  # jadi progres sub-issue tertahan 0%); WORKFLOW.md: "Tutup issue setelah merge integrasi: ya"
  if grep -qE '^[- ]*Tutup issue setelah merge integrasi: *ya' <<<"$wfc"; then
    for n in $(ghx_issues open "$(bash "$(dirname "$0")/label.sh" integrated)" 200 number,labels | jq -r '.[]|select((.labels|map(.name)|index("epic"))|not)|.number'); do
      ghx_issue_close "$n" "Sudah masuk cabang integrasi; ditutup sesuai WORKFLOW.md." || true
    done
  fi
  # cerminkan issue yang ditutup TANPA PR ke Done, hanya bila WORKFLOW.md menulis "Kartu Done: agen-setelah-merge"
  grep -qE '^[- ]*Kartu Done: *agen-setelah-merge' <<<"$wfc" || { echo "board --sync: Kartu Done bukan agen-setelah-merge; tidak ada yang diubah"; finish; }
  [ "$cards" = 1 ] || { skipped=$((skipped+1)); finish; }
  done_items="$(ghx_items "$owner" "$num")" || { skipped=$((skipped+1)); finish; }
  done_n="$(jq -r '.items[]|select(.status=="Done" and .content.type=="Issue")|.content.number' <<<"$done_items")"
  # closedByPullRequestsReferences hanya ada di GraphQL: pada mode cadangan langkah ini dilewati (bukan ditebak)
  r=0; closed="$(ghx_gql gh issue list --state closed --limit 200 --json number,labels,closedByPullRequestsReferences)" || r=$?
  if [ "$r" = 75 ]; then skipped=$((skipped+1)); finish; elif [ "$r" != 0 ]; then exit "$r"; fi
  for n in $(jq -r '.[]|select((.closedByPullRequestsReferences|length)==0 and ((.labels // [])|map(.name)|index("epic")|not))|.number' <<<"$closed"); do
    grep -qx "$n" <<<"$done_n" || bash "$0" "$owner" "$num" "$n" Done || true
  done
  exit 0
fi
issue="${3:?nomor issue}"; status="${4:?status}"
field="$(ghx_status_field "$owner" "$num")"
[ -n "$field" ] || { echo "board: project $num tidak punya field Status" >&2; exit 1; }
fid="$(jq -r .id <<<"$field")"
oid="$(jq -r --arg s "$status" '.options[] | select(.name|ascii_downcase==($s|ascii_downcase)) | .id' <<<"$field")"
[ -n "$oid" ] || { echo "board: status '$status' tidak ada; pilihan: $(jq -r '[.options[].name]|join(", ")' <<<"$field")" >&2; exit 1; }
item="$(ghx_items "$owner" "$num" | jq -r --argjson n "$issue" '.items[] | select(.content.number==$n and .content.type=="Issue") | .id' | head -1)"
[ -n "$item" ] || item="$(ghx_card_add "$owner" "$num" "$issue")"
ghx_card_set "$owner" "$num" "$item" "$fid" "$oid"
echo "board: #$issue -> $status"
