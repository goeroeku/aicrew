#!/usr/bin/env bash
# aicrew pr-merge-check: cegah merge PR bertumpuk tersasar (GitHub/gh saja).
#   pr-merge-check.sh <pr> <cabang-tujuan>          sebelum merge: exit 1 bila basis PR != tujuan, atau PR/issue yang ditutupnya
#                                                   berlabel needs-security/needs-perf tanpa laporan lulus untuk head PR (waiver owner bercakupan perf atau rahasia)
#                                                   PR yang menyentuh package-lock.json/go.mod/requirements*.txt juga diperiksa CVE-nya (paket baru/berubah; waiver owner (cve))
#   pr-merge-check.sh <pr> <cabang-tujuan> --auto   seperti mode pertama, dan menolak PR/issue berlabel risk:L2 (auto-merge tidak boleh)
#   pr-merge-check.sh <pr> <cabang-tujuan> --after  setelah merge: exit 1 bila commit merge tak ada di origin/<tujuan>
set -u
GHX_STATE=/dev/null  # gerbang tidak memakai mode cadangan: tanpa berkas status
source "$(dirname "$0")/lib/grants.sh"  # izin sementara terstruktur (#61)
source "$(dirname "$0")/ghx.sh"  # ghx_repo, ghx_gql, ghx_explain_limit; semua bacaan gerbang lewat REST, kecuali closingIssuesReferences (#113)
pr="${1:?pr}"; dst="${2:?cabang-tujuan}"
fail() { echo "GAGAL: $*"; ghx_explain_limit; ghx_explain_rest_limit; exit 1; }  # fail-closed; bila penyebabnya batas GraphQL, jelaskan dan beri jam reset
cr="$(ghx_repo)" && [ -n "$cr" ] || fail "repo tak dapat ditentukan"
prj="$(gh api "repos/$cr/pulls/$pr")" && jq -e 'type=="object"' <<<"$prj" >/dev/null 2>&1 || fail "PR #$pr tak terbaca (REST)"
if [ "${3:-}" = "--after" ]; then
  read -r st oid < <(jq -r 'if .merged_at then "MERGED" else (.state|ascii_upcase) end as $s | [$s, (.merge_commit_sha // "-")] | @tsv' <<<"$prj")
  [ "$st" = MERGED ] || { echo "GAGAL: PR #$pr belum MERGED ($st)"; exit 1; }
  git fetch -q origin "$dst" && git merge-base --is-ancestor "$oid" "origin/$dst" \
    && echo "ok: PR #$pr ($oid) ada di $dst" || { echo "GAGAL: PR #$pr ter-merge tetapi $oid tidak ada di $dst"; exit 1; }
