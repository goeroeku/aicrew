#!/usr/bin/env bash
# aicrew release-report: laporan calon rilis (cabang integrasi -> main) dari FAKTA GitHub + suite tes di salinan segar. GitHub/gh saja.
#   release-report.sh [--integ CABANG] [--test-cmd "node --test"] [--out BERKAS] [--base main] [--open-pr] [--dry-run] [--version X.Y.Z]
# Cabang integrasi default dibaca dari docs/WORKFLOW.md ("Integration branch: <nama>"). Laporan ditulis ke --out (default .aicrew/release-report.md).
# PR integrasi -> base HANYA dibuka bila --buka-pr, vonis SIAP, dan tanpa --dry-run. Tidak pernah merge. Item daftar periksa yang butuh
# penilaian (keamanan, smoke test, runbook) dicetak sebagai kotak kosong untuk diisi agen; skrip hanya memvonis fakta.
# Exit: 0 SIAP, 1 BELUM SIAP, 64 argumen/cabang tidak diketahui.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; L_INT="$(bash "$here/label.sh" integrated --json)"; L_AUTO="$(bash "$here/label.sh" auto --json)"
integ=""; testcmd=""; out=""; base=main; open_pr=0; dry=0; versi=""; wf=docs/WORKFLOW.md
while [ $# -gt 0 ]; do case "$1" in
  --integ) integ="$2"; shift 2 ;; --test-cmd) testcmd="$2"; shift 2 ;; --out) out="$2"; shift 2 ;; --base) base="$2"; shift 2 ;;
  --open-pr|--buka-pr) open_pr=1; shift ;; --dry-run) dry=1; shift ;; --version|--versi) versi="$2"; shift 2 ;; *) echo "argumen tak dikenal: $1" >&2; exit 64 ;; esac; done
[ -n "$integ" ] || integ="$({ bash "$here/lib/wf-normalize.sh" < "$wf"; } 2>/dev/null | grep -oE 'Integration branch: [A-Za-z0-9._/-]+' | head -1 | awk '{print $3}' | sed 's/[.]*$//')"
[ -n "$integ" ] || { echo "release-report: cabang integrasi tidak diketahui (pakai --integ)" >&2; exit 64; }
g="$(git rev-parse --git-common-dir)" && d="$(cd "$g/.." && pwd)/.aicrew"; mkdir -p "$d"; [ -n "$out" ] || out="$d/release-report.md"

