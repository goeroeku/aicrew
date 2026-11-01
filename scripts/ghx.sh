#!/usr/bin/env bash
# aicrew ghx: pembungkus gh untuk batas GraphQL GitHub. Di-source (bukan dijalankan) oleh board.sh, epic-link.sh, pr-merge-check.sh.
# Pola: jalankan panggilan GraphQL; bila gagal karena batas, masuk MODE CADANGAN dan ulangi SEKALI lewat REST. Tanpa loop ulang.
# Mode disimpan di GHX_REST (diekspor) dan di berkas GHX_STATE, karena pembungkus sering dipanggil di dalam $(...): variabel yang
# diset di subshell hilang, berkas tidak. Anak proses (bash "$0" ...) mewarisi keduanya lewat lingkungan.

_ghx_own=0; [ -n "${GHX_STATE:-}" ] || _ghx_own=1
GHX_STATE="${GHX_STATE:-${TMPDIR:-/tmp}/ghx-state.$$}"; export GHX_STATE
[ "$_ghx_own" = 0 ] || [ -n "$(trap -p EXIT)" ] || trap 'rm -f "$GHX_STATE"' EXIT  # hanya pemilik status; jangan menimpa trap skrip

# 0 bila teks galat adalah batas GraphQL ("unknown owner type" adalah gejala batas yang tak menyebut kata itu)
ghx_is_limit() { grep -qiE 'rate limit|RATE_LIMIT|graphql_rate_limit|unknown owner type' <<<"$1"; }

ghx_in_rest() { [ "${GHX_REST:-0}" = 1 ] || [ -s "$GHX_STATE" ]; }

# header respons GraphQL: batas yang benar ada di sini, BUKAN di `gh api rate_limit` (angkanya bisa menyesatkan)
_ghx_probe() { gh api graphql -i -f query='{viewer{login}}' 2>/dev/null || true; }
_ghx_hdr() { tr -d '\r' <<<"$1" | awk -F': *' -v k="$2" 'tolower($1)==k{print $2; exit}'; }
_ghx_fmt() { [[ "$1" =~ ^[0-9]+$ ]] || return 0; date -u -r "$1" +%H:%M:%S 2>/dev/null || date -u -d "@$1" +%H:%M:%S 2>/dev/null || true; }

# HH:MM:SS UTC kapan batas GraphQL pulih; kosong bila tak terbaca
ghx_reset_time() { _ghx_fmt "$(_ghx_hdr "$(_ghx_probe)" x-ratelimit-reset)"; }

# dipakai pr-merge-check.sh saat menolak: hanya mencetak bila GraphQL benar-benar habis (Remaining: 0)
ghx_explain_limit() {
  local h t; h="$(_ghx_probe)"; [ "$(_ghx_hdr "$h" x-ratelimit-remaining)" = 0 ] || return 0
  t="$(_ghx_fmt "$(_ghx_hdr "$h" x-ratelimit-reset)")"
  echo "Penyebab: batas GraphQL GitHub habis${t:+; reset $t UTC}. Tunggu lalu ulangi; gerbang tidak dilewati."
}

ghx_enter_rest() {
  local first=1; [ -s "$GHX_STATE" ] && first=0
  GHX_REST=1; export GHX_REST; echo 1 > "$GHX_STATE"
  [ "$first" = 1 ] || return 0
  local t; t="$(ghx_reset_time)"
  echo "mode cadangan REST: batas GraphQL GitHub tercapai${t:+; reset $t UTC}" >&2
}

# ghx_gql <perintah gh...>: exit 0 + stdout bila sukses; 75 bila batas (mode cadangan aktif, panggil jalur REST);
# selain itu teruskan stdout, stderr, dan exit code asli. Dalam mode cadangan tidak menyentuh GraphQL lagi.
ghx_gql() {
  ghx_in_rest && return 75
  local out err rc=0 ef; ef="$(mktemp "${TMPDIR:-/tmp}/ghx.err.XXXXXX")"
  out="$("$@" 2>"$ef")" || rc=$?
  err="$(cat "$ef")"; rm -f "$ef"
  if [ "$rc" != 0 ] && ghx_is_limit "$err"; then ghx_enter_rest; return 75; fi
  [ -z "$out" ] || printf '%s\n' "$out"; [ -z "$err" ] || printf '%s\n' "$err" >&2
  return "$rc"
}

# owner/repo tanpa GraphQL: GH_REPO, lalu remote origin, lalu gh repo view
ghx_repo() {
  local u; [ -z "${GH_REPO:-}" ] || { echo "$GH_REPO"; return 0; }
  u="$(git remote get-url origin 2>/dev/null || true)"
  case "$u" in *github.com[:/]*) u="${u#*github.com[:/]}"; echo "${u%.git}"; return 0 ;; esac
  gh repo view --json nameWithOwner -q .nameWithOwner
}

