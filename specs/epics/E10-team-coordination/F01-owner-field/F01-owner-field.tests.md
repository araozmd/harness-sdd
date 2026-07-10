# Ownership primitive: `owner` field + scoped `/sdd-next` — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete,
> executable test. The Reviewer fails the feature if any R-id lacks a passing test.
> Tests are shell suites in the harness style (see `tests/test_mirror.sh`,
> `tests/test_install.sh`). Assert **behavior**; never pin the exact VERSION and never
> diff DO-NOT-TOUCH files against `main`.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Schema defines optional string `owner` on epic + feature, not required | `tests/test_ownership.sh::owner_present_validates` | schema | ⬜ |
| R2 | Owner-free `state/tasks.json` still validates (no regression) | `tests/test_ownership.sh::owner_absent_validates` | schema | ⬜ |
| R3 | String `owner` valid; non-string `owner` rejected | `tests/test_ownership.sh::owner_type_enforced` | schema | ⬜ |
| R4 | Bare `/sdd-next` (no scope, no identity) = today's board-wide selection | `tests/test_ownership.sh::unscoped_is_boardwide_regression` | contract | ⬜ |
| R5 | `/sdd-next --mine` selects only effective-owner-== identity, else actionable rules | `tests/test_ownership.sh::mine_filters_to_owned` | contract | ⬜ |
| R6 | Effective owner = feature `owner` else epic `owner` else unowned | `tests/test_ownership.sh::effective_owner_rule_documented` | contract | ⬜ |
| R7 | Scoped mode never selects unowned + never writes/claims an owner | `tests/test_ownership.sh::scoped_owned_only_no_claim` | contract | ⬜ |
| R8 | Identity: `@me`/`self` → gh login; else literal | `tests/test_ownership.sh::identity_resolution_documented` | contract | ⬜ |
| R9 | Unresolved identity under `--mine` ⇒ fail closed, no widen, no state change | `tests/test_ownership.sh::unresolved_identity_fails_closed` | contract | ⬜ |
| R10 | Scoped select with no owned work ⇒ report + no widen to board-wide | `tests/test_ownership.sh::no_owned_work_no_widen` | contract | ⬜ |
| R11 | Scoping wording is tool-agnostic (in orchestrator contract, not CLI glue) | `tests/test_ownership.sh::scoping_contract_is_portable` | contract | ⬜ |
| R12 | Generated `/sdd-next` glue produced per target, byte-identical, carries scope | `tests/test_install.sh::sdd_next_glue_generated_all_targets` | installer | ⬜ |
| R13 | `/sdd-next` forwards `$ARGUMENTS`; installer assertion for `--mine` wiring | `tests/test_install.sh::sdd_next_scope_wiring_asserted` | installer | ⬜ |
| R14 | Docs describe owner field, effective owner, `workflow.identity`, `--mine` | `tests/test_ownership.sh::docs_describe_ownership` | doc | ⬜ |
| R15 | `VERSION` is valid SemVer + has a matching `CHANGELOG.md` entry (shape, not a git delta) | `tests/test_ownership.sh::version_bumped_minor` | meta | ⬜ |

## Test intent notes (how each check stays a behavior test)

