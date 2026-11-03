#!/usr/bin/env bash
# aicrew blocked-list: open issues labelled `blocked`, one per line "#<n><TAB><reason>" (reason = latest comment starting "blocked:" or "blocked-by-permission:", else "-").
set -u
gh issue list --state open --limit 200 --json number,labels,comments | jq -r '.[]?|select((.labels // [])|map(.name)|index("blocked"))|"#\(.number)\t\([(.comments // [])[]|(.body // "")|select(startswith("blocked:") or startswith("blocked-by-permission:"))]|last // "blocked: -"|split("\n")[0]|sub("^blocked: *";"")|.[0:300])"'
