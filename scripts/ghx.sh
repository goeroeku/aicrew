#!/usr/bin/env bash
# aicrew ghx: pembungkus gh untuk batas GraphQL GitHub. Di-source (bukan dijalankan) oleh board.sh, epic-link.sh, pr-merge-check.sh.
# Pola: jalankan panggilan GraphQL; bila gagal karena batas, masuk MODE CADANGAN dan ulangi SEKALI lewat REST. Tanpa loop ulang.
# Mode disimpan di GHX_REST (diekspor) dan di berkas GHX_STATE, karena pembungkus sering dipanggil di dalam $(...): variabel yang
# diset di subshell hilang, berkas tidak. Anak proses (bash "$0" ...) mewarisi keduanya lewat lingkungan.

_ghx_own=0; [ -n "${GHX_STATE:-}" ] || _ghx_own=1
[ "$_ghx_own" = 0 ] || GHX_STATE="$(mktemp "${TMPDIR:-/tmp}/ghx-state.XXXXXX")"  # nama acak (bukan PID): tak basi, tak bisa ditebak
export GHX_STATE
[ "$_ghx_own" = 0 ] || [ -n "$(trap -p EXIT)" ] || trap 'rm -f "$GHX_STATE"' EXIT  # hanya pemilik status; jangan menimpa trap skrip

# 0 bila teks galat adalah batas GraphQL ("unknown owner type" adalah gejala batas yang tak menyebut kata itu)
ghx_is_limit() { grep -qiE 'rate limit|RATE_LIMIT|graphql_rate_limit|unknown owner type' <<<"$1"; }

ghx_in_rest() {
  if ghx_persist && _ghx_dir >/dev/null; then [ "$(_ghx_state_get graphql)" -gt "$(date +%s)" ]; return; fi   # status bertahan: hanya epoch (pulih otomatis sesudah reset)
  [ "${GHX_REST:-0}" = 1 ] || [ -s "$GHX_STATE" ]
}

