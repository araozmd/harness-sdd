# /sdd-plan inception skill (vision + architecture + draft epics) — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete, executable
> test. The Reviewer fails the feature if any R-id lacks a passing test.
>
> This feature ships **prose + templates + docs** (a portable role file, a Claude
> slash-command wrapper, three templates, two doc edits), so verification is the house
> way (cf. `tests/test_inception.sh`): file-existence + required-phrase greps over the
> portable contract, one python fixture that proves the canonical seeded shape
> (`status: draft`, `features: []`) validates against `store/tasks.schema.json`, and one
> sandboxed `./init.sh` exit-0 run. All automated tests live in
> **`tests/test_sdd_plan.sh`** (POSIX sh; grep + python3 here-docs; zero new deps),
> wired into `verification.test_command`.
>
> **Suite-wide constraints (permanent-suite anti-pattern):** never assert the exact
> `VERSION` literal (read the file at runtime); never `git diff` a DO-NOT-TOUCH file
> against `main` (the genuine permanent invariant is the *content* of the portable
> contract, re-checked below — whether a PR touched a DO-NOT-TOUCH file is a
> Reviewer-reads-the-diff concern, not a frozen suite assertion). Never mutate the live
> `state/tasks.json` — fixtures use temp files.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Portable Planner role file exists, names the artifacts it produces, stated portable | `tests/test_sdd_plan.sh::R1_planner_role_exists` — `[ -f agents/planner.md ]`; grep for `vision`, `architecture`, `ADR`/`adr`, `draft`, and `AGENTS.md-compatible`/`portable` | static | ✅ |
| R2 | `/sdd-plan` command points at the role file + reads `$ARGUMENTS` | `tests/test_sdd_plan.sh::R2_sdd_plan_command` — `[ -f .claude/commands/sdd-plan.md ]`; grep `agents/planner.md` and `$ARGUMENTS` | static | ✅ |
| R3 | ≤3 text-only option mockups, never images — in BOTH role and command | `tests/test_sdd_plan.sh::R3_text_only_options` — grep `text.*only`/`markdown/ASCII` and `at most 3`/`≤ *3` in `agents/planner.md` AND `.claude/commands/sdd-plan.md`; assert "never images"/"not generate images" in the role | static | ✅ |
| R4 | Vision template exists with problem/users/outcomes/non-goals | `tests/test_sdd_plan.sh::R4_vision_template` — `[ -f specs/_templates/vision.md ]`; grep (case-insensitive) `Problem`, `User`/`Audience`, `Outcome`, `Non-goal` | static | ✅ |
| R5 | Architecture template exists with system shape + upfront decisions + ADR index | `tests/test_sdd_plan.sh::R5_arch_template` — `[ -f specs/_templates/architecture.md ]`; grep `shape`, `decision`, and `ADR` | static | ✅ |
| R6 | One-decision ADR template exists | `tests/test_sdd_plan.sh::R6_adr_template` — `[ -f specs/_templates/adr.md ]`; grep `Decision` and (`Context` or `Consequence`) | static | ✅ |
| R7 | Role mandates writing `specs/vision.md` from the vision template on a greenfield run | `tests/test_sdd_plan.sh::R7_writes_vision` — grep `agents/planner.md` for `specs/vision.md` and `specs/_templates/vision.md` | static | ✅ |
| R8 | Role mandates writing `specs/architecture.md` referencing its ADRs by id | `tests/test_sdd_plan.sh::R8_writes_architecture` — grep `agents/planner.md` for `specs/architecture.md`, `specs/_templates/architecture.md`, and `ADR-` (reference-by-id) | static | ✅ |
| R9 | Role pins ADR path `specs/adr/NNNN-...`, 4-digit, above-max numbering | `tests/test_sdd_plan.sh::R9_adr_location_numbering` — grep `agents/planner.md` for `specs/adr/` and `NNNN`/`4-digit`/`zero-pad` and `above`/`max`/`no reuse` | static | ✅ |
| R10 | Role scopes depth to stable upfront decisions; defers per-epic deltas to F03; no feature-level design | `tests/test_sdd_plan.sh::R10_depth_boundary` — grep `agents/planner.md` for `upfront`/`stable`/`whole-system`, `delta`, `/sdd-drill`/`F03`, and `feature-level` (deferred/never) | static | ✅ |
| R11 | Role seeds `draft` epics with `features: []`, next-sequential id block, no reuse | `tests/test_sdd_plan.sh::R11_draft_features_empty` — grep `agents/planner.md` for `status: "draft"`/`draft`, `features: []`/`empty`, `next-sequential`/`above`, `no reuse`/`never reuse`; PLUS python fixture: a synthetic epic `{id:"E99",status:"draft",features:[]}` written to a TEMP store validates against `store/tasks.schema.json` (jsonschema if present, else structural fallback mirroring init.sh) | static + fixture | ✅ |
| R12 | Role mandates per-epic `epic.md` = title + one-paragraph brief only (no F01/specs) | `tests/test_sdd_plan.sh::R12_epic_md_brief_only` — grep `agents/planner.md` for `epic.md`, `one-paragraph`/`business brief`, and that it states no `F01`/no feature spec | static | ✅ |
| R13 | Role re-validates after seeding and fail-stops on validation failure | `tests/test_sdd_plan.sh::R13_revalidate_fail_stop` — grep `agents/planner.md` for `store/tasks.schema.json`/`re-validate` and `not.*claim.*success`/`must not claim a successful plan`/`report the failure` | static | ✅ |
| R14 | Role states seeds-never-specs (no spec files, no EARS/plan, no Architect spawn) | `tests/test_sdd_plan.sh::R14_seeds_never_specs` — grep `agents/planner.md` for each of `.spec`, `.plan`, `.tasks`, `.tests` as forbidden, `never.*spec`/`produce.*never spec`, and `not.*spawn`/`never.*spawn` the Architect | static | ✅ |
| R15 | Role states never past `draft`; names F03 as the `draft → planned` step | `tests/test_sdd_plan.sh::R15_never_past_draft` — grep `agents/planner.md`: every seeded epic `draft`; forbids advancing to each of `planned`, `in-progress`, `in-review`, `done`; forbids stamping `autonomous: true`; names `/sdd-drill`/`F03` as the flip step | static | ✅ |
| R16 | Role reuses F01 `draft` state/gate — no new status, no new approval mechanism | `tests/test_sdd_plan.sh::R16_reuse_f01_gate` — grep `agents/planner.md` for `draft` gate/`next()` reference, `no new status`, and `inert`/`never select`/`gate` | static | ✅ |
| R17 | Role: existing vision.md/architecture.md ⇒ default refuse + amend appends only | `tests/test_sdd_plan.sh::R17_rerun_behavior` — grep `agents/planner.md` for `already exists`/`already has a plan`, `STOP`/`refuse`, `/sdd-drill`/`amend`, and `append`/`without rewriting`/`renumber` | static | ✅ |
| R18 | Role + vision template: `vision.md` complements `product.md`/`glossary.md` | `tests/test_sdd_plan.sh::R18_complements_product` — grep `agents/planner.md` AND `specs/_templates/vision.md` for `complement` (not supersede/absorb) and `product.md`; grep role states it does not rewrite/delete `product.md`/`glossary.md` | static | ✅ |
| R19 | `/sdd-new`, `/sdd-next`, Inception unchanged; untouched repo green | `tests/test_sdd_plan.sh::R19_backward_compatible` — assert `.claude/commands/sdd-new.md`, `.claude/commands/sdd-next.md`, `agents/inception.md` all still exist and still point at their original contracts (grep `agents/inception.md` in sdd-new.md); run `./init.sh` and assert exit 0; assert no `specs/vision.md`/`specs/architecture.md` is required by the schema (a store without them validates — covered by R11 fixture / live store) | static + behavioral | ✅ |
| R20 | Contract lives in the portable role file, not solely `.claude/` glue | `tests/test_sdd_plan.sh::R20_portable_contract` — assert the producer rules (`draft`, `features: []`, seeds-never-specs) are present in `agents/planner.md` itself (presence in the portable file is the contract — no assertion about `.claude/` contents) | static | ✅ |
| R21 | WORKFLOW.md places `/sdd-plan` upstream of `/sdd-drill` + `/sdd-next`, producer-only | `tests/test_sdd_plan.sh::R21_workflow_doc` — grep `docs/WORKFLOW.md` for `/sdd-plan`, `draft`, and `/sdd-drill`/`drill`; assert it states producer/never feature specs/never past `draft` | static | ✅ |
| R22 | README one-liner for `/sdd-plan` | `tests/test_sdd_plan.sh::R22_readme_oneliner` — grep `README.md` for `/sdd-plan` | static | ✅ |
| R23 | One MINOR bump recorded in CHANGELOG | `tests/test_sdd_plan.sh::R23_version_changelog` — assert `VERSION` matches `^[0-9]+\.[0-9]+\.[0-9]+$`; read `V=$(cat VERSION)` at runtime and assert `CHANGELOG.md` contains a `## [<V>]` heading whose section mentions `/sdd-plan` (no literal version hard-coded) | static | ✅ |

