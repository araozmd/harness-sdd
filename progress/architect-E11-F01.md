# Architect run — E11-F01 (GitHub Projects sync via gh CLI, no MCP)

Wrote the 4-file spec under `specs/epics/E11-github-projects/F01-gh-cli-sync/`.

## Key decision: EXTEND, not replace
The existing `tools/sync-board.mjs` is already a gh-CLI-only, no-MCP, idempotent,
inert-by-default `github-projects` mirror using the Projects **v2** GraphQL / `gh
project` surface. F01 completes it (preflight hardening + docs pin + installer-test
assertion + VERSION bump) rather than forking it, avoiding a second GitHub code path.

## Doc-critic checkpoint (target-type=feature-spec, run inline by the Architect)
Reviewed the four files across completeness, consistency, clarity, scope, YAGNI.
- **Finding (applied inline):** R5 and R8 were not cited by any task in `tasks.md`,
  leaving two requirements untraced in the requirement→task matrix. Added task **T5b**
  citing R5, R8. All R-ids R1–R14 now appear in both `tasks.md` and `tests.md`.
- No other blocking findings. Ownership correctly deferred to E10 (R9); Jira/Azure
  left as stubs (no scope creep); tests reuse existing suites (test_mirror.sh +
  test_install.sh) rather than adding a new one; VERSION asserted by shape, not literal.

Handoff: told the Orchestrator the feature is spec-ready.
