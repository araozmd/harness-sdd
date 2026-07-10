# Builder — E09-F01 Doc-critic

## Summary

Implemented the doc-critic advisory review pass over harness-generated docs per the
E09-F01 spec and plan.

## Files changed

- `agents/doc-critic.md` (new) — portable reviewer contract defining the three
  `target-type` scopes (`plan-output`, `epic-decomposition`, `feature-spec`),
  calibration (completeness/consistency/clarity/scope/YAGNI), advisory-only behavior,
  inline-fix-then-proceed, best-effort error/timeout handling, progress-note output,
  and the documents-only boundary.
- `agents/planner.md` — added the `/sdd-plan` doc-critic checkpoint
  (`target-type=plan-output`) and the drillable-minimum checklist for each seeded
  `epic.md`.
- `agents/driller.md` — reordered so ADR deltas are written before re-validation,
  and added the `/sdd-drill` doc-critic checkpoint
  (`target-type=epic-decomposition`).
- `agents/architect.md` — added the pre-`spec-ready` doc-critic checkpoint
  (`target-type=feature-spec`).
- `harness-install.sh` — no behavioral change required; the existing `copy agents`
  step already copies `agents/doc-critic.md` into `.harness/agents/` on every
  install/upgrade.
- `tests/test_install.sh` — added assertions that `.harness/agents/doc-critic.md`
  is installed and that the installed Planner/Driller/Architect contracts reference
  the doc-critic role and their `target-type` values.
- `tests/test_doc_critic.sh` (new) — static grep contract assertions covering
  R1–R18 plus portability.
- `docs/WORKFLOW.md` — added a distinct `## Doc-critic checkpoints` section
  documenting the three checkpoints and the advisory/inline-fix/best-effort nature.
- `VERSION` — bumped 0.25.0 → 0.26.0.
- `CHANGELOG.md` — added `## [0.26.0]` entry describing the doc-critic role and
  the three checkpoint wirings.
- `harness.config.yaml` — appended `&& sh tests/test_doc_critic.sh` to
  `verification.test_command`.

## Files NOT changed

- `store/tasks.schema.json` — unchanged (R17).
- `state/tasks.json` — unchanged by the Builder (pre-existing Orchestrator/Architect
  edits were present before implementation).
- Existing feature specs (E00–E08, E09-F02) — not retro-fitted.
- Existing test suites other than `tests/test_install.sh` and the new
  `tests/test_doc_critic.sh` — additive only.
- `specs/_templates/*.md` — unchanged.

## Tests run

1. `./init.sh` — exits 0.
2. Full `verification.test_command` from `harness.config.yaml` — all suites green,
   including the new `tests/test_doc_critic.sh`.
3. Fresh install into a temp dir with `harness-install.sh` — verified
   `.harness/agents/doc-critic.md` is present.

## Deviations / risks

- `harness-install.sh` required no source-code modification because the existing
  `copy agents` step copies the entire `agents/` directory. The plan acknowledged this
  possibility ("adding the file to the source is sufficient"). The new
  `tests/test_install.sh` assertions close the loop.
- `agents/driller.md` was reordered so ADR deltas are written before the doc-critic
  checkpoint and before re-validation. This is necessary so the critic can review ADR
  deltas per R11; the reorder is minimal and does not change the Driller's contract
  semantics.

## Status

All tasks ticked, all self-checks pass. Ready for Reviewer.
