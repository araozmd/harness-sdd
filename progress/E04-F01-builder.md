# E04-F01 — Builder hand-off note

Feature: Inception role + /sdd-new intake. Status confirmed `in-progress` before any
code was written. Backend `execution.builder.backend: in-session` (Loop A).

## What I implemented, per task (all T1–T14 ticked)

- **T1–T7 → `agents/inception.md` (created)** — the portable Inception role contract:
  - T1: skeleton in house style; guardrails up front (seeds-never-specs, pending-only,
    never-advance, no touching schema/orchestrator/architect, no new status).
  - T2: triage decision tree (3 altitudes, "exactly one"), next-sequential id
    allocation (epics project-wide, features within epic), no-reuse-of-vacated-ids,
    new-epic creates epic entry + `epic.md` + `F01`.
  - T3: TaskStore write spec (id/title/status:pending/sdd/autonomous/depends_on/spec_path).
  - T4: mandatory post-write schema re-validation + fail-stop (failure ⇒ report, not
    "seeded").
  - T5: intent-brief write to `progress/inbox/<feature-id>.md` (filename == id),
    frontmatter + sections, references `progress/inbox/E04-F01.md` as template.
  - T6: options/mockups text-only, at most 3.
  - T7: completion report (id + entry + inbox path + "run /sdd-next"); states it does
    NOT spawn the Architect or change status.
- **T8 → `.claude/commands/sdd-new.md` (created)** — thin Claude wrapper mirroring
  `.claude/commands/sdd-next.md`: `description:` frontmatter, "Act as Inception",
  reads idea via `$ARGUMENTS`, carries the interactive adaptive Q&A + ≤3 text-only
  options, defers the durable contract to the role file, ends with the seed report +
  "run /sdd-next".
- **T9 → `AGENTS.md` (modified)** — added Inception to the role list (`agents/*.md`
  row) and the flow diagram (`Inception ─► Orchestrator → …`); additive, no restructure.
- **T10 → `docs/WORKFLOW.md` (modified)** — added an "Intake — the step before
  `pending` (`/sdd-new`)" section + a small ASCII step feeding the existing state
  machine; the existing state diagram's states are untouched.
- **T11 → `tests/test_inception.sh` (created)** — static R1–R16 verification in the
  `tests/test_install.sh` style (POSIX sh + grep + python3 schema validation, with a
  jsonschema-or-fallback validator). Also wired into `verification.test_command` in
  `harness.config.yaml`. The manual `/sdd-new` walkthrough (§A/§B/§C) is the contract
  already documented in `inception.tests.md` for the Reviewer to perform once.
- **T12** — ran `./init.sh` (green) and all four test suites (green).
- **T13 → `VERSION`** — bumped `0.3.0` → `0.4.0` (MINOR ✨; touches `agents/`,
  `.claude/` glue, docs).
- **T14 → `CHANGELOG.md`** — added a `[0.4.0] — 2026-06-01` entry. (The `vX.Y.Z`
  git tag is a merge-time PR step for the human/Orchestrator — I do not commit/tag.)

## Files created / changed
- Created: `agents/inception.md`, `.claude/commands/sdd-new.md`,
  `tests/test_inception.sh`.
- Modified: `AGENTS.md`, `docs/WORKFLOW.md`, `harness.config.yaml`
  (test_command wiring), `VERSION`, `CHANGELOG.md`,
  `specs/epics/E04-intake/F01-inception/inception.tasks.md` (ticked T1–T14).
- NOT touched (DO NOT TOUCH, verified clean vs `main`): `store/tasks.schema.json`,
  `agents/orchestrator.md`, `agents/architect.md`, `.claude/commands/sdd-next.md`.
- Did NOT change `state/tasks.json` frontmatter/status or any spec frontmatter
  (Orchestrator owns status). Did not commit/push.

## Test results

`./init.sh` → exit 0 ("environment ready").

`tests/test_inception.sh` → exit 0, all 16 checks pass:
```
ok - R1 role_file_exists … ok - R16 docs_mention_intake
All inception tests passed.
```

Full configured suite:
```
install: PASS   umbrella: PASS   cascade: PASS   inception: PASS
```

## R-id coverage (R1–R16 all covered by a passing check)
R1 role_file_exists · R2 sdd_new_command · R3 seed_entry_schema_valid · R4
inbox_brief_exists · R5 inbox_brief_format · R6 tasks_schema_valid · R7
fail_stop_documented · R8 triage_documented · R9 new_epic_documented · R10
id_policy_documented · R11 no_spec_writes · R12 pending_only · R13 do_not_touch_clean
· R14 text_only_options · R15 completion_report · R16 docs_mention_intake.

R3/R4/R9 also have a manual `/sdd-new` walkthrough leg (§A/§B in `inception.tests.md`)
that the Reviewer runs once — the static legs assert the role/command/store contract;
the walkthrough exercises the live behavior end to end.

## For the Reviewer to scrutinize
- **R13 diff check** is conditional on a local `main` ref (`git rev-parse main`). It
  passed here; in CI confirm `main` is fetched or treat the unconditional schema-enum
  grep as the backstop.
- **`harness.config.yaml` edit** (adding `tests/test_inception.sh` to
  `test_command`) is not in the plan's explicit touch-list, but it is the established
  pattern used by E03-F01/F02 and is required by the tests.md non-functional check
  ("run alongside the existing tests/*.sh"). It is not on the DO NOT TOUCH list.
- **Manual walkthrough (§A/§B/§C)** is the only non-static verification and is the
  Reviewer's to perform — it is behavioral, not scripted.
- `progress/inbox/E04-F01.md` is reused as both the canonical brief template and the
  R5 fixture; if it changes, the R5 grep tokens must stay in sync.

## Open concerns
None blocking. Open *questions* are spec-level (deferred `--from-file`; next-sequential
vs fill-the-gap) and were confirmed at the human gate — not relitigated.
```
