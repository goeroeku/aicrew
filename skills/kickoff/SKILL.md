---
name: kickoff
description: Use at the start of a new project (or when adopting aicrew in an existing repo) to decide the working pattern and write docs/WORKFLOW.md. Asks the owner for repo/backend, profile (ringan/standar/penuh), roles, gates, and stop rules.
---

Language: reply in the language the user writes in. Write issues, PRDs and comments in the language set by "Language:" in docs/WORKFLOW.md, or in the user's language when it is absent. "Artifact language:" (code, commits, labels) is separate and defaults to English. Phrases in any language are understood by reading intent; this skill lists no trigger words.

# aicrew kickoff

Goal: one short discussion with the owner, resulting in `docs/WORKFLOW.md` in the project repo.
Document language: follows `Language:` in `docs/WORKFLOW.md` (default English). Do not write project code in this skill.

## Rules
- **Repo and backend (GitHub/GitLab) are the owner's decision.** Ask; never choose on your own. Check `command -v gh glab` only to report what is installed.
- Read the repo first when it already exists (size, stack, tests) before recommending a profile.
- One question per turn. Offer a recommendation, not an empty list of choices.

## Audit mode (when `docs/WORKFLOW.md` already exists)
Do not overwrite it. Compare against `templates/WORKFLOW.md`: task size, labels, stop rules,
limits, completion evidence, backend commands, PRD/Existing code. Report a *matches / missing / conflicts* table
(with the relevant lines). Local rules that intentionally differ are respected and only noted.
A missing `Release notes:` line is reported as *missing* and recommended (not applied automatically). Prepare ready-to-apply changes (diff) and ask for owner approval once before applying them.

## Steps
0. **Existing PRD**: search for `PRD*`, `docs/`, `spec*`. If found, ask the owner to confirm the location and
   whether that PRD is already approved; record both in `WORKFLOW.md` (`PRD: <path>`, `Status PRD: disetujui|belum`). Write machine tokens such as `Status PRD: disetujui`, `Status PRD: belum`, and `tidak diketahui` exactly as shown because scripts read them back.
   A PRD with status `draf` (from the `prd` draft path) → record `Status PRD: belum`.
   Run `git check-ignore -v docs`. When `docs/` is ignored: show the rule and its file, then ask the owner
   (do not edit `.gitignore` yourself): (a) keep ignored (intentional), or (b) track only `PRD.md` and `WORKFLOW.md`.
   Record the answer in `WORKFLOW.md`.
   Do not modify the PRD. If the repo already contains code, record `Existing code: yes` (triggers the status audit in breakdown).
1. **Context**: what is being built, who the users are, risks (auth, money, data, migration?).
2. **Profile** (recommend one, owner decides):
   - `ringan`: no PRD; one issue, one role. For small scripts/fixes.
   - `standar`: PRD + issues + roles as needed; gates on the PRD and first PR.
   - `penuh`: all roles, context-free PRD reviewer, strict stop rules, parallel phases.
3. **Backend & repo**: GitHub or GitLab, repo name. Once the owner chooses, run
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh <backend>`; if it fails (CLI not installed/logged in),
   report what is missing and do not proceed to steps that require it. Also show Codex and Telegram status. If preflight prints `AWAS` (workflows run on push to main), record it under gate 4 of `WORKFLOW.md` and ask the owner. Write backend commands in a single section of `WORKFLOW.md` so they are easy to swap.
4. **Active roles**: choose from `agents/` (principal, senior-coder, qa, security, perf, devops, ui-ux).
5. **Gates & stop rules**: start from the defaults in `templates/WORKFLOW.md`; the owner may override them. Also ask whether to use a Kanban board (GitHub Project; requires the `gh` `project` scope: preflight prints the command). If yes and no board exists yet, create one with `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board-init.sh <owner> "<nama project>"` (prints its number; record it in `WORKFLOW.md`); if the owner already has one, pass its number as the third argument. Also ask who moves cards to Done: `owner` (default) or `agent-after-merge` (autopilot, pairs with `agent-after-qa` merge mode). Also ask who decides level-1 `needs-principal`: `owner` (default) or `principal-auto` (requires an active principal role; level 2 stays with the owner). Ask the merge mode for the integration branch: `owner` (default, manual) or `agent-after-qa` (automatic after QA passes; recommendation: merging to `main` stays with the owner). Also ask for the message language, `en` (default) or `id`, and write the answer as the `Language:` line of `docs/WORKFLOW.md`.
5a. **Release notes**: ask for the `Release notes:` option (`CHANGELOG.md` | `external` | `none`); recommend `CHANGELOG.md` for new projects and explain that PRs need a `Release note: <Added|Changed|Fixed|Security> - <teks>` line. Older projects without that line = `none` (opt-in; do not add it without owner approval).
5b. **Hardware limits**: ask for disk IOPS, RAM, volume tier, mount options, and host container limits; fill in the `Batas perangkat keras` (`Hardware limits`) section in `WORKFLOW.md`. Not yet known → write "unknown" (`tidak diketahui`, not a guessed number).
6. **Limits**: max parallel, iterations per session, consecutive failures per issue.
6b. **`.gitignore`**: run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ensure-gitignore.sh` (adds `.aicrew/` and `.claude/settings.local.json`, idempotent) and report the result to the owner. Inside an Orca workspace (preflight prints the Orca `AWAS`), also ask for the absolute worktree base path and fill in the `Worktree base:` line; note that Orca launches agents with `--dangerously-skip-permissions` by default.
7. Write `docs/WORKFLOW.md` from `${CLAUDE_PLUGIN_ROOT}/templates/WORKFLOW.md`, fill in the values, show it to the owner, and ask for approval.

Done only when `docs/WORKFLOW.md` exists and is approved by the owner.
