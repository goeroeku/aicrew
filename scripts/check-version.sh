#!/usr/bin/env bash
# aicrew check-version: tag rilis (vX.Y.Z) harus sama dengan "version" di .claude-plugin/plugin.json. Pakai: check-version.sh <tag>
# Dipakai workflow rilis agar rilis GitHub dan marketplace tidak melaporkan versi yang berbeda. Exit 1 bila beda atau bukan semver.
set -u
tag="${1:?pakai: check-version.sh vX.Y.Z}"; want="${tag#v}"
have="$(jq -r .version "$(dirname "$0")/../.claude-plugin/plugin.json")"
printf '%s' "$want" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "GAGAL: '$tag' bukan vX.Y.Z" >&2; exit 1; }
[ "$want" = "$have" ] || { echo "GAGAL: tag $tag != versi plugin.json ($have); naikkan versi dulu" >&2; exit 1; }
echo "ok: $tag = plugin.json $have"
