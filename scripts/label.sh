#!/usr/bin/env bash
# aicrew label: nama label yang dapat dikonfigurasi. Pakai: label.sh integrated|auto
# Urutan: env (AICREW_LABEL_INTEGRATED / AICREW_LABEL_AUTO), baris docs/WORKFLOW.md ("Label integrasi: x" / "Label keputusan otomatis: x"), bawaan.
case "${1:-}" in
  integrated) v="${AICREW_LABEL_INTEGRATED:-}"; k='Label integrasi'; def=di-integrasi ;;
  auto) v="${AICREW_LABEL_AUTO:-}"; k='Label keputusan otomatis'; def=keputusan-otomatis ;;
  discovery) v="${AICREW_LABEL_DISCOVERY:-}"; k='Label discovery'; def='discovery phase:discovery' ;;
  notsplit) v="${AICREW_LABEL_NOTSPLIT:-}"; k='Label epic belum dipecah'; def=belum-dipecah ;;
  noparent) v="${AICREW_LABEL_NOPARENT:-}"; k='Label tanpa induk'; def=tanpa-induk ;;
  *) echo "pakai: label.sh integrated|auto|discovery|notsplit|noparent" >&2; exit 64 ;;
esac
[ -n "$v" ] || v="$(sed -n "s/^[- ]*$k: *\([A-Za-z0-9._:\/-]*\).*/\1/p" 2>/dev/null <<<"$(bash "$(dirname "$0")/workflow.sh")" | head -1)"
echo "${v:-$def}"
