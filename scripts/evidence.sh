#!/usr/bin/env bash
# aicrew evidence: uji HASIL MERGE di worktree bersih (#159 tahap 3). Dipakai gerbang lokal saat kuota GitHub habis; bukti bukan klaim agen: skrip ini sendiri yang menjalankan tes.
#   evidence.sh run <cabang-tujuan> <sha-kepala>
# Langkah: fetch origin/<tujuan>; worktree detached bersih dari origin/<tujuan>; `git merge --no-ff <sha-kepala>`; jalankan `Test command:` dari docs/WORKFLOW.md di
# origin/<tujuan> (aturan datang dari cabang tujuan, bukan dari PR); tulis jejak audit .aicrew/evidence/<sha-kepala>.json.
# Stdout: baris `merge: <sha-hasil-merge>` bila tes lulus. Exit 0 = lulus, 1 = tes gagal, 2 = tak dapat disiapkan (fetch, konflik merge, tanpa Test command, sha tak ada).
set -u
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib/msg.sh"
[ "${1:-}" = run ] && dst="${2:-}" && head="${3:-}" || { echo "usage: evidence.sh run <dst-branch> <head-sha> [--local]" >&2; exit 64; }
localref=0; [ "${4:-}" != --local ] || localref=1   # mode mandiri (Quota mode: local): tanpa remote, dasar = cabang lokal <dst>
[[ "$dst" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]] && [[ "$head" =~ ^[0-9a-f]{7,40}$ ]] || { echo "$(msg evidence.bad_args)" >&2; exit 64; }
g="$(git rev-parse --git-common-dir 2>/dev/null)" && root="$(cd "$g/.." && pwd)" || { echo "$(msg evidence.no_repo)" >&2; exit 2; }
if [ "$localref" = 1 ]; then bref="refs/heads/$dst"; else bref="origin/$dst"; git fetch -q origin "$dst" 2>/dev/null || { echo "$(msg evidence.fetch_failed "$dst")" >&2; exit 2; }; fi
git cat-file -e "$head^{commit}" 2>/dev/null || { echo "$(msg evidence.no_head "$head")" >&2; exit 2; }
wf="$(git show "$bref:docs/WORKFLOW.md" 2>/dev/null)" || wf=""
cmd="$(sed -n 's/^[- ]*Test command: *//p' <<<"$wf" | head -1 | sed 's/^`//; s/`[[:space:]]*$//; s/[[:space:]]*$//')"
[ -n "$cmd" ] || { echo "$(msg evidence.no_test_command "$dst")" >&2; exit 2; }
base="$(git rev-parse "$bref")"
wt="$(mktemp -d "${TMPDIR:-/tmp}/aicrew-evid.XXXXXX")"; log="$(mktemp "${TMPDIR:-/tmp}/aicrew-evid-log.XXXXXX")"
cleanup() { git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1; rm -rf "$wt" "$log"; }
trap cleanup EXIT
git worktree add -q --detach "$wt" "$bref" 2>/dev/null || { echo "$(msg evidence.worktree_failed)" >&2; exit 2; }
if ! git -C "$wt" -c user.name=aicrew -c user.email=aicrew@localhost merge -q --no-ff --no-edit "$head" >/dev/null 2>&1; then
  echo "$(msg evidence.merge_conflict "$head" "$dst")" >&2; exit 2
fi
msha="$(git -C "$wt" rev-parse HEAD)"
started="$(date +%s)"; rc=0
# tes menjalankan kode PR yang belum ditinjau: token dan agen SSH tidak diteruskan (credential di ~/.config/gh tetap terjangkau; ini pagar kecelakaan, bukan sandbox)
( cd "$wt" && env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u SSH_AUTH_SOCK -u GIT_ASKPASS AICREW_EVIDENCE=1 bash -c "$cmd" ) >"$log" 2>&1 || rc=$?
finished="$(date +%s)"
ed="$root/.aicrew/evidence"; mkdir -p "$ed" 2>/dev/null
jq -nc --arg head "$head" --arg merge "$msha" --arg base "$base" --arg dst "$dst" --arg cmd "$cmd" --argjson rc "$rc" --arg out "$(shasum < "$log" | cut -d' ' -f1)" \
  --argjson s "$started" --argjson f "$finished" --arg host "$(hostname 2>/dev/null)" \
  '{head:$head,merge:$merge,base:$base,dst:$dst,cmd:$cmd,rc:$rc,output_sha1:$out,started:$s,finished:$f,host:$host}' > "$ed/$head.json" 2>/dev/null || true
if [ "$rc" != 0 ]; then tail -20 "$log" >&2; echo "$(msg evidence.tests_failed "$rc")" >&2; exit 1; fi
echo "merge: $msha"
exit 0
