#!/usr/bin/env bash
# aicrew board-init: buat (atau pakai ulang) GitHub Project untuk repo ini, tautkan, seragamkan opsi Status.
# Pakai: board-init.sh <owner> <judul> [nomor-project-yang-sudah-ada]   -> mencetak nomor project di baris terakhir.
# Opsi Status: Backlog, Ready, In progress, In review, Done. Hanya mengganti opsi bila project BELUM berisi kartu
# (mengganti opsi menghapus status kartu yang ada). Juga membuat view papan (BOARD_LAYOUT) bila belum ada. Butuh scope gh 'project'.
# Workflow "Item closed" (kartu otomatis ke Done saat issue ditutup) TIDAK bisa diaktifkan lewat API (hanya deleteProjectV2Workflow yang ada): nyalakan di UI Project > Workflows.
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
  [ "$items" = 0 ] || { echo "board-init: project $num berisi kartu; opsi Status tidak diganti (pakai nama status yang ada)" >&2; echo "board-init: langkah manual di UI project: kolom 'Parent issue', Group by -> Parent issue, dan view 'Journeys' (filter label:epic); tidak ada API untuk tampilan." >&2
echo "$num"; exit 0; }
  jq -n --arg f "$fid" --argjson w "$want" '{query:"mutation($i:UpdateProjectV2FieldInput!){updateProjectV2Field(input:$i){clientMutationId}}",
    variables:{i:{fieldId:$f,singleSelectOptions:[$w[]|{name:.,color:"GRAY",description:""}]}}}' \
  | gh api graphql --input - >/dev/null
fi
# view papan (BOARD_LAYOUT): project baru hanya punya view TABLE; dibuat bila belum ada
pid="$(gh project view "$num" --owner "$owner" --format json -q .id)"
layouts="$(gh api graphql -f query='query($p:ID!){node(id:$p){... on ProjectV2{views(first:50){nodes{layout}}}}}' -f p="$pid" -q '[.data.node.views.nodes[].layout]' 2>/dev/null || echo '[]')"
if ! grep -q BOARD_LAYOUT <<<"$layouts"; then
  jq -n --arg p "$pid" '{query:"mutation($i:CreateProjectV2ViewInput!){createProjectV2View(input:$i){projectV2View{id}}}",
    variables:{i:{projectId:$p,name:"Board",layout:"BOARD_LAYOUT"}}}' | gh api graphql --input - >/dev/null \
  || echo "board-init: gagal membuat view papan (project tetap berguna sebagai tabel)" >&2
fi
echo "$num"
