#!/usr/bin/env bash
# aicrew lock: jalankan perintah dengan kunci bernama, agar dua sesi tidak memakai stack bersama (Docker/Keycloak, DB tes) bersamaan.
# Pakai: lock.sh <nama> [--wait detik] -- perintah...   (bawaan tunggu 300 dtk; habis waktu = exit 75; selain itu exit status perintah)
# Kunci = direktori (mkdir atomik; flock tidak ada di macOS) berisi pid pemegang; kunci milik proses yang sudah mati diambil alih.
set -uo pipefail
name="${1:?nama kunci}"; shift; wait_s=300
[ "${1:-}" = "--wait" ] && { wait_s="${2:?detik}"; shift 2; }
[ "${1:-}" = "--" ] && shift; [ "$#" -gt 0 ] || { echo "pakai: lock.sh <nama> [--wait detik] -- perintah..." >&2; exit 64; }
d="${TMPDIR:-/tmp}/aicrew-lock-$name"; waited=0
until mkdir "$d" 2>/dev/null; do
  holder="$(cat "$d/pid" 2>/dev/null || true)"
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$d"; continue; fi
  [ "$waited" -lt "$wait_s" ] || { echo "lock: '$name' dipegang pid ${holder:-?}; habis waktu ${wait_s}s" >&2; exit 75; }
  sleep 1; waited=$((waited+1))
done
echo $$ > "$d/pid"; trap 'rm -rf "$d"' EXIT
"$@"