# --- jenjang bertahan (#159 tahap 1). Hanya aktif bila GHX_PERSIST=1 (autopilot); gerbang dan skrip lain tidak memakainya, jadi perilaku lama tidak berubah.
# Status: satu berkas per kunci, <repo>/.aicrew/backend/{graphql,rest}.until berisi epoch kuota pulih; tulis atomik (mktemp + mv), tanpa baca-ubah-tulis, jadi dua penulis tidak saling menghapus.
# Cache: .aicrew/backend/cache/<hash>: baris 1 = ETag, sisanya = isi; satu berkas = pasangan atomik. Nilai epoch dibatasi sekarang+3700 detik (jendela GitHub 1 jam) agar berkas rusak/dipalsukan tak bisa menunda tanpa batas.
ghx_persist() { [ "${GHX_PERSIST:-0}" = 1 ]; }
_ghx_dir() {
  if [ -n "${_GHX_DIR_MEMO:-}" ]; then printf '%s' "$_GHX_DIR_MEMO"; return 0; fi
  local d="${AICREW_BACKEND_DIR:-}"
  if [ -z "$d" ]; then   # akar checkout utama (bukan worktree): sama dengan .aicrew milik autopilot, jadi antrean dari worktree isu ikut terkuras
    d="$(git rev-parse --git-common-dir 2>/dev/null)" && d="$(cd "$d/.." 2>/dev/null && pwd)" || return 1; d="$d/.aicrew/backend"
  fi
  mkdir -p "$d/cache" 2>/dev/null || return 1; _GHX_DIR_MEMO="$d"; printf '%s' "$d"
}
_ghx_state_get() {   # <graphql|rest> -> epoch kuota pulih (0 bila tidak ada), dibatasi sekarang+3700
  local d v now; ghx_persist && d="$(_ghx_dir)" || { echo 0; return 0; }
  v="$(cat "$d/$1.until" 2>/dev/null)"; [[ "$v" =~ ^[0-9]{1,12}$ ]] || v=0
  now="$(date +%s)"; [ "$v" -le $((now + 3700)) ] || v=$((now + 3700)); echo "$v"
}
_ghx_state_set() {   # <graphql|rest> <epoch>
  local d t; ghx_persist && d="$(_ghx_dir)" || return 0
  t="$(mktemp "$d/$1.until.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$2" > "$t" && mv "$t" "$d/$1.until" || rm -f "$t"
  return 0
}
# graphql = normal; rest = GraphQL habis tetapi REST masih ada; local = keduanya habis (tahap 1: pemanggil menunggu sampai reset)
ghx_tier() {
  local now; now="$(date +%s)"
  if [ "$(_ghx_state_get graphql)" -gt "$now" ]; then
    if [ "$(_ghx_state_get rest)" -gt "$now" ]; then echo local; else echo rest; fi
  else echo graphql; fi
}
# detik menunggu sampai salah satu kuota pulih (terdekat), dibatasi AICREW_QUOTA_WAIT_MIN (bawaan 30) .. 900
ghx_wait_seconds() {
  local g r now w m; now="$(date +%s)"; g="$(_ghx_state_get graphql)"; r="$(_ghx_state_get rest)"
  w=$(( (g < r ? g : r) - now )); m="${AICREW_QUOTA_WAIT_MIN:-30}"; [ "$w" -ge "$m" ] || w="$m"; [ "$w" -le 900 ] || w=900; echo "$w"
}
# GET REST dengan ETag bila status bertahan aktif (304 tidak memotong kuota); selain itu `gh api <url>` biasa (panggilan lama tak berubah).
# REST habis (epoch di masa depan) -> gagal cepat tanpa panggilan. Galat batas REST menandai rest habis sampai x-ratelimit-reset (atau +60 dtk).
# ETag hanya dipakai bila cache lebih muda dari AICREW_CACHE_MAX_AGE menit (bawaan 10): cache basi/dipalsukan paling lama bertahan segitu.
_ghx_rest_get() {
  local u="$1" d k f ef tf out rc=0 st et body etag rst
  if ! ghx_persist || ! d="$(_ghx_dir)"; then gh api "$u"; return; fi
  if [ "$(_ghx_state_get rest)" -gt "$(date +%s)" ]; then echo "ghx: batas REST GitHub habis; menunggu reset" >&2; return 1; fi
  k="$(printf '%s' "$u" | shasum | cut -c1-40)"; f="$d/cache/$k"; ef="$(mktemp "${TMPDIR:-/tmp}/ghx.err.XXXXXX")"; et=""
  [ -s "$f" ] && [ -n "$(find "$f" -mmin "-${AICREW_CACHE_MAX_AGE:-10}" 2>/dev/null)" ] && et="$(head -1 "$f")"
  if [ -n "$et" ]; then out="$(gh api -i -H "If-None-Match: $et" "$u" 2>"$ef")" || rc=$?; else out="$(gh api -i "$u" 2>"$ef")" || rc=$?; fi
  st="$(printf '%s\n' "$out" | head -1 | tr -d '\r' | awk '{print $2}')"
  if [ "$st" = 304 ] && [ -n "$et" ]; then rm -f "$ef"; tail -n +2 "$f"; return 0; fi
  if [ "$rc" = 0 ] && [ "$st" = 200 ]; then
    body="$(printf '%s\n' "$out" | awk 'b{print;next} {sub(/\r$/,"")} $0==""{b=1}')"
    etag="$(printf '%s\n' "$out" | tr -d '\r' | awk -F': *' 'tolower($1)=="etag"{print $2; exit}')"
    if [ -n "$etag" ]; then tf="$f.tmp.$$.$RANDOM"; { printf '%s\n' "$etag"; printf '%s\n' "$body"; } > "$tf" && mv "$tf" "$f" || rm -f "$tf"; else rm -f "$f"; fi
    rm -f "$ef"; printf '%s\n' "$body"; return 0
  fi
  if ghx_is_limit "$(cat "$ef") $out"; then
    rst="$(_ghx_hdr "$out" x-ratelimit-reset)"; [[ "$rst" =~ ^[0-9]+$ ]] || rst=$(( $(date +%s) + 60 ))
    _ghx_state_set rest "$rst"
  fi
  cat "$ef" >&2; rm -f "$ef"; [ "$rc" != 0 ] || rc=1; return "$rc"
}
# Proaktif: sisa GraphQL di bawah AICREW_QUOTA_FLOOR persen (bawaan 5) -> tandai GraphQL habis sampai reset, supaya sisanya tersedia untuk tindakan penting. 1 poin per panggilan.
ghx_probe_floor() {
  ghx_persist || return 0
  local h rem lim rst fl; h="$(_ghx_probe)"
  rem="$(_ghx_hdr "$h" x-ratelimit-remaining)"; lim="$(_ghx_hdr "$h" x-ratelimit-limit)"; rst="$(_ghx_hdr "$h" x-ratelimit-reset)"; fl="${AICREW_QUOTA_FLOOR:-5}"
  [[ "$rem" =~ ^[0-9]+$ && "$lim" =~ ^[0-9]+$ && "$rst" =~ ^[0-9]+$ && "$fl" =~ ^[0-9]+$ ]] || return 0
  [ $((rem * 100)) -lt $((lim * fl)) ] && _ghx_state_set graphql "$rst"
  return 0
}

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

