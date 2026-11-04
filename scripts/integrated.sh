#!/usr/bin/env bash
# aicrew terintegrasi: apakah PR yang sudah merged benar-benar masuk cabang integrasi? Pakai: integrated.sh <pr>
# Dipakai sebelum label di-integrasi, penutupan issue, dan kartu Done: status "merged" saja tidak cukup (PR bertumpuk bisa merged ke cabang induk).
# Lolos bila merged_at terisi dan: base.ref = integrasi, atau merge_commit_sha / head.sha PR adalah leluhur origin/<integrasi>.
# Tanpa cabang integrasi di WORKFLOW.md (yang terbaca): lolos. GitHub REST + git saja.
# Opsional <issue>: bila terintegrasi, label integrated dipasang, in-progress/in-review dilepas, lalu diperiksa ulang (gagal keras: exit 1).
# Kode keluar: 0 terintegrasi (atau tanpa integrasi), 1 belum (alasan di stdout), 2 tak bisa diperiksa (alasan di stderr; fail-closed).
set -u
here="$(dirname "$0")"; source "$here/ghx.sh"; source "$here/lib/msg.sh"
pr="${1:?pr}"; issue="${2:-}"
cant() { echo "terintegrasi: $*" >&2; exit 2; }
okx() {   # lolos; dengan <issue>: tukar label dan verifikasi
  [ -n "$issue" ] || exit 0
  local il l got; il="$(bash "$here/label.sh" integrated)"
  gh api -X POST "repos/$repo/issues/$issue/labels" -f "labels[]=$il" >/dev/null || { echo "$(msg integrated.label_apply_failed "$il" "$issue")" >&2; exit 1; }
  for l in in-progress in-review; do gh api -X DELETE "repos/$repo/issues/$issue/labels/$l" >/dev/null 2>&1 || true; done
  got="$(gh api "repos/$repo/issues/$issue" | jq -r '[.labels[].name]|join(" ")')" || { echo "$(msg integrated.labels_unreadable "$issue")" >&2; exit 1; }
  case " $got " in *" $il "*) ;; *) echo "$(msg integrated.missing_label "$issue" "$il" "$got")" >&2; exit 1 ;; esac
  case " $got " in *" in-progress "*|*" in-review "*) echo "$(msg integrated.stale_label "$issue" "$got")" >&2; exit 1 ;; esac
  exit 0
}
repo="$(ghx_repo)" || cant "$(msg integrated.repo_unknown)"
pj="$(gh api "repos/$repo/pulls/$pr")" || cant "$(msg integrated.pr_unreadable "$pr")"
read -r merged msha hsha base < <(jq -r '[(.merged_at // "-"), (.merge_commit_sha // "-"), (.head.sha // "-"), (.base.ref // "-")] | @tsv' <<<"$pj") || cant "$(msg integrated.pr_unparseable "$pr")"
[ "$merged" != "-" ] || { echo "$(msg integrated.not_merged "$pr")"; exit 1; }
wf="$(bash "$here/workflow.sh" 2>/dev/null)"
integ="${AICREW_INTEG_BRANCH:-$(sed -n 's/^[- ]*.*Integration branch: *\([A-Za-z0-9._\/-]*\).*/\1/p' <<<"$wf" | head -1 | sed 's/[.,;:]*$//')}"
case "$integ" in tidak|none|nihil|-) integ="" ;; esac   # templat WORKFLOW: "Integration branch: none"
if [ -z "$integ" ]; then
  # tanpa cabang integrasi yang diketahui (WORKFLOW.md tak terbaca, tanpa barisnya, atau "tidak ada"): hanya PR ke cabang bawaan yang pasti aman
  def="$(gh api "repos/$repo" | jq -r '.default_branch // empty')" || cant "$(msg integrated.default_branch_unreadable)"
  [ -n "$def" ] && [ "$base" = "$def" ] && { echo "$(msg integrated.to_default_branch "$def")"; okx; }
  cant "$(msg integrated.integ_unknown "$base")"
fi
[ "$base" != "$integ" ] || { echo "$(msg integrated.to_integ_branch "$integ")"; okx; }
git fetch -q origin "$integ" 2>/dev/null || cant "$(msg integrated.fetch_failed "$integ")"
for sha in "$msha" "$hsha"; do
  [ "$sha" != "-" ] || continue
  git merge-base --is-ancestor "$sha" "origin/$integ" 2>/dev/null && { echo "$(msg integrated.sha_in_integ "$sha" "$integ")"; okx; }
done
echo "$(msg integrated.not_in_integ "$base" "$integ")"; exit 1
