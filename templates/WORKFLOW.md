# WORKFLOW — {{project name}}

Created by `aicrew:kickoff`. Project-specific decisions; overrides aicrew defaults.

## Owner decisions
- Profile: {{light | standard | full}}
- Backend: {{github | gitlab}} — repo: {{owner/name}}
- Active roles: {{list}}
- PRD: {{docs/PRD.md}} — PRD status: {{approved | not yet}}
- Existing code: {{yes | no}} (yes → breakdown runs a status audit)
- Worktree: {{created by orchestrator beside the repo (../<repo>-wt-N) | prepared manually / Orca}}
- Worktree base: {{absolute path, e.g. inside an Orca workspace | empty = beside the repo}}. `install-permissions.sh` populates worktree read permissions from here.
- Kanban board: {{none | GitHub Project <owner>/<number>, default statuses: Backlog, Ready, In progress, In review, Done}}
- Done card: {{owner | agent-after-merge}}. Default: owner. `agent-after-merge` (autopilot): the orchestrator moves the card to Done
  after a verified merge (`pr-merge-check.sh --after`) in `agent-after-qa` merge mode; applies only when a Kanban board is active.
- needs-principal: {{owner | principal-auto}}. Default: owner (all levels are escalated to the owner). `principal-auto`: only LEVEL 1 is decided
  by the `aicrew-principal` agent (requires an active principal role); level 2 still goes to the owner. Automatic decisions receive the `auto-decision` label and are included in the release report.
