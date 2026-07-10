# Review — E09-F01 Doc-critic (round 2)

**Status: APPROVE** — ready to set `done`.

## Environment

- `./init.sh` exits 0.
- Full `verification.test_command` from `harness.config.yaml` exits 0, including `tests/test_doc_critic.sh` and the E09-F01 assertions in `tests/test_install.sh`.
- Fresh install into a temp dir with `harness-install.sh` places `.harness/agents/doc-critic.md` and the installed Planner/Driller/Architect reference the doc-critic role and the correct `target-type` values.

## Round-1 fix verification

The internal contradiction in `agents/planner.md` is resolved:

- **Previous state (round 1):** lines 104–109 said each seeded `epic.md` was "the epic title + a one-paragraph business brief only — no feature specs, no F01, no EARS, and no technical plan", while lines 111–123 required the same file to carry five drillable-minimum elements.
- **Round-2 state:** `agents/planner.md` lines 104–110 now state that each `epic.md` is **anchored by a one-paragraph business brief** and **also carries the drillable-minimum five elements**, while still prohibiting feature specs, `F01`, EARS acceptance criteria, and detailed technical plans. The "Drillable-minimum checklist" subheading and five-item list are preserved, so the R10 test assertion continues to match.

This unambiguously satisfies R10.

## Traceability

Every R-id in `specs/epics/E09-doc-quality/F01-doc-critic/E09-F01.spec.md` is covered by a passing test:

| R-id | Test |
|---|---|
| R1 | `tests/test_doc_critic.sh::test_doc_critic_role_exists` |
| R2 | `tests/test_doc_critic.sh::test_target_type_argument` |
| R3 | `tests/test_doc_critic.sh::test_target_type_scopes` |
| R4 | `tests/test_doc_critic.sh::test_calibration` |
| R5 | `tests/test_doc_critic.sh::test_advisory_inline_fix` |
| R6 | `tests/test_doc_critic.sh::test_best_effort_failure` |
| R7 | `tests/test_doc_critic.sh::test_progress_note` |
| R8 | `tests/test_doc_critic.sh::test_no_code_review` |
| R9 | `tests/test_doc_critic.sh::test_planner_invokes_critic` |
| R10 | `tests/test_doc_critic.sh::test_drillable_minimum` |
| R11 | `tests/test_doc_critic.sh::test_driller_invokes_critic` |
| R12 | `tests/test_doc_critic.sh::test_architect_invokes_critic` |
| R13 | `tests/test_install.sh::test_doc_critic_installed` |
| R14 | `tests/test_install.sh::test_doc_critic_references` |
| R15 | `tests/test_doc_critic.sh::test_version_and_changelog` |
| R16 | `tests/test_doc_critic.sh::test_workflow_docs` |
| R17 | `tests/test_doc_critic.sh::test_no_schema_change` |
| R18 | `tests/test_doc_critic.sh::test_no_new_gate` |

## Cross-file consistency

The three generating-agent contracts invoke `agents/doc-critic.md` consistently with the `target-type` values it defines:

| Caller | File | Invocation |
|---|---|---|
| Planner | `agents/planner.md` | `target-type=plan-output` |
| Driller | `agents/driller.md` | `target-type=epic-decomposition` |
| Architect | `agents/architect.md` | `target-type=feature-spec` |

`agents/doc-critic.md` defines exactly these three values in its invocation contract table. No contradiction detected.

## Conventions / DO NOT TOUCH

- `store/tasks.schema.json` is unchanged; R17 test passes.
- No new feature/epic status value or human gate is introduced; R18 test passes.
- Existing feature specs (E00–E08, E09-F02) are not retro-fitted.
- Existing test suites other than `tests/test_install.sh` and the new `tests/test_doc_critic.sh` are unchanged.
- `specs/_templates/*.md` are untouched.
- No new `/sdd-*` slash command was created; the critic is invoked by role contracts.

## Architecture alignment

`specs/architecture.md` does not exist and `specs/adr/` is empty. The feature's `.spec.md` correctly records `ADRs touched: none`; no fabricated ADRs are cited. The additive ADR-citation check does not fire.

## Verdict

Approve. The round-1 contradiction is resolved, every R-id traces to a passing test, the full test command is green, and the fresh install check passes. Recommend the Orchestrator set `E09-F01` to `done`.