## Behavioral / end-to-end checks (Reviewer, manual)
- Hand-walk a `/sdd-plan` greenfield run from the role contract: confirm the prose
  unambiguously produces `specs/vision.md`, `specs/architecture.md`, one or more
  `specs/adr/NNNN-*.md`, and ≥1 `draft` epic with `features: []` + matching `epic.md` —
  and that nothing in the contract permits writing a feature `.spec/.plan/.tasks/.tests`,
  spawning the Architect, or advancing an epic past `draft`. Any ambiguity is a reject.
- Confirm purely-additive scope by reading the **PR diff** (not a test that diffs against
  `main`): the diff touches no schema enum, no `next()` gating in
  `agents/orchestrator.md`/`store/local.md`, no `agents/inception.md`, no
  `.claude/commands/sdd-new.md` / `sdd-next.md`, and no `specs/product.md`/`glossary.md`.
- Run the **full** `verification.test_command` (all existing suites + the new one):
  green, proving the additive change broke nothing.

## Non-functional checks
- Lint: n/a (`lint_command` empty for this repo).
- Types: n/a (`typecheck_command` empty).
- Zero-dependency: `tests/test_sdd_plan.sh` runs on POSIX sh + python3 only; the
  `jsonschema`-absent fallback still validates the seeded `features: []` draft-epic
  fixture (R11). The fixture never mutates the live `state/tasks.json`.
