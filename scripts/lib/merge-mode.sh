#!/usr/bin/env bash
# aicrew merge-mode: mode "Merge PR to integration branch:" -> owner | agent-after-qa.
# Pakai (setelah `source`): merge_mode <docs/WORKFLOW.md>. Env AICREW_MERGE_MODE menang; selain itu dibaca lewat wf-normalize.sh
# (kunci boleh di tengah baris, nilai boleh dibungkus ` atau **, huruf besar-kecil tak dibedakan); bawaan owner.
# Gagal selalu ke arah ketat (owner): nol nilai, nilai tak dikenal, atau lebih dari satu nilai berbeda (prosa yang mengutip kunci, salah konfigurasi) = owner.
# Pemetaan di fungsi sendiri: pola case dengan ")" di dalam $(...) salah diurai bash 3.2.
_mm_canon() { case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    agent-after-qa|agen-setelah-qa) echo agent-after-qa ;;   # alias-usang
    *) echo "$1" ;;
  esac; }
merge_mode() {
  local m="${AICREW_MERGE_MODE:-}" vals="" v
  if [ -z "$m" ] && [ -f "${1:-}" ]; then
    vals="$({ bash "$(dirname "${BASH_SOURCE[0]}")/wf-normalize.sh" < "$1"; } 2>/dev/null | grep -oiE 'merge pr to integration branch:[*` ]*[a-z-]+' | sed -E 's/^[^:]*:[*` ]*//' | while read -r v; do _mm_canon "$v"; done | tr '[:upper:]' '[:lower:]' | sort -u || true)"
    [ "$(printf '%s\n' "$vals" | grep -c .)" = 1 ] && m="$vals"
  fi
  case "$(_mm_canon "$m")" in
    agent-after-qa) echo agent-after-qa ;;
    *) echo owner ;;
  esac
}
