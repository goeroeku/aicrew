#!/usr/bin/env bash
# Tes deterministik aicrew, tanpa jaringan dan tanpa kerangka. Pakai: bash tests/run.sh  (exit 1 bila ada yang gagal)
cd "$(dirname "$0")/.." || exit 1
export GIT_AUTHOR_NAME=aicrew-test GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=aicrew-test GIT_COMMITTER_EMAIL=t@example.com
root="$PWD"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT; fails=0
ok() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "GAGAL $1 (dapat '$2', harap '$3')"; fails=$((fails+1)); fi; }

# 1. budget.sh: batas iterasi dan gagal (repo git sementara)
git init -q "$tmp/r" && cd "$tmp/r" || exit 1
B="bash $root/scripts/budget.sh"
$B check 2 2 7 >/dev/null; ok "budget: awal boleh lanjut" $? 0
$B iter >/dev/null; $B iter >/dev/null; $B check 2 2 7 >/dev/null; ok "budget: iterasi penuh -> exit 2" $? 2
rm -rf .aicrew; $B fail 7 >/dev/null; $B check 5 2 7 >/dev/null; ok "budget: 1 gagal masih boleh" $? 0
$B fail 7 >/dev/null; $B check 5 2 7 >/dev/null; ok "budget: 2 gagal -> exit 3" $? 3
$B reset 7; $B check 5 2 7 >/dev/null; ok "budget: reset membuka lagi" $? 0
$B bogus >/dev/null 2>&1; ok "budget: perintah asing -> exit 64" $? 64

# 2. pr-merge-check.sh dengan gh palsu (BASE/BODY dari lingkungan)
mkdir "$tmp/bin"; cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr diff"*) [ -n "${DIFFFAIL:-}" ] && exit 1; printf '%s\n' "${DIFF:-}" ;;
  *baseRefName*) echo "$BASE" ;;
  *headRefOid*) echo "${HEAD:-abc1234567}" ;;
  *comments*) jq -n --arg a "${COMM:-}" --arg b "${COMM2:-}" '{comments:([$a,$b]|map(select(.!=""))|map({body:.}))}' ;;
  *"issue view"*) [ -n "${ISSFAIL:-}" ] && exit 1; v="ISSL_$3"; echo "${!v:-${ISSL:-}}" ;;
  *closingIssuesReferences*) for n in ${CLOSING:-}; do echo "$n"; done ;;
  *labels*) printf '%s\n' "${PRL:-}" ;;
  *body*) printf '%s\n' "$BODY" ;;
esac
EOF
chmod +x "$tmp/bin/gh"; P="$tmp/bin:$PATH"; M="bash $root/scripts/pr-merge-check.sh"
BASE=integrasi BODY="Closes #1" PATH="$P" $M 9 integrasi >/dev/null; ok "pr-merge: basis benar" $? 0
BASE=main BODY="Closes #1" PATH="$P" $M 9 integrasi >/dev/null; ok "pr-merge: basis salah -> exit 1" $? 1
out="$(BASE=integrasi BODY="Closes #4, #5" PATH="$P" $M 9 integrasi)"
case "$out" in *PERINGATAN*) r=ada ;; *) r=tidak ;; esac; ok "pr-merge: 'Closes #4, #5' diperingatkan" $r ada
out="$(BASE=integrasi BODY=$'Closes #4\nCloses #5' PATH="$P" $M 9 integrasi)"
case "$out" in *PERINGATAN*) r=ada ;; *) r=tidak ;; esac; ok "pr-merge: satu per baris tidak diperingatkan" $r tidak