# awalan jalur REST Project v2: orgs/<owner> atau users/<owner> (tipe dari REST, bukan GraphQL)
ghx_owner_base() { case "$(gh api "users/$1" -q .type)" in Organization) echo "orgs/$1" ;; *) echo "users/$1" ;; esac; }

# --- operasi issue. Jalur GraphQL = panggilan gh yang sama persis seperti sebelum ada pustaka ini; batas -> REST sekali.
# Catatan set -e: jangan tulis `ghx_gql ...; rc=$?` (kode 75 menghentikan skrip); pakai `|| rc=$?`.

# ghx_issues <open|closed|all> <label|-> <batas> <json-fields>  -> larik JSON {number,title,body,labels,state(HURUF BESAR)} bila REST
ghx_issues() {
  local s="$1" l="$2" n="$3" f="$4" rc=0 repo page=1 acc='[]' pg q a=(--state "$1")
  [ "$l" = - ] || a+=(--label "$l"); a+=(--limit "$n" --json "$f")
  ghx_gql gh issue list "${a[@]}" || rc=$?; [ "$rc" = 75 ] || return "$rc"
  repo="$(ghx_repo)" || return 1
  while :; do   # REST per halaman 100; entri bergaris pull_request dibuang; berhenti saat batas terkumpul
    q="repos/$repo/issues?state=$s&per_page=100&page=$page"; [ "$l" = - ] || q="$q&labels=$l"
    pg="$(gh api "$q")" || { echo "ghx: REST juga gagal (GraphQL terblokir); coba lagi setelah reset" >&2; return 1; }
    acc="$(jq -c --argjson p "$pg" '. + [$p[]|select(has("pull_request")|not)]' <<<"$acc")"
    [ "$(jq length <<<"$pg")" -ge 100 ] && [ "$(jq length <<<"$acc")" -lt "$n" ] || break
    page=$((page+1))
  done
  jq -c --argjson n "$n" '.[:$n]|map({number,title,body:(.body // ""),labels:(.labels // []),state:(.state|ascii_upcase)})' <<<"$acc"
}

ghx_issue_body() {   # <n> -> badan issue ("" bila kosong)
  local rc=0; ghx_gql gh issue view "$1" --json body -q .body || rc=$?; [ "$rc" = 75 ] || return "$rc"
  gh api "repos/$(ghx_repo)/issues/$1" | jq -r '.body // ""'
}

ghx_issue_set_body() {   # <n> <teks>; -f body= (bukan interpolasi) agar kutip, $ dan baris baru utuh
  local rc=0; ghx_gql gh issue edit "$1" --body "$2" >/dev/null || rc=$?; [ "$rc" = 75 ] || return "$rc"
  gh api -X PATCH "repos/$(ghx_repo)/issues/$1" -f body="$2" >/dev/null
}

ghx_issue_close() {   # <n> <komentar>
  local rc=0 r; ghx_gql gh issue close "$1" --comment "$2" >/dev/null || rc=$?; [ "$rc" = 75 ] || return "$rc"
  r="$(ghx_repo)"; gh api -X POST "repos/$r/issues/$1/comments" -f body="$2" >/dev/null \
    && gh api -X PATCH "repos/$r/issues/$1" -f state=closed -f state_reason=completed >/dev/null
}

# --- operasi kartu Project v2. REST: orgs|users/<owner>/projectsV2/<n>. Kode keluar khusus pada jalur REST:
#   77 = kartu ditolak (HTTP 403/404, biasanya scope 'project' kurang); 78 = kartu sudah ada (422 "Content already exists").
# Id GraphQL (string PVTI_/PVTSSF_) berbeda dari id REST (angka): fungsi REST menerjemahkan bila batas tercapai di tengah alur.

_ghx_papi() {   # jalankan gh api; petakan galat REST kartu ke kode di atas. Stdin diteruskan.
  local ef out rc=0 e; ef="$(mktemp "${TMPDIR:-/tmp}/ghx.err.XXXXXX")"
  out="$("$@" 2>"$ef")" || rc=$?; e="$(cat "$ef") $out"; rm -f "$ef"
  if [ "$rc" = 0 ]; then [ -z "$out" ] || printf '%s\n' "$out"; return 0; fi
  grep -q 'Content already exists' <<<"$e" && return 78
  if grep -qE 'HTTP 40[34]' <<<"$e"; then
    echo "ghx: REST kartu ditolak ($(grep -oE 'HTTP 40[34]' <<<"$e" | head -1)); cek scope 'project': gh auth refresh -h github.com -s project" >&2; return 77
  fi
  printf '%s\n' "$e" >&2; return 1
}
_ghx_pbase() { local b; b="$(ghx_owner_base "$1")" || return 1; echo "$b/projectsV2/$2"; }

_ghx_status_field_rest() {   # <owner> <num> -> {"id":<angka>,"options":[{"id","name"}]}; nama string (user) atau {raw} (org)
  local b o; b="$(_ghx_pbase "$1" "$2")" || return 1
  o="$(_ghx_papi gh api "$b/fields?per_page=100")" || return $?
  jq -c '[.[]|select((.name|if type=="object" then .raw else . end)=="Status")|{id,options:[(.options // [])[]|{id,name:(.name|if type=="object" then .raw else . end)}]}]|.[0] // empty' <<<"$o"
}

