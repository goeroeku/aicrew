#!/usr/bin/env bash
# aicrew board-init: buat (atau pakai ulang) GitHub Project untuk repo ini, tautkan, seragamkan opsi Status.
# Pakai: board-init.sh <owner> <judul> [nomor-project-yang-sudah-ada]   -> mencetak nomor project di baris terakhir.
# Opsi Status: Backlog, Ready, In progress, In review, Done. Hanya mengganti opsi bila project BELUM berisi kartu
# (mengganti opsi menghapus status kartu yang ada). Butuh scope gh 'project'.
set -euo pipefail
owner="${1:?owner}"; title="${2:?judul}"; num="${3:-}"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
[ -n "$num" ] || num="$(gh project create --owner "$owner" --title "$title" --format json -q .number)"
gh project link "$num" --owner "$owner" --repo "$repo" >/dev/null 2>&1 || echo "board-init: tautan repo gagal/sudah ada" >&2
field="$(gh project field-list "$num" --owner "$owner" --format json | jq -c '.fields[] | select(.name=="Status")')"
fid="$(jq -r .id <<<"$field")"
want='["Backlog","Ready","In progress","In review","Done"]'
have="$(jq -c '[.options[].name]' <<<"$field")"
if [ "$have" != "$want" ]; then
  items="$(gh project item-list "$num" --owner "$owner" --limit 1 --format json -q '.items|length')"
  [ "$items" = 0 ] || { echo "board-init: project $num berisi kartu; opsi Status tidak diganti (pakai nama status yang ada)" >&2; echo "$num"; exit 0; }
  jq -n --arg f "$fid" --argjson w "$want" '{query:"mutation($i:UpdateProjectV2FieldInput!){updateProjectV2Field(input:$i){clientMutationId}}",
    variables:{i:{fieldId:$f,singleSelectOptions:[$w[]|{name:.,color:"GRAY",description:""}]}}}' \
  | gh api graphql --input - >/dev/null
fi
echo "$num"