issues="$(gh issue list --state all --limit 200 --json number,title,state,labels)" || { echo "release-report: gagal membaca issue (BELUM SIAP)" >&2; exit 1; }
prs="$(gh pr list --state all --limit 200 --json number,title,state,baseRefName,comments,body,labels,closingIssuesReferences)" || { echo "release-report: gagal membaca PR (BELUM SIAP)" >&2; exit 1; }
merged="$(jq --arg b "$integ" '[.[]|select(.state=="MERGED" and .baseRefName==$b)]' <<<"$prs")"
has() { jq --argjson ls "$1" 'map(select((.labels|map(.name)) as $n|any($ls[]; . as $x|$n|index($x))))' <<<"$2"; }
blocking="$(jq --argjson ls "$L_INT" '[.[]|select(.state=="OPEN" and (((.labels|map(.name)) as $n|(any($ls[]; . as $x|$n|index($x)) or ($n|index("epic"))))|not))]' <<<"$issues")"
needs="$(jq '[.[]|select(.state=="OPEN" and ((.labels|map(.name)|index("epic"))|not))]' <<<"$issues" | jq 'map(select(.labels|map(.name)|index("needs-principal")))')"
auto="$(has "$L_AUTO" "$issues")"
noevid="$(jq '[.[]|select((.comments|map(.body)|map(contains("Bukti selesai"))|any)|not)]' <<<"$merged")"
# jejak audit: PR ter-merge berlabel needs-security/needs-perf (label PR + issue yang ditutup badan PR) dan bukti laporannya
audit="$(jq -n --argjson prs "$merged" --argjson iss "$issues" '
  def has_line(re): any(.comments[]?; (.body // "") | test("(^|\n)" + re));
  def first_line(re): ([.comments[]?.body // "" | split("\n")[] | select(test(re))] | first) // "";
  [ $prs[] | . as $p
    | ([ ($p.body // "") | split("\n")[] | select(test("(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]"; "i")) | scan("#([0-9]+)") | .[0] | tonumber ] + [ $p.closingIssuesReferences[]?.number ]) as $ns
    | (($p.labels // [] | map(.name)) + [ $iss[] | select(.number as $n | $ns | index($n)) | .labels[]?.name ]) as $L
    | { n: $p.number, title: ($p.title // ""), sec: (($L | map(ascii_downcase) | index("needs-security")) != null), perf: (($L | map(ascii_downcase) | index("needs-perf")) != null),
        sec_ok: ($p | has_line("Laporan security: lulus")), perf_ok: ($p | has_line("Laporan perf: lulus")),
        waiver_perf: ($p | has_line("Pengecualian disetujui owner \\(perf\\): .*[^ ].* \\(Commit: ")), tuning: ($p | first_line("^Tuning:")) }
    | select(.sec or .perf) ]')" || { echo "release-report: gagal menyusun jejak audit (BELUM SIAP)" >&2; exit 1; }
waivers="$(jq '[.[]|{n:.number, w:([.comments[]?.body // "" | split("\n")[] | select(test("^Pengecualian disetujui owner \\((perf|rahasia)\\): "))])}|select(.w|length>0)]' <<<"$merged")" || { echo "release-report: gagal menyusun waiver (BELUM SIAP)" >&2; exit 1; }
missing="$(jq '[.[]|select((.sec and (.sec_ok|not)) or (.perf and ((.perf_ok or .waiver_perf)|not)))]' <<<"$audit")"

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
[ "$(jq length <<<"$missing")" != 0 ] && reasons+=("PR berlabel needs-security/needs-perf tanpa laporan lulus (perf: atau waiver owner): $(jq -r 'map("#\(.n)")|join(" ")' <<<"$missing")")
[ "$suite_ok" = 1 ] || reasons+=("suite penuh tidak lulus/tidak dijalankan")
verdict="SIAP"; [ "${#reasons[@]}" != 0 ] && verdict="BELUM SIAP"

if [ -f "$wf" ] && grep -q '^## Daftar periksa rilis' "$wf"; then
  checklist="$(sed -n '/^## Daftar periksa rilis/,/^## /p' "$wf" | grep '^- ' | sed 's/^- \(\[.\] \)\?/- [ ] /')"
else
  checklist="- [ ] Build bersih di salinan segar
- [ ] Aplikasi dijalankan lokal; smoke test lulus
- [ ] aicrew-security: auth, input, rahasia, dependensi; hardening dan log audit untuk needs-security
- [ ] aicrew-perf: anggaran I/O, config default, uji beban di server nyata (angka, bukan perkiraan)
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
  if [ -n "$versi" ] && grep -Eq '^[- 0-9.]*Release notes: *CHANGELOG\.md' "$wf" 2>/dev/null; then
    echo; echo "## Catatan rilis (draf)"
    if draft="$(bash "$here/release-notes.sh" --version "$versi" 2>"$d/release-notes.err")"; then printf '%s\n' "$draft"; else echo "(draf tidak dapat disusun: $(tail -n 1 "$d/release-notes.err" 2>/dev/null))"; fi
    [ ! -s "$d/release-notes.err" ] || { echo; sed 's/^/> /' "$d/release-notes.err" | head -n 20; }
  fi
  echo; echo "## Issue"; jq -r '.[]|"- #\(.number) [\(.state)] \(.title)"' <<<"$issues"
  echo; echo "## Keputusan otomatis (tinjau sebelum merge)"
  [ "$(jq length <<<"$auto")" = 0 ] && echo "- tidak ada" || jq -r '.[]|"- #\(.number) \(.title)"' <<<"$auto"
  echo; echo "## Jejak audit (needs-security / needs-perf)"
  [ "$(jq length <<<"$audit")" = 0 ] && echo "- tidak ada PR berlabel" || jq -r '.[]|"- #\(.n) \(.title) | security: \(if .sec then (if .sec_ok then "lulus" else "TIDAK ADA" end) else "-" end) | perf: \(if .perf then (if .perf_ok then "lulus" elif .waiver_perf then "WAIVER owner (perf)" else "TIDAK ADA" end) else "-" end) | \(if .tuning == "" then "Tuning: -" else .tuning end)"' <<<"$audit"
  echo; echo "## Pengecualian owner (waiver)"
  [ "$(jq length <<<"$waivers")" = 0 ] && echo "- tidak ada" || jq -r '.[]|.n as $n|.w[]|"- #\($n): \(.)"' <<<"$waivers"
  echo; echo "## Daftar periksa (diisi agen; skrip hanya memvonis fakta di atas)"; echo "$checklist"
  echo; echo "Merge ke \`$base\` oleh owner. Laporan ini dibuat otomatis oleh aicrew."
} > "$out"
echo "release-report: $verdict -> $out"
if [ "$open_pr" = 1 ] && [ "$dry" = 0 ] && [ "$verdict" = SIAP ]; then
  gh pr create --base "$base" --head "$integ" --title "Rilis: $integ -> $base" --body-file "$out"
fi
[ "$verdict" = SIAP ]
