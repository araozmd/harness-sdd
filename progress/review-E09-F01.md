# Review — E09-F01 Doc-critic

**Status: REJECT** — return to `in-progress`.

## Environment

- `./init.sh` exits 0.
- Full `verification.test_command` from `harness.config.yaml` exits 0, including `tests/test_doc_critic.sh` and the E09-F01 assertions in `tests/test_install.sh`.
- Fresh install into a temp dir with `harness-install.sh` places `.harness/agents/doc-critic.md` correctly.

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
| R13 | `tests/test_install.sh` (fresh-install `doc-critic.md` presence) |
| R14 | `tests/test_install.sh` (installed planner/driller/architect reference `doc-critic`) |
| R15 | `tests/test_doc_critic.sh::test_version_and_changelog` |
| R16 | `tests/test_doc_critic.sh::test_workflow_docs` |
| R17 | `tests/test_doc_critic.sh::test_no_schema_change` |
| R18 | `tests/test_doc_critic.sh::test_no_new_gate` |

## Cross-file consistency — hard reject

`agents/planner.md` contains a **provable internal contradiction** that the tests do not catch:

- **Lines 104–109** say each seeded `epic.md` is `"the epic title + a one-paragraph business brief only — no feature specs, no F01, no EARS, and no technical plan"`.
- **Lines 111–123** (the new E09-F01 drillable-minimum checklist) require the same `epic.md` to carry **five** elements: business brief, epic-level success criteria, technical considerations / restrictions / non-goals, cross-epic dependencies and boundaries, and pointers to relevant shared ADRs.

These two instructions cannot both be true. A Planner agent reading this contract cannot know whether it should write only a one-paragraph brief or the full five-element drillable-minimum block. This directly undermines **R10** of `E09-F01.spec.md`, which requires the Planner to enforce those five elements on every seeded `epic.md`.

**Expected:** `agents/planner.md` should state unambiguously that each seeded `epic.md` contains the drillable-minimum five elements. The old "title + one-paragraph brief only" language must be updated or removed (e.g., rephrase to say the `epic.md` is anchored by a one-paragraph business brief **and** carries the drillable-minimum checklist).

**Actual:** `agents/planner.md` still instructs the Planner to write "title + one-paragraph brief only" while also instructing it to enforce the five-element checklist.

## Additional note (non-blocking)

`harness-install.sh` was not modified, contrary to `E09-F01.plan.md`. The file is installed anyway because `copy agents` copies the whole directory, and `tests/test_install.sh` confirms this. This is functionally acceptable, but the Builder should either (a) update `harness-install.sh`/`manifest.txt` as the plan requested, or (b) explicitly document the deviation as intentional. It is not the reason for rejection.

## Required action before re-review

1. Reconcile `agents/planner.md` so the per-epic `epic.md` contract unambiguously requires the drillable-minimum five elements.
2. Re-run `./init.sh` and the full `verification.test_command`; confirm green.
3. Update this review file or the Builder hand-off with the fix.
