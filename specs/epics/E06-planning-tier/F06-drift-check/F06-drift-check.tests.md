# Drift check on epic rollup (Scout re-validates remaining epics) — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete, executable
> test. The Reviewer fails the feature if any R-id lacks a passing test.
>
> This feature ships **prose + docs** (edits to two portable role files, the store
> contract, and one workflow doc) plus one test suite, so verification is the house way
> (cf. `tests/test_sdd_drill.sh`, `tests/test_architect_adr.sh`): required-phrase greps
> over the portable contract, one python fixture proving the F06 state shapes (a `done`
> epic whose features are all `done`; a `draft` post-demotion epic) validate against the
> **live** `store/tasks.schema.json` with **no schema change**, and one sandboxed
> `./init.sh` exit-0 run. All automated tests live in **`tests/test_drift_check.sh`**
> (POSIX sh; grep + python3 here-docs; zero new deps), wired into
> `verification.test_command`.
>
> **Suite-wide constraints (permanent-suite anti-pattern, recurred 4×):** never assert the
> exact `VERSION` literal (read the file at runtime); never couple the feature's CHANGELOG
> mention to the current-top version — grep the **marker across the whole CHANGELOG**, not
> the `## [$(cat VERSION)]` section; never `git diff` a DO-NOT-TOUCH file against `main`.
> Never mutate the live `state/tasks.json` — the fixture uses a **temp** file carrying the
> **required root `project` field**.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | `store/local.md` formalizes epic-done rollup (all features `done` ⇒ epic `done`, derive+persist+re-validate), no new status/schema | `tests/test_drift_check.sh::R1_epic_done_rollup_doc` — grep `store/local.md` for `epic` + `done`, `all features`/`every feature`, `derive`/`derived`, `persist`/`persisted`, `re-validate`/`revalidate`, and `no new status`/`no schema change` | static | ⬜ |
| R2 | Orchestrator derives+persists epic `done`, re-validates, then triggers drift check before selecting next | `tests/test_drift_check.sh::R2_orch_rollup_then_drift` — grep `agents/orchestrator.md` for `all`/`every` feature `done`, `set_status`, `re-validate`/`revalidate`, `drift`, and `before`/`next` (trigger before selecting next) | static | ⬜ |
| R3 | Drift check fires only on epic rollup to `done`; spawns read-only Scout in drift-check mode | `tests/test_drift_check.sh::R3_drift_trigger` — grep `agents/orchestrator.md` for `drift`, `only`/`only when` + `roll`/`rollup` + `done`, `Scout`, `read-only`, and `draft`/`planned`/`pending` (the re-validated set) | static | ⬜ |
| R4 | Scout drift-check mode: inputs + findings-file path + per-epic still-valid/stale+reason verdict | `tests/test_drift_check.sh::R4_scout_findings_shape` — grep `agents/scout.md` for `drift`, `progress/`+`scout-drift`, `per`/`each` epic, `still-valid`/`valid`, `stale`, and `reason`/`why`+`artifact` | static | ⬜ |
| R5 | Scout defines concrete S1/S2/S3 staleness signals; stale only when ≥1 fires | `tests/test_drift_check.sh::R5_concrete_signals` — grep `agents/scout.md` for `contradict`, `removed`/`renamed`, `supersedes`/`obsoletes`, and `at least one`/`≥ *1`/`one of`/`only when` (stale gate) | static | ⬜ |
| R6 | Scout read-only preserved: writes only `progress/`, never `state/tasks.json` | `tests/test_drift_check.sh::R6_scout_read_only` — grep `agents/scout.md` for `read-only`, `progress/`, and `never`/`not` + `state/tasks.json`/`set_status`/`state change` | static | ⬜ |
| R7 | Orchestrator demotes stale `planned`/`pending` → `draft` + re-validates `state/tasks.json` | `tests/test_drift_check.sh::R7_demote_to_draft` — grep `agents/orchestrator.md` for `demote`/`demotion`, `planned`+`draft` (and `pending`), `set_status`, `re-validate`/`revalidate`; PLUS the python fixture (below) proving the `planned → draft` post-demotion shape is schema-valid | static + fixture | ⬜ |
| R8 | Scout never writes `state/tasks.json`; Orchestrator alone applies demotion | `tests/test_drift_check.sh::R8_scout_flags_orch_acts` — grep `agents/orchestrator.md` for `Scout` + `never`/`not` + `state/tasks.json`/`write`, and `Orchestrator`/`set_status` + `demote`/`apply` (the Orchestrator acts) | static | ⬜ |
| R9 | Considers `planned`/`pending`/`draft`; stale `draft` stays+flagged; `in-progress`/`done` never demoted | `tests/test_drift_check.sh::R9_status_scope` — grep `agents/orchestrator.md` AND `store/local.md` for `planned`, `pending`, `draft`, and `never`/`not` + `in-progress`/`done` (excluded) | static | ⬜ |
| R10 | Backward-only invariant; re-drill stays manual `/sdd-drill` | `tests/test_drift_check.sh::R10_backward_only` — grep `agents/orchestrator.md` for `backward`, `never`/`not` + `forward`/`advance`, `in-progress`/`done` (never demoted), and `/sdd-drill` + `manual` | static | ⬜ |
| R11 | Reports re-drill pointer + optional flag-only `epic.md` note, never a content rewrite | `tests/test_drift_check.sh::R11_redrill_pointer_flag` — grep `agents/orchestrator.md` for `/sdd-drill`, `demoted on drift`, `flag`/`flag-only`/`flag only`, and `not`/`never` + `rewrite`/`content` | static | ⬜ |
| R12 | No remaining `draft`/`planned`/`pending` epics ⇒ no-op "nothing to re-validate" note, no status change | `tests/test_drift_check.sh::R12_noop_no_epics` — grep `agents/orchestrator.md` AND `agents/scout.md` for `nothing to re-validate`, and `no`/`none`/`empty` + `remaining`/`draft`/`planned` epics | static | ⬜ |
| R13 | No architecture/ADRs ⇒ no-op "nothing to re-validate" note, no status change | `tests/test_drift_check.sh::R13_noop_no_arch` — grep `agents/scout.md` (and/or `agents/orchestrator.md`) for `nothing to re-validate` and `no architecture`/`no`+`specs/architecture.md`/`absent` | static | ⬜ |
| R14 | `store/local.md` documents both the epic-done rollup and the drift check that follows | `tests/test_drift_check.sh::R14_store_doc` — grep `store/local.md` for `drift`, `demote`/`demotion`, `Scout`, `planned`+`draft`, and `re-validate`/`re-check`/`re-validates` (remaining epics) | static | ⬜ |
| R15 | WORKFLOW.md adds a distinct drift-check section: Scout flags, Orchestrator demotes, re-drill manual, backward-only | `tests/test_drift_check.sh::R15_workflow_doc` — grep `docs/WORKFLOW.md` for `drift`, `Scout`, `demote`/`demotion`/`demoted`, `draft`, `/sdd-drill`, and `backward` | static | ⬜ |
| R16 | Schema unchanged; an untouched TaskStore still validates; `./init.sh` exits 0 | `tests/test_drift_check.sh::R16_no_schema_change` — assert `store/tasks.schema.json` still admits `draft`/`planned`/`pending`/`done` epic statuses (the fixture below) and that NO new epic-status enum / field was added; run `./init.sh` and assert exit 0 | static + fixture + behavioral | ⬜ |
| R17 | Feature rollup, F01 gate, per-feature state machine, all `/sdd-*` + roles behaviorally unchanged; no-planning repo no-op | `tests/test_drift_check.sh::R17_backward_compatible` — assert `.claude/commands/sdd-new.md`, `sdd-plan.md`, `sdd-drill.md`, `sdd-next.md`, `sdd-fix.md`, `agents/planner.md`, `agents/driller.md`, `agents/architect.md`, `agents/builder.md`, `agents/reviewer.md` all still exist; assert `store/local.md` still carries the **feature-level** rollup (`Rollup rule`/`done` rollup for slices); run `./init.sh` exit 0 | static + behavioral | ⬜ |
| R18 | Contract lives in portable role/store/doc files; no new slash command, no installer wiring | `tests/test_drift_check.sh::R18_portable_no_glue` — assert the drift rules (`drift`, `demote`, `read-only` Scout, `nothing to re-validate`) are present in `agents/orchestrator.md`/`agents/scout.md`/`store/local.md` themselves; assert **no** `.claude/commands/sdd-drift*.md` was added and `harness-install.sh` is not newly referenced by F06 | static | ⬜ |
| R19 | One MINOR bump recorded in CHANGELOG (no literal version frozen; marker grepped across whole file) | `tests/test_drift_check.sh::R19_version_changelog` — assert `VERSION` matches `^[0-9]+\.[0-9]+\.[0-9]+$`; read `V=$(cat VERSION)` at runtime, assert `CHANGELOG.md` has a `## [<V>]` heading; assert the **drift-check marker** (`drift check`/`drift-check`) appears **somewhere in `CHANGELOG.md`** (grep the whole file, NOT the `## [<V>]` section) | static | ⬜ |

