#!/usr/bin/env bash
# aicrew card-sync: board.sh <owner> <proj> --sync-cards [--dry-run] (#69). Di-source oleh board.sh (butuh ghx.sh). Pemetaan ada di card-status.sh; README bagian kanban.
# Data: issue terbuka (GraphQL/REST via ghx), PR lewat REST (satu halaman 100 terbaru; ponytail: PR merged lebih lama dari itu tak terlihat), worktree <repo>-wt-<n>, satu pembacaan papan.
# Hanya kartu yang berubah ditulis (lewat board.sh <issue> <status>). Batas GraphQL dibaca dari header; kurang dari AICREW_BOARD_MIN_GRAPHQL (1500) -> dilewati. Selalu return 0.
_cs_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; _cs_scripts="$(cd "$_cs_lib/.." && pwd)"
. "$_cs_lib/card-status.sh"; . "$_cs_lib/blockers.sh"
card_sync() {
  local owner="$1" num="$2" dry="$3" min="${AICREW_BOARD_MIN_GRAPHQL:-1500}" h rem items all openset repo prs wts il ilj n lb bl pr wt cur want ch=0 sk=0 fail=0 reasons="" r c
  h="$(_ghx_probe)"; rem="$(_ghx_hdr "$h" x-ratelimit-remaining)"
  if [[ "$rem" =~ ^[0-9]+$ ]] && [ "$rem" -lt "$min" ]; then echo "board: graphql sisa $rem < $min, sinkron kartu dilewati"; return 0; fi
  items="$(ghx_items "$owner" "$num")" || { echo "board: papan tak terbaca, sinkron kartu dilewati"; return 0; }
  all="$(ghx_issues open - 200 number,body,labels)" || { echo "board: issue tak terbaca, sinkron kartu dilewati"; return 0; }
  repo="$(ghx_repo)" || { echo "board: repo tak diketahui, sinkron kartu dilewati"; return 0; }
  prs="$(gh api "repos/$repo/pulls?state=all&per_page=100" 2>/dev/null)" || { echo "board: PR tak terbaca, sinkron kartu dilewati"; return 0; }
  il="$(bash "$_cs_scripts/label.sh" integrated --all)" && ilj="$(bash "$_cs_scripts/label.sh" integrated --json)" || { echo "board: label integrated tak terbaca, sinkron kartu dilewati"; return 0; }
  openset="$(jq --argjson ls "$ilj" '[.[]|select((.labels|map(.name)) as $n|(any($ls[]; . as $x|$n|index($x)) or ($n|index("epic")))|not)]' <<<"$all")" || { echo "board: issue tak terurai, sinkron kartu dilewati"; return 0; }  # sama dengan autopilot: epic dan integrated bukan blocker
  wts="$(git worktree list --porcelain 2>/dev/null | sed -n 's#^worktree .*-wt-\([0-9][0-9]*\)$#\1#p')" || true
  while IFS=$'\t' read -r n lb; do
    [ -n "$n" ] || continue
    cur="$(jq -r --argjson n "$n" '[.items[]|select(.content.number==$n and .content.type=="Issue")]|if length==0 then "-" else (.[0].status // "") end' <<<"$items")"
    bl="$(unsat_blockers "$openset" "$n" | wc -l | tr -d ' ')"
    pr="$(jq -r --arg h "issue-$n" '[.[]|select(.head.ref==$h)] as $p|if ([$p[]|select(.merged_at!=null)]|length)>1 then "multi-merged" elif ([$p[]|select(.state=="open" and .draft==false)]|length)>0 then "open" elif ([$p[]|select(.state=="open")]|length)>0 then "draft" else "none" end' <<<"$prs")"
    wt=0; grep -qx "$n" <<<"$wts" && wt=1
    want="$(card_status "$lb" "$bl" "$pr" "$wt" "$cur" "$il")"
    case "$want" in
      skip:*) sk=$((sk+1)); reasons="$reasons ${want#skip:}" ;;
      *) [ "$(printf %s "$want" | tr '[:upper:]' '[:lower:]')" = "$(printf %s "$cur" | tr '[:upper:]' '[:lower:]')" ] && continue
         ch=$((ch+1)); echo "#$n: ${cur:--} -> $want"
         [ "$dry" = 1 ] || bash "$_cs_scripts/board.sh" "$owner" "$num" "$n" "$want" >/dev/null </dev/null || fail=$((fail+1)) ;;
    esac
  done < <(jq -r '.[]|select((.labels|map(.name)|index("epic"))|not)|"\(.number)\t\(.labels|map(.name)|join(" "))"' <<<"$all")
  r=""; for c in integrated multi-merged-pr needs-principal no-card; do
    k=$(printf '%s\n' $reasons | grep -cx "$c" || true); [ "$k" = 0 ] || r="$r${r:+, }$c $k"; done
  echo "board: $ch kartu $([ "$dry" = 1 ] && echo akan\ diubah || echo diubah), $sk dilewati${r:+ ($r)}${fail:+$([ "$fail" = 0 ] || echo ", $fail gagal ditulis")}, graphql sisa ${rem:-?}"
  return 0
}
