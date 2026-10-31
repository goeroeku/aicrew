#!/usr/bin/env bash
# aicrew workflow: cetak isi WORKFLOW.md yang paling baru. Pakai: workflow.sh
# WORKFLOW terbaru sering hanya ada di cabang integrasi (checkout aktif = main yang basi): bila cabang integrasi dikenal
# (env AICREW_INTEG_BRANCH atau baris "Cabang integrasi:" di berkas lokal) dan origin/<cabang> memuatnya, pakai itu; selain itu berkas lokal.
f=docs/WORKFLOW.md
br="${AICREW_INTEG_BRANCH:-$(sed -n 's/^[- ]*.*Cabang integrasi: *\([A-Za-z0-9._\/-]*\).*/\1/p' "$f" 2>/dev/null | head -1 | sed 's/[.,;:]*$//')}"
if [ -n "$br" ]; then
  git fetch -q origin "$br" 2>/dev/null || true
  git show "origin/$br:$f" 2>/dev/null && exit 0
fi
cat "$f" 2>/dev/null || true
