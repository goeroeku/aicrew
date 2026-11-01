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
chmod +x "$tmp/bin/gh"; mkdir "$tmp/pmb"; cp "$tmp/bin/gh" "$tmp/pmb/gh"; P="$tmp/bin:$PATH"; M="bash $root/scripts/pr-merge-check.sh"
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
BUMP() { printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n-%s\n+%s\n' "$1" "$1" "$1" "$1" "$2" "$3"; }
sc "$(BUMP go.mod $'\tgithub.com/foo/bar v1.2.2' $'\tgithub.com/foo/bar v1.2.3')"; ok "scan: kenaikan versi go.mod bukan dependensi baru" "$rc:$(has github.com/foo/bar)" "0:tidak"
sc "$(BUMP package.json '    "left-pad": "^1.2.0"' '    "left-pad": "^1.3.0"')"; ok "scan: kenaikan versi package.json bukan dependensi baru" "$rc:$(has left-pad)" "0:tidak"
sc "$(BUMP Dockerfile 'FROM golang:1.26-alpine' 'FROM golang:1.27-alpine')"; ok "scan: kenaikan tag image bukan dependensi baru" "$(has 'dependensi baru')" tidak
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
  neg) printf 'Round summary\n- reviewed issue 1\n- waited for QA\n- no PR changes\n- budget ok\nNo agent hit a usage limit, and I created no new issues.\n'; exit 0 ;;
  short0) echo "Claude usage limit reached. Your limit will reset at 5pm."; exit 0 ;;
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
# 2b1. #24: laporan normal panjang yang memuat kata limit (rc=0) bukan limit; limit sungguhan menunda; rc tercatat; keluaran mencurigakan diarsipkan
APO() { printf '%s\n' "$1" > "$F/script"; rm -f "$F/n"; echo "$OPEN" > "$F/issues.json"; rm -rf .aicrew; PATH="$P" AICREW_CAFF=1 AICREW_ERR_SLEEP=0 AICREW_CLAUDE=claude $AP 2>&1; }
out="$(APO $'neg\nclose')"; rc=$?
ok "autopilot #24: laporan panjang berisi 'No agent hit a usage limit' dengan rc=0 -> bukan limit, dicatat dianggap normal" "$rc|$(grep -c 'kena limit' <<<"$out")|$(grep -c 'dianggap normal' <<<"$out")" '0|0|1'
ok "autopilot #24: rc tercatat tiap putaran di autopilot.log" "$(grep -c 'putaran 1: rc=0' .aicrew/autopilot.log)|$(grep -c 'putaran 2: rc=0' .aicrew/autopilot.log)" '1|1'
ok "autopilot #24: keluaran yang menyebut limit diarsipkan (round-<run>-1-rc0.log), putaran biasa tidak" "$(ls .aicrew/archive 2>/dev/null | grep -c -- '-1-rc0.log$')|$(ls .aicrew/archive 2>/dev/null | grep -c -- '-2-rc')" '1|0'
out="$(APO $'limit\nclose')"; rc=$?
ok "autopilot #24: limit sungguhan (rc!=0 + teks) tetap memicu tunggu dan diarsipkan dengan rc-nya" "$rc|$(grep -c 'kena limit' <<<"$out")|$(grep -c 'dianggap normal' <<<"$out")|$(ls .aicrew/archive | grep -c -- '-1-rc1.log$')" '0|1|0|1'
out="$(APO $'short0\nclose')"; rc=$?
ok "autopilot #24: keluaran limit pendek dengan rc=0 (bug API yang dilaporkan) tetap dianggap limit" "$rc|$(grep -c 'kena limit' <<<"$out")" '0|1'
# 2b2. autopilot menunggu owner (merge/keputusan): polling murah tanpa claude, merge terdeteksi otomatis, tahan restart, notifikasi tidak berulang
printf '#!/usr/bin/env bash\necho "$*" >> "$FAKE/curl.calls"\n' > "$tmp/bin/curl"; chmod +x "$tmp/bin/curl"
WI='[{"number":1,"state":"OPEN","labels":[{"name":"in-review"}]}]'; echo '[{"number":7,"state":"OPEN","head":"issue-1"}]' > "$F/pr.json"
export AICREW_TG_TOKEN=t AICREW_TG_CHAT=c; : > "$F/curl.calls"
run_ap "$WI" $'noop\nnoop\nnoop' --wait 1 --wait-max 3; ok "menunggu: PR terbuka tanpa perubahan -> exit 3 (bukan buntu exit 2)" $? 3
ok "menunggu: claude hanya satu putaran (tidak membakar token)" "$(cat $F/n)" 1
n1=$(wc -l < "$F/curl.calls" | tr -d ' '); ok "menunggu: notifikasi mulai-menunggu dan batas-tunggu (2 pesan)" "$n1" 2
n=$(cat "$F/n"); PATH="$P" AICREW_CAFF=1 AICREW_CLAUDE=claude $AP --wait 1 --wait-max 2 >/dev/null 2>&1; r=$?
ok "menunggu: restart langsung menunggu/berhenti, exit 3" $r 3; ok "menunggu: restart tidak memanggil claude lagi" "$(cat $F/n)" "$n"
ok "menunggu: restart tidak mengirim notifikasi ulang" "$(wc -l < $F/curl.calls | tr -d ' ')" "$n1"
printf 'noop\nclose\n' > "$F/script"; rm -f "$F/n"; echo "$WI" > "$F/issues.json"; echo '[{"number":7,"state":"OPEN","head":"issue-1"}]' > "$F/pr.json"; rm -rf .aicrew
PATH="$P" AICREW_CAFF=1 AICREW_ERR_SLEEP=0 AICREW_CLAUDE=claude $AP --wait 1 --wait-max 30 >/dev/null 2>&1 & bg=$!
sleep 4; echo '[{"number":7,"state":"MERGED","head":"issue-1"}]' > "$F/pr.json"; wait $bg; r=$?
ok "menunggu: merge oleh owner terdeteksi otomatis, lanjut sampai selesai -> exit 0" $r 0; ok "menunggu: dua putaran claude (sebelum menunggu dan setelah merge)" "$(cat $F/n)" 2
echo '[]' > "$F/pr.json"; : > "$F/curl.calls"; PI='[{"number":1,"state":"OPEN","labels":[{"name":"needs-principal"}]}]'
run_ap "$PI" close; ok "needs-principal saja -> exit 3" $? 3
echo "$PI" > "$F/issues.json"; PATH="$P" AICREW_CAFF=1 AICREW_CLAUDE=claude $AP >/dev/null 2>&1; ok "needs-principal: tick berulang tidak mengirim notifikasi ulang" "$(wc -l < $F/curl.calls | tr -d ' ')" 1
run_ap "$OPEN" $'noop\nnoop\nnoop\nnoop' --stuck 3; ok "menunggu: issue tanpa PR tetap dihitung buntu -> exit 2" $? 2
unset AICREW_TG_TOKEN AICREW_TG_CHAT; rm -f "$F/pr.json"
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

# 2g. install-permissions: segmen versi path cache menjadi wildcard (izin tahan auto-update)
mkdir -p "$tmp/plugins/cache/mk/pl/9.9.9/scripts" "$tmp/plugins/cache/mk/pl/9.9.9/templates"
cp "$root/scripts/install-permissions.sh" "$tmp/plugins/cache/mk/pl/9.9.9/scripts/"; cp "$root/templates/autopilot-permissions.json" "$tmp/plugins/cache/mk/pl/9.9.9/templates/"
echo '{}' > "$tmp/sv.json"; bash "$tmp/plugins/cache/mk/pl/9.9.9/scripts/install-permissions.sh" "$tmp/sv.json" >/dev/null
jq -e --arg r "Bash(bash $tmp/plugins/cache/mk/pl/*/scripts/*)" '.permissions.allow|index($r)!=null' "$tmp/sv.json" >/dev/null; ok "izin: path cache berversi dijadikan wildcard" $? 0
grep -q '9\.9\.9' "$tmp/sv.json"; ok "izin: versi tidak terkunci di settings" $? 1

# 2h. autostart.sh: LaunchAgent per project, pemulihan setelah laptop mati/hidup (launchctl dilewati lewat AICREW_NO_LAUNCHCTL)
AS="bash $root/scripts/autostart.sh"; RP="$tmp/ar"; LD="$tmp/la"; FB="$tmp/fbin"; mkdir -p "$RP" "$LD" "$FB"
git init -q "$RP"; mkdir -p "$RP/.claude"; echo '{"permissions":{"allow":["Bash(gh issue:*)"]}}' > "$RP/.claude/settings.local.json"
printf '#!/bin/sh\nexit 0\n' > "$FB/claude"; printf '#!/bin/sh\n[ -n "$FAKEGH_FAIL" ] && exit 1\nexit 0\n' > "$FB/gh"; chmod +x "$FB/claude" "$FB/gh"
cat > "$tmp/fakeap.sh" <<'EOF'
#!/usr/bin/env bash
echo "$* probe=${AICREW_PROBE:-}" >> "$AP_CALLS"; [ -f "$AP_SLEEP" ] && sleep "$(cat "$AP_SLEEP")"; exit "$(cat "$AP_RC" 2>/dev/null || echo 0)"
EOF
export AP_CALLS="$tmp/ap.calls" AP_RC="$tmp/ap.rc" AP_SLEEP="$tmp/ap.sleep"; : > "$AP_CALLS"
IN() { AICREW_NO_LAUNCHCTL=1 AICREW_LAUNCH_DIR="$LD" PATH="$FB:$PATH" AICREW_TG_TOKEN=rahasia123 $AS install "$RP" "$@" >"$tmp/in.out" 2>&1; }
IN --interval 900; ok "autostart: install tanpa --max-total ditolak (exit 64)" $? 64
mkdir -p "$tmp/ar2" && git init -q "$tmp/ar2"; AICREW_NO_LAUNCHCTL=1 AICREW_LAUNCH_DIR="$LD" PATH="$FB:$PATH" $AS install "$tmp/ar2" --max-total 5 >/dev/null 2>&1; ok "autostart: install tanpa izin autopilot di project ditolak (exit 1)" $? 1
IN --max-total 50 --dry-run; ok "autostart: install --dry-run exit 0" $? 0
ok "autostart: dry-run tidak menulis plist" "$(ls "$LD" | wc -l | tr -d ' ')" 0
for k in '<key>RunAtLoad</key>' '<integer>900</integer>' "<string>$RP</string>" 'AICREW_MAX_TOTAL' '<string>50</string>' "$FB"; do grep -qF -- "$k" "$tmp/in.out"; ok "autostart: plist memuat $k" $? 0; done
grep -q 'rahasia123\|AICREW_TG' "$tmp/in.out"; ok "autostart: rahasia Telegram tidak masuk plist" $? 1
command -v plutil >/dev/null && { sed -n '/<?xml/,/<\/plist>/p' "$tmp/in.out" > "$tmp/l.plist"; plutil -lint "$tmp/l.plist" >/dev/null; ok "autostart: plist lolos plutil -lint" $? 0; }
IN --max-total 50; ok "autostart: install menulis plist (exit 0)" $? 0; ok "autostart: satu plist terpasang" "$(ls "$LD"/com.aicrew.*.plist | wc -l | tr -d ' ')" 1
c1="$(cat "$LD"/com.aicrew.*.plist | shasum)"; IN --max-total 50; ok "autostart: install idempoten" "$(cat "$LD"/com.aicrew.*.plist | shasum)" "$c1"
AICREW_NO_LAUNCHCTL=1 AICREW_LAUNCH_DIR="$LD" $AS status "$RP" 2>&1 | grep -q 'terpasang: ya'; ok "autostart: status menyebut terpasang: ya" $? 0
AICREW_NO_LAUNCHCTL=1 AICREW_LAUNCH_DIR="$LD" $AS uninstall "$RP" >/dev/null 2>&1; ok "autostart: uninstall menghapus plist" "$(ls "$LD" | wc -l | tr -d ' ')" 0
R() { AICREW_AUTOPILOT="$tmp/fakeap.sh" AICREW_MAX_TOTAL="${MT-50}" AICREW_ENV_FILE="${EF:-/nonexistent}" PATH="$FB:$PATH" $AS run "$RP" >/dev/null 2>&1; }
calls() { wc -l < "$AP_CALLS" | tr -d ' '; }
: > "$AP_CALLS"; rm -f "$AP_RC" "$AP_SLEEP"; rm -rf "$RP/.aicrew"
R; ok "autostart run: jalan normal exit 0" $? 0; ok "autostart run: autopilot dipanggil dengan --max-total 50" "$(grep -c -- '--max-total 50' "$AP_CALLS")" 1
ok "autostart run: exit 0 tidak membuat halted" "$([ -f "$RP/.aicrew/halted" ] && echo ada || echo tidak)" tidak
mkdir -p "$RP/.aicrew"; touch "$RP/.aicrew/PAUSE"; R; ok "autostart run: PAUSE -> tidak memanggil autopilot" "$(calls)" 1; rm -f "$RP/.aicrew/PAUSE"
for rc in 3 4; do echo $rc > "$AP_RC"; R; ok "autostart run: exit $rc tidak membuat halted" "$([ -f "$RP/.aicrew/halted" ] && echo ada || echo tidak)" tidak; done
echo 2 > "$AP_RC"; R; ok "autostart run: exit 2 (buntu) membuat halted" "$([ -f "$RP/.aicrew/halted" ] && echo ada || echo tidak)" ada
grep -q 'rc=2' "$RP/.aicrew/halted"; ok "autostart run: halted mencatat rc" $? 0
n=$(calls); R; ok "autostart run: halted -> tidak memanggil autopilot lagi" "$(calls)" "$n"
AICREW_NO_LAUNCHCTL=1 $AS resume "$RP" >/dev/null 2>&1; ok "autostart: resume menghapus halted" "$([ -f "$RP/.aicrew/halted" ] && echo ada || echo tidak)" tidak
echo 0 > "$AP_RC"; n=$(calls); R; ok "autostart run: setelah resume autopilot dipanggil lagi" "$(calls)" $((n+1))
echo 1 > "$AP_RC"; R; ok "autostart run: exit 1 (gagal beruntun) membuat halted" "$([ -f "$RP/.aicrew/halted" ] && echo ada || echo tidak)" ada; rm -f "$RP/.aicrew/halted"; echo 0 > "$AP_RC"
echo 2 > "$AP_SLEEP"; n=$(calls); AICREW_AUTOPILOT="$tmp/fakeap.sh" AICREW_MAX_TOTAL=50 AICREW_ENV_FILE=/nonexistent PATH="$FB:$PATH" $AS run "$RP" >/dev/null 2>&1 &
bg=$!; for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$RP/.aicrew/autostart.lock" ] && break; sleep 0.3; done
R; ok "autostart run: kunci mencegah autopilot ganda" "$(calls)" $((n+1)); wait $bg; ok "autostart run: kunci dilepas setelah selesai" "$([ -f "$RP/.aicrew/autostart.lock" ] && echo ada || echo tidak)" tidak
rm -f "$AP_SLEEP"; echo 999999 > "$RP/.aicrew/autostart.lock"; n=$(calls); R; ok "autostart run: kunci PID mati dianggap basi" "$(calls)" $((n+1))
sleep 30 & sp=$!; echo $sp > "$RP/.aicrew/autostart.lock"; n=$(calls); R; ok "autostart run: PID hidup bukan autostart (PID daur ulang) dianggap basi" "$(calls)" $((n+1)); kill $sp 2>/dev/null; rm -f "$RP/.aicrew/autostart.lock"
n=$(calls); FAKEGH_FAIL=1 R; ok "autostart run: gh/jaringan tak tersedia -> keluar tanpa memanggil autopilot" "$(calls)" "$n"
n=$(calls); MT= R; ok "autostart run: tanpa AICREW_MAX_TOTAL ditolak (tidak memanggil autopilot)" "$(calls)" "$n"
echo 'export AICREW_PROBE=ok' > "$tmp/aicrew.env"; EF="$tmp/aicrew.env" R; ok "autostart run: berkas env dibaca" "$(tail -1 "$AP_CALLS" | grep -c 'probe=ok')" 1
cd "$root" || exit 1

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
grep -q 'keputusan-otomatis' templates/WORKFLOW.md && grep -q 'keputusan-otomatis' skills/orchestrate/SKILL.md && grep -q 'keputusan-otomatis' scripts/label.sh; ok "label keputusan-otomatis konsisten (template, skill, laporan rilis)" $? 0
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

grep -q 'autostart.sh' README.md && grep -q -- '--wait-max' README.md && [ -f scripts/autostart.sh ] && grep -q -- '--wait-max' scripts/autopilot.sh; ok "autostart dan menunggu owner terdokumentasi dan ada" $? 0

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

# 3. perbaikan dari pilot Nexora (0.4.0)
cd "$root" || exit 1
# 3a. notify.sh: driver telegram | orca | both (orca palsu merekam argumen)
mkdir -p "$tmp/nb3"; printf '#!/bin/sh\necho "$@" >> "$ORCA_LOG"\n' > "$tmp/nb3/orca"; printf '#!/bin/sh\necho "$@" >> "$CURL_LOG"\n' > "$tmp/nb3/curl"; chmod +x "$tmp/nb3/orca" "$tmp/nb3/curl"
n3() { : > "$tmp/o.log"; : > "$tmp/c.log"; echo '{"message":"uji","cwd":"/w/x"}' | env -i PATH="$tmp/nb3:$PATH" ORCA_LOG="$tmp/o.log" CURL_LOG="$tmp/c.log" AICREW_ORCA_BIN="$tmp/nb3/orca" "$@" bash "$root/scripts/notify.sh"; }
n3 AICREW_NOTIFY=orca; ok "notify orca: worktree set path:<cwd> --unread --comment" "$(grep -c -- 'worktree set --worktree path:/w/x --unread --comment aicrew: uji' "$tmp/o.log")" 1
ok "notify orca: tanpa Telegram" "$(grep -c . "$tmp/c.log")" 0
n3 AICREW_NOTIFY=both AICREW_TG_TOKEN=t AICREW_TG_CHAT=1; ok "notify both: orca dan telegram" "$(grep -c . "$tmp/o.log")$(grep -c 'bott/sendMessage' "$tmp/c.log")" 11
n3 AICREW_TG_TOKEN=t AICREW_TG_CHAT=1; ok "notify bawaan: telegram saja" "$(grep -c . "$tmp/o.log")$(grep -c . "$tmp/c.log")" 01
n3 CLAUDE_PLUGIN_OPTION_NOTIFY=orca; ok "notify: opsi plugin notify=orca" "$(grep -c . "$tmp/o.log")" 1
n3 AICREW_NOTIFY=orca AICREW_ORCA_BIN="$tmp/tidak-ada"; ok "notify orca: biner tak ada -> exit 0" $? 0
jq -e '.userConfig.notify' .claude-plugin/plugin.json >/dev/null; ok "plugin.json: opsi notify" $? 0

# 3b. board-init.sh membuat view BOARD (gh palsu); "Item closed" tidak bisa lewat API -> terdokumentasi
mkdir -p "$tmp/bi" "$tmp/bib"; cat > "$tmp/bib/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$*" in
  "repo view"*) echo o/r ;;
  "project create"*) echo 3 ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"F1","options":[{"name":"Backlog"},{"name":"Ready"},{"name":"In progress"},{"name":"In review"},{"name":"Done"}]}]}' ;;
  "api graphql --input"*) cat >> "$FAKE/gql" ;;
  "api graphql"*) echo "${VIEWS:-[]}" ;;
