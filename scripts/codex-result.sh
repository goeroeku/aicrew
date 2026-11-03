#!/usr/bin/env bash
# Decide whether Codex produced a usable result in <worktree>: any tracked diff vs HEAD or untracked file.
# Exit 0 = usable; exit 1 + "codex unavailable: empty diff" = caller falls back to a Claude subagent.
wt="${1:-}"
if [ -d "$wt" ] && { [ -n "$(git -C "$wt" diff --stat HEAD 2>/dev/null)" ] || [ -n "$(git -C "$wt" ls-files --others --exclude-standard 2>/dev/null)" ]; }; then
  exit 0
fi
echo "codex unavailable: empty diff"; exit 1
