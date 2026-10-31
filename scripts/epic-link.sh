#!/usr/bin/env bash
# aicrew epic-link: pasang issue anak ke epic (daftar centang di badan epic + sub-issue native GitHub).
#   epic-link.sh <epic> <anak...>          pasang tiap anak ke epic
#   epic-link.sh --check                   daftar issue terbuka non-epic tanpa induk ("yatim: #n judul"); exit 3 bila ada
#   epic-link.sh --inherit <sumber> <anak> anak mewarisi epic dari issue sumber (sub-issue native, cadangan: daftar centang); exit 3 bila sumber yatim
# Idempoten. Sub-issue native butuh id numerik issue (bukan nomor). Gagal native tidak fatal: daftar centang tetap terpasang.
set -euo pipefail
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
if [ "${1:-}" = "--check" ]; then
  epics="$(gh issue list --state open --label epic --limit 100 --json number,body)"; orphan=0
  while read -r i; do
    [ -n "$i" ] || continue; n="$(jq .number <<<"$i")"
    p="$(gh api "repos/$repo/issues/$n/parent" --jq .number 2>/dev/null || true)"; [[ "$p" =~ ^[0-9]+$ ]] && continue
    jq -r '.[].body // ""' <<<"$epics" | grep -qE "^- \[[ xX]\] #$n\b" && continue
    echo "yatim: #$n $(jq -r .title <<<"$i")"; orphan=1
  done < <(gh issue list --state open --limit 200 --json number,title,labels | jq -c '.[]|select((.labels|map(.name)|index("epic"))|not)')
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
    done < <(gh issue list --state open --label epic --limit 100 --json number,body | jq -c '.[]')
  fi
  [ -n "$epic" ] || { echo "epic-link: #$src tidak punya epic induk; #$kid yatim" >&2; exit 3; }
  set -- "$epic" "$kid"
fi
epic="${1:?epic}"; shift; [ "$#" -gt 0 ] || { echo "pakai: epic-link.sh <epic> <anak...>" >&2; exit 64; }
for kid in "$@"; do
  # baca ulang tepat sebelum menulis dan verifikasi sesudahnya: dua proses yang menambah anak bersamaan bisa saling menimpa; coba lagi
  for try in 1 2 3; do
    body="$(gh issue view "$epic" --json body -q .body)"
    grep -qE "^- \[[ xX]\] #$kid\b" <<<"$body" && break
    gh issue edit "$epic" --body "$body"$'\n'"- [ ] #$kid" >/dev/null
    sleep "0.$((try*3))"; gh issue view "$epic" --json body -q .body | grep -qE "^- \[[ xX]\] #$kid\b" && break
  done
  id="$(gh api "repos/$repo/issues/$kid" --jq .id)"
  gh api -X POST "repos/$repo/issues/$epic/sub_issues" -F sub_issue_id="$id" >/dev/null 2>&1 || echo "epic-link: sub-issue native #$kid tidak terpasang (mungkin sudah)" >&2
  echo "epic-link: #$kid -> epic #$epic"
done