esac
EOF
chmod +x "$tmp/bib/gh"; export FAKE="$tmp/bi"; : > "$FAKE/calls"; : > "$FAKE/gql"
PATH="$tmp/bib:$PATH" bash "$root/scripts/board-init.sh" o T 3 >/dev/null; ok "board-init: createProjectV2View BOARD_LAYOUT" "$(grep -c 'createProjectV2View' "$FAKE/gql")$(grep -c 'BOARD_LAYOUT' "$FAKE/gql")" 11
: > "$FAKE/gql"; VIEWS='["BOARD_LAYOUT"]' PATH="$tmp/bib:$PATH" bash "$root/scripts/board-init.sh" o T 3 >/dev/null; ok "board-init: idempoten (view BOARD sudah ada)" "$(grep -c 'createProjectV2View' "$FAKE/gql")" 0
ok "board-init: petunjuk langkah UI manual tercetak di jalur normal" "$(PATH="$tmp/bib:$PATH" bash "$root/scripts/board-init.sh" o T 3 2>&1 >/dev/null | grep -c 'Parent issue')" 1
ok "board-init: nomor project tetap baris terakhir stdout" "$(PATH="$tmp/bib:$PATH" bash "$root/scripts/board-init.sh" o T 3 2>/dev/null | tail -1)" 3
grep -q 'deleteProjectV2Workflow' README.md && grep -q 'Item closed' README.md; ok "README: workflow 'Item closed' tak bisa diaktifkan lewat API" $? 0

# 3c. preflight: peringatan Orca (agen diluncurkan dengan --dangerously-skip-permissions)
mkdir -p "$tmp/home/orca/workspaces/p" "$tmp/plain"; git init -q "$tmp/home/orca/workspaces/p"; git init -q "$tmp/plain"
out="$(cd "$tmp/home/orca/workspaces/p" && bash "$root/scripts/preflight.sh" 2>&1)"; case "$out" in *dangerously-skip-permissions*) r=ada ;; *) r=tidak ;; esac; ok "preflight: di workspace Orca -> peringatan" $r ada
out="$(cd "$tmp/plain" && bash "$root/scripts/preflight.sh" 2>&1)"; case "$out" in *dangerously-skip-permissions*) r=ada ;; *) r=tidak ;; esac; ok "preflight: repo biasa tanpa peringatan Orca" $r tidak

# 3d. install-permissions: basis worktree absolut, izin merge per mode, deny baru
IP() { (cd "$1" && bash "$root/scripts/install-permissions.sh" "$2" >/dev/null); }
mkdir -p "$tmp/ip1/docs" "$tmp/ip2/docs"; git init -q "$tmp/ip1"; git init -q "$tmp/ip2"
printf -- '- Basis worktree: /opt/orca/ws/ip1\n- Merge PR ke cabang integrasi: agen-setelah-QA.\n' > "$tmp/ip1/docs/WORKFLOW.md"
printf -- '- Merge PR ke cabang integrasi: owner.\n' > "$tmp/ip2/docs/WORKFLOW.md"
IP "$tmp/ip1" "$tmp/ip1/s.json"; IP "$tmp/ip2" "$tmp/ip2/s.json"
jq -e '.permissions.allow|index("Read(//opt/orca/ws/ip1/ip1-wt-*/**)")!=null' "$tmp/ip1/s.json" >/dev/null; ok "install-permissions: __REPO_PARENT__ dari Basis worktree" $? 0
jq -e '.permissions.allow|index("Bash(gh pr merge:*)")!=null' "$tmp/ip1/s.json" >/dev/null; ok "install-permissions: mode agen-setelah-QA mengizinkan gh pr merge" $? 0
jq -e '.permissions.allow|index("Bash(gh pr merge:*)")==null' "$tmp/ip2/s.json" >/dev/null; ok "install-permissions: mode owner tanpa gh pr merge" $? 0
for d in "gh repo delete" "gh ssh-key" "gh gist" "gh auth login" "gh auth token"; do
  jq -e --arg d "Bash($d:*)" '.permissions.deny|index($d)!=null' "$tmp/ip2/s.json" >/dev/null; ok "izin: deny $d" $? 0
done
jq -e '.permissions.allow|index("Bash(gh auth status:*)")!=null' "$tmp/ip2/s.json" >/dev/null; ok "izin: gh auth status tetap diizinkan" $? 0

# 3e. ensure-gitignore.sh (kickoff): .aicrew/ dan .claude/settings.local.json, idempoten
mkdir -p "$tmp/gi"; printf 'node_modules\n' > "$tmp/gi/.gitignore"
bash "$root/scripts/ensure-gitignore.sh" "$tmp/gi" >/dev/null; bash "$root/scripts/ensure-gitignore.sh" "$tmp/gi" >/dev/null
ok "gitignore: dua entri, sekali saja, isi lama utuh" "$(grep -cxF -e '.aicrew/' -e '.claude/settings.local.json' -e node_modules "$tmp/gi/.gitignore")" 3
mkdir -p "$tmp/gi2"; bash "$root/scripts/ensure-gitignore.sh" "$tmp/gi2" >/dev/null; ok "gitignore: dibuat bila belum ada" "$(wc -l < "$tmp/gi2/.gitignore" | tr -d ' ')" 2
grep -q 'ensure-gitignore.sh' skills/kickoff/SKILL.md; ok "kickoff memanggil ensure-gitignore.sh" $? 0

P="$tmp/pmb:$PATH"
# 3f. risk:L0/L1/L2: breakdown memberi label, auto-merge menolak L2 (pr-merge-check.sh --auto)
for l in risk:L0 risk:L1 risk:L2; do grep -q "$l" skills/breakdown/SKILL.md && grep -q "$l" templates/WORKFLOW.md; ok "label $l di breakdown dan WORKFLOW" $? 0; done
a() { env BASE=integrasi BODY="Closes #1" HEAD=abc1234567 "$@" PATH="$P" bash "$root/scripts/pr-merge-check.sh" 9 integrasi --auto >/dev/null; }
a ISSL=risk:L2; ok "auto-merge: issue risk:L2 -> exit 1" $? 1
a PRL=risk:L2; ok "auto-merge: PR risk:L2 -> exit 1" $? 1
a ISSL=risk:L1; ok "auto-merge: risk:L1 lolos" $? 0
g ISSL=risk:L2; ok "merge manual: risk:L2 tidak ditahan oleh gerbang" $? 0
grep -q -- '--auto' skills/orchestrate/SKILL.md; ok "orchestrate: auto-merge memakai --auto" $? 0

# 3g. board.sh --sync: issue ditutup tanpa PR -> Done bila 'Kartu Done: agen-setelah-merge'
mkdir -p "$tmp/bs/docs" "$tmp/bsb"; git init -q "$tmp/bs"; cat > "$tmp/bsb/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$*" in
  "repo view"*) echo o/r ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"F1","options":[{"name":"In review","id":"O1"},{"name":"Done","id":"OD"}]}]}' ;;
  "project item-list"*) echo '{"items":[{"id":"I5","status":"In review","content":{"number":5,"type":"Issue"}},{"id":"I6","status":"In review","content":{"number":6,"type":"Issue"}},{"id":"I7","status":"Done","content":{"number":7,"type":"Issue"}}]}' ;;
  "issue list"*) echo '[{"number":5,"closedByPullRequestsReferences":[]},{"number":6,"closedByPullRequestsReferences":[{"number":9}]},{"number":7,"closedByPullRequestsReferences":[]}]' ;;
esac
EOF
chmod +x "$tmp/bsb/gh"; export FAKE="$tmp/bs"; : > "$FAKE/calls"
printf -- '- Kartu Done: agen-setelah-merge.\n' > "$tmp/bs/docs/WORKFLOW.md"
(cd "$tmp/bs" && PATH="$tmp/bsb:$PATH" bash "$root/scripts/board.sh" o 3 --sync >/dev/null)
ok "board --sync: hanya #5 (tanpa PR, belum Done) dipindah" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I5.*OD')$(grep -c 'item-edit' "$FAKE/calls")" 11
: > "$FAKE/calls"; printf -- '- Kartu Done: owner.\n' > "$tmp/bs/docs/WORKFLOW.md"
(cd "$tmp/bs" && PATH="$tmp/bsb:$PATH" bash "$root/scripts/board.sh" o 3 --sync >/dev/null); ok "board --sync: Kartu Done owner -> tidak ada perubahan" "$(grep -c 'item-edit' "$FAKE/calls")" 0

# 3h. nama label dapat dikonfigurasi (label.sh, release-report, autopilot, skill)
mkdir -p "$tmp/lb/docs"; printf -- '- Label integrasi: integrated\n- Label keputusan otomatis: auto-decided\n' > "$tmp/lb/docs/WORKFLOW.md"
L() { (cd "$tmp/lb" && env -u AICREW_LABEL_INTEGRATED "$@" bash "$root/scripts/label.sh" "$LK"); }
LK=integrated; ok "label.sh: dari WORKFLOW.md" "$(L)" integrated
LK=auto; ok "label.sh: keputusan otomatis dari WORKFLOW.md" "$(L)" auto-decided
LK=integrated; ok "label.sh: env menang" "$(L AICREW_LABEL_INTEGRATED=zzz)" zzz
LK=integrated; ok "label.sh: bawaan di-integrasi" "$(cd "$tmp/plain" && bash "$root/scripts/label.sh" integrated)" di-integrasi
LK=auto; ok "label.sh: bawaan keputusan-otomatis" "$(cd "$tmp/plain" && bash "$root/scripts/label.sh" auto)" keputusan-otomatis
! grep -q '"di-integrasi"\|has keputusan-otomatis' scripts/release-report.sh scripts/autopilot.sh; ok "release-report/autopilot tanpa nama label tertanam" $? 0
grep -q 'label.sh' scripts/release-report.sh && grep -q 'label.sh' scripts/autopilot.sh && grep -q 'Label integrasi' templates/WORKFLOW.md; ok "label.sh dipakai skrip dan WORKFLOW" $? 0

# 3i. ISSUE.md: boilerplate keamanan untuk issue discovery yang membaca repo lain
grep -q '\.env' templates/ISSUE.md && grep -qi 'data' templates/ISSUE.md && grep -qi 'git history' templates/ISSUE.md; ok "ISSUE.md: boilerplate keamanan discovery" $? 0
cd "$root" || exit 1

# 4. journey dan epic (0.5.0): issue berlabel epic bukan pekerjaan
export FAKE="$F"; Q="$tmp/bin:$PATH"; P="$Q"; EPIC='{"number":9,"title":"[J1] x","state":"OPEN","labels":[{"name":"epic"},{"name":"in-progress"}]}'
cd "$tmp/r" || exit 1
run_epic() { printf 'close\n' > "$F/script"; rm -f "$F/n"; echo "$1" > "$F/issues.json"; rm -rf .aicrew; PATH="$Q" AICREW_CAFF=1 AICREW_CLAUDE=claude bash "$root/scripts/autopilot.sh" --sleep 0 >/dev/null 2>&1; }
run_epic "[$EPIC]"; r=$?; ok "epic: hanya epic terbuka -> autopilot exit 0" $r 0; ok "epic: claude tidak dipanggil" "$(cat $F/n 2>/dev/null || echo 0)" 0
run_epic "[$EPIC,{\"number\":1,\"state\":\"OPEN\",\"labels\":[{\"name\":\"role:qa\"}]}]"; ok "epic: issue biasa tetap dikerjakan di samping epic" "$(cat $F/n)" 1
echo "[$EPIC]" > "$F/issues.json"; [ -z "$(PATH="$Q" bash "$root/scripts/resume.sh")" ]; ok "epic: resume.sh tidak mengklasifikasi epic" $? 0
cd "$tmp/rr" || exit 1
rr "$(jq -c '. + ['"$EPIC"']' <<<"$OKI")" "$OKPR" --test-cmd true; ok "epic: release-report SIAP walau epic masih terbuka" $? 0
# 4b. templat PRD/EPIC dan skill breakdown/orchestrate
cd "$root" || exit 1
grep -q '^## Journeys' templates/PRD.md && grep -q '^## Kebutuhan non-fungsional' templates/PRD.md; ok "PRD: bagian Journeys dan NFR" $? 0
grep -q 'journey' templates/PRD.md && grep -q 'R-ID' templates/PRD.md; ok "PRD: peta issue menyebut journey" $? 0
[ -f templates/EPIC.md ] && grep -q -- '- \[ \] #' templates/EPIC.md; ok "EPIC.md ada dengan daftar centang anak" $? 0
grep -q '`epic`' templates/WORKFLOW.md; ok "WORKFLOW: label epic" $? 0
grep -q 'templates/EPIC.md' skills/breakdown/SKILL.md && grep -q 'Unassigned' skills/breakdown/SKILL.md && grep -q 'membuat epic tidak mengedit' skills/breakdown/SKILL.md && ! grep -q 'tidak pernah diedit' skills/breakdown/SKILL.md README.md; ok "breakdown: epic, Unassigned, issue lama tidak diedit" $? 0
e1=$(grep -n 'epic' skills/orchestrate/SKILL.md | head -1 | cut -d: -f1); p4=$(grep -n '^4\. Ada issue terbuka' skills/orchestrate/SKILL.md | cut -d: -f1)
[ -n "$e1" ] && [ "$e1" -lt "$p4" ]; ok "orchestrate: pengecualian epic sebelum prasyarat 4" $? 0
sed -n '/^## Tahap penutup/p' skills/orchestrate/SKILL.md | grep -q 'epic'; ok "orchestrate: tahap penutup mengabaikan epic" $? 0
grep -q 'Journey' README.md && grep -q 'FR' README.md; ok "README: Journey dan epic" $? 0
# 4c. kanban: status epic dihitung dari anak lewat board.sh --sync (gh palsu)
mkdir -p "$tmp/eb" "$tmp/ebb"; cat > "$tmp/ebb/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$*" in
  "repo view"*) echo o/r ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"F1","options":[{"name":"Backlog","id":"OB"},{"name":"In progress","id":"OP"},{"name":"In review","id":"OR"},{"name":"Done","id":"OD"}]}]}' ;;
  "project item-list"*) cat "$FAKE/items.json" ;;
  "project item-add"*) echo '{"id":"NEW"}' ;;
  "issue list --state open --label epic"*) cat "$FAKE/epics.json" ;;
  "issue list --state all"*) cat "$FAKE/states.json" ;;
  "issue list"*) echo '[]' ;;
esac
EOF
chmod +x "$tmp/ebb/gh"; export FAKE="$tmp/eb"; mkdir -p "$tmp/eb/w/docs"; git init -q "$tmp/eb/w"; echo '- Kartu Done: owner.' > "$tmp/eb/w/docs/WORKFLOW.md"
echo '[{"number":20,"body":"## Child issues\n- [ ] #5 a\n- [x] #6 b"}]' > "$FAKE/epics.json"
ES() { : > "$FAKE/calls"; (cd "$tmp/eb/w" && PATH="$tmp/ebb:$PATH" bash "$root/scripts/board.sh" o 3 --sync >/dev/null); }
echo '{"items":[{"id":"I20","status":"Backlog","content":{"number":20,"type":"Issue"}},{"id":"I5","status":"In progress","content":{"number":5,"type":"Issue"}}]}' > "$FAKE/items.json"
echo '[{"number":5,"state":"OPEN"},{"number":6,"state":"CLOSED"}]' > "$FAKE/states.json"; ES
ok "epic kanban: anak berjalan -> epic In progress" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20.*OP')" 1
echo '[{"number":5,"state":"CLOSED"},{"number":6,"state":"CLOSED"}]' > "$FAKE/states.json"; ES
ok "epic kanban: semua anak selesai -> epic In review" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20.*OR')" 1
echo '{"items":[{"id":"I20","status":"Backlog","content":{"number":20,"type":"Issue"}},{"id":"I5","status":"Backlog","content":{"number":5,"type":"Issue"}}]}' > "$FAKE/items.json"
echo '[{"number":5,"state":"OPEN"},{"number":6,"state":"OPEN"}]' > "$FAKE/states.json"; ES
ok "epic kanban: anak belum mulai, epic sudah Backlog -> tanpa perubahan" "$(grep -c 'item-edit' "$FAKE/calls")" 0
echo '[{"number":5,"state":"OPEN"},{"number":6,"state":"OPEN"}]' > "$FAKE/states.json"
echo '{"items":[{"id":"I5","status":"Backlog","content":{"number":5,"type":"Issue"}}]}' > "$FAKE/items.json"; ES
ok "epic kanban: epic belum di board -> ditambahkan (Backlog)" "$(grep -c 'item-add' "$FAKE/calls")$(grep 'item-edit' "$FAKE/calls" | grep -c 'NEW.*OB')" 11
grep -q 'board.sh' skills/breakdown/SKILL.md && grep -q 'label:epic' README.md; ok "kanban epic: breakdown menaruh epic di board; README: view Journeys" $? 0
# 4e. sub-issue native, progres epic, status epic yang tidak menyesatkan, tutup issue di-integrasi, WORKFLOW dari cabang integrasi (0.6.0)
mkdir -p "$tmp/ec/w/docs" "$tmp/ecb"; git init -q "$tmp/ec/w"; echo '- Kartu Done: owner.' > "$tmp/ec/w/docs/WORKFLOW.md"
cat > "$tmp/ecb/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$*" in
  "repo view"*) echo o/r ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"F1","options":[{"name":"Backlog","id":"OB"},{"name":"In progress","id":"OP"},{"name":"In review","id":"OR"},{"name":"Done","id":"OD"}]}]}' ;;
  "project item-list"*) cat "$FAKE/items.json" ;;
  "project item-add"*) echo '{"id":"NEW"}' ;;
  "api repos/o/r/issues/20/sub_issues"*"--jq"*) cat "$FAKE/native.txt" 2>/dev/null ;;
  "api repos/o/r/issues/"*"/comments"*) cat "$FAKE/comments.txt" 2>/dev/null ;;
  "api repos/o/r/issues/"*"/parent"*) cat "$FAKE/parent.txt" 2>/dev/null || exit 1 ;;
  "api -X POST"*|"api -X PATCH"*) : ;;
  "api repos/o/r/issues/"*) n="${2##*/}"; echo $((1000+n)) ;;
  "issue view"*) cat "$FAKE/epicbody.txt" ;;
  "issue edit"*) printf '%s\n' "${@: -1}" > "$FAKE/epicbody.txt" ;;
  "issue close"*) : ;;
  "issue list --state open --label epic"*) cat "$FAKE/epics.json" ;;
  "issue list --state open --label di-integrasi"*) cat "$FAKE/integrated.json" ;;
  "issue list --state all"*) cat "$FAKE/states.json" ;;
  "issue list --state closed"*) cat "$FAKE/closed.json" ;;
  "issue list --state open --limit"*) cat "$FAKE/open.json" ;;
  "issue list"*) echo '[]' ;;
