#!/usr/bin/env bash
# aicrew merge-mode: mode "Merge PR to integration branch:" -> owner | agent-after-qa.
# Pakai (setelah `source`): merge_mode <docs/WORKFLOW.md>. Env AICREW_MERGE_MODE menang; selain itu dibaca lewat wf-normalize.sh
# (kunci boleh di tengah baris, nilai boleh dibungkus ` atau **, huruf besar-kecil tak dibedakan); bawaan owner.
merge_mode() {
  local m="${AICREW_MERGE_MODE:-}"
  if [ -z "$m" ] && [ -f "${1:-}" ]; then
    m="$({ bash "$(dirname "${BASH_SOURCE[0]}")/wf-normalize.sh" < "$1"; } 2>/dev/null | sed -nE 's/.*Merge PR to integration branch:[*` ]*([A-Za-z-]+).*/\1/p' | head -1 || true)"
  fi
  case "$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]')" in
    agent-after-qa|agen-setelah-qa) echo agent-after-qa ;;   # alias-usang
    *) echo owner ;;
  esac
}
