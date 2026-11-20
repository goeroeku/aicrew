#!/usr/bin/env bash
# aicrew local-merge: jalur merge lokal saat kuota GitHub (GraphQL dan REST) habis (#159 tahap 3). Hanya dipanggil merge-pr.sh setelah (a) probe langsung membuktikan kuota habis dan
# (b) gerbang berhenti karena panggilan gh terakhirnya gagal oleh batas kuota.
#   local-merge.sh <pr> <cabang-tujuan> <cabang-isu>      exit 0 = di-merge dan di-push; exit 1 = ditolak/menunggu (tidak ada yang berubah di origin)
# GAGAL TERTUTUP: syarat yang butuh bukti GitHub (L2, grant, persetujuan pemilik, vonis security/perf, CVE, CI, tes yang ada atau konfigurasi tes, WORKFLOW.md) membuat merge MENUNGGU.
# Hanya L0/L1: label PR dan issue dari cache baca berumur <= 600 dtk (tetap, tak dapat diubah env), PR terikat ke cabang isu dan sha kepala, tes dijalankan SENDIRI pada hasil merge
# (evidence.sh), lalu `git push origin <sha-merge>:<tujuan>` (hanya fast-forward). Bukti lokal bukan CI independen; CI GitHub pada `main` hasil push menjadi pemeriksa silang.
# Batas yang diterima: berkas cache/bukti dapat ditulis agen yang punya Bash (pagar kecelakaan dan prompt injection, bukan agen berniat jahat); lihat README.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
export GHX_PERSIST=1
source "$here/lib/msg.sh"; source "$here/ghx.sh"; source "$here/lib/ownerlocal.sh"
solo=0; dry=0; [ "${4:-}" != --dry ] || dry=1   # Quota mode: local (tanpa remote): cabang lokal, isu dari store, persetujuan pemilik lokal, ff-only ke cabang bawaan
needs=""; soft() { if [ "$solo" = 1 ]; then needs="${needs:+$needs; }$*"; else refuse "$*"; fi; }   # syarat yang dapat disetujui pemilik (mode mandiri); selain itu tolak
pr="${1:-}"; dst="${2:-}"; br="${3:-}"
refuse() { echo "GAGAL: $*"; exit 1; }
[[ "$pr" =~ ^[0-9]+$ ]] && [[ "$dst" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] || { echo "usage: local-merge.sh <pr> <dst-branch> <issue-branch>" >&2; exit 64; }
[[ "$br" =~ ^issue-([0-9]+)$ ]] || refuse "$(msg local.bad_branch "$br")"; n="${BASH_REMATCH[1]}"
# 1. konfigurasi dibaca dari cabang tujuan (git show), bukan dari PR atau env; hanya cabang bawaan (dibaca dari remote, bukan ref lokal yang dapat ditulis)
g="$(git rev-parse --git-common-dir)"; root="$(cd "$g/.." && pwd)"
ghx_local_committed "$dst" && solo=1   # dari WORKFLOW.md tercatat di cabang tujuan, bukan env
if [ "$solo" = 1 ]; then
  dref="refs/heads/$dst"; bref="refs/heads/$br"; dflt="$(git -C "$root" symbolic-ref -q --short HEAD 2>/dev/null)"   # cabang yang di-checkout di checkout utama
  [ -n "$dflt" ] || refuse "$(msg local.default_unknown)"
else
  dref="origin/$dst"; bref="origin/$br"
  git fetch -q origin "$dst" "$br" 2>/dev/null || refuse "$(msg local.fetch_failed)"
  dflt="$(git ls-remote --symref origin HEAD 2>/dev/null | sed -n 's#^ref: refs/heads/\(.*\)[[:space:]]HEAD$#\1#p' | head -1)"
  [ -n "$dflt" ] || refuse "$(msg local.default_unknown)"   # gagal tertutup: tanpa jawaban remote tidak ada tebakan (ref lokal dapat ditulis agen)
fi
[ "$dst" = "$dflt" ] || refuse "$(msg local.not_default "$dst" "$dflt")"
wf="$(git show "$dref:docs/WORKFLOW.md" 2>/dev/null)" || wf=""
qraw="$(sed -n 's/^[- ]*Quota mode: *//p' <<<"$wf" | head -1)"
qm="$(sed -nE 's/^([A-Za-z]+)([[:space:].,;(]|$).*/\1/p' <<<"$qraw" | tr 'A-Z' 'a-z')"   # kata penuh; 'local-never' atau placeholder tak terisi bukan nilai valid
if [ -n "$qraw" ]; then case "$qm" in auto|local) ;; *) refuse "$(msg local.mode_forbidden "${qm:-$qraw}")" ;; esac; fi   # github atau nilai tak dikenal: gagal tertutup
head="$(git rev-parse "$bref" 2>/dev/null)" || refuse "$(msg local.fetch_failed)"
# 2. PR dari cache segar: terikat ke cabang isu dan sha kepala, terbuka, bukan draft, tanpa label penahan (label PR belum tentu sama dengan label issue)
holdre='risk:L2|needs-principal|needs-security|needs-perf|owner-hold|blocked|epic'
hardre='owner-hold|blocked'   # pemilik/agen sengaja menahan: tidak dapat disetujui lewat persetujuan lama; label harus dicabut dulu
if [ "$solo" = 1 ]; then prrec="$(ghx_prs open 1000 x | jq -c --argjson n "$pr" '[.[]|select(.number==$n)]|.[0] // empty')"; [ -n "$prrec" ] || refuse "$(msg local.pr_unknown "$pr")"
else prrec="$(ghx_cached_pr "$pr" 600)" || refuse "$(msg local.pr_unknown "$pr")"; fi
jq -e --arg br "$br" --arg h "$head" --arg d "$dst" '(.state|ascii_upcase)=="OPEN" and ((.isDraft // false)==false) and ((.isCrossRepository // false)==false) and .headRefName==$br and .headRefOid==$h and .baseRefName==$d' <<<"$prrec" >/dev/null 2>&1 \
  || refuse "$(msg local.pr_mismatch "$pr" "$br")"