esac
EOF
chmod +x "$tmp/ecb/gh"; export FAKE="$tmp/ec"; rm -f "$FAKE/native.txt" "$FAKE/parent.txt" "$FAKE/comments.txt"
EY() { : > "$FAKE/calls"; (cd "$tmp/ec/w" && PATH="$tmp/ecb:$PATH" bash "$root/scripts/board.sh" o 3 --sync >/dev/null); }
echo '{"items":[{"id":"I20","status":"Backlog","content":{"number":20,"type":"Issue"}}]}' > "$FAKE/items.json"
echo '[{"number":20,"body":"- [ ] #5 a","labels":[]}]' > "$FAKE/epics.json"
echo 7 > "$FAKE/native.txt"; echo '[{"number":5,"state":"CLOSED","labels":[]},{"number":7,"state":"OPEN","labels":[]}]' > "$FAKE/states.json"; EY
ok "epic: anak dibaca dari sub-issue native (bukan daftar centang)" "$(grep -c 'item-edit' "$FAKE/calls")" 0
rm "$FAKE/native.txt"
echo '[{"number":5,"state":"CLOSED","labels":[{"name":"enhancement"}]},{"number":6,"state":"OPEN","labels":[]}]' > "$FAKE/states.json"
echo '[{"number":20,"body":"- [ ] #5 a\n- [ ] #6 b","labels":[]}]' > "$FAKE/epics.json"; EY
ok "epic: sebagian anak Done, belum ada yang berjalan -> In progress (bukan Backlog)" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20.*OP')" 1
ok "epic: progres diposting ke epic ('1/2 Done')" "$(grep -c 'aicrew-progress: 1/2 Done' "$FAKE/calls")" 1
echo '[{"number":5,"state":"CLOSED","labels":[{"name":"phase:discovery"}]},{"number":6,"state":"CLOSED","labels":[{"name":"discovery"}]}]' > "$FAKE/states.json"; EY
ok "epic: semua anak Done tapi hanya discovery -> bukan In review" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20.*OR')" 0
echo '[{"number":5,"state":"CLOSED","labels":[{"name":"discovery"}]},{"number":6,"state":"CLOSED","labels":[]}]' > "$FAKE/states.json"; EY
ok "epic: ada anak non-discovery dan semua Done -> In review" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20.*OR')" 1
echo '[{"number":20,"body":"- [ ] #5 a","labels":[{"name":"belum-dipecah"}]}]' > "$FAKE/epics.json"
echo '[{"number":5,"state":"CLOSED","labels":[]}]' > "$FAKE/states.json"; EY
ok "epic: label belum-dipecah -> tidak pernah In review" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20.*OR')" 0
echo '[{"number":8,"labels":[{"name":"di-integrasi"}]}]' > "$FAKE/integrated.json"; echo '[]' > "$FAKE/epics.json"
printf -- '- Kartu Done: owner.\n- Tutup issue setelah merge integrasi: ya\n' > "$tmp/ec/w/docs/WORKFLOW.md"; EY
ok "tutup issue di-integrasi: ya -> issue close 8" "$(grep -c '^issue close 8' "$FAKE/calls")" 1
printf -- '- Kartu Done: owner.\n- Tutup issue setelah merge integrasi: tidak\n' > "$tmp/ec/w/docs/WORKFLOW.md"; EY
ok "tutup issue di-integrasi: tidak -> tidak menutup" "$(grep -c '^issue close' "$FAKE/calls")" 0
printf -- '- Label discovery: eksplorasi\n- Label epic belum dipecah: mentah\n' > "$tmp/ec/w/docs/WORKFLOW.md"
echo '[{"number":20,"body":"- [ ] #5 a","labels":[]}]' > "$FAKE/epics.json"; echo '[{"number":5,"state":"CLOSED","labels":[{"name":"eksplorasi"}]}]' > "$FAKE/states.json"; EY
ok "label discovery dari WORKFLOW: anak 'eksplorasi' = discovery -> bukan In review" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20.*OR')" 0
echo '[{"number":20,"body":"- [ ] #5 a","labels":[{"name":"mentah"}]}]' > "$FAKE/epics.json"; echo '[{"number":5,"state":"CLOSED","labels":[]}]' > "$FAKE/states.json"; EY
ok "label belum-dipecah dari WORKFLOW: 'mentah' -> bukan In review" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20.*OR')" 0
printf -- '- Kartu Done: agen-setelah-merge\n' > "$tmp/ec/w/docs/WORKFLOW.md"; echo '[]' > "$FAKE/epics.json"
echo '{"items":[{"id":"I20","status":"In review","content":{"number":20,"type":"Issue"}},{"id":"I9","status":"In review","content":{"number":9,"type":"Issue"}}]}' > "$FAKE/items.json"
echo '[{"number":20,"labels":[{"name":"epic"}],"closedByPullRequestsReferences":[]},{"number":9,"labels":[],"closedByPullRequestsReferences":[]}]' > "$FAKE/closed.json"; EY
ok "Done-mirror: epic ditutup tidak ikut dicerminkan, issue biasa ya" "$(grep 'item-edit' "$FAKE/calls" | grep -c 'I9.*OD')$(grep 'item-edit' "$FAKE/calls" | grep -c 'I20')" 10
# epic-link.sh
EL() { : > "$FAKE/calls"; (cd "$tmp/ec/w" && PATH="$tmp/ecb:$PATH" bash "$root/scripts/epic-link.sh" "$@" 2>/dev/null); }
echo '- [ ] #1 x' > "$FAKE/epicbody.txt"; cp "$tmp/ecb/gh" "$tmp/ecb/gh.ok"; sed -i.bak 's#"issue edit"\*) printf.*#"issue edit"*) : ;;#' "$tmp/ecb/gh"
EL 20 7 >/dev/null; ok "epic-link: checklist gagal terpasang setelah 3 percobaan -> exit non-zero" "$([ $? -ne 0 ] && echo gagal)" gagal
mv "$tmp/ecb/gh.ok" "$tmp/ecb/gh"; chmod +x "$tmp/ecb/gh"
# epic-link.sh --check: daftar issue terbuka non-epic tanpa induk
echo '[{"number":5,"title":"a","labels":[]},{"number":6,"title":"b","labels":[]},{"number":20,"title":"[J1]","labels":[{"name":"epic"}]}]' > "$FAKE/open.json"
echo '[{"number":20,"body":"- [ ] #5 a"}]' > "$FAKE/epics.json"; rm -f "$FAKE/parent.txt"
ok "epic-link --check: #6 yatim terdaftar, #5 (di checklist) dan epic tidak" "$(EL --check | tr '\n' ' ')" "yatim: #6 b "
EL --check >/dev/null; ok "epic-link --check: exit 3 bila ada yatim" "$?" 3
echo '[{"number":20,"body":"- [ ] #5 a\n- [ ] #6 b"}]' > "$FAKE/epics.json"; EL --check >/dev/null; ok "epic-link --check: tanpa yatim -> exit 0" "$?" 0
echo '[{"number":6,"title":"b","labels":[{"name":"tanpa-induk"}]}]' > "$FAKE/open.json"; echo '[]' > "$FAKE/epics.json"; EL --check >/dev/null
ok "epic-link --check: label tanpa-induk dilewati (yatim disengaja)" "$?" 0
printf -- '- Label tanpa induk: payung\n' > "$tmp/ec/w/docs/WORKFLOW.md"
echo '[{"number":6,"title":"b","labels":[{"name":"payung"}]}]' > "$FAKE/open.json"; EL --check >/dev/null
ok "epic-link --check: nama label tanpa induk dari WORKFLOW" "$?" 0
# lock.sh: kunci per nama untuk stack bersama (Docker/Keycloak); mkdir atomik, tanpa flock (tak ada di macOS)
export TMPDIR_LOCK="$tmp/lk"; mkdir -p "$TMPDIR_LOCK"; LK() { TMPDIR="$TMPDIR_LOCK" bash "$root/scripts/lock.sh" "$@"; }
LK t --wait 2 -- true; ok "lock.sh: menjalankan perintah dan melepas kunci" "$?$([ -d "$TMPDIR_LOCK/aicrew-lock-t" ] && echo ada)" 0
( LK t -- sleep 3 ) & sleep 1; LK t --wait 1 -- true; ok "lock.sh: kunci dipegang proses lain -> habis waktu (exit 75)" "$?" 75; wait
LK t -- bash -c 'exit 7'; ok "lock.sh: meneruskan exit status perintah" "$?" 7
mkdir "$TMPDIR_LOCK/aicrew-lock-s"; echo 999999 > "$TMPDIR_LOCK/aicrew-lock-s/pid"; LK s --wait 2 -- true; ok "lock.sh: kunci basi (proses mati) diambil alih" "$?" 0
echo '- [ ] #1 x' > "$FAKE/epicbody.txt"; EL 20 6 >/dev/null
ok "epic-link: sub-issue native memakai id numerik, bukan nomor" "$(grep -c 'sub_issues -F sub_issue_id=1006' "$FAKE/calls")" 1
ok "epic-link: daftar centang ikut ditambahkan" "$(grep -c '^- \[ \] #6' "$FAKE/calls")" 1
echo '- [ ] #6 sudah' > "$FAKE/epicbody.txt"; EL 20 6 >/dev/null
ok "epic-link: idempoten untuk daftar centang" "$(grep -c 'issue edit' "$FAKE/calls")" 0
echo 20 > "$FAKE/parent.txt"; echo '- [ ] #1 x' > "$FAKE/epicbody.txt"; EL --inherit 5 9 >/dev/null
ok "epic-link --inherit: anak baru masuk epic induk sumber (native)" "$(grep -c 'sub_issues -F sub_issue_id=1009' "$FAKE/calls")" 1
rm "$FAKE/parent.txt"; echo '[{"number":20,"body":"- [ ] #5 a"}]' > "$FAKE/epics.json"; EL --inherit 5 10 >/dev/null
ok "epic-link --inherit: cadangan lewat daftar centang epic" "$(grep -c 'sub_issues -F sub_issue_id=1010' "$FAKE/calls")" 1
echo '[]' > "$FAKE/epics.json"; EL --inherit 5 11 >/dev/null; ok "epic-link --inherit: sumber yatim -> exit 3" "$?" 3
# workflow.sh: cabang integrasi lebih baru dari checkout aktif
W="$tmp/ec/wf"; mkdir -p "$W/o" "$W/c"; git init -q --bare "$W/o/r.git"; git clone -q "$W/o/r.git" "$W/c/r" 2>/dev/null
( cd "$W/c/r" && git config user.email t@t && git config user.name t && mkdir docs && printf -- 'Cabang integrasi: feat-int\nLama\n' > docs/WORKFLOW.md && git add . && git commit -qm a && git branch -M main && git push -q origin main \
  && git checkout -qb feat-int && printf -- 'Cabang integrasi: feat-int\nBaru\n' > docs/WORKFLOW.md && git commit -qam b && git push -q origin feat-int && git checkout -q main )
ok "workflow.sh: membaca versi cabang integrasi, bukan main yang basi" "$(cd "$W/c/r" && bash "$root/scripts/workflow.sh" | grep -c Baru)" 1
V="$tmp/ec/wf2"; mkdir -p "$V/o" "$V/c"; git init -q --bare "$V/o/r.git"; git clone -q "$V/o/r.git" "$V/c/r" 2>/dev/null
( cd "$V/c/r" && git config user.email t@t && git config user.name t && mkdir docs && printf -- '3. Cabang integrasi: int.v2. Issue yang saling bergantung\nLama\n' > docs/WORKFLOW.md && git add . && git commit -qm a && git branch -M main && git push -q origin main \
  && git checkout -qb int.v2 && printf -- '3. Cabang integrasi: int.v2. Issue yang saling bergantung\nBaru\n' > docs/WORKFLOW.md && git commit -qam b && git push -q origin int.v2 && git checkout -q main )
ok "workflow.sh: titik penutup kalimat tidak ikut nama cabang (titik di tengah tetap)" "$(cd "$V/c/r" && bash "$root/scripts/workflow.sh" | grep -c Baru)" 1
ok "workflow.sh: tanpa cabang integrasi -> berkas lokal" "$(cd "$tmp/ec/w" && printf 'Halo\n' > docs/WORKFLOW.md && bash "$root/scripts/workflow.sh")" Halo
grep -q 'epic-link.sh' skills/breakdown/SKILL.md && grep -q 'epic-link.sh --inherit' skills/orchestrate/SKILL.md && grep -q 'Tutup issue setelah merge integrasi' templates/WORKFLOW.md && grep -q 'sub-issue native' README.md; ok "0.6.0: skill, templat WORKFLOW dan README menyebut epic-link/inherit/tutup issue" $? 0
grep -q 'Konsep (0.6.1)' README.md && grep -q 'Parent issue' README.md && grep -q 'Parent issue' scripts/board-init.sh && grep -q 'epic-link.sh --check' skills/orchestrate/SKILL.md; ok "0.6.1: README konsep, langkah UI manual, skill menyebut --check" $? 0
grep -q 'lock.sh' skills/orchestrate/SKILL.md && grep -q 'Label tanpa induk' templates/WORKFLOW.md && grep -q 'lock.sh' README.md; ok "0.6.3: skill, templat WORKFLOW dan README menyebut lock.sh dan tanpa-induk" $? 0
# 4d. journey otomatis: skill prd menggali journey saat diskusi; breakdown mengusulkan journey bila PRD belum punya
cd "$root" || exit 1
grep -q 'Journeys' skills/prd/SKILL.md && grep -q 'infrastruktur' skills/prd/SKILL.md && grep -qi 'apa yang bisa dilakukan pengguna' skills/prd/SKILL.md; ok "prd: menggali journey, tiap kebutuhan masuk journey atau infrastruktur" $? 0
grep -q 'Bila PRD belum punya Journeys' skills/breakdown/SKILL.md && grep -q 'Usulan journey' skills/breakdown/SKILL.md && grep -qi 'persetujuan owner' skills/breakdown/SKILL.md; ok "breakdown: mengusulkan journey dari kebutuhan dan issue lama, minta persetujuan" $? 0
! grep -q 'bila PRD punya bagian Journeys' skills/breakdown/SKILL.md; ok "breakdown: epic tidak lagi dilewati diam-diam tanpa Journeys" $? 0
cd "$root" || exit 1

# 3i. scripts/ghx.sh: deteksi batas GraphQL dan cadangan REST (gh palsu, tanpa jaringan)
mkdir -p "$tmp/rl/bin" "$tmp/rl/w"; git init -q "$tmp/rl/w"; cat > "$tmp/rl/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$1" in issue|project|repo|pr) [ "${GHX_SIM:-0}" = 1 ] && { echo "GraphQL: API rate limit already exceeded for user ID 1" >&2; exit 1; } ;; esac
[ "${ERR404:-0}" = 1 ] && case "$1" in issue|project|repo|pr) echo "HTTP 404: Not Found" >&2; exit 1 ;; esac
case "$*" in
  "repo view"*) echo o/viewed ;;
  "api users/o -q"*) echo "${OWNER_TYPE:-User}" ;;
  "api graphql"*) printf 'HTTP/2.0 200 OK\nX-Ratelimit-Remaining: %s\n' "${REMAINING:-0}"; [ "${NORESET:-0}" = 1 ] || echo 'X-Ratelimit-Reset: 1793490517' ;;
  "issue list"*) echo '[]' ;;
  "api repos/o/r/issues?"*) [ "${RESTFAIL:-0}" = 1 ] && { echo "HTTP 500" >&2; exit 1; }
    a="$*"; p="${a##*page=}"; p="${p%%&*}"; f="$FAKE/issues.json"; case "$a" in *labels=epic*) [ -f "$FAKE/issues-epic.json" ] && f="$FAKE/issues-epic.json" ;; esac
    jq -c ".[$(((p-1)*100)):$((p*100))]" "$f" ;;
  "api repos/o/r/issues/"*"/parent"*) echo "HTTP 404: Not Found" >&2; exit 1 ;;
  "api repos/o/r/issues/7") cat "$FAKE/issue7.json" ;;
  "api repos/o/r/issues/"[59]) a="$*"; n="${a##*/}"; echo "{\"id\":${n}000,\"body\":\"\"}" ;;
  "project item-list"*) echo '{"items":[]}' ;;
  "project view"*) echo PID ;;
  "project field-list"*) echo '{"fields":[{"name":"Status","id":"F1","options":[{"name":"Done","id":"OD"}]}]}' ;;
  "project item-add"*) echo '{"id":"PVTI_new"}' ;;
  "api "*"/projectsV2/3/"*) [ -n "${PROJ_ERR:-}" ] && { echo "gh: Not Found (HTTP $PROJ_ERR)" >&2; echo '{"message":"Not Found"}'; exit 1; }
    case "$*" in
      *"/fields"*) cat "$FAKE/fields.json" ;;
      *"/items?"*) a="$*"; p="${a##*page=}"; p="${p%%&*}"; jq -c ".[$(((p-1)*100)):$((p*100))]" "$FAKE/pitems.json" ;;
      "api -X POST "*) case "$(cat "$FAKE/postmode" 2>/dev/null)" in
        exists) echo "gh: Content already exists in this project (HTTP 422)" >&2; echo '{"message":"Content already exists in this project"}'; exit 1 ;;
        other) echo "gh: Validation Failed (HTTP 422)" >&2; echo '{"message":"Validation Failed"}'; exit 1 ;;
        *) echo '{"id":555}' ;; esac ;;
      "api -X PATCH "*) cat > "$FAKE/patch.json"; echo '{}' ;;
    esac ;;
  "api -X "*) for a in "$@"; do case "$a" in body=*) printf '%s' "${a#body=}" > "$FAKE/body.out"
    case "$*" in "api -X PATCH repos/o/r/issues/7"*) jq -n --arg b "${a#body=}" '{body:$b}' > "$FAKE/issue7.json" ;; esac ;; esac; done ;;
esac
EOF
chmod +x "$tmp/rl/bin/gh"; export FAKE="$tmp/rl"; : > "$FAKE/calls"
RL() { (cd "$tmp/rl/w" && PATH="$tmp/rl/bin:$PATH" bash -c 'source "$1/scripts/ghx.sh" || exit 99; shift; "$@"' _ "$root" "$@"); }
r=""; for t in "GraphQL: API rate limit already exceeded" "RATE_LIMIT" "graphql_rate_limit" "Unknown owner type"; do RL ghx_is_limit "$t" 2>/dev/null; r="$r$?"; done
ok "ghx_is_limit: 4 teks pemicu" "$r" 0000
RL ghx_is_limit "HTTP 404: Not Found" 2>/dev/null; ok "ghx_is_limit: 404 bukan batas" $? 1
ok "ghx_repo: GH_REPO menang" "$(export GH_REPO=x/y; RL ghx_repo 2>/dev/null)" x/y
git -C "$tmp/rl/w" remote add origin git@github.com:a/b.git; ok "ghx_repo: batas -> remote ssh" "$(export GHX_SIM=1; RL ghx_repo 2>/dev/null)" a/b
git -C "$tmp/rl/w" remote set-url origin https://github.com/a/b; ok "ghx_repo: batas -> remote https" "$(export GHX_SIM=1; RL ghx_repo 2>/dev/null)" a/b
git -C "$tmp/rl/w" remote set-url origin https://github.com/a/b.git; ok "ghx_repo: batas -> remote https .git" "$(export GHX_SIM=1; RL ghx_repo 2>/dev/null)" a/b
ok "ghx_repo: tanpa batas -> gh repo view (perilaku lama), remote origin diabaikan" "$(RL ghx_repo 2>/dev/null)" o/viewed
git -C "$tmp/rl/w" remote set-url origin git@github.com-work:a/b.git; ok "ghx_repo: batas -> remote dengan alias host" "$(export GHX_SIM=1; RL ghx_repo 2>/dev/null)" a/b
git -C "$tmp/rl/w" remote remove origin; ok "ghx_repo: tanpa remote -> gh repo view" "$(RL ghx_repo 2>/dev/null)" o/viewed
(export GHX_SIM=1; RL ghx_repo >/dev/null 2>&1); ok "ghx_repo: batas tanpa remote -> exit non-0" $? 1
ok "ghx_gql: sukses meneruskan stdout" "$(RL ghx_gql gh issue list --json number 2>/dev/null)" '[]'
ok "ghx_gql: batas -> exit 75 dan GHX_REST=1" "$(export GHX_SIM=1; RL eval 'ghx_gql gh issue list; echo "rc=$? rest=${GHX_REST:-0}"' 2>/dev/null)" "rc=75 rest=1"
(export GHX_SIM=1; RL ghx_gql gh issue list >/dev/null 2>"$tmp/rl/err"); ok "ghx_gql: satu baris pengumuman" "$(grep -c 'mode cadangan REST' "$tmp/rl/err")" 1
ok "ghx_gql: 404 -> exit asli, GHX_REST tidak diset" "$(export ERR404=1; RL eval 'ghx_gql gh issue list; echo "rc=$? rest=${GHX_REST:-0}"' 2>/dev/null)" "rc=1 rest=0"
ok "ghx_reset_time: epoch 1793490517 -> 23:48:37" "$(RL ghx_reset_time 2>/dev/null)" 23:48:37
ok "ghx_owner_base: User" "$(RL ghx_owner_base o 2>/dev/null)" users/o
ok "ghx_owner_base: Organization" "$(export OWNER_TYPE=Organization; RL ghx_owner_base o 2>/dev/null)" orgs/o
ok "ghx_explain_limit: Remaining 0 -> penyebab dan jam reset" "$(RL ghx_explain_limit 2>/dev/null | grep -c 'batas GraphQL GitHub habis; reset 23:48:37 UTC')" 1
ok "ghx_explain_limit: Remaining > 0 -> diam" "$(export REMAINING=7; RL ghx_explain_limit 2>/dev/null)" ""

