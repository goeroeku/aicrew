#!/usr/bin/env bash
# aicrew wf-normalize: pemeta alias WORKFLOW.md. Menulis ulang kunci dan nilai Indonesia (alias usang) ke bentuk Inggris kanonik.
# Pakai: wf_normalize < docs/WORKFLOW.md   (setelah `source`), atau: bash scripts/lib/wf-normalize.sh < berkas
# Nilai hanya dipetakan pada token pertama setelah kunci; prosa tidak diubah. Input Inggris tak berubah (idempoten).
wf_normalize() {
  sed -E \
    -e 's/Merge PR ke cabang integrasi:/Merge PR to integration branch:/g' \
    -e 's/Cabang integrasi:/Integration branch:/g' \
    -e 's/Tutup issue setelah merge integrasi:/Close issues after integration merge:/g' \
    -e 's/Bersihkan setelah merge:/Clean up after merge:/g' \
    -e 's/Label keputusan otomatis:/Auto-decision label:/g' \
    -e 's/Label epic belum dipecah:/Unsplit epic label:/g' \
    -e 's/Label menunggu rilis:/Awaiting-release label:/g' \
    -e 's/Label tanpa induk:/No-parent label:/g' \
    -e 's/Label integrasi:/Integrated label:/g' \
    -e 's/Label discovery:/Discovery label:/g' \
    -e 's/Pemeriksaan CVE:/CVE check:/g' \
    -e 's/Paket privat:/Private packages:/g' \
    -e 's/Bahasa artefak( \([^)]*\))?:/Artifact language\1:/g' \
    -e 's/Berkas docs\/ dilacak git:/Track docs\/ in git:/g' \
    -e 's/Basis worktree:/Worktree base:/g' \
    -e 's/Board kanban:/Kanban board:/g' \
    -e 's/Kartu Done:/Done card:/g' \
    -e 's/Role aktif:/Active roles:/g' \
    -e 's/Kode ada:/Existing code:/g' \
    -e 's/Profil:/Profile:/g' \
    -e 's/(Integration branch: *)[Tt][Ii][Dd][Aa][Kk] [Aa][Dd][Aa]/\1none/' \
    -e 's/(Clean up after merge: *)[Yy][Aa]([^A-Za-z0-9-]|$)/\1yes\2/' \
    -e 's/(Clean up after merge: *)[Ll][Aa][Pp][Oo][Rr][Kk][Aa][Nn]([^A-Za-z0-9-]|$)/\1report\2/' \
    -e 's/(Clean up after merge: *)[Tt][Ii][Dd][Aa][Kk]([^A-Za-z0-9-]|$)/\1no\2/' \
    -e 's/(Close issues after integration merge: *)[Yy][Aa]([^A-Za-z0-9-]|$)/\1yes\2/' \
    -e 's/(Close issues after integration merge: *)[Tt][Ii][Dd][Aa][Kk]([^A-Za-z0-9-]|$)/\1no\2/' \
    -e 's/(CVE check: *)[Yy][Aa]([^A-Za-z0-9-]|$)/\1yes\2/' \
    -e 's/(CVE check: *)[Tt][Ii][Dd][Aa][Kk]([^A-Za-z0-9-]|$)/\1no\2/' \
    -e 's/(Existing code: *)[Yy][Aa]([^A-Za-z0-9-]|$)/\1yes\2/' \
    -e 's/(Existing code: *)[Tt][Ii][Dd][Aa][Kk]([^A-Za-z0-9-]|$)/\1no\2/' \
    -e 's/(Profile: *)[Rr][Ii][Nn][Gg][Aa][Nn]([^A-Za-z0-9-]|$)/\1light\2/' \
    -e 's/(Profile: *)[Ss][Tt][Aa][Nn][Dd][Aa][Rr]([^A-Za-z0-9-]|$)/\1standard\2/' \
    -e 's/(Profile: *)[Pp][Ee][Nn][Uu][Hh]([^A-Za-z0-9-]|$)/\1full\2/' \
    -e 's/(Done card: *)agen-setelah-merge/\1agent-after-merge/' \
    -e 's/(Merge PR to integration branch: *)agen-setelah-(QA|qa)/\1agent-after-qa/'
}
# dijalankan langsung = filter stdin
[ "${BASH_SOURCE[0]}" != "$0" ] || wf_normalize