prlabels="$(jq -r '[.labels[]?|if type=="object" then .name else . end]|.[]' <<<"$prrec")"
# 3. isi diff (nama tanpa kutip git; nama yang tetap dikutip = karakter aneh = tolak): berkas yang butuh bukti GitHub = tunggu
names="$(git -c core.quotepath=false diff --name-status "$dref...$head")" || refuse "$(msg local.diff_failed)"
[ -n "$names" ] || refuse "$(msg local.empty_diff)"
paths="$(printf '%s\n' "$names" | awk -F'\t' '{for(i=2;i<=NF;i++)print $i}')"
grep -q '^"' <<<"$paths" && soft "$(msg local.odd_filename)"
grep -iqx 'docs/workflow.md' <<<"$paths" && soft "$(msg local.touches_workflow)"
dep="$(grep -E '(^|/)(package-lock\.json|package\.json|npm-shrinkwrap\.json|\.npmrc|yarn\.lock|pnpm-lock\.yaml|go\.mod|go\.sum|requirements[^/]*\.txt|Pipfile(\.lock)?|poetry\.lock|pyproject\.toml|uv\.lock|Cargo\.(toml|lock)|Gemfile(\.lock)?|composer\.(json|lock)|pom\.xml|build\.gradle(\.kts)?|settings\.gradle(\.kts)?|\.pnpmfile\.cjs|\.yarnrc\.ya?ml|pnpm-workspace\.ya?ml|bun\.lockb?|deno\.jsonc?)$' <<<"$paths" | head -3 | paste -sd' ' -)"
[ -z "$dep" ] || soft "$(msg local.dep_manifest "$dep")"
testre='(^|/)(tests?|__tests__|spec|testdata|__snapshots__|e2e)/|(^|/)test_[^/]*$|(^|/)tests\.py$|(_test|\.test|\.spec|_spec)\.[a-z0-9]+$|Test\.java$'
cfgre='(^|/)(Makefile|GNUmakefile|justfile|Rakefile|Taskfile\.ya?ml|CMakeLists\.txt|noxfile\.py|conftest\.py|pytest\.ini|tox\.ini|setup\.cfg|phpunit\.xml(\.dist)?|(jest|vitest|playwright|cypress)\.config\.[a-z]+|karma\.conf\.[a-z]+|\.mocharc\.[a-z]+|Dockerfile[^/]*|docker-compose[^/]*\.ya?ml|\.gitlab-ci\.ya?ml|\.travis\.ya?ml|Jenkinsfile|azure-pipelines\.ya?ml)$|^\.(github|circleci)/'
# berkas tes yang sudah ada TIDAK boleh berubah sama sekali (penambahan murni pun dapat menetralkan tes: `exit 0`); berkas BARU boleh. Konfigurasi tes/build/CI = tunggu.
bad="$(printf '%s\n' "$names" | while IFS=$'\t' read -r st f1 f2; do
  if [ "${st#A}" != "$st" ]; then continue; fi
  if grep -Eiq "$testre" <<<"$f1" || grep -Eiq "$testre" <<<"$f2"; then echo "$f1"; fi
