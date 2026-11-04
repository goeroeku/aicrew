---
name: prd
description: Use after brainstorming with the owner to write the PRD from the agreed discussion, using templates/PRD.md, and get owner approval. Run before aicrew:breakdown.
---

Language: reply in the language the user writes in. Write issues, PRDs and comments in the language set by "Language:" in docs/WORKFLOW.md, or in the user's language when it is absent. "Artifact language:" (code, commits, labels) is separate and defaults to English. Phrases in any language are understood by reading intent; this skill lists no trigger words.

# aicrew prd

Write the PRD from the discussion/brainstorming results. Follow the document language in `docs/WORKFLOW.md` (default English). Do not write code.

## Rules
- If there has been no discussion/brainstorming for this project yet, run it first (`brainstorming` skill); do not guess.
- If a PRD already exists (see `WORKFLOW.md` → `PRD:`), do not overwrite it: show its gaps against the template and propose changes.
- Every requirement must have an ID and testable acceptance criteria. Criteria that cannot be written → put in "Open questions" and ask the owner.
- Flag hard-to-reverse decisions (DB schema, API shape, auth, money) as `needs-principal` candidates.
- **Journeys**: during discussion, ask "what can a user accomplish when this is done?" and fill in the *Journeys* section (one row per outcome understood by a lead) as well as *Non-functional requirements* from the answer.
  Every requirement (R-ID) must belong to at least one journey, or be marked `infrastruktur` (e.g. CI, migration) when it genuinely does not serve a journey. A journey with no requirements = a gap: ask the owner.
- Do not invent requirements that were not discussed; anything assumed is written explicitly as an assumption.

## Steps
1. Read `docs/WORKFLOW.md` (profile, PRD path). Missing → **draft path**: write the PRD from the discussion to `docs/PRD.md`
   with `Status: draf`, DO NOT ask for approval, then point to `/aicrew:kickoff` (which fills in the location and
   status). Once `WORKFLOW.md` exists, run `prd` again only for approval (step 4). Write machine tokens such as `Status: draf` and `Status PRD: disetujui` exactly as shown because scripts read them back.
2. Fill in `${CLAUDE_PLUGIN_ROOT}/templates/PRD.md` from the discussion; save it to the PRD path in `WORKFLOW.md`.
3. Profile `penuh`: ask the `aicrew-reviewer` agent to review the PRD (read-only, without conversation context); bring serious findings to the owner.
4. Show a summary (not the entire document) and ask for approval. Once approved: update `Status:` in the PRD
   and `Status PRD: disetujui` in `WORKFLOW.md`. Only the owner approves.
5. Proceed to `/aicrew:breakdown`.
