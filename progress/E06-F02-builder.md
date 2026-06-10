# E06-F02 `/sdd-plan` — Builder progress

Feature: **E06-F02** (`/sdd-plan` inception skill: vision + architecture + draft epics)
Branch: `feat/sdd-plan-skill` · Status on entry/exit: `in-progress` (unchanged — Builder
does not advance status).

## Tasks completed (all, in order)
- **T1** (R4, R18) — created `specs/_templates/vision.md` (Problem / Users / Outcomes /
  Non-goals + a "complements `product.md`/`glossary.md`" note).
- **T2** (R5) — created `specs/_templates/architecture.md` (System shape / Stable upfront
  decisions / ADR index referencing `ADR-NNNN` ids).
- **T3** (R6) — created `specs/_templates/adr.md` (one-decision: Context / Decision /
  Consequences).
- **T4** (R1, R3, R9, R10, R11, R12, R13, R14, R15, R16, R17, R18, R20) — created the
  portable Planner role `agents/planner.md` carrying every pinned guardrail
  (producer-never-specs, never-past-`draft`, F01 `draft`/`next()` gate reuse, ADR
  location/numbering D4, id-block allocation D5, re-run/amend D2, depth boundary D6,
  vision-complements-`product.md` D3, portability for any AGENTS.md CLI).
- **T5** (R2, R3) — created `.claude/commands/sdd-plan.md` wrapper (points at
  `agents/planner.md`, reads `$ARGUMENTS`, runs `./init.sh` first, ≤3 text-only options,
  re-run guard, reports without spawning the Architect or advancing status).
- **T6** (R21) — added a "Whole-project inception (`/sdd-plan`)" section to
  `docs/WORKFLOW.md` placing it upstream of `/sdd-drill` (F03) and `/sdd-next`.
- **T7** (R22) — added a `/sdd-plan` one-liner to `README.md` quickstart.
- **T8** (R1–R23) — created `tests/test_sdd_plan.sh` (POSIX sh; grep contract + python
  `features: []` draft-epic fixture against `store/tasks.schema.json` + `./init.sh`
  exit-0 run). Reads `VERSION` at runtime; no `git diff` vs main; never mutates the live
  `state/tasks.json`.
- **T9** (wiring) — appended `&& sh tests/test_sdd_plan.sh` to
  `harness.config.yaml` `verification.test_command` and extended its comment.
- **T10** (R23) — bumped `VERSION` 0.15.0 → 0.16.0 (MINOR) and added the matching
  `## [0.16.0]` `CHANGELOG.md` entry describing `/sdd-plan`, the vision/architecture/ADR
  artifacts, and the `features: []` draft-epic seeding.
- **T11** — final self-check: new suite + full `verification.test_command` + `./init.sh`
  all green.

## Files created
- `agents/planner.md`
- `.claude/commands/sdd-plan.md`
- `specs/_templates/vision.md`
- `specs/_templates/architecture.md`
- `specs/_templates/adr.md`
- `tests/test_sdd_plan.sh`

## Files modified
- `docs/WORKFLOW.md`
- `README.md`
- `harness.config.yaml`
- `VERSION` (0.15.0 → 0.16.0)
- `CHANGELOG.md`
- `specs/epics/E06-planning-tier/F02-sdd-plan/F02-sdd-plan.tasks.md` (ticked)
- `specs/epics/E06-planning-tier/F02-sdd-plan/F02-sdd-plan.tests.md` (status ✅)

## DO-NOT-TOUCH honored
`agents/inception.md`, `.claude/commands/sdd-new.md`, `.claude/commands/sdd-next.md`,
`store/tasks.schema.json`, `agents/orchestrator.md`, `store/local.md`,
`specs/product.md`, `specs/glossary.md`, existing `tests/test_*.sh`, and all
`state/tasks.json` statuses — none modified.

## Verification
- New suite: `sh tests/test_sdd_plan.sh` → 23/23 R-ids pass, exit 0.
- Full suite (`harness.config.yaml` `verification.test_command`): all 9 suites green,
  exit 0.
- `./init.sh` → exit 0 (structure intact, TaskStore valid against schema).

## Hand-off
All tasks ticked, self-check green. Ready for the Orchestrator to move E06-F02 to
`in-review` for the Reviewer. Builder did not change any status and did not open a PR.
