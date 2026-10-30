#!/usr/bin/env bash
# aicrew install-permissions: gabungkan templates/autopilot-permissions.json ke settings project (union, tidak menimpa).
# Placeholder __PLUGIN__ (akar plugin), __REPO_PARENT__/__REPO_NAME__ (repo project; worktree ../<repo>-wt-N) diisi saat dipasang.
# Pakai (dijalankan OWNER, mis. di prompt sesi dengan !): install-permissions.sh [berkas=.claude/settings.local.json]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"; f="${1:-.claude/settings.local.json}"
mkdir -p "$(dirname "$f")"; [ -f "$f" ] || echo '{}' > "$f"
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# path cache berversi (.../plugins/cache/<mp>/<plugin>/X.Y.Z) -> segmen versi jadi wildcard, supaya izin tetap berlaku setelah auto-update
plug="$here"; case "$plug" in */plugins/cache/*/*/[0-9]*.[0-9]*.[0-9]*) plug="$(dirname "$plug")/*" ;; esac
tpl="$(sed "s|__PLUGIN__|$plug|g; s|__REPO_PARENT__|$(dirname "$top")|g; s|__REPO_NAME__|$(basename "$top")|g" "$here/templates/autopilot-permissions.json")"
jq -s '.[0] as $a | .[1] as $b | $a * {permissions:(($a.permissions//{}) * {
  allow:((($a.permissions.allow//[])+$b.permissions.allow)|unique),
  deny:((($a.permissions.deny//[])+$b.permissions.deny)|unique)})}' "$f" <(printf '%s' "$tpl") > "$f.tmp" && mv "$f.tmp" "$f"
jq -r '"terpasang di '"$f"': allow \(.permissions.allow|length), deny \(.permissions.deny|length)"' "$f"