# 2a. pr-merge-check.sh: gerbang needs-security dan needs-perf (label di issue yang ditutup atau di PR; laporan terikat head PR)
g() { env BASE=integrasi BODY="Closes #1" HEAD=abc1234567 "$@" PATH="$P" bash "$root/scripts/pr-merge-check.sh" 9 integrasi >/dev/null; }
RP=$'Laporan perf: lulus\nAngka sebelum/sesudah: 120/45 fsync/s\nTuning: tidak ada\nCommit: abc1234'
RS=$'Laporan security: lulus\nCommit: abc1234'
g ISSL=needs-security; ok "security: issue sensitif tanpa laporan -> exit 1" $? 1
g PRL=needs-security; ok "security: PR berlabel tanpa laporan -> exit 1" $? 1
g ISSL=needs-security COMM=$'Laporan security: gagal\nCommit: abc1234'; ok "security: laporan gagal -> exit 1" $? 1
g ISSL=needs-security COMM=$'Laporan security: lulus\nCommit: def4567'; ok "security: laporan untuk commit lama -> exit 1" $? 1
g ISSL=needs-security COMM="Laporan security: lulus"; ok "security: lulus tanpa baris Commit -> exit 1" $? 1
g ISSL=needs-security COMM="$RS"; ok "security: laporan lulus untuk head -> exit 0" $? 0
g ISSL=role:qa; ok "gerbang: issue biasa tidak ditahan" $? 0
g ISSL=needs-perf; ok "perf: issue sensitif tanpa laporan -> exit 1" $? 1
g PRL=needs-perf; ok "perf: PR berlabel tanpa laporan -> exit 1" $? 1
g ISSL=needs-perf COMM=$'Laporan perf: lulus\nTuning: tidak ada\nCommit: abc1234'; ok "perf: tanpa baris Angka -> exit 1" $? 1
g ISSL=needs-perf COMM=$'Laporan perf: lulus\nAngka sebelum/sesudah: n/a\nTuning: tidak ada\nCommit: abc1234'; ok "perf: Angka tanpa digit -> exit 1" $? 1
g ISSL=needs-perf COMM=$'Laporan perf: lulus\nAngka sebelum/sesudah: 120/45\nCommit: abc1234'; ok "perf: tanpa baris Tuning -> exit 1" $? 1
g ISSL=needs-perf COMM="${RP/abc1234/def4567}"; ok "perf: laporan untuk commit lama -> exit 1" $? 1
g ISSL=needs-perf COMM=$'> Laporan perf: lulus\n> Angka sebelum/sesudah: 120/45\n> Tuning: tidak ada\n> Commit: abc1234'; ok "perf: laporan dalam kutipan -> exit 1" $? 1
g ISSL=needs-perf COMM="${RP/lulus/gagal}"; ok "perf: laporan gagal -> exit 1" $? 1
g ISSL=needs-perf COMM="${RP/abc1234/def4567}" COMM2=$'Catatan\nCommit: abc1234'; ok "perf: bagian laporan tersebar di komentar berbeda -> exit 1" $? 1
g ISSL=needs-perf COMM="$RP"; ok "perf: laporan lengkap untuk head -> exit 0" $? 0
g BODY="Closes #1, #2" ISSL_1=role:qa ISSL_2=needs-perf; ok "gerbang: 'Closes #1, #2' dengan #2 sensitif -> exit 1" $? 1
g BODY="Closes #1, #2" ISSL_1=role:qa ISSL_2=needs-perf COMM="$RP"; ok "gerbang: #2 sensitif dengan laporan -> exit 0" $? 0
g ISSL=needs-perf COMM="Pengecualian disetujui owner (perf): fixture pemindai (Commit: abc1234)"; ok "waiver: perf dengan waiver untuk head -> exit 0" $? 0
g ISSL=needs-perf COMM="Pengecualian disetujui owner (perf): fixture pemindai (Commit: def4567)"; ok "waiver: sha lama -> exit 1" $? 1
g ISSL=needs-security COMM="Pengecualian disetujui owner (perf): coba (Commit: abc1234)"; ok "waiver: tidak berlaku untuk security -> exit 1" $? 1
g ISSL=needs-perf ISSFAIL=1; ok "gerbang: label issue tak terbaca -> exit 1 (fail-closed)" $? 1

# 2e. baseline-scan.sh (fixture rahasia dipecah dengan '' agar diff repo ini tidak memicu pemindainya sendiri) (diff dari stdin) dan integrasinya di pr-merge-check.sh
BS="bash $root/scripts/baseline-scan.sh"; : > "$tmp/empty.txt"; echo "bump github.com/foo/bar, left-pad dan postgres" > "$tmp/mentioned.txt"
D() { printf 'diff --git a/%s b/%s\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n%s\n' "$1" "$1" "$1" "$2"; }
sc() { out="$(printf '%s\n' "$1" | $BS --body "${3:-$tmp/empty.txt}" --perf-labeled "${2:-0}" 2>&1)"; rc=$?; }
has() { case "$out" in *"$1"*) echo ada ;; *) echo tidak ;; esac; }
sc "$(D app.go '+k = "AKI''AABCDEFGHIJKLMNOP"')"; ok "scan: kunci AWS -> exit 1" $rc 1; ok "scan: nilai rahasia tidak dicetak" "$(has AKI''AABCDEFGHIJKLMNOP)" tidak; ok "scan: BLOK menyebut berkas" "$(has 'BLOK')" ada
sc "$(D k.pem '+-----BEGIN RSA PRIV''ATE KEY-----')"; ok "scan: kunci privat -> exit 1" $rc 1
sc "$(D cfg.go '+pass''word = "supersecretvalue123"')"; ok "scan: password literal -> exit 1" $rc 1
sc "$(D .env '+X=1')"; ok "scan: berkas .env -> exit 1" $rc 1
sc "$(D .env.example '+X=1')"; ok "scan: .env.example lolos" $rc 0
sc "$(D a.go '-pass''word = "supersecretvalue123"')"; ok "scan: baris yang dihapus tidak dihitung" $rc 0
sc "$(D scripts/a.sh '+sync || true')"; ok "scan: sync || true -> peringatan, exit 0" $rc 0; ok "scan: sync || true bertanda PERINGATAN" "$(has PERINGATAN)" ada
sc "$(D go.mod $'+\tgithub.com/foo/bar v1.2.3')"; ok "scan: dependensi go.mod tak disebut -> PERINGATAN" "$(has github.com/foo/bar)" ada
sc "$(D go.mod $'+\tgithub.com/foo/bar v1.2.3')" 0 "$tmp/mentioned.txt"; ok "scan: dependensi disebut di badan PR -> tanpa peringatan" "$(has PERINGATAN)" tidak
sc "$(D package.json '+    "left-pad": "^1.3.0"')"; ok "scan: dependensi package.json tak disebut -> PERINGATAN" "$(has left-pad)" ada
sc "$(D Dockerfile '+FROM postgres:16')"; ok "scan: FROM image baru -> PERINGATAN" "$(has postgres)" ada
sc "$(D db/migrations/001.sql '+create table x(id int);')" 0; ok "scan: migrasi tanpa needs-perf -> PERINGATAN needs-perf" "$(has needs-perf)" ada
sc "$(D db/migrations/001.sql '+create table x(id int);')" 1; ok "scan: migrasi dengan needs-perf -> tanpa peringatan" "$(has needs-perf)" tidak
sc "$(D redis.conf '+save 60 10000')" 0; ok "scan: redis.conf tanpa needs-perf -> PERINGATAN" "$(has needs-perf)" ada
sc "$(D README.md '+halo')"; ok "scan: diff bersih -> exit 0 tanpa keluaran" "$rc:$out" "0:"
g DIFF="$(D app.go '+k = "AKI''AABCDEFGHIJKLMNOP"')"; ok "merge: rahasia di diff tanpa waiver -> exit 1" $? 1
g DIFF="$(D app.go '+k = "AKI''AABCDEFGHIJKLMNOP"')" COMM="Pengecualian disetujui owner (rahasia): fixture (Commit: abc1234)"; ok "merge: rahasia dengan waiver untuk head -> exit 0" $? 0
g DIFF="$(D app.go '+k = "AKI''AABCDEFGHIJKLMNOP"')" COMM="Pengecualian disetujui owner (rahasia): fixture (Commit: def4567)"; ok "merge: rahasia dengan waiver commit lama -> exit 1" $? 1
g DIFFFAIL=1; ok "merge: gh pr diff gagal -> exit 1 (fail-closed)" $? 1
g DIFF="$(D scripts/a.sh '+sync || true')"; ok "merge: hanya peringatan -> exit 0" $? 0

