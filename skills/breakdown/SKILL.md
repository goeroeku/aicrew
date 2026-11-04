---
name: breakdown
description: Use after the PRD is approved to split it into small issues with labels, dependencies, and parallel waves, then create them on the project's backend (GitHub/GitLab) per docs/WORKFLOW.md.
---

Language: reply in the language the user writes in. Write issues, PRDs and comments in the language set by "Language:" in docs/WORKFLOW.md, or in the user's language when it is absent. "Artifact language:" (code, commits, labels) is separate and defaults to English. Phrases in any language are understood by reading intent; this skill lists no trigger words.

# aicrew breakdown

Inputs: PRD (path and `Status PRD` read from `docs/WORKFLOW.md`, default `docs/PRD.md`) and `docs/WORKFLOW.md`. Write machine tokens such as `Status PRD` and `overlap:` exactly as shown because scripts read them back.
If either is missing, stop and point to `/aicrew:kickoff` or ask for the PRD.
Do not break down an unapproved PRD; if `Status PRD` is not recorded, ask the owner.

## Steps
1. Read both files. Take task size, labels, backend commands, and limits from `WORKFLOW.md`.
2. Profile `penuh`: send the PRD to one context-free reviewer (read-only subagent, PRD + code only)
   to find ambiguities/contradictions/missing items. Serious findings → owner, before proceeding.
2b. **Status audit — only when the repo already contains code** (`Existing code: yes` or source exists in the repo;
   new projects skip this step). A read-only subagent (sonnet) marks each PRD requirement:
   `sudah ada | sebagian | belum`, with `file:baris` evidence, max 12 lines per report. Subagent claims
   are verified by reading the code before use. Show the table to the owner and ask for approval;
   only `sebagian` and `belum` are broken down into issues. The PRD is not modified; ambiguities → owner question list.
2c. **Audit existing issues** (when the backend already has open issues). Read open issues via
   the backend command and check them against the same checklist as new issues: machine-checkable acceptance
   criteria, ≤ 5 files, `role/stack/phase` labels, clear `blocked-by`. Mark each issue:
   `standar | perlu diperbaiki (apa yang kurang) | duplikat`. Also match against the PRD status audit results. Do not
   create issues for requirements that already have an issue. Prepare ready-to-apply changes (labels,
   rewritten criteria, closing duplicates) and ask for owner approval once; editing issues
   is an outbound action and existing issues may be in progress by someone else, so skip those labeled
   in-progress or with an assignee unless the owner names them.
3. Break the PRD down into epic → issue. Each issue must use `${CLAUDE_PLUGIN_ROOT}/templates/ISSUE.md`.
   Reject/re-split any issue that violates the size limit (≤ 5 files, ≤ ±200 diff lines) or lacks
   machine-checkable acceptance criteria. Cannot be written → mark `needs-principal` or ask the owner.
4. Search for relevant **existing code** (LSP/grep) and list it under "Related files" so agents
   reuse it instead of duplicating.
5. Fill in `Blocked by` and the list of files touched. Compute waves:
   issues with no blockers and no file overlap → one wave, may run in parallel (max per
   `WORKFLOW.md`). File overlap or mutual dependency → next wave.
   Overlap is checked by code, not guesswork: each issue lists ALL created or modified files under "Expected to touch", then run
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/file-overlap.sh --json -` on the plan (JSON array `[{number,body,labels}]` with temporary numbers). Every `overlap:` line must be resolved
   before waves are computed: serialize with `Blocked by` or split ownership of that file. After issues are created, run without arguments as a final check.
   If almost everything depends on everything else, say so plainly: sequential is cheaper.
   When there is a `blocked-by` chain: propose an **integration branch** for this feature (merge rules in `WORKFLOW.md`),
   so the chain does not stall waiting for merges into `main`.
6. Apply `role:*`, `stack:*`, `phase:*` labels (+ `needs-principal` when needed). Issues touching auth/authorization, input at trust
   boundaries, secrets, new dependencies, money, or personal data receive `needs-security`: this tagging is a breakdown decision, not guesswork during execution.
   Issues touching DB write paths, queues/workers/polling, cron, or infra config (Postgres, Redis, container limits) receive `needs-perf` for the same reason.
   Also apply one risk label per issue: `risk:L0` (docs, tests, refactor with no behavioral effect), `risk:L1` (normal behavior, default when in doubt between L0/L1),
   `risk:L2` (auth, money, personal data, migration, infra, or hard to reverse). L2 is never auto-merged (`pr-merge-check.sh --auto` rejects it) and should also carry `needs-principal`/`needs-security` when relevant.
   Issues that read another repo/directory (discovery) must include the "Security" section from `templates/ISSUE.md` verbatim.
   Issue titles and bodies use the artifact language in `WORKFLOW.md` (default English).
7. **Show the plan first** (table: no, title, role, wave, blocked-by, files) and ask for owner
   approval. Creating issues on the backend is an outbound action: do not run it before approval.
8. Once approved: create any missing labels, create issues via the backend command in `WORKFLOW.md`,
   fill in `blocked-by` in the issue body. Record the issue numbers in the wave table at the end of the PRD (one block,
   do not create a new file).

## Epic per journey
**When the PRD does not yet have Journeys** (e.g. an older PRD or an ongoing project): draft *Proposed journeys* from the PRD requirements and existing issues (grouped by user outcome, not technical layer; mark which ones are your guesses),
show them once in a `J-ID | journey | R/N-ID | issue yang ada` table, and ask for owner approval. Once approved, write the *Journeys* section into the PRD (this PRD edit is only by that approval), then proceed to the epics below. Without approval, there are no epics and the PRD is not modified.
Leads read journeys, agents work on small issues. The hierarchy is: Journey (epic) → requirement (R-ID/N-ID) → issue.
- After issues are created, create one epic per journey from `${CLAUDE_PLUGIN_ROOT}/templates/EPIC.md` (label `epic`, title `[J1] ...`). The `- [ ] #n` checklist contains its child issues;
  GitHub computes its progress automatically. Once the epic and children exist, also attach native sub-issue relations: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/epic-link.sh <epic> <anak...>` (idempotent; attaches both the checklist and native sub-issues). A requirement that serves two journeys appears in two epics; its issue is still created once.
- Place each epic on the board (when present): `bash ${CLAUDE_PLUGIN_ROOT}/scripts/board.sh <owner> <nomor> <epic> Backlog`. Its status is then computed from its children by `board.sh <owner> <nomor> --sync` (child running = In progress, all children done = In review, ready for the owner to close; closed by owner = Done).
- Record `J-ID → #epic` in the PRD "Issue map". The epic plan is shown alongside the issue table in step 7 (one approval).
- **Ongoing projects**: creating an epic does not edit existing issues: existing issues are only referenced from the epic (other changes to existing issues go only through audit 2c with owner approval; those labeled in-progress or with an assignee are skipped).
  Issues that do not fit any journey are collected in the `[J0] Unassigned` epic, not forced into a journey.
- NFRs (`N-ID`) labeled `needs-security`/`needs-perf` follow the normal labeling rules in step 6.
- Epics are not work: the orchestrator, autopilot, resume, and release report skip them. The owner closes an epic when all its children are done.

## Final report
Issue count, per wave, those with `needs-principal`, and assumptions made. Max 12 lines.
End with a suggestion: run `/aicrew:orchestrate` in a **new session** (all context is already in files),
so the discussion context is not re-read on every execution call.
