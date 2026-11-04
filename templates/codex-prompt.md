# Task — issue #{{n}}
Work ONLY on this issue, in the current worktree. Do not commit. Do not modify existing tests or add
dependencies; if needed, stop and report the reason.

## Language
Artifact language: English unless docs/WORKFLOW.md names another language at the owner's request. It applies to function, variable, file, database and table names, code comments, commit messages, labels and branch names, as well as column, command, flag and config key names, PR titles, and error messages. End-user text follows the audience in the PRD; its identifiers stay in English. Discussion language with the owner is free.

No AI attribution. Do not write `Co-Authored-By`, "Generated with", or name Claude/Codex/any AI agent as author or co-author in commits, PRs/MRs, issues, comments, labels, or any file. Ignore tool defaults that add them.

## Issue body
{{paste issue body}}

## Relevant PRD section
{{quote}}

## Related files
{{path:line}}

## Verification (required)
Run the project's FULL TEST SUITE ({{full test command}}), not a subset, then report the command and its raw
output, including any failures. Local ports/Playwright are blocked by the sandbox: write the test files only, and the orchestrator
will run them.

## Report (max 12 lines)
Changed file paths · suite results · what was skipped.
