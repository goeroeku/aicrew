#!/usr/bin/env bash
# aicrew blocked-list: open issues labelled `blocked`, one per line "#<n><TAB><reason>" (reason = latest comment starting "blocked:" or "blocked-by-permission:", else "-").
set -u
source "$(dirname "$0")/ghx.sh"
if ghx_local; then   # mode lokal: isu dan komentar dari store
  for n in $(ls_list open blocked 1000 | jq -r '.[].number'); do
    printf '#%s\t%s\n' "$n" "$(ls_comments "$n" | jq -r '[.[]|(.body // "")|select(startswith("blocked:") or startswith("blocked-by-permission:"))]|last // "blocked: -"|split("\n")[0]|sub("^blocked: *";"")|.[0:300]')"
  done; exit 0
fi
gh issue list --state open --limit 200 --json number,labels,comments | jq -r '.[]?|select((.labels // [])|map(.name)|index("blocked"))|"#\(.number)\t\([(.comments // [])[]|(.body // "")|select(startswith("blocked:") or startswith("blocked-by-permission:"))]|last // "blocked: -"|split("\n")[0]|sub("^blocked: *";"")|.[0:300])"'