# dipakai pr-merge-check.sh saat menolak: hanya mencetak bila batas REST (core) benar-benar habis (#113); `gh api rate_limit` tidak memakai kuota
ghx_explain_rest_limit() {
  local r rem rst t; r="$(gh api rate_limit --jq '.resources.core | "\(.remaining) \(.reset)"' 2>/dev/null)" || return 0
  read -r rem rst <<<"$r"; [ "${rem:-}" = 0 ] || return 0
  t="$(_ghx_fmt "${rst:-}")"
  echo "Penyebab: batas REST GitHub habis${t:+; reset $t UTC}. Tunggu lalu ulangi; gerbang tidak dilewati."
}

ghx_enter_rest() {
  local first=1 h ep t; [ -s "$GHX_STATE" ] && first=0
  GHX_REST=1; export GHX_REST; echo 1 > "$GHX_STATE"
  if ghx_persist && _ghx_dir >/dev/null; then first=1; fi   # status bertahan: tiap masuk menulis epoch baru
  [ "$first" = 1 ] || return 0
  h="$(_ghx_probe)"; ep="$(_ghx_hdr "$h" x-ratelimit-reset)"; t="$(_ghx_fmt "$ep")"
  if ghx_persist; then [[ "$ep" =~ ^[0-9]+$ ]] || ep=$(( $(date +%s) + 60 )); _ghx_state_set graphql "$ep"; fi
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

# owner/repo: GH_REPO; lalu `gh repo view` (perilaku lama, mengikuti repo bawaan gh); hanya bila batas tercapai, dari remote origin
# (mendukung ssh, https, dan alias host seperti github.com-kerja:). Tanpa remote yang terbaca -> galat, bukan tebakan.
ghx_repo() {
  local u o rc=0; [ -z "${GH_REPO:-}" ] || { echo "$GH_REPO"; return 0; }
  o="$(ghx_gql gh repo view --json nameWithOwner -q .nameWithOwner)" || rc=$?
  if [ "$rc" = 0 ]; then echo "$o"; return 0; fi; [ "$rc" = 75 ] || return "$rc"
  u="$(git remote get-url origin 2>/dev/null || true)"
  case "$u" in *github.com*) u="${u#*github.com}"; u="${u#*[:/]}"; echo "${u%.git}"; return 0 ;; esac
  echo "ghx: repo tak dapat ditentukan saat GraphQL terblokir (tak ada remote GitHub); set GH_REPO=owner/repo" >&2; return 1
}

# awalan jalur REST Project v2: orgs/<owner> atau users/<owner> (tipe dari REST, bukan GraphQL)
ghx_owner_base() { case "$(gh api "users/$1" -q .type)" in Organization) echo "orgs/$1" ;; *) echo "users/$1" ;; esac; }

# --- operasi issue. Jalur GraphQL = panggilan gh yang sama persis seperti sebelum ada pustaka ini; batas -> REST sekali.
# Catatan set -e: jangan tulis `ghx_gql ...; rc=$?` (kode 75 menghentikan skrip); pakai `|| rc=$?`.