# 3i-2. ghx: operasi issue (GraphQL identik; batas -> REST sekali)
git -C "$tmp/rl/w" remote add origin https://github.com/o/r.git
jq -n '[range(1;151)|{number:.,title:"t\(.)",body:(if .%7==0 then null else "b" end),state:"open",labels:[{name:"epic"}]}+(if .%5==0 then {pull_request:{url:"x"}} else {} end)]' > "$FAKE/issues.json"
echo '{"body":null}' > "$FAKE/issue7.json"
: > "$FAKE/calls"; RL ghx_issues open epic 100 number,body >/dev/null 2>&1
ok "ghx_issues: tanpa batas = panggilan identik" "$(grep -c '^issue list --state open --label epic --limit 100 --json number,body$' "$FAKE/calls")" 1
R="$(export GHX_SIM=1; RL ghx_issues open epic 100 number,body 2>/dev/null)"
ok "ghx_issues: batas -> REST tepat limit, tanpa PR" "$(jq 'length' <<<"$R")/$(jq '[.[]|select(.number%5==0)]|length' <<<"$R")" 100/0
ok "ghx_issues: REST state huruf besar" "$(jq -r '.[0].state' <<<"$R")" OPEN
ok "ghx_issues: REST body null -> teks kosong" "$(jq -c '[.[]|select(.number==7)|.body]' <<<"$R")" '[""]'
: > "$FAKE/calls"; (export GHX_SIM=1; RL eval 'set -euo pipefail; a="$(ghx_issues open epic 100 number,body)"; b="$(ghx_issues open epic 100 number,body)"; :' >/dev/null 2>&1)
ok "ghx_issues: setelah batas (di bawah set -e), panggilan berikutnya tidak memanggil 'issue list'" "$(grep -c '^issue list' "$FAKE/calls")" 1
: > "$FAKE/calls"; (export GHX_SIM=1 RESTFAIL=1; RL ghx_issues open epic 100 number,body >/dev/null 2>&1); rc=$?
ok "ghx_issues: REST juga gagal -> exit non-0 tanpa loop" "$([ $rc != 0 ] && echo gagal)/$(grep -c '^api repos/o/r/issues?' "$FAKE/calls")" gagal/1
: > "$FAKE/calls"; (export ERR404=1; RL ghx_issues open epic 100 number,body >/dev/null 2>&1); rc=$?
ok "ghx_issues: 404 bukan batas -> tanpa fallback REST" "$([ $rc != 0 ] && echo gagal)/$(grep -c '^api repos' "$FAKE/calls")" gagal/0
ok "ghx_issue_body: REST body null -> teks kosong, bukan 'null'" "$(export GHX_SIM=1; RL ghx_issue_body 7 2>/dev/null)" ""
echo '{"body":"abc"}' > "$FAKE/issue7.json"; ok "ghx_issue_body: REST teks" "$(export GHX_SIM=1; RL ghx_issue_body 7 2>/dev/null)" abc
B='a "q" $HOME `x`'$'\n''- [ ] #5'
(export GHX_SIM=1; RL ghx_issue_set_body 7 "$B" >/dev/null 2>&1); ok "ghx_issue_set_body: badan utuh via REST" "$(cat "$FAKE/body.out")" "$B"
: > "$FAKE/calls"; (export GHX_SIM=1; RL ghx_issue_close 7 "Sudah masuk" >/dev/null 2>&1)
ok "ghx_issue_close: REST = komentar lalu tutup" "$(grep -E '^api -X (POST|PATCH) repos/o/r/issues/7' "$FAKE/calls" | awk '{print $3}' | tr '\n' ' ')" "POST PATCH "

# 3i-3. epic-link.sh memakai pustaka: GraphQL diblokir -> REST
jq -n '[{number:1,title:"E",body:"- [ ] #3",state:"open",labels:[{name:"epic"}]},{number:2,title:"orfan",body:"",state:"open",labels:[]},{number:3,title:"anak",body:"",state:"open",labels:[]}]' > "$FAKE/issues.json"; jq -c '[.[0]]' "$FAKE/issues.json" > "$FAKE/issues-epic.json"
out="$(cd "$tmp/rl/w" && GHX_SIM=1 PATH="$tmp/rl/bin:$PATH" bash "$root/scripts/epic-link.sh" --check 2>/dev/null)"; rc=$?
ok "epic-link --check: GraphQL diblokir -> yatim lewat REST, exit 3" "$rc|$out" "3|yatim: #2 orfan"
echo '{"body":"- [ ] #4"}' > "$FAKE/issue7.json"
out="$(cd "$tmp/rl/w" && GHX_SIM=1 PATH="$tmp/rl/bin:$PATH" bash "$root/scripts/epic-link.sh" 7 9 2>/dev/null)"
ok "epic-link <epic> <anak>: GraphQL diblokir -> daftar centang lewat REST" "$out|$(jq -r .body "$FAKE/issue7.json" | tail -1)" "epic-link: #9 -> epic #7|- [ ] #9"

# 3i-4. ghx: operasi kartu project (GraphQL identik; batas -> REST; id GraphQL string vs REST angka)
FU='[{"id":434173138,"name":"Title","data_type":"title"},{"id":434173140,"name":"Status","data_type":"single_select","options":[{"id":"f75ad846","name":"Backlog"},{"id":"df73e18b","name":"In review"},{"id":"98236657","name":"Done"}]}]'
FO='[{"id":434173138,"name":{"html":"Title","raw":"Title"}},{"id":434173140,"name":{"html":"Status","raw":"Status"},"options":[{"id":"f75ad846","name":{"html":"Backlog","raw":"Backlog"}},{"id":"df73e18b","name":{"html":"In review","raw":"In review"}},{"id":"98236657","name":{"html":"Done","raw":"Done"}}]}]'
echo "$FU" > "$FAKE/fields.json"
echo '[{"id":285528753,"node_id":"PVTI_x","content_type":"Issue","content":{"number":5},"fields":[{"id":434173140,"value":{"id":"df73e18b","name":{"html":"In review","raw":"In review"}}}]},{"id":285528754,"node_id":"PVTI_y","content_type":"Issue","content":{"number":6},"fields":[]}]' > "$FAKE/pitems.json"
: > "$FAKE/calls"; ok "ghx_items: tanpa batas = panggilan identik" "$(RL ghx_items o 3 2>/dev/null)|$(grep -c '^project item-list 3 --owner o --limit 200 --format json$' "$FAKE/calls")" '{"items":[]}|1'
ok "ghx_items: REST user (nama kolom string)" "$(export GHX_SIM=1; RL ghx_items o 3 2>/dev/null | jq -c '[.items[]|[.content.number,.content.type,.status]]')" '[[5,"Issue","In review"],[6,"Issue",null]]'
echo "$FO" > "$FAKE/fields.json"
: > "$FAKE/calls"; (export GHX_SIM=1 OWNER_TYPE=Organization; RL ghx_items o 3 >/dev/null 2>&1); ok "ghx_items: REST meminta Status dengan fields[]=<id> (bentuk dokumentasi, teruji di org)" "$(grep -c 'items?per_page=100&fields\[\]=434173140&page=1' "$FAKE/calls")" 1
ok "ghx_items: REST org (nama kolom {raw})" "$(export GHX_SIM=1 OWNER_TYPE=Organization; RL ghx_items o 3 2>/dev/null | jq -c '[.items[]|[.content.number,.status]]')" '[[5,"In review"],[6,null]]'
ok "ghx_status_field: REST org, opsi dinormalkan" "$(export GHX_SIM=1 OWNER_TYPE=Organization; RL ghx_status_field o 3 2>/dev/null | jq -c '[.id,(.options|map(.name))]')" '[434173140,["Backlog","In review","Done"]]'
echo "$FU" > "$FAKE/fields.json"
ok "ghx_status_field: REST user, opsi dinormalkan" "$(export GHX_SIM=1; RL ghx_status_field o 3 2>/dev/null | jq -c '[.id,(.options|map(.name))]')" '[434173140,["Backlog","In review","Done"]]'
ok "ghx_status_field: GraphQL = panggilan identik" "$(RL ghx_status_field o 3 2>/dev/null | jq -r .id)" F1
: > "$FAKE/calls"; ok "ghx_card_add: GraphQL = item-add identik" "$(RL ghx_card_add o 3 5 2>/dev/null)|$(grep -c '^project item-add 3 --owner o --url https://github.com/o/viewed/issues/5 --format json$' "$FAKE/calls")" 'PVTI_new|1'
: > "$FAKE/calls"; rm -f "$FAKE/postmode"
ok "ghx_card_add: REST sukses, id kartu dari respons" "$(export GHX_SIM=1; RL ghx_card_add o 3 9 2>/dev/null)" 555
ok "ghx_card_add: REST memakai id NUMERIK issue" "$(grep -c -- '-X POST users/o/projectsV2/3/items -f type=Issue -F id=9000' "$FAKE/calls")" 1
echo exists > "$FAKE/postmode"
ok "ghx_card_add: 422 already exists = sukses, id dari daftar" "$(export GHX_SIM=1; RL ghx_card_add o 3 5 2>/dev/null)" 285528753
echo other > "$FAKE/postmode"; (export GHX_SIM=1; RL ghx_card_add o 3 5 >/dev/null 2>&1); rc=$?
ok "ghx_card_add: 422 selain already exists -> exit non-0" "$([ $rc != 0 ] && [ $rc != 78 ] && echo gagal)" gagal
rm -f "$FAKE/postmode"
(export GHX_SIM=1; RL ghx_card_set o 3 285528753 434173140 df73e18b >/dev/null 2>&1)
ok "ghx_card_set: REST body PATCH persis" "$(jq -c . "$FAKE/patch.json")" '{"fields":[{"id":434173140,"value":"df73e18b"}]}'
: > "$FAKE/calls"; rm -f "$FAKE/patch.json"; (export GHX_SIM=1; RL ghx_card_set o 3 PVTI_x PVTSSF_abc df73e18b >/dev/null 2>&1)
ok "ghx_card_set: id GraphQL (string) diterjemahkan ke id REST" "$(grep -c -- '-X PATCH users/o/projectsV2/3/items/285528753' "$FAKE/calls")|$(jq -c '.fields[0].id' "$FAKE/patch.json")" '1|434173140'
: > "$FAKE/calls"; ok "ghx_card_set: GraphQL = project view lalu item-edit" "$(RL ghx_card_set o 3 PVTI_x F1 OD >/dev/null 2>&1; grep -cE '^project (view 3 --owner o --format json -q .id|item-edit --id PVTI_x --project-id PID --field-id F1 --single-select-option-id OD)$' "$FAKE/calls")" 2
(export GHX_SIM=1 PROJ_ERR=404; RL ghx_items o 3 >/dev/null 2>"$tmp/rl/err"); rc=$?
ok "ghx_items: REST kartu 404 -> exit 77 dengan petunjuk scope project" "$rc|$(grep -c "scope 'project'" "$tmp/rl/err")" '77|1'

# 3i-5. board.sh memakai pustaka: batas -> REST; langkah khusus GraphQL dilewati dengan PERINGATAN
mkdir -p "$tmp/rl/w/docs"; BD() { (cd "$tmp/rl/w" && PATH="$tmp/rl/bin:$PATH" bash "$root/scripts/board.sh" "$@"); }
printf -- '- Kartu Done: agen-setelah-merge.\n' > "$tmp/rl/w/docs/WORKFLOW.md"
: > "$FAKE/calls"; rm -f "$FAKE/patch.json" "$FAKE/body.out"
(export GHX_SIM=1; BD o 3 --sync >"$tmp/rl/out" 2>"$tmp/rl/err"); rc=$?
ok "board --sync: batas -> exit 0, status epic dipindah lewat REST (Backlog)" "$rc|$(jq -c '.fields[0].value' "$FAKE/patch.json" 2>/dev/null)" '0|"f75ad846"'
ok "board --sync: batas -> PERINGATAN 1 langkah dilewati" "$(grep -c 'PERINGATAN: 1 langkah dilewati (batas GraphQL), jalankan --sync lagi setelah reset' "$tmp/rl/err")" 1
ok "board --sync: anak proses tidak memanggil GraphQL lagi (hanya satu percobaan 'project')" "$(grep -c '^project ' "$FAKE/calls")" 1
ok "board --sync: komentar progres epic tetap ditulis" "$(cat "$FAKE/body.out")" $'<!-- aicrew-progress -->\naicrew-progress: 0/1 Done'
: > "$FAKE/calls"; (BD o 3 --sync >"$tmp/rl/out" 2>"$tmp/rl/err"); rc=$?
ok "board --sync: tanpa batas -> exit 0 tanpa PERINGATAN" "$rc|$(grep -c PERINGATAN "$tmp/rl/err")" '0|0'
printf -- '- Kartu Done: agen-setelah-merge.\n- Tutup issue setelah merge integrasi: ya\n' > "$tmp/rl/w/docs/WORKFLOW.md"
: > "$FAKE/calls"; rm -f "$FAKE/patch.json"
(export GHX_SIM=1 PROJ_ERR=404; BD o 3 --sync >"$tmp/rl/out" 2>"$tmp/rl/err"); rc=$?
ok "board --sync: REST kartu 404 -> exit 0, 2 langkah dilewati, tidak ada PATCH kartu, tutup issue di-integrasi tetap jalan" "$rc|$(grep -c 'PERINGATAN: 2 langkah dilewati' "$tmp/rl/err")|$([ -e "$FAKE/patch.json" ] && echo patch || echo nopatch)|$(grep -c 'PATCH repos/o/r/issues/[23] -f state=closed' "$FAKE/calls")|$(grep -c -- '-X POST repos/o/r/issues/1/comments' "$FAKE/calls")" '0|1|nopatch|2|0'
ok "board <owner> <n> <issue> Done: batas -> PATCH opsi Done via REST" "$(export GHX_SIM=1; BD o 3 5 Done 2>/dev/null)|$(jq -c '.fields[0].value' "$FAKE/patch.json")" 'board: #5 -> Done|"98236657"'
(export GHX_SIM=1 PROJ_ERR=403; BD o 3 5 Done >/dev/null 2>"$tmp/rl/err"); rc=$?
ok "board <owner> <n> <issue> Done: REST kartu 403 -> exit non-0 dengan petunjuk scope" "$([ $rc != 0 ] && echo gagal)|$(grep -c "scope 'project'" "$tmp/rl/err")" 'gagal|1'

# 3i-6. pr-merge-check.sh: tetap menolak saat GraphQL habis, tetapi menjelaskan penyebab dan jam reset
PM() { (cd "$tmp/rl/w" && PATH="$tmp/rl/bin:$PATH" bash "$root/scripts/pr-merge-check.sh" 15 main 2>&1); }
out="$(export GHX_SIM=1; PM)"; rc=$?
ok "pr-merge-check: GraphQL habis -> exit 1, GAGAL, batas GraphQL, jam reset" "$rc|$(grep -c '^GAGAL' <<<"$out")|$(grep -c 'batas GraphQL GitHub habis; reset 23:48:37 UTC' <<<"$out")" '1|1|1'
out="$(export GHX_SIM=1 NORESET=1; PM)"; rc=$?
ok "pr-merge-check: header reset hilang -> tetap menolak, pesan batas tanpa jam" "$rc|$(grep -c 'batas GraphQL GitHub habis\. Tunggu' <<<"$out")|$(grep -c 'reset 23' <<<"$out")" '1|1|0'
out="$(export REMAINING=7; PM)"; rc=$?
ok "pr-merge-check: kegagalan biasa (basis salah) -> tanpa baris Penyebab" "$rc|$(grep -c '^GAGAL: basis' <<<"$out")|$(grep -c '^Penyebab' <<<"$out")" '1|1|0'

# 3i-7. README menjelaskan mode cadangan REST dan perilakunya
grep -q 'mode cadangan REST' README.md && grep -q 'langkah dilewati' README.md; ok "README: mode cadangan REST dan PERINGATAN langkah dilewati" $? 0

# 3i-8. perbaikan hasil review akhir
jq -n '[range(1;101)|{number:.,title:"t",body:("x"*12000),state:"open",labels:[]}]' > "$FAKE/issues.json"
R="$(export GHX_SIM=1; RL ghx_issues open - 100 number,body 2>/dev/null)"
ok "ghx_issues: halaman REST >1 MB tidak melewati batas argumen" "$(jq 'length' <<<"$R" 2>/dev/null)" 100
jq -n '[range(1;101)|{id:.,node_id:"n\(.)",content_type:"Issue",content:{number:.},fields:[{id:434173140,value:{name:{raw:"Done"}}}],pad:("x"*12000)}]' > "$FAKE/pitems.json"; echo "$FU" > "$FAKE/fields.json"
ok "ghx_items: halaman REST >1 MB" "$(export GHX_SIM=1; RL ghx_items o 3 2>/dev/null | jq '.items|length')" 100
ok "ghx: GHX_STATE tidak berbasis PID" "$(RL eval 'case "$GHX_STATE" in *.$$) echo pid ;; *) echo acak ;; esac')" acak
D="$(mktemp -d)"; (export TMPDIR="$D" GHX_SIM=1; RL ghx_gql gh issue list >/dev/null 2>&1; PM >/dev/null 2>&1)
ok "ghx: tidak ada berkas status tersisa" "$(ls "$D" | wc -l | tr -d ' ')" 0; rm -rf "$D"

