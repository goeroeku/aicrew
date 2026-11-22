#!/usr/bin/env bash
# aicrew preflight: cek lingkungan. Pakai: preflight.sh [github|gitlab]
# Exit 1 bila backend yang diminta tidak siap (tak terpasang / belum login / bukan repo git).
backend="${1:-}"; rc=0
source "$(dirname "$0")/ghx.sh"; source "$(dirname "$0")/lib/msg.sh"
ghx_local && [ -z "$backend" -o "$backend" = github ] && backend=local   # Quota mode: local: tanpa pemeriksaan gh/remote
have() { command -v "$1" >/dev/null 2>&1; }
say() { printf '%-6s %s\n' "$1" "$2"; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 && say ok "$(msg pf.repo_ok)" || { say GAGAL "$(msg pf.not_repo)"; rc=1; }
git remote -v 2>/dev/null | grep -q . && say ok "$(msg pf.remote_ok)" || say info "$(msg pf.no_remote)"
have codex && say ok "$(msg pf.codex_ok)" || say info "$(msg pf.codex_missing)"
have jq && say ok jq || say info "$(msg pf.jq_missing)"
for f in .github/workflows/*.y*ml; do [ -f "$f" ] || continue
  grep -qE '^[[:space:]]*push:' "$f" && grep -qE 'branches:.*(main|master)|^[[:space:]]*-[[:space:]]*(main|master)[[:space:]]*$' "$f" \
    && say AWAS "$(msg pf.push_workflow "$f")"
done
# mode merge (#66): env AICREW_MERGE_MODE, lalu docs/WORKFLOW.md, bawaan owner; agent-after-qa = alur integrasi oleh agen (butuh 'gh pr merge', git merge, git rebase)
# shellcheck source=lib/merge-mode.sh
source "$(dirname "$0")/lib/merge-mode.sh"; mmode="$(merge_mode "$(git rev-parse --show-toplevel 2>/dev/null || pwd)/docs/WORKFLOW.md")"
# izin subagen (#58): subagen unattended ditolak diam-diam bila aturan Bash tak ada; baca .permissions.allow efektif, sebut aturan yang hilang
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
aut_added=""
if have jq && [ -f "$top/.aicrew/autonomy.json" ]; then
  aut_added="$(jq -r '.files[]?.added_allow[]? | strings' "$top/.aicrew/autonomy.json" 2>/dev/null)"
  aut_ep="$(jq -r '.until_epoch // empty' "$top/.aicrew/autonomy.json" 2>/dev/null)"
  aut_un="$(jq -r '.until // empty' "$top/.aicrew/autonomy.json" 2>/dev/null)"
  if [[ "$aut_ep" =~ ^[0-9]+$ ]] && [ "$(date +%s)" -ge "$aut_ep" ]; then
    say AWAS "$(msg pf.autonomy_expired "$aut_un")"
  fi
fi
set -- "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" "$top/.claude/settings.json" "$top/.claude/settings.local.json"
ex=(); for f in "$@"; do [ -f "$f" ] && ex+=("$f"); done
if ! have jq; then say info "$(msg pf.perm_no_jq)"
elif [ "${#ex[@]}" -gt 0 ] && jq -e '.permissions.defaultMode == "bypassPermissions"' "${ex[@]}" 2>/dev/null | grep -q true; then say info "$(msg pf.perm_bypass)"
else
  allow="$( [ "${#ex[@]}" -gt 0 ] && jq -r '.permissions.allow[]? | strings' "${ex[@]}" 2>/dev/null)"
  [ -n "$aut_added" ] && allow="$(grep -vxF -f <(printf '%s\n' "$aut_added") <<<"$allow" || true)"
  need="git worktree|git commit|git push"; [ "$backend" = github ] && need="$need|gh pr|gh issue"
  [ -f "$top/Makefile" ] && need="$need|make"; [ -f "$top/go.mod" ] && need="$need|go test"
  [ "$mmode" = agent-after-qa ] && need="$need|git merge|git rebase"
  miss=""; while IFS= read -r r; do
    case "$r" in git*) b="git" ;; gh*) b="gh" ;; make) b="make" ;; go*) b="go" ;; esac
    grep -qxF -e "Bash($r:*)" -e "Bash($b:*)" -e "Bash" <<<"$allow" || miss="$miss Bash($r:*)"
  done <<<"$(tr "|" "\n" <<<"$need")"
  if [ -z "$miss" ]; then say ok "$(msg pf.perm_ok)"
  else say AWAS "$(msg pf.perm_missing "$miss" "$(dirname "$0")")"; fi
fi
case "$PWD$(git worktree list 2>/dev/null)" in *orca/workspaces/*) say AWAS "$(msg pf.orca_skip)" ;; esac

case "$backend" in
  github)
    if ! have gh; then say GAGAL "$(msg pf.gh_missing)"; rc=1
    elif gh auth status >/dev/null 2>&1; then say ok "gh login"
    else say GAGAL "$(msg pf.gh_logged_out)"; rc=1; fi
    # mode merge (#66): sama seperti install-permissions.sh: env AICREW_MERGE_MODE, lalu docs/WORKFLOW.md, bawaan owner; agent-after-qa menuntut aturan 'gh pr merge'
    has_merge_perm=0
    if [ -n "$aut_added" ]; then
      grep -qE 'Bash\(gh pr merge' <<<"$allow" && has_merge_perm=1
    elif grep -qsE 'Bash\(gh pr merge' "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" "$top/.claude/settings.json" "$top/.claude/settings.local.json"; then
      has_merge_perm=1
    fi
    if [ "$has_merge_perm" = 1 ]; then
      say ok "$(msg pf.merge_perm_ok)"
    elif [ "$mmode" = agent-after-qa ]; then say AWAS "$(msg pf.merge_perm_missing "$(dirname "$0")")"
    else say info "$(msg pf.merge_perm_owner)"; fi
    # setelan GitHub: hapus cabang otomatis saat merge (plugin tidak mengubahnya; milik owner repo) dan jumlah cabang ter-merge (bukti offline saja)
    if rp="$(ghx_repo 2>/dev/null)" && [ -n "$rp" ]; then
      case "$(gh api "repos/$rp" 2>/dev/null | jq -r '.delete_branch_on_merge | if . == null then empty else tostring end' 2>/dev/null)" in
        true) say ok "$(msg pf.delete_on_merge_ok)" ;;
        false) say AWAS "$(msg pf.delete_on_merge_off "$rp")" ;;
      esac
    fi
    # labels (#111): label.sh owns the fixed names; warn when open issues carry a default/legacy name other than the configured one (agent-created duplicate)
    if [ -n "${rp:-}" ]; then
      used="$(gh api "repos/$rp/issues?state=open&per_page=100" 2>/dev/null | jq -r '.[].labels[]?.name' 2>/dev/null || true)"
      for t in integrated:integrated:di-integrasi auto:auto-decision:keputusan-otomatis notsplit:unsplit:belum-dipecah noparent:no-parent:tanpa-induk waiting:awaiting-release:menunggu-rilis; do
        IFS=: read -r k d1 d2 <<<"$t"; eff="$(bash "$(dirname "$0")/label.sh" "$k")"; known="$(bash "$(dirname "$0")/label.sh" "$k" --all)"
        for d in $d1 $d2; do
          grep -qxF "$d" <<<"$known" || ! grep -qxF "$d" <<<"$used" || say AWAS "label '$d' is on open issues but the configured $k label is '$eff': agent-created duplicate? Use: bash scripts/label.sh $k"
        done
      done
    fi
    if git remote -v 2>/dev/null | grep -q .; then
      n="$(bash "$(dirname "$0")/cleanup.sh" --count 2>/dev/null)"
      [ "${n:-0}" = 0 ] || say info "$(msg pf.stale_branches "$n")"
    fi
    gh auth status 2>&1 | grep -qE "Token scopes:.*'project'" && say ok "$(msg pf.gh_scope_ok)" \
      || say info "$(msg pf.gh_scope_missing)" ;;
  local)
    say ok "$(msg pf.local_mode)"
    have openssl && say ok "$(msg pf.openssl_ok)" || { say GAGAL "$(msg pf.openssl_missing)"; rc=1; }
    root="$(cd "$(git rev-parse --git-common-dir)/.." 2>/dev/null && pwd)"
    git show "HEAD:docs/WORKFLOW.md" 2>/dev/null | grep -qE '^[- ]*Test command: *[^ {]' && say ok "$(msg pf.testcmd_ok)" || say AWAS "$(msg pf.testcmd_missing)"
    git show "HEAD:docs/WORKFLOW.md" 2>/dev/null | grep -qE '^[- ]*Quota mode: *local' && say ok "$(msg pf.mode_committed)" || say AWAS "$(msg pf.mode_uncommitted)" ;;
  gitlab)
    if ! have glab; then say GAGAL "$(msg pf.glab_missing)"; rc=1
    elif glab auth status >/dev/null 2>&1; then say ok "glab login"
    else say GAGAL "$(msg pf.glab_logged_out)"; rc=1; fi ;;
  "") have gh && say info "$(msg pf.gh_present)"; have glab && say info "$(msg pf.glab_present)" ;;
  *) say GAGAL "$(msg pf.unknown_backend "$backend")"; rc=1 ;;
esac
[ -n "${AICREW_TG_TOKEN:-}" ] && [ -n "${AICREW_TG_CHAT:-}" ] && say ok "$(msg pf.tg_on)" || say info "$(msg pf.tg_off)"
exit $rc
