# Installer script — Tasks

> Worked top to bottom, one at a time. Each names the R-id(s) it satisfies.

- [x] **T1** (R10) — Make `init.sh` self-locating (cd to its own script dir on startup).
- [x] **T2** (R2) — Add a `VERSION` file as the single source of the version string.
- [x] **T3** (R1) — In `harness-install.sh`, allowlist-copy the harness body into `<target>/.harness/`.
- [x] **T4** (R8) — After copy, `sed`-reset `test_command`/`lint_command`/`typecheck_command` to empty in the target config.
- [x] **T5** (R6) — Seed `product.md`, a schema-valid bootstrap `tasks.json`, and `progress/history.md` behind not-exists guards.
- [x] **T6** (R5) — Guard project files so upgrade re-runs never overwrite them.
- [x] **T7** (R2) — Write `.harness/.harness-version` and an informational `manifest.txt`.
- [x] **T8** (R3, R4) — Implement the idempotent `awk` pointer-block merge for CLAUDE.md/AGENTS.md/GEMINI.md.
- [x] **T9** (R7) — Generate `.claude/agents/*.md` shims + `.claude/commands/sdd-next.md` resolving against `.harness/`.
- [x] **T10** (R9) — Add arg guards (missing target / self-target) that exit non-zero before any writes.
- [x] **T11** — Write tests per `installer.tests.md` (`tests/test_install.sh`).
- [x] **T12** — Run `./init.sh` + `sh tests/test_install.sh`; ensure green before hand-off.
- [x] **T13** — Document usage and the bootstrap story in `docs/INSTALL.md`.
