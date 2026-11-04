#!/usr/bin/env bash
# aicrew release-report: laporan calon rilis (cabang integrasi -> main) dari FAKTA GitHub + suite tes di salinan segar. GitHub/gh saja.
#   release-report.sh [--integ CABANG] [--test-cmd "node --test"] [--out BERKAS] [--base main] [--open-pr] [--dry-run] [--version X.Y.Z]
# Cabang integrasi default dibaca dari docs/WORKFLOW.md ("Integration branch: <nama>"). Laporan ditulis ke --out (default .aicrew/release-report.md).
# PR integrasi -> base HANYA dibuka bila --buka-pr, vonis SIAP, dan tanpa --dry-run. Tidak pernah merge. Item daftar periksa yang butuh
# penilaian (keamanan, smoke test, runbook) dicetak sebagai kotak kosong untuk diisi agen; skrip hanya memvonis fakta.
# Exit: 0 SIAP, 1 BELUM SIAP, 64 argumen/cabang tidak diketahui.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; source "$here/lib/msg.sh"; L_INT="$(bash "$here/label.sh" integrated --json)"; L_AUTO="$(bash "$here/label.sh" auto --json)"
integ=""; testcmd=""; out=""; base=main; open_pr=0; dry=0; versi=""; wf=docs/WORKFLOW.md
while [ $# -gt 0 ]; do case "$1" in
  --integ) integ="$2"; shift 2 ;; --test-cmd) testcmd="$2"; shift 2 ;; --out) out="$2"; shift 2 ;; --base) base="$2"; shift 2 ;;
  --open-pr|--buka-pr) open_pr=1; shift ;; --dry-run) dry=1; shift ;; --version|--versi) versi="$2"; shift 2 ;; *) echo "$(msg relreport.unknown_arg "$1")" >&2; exit 64 ;; esac; done
[ -n "$integ" ] || integ="$({ bash "$here/lib/wf-normalize.sh" < "$wf"; } 2>/dev/null | grep -oE 'Integration branch: [A-Za-z0-9._/-]+' | head -1 | awk '{print $3}' | sed 's/[.]*$//')"
[ -n "$integ" ] || { echo "$(msg relreport.integ_unknown)" >&2; exit 64; }
g="$(git rev-parse --git-common-dir)" && d="$(cd "$g/.." && pwd)/.aicrew"; mkdir -p "$d"; [ -n "$out" ] || out="$d/release-report.md"

issues="$(gh issue list --state all --limit 200 --json number,title,state,labels)" || { echo "$(msg relreport.issues_unreadable)" >&2; exit 1; }
prs="$(gh pr list --state all --limit 200 --json number,title,state,baseRefName,comments,body,labels,closingIssuesReferences)" || { echo "$(msg relreport.prs_unreadable)" >&2; exit 1; }
merged="$(jq --arg b "$integ" '[.[]|select(.state=="MERGED" and .baseRefName==$b)]' <<<"$prs")"
has() { jq --argjson ls "$1" 'map(select((.labels|map(.name)) as $n|any($ls[]; . as $x|$n|index($x))))' <<<"$2"; }
blocking="$(jq --argjson ls "$L_INT" '[.[]|select(.state=="OPEN" and (((.labels|map(.name)) as $n|(any($ls[]; . as $x|$n|index($x)) or ($n|index("epic"))))|not))]' <<<"$issues")"
needs="$(jq '[.[]|select(.state=="OPEN" and ((.labels|map(.name)|index("epic"))|not))]' <<<"$issues" | jq 'map(select(.labels|map(.name)|index("needs-principal")))')"
held="$(jq '[.[]|select(.state=="OPEN" and (.labels|map(.name|ascii_downcase)|index("owner-hold")))]' <<<"$issues")"
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
    | select(.sec or .perf) ]')" || { echo "$(msg relreport.audit_failed)" >&2; exit 1; }
waivers="$(jq '[.[]|{n:.number, w:([.comments[]?.body // "" | split("\n")[] | select(test("^Pengecualian disetujui owner \\((perf|rahasia)\\): "))])}|select(.w|length>0)]' <<<"$merged")" || { echo "$(msg relreport.waivers_failed)" >&2; exit 1; }
missing="$(jq '[.[]|select((.sec and (.sec_ok|not)) or (.perf and ((.perf_ok or .waiver_perf)|not)))]' <<<"$audit")"

# suite di salinan segar dari cabang integrasi
suite="$(msg relreport.suite_not_run)"; suite_ok=0; sha="?"
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
  else suite="$(msg relreport.fresh_clone_failed "$ref")"; fi
  rm -rf "$wt"
fi

