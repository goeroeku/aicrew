#!/usr/bin/env bash
# aicrew epic-link: pasang issue anak ke epic (daftar centang di badan epic + sub-issue native GitHub).
#   epic-link.sh <epic> <anak...>          pasang tiap anak ke epic
#   epic-link.sh --check                   daftar issue terbuka non-epic tanpa induk ("yatim: #n judul"); exit 3 bila ada
#   epic-link.sh --inherit <sumber> <anak> anak mewarisi epic dari issue sumber (sub-issue native, cadangan: daftar centang); exit 3 bila sumber yatim
# Idempoten. Sub-issue native butuh id numerik issue (bukan nomor). Gagal native tidak fatal: daftar centang tetap terpasang.
set -euo pipefail
source "$(dirname "$0")/ghx.sh"  # cadangan REST saat GraphQL kena batas
repo="$(ghx_repo)"
if [ "${1:-}" = "--check" ]; then
  epics="$(ghx_issues open epic 100 number,body)"; orphan=0
  np="$(bash "$(dirname "$0")/label.sh" noparent --json)"  # yatim yang disengaja (mis. payung tindak lanjut) diberi label ini
  while read -r i; do
    [ -n "$i" ] || continue; n="$(jq .number <<<"$i")"
    p="$(gh api "repos/$repo/issues/$n/parent" --jq .number 2>/dev/null || true)"; [[ "$p" =~ ^[0-9]+$ ]] && continue
    jq -r '.[].body // ""' <<<"$epics" | grep -qE "^- \[[ xX]\] #$n\b" && continue
    echo "yatim: #$n $(jq -r .title <<<"$i")"; orphan=1
  done < <(open="$(ghx_issues open - 200 number,title,labels)"; [ "$(jq length <<<"$open")" -lt 200 ] || echo "epic-link --check: 200 issue terbuka pertama saja diperiksa; hasil bisa tidak lengkap" >&2
           jq -c --argjson np "$np" '.[]|select(((.labels|map(.name)) as $n|($n|index("epic")) or any($np[]; . as $x|$n|index($x)))|not)' <<<"$open")
  exit $((orphan*3))
fi
if [ "${1:-}" = "--inherit" ]; then
  src="${2:?issue sumber}"; kid="${3:?issue anak}"
  epic="$(gh api "repos/$repo/issues/$src/parent" --jq .number 2>/dev/null || true)"
  if ! [[ "$epic" =~ ^[0-9]+$ ]]; then
    epic=""
    while read -r e; do
      [ -n "$e" ] || continue
      if jq -r '.body // ""' <<<"$e" | grep -qE "^- \[[ xX]\] #$src\b"; then epic="$(jq .number <<<"$e")"; break; fi
    done < <(ghx_issues open epic 100 number,body | jq -c '.[]')
  fi
  [ -n "$epic" ] || { echo "epic-link: #$src tidak punya epic induk; #$kid yatim" >&2; exit 3; }
  set -- "$epic" "$kid"
fi
epic="${1:?epic}"; shift; [ "$#" -gt 0 ] || { echo "pakai: epic-link.sh <epic> <anak...>" >&2; exit 64; }
for kid in "$@"; do
  # baca ulang tepat sebelum menulis dan verifikasi sesudahnya: dua proses yang menambah anak bersamaan bisa saling menimpa; coba lagi
  for try in 1 2 3; do
    body="$(ghx_issue_body "$epic")"
    grep -qE "^- \[[ xX]\] #$kid\b" <<<"$body" && break
    ghx_issue_set_body "$epic" "$body"$'\n'"- [ ] #$kid"
    sleep "0.$((try*3))"; ghx_issue_body "$epic" | grep -qE "^- \[[ xX]\] #$kid\b" && break
  done
  ghx_issue_body "$epic" | grep -qE "^- \[[ xX]\] #$kid\b" || { echo "epic-link: daftar centang #$kid di epic #$epic gagal terpasang setelah 3 percobaan (tertimpa proses lain?)" >&2; exit 1; }
  id="$(gh api "repos/$repo/issues/$kid" --jq .id)"
  gh api -X POST "repos/$repo/issues/$epic/sub_issues" -F sub_issue_id="$id" >/dev/null 2>&1 || echo "epic-link: sub-issue native #$kid tidak terpasang (mungkin sudah)" >&2
  echo "epic-link: #$kid -> epic #$epic"
done
