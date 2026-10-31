#!/usr/bin/env bash
# aicrew board: pindahkan kartu issue di GitHub Project. Pakai: board.sh <owner> <nomor-project> <issue> <nama-status>
# Contoh: board.sh goeroeku 2 3 "In review" (nama status tanpa beda huruf besar/kecil; bawaan GitHub: Backlog, Ready, In progress, In review, Done). Butuh scope gh 'project'. Kartu belum ada -> ditambahkan.
# --sync (board.sh <owner> <nomor> --sync): status + progres epic, issue yang ditutup tanpa PR dipindah ke Done bila "Kartu Done: agen-setelah-merge", dan (opsional) menutup issue di-integrasi.
# Gagal tidak fatal bagi alur: label tetap sumber status; skrip ini hanya cermin kanban (exit != 0 = laporkan, lanjut).
set -euo pipefail
owner="${1:?owner}"; num="${2:?nomor project}"
if [ "${3:-}" = "--sync" ]; then
  # status epic dari anaknya: sub-issue native bila ada, selain itu daftar centang "- [ ] #n" (kotak centang tidak pernah dicentang otomatis,
  # jadi status anak dibaca dari issue/board, bukan dari kotaknya). Ada anak berjalan atau sebagian sudah Done -> In progress; semua anak
  # selesai -> In review (siap ditutup owner) HANYA bila ada anak bukan-discovery dan epic tak berlabel belum-dipecah; selain itu Backlog.
  # Progres ("6/9 Done, 1 In progress") ditulis ke satu komentar epic bertanda. Epic yang belum ada di board ditambahkan.
  items="$(gh project item-list "$num" --owner "$owner" --limit 200 --format json)"
  st_of() { jq -r --argjson n "$1" '.items[]|select(.content.number==$n and .content.type=="Issue")|.status // empty' <<<"$items" | head -1; }
  states="$(gh issue list --state all --limit 200 --json number,state,labels)"
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  # WORKFLOW terbaru (bisa di cabang integrasi, bukan checkout aktif)
  wfc="$(bash "$(dirname "$0")/workflow.sh")"
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
      grep -qwE 'discovery|phase:discovery' <<<"$kl" || real=1
    done
    notsplit=0; jq -e '(.labels // [])|map(.name)|index("belum-dipecah")' <<<"$e" >/dev/null 2>&1 && notsplit=1
    if [ "$unfinished" = 0 ] && [ "$real" = 1 ] && [ "$notsplit" = 0 ]; then want="In review"
    elif [ "$active" -gt 0 ] || [ "$done_n" -gt 0 ]; then want="In progress"; else want=Backlog; fi
    [ "$(st_of "$en")" = "$want" ] || bash "$0" "$owner" "$num" "$en" "$want" || true
    prog="aicrew-progress: $done_n/$total Done"; [ "$active" -gt 0 ] && prog="$prog, $active In progress"
    cid="$(gh api "repos/$repo/issues/$en/comments" --jq '[.[]|select(.body|startswith("<!-- aicrew-progress -->"))][0]|"\(.id)\t\(.body)"' 2>/dev/null || true)"
    cbody="<!-- aicrew-progress -->"$'\n'"$prog"
    if [ -z "$cid" ] || [ "$cid" = "null"$'\t'"null" ]; then gh api -X POST "repos/$repo/issues/$en/comments" -f body="$cbody" >/dev/null 2>&1 || true
    elif [ "${cid#*$'\t'}" != "$cbody" ]; then gh api -X PATCH "repos/$repo/issues/comments/${cid%%$'\t'*}" -f body="$cbody" >/dev/null 2>&1 || true; fi
  done < <(gh issue list --state open --label epic --limit 100 --json number,body,labels | jq -c '.[]')
  # opsional: tutup issue anak yang sudah masuk cabang integrasi (GitHub hanya menutup issue lewat merge ke cabang bawaan,
  # jadi progres sub-issue tertahan 0%); WORKFLOW.md: "Tutup issue setelah merge integrasi: ya"
  if grep -qE '^[- ]*Tutup issue setelah merge integrasi: *ya' <<<"$wfc"; then
    for n in $(gh issue list --state open --label "$(bash "$(dirname "$0")/label.sh" integrated)" --limit 200 --json number,labels | jq -r '.[]|select((.labels|map(.name)|index("epic"))|not)|.number'); do
      gh issue close "$n" --comment "Sudah masuk cabang integrasi; ditutup sesuai WORKFLOW.md." >/dev/null || true
    done
  fi
  # cerminkan issue yang ditutup TANPA PR ke Done, hanya bila WORKFLOW.md menulis "Kartu Done: agen-setelah-merge"
  grep -qE '^[- ]*Kartu Done: *agen-setelah-merge' <<<"$wfc" || { echo "board --sync: Kartu Done bukan agen-setelah-merge; tidak ada yang diubah"; exit 0; }
  done_n="$(gh project item-list "$num" --owner "$owner" --limit 200 --format json | jq -r '.items[]|select(.status=="Done" and .content.type=="Issue")|.content.number')"
  for n in $(gh issue list --state closed --limit 200 --json number,closedByPullRequestsReferences | jq -r '.[]|select((.closedByPullRequestsReferences|length)==0)|.number'); do
    grep -qx "$n" <<<"$done_n" || bash "$0" "$owner" "$num" "$n" Done || true
  done
  exit 0
fi
issue="${3:?nomor issue}"; status="${4:?status}"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
pid="$(gh project view "$num" --owner "$owner" --format json -q .id)"
field="$(gh project field-list "$num" --owner "$owner" --format json | jq -c '.fields[] | select(.name=="Status")')"
[ -n "$field" ] || { echo "board: project $num tidak punya field Status" >&2; exit 1; }
fid="$(jq -r .id <<<"$field")"
oid="$(jq -r --arg s "$status" '.options[] | select(.name|ascii_downcase==($s|ascii_downcase)) | .id' <<<"$field")"
[ -n "$oid" ] || { echo "board: status '$status' tidak ada; pilihan: $(jq -r '[.options[].name]|join(", ")' <<<"$field")" >&2; exit 1; }
item="$(gh project item-list "$num" --owner "$owner" --limit 200 --format json \
  | jq -r --argjson n "$issue" '.items[] | select(.content.number==$n and .content.type=="Issue") | .id' | head -1)"
if [ -z "$item" ]; then
  item="$(gh project item-add "$num" --owner "$owner" --url "https://github.com/$repo/issues/$issue" --format json | jq -r .id)"
fi
gh project item-edit --id "$item" --project-id "$pid" --field-id "$fid" --single-select-option-id "$oid" >/dev/null
echo "board: #$issue -> $status"
