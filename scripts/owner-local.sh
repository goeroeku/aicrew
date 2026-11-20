#!/usr/bin/env bash
# aicrew owner-local: persetujuan pemilik untuk `Quota mode: local` (#159 tahap 4B). HANYA pemilik, di terminal interaktif.
#   owner-local.sh approve <n>     setujui merge isu #n pada ujung cabang issue-<n> SAAT INI (sha terikat; dorong ulang = setujui ulang)
#   owner-local.sh status <n>      apakah ujung cabang issue-<n> saat ini sudah disetujui
#   owner-local.sh list            semua persetujuan (waktu, isu, sha7, sah/tidak)
# approve menolak (exit 3) tanpa TTY di stdin dan stdout: agen yang berjalan tanpa terminal tidak dapat menyetujui; izin agen juga menolak perintah ini.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/lib/msg.sh"; source "$here/ghx.sh"; source "$here/lib/ownerlocal.sh"
cmd="${1:-}"; n="${2:-}"
head_of() { git rev-parse "refs/heads/issue-$1" 2>/dev/null; }
case "$cmd" in
  approve)
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "usage: owner-local.sh approve <issue-number>" >&2; exit 64; }
    { [ -t 0 ] && [ -t 1 ]; } || { echo "$(msg ownerlocal.need_tty)" >&2; exit 3; }
    sha="$(head_of "$n")" || { echo "$(msg ownerlocal.no_branch "$n")" >&2; exit 1; }
    g="$(git rev-parse --git-common-dir)"; root="$(cd "$g/.." && pwd)"; dflt="$(git -C "$root" symbolic-ref -q --short HEAD 2>/dev/null)" || dflt=HEAD
    echo "$(msg ownerlocal.summary "$n" "$(ls_view "$n" 2>/dev/null | jq -r '.title // "-"')" "${sha:0:7}")"
    echo "$(msg ownerlocal.reasons) $(bash "$here/local-merge.sh" "$n" "$dflt" "issue-$n" --dry 2>&1 | tail -3 | paste -sd' ' -)"   # alasan (needs:) atau penolakan keras
    git diff --stat=100 "$dflt...$sha" 2>/dev/null | cut -c1-140   # semua berkas, terhadap cabang bawaan
    printf '%s ' "$(msg ownerlocal.confirm)" > /dev/tty; read -r a < /dev/tty
    [ "$a" = yes ] || { echo "$(msg ownerlocal.cancelled)"; exit 1; }
    ol_record "$n" "$sha" merge || { echo "$(msg ownerlocal.write_failed)" >&2; exit 1; }
    echo "$(msg ownerlocal.approved "$n" "${sha:0:7}")" ;;
  status)
    [[ "$n" =~ ^[0-9]+$ ]] || exit 64; sha="$(head_of "$n")" || exit 1
    if ol_approved "$n" "$sha" merge; then echo "$(msg ownerlocal.status_yes "$n" "${sha:0:7}")"; else echo "$(msg ownerlocal.status_no "$n" "${sha:0:7}")"; exit 1; fi ;;
  list)
    log="$(_ol_log)" || exit 1; [ -s "$log" ] || { echo "-"; exit 0; }
    while IFS='|' read -r ts nn sha sc cx mac; do
      ok=tidak; [ -n "$mac" ] && [ "$(_ol_hmac "$ts|$nn|$sha|$sc|$cx")" = "$mac" ] && ok=sah
      printf '%s\t#%s\t%s\t%s\t%s\n' "$(date -r "$ts" '+%F %T' 2>/dev/null || echo "$ts")" "$nn" "${sha:0:7}" "$sc" "$ok"
    done < "$log" ;;
  *) echo "usage: owner-local.sh approve <n> | status <n> | list" >&2; exit 64 ;;
esac