reasons=()
[ "$(jq length <<<"$merged")" = 0 ] && reasons+=("$(msg relreport.reason_no_merged "$integ")")
[ "$(jq length <<<"$blocking")" != 0 ] && reasons+=("$(msg relreport.reason_blocking "$(jq length <<<"$blocking")" "$(jq -r 'map("#\(.number)")|join(" ")' <<<"$blocking")")")
[ "$(jq length <<<"$needs")" != 0 ] && reasons+=("$(msg relreport.reason_needs_principal "$(jq -r 'map("#\(.number)")|join(" ")' <<<"$needs")")")
[ "$(jq length <<<"$held")" != 0 ] && reasons+=("$(msg relreport.reason_owner_hold "$(jq -r 'map("#\(.number)")|join(" ")' <<<"$held")")")
[ "$(jq length <<<"$noevid")" != 0 ] && reasons+=("$(msg relreport.reason_no_evidence "$(jq -r 'map("#\(.number)")|join(" ")' <<<"$noevid")")")
[ "$(jq length <<<"$missing")" != 0 ] && reasons+=("$(msg relreport.reason_missing_verdict "$(jq -r 'map("#\(.n)")|join(" ")' <<<"$missing")")")
[ "$suite_ok" = 1 ] || reasons+=("$(msg relreport.reason_suite)")
verdict="SIAP"; [ "${#reasons[@]}" != 0 ] && verdict="BELUM SIAP"

if [ -f "$wf" ] && grep -q '^## Daftar periksa rilis' "$wf"; then
  checklist="$(sed -n '/^## Daftar periksa rilis/,/^## /p' "$wf" | grep '^- ' | sed 's/^- \(\[.\] \)\?/- [ ] /')"
else
  checklist="$(msg relreport.default_checklist)"
fi

{
  echo "$(msg relreport.title "$integ" "$base")"
  echo; echo "$(msg relreport.fact_verdict "$verdict" "$sha" "$(date '+%F %T')")"
  [ "${#reasons[@]}" != 0 ] && { echo; echo "$(msg relreport.not_ready_reasons)"; printf -- '- %s\n' "${reasons[@]}"; }
  echo; echo "## Suite penuh (salinan segar $integ)"; echo "$suite"
  echo; echo "## PR ter-merge ke $integ"; jq -r '.[]|"- #\(.number) \(.title)"' <<<"$merged"
  if [ -n "$versi" ] && grep -Eq '^[- 0-9.]*Release notes: *CHANGELOG\.md' "$wf" 2>/dev/null; then
    echo; echo "## Catatan rilis (draf)"
    if draft="$(bash "$here/release-notes.sh" --version "$versi" 2>"$d/release-notes.err")"; then printf '%s\n' "$draft"; else echo "$(msg relreport.draft_failed "$(tail -n 1 "$d/release-notes.err" 2>/dev/null)")"; fi
    [ ! -s "$d/release-notes.err" ] || { echo; sed 's/^/> /' "$d/release-notes.err" | head -n 20; }
  fi
  echo; echo "## Issue"; jq -r '.[]|"- #\(.number) [\(.state)] \(.title)"' <<<"$issues"
  echo; echo "## Keputusan otomatis (tinjau sebelum merge)"
  [ "$(jq length <<<"$auto")" = 0 ] && echo "$(msg relreport.none_bullet)" || jq -r '.[]|"- #\(.number) \(.title)"' <<<"$auto"
  echo; echo "## Jejak audit (needs-security / needs-perf)"
  [ "$(jq length <<<"$audit")" = 0 ] && echo "$(msg relreport.no_labeled_prs)" || jq -r '.[]|"- #\(.n) \(.title) | security: \(if .sec then (if .sec_ok then "lulus" else "TIDAK ADA" end) else "-" end) | perf: \(if .perf then (if .perf_ok then "lulus" elif .waiver_perf then "WAIVER owner (perf)" else "TIDAK ADA" end) else "-" end) | \(if .tuning == "" then "Tuning: -" else .tuning end)"' <<<"$audit"
  echo; echo "## Pengecualian owner (waiver)"
  [ "$(jq length <<<"$waivers")" = 0 ] && echo "$(msg relreport.none_bullet)" || jq -r '.[]|.n as $n|.w[]|"- #\($n): \(.)"' <<<"$waivers"
  echo; echo "## Daftar periksa (diisi agen; skrip hanya memvonis fakta di atas)"; echo "$checklist"
  echo; echo "$(msg relreport.footer "$base")"
} > "$out"
echo "release-report: $verdict -> $out"
if [ "$open_pr" = 1 ] && [ "$dry" = 0 ] && [ "$verdict" = SIAP ]; then
  gh pr create --base "$base" --head "$integ" --title "$(msg relreport.pr_title "$integ" "$base")" --body-file "$out"
fi
[ "$verdict" = SIAP ]
