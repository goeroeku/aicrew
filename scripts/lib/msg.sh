#!/usr/bin/env bash
# aicrew msg: katalog pesan dua bahasa (#64, tahap C). Di-source; tidak dijalankan.
#   msg_lang          -> en | id. Urutan: env AICREW_LANG, berkas env AICREW_ENV_FILE, "Language:" di docs/WORKFLOW.md repo, lalu en. Nilai tak dikenal = en.
#   msg <kunci> [arg...]  -> teks pesan ke stdout (printf, tanpa baris baru di akhir). Pemanggil yang memilih >&2, prefiks, dan kode keluar.
# Katalog: scripts/lib/msg/en.sh dan id.sh, masing-masing fungsi msg_en / msg_id berisi `case` per kunci (bash 3.2 tanpa array asosiatif).
# Kunci tak ada di katalog bahasa terpilih -> jatuh ke en; tak ada di keduanya -> mencetak kuncinya (gagal terlihat). AICREW_MSG_DIR hanya untuk tes.
# Kontrak mesin (token vonis, heading, penanda stderr, GAGAL:/PERINGATAN:) TIDAK dikatalogkan: lihat spec 2026-11-04-bahasa-inggris-bawaan-design.md.
_msg_dir="${AICREW_MSG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/msg}"
_msg_norm() { case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in id) echo id ;; *) echo en ;; esac; }
msg_lang() {
  local l="${AICREW_LANG:-}" f top wf
  if [ -z "$l" ] && [ -n "${AICREW_ENV_FILE:-}" ] && [ -f "$AICREW_ENV_FILE" ]; then
    l="$(sed -n -E "s/^(export )?AICREW_LANG=[\"']?([A-Za-z]*).*/\2/p" "$AICREW_ENV_FILE" | head -1)"
  fi
  if [ -z "$l" ]; then
    top="$(git rev-parse --show-toplevel 2>/dev/null)"; wf="$top/docs/WORKFLOW.md"
    # kunci "Language:" di awal baris (boleh butir, nomor, ** atau `); "Artifact language:" tidak cocok karena diawali kata lain
    [ -n "$top" ] && [ -f "$wf" ] && l="$(sed -n -E 's/^[-*0-9. ]*[*`]*[Ll][Aa][Nn][Gg][Uu][Aa][Gg][Ee]:?[*` ]*([A-Za-z]+).*/\1/p' "$wf" | head -1)"
  fi
  _msg_norm "$l"
}
msg() {
  local k="${1:-}" l; shift 2>/dev/null
  l="$(msg_lang)"
  for lang in "$l" en; do
    [ -f "$_msg_dir/$lang.sh" ] || continue
    ( . "$_msg_dir/$lang.sh"; "msg_$lang" "$k" "$@" ) 2>/dev/null && return 0
  done
  printf '%s' "$k"
}
