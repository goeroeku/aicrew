#!/usr/bin/env bash
# aicrew check-version: tag rilis (vX.Y.Z) harus sama dengan "version" di .claude-plugin/plugin.json. Pakai: check-version.sh <tag>
# Dipakai workflow rilis agar rilis GitHub dan marketplace tidak melaporkan versi yang berbeda. Exit 1 bila beda atau bukan semver.
set -u
tag="${1:?pakai: check-version.sh vX.Y.Z}"; want="${tag#v}"
have="$(jq -r .version "$(dirname "$0")/../.claude-plugin/plugin.json")"
printf '%s' "$want" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "GAGAL: '$tag' bukan vX.Y.Z" >&2; exit 1; }
[ "$want" = "$have" ] || { echo "GAGAL: tag $tag != versi plugin.json ($have); naikkan versi dulu" >&2; exit 1; }
# catatan rilis (#30): bila WORKFLOW.md memakai CHANGELOG.md, bagian versi ini seharusnya sudah ada (peringatan saja, tidak menggagalkan rilis)
opsi="$(bash "$(dirname "$0")/workflow.sh" 2>/dev/null | sed -En 's/^[- ]*Release notes: *(CHANGELOG\.md).*$/\1/p' | head -1)"
if [ -n "$opsi" ] && ! grep -q "^## \[$want\]" CHANGELOG.md 2>/dev/null; then echo "::warning::CHANGELOG.md tidak memuat bagian [$want]; jalankan scripts/release-notes.sh --version $want --write sebelum merge rilis"; fi
echo "ok: $tag = plugin.json $have"