done | head -3 | paste -sd' ' -)"
[ -z "$bad" ] || soft "$(msg local.tests_modified "$bad")"
cfg="$(grep -E "$cfgre" <<<"$paths" | head -3 | paste -sd' ' -)"
[ -z "$cfg" ] || soft "$(msg local.test_config "$cfg")"
git diff "$dref...$head" | bash "$here/baseline-scan.sh" --body /dev/null --perf-labeled 0 >/dev/null 2>&1 || refuse "$(msg local.baseline_block)"
# 4. issue dari cache segar: issue cabang DAN semua #N yang disebut di badan PR (seperti gerbang normal, cadangan paling ketat): masing-masing terbuka, di cache, tanpa penanda
# penahan; risk:L0/L1 pada gabungan label PR+issue; L2 di mana pun menahan
linked="$( { echo "$n"; jq -r '.body // ""' <<<"$prrec" | grep -Eo '#[0-9]+' | tr -d '#'; } | sort -un)"
labels="$prlabels"
for m in $linked; do
  if [ "$solo" = 1 ]; then
    rec="$(ls_view "$m" 2>/dev/null)" || refuse "$(msg local.cache_stale "$m")"
    jq -e '.state=="OPEN"' <<<"$rec" >/dev/null 2>&1 || refuse "$(msg local.cache_stale "$m")"
  else rec="$(ghx_cached_issue "$m" 600)" || refuse "$(msg local.cache_stale "$m")"; fi
  il="$(jq -r '[.labels[]?|if type=="object" then .name else . end]|.[]' <<<"$rec")"
  labels="$labels"$'\n'"$il"
  grep -ixqE "$hardre" <<<"$il" && refuse "$(msg local.label_blocked "$m" "$(grep -ixE "$hardre" <<<"$il" | sort -u | paste -sd, -)")"
  hold="$(grep -ixE "$holdre" <<<"$il" | sort -u | paste -sd, -)"
  [ -z "$hold" ] || soft "$(msg local.label_blocked "$m" "$hold")"
  jq -r '.body // ""' <<<"$rec" | grep -Eiq '^[[:space:]>]*([-*+]|[0-9]+[.)])[[:space:]]+\[ \].*owner[[:space:]_-]+only' && soft "$(msg local.owner_only "$m")"
done
grep -qixE 'risk:L[01]' <<<"$labels" || soft "$(msg local.risk_unknown "$n")"
grep -ixqE "$hardre" <<<"$labels" && refuse "$(msg local.label_blocked "$n" "$(grep -ixE "$hardre" <<<"$labels" | sort -u | paste -sd, -)")"
hold="$(grep -ixE "$holdre" <<<"$labels" | sort -u | paste -sd, -)"
[ -z "$hold" ] || soft "$(msg local.label_blocked "$n" "$hold")"
if [ "$dry" = 1 ]; then echo "needs: ${needs:--}"; exit 0; fi   # owner-local.sh approve: tampilkan alasan sebelum pemilik mengetik yes
# mode mandiri: syarat yang menunggu GitHub di jalur lain menunggu PERSETUJUAN PEMILIK LOKAL (owner-local.sh approve, terikat ke isu dan sha kepala)
if [ "$solo" = 1 ] && [ -n "$needs" ]; then
  ol_approved "$n" "$head" merge || refuse "$(msg local.needs_owner "$n" "$needs" "$n")"
fi
# 5. bukti: gerbang menjalankan sendiri tes pada hasil merge
ev="$(bash "$here/evidence.sh" run "$dst" "$head" $([ "$solo" = 1 ] && echo --local))"; erc=$?
case "$erc" in 0) ;; 1) refuse "$(msg local.tests_failed)" ;; *) refuse "$(msg local.evidence_unavailable)" ;; esac
msha="$(sed -n 's/^merge: //p' <<<"$ev" | head -1)"; [[ "$msha" =~ ^[0-9a-f]{40}$ ]] || refuse "$(msg local.evidence_unavailable)"
# 6. mode jaringan: push persis sha yang diuji (hanya fast-forward). Mode mandiri: ff-only di checkout utama (harus bersih); tidak ada remote.
if [ "$solo" = 1 ]; then
  [ -z "$(git -C "$root" status --porcelain --untracked-files=no 2>/dev/null)" ] || refuse "$(msg local.dirty_tree)"
  git -C "$root" merge --ff-only -q "$msha" >/dev/null 2>&1 || refuse "$(msg local.ff_failed "$dst")"
else
  git push -q origin "$msha:refs/heads/$dst" 2>/dev/null || refuse "$(msg local.push_rejected "$dst")"
fi
mkdir -p "$root/.aicrew/backend" 2>/dev/null
printf '%s PR #%s issue #%s head %s merge %s -> %s\n' "$(date '+%F %T')" "$pr" "$n" "$head" "$msha" "$dst" >> "$root/.aicrew/backend/local-merges.log"
if [ "$solo" = 1 ]; then ls_close "$n" "aicrew: merged locally $head -> $dst ($msha); tests ran on the merge result." >/dev/null 2>&1 || true
else   # jejak untuk pemilik: komentar PR diantre, dikirim sinkron setelah kuota pulih
  ghx_queue comment n="$pr" body="aicrew: merged while GitHub API quota was exhausted. Tests ran locally on the merge result $msha (head $head); the GitHub CI on $dst is the cross-check once the quota recovers." 2>/dev/null || true
fi
echo "ok: $(msg local.merged "$pr" "$head" "$msha" "$dst")"
exit 0