- **R1 / R2 / R3 — schema (behavior, not snapshot).** Validate concrete
  `state/tasks.json` fixtures against `store/tasks.schema.json` (via `python3` /
  `ajv` / `jsonschema` as available; skip-and-report if no validator, matching
  `test_mirror.sh`'s node-absent skip pattern):
  - a doc with **no** `owner` anywhere ⇒ **valid** (R2 — the backward-compat guardrail);
  - a doc with a **string** `owner` on an epic and on a feature ⇒ **valid** (R1);
  - a doc with a **non-string** `owner` (e.g. `owner: 5`) ⇒ **invalid** (R3).
  Do **not** assert the exact schema bytes and do **not** diff the schema against `main`.

- **R4 — the byte-for-byte regression MUST.** Assert that with **no `owner` anywhere**
  and no `workflow.identity`, the documented `next()` selection is unchanged: verify the
  Orchestrator contract + `store/local.md` state that unscoped selection ignores `owner`
  and matches today's ordering/gating, and that the owner-free schema fixture (R2) is
  the same acceptance today. This is the anti-regression guardrail called out in the
  brief — keep it as a behavior/contract check, not a VERSION snapshot.

- **R5 / R6 / R7 / R8 / R9 / R10 / R11 — contract-wording assertions.** Because the
  Orchestrator is a markdown-prompt agent, these verify the **contract text** in
  `agents/orchestrator.md` deterministically encodes each behavior: the effective-owner
  rule (R6), the `--mine` filter layered on `next()` without relaxing gates (R5), the
  owned-only + no-claim rule (R7), identity resolution (R8), fail-closed on unresolved
  identity (R9), no-widen on empty scoped result (R10), and that the scoping lives in the
  portable contract rather than any CLI-specific glue (R11). Assert the presence of the
  governing phrases (e.g. `--mine`, "effective owner", "fail closed" / "unresolved",
  "no owned actionable", "never widen"/"board-wide"), not verbatim paragraphs.

- **R12 / R13 — installer wiring (asserted, per recurring Codex finding).** In
  `tests/test_install.sh`, run the installer into a temp target with the relevant
  front-ends selected and assert the generated `/sdd-next` body in each selected target
  dir (`.claude/commands/`, `.opencode/command/`, `.agents/workflows/`, and the Codex
  global prompts under the sandboxed `CODEX_HOME`) (a) exists, (b) is byte-identical
  across targets (reuse the existing `cmp -s` pattern), (c) forwards `$ARGUMENTS`, and
  (d) carries the `--mine` scoped-selection wiring. Sandbox `CODEX_HOME` for every
  installer-invoking case (existing suite guard).

- **R14 — docs.** Grep `docs/WORKFLOW.md` and `store/local.md` for the ownership
  vocabulary: an optional `owner` field (epic + feature), the effective-owner rule, the
  `workflow.identity` key, `/sdd-next --mine`, and the "no owner ⇒ today's behavior"
  guarantee.

- **R15 — VERSION bump (shape, not a git delta).** Assert `VERSION` parses as valid
  SemVer (`MAJOR.MINOR.PATCH`, numeric segments) and that `CHANGELOG.md` carries a
  matching entry for that version — the same stable shape-only form used by sibling
  suites in the gate (`test_doc_critic.sh` R15, `test_epic_lifecycle.sh` R14,
  `test_sdd_plan.sh` R23). Do **not** hard-code the exact new string, do **not** compare
  the working tree against `HEAD`/`main` (both are permanent-suite anti-patterns that
  break the gate once this feature is committed) — assert the *shape*, preserving the
  intent that an additive change ships with a VERSION bump documented in the changelog.

## Behavioral / end-to-end checks (Reviewer)
- Validate the three schema fixtures (owner-absent, owner-present, non-string-owner)
  against `store/tasks.schema.json` and confirm valid/valid/invalid respectively.
- Read `agents/orchestrator.md` and confirm a scoped-select walk-through:
  `/sdd-next --mine` with identity `alice` selects only `alice`-owned actionable
  features; an unowned actionable feature is skipped; an unresolved identity stops and
  reports; an empty owned result stops and reports (no board-wide fallback).
- Run the installer into a temp dir with all front-ends selected; confirm each
  `/sdd-next` glue is generated, byte-identical, and carries `--mine` + `$ARGUMENTS`.

## Non-functional checks
- Lint: `verification.lint_command` (empty in this repo) — n/a.
- Types: `verification.typecheck_command` (empty in this repo) — n/a.
- Full gate: `./init.sh` green, then `verification.test_command` (now including
  `sh tests/test_ownership.sh`) green.
