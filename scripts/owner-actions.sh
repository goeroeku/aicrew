#!/usr/bin/env bash
# aicrew owner-actions: ringkasan tindakan yang hanya bisa dilakukan owner, satu baris per item (#57).
#   owner-actions.sh [DIR=.aicrew]  -> menulis DIR/owner-actions.md dan mencetak "<path> (<N> item)". Selalu exit 0; gh gagal = tidak menulis apa pun.
# Item deterministik (tanpa model): issue berlabel needs-principal, dan PR terbuka bukan-draft dari cabang issue-<n> (menunggu merge owner).
# Catatan agen: komentar terbaru berawalan "owner-action: <tindakan> | <perintah> | <alasan>" pada issue/PR itu ikut sebagai catatan (ditulis orchestrator, lihat skill orchestrate).
set -u
here="$(cd "$(dirname "$0")" && pwd)"; source "$here/ghx.sh"
d="${1:-.aicrew}"; mkdir -p "$d"; f="$d/owner-actions.md"
issues="$(gh issue list --state open --limit 200 --json number,title,labels 2>/dev/null)" || exit 0
prs="$(gh pr list --state open --limit 100 --json number,title,headRefName,headRefOid,isDraft,labels 2>/dev/null)" || exit 0
repo="$(ghx_repo 2>/dev/null)" || repo=""
# catatan agen terbaru untuk #n ("" bila tidak ada); ponytail: hanya 100 komentar pertama
note_of() { [ -n "$repo" ] || return 0; gh api "repos/$repo/issues/$1/comments?per_page=100" 2>/dev/null | jq -r '[.[]?|(.body // "")|select(startswith("owner-action:"))]|last // empty|sub("^owner-action: *";"")' 2>/dev/null; }
lines="$({
  jq -r '.[]?|select((.labels // [])|map(.name)|index("needs-principal"))|"\(.number)\t- #\(.number) \(.title) — answer the question in the issue, then remove the label — `gh issue edit \(.number) --remove-label needs-principal` — an owner decision; an agent must not decide it"' <<<"$issues" 2>/dev/null
  jq -r '.[]?|select(.isDraft==false and (.headRefName|test("^issue-[0-9]+$")))|"\(.number)\t- PR #\(.number) (issue #\(.headRefName|sub("^issue-";""))) \(.title) — review and merge — `gh pr merge \(.number) --merge --match-head-commit \(.headRefOid)` — \(if ((.labels // [])|map(.name)|index("risk:L2")) then "risk:L2 is never merged automatically" elif ((.labels // [])|map(.name)|index("needs-security")) then "security review is pending" else "the merge mode needs the owner" end)"' <<<"$prs" 2>/dev/null
})"
n=0; out="# Owner actions ($(date '+%F %T'))"$'\n'
while IFS=$'\t' read -r num text; do
  [ -n "$num" ] || continue
  n=$((n+1)); out="$out"$'\n'"$text"
  nt="$(note_of "$num")"; [ -z "$nt" ] || out="$out"$'\n'"  - agent note: $nt"
done <<<"$lines"
[ "$n" -gt 0 ] || out="$out"$'\n'"No owner actions found."
printf '%s\n' "$out" > "$f.tmp" && mv "$f.tmp" "$f"
printf '%s (%s item)\n' "$f" "$n"
