# katalog pesan aicrew, Indonesia (pilihan). Satu cabang `case` per kunci; argumen adalah $2.. setelah kunci.
msg_id() {
  local k="$1"; shift
  case "$k" in
    lang.selftest) printf 'bahasa: Indonesia' ;;
    lang.args) printf 'dua argumen: %s dan %s' "$@" ;;
    *) return 1 ;;
  esac
}
