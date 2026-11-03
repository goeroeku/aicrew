#!/usr/bin/env bash
# aicrew autonomy: nyalakan/matikan izin sementara untuk sesi otonom (#116). Dijalankan oleh OWNER saja.
# Pakai:
#   autonomy.sh on <until> [--branch <cabang>] [--file <settings.json>]...
#   autonomy.sh off
#   autonomy.sh status
set -u

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/grants.sh
source "$here/lib/grants.sh"
# shellcheck source=lib/merge-mode.sh
[ ! -f "$here/lib/merge-mode.sh" ] || source "$here/lib/merge-mode.sh"

AUTONOMY_ALLOW=(
  "Bash(gh pr merge:*)"
  "Bash(rtk gh pr merge:*)"
  "Bash(git merge:*)"
  "Bash(rtk git merge:*)"
  "Bash(git rebase:*)"
  "Bash(rtk git rebase:*)"
)

usage() {
  echo "pakai: autonomy.sh on <until> [--branch <cabang>] [--file <settings.json>]... | off | status" >&2
  exit 64
}

cmd="${1:-}"
case "$cmd" in
  on|off|status|_expire) shift ;;
  *) usage ;;
esac

until_arg=""
branch_arg=""
file_args=()
case "$cmd" in
  on)
    while [ $# -gt 0 ]; do
      case "$1" in
        --branch)
          [ $# -ge 2 ] && [ -n "${2:-}" ] || usage
          branch_arg="$2"
          shift 2 ;;
        --file)
          [ $# -ge 2 ] && [ -n "${2:-}" ] || usage
          file_args+=("$2")
          shift 2 ;;
        -*)
          usage ;;
        *)
          [ -z "$until_arg" ] || usage
          until_arg="$1"
          shift ;;
      esac
    done
    [ -n "$until_arg" ] || usage ;;
  off|status|_expire)
    [ $# -eq 0 ] || usage ;;
esac

command -v jq >/dev/null 2>&1 || { echo "autonomy: jq tidak terpasang" >&2; exit 2; }
top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "autonomy: bukan repo git" >&2; exit 2; }

state_dir="$top/.aicrew"
state_file="$state_dir/autonomy.json"
lock_dir="$state_dir/autonomy.lock"
wf_file="$top/docs/WORKFLOW.md"
tpl_file="$here/../templates/autopilot-permissions.json"

autonomy_allow_json() {
  printf '%s\n' "${AUTONOMY_ALLOW[@]}" | jq -R . | jq -sc .
}

helper_alive() {
  local pid="${1:-}" pcmd
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  pcmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  case "$pcmd" in *autonomy.sh*) return 0 ;; esac
  return 1
}