else
  base="$(jq -r '.base.ref // empty' <<<"$prj")"
  echo "PR #$pr basis: $base"
  body="$(jq -r '.body // ""' <<<"$prj")"
  grep -Eiq '(close[sd]?|fix(e[sd])?|resolve[sd]?) +#[0-9]+ *(,|&|and|dan) *#?[0-9]' <<<"$body" \
    && echo "PERINGATAN: satu kata kunci hanya menutup satu issue; tulis satu 'Closes #n' per baris"
  [ "$base" = "$dst" ] || fail "basis $base != $dst; jalankan: gh pr edit $pr --base $dst"

  # gerbang label: needs-security / needs-perf (label PR + semua issue pada baris berkata-kunci) wajib punya laporan lulus untuk head PR
  head="$(jq -r '.head.sha // empty' <<<"$prj")"; [ -n "$head" ] || fail "head PR #$pr tak terbaca"
  labels="$(jq -r '.labels[]?.name' <<<"$prj")" || fail "label PR #$pr tak terbaca"
  # closingIssuesReferences hanya ada di GraphQL (#113). Bila batas GraphQL habis (rc 75): kata kunci di badan PR (sudah diurai di bawah) + timeline REST;
  # event `connected` (tautan sidebar) tak memuat nomor issue lewat REST, jadi ada tautan sidebar = gagal tertutup, tanpa tautan = lanjut dengan peringatan
  closing="$(ghx_gql gh pr view "$pr" -R "$cr" --json closingIssuesReferences -q '.closingIssuesReferences[].number')"; crc=$?
  if [ "$crc" = 75 ]; then
    closing=""; tl="$(gh api "repos/$cr/issues/$pr/timeline" --paginate --jq '.[] | select(.event=="connected" or .event=="disconnected") | .event')" || fail "timeline PR #$pr tak terbaca (REST); closingIssuesReferences tak dapat diperiksa saat GraphQL habis"
    [ "$(grep -cx connected <<<"$tl" || true)" -le "$(grep -cx disconnected <<<"$tl" || true)" ] || fail "PR #$pr punya tautan sidebar (Development) yang tak dapat diurai lewat REST saat GraphQL habis; tunggu reset lalu ulangi"
    # cadangan harus lebih ketat dari closingIssuesReferences: referensi lintas repo atau URL issue di samping kata kunci tak dapat diperiksa (gagal tertutup),
    # dan SEMUA #N di badan PR diperiksa labelnya (kata kunci + tab/baris baru/bentuk lain tidak lolos)
    grep -Eiq '(close[sd]?|fix(e[sd])?|resolve[sd]?)[:[:space:]]+(https?://[^[:space:]]*/issues/[0-9]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+)' <<<"$body" \
      && fail "PR #$pr menutup issue lewat URL atau owner/repo#N yang tak dapat diperiksa saat GraphQL habis; tunggu reset lalu ulangi"
    closing="$(grep -Eo '#[0-9]+' <<<"$body" | tr -d '#' || true)"
    echo "PERINGATAN: GraphQL habis; issue yang ditutup PR dibaca dari semua #N di badan PR (tanpa tautan sidebar)"
  elif [ "$crc" != 0 ]; then fail "closingIssuesReferences PR #$pr tak terbaca"; fi
  # issue yang diperiksa = daftar resmi GitHub (URL, owner/repo#n, sidebar Development) ∪ semua #n pada baris berkata-kunci
  linked=""
  for n in $( { grep -Ei '(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#[0-9]' <<<"$body" | grep -Eo '#[0-9]+' | tr -d '#'; echo "$closing"; } | sort -un); do
    linked="$linked $n"
    l="$(gh api "repos/$cr/issues/$n" --jq '.labels[]?.name')" || fail "label issue #$n tak terbaca"
    labels="$labels"$'\n'"$l"
  done
  if [ "${3:-}" = "--auto" ]; then
    # A canonical issue branch is held even when the PR has no closing reference.
    head_ref="$(jq -r '.head.ref // ""' <<<"$prj")" || fail "PR branch could not be read"
    if [[ "$head_ref" =~ ^issue-([0-9]+)$ ]]; then
      branch_issue="${BASH_REMATCH[1]}"
      branch_labels="$(gh api "repos/$cr/issues/$branch_issue" --jq '.labels[]?.name')" || fail "owner-hold: issue #$branch_issue labels could not be read (REST)"
      grep -qix owner-hold <<<"$branch_labels" && fail "owner-hold: issue #$branch_issue is held by the owner"
    fi
    grep -qix owner-hold <<<"$labels" && fail "owner-hold: automatic merge requires the owner to release the hold"
    [[ "$dst" =~ ^[A-Za-z0-9._/-]+$ ]] || fail "cabang tujuan '$dst' berkarakter tidak sah"
    acr="$cr"
    # PR yang menyentuh docs/WORKFLOW.md (termasuk rename) tidak di-merge otomatis: izin sementara hanya dimasukkan owner (#61)
    pg=1
    nondoc=0
    files='[]'
    while :; do
      pj="$(gh api "repos/$acr/pulls/$pr/files?per_page=100&page=$pg")" || fail "daftar file PR #$pr tak terbaca"
      jq -e 'type=="array"' <<<"$pj" >/dev/null 2>&1 || fail "daftar file PR #$pr tak terurai"
      files="$(printf '%s\n%s\n' "$files" "$pj" | jq -cs '.[0] + (.[1] | map({filename,previous_filename,status,additions,deletions}))')" || fail "PR files could not be accumulated"
      jq -e 'any(.[]; (.filename|ascii_downcase)=="docs/workflow.md" or ((.previous_filename // "")|ascii_downcase)=="docs/workflow.md")' <<<"$pj" >/dev/null 2>&1 && fail "PR menyentuh docs/WORKFLOW.md; auto-merge ditolak (izin sementara hanya dari owner); minta owner merge"
      # dokumentasi saja = semua berkas (dan nama lamanya) di docs/ atau README/CHANGELOG/PRIVACY berekstensi md/txt/rst, atau LICENSE; selain itu butuh vonis QA (#86). Daftar kosong = tidak ada yang diubah.
      # Gagal tertutup: jq error (mis. nama berkas null) dianggap bukan dokumentasi.
      jq -e 'any(.[]; ([.filename, (.previous_filename // empty)] | map(ascii_downcase) | any(.[]; (test("^docs/") or test("^(readme|changelog|privacy)\\.(md|txt|rst)$") or test("^license(\\.(md|txt))?$")) | not)))' <<<"$pj" >/dev/null 2>&1; [ $? = 1 ] || nondoc=1
      [ "$(jq length <<<"$pj")" -ge 100 ] || break
      pg=$((pg+1)); [ "$pg" -le 30 ] || fail "PR punya lebih dari 3000 file; auto-merge ditolak"
    done
    if grep -qix "risk:L2" <<<"$labels"; then
      # izin dibaca HANYA dari cabang tujuan (refs/heads/, bukan tag) lewat REST, gagal tertutup; waktu dari jam sistem
      dflt="$(gh api "repos/$acr" 2>/dev/null | jq -r '.default_branch // empty' 2>/dev/null)"
      [ -n "$dflt" ] || fail "risk:L2: auto-merge ditolak; cabang bawaan tak terbaca (izin tidak dievaluasi)"
      wfg="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$acr/contents/docs/WORKFLOW.md?ref=refs/heads/$dst" 2>/dev/null)" || fail "risk:L2: auto-merge ditolak; docs/WORKFLOW.md tak terbaca di $dst (izin tidak dievaluasi)"
      gl="$(grant_allows L2 "$dst" "$wfg" "$(date -u +%s)" "main master $dflt")" || fail "risk:L2: auto-merge ditolak; minta owner merge (tidak ada izin sementara yang sah dan belum kedaluwarsa untuk $dst)"
      echo "izin sementara: ${gl#- Grant: } (merge sebelum expires di atas; jalankan gerbang ulang tepat sebelum merge)"
    fi
    # hasil merge terhadap target terkini (#109): PR non-dokumentasi harus tidak tertinggal dari $dst dan punya CI hijau untuk head ini.
    # PR dokumentasi saja dikecualikan (tak ada kode yang bisa berbenturan; vonis terikat head tak perlu dihapus). Gagal tertutup; fork -> compare/check-runs gagal -> ditolak.
    if [ "${nondoc:-0}" = 1 ]; then
      behind="$(gh api "repos/$acr/compare/$dst...$head" --jq '.behind_by')" || fail "PR tertinggal dari $dst tak dapat diperiksa (compare REST gagal; PR dari fork tidak di-merge otomatis)"
      [[ "$behind" =~ ^[0-9]+$ ]] || fail "behind_by dari compare $dst...$head tak terbaca"
      [ "$behind" = 0 ] || fail "PR tertinggal $behind commit dari $dst; perbarui cabang (merge $dst ke cabang PR) lalu tunggu CI untuk head baru; CI hijau pada head lama tidak membuktikan hasil merge"
      crj="$(set -o pipefail; gh api "repos/$acr/commits/$head/check-runs?per_page=100" --paginate --jq '.check_runs[]' | jq -s '{check_runs: (group_by([.app.id, .name]) | map(max_by(.started_at // "9999-12-31T00:00:00Z")))}')" || fail "check-run CI untuk head $head tak terbaca (REST)"
      # check-run tanpa nama tak dapat dideduplikasi dengan aman; run tanpa started_at (antre) dihitung terbaru; nama sama dari aplikasi berbeda tidak saling menutupi
      jq -e 'all(.check_runs[]; (.name|type)=="string" and .name != "")' <<<"$crj" >/dev/null 2>&1 || fail "ada check-run CI tanpa nama untuk head $head; tak dapat dinilai"
      # workflow run untuk head yang belum selesai (mis. workflow lambat yang check-run-nya belum terdaftar) = CI belum selesai
      runs_open="$(gh api "repos/$acr/actions/runs?head_sha=$head&per_page=100" --jq '[.workflow_runs[]|select(.status!="completed")]|length')" || fail "workflow run untuk head $head tak terbaca (REST)"
      [[ "$runs_open" =~ ^[0-9]+$ ]] || fail "jumlah workflow run belum selesai untuk head $head tak terbaca"
      [ "$runs_open" = 0 ] || fail "CI belum selesai untuk head $head ($runs_open workflow run masih berjalan); tunggu lalu ulangi"
      if [ "$(jq '.check_runs|length' <<<"$crj" 2>/dev/null || echo x)" = 0 ]; then
        wfn="$(gh api "repos/$acr/actions/workflows" --jq '.total_count')" || fail "daftar workflow tak terbaca (CI belum dapat dipastikan)"
        [[ "$wfn" =~ ^[0-9]+$ ]] || fail "total workflow tak terbaca (CI belum dapat dipastikan)"
        [ "$wfn" = 0 ] || fail "CI belum mulai untuk head $head ($wfn workflow terdaftar, belum ada check-run); tunggu lalu ulangi"
      else
        cv="$(printf '%s' "$crj" | bash "$(dirname "$0")/ci-classify.sh" 2>/dev/null)" || fail "klasifikasi CI untuk head $head gagal"
        case "$(head -1 <<<"$cv")" in
          none) jq -e 'all(.check_runs[]; .conclusion | IN("success","skipped","neutral"))' <<<"$crj" >/dev/null 2>&1 || fail "CI untuk head $head punya check dengan hasil yang belum dapat dianggap hijau (mis. action_required atau stale)"
                jq -e 'any(.check_runs[]; .conclusion=="success")' <<<"$crj" >/dev/null 2>&1 || fail "CI untuk head $head tidak punya check yang berhasil (semua dilewati atau netral)" ;;
          pending) fail "CI belum selesai untuk head $head; tunggu lalu ulangi" ;;
          infrastructure) fail "CI tidak dapat mulai (infrastruktur, bukan kegagalan kode): $(sed -n 2p <<<"$cv"); perbaiki akun/runner lalu ulangi" ;;
          code) fail "CI gagal untuk head $head" ;;
          *) fail "klasifikasi CI untuk head $head tak dikenal" ;;
        esac
      fi
    fi
  else
    # merge manual (owner): hanya informasi, tidak pernah memblokir (#109)
    bh="$(gh api "repos/$cr/compare/$dst...$head" --jq '.behind_by' 2>/dev/null || true)"
    [[ "$bh" =~ ^[0-9]+$ ]] && [ "$bh" -gt 0 ] && echo "PERINGATAN: PR tertinggal $bh commit dari $dst; CI pada head ini tidak menguji hasil merge ke $dst terkini"
  fi
  comments="$(set -o pipefail; gh api "repos/$cr/issues/$pr/comments" --paginate --jq '.[] | {body: (.body // ""), authorAssociation: .author_association, created_at: .created_at, updated_at: (.updated_at // .created_at), login: (.user.login // ""), url: (.html_url // "")}' | jq -s '{comments: .}')" || fail "komentar PR #$pr tak terbaca (REST)"
  # Approvals cover paths on this PR only; commit text is informational.
  if [ "${3:-}" = "--auto" ] && [ "${nondoc:-0}" = 1 ]; then
    uncovered="$(printf '%s\n%s\n' "$comments" "$files" | jq -rs '
      .[0] as $comments | .[1] as $files | $comments |
      [ .comments[]
        | select(.authorAssociation | IN("OWNER","MEMBER","COLLABORATOR"))
        | select(.created_at != null and .updated_at == .created_at)
        | select(.body | test("^\\s*(laporan[ :]|owner-action:|decision applied:|blocked-by-permission:)"; "i") | not)
        | .body | split("\n")[]
        | capture("^owner approval \\(scope: test-change\\s+(?<paths>.*?)\\): .+?(?: \\(commit: [^\\r\\n]*\\))?\\s*$"; "i")
        | .paths | split(",")[] | gsub("^\\s+|\\s+$"; "") | select(length > 0)
      ] as $approved
      | $files[]
      | select(.status != "added" and ((.status == "modified" and (.additions|type) == "number" and .additions > 0 and (.deletions|type) == "number" and .deletions == 0 and ((.previous_filename // "") == "")) | not))
      | select([.filename, (.previous_filename // "")] | any(.[];
          test("(^|/)(tests?|__tests__|spec|testdata|__snapshots__|e2e)/|(^|/)test_[^/]*$|(^|/)tests\\.py$|(_test|\\.test|\\.spec|_spec)\\.[a-z0-9]+$|Test\\.java$"; "i")))
      | . as $file
      | select($approved | any(.[]; . as $approval
          | [$file.filename, ($file.previous_filename // empty)]
          | any(.[]; . == $approval or (($approval | endswith("/")) and startswith($approval)))) | not)
      | .filename + (if .previous_filename then " (previous: " + .previous_filename + ")" else "" end)')" || fail "Owner test-change approvals could not be evaluated"
    [ -z "$uncovered" ] || fail "Existing test changes require approval: $uncovered
Owner approval (scope: test-change <path>[, <path>...]): <text> (Commit: <sha>)"
  fi
  # hanya komentar OWNER/MEMBER/COLLABORATOR yang dihitung sebagai vonis atau waiver (#99); tanpa authorAssociation = tak tepercaya
  trusted_cmts='.comments[] | select(.authorAssociation | IN("OWNER","MEMBER","COLLABORATOR"))'
  sha_ok() { [ "${#1}" -ge 7 ] && case "$head" in "$1"*) return 0 ;; esac; return 1; }
  # verdict_ok <awalan> <wajib-angka-dan-tuning:0|1>: vonis TERAKHIR untuk head menang. lulus = satu komentar memuat vonis lulus (tanpa gagal),
  # Commit = head, dan (perf) Angka berdigit + Tuning; gagal, atau lulus tak lengkap, membuat hasil gagal sampai ada lulus lengkap berikutnya
  verdict_ok() {
    res=1
    while IFS= read -r cj; do
      b="$(jq -r .body <<<"$cj")"
      # label, vonis, dan "Commit" tak peka huruf; Commit boleh di baris sendiri atau di baris vonis yang sama (#86)
      grep -Eiq "^$1 (lulus|gagal)([^[:alnum:]_]|$)" <<<"$b" || continue
      cs="$(sed -nE 's/^[Cc][Oo][Mm][Mm][Ii][Tt]: *([0-9a-fA-F]+).*/\1/p' <<<"$b" | head -1)"
      [ -n "$cs" ] || cs="$(grep -Ei "^$1 (lulus|gagal)([^[:alnum:]_]|$)" <<<"$b" | head -1 | sed -nE 's/.*[Cc][Oo][Mm][Mm][Ii][Tt]: *([0-9a-fA-F]+).*/\1/p')"
      sha_ok "$(tr 'A-F' 'a-f' <<<"$cs")" || continue
      if grep -Eiq "^$1 gagal([^[:alnum:]_]|$)" <<<"$b"; then res=1; continue; fi
      if [ "$2" != 0 ] && ! { grep -Eq '^Angka sebelum/sesudah:.*[0-9]' <<<"$b" && grep -Eq '^Tuning: *[^ ]' <<<"$b"; }; then res=1; continue; fi
      res=0
    done < <(jq -c "$trusted_cmts" <<<"$comments")
    return $res
  }
  # waiver_ok <perf|rahasia>: komentar owner `Pengecualian disetujui owner (<cakupan>): <alasan> (Commit: <sha>)` untuk head PR; satu waiver hanya berlaku untuk cakupannya
  waiver_ok() {
    while IFS= read -r cj; do
      sha_ok "$(jq -r .body <<<"$cj" | sed -nE "s/^Pengecualian disetujui owner \($1\): .*[^ ].* \(Commit: *([0-9a-f]*)\).*/\1/p" | head -1)" && return 0
    done < <(jq -c "$trusted_cmts" <<<"$comments")
    return 1
  }
  if grep -qix needs-security <<<"$labels" && ! verdict_ok "Laporan security:" 0; then
    fail "needs-security: butuh komentar 'Laporan security: lulus' dengan 'Commit: <sha head>' dari aicrew-security, ditulis oleh OWNER/MEMBER/COLLABORATOR (dua baris, atau satu baris: 'Laporan security: lulus Commit: <sha head>'; huruf besar/kecil bebas)"
  fi
  if grep -qix needs-perf <<<"$labels" && ! verdict_ok "Laporan perf:" 1 && ! waiver_ok perf; then
    fail "needs-perf: butuh 'Laporan perf: lulus' dengan Angka sebelum/sesudah (berdigit), Tuning, dan 'Commit: <sha head>' dari aicrew-perf, atau waiver owner untuk head"
  fi
  # vonis QA untuk head dituntut oleh --auto pada PR yang bukan dokumentasi saja (#86); merge manual oleh owner tidak berubah
  if [ "${3:-}" = "--auto" ] && [ "${nondoc:-0}" = 1 ] && ! verdict_ok "Laporan qa:" 0; then
    fail "PR bukan dokumentasi saja: butuh komentar 'Laporan qa: lulus' dari aicrew-qa dengan 'Commit: <sha head>' (dua baris, atau satu baris: 'Laporan qa: lulus Commit: <sha head>'; huruf besar/kecil bebas); vonis terakhir untuk head menang"
  fi
  # keputusan owner setelah vonis terakhir untuk head (#110), hanya --auto: komentar tepercaya (OWNER/MEMBER/COLLABORATOR) pada PR atau issue terkait yang lebih baru
  # daripada vonis terakhir untuk head (tanpa vonis: waktu PR dibuat) memblokir sampai penulis PR menulis 'Decision applied: ...' yang lebih baru. Vonis, waiver, ack, dan catatan owner-action mesin tidak dihitung;
  # catatan berhenti orchestrator (terblokir:, blocked-by-permission:) dihitung. Merge manual oleh owner tidak diblokir.
  if [ "${3:-}" = "--auto" ]; then
    allc="$(jq -c '.comments' <<<"$comments")"
    for n in $linked; do
      ic="$(set -o pipefail; gh api "repos/$cr/issues/$n/comments" --paginate --jq '.[] | {body: (.body // ""), authorAssociation: .author_association, created_at: .created_at, updated_at: (.updated_at // .created_at), login: (.user.login // ""), url: (.html_url // "")}' | jq -s '.')" || fail "komentar issue #$n tak terbaca (REST); keputusan owner tak dapat diperiksa"
      allc="$(jq -c --argjson i "$ic" '. + $i' <<<"$allc")" || fail "komentar issue #$n tak terurai"
    done
    pra="$(jq -r '.user.login // ""' <<<"$prj")"; pat="$(jq -r '.created_at // ""' <<<"$prj")"
    pend="$(jq -r --arg head "$head" --arg pra "$pra" --arg pat "$pat" '
      def trusted: (.authorAssociation // "") | IN("OWNER","MEMBER","COLLABORATOR");
      # vonis sah = awalan laporan DAN Commit hex >= 7 (untuk commit mana pun); komentar yang hanya berawalan serupa tidak dikecualikan
      def isverdict: (.body | test("^laporan (qa|security|perf): (lulus|gagal)"; "i")) and ((.body | test("commit: *[0-9a-f]{7,}"; "i")));
      def forhead: ((.body | capture("(?i)commit: *(?<c>[0-9a-f]+)").c) // "" | ascii_downcase) as $c | ($c | length) >= 7 and ($head | startswith($c));
      def isack: (.login == $pra) and (.body | test("^\\s*decision applied:"; "i"));
      # komentar mesin: catatan owner-action tiga bagian (tindakan | perintah | alasan) dan waiver berbentuk sah
      def machine: isverdict or isack
        or (.body | test("\\Aowner approval \\(scope: [^\\r\\n]*?\\): [^\\r\\n]+(?: \\(commit: [^\\r\\n]*\\))?\\z"; "i"))
        or (.body | test("^\\s*owner-action: [^|]+\\|[^|]+\\|[^|]+$"; "i"))
        or (.body | test("^\\s*pengecualian disetujui owner \\((perf|rahasia|cve)\\): .+ \\(commit: *[0-9a-f]+\\)"; "i"));
      def ts: ([.created_at, (.updated_at // .created_at)] | max);
      . as $all
      | ([ .[] | select(trusted and isverdict and forhead) | .created_at ] | max // $pat) as $base
      | [ .[] | select(isack) ] as $acks
      | [ .[] | select(trusted and (machine | not) and (ts > $base)) ] as $cands
      | $cands | map(select(ts as $t | ($acks | any(.created_at > $t)) | not))
      | if length == 0 then empty else (.[0] | "\(ts) \(.url): \(.body | gsub("[\r\n]+"; " ") | .[0:300])") end' <<<"$allc")" || fail "keputusan owner tak dapat dievaluasi"
    [ -z "$pend" ] || fail "keputusan owner setelah vonis terakhir untuk head belum diakui: $pend; terapkan, lalu penulis PR menulis komentar 'Decision applied: <ringkasan>' (dan vonis baru bila head berubah)"
  fi
  # baseline: rahasia memblokir (kecuali waiver owner untuk head), sisanya hanya peringatan; diff tak terbaca = tolak
  diff="$(gh api -H 'Accept: application/vnd.github.v3.diff' "repos/$cr/pulls/$pr")" || fail "diff PR #$pr tak terbaca (REST)"
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
    if [ "$fr" = 0 ] && bash "$(dirname "$0")/lib/wf-normalize.sh" < "$cdir/wf" | grep -qE '^[- ]*CVE check: *no'; then
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
  at="$(bash "$(dirname "$0")/scheduled-workflow.sh" "$pr" "$head")"; arc=$?
  if [ "$arc" != 0 ]; then echo "PERINGATAN: alur terjadwal tidak dapat diperiksa"
  elif [ -n "$at" ]; then
    dflt="$(gh api "repos/$(ghx_repo)" 2>/dev/null | jq -r '.default_branch // empty' 2>/dev/null)"
    if [ -z "$dflt" ]; then echo "PERINGATAN: alur terjadwal tidak dapat diperiksa (cabang bawaan tak terbaca)"
    elif [ "$dst" != "$dflt" ]; then
      while IFS= read -r af; do echo "PERINGATAN: alur terjadwal $af tidak aktif sampai ada di cabang bawaan ($dflt)"; done <<<"$at"
    fi
  fi
  # catatan rilis (#30): bila opsi di cabang tujuan = CHANGELOG.md, PR tanpa baris 'Release note:' diperingatkan (tidak memblokir; galat baca = tanpa peringatan)
  wfr="$(gh api -H 'Accept: application/vnd.github.raw' "repos/$(ghx_repo)/contents/docs/WORKFLOW.md?ref=$dst" 2>/dev/null)" || wfr=""
  if bash "$(dirname "$0")/lib/wf-normalize.sh" <<<"$wfr" | sed -En 's/^[- ]*Release notes: *(CHANGELOG\.md).*$/\1/p' | grep -q . && [ -z "$(bash "$(dirname "$0")/release-notes.sh" --parse-body <<<"$body" 2>/dev/null)" ]; then
    echo "PERINGATAN: PR tanpa baris 'Release note:' (docs/WORKFLOW.md di $dst memakai CHANGELOG.md); tulis 'Release note: <Added|Changed|Fixed|Security> - <teks>' atau 'Release note: -' bila internal"
  fi
  echo "ok: gerbang lolos untuk head $head. Merge dengan: gh pr merge $pr --match-head-commit $head"
fi
