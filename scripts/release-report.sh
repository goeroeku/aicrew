#!/usr/bin/env bash
# aicrew release-report: laporan calon rilis (cabang integrasi -> main) dari FAKTA GitHub + suite tes di salinan segar. GitHub/gh saja.
#   release-report.sh [--integ CABANG] [--test-cmd "node --test"] [--out BERKAS] [--base main] [--buka-pr] [--dry-run]
# Cabang integrasi default dibaca dari docs/WORKFLOW.md ("Cabang integrasi: <nama>"). Laporan ditulis ke --out (default .aicrew/release-report.md).
# PR integrasi -> base HANYA dibuka bila --buka-pr, vonis SIAP, dan tanpa --dry-run. Tidak pernah merge. Item daftar periksa yang butuh
# penilaian (keamanan, smoke test, runbook) dicetak sebagai kotak kosong untuk diisi agen; skrip hanya memvonis fakta.
# Exit: 0 SIAP, 1 BELUM SIAP, 64 argumen/cabang tidak diketahui.
set -u
integ=""; testcmd=""; out=""; base=main; open_pr=0; dry=0; wf=docs/WORKFLOW.md
while [ $# -gt 0 ]; do case "$1" in
  --integ) integ="$2"; shift 2 ;; --test-cmd) testcmd="$2"; shift 2 ;; --out) out="$2"; shift 2 ;; --base) base="$2"; shift 2 ;;
  --buka-pr) open_pr=1; shift ;; --dry-run) dry=1; shift ;; *) echo "argumen tak dikenal: $1" >&2; exit 64 ;; esac; done
[ -n "$integ" ] || integ="$(grep -oE 'Cabang integrasi: [A-Za-z0-9._/-]+' "$wf" 2>/dev/null | head -1 | awk '{print $3}' | sed 's/[.]*$//')"
[ -n "$integ" ] || { echo "release-report: cabang integrasi tidak diketahui (pakai --integ)" >&2; exit 64; }
g="$(git rev-parse --git-common-dir)" && d="$(cd "$g/.." && pwd)/.aicrew"; mkdir -p "$d"; [ -n "$out" ] || out="$d/release-report.md"

issues="$(gh issue list --state all --limit 200 --json number,title,state,labels)"
prs="$(gh pr list --state all --limit 200 --json number,title,state,baseRefName,comments)"
merged="$(jq --arg b "$integ" '[.[]|select(.state=="MERGED" and .baseRefName==$b)]' <<<"$prs")"
has() { jq --arg l "$1" 'map(select(.labels|map(.name)|index($l)))' <<<"$2"; }
blocking="$(jq '[.[]|select(.state=="OPEN" and ((.labels|map(.name)|index("di-integrasi"))|not))]' <<<"$issues")"
needs="$(jq '[.[]|select(.state=="OPEN")]' <<<"$issues" | jq 'map(select(.labels|map(.name)|index("needs-principal")))')"
auto="$(has keputusan-otomatis "$issues")"
noevid="$(jq '[.[]|select((.comments|map(.body)|map(contains("Bukti selesai"))|any)|not)]' <<<"$merged")"

# suite di salinan segar dari cabang integrasi
suite="tidak dijalankan (tanpa --test-cmd)"; suite_ok=0; sha="?"
if [ -n "$testcmd" ]; then
  git fetch -q origin "$integ" 2>/dev/null || true
  ref="origin/$integ"; git rev-parse -q --verify "$ref" >/dev/null || ref="$integ"
  wt="$(mktemp -d)"
  if git worktree add -q --detach "$wt/w" "$ref" 2>/dev/null; then
    sha="$(git -C "$wt/w" rev-parse --short HEAD)"
    log="$(cd "$wt/w" && sh -c "$testcmd" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && suite_ok=1
    sum="$(printf '%s' "$log" | grep -E '^ℹ (tests|pass|fail) ' | tr '\n' ' ')"; [ -n "$sum" ] || sum="$(printf '%s' "$log" | tail -n 3 | tr '\n' ' ')"
    suite="\`$testcmd\` -> exit $rc: $sum"
    git worktree remove --force "$wt/w" 2>/dev/null
  else suite="gagal membuat salinan segar dari $ref"; fi
  rm -rf "$wt"
fi

reasons=()
[ "$(jq length <<<"$merged")" = 0 ] && reasons+=("tidak ada PR ter-merge ke $integ")
[ "$(jq length <<<"$blocking")" != 0 ] && reasons+=("$(jq length <<<"$blocking") issue terbuka belum di-integrasi: $(jq -r 'map("#\(.number)")|join(" ")' <<<"$blocking")")
[ "$(jq length <<<"$needs")" != 0 ] && reasons+=("needs-principal menunggu keputusan: $(jq -r 'map("#\(.number)")|join(" ")' <<<"$needs")")
[ "$(jq length <<<"$noevid")" != 0 ] && reasons+=("PR tanpa komentar 'Bukti selesai': $(jq -r 'map("#\(.number)")|join(" ")' <<<"$noevid")")
[ "$suite_ok" = 1 ] || reasons+=("suite penuh tidak lulus/tidak dijalankan")
verdict="SIAP"; [ "${#reasons[@]}" != 0 ] && verdict="BELUM SIAP"

if [ -f "$wf" ] && grep -q '^## Daftar periksa rilis' "$wf"; then
  checklist="$(sed -n '/^## Daftar periksa rilis/,/^## /p' "$wf" | grep '^- ' | sed 's/^- \(\[.\] \)\?/- [ ] /')"
else
  checklist="- [ ] Build bersih di salinan segar
- [ ] Aplikasi dijalankan lokal; smoke test lulus
- [ ] aicrew-security: auth, input, rahasia, dependensi
- [ ] Tidak ada rahasia di repo
- [ ] Runbook singkat: cara jalan, konfigurasi, rollback
- [ ] Setiap kriteria PRD dicentang dengan perintah dan hasilnya"
fi

{
  echo "# Laporan calon rilis: $integ -> $base"
  echo; echo "**Vonis fakta: $verdict** (commit uji: $sha, $(date '+%F %T'))"
  [ "${#reasons[@]}" != 0 ] && { echo; echo "Alasan belum siap:"; printf -- '- %s\n' "${reasons[@]}"; }
  echo; echo "## Suite penuh (salinan segar $integ)"; echo "$suite"
  echo; echo "## PR ter-merge ke $integ"; jq -r '.[]|"- #\(.number) \(.title)"' <<<"$merged"
  echo; echo "## Issue"; jq -r '.[]|"- #\(.number) [\(.state)] \(.title)"' <<<"$issues"
  echo; echo "## Keputusan otomatis (tinjau sebelum merge)"
  [ "$(jq length <<<"$auto")" = 0 ] && echo "- tidak ada" || jq -r '.[]|"- #\(.number) \(.title)"' <<<"$auto"
  echo; echo "## Daftar periksa (diisi agen; skrip hanya memvonis fakta di atas)"; echo "$checklist"
  echo; echo "Merge ke \`$base\` oleh owner. Laporan ini dibuat otomatis oleh aicrew."
} > "$out"
echo "release-report: $verdict -> $out"
if [ "$open_pr" = 1 ] && [ "$dry" = 0 ] && [ "$verdict" = SIAP ]; then
  gh pr create --base "$base" --head "$integ" --title "Rilis: $integ -> $base" --body-file "$out"
fi
[ "$verdict" = SIAP ]