# 3j-1. cve-check.sh --list: pengurai lockfile (tanpa jaringan)
mkdir -p "$tmp/cve"; CV="bash $root/scripts/cve-check.sh"
cat > "$tmp/cve/package-lock.json" <<'EOF'
{"lockfileVersion":3,"packages":{"":{"name":"x"},"node_modules/lodash":{"version":"4.17.15"},"node_modules/@scope/pkg":{"version":"1.2.3"},"node_modules/a/node_modules/lodash":{"version":"3.0.0"},"node_modules/jest":{"version":"29.0.0","dev":true},"node_modules/ln":{"link":true}}}
EOF
L() { $CV --list "$1" 2>"$tmp/cve/err" | tr '\t' ':' | paste -sd'|' -; }
ok "cve --list npm: nama dari node_modules terdalam, dev:true -> dev, link dilewati" "$(L "$tmp/cve/package-lock.json")" 'npm:@scope/pkg:1.2.3:prod|npm:jest:29.0.0:dev|npm:lodash:3.0.0:prod|npm:lodash:4.17.15:prod'
echo '{"lockfileVersion":1,"dependencies":{"a":{"version":"1.0.0"}}}' > "$tmp/cve/v1/package-lock.json" 2>/dev/null || { mkdir -p "$tmp/cve/v1"; echo '{"lockfileVersion":1,"dependencies":{"a":{"version":"1.0.0"}}}' > "$tmp/cve/v1/package-lock.json"; }
ok "cve --list npm lockfileVersion 1 -> kosong + 'tidak lengkap'" "$(L "$tmp/cve/v1/package-lock.json")|$(grep -c 'tidak lengkap' "$tmp/cve/err")" '|1'
mkdir -p "$tmp/cve/go"; printf 'module example.com/m\n\ngo 1.21\n\nrequire (\n\tgolang.org/x/net v0.7.0\n\t// komentar\n\tgithub.com/pkg/errors v0.9.1 // indirect\n)\n\nrequire github.com/google/uuid v1.3.0\n' > "$tmp/cve/go/go.mod"
ok "cve --list go.mod: blok dan baris tunggal, awalan v dibuang, indirect tetap prod" "$(L "$tmp/cve/go/go.mod")" 'Go:github.com/google/uuid:1.3.0:prod|Go:github.com/pkg/errors:0.9.1:prod|Go:golang.org/x/net:0.7.0:prod'
mkdir -p "$tmp/cve/py"; printf '# komentar\nDjango==3.0\nrequests[security]==2.0.0 --hash=sha256:abc\nFlask_Login==0.5.0 ; python_version > "3"\nnumpy>=1.0\n-r other.txt\ngit+https://example.com/x.git#egg=x\n' > "$tmp/cve/py/requirements.txt"
ok "cve --list requirements: nama==versi, extras/hash dibuang, bentuk lain dilewati dan dihitung" "$(L "$tmp/cve/py/requirements.txt")|$(grep -c 'tidak lengkap: 3 baris' "$tmp/cve/err")" 'PyPI:django:3.0:prod|PyPI:flask-login:0.5.0:prod|PyPI:requests:2.0.0:prod|1'
printf 'pytest==7.0.0\n' > "$tmp/cve/py/requirements-dev.txt"; ok "cve --list requirements-dev.txt -> lingkup dev" "$(L "$tmp/cve/py/requirements-dev.txt")" 'PyPI:pytest:7.0.0:dev'
echo "gem 'rails'" > "$tmp/cve/Gemfile"; $CV --list "$tmp/cve/Gemfile" >/dev/null 2>&1; ok "cve --list Gemfile -> exit 64" $? 64

# 3j-2. cve-check.sh: kueri OSV (curl palsu), pengelompokan alias, severity, kode keluar
export CVE_FIX="$tmp/cve/fix"; mkdir -p "$CVE_FIX" "$tmp/cve/bin" "$tmp/cve/w"
cat > "$tmp/cve/bin/curl" <<'EOF'
#!/usr/bin/env bash
d=""; while [ $# -gt 0 ]; do [ "$1" = -d ] && { d="$2"; break; }; shift; done
[ "${CVE_DOWN:-0}" = 1 ] && exit 7
[ "${CVE_HTTP:-0}" != 0 ] && exit "$CVE_HTTP"
e="$(jq -r .package.ecosystem <<<"$d")"; n="$(jq -r .package.name <<<"$d")"; v="$(jq -r .version <<<"$d")"; t="$(jq -r '.page_token // ""' <<<"$d")"
echo "$e $n $v $t" >> "$CVE_FIX/calls"; [ -n "${CVE_SLOW:-}" ] && sleep "$CVE_SLOW"
k="$(printf '%s_%s_%s' "$e" "$n" "$v" | tr '/@' '__')"; f="$CVE_FIX/$k${t:+.$t}.json"
if [ -f "$f" ]; then cat "$f"; else echo '{}'; fi
EOF
chmod +x "$tmp/cve/bin/curl"
FX() { printf '%s' "$4" > "$CVE_FIX/$(printf '%s_%s_%s' "$1" "$2" "$3" | tr '/@' '__').json"; }   # eco nama versi json
CK() { (PATH="$tmp/cve/bin:$PATH" $CV "$@"); }
LOCK() { jq -n --arg n "$1" --arg v "$2" --argjson d "${3:-false}" '{lockfileVersion:3,packages:{"":{},("node_modules/"+$n):({version:$v}+(if $d then {dev:true} else {} end))}}' > "$tmp/cve/w/package-lock.json"; }   # nome versao [dev]
V() { jq -nc --arg id "$1" --arg al "$2" --arg sv "$3" '{id:$id,aliases:($al|split(",")|map(select(.!=""))),database_specific:(if $sv=="" then {} else {severity:$sv} end)}'; }   # id aliases severity
: > "$CVE_FIX/calls"; LOCK lodash 4.17.15
out="$(CK "$tmp/cve/w/package-lock.json" 2>/dev/null)"; ok "cve: bersih -> exit 0, tanpa keluaran" "$?|$out" '0|'
FX npm lodash 4.17.15 "{\"vulns\":[$(V GHSA-aaaa-1111-bbbb CVE-2020-28500 HIGH)]}"
out="$(CK "$tmp/cve/w/package-lock.json" 2>/dev/null)"; rc=$?; ok "cve: HIGH prod -> exit 1 dan baris 9 kolom persis" "$rc|$(tr '\t' '|' <<<"$out")" '1|lodash|4.17.15|GHSA-aaaa-1111-bbbb|CVE-2020-28500|HIGH|prod|-|tanpa-perbaikan|baru'
LOCK @scope/pkg 1.2.3; FX npm @scope/pkg 1.2.3 "{\"vulns\":[$(V GHSA-cccc-2222-dddd CVE-2021-1 CRITICAL)]}"
out="$(CK "$tmp/cve/w/package-lock.json" 2>/dev/null)"; rc=$?; ok "cve: nama berskop @scope/pkg -> kueri dan keluaran benar" "$rc|$(cut -f1,5 <<<"$out" | tr '\t' '|')" '1|@scope/pkg|CRITICAL'
mkdir -p "$tmp/cve/w/go"; printf 'module m\n\nrequire golang.org/x/net v0.7.0\n' > "$tmp/cve/w/go/go.mod"
FX Go golang.org/x/net 0.7.0 "{\"vulns\":[$(V GO-2023-1988 GHSA-2wrh-6pvc-2jm9,CVE-2023-39325 ""),$(V GHSA-2wrh-6pvc-2jm9 CVE-2023-39325 HIGH)]}"
out="$(CK "$tmp/cve/w/go/go.mod" 2>/dev/null)"; rc=$?; ok "cve: GO- tanpa severity memakai kembaran GHSA, satu baris, path Go" "$rc|$(grep -c . <<<"$out")|$(cut -f1,3,4,5 <<<"$out" | tr '\t' '|')" '1|1|golang.org/x/net|GHSA-2wrh-6pvc-2jm9|CVE-2023-39325|HIGH'
mkdir -p "$tmp/cve/w/py"; printf 'oldlib==1.0\n' > "$tmp/cve/w/py/requirements.txt"; FX PyPI oldlib 1.0 "{\"vulns\":[$(V PYSEC-2020-1 CVE-2020-9 "")]}"
out="$(CK "$tmp/cve/w/py/requirements.txt" 2>/dev/null)"; rc=$?; ok "cve: tanpa kembaran -> UNKNOWN dan exit 1" "$rc|$(cut -f5 <<<"$out")" '1|UNKNOWN'
LOCK midlib 2.0; FX npm midlib 2.0 "{\"vulns\":[$(V GHSA-eeee-3333-ffff CVE-2022-2 MODERATE)]}"
out="$(CK "$tmp/cve/w/package-lock.json" 2>/dev/null)"; rc=$?; ok "cve: MODERATE prod -> exit 0 dengan baris" "$rc|$(cut -f5 <<<"$out")" '0|MODERATE'
LOCK devlib 3.0 true; FX npm devlib 3.0 "{\"vulns\":[$(V GHSA-gggg-4444-hhhh CVE-2022-3 HIGH)]}"
out="$(CK "$tmp/cve/w/package-lock.json" 2>/dev/null)"; rc=$?; ok "cve: HIGH dev -> exit 0 dengan baris" "$rc|$(cut -f5,6 <<<"$out" | tr '\t' '|')" '0|HIGH|dev'
LOCK lodash 4.17.15; (export CVE_DOWN=1; CK "$tmp/cve/w/package-lock.json" >/dev/null 2>"$tmp/cve/err"); rc=$?
ok "cve: OSV mati -> exit 2 dan pesan" "$rc|$(grep -c 'OSV tidak terjangkau' "$tmp/cve/err")" '2|1'
(export CVE_HTTP=22; CK "$tmp/cve/w/package-lock.json" >/dev/null 2>&1); ok "cve: HTTP 4xx/5xx (curl -f) -> exit 2, bukan dianggap bersih" $? 2
LOCK paged 1.0; printf '%s' "{\"vulns\":[$(V GHSA-p1p1-0000-aaaa CVE-1 HIGH)],\"next_page_token\":\"T2\"}" > "$CVE_FIX/npm_paged_1.0.json"; printf '%s' "{\"vulns\":[$(V GHSA-p2p2-0000-bbbb CVE-2 HIGH)]}" > "$CVE_FIX/npm_paged_1.0.T2.json"
out="$(CK "$tmp/cve/w/package-lock.json" 2>/dev/null)"; ok "cve: next_page_token -> dua halaman digabung" "$(cut -f3 <<<"$out" | paste -sd, -)" 'GHSA-p1p1-0000-aaaa,GHSA-p2p2-0000-bbbb'
jq -n '{lockfileVersion:3,packages:{"":{},"node_modules/twin":{version:"1.0.0"},"node_modules/a/node_modules/twin":{version:"1.0.0",dev:true}}}' > "$tmp/cve/w/package-lock.json"; : > "$CVE_FIX/calls"; FX npm twin 1.0.0 "{\"vulns\":[$(V GHSA-tttt-0000-cccc CVE-3 LOW)]}"
out="$(CK "$tmp/cve/w/package-lock.json" 2>/dev/null)"; ok "cve: pasangan kembar (prod dan dev) dikueri sekali, dua baris" "$(grep -c '^npm twin 1.0.0' "$CVE_FIX/calls")|$(grep -c . <<<"$out")" '1|2'

# 3j-3. cve-check.sh: target versi, saran, dan paparan baru (--base)
LK() { jq -n --arg n "$2" --arg v "$3" '{lockfileVersion:3,packages:{"":{},("node_modules/"+$n):{version:$v}}}' > "$1"; }   # berkas nama versi
VF() { jq -nc --arg id "$1" --arg al "$2" --arg sv "$3" --arg n "$4" --arg fx "$5" '{id:$id,aliases:($al|split(",")|map(select(.!=""))),database_specific:{severity:$sv},affected:[{package:{name:$n,ecosystem:"npm"},ranges:[{type:"SEMVER",events:([{introduced:"0"}]+($fx|split(",")|map(select(.!=""))|map({fixed:.})))}]}]}'; }   # id aliases sev nama fixed-csv
CKT() { CK "$@" 2>/dev/null | cut -f1,7,8 | tr '\t' '|' | paste -sd';' -; }   # paket|target|saran
W="$tmp/cve/w/t3"; mkdir -p "$W"
LK "$W/a.json" sa 4.17.15; cp "$W/a.json" "$W/package-lock.json"; FX npm sa 4.17.15 "{\"vulns\":[$(VF GHSA-s1s1-0000-aaaa CVE-1 HIGH sa 4.17.21)]}"
ok "cve: saran patch" "$(CKT "$W/package-lock.json")" 'sa|4.17.21|patch'
LK "$W/package-lock.json" sb 1.2.0; FX npm sb 1.2.0 "{\"vulns\":[$(VF GHSA-s2s2-0000-aaaa CVE-2 HIGH sb 1.3.1)]}"; ok "cve: saran minor" "$(CKT "$W/package-lock.json")" 'sb|1.3.1|minor'
LK "$W/package-lock.json" sc 1.2.0; FX npm sc 1.2.0 "{\"vulns\":[$(VF GHSA-s3s3-0000-aaaa CVE-3 HIGH sc 2.0.0)]}"; ok "cve: saran major" "$(CKT "$W/package-lock.json")" 'sc|2.0.0|major'
LK "$W/package-lock.json" sd 4.17.15; FX npm sd 4.17.15 "{\"vulns\":[$(VF GHSA-s4s4-0000-aaaa CVE-4 HIGH sd 4.17.19),$(VF GHSA-s5s5-0000-aaaa CVE-5 HIGH sd 4.17.21)]}"
ok "cve: dua kerentanan (4.17.19 dan 4.17.21) -> target tunggal 4.17.21 di kedua baris" "$(CKT "$W/package-lock.json")" 'sd|4.17.21|patch;sd|4.17.21|patch'
LK "$W/package-lock.json" se 4.17.9; FX npm se 4.17.9 "{\"vulns\":[$(VF GHSA-s6s6-0000-aaaa CVE-6 HIGH se 3.0.0,4.17.21)]}"; ok "cve: 4.17.9 vs 4.17.21 numerik, cabang 3.0.0 diabaikan" "$(CKT "$W/package-lock.json")" 'se|4.17.21|patch'
LK "$W/package-lock.json" sf 1.0.0-rc.1; FX npm sf 1.0.0-rc.1 "{\"vulns\":[$(VF GHSA-s7s7-0000-aaaa CVE-7 HIGH sf 1.0.0-rc.2,1.0.0)]}"; ok "cve: pra-rilis: target terkecil di atas rc.1 adalah rc.2" "$(CKT "$W/package-lock.json")" 'sf|1.0.0-rc.2|patch'
LK "$W/package-lock.json" sg 1.0.0-rc.1; FX npm sg 1.0.0-rc.1 "{\"vulns\":[$(VF GHSA-s8s8-0000-aaaa CVE-8 HIGH sg 1.0.0)]}"; ok "cve: 1.0.0-rc.1 < 1.0.0 (rilis final lebih besar)" "$(CKT "$W/package-lock.json")" 'sg|1.0.0|patch'
LK "$W/package-lock.json" sh 2.0.0; FX npm sh 2.0.0 "{\"vulns\":[$(VF GHSA-s9s9-0000-aaaa CVE-9 HIGH sh ""),$(VF GHSA-t1t1-0000-aaaa CVE-10 HIGH sh 2.0.5)]}"
ok "cve: tanpa versi perbaikan -> tanpa-perbaikan; yang lain tetap punya target" "$(CKT "$W/package-lock.json")" 'sh|-|tanpa-perbaikan;sh|2.0.5|patch'
LK "$W/head.json" sm 4.17.15; LK "$W/base.json" sm 4.17.15; cp "$W/head.json" "$W/package-lock.json"; cp "$W/base.json" "$W/base-lock.json"
FX npm sm 4.17.15 "{\"vulns\":[$(VF GHSA-m1m1-0000-aaaa CVE-11 HIGH sm 4.17.21)]}"
out="$(CK "$W/package-lock.json" --base "$W/base-lock.json" 2>/dev/null)"; rc=$?; ok "cve --base: pasangan identik dikeluarkan, exit 0" "$rc|$out" '0|'
LK "$W/package-lock.json" sm 4.17.19; FX npm sm 4.17.19 "{\"vulns\":[$(VF GHSA-m1m1-0000-aaaa CVE-11 HIGH sm 4.17.21)]}"; FX npm sm 4.17.15 "{\"vulns\":[$(VF GHSA-m1m1-0000-aaaa CVE-11 HIGH sm 4.17.21),$(VF GHSA-m2m2-0000-aaaa CVE-12 HIGH sm 4.17.19)]}"
out="$(CK "$W/package-lock.json" --base "$W/base-lock.json" 2>/dev/null)"; rc=$?; ok "cve --base: naik ke versi yang kerentanannya himpunan-bagian -> paparan=lama, exit 0" "$rc|$(cut -f3,9 <<<"$out" | tr '\t' '|')" '0|GHSA-m1m1-0000-aaaa|lama'
FX npm sm 4.17.19 "{\"vulns\":[$(VF GHSA-m1m1-0000-aaaa CVE-11 HIGH sm 4.17.21),$(VF GHSA-m3m3-0000-aaaa CVE-13 HIGH sm 4.17.21)]}"
out="$(CK "$W/package-lock.json" --base "$W/base-lock.json" 2>/dev/null)"; rc=$?; ok "cve --base: kerentanan baru di versi head -> baru dan exit 1; yang lama tetap lama" "$rc|$(cut -f3,9 <<<"$out" | tr '\t' '|' | paste -sd';' -)" '1|GHSA-m1m1-0000-aaaa|lama;GHSA-m3m3-0000-aaaa|baru'
LK "$W/base-lock.json" other 1.0.0; out="$(CK "$W/package-lock.json" --base "$W/base-lock.json" 2>/dev/null)"; rc=$?; ok "cve --base: paket baru (tak ada di basis) -> semua baru, exit 1" "$rc|$(cut -f9 <<<"$out" | sort -u | paste -sd, -)" '1|baru'
: > "$W/kosong.json"; out="$(CK "$W/package-lock.json" --base "$W/kosong.json" 2>/dev/null)"; rc=$?; ok "cve --base: berkas basis kosong (404) -> semua paket baru" "$rc" 1

# 3j-4. pr-merge-check.sh: gerbang CVE (paket baru/berubah; fail-closed; waiver cve; opt-out)
mkdir -p "$tmp/cve/gbin" "$tmp/cve/gw/docs"; export CF="$tmp/cvegate"; mkdir -p "$CF/abc1234567" "$CF/main"
cat > "$tmp/cve/gbin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"/contents/"*) a="$*"; u="${a##*contents/}"; r="${u##*ref=}"; p="${u%%\?ref=*}"; p="$(printf '%b' "${p//%/\\x}")"
    [ -n "${CF_ERR:-}" ] && { [ -z "${CF_ERR_PATH:-}" ] || [ "$p" = "$CF_ERR_PATH" ]; } && { echo "gh: Server Error (HTTP 500)" >&2; exit 1; }
    if [ -f "$CF/$r/$p" ]; then cat "$CF/$r/$p"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
  *"/pulls/"*"/files"*) if [ -n "${FILES_JSON:-}" ]; then echo "$FILES_JSON"; else printf '%s\n' "${DIFF:-}" | sed -n 's#^diff --git a/.* b/\(.*\)$#\1#p' | jq -R '{filename:.,status:"modified"}' | jq -cs .; fi ;;
  *"/compare/"*) echo "{\"merge_base_commit\":{\"sha\":\"${MB:-main}\"}}" ;;
  *) exec "$PMB/gh" "$@" ;;
