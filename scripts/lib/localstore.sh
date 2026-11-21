#!/usr/bin/env bash
# aicrew localstore: isu lokal untuk `Quota mode: local` (#159 tahap 4), tanpa GitHub. Di-source (bukan dijalankan); bash 3.2 aman.
# Penyimpanan: <akar checkout utama>/.aicrew/issues/<n>.json = {number,title,body,state(open|closed),labels:[nama],parent,created,updated}
#              <n>.comments.jsonl = satu komentar per baris {id,author,body,created}; `next` = nomor berikutnya. Tulis atomik (mktemp + mv), penomoran dengan kunci mkdir.
# Keluaran ls_list/ls_view berbentuk `gh issue list --json`: [{number,title,body,state:OPEN|CLOSED,labels:[{name}]}].
# Berkas ini dapat ditulis agen yang punya Bash: pagar kecelakaan, bukan keamanan terhadap agen berniat jahat (persetujuan pemilik tetap lewat owner-local.sh dengan TTY).
_ls_dir() {
  local g root d; d="${AICREW_LOCAL_DIR:-}"
  if [ -z "$d" ]; then g="$(git rev-parse --git-common-dir 2>/dev/null)" && root="$(cd "$g/.." && pwd)" || return 1; d="$root/.aicrew/issues"; fi
  mkdir -p "$d" 2>/dev/null || return 1; printf '%s' "$d"
}
_ls_age() { local m; m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)"; if [[ "$m" =~ ^[0-9]+$ ]]; then echo $(( $(date +%s) - m )); else echo 0; fi; }
# <dir>: kunci mkdir berisi pid. Kunci yatim diambil alih bila (umur >= 3 dtk DAN pid mati) atau umur >= 2 menit; pengambilalihan memakai mv atomik lalu memeriksa ulang umur kunci yang
# terambil: bila ternyata kunci baru (umur < 3 dtk, diambil orang lain di antara pembacaan dan mv) dikembalikan. Sisa jendela sangat sempit dan hanya ada setelah proses mati.
_ls_lock() {
  local d="$1" i=0 p a st
  while ! mkdir "$d/.lock" 2>/dev/null; do
    i=$((i+1))
    if [ "$i" -ge 20 ]; then
      a="$(_ls_age "$d/.lock")"; p="$(cat "$d/.lock/pid" 2>/dev/null)"
      if [ "$a" -ge 120 ] || { [ "$a" -ge 3 ] && [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; }; then
        st="$d/.lock.stale.$$.$RANDOM"
        if mv "$d/.lock" "$st" 2>/dev/null; then
          if [ "$(_ls_age "$st")" -ge 3 ]; then rm -rf "$st"; else mv "$st" "$d/.lock" 2>/dev/null || rm -rf "$st"; fi
        fi
        i=0; continue
      fi
    fi
    [ "$i" -le 400 ] || return 1
    sleep 0.05
  done
  echo $$ > "$d/.lock/pid" 2>/dev/null; return 0
}
_ls_unlock() { rm -rf "$1/.lock" 2>/dev/null; return 0; }   # berisi berkas pid: rmdir saja tidak cukup
_ls_write() {   # <berkas> <json>: atomik
  local f="$1" t; t="$(mktemp "$1.XXXXXX")" || return 1
  printf '%s\n' "$2" > "$t" && mv "$t" "$f" || { rm -f "$t"; return 1; }
}
_ls_label_ok() { [[ "$1" =~ ^[A-Za-z0-9._:\ -]+$ ]] && [ "$1" != - ]; }
_ls_num_ok() { [[ "$1" =~ ^[0-9]+$ ]]; }
_ls_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ls_create <judul> <badan> [label ...]  -> mencetak nomor; label bentuk "parent=N" tidak dipakai (gunakan ls_set_parent)
ls_create() {
  local title="$1" body="$2" d n j l labs='[]'; shift 2; d="$(_ls_dir)" || return 1
  for l in "$@"; do _ls_label_ok "$l" || { echo "localstore: label tak valid: $l" >&2; return 1; }; labs="$(jq -c --arg l "$l" '. + [$l] | unique' <<<"$labs")"; done
  # tanpa kunci: nomor diklaim dengan `ln` (hard link atomik, gagal bila berkas sudah ada), isi sudah lengkap saat terlihat pembaca; tabrakan = coba nomor berikutnya (#159 perbaikan CI)
  local mx t tries=0; mx="$(ls "$d" 2>/dev/null | sed -n 's/^\([0-9][0-9]*\)\.json$/\1/p' | sort -n | tail -1)"; n=$(( 10#${mx:-0} + 1 ))
  t="$(mktemp "$d/.new.XXXXXX")" || return 1
  while :; do
    j="$(jq -nc --argjson n "$n" --arg t "$title" --arg b "$body" --argjson l "$labs" --arg now "$(_ls_now)" '{number:$n,title:$t,body:$b,state:"open",labels:$l,created:$now,updated:$now}')" || { rm -f "$t"; return 1; }
    printf '%s\n' "$j" > "$t" || { rm -f "$t"; return 1; }
    ln "$t" "$d/$n.json" 2>/dev/null && break
    tries=$((tries+1)); [ "$tries" -le 2000 ] || { rm -f "$t"; echo "localstore: tidak dapat memberi nomor isu" >&2; return 1; }
    n=$((n+1))
  done
  rm -f "$t"; printf '%s\n' "$((n+1))" > "$d/next" 2>/dev/null || true   # petunjuk saja; nomor sebenarnya = klaim ln di atas
  echo "$n"
}
_ls_edit() {   # <n> <filtro jq> [--arg k v ...]: aplica ao registro sob kunci
  local n="$1" f="$2" d cur new rc=0; shift 2; _ls_num_ok "$n" || { echo "localstore: nomor tak valid: $n" >&2; return 1; }
  d="$(_ls_dir)" || return 1; [ -f "$d/$n.json" ] || { echo "localstore: isu #$n tidak ada" >&2; return 1; }
  _ls_lock "$d" || return 1
  cur="$(cat "$d/$n.json")"; new="$(jq -c "$@" "$f | .updated=\"$(_ls_now)\"" <<<"$cur")" && _ls_write "$d/$n.json" "$new" || rc=1
  _ls_unlock "$d"; return "$rc"
}
# GitHub memperlakukan nama label tanpa peka huruf besar-kecil: tambah/cabut/filter juga begitu
ls_label_add() { _ls_label_ok "$2" || { echo "localstore: label tak valid: $2" >&2; return 1; }; _ls_edit "$1" 'if any(.labels[]?; ascii_downcase == ($l|ascii_downcase)) then . else .labels = ((.labels // []) + [$l]) end' --arg l "$2"; }
ls_label_remove() { _ls_edit "$1" '.labels = ((.labels // []) | map(select(ascii_downcase != ($l|ascii_downcase))))' --arg l "$2"; }
ls_set_body() { _ls_edit "$1" '.body = $b' --arg b "$2"; }
ls_set_parent() { _ls_num_ok "$2" || return 1; _ls_edit "$1" '.parent = ($p|tonumber)' --arg p "$2"; }
ls_reopen() { _ls_edit "$1" '.state = "open"'; }
ls_comment() {   # <n> <teks> [autor=$AICREW_LOCAL_AUTHOR|agent]
  local n="$1" d id line; _ls_num_ok "$n" || return 1; d="$(_ls_dir)" || return 1; [ -f "$d/$n.json" ] || { echo "localstore: isu #$n tidak ada" >&2; return 1; }
  _ls_lock "$d" || return 1
  id=$(( $( [ -f "$d/$n.comments.jsonl" ] && wc -l < "$d/$n.comments.jsonl" | tr -d ' ' || echo 0 ) + 1 ))
  line="$(jq -nc --argjson id "$id" --arg a "${3:-${AICREW_LOCAL_AUTHOR:-agent}}" --arg b "$2" --arg now "$(_ls_now)" '{id:$id,author:$a,body:$b,created:$now}')" && printf '%s\n' "$line" >> "$d/$n.comments.jsonl"
  local rc=$?; _ls_unlock "$d"; return "$rc"
}
ls_close() {   # <n> [komentar]
  [ -z "${2:-}" ] || ls_comment "$1" "$2" || return 1
  _ls_edit "$1" '.state = "closed"'
}
ls_body() { local d; _ls_num_ok "$1" || return 1; d="$(_ls_dir)" || return 1; jq -r '.body // ""' "$d/$1.json" 2>/dev/null; }
ls_comments() { local d; _ls_num_ok "$1" || return 1; d="$(_ls_dir)" || return 1; [ -s "$d/$1.comments.jsonl" ] && jq -sc . "$d/$1.comments.jsonl" || echo '[]'; }
_ls_shape='map({number,title,body:(.body // ""),state:(.state|ascii_upcase),labels:((.labels // [])|map({name:.})),parent:(.parent // null)})'
# ls_list <open|closed|all> <label|-> <batas>
ls_list() {
  local d f; d="$(_ls_dir)" || return 1
  for f in "$d"/[0-9]*.json; do [ -f "$f" ] && cat "$f"; done | jq -sc --arg s "$1" --arg l "${2:--}" --argjson n "${3:-1000}" \
    "[.[]|select(\$s==\"all\" or .state==\$s)|select(\$l==\"-\" or any((.labels // [])[]; ascii_downcase == (\$l|ascii_downcase)))]|sort_by(.number)|.[:\$n]|$_ls_shape"
}
ls_view() {   # <n> -> um objeto com comentarios
  local d; _ls_num_ok "$1" || return 1; d="$(_ls_dir)" || return 1; [ -f "$d/$1.json" ] || return 1
  jq -c "[.]|$_ls_shape|.[0]" "$d/$1.json" | jq -c --argjson c "$(ls_comments "$1")" '.comments=$c'
}
