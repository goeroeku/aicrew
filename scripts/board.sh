#!/usr/bin/env bash
# aicrew board: pindahkan kartu issue di GitHub Project. Pakai: board.sh <owner> <nomor-project> <issue> <nama-status>
# Contoh: board.sh goeroeku 2 3 "In review" (nama status tanpa beda huruf besar/kecil; bawaan GitHub: Backlog, Ready, In progress, In review, Done). Butuh scope gh 'project'. Kartu belum ada -> ditambahkan.
# Gagal tidak fatal bagi alur: label tetap sumber status; skrip ini hanya cermin kanban (exit != 0 = laporkan, lanjut).
set -euo pipefail
owner="${1:?owner}"; num="${2:?nomor project}"; issue="${3:?nomor issue}"; status="${4:?status}"
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
