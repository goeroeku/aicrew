#!/usr/bin/env bash
# aicrew label: nama label yang dapat dikonfigurasi. Pakai: label.sh integrated|auto|discovery|notsplit|noparent|waiting [--all]
# Urutan: env (AICREW_LABEL_*), baris docs/WORKFLOW.md ("Integrated label: x" dst.; kunci Indonesia lama dipetakan oleh workflow.sh), bawaan Inggris.
# --all: cetak nama efektif lalu nama bawaan lama (alias usang), satu per baris, supaya issue yang sudah berlabel lama tetap dikenali.
case "${1:-}" in
  integrated) v="${AICREW_LABEL_INTEGRATED:-}"; k='Integrated label'; def=integrated; old=di-integrasi ;;
  auto) v="${AICREW_LABEL_AUTO:-}"; k='Auto-decision label'; def=auto-decision; old=keputusan-otomatis ;;
  discovery) v="${AICREW_LABEL_DISCOVERY:-}"; k='Discovery label'; def='discovery phase:discovery'; old= ;;
  notsplit) v="${AICREW_LABEL_NOTSPLIT:-}"; k='Unsplit epic label'; def=unsplit; old=belum-dipecah ;;
  noparent) v="${AICREW_LABEL_NOPARENT:-}"; k='No-parent label'; def=no-parent; old=tanpa-induk ;;
  waiting) v="${AICREW_LABEL_WAITING:-}"; k='Awaiting-release label'; def=awaiting-release; old=menunggu-rilis ;;
  *) echo "pakai: label.sh integrated|auto|discovery|notsplit|noparent|waiting [--all]" >&2; exit 64 ;;
esac
[ -n "$v" ] || v="$(sed -n "s/^[- ]*$k: *\([A-Za-z0-9._:\/-]*\).*/\1/p" 2>/dev/null <<<"$(bash "$(dirname "$0")/workflow.sh")" | head -1)"
v="${v:-$def}"; echo "$v"
if [ "${2:-}" = "--all" ] && [ -n "$old" ]; then [ "$old" = "$v" ] || echo "$old"; [ "$def" = "$v" ] || echo "$def"; fi