# 2f. perbaikan hasil review menyeluruh
SEC='+k = "AKI''AABCDEFGHIJKLMNOP"'
g BODY="Closes: #2" ISSL_1=role:qa ISSL_2=needs-perf; ok "review#1: 'Closes: #2' (titik dua) dengan #2 sensitif -> exit 1" $? 1
g BODY="Fixes https://github.com/o/r/issues/2" CLOSING=2 ISSL_2=needs-perf; ok "review#1: issue dari closingIssuesReferences (URL) sensitif -> exit 1" $? 1
g BODY="Resolves owner/repo#2" CLOSING=2 ISSL_2=needs-perf COMM="$RP"; ok "review#1: closingIssuesReferences sensitif dengan laporan -> exit 0" $? 0
g ISSL=needs-perf DIFF="$(D app.go "$SEC")" COMM="Pengecualian disetujui owner (perf): perf tak terukur (Commit: abc1234)"; ok "review#2: waiver perf tidak menutup rahasia -> exit 1" $? 1
g ISSL=needs-perf COMM="Pengecualian disetujui owner (rahasia): fixture (Commit: abc1234)"; ok "review#2: waiver rahasia tidak menutup perf -> exit 1" $? 1
g DIFF="$(D app.go "$SEC")" COMM="Pengecualian disetujui owner (rahasia): fixture (Commit: abc1234)"; ok "review#2: waiver rahasia menutup rahasia -> exit 0" $? 0
printf 'diff --git a/x.go b/x.go\n--- a/x.go\n+++ b/x.go\n@@ -0,0 +1,2 @@\n+++ \n%s\n' "$SEC" > "$tmp/trick.diff"; out="$($BS --body "$tmp/empty.txt" --perf-labeled 0 < "$tmp/trick.diff" 2>&1)"; ok "review#3: baris tambahan '++ ' tidak mematikan pemindai -> exit 1" $? 1
printf 'diff --git a/r.env b/r.env\n--- /dev/null\n+++ "b/r\\303\\251gl\\303\\251/.env"\n@@ -0,0 +1 @@\n+X=1\n' | $BS --body "$tmp/empty.txt" --perf-labeled 0 >/dev/null 2>&1; ok "review#4: .env dengan path non-ASCII (dikutip git) -> exit 1" $? 1
sc "$(D 'dir dengan spasi/.env' '+X=1')"; ok "review#4: .env pada path berspasi -> exit 1" $rc 1
sc "$(D conf.json '+  "api''_key": "sk''_live_abcdefghijklmnop",')"; ok "review#5: JSON \"api_key\": \"...\" -> exit 1" $rc 1
sc "$(D main.go '+	tok''en := "abcdefghijklmnop12"')"; ok "review#5: Go token := \"...\" -> exit 1" $rc 1
sc "$(D ci.sh '+export T=github''_pat_11ABCDEFG0abcdefghijkl_mnopqrstuv')"; ok "review#5: github_pat_ -> exit 1" $rc 1
sc "$(D ci.sh '+export S=xo''xb-1234567890-abcdefghijkl')"; ok "review#5: token Slack xoxb- -> exit 1" $rc 1
sc "$(D app.yml '+password: hunter2hunter2hunter2')"; ok "review#5: YAML password polos -> PERINGATAN, exit 0" "$rc:$(has PERINGATAN)" "0:ada"
g ISSL=needs-perf COMM="$RP" COMM2=$'Laporan perf: gagal\nCommit: abc1234'; ok "review#8: gagal susulan untuk head yang sama -> exit 1" $? 1
g ISSL=needs-perf COMM=$'Laporan perf: gagal\nCommit: abc1234' COMM2="$RP"; ok "review#8: lulus susulan setelah gagal -> exit 0" $? 0
g ISSL=needs-perf COMM=$'Laporan perf: gagal\nLaporan perf: lulus\nAngka sebelum/sesudah: 1/2\nTuning: tidak ada\nCommit: abc1234'; ok "review#8: satu komentar memuat gagal dan lulus -> exit 1" $? 1
out="$(env BASE=integrasi BODY="Closes #1" HEAD=abc1234567 PATH="$P" bash "$root/scripts/pr-merge-check.sh" 9 integrasi 2>&1)"; case "$out" in *"--match-head-commit abc1234567"*) r=ada ;; *) r=tidak ;; esac; ok "review#9: keluaran menyebut --match-head-commit <head>" $r ada
grep -q 'match-head-commit' "$root/skills/orchestrate/SKILL.md"; ok "review#9: orchestrate mewajibkan --match-head-commit" $? 0

