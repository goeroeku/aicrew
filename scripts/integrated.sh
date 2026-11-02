#!/usr/bin/env bash
# aicrew terintegrasi: apakah PR yang sudah merged benar-benar masuk cabang integrasi? Pakai: integrated.sh <pr>
# Dipakai sebelum label di-integrasi, penutupan issue, dan kartu Done: status "merged" saja tidak cukup (PR bertumpuk bisa merged ke cabang induk).
# Lolos bila merged_at terisi dan: base.ref = integrasi, atau merge_commit_sha / head.sha PR adalah leluhur origin/<integrasi>.
# Tanpa cabang integrasi di WORKFLOW.md (yang terbaca): lolos. GitHub REST + git saja.
# Opsional <issue>: bila terintegrasi, label integrated dipasang, in-progress/in-review dilepas, lalu diperiksa ulang (gagal keras: exit 1).
# Kode keluar: 0 terintegrasi (atau tanpa integrasi), 1 belum (alasan di stdout), 2 tak bisa diperiksa (alasan di stderr; fail-closed).
set -u
here="$(dirname "$0")"; source "$here/ghx.sh"
pr="${1:?pr}"; issue="${2:-}"
cant() { echo "terintegrasi: $*" >&2; exit 2; }
okx() {   # lolos; dengan <issue>: tukar label dan verifikasi
  [ -n "$issue" ] || exit 0
  local il l got; il="$(bash "$here/label.sh" integrated)"
  gh api -X POST "repos/$repo/issues/$issue/labels" -f "labels[]=$il" >/dev/null || { echo "integrated: label $il tak dapat dipasang pada #$issue" >&2; exit 1; }
  for l in in-progress in-review; do gh api -X DELETE "repos/$repo/issues/$issue/labels/$l" >/dev/null 2>&1 || true; done
  got="$(gh api "repos/$repo/issues/$issue" | jq -r '[.labels[].name]|join(" ")')" || { echo "integrated: label #$issue tak terbaca" >&2; exit 1; }
  case " $got " in *" $il "*) ;; *) echo "integrated: #$issue missing integrated label $il (label: $got)" >&2; exit 1 ;; esac
  case " $got " in *" in-progress "*|*" in-review "*) echo "integrated: #$issue still has in-progress/in-review (label: $got)" >&2; exit 1 ;; esac
  exit 0
}
repo="$(ghx_repo)" || cant "repo tak dapat ditentukan"
pj="$(gh api "repos/$repo/pulls/$pr")" || cant "PR #$pr tak terbaca (REST)"
read -r merged msha hsha base < <(jq -r '[(.merged_at // "-"), (.merge_commit_sha // "-"), (.head.sha // "-"), (.base.ref // "-")] | @tsv' <<<"$pj") || cant "PR #$pr tak dapat diurai"
[ "$merged" != "-" ] || { echo "PR #$pr belum merged"; exit 1; }
wf="$(bash "$here/workflow.sh" 2>/dev/null)"
integ="${AICREW_INTEG_BRANCH:-$(sed -n 's/^[- ]*.*Integration branch: *\([A-Za-z0-9._\/-]*\).*/\1/p' <<<"$wf" | head -1 | sed 's/[.,;:]*$//')}"
case "$integ" in tidak|none|nihil|-) integ="" ;; esac   # templat WORKFLOW: "Integration branch: none"
if [ -z "$integ" ]; then
  # tanpa cabang integrasi yang diketahui (WORKFLOW.md tak terbaca, tanpa barisnya, atau "tidak ada"): hanya PR ke cabang bawaan yang pasti aman
  def="$(gh api "repos/$repo" | jq -r '.default_branch // empty')" || cant "cabang bawaan tak terbaca (REST)"
  [ -n "$def" ] && [ "$base" = "$def" ] && { echo "ke cabang bawaan $def"; okx; }
  cant "cabang integrasi tak diketahui (docs/WORKFLOW.md tak terbaca, tanpa baris 'Integration branch:', atau 'none'), PR ter-merge ke $base bukan cabang bawaan"
fi
[ "$base" != "$integ" ] || { echo "ke cabang integrasi $integ"; okx; }
git fetch -q origin "$integ" 2>/dev/null || cant "origin/$integ tak dapat diambil"
for sha in "$msha" "$hsha"; do
  [ "$sha" != "-" ] || continue
  git merge-base --is-ancestor "$sha" "origin/$integ" 2>/dev/null && { echo "SHA $sha ada di $integ"; okx; }
done
echo "ter-merge ke $base, belum ke $integ"; exit 1