esac
EOF
chmod +x "$tmp/cve/gbin/gh"; printf '#!/bin/sh\nexit 1\n' > "$tmp/cve/gbin/go"; chmod +x "$tmp/cve/gbin/go"
GE() { (cd "$tmp/cve/gw" && BASE=main BODY=x GH_REPO=o/r PMB="$tmp/pmb" PATH="$tmp/cve/gbin:$tmp/cve/bin:$PATH" bash "$root/scripts/pr-merge-check.sh" 9 main 2>&1); }
DGO=$'diff --git a/go.mod b/go.mod\n--- a/go.mod\n+++ b/go.mod\n@@ -1 +1 @@\n+require golang.org/x/net v0.7.0'
printf 'module m\n\nrequire golang.org/x/net v0.7.0\n' > "$CF/abc1234567/go.mod"
FX Go golang.org/x/net 0.7.0 "{\"vulns\":[$(jq -nc '{id:"GHSA-gate-0000-aaaa",aliases:["CVE-2099-1"],database_specific:{severity:"HIGH"},affected:[{package:{name:"golang.org/x/net",ecosystem:"Go"},ranges:[{type:"SEMVER",events:[{introduced:"0"},{fixed:"0.17.0"}]}]}]}')]}"
: > "$CVE_FIX/calls"; out="$(export DIFF="$DGO"; GE)"; rc=$?
ok "gerbang cve: kerentanan HIGH baru pada go.mod -> exit 1, pesan cve, saran" "$rc|$(grep -c '^GAGAL: cve' <<<"$out")|$(grep -c 'BLOK: cve (go.mod) golang.org/x/net 0.7.0 GHSA-gate-0000-aaaa HIGH.*0.17.0.*minor' <<<"$out")" '1|1|1'
out="$(export DIFF="$DGO" COMM='Pengecualian disetujui owner (cve): belum ada perbaikan upstream (Commit: abc1234)'; GE)"; ok "gerbang cve: waiver (cve) untuk head -> exit 0" $? 0
out="$(export DIFF="$DGO" COMM='Pengecualian disetujui owner (perf): angka ukur belum ada (Commit: abc1234)'; GE)"; ok "gerbang cve: waiver (perf) tidak menutup cve -> exit 1" $? 1
out="$(export DIFF="$DGO" CVE_DOWN=1; GE)"; rc=$?; ok "gerbang cve: OSV mati + manifest -> exit 1 'GAGAL: cve: OSV tidak terjangkau'" "$rc|$(grep -c '^GAGAL: cve: OSV tidak terjangkau' <<<"$out")" '1|1'
out="$(export DIFF="$DGO" CVE_DOWN=1 COMM='Pengecualian disetujui owner (cve): OSV mati, risiko diterima (Commit: abc1234)'; GE)"; ok "gerbang cve: OSV mati + waiver cve -> exit 0" $? 0
: > "$CVE_FIX/calls"; out="$(export DIFF=$'diff --git a/README.md b/README.md\n+x'; GE)"; ok "gerbang cve: diff tanpa manifest -> curl tidak dipanggil, exit 0" "$?|$(wc -l < "$CVE_FIX/calls" | tr -d ' ')" '0|0'
rm -f "$CF/abc1234567/go.mod"; : > "$CVE_FIX/calls"; out="$(export DIFF="$DGO" FILES_JSON='[{"filename":"go.mod","status":"removed"}]'; GE)"; ok "gerbang cve: berkas status removed -> dilewati, exit 0, curl 0" "$?|$(wc -l < "$CVE_FIX/calls" | tr -d ' ')" '0|0'
out="$(export DIFF="$DGO"; GE)"; rc=$?; ok "gerbang cve: 404 pada head untuk berkas yang TIDAK dihapus -> exit 1 (fail-closed)" "$rc|$(grep -c '^GAGAL: cve' <<<"$out")" '1|1'
printf 'module m\n\nrequire golang.org/x/net v0.7.0\n' > "$CF/abc1234567/go.mod"
out="$(export DIFF="$DGO" CF_ERR=1; GE)"; rc=$?; ok "gerbang cve: galat selain 404 saat membaca berkas -> exit 1 (fail-closed)" "$rc|$(grep -c 'tak terbaca' <<<"$out")" '1|1'
FX Go golang.org/x/net 0.7.0 "{\"vulns\":[$(jq -nc '{id:"GHSA-gate-0000-bbbb",aliases:["CVE-2099-2"],database_specific:{severity:"MODERATE"},affected:[]}')]}"
out="$(export DIFF="$DGO"; GE)"; rc=$?; ok "gerbang cve: MODERATE saja -> exit 0 dengan PERINGATAN cve" "$rc|$(grep -c '^PERINGATAN: cve (go.mod)' <<<"$out")" '0|1'
FX Go golang.org/x/net 0.7.0 "{\"vulns\":[$(jq -nc '{id:"GHSA-gate-0000-aaaa",aliases:["CVE-2099-1"],database_specific:{severity:"HIGH"},affected:[]}')]}"
mkdir -p "$CF/main/docs"; printf -- '- Pemeriksaan CVE: tidak. Dimatikan untuk uji.\n' > "$CF/main/docs/WORKFLOW.md"; : > "$CVE_FIX/calls"; out="$(export DIFF="$DGO"; GE)"; rc=$?
ok "gerbang cve: opt-out di WORKFLOW.md CABANG TUJUAN -> exit 0, PERINGATAN dimatikan, curl 0" "$rc|$(grep -c 'PERINGATAN: pemeriksaan CVE dimatikan di WORKFLOW.md' <<<"$out")|$(wc -l < "$CVE_FIX/calls" | tr -d ' ')" '0|1|0'
printf 'module m\n\nrequire golang.org/x/net v0.7.0\n' > "$CF/abc1234567/go.mod"; rm -f "$CF/main/docs/WORKFLOW.md"; printf -- '- Pemeriksaan CVE: tidak. PR ini mencoba mematikan gerbang.\n' > "$tmp/cve/gw/docs/WORKFLOW.md"
out="$(export DIFF="$DGO"; GE)"; rc=$?; ok "gerbang cve: opt-out hanya di checkout/PR (bukan cabang tujuan) tidak mematikan gerbang -> exit 1" "$rc|$(grep -c 'dimatikan' <<<"$out")" '1|0'
rm -f "$tmp/cve/gw/docs/WORKFLOW.md"; rm -f "$CF/abc1234567/go.mod"; mkdir -p "$CF/abc1234567/sub dir"; printf 'module m\n\nrequire golang.org/x/net v0.7.0\n' > "$CF/abc1234567/sub dir/go.mod"; rm -f "$CF/abc1234567/go.mod"
out="$(export DIFF=$'diff --git a/sub dir/go.mod b/sub dir/go.mod\n+x'; GE)"; rc=$?; ok "gerbang cve: path bersepasi (sub dir/go.mod) dibaca dan diperiksa -> exit 1" "$rc|$(grep -c 'BLOK: cve (sub dir/go.mod)' <<<"$out")" '1|1'

# 3j-5. cve-audit.sh: audit seluruh repo -> satu issue per paket rentan (REST), tanpa duplikat; skill dan dokumen
mkdir -p "$tmp/cve/abin" "$tmp/cve/au"; export CFA="$tmp/cveaudit"; mkdir -p "$CFA"
cat > "$tmp/cve/abin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" | tr '\n' '~' >> "$CFA/calls"; echo >> "$CFA/calls"
case "$*" in
  "issue list"*) cat "$CFA/open.json" 2>/dev/null || echo '[]' ;;
  "api -X POST"*) for a in "$@"; do case "$a" in body=*) printf '%s' "${a#body=}" > "$CFA/last-body" ;; esac; done; echo '{"number":99}' ;;
esac
EOF
chmod +x "$tmp/cve/abin/gh"
AU() { (cd "$tmp/cve/au" && GH_REPO=o/r PATH="$tmp/cve/abin:$tmp/cve/bin:$PATH" bash "$root/scripts/cve-audit.sh" "$@" 2>&1); }
jq -n '{lockfileVersion:3,packages:{"":{},"node_modules/aa":{version:"1.0.0"},"node_modules/bb":{version:"1.0.0"},"node_modules/cc":{version:"1.0.0"},"node_modules/dd":{version:"1.0.0"}}}' > "$tmp/cve/au/package-lock.json"
git init -q "$tmp/cve/au" 2>/dev/null; git -C "$tmp/cve/au" add package-lock.json 2>/dev/null
FX npm aa 1.0.0 "{\"vulns\":[$(VF GHSA-aaaa-0001-aaaa CVE-A1 HIGH aa 1.0.1),$(VF GHSA-aaaa-0002-aaaa CVE-A2 MODERATE aa 1.0.2)]}"
FX npm bb 1.0.0 "{\"vulns\":[$(VF GHSA-bbbb-0001-aaaa CVE-B1 CRITICAL bb 2.0.0)]}"
FX npm cc 1.0.0 "{\"vulns\":[$(VF GHSA-cccc-0001-aaaa CVE-C1 HIGH cc "")]}"
FX npm dd 1.0.0 "{\"vulns\":[$(VF GHSA-dddd-0001-aaaa CVE-D1 HIGH dd 1.0.1)]}"
echo '[{"number":7,"title":"CVE: dd 1.0.0 -> 1.0.1 (patch)"}]' > "$CFA/open.json"; : > "$CFA/calls"
out="$(AU)"; rc=$?   # tanpa argumen: berkas dikenali dari git ls-files
ok "audit: tiga issue dibuat (aa, bb, cc); dd dilewati karena issue terbuka berawalan sama" "$rc|$(grep -c '^api -X POST' "$CFA/calls")|$(grep -c 'title=CVE: dd' "$CFA/calls")" '0|3|0'
ok "audit: dua temuan satu paket -> satu issue, target tunggal, hanya needs-security" "$(grep -c 'title=CVE: aa 1.0.0 -> 1.0.2 (patch)' "$CFA/calls")|$(grep 'title=CVE: aa ' "$CFA/calls" | grep -c 'labels\[\]=needs-principal')|$(grep 'title=CVE: aa ' "$CFA/calls" | grep -c 'labels\[\]=needs-security')" '1|0|1'
ok "audit: saran major -> needs-security dan needs-principal" "$(grep 'title=CVE: bb 1.0.0 -> 2.0.0 (major)' "$CFA/calls" | grep -c 'labels\[\]=needs-security.*labels\[\]=needs-principal\|labels\[\]=needs-principal.*labels\[\]=needs-security')" 1
ok "audit: tanpa perbaikan -> judul tanpa target dan needs-principal" "$(grep 'title=CVE: cc 1.0.0 (tanpa-perbaikan)' "$CFA/calls" | grep -c 'labels\[\]=needs-principal')" 1
ok "audit: badan memuat tanggal, sumber OSV, dan batas klaim" "$(grep -c "per $(date -u +%F)" "$CFA/last-body")|$(grep -c 'osv.dev' "$CFA/last-body")|$(grep -ci 'bebas CVE' "$CFA/last-body")" '1|1|1'
: > "$CFA/calls"; out="$(AU --dry-run)"; ok "audit: --dry-run tidak memanggil POST, mencetak tiga rencana" "$(grep -c '^api -X POST' "$CFA/calls")|$(grep -c '^\[dry-run\]' <<<"$out")" '0|3'
jq -n '{lockfileVersion:3,packages:{"":{},"node_modules/zz":{version:"1.0.0"}}}' > "$tmp/cve/au/clean-lock/package-lock.json" 2>/dev/null || { mkdir -p "$tmp/cve/au/clean-lock"; jq -n '{lockfileVersion:3,packages:{"":{},"node_modules/zz":{version:"1.0.0"}}}' > "$tmp/cve/au/clean-lock/package-lock.json"; }
: > "$CFA/calls"; out="$(AU clean-lock/package-lock.json)"; rc=$?
ok "audit: bersih -> kalimat per tanggal, tanpa POST, exit 0" "$rc|$(grep -c "tidak ada kerentanan diketahui di OSV per $(date -u +%F) untuk clean-lock/package-lock.json" <<<"$out")|$(grep -c '^api -X POST' "$CFA/calls")" '0|1|0'
: > "$CFA/calls"; out="$(export CVE_DOWN=1; AU)"; rc=$?; ok "audit: OSV mati -> exit 2, tanpa POST" "$rc|$(grep -c '^api -X POST' "$CFA/calls")" '2|0'
grep -q 'cve-audit.sh' skills/cve-audit/SKILL.md && grep -q 'dry-run' skills/cve-audit/SKILL.md && grep -q '^name: cve-audit' skills/cve-audit/SKILL.md; ok "skill cve-audit: ada, memanggil cve-audit.sh dan dry-run" $? 0
grep -q 'Pemeriksaan CVE:' templates/WORKFLOW.md; ok "templat WORKFLOW memuat 'Pemeriksaan CVE:'" $? 0
grep -q 'cve-check.sh' agents/security.md; ok "agen security menyebut cve-check.sh" $? 0

# 3j-6. PRIVACY.md dan README menjelaskan pemeriksaan CVE (jaringan keluar ke OSV)
grep -q 'api.osv.dev' PRIVACY.md && ! grep -q 'Satu-satunya jaringan keluar' PRIVACY.md; ok "PRIVACY: menyebut api.osv.dev dan tidak lagi mengaku 'satu-satunya' jaringan keluar" $? 0
grep -q 'cve-check.sh' README.md && grep -q 'waiver owner `(cve)`' README.md && grep -q 'Pemeriksaan CVE:' README.md && grep -q 'cve-audit' README.md; ok "README: cve-check.sh, waiver (cve), Pemeriksaan CVE, cve-audit" $? 0

# 3j-7. perbaikan hasil review akhir
mkdir -p "$CF/abc1234567/x b/y" "$CF/abc1234567/é" "$CF/mb1234"; printf 'module m\n\nrequire golang.org/x/net v0.7.0\n' > "$CF/abc1234567/x b/y/go.mod"; cp "$CF/abc1234567/x b/y/go.mod" "$CF/abc1234567/é/go.mod"
FX Go golang.org/x/net 0.7.0 "{\"vulns\":[$(jq -nc '{id:"GHSA-gate-0000-aaaa",aliases:["CVE-2099-1"],database_specific:{severity:"HIGH"},affected:[]}')]}"
out="$(export DIFF=$'diff --git a/x b/y/go.mod b/x b/y/go.mod\n+x' FILES_JSON='[{"filename":"x b/y/go.mod","status":"modified"}]'; GE)"; rc=$?
ok "gerbang cve: path berisi ' b/' tidak lolos (daftar berkas dari REST, bukan header diff)" "$rc|$(grep -c 'BLOK: cve (x b/y/go.mod)' <<<"$out")" '1|1'
out="$(export DIFF=$'diff --git "a/\\303\\251/go.mod" "b/\\303\\251/go.mod"\n+x' FILES_JSON='[{"filename":"é/go.mod","status":"modified"}]'; GE)"; rc=$?
ok "gerbang cve: path non-ASCII ber-kutip git tidak lolos" "$rc|$(grep -c 'BLOK: cve (é/go.mod)' <<<"$out")" '1|1'
mkdir -p "$CF/abc1234567"; echo '{"lockfileVersion":1,"dependencies":{"a":{"version":"1.0.0"}}}' > "$CF/abc1234567/package-lock.json"
out="$(export DIFF=$'diff --git a/package-lock.json b/package-lock.json\n+x'; GE)"; rc=$?
ok "gerbang cve: lockfile yang tak terparsir -> PERINGATAN 'tidak lengkap' di keluaran gerbang" "$rc|$(grep -c '^PERINGATAN: cve (package-lock.json) tidak lengkap' <<<"$out")" '0|1'
rm -f "$CF/abc1234567/package-lock.json"
# merge-base: cabang PR tertinggal; ujung cabang tujuan lebih baru, merge-base sama dengan head -> tidak berubah
printf 'module m\n\nrequire golang.org/x/net v0.7.0\n' > "$CF/abc1234567/go.mod"; printf 'module m\n\nrequire golang.org/x/net v0.7.0\n' > "$CF/mb1234/go.mod"; printf 'module m\n\nrequire golang.org/x/net v0.62.0\n' > "$CF/main/go.mod"
out="$(export DIFF="$DGO" MB=mb1234; GE)"; rc=$?; ok "gerbang cve: dibanding merge-base (bukan ujung cabang tujuan) -> paket tak disentuh PR tidak dianggap baru" "$rc|$(grep -c '^BLOK' <<<"$out")" '0|0'
rm -f "$CF/main/go.mod" "$CF/mb1234/go.mod" "$CF/abc1234567/go.mod"
# cve-check: range tipe GIT (fixed = hash commit) diabaikan
LK "$W/package-lock.json" gg 1.0.0
FX npm gg 1.0.0 "{\"vulns\":[$(jq -nc '{id:"GHSA-gitg-0000-aaaa",aliases:["CVE-2099-5"],database_specific:{severity:"HIGH"},affected:[{package:{name:"gg",ecosystem:"npm"},ranges:[{type:"GIT",repo:"https://x",events:[{introduced:"0"},{fixed:"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"}]},{type:"SEMVER",events:[{introduced:"0"},{fixed:"1.0.5"}]}]}]}')]}"
ok "cve: range GIT diabaikan, target dari range SEMVER" "$(CKT "$W/package-lock.json")" 'gg|1.0.5|patch'
FX npm gg 1.0.0 "{\"vulns\":[$(jq -nc '{id:"GHSA-gitg-0000-bbbb",aliases:[],database_specific:{severity:"HIGH"},affected:[{package:{name:"gg",ecosystem:"npm"},ranges:[{type:"GIT",repo:"https://x",events:[{introduced:"0"},{fixed:"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"}]}]}]}')]}"
ok "cve: hanya range GIT -> tanpa-perbaikan (hash tidak jadi target)" "$(CKT "$W/package-lock.json")" 'gg|-|tanpa-perbaikan'
# kueri paralel: 16 paket x 0.3 dtk berurutan = 4,8 dtk; paralel (8) < 3 dtk, hasil sama, tiap pasangan sekali
jq -n '{lockfileVersion:3,packages:({"":{}}+([range(1;17)|{key:("node_modules/pp\(.)"),value:{version:"1.0.0"}}]|from_entries))}' > "$W/package-lock.json"; : > "$CVE_FIX/calls"
for i in $(seq 1 16); do FX npm "pp$i" 1.0.0 "{\"vulns\":[$(VF GHSA-pp$i-0000-aaaa CVE-2099-$i MODERATE pp$i 1.0.1)]}"; done
t0="$(date +%s)"; out="$( (export CVE_SLOW=0.3; CK "$W/package-lock.json" 2>/dev/null) )"; t1="$(date +%s)"
ok "cve: 16 paket dikueri paralel (<3 dtk), semua baris ada, tiap pasangan sekali" "$([ $((t1-t0)) -lt 3 ] && echo cepat)|$(grep -c . <<<"$out")|$(wc -l < "$CVE_FIX/calls" | tr -d ' ')" 'cepat|16|16'
# audit: paket sama pada dua versi (npm bersarang) -> satu issue dalam satu putaran
jq -n '{lockfileVersion:3,packages:{"":{},"node_modules/aa":{version:"1.0.0"},"node_modules/x/node_modules/aa":{version:"0.9.0"}}}' > "$tmp/cve/au/dup-lock/package-lock.json" 2>/dev/null || { mkdir -p "$tmp/cve/au/dup-lock"; jq -n '{lockfileVersion:3,packages:{"":{},"node_modules/aa":{version:"1.0.0"},"node_modules/x/node_modules/aa":{version:"0.9.0"}}}' > "$tmp/cve/au/dup-lock/package-lock.json"; }
FX npm aa 0.9.0 "{\"vulns\":[$(VF GHSA-aaaa-0009-aaaa CVE-A9 HIGH aa 1.0.2)]}"; echo '[]' > "$CFA/open.json"; : > "$CFA/calls"; out="$(AU dup-lock/package-lock.json)"
ok "audit: paket sama di dua versi -> satu issue dalam satu putaran" "$(grep -c '^api -X POST' "$CFA/calls")" 1
grep -q 'privat' PRIVACY.md; ok "PRIVACY: menyebut nama paket privat/internal ikut terkirim" $? 0
grep -q 'yarn.lock' README.md && grep -q 'pnpm-lock.yaml' README.md; ok "README: jujur soal lockfile yang belum tercakup (yarn.lock, pnpm-lock.yaml)" $? 0

