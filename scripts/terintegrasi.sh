#!/usr/bin/env bash
# aicrew terintegrasi: apakah PR yang sudah merged benar-benar masuk cabang integrasi? Pakai: terintegrasi.sh <pr>
# Dipakai sebelum label di-integrasi, penutupan issue, dan kartu Done: status "merged" saja tidak cukup (PR bertumpuk bisa merged ke cabang induk).
# Lolos bila merged_at terisi dan: base.ref = integrasi, atau merge_commit_sha / head.sha PR adalah leluhur origin/<integrasi>.
# Tanpa cabang integrasi di WORKFLOW.md (yang terbaca): lolos. GitHub REST + git saja.
# Kode keluar: 0 terintegrasi (atau tanpa integrasi), 1 belum (alasan di stdout), 2 tak bisa diperiksa (alasan di stderr; fail-closed).
set -u
here="$(dirname "$0")"; source "$here/ghx.sh"
pr="${1:?pr}"
cant() { echo "terintegrasi: $*" >&2; exit 2; }
repo="$(ghx_repo)" || cant "repo tak dapat ditentukan"
pj="$(gh api "repos/$repo/pulls/$pr")" || cant "PR #$pr tak terbaca (REST)"
read -r merged msha hsha base < <(jq -r '[(.merged_at // "-"), (.merge_commit_sha // "-"), (.head.sha // "-"), (.base.ref // "-")] | @tsv' <<<"$pj") || cant "PR #$pr tak dapat diurai"
[ "$merged" != "-" ] || { echo "PR #$pr belum merged"; exit 1; }
wf="$(bash "$here/workflow.sh" 2>/dev/null)"
integ="${AICREW_INTEG_BRANCH:-$(sed -n 's/^[- ]*.*Cabang integrasi: *\([A-Za-z0-9._\/-]*\).*/\1/p' <<<"$wf" | head -1 | sed 's/[.,;:]*$//')}"
if [ -z "$integ" ]; then
  if [ -n "$wf" ]; then echo "tanpa cabang integrasi; tidak ada yang diperiksa"; exit 0; fi
  # WORKFLOW.md tak terbaca: hanya PR ke cabang bawaan yang pasti aman; selain itu tak bisa dinilai
  def="$(gh api "repos/$repo" | jq -r '.default_branch // empty')" || cant "cabang bawaan tak terbaca (REST)"
  [ -n "$def" ] && [ "$base" = "$def" ] && { echo "ke cabang bawaan $def"; exit 0; }
  cant "docs/WORKFLOW.md tak terbaca; cabang integrasi tak diketahui (PR ter-merge ke $base)"
fi
[ "$base" != "$integ" ] || { echo "ke cabang integrasi $integ"; exit 0; }
git fetch -q origin "$integ" 2>/dev/null || cant "origin/$integ tak dapat diambil"
for sha in "$msha" "$hsha"; do
  [ "$sha" != "-" ] || continue
  git merge-base --is-ancestor "$sha" "origin/$integ" 2>/dev/null && { echo "SHA $sha ada di $integ"; exit 0; }
done
echo "ter-merge ke $base, belum ke $integ"; exit 1
