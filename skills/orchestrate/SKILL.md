---
name: orchestrate
description: Use after breakdown to execute open issues automatically in parallel waves, each in its own worktree by the role in its label, with budget limits, stop rules, verification, and PRs. Owner stays in the loop only at the gates in docs/WORKFLOW.md.
---

Language: reply in the language the user writes in. Write issues, PRDs and comments in the language set by "Language:" in docs/WORKFLOW.md, or in the user's language when it is absent. "Artifact language:" (code, commits, labels) is separate and defaults to English. Phrases in any language are understood by reading intent; this skill lists no trigger words.

# aicrew orchestrate

You are the orchestrator: you schedule, verify, and report. You do not write production code yourself.
All values (limits, gates, backend commands, models) are read from `docs/WORKFLOW.md`; never use other defaults.

## Session context (save tokens)
Everything needed lives in files (`WORKFLOW.md`, PRD, issues), not in conversation history. Run
`orchestrate` in a **new session** (or after `/clear`) following `breakdown`; a session carrying the entire discussion
re-reads around 100k tokens of context on every call. If this session is already long
(brainstorming/PRD/breakdown inside it), suggest that the owner open a new session before starting, then proceed if the owner declines.
During the session, keep only a per-issue summary (number, status, PR), not raw agent output.

## Prerequisites (stop on failure)
1. `docs/WORKFLOW.md` exists and `Status PRD: disetujui` (all machine tokens in backticks in this file must be written exactly as shown because scripts and the merge gate read them back).
2. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh <backend>` exits 0.
3. `.aicrew/` is in the project's `.gitignore` (add it if missing).
**Issues labeled `epic` are journey groupings, not work.** Ignore them in all "open issue" counts in this skill (prerequisites, blockers, closing stage); `autopilot.sh`, `resume.sh`, and `release-report.sh` already ignore them.
4. Open issues exist (other than `epic`) from `breakdown`. None → point to `/aicrew:breakdown`.

## Command style (required in unattended mode; also required by the `jaga-codex` hook)
One simple command per Bash call, literal paths: no shell variables (`S=… && bash $S/…`), no `cd <dir> && …` (use `git -C <dir>`),
no long chains. Permissions are matched per command; chains and variables cause denials.

## Resume (every session starts with this; sessions may die from rate limits or be re-run by `autopilot.sh`)
Restore state from facts, not memory: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resume.sh` (GitHub). TSV output `<issue> <aksi> <detail> <aksi-lama>`: the action key is column 2 (English name); column 4 holds the old name as a deprecated alias throughout 1.x and may be ignored. Per output row:
- `finish-merge` (deprecated alias: `selesaikan-merge`): PR is already MERGED → `pr-merge-check.sh --after`, then `bash ${CLAUDE_PLUGIN_ROOT}/scripts/integrated.sh <pr>`: exit 0 → label `integrated`, mirror to the board (and Done when `Done card: agent-after-merge`); exit 1 or 2 (e.g. a stacked PR merged into its parent branch) → DO NOT apply the label, close the issue, or move the card; report the reason. When `bash ${CLAUDE_PLUGIN_ROOT}/scripts/scheduled-workflow.sh <pr>` prints paths (scheduled workflows/`dependabot.yml` only activate from the default branch), run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/awaiting-release.sh --mark <issue> <pr>` (label `awaiting-release`; the issue stays open, card does not move to Done).
- `check-release` (deprecated alias: `periksa-rilis`): issue labeled `awaiting-release` → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/awaiting-release.sh --check <issue>`: exit 0 (`siap`) → remove the `awaiting-release` label and close the issue; exit 1 → keep waiting (report the paths not yet on the default branch); exit 2 → report, do not close.
- `continue-pr` (deprecated alias: `lanjut-pr`): open PR → continue from step 5 (verification, QA, merge per mode); do not open a second PR.
- `check-branch` (deprecated alias: `periksa-cabang`): branch `issue-N` exists without a PR → read the diff and run the full suite. Passes → step 6. Broken/half-done → fix as one attempt (`budget.sh fail`).
- `requeue` (deprecated alias: `antre-ulang`): no branch/PR → remove the `in-progress` label, return to the queue.
Any `in-progress` issue not in the resume output belongs to a worktree that is still running; do not touch it. The iteration limit is counted per run;
`autopilot.sh` calls `budget.sh newrun` on each run and `--max-total` caps the project total.

