#!/usr/bin/env bash
# aicrew board: pindahkan kartu issue di GitHub Project. Pakai: board.sh <owner> <nomor-project> <issue> <nama-status>
# Contoh: board.sh goeroeku 2 3 "In review" (nama status tanpa beda huruf besar/kecil; bawaan GitHub: Backlog, Ready, In progress, In review, Done). Butuh scope gh 'project'. Kartu belum ada -> ditambahkan.
# --sync (board.sh <owner> <nomor> --sync): issue yang ditutup tanpa PR dipindah ke Done bila "Kartu Done: agen-setelah-merge".
# Gagal tidak fatal bagi alur: label tetap sumber status; skrip ini hanya cermin kanban (exit != 0 = laporkan, lanjut).
set -euo pipefail
owner="${1:?owner}"; num="${2:?nomor project}"
if [ "${3:-}" = "--sync" ]; then
  # status epic dari anak (daftar centang "- [ ] #n" di badan epic): ada anak berjalan -> In progress; semua anak selesai -> In review
  # (siap ditutup owner); selain itu Backlog. Epic yang belum ada di board ditambahkan. Berlaku untuk semua mode Kartu Done.
  items="$(gh project item-list "$num" --owner "$owner" --limit 200 --format json)"
  st_of() { jq -r --argjson n "$1" '.items[]|select(.content.number==$n and .content.type=="Issue")|.status // empty' <<<"$items" | head -1; }
  states="$(gh issue list --state all --limit 200 --json number,state)"
  while read -r e; do
    [ -n "$e" ] || continue
    en="$(jq .number <<<"$e")"; kids="$(jq -r '.body // ""' <<<"$e" | grep -oE '^- \[[ xX]\] #[0-9]+' | grep -oE '[0-9]+$' || true)"
    [ -n "$kids" ] || continue
    unfinished=0; active=0
    for k in $kids; do
      ks="$(jq -r --argjson n "$k" '.[]|select(.number==$n)|.state' <<<"$states")"; ks_board="$(st_of "$k")"
      [ "$ks" = OPEN ] && [ "$ks_board" != Done ] && unfinished=1
      [ "$ks" = OPEN ] && case "$ks_board" in "In progress"|"In review") active=1 ;; esac
    done
    if [ "$unfinished" = 0 ]; then want="In review"; elif [ "$active" = 1 ]; then want="In progress"; else want=Backlog; fi
    [ "$(st_of "$en")" = "$want" ] || bash "$0" "$owner" "$num" "$en" "$want" || true
  done < <(gh issue list --state open --label epic --limit 100 --json number,body | jq -c '.[]')
  # cerminkan issue yang ditutup TANPA PR ke Done, hanya bila WORKFLOW.md menulis "Kartu Done: agen-setelah-merge"
  grep -qE '^[- ]*Kartu Done: *agen-setelah-merge' docs/WORKFLOW.md 2>/dev/null || { echo "board --sync: Kartu Done bukan agen-setelah-merge; tidak ada yang diubah"; exit 0; }
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
