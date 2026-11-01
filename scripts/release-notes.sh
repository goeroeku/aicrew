#!/usr/bin/env bash
# aicrew release-notes: bagian CHANGELOG.md per versi, disusun dari baris bertanda di badan PR yang ter-merge (#30). REST + git saja, deterministik (bukan model).
#   release-notes.sh --versi X.Y.Z [--sejak REF] [--tanggal YYYY-MM-DD]
# Opt-in: hanya bila docs/WORKFLOW.md memuat "Catatan rilis: CHANGELOG.md" (lain/hilang/placeholder = tidak ada: tidak mencetak dan tidak menyentuh berkas).
# Baris bertanda di badan PR (satu baris per entri; blok kode dan komentar HTML diabaikan):
#   Catatan rilis: <Added|Changed|Fixed|Security> - <teks>     Catatan rilis: -   (PR internal, tanpa entri)     Perubahan perilaku: <teks>
# Jendela: PR ter-merge ke cabang bawaan atau cabang integrasi yang merge_commit_sha-nya BUKAN leluhur tag sebelumnya (tag vX.Y.Z tertinggi di bawah --versi,
# atau --sejak REF) dan, bila tag v<versi> sudah ada, leluhur tag itu (jalan ulang setelah rilis memberi hasil sama). Gagal baca/REST/tanpa tag sebelumnya = exit 2, tanpa menulis apa pun.
# Kode keluar: 0, 1 (--ekstrak: bagian versi tak ada), 2 tak bisa disusun, 64 argumen.
set -u
here="$(cd "$(dirname "$0")" && pwd)"; source "$here/ghx.sh"
versi=""; sejak=""; tanggal=""
while [ $# -gt 0 ]; do case "$1" in
  --versi) versi="${2:-}"; shift 2 ;; --sejak) sejak="${2:-}"; shift 2 ;; --tanggal) tanggal="${2:-}"; shift 2 ;;
  *) echo "pakai: release-notes.sh --versi X.Y.Z [--sejak REF] [--tanggal YYYY-MM-DD]" >&2; exit 64 ;; esac; done
printf '%s' "$versi" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "release-notes: --versi harus X.Y.Z" >&2; exit 64; }
cant() { echo "release-notes: $*" >&2; exit 2; }
CL=CHANGELOG.md

opsi="$(bash "$here/workflow.sh" 2>/dev/null | sed -En 's/^[- ]*Catatan rilis: *(CHANGELOG\.md|dikelola alat lain|tidak ada).*$/\1/p' | head -1)"
if [ "$opsi" != "CHANGELOG.md" ]; then echo "release-notes: Catatan rilis bukan CHANGELOG.md; tidak ada yang disusun" >&2; exit 0; fi
[ -n "$tanggal" ] || tanggal="$(date -u +%F)"

repo="$(ghx_repo)" || cant "repo tak dapat ditentukan"
git fetch -q --tags origin 2>/dev/null || true
if [ -n "$sejak" ]; then
  git rev-parse -q --verify "$sejak^{commit}" >/dev/null || cant "--sejak $sejak tidak dikenal"
  prev="$sejak"
else
  prev="$(git tag -l 'v[0-9]*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n \
    | awk -v v="$versi" 'function cmp(a,b,  x,y,i){split(a,x,".");split(b,y,".");for(i=1;i<=3;i++){if(x[i]+0<y[i]+0)return -1;if(x[i]+0>y[i]+0)return 1}return 0} cmp($0,v)<0{last=$0} END{if(last!="")print "v" last}')"
  [ -n "$prev" ] || cant "tidak ada tag sebelum v$versi; pakai --sejak <ref> (rilis pertama dimulai dari sana)"
fi
ub=""; git rev-parse -q --verify "refs/tags/v$versi^{commit}" >/dev/null && ub="v$versi"

def="$(gh api "repos/$repo" | jq -r '.default_branch // empty')" && [ -n "$def" ] || cant "cabang bawaan tak terbaca (REST)"
integ="$(bash "$here/workflow.sh" 2>/dev/null | sed -n 's/^[- ]*.*Cabang integrasi: *\([A-Za-z0-9._\/-]*\).*/\1/p' | head -1 | sed 's/[.,;:]*$//')"
case "$integ" in tidak|none|nihil|-) integ="" ;; esac
bases="$def"; [ -z "$integ" ] || [ "$integ" = "$def" ] || bases="$bases $integ"
for b in $bases; do git fetch -q origin "$b" 2>/dev/null; git rev-parse -q --verify "origin/$b" >/dev/null || cant "origin/$b tak dapat diambil"; done
basesj="$(printf '%s\n' $bases | jq -R . | jq -sc .)"

