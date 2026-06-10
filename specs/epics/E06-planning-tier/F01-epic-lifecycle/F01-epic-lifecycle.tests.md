# Epic lifecycle: draft/planned states + next() gating — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete,
> executable test. The Reviewer fails the feature if any R-id lacks a passing test.
>
> All automated tests live in **`tests/test_epic_lifecycle.sh`** (POSIX sh, zero
> new deps: grep + python3 here-docs, one sandboxed `init.sh` run), wired into
> `verification.test_command`. `next()` is prose executed by the Orchestrator, so
> R5/R6/R8 are verified the house way (cf. `tests/test_inception.sh`): static
> assertion that the normative rule text exists in the portable contract files,
> plus fixture checks that the gated states are representable. **Suite-wide
> constraints:** never assert the exact `VERSION` literal (read the file at
> runtime); never diff DO-NOT-TOUCH files against `main`.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Schema accepts epic statuses `draft`, `planned` (plus the existing three) | `tests/test_epic_lifecycle.sh::R1_epic_enum_additive` — python fixture: synthetic store with one `draft` and one `planned` epic validates against `store/tasks.schema.json` (jsonschema if installed, else a fallback mirroring init.sh); also grep the schema for `"draft"`/`"planned"` inside the epic status enum | fixture | ✅ |
| R2 | Feature/slice status enums unchanged — feature `status: "draft"` rejected | `tests/test_epic_lifecycle.sh::R2_feature_enum_unchanged` — python fixture: synthetic store with a feature `status: "draft"` FAILS validation; grep that the feature enum line contains no `draft`/`planned` | fixture | ✅ |
| R3 | Legacy stores (no draft/planned epics) validate unchanged | `tests/test_epic_lifecycle.sh::R3_legacy_store_valid` — python fixture: synthetic store using only `pending`/`in-progress`/`done` epics validates; PLUS the live `state/tasks.json` validates against the edited schema | fixture | ✅ |
| R4 | init.sh fallback validator accepts the new epic statuses; `./init.sh` green on untouched repo | `tests/test_epic_lifecycle.sh::R4_init_parity` — grep `init.sh` `EPIC_STATUS` set for `draft` and `planned`; then run `./init.sh` and assert exit 0 | static + behavioral | ✅ |
| R5 | While an epic is `draft`, `next()` never returns its features (no per-feature override) | `tests/test_epic_lifecycle.sh::R5_draft_gate_normative` — grep `store/local.md` AND `agents/orchestrator.md` for the draft-gate rule (the words `draft` + never-actionable/never-select phrasing, and the no-override of `autonomous`) | static | ✅ |
| R6 | `planned` epics' features selectable exactly as `pending` epics' features | `tests/test_epic_lifecycle.sh::R6_planned_equals_pending` — grep `store/local.md` for the `planned`-treated-as-`pending` selection statement | static | ✅ |
| R7 | `store/local.md` documents the epic-level gate in the next() contract | `tests/test_epic_lifecycle.sh::R7_local_contract` — grep the `next()` section of `store/local.md` for the epic gate | static | ✅ |
| R8 | Rule lives in the portable role file, not `.claude/` glue | `tests/test_epic_lifecycle.sh::R8_portable_role_file` — grep `agents/orchestrator.md` for the gate; assert the rule exists there (presence in the portable file is the contract — no assertion about `.claude/` contents) | static | ✅ |
| R9 | WORKFLOW.md documents `draft → planned → in-progress → done` + legacy alias | `tests/test_epic_lifecycle.sh::R9_workflow_lifecycle` — grep `docs/WORKFLOW.md` for the lifecycle chain and the `legacy alias` phrasing for `pending` | static | ✅ |
| R10 | Epic template comment shows the new lifecycle | `tests/test_epic_lifecycle.sh::R10_epic_template` — grep `specs/_templates/epic.md` for `draft` and `planned` in the status comment | static | ✅ |
| R11 | local.md states `pending` ≡ `planned` for gating | `tests/test_epic_lifecycle.sh::R11_alias_equivalence` — grep `store/local.md` for the equivalence/legacy-alias statement | static | ✅ |
| R12 | Draft epic with non-`pending` feature ⇒ init.sh warns AND exits 0; schema does not reject | `tests/test_epic_lifecycle.sh::R12_warn_only_invariant` — sandbox: copy the harness to a temp dir (no `.git`), write a `state/tasks.json` with a `draft` epic containing an `in-progress` feature, run `./init.sh`; assert exit 0 and a warning line (`⚠️` + the epic/feature id) in output; python fixture: the same store passes schema validation | behavioral + fixture | ✅ |
| R13 | board-mirror.md notes epic statuses never map to columns | `tests/test_epic_lifecycle.sh::R13_mirror_note` — grep `store/board-mirror.md` for the epic-status/`draft`/`planned` note | static | ✅ |
| R14 | One MINOR bump recorded in CHANGELOG | `tests/test_epic_lifecycle.sh::R14_version_changelog` — assert `VERSION` matches `^[0-9]+\.[0-9]+\.[0-9]+$`; read `V=$(cat VERSION)` at runtime and assert `CHANGELOG.md` contains a `## [<V>]` heading whose section mentions `draft` and `planned` (no literal version is hard-coded in the test) | static | ✅ |

## Behavioral / end-to-end checks (Reviewer, manual)
- Hand-walk `next()` as the Orchestrator would: given a hypothetical store with
  epic `Ex: draft` containing feature `Ex-F01: pending, autonomous: true` and epic
  `Ey: planned` containing `Ey-F01: pending`, confirm the contract text in
  `store/local.md` + `agents/orchestrator.md` unambiguously selects `Ey-F01` and
  can never select `Ex-F01`. Any ambiguity in the prose is a reject.
- Confirm purely-additive scope: the diff touches no feature/slice enum values, no
  `.claude/` glue, no `tools/sync-board.mjs`, no `agents/inception.md`, and no
  status in `state/tasks.json` (verify by reading the PR diff, **not** by a
  test that diffs against `main`).
- Run the **full** `verification.test_command` (all existing suites + the new
  one): green, proving the additive change broke nothing.

## Non-functional checks
- Lint: n/a (`lint_command` empty for this repo).
- Types: n/a (`typecheck_command` empty).
- Zero-dependency: `tests/test_epic_lifecycle.sh` and the edited `init.sh` run on
  POSIX sh + python3 only; the `jsonschema`-absent fallback path still validates
  (R4) and still warns (R12).
