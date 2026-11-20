#!/usr/bin/env bash
# aicrew ownerlocal: persetujuan pemilik LOKAL (#159 tahap 4B, `Quota mode: local`). Di-source. Persetujuan = baris `ts|n|sha|scope|hmac` di .aicrew/owner.log, HMAC-SHA256 dengan kunci
# ~/.config/aicrew/owner.key (dibuat saat persetujuan pertama, mode 0600; AICREW_OWNER_KEY menimpa lokasinya). Terikat ke isu, sha kepala, dan cakupan (merge): cabang yang didorong ulang
# membuat persetujuan lama tak berlaku. Penulisnya owner-local.sh (menolak berjalan tanpa TTY); izin agen menolak Read kunci, Write log, dan perintah approve (templates/autopilot-permissions.json).
# Batas: agen dengan Bash penuh sebagai pengguna yang sama tetap dapat membaca kunci; ini pagar kecelakaan dan prompt injection, bukan pertahanan terhadap agen berniat jahat.
_ol_root() { local g; g="$(git rev-parse --git-common-dir 2>/dev/null)" && (cd "$g/.." && pwd); }
_ol_log() { local r; r="$(_ol_root)" || return 1; printf '%s/.aicrew/owner.log' "$r"; }
_ol_keyfile() { printf '%s' "${AICREW_OWNER_KEY:-$HOME/.config/aicrew/owner.key}"; }
_ol_key() { local k; k="$(_ol_keyfile)"; [ -s "$k" ] && cat "$k"; }
_ol_ensure_key() {
  local k; k="$(_ol_keyfile)"; [ -s "$k" ] && return 0
  mkdir -p "$(dirname "$k")" 2>/dev/null || return 1
  ( umask 077; openssl rand -hex 32 > "$k" ) 2>/dev/null; [ -s "$k" ] && chmod 600 "$k"
}
_ol_hmac() { printf '%s' "$1" | openssl dgst -sha256 -hmac "$(_ol_key)" 2>/dev/null | sed 's/^.* //'; }
# ol_record <n> <sha> [scope=merge]: tulis persetujuan (dipanggil owner-local.sh setelah TTY dan konfirmasi)
ol_record() {
  [[ "$1" =~ ^[0-9]+$ ]] && [[ "$2" =~ ^[0-9a-f]{40}$ ]] || return 1
  local scope="${3:-merge}" log msg; log="$(_ol_log)" || return 1; _ol_ensure_key || return 1
  mkdir -p "$(dirname "$log")" 2>/dev/null; msg="$(date +%s)|$1|$2|$scope"
  printf '%s|%s\n' "$msg" "$(_ol_hmac "$msg")" >> "$log"
}
# ol_approved <n> <sha> [scope=merge]: exit 0 bila ada baris sah (HMAC cocok) untuk isu, sha, dan cakupan itu
ol_approved() {
  local scope="${3:-merge}" log line msg mac ts n sha sc; log="$(_ol_log)" || return 1; [ -s "$log" ] && [ -n "$(_ol_key)" ] || return 1
  while IFS= read -r line; do
    IFS='|' read -r ts n sha sc mac <<<"$line"; [ "$n" = "$1" ] && [ "$sha" = "$2" ] && [ "$sc" = "$scope" ] || continue
    msg="$ts|$n|$sha|$sc"; [ -n "$mac" ] && [ "$(_ol_hmac "$msg")" = "$mac" ] && return 0
  done < "$log"
  return 1
}