kill_helper() {
  local pid="${1:-}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  [ "$pid" != "$$" ] && [ "$pid" != "${PPID:-}" ] || return 0
  if helper_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

acquire_lock() {
  mkdir -p "$state_dir" 2>/dev/null || { echo "autonomy: gagal membuat $state_dir" >&2; exit 2; }
  mkdir "$lock_dir" 2>/dev/null || { echo "autonomy: sedang terkunci ($lock_dir)" >&2; exit 1; }
  trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
}

revoke_file() {
  local fobj="$1" allow_const="$2" mode="$3"
  local f bak created rec_added tpl_mode_allow tpl_base_allow keep_allow rem had_perm="true" had_allow="true"
  f="$(jq -r '.path // empty' <<<"$fobj")"
  bak="$(jq -r '.backup // empty' <<<"$fobj")"
  created="$(jq -r '.created // false' <<<"$fobj")"
  rec_added="$(jq -c '.added_allow // []' <<<"$fobj")"
  [ -n "$f" ] || return 0
  [ -n "$bak" ] || bak="$f.bak-autonomy"
  if [ ! -f "$f" ]; then
    rm -f "$bak"
    return 0
  fi
  jq -e 'type == "object"' "$f" >/dev/null 2>&1 || { echo "autonomy: JSON rusak di $f" >&2; return 2; }

  tpl_mode_allow="[]"
  tpl_base_allow="[]"
  if [ -f "$tpl_file" ]; then
    tpl_mode_allow="$(jq -c --arg m "$mode" '.modes[$m].allow // []' "$tpl_file" 2>/dev/null || echo '[]')"
    if jq -e '(.permissions.allow // []) | index("Bash(gh issue:*)") != null' "$f" >/dev/null 2>&1; then
      tpl_base_allow="$(jq -c '.permissions.allow // []' "$tpl_file" 2>/dev/null || echo '[]')"
    fi
  fi
  keep_allow="$(jq -nc --argjson m "$tpl_mode_allow" --argjson b "$tpl_base_allow" '($m + $b) | unique')"
  if [ -f "$bak" ] && jq -e 'type == "object"' "$bak" >/dev/null 2>&1; then
    keep_allow="$(jq -c --argjson k "$keep_allow" '((.permissions.allow // []) + $k) | unique' "$bak")"
    jq -e 'has("permissions")' "$bak" >/dev/null 2>&1 || had_perm="false"
    jq -e '(.permissions | type) == "object" and (.permissions | has("allow"))' "$bak" >/dev/null 2>&1 || had_allow="false"
  fi

  rem="$(jq -nc --argjson add "$rec_added" --argjson allow "$allow_const" --argjson keep "$keep_allow" '
    [ $add[] | select((. as $x | ($allow | index($x)) != null) and (. as $x | ($keep | index($x)) == null)) ]
  ')"

  jq --argjson rem "$rem" --argjson hp "$had_perm" --argjson ha "$had_allow" '
    if (.permissions | type) == "object" and (.permissions.allow | type) == "array" then
      .permissions.allow = (.permissions.allow - $rem)
      | if ($ha | not) and (.permissions.allow | length == 0) then del(.permissions.allow) else . end
      | if ($hp | not) and (.permissions | length == 0) then del(.permissions) else . end
    else . end
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f" || { rm -f "$f.tmp"; echo "autonomy: gagal menulis $f" >&2; return 2; }

  if [ "$created" = "true" ]; then
    if jq -e '((.permissions.allow // []) | length == 0) and ((.permissions.deny // []) | length == 0) and ((del(.permissions) | keys | length) == 0) and (((.permissions // {}) | del(.allow, .deny) | keys | length) == 0)' "$f" >/dev/null 2>&1; then
      rm -f "$f" "$bak"
      return 0
    fi
  elif [ -f "$bak" ] && jq -e 'type == "object"' "$bak" >/dev/null 2>&1; then
    if [ "$(jq -Sc . "$f" 2>/dev/null)" = "$(jq -Sc . "$bak" 2>/dev/null)" ]; then
      cp "$bak" "$f.tmp" && mv "$f.tmp" "$f" || true
    fi
  fi
  rm -f "$bak"
  return 0
}

update_workflow() {
  local wf="$1" gline="$2"
  mkdir -p "$(dirname "$wf")" 2>/dev/null || { echo "autonomy: gagal membuat direktori $(dirname "$wf")" >&2; return 2; }
  [ -f "$wf" ] || : > "$wf" || { echo "autonomy: gagal membuat $wf" >&2; return 2; }
  awk -v gl="$gline" '
    BEGIN { sec = 0; seen = 0; done_gl = 0; sec_count = 0 }
    /^## Temporary grants$/ && !seen {
      seen = 1; sec = 1
      print
      next
    }
    sec && /^#+([ \t]|$)/ {
      flush_sec()
      sec = 0
    }
    sec {
      sec_lines[++sec_count] = $0
      next
    }
    { print }
    function flush_sec(    i, has_existing) {
      has_existing = 0
      for (i = 1; i <= sec_count; i++) {
        if (sec_lines[i] ~ /^- Grant: / && sec_lines[i] ~ /; note=autonomy\.sh$/) has_existing = 1
      }
      if (!has_existing) {
        print gl
        done_gl = 1
      }
      for (i = 1; i <= sec_count; i++) {
        if (sec_lines[i] ~ /^- Grant: / && sec_lines[i] ~ /; note=autonomy\.sh$/) {
          if (!done_gl) { print gl; done_gl = 1 }
          continue
        }
        print sec_lines[i]
      }
    }
    END {
      if (sec) flush_sec()
      if (!seen) {
        print "## Temporary grants"
        print gl
      }
    }
  ' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf" || { rm -f "$wf.tmp"; echo "autonomy: gagal menulis $wf" >&2; return 2; }
  return 0
}

