#!/usr/bin/env bash
# aicrew pr-merge-check: cegah merge PR bertumpuk tersasar (GitHub/gh saja).
#   pr-merge-check.sh <pr> <cabang-tujuan>          sebelum merge: exit 1 bila basis PR != tujuan, atau PR/issue yang ditutupnya
#                                                   berlabel needs-security/needs-perf tanpa laporan lulus untuk head PR (waiver owner bercakupan perf atau rahasia)
#                                                   PR yang menyentuh package-lock.json/go.mod/requirements*.txt juga diperiksa CVE-nya (paket baru/berubah; waiver owner (cve))
#   pr-merge-check.sh <pr> <cabang-tujuan> --auto   seperti mode pertama, dan menolak PR/issue berlabel risk:L2 (auto-merge tidak boleh)
#   pr-merge-check.sh <pr> <cabang-tujuan> --after  setelah merge: exit 1 bila commit merge tak ada di origin/<tujuan>
set -u
GHX_STATE=/dev/null  # gerbang tidak memakai mode cadangan: tanpa berkas status
source "$(dirname "$0")/ghx.sh"  # hanya ghx_explain_limit: gerbang TIDAK pindah ke REST (closingIssuesReferences tak ada di REST)
pr="${1:?pr}"; dst="${2:?cabang-tujuan}"
if [ "${3:-}" = "--after" ]; then
  read -r st oid < <(gh pr view "$pr" --json state,mergeCommit -q '[.state, .mergeCommit.oid // "-"] | @tsv')
  [ "$st" = MERGED ] || { echo "GAGAL: PR #$pr belum MERGED ($st)"; exit 1; }
  git fetch -q origin "$dst" && git merge-base --is-ancestor "$oid" "origin/$dst" \
    && echo "ok: PR #$pr ($oid) ada di $dst" || { echo "GAGAL: PR #$pr ter-merge tetapi $oid tidak ada di $dst"; exit 1; }