g ISSL=needs-perf COMM="Pengecualian disetujui owner (perf):  (Commit: abc1234)"; ok "minor#7: waiver tanpa alasan -> exit 1" $? 1
g ISSL=Needs-Perf; ok "minor#10: label Needs-Perf (beda huruf) tanpa laporan -> exit 1" $? 1
g PRL=NEEDS-SECURITY; ok "minor#10: label NEEDS-SECURITY di PR tanpa laporan -> exit 1" $? 1

# 2b. budget total, resume.sh, autopilot.sh (gh dan claude palsu)
cd "$tmp/r" || exit 1; rm -rf .aicrew
$B iter >/dev/null; $B iter >/dev/null; $B newrun; $B check 5 2 "" 2 >/dev/null; ok "budget: newrun nol-kan putaran, total tetap -> exit 4" $? 4
$B check 5 2 "" 9 >/dev/null; ok "budget: total di bawah batas -> exit 0" $? 0
F="$tmp/fake"; mkdir -p "$F"; export FAKE="$F"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ -n "${GHFAIL:-}" ] && exit 1
echo "$*" >> "$FAKE/calls"
c="$1 $2"; q=""; head=""; st=""; prev=""
for a in "$@"; do [ "$prev" = -q ] && q="$a"; [ "$prev" = --head ] && head="$a"; [ "$prev" = --state ] && st="$a"; prev="$a"; done
if [ "$c" = "pr list" ]; then data="$(cat "$FAKE/pr.json" 2>/dev/null || echo '[]')"
  [ -n "$head" ] && data="$(jq --arg h "$head" '[.[]|select(.head==$h)]' <<<"$data")"
else data="$(cat "$FAKE/issues.json")"; [ "$st" = open ] && data="$(jq '[.[]|select(.state=="OPEN")]' <<<"$data")"; fi
if [ -n "$q" ]; then jq -r "$q" <<<"$data"; else echo "$data"; fi
EOF
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE/n" 2>/dev/null || echo 0) + 1 )); echo $n > "$FAKE/n"
case "$(sed -n "${n}p" "$FAKE/script")" in
  limit) echo "Claude usage limit reached. Your limit will reset at 5pm."; exit 1 ;;
  close) jq 'map(.state="CLOSED")' "$FAKE/issues.json" > "$FAKE/i2" && mv "$FAKE/i2" "$FAKE/issues.json"; echo ok ;;
  fail) echo boom; exit 1 ;;
  *) echo noop ;;
esac
EOF
chmod +x "$tmp/bin/gh" "$tmp/bin/claude"
AP="bash $root/scripts/autopilot.sh --sleep 0"
run_ap() { printf '%s\n' "$2" > "$F/script"; rm -f "$F/n"; echo "$1" > "$F/issues.json"; rm -rf .aicrew
  PATH="$P" AICREW_CAFF=1 AICREW_ERR_SLEEP=0 AICREW_CLAUDE=claude $AP "${@:3}" >/dev/null 2>&1; }
OPEN='[{"number":1,"state":"OPEN","labels":[{"name":"role:qa"}]}]'
run_ap "$OPEN" "close"; ok "autopilot: semua issue selesai -> exit 0" $? 0
run_ap "$OPEN" $'limit\nlimit\nlimit\nclose'; r=$?; ok "autopilot: tiga limit beruntun lalu lanjut -> exit 0" $r 0; ok "autopilot: claude dipanggil 4 kali" "$(cat $F/n)" 4
run_ap "$OPEN" $'noop\nnoop\nnoop\nnoop' --stuck 3; ok "autopilot: tanpa kemajuan -> exit 2" $? 2
run_ap "$OPEN" $'fail\nfail\nfail\nfail'; ok "autopilot: 3 gagal beruntun -> exit 1" $? 1
run_ap '[{"number":1,"state":"OPEN","labels":[{"name":"needs-principal"}]}]' "close"; r=$?; ok "autopilot: hanya needs-principal -> exit 3" $r 3; ok "autopilot: claude tidak dipanggil" "$(cat $F/n 2>/dev/null || echo 0)" 0
run_ap '[{"number":1,"state":"OPEN","labels":[{"name":"di-integrasi"}]},{"number":2,"state":"OPEN","labels":[{"name":"di-integrasi"}]}]' "close"; r=$?; ok "autopilot: issue di-integrasi dianggap selesai -> exit 0" $r 0; ok "autopilot: claude tidak dipanggil (di-integrasi)" "$(cat $F/n 2>/dev/null || echo 0)" 0
run_ap '[{"number":1,"state":"OPEN","labels":[{"name":"di-integrasi"}]},{"number":2,"state":"OPEN","labels":[{"name":"role:qa"}]}]' $'close'; ok "autopilot: sisa satu issue biasa tetap dikerjakan" "$(cat $F/n)" 1
if command -v caffeinate >/dev/null 2>&1; then printf 'close\n' > "$F/script"; rm -f "$F/n"; echo "$OPEN" > "$F/issues.json"; rm -rf .aicrew
  PATH="$P" AICREW_CLAUDE=claude bash "$root/scripts/autopilot.sh" >/dev/null 2>&1; ok "autopilot: jalur caffeinate (tanpa AICREW_CAFF) -> exit 0" $? 0; fi
