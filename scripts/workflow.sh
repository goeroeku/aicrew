#!/usr/bin/env bash
# aicrew workflow: cetak isi WORKFLOW.md yang paling baru. Pakai: workflow.sh
# WORKFLOW terbaru sering hanya ada di cabang integrasi (checkout aktif = main yang basi): bila cabang integrasi dikenal
# (env AICREW_INTEG_BRANCH atau baris "Integration branch:" di berkas lokal) dan origin/<cabang> memuatnya, pakai itu; selain itu berkas lokal.
f=docs/WORKFLOW.md
# shellcheck source=lib/wf-normalize.sh
source "$(dirname "$0")/lib/wf-normalize.sh"   # alias Indonesia -> kunci/nilai Inggris kanonik
br="${AICREW_INTEG_BRANCH:-$(wf_normalize < "$f" 2>/dev/null | sed -n 's/^[- ]*.*Integration branch: *\([A-Za-z0-9._\/-]*\).*/\1/p' | head -1 | sed 's/[.,;:]*$//')}"
if [ -n "$br" ]; then
  git fetch -q origin "$br" 2>/dev/null || true
  if t="$(git show "origin/$br:$f" 2>/dev/null)"; then printf '%s\n' "$t" | wf_normalize; exit 0; fi
fi
wf_normalize < "$f" 2>/dev/null || true
