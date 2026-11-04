#!/usr/bin/env bash
# aicrew file-overlap: dua issue yang membuat atau mengubah berkas yang sama tanpa urutan Blocked by (#60). Deterministik, tanpa model.
#   file-overlap.sh                 issue terbuka dari backend (gh)
#   file-overlap.sh --json FILE|-   larik JSON [{number,body,labels}] (mis. rencana breakdown sebelum issue dibuat)
# Berkas diambil dari baris "- Expected to touch: ..." di bagian "## Related files" (dipisah koma/spasi; `backtick` dan ":baris" dibuang; token tanpa "." atau "/" diabaikan,
# jadi placeholder {{path}} tidak dihitung; nama berkas bersepasi tidak didukung; "./" di depan dan ".,;" di akhir dibuang; huruf besar/kecil dan bullet - atau * diterima). Urutan = ada rantai "## Blocked by" (transitif; owner/repo#n lintas repo tidak dihitung) di salah satu arah. Epic diabaikan.
# Keluaran: "overlap: <berkas> #a #b -> beri #b 'Blocked by #a' (atau pisahkan kepemilikan berkas itu)". Exit 0 tanpa overlap, 1 ada overlap, 2 masukan tak terbaca.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib/msg.sh"
src=""; [ "${1:-}" != --json ] || src="${2:--}"
if [ -n "$src" ]; then if [ "$src" = - ]; then data="$(cat)"; else data="$(cat "$src")" || exit 2; fi
else source "$here/ghx.sh"; data="$(ghx_issues open - 200 number,body,labels)" || exit 2; fi
out="$(jq -r '
  def clos($B): . as $s | {seen:[], q:[$s]} | until(.q|length==0; .q[0] as $x | .q=.q[1:] | if (.seen|index($x)) then . else .seen += [$x] | .q += ($B[($x|tostring)] // []) end) | .seen - [$s];
  [ .[] | select(((.labels // [])|map(.name)|index("epic"))|not)
    | {n:.number, L:((.body // "")|split("\n"))}
    | . + (reduce .L[] as $l ({s:"",t:[],b:[]};
        (if ($l|test("^## ")) then .s=$l else . end)
        | (if ((.s|test("^## Related files";"i")) and ($l|test("^[-*] Expected to touch:";"i")))
            then .t += ($l|sub("^[-*] Expected to touch: *";"";"i")|gsub("`";"")|[splits("[ ,]+")]|map(sub(":[0-9]+(-[0-9]+)?$";"")|sub("[.,;]+$";"")|sub("^\\./";""))|map(select(test("[./]") and (test("[{}]")|not))))
            else . end)
        | (if (.s|test("^## Blocked by")) then .b += ([$l|scan("(?<![A-Za-z0-9_./-])#[0-9]+")|ltrimstr("#")|tonumber]) else . end))) ] as $I
  | ($I|map({key:(.n|tostring), value:.b})|from_entries) as $B
  | ($I|map(.t[])|unique) as $paths
  | $paths[] as $p
  | ([$I[]|select(.t|index($p))|.n]|sort) as $ns
  | range(0; $ns|length) as $i | range($i+1; $ns|length) as $j | $ns[$i] as $a | $ns[$j] as $b
  | select((($a|clos($B))|index($b)|not) and (($b|clos($B))|index($a)|not))
  | "'"$(msg overlap.line '\($p)' '\($a)' '\($b)' '\($b)' '\($a)')"'"
' <<<"$data" 2>/dev/null)" || { echo "$(msg overlap.unparseable)" >&2; exit 2; }
[ -z "$out" ] || { printf '%s\n' "$out"; exit 1; }
exit 0
