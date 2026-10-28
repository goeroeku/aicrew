#!/usr/bin/env bash
# aicrew notify: hook Notification -> Telegram (hanya KELUAR, tidak menerima perintah).
# Aktif bila token dan chat ID Telegram diisi (pengaturan plugin atau AICREW_TG_*); selain itu diam. Selalu exit 0.
# token dari pengaturan plugin (userConfig tg_token/tg_chat, diekspor ke hook sebagai CLAUDE_PLUGIN_OPTION_*), cadangan AICREW_TG_*
tok="${CLAUDE_PLUGIN_OPTION_TG_TOKEN:-${AICREW_TG_TOKEN:-}}"; chat="${CLAUDE_PLUGIN_OPTION_TG_CHAT:-${AICREW_TG_CHAT:-}}"
[ -n "$tok" ] && [ -n "$chat" ] || exit 0
input="$(cat 2>/dev/null)"
msg="aicrew: butuh perhatian"
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  m="$(printf '%s' "$input" | jq -r '.message // empty' 2>/dev/null)"
  [ -n "$m" ] && msg="aicrew: $m"
fi
curl -sS -m 10 -o /dev/null "https://api.telegram.org/bot${tok}/sendMessage" \
  --data-urlencode "chat_id=${chat}" --data-urlencode "text=${msg} [$(basename "$PWD")]" >/dev/null 2>&1
exit 0