else
  base=$(gh pr view "$pr" --json baseRefName -q .baseRefName)
  echo "PR #$pr basis: $base"
  fail() { echo "GAGAL: $*"; ghx_explain_limit; exit 1; }  # fail-closed; bila penyebabnya batas GraphQL, jelaskan dan beri jam reset
  body="$(gh pr view "$pr" --json body -q .body)" || fail "badan PR #$pr tak terbaca"
  grep -Eiq '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]+ *(,|&|and|dan) *#?[0-9]' <<<"$body" \
    && echo "PERINGATAN: satu kata kunci hanya menutup satu issue; tulis satu 'Closes #n' per baris"
  [ "$base" = "$dst" ] || fail "basis $base != $dst; jalankan: gh pr edit $pr --base $dst"

  # gerbang label: needs-security / needs-perf (label PR + semua issue pada baris berkata-kunci) wajib punya laporan lulus untuk head PR
  head="$(gh pr view "$pr" --json headRefOid -q .headRefOid)" && [ -n "$head" ] || fail "head PR #$pr tak terbaca"
  labels="$(gh pr view "$pr" --json labels -q '.labels[].name')" || fail "label PR #$pr tak terbaca"
  closing="$(gh pr view "$pr" --json closingIssuesReferences -q '.closingIssuesReferences[].number')" || fail "closingIssuesReferences PR #$pr tak terbaca"
  # issue yang diperiksa = daftar resmi GitHub (URL, owner/repo#n, sidebar Development) ∪ semua #n pada baris berkata-kunci
  for n in $( { grep -Ei '(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]' <<<"$body" | grep -Eo '#[0-9]+' | tr -d '#'; echo "$closing"; } | sort -un); do
    l="$(gh issue view "$n" --json labels -q '.labels[].name')" || fail "label issue #$n tak terbaca"
    labels="$labels"$'\n'"$l"
  done
  if [ "${3:-}" = "--auto" ] && grep -qix "risk:L2" <<<"$labels"; then fail "risk:L2: auto-merge ditolak; minta owner merge"; fi
  comments="$(gh pr view "$pr" --json comments)" || fail "komentar PR #$pr tak terbaca"
  sha_ok() { [ "${#1}" -ge 7 ] && case "$head" in "$1"*) return 0 ;; esac; return 1; }
  # verdict_ok <awalan> <wajib-angka-dan-tuning:0|1>: vonis TERAKHIR untuk head menang. lulus = satu komentar memuat vonis lulus (tanpa gagal),
  # Commit = head, dan (perf) Angka berdigit + Tuning; gagal, atau lulus tak lengkap, membuat hasil gagal sampai ada lulus lengkap berikutnya
  verdict_ok() {
    res=1
    while IFS= read -r cj; do
      b="$(jq -r .body <<<"$cj")"
      grep -Eq "^$1 (lulus|gagal)" <<<"$b" || continue
      sha_ok "$(sed -n 's/^Commit: *\([0-9a-f]*\).*/\1/p' <<<"$b" | head -1)" || continue
      if grep -q "^$1 gagal" <<<"$b"; then res=1; continue; fi
      if [ "$2" != 0 ] && ! { grep -Eq '^Angka sebelum/sesudah:.*[0-9]' <<<"$b" && grep -Eq '^Tuning: *[^ ]' <<<"$b"; }; then res=1; continue; fi
      res=0
    done < <(jq -c '.comments[]' <<<"$comments")
    return $res
  }
  # waiver_ok <perf|rahasia>: komentar owner `Pengecualian disetujui owner (<cakupan>): <alasan> (Commit: <sha>)` untuk head PR; satu waiver hanya berlaku untuk cakupannya
  waiver_ok() {
    while IFS= read -r cj; do
      sha_ok "$(jq -r .body <<<"$cj" | sed -nE "s/^Pengecualian disetujui owner \($1\): .*[^ ].* \(Commit: *([0-9a-f]*)\).*/\1/p" | head -1)" && return 0
    done < <(jq -c '.comments[]' <<<"$comments")
    return 1
  }
  if grep -qix needs-security <<<"$labels" && ! verdict_ok "Laporan security:" 0; then
    fail "needs-security: butuh komentar 'Laporan security: lulus' dengan 'Commit: <sha head>' dari aicrew-security"
  fi
  if grep -qix needs-perf <<<"$labels" && ! verdict_ok "Laporan perf:" 1 && ! waiver_ok perf; then
    fail "needs-perf: butuh 'Laporan perf: lulus' dengan Angka sebelum/sesudah (berdigit), Tuning, dan 'Commit: <sha head>' dari aicrew-perf, atau waiver owner untuk head"
  fi
  # baseline: rahasia memblokir (kecuali waiver owner untuk head), sisanya hanya peringatan; diff tak terbaca = tolak
  diff="$(gh pr diff "$pr")" || fail "diff PR #$pr tak terbaca"
  bf="$(mktemp)"; trap 'rm -f "$bf"' EXIT; printf '%s\n' "$body" > "$bf"
  grep -qix needs-perf <<<"$labels" && perfl=1 || perfl=0
  scan="$(printf '%s\n' "$diff" | bash "$(dirname "$0")/baseline-scan.sh" --body "$bf" --perf-labeled "$perfl")"; rc=$?
  [ -z "$scan" ] || echo "$scan"
  [ "$rc" = 0 ] || waiver_ok rahasia || fail "baseline-scan menemukan rahasia pada diff; perbaiki, atau waiver owner (rahasia) untuk head PR"
  # CVE (OSV): hanya bila PR menyentuh manifest/lockfile, dan hanya paket baru/berubah dibanding MERGE-BASE (bukan ujung cabang tujuan,
  # yang bisa lebih baru dari cabang PR). Daftar berkas dari REST pulls/N/files (header diff bisa menipu: path berisi " b/" atau ber-kutip git).
  # Fail-closed: berkas tak terbaca atau OSV mati = tolak, kecuali waiver owner (cve). Opt-out dibaca dari CABANG TUJUAN, bukan dari PR itu sendiri.
  if printf '%s\n' "$diff" | grep -qE 'package-lock\.json|go\.mod|requirements[^ ]*\.txt'; then
    cr="$(ghx_repo)" || fail "cve: repo tak dapat ditentukan"
    cj="$(gh api "repos/$cr/pulls/$pr/files" --paginate)" || fail "cve: daftar berkas PR #$pr tak terbaca (REST)"
    mfs="$(jq -r '.[]|select(.status!="removed")|.filename' <<<"$cj" | grep -E '(^|/)(package-lock\.json|go\.mod|requirements[^/]*\.txt)$' | sort -u)"
  else mfs=""; fi
  if [ -n "$mfs" ]; then
    cve_fetch() { # <ref> <path> <keluaran>: 0 ok, 4 = 404 (tidak ada di ref itu), 1 = galat lain. Isi lewat REST (mendukung berkas >1 MB), tanpa GraphQL
      local e rc=0 q; q="$(jq -rn --arg p "$2" '$p|split("/")|map(@uri)|join("/")')"
      e="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$cr/contents/$q?ref=$1" 2>&1 >"$3")" || rc=$?
      [ "$rc" = 0 ] && return 0; grep -qE 'HTTP 404|Not Found' <<<"$e" && return 4; return 1
    }
    cdir="$(mktemp -d)"; trap 'rm -f "$bf"; rm -rf "$cdir"' EXIT
    cve_fetch "$dst" docs/WORKFLOW.md "$cdir/wf"; fr=$?
    # pola paket privat dibaca dari cabang tujuan; sumber yang gagal dibaca (selain 404) = tolak, karena nama privat bisa terkirim ke OSV
    [ "$fr" = 0 ] || [ "$fr" = 4 ] || fail "cve: docs/WORKFLOW.md tak terbaca di cabang tujuan (REST); pola paket privat tak diketahui"
    if [ "$fr" = 0 ] && grep -qE '^[- ]*Pemeriksaan CVE: *tidak' "$cdir/wf"; then
      echo "PERINGATAN: pemeriksaan CVE dimatikan di WORKFLOW.md"
    else
      cbase="$(gh api "repos/$cr/compare/$dst...$head" 2>/dev/null | jq -r '.merge_base_commit.sha // empty' 2>/dev/null)"; [ -n "$cbase" ] || cbase="$dst"
      cblock=0; cdown=0; ci=0
      while IFS= read -r mp; do
        [ -n "$mp" ] || continue; ci=$((ci+1)); mn="${mp##*/}"; mkdir -p "$cdir/$ci/h" "$cdir/$ci/b"
        cve_fetch "$head" "$mp" "$cdir/$ci/h/$mn"; fr=$?
        [ "$fr" = 0 ] || { [ "$fr" = 4 ] && fail "cve: $mp tidak ditemukan di head (REST) padahal tidak dihapus"; fail "cve: $mp tak terbaca di head (REST)"; }
        cve_fetch "$cbase" "$mp" "$cdir/$ci/b/$mn"; fr=$?
        if [ "$fr" = 4 ]; then : > "$cdir/$ci/b/$mn"; elif [ "$fr" != 0 ]; then fail "cve: $mp tak terbaca di merge-base (REST)"; fi   # berkas baru/dipindah: semua paket baru
        # .npmrc di direktori manifest dan akar repo (cabang tujuan, lalu head hanya untuk peringatan pola baru)
        md="$(dirname "$mp")"; tn=""; hn=""; ni=0
        npmrc_src() { # <jalur .npmrc>: tambah ke $tn (cabang tujuan; galat selain 404 = tolak) dan $hn (head, hanya untuk peringatan)
          ni=$((ni+1)); cve_fetch "$dst" "$1" "$cdir/$ci/nt$ni"; fr=$?
          if [ "$fr" = 0 ]; then tn="$tn --npmrc $cdir/$ci/nt$ni"; elif [ "$fr" != 4 ]; then fail "cve: $1 tak terbaca di cabang tujuan (REST); pola paket privat tak diketahui"; fi
          if cve_fetch "$head" "$1" "$cdir/$ci/nh$ni"; then hn="$hn --npmrc $cdir/$ci/nh$ni"; fi
        }
        npmrc_src .npmrc; [ "$md" = . ] || npmrc_src "$md/.npmrc"
        # shellcheck disable=SC2086
        bash "$(dirname "$0")/cve-private.sh" --workflow "$cdir/wf" $tn --goprivate > "$cdir/$ci/pat"
        : > "$cdir/$ci/wfh"; cve_fetch "$head" docs/WORKFLOW.md "$cdir/$ci/wfh" || : > "$cdir/$ci/wfh"
        # shellcheck disable=SC2086
        bash "$(dirname "$0")/cve-private.sh" --workflow "$cdir/$ci/wfh" $hn > "$cdir/$ci/pat.h"
        if [ -n "$(LC_ALL=C comm -13 "$cdir/$ci/pat" "$cdir/$ci/pat.h")" ]; then echo "PERINGATAN: cve ($mp) pola privat baru baru berlaku setelah di-merge; paket yang cocok pada PR ini tetap dikirim"; fi
        cres="$(bash "$(dirname "$0")/cve-check.sh" "$cdir/$ci/h/$mn" --base "$cdir/$ci/b/$mn" --private "$cdir/$ci/pat" 2>"$cdir/err")"; crc=$?
        grep '^tidak lengkap' "$cdir/err" | sed "s#^#PERINGATAN: cve ($mp) #"
        cn="$(grep -c '^dilewati (privat):' "$cdir/err")"; [ "$cn" = 0 ] || echo "PERINGATAN: cve ($mp) $cn paket privat tidak diperiksa"
        grep -Ev '^(tidak lengkap|dilewati \(privat\):)' "$cdir/err" >&2
        [ -z "$cres" ] || printf '%s\n' "$cres" | awk -F'\t' -v p="$mp" '{k=($9=="baru" && $6=="prod" && ($5=="HIGH"||$5=="CRITICAL"||$5=="UNKNOWN"))?"BLOK":"PERINGATAN"; printf "%s: cve (%s) %s %s %s %s %s paparan=%s target=%s saran=%s\n",k,p,$1,$2,$3,$5,$6,$9,$7,$8}'
        case "$crc" in 0) ;; 1) cblock=1 ;; *) cdown=1 ;; esac
      done <<<"$mfs"
      [ "$cblock" = 0 ] || waiver_ok cve || fail "cve: kerentanan HIGH/CRITICAL/UNKNOWN baru pada dependensi; naikkan sesuai saran di atas, atau waiver owner (cve) untuk head PR"
      [ "$cdown" = 0 ] || waiver_ok cve || fail "cve: OSV tidak terjangkau untuk PR yang menyentuh manifest; ulangi nanti, atau waiver owner (cve) untuk head PR"
    fi
  fi
  # alur terjadwal/dependabot (#32): GitHub hanya mengaktifkannya dari cabang bawaan; peringatan saja, tidak memblokir
  at="$(bash "$(dirname "$0")/alur-terjadwal.sh" "$pr" "$head")"; arc=$?
  if [ "$arc" != 0 ]; then echo "PERINGATAN: alur terjadwal tidak dapat diperiksa"
  elif [ -n "$at" ]; then
    dflt="$(gh api "repos/$(ghx_repo)" 2>/dev/null | jq -r '.default_branch // empty' 2>/dev/null)"
    if [ -z "$dflt" ]; then echo "PERINGATAN: alur terjadwal tidak dapat diperiksa (cabang bawaan tak terbaca)"
    elif [ "$dst" != "$dflt" ]; then
      while IFS= read -r af; do echo "PERINGATAN: alur terjadwal $af tidak aktif sampai ada di cabang bawaan ($dflt)"; done <<<"$at"
    fi
  fi
  # catatan rilis (#30): bila opsi di cabang tujuan = CHANGELOG.md, PR tanpa baris 'Catatan rilis:' diperingatkan (tidak memblokir; galat baca = tanpa peringatan)
  wfr="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$(ghx_repo)/contents/docs/WORKFLOW.md?ref=$dst" 2>/dev/null)" || wfr=""
  if sed -En 's/^[- ]*Catatan rilis: *(CHANGELOG\.md).*$/\1/p' <<<"$wfr" | grep -q . && [ -z "$(bash "$(dirname "$0")/release-notes.sh" --parse-badan <<<"$body" 2>/dev/null)" ]; then
    echo "PERINGATAN: PR tanpa baris 'Catatan rilis:' (docs/WORKFLOW.md di $dst memakai CHANGELOG.md); tulis 'Catatan rilis: <Added|Changed|Fixed|Security> - <teks>' atau 'Catatan rilis: -' bila internal"
  fi
  echo "ok: gerbang lolos untuk head $head. Merge dengan: gh pr merge $pr --match-head-commit $head"
fi