- Risk (`risk:*`, assigned by breakdown): L0 = docs/tests/refactor with no behavioral effect; L1 = normal behavior; L2 = auth, money, personal data, migration, infra, or hard to reverse.
- `epic` = one issue per journey (checklist of child issues). Not work: agents and scripts skip it; the owner closes it when all children are done.
- Integrated label: {{integrated (default) | other name}}. Auto-decision label: {{auto-decision (default) | other name}}. Read by `scripts/label.sh`.
- Discovery label: {{discovery phase:discovery (default) | other name}}. Unsplit epic label: {{unsplit (default) | other name}}. Read by `scripts/label.sh`; an epic only reaches In review when it has at least one non-discovery child.
- Awaiting-release label: {{awaiting-release (default) | other name}}. Applied to issues whose PR adds a scheduled workflow (`schedule`/`workflow_dispatch`) or `dependabot.yml` to a non-default branch: GitHub only activates them from the default branch. The issue stays open until the file exists on the default branch. Read by `scripts/label.sh`.
- No-parent label: {{no-parent (default) | other name}}. Open issues with this label are intentionally outside any epic (e.g. follow-up umbrellas) and are skipped by `epic-link.sh --check`.
- Close issues after integration merge: {{no (default) | yes}}. GitHub only closes issues via merge into the default branch, so epic sub-issue progress stays at 0% until integration reaches `main`; `yes` = `board.sh --sync` closes issues labeled integrated (except `epic`).
- Clean up after merge: {{yes (default) | report | no}}. After a verified merge, `scripts/cleanup.sh --after-merge` removes the `<repo>-wt-<n>` worktree and `issue-<n>` branch (local and remote) that are PROVEN merged (an ancestor of the default/integration branch, or a merged PR with the same tip), without `--force`, and prints the tip SHA so it can be restored. `report` only prints; `no` skips. Branches with other names are never removed automatically: run `scripts/cleanup.sh` (report) then `--apply`. A missing line in an older installation = `yes`. Note: the `<repo>-wt-<n>` worktree is removed along with any git-ignored files inside it (e.g. local `.env`, `node_modules`); `git worktree remove` without force only refuses uncommitted changes or untracked files. Choose `report` if you have such files that are still needed.
- Release notes: {{CHANGELOG.md | external | none (default)}}. `CHANGELOG.md` = `scripts/release-notes.sh` builds a per-version section (Keep a Changelog) from `Release note:` lines in PR bodies at release time; only marked lines are included, and Security comes only from `Release note: Security - ...` lines. `external` (release-please, changesets, etc.) = aicrew does not touch the file. `none` = generates nothing. `CHANGELOG.md` is recommended for new projects.
- CVE check: {{yes (default) | no}}. `yes`: PRs that touch `package-lock.json`, `go.mod`, or `requirements*.txt` are checked against OSV by `scripts/pr-merge-check.sh` (new/changed packages only; HIGH, CRITICAL, or unranked vulnerabilities block unless there is an owner `(cve)` waiver; OSV unreachable = reject). `no` skips the check with a single warning. Full repo audit: `cve-audit` skill. Only ecosystem, package name, and version are sent to OSV.
- Private packages: {{comma-separated patterns, e.g. @company/*, git.company.com/team | empty}}. Matching packages are never sent to OSV and are reported as "not checked" (not safe). Other sources read automatically: `GOPRIVATE` (Go) and project `.npmrc` scopes mapped to non-public registries (npm). Patterns are read from the target branch, so merge a PR containing only this line first.
- Language (messages, replies, issues and documents written for people): {{en (default) | id}}
- Artifact language (code, comments, commits, labels, branch/database names): {{English (default) | other language, only at the owner's request}}
- Track `docs/` in git: {{yes | no (ignored, intentional)}}

## Backend commands (single place, easy to swap)
| Action | Command |
|---|---|
| Create issue | {{gh issue create | glab issue create}} |
| Edit labels | {{gh issue edit | glab issue update}} |
| Open PR/MR | {{gh pr create | glab mr create}} |
| Evidence comment | {{gh pr comment | glab mr note}} |

## Task size
- One task = one observable outcome; ≤ 5 files, ≤ ±200 diff lines.
- Machine-checkable acceptance criteria are required. Without them, return to breakdown.
- Write what and why, not how (except for high-risk tasks).

## Labels
`role:*`, `stack:*`, `phase:*`, `needs-principal`, `needs-security`, `needs-perf`, `auto-decision`, `risk:L0`, `risk:L1`, `risk:L2`, `epic`, `bug`, `enhancement`, `in-progress`, `in-review`, `integrated`
(GitLab: use scoped labels `role::qa`, etc.)

## Owner approval gates
1. PRD is approved before breakdown.
2. First PR/MR is reviewed by the owner (relaxed once trusted).
3. Integration branch: {{name, e.g. feature-x-integration | none}}. Dependent issues stack here,
   not on `main`. Merge PR to integration branch: {{owner | agent-after-qa}}. Default: owner (manual approval).
   `agent-after-qa`: the agent merges on its own only when the full suite is green, `aicrew-qa` passes (and `aicrew-security`
   for sensitive changes labeled `needs-security`; `aicrew-perf` for `needs-perf`), with no `needs-principal` and no `risk:L2` (L2 is always owner; `pr-merge-check.sh --auto` rejects it). Bash permission installed in
   {{settings file, e.g. `.claude/settings.local.json`: `Bash(gh pr merge:*)`}} (chat-based approval does not count).
4. Merge integration branch / PR to `main` and move to Done: {{owner | automatic rule}}. Default: owner.
   Merge to `main` triggers: {{none | workflow name (e.g. deploy)}}.

## Daftar periksa rilis
Run during the closing stage, before the `integration → main` PR is opened (keep the heading `## Daftar periksa rilis` exact because `release-report.sh` reads it back and prints the items as empty checkboxes for agents to fill in; items may be customized per project).
- Clean build in a fresh clone
- Application runs locally; smoke test passes (UI: screenshot read)
- aicrew-security: auth, input, secrets, dependencies; hardening and audit log for `needs-security`
- aicrew-perf: I/O budget, default config, load test on the real server (numbers, not estimates)
- No secrets in the repo
- Short runbook: how to run, configure, and roll back
- Every PRD criterion is checked off with the command and its output

## Hardware limits
Filled in during kickoff. "unknown" (`tidak diketahui`) = not yet measured; `aicrew-perf` must not mark a capacity claim `lulus` when a relevant limit is unknown (the verdict token `lulus`/`gagal` must be written exactly as shown because scripts read it back).
- Disk IOPS (write/read): {{number | unknown}}
- Host RAM and container limits: {{number | unknown}}
- Volume tier/type and mount options (e.g. `discard`): {{value | unknown}}
- Other limits (DB connections, bandwidth, CPU): {{value | unknown}}

## Stop rules (agent marks the issue, moves on to another task, notifies the owner)
- `needs-principal` label (two levels): (1) design decision within PRD bounds (data schema, internal API shape,
  thresholds) → principal decides only when `needs-principal: principal-auto`, otherwise owner; the owner reviews in the PR/release report; (2) conflicts with the PRD/non-goals, auth, money, personal
  data, or hard to reverse → escalate to the owner, do not decide yourself. When in doubt → escalate.
- Two consecutive failures on the same issue.
- Ambiguous or contradictory requirements.
- Need to modify existing tests or add a dependency.
- Iteration/cost limit reached.

## Temporary grants
Temporary permission from the owner for the `pr-merge-check.sh --auto` gate (keep the heading `## Temporary grants` exact because scripts read it back). First type: `scope=merge; risk=L2`. Written only by the owner; free-text "temporary permission" has no effect.
Single-line format (column 0, in this section only): `- Grant: scope=merge; risk=L2; branch=<integration branch>; expires=<YYYY-MM-DDTHH:MM:SS+07:00 or Z>; note=<text, last, no semicolons>`.
Second type, `- Grant: scope=ci-local; branch=<branch>; expires=<time>; note=<text>` (no `risk`), allows a full local test suite to replace CI ONLY when CI is classified as infrastructure (billing/no runner, `ci-classify.sh`); code failures are never replaced. The gate also requires a comment with the exact tokens `Laporan ci-lokal: lulus` + `Commit: <sha head>` (+ `Perintah:` and `Hasil:`) from an OWNER/MEMBER/COLLABORATOR because scripts read them back. Maximum 7 days from the time it is read; default branch is not allowed; a PR that touches this file is never auto-merged. Invalid example (intentional, has no effect):
`- Grant: scope=merge; risk=L2; branch=integration; expires=EXAMPLE`

## Limits
- Max parallel: {{3}}
- Iterations per session: {{20}}
- Consecutive failures per issue: 2

## Completion evidence (comment on PR/MR)
Acceptance criteria (checked) · tests: command + output · key changes `file:line` ·
screenshot (UI) · what was skipped / unverified.

## Notifications (optional)
Telegram: set `AICREW_TG_TOKEN` and `AICREW_TG_CHAT` (owner chat ID only) in the shell environment, never in repo files.
One-way (outbound); control from a phone via Remote Control, not the bot.

## Model per role
principal=opus (`needs-principal` only) · senior-coder=codex if available, else sonnet ·
qa=haiku · security=sonnet · perf=sonnet · devops=sonnet · ui-ux=sonnet
