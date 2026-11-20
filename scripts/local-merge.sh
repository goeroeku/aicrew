#!/usr/bin/env bash
# aicrew local-merge: jalur merge lokal saat kuota GitHub (GraphQL dan REST) habis (#159 tahap 3). Hanya dipanggil merge-pr.sh setelah probe langsung membuktikan kuota habis.
#   local-merge.sh <pr> <cabang-tujuan> <cabang-isu>      exit 0 = di-merge dan di-push; exit 1 = ditolak/menunggu (tidak ada yang berubah di origin)
# GAGAL TERTUTUP: syarat yang butuh bukti GitHub (L2, grant, persetujuan pemilik, vonis security/perf, CVE, CI, perubahan tes yang ada, perubahan WORKFLOW.md) membuat merge MENUNGGU.
# Hanya pekerjaan L0/L1 yang lolos: label dari cache baca berumur <= 600 dtk (tetap, tak dapat diubah env), tes dijalankan SENDIRI pada hasil merge (evidence.sh), lalu
# `git push origin <sha-merge>:<tujuan>` (hanya fast-forward). Bukti lokal bukan CI independen; CI GitHub pada `main` hasil push menjadi pemeriksa silang setelah kuota pulih.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
export GHX_PERSIST=1
source "$here/lib/msg.sh"; source "$here/ghx.sh"
pr="${1:-}"; dst="${2:-}"; br="${3:-}"
refuse() { echo "GAGAL: $*"; exit 1; }
[[ "$pr" =~ ^[0-9]+$ ]] && [[ "$dst" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "usage: local-merge.sh <pr> <dst-branch> <issue-branch>" >&2; exit 64; }
[[ "$br" =~ ^issue-([0-9]+)$ ]] || refuse "$(msg local.bad_branch "$br")"; n="${BASH_REMATCH[1]}"
# 1. hanya cabang bawaan; konfigurasi dibaca dari cabang tujuan (git show), bukan dari PR atau env
git fetch -q origin "$dst" "$br" 2>/dev/null || refuse "$(msg local.fetch_failed)"
dflt="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"; [ -n "$dflt" ] || dflt=main
[ "$dst" = "$dflt" ] || refuse "$(msg local.not_default "$dst" "$dflt")"
wf="$(git show "origin/$dst:docs/WORKFLOW.md" 2>/dev/null)" || wf=""
case "$(sed -n 's/^[- ]*Quota mode: *\([A-Za-z]*\).*/\1/p' <<<"$wf" | head -1 | tr 'A-Z' 'a-z')" in github) refuse "$(msg local.mode_github)" ;; esac
head="$(git rev-parse "origin/$br" 2>/dev/null)" || refuse "$(msg local.fetch_failed)"
# 2. isi diff: berkas yang butuh bukti GitHub = tunggu
names="$(git diff --name-status "origin/$dst...$head")" || refuse "$(msg local.diff_failed)"
[ -n "$names" ] || refuse "$(msg local.empty_diff)"
nums="$(git diff --numstat "origin/$dst...$head")"
printf '%s\n' "$names" | awk -F'\t' '{for(i=2;i<=NF;i++)print tolower($i)}' | grep -qx 'docs/workflow.md' && refuse "$(msg local.touches_workflow)"
dep="$(printf '%s\n' "$names" | awk -F'\t' '{for(i=2;i<=NF;i++)print $i}' | grep -E '(^|/)(package-lock\.json|package\.json|yarn\.lock|pnpm-lock\.yaml|go\.mod|go\.sum|requirements[^/]*\.txt|Pipfile\.lock|poetry\.lock|Cargo\.lock)$' | head -3 | paste -sd' ' -)"
[ -z "$dep" ] || refuse "$(msg local.dep_manifest "$dep")"
testre='(^|/)(tests?|__tests__|spec|testdata|__snapshots__|e2e)/|(^|/)test_[^/]*$|(^|/)tests\.py$|(_test|\.test|\.spec|_spec)\.[a-z0-9]+$|Test\.java$'
# berkas tes yang sudah ada: hanya penambahan murni yang lolos (selain itu butuh persetujuan pemilik di GitHub)
tests_changed() {   # stdin: git diff --name-status; $1 = git diff --numstat. Mencetak berkas tes lama yang berubah selain penambahan murni
  local st f1 f2 del
  while IFS=$'\t' read -r st f1 f2; do
    [ "${st#A}" = "$st" ] || continue
    if ! { grep -Eiq "$testre" <<<"$f1" || grep -Eiq "$testre" <<<"$f2"; }; then continue; fi
    if [ "$st" = M ]; then del="$(printf '%s\n' "$1" | awk -F'\t' -v f="$f1" '$3==f{print $2}')"; [ "$del" = 0 ] && continue; fi
    echo "$f1"
  done
}
bad="$(printf '%s\n' "$names" | tests_changed "$nums" | head -3 | paste -sd' ' -)"
[ -z "$bad" ] || refuse "$(msg local.tests_modified "$bad")"
git diff "origin/$dst...$head" | bash "$here/baseline-scan.sh" --body /dev/null --perf-labeled 0 >/dev/null 2>&1 || refuse "$(msg local.baseline_block)"
# 3. label dari cache segar (<= 600 dtk): risk:L0/L1 dan tanpa penanda yang butuh pemilik/GitHub
rec="$(ghx_cached_issue "$n" 600)" || refuse "$(msg local.cache_stale "$n")"
labels="$(jq -r '[.labels[]?|if type=="object" then .name else . end]|.[]' <<<"$rec")"
grep -qixE 'risk:L[01]' <<<"$labels" || refuse "$(msg local.risk_unknown "$n")"
hold="$(grep -ixE 'risk:L2|needs-principal|needs-security|needs-perf|owner-hold|blocked|epic' <<<"$labels" | paste -sd, -)"
[ -z "$hold" ] || refuse "$(msg local.label_blocked "$n" "$hold")"
jq -r '.body // ""' <<<"$rec" | grep -Eiq '^[[:space:]>]*([-*+]|[0-9]+[.)])[[:space:]]+\[ \].*owner[[:space:]_-]+only' && refuse "$(msg local.owner_only "$n")"
# 4. bukti: gerbang menjalankan sendiri tes pada hasil merge
ev="$(bash "$here/evidence.sh" run "$dst" "$head")"; erc=$?
case "$erc" in 0) ;; 1) refuse "$(msg local.tests_failed)" ;; *) refuse "$(msg local.evidence_unavailable)" ;; esac
msha="$(sed -n 's/^merge: //p' <<<"$ev" | head -1)"; [[ "$msha" =~ ^[0-9a-f]{40}$ ]] || refuse "$(msg local.evidence_unavailable)"
# 5. push persis sha yang diuji (hanya fast-forward; cabang dilindungi atau berubah = ditolak, tidak ada yang berubah)
git push -q origin "$msha:refs/heads/$dst" 2>/dev/null || refuse "$(msg local.push_rejected "$dst")"
g="$(git rev-parse --git-common-dir)"; root="$(cd "$g/.." && pwd)"; mkdir -p "$root/.aicrew/backend" 2>/dev/null
printf '%s PR #%s issue #%s head %s merge %s -> %s\n' "$(date '+%F %T')" "$pr" "$n" "$head" "$msha" "$dst" >> "$root/.aicrew/backend/local-merges.log"
# jejak untuk pemilik: komentar PR diantre, dikirim sinkron setelah kuota pulih
ghx_queue comment n="$pr" body="aicrew: merged while GitHub API quota was exhausted. Tests ran locally on the merge result $msha (head $head); the GitHub CI on $dst is the cross-check once the quota recovers." 2>/dev/null || true
echo "ok: $(msg local.merged "$pr" "$head" "$msha" "$dst")"
exit 0
