#!/usr/bin/env bash
# aicrew guard: penjaga proses (#154). Dijalankan di latar oleh skrip yang tidak boleh meninggalkan anak yatim:  guard.sh <pid-induk> [timeout-detik=0] [jalur-untuk-dihapus ...]
# - Tiap 0,5 dtk mencatat keturunan induk. Induk mati (mis. dimatikan pemanggil dengan TERM/INT/timeout) -> semua keturunan yang tercatat dimatikan.
# - timeout > 0 dan induk masih hidup melewatinya -> keturunan dimatikan, lalu induk di-TERM (dan KILL bila masih ada setelah 1 dtk).
# Jalur tambahan dihapus (rm -rf) saat induk selesai: induk TIDAK memasang trap EXIT, karena bash menunda TERM selama perintah latar depan jika ada trap (anak yatim); semua pembersihan ada di sini.
# Tidak pernah gagal keras; berhenti sendiri saat induk selesai normal (induk mematikan penjaga di EXIT).
exec 2>>/tmp/guard2.trace; set -x; parent="${1:-}"; limit="${2:-0}"; me="$$"; shift 2 2>/dev/null; cleanup_paths=("$@")
finish() { local f; for f in "${cleanup_paths[@]+"${cleanup_paths[@]}"}"; do [ -n "$f" ] && rm -rf "$f" 2>/dev/null; done; exit 0; }
[[ "$parent" =~ ^[0-9]+$ ]] || exit 64; [[ "$limit" =~ ^[0-9]+$ ]] || limit=0
tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do [ "$c" = "$me" ] && continue; echo "$c"; tree "$c"; done; }
# mata hanya pid yang induknya masih salah satu pid tercatat atau 1 (sudah yatim): pid yang kebetulan dipakai ulang proses lain tidak ikut terbunuh
killall_pids() { local p pp; for p in "$@"; do pp="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; [ -n "$pp" ] || continue
  case " $* $parent 1 " in *" $pp "*) kill "$p" 2>/dev/null ;; esac; done; }
end=$(( $(date +%s) + limit )); snap=""
while :; do
  if ! kill -0 "$parent" 2>/dev/null; then killall_pids $snap; finish; fi
  snap="$(tree "$parent" | tr '\n' ' ')"
  if [ "$limit" != 0 ] && [ "$(date +%s)" -ge "$end" ]; then
    echo "guard: batas waktu ${limit}s tercapai; menghentikan proses $parent" >&2
    killall_pids $snap; kill -TERM "$parent" 2>/dev/null; sleep 1; kill -KILL "$parent" 2>/dev/null; finish
  fi
  sleep 0.5
done
