#!/usr/bin/env bash
# aicrew baseline-scan: pemeriksaan keamanan baseline atas diff (stdin), tanpa jaringan. Dipanggil pr-merge-check.sh untuk semua PR.
#   git diff <basis>...HEAD | baseline-scan.sh --body <berkas-badan-PR> --perf-labeled <0|1>
# BLOK: (exit 1) rahasia pada baris tambahan atau berkas .env; nilainya tidak pernah dicetak.
# PERINGATAN: (exit 0) `|| true` pada jalur sync/auth/verify, dependensi baru yang tak disebut di badan PR, jalur perf tanpa needs-perf.
set -u
body=""; perf=0
while [ $# -gt 0 ]; do case "$1" in
  --body) body="$2"; shift 2 ;; --perf-labeled) perf="$2"; shift 2 ;; *) echo "argumen tak dikenal: $1" >&2; exit 64 ;; esac; done
[ -f "$body" ] || body=/dev/null
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
# F = berkas yang disentuh; A = baris tambahan: "berkas<TAB>teks" (header +++ tidak dihitung)
awk '/^\+\+\+ /{f=substr($0,7); print f > "'"$t"'/f"; next} /^\+/{print f "\t" substr($0,2) > "'"$t"'/a"}' 
touch "$t/f" "$t/a"
blok=0
secret() { # <nama> <regex>: cetak BLOK per berkas yang cocok
  for f in $(grep -Ei "$2" "$t/a" | cut -f1 | sort -u); do echo "BLOK: $1 di $f"; blok=1; done; }
secret "kunci AWS" 'AKIA[0-9A-Z]{16}'
secret "kunci privat" 'BEGIN ([A-Z]+ )?PRIVATE KEY'
secret "token GitHub" 'gh[pousr]_[A-Za-z0-9]{36,}'
secret "kredensial literal" "(password|passwd|secret|token|api[_-]?key)[A-Za-z_]*[[:space:]]*[:=][[:space:]]*['\"][^'\"]{12,}['\"]"
for f in $(grep -E '(^|/)\.env(\.[^/]*)?$' "$t/f" | grep -Eiv '\.(example|sample|template)$'); do echo "BLOK: berkas .env ditambahkan: $f"; blok=1; done
for f in $(grep -Ei '(sync|fsync|auth|verif).*\|\|[[:space:]]*true' "$t/a" | cut -f1 | sort -u); do
  echo "PERINGATAN: '|| true' membungkam kegagalan pada jalur sync/auth/verify di $f"; done
while IFS="$(printf '\t')" read -r f x; do
  name=""; b="${f##*/}"
  case "$b" in
    package.json|composer.json) name="$(sed -nE 's/^[[:space:]]*"([^"]+)":[[:space:]]*"[~^]?[0-9][0-9A-Za-z.*-]*",?$/\1/p' <<<"$x")" ;;
    go.mod) name="$(sed -nE 's/^[[:space:]]*(require[[:space:]]+)?([^[:space:]]+\/[^[:space:]]+)[[:space:]]+v[0-9].*/\2/p' <<<"$x")" ;;
    requirements*.txt) name="$(sed -nE 's/^([A-Za-z0-9_.-]+)([=<>~!].*)?$/\1/p' <<<"$x")" ;;
    Cargo.toml) name="$(sed -nE 's/^([a-z0-9_-]+)[[:space:]]*=[[:space:]]*["{].*/\1/p' <<<"$x")" ;;
    Gemfile) name="$(sed -nE "s/^[[:space:]]*gem[[:space:]]+['\"]([^'\"]+)['\"].*/\1/p" <<<"$x")" ;;
    Dockerfile*) name="$(sed -nE 's/^FROM[[:space:]]+(--[^[:space:]]+[[:space:]]+)?([^[:space:]:@]+).*/\2/p' <<<"$x")" ;;
    *compose*.y*ml) name="$(sed -nE "s/^[[:space:]]*image:[[:space:]]*[\"']?([^[:space:]\"':@]+).*/\1/p" <<<"$x")" ;;
  esac
  case "$name" in ""|version|name|edition|description|license|authors|main|type|scratch) continue ;; esac
  grep -qiF -- "$name" "$body" || echo "PERINGATAN: dependensi baru '$name' ($f) tidak disebut di badan PR"
done < "$t/a"
if [ "$perf" = 0 ]; then
  for f in $(grep -Ei '(^|/)migrations?/|(^|/)Dockerfile|compose[^/]*\.ya?ml$|redis[^/]*\.conf$|postgres[^/]*\.conf$|(queue|worker|cron)' "$t/f" | sort -u); do
    echo "PERINGATAN: $f menyentuh jalur tulis DB/antrean/cron/config infra tetapi PR belum berlabel needs-perf"; done
fi
exit "$blok"
