#!/usr/bin/env bash
# aicrew check-version: tag rilis (vX.Y.Z) harus sama dengan "version" di .claude-plugin/plugin.json. Pakai: check-version.sh <tag>
# Dipakai workflow rilis agar rilis GitHub dan marketplace tidak melaporkan versi yang berbeda. Exit 1 bila beda atau bukan semver.
set -u
source "$(dirname "$0")/lib/msg.sh"
tag="${1:?$(msg checkver.usage)}"; want="${tag#v}"
have="$(jq -r .version "$(dirname "$0")/../.claude-plugin/plugin.json")"
printf '%s' "$want" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "GAGAL: $(msg checkver.bad_tag "$tag")" >&2; exit 1; }
[ "$want" = "$have" ] || { echo "GAGAL: $(msg checkver.mismatch "$tag" "$have")" >&2; exit 1; }
# catatan rilis (#30): bila WORKFLOW.md memakai CHANGELOG.md, bagian versi ini seharusnya sudah ada (peringatan saja, tidak menggagalkan rilis)
opsi="$(bash "$(dirname "$0")/workflow.sh" 2>/dev/null | sed -En 's/^[- ]*Release notes: *(CHANGELOG\.md).*$/\1/p' | head -1)"
if [ -n "$opsi" ] && ! grep -q "^## \[$want\]" CHANGELOG.md 2>/dev/null; then echo "::warning::$(msg checkver.changelog_missing "$want" "$want")"; fi
echo "ok: $tag = plugin.json $have"
