#!/usr/bin/env bash
# aicrew preflight: cek lingkungan. Pakai: preflight.sh [github|gitlab]
# Exit 1 bila backend yang diminta tidak siap (tak terpasang / belum login / bukan repo git).
backend="${1:-}"; rc=0
source "$(dirname "$0")/ghx.sh"
have() { command -v "$1" >/dev/null 2>&1; }
say() { printf '%-6s %s\n' "$1" "$2"; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 && say ok "repo git" || { say GAGAL "bukan repo git"; rc=1; }
git remote -v 2>/dev/null | grep -q . && say ok "remote git ada" || say info "belum ada remote git"
have codex && say ok "codex terpasang (senior-coder dapat didelegasikan)" || say info "codex tidak ada: senior-coder pakai sonnet"
have jq && say ok jq || say info "jq tidak ada: notifikasi memakai teks generik"
for f in .github/workflows/*.y*ml; do [ -f "$f" ] || continue
  grep -qE '^[[:space:]]*push:' "$f" && grep -qE 'branches:.*(main|master)|^[[:space:]]*-[[:space:]]*(main|master)[[:space:]]*$' "$f" \
    && say AWAS "$f jalan saat push ke main/master: merge ke main memicunya (deploy?)"
done
# izin subagen (#58): subagen unattended ditolak diam-diam bila aturan Bash tak ada; baca .permissions.allow efektif, sebut aturan yang hilang
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
set -- "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json" "$top/.claude/settings.json" "$top/.claude/settings.local.json"
ex=(); for f in "$@"; do [ -f "$f" ] && ex+=("$f"); done
if ! have jq; then say info "izin subagen: jq tidak ada, aturan Bash tidak diperiksa"
elif [ "${#ex[@]}" -gt 0 ] && jq -e '.permissions.defaultMode == "bypassPermissions"' "${ex[@]}" 2>/dev/null | grep -q true; then say info "izin subagen: mode bypassPermissions aktif, aturan Bash tidak diperiksa"
else
  allow="$( [ "${#ex[@]}" -gt 0 ] && jq -r '.permissions.allow[]? | strings' "${ex[@]}" 2>/dev/null)"
  need="git worktree|git commit|git push"; [ "$backend" = github ] && need="$need|gh pr|gh issue"
  [ -f "$top/Makefile" ] && need="$need|make"; [ -f "$top/go.mod" ] && need="$need|go test"
  miss=""; while IFS= read -r r; do
    case "$r" in git*) b="git" ;; gh*) b="gh" ;; make) b="make" ;; go*) b="go" ;; esac
    grep -qxF -e "Bash($r:*)" -e "Bash($b:*)" -e "Bash" <<<"$allow" || miss="$miss Bash($r:*)"
  done <<<"$(tr "|" "\n" <<<"$need")"
  if [ -z "$miss" ]; then say ok "izin subagen: aturan Bash yang dibutuhkan ada"
  else say AWAS "izin subagen: aturan allow hilang:$miss. Subagen tanpa aturan ini ditolak (QA 'no tests executed', PR menggantung). Pasang dari template: ! bash $(dirname "$0")/install-permissions.sh (template belum memuat make/go test: tambahkan manual)"; fi
fi
case "$PWD$(git worktree list 2>/dev/null)" in *orca/workspaces/*) say AWAS "workspace Orca: Orca meluncurkan agen dengan --dangerously-skip-permissions secara bawaan, sehingga aturan deny di settings TIDAK ditegakkan; matikan flag itu di pengaturan agen Orca" ;; esac

case "$backend" in
  github)
    if ! have gh; then say GAGAL "gh tidak terpasang"; rc=1
    elif gh auth status >/dev/null 2>&1; then say ok "gh login"
    else say GAGAL "gh belum login (jalankan: gh auth login)"; rc=1; fi
    if grep -qsE 'Bash\(gh pr merge' ~/.claude/settings.json ~/.claude/settings.local.json .claude/settings.json .claude/settings.local.json; then
      say ok "aturan izin 'gh pr merge' ada"
    else say info "tanpa aturan izin 'gh pr merge': agen akan ditolak (mode agent-after-qa butuh ini). Owner yang merge, atau ketik di prompt sesi: ! mkdir -p .claude && echo '{\"permissions\":{\"allow\":[\"Bash(gh pr merge:*)\"]}}' > .claude/settings.local.json  (jangan menimpa bila berkas sudah ada)"; fi
    # setelan GitHub: hapus cabang otomatis saat merge (plugin tidak mengubahnya; milik owner repo) dan jumlah cabang ter-merge (bukti offline saja)
    if rp="$(ghx_repo 2>/dev/null)" && [ -n "$rp" ]; then
      case "$(gh api "repos/$rp" 2>/dev/null | jq -r '.delete_branch_on_merge | if . == null then empty else tostring end' 2>/dev/null)" in
        true) say ok "GitHub: cabang dihapus otomatis saat merge" ;;
        false) say AWAS "GitHub: delete_branch_on_merge=false, cabang ter-merge menumpuk dan PR bertumpuk bisa berbasis cabang induk yang sudah ter-merge (isinya tak masuk integrasi). Perbaiki: gh api -X PATCH repos/$rp -F delete_branch_on_merge=true" ;;
      esac
    fi
    if git remote -v 2>/dev/null | grep -q .; then
      n="$(bash "$(dirname "$0")/cleanup.sh" --count 2>/dev/null)"
      [ "${n:-0}" = 0 ] || say info "$n cabang ter-merge (bukti offline) belum dihapus; daftar dan pengecualian PR terbuka: bash scripts/cleanup.sh"
    fi
    gh auth status 2>&1 | grep -qE "Token scopes:.*'project'" && say ok "gh scope project (kanban)" \
      || say info "gh tanpa scope 'project' (hanya untuk sinkron kanban): ! gh auth refresh -h github.com -s project -c" ;;
  gitlab)
    if ! have glab; then say GAGAL "glab tidak terpasang"; rc=1
    elif glab auth status >/dev/null 2>&1; then say ok "glab login"
    else say GAGAL "glab belum login (jalankan: glab auth login)"; rc=1; fi ;;
  "") have gh && say info "gh terpasang"; have glab && say info "glab terpasang" ;;
  *) say GAGAL "backend tidak dikenal: $backend"; rc=1 ;;
esac
[ -n "${AICREW_TG_TOKEN:-}" ] && [ -n "${AICREW_TG_CHAT:-}" ] && say ok "notifikasi Telegram aktif" || say info "notifikasi Telegram nonaktif (AICREW_TG_TOKEN/AICREW_TG_CHAT belum diset)"
exit $rc