# 3l-1. cve-check.sh: paket privat tidak pernah dikirim ke OSV (#25)
P="$tmp/cve/w/priv"; mkdir -p "$P"
PL() { printf "$@" > "$P/pat"; }   # tulis berkas pola (printf: \t = tab)
LK2() { jq -n --arg n1 "$2" --arg v1 "$3" --arg n2 "$4" --arg v2 "$5" '{lockfileVersion:3,packages:{"":{},("node_modules/"+$n1):{version:$v1},("node_modules/"+$n2):{version:$v2}}}' > "$1"; }   # berkas n1 v1 n2 v2
CP() { (PATH="$tmp/cve/bin:$PATH" $CV "$@" 2>"$P/err"); }
LK2 "$P/package-lock.json" @acme/x 1.0.0 lodash 4.17.15; FX npm @acme/x 1.0.0 "{\"vulns\":[$(V GHSA-priv-0000-aaaa CVE-P1 HIGH)]}"
rm -f "$CVE_FIX/npm_lodash_4.17.15.json"; PL 'npm\t@acme/*\n'; : > "$CVE_FIX/calls"; out="$(CP "$P/package-lock.json" --private "$P/pat")"; rc=$?
ok "cve privat: npm @acme/x tidak dikueri, publik tetap, 1 laporan dilewati" "$rc|$(grep -c '@acme' "$CVE_FIX/calls")|$(grep -c '^npm lodash 4.17.15' "$CVE_FIX/calls")|$(grep -c '^dilewati (privat): @acme/x@1.0.0$' "$P/err")" '0|0|1|1'
LK2 "$P/h.json" @acme/x 2.0.0 lodash 4.17.15; LK2 "$P/b.json" @acme/x 1.0.0 lodash 4.17.15; cp "$P/h.json" "$P/package-lock.json"; : > "$CVE_FIX/calls"
out="$(CP "$P/package-lock.json" --base "$P/b.json" --private "$P/pat")"; ok "cve privat: kueri basis tidak membocorkan nama" "$(grep -c '@acme' "$CVE_FIX/calls")|$(grep -c '^dilewati (privat): @acme/x@' "$P/err")" '0|1'
mkdir -p "$P/go"; printf 'module m\n\nrequire (\n\tgit.corp.com/team/x v1.0.0\n\tgit.corp.com/teamx/y v1.0.0\n)\n' > "$P/go/go.mod"; PL 'Go\tgit.corp.com/team\n'; : > "$CVE_FIX/calls"
out="$(CP "$P/go/go.mod" --private "$P/pat")"; ok "cve privat: Go awalan modul (team/x dilewati, teamx/y tidak)" "$(grep -c ' git.corp.com/team/x ' "$CVE_FIX/calls")|$(grep -c ' git.corp.com/teamx/y ' "$CVE_FIX/calls")" '0|1'
PL 'Go\t@acme/*\n'; cp "$P/h.json" "$P/package-lock.json"; : > "$CVE_FIX/calls"; out="$(CP "$P/package-lock.json" --private "$P/pat")"
ok "cve privat: pola ekosistem lain tidak berlaku" "$(grep -c '@acme/x' "$CVE_FIX/calls")" 1
mkdir -p "$P/py"; printf 'Internal_Lib==1.0\nrequests==2.0.0\n' > "$P/py/requirements.txt"; PL 'Internal.Lib\n'; : > "$CVE_FIX/calls"; out="$(CP "$P/py/requirements.txt" --private "$P/pat")"
ok "cve privat: PyPI dinormalisasi, pola tanpa tab berlaku untuk semua ekosistem" "$(grep -c 'internal-lib' "$CVE_FIX/calls")|$(grep -c '^PyPI requests' "$CVE_FIX/calls")" '0|1'
cp "$P/h.json" "$P/package-lock.json"; : > "$CVE_FIX/calls"; out="$( (export CVE_PRIVATE='zzz,@acme/*'; CP "$P/package-lock.json") )"
ok "cve privat: env CVE_PRIVATE dipisah koma" "$(grep -c '@acme/x' "$CVE_FIX/calls")" 0
for pat in '*' '**'; do PL '%s\n' "$pat"; : > "$CVE_FIX/calls"; out="$(CP "$P/package-lock.json" --private "$P/pat")"
  ok "cve privat: pola '$pat' diabaikan dengan PERINGATAN (lodash tetap dikueri)" "$(grep -c '^npm lodash' "$CVE_FIX/calls")|$(grep -c "^PERINGATAN: pola '\*' mematikan pemeriksaan" "$P/err")" '1|1'; done
PL 'npm\t*\n'; : > "$CVE_FIX/calls"; out="$(CP "$P/package-lock.json" --private "$P/pat")"; ok "cve privat: pola 'npm<tab>*' juga diabaikan" "$(grep -c '^npm lodash' "$CVE_FIX/calls")" 1
LK2 "$P/package-lock.json" @acme/x 1.0.0 @acme/y 1.0.0; PL 'npm\t@acme/*\n'; out="$(CP "$P/package-lock.json" --private "$P/pat")"; rc=$?
ok "cve privat: semua entri dilewati -> exit 0 tanpa keluaran" "$rc|$out" '0|'
LK2 "$P/package-lock.json" @acme/x 1.0.0 lodash 4.17.15; FX npm lodash 4.17.15 "{\"vulns\":[$(V GHSA-pub-0000-aaaa CVE-P2 HIGH)]}"; out="$(CP "$P/package-lock.json" --private "$P/pat")"; rc=$?
ok "cve privat: publik HIGH di lockfile campuran -> exit 1 dan hanya lodash" "$rc|$(cut -f1 <<<"$out")" '1|lodash'
$CV --list "$P/package-lock.json" 2>/dev/null | grep -q '@acme/x'; ok "cve --list tidak menyaring" $? 0

# 3l-2. cve-private.sh: pengumpul pola dari WORKFLOW, .npmrc, GOPRIVATE (#25)
CPV="$root/scripts/cve-private.sh"; Q="$tmp/cve/w/priv2"; mkdir -p "$Q"
CQ() { (unset GOPRIVATE; PATH="$Q/nogo:$PATH" bash "$CPV" "$@" 2>&1 | tr '\t' ':' | paste -sd'|' -); }
printf -- '# t\n- Paket privat: @acme/*, git.corp.com/team,  internal-lib.\n' > "$Q/wf.md"
ok "cve-private: baris Paket privat dari WORKFLOW (spasi dipangkas, titik penutup dibuang)" "$(CQ --workflow "$Q/wf.md")" '*:@acme/*|*:git.corp.com/team|*:internal-lib'
printf -- '- Paket privat: \n- Pemeriksaan CVE: ya\n' > "$Q/wf0.md"; ok "cve-private: baris Paket privat kosong -> tanpa pola" "$(CQ --workflow "$Q/wf0.md")" ''
printf '@acme:registry=https://corp.example/npm/\n@pub:registry=https://REGISTRY.npmjs.org/\n@y:registry="https://registry.yarnpkg.com"\n' > "$Q/.npmrc"
ok "cve-private: .npmrc scope ke proxy -> npm @scope/*; npmjs/yarnpkg (huruf besar, kutip, / akhir) -> publik" "$(CQ --npmrc "$Q/.npmrc")" 'npm:@acme/*'
printf '//corp.example/:_authToken=SECRET123\nregistry=https://proxy.example/\n@acme:registry=https://corp.example/\n' > "$Q/.npmrc2"; o="$(CQ --npmrc "$Q/.npmrc2")"
ok "cve-private: token dan registry global .npmrc tidak pernah tampil" "$o|$(grep -c 'SECRET123\|proxy.example\|_authToken' <<<"$o")" 'npm:@acme/*|0'
mkdir -p "$Q/nogo"; printf '#!/bin/sh\nexit 1\n' > "$Q/nogo/go"; chmod +x "$Q/nogo/go"
ok "cve-private: GOPRIVATE env -> pola Go per koma" "$( (export GOPRIVATE='git.corp.com/*,x.io/y'; PATH="$Q/nogo:$PATH" bash "$CPV" --goprivate | tr '\t' ':' | paste -sd'|' -) )" 'Go:git.corp.com/*|Go:x.io/y'
ok "cve-private: GOPRIVATE kosong dan go gagal -> kosong" "$(CQ --goprivate)" ''
ok "cve-private: berkas tak ada -> kosong, exit 0" "$(CQ --workflow "$Q/tidak.md" --npmrc "$Q/tidak")|$(bash "$CPV" --workflow "$Q/tidak.md" >/dev/null 2>&1; echo $?)" '|0'
ok "cve-private: dua sumber digabung tanpa duplikat" "$(CQ --workflow "$Q/wf.md" --workflow "$Q/wf.md" | tr '|' '\n' | grep -c .)" 3

# 3l-3. pr-merge-check.sh: pola privat dari cabang tujuan (#25)
rm -rf "$CF/main" "$CF/abc1234567"; mkdir -p "$CF/main/docs" "$CF/abc1234567/docs" "$CF/abc1234567/web" "$CF/main/web"
printf 'module m\n\nrequire git.corp.com/team/x v1.0.0\n' > "$CF/abc1234567/go.mod"
FX Go git.corp.com/team/x 1.0.0 "{\"vulns\":[$(jq -nc '{id:"GHSA-priv-0000-gate",aliases:["CVE-2099-7"],database_specific:{severity:"HIGH"},affected:[]}')]}"
printf -- '- Paket privat: git.corp.com/team\n' > "$CF/main/docs/WORKFLOW.md"; : > "$CVE_FIX/calls"
out="$(export DIFF="$DGO"; GE)"; rc=$?
ok "gerbang privat: pola WORKFLOW cabang tujuan -> exit 0, curl tanpa nama, PERINGATAN jumlah tanpa nama" "$rc|$(grep -c 'git.corp.com' "$CVE_FIX/calls")|$(grep -c '^PERINGATAN: cve (go.mod) 1 paket privat tidak diperiksa$' <<<"$out")|$(grep -c 'git.corp.com' <<<"$out")" '0|0|1|0'
rm -f "$CF/main/docs/WORKFLOW.md"; printf -- '- Paket privat: git.corp.com/team\n' > "$CF/abc1234567/docs/WORKFLOW.md"
out="$(export DIFF="$DGO"; GE)"; rc=$?
ok "gerbang privat: pola hanya di PR (bukan cabang tujuan) -> tetap BLOK dan PERINGATAN pola baru" "$rc|$(grep -c '^BLOK: cve (go.mod)' <<<"$out")|$(grep -c '^PERINGATAN: cve (go.mod) pola privat baru' <<<"$out")" '1|1|1'
rm -f "$CF/abc1234567/docs/WORKFLOW.md"
DNPM=$'diff --git a/web/package-lock.json b/web/package-lock.json\n+x'
jq -n '{lockfileVersion:3,packages:{"":{},"node_modules/@acme/x":{version:"1.0.0"}}}' > "$CF/abc1234567/web/package-lock.json"; FX npm @acme/x 1.0.0 "{\"vulns\":[$(V GHSA-priv-0000-npm CVE-2099-8 HIGH)]}"
printf '@acme:registry=https://corp.example/\n//corp.example/:_authToken=SECRET123\n' > "$CF/main/web/.npmrc"; : > "$CVE_FIX/calls"
out="$(export DIFF="$DNPM"; GE)"; rc=$?; ok "gerbang privat: .npmrc di direktori lockfile (cabang tujuan) -> exit 0, tanpa token di keluaran, curl tanpa nama" "$rc|$(grep -c '@acme' "$CVE_FIX/calls")|$(grep -c 'SECRET123' <<<"$out")" '0|0|0'
rm -f "$CF/main/web/.npmrc"; printf '@acme:registry=https://corp.example/\n' > "$CF/main/.npmrc"; : > "$CVE_FIX/calls"
out="$(export DIFF="$DNPM"; GE)"; rc=$?; ok "gerbang privat: .npmrc di akar repo juga dibaca -> exit 0" "$rc|$(grep -c '@acme' "$CVE_FIX/calls")" '0|0'
out="$(export DIFF="$DNPM" CF_ERR=1 CF_ERR_PATH=.npmrc; GE)"; rc=$?; ok "gerbang privat: .npmrc 500 di cabang tujuan -> GAGAL cve (fail-closed)" "$rc|$(grep -c '^GAGAL: cve: .*npmrc' <<<"$out")" '1|1'
rm -f "$CF/main/.npmrc"; printf -- '- Paket privat: git.corp.com/team\n' > "$CF/main/docs/WORKFLOW.md"
out="$(export DIFF="$DGO" CF_ERR=1 CF_ERR_PATH=docs/WORKFLOW.md; GE)"; rc=$?; ok "gerbang privat: WORKFLOW 500 di cabang tujuan -> GAGAL cve (fail-closed), nama tidak terkirim" "$rc|$(grep -c '^GAGAL: cve: .*WORKFLOW' <<<"$out")" '1|1'
rm -f "$CF/main/docs/WORKFLOW.md"; : > "$CVE_FIX/calls"; out="$(export DIFF="$DNPM"; GE)"; rc=$?
ok "gerbang privat: .npmrc dan WORKFLOW 404 = tanpa pola -> normal (BLOK, nama dikueri)" "$rc|$(grep -c '^BLOK: cve (web/package-lock.json)' <<<"$out")|$(grep -c '@acme/x' "$CVE_FIX/calls")" '1|1|1'
printf -- '- Pemeriksaan CVE: tidak. uji\n- Paket privat: git.corp.com/team\n' > "$CF/main/docs/WORKFLOW.md"; out="$(export DIFF="$DGO"; GE)"; rc=$?
ok "gerbang privat: opt-out WORKFLOW tetap menang bersama pola" "$rc|$(grep -c 'dimatikan' <<<"$out")" '0|1'
rm -rf "$CF/main" "$CF/abc1234567"; mkdir -p "$CF/main" "$CF/abc1234567"