## The schema fixture (R7, R16 — the load-bearing python here-doc)
Construct a **temp** store (never the live `state/tasks.json`) carrying the **required root
`project` field**, holding (a) a `done` epic whose every feature is `done` (the epic-done
rollup target — D4/R1) and (b) a `draft` epic with one `pending` feature (the
post-demotion shape — R7), then assert it validates against `store/tasks.schema.json`
(jsonschema if installed, else the structural fallback that mirrors `init.sh`):

```json
{"project":"fixture","epics":[
 {"id":"E98","title":"Completed epic","status":"done",
  "features":[{"id":"E98-F01","title":"Done feature","status":"done","sdd":true,
   "depends_on":[],"spec_path":"specs/epics/E98-x/F01-y/"}]},
 {"id":"E99","title":"Demoted epic","status":"draft",
  "features":[{"id":"E99-F01","title":"Re-gated feature","status":"pending","sdd":true,
   "depends_on":[],"spec_path":"specs/epics/E99-x/F01-y/"}]}]}
```

This proves both F06 state shapes — a `done` epic whose features are all `done` (the rollup
output) and a `draft` epic (the demotion output) — are schema-valid **as written, with no
schema change** (R16). The fixture is created with `mktemp`, cleaned up on exit, and never
touches the live store. The structural fallback mirrors `init.sh`: `project` required, epic
`status` ∈ {`draft`,`planned`,`pending`,`in-progress`,`done`}, feature `status` ∈
{`pending`,`spec-ready`,`in-progress`,`in-review`,`done`}, id patterns.

