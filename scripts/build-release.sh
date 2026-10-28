#!/usr/bin/env bash
# aicrew build-release: bangun arsip rilis dari commit HEAD tanpa infrastruktur repo (.github, .gitignore).
# Pakai: build-release.sh <versi> <folder-keluaran>   -> aicrew-<versi>.zip, aicrew-<versi>.tar.gz, SHA256SUMS
# Tidak memakai export-ignore di .gitattributes: direktori plugin Anthropic menolak repo yang memuat atribut itu.
set -eu
v="${1:?pakai: build-release.sh <versi> <folder-keluaran>}"; out="${2:?folder-keluaran}"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
git archive --format=tar --prefix="aicrew-$v/" HEAD | tar -x -C "$tmp"
[ -d "$tmp/aicrew-$v/.github" ] && rm -r "$tmp/aicrew-$v/.github"
rm -f "$tmp/aicrew-$v/.gitignore" "$tmp/aicrew-$v/.gitattributes"
(cd "$tmp" && zip -qr "$out/aicrew-$v.zip" "aicrew-$v" && tar -czf "$out/aicrew-$v.tar.gz" "aicrew-$v")
(cd "$out" && if command -v sha256sum >/dev/null 2>&1; then sha256sum "aicrew-$v.zip" "aicrew-$v.tar.gz"; else shasum -a 256 "aicrew-$v.zip" "aicrew-$v.tar.gz"; fi > SHA256SUMS)
echo "ok: $out/aicrew-$v.zip, .tar.gz, SHA256SUMS"