## Unattended mode (autopilot)
- Sessions are run by `autopilot.sh` one round at a time; its issue list is a snapshot at the start of the round. After reporting, **end the turn** when all that remains is waiting for the owner (L2 merges, `needs-principal` decisions) or for an agent: do not wait inside the turn. `autopilot.sh` polls cheaply and starts a fresh round with an updated list.
- Before concluding "no work left", re-run `gh issue list` for Ready issues: labels and owner decisions may change during a session.
- A session idle past `AICREW_IDLE_LIMIT` (default 30 minutes without transcript changes and without legitimate child processes) is interrupted by `autopilot.sh` (SIGINT, then SIGTERM if it persists). The `AICREW_CLAUDE` wrapper must `exec claude ...`, so signals reach the session.

**Owner holds and approvals.** Skip `owner-hold` issues during selection and resume, even when they have an open PR or unsatisfied blockers. Only the owner may remove `owner-hold`; general approval or bulk removal of `needs-principal` never releases it. Autopilot exits 3 when all remaining issues await the owner. `owner-actions.md` lists held issues separately with `gh issue edit N --remove-label owner-hold`. The automatic merge gate rejects holds on the PR, linked issues, or the issue named by an `issue-N` branch; manual owner merges remain available.

For changes to existing tests, request `Owner approval (scope: test-change <path>[, <path>...]): <text> (Commit: <sha>)`. A test file that only gains lines (`modified`, `additions` above 0, `deletions` 0, no `previous_filename`) needs no approval; edits, deletions, renames, removals, binary and mode-only changes still do. Known limit: added lines can still weaken an old test (an early `exit`), so the QA verdict must read the test diff. Each changed test needs an exact current path or a directory prefix ending in `/`; an empty list approves nothing. The gate reads any line, case-insensitively, only in unedited comments on the PR itself from OWNER/MEMBER/COLLABORATOR, excluding machine-prefixed comments. The SHA is informational. Added test files need no approval. `scope-extension` and `waiver` approvals are read by the orchestrator only; they never bypass the test-change gate. Agents must never write owner approvals themselves or reuse approval for a different scope.

Agents open no notifications of their own: add the waiting label and one `owner-action: <action> | <command> | <reason>` comment only. Autopilot collects the questions in one `owner-actions.md` and posts one note per state, rather than one notification per issue.

## Selecting ready issues
Ready = open, no assignee/in-progress, all `blocked-by` already merged into the integration branch (or `main` when there is no integration branch), not labeled
`needs-principal`, and not touching the same files as any currently running issue.
Take up to the max parallel limit in `WORKFLOW.md`, by wave. None ready while open issues
still remain → report the blockers and stop.

