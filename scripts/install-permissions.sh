#!/usr/bin/env bash
# aicrew install-permissions: gabungkan templates/autopilot-permissions.json ke settings project (union, tidak menimpa).
# Placeholder __PLUGIN__ (akar plugin), __REPO_PARENT__/__REPO_NAME__ (repo project; worktree ../<repo>-wt-N) diisi saat dipasang.
# Basis worktree dan mode merge dibaca dari docs/WORKFLOW.md (lihat templates/WORKFLOW.md); modes.<mode>.allow di template hanya ditambahkan untuk mode itu.
# Pakai (dijalankan OWNER, mis. di prompt sesi dengan !): install-permissions.sh [berkas=.claude/settings.local.json]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"; f="${1:-.claude/settings.local.json}"
mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{}' > "$f"
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# path cache berversi (.../plugins/cache/<mp>/<plugin>/X.Y.Z) -> segmen versi jadi wildcard, supaya izin tetap berlaku setelah auto-update
plug="$here"; case "$plug" in */plugins/cache/*/*/[0-9]*.[0-9]*.[0-9]*) plug="$(dirname "$plug")/*" ;; esac
wf="$top/docs/WORKFLOW.md"
# basis worktree absolut (mis. di dalam workspace Orca): baris "Worktree base: /path" di WORKFLOW.md, atau AICREW_WORKTREE_BASE; selain itu induk repo
base="${AICREW_WORKTREE_BASE:-$({ bash "$here/scripts/lib/wf-normalize.sh" < "$wf"; } 2>/dev/null | sed -n 's/^[- ]*Worktree base: *\(\/[^ ]*\).*/\1/p' | head -1 || true)}"; base="${base%/}"; [ -n "$base" ] || base="$(dirname "$top")"
# mode merge ke cabang integrasi: izin gh pr merge hanya untuk agent-after-qa
# shellcheck source=lib/merge-mode.sh
# helper hilang (salinan skrip tunggal): peringatkan, mode hanya dari env (dinormalkan), selain itu owner
if [ -f "$here/scripts/lib/merge-mode.sh" ]; then source "$here/scripts/lib/merge-mode.sh"; mode="$(merge_mode "$wf")"
else echo "install-permissions: scripts/lib/merge-mode.sh tidak ada (merge-mode tidak dibaca dari WORKFLOW.md); mode dari AICREW_MERGE_MODE saja" >&2
  case "$(printf '%s' "${AICREW_MERGE_MODE:-}" | tr '[:upper:]' '[:lower:]')" in agent-after-qa|agen-setelah-qa) mode=agent-after-qa ;; *) mode=owner ;; esac   # alias-usang
fi
tpl="$(sed "s|__PLUGIN__|$plug|g; s|__REPO_PARENT__|$base|g; s|__REPO_NAME__|$(basename "$top")|g" "$here/templates/autopilot-permissions.json")"
jq -s --arg m "$mode" '.[0] as $a | .[1] as $b | $a * {permissions:(($a.permissions//{}) * {
  allow:((($a.permissions.allow//[])+$b.permissions.allow+($b.modes[$m].allow//[]))|unique),
  deny:((($a.permissions.deny//[])+$b.permissions.deny)|unique)})}' "$f" <(printf '%s' "$tpl") > "$f.tmp" && mv "$f.tmp" "$f"
jq -r '"terpasang di '"$f"': allow \(.permissions.allow|length), deny \(.permissions.deny|length)"' "$f"
