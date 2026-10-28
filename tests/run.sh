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
case "$*" in *baseRefName*) echo "$BASE" ;; *body*) printf '%s\n' "$BODY" ;; esac
EOF
chmod +x "$tmp/bin/gh"; P="$tmp/bin:$PATH"; M="bash $root/scripts/pr-merge-check.sh"
BASE=integrasi BODY="Closes #1" PATH="$P" $M 9 integrasi >/dev/null; ok "pr-merge: basis benar" $? 0
BASE=main BODY="Closes #1" PATH="$P" $M 9 integrasi >/dev/null; ok "pr-merge: basis salah -> exit 1" $? 1
out="$(BASE=integrasi BODY="Closes #4, #5" PATH="$P" $M 9 integrasi)"
case "$out" in *PERINGATAN*) r=ada ;; *) r=tidak ;; esac; ok "pr-merge: 'Closes #4, #5' diperingatkan" $r ada
out="$(BASE=integrasi BODY=$'Closes #4\nCloses #5' PATH="$P" $M 9 integrasi)"
case "$out" in *PERINGATAN*) r=ada ;; *) r=tidak ;; esac; ok "pr-merge: satu per baris tidak diperingatkan" $r tidak

# 2b. budget total, resume.sh, autopilot.sh (gh dan claude palsu)
cd "$tmp/r" || exit 1; rm -rf .aicrew
$B iter >/dev/null; $B iter >/dev/null; $B newrun; $B check 5 2 "" 2 >/dev/null; ok "budget: newrun nol-kan putaran, total tetap -> exit 4" $? 4
$B check 5 2 "" 9 >/dev/null; ok "budget: total di bawah batas -> exit 0" $? 0
F="$tmp/fake"; mkdir -p "$F"; export FAKE="$F"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
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
if git rev-parse --git-dir >/dev/null 2>&1 && git rev-parse -q --verify HEAD >/dev/null; then
  lst="$(git archive --worktree-attributes HEAD | tar -t)"
  printf '%s\n' "$lst" | grep -q '^LICENSE$'; ok "arsip rilis memuat LICENSE" $? 0
  printf '%s\n' "$lst" | grep -q '^\.claude-plugin/plugin.json$'; ok "arsip rilis memuat plugin.json" $? 0
  printf '%s\n' "$lst" | grep -qE '^\.github/|^\.gitignore$|^\.gitattributes$'; ok "arsip rilis tanpa infrastruktur repo (.github, .gitignore)" $? 1
fi

# 3. konsistensi plugin
cd "$root" || exit 1
for f in scripts/*.sh tests/run.sh; do bash -n "$f"; ok "sintaks $f" $? 0; done
for s in $(grep -rhoE 'scripts/[a-z-]+\.sh' skills templates agents hooks 2>/dev/null | sort -u); do
  [ -f "$s" ]; ok "dirujuk ada: $s" $? 0
done
for f in templates/WORKFLOW.md skills/kickoff/SKILL.md skills/orchestrate/SKILL.md agents/principal.md; do grep -q 'principal-auto\|ESKALASI' "$f"; ok "principal-auto disebut di $f" $? 0; done
grep -q 'keputusan-otomatis' templates/WORKFLOW.md && grep -q 'keputusan-otomatis' skills/orchestrate/SKILL.md && grep -q 'keputusan-otomatis' scripts/release-report.sh; ok "label keputusan-otomatis konsisten (template, skill, laporan rilis)" $? 0
for k in skills/*/SKILL.md; do head -1 "$k" | grep -q '^---$'; ok "frontmatter $k" $? 0; done

[ "$fails" = 0 ] && echo "SEMUA LULUS" || { echo "$fails GAGAL"; exit 1; }