revoke_workflow() {
  local wobj="$1"
  local wf line created_sec
  wf="$(jq -r '.path // empty' <<<"$wobj")"
  line="$(jq -r '.line // empty' <<<"$wobj")"
  created_sec="$(jq -r '.created_section // false' <<<"$wobj")"
  [ -n "$wf" ] && [ -f "$wf" ] || return 0

  awk -v target="$line" -v csec="$created_sec" '
    BEGIN { sec = 0; seen = 0; sec_count = 0 }
    /^## Temporary grants$/ && !seen {
      seen = 1; sec = 1
      sec_hdr = $0
      sec_count = 0
      next
    }
    sec && /^#+([ \t]|$)/ {
      flush_sec()
      sec = 0
    }
    sec {
      if ($0 == target && $0 ~ /^- Grant: / && $0 ~ /; note=autonomy\.sh$/) next
      if ($0 ~ /^- Grant: scope=merge; risk=L2; branch=[A-Za-z0-9._\/-]+; expires=[^;]+; note=autonomy\.sh$/ && target !~ /; note=autonomy\.sh$/) next
      sec_lines[++sec_count] = $0
      next
    }
    { print }
    function flush_sec(    i, nonblank) {
      nonblank = 0
      for (i = 1; i <= sec_count; i++) {
        if (sec_lines[i] !~ /^[ \t]*$/) nonblank = 1
      }
      if (csec == "true" && !nonblank) return
      print sec_hdr
      for (i = 1; i <= sec_count; i++) print sec_lines[i]
    }
    END {
      if (sec) flush_sec()
    }
  ' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf" || { rm -f "$wf.tmp"; echo "autonomy: gagal menulis $wf" >&2; return 2; }
  return 0
}

canon_path() {
  local p="$1" d b
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  d="$(dirname "$p")"; b="$(basename "$p")"
  if [ -d "$d" ]; then
    printf '%s/%s\n' "$(cd "$d" && pwd -P)" "$b"
  else
    printf '%s/%s\n' "$d" "$b"
  fi
}

