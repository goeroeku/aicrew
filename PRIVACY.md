# aiCrew privacy policy

Applies to the aiCrew plugin (`goeroeku/aicrew`). Last updated: 2026-11-01.

**Data collected: none.** aiCrew has no server, accounts, analytics or telemetry. All working files (`docs/`, `.aicrew/`, worktrees) stay on your own machine and in your own repository.

**This plugin has two outbound network paths: Telegram notifications (only if you enable them) and the dependency vulnerability check against OSV (on by default).** (The Orca driver, `AICREW_NOTIFY=orca`, only calls the local `orca` binary; no network.)

**1. Telegram.**
- Active only when you fill in your own Telegram bot token and chat ID (through the plugin settings `tg_token` and `tg_chat`, or the environment variables `AICREW_TG_TOKEN` and `AICREW_TG_CHAT`). Empty means nothing is sent.
- What is sent to `api.telegram.org`: one short notification text (e.g. "issue #N needs a decision") and the project folder name. No code, issue content or conversation.
- Telegram processes that message under Telegram's own policy. The token is kept in Claude Code's secure storage (plugin settings) or in your shell environment, not in the repository.

**2. CVE check (OSV), since 0.7.0.** `scripts/cve-check.sh` and `scripts/cve-audit.sh` ask the OSV service (`api.osv.dev`) whether your dependency versions have known vulnerabilities. It runs when a PR touches `package-lock.json`, `go.mod` or `requirements*.txt` (the `pr-merge-check.sh` gate) and when you run the `cve-audit` skill.
- What is sent to `api.osv.dev`: the ecosystem (npm, Go, PyPI), package name and version. No code, repository name, issue content or token.
- The names of private or internal packages (e.g. `@company/x`, `git.company.com/...`) are sent **unless you register them** (since 0.9.0). The IP address of the machine running the check is still sent. The plugin does not guess which packages are private; there are only three explicit sources: a `Paket privat: <pattern>, <pattern>` line in `docs/WORKFLOW.md` (all ecosystems; prefer this one, it travels with the repository and does not depend on the machine), `GOPRIVATE` (Go only; from the machine running the check), and project `.npmrc` scopes mapped to a registry other than `registry.npmjs.org`/`registry.yarnpkg.com` (npm only). `~/.npmrc` is never read, and from the project `.npmrc` only `@scope:registry=` lines are read (never tokens). Skipped packages are **not checked** (reported as a count, never by name), not treated as safe. The gate reads patterns from the target branch, so a new pattern takes effect after it is merged: merge a PR that contains only the pattern first. Public scopes deliberately mapped to a proxy (e.g. `@types`) are skipped too. Turn the whole check off with `Pemeriksaan CVE: tidak` if needed.
- OSV processes those requests under OSV's own policy. There is no token or account.
- To turn it off: the line `Pemeriksaan CVE: tidak` in `docs/WORKFLOW.md`. To use your own mirror: the environment variable `OSV_API`.

**Commands on your behalf.** Scripts call `git` and `gh` against your own project repository, using the account you are already logged in with. Those scripts send no data to anyone other than the GitHub or GitLab you use (exception: the CVE check to OSV above).

Questions or feedback: https://github.com/goeroeku/aicrew/issues
