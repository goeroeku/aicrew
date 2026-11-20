#!/usr/bin/env bash
# aicrew ownerlocal: persetujuan pemilik LOKAL (#159 tahap 4B, `Quota mode: local`). Di-source.
# Persetujuan = baris `ts|n|sha|scope|ctx|hmac` di .aicrew/owner.log, HMAC-SHA256 dengan kunci ~/.config/aicrew/owner.key (dibuat saat persetujuan pertama, mode 0600). Lokasi kunci
# diambil dari basis data pengguna (`~nama`), BUKAN dari env HOME/AICREW_*: agen tidak dapat menggeser kuncinya lewat lingkungan. Persetujuan terikat ke isu, sha kepala, cakupan (merge), dan
# KONTEKS isu (label terurut + badan + nomor): menambah label penahan atau mengubah isu setelah persetujuan membatalkannya; cabang yang didorong ulang juga.
# Penulisnya owner-local.sh (menolak tanpa TTY); izin agen menolak Read kunci, Write log, dan perintah approve (templates/autopilot-permissions.json).
# Batas: agen dengan Bash penuh sebagai pengguna yang sama tetap dapat membaca kunci atau memakai pty; ini pagar kecelakaan dan prompt injection, bukan pertahanan terhadap agen berniat jahat.
. "$(dirname "${BASH_SOURCE[0]}")/localstore.sh"
_ol_root() { local g; g="$(git rev-parse --git-common-dir 2>/dev/null)" && (cd "$g/.." && pwd); }
_ol_log() { local r; r="$(_ol_root)" || return 1; printf '%s/.aicrew/owner.log' "$r"; }
_ol_keyfile() { local h; h="$(eval echo "~$(id -un)" 2>/dev/null)"; [ -d "$h" ] || return 1; printf '%s/.config/aicrew/owner.key' "$h"; }
_ol_key() { local k; k="$(_ol_keyfile)" || return 1; [ -s "$k" ] && cat "$k"; }
_ol_ensure_key() {
  local k; k="$(_ol_keyfile)" || return 1; [ -s "$k" ] && return 0
  mkdir -p "$(dirname "$k")" 2>/dev/null || return 1
  ( umask 077; openssl rand -hex 32 > "$k" ) 2>/dev/null; [ -s "$k" ] && chmod 600 "$k"
}
_ol_hmac() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$(_ol_key)" 2>/dev/null | sed 's/^.* //'; }
# ol_context <n>: sidik jari isu (nomor, label terurut, badan, state) pada saat ini
ol_context() { ls_view "$1" 2>/dev/null | jq -c '[.number,((.labels // [])|map(.name)|sort),(.body // ""),.state]' | shasum | cut -d' ' -f1; }
# ol_record <n> <sha> [scope=merge]: tulis persetujuan (dipanggil owner-local.sh setelah TTY dan konfirmasi); konteks dihitung di sini
ol_record() {
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$2" =~ ^[0-9a-f]{40}$ ]] || return 1
  local scope="${3:-merge}" log msg ctx; log="$(_ol_log)" || return 1; _ol_ensure_key || return 1; ctx="$(ol_context "$1")"; [ -n "$ctx" ] || return 1
  mkdir -p "$(dirname "$log")" 2>/dev/null; msg="$(date +%s)|$1|$2|$scope|$ctx"
  printf '%s|%s\n' "$msg" "$(_ol_hmac "$msg")" >> "$log"
}
# ol_approved <n> <sha> [scope=merge]: exit 0 bila ada baris sah (HMAC cocok) untuk isu, sha, cakupan, dan konteks isu SAAT INI
ol_approved() {
  local scope="${3:-merge}" log line msg mac ts n sha sc cx now; log="$(_ol_log)" || return 1; [ -s "$log" ] && [ -n "$(_ol_key)" ] || return 1
  now="$(ol_context "$1")"; [ -n "$now" ] || return 1
  while IFS= read -r line; do
    IFS='|' read -r ts n sha sc cx mac <<<"$line"; [ "$n" = "$1" ] && [ "$sha" = "$2" ] && [ "$sc" = "$scope" ] && [ "$cx" = "$now" ] || continue
    msg="$ts|$n|$sha|$sc|$cx"; [ -n "$mac" ] && [ "$(_ol_hmac "$msg")" = "$mac" ] && return 0
  done < "$log"
  return 1
}