git init -q "$tmp/rs" && cd "$tmp/rs" && git commit -q --allow-empty -m x && git branch issue-12
echo '[{"number":10,"state":"OPEN","labels":[{"name":"in-progress"}]},{"number":11,"state":"OPEN","labels":[{"name":"in-review"}]},{"number":12,"state":"OPEN","labels":[{"name":"in-progress"}]},{"number":13,"state":"OPEN","labels":[{"name":"in-progress"}]},{"number":14,"state":"OPEN","labels":[{"name":"role:qa"}]}]' > "$F/issues.json"
echo '[{"number":20,"state":"MERGED","head":"issue-10"},{"number":21,"state":"OPEN","head":"issue-11"}]' > "$F/pr.json"
got="$(PATH="$P" bash $root/scripts/resume.sh | cut -f1,2 | tr '\t\n' '::')"
ok "resume: klasifikasi dari fakta" "$got" "10:selesaikan-merge:11:lanjut-pr:12:periksa-cabang:13:antre-ulang:"
rm -f "$F/pr.json"; cd "$root" || exit 1

# 2d. release-report.sh (gh palsu)
git init -q "$tmp/rr" && cd "$tmp/rr" && git commit -q --allow-empty -m x && git branch -M main && git branch integ && mkdir docs && echo "3. Cabang integrasi: integ." > docs/WORKFLOW.md
RR="bash $root/scripts/release-report.sh --out $tmp/rr.md"; OKPR='[{"number":5,"state":"MERGED","baseRefName":"integ","comments":[{"body":"**Bukti selesai** ok"}]}]'
OKI='[{"number":1,"title":"a","state":"CLOSED","labels":[{"name":"di-integrasi"}]}]'
rr() { echo "$1" > "$F/issues.json"; echo "$2" > "$F/pr.json"; rm -f "$F/calls"; shift 2; PATH="$P" $RR "$@" >/dev/null 2>&1; }
rr "$OKI" "$OKPR" --test-cmd true; ok "release: semua fakta lengkap -> SIAP (exit 0), titik di nama cabang dibuang" $? 0
rr "$OKI" "$OKPR" --test-cmd true --buka-pr --dry-run; r=$?; ok "release: dry-run tidak membuka PR" "$(grep -c 'pr create' "$F/calls" 2>/dev/null || true)" 0
rr "$OKI" "$OKPR" --test-cmd true --buka-pr; ok "release: --buka-pr tanpa dry-run membuka PR" "$(grep -c 'pr create' "$F/calls")" 1
rr "$OKI" '[{"number":5,"state":"MERGED","baseRefName":"integ","comments":[]}]' --test-cmd true; ok "release: PR tanpa komentar bukti -> BELUM SIAP" $? 1
rr '[{"number":1,"title":"a","state":"OPEN","labels":[]}]' "$OKPR" --test-cmd true; ok "release: issue terbuka belum di-integrasi -> BELUM SIAP" $? 1
rr '[{"number":1,"title":"a","state":"OPEN","labels":[{"name":"needs-principal"},{"name":"di-integrasi"}]}]' "$OKPR" --test-cmd true; ok "release: needs-principal menunggu -> BELUM SIAP" $? 1
rr "$OKI" "$OKPR" --test-cmd false; ok "release: suite gagal -> BELUM SIAP" $? 1
rr "$OKI" "$OKPR"; ok "release: suite tidak dijalankan -> BELUM SIAP" $? 1
rr "$OKI" "$OKPR" --buka-pr --test-cmd false; ok "release: BELUM SIAP tidak membuka PR" "$(grep -c 'pr create' "$F/calls" 2>/dev/null || true)" 0
# 2d2. release-report.sh: PR berlabel needs-perf/needs-security wajib punya laporan lulus; jejak audit dan waiver tercetak
PP='"number":5,"title":"jalur tulis","state":"MERGED","baseRefName":"integ","body":"Closes #1"'; BE='{"body":"**Bukti selesai** ok"}'
LP='{"body":"Laporan perf: lulus\nAngka sebelum/sesudah: 120/45 fsync/s\nTuning: shared_buffers=2GB, alasan cache, rollback reload\nCommit: abc1234"}'
LS='{"body":"Laporan security: lulus\nCommit: abc1234"}'; WV='{"body":"Pengecualian disetujui owner (perf): fixture (Commit: abc1234)"}'
IP='[{"number":1,"title":"a","state":"CLOSED","labels":[{"name":"di-integrasi"},{"name":"needs-perf"}]}]'
IS='[{"number":1,"title":"a","state":"CLOSED","labels":[{"name":"di-integrasi"},{"name":"needs-security"}]}]'
rr "$IP" "[{$PP,\"labels\":[],\"comments\":[$BE]}]" --test-cmd true; ok "release: needs-perf (via issue) tanpa laporan -> BELUM SIAP" $? 1
rr "$IP" "[{$PP,\"labels\":[],\"comments\":[$BE,$LP]}]" --test-cmd true; ok "release: needs-perf dengan laporan lulus -> SIAP" $? 0
grep -q 'Jejak audit' "$tmp/rr.md" && grep -q '#5' "$tmp/rr.md" && grep -q 'shared_buffers=2GB' "$tmp/rr.md"; ok "release: jejak audit memuat PR dan baris Tuning" $? 0
rr "$IP" "[{$PP,\"labels\":[],\"comments\":[$BE,$WV]}]" --test-cmd true; ok "release: needs-perf dengan waiver -> SIAP" $? 0
grep -q 'Pengecualian owner' "$tmp/rr.md" && grep -q 'fixture' "$tmp/rr.md"; ok "release: waiver tercetak di bagian tersendiri" $? 0
rr "$IS" "[{$PP,\"labels\":[],\"comments\":[$BE]}]" --test-cmd true; ok "release: needs-security tanpa laporan -> BELUM SIAP" $? 1
rr "$IS" "[{$PP,\"labels\":[],\"comments\":[$BE,$LS]}]" --test-cmd true; ok "release: needs-security dengan laporan lulus -> SIAP" $? 0
rr "$IS" "[{$PP,\"labels\":[],\"comments\":[$BE,$WV]}]" --test-cmd true; ok "release: waiver tidak menolong needs-security -> BELUM SIAP" $? 1
rr "$OKI" "[{$PP,\"labels\":[{\"name\":\"needs-security\"}],\"comments\":[$BE]}]" --test-cmd true; ok "release: label langsung di PR tanpa laporan -> BELUM SIAP" $? 1
GHFAIL=1 rr "$OKI" "$OKPR" --test-cmd true; ok "release: gh gagal -> BELUM SIAP (fail-closed)" $? 1
rr "$OKI" "$OKPR" --test-cmd true; grep -q 'uji beban' "$tmp/rr.md"; ok "release: daftar periksa bawaan memuat uji beban dan hardening" $? 0
# 2f2. hasil review: sisi release-report
PW='{"body":"Pengecualian disetujui owner (rahasia): fx (Commit: abc1234)"}'
rr "$OKI" "[{\"number\":5,\"title\":\"t\",\"state\":\"MERGED\",\"baseRefName\":\"integ\",\"labels\":[],\"comments\":[$BE,$PW]}]" --test-cmd true; r=$?; grep -q 'Pengecualian owner' "$tmp/rr.md" && grep -q 'fx' "$tmp/rr.md"; ok "review#6: waiver rahasia pada PR tanpa label tercetak di laporan rilis" "$r:$?" "0:0"
rr "$OKI" "[{\"number\":5,\"title\":\"t\",\"state\":\"MERGED\",\"baseRefName\":\"integ\",\"body\":\"tanpa kata kunci\",\"closingIssuesReferences\":[{\"number\":1}],\"labels\":[],\"comments\":[$BE]}]" --test-cmd true; ok "review#1: rilis memakai closingIssuesReferences (issue 1 di OKI tidak sensitif) -> SIAP" $? 0
rr "$IP" "[{\"number\":5,\"title\":\"t\",\"state\":\"MERGED\",\"baseRefName\":\"integ\",\"body\":\"tanpa kata kunci\",\"closingIssuesReferences\":[{\"number\":1}],\"labels\":[],\"comments\":[$BE]}]" --test-cmd true; ok "review#1: rilis: issue sensitif via closingIssuesReferences tanpa laporan -> BELUM SIAP" $? 1
rr "$IP" "[{$PP,\"labels\":[],\"comments\":[$BE,{\"body\":\"Pengecualian disetujui owner (perf):  (Commit: abc1234)\"}]}]" --test-cmd true; ok "minor#7: rilis: waiver tanpa alasan tidak dihitung -> BELUM SIAP" $? 1
rr '[{"number":1,"title":"a","state":"CLOSED","labels":[{"name":"di-integrasi"},{"name":"Needs-Perf"}]}]' "[{$PP,\"labels\":[],\"comments\":[$BE]}]" --test-cmd true; ok "minor#10: rilis: label Needs-Perf (beda huruf) tanpa laporan -> BELUM SIAP" $? 1
cd "$root" || exit 1

