# Builder — E09-F01 Doc-critic (round 2)

## Summary

Addressed the Reviewer's round-1 rejection: reconciled the internal contradiction
in `agents/planner.md` between the per-epic `epic.md` contract and the
E09-F01 drillable-minimum checklist.

## Fix detail

- **Problem:** `agents/planner.md` lines 104–109 said each seeded `epic.md` was
  "the epic title + a one-paragraph business brief only — no feature specs, no
  F01, no EARS, and no technical plan", while lines 111–123 required the same
  file to carry five elements (business brief, success criteria, technical
  considerations/restrictions/non-goals, cross-epic dependencies/boundaries, and
  pointers to shared ADRs).
- **Resolution:** Rewrote the per-epic `epic.md` section heading and lead
  paragraph so the contract now unambiguously states that the file is
  **anchored by a one-paragraph business brief** and **also carries the
  drillable-minimum five elements**, while still prohibiting feature specs,
  `F01`, EARS acceptance criteria, and detailed technical plans. The
  "Drillable-minimum checklist" subheading and five-item list are preserved
  intact so the existing R10 test assertion continues to match.

## Files changed (round 2)

- `agents/planner.md` — reconciled the per-epic `epic.md` contract (R10, R12).
- `specs/epics/E09-doc-quality/F01-doc-critic/E09-F01.tasks.md` — added a
  round-2 reconciliation note to T2.

## Files NOT changed (round 2)

- `harness-install.sh` / `manifest.txt` — still not modified. The manifest
  already lists `.harness/agents/` as a harness-owned directory that is copied
  in full on every install/upgrade, so `agents/doc-critic.md` is included
  implicitly. `tests/test_install.sh` verifies the installed file and
  references explicitly. This deviation from the plan's optional explicit-list
  wording remains intentional and functionally acceptable per the Reviewer's
  non-blocking note.

## Tests run

1. `./init.sh` — exits 0.
2. Full `verification.test_command` from `harness.config.yaml` — all suites green,
   including `tests/test_doc_critic.sh` and the E09-F01 assertions in
   `tests/test_install.sh`.
3. Re-read `agents/planner.md` lines 104–127 — the contradiction is gone; the
   drillable-minimum five elements are required while the prohibited
   feature-spec/EARS/technical-plan boundaries remain.

## Status

Round-2 fix complete, all self-checks pass. Ready for re-review.
