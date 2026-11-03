#!/usr/bin/env bash
# Probe whether Codex delegation can work: api.github.com reachable and gh authenticated.
# Prints "codex-ready" (exit 0) or "codex-unavailable: <reason>" (exit 1).
if ! curl -sI --max-time 5 https://api.github.com >/dev/null 2>&1; then
  echo "codex-unavailable: api.github.com unreachable"; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "codex-unavailable: gh auth status failed"; exit 1
fi
echo "codex-ready"
