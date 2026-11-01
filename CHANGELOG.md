# Changelog

All notable changes to aiCrew are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Entries before 0.11.0 were reconstructed from tags, merged pull requests and commit history.

## [1.1.0] - 2026-11-02

### Changed

- Commands, options, `WORKFLOW.md` keys and values, script names and default labels are now English; the Indonesian forms keep working as deprecated aliases. (#65)
- README banner and social preview images are in English. (#65)

### Behavior changes

- default label names are now `integrated`, `auto-decision`, `unsplit`, `awaiting-release` and `no-parent`; issues that already carry the old default labels are still recognized. (#65)

## [1.0.0] - 2026-11-01

### Added

- CHANGELOG.md with the full history from 0.1.0, and a Stability section in the README that defines the public interface under SemVer. (#53)

### Changed

- Public documentation is now in English: README.md, PRIVACY.md, plugin and marketplace descriptions and the user-facing settings text. (#53)

## [0.12.0] - 2026-11-01

### Added

- Idle watchdog in `autopilot.sh`, on by default (30 minutes): a `claude -p` round with no transcript activity and no non-helper child process is interrupted (SIGINT, then SIGTERM after a grace period, never SIGKILL) and the next round starts with a fresh issue list. Options `--idle-limit`, `--round-timeout` and the matching `AICREW_IDLE_*` / `AICREW_ROUND_TIMEOUT` variables (#52)
- `.aicrew/autopilot.json` health status with phase, round, idle seconds and a heartbeat (#52)
- `orchestrate` unattended-mode guidance: end the turn after the report when only waiting for the owner (#52)

### Changed

- Issues whose `## Blocked by` blockers are themselves waiting (needs-principal or an open PR) now count as waiting for the owner; the check stops at the first plainly Ready issue to save GraphQL quota (#52)

### Behavior changes

- The idle watchdog is enabled by default: a session that sits idle for more than 30 minutes is interrupted. Disable with `--idle-limit 0`.

## [0.11.1] - 2026-11-01

### Changed

- Release-note keys are English: `Release note:`, `Behavior change:` in PR bodies and `Release notes: CHANGELOG.md | external | none` in `docs/WORKFLOW.md` (#51)
- The artifact-language rule now also covers database, branch, command, flag and configuration-key names (#51)

### Behavior changes

- The Indonesian keys introduced in 0.11.0 (`Catatan rilis:`, `Perubahan perilaku:`) are no longer recognized.

## [0.11.0] - 2026-11-01

### Added

- `scripts/release-notes.sh`: builds a `CHANGELOG.md` section from marked lines in the bodies of PRs merged since the previous tag (`--versi`, `--sejak`, `--tulis`, `--ekstrak`); opt-in, deterministic, REST + git only (#50)
- PR gate warns when a PR has no release-note line; `check-version.sh` warns when the version has no CHANGELOG section; `release.yml` uses the CHANGELOG section as the release description (#50)
- `templates/pull_request_template.md`; release-notes rules for the `senior-coder` agent (#50)
- `release-report.sh --versi` embeds a draft section in the release-candidate report (#50)

### Changed

- The epic progress comment explains that `In review` is intentional (ready for the owner to close) (#49)

## [0.10.1] - 2026-11-01

### Added

- `templates/dependabot.yml`: groups minor/patch GitHub Actions updates and documents toolchain bumps as decisions (#46)
- `cve-audit` skill documents the bridge pattern for repositories released from a non-default branch (#45)

### Changed

- `templates/WORKFLOW.md` notes that orchestrator worktrees are removed together with their ignored files (#47)

## [0.10.0] - 2026-11-01

### Added

- `scripts/terintegrasi.sh`: verifies that a merged PR actually reached the integration branch before the integrated label, closing the issue or moving the card to Done (#41)
- Scheduled-workflow warning in `pr-merge-check.sh` for PRs that add `schedule`/`workflow_dispatch` workflows or `dependabot.yml` to a non-default branch; `menunggu-rilis` label and `scripts/menunggu-rilis.sh` keep such issues open until the files reach the default branch (#41)
- `cve-audit.sh` reports scheduled workflows that exist only on the integration branch (#41)
- `aicrew-ui-ux` asset guidance: SVG icons and logos (#40)

### Behavior changes

- `board.sh --sync` with `Tutup issue setelah merge integrasi: ya` no longer closes an issue without proof: exactly one merged PR from `issue-<n>` that reached the integration branch is required.
- Without a known integration branch, `terintegrasi.sh` only accepts PRs merged into the default branch (exit 2 otherwise).

## [0.9.1] - 2026-11-01

### Added

- `--reset-total` for `autopilot.sh`; the `--max-total` stop message now states the current value (#37)

### Fixed

- `board.sh` prints usage and exits 64 when arguments are missing (#38)

## [0.9.0] - 2026-11-01

### Added

- `scripts/cve-private.sh` collects the private-package patterns (#35)

### Security

- Private packages are never sent to OSV: patterns from a `Paket privat:` line in `docs/WORKFLOW.md`, `GOPRIVATE` (Go) and project `.npmrc` scopes mapped to non-public registries are removed before any query, including base-version queries. Skipped packages are reported as a count, never by name, and are not treated as safe. The gate reads patterns from the target branch and fails closed when they cannot be read (#35)

### Behavior changes

- Packages matching a private pattern are skipped by the CVE check instead of being sent to OSV; they are reported as not checked.

## [0.8.2] - 2026-11-01

### Fixed

- Autopilot limit detection is no longer fooled by normal reports that contain the word limit; the exit code is logged and suspicious output is archived (#33)

## [0.8.1] - 2026-11-01

### Fixed

- `cleanup.sh`: merged-PR evidence must be based on the default or integration branch; stacked PRs merged into a parent branch are not evidence (#31)
- Project v2 REST calls use `fields[]=` (#31)

## [0.8.0] - 2026-11-01

### Added

- `scripts/cleanup.sh`: reports and (with `--apply`) removes branches and worktrees proven merged (ancestor of the default/integration branch, or a merged PR with the same head SHA); never uses `--force`, prints tip SHAs for recovery, remote deletion with compare-and-swap (#26)
- `Bersihkan setelah merge: ya|laporkan|tidak` option and `orchestrate` cleanup step; `preflight` warns when the repository does not delete branches on merge and counts merged leftovers (#26)

### Behavior changes

- `Bersihkan setelah merge` defaults to `ya` for orchestrator-owned branches and worktrees (`issue-<n>`, `<repo>-wt-<n>`) when the line is missing from `WORKFLOW.md`.

## [0.7.0] - 2026-11-01

### Added

- Dependency CVE check against OSV: `scripts/cve-check.sh` (npm `package-lock.json`, Go `go.mod`, PyPI `requirements*.txt`) with target version and patch/minor/major advice, new-versus-existing exposure (#23)
- `pr-merge-check.sh` CVE gate for new or changed packages, with owner waiver `(cve)`; opt-out `Pemeriksaan CVE: tidak` read from the target branch (#23)
- `scripts/cve-audit.sh` and the `cve-audit` skill: one issue per vulnerable package, no duplicates (#23)

### Security

- Outbound network to `api.osv.dev` (ecosystem, package name and version only); unranked severity (`UNKNOWN`) is treated like HIGH; the gate fails closed when OSV is unreachable (#23)

### Behavior changes

- The dependency CVE gate is on by default: a PR that touches a lockfile can be rejected for new HIGH/CRITICAL/UNKNOWN exposure on production dependencies, and an unreachable OSV rejects the PR (fail-closed). Opt out with `Pemeriksaan CVE: tidak`.


## [0.6.4] - 2026-11-01

### Added

- REST fallback when the shared GraphQL limit is hit: `scripts/ghx.sh`, `board.sh`, `epic-link.sh` retry once through REST and announce `mode cadangan REST`; GraphQL-only steps are skipped with a warning, never guessed (#20)
- `pr-merge-check.sh` stays fail-closed but explains the GraphQL limit and the reset time (#20)

### Fixed

- Large REST pages go through stdin; the progress comment is not overwritten when a card is rejected (#20)

## [0.6.3] - 2026-10-31

### Added

- `scripts/lock.sh`: named lock for shared stacks (Docker/Keycloak) (#14)
- `tanpa-induk` label: issues intentionally outside an epic are skipped by `epic-link.sh --check` (#14)

## [0.6.2] - 2026-10-31

### Changed

- `board-init.sh` prints the manual UI steps on the normal path; `epic-link.sh` fails loudly; `--check` warns at the 200-issue limit (#13)

## [0.6.1] - 2026-10-31

### Added

- `epic-link.sh --check` lists open non-epic issues without a parent (#12)

### Changed

- Concept documentation (journey = epic = parent) and manual UI steps (#12)

### Fixed

- Integration branch name parsing with a trailing dot; safe rewrite of epic bodies (#12)

## [0.6.0] - 2026-10-31

### Added

- `scripts/epic-link.sh`: native sub-issues and checklist, `--inherit` so follow-up issues inherit their source epic (#11)
- Epic progress comment (`6/9 Done, 1 In progress`) and epic status that is not misleading; `WORKFLOW.md` is read from the integration branch; option `Tutup issue setelah merge integrasi` (#11)

### Changed

- Discovery and not-split labels are configurable; a closed epic is not mirrored to Done (#11)

## [0.5.1] - 2026-10-31

### Added

- Journeys are derived automatically from the PRD discussion; `breakdown` proposes journeys when the PRD has none (#10)

## [0.5.0] - 2026-10-31

### Added

- Journey/epic model: PRD and EPIC templates, `breakdown` creates one epic per journey (#9)
- Kanban: epic status computed from its children by `board.sh --sync`; epics appear on the board (#9)

### Changed

- Epics are not work: ignored by autopilot, the release report and resume (#9)

## [0.4.1] - 2026-10-31

### Changed

- `ISSUE.md` template is written in English, matching the default artifact language (#7)

## [0.4.0] - 2026-10-31

### Added

- Notification drivers `telegram | orca | both` in `notify.sh` (#6)
- `board-init.sh` creates a kanban board view; `.gitignore` entries for `.aicrew/` and `.claude/settings.local.json` through `kickoff` (`ensure-gitignore.sh`) (#6)
- Risk classes `risk:L0/L1/L2`: `breakdown` labels issues, auto-merge refuses `risk:L2` (#6)
- Configurable label names (`label.sh`) for the integrated and auto-decision labels; absolute worktree base path for Orca workspaces; `board.sh --sync` mirrors issues closed without a PR to Done when `Kartu Done: agen-setelah-merge` (#6)
- `preflight` warns about bypass-permissions launches; cross-repository discovery safety boilerplate in `ISSUE.md` (#6)

### Security

- `install-permissions.sh` grants merge permission per mode and adds deny rules for `gh repo delete`, `gh auth`, `gh ssh-key`, `gh gist` (#6)

### Behavior changes

- Merge permission is no longer granted unconditionally by `install-permissions.sh`; it depends on the configured merge mode.

## [0.3.0] - 2026-10-31

### Added

- `scripts/autostart.sh`: per-project macOS LaunchAgent that starts the autopilot (#5)
- The autopilot waits for the owner (merge or decision) by polling `gh` cheaply instead of running `claude` (#5)

### Behavior changes

- When a round changes nothing and every remaining issue only waits for a human, the autopilot now stops running `claude` and polls `gh`, ending with exit 3 after the wait limit instead of looping.


## [0.2.0] - 2026-10-31

### Added

- `aicrew-perf` role, `Batas perangkat keras` section and the `needs-perf` flow (#2, #3)
- `needs-security` and `needs-perf` merge gates: the PR must carry a passing report bound to the head commit, or an owner waiver with a reason (#2, #3)
- `scripts/baseline-scan.sh`: secrets, new dependencies and path warnings on the PR diff (#2, #3)
- The release verdict checks performance and security reports (#2, #3)

### Fixed

- Closing references, scoped waivers, a sturdier scanner, last verdict wins, labels matched case-insensitively (#2, #3)

### Behavior changes

- PRs labeled `needs-security` or `needs-perf` can no longer be merged through the gate without a passing report bound to the head commit or an owner waiver.


## [0.1.2] - 2026-10-31

### Added

- `scripts/guard-attribution.sh` hook blocks AI attribution in commits and PRs

### Changed

- Default artifact language is English for code, comments, commits and labels (#1)
- AI attribution is forbidden in all artifacts (#1)

### Behavior changes

- Commits and PRs that contain AI attribution are now blocked by the guard hook.

## [0.1.1] - 2026-10-28

### Added

- `PRIVACY.md`; Telegram settings through sensitive `userConfig`; directory listing columns
- Automatic release when the version in `plugin.json` is bumped (`release.yml`, `build-release.sh`)

### Fixed

- Removed `.gitattributes` that blocked the Anthropic plugin directory

## [0.1.0] - 2026-10-28

### Added

- Initial release: skills `kickoff`, `prd`, `breakdown`, `orchestrate`; agent roles `principal`, `senior-coder`, `qa`, `security`, `devops`, `ui-ux`, `reviewer`
- Scripts for autopilot, budget limits, resume, board, pre-flight checks, release report, PR merge gate and Telegram notifications; templates for ISSUE, PRD and WORKFLOW
- Visual identity, marketplace installation instructions and the release/test workflows