case "$cmd" in
  on)
    until_epoch="$(grant_epoch "$until_arg")" || { echo "autonomy: format until tidak sah: $until_arg" >&2; exit 1; }
    now="$(date +%s)"
    if [ "$until_epoch" -le "$now" ] || [ $((until_epoch - now)) -gt 604800 ]; then
      echo "autonomy: tenggat harus di masa depan dan paling lama 7 hari: $until_arg" >&2
      exit 1
    fi

    branch="$branch_arg"
    if [ -z "$branch" ] && [ -f "$wf_file" ]; then
      raw_integ="$({ bash "$here/lib/wf-normalize.sh" < "$wf_file"; } 2>/dev/null | grep -i 'Integration branch:' | head -1 || true)"
      case "$raw_integ" in
        *"{{"*|*"}}"*) branch="{{placeholder}}" ;;
        *) branch="$({ bash "$here/lib/wf-normalize.sh" < "$wf_file"; } 2>/dev/null | sed -n 's/^[- ]*.*Integration branch: *\([A-Za-z0-9._\/-]*\).*/\1/p' | head -1 | sed 's/[.,;:]*$//')" ;;
      esac
    fi
    def="$(git -C "$top" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    def="${def#origin/}"
    lc_branch="$(printf '%s' "$branch" | tr '[:upper:]' '[:lower:]')"
    if [ -z "$branch" ] || [ "$lc_branch" = "none" ] || [ "$lc_branch" = "tidak" ] \
      || [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ "$branch" = "origin/HEAD" ] \
      || { [ -n "$def" ] && [ "$branch" = "$def" ]; } \
      || ! [[ "$branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
      echo "autonomy: cabang integrasi tidak sah atau cabang bawaan ditolak: '${branch:-}'" >&2
      exit 1
    fi
    case "$branch" in
      *"{{"*|*"}}"*|*..*|*/|//*|*//*)
        echo "autonomy: cabang integrasi tidak sah: '$branch'" >&2
        exit 1 ;;
    esac

    acquire_lock

    def_settings="$top/.claude/settings.local.json"
    target_files=("$def_settings")
    seen_canon=" $(canon_path "$def_settings") "
    if [ "${#file_args[@]}" -gt 0 ]; then
      for fa in "${file_args[@]}"; do
        case "$fa" in /*) abs_fa="$fa" ;; *) abs_fa="$PWD/$fa" ;; esac
        cfa="$(canon_path "$abs_fa")"
        case "$seen_canon" in
          *" $cfa "*) ;;
          *) target_files+=("$abs_fa"); seen_canon="$seen_canon$cfa " ;;
        esac
      done
    fi

    allow_const="$(autonomy_allow_json)"
    mode="owner"
    if declare -F merge_mode >/dev/null 2>&1; then mode="$(merge_mode "$wf_file")"; fi

    old_state="{}"
    if [ -f "$state_file" ]; then
      jq -e 'type == "object"' "$state_file" >/dev/null 2>&1 || { echo "autonomy: berkas status rusak: $state_file" >&2; exit 2; }
      old_state="$(cat "$state_file")"
      old_pid="$(jq -r '.helper_pid // empty' <<<"$old_state")"
      kill_helper "$old_pid"

      while IFS= read -r old_fobj; do
        [ -n "$old_fobj" ] || continue
        old_p="$(jq -r '.path // empty' <<<"$old_fobj")"
        [ -n "$old_p" ] || continue
        cold_p="$(canon_path "$old_p")"
        case "$seen_canon" in
          *" $cold_p "*) ;;
          *) revoke_file "$old_fobj" "$allow_const" "$mode" || exit $? ;;
        esac
      done < <(jq -c '.files[]?' <<<"$old_state")
    fi

    if jq -e '.workflow.created_section != null' <<<"$old_state" >/dev/null 2>&1; then
      created_sec="$(jq -r '.workflow.created_section' <<<"$old_state")"
    elif [ -f "$wf_file" ] && grep -qxF '## Temporary grants' "$wf_file" 2>/dev/null; then
      created_sec="false"
    else
      created_sec="true"
    fi

    files_json="[]"
    for f in "${target_files[@]}"; do
      cf="$(canon_path "$f")"
      prev_fobj=""
      while IFS= read -r cand_obj; do
        [ -n "$cand_obj" ] || continue
        cp_path="$(jq -r '.path // empty' <<<"$cand_obj")"
        if [ "$cp_path" = "$f" ] || [ "$(canon_path "$cp_path")" = "$cf" ]; then
          prev_fobj="$cand_obj"
          break
        fi
      done < <(jq -c '.files[]?' <<<"$old_state")

      mkdir -p "$(dirname "$f")" 2>/dev/null || { echo "autonomy: gagal membuat direktori $(dirname "$f")" >&2; exit 2; }
      if [ -n "$prev_fobj" ]; then
        created="$(jq -r '.created // false' <<<"$prev_fobj")"
        bak="$(jq -r '.backup // empty' <<<"$prev_fobj")"
        [ -n "$bak" ] || bak="$f.bak-autonomy"
        prev_added="$(jq -c '.added_allow // []' <<<"$prev_fobj")"
        if [ ! -f "$f" ]; then
          echo '{}' > "$f" 2>/dev/null || { echo "autonomy: gagal menulis $f" >&2; exit 2; }
        fi
        jq -e 'type == "object"' "$f" >/dev/null 2>&1 || { echo "autonomy: JSON rusak di $f" >&2; exit 2; }
        cur_allow="$(jq -c '.permissions.allow // []' "$f")"
        missing_allow="$(jq -nc --argjson a "$allow_const" --argjson c "$cur_allow" '$a - $c')"
        added_allow="$(jq -nc --argjson p "$prev_added" --argjson m "$missing_allow" --argjson a "$allow_const" '
          [ $a[] | select((. as $x | ($p | index($x)) != null) or (. as $x | ($m | index($x)) != null)) ]
        ')"
        if [ "$missing_allow" != "[]" ]; then
          jq --argjson add "$missing_allow" '.permissions = ((.permissions // {}) | .allow = (((.allow // []) + $add) | unique))' "$f" > "$f.tmp" && mv "$f.tmp" "$f" || { rm -f "$f.tmp"; echo "autonomy: gagal menulis $f" >&2; exit 2; }
        fi
      else
        bak="$f.bak-autonomy"
        if [ -f "$f" ]; then
          created="false"
          jq -e 'type == "object"' "$f" >/dev/null 2>&1 || { echo "autonomy: JSON rusak di $f" >&2; exit 2; }
          cp "$f" "$bak" 2>/dev/null || { echo "autonomy: gagal menulis cadangan $bak" >&2; exit 2; }
        else
          created="true"
          echo '{}' > "$f" 2>/dev/null || { echo "autonomy: gagal menulis $f" >&2; exit 2; }
          cp "$f" "$bak" 2>/dev/null || { echo "autonomy: gagal menulis cadangan $bak" >&2; exit 2; }
        fi
        cur_allow="$(jq -c '.permissions.allow // []' "$f")"
        added_allow="$(jq -nc --argjson a "$allow_const" --argjson c "$cur_allow" '$a - $c')"
        if [ "$added_allow" != "[]" ] || [ "$created" = "true" ]; then
          jq --argjson add "$added_allow" '.permissions = ((.permissions // {}) | .allow = (((.allow // []) + $add) | unique))' "$f" > "$f.tmp" && mv "$f.tmp" "$f" || { rm -f "$f.tmp"; echo "autonomy: gagal menulis $f" >&2; exit 2; }
        fi
      fi

      files_json="$(jq -nc --argjson arr "$files_json" --arg p "$f" --arg b "$bak" --argjson cr "$created" --argjson aa "$added_allow" '
        $arr + [{path: $p, backup: $b, created: $cr, added_allow: $aa, added_deny: []}]
      ')"
    done

    gline="- Grant: scope=merge; risk=L2; branch=$branch; expires=$until_arg; note=autonomy.sh"
    update_workflow "$wf_file" "$gline" || exit $?

    bash "$here/autonomy.sh" _expire </dev/null >/dev/null 2>&1 &
    hpid=$!
    disown "$hpid" 2>/dev/null || true

    jq -n \
      --arg u "$until_arg" \
      --argjson ue "$until_epoch" \
      --arg br "$branch" \
      --argjson fls "$files_json" \
      --arg wfp "$wf_file" \
      --arg wfl "$gline" \
      --argjson wfcs "$created_sec" \
      --argjson hp "$hpid" \
      '{
        until: $u,
        until_epoch: $ue,
        branch: $br,
        files: $fls,
        workflow: {path: $wfp, line: $wfl, created_section: $wfcs},
        helper_pid: $hp
      }' > "$state_file.tmp" && mv "$state_file.tmp" "$state_file" || { rm -f "$state_file.tmp"; kill_helper "$hpid"; echo "autonomy: gagal menulis $state_file" >&2; exit 2; }

    echo "PERINGATAN: Grant risk=L2 ditambahkan ke docs/WORKFLOW.md (pengecualian sementara #61 untuk 'L2 selalu owner' pada cabang $branch sampai $until_arg)."
    echo "autonomy: aktif sampai $until_arg (cabang $branch, pid $hpid)"
    exit 0 ;;

  off)
    acquire_lock
    if [ ! -f "$state_file" ]; then
      echo "autonomy: mati"
      exit 0
    fi
    jq -e 'type == "object"' "$state_file" >/dev/null 2>&1 || { echo "autonomy: berkas status rusak: $state_file" >&2; exit 2; }
    hpid="$(jq -r '.helper_pid // empty' "$state_file")"
    kill_helper "$hpid"

    mode="owner"
    if declare -F merge_mode >/dev/null 2>&1; then mode="$(merge_mode "$wf_file")"; fi
    allow_const="$(autonomy_allow_json)"

    while IFS= read -r fobj; do
      [ -n "$fobj" ] || continue
      revoke_file "$fobj" "$allow_const" "$mode" || exit $?
    done < <(jq -c '.files[]?' "$state_file")

    wobj="$(jq -c '.workflow // empty' "$state_file")"
    if [ -n "$wobj" ] && [ "$wobj" != "null" ]; then
      revoke_workflow "$wobj" || exit $?
    fi

    rm -f "$state_file" "$state_file.tmp"
    echo "autonomy: dicabut"
    exit 0 ;;

  status)
    ap_pids="$(pgrep -f 'scripts/autopilot\.sh' 2>/dev/null | grep -vx "$$" | grep -vx "${PPID:-}" | tr '\n' ' ' | sed 's/ *$//' || true)"
    if [ ! -f "$state_file" ]; then
      echo "autonomy: mati"
      if [ -n "$ap_pids" ]; then
        echo "autopilot.sh (mungkin milik repo lain): $ap_pids"
      else
        echo "autopilot.sh: tidak ada"
      fi
      exit 0
    fi
    jq -e 'type == "object"' "$state_file" >/dev/null 2>&1 || { echo "autonomy: berkas status rusak: $state_file" >&2; exit 2; }
    u="$(jq -r '.until // ""' "$state_file")"
    ue="$(jq -r '.until_epoch // 0' "$state_file")"
    br="$(jq -r '.branch // ""' "$state_file")"
    hpid="$(jq -r '.helper_pid // ""' "$state_file")"
    wfp="$(jq -r '.workflow.path // ""' "$state_file")"
    wfl="$(jq -r '.workflow.line // ""' "$state_file")"
    now="$(date +%s)"

    if [[ "$ue" =~ ^[0-9]+$ ]] && [ "$now" -ge "$ue" ]; then
      echo "autonomy: aktif sampai $u (cabang $br) — KEDALUWARSA, jalankan: autonomy.sh off"
    else
      echo "autonomy: aktif sampai $u (cabang $br)"
    fi

    while IFS= read -r fobj; do
      [ -n "$fobj" ] || continue
      fp="$(jq -r '.path // ""' <<<"$fobj")"
      cnt="$(jq -r '(.added_allow // []) | length' <<<"$fobj")"
      ents="$(jq -r '(.added_allow // []) | join(", ")' <<<"$fobj")"
      echo "berkas: $fp ($cnt entri: $ents)"
    done < <(jq -c '.files[]?' "$state_file")

    if [ -n "$wfp" ] && [ -f "$wfp" ] && [ -n "$wfl" ] && grep -qxF -- "$wfl" "$wfp" 2>/dev/null; then
      echo "workflow: ada ($wfp: $wfl)"
    else
      echo "workflow: tidak ada ($wfp)"
    fi

    if helper_alive "$hpid"; then
      echo "helper: hidup (pid $hpid)"
    else
      echo "helper: mati${hpid:+ (pid $hpid)}"
    fi

    if [ -n "$ap_pids" ]; then
      echo "autopilot.sh (mungkin milik repo lain): $ap_pids"
    else
      echo "autopilot.sh: tidak ada"
    fi
    exit 0 ;;

  _expire)
    poll="${AUTONOMY_POLL:-30}"
    [[ "$poll" =~ ^[1-9][0-9]*$ ]] || poll=30
    while :; do
      sleep "$poll"
      [ -f "$state_file" ] || exit 0
      exp="$(jq -r '.until_epoch // empty' "$state_file" 2>/dev/null || true)"
      hpid="$(jq -r '.helper_pid // empty' "$state_file" 2>/dev/null || true)"
      [[ "$exp" =~ ^[0-9]+$ ]] || exit 0
      [ -z "$hpid" ] || [ "$hpid" = "$$" ] || exit 0
      now="$(date +%s)"
      if [ "$now" -ge "$exp" ]; then
        exec bash "$here/autonomy.sh" off
      fi
    done ;;
esac
