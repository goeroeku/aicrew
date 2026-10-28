#!/usr/bin/env bash
# aicrew notify: hook Notification -> Telegram (hanya KELUAR, tidak menerima perintah).
# Aktif bila AICREW_TG_TOKEN dan AICREW_TG_CHAT diset di lingkungan; selain itu diam. Selalu exit 0.
[ -n "${AICREW_TG_TOKEN:-}" ] && [ -n "${AICREW_TG_CHAT:-}" ] || exit 0
input="$(cat 2>/dev/null)"
msg="aicrew: butuh perhatian"
if command -v jq >/dev/null 2>&1 && [ -n "$input" ]; then
  m="$(printf '%s' "$input" | jq -r '.message // empty' 2>/dev/null)"
  [ -n "$m" ] && msg="aicrew: $m"
fi
curl -sS -m 10 -o /dev/null "https://api.telegram.org/bot${AICREW_TG_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${AICREW_TG_CHAT}" --data-urlencode "text=${msg} [$(basename "$PWD")]" >/dev/null 2>&1
exit 0