# 2c. install-permissions.sh: gabung tanpa menimpa, idempoten
echo '{"permissions":{"allow":["Bash(gh pr merge:*)"]},"model":"x"}' > "$tmp/s.json"
bash "$root/scripts/install-permissions.sh" "$tmp/s.json" >/dev/null; a1="$(jq -c '[(.permissions.allow|length), (.permissions.allow|index("Bash(gh pr merge:*)")!=null), .model]' "$tmp/s.json")"
bash "$root/scripts/install-permissions.sh" "$tmp/s.json" >/dev/null; a2="$(jq -c '[(.permissions.allow|length), (.permissions.allow|index("Bash(gh pr merge:*)")!=null), .model]' "$tmp/s.json")"
want="$(jq '.permissions.allow|length' "$root/templates/autopilot-permissions.json")"; want=$((want+1))
ok "install-permissions: gabung, pertahankan aturan dan kunci lain" "$a1" "[$want,true,\"x\"]"; ok "install-permissions: idempoten" "$a2" "$a1"
ok "install-permissions: placeholder terisi (tanpa __ tersisa)" "$(grep -c '__' "$tmp/s.json")" 0
jq -e --arg r "Bash(bash $root/scripts/*)" '.permissions.allow|index($r)!=null' "$tmp/s.json" >/dev/null; ok "install-permissions: path plugin milik pengguna terpasang" $? 0
jq -e '.permissions.allow|map(select(startswith("Bash(rtk git:")))|length==1' "$root/templates/autopilot-permissions.json" >/dev/null; ok "izin: varian rtk git ada" $? 0