# 3k-1. cleanup.sh: laporan kandidat cabang/worktree ter-merge (repo git nyata + remote bare lokal; gh palsu untuk REST)
CL="$tmp/cl"; mkdir -p "$CL/bin"; export CL
cat > "$CL/bin/gh" <<'EOF'
#!/usr/bin/env bash
a="$*"; [ -n "${GHLOG:-}" ] && echo "$a" >> "$GHLOG"
case "$a" in
  "api repos/o/r") [ -n "${REPO_FAIL:-}" ] && { echo "HTTP 500" >&2; exit 1; }; echo "{\"default_branch\":\"main\",\"delete_branch_on_merge\":${DBM:-false}}" ;;
  "api repos/o/r/pulls?state=open"*) [ -n "${OPEN_FAIL:-}" ] && { echo "HTTP 500" >&2; exit 1; }; cat "$CL/open.json" ;;
  "api repos/o/r/pulls?head="*) b="${a##*head=}"; b="${b%%&*}"; b="$(printf '%b' "${b//%/\\x}")"; b="${b#o:}"; f="$CL/pr-$(printf '%s' "$b" | tr / _).json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi ;;
esac
EOF
chmod +x "$CL/bin/gh"
G() { git -C "$CL/w" "$@"; }
MK() {   # repo sementara: main (bawaan), integ (integrasi), cabang ter-merge/squash/belum, worktree bersih/kotor/terkunci/terlepas/Orca
  rm -rf "$CL/w" "$CL/remote.git" "$CL"/w-* "$CL/orca"; git init -q --bare "$CL/remote.git"; git --git-dir="$CL/remote.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$CL/remote.git" "$CL/w" 2>/dev/null; G checkout -q -b main; mkdir -p "$CL/w/docs"
  printf -- '- Backend: github — repo: o/r\n3. Cabang integrasi: integ\n' > "$CL/w/docs/WORKFLOW.md"; G add -A; G commit -q -m base; G push -q -u origin main; G remote set-head origin main >/dev/null
  G branch integ; G push -q origin integ
  for n in issue-1 issue-5 issue-6 issue-7 issue-8 fitur/x stack-base; do G checkout -q -b "$n" main; echo "$n" > "$CL/w/$(tr / _ <<<"$n").txt"; G add -A; G commit -q -m "$n"; G push -q origin "$n"; G checkout -q main; G merge -q --no-ff "$n" -m "merge $n"; done
  G push -q origin main
  for n in issue-2 stack-child; do G checkout -q -b "$n" main; echo "$n" > "$CL/w/$n.txt"; G add -A; G commit -q -m "$n"; G push -q origin "$n"; G checkout -q main; done
  for n in issue-3 issue-4; do G checkout -q -b "$n" main; echo "$n" > "$CL/w/$n.txt"; G add -A; G commit -q -m "$n"; G push -q origin "$n"; G checkout -q main; G merge -q --squash "$n"; G commit -q -m "squash $n"; done
  G push -q origin main; S3="$(G rev-parse issue-3)"; S4="$(G rev-parse issue-4)"
  G checkout -q issue-4; echo extra > "$CL/w/extra.txt"; G add -A; G commit -q -m extra; G checkout -q main   # ujung lokal issue-4 menyimpang dari PR
  G worktree add -q "$CL/w-wt-5" issue-5; G worktree add -q "$CL/w-wt-6" issue-6; echo dirty > "$CL/w-wt-6/kotor.txt"
  G worktree add -q "$CL/w-wt-7" issue-7; G worktree lock "$CL/w-wt-7"; G worktree add -q --detach "$CL/w-detached" main
  mkdir -p "$CL/orca/workspaces"; G worktree add -q "$CL/orca/workspaces/w-wt-8" issue-8
  for n in 3 4; do v="S$n"; printf '[{"number":%s,"merged_at":"2026-11-01T00:00:00Z","head":{"ref":"issue-%s","sha":"%s"},"base":{"ref":"main"}}]' "1$n" "$n" "${!v}" > "$CL/pr-issue-$n.json"; done
  printf '[{"number":21,"head":{"ref":"fitur/x"},"base":{"ref":"main"}},{"number":22,"head":{"ref":"stack-child"},"base":{"ref":"stack-base"}}]' > "$CL/open.json"
}
CLN() { (cd "$CL/w" && GH_REPO=o/r PATH="$CL/bin:$PATH" bash "$root/scripts/cleanup.sh" "$@" 2>"$CL/err"); }
TBL() { cut -f1,2,4,5 | LC_ALL=C sort | paste -sd'|' -; }
MK
EXP='cabang-lokal	fitur/x	leluhur	lewati:pr-terbuka|cabang-lokal	issue-1	leluhur	hapus|cabang-lokal	issue-2	-	lewati:belum-ter-merge|cabang-lokal	issue-3	pr-merged	hapus|cabang-lokal	issue-4	-	lewati:belum-ter-merge|cabang-lokal	issue-5	leluhur	hapus|cabang-lokal	issue-6	leluhur	lewati:checkout|cabang-lokal	issue-7	leluhur	lewati:checkout|cabang-lokal	issue-8	leluhur	lewati:checkout|cabang-lokal	stack-base	leluhur	lewati:base-pr-terbuka|cabang-lokal	stack-child	-	lewati:pr-terbuka|cabang-remote	fitur/x	leluhur	lewati:pr-terbuka|cabang-remote	issue-1	leluhur	hapus|cabang-remote	issue-2	-	lewati:belum-ter-merge|cabang-remote	issue-3	pr-merged	hapus|cabang-remote	issue-4	pr-merged	hapus|cabang-remote	issue-5	leluhur	hapus|cabang-remote	issue-6	leluhur	hapus|cabang-remote	issue-7	leluhur	hapus|cabang-remote	issue-8	leluhur	hapus|cabang-remote	stack-base	leluhur	lewati:base-pr-terbuka|cabang-remote	stack-child	-	lewati:pr-terbuka|worktree	w-detached	-	lewati:tanpa-cabang|worktree	w-wt-5	leluhur	hapus|worktree	w-wt-6	-	lewati:kotor|worktree	w-wt-7	-	lewati:terkunci|worktree	w-wt-8	-	lewati:orca'
ok "cleanup laporan: kandidat, bukti, dan semua perlindungan (tabel lengkap)" "$(CLN --no-fetch | TBL)" "$EXP"
ok "cleanup laporan: bawaan tidak menghapus apa pun" "$(G for-each-ref refs/heads | wc -l | tr -d ' ')" 13
ok "cleanup laporan: main dan integ (bawaan dan integrasi) tidak pernah tampil" "$(CLN --no-fetch | cut -f2 | grep -cxE 'main|integ')" 0
ok "cleanup laporan: dengan fetch (tanpa --no-fetch) hasilnya sama" "$(CLN | TBL)" "$EXP"
ok "cleanup laporan: --only orkestrator hanya issue-N dan w-wt-N" "$(CLN --no-fetch --only orkestrator | cut -f2 | grep -cvE '^(issue-[0-9]+|w-wt-[0-9]+)$')" 0
OPEN_FAIL=1 CLN --no-fetch | grep -q "^cabang-remote.issue-1.*lewati:pr-tak-terbaca"; ok "cleanup laporan: daftar PR terbuka tak terbaca -> remote lewati:pr-tak-terbaca" $? 0
G remote set-head origin integ >/dev/null; ok "cleanup laporan: cabang bawaan bukan main (origin/HEAD=integ) dikenali" "$(CLN --no-fetch | cut -f2 | grep -cxE 'integ')" 0; G remote set-head origin main >/dev/null
printf -- '- Backend: gitlab — repo: o/r\n' > "$CL/w/docs/WORKFLOW.md"; out="$(CLN --no-fetch)"; rc=$?; ok "cleanup: Backend gitlab -> exit 0, pesan tidak didukung, tanpa tabel" "$rc|$(grep -c 'tidak didukung' "$CL/err")|$(grep -c . <<<"$out")" '0|1|0'

# 3k-2. cleanup.sh --apply: urutan worktree -> cabang lokal -> remote; hanya yang terbukti; SHA dicetak; idempoten
LB() { G for-each-ref --format='%(refname:short)' refs/heads | LC_ALL=C sort | paste -sd' ' -; }
RB() { git --git-dir="$CL/remote.git" for-each-ref --format='%(refname:short)' refs/heads | LC_ALL=C sort | paste -sd' ' -; }
MK; OUT="$(CLN --no-fetch --apply)"; rc=$?
ok "cleanup apply: exit 0" $rc 0
ok "cleanup apply: cabang lokal tersisa hanya yang tak terbukti/dilindungi" "$(LB)" 'fitur/x integ issue-2 issue-4 issue-6 issue-7 issue-8 main stack-base stack-child'
ok "cleanup apply: cabang remote tersisa hanya yang tak terbukti/dilindungi" "$(RB)" 'fitur/x integ issue-2 main stack-base stack-child'
ok "cleanup apply: worktree bersih dihapus; kotor, terkunci, terlepas, Orca tetap ada" "$([ -d "$CL/w-wt-5" ] && echo ada || echo hilang)|$([ -d "$CL/w-wt-6" ] && echo ada)|$([ -d "$CL/w-wt-7" ] && echo ada)|$([ -d "$CL/w-detached" ] && echo ada)|$([ -d "$CL/orca/workspaces/w-wt-8" ] && echo ada)" 'hilang|ada|ada|ada|ada'
SHA1="$(awk -F'\t' '$1=="cabang-lokal" && $2=="issue-1"{print $3}' <<<"$OUT")"
ok "cleanup apply: SHA ujung dicetak (40 hex) dan aksi dihapus" "$(grep -c "^cabang-lokal.issue-1.${SHA1}.leluhur.dihapus" <<<"$OUT")|${#SHA1}" '1|40'
G branch pulih "$SHA1" 2>/dev/null; ok "cleanup apply: cabang yang dihapus dapat dipulihkan dari SHA yang dicetak" "$(G rev-parse --verify -q refs/heads/pulih >/dev/null && echo pulih)" pulih
G branch -q -D pulih; OUT2="$(CLN --no-fetch --apply)"; rc=$?; ok "cleanup apply: dijalankan lagi -> tak ada yang dihapus, exit 0" "$rc|$(grep -c $'\tdihapus$' <<<"$OUT2")" '0|0'
MK; CLN --no-fetch --issue 1 --apply >/dev/null; ok "cleanup apply --issue 1: hanya issue-1 yang hilang" "$(LB | tr ' ' '\n' | grep -cE '^issue-(1)$')|$(LB | tr ' ' '\n' | grep -cE '^issue-3$')" '0|1'
MK; G checkout -q -b bebas main; echo b > "$CL/w/bebas.txt"; G add -A; G commit -q -m bebas; G push -q origin bebas; G checkout -q main; G merge -q --no-ff bebas -m "merge bebas"; G push -q origin main
CLN --no-fetch --only orkestrator --apply >/dev/null; ok "cleanup apply --only orkestrator: cabang ter-merge bernama bebas tidak disentuh" "$(LB | tr ' ' '\n' | grep -cx bebas)|$(RB | tr ' ' '\n' | grep -cx bebas)" '1|1'
MK; git --git-dir="$CL/remote.git" branch -q -D issue-1; OUT="$(CLN --no-fetch --apply)"; rc=$?
ok "cleanup apply: cabang remote yang sudah dihapus GitHub -> dihapus (idempoten), exit 0" "$rc|$(grep -c $'^cabang-remote\tissue-1\t.*\tdihapus$' <<<"$OUT")" '0|1'
MK; G remote set-url origin "$CL/tidak-ada.git"; OUT="$(CLN --no-fetch --apply)"; rc=$?
ok "cleanup apply: push gagal (bukan 'sudah terhapus') -> lewati:gagal dan exit 1, lokal tetap diproses" "$rc|$(grep -c $'^cabang-remote.*lewati:gagal' <<<"$OUT" | awk '{print ($1>0)?"ada":"nol"}')|$(LB | tr ' ' '\n' | grep -cx issue-1)" '1|ada|0'

# 3k-3. cleanup.sh --setelah-merge: opsi WORKFLOW "Bersihkan setelah merge", langkah 8 orchestrate, izin update-ref
WFO() { printf -- '- Backend: github — repo: o/r\n%s' "$1" > "$CL/w/docs/WORKFLOW.md"; }   # tanpa baris Cabang integrasi: workflow.sh memakai berkas lokal
MK; WFO '- Bersihkan setelah merge: ya\n'; CLN --no-fetch --setelah-merge --issue 1 >/dev/null
ok "setelah-merge: opsi ya -> issue-1 terhapus (lokal dan remote), issue-3 tidak disentuh" "$(LB | tr ' ' '\n' | grep -cx issue-1)|$(RB | tr ' ' '\n' | grep -cx issue-1)|$(LB | tr ' ' '\n' | grep -cx issue-3)" '0|0|1'
MK; WFO ''; CLN --no-fetch --setelah-merge --issue 1 >/dev/null; ok "setelah-merge: baris hilang = bawaan ya -> terhapus" "$(LB | tr ' ' '\n' | grep -cx issue-1)" 0
MK; WFO '- Bersihkan setelah merge: laporkan\n'; out="$(CLN --no-fetch --setelah-merge --issue 1)"; rc=$?
ok "setelah-merge: opsi laporkan -> hanya melaporkan, tidak ada yang terhapus" "$rc|$(LB | tr ' ' '\n' | grep -cx issue-1)|$(grep -c $'\thapus$' <<<"$out")" '0|1|2'
MK; WFO '- Bersihkan setelah merge: tidak\n'; out="$(CLN --no-fetch --setelah-merge --issue 1)"; rc=$?
ok "setelah-merge: opsi tidak -> tanpa keluaran, tidak terhapus, exit 0" "$rc|$(grep -c . <<<"$out")|$(LB | tr ' ' '\n' | grep -cx issue-1)" '0|0|1'
MK; WFO '- Bersihkan setelah merge: mungkin\n'; CLN --no-fetch --setelah-merge --issue 1 >/dev/null; ok "setelah-merge: nilai tak dikenal diperlakukan laporkan (aman)" "$(LB | tr ' ' '\n' | grep -cx issue-1)" 1
CLN --setelah-merge >/dev/null 2>&1; ok "setelah-merge tanpa --issue -> exit 64" $? 64
MK; WFO '- Bersihkan setelah merge: ya\n'; CLN --no-fetch --setelah-merge --issue 5 >/dev/null
ok "setelah-merge --issue 5: worktree w-wt-5 dan cabang issue-5 terhapus dalam satu putaran" "$([ -d "$CL/w-wt-5" ] && echo ada || echo hilang)|$(LB | tr ' ' '\n' | grep -cx issue-5)" 'hilang|0'
grep -q 'Bersihkan setelah merge:' templates/WORKFLOW.md; ok "templat WORKFLOW memuat 'Bersihkan setelah merge:'" $? 0
grep -q 'cleanup.sh --setelah-merge' skills/orchestrate/SKILL.md && grep -q 'tidak pernah menghentikan' skills/orchestrate/SKILL.md; ok "orchestrate langkah 8 memanggil cleanup.sh --setelah-merge dan 'tidak pernah menghentikan'" $? 0
jq -e '.permissions.allow|index("Bash(git update-ref:*)")' templates/autopilot-permissions.json >/dev/null; ok "autopilot-permissions.json memuat git update-ref" $? 0

# 3k-4. preflight.sh: setelan GitHub hapus-cabang-saat-merge dan jumlah cabang ter-merge (bukti offline)
PF() { (cd "$CL/w" && GH_REPO=o/r PATH="$CL/bin:$PATH" bash "$root/scripts/preflight.sh" github 2>&1); }
MK; out="$(DBM=false PF)"; ok "preflight: delete_branch_on_merge=false -> AWAS beserta perintah PATCH" "$(grep -c '^AWAS.*delete_branch_on_merge=false.*gh api -X PATCH repos/o/r -F delete_branch_on_merge=true' <<<"$out")" 1
out="$(DBM=true PF)"; ok "preflight: delete_branch_on_merge=true -> ok" "$(grep -c '^ok.*cabang dihapus otomatis saat merge' <<<"$out")|$(grep -c 'delete_branch_on_merge=false' <<<"$out")" '1|0'
ok "preflight: ada cabang ter-merge -> info jumlah (bukti offline)" "$(DBM=true PF | grep -c '^info.* 7 cabang ter-merge')" 1
rm -f "$CL/ghlog"; DBM=true GHLOG="$CL/ghlog" PF >/dev/null; ok "preflight: tidak memanggil REST pulls (bukti offline saja)" "$(grep -c 'pulls' "$CL/ghlog" 2>/dev/null; true)" 0
G remote remove origin; ok "preflight: tanpa remote -> tanpa baris info jumlah" "$(DBM=true PF | grep -c 'cabang ter-merge')" 0

# 3k-5. README menjelaskan pembersihan cabang/worktree dan perubahan perilaku bawaan
grep -q 'cleanup.sh' README.md && grep -q 'Bersihkan setelah merge' README.md && grep -q 'bawaan `ya`' README.md && grep -q 'delete_branch_on_merge' README.md; ok "README: cleanup.sh, Bersihkan setelah merge, bawaan ya, delete_branch_on_merge" $? 0

# 3k-6. perbaikan hasil review akhir (keselamatan data)
RG="$(command -v git)"; mkdir -p "$CL/gbin"; printf '#!/usr/bin/env bash\nif [ "$1" = worktree ] && [ "$2" = remove ]; then echo "fatal: simulasi gagal" >&2; exit 1; fi\nexec "$REAL_GIT" "$@"\n' > "$CL/gbin/git"; chmod +x "$CL/gbin/git"
# opsi WORKFLOW: huruf kapital, markup, baris ada tapi tak terbaca, dan WORKFLOW.md tak terbaca -> tidak menghapus
for wv in '- Bersihkan setelah merge: Tidak' '- **Bersihkan setelah merge:** tidak' '- Bersihkan setelah merge: `Laporkan`' '- Bersihkan setelah merge: {{ya (bawaan) | laporkan | tidak}}'; do
  MK; WFO "$wv"$'\n'; CLN --no-fetch --setelah-merge --issue 1 >/dev/null; ok "setelah-merge: '$wv' -> tidak menghapus" "$(LB | tr ' ' '\n' | grep -cx issue-1)" 1
done
MK; WFO '- Bersihkan setelah merge: YA\n'; CLN --no-fetch --setelah-merge --issue 1 >/dev/null; ok "setelah-merge: 'YA' (kapital) dibaca sebagai ya -> menghapus" "$(LB | tr ' ' '\n' | grep -cx issue-1)" 0
MK; rm -f "$CL/w/docs/WORKFLOW.md"; CLN --no-fetch --setelah-merge --issue 1 >/dev/null; ok "setelah-merge: WORKFLOW.md tak terbaca -> tidak menghapus" "$(LB | tr ' ' '\n' | grep -cx issue-1)" 1
# hapus remote dengan CAS: teman mendorong commit setelah fetch -> tidak boleh hilang
MK; rm -rf "$CL/mate"; git clone -q "$CL/remote.git" "$CL/mate" 2>/dev/null; git -C "$CL/mate" checkout -q issue-1; echo more > "$CL/mate/more.txt"; git -C "$CL/mate" add -A; git -C "$CL/mate" commit -q -m more; git -C "$CL/mate" push -q origin issue-1
OUT="$(CLN --no-fetch --apply)"; rc=$?; ok "apply: remote didorong orang lain setelah fetch -> tidak dihapus (CAS), exit 1" "$rc|$(RB | tr ' ' '\n' | grep -cx issue-1)|$(grep -c $'^cabang-remote\tissue-1\t.*lewati:gagal' <<<"$OUT")" '1|1|1'
rm -rf "$CL/mate"
# worktree gagal dihapus -> cabangnya tidak boleh ikut terhapus
MK; OUT="$( (cd "$CL/w" && REAL_GIT="$RG" GH_REPO=o/r PATH="$CL/gbin:$CL/bin:$PATH" bash "$root/scripts/cleanup.sh" --no-fetch --apply 2>/dev/null) )"; rc=$?
ok "apply: git worktree remove gagal -> worktree dan cabang issue-5 tetap ada, exit 1" "$rc|$([ -d "$CL/w-wt-5" ] && echo ada)|$(LB | tr ' ' '\n' | grep -cx issue-5)|$(grep -c $'^worktree\tw-wt-5\t.*lewati:gagal' <<<"$OUT")" '1|ada|1|1'
# cabang bawaan tak dapat ditentukan -> fail-closed
MK; G remote set-head origin -d >/dev/null; out="$(REPO_FAIL=1 CLN --no-fetch --apply)"; rc=$?
ok "apply: cabang bawaan tak diketahui -> exit 1, main tetap ada, pesan jelas" "$rc|$(LB | tr ' ' '\n' | grep -cx main)|$(grep -c 'cabang bawaan' "$CL/err")" '1|1|1'
ok "hitung: cabang bawaan tak diketahui -> 0 (preflight diam)" "$(REPO_FAIL=1 CLN --hitung)" 0
# cabang dan worktree baru tanpa commit (ujung sama dengan basis) tidak boleh dihapus
MK; G branch issue-9 main; G push -q origin issue-9; G worktree add -q "$CL/w-wt-9" issue-9; OUT="$(CLN --no-fetch --apply)"
ok "apply: issue-9 baru (ujung = basis) -> worktree, cabang lokal, dan remote tetap ada" "$([ -d "$CL/w-wt-9" ] && echo ada)|$(LB | tr ' ' '\n' | grep -cx issue-9)|$(RB | tr ' ' '\n' | grep -cx issue-9)|$(grep -c 'lewati:baru-tanpa-commit' <<<"$OUT")" 'ada|1|1|3'
grep -q 'di-.gitignore' README.md; ok "README: menyebut berkas yang di-.gitignore ikut terhapus bersama worktree" $? 0

# 3k-7. PR bertumpuk: bukti pr-merged hanya sah bila base PR = cabang bawaan/integrasi (kasus nyata Nexora: PR di-merge ke cabang induk, bukan ke integrasi)
MK
for n in 11 12; do G checkout -q -b "issue-$n" main; echo "$n" > "$CL/w/issue-$n.txt"; G add -A; G commit -q -m "issue-$n"; G push -q origin "issue-$n"; G checkout -q main; done
T11="$(G rev-parse issue-11)"; T12="$(G rev-parse issue-12)"
printf '[{"number":31,"merged_at":"2026-11-01T01:32:00Z","head":{"ref":"issue-11","sha":"%s"},"base":{"ref":"issue-10"}}]' "$T11" > "$CL/pr-issue-11.json"   # di-merge ke cabang induk issue-10
printf '[{"number":32,"merged_at":"2026-11-01T01:32:00Z","head":{"ref":"issue-12","sha":"%s"},"base":{"ref":"integ"}}]' "$T12" > "$CL/pr-issue-12.json"      # di-merge ke cabang integrasi
OUT="$(CLN --no-fetch --apply)"
ok "PR merged ke cabang induk (bukan bawaan/integrasi) -> bukan bukti ter-merge, issue-11 tetap ada (lokal dan remote)" "$(LB | tr ' ' '\n' | grep -cx issue-11)|$(RB | tr ' ' '\n' | grep -cx issue-11)|$(grep -c $'^cabang-lokal\tissue-11\t.*\t-\tlewati:belum-ter-merge' <<<"$OUT")" '1|1|1'
ok "PR merged ke cabang integrasi -> tetap bukti sah, issue-12 dihapus" "$(LB | tr ' ' '\n' | grep -cx issue-12)|$(RB | tr ' ' '\n' | grep -cx issue-12)" '0|0'
MK; DBM=false out="$(cd "$CL/w" && GH_REPO=o/r PATH="$CL/bin:$PATH" bash "$root/scripts/preflight.sh" github 2>&1)"; ok "preflight: AWAS menyebut dampak PR bertumpuk salah-base" "$(grep -c 'PR bertumpuk' <<<"$out")" 1

[ "$fails" = 0 ] && echo "SEMUA LULUS" || { echo "$fails GAGAL"; exit 1; }
