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
# F = berkas yang disentuh; A = baris tambahan "berkas<TAB>teks". Header (+++) hanya diakui antara `diff --git` dan `@@` pertama,
# sehingga baris tambahan berawalan "++ " di dalam hunk tidak bisa dibaca sebagai header. Path berkutip git (non-ASCII) dibuka kutipnya.
awk -v F="$t/f" -v A="$t/a" -v R="$t/r" '
  /^diff --git /{hdr=1; next}
  hdr && /^@@/{hdr=0; next}
  hdr && /^\+\+\+ /{p=substr($0,5); sub(/^"/,"",p); sub(/"$/,"",p); sub(/^b\//,"",p); f=p; print f > F; next}
  hdr{next}
  /^\+/{print f "\t" substr($0,2) > A}
  /^-/{print f "\t" substr($0,2) > R}'
touch "$t/f" "$t/a" "$t/r"
blok=0
secret() { # <nama> <regex>: BLOK per berkas yang cocok; blok ditetapkan dari ada-tidaknya cocokan, bukan dari nama berkas
  grep -Eiq "$2" "$t/a" || return 0; blok=1
  grep -Ei "$2" "$t/a" | cut -f1 | sort -u | while IFS= read -r f; do echo "BLOK: $1 di $f"; done; }
secret "kunci AWS" 'AKIA[0-9A-Z]{16}'
secret "kunci privat" 'BEGIN ([A-Z]+ )?PRIVATE KEY'
secret "token GitHub" 'gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,}'
secret "token Slack/Stripe" 'xox[abprs]-[A-Za-z0-9-]{10,}|sk_live_[A-Za-z0-9]{16,}'
secret "kredensial literal" "(password|passwd|secret|token|api[_-]?key)[A-Za-z_]*[\"']?[[:space:]]*(:=|[:=])[[:space:]]*[\"'][^\"']{12,}[\"']"
grep -E '(^|/)\.env(\.[^/]*)?$' "$t/f" | grep -Eiv '\.(example|sample|template)$' > "$t/e"
[ -s "$t/e" ] && blok=1
while IFS= read -r f; do echo "BLOK: berkas .env ditambahkan: $f"; done < "$t/e"
grep -Ei '(password|passwd|secret|api[_-]?key|token)[A-Za-z_]*[[:space:]]*[:=][[:space:]]*[A-Za-z0-9/+_=.-]{16,}[[:space:]]*$' "$t/a" | cut -f1 | sort -u \
  | while IFS= read -r f; do echo "PERINGATAN: nilai tanpa kutip mirip kredensial di $f (periksa; tidak diblokir karena rawan positif palsu)"; done
grep -Ei '(sync|fsync|auth|verif).*\|\|[[:space:]]*true' "$t/a" | cut -f1 | sort -u \
  | while IFS= read -r f; do echo "PERINGATAN: '|| true' membungkam kegagalan pada jalur sync/auth/verify di $f"; done
depname() { # <berkas> <teks>: nama dependensi bila baris itu mendeklarasikannya, kosong bila bukan
  local b="${1##*/}" x="$2" n=""
  case "$b" in
    package.json|composer.json) n="$(sed -nE 's/^[[:space:]]*"([^"]+)":[[:space:]]*"[~^]?[0-9][0-9A-Za-z.*-]*",?$/\1/p' <<<"$x")" ;;
    go.mod) n="$(sed -nE 's/^[[:space:]]*(require[[:space:]]+)?([^[:space:]]+\/[^[:space:]]+)[[:space:]]+v[0-9].*/\2/p' <<<"$x")" ;;
    requirements*.txt) n="$(sed -nE 's/^([A-Za-z0-9_.-]+)([=<>~!].*)?$/\1/p' <<<"$x")" ;;
    Cargo.toml) n="$(sed -nE 's/^([a-z0-9_-]+)[[:space:]]*=[[:space:]]*["{].*/\1/p' <<<"$x")" ;;
    Gemfile) n="$(sed -nE "s/^[[:space:]]*gem[[:space:]]+['\"]([^'\"]+)['\"].*/\1/p" <<<"$x")" ;;
    Dockerfile*) n="$(sed -nE 's/^FROM[[:space:]]+(--[^[:space:]]+[[:space:]]+)?([^[:space:]:@]+).*/\2/p' <<<"$x")" ;;
    *compose*.y*ml) n="$(sed -nE "s/^[[:space:]]*image:[[:space:]]*[\"']?([^[:space:]\"':@]+).*/\1/p" <<<"$x")" ;;
  esac
  case "$n" in version|name|edition|description|license|authors|main|type|scratch) n="" ;; esac
  printf '%s' "$n"
}
# dependensi "baru" = nama yang muncul di baris tambahan tetapi tidak pernah di baris yang dihapus pada berkas yang sama (kenaikan versi bukan baru)
: > "$t/rn"
while IFS="$(printf '\t')" read -r f x; do n="$(depname "$f" "$x")"; [ -z "$n" ] || printf '%s\t%s\n' "$f" "$n" >> "$t/rn"; done < "$t/r"
while IFS="$(printf '\t')" read -r f x; do
  name="$(depname "$f" "$x")"; [ -n "$name" ] || continue
  grep -qxF "$(printf '%s\t%s' "$f" "$name")" "$t/rn" && continue
  grep -qiF -- "$name" "$body" || echo "PERINGATAN: dependensi baru '$name' ($f) tidak disebut di badan PR"
done < "$t/a"
if [ "$perf" = 0 ]; then
  grep -Ei '(^|/)migrations?/|(^|/)Dockerfile|compose[^/]*\.ya?ml$|redis[^/]*\.conf$|postgres[^/]*\.conf$|(queue|worker|cron)' "$t/f" | sort -u \
    | while IFS= read -r f; do echo "PERINGATAN: $f menyentuh jalur tulis DB/antrean/cron/config infra tetapi PR belum berlabel needs-perf"; done
fi
exit "$blok"