# 2e. rilis: sinkron versi tag, isi arsip
v="$(jq -r .version .claude-plugin/plugin.json)"
bash scripts/check-version.sh "v$v" >/dev/null 2>&1; ok "rilis: tag sama dengan versi plugin.json -> exit 0" $? 0
bash scripts/check-version.sh "v9.9.9" >/dev/null 2>&1; ok "rilis: tag beda versi -> exit 1" $? 1
bash scripts/check-version.sh "release-1" >/dev/null 2>&1; ok "rilis: tag bukan vX.Y.Z -> exit 1" $? 1
[ ! -f .gitattributes ] || ! grep -qE 'export-ignore|export-subst' .gitattributes; ok "tanpa export-ignore/export-subst (direktori Anthropic menolaknya)" $? 0
if git rev-parse --git-dir >/dev/null 2>&1 && git rev-parse -q --verify HEAD >/dev/null; then
  bash scripts/build-release.sh 9.9.9 "$tmp/dist" >/dev/null 2>&1; ok "build-release: arsip terbentuk" $? 0
  lst="$(unzip -Z1 "$tmp/dist/aicrew-9.9.9.zip" 2>/dev/null)"
  printf '%s\n' "$lst" | grep -q '^aicrew-9.9.9/LICENSE$'; ok "arsip rilis memuat LICENSE" $? 0
  printf '%s\n' "$lst" | grep -q '^aicrew-9.9.9/.claude-plugin/plugin.json$'; ok "arsip rilis memuat plugin.json" $? 0
  printf '%s\n' "$lst" | grep -qE '/\.github|/\.gitignore|/\.gitattributes'; ok "arsip rilis tanpa infrastruktur repo (.github, .gitignore)" $? 1
  (cd "$tmp/dist" && { command -v sha256sum >/dev/null && sha256sum -c SHA256SUMS || shasum -a 256 -c SHA256SUMS; } >/dev/null 2>&1); ok "arsip rilis: checksum cocok" $? 0
fi

# 2f. notify.sh: token dari userConfig plugin (CLAUDE_PLUGIN_OPTION_*), cadangan AICREW_TG_*, diam bila tidak lengkap
mkdir -p "$tmp/nbin"; cat > "$tmp/nbin/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CURL_LOG"
EOF
chmod +x "$tmp/nbin/curl"; export CURL_LOG="$tmp/curl.log"
nt() { : > "$CURL_LOG"; echo '{"message":"uji"}' | env -i PATH="$tmp/nbin:$PATH" CURL_LOG="$CURL_LOG" "$@" bash "$root/scripts/notify.sh"; echo $?; }
r="$(nt)"; ok "notify: tanpa kredensial -> exit 0" "$r" 0; ok "notify: tanpa kredensial -> tidak memanggil curl" "$(grep -c . "$CURL_LOG")" 0
nt CLAUDE_PLUGIN_OPTION_TG_TOKEN=tok1 CLAUDE_PLUGIN_OPTION_TG_CHAT=42 >/dev/null; ok "notify: userConfig dipakai (token di URL)" "$(grep -c 'bottok1/sendMessage' "$CURL_LOG")" 1
nt AICREW_TG_TOKEN=tok2 AICREW_TG_CHAT=7 >/dev/null; ok "notify: variabel lama AICREW_TG_* tetap jalan" "$(grep -c 'bottok2/sendMessage' "$CURL_LOG")" 1
nt CLAUDE_PLUGIN_OPTION_TG_TOKEN=tokA CLAUDE_PLUGIN_OPTION_TG_CHAT=1 AICREW_TG_TOKEN=tokB AICREW_TG_CHAT=2 >/dev/null; ok "notify: userConfig menang atas variabel lama" "$(grep -c 'bottokA/' "$CURL_LOG")" 1
nt CLAUDE_PLUGIN_OPTION_TG_TOKEN=tok3 >/dev/null; ok "notify: token tanpa chat -> diam" "$(grep -c . "$CURL_LOG")" 0
jq -e '.userConfig.tg_token.sensitive==true and (.userConfig.tg_token.required//false)==false and (.userConfig.tg_chat|type=="object")' "$root/.claude-plugin/plugin.json" >/dev/null; ok "plugin.json: userConfig tg_token sensitif dan opsional" $? 0
jq -e '.icon and .privacyPolicyUrl and .supportUrl and .documentationUrl' "$root/.claude-plugin/plugin.json" >/dev/null; ok "plugin.json: kolom listing direktori terisi" $? 0
[ -f "$root/PRIVACY.md" ]; ok "PRIVACY.md ada (tautan privasi direktori)" $? 0

