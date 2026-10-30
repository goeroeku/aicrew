#!/usr/bin/env bash
# aicrew notify: hook Notification -> Telegram dan/atau Orca (hanya KELUAR, tidak menerima perintah). Selalu exit 0.
# Driver: AICREW_NOTIFY atau opsi plugin notify = telegram (bawaan) | orca | both.
# Telegram aktif bila token dan chat ID diisi (pengaturan plugin atau AICREW_TG_*); selain itu diam.
# Orca: menandai workspace (worktree path:<cwd>) belum dibaca dan menyimpan teks sebagai komentar; biner dari AICREW_ORCA_BIN, Orca.app, atau PATH.
driver="${CLAUDE_PLUGIN_OPTION_NOTIFY:-${AICREW_NOTIFY:-telegram}}"
tok="${CLAUDE_PLUGIN_OPTION_TG_TOKEN:-${AICREW_TG_TOKEN:-}}"; chat="${CLAUDE_PLUGIN_OPTION_TG_CHAT:-${AICREW_TG_CHAT:-}}"
input="$(cat 2>/dev/null)"
msg="butuh perhatian"; dir="$PWD"
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  m="$(printf '%s' "$input" | jq -r '.message // empty' 2>/dev/null)"; [ -n "$m" ] && msg="$m"
  d="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"; [ -n "$d" ] && dir="$d"
fi
case "$driver" in telegram|both)
  if [ -n "$tok" ] && [ -n "$chat" ]; then
    curl -sS -m 10 -o /dev/null "https://api.telegram.org/bot${tok}/sendMessage" \
      --data-urlencode "chat_id=${chat}" --data-urlencode "text=aicrew: ${msg} [$(basename "$dir")]" >/dev/null 2>&1
  fi ;; esac
case "$driver" in orca|both)
  orca="${AICREW_ORCA_BIN:-/Applications/Orca.app/Contents/Resources/bin/orca}"
  [ -x "$orca" ] || orca="$(command -v orca 2>/dev/null)"
  [ -x "$orca" ] && "$orca" worktree set --worktree "path:$dir" --unread --comment "aicrew: $msg ($(date +%H:%M))" >/dev/null 2>&1 ;; esac
exit 0
