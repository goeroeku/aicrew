# aicrew message catalog, English (default). One `case` branch per key; arguments are $2.. after the key.
msg_en() {
  local k="$1"; shift
  case "$k" in
    lang.selftest) printf 'language: English' ;;
    lang.args) printf 'two args: %s and %s' "$@" ;;
    *) return 1 ;;
  esac
}