# cache daftar issue (hanya status bertahan): hasil GraphQL maupun REST ditulis ke .aicrew/backend/cache/lst-issues-<status>-<label>.json; gerbang lokal membacanya
# (ghx_cached_issue, umur dibatasi) saat kuota habis. Berkas ini dapat ditulis agen (batas yang sama dengan bukti lokal): umur maksimum 10 menit mengecilkan risikonya.
_ghx_cache_list() {   # <kunci> <json>
  ghx_persist || return 0; local d k t; d="$(_ghx_dir)" || return 0; k="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"; t="$d/cache/lst-$k.json.tmp.$$"
  printf '%s\n' "$2" > "$t" 2>/dev/null && mv "$t" "$d/cache/lst-$k.json" || rm -f "$t"; return 0
}
# ghx_cached_issue <n> [umur-maks-detik=600]: catatan issue {number,labels,body,...} dari cache segar; exit 1 bila tak ada atau basi
ghx_cached_issue() {
  ghx_persist || return 1; local d f r mins; d="$(_ghx_dir)" || return 1; mins=$(( ${2:-600} / 60 )); [ "$mins" -ge 1 ] || mins=1
  while IFS= read -r f; do
    r="$(jq -c --argjson n "$1" '[.[]?|select(.number==$n)]|.[0] // empty' "$f" 2>/dev/null)"
    [ -z "$r" ] || { printf '%s\n' "$r"; return 0; }
  done < <(find "$d/cache" -maxdepth 1 -name 'lst-issues-*.json' -mmin "-$mins" 2>/dev/null)
  return 1
}

# ghx_issues <open|closed|all> <label|-> <batas> <json-fields>  -> larik JSON {number,title,body,labels,state(HURUF BESAR)} bila REST
ghx_issues() {
  local s="$1" l="$2" n="$3" f="$4" rc=0 repo page=1 acc='[]' pg q a=(--state "$1")
  [ "$l" = - ] || a+=(--label "$l"); a+=(--limit "$n" --json "$f")
  if ghx_persist; then   # status bertahan: tangkap hasil agar dapat disimpan ke cache daftar (dipakai gerbang lokal)
    local gout; gout="$(ghx_gql gh issue list "${a[@]}")" || rc=$?
    if [ "$rc" = 0 ]; then _ghx_cache_list "issues-$s-$l" "$gout"; printf '%s\n' "$gout"; return 0; fi
    [ "$rc" = 75 ] || { [ -z "$gout" ] || printf '%s\n' "$gout"; return "$rc"; }
  else
    ghx_gql gh issue list "${a[@]}" || rc=$?; [ "$rc" = 75 ] || return "$rc"
  fi
  repo="$(ghx_repo)" || return 1
  while :; do   # REST per halaman 100; entri bergaris pull_request dibuang; berhenti saat batas terkumpul
    q="repos/$repo/issues?state=$s&per_page=100&page=$page"; [ "$l" = - ] || q="$q&labels=$l"
    pg="$(_ghx_rest_get "$q")" || { echo "ghx: REST juga gagal (GraphQL terblokir); coba lagi setelah reset" >&2; return 1; }
    acc="$({ printf '%s\n' "$acc"; printf '%s\n' "$pg"; } | jq -c -s '.[0] + [.[1][]|select(has("pull_request")|not)]')"  # stdin: halaman bisa >1 MB, argv terbatas
    [ "$(jq length <<<"$pg")" -ge 100 ] && [ "$(jq length <<<"$acc")" -lt "$n" ] || break
    page=$((page+1))
  done
  acc="$(jq -c --argjson n "$n" '.[:$n]|map({number,title,body:(.body // ""),labels:(.labels // []),state:(.state|ascii_upcase)})' <<<"$acc")" || return 1
  _ghx_cache_list "issues-$s-$l" "$acc"; printf '%s\n' "$acc"
}