## Behavioral / end-to-end checks (Reviewer, manual)
- Hand-walk an epic-rollup → drift-check run from the role contracts: confirm the prose
  unambiguously (1) derives+persists the epic's `done` when all its features are `done` and
  re-validates, (2) spawns the **read-only** Scout in drift-check mode against the remaining
  `draft`/`planned`/`pending` epics + architecture, (3) has the Scout write a per-epic
  still-valid/stale findings file to `progress/` and **no** state change, (4) has the
  **Orchestrator** demote stale `planned`/`pending` epics to `draft` and re-validate, (5)
  reports the `/sdd-drill <epic>` re-drill pointer and only ever moves an epic **backward**,
  and (6) emits a clear "nothing to re-validate" note on the no-op paths. Confirm nothing in
  the contract permits the Scout to write `state/tasks.json`, F06 to advance an epic or
  demote an `in-progress`/`done` epic, or F06 to rewrite an epic's brief / a feature spec
  (beyond the single `demoted on drift:` flag line). Any ambiguity is a reject.
- Confirm purely-additive scope by reading the **PR diff** (not a test that diffs against
  `main`): the diff touches no `store/tasks.schema.json`, no existing **feature-level**
  rollup logic, no `agents/planner.md`/`agents/driller.md`/`agents/architect.md`, no
  existing `/sdd-*` command, and adds **no** new `.claude/commands/*` file.
- Run the **full** `verification.test_command` (all existing suites + the new one): green,
  proving the additive change broke nothing.

## Non-functional checks
- Lint: n/a (`lint_command` empty for this repo).
- Types: n/a (`typecheck_command` empty).
- Zero-dependency: `tests/test_drift_check.sh` runs on POSIX sh + python3 only; the
  `jsonschema`-absent fallback still validates the F06-shape fixture. The fixture never
  mutates the live `state/tasks.json` and carries the required root `project` field.
