#!/usr/bin/env bash
# PreToolUse/Bash: blocks commit/PR/issue commands that carry AI attribution. Exit 2 = block.
in="$(cat)"
echo "$in" | grep -qiE 'git (-C [^ ]+ )?commit|gh (pr|issue)|glab (mr|issue)' || exit 0
if echo "$in" | grep -qiE 'co-authored-by|generated with'; then
  echo "Diblokir: atribusi AI (Co-Authored-By / Generated with) dilarang. Hapus barisnya lalu ulangi." >&2
  exit 2
fi