# 3. konsistensi plugin
cd "$root" || exit 1
for f in scripts/*.sh tests/run.sh; do bash -n "$f"; ok "sintaks $f" $? 0; done
for s in $(grep -rhoE 'scripts/[a-z-]+\.sh' skills templates agents hooks 2>/dev/null | sort -u); do
  [ -f "$s" ]; ok "dirujuk ada: $s" $? 0
done
for f in templates/WORKFLOW.md skills/kickoff/SKILL.md skills/orchestrate/SKILL.md agents/principal.md; do grep -q 'principal-auto\|ESKALASI' "$f"; ok "principal-auto disebut di $f" $? 0; done
grep -q 'keputusan-otomatis' templates/WORKFLOW.md && grep -q 'keputusan-otomatis' skills/orchestrate/SKILL.md && grep -q 'keputusan-otomatis' scripts/release-report.sh; ok "label keputusan-otomatis konsisten (template, skill, laporan rilis)" $? 0
for k in skills/*/SKILL.md; do head -1 "$k" | grep -q '^---$'; ok "frontmatter $k" $? 0; done

# gerbang kapasitas dan keamanan: role perf, label, bagian host, artefak bukti
head -6 agents/perf.md | grep -q '^name: aicrew-perf$' && head -6 agents/perf.md | grep -q '^model: sonnet$'; ok "perf: frontmatter aicrew-perf, sonnet" $? 0
head -6 agents/perf.md | grep '^tools:' | grep -Eq 'Edit|Write'; ok "perf: read-only (tanpa Edit/Write)" $? 1
for f in templates/WORKFLOW.md skills/breakdown/SKILL.md skills/orchestrate/SKILL.md agents/perf.md; do grep -q 'needs-perf' "$f"; ok "needs-perf disebut di $f" $? 0; done
for f in templates/WORKFLOW.md skills/kickoff/SKILL.md; do grep -q 'Batas perangkat keras' "$f"; ok "Batas perangkat keras disebut di $f" $? 0; done
grep -q 'perf' README.md && grep -q 'perf' skills/kickoff/SKILL.md && grep -q 'perf=sonnet' templates/WORKFLOW.md; ok "role perf terdaftar (README, kickoff, model per role)" $? 0
grep -q 'Tuning:' agents/perf.md && grep -q 'Angka sebelum/sesudah:' agents/perf.md && grep -q 'Commit:' agents/perf.md; ok "perf: format vonis memuat Angka, Tuning, Commit" $? 0
grep -qi 'log audit' agents/security.md && grep -q 'Commit:' agents/security.md; ok "security: log audit dan Commit di daftar/format" $? 0
grep -q 'Laporan perf: lulus' skills/orchestrate/SKILL.md && grep -q 'Pengecualian disetujui owner' skills/orchestrate/SKILL.md; ok "orchestrate: vonis perf dan larangan agen menulis waiver" $? 0

# aicrew-perf membawa resep ukur baca-saja (dari kasus mailora), bukan hanya daftar periksa
for k in 'PGOPTIONS' 'default_transaction_read_only' 'statement_timeout' 'pg_stat_user_tables' 'n_tup_hot_upd' 'pg_stat_activity' 'pg_stat_database' '/proc/pressure/io' 'vmstat' 'docker stats' '/dev/shm' 'redis-cli' 'server_version' 'tidak boleh dijalankan di server nyata tanpa izin'; do
  grep -qF -- "$k" agents/perf.md; ok "perf: resep ukur memuat '$k'" $? 0
done

# Atribusi AI dilarang: aturan harus ada di agen penulis kode dan prompt Codex
for f in agents/senior-coder.md agents/ui-ux.md agents/devops.md agents/perf.md templates/codex-prompt.md; do
  grep -q "Tanpa atribusi AI" "$f"; ok "aturan tanpa atribusi AI di $f" $? 0
done

# guard-attribution.sh memblokir atribusi AI pada commit/PR, tidak pada perintah lain
G="bash scripts/guard-attribution.sh"
echo '{"tool_input":{"command":"git commit -m \"x\n\nCo-Authored-By: Bot\""}}' | $G 2>/dev/null; ok "guard: commit dengan Co-Authored-By -> exit 2" $? 2
echo '{"tool_input":{"command":"gh pr create --body \"Generated with Bot\""}}' | $G 2>/dev/null; ok "guard: PR dengan Generated with -> exit 2" $? 2
echo '{"tool_input":{"command":"git commit -m \"fix bug\""}}' | $G; ok "guard: commit bersih lolos" $? 0
echo '{"tool_input":{"command":"grep -r co-authored ."}}' | $G; ok "guard: perintah lain lolos" $? 0

[ "$fails" = 0 ] && echo "SEMUA LULUS" || { echo "$fails GAGAL"; exit 1; }