_ghx_item_num() {   # <owner> <num> <node_id PVTI_...> -> id angka kartu (REST)
  local b page=1 pg r; b="$(_ghx_pbase "$1" "$2")" || return 1
  while :; do
    pg="$(_ghx_papi gh api "$b/items?per_page=100&page=$page")" || return $?
    r="$(jq -r --arg n "$3" '.[]|select(.node_id==$n)|.id' <<<"$pg" | head -1)"; [ -z "$r" ] || { echo "$r"; return 0; }
    [ "$(jq length <<<"$pg")" -ge 100 ] || return 1; page=$((page+1))
  done
}

ghx_status_field() {   # <owner> <num> -> {"id","options":[{"id","name"}]} untuk kolom Status; kosong bila tak ada
  local rc=0 o; o="$(ghx_gql gh project field-list "$2" --owner "$1" --format json)" || rc=$?
  if [ "$rc" = 0 ]; then jq -c '.fields[]|select(.name=="Status")' <<<"$o"; return 0; fi
  [ "$rc" = 75 ] || return "$rc"
  _ghx_status_field_rest "$1" "$2"
}

ghx_items() {   # <owner> <num> -> {"items":[{"id","status","content":{"number","type"}}]} (bentuk gh project item-list)
  local rc=0 b fld fid page=1 acc='[]' pg
  ghx_gql gh project item-list "$2" --owner "$1" --limit 200 --format json || rc=$?; [ "$rc" = 75 ] || return "$rc"
  b="$(_ghx_pbase "$1" "$2")" || return 1
  fld="$(_ghx_status_field_rest "$1" "$2")" || return $?; fid="$(jq -r '.id // empty' <<<"$fld")"
  while :; do   # semua halaman; Status hanya ikut bila diminta lewat ?fields=<id kolom>
    pg="$(_ghx_papi gh api "$b/items?per_page=100&fields=$fid&page=$page")" || return $?
    acc="$(jq -c --argjson p "$pg" '. + $p' <<<"$acc")"
    [ "$(jq length <<<"$pg")" -ge 100 ] || break; page=$((page+1))
  done
  jq -c --arg f "$fid" '{items:map({id,status:([.fields[]?|select((.id|tostring)==$f)|.value.name|if type=="object" then .raw else . end]|.[0]),content:{number:.content.number,type:.content_type}})}' <<<"$acc"
}

ghx_card_add() {   # <owner> <num> <issue> -> id kartu
  local rc=0 repo b iid out; repo="$(ghx_repo)" || return 1
  out="$(ghx_gql gh project item-add "$2" --owner "$1" --url "https://github.com/$repo/issues/$3" --format json)" || rc=$?
  if [ "$rc" = 0 ]; then jq -r .id <<<"$out"; return 0; fi
  [ "$rc" = 75 ] || return "$rc"
  b="$(_ghx_pbase "$1" "$2")" || return 1; iid="$(gh api "repos/$repo/issues/$3" | jq -r .id)"   # id NUMERIK issue; nomor memberi 404
  rc=0; out="$(_ghx_papi gh api -X POST "$b/items" -f type=Issue -F id="$iid")" || rc=$?
  case "$rc" in   # 78 = kartu sudah ada: idempoten, cari id-nya
    0) jq -r .id <<<"$out" ;;
    78) ghx_items "$1" "$2" | jq -r --argjson n "$3" '.items[]|select(.content.number==$n and .content.type=="Issue")|.id' | head -1 ;;
    *) return "$rc" ;;
  esac
}

ghx_card_set() {   # <owner> <num> <item> <id-kolom-Status> <id-opsi>
  local rc=0 pid b item="$3" fid="$4" fld
  pid="$(ghx_gql gh project view "$2" --owner "$1" --format json -q .id)" || rc=$?
  if [ "$rc" = 0 ]; then
    ghx_gql gh project item-edit --id "$item" --project-id "$pid" --field-id "$fid" --single-select-option-id "$5" >/dev/null || rc=$?
    [ "$rc" = 0 ] && return 0
  fi
  [ "$rc" = 75 ] || return "$rc"
  b="$(_ghx_pbase "$1" "$2")" || return 1
  if ! [[ "$fid" =~ ^[0-9]+$ ]]; then fld="$(_ghx_status_field_rest "$1" "$2")" || return $?; fid="$(jq -r .id <<<"$fld")"; fi
  if ! [[ "$item" =~ ^[0-9]+$ ]]; then item="$(_ghx_item_num "$1" "$2" "$item")" || return $?; fi
  jq -nc --argjson f "$fid" --arg v "$5" '{fields:[{id:$f,value:$v}]}' | _ghx_papi gh api -X PATCH "$b/items/$item" --input - >/dev/null
}
