#!/usr/bin/env bash
# aicrew label: nama label yang dapat dikonfigurasi. Pakai: label.sh integrated|auto|discovery|notsplit|noparent|waiting [--all | --json]
# Urutan: env (AICREW_LABEL_*), baris docs/WORKFLOW.md ("Integrated label: x" dst.; kunci Indonesia lama dipetakan oleh workflow.sh), bawaan Inggris.
# --all / --json: nama efektif + alias usang (nama bawaan lama), supaya issue yang sudah berlabel lama tetap dikenali.
# Alias hanya ditambahkan bila owner TIDAK memakai nama kustom (nama kustom tidak diperluas, agar label lain tak ikut cocok).
case "${1:-}" in
  integrated) v="${AICREW_LABEL_INTEGRATED:-}"; k='Integrated label'; def=integrated; old=di-integrasi ;;
  auto) v="${AICREW_LABEL_AUTO:-}"; k='Auto-decision label'; def=auto-decision; old=keputusan-otomatis ;;
  discovery) v="${AICREW_LABEL_DISCOVERY:-}"; k='Discovery label'; def='discovery phase:discovery'; old= ;;
  notsplit) v="${AICREW_LABEL_NOTSPLIT:-}"; k='Unsplit epic label'; def=unsplit; old=belum-dipecah ;;
  noparent) v="${AICREW_LABEL_NOPARENT:-}"; k='No-parent label'; def=no-parent; old=tanpa-induk ;;
  waiting) v="${AICREW_LABEL_WAITING:-}"; k='Awaiting-release label'; def=awaiting-release; old=menunggu-rilis ;;
  *) echo "pakai: label.sh integrated|auto|discovery|notsplit|noparent|waiting [--all|--json]" >&2; exit 64 ;;
esac
[ -n "$v" ] || v="$(sed -n "s/^[- ]*$k: *\([A-Za-z0-9._:\/-]*\).*/\1/p" 2>/dev/null <<<"$(bash "$(dirname "$0")/workflow.sh")" | head -1)"
v="${v:-$def}"
names="$v"
if [ -n "$old" ] && { [ "$v" = "$def" ] || [ "$v" = "$old" ]; }; then
  for n in "$old" "$def"; do case $'\n'"$names"$'\n' in *$'\n'"$n"$'\n'*) ;; *) names="$names"$'\n'"$n" ;; esac; done
fi
case "${2:-}" in
  --all) printf '%s\n' "$names" ;;
  --json) printf '%s\n' "$names" | jq -Rsc 'split("\n")|map(select(.!=""))' ;;
  *) echo "$v" ;;
esac