all="[]"; page=1
while :; do
  pj="$(gh api "repos/$repo/pulls?state=closed&per_page=100&page=$page")" || cant "daftar PR tak terbaca (REST)"
  n="$(jq 'length' <<<"$pj" 2>/dev/null)" || cant "daftar PR tak dapat diurai"
  [ "$n" -gt 0 ] || break
  all="$(jq -c --argjson a "$all" '$a + .' <<<"$pj")" || cant "daftar PR tak dapat digabung"
  page=$((page+1)); [ "$page" -le 200 ] || cant "terlalu banyak halaman PR"
done
prs="$(jq -c --argjson b "$basesj" '[.[]|select(.merged_at != null and (.base.ref as $x | $b | index($x)))] | sort_by(.number)' <<<"$all")" || cant "PR tak dapat disaring"

# badan PR -> "Kategori<TAB>teks" | "BEHAVIOR<TAB>teks" | "INTERNAL" | "BAD<TAB>teks"; \r dibuang, blok kode dan komentar HTML diabaikan
parse_body() {
  tr -d '\r' | awk '
    BEGIN { fence = 0; com = 0 }
    { line = $0
      if (com) { if (line ~ /-->/) com = 0; next }
      if (line ~ /^[ \t]*```/) { fence = !fence; next }
      if (fence) next
      if (line ~ /^[ \t]*<!--/) { if (line !~ /-->/) com = 1; next }
      sub(/^- /, "", line)
      sub(/[ \t]+$/, "", line)
      if (line == "Catatan rilis: -") { print "INTERNAL"; next }
      if (line ~ /^Catatan rilis: /) {
        rest = substr(line, 16)
        if (match(rest, / - /)) {
          k = tolower(substr(rest, 1, RSTART - 1)); t = substr(rest, RSTART + 3)
          if (t != "" && k == "added") { print "Added\t" t; next }
          if (t != "" && k == "changed") { print "Changed\t" t; next }
          if (t != "" && k == "fixed") { print "Fixed\t" t; next }
          if (t != "" && k == "security") { print "Security\t" t; next }
        }
        print "BAD\t" rest; next
      }
      if (line ~ /^Perubahan perilaku: / && length(line) > 20) { print "BEHAVIOR\t" substr(line, 21); next }
    }'
}
anc() { git merge-base --is-ancestor "$1" "$2" 2>/dev/null; }   # 0 leluhur, 1 bukan, 128 commit tak dikenal

td="$(mktemp -d)"; trap 'rm -rf "$td"' EXIT
while IFS= read -r pr; do
  [ -n "$pr" ] || continue
  num="$(jq -r .number <<<"$pr")"; sha="$(jq -r '.merge_commit_sha // empty' <<<"$pr")"
  [ -n "$sha" ] || cant "PR #$num tanpa merge_commit_sha"
  git cat-file -e "$sha^{commit}" 2>/dev/null || cant "commit $sha (PR #$num) tak dikenal; jalankan git fetch"
  if anc "$sha" "$prev"; then continue; fi
  if [ -n "$ub" ] && ! anc "$sha" "$ub"; then continue; fi
  sec_label=0; jq -e '(.labels // [])|map(.name)|index("needs-security")' <<<"$pr" >/dev/null 2>&1 && sec_label=1
  parsed="$(jq -r '.body // ""' <<<"$pr" | parse_body)"
  marked=0; has_sec=0
  while IFS="$(printf '\t')" read -r kat txt; do
    [ -n "$kat" ] || continue
    case "$kat" in
      INTERNAL) marked=1 ;;
      BAD) marked=1; echo "PERINGATAN: PR #$num kategori tak dikenal pada baris 'Catatan rilis:' (entri tidak ditulis)" >&2 ;;
      BEHAVIOR) printf '%s\t%s\n' "$num" "$txt" >> "$td/Behavior" ;;
      *) marked=1; [ "$kat" != Security ] || has_sec=1; printf '%s\t%s\n' "$num" "$txt" >> "$td/$kat" ;;
    esac
  done <<<"$parsed"
  [ "$marked" = 1 ] || echo "PERINGATAN: PR #$num tanpa baris 'Catatan rilis:'" >&2
  [ "$sec_label" = 0 ] || [ "$has_sec" = 1 ] || echo "PERINGATAN: PR #$num berlabel needs-security tanpa baris 'Catatan rilis: Security - ...'" >&2
done < <(jq -c '.[]' <<<"$prs")

sec="## [$versi] - $tanggal"
for k in Added Changed Fixed Security Behavior; do
  [ -s "$td/$k" ] || continue
  h="$k"; [ "$k" != Behavior ] || h="Behavior changes"
  sec="$sec"$'\n\n'"### $h"$'\n'
  while IFS="$(printf '\t')" read -r num txt; do sec="$sec"$'\n'"- $txt (#$num)"; done < "$td/$k"
done

printf '%s\n' "$sec"