# ghx_prs <open|closed|all> <batas> <json-fields>  -> larik JSON bentuk `gh pr list`; REST: number,title,state(OPEN|MERGED|CLOSED),mergedAt,headRefOid,headRefName,isDraft,isCrossRepository
ghx_prs() {
  local s="$1" n="$2" f="$3" rc=0 repo page=1 acc='[]' pg
  ghx_gql gh pr list --state "$s" --limit "$n" --json "$f" || rc=$?; [ "$rc" = 75 ] || return "$rc"
  repo="$(ghx_repo)" || return 1
  while :; do
    pg="$(_ghx_rest_get "repos/$repo/pulls?state=$s&per_page=100&page=$page")" || { echo "ghx: REST juga gagal (GraphQL terblokir); coba lagi setelah reset" >&2; return 1; }
    acc="$({ printf '%s\n' "$acc"; printf '%s\n' "$pg"; } | jq -c -s '.[0] + .[1]')"
    [ "$(jq length <<<"$pg")" -ge 100 ] && [ "$(jq length <<<"$acc")" -lt "$n" ] || break
    page=$((page+1))
  done
  jq -c --argjson n "$n" '.[:$n]|map({number,title,state:(if .merged_at then "MERGED" else (.state|ascii_upcase) end),mergedAt:.merged_at,headRefOid:.head.sha,headRefName:.head.ref,isDraft:(.draft // false),isCrossRepository:((.head.repo.full_name // "") != (.base.repo.full_name // ""))})' <<<"$acc"
}