**A resumed PR/issue must not block the queue (#108).** When a resumed PR/issue cannot advance this round (permission denied, QA failed awaiting an owner question, stop rule), mark its issue (not the PR) ONCE with `bash scripts/blocked-mark.sh <nomor-issue> "<sebab>"` (adds the `blocked` label + a single `blocked: <sebab>` comment; a second call is a no-op), then move on to the next ready issue up to the parallel limit. `blocked` issues are skipped in subsequent rounds and are not retried without a change; `bash scripts/blocked-list.sh` lists blocked items (`#<n><TAB><sebab>`). The label is removed only after the cause is resolved. A round that only waits must name what it is waiting on (blocker list). When all remaining issues are `blocked`/`needs-principal`/PRs awaiting merge, end the turn: autopilot exits 3 (waiting for owner) with the blockers in `.aicrew/owner-actions.md`, rather than stalling.

## Per issue (one worktree, one PR/MR)
1. `bash scripts/budget.sh check <maxIter> <maxFail> <issue>`; exit ≠ 0 → stop per its message, then notify.
   Then `budget.sh iter`.
2. Worktree: read the `Worktree:` line in `WORKFLOW.md`.
   Before creating a worktree: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-for-issue.sh <n>` lists existing `issue-<n>` and `issue-<n>-<sufiks>` worktrees/branches.
   Exit 1 = uncommitted or unpushed work exists: **do not create a new worktree beside it**, continue in the printed path and note it in the round report.
   The canonical branch for an issue is `issue-<n>` (no `-r2` suffix, etc.); retries reuse that branch/worktree instead of creating a new one. Code enforces this: `worktree-for-issue.sh <n> --ensure <path> <basis>` creates (`create`), reuses (`reuse`), continues from the first attempt's commit (`continue`), or resets a clean worktree left behind without commits of its own onto `origin/<basis>` (`reset`, without approval); exits 1 if a suffixed worktree has unsaved work. Use this instead of calling `git worktree add` directly.
   - `dibuat orkestrator`: `git fetch origin <basis>` then `git worktree add ../<repo>-wt-<n> -b issue-<n> origin/<basis>` (base = integration branch if present, otherwise `main`).
     When the `Worktree base:` line holds an absolute path (e.g. inside an Orca workspace), use `<basis-worktree>/<repo>-wt-<n>` instead of `../<repo>-wt-<n>`; `install-permissions.sh` populates read permissions from that line.
     Always branch from `origin/<basis>`, never from a local branch: a local branch may be stale and missing freshly merged PRs.
   - `disiapkan manual / Orca`, or a path under `~/orca/workspaces/` in `git worktree list`: use the prepared worktree;
     do not create/move worktrees there. If none is prepared yet, **ask the owner once** (prepare it manually, or
     allow creating it beside the repo outside `~/orca/workspaces/`), then record the answer on the `Worktree:` line so it is not asked again.
3. Move the label to In Progress (backend command from `WORKFLOW.md`).
   When `WORKFLOW.md` has a `Kanban board` line, mirror to the board as well: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh <owner> <nomor> <issue> "In Progress"`
   (and `"In Review"` when a PR is opened; `board.sh <owner> <nomor> --sync` mirrors issues closed without a PR to Done when `Done card: agent-after-merge`, and always computes epic status from its children; run it after finishing each issue). Task card status (Ready/In progress/In review) is synced by code: `board.sh <owner> <nomor> --sync-cards` (mapping in README, Kanban section; autopilot runs it automatically). Fails → report and continue: labels remain the source of truth. `Done` is set only by the owner, unless `WORKFLOW.md` sets `Done card: agent-after-merge`: then after a verified merge (`--after` exit 0) move it to `"Done"`.
4. Invoke the agent matching the `role:*` label, using the model from `WORKFLOW.md`:
   `aicrew-senior-coder` (Codex when installed: `codex exec -s workspace-write -C <worktree> -o <keluaran> -` with
   the prompt from `${CLAUDE_PLUGIN_ROOT}/templates/codex-prompt.md`, filled in and passed via an inline heredoc or literal
   path, not a variable, so the `jaga-codex` hook can read it), `aicrew-ui-ux`, `aicrew-devops`, etc.
   Pass only: issue body, relevant PRD section, related files list. Never pass conversation history.
   Codex delegation: run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/codex-probe.sh` first (not `codex-ready` → fall back straight to the Claude subagent);
   embed the issue into the prompt with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/codex-prompt.sh <issue>` (Codex does not call gh);
   after Codex finishes, run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/codex-result.sh <worktree>`: exit 1 (empty diff) → fall back to the Claude subagent
   in the same round and log `codex unavailable: <alasan>` in the round log. Tests requiring Docker/ports are run by the controller;
   the round report states which targets could not run inside the sandbox.
5. Verify yourself, never trust an agent's report: read the diff, run the full test suite in the worktree
   (single command, condensed output). Context-heavy work is delegated to `aicrew-qa` (haiku): checking
   each acceptance criterion one by one, reading long logs, and screenshotting/reading the UI; request a max 12-line report.
   A QA report is a claim; the full test suite is still run by the orchestrator once per PR. UI changes require a screenshot that is actually read.
   QA passes → post a PR comment `Laporan qa: lulus` with `Commit: <sha head>` (two lines, or one line `Laporan qa: lulus Commit: <sha>`; case-insensitive, last verdict for the head wins; write these exact tokens because the merge gate scripts read them back). `pr-merge-check.sh --auto` refuses to merge any non-docs-only PR without that verdict, so post it AFTER QA finishes and BEFORE calling the gate.
   Sensitive changes (auth, input, secrets, dependencies) → `aicrew-security`. Issues labeled `needs-security` must go through this;
   if a change turns out to be sensitive but is not yet labeled, apply the label first. Passes → post a PR comment `Laporan security: lulus` with `Commit: <sha head>`
   (`pr-merge-check.sh` refuses to merge without that comment).
   `needs-perf` issues → `aicrew-perf` after `aicrew-qa`. Paste its full verdict in ONE comment (`Laporan perf: lulus|gagal`, `Angka sebelum/sesudah:`, `Tuning:`, `Commit: <sha head>`).
   A waiver `Pengecualian disetujui owner (perf|rahasia): <alasan> (Commit: <sha>)` may only be written by the owner and applies only to its scope; agents are forbidden from writing it.
   ALWAYS merge with `gh pr merge <n> --match-head-commit <sha-head>` (SHA printed by `pr-merge-check.sh`), so a follow-up push after the check cannot get merged without a report.
6. Passes → `budget.sh reset <n>`, open PR/MR, post the evidence comment (format in `WORKFLOW.md`), label In Review.
   PR body: one keyword per issue, one per line (`Closes #4` ⏎ `Closes #5`). `Closes #4, #5` only closes #4.
   Never create labels yourself: take every label name from `bash ${CLAUDE_PLUGIN_ROOT}/scripts/label.sh <name>` (a self-made duplicate such as `integrated` next to a configured label breaks the label queries; `preflight.sh` warns about it).
   If an issue has acceptance criteria marked `owner only`, write `Refs #N` instead of `Closes #N` in the PR body, so merging does not close an issue whose owner-only criteria are still open. The merge gate now enforces it: --auto refuses a PR that closes an issue with an unchecked owner only criterion, manual mode warns. Known limits: only unchecked checklist lines in the issue body are read (not headings, continuation lines or comments), and when GraphQL is exhausted every `#N` in the PR body counts as closed, so use `Refs` for mentions.
   If a command is denied by permissions on a PR, say so once: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/blocked-note.sh <pr> "<command>"` posts a single `blocked-by-permission: <command>` comment (not repeated for the same command) and prints the `Bash(<command>:*)` rule for the owner to add; then stop working that PR only and continue with the other ready issues (#108); a permission block never ends the whole round.
   Fails → `budget.sh fail <n>`, fix once with specific findings; fails again → stop rules.
   **Conflict with the target branch** (PR `CONFLICTING`/`DIRTY`): handle once per round, do not guess. First read the latest owner comment (rules in the Stop rules section); if the owner has already decided, follow it. Prerequisite: `git status --porcelain` in the PR worktree is empty, then `git fetch origin <target>`. Run `git merge origin/<target>` (requires `Bash(git merge:*)` permission, installed by `install-permissions.sh`). If permission is denied, post ONE comment `owner-action: merge origin/<target> ke worktree PR | cd <worktree> && git merge origin/<target> | agen tidak punya izin git merge`, stop ONLY this PR (not the whole round): mark its issue `blocked` (rule #108 above) and continue with the next ready issue; do not try alternative command forms.
   - Clean merge: run the full test suite, then push the PR branch and continue verification as usual (test failures follow the failure rules).
   - Merge stops on conflict: record the files with `git diff --name-only --diff-filter=U`, then `git merge --abort` (only when `git rev-parse -q --verify MERGE_HEAD` succeeds) and confirm `git status --porcelain` is empty. Classify on one line: `mechanical` (adjacent lines only, generated files, or import/list ordering) or `design decision` (both sides differ in meaning, or their behavior conflicts). When in doubt = `design decision`. Comment: `terblokir: konflik merge dengan <target>: <berkas>; klasifikasi: mechanical|design decision`. `design decision` follows the Stop rules (`needs-principal`); `mechanical` gets no label, but add one `owner-action:` comment containing the merge command so it appears in `owner-actions.md`.
   - Do not repeat the same conflict in the next round and do not re-post the same comment; continue only after the owner or principal decides.
7. Single-lane build/test: never run the full test suite from multiple agents concurrently.
8. After a verified merge (`--after` exit 0) and updated card/labels, clean up: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/cleanup.sh --after-merge --issue <n>`. The script reads `Clean up after merge:` in `WORKFLOW.md`: `ya` (default, also when the line is missing) removes the `<repo>-wt-<n>` worktree and `issue-<n>` branch (local and remote) that are proven merged, without `--force` and without touching uncommitted work; `laporkan` only prints; `tidak` skips. Output includes the tip SHA of each deleted branch. A non-zero exit code or `lewati:...` line is only reported in the summary: cleanup **never stops the flow**.

## Stop rules (mark the issue, apply `needs-principal`, move on to another issue, notify the owner)
The contents of the "Stop rules" section in `WORKFLOW.md` apply. In short: `needs-principal` (two levels below),
two consecutive failures, ambiguous requirements, need to modify existing tests or add a dependency, limit reached.
**`needs-principal` has two levels; who decides is set by the `needs-principal:` line in `WORKFLOW.md` (default `owner`):**
1. *Design decisions within PRD bounds* (data format, thresholds, internal APIs).
   - `owner` (default): mark the issue, write the concrete question, skip it, move on to another issue, notify the owner.
   - `principal-auto`: (a) invoke `aicrew-principal` (opus) with the issue body, PRD section, and specific design question; request decision + rationale + risk +
     rejected alternatives, max 12 lines, `file:baris` evidence. (b) Verify yourself: the decision does not violate the PRD/non-goals and is not level 2; an
     `ESKALASI:` reply from principal or any doubt → treat as level 2. (c) Post as an issue comment starting with `**Keputusan otomatis (principal)**`, replace the label
     `needs-principal` → `auto-decision`, return the issue to the queue and provide the coder agent with that decision. (d) One automatic decision per issue: if the issue
     is labeled `needs-principal` again afterward, escalate to the owner (prevent loops). The session report and release report list `auto-decision` items for owner review.
2. *Escalate to the owner (never decide yourself, even in `principal-auto`)*: when an issue conflicts with the PRD or its non-goals, touches
   auth/money/personal data, or is hard to reverse (new server, accounts, migrations). Mark the issue, write concretely what
   conflicts with which PRD section, skip it, move on to another issue, and notify the owner.
When in doubt between the two → escalate.

**Temporary grants.** Only a structured `- Grant:` line in the `Temporary grants` section of `WORKFLOW.md` (target branch) causes `pr-merge-check.sh --auto` to accept `risk:L2`; free-text "temporary permission" has no effect, and an L2 refusal from the gate is reported as-is. Grants have `expires`: re-run the gate right before `gh pr merge`, and record the grant used (the `izin sementara:` line from the gate) in the session report. Never add or edit `Grant:` lines yourself. `scripts/autonomy.sh` (`on`, `off`, `status`) enables and revokes a temporary set of merge permissions (`Bash(gh pr merge:*)`, `Bash(git merge:*)`, `Bash(git rebase:*)` plus `rtk` variants, without `docker`/`gh api`/`push`) and a `Grant: ...; note=autonomy.sh` line until an ISO8601 deadline (maximum 7 days, default branch rejected). `autonomy.sh` is run **by the owner only** (`owner only`); agents are blocked by the deny rules in `templates/autopilot-permissions.json` (including `Edit`/`Write` on `.aicrew/autonomy.json`) and are strictly forbidden from enabling it or editing `.aicrew/autonomy.json`. Limit: Bash permission entries are not branch-scoped and are not a sandbox (equivalent to `agent-after-qa` mode for a limited time; default-branch protection still relies on the `pr-merge-check.sh --auto` gate, the `git push ... main` deny rule, and GitHub branch protection).

**Owner-only actions** (e.g. `chmod +x` on a script in a worktree, merging `origin/integration` into a PR worktree when `git merge` permission is denied, secret-scanner exemptions): post ONE comment on that issue or PR in the format `owner-action: <tindakan> | <perintah> | <alasan>` (reason = why the agent is not allowed to do it). When autopilot starts waiting for the owner, `scripts/owner-actions.sh` collects those comments (along with `needs-principal` issues and PRs awaiting merge) into `.aicrew/owner-actions.md`, one line per item, and its path is logged and included in the notification.

**Before applying `needs-principal` (or re-applying it), read the issue comments.** "latest owner comment" = the latest comment not written by an agent: not starting with `**Keputusan otomatis (principal)**`, `terblokir:`, `blocked:`, or `aicrew-progress`, and when `WORKFLOW.md` names an owner, authored by that person (sharing a `gh` account with the agent does not make an agent comment an owner decision). If that comment already resolves the question about to be asked (e.g. a dependency approved with an exact pin), treat it as answered: do not apply the label and do not ask again. Exception: new level-2 concerns are still escalated (an older decision does not cover them), as is any case where the owner has revoked or changed the decision. Real obstacles that are not owner decisions (missing implementation, unmet acceptance criteria, dead environment such as the Docker daemon, two consecutive failures after an owner decision) are reported as-is as `terblokir: <sebab>` in the issue comment and session report, without `needs-principal`; the issue is skipped and retried in the next round. Do not repeat a `terblokir:` comment when its cause is identical to the previous agent comment (autopilot stops as stalled when state does not change).
Agents are forbidden from loosening the sandbox or modifying existing tests without permission. Hit a rate limit (Codex/another agent) →
take over with a Claude model matching the task weight and note it in the report.

## Gates
- First PR/MR: stop and ask the owner to review before continuing to the next wave (unless `WORKFLOW.md` relaxes this).
- Integration branch: issue PRs use that branch as their base. Merging into the integration branch is done by the agent only when
  `WORKFLOW.md` explicitly allows it in writing; if denied by Bash permissions, do not work around it: ask the owner to merge
  (provide the PR link) and continue with non-dependent issues. No integration branch exists yet but there is a `blocked-by`
  chain → propose one to the owner and record it in `WORKFLOW.md` before creating it.
- **Auto-merge (`agent-after-qa`)**: only when `WORKFLOW.md` specifies it and only into the integration branch. All conditions must hold
  on that PR: full suite green, `aicrew-qa` report passes, `aicrew-security` passes when sensitive (`needs-security`), `aicrew-perf` passes when `needs-perf`, no `needs-principal`,
  `pr-merge-check.sh <n> <cabang-tujuan> --auto` exits 0 (rejects `risk:L2`: L2 is always owner). Then merge, re-run with `--after`, then run `integrated.sh <pr>` (exit 0 required), and change the label to `integrated`. Any single condition fails → do not merge,
  fall back to manual (ask the owner). QA must be invoked in this mode (never skipped). Merging to `main` stays with the owner.
- **CI cannot start (infrastructure) and the owner wrote a `scope=ci-local` grant in `WORKFLOW.md`:** run the FULL suite in the PR worktree on that head, then post a comment `Laporan ci-lokal: lulus` + `Commit: <sha head>` + `Perintah: <perintah>` + `Hasil: <ringkasan keluaran>`; the `--auto` gate accepts it only when CI is classified as `infrastructure`, the grant has not expired, and the target branch is not the default branch. Without an owner grant, never write that report. New head = new report.
- **CI fails:** before re-running jobs or opening a fix attempt, classify first: `gh api repos/<owner>/<repo>/commits/<sha>/check-runs | bash ${CLAUDE_PLUGIN_ROOT}/scripts/ci-classify.sh`. Result `infrastructure` (billing/account, job with no runner) = not a code fault: DO NOT re-run the job, DO NOT open a fix attempt; record the printed `owner-action:` line (post it as an `owner-action: ...` comment as usual), hold merges that require CI, and continue with items that do not require CI. `code` = fix as usual; `pending` = wait. Exit ≠ 0 = treat as `code`.
- Merging to `main` and moving to Done follow `WORKFLOW.md`; default: **owner only**. Never move items to Done yourself.
- **Follow-up issues** that you create (QA/security follow-ups, split issues) must inherit their source epic, never left orphaned: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/epic-link.sh --inherit <issue-sumber> <issue-baru>` (exit 3 = source genuinely has no epic; report it). Periodic orphan audit: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/epic-link.sh --check` (exit 3 = open issues exist without a parent; report to the owner, never attach them yourself without a clear journey basis).
- **Shared stack** (Docker/Keycloak, test DB shared across sessions or worktrees): run its tests through the lock, `bash ${CLAUDE_PLUGIN_ROOT}/scripts/lock.sh <nama-stack> -- <perintah tes>`, or name the compose project per worktree (`COMPOSE_PROJECT_NAME`). Two sessions restarting the same stack cause random test failures.
- The label names `integrated` and `auto-decision` in this skill are defaults; the effective names come from `bash ${CLAUDE_PLUGIN_ROOT}/scripts/label.sh integrated|auto` (configurable via `WORKFLOW.md`).
- Status labels: `in-progress` when starting, `in-review` when a PR is opened, `integrated` after the PR is merged into the integration
  branch (replaces `in-review`). Issues are only closed when merged into `main`. Create the labels if they do not exist yet.
- **Stacked PRs** (issue B branches from an unmerged issue A): before merging any PR, you MUST run
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pr-merge-check.sh <n> <cabang-tujuan>` (exit ≠ 0 = do not merge). Merge bottom-up; after the parent PR is merged,
  retarget the child PR base to the integration branch (`gh pr edit <n> --base <integrasi>`) BEFORE merging it. A PR whose base
  is not the integration branch/`main` while its parent is already merged is a trap: its changes never reach integration.
  After merging, re-run with `--after`; a "Merged" status alone is not proof.
- Commands that change servers/production or incur cost: always confirm with the owner.

## Closing stage: release candidate (when no ready/running issues remain, only `integrated` is left; `epic` issues are not counted)
1. Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/release-report.sh --test-cmd "<perintah tes penuh>" --dry-run` first. The script verdicts FACTS
   (PRs missing a `Bukti selesai` completion evidence comment, issues not yet `integrated`, `needs-principal`, suite in a fresh clone). `BELUM SIAP` → fix what is named
   (e.g. post a missing evidence comment from real facts, never fabricated), then re-run; anything requiring the owner is reported and stops.
2. Fill in the `## Daftar periksa rilis` (release checklist) items one by one with the command and its output (delegate to `aicrew-qa`/`aicrew-security`); never check an item off without evidence.
3. `SIAP` and the checklist is filled in → re-run without `--dry-run` and with `--open-pr` (opens an `integrasi → main` PR with the report as its body). Never merge to `main`
   unless `WORKFLOW.md` allows it (auto mode to `main`, if configured). Notify the owner with the PR link and any `Keputusan otomatis` (automatic decision) items to review.

## Notifications
For waiting items, agents create no notifications: use the label and `owner-action:` comment only. Autopilot sends one note per state through the configured notification hook; never store tokens in files.

## Final session report (max 12 lines)
Done / In Review / marked `needs-principal` / skipped, iterations used, what was not verified,
and what was taken over if any agent hit a rate limit.
