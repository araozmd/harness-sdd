# Builder — E10-F01: Ownership primitive (`owner` field + scoped `/sdd-next`)

Status handed back to Orchestrator for `in-review` (Builder does not declare `done`).

## Tasks completed (T1–T13, all ticked)
- **T1** `store/tasks.schema.json` — added optional `"owner": {"type":"string"}` to the
  epic object `properties` and the feature object `properties`. Did NOT touch any
  `required` array, `status` enums, the `slices` subschema, or the `allOf` cross-field rule.
- **T2** `agents/orchestrator.md` — added the "Ownership & scoped selection" subsection
  (tool-agnostic): unscoped = today's behavior (R4), effective owner (R6), `--mine` filter
  layered on `next()` never relaxing gates (R5), owned-only + no claim (R7), identity
  resolution (R8), fail-closed (R9), no-widen (R10). Board-mirror one-way note preserved.
- **T3** `harness.config.yaml` — added `workflow.identity: ""` with resolution comment.
- **T4** `harness-install.sh` — edited the single `CMDDIR/sdd-next.md` heredoc to document
  + forward `--mine` via `$ARGUMENTS`, delegating semantics to `.harness/agents/orchestrator.md`.
  One edit propagates to Claude/OpenCode/Antigravity/Codex via existing copy loops.
- **T5** `.claude/commands/sdd-next.md` — source-repo committed body mirrored to match.
- **T6** `docs/WORKFLOW.md` — "Ownership & scoped selection" section (owner, effective owner,
  identity, `--mine`, "no owner anywhere ⇒ today's behavior").
- **T7** `store/local.md` — extended the TaskStore/`next()` description with owner +
  effective-owner + scoped filter (owned-only, no claim, fail-closed, no-widen).
- **T8** `tests/test_ownership.sh` — NEW behavior suite (R1–R11, R14, R15).
- **T9** `tests/test_install.sh` — added `--mine` + `$ARGUMENTS` assertions on the generated
  `/sdd-next` for Claude/OpenCode/Antigravity/Codex (byte-identity already cross-checked).
- **T10** `harness.config.yaml` — appended `&& sh tests/test_ownership.sh` to
  `verification.test_command`.
- **T11** `VERSION` 0.27.3 → 0.28.0 (MINOR, additive) + `CHANGELOG.md` entry.
- **T12/T13** — every R-id maps to a passing test; `./init.sh` exits 0; full
  `verification.test_command` (incl. the new ownership suite) green.

## Verification
- `./init.sh` → exit 0.
- Full `verification.test_command` (14 existing suites + `test_ownership.sh`) → exit 0.
- `test_doc_critic.sh` R15 auto-picked up VERSION `0.28.0` (no exact-string freeze).

## Spec ambiguity resolved
- None substantive. The four spec files fully specified the boundary (F01 owned-only,
  no claim-on-select, no reassign UX). I kept the schema change strictly additive and
  used behavior/contract-text assertions (never a VERSION freeze, never a DO-NOT-TOUCH
  diff vs `main`). VERSION was bumped exactly one MINOR step per R15 (0.27.3 → 0.28.0).