# ghx_has_open_pr <cabang>: exit 0 bila ada PR terbuka dari cabang itu; panggilan GraphQL identik dengan yang lama, REST bila batas
ghx_has_open_pr() {
  local rc=0 out repo
  out="$(ghx_gql gh pr list --head "$1" --state open --json number,state -q '[.[]|select(.state=="OPEN")]|length' 2>/dev/null)" || rc=$?
  if [ "$rc" = 0 ]; then [ "$out" -ge 1 ] 2>/dev/null; return; fi
  [ "$rc" = 75 ] || return 1
  repo="$(ghx_repo 2>/dev/null)" || return 1
  out="$(_ghx_rest_get "repos/$repo/pulls?state=open&head=${repo%%/*}:$1&per_page=100" 2>/dev/null | jq 'length' 2>/dev/null)" || return 1
  [ "$out" -ge 1 ] 2>/dev/null
}

# --- outbox (#159 tahap 2): operasi tulis yang tak bisa dikirim karena REST (jalan terakhir) habis diantre sebagai satu berkas per operasi
# <repo>/.aicrew/backend/outbox/<epoch>-<hash>.json {id,op,args,ts,tries}; backend-sync.sh mengurasnya setelah kuota pulih. Operasi yang sama (op+args) tidak diantre dua kali.
# ghx_queue <op> [chave=nilai ...]: 0 = diantre; 1 = belum saatnya antre (status bertahan nonaktif atau REST belum habis): pemanggil menangani galat seperti biasa.
ghx_queue() {
  ghx_persist || return 1; [ "${GHX_NOQUEUE:-0}" != 1 ] || return 1; [ "$(_ghx_state_get rest)" -gt "$(date +%s)" ] || return 1
  local op="$1" d args='{}' kv h f tmp ts; shift; d="$(_ghx_dir)" || return 1; mkdir -p "$d/outbox" 2>/dev/null || return 1
  for kv in "$@"; do args="$(jq -c --arg k "${kv%%=*}" --arg v "${kv#*=}" '.[$k]=$v' <<<"$args")"; done
  h="$(printf '%s %s' "$op" "$args" | shasum | cut -c1-16)"
  if ls "$d/outbox"/*-"$h".json >/dev/null 2>&1; then echo "$(msg backend.queued_dup "$op" 2>/dev/null || echo "queued: $op")" >&2; return 0; fi
  ts="$(date +%s)"; f="$d/outbox/$ts-$(printf '%03d' "$(ls "$d/outbox" 2>/dev/null | grep -c "^$ts-")")-$h.json"; tmp="$f.tmp.$$"   # epoch-urut-hash: urutan antre terjaga
  jq -nc --arg id "$(printf '%s %s %s' "$h" "$ts" "$RANDOM" | shasum | cut -c1-16)" --arg op "$op" --argjson a "$args" --argjson ts "$(date +%s)" '{id:$id,op:$op,args:$a,ts:$ts,tries:0}' > "$tmp" 2>/dev/null && mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  echo "$(msg backend.queued "$op" 2>/dev/null || echo "queued: $op")" >&2; return 0
}
# ghx_rest_write <op> [chave=nilai ...] -- <perintah gh api ...>: jalankan; REST habis (sudah tercatat, atau galat batas di sini) -> antre operasi dan sukses.
ghx_rest_write() {
  local op="$1" kv=() ef rc=0 e; shift
  while [ $# -gt 0 ] && [ "$1" != -- ]; do kv+=("$1"); shift; done; shift
  ghx_queue "$op" "${kv[@]}" && return 0
  ef="$(mktemp "${TMPDIR:-/tmp}/ghx.err.XXXXXX")"; "$@" >/dev/null 2>"$ef" || rc=$?; e="$(cat "$ef")"; rm -f "$ef"
  if [ "$rc" != 0 ] && ghx_persist && ghx_is_limit "$e"; then
    _ghx_state_set rest "$(( $(date +%s) + 60 ))"; ghx_queue "$op" "${kv[@]}" && return 0
  fi
  [ -z "$e" ] || printf '%s\n' "$e" >&2
  return "$rc"
}

ghx_label_add() {   # <n> <label>: tambah label (GraphQL gh issue edit; REST bila batas; antre bila REST habis)
  local rc=0; ghx_gql gh issue edit "$1" --add-label "$2" >/dev/null || rc=$?; [ "$rc" = 75 ] || return "$rc"
  ghx_rest_write label_add n="$1" label="$2" -- gh api -X POST "repos/$(ghx_repo)/issues/$1/labels" -f "labels[]=$2"
}
ghx_comment() {   # <n> <teks>: komentar di isu/PR (GraphQL gh issue comment; REST bila batas; antre bila REST habis)
  local rc=0; ghx_gql gh issue comment "$1" --body "$2" >/dev/null || rc=$?; [ "$rc" = 75 ] || return "$rc"
  ghx_rest_write comment n="$1" body="$2" -- gh api -X POST "repos/$(ghx_repo)/issues/$1/comments" -f body="$2"
}
_ghx_close_rest() { local r; r="$(ghx_repo)"; gh api -X POST "repos/$r/issues/$1/comments" -f body="$2" >/dev/null \
  && gh api -X PATCH "repos/$r/issues/$1" -f state=closed -f state_reason=completed >/dev/null; }

ghx_issue_body() {   # <n> -> badan issue ("" bila kosong)
  local rc=0; ghx_gql gh issue view "$1" --json body -q .body || rc=$?; [ "$rc" = 75 ] || return "$rc"
  gh api "repos/$(ghx_repo)/issues/$1" | jq -r '.body // ""'
}

ghx_issue_set_body() {   # <n> <teks>; -f body= (bukan interpolasi) agar kutip, $ dan baris baru utuh
  local rc=0; ghx_gql gh issue edit "$1" --body "$2" >/dev/null || rc=$?; [ "$rc" = 75 ] || return "$rc"
  ghx_rest_write issue_body n="$1" body="$2" -- gh api -X PATCH "repos/$(ghx_repo)/issues/$1" -f body="$2"
}

ghx_issue_close() {   # <n> <komentar>
  local rc=0 r; ghx_gql gh issue close "$1" --comment "$2" >/dev/null || rc=$?; [ "$rc" = 75 ] || return "$rc"
  ghx_rest_write issue_close n="$1" comment="$2" -- _ghx_close_rest "$1" "$2"
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
  while :; do   # semua halaman; Status hanya ikut bila diminta lewat ?fields[]=<id kolom>
    pg="$(_ghx_papi gh api "$b/items?per_page=100&fields[]=$fid&page=$page")" || return $?
    acc="$({ printf '%s\n' "$acc"; printf '%s\n' "$pg"; } | jq -c -s '.[0] + .[1]')"
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
  ghx_queue card_set owner="$1" num="$2" item="$3" field="$4" option="$5" && return 0   # REST habis: antre (#159)
  b="$(_ghx_pbase "$1" "$2")" || return 1
  if ! [[ "$fid" =~ ^[0-9]+$ ]]; then fld="$(_ghx_status_field_rest "$1" "$2")" || return $?; fid="$(jq -r .id <<<"$fld")"; fi
  if ! [[ "$item" =~ ^[0-9]+$ ]]; then item="$(_ghx_item_num "$1" "$2" "$item")" || return $?; fi
  jq -nc --argjson f "$fid" --arg v "$5" '{fields:[{id:$f,value:$v}]}' | _ghx_papi gh api -X PATCH "$b/items/$item" --input - >/dev/null
}
