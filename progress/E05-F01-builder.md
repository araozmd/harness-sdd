# E05-F01 — Builder progress (Loop A, in-session)

Feature: Reviewer cross-file consistency + explicit build↔review rounds.
Status confirmed `in-progress` + `autonomous: true` in TaskStore before any edit.

## What I did (tasks T1–T9, all ticked)
- **T1–T3** `agents/reviewer.md`: added "What you check" item **5. Cross-file
  consistency** — load the collaborators the diff references (scoped,
  curate-don't-dump, no whole-repo dump); verify preconditions are satisfied by and
  do not contradict the invoked contracts; verdict rule (provably violated ⇒ hard
  reject, suspected ⇒ flag for Builder to justify); inline **PR #10 worked example**
  (orchestrator dispatch telling the Builder to open a child PR vs. builder.md Loop A
  "Builder never opens a PR"). Renumbered the old item 5 (Contract artifact) to 6.
- **T4** `agents/reviewer.md` "Be honest, not generous": reject emits specific,
  actionable, **file-based** feedback naming the contradicting files + expected vs.
  actual, written to `progress/<run>/review.md`.
- **T5** `agents/orchestrator.md`: new "Build↔review rounds" section — explicit,
  multi-round loop repeating **until green** (reject → file feedback → `in-progress`
  → Builder addresses → re-review); each round recorded as one line per round in
  `progress/history.md`; no status/schema change.
- **T6** `docs/WORKFLOW.md`: aligned the end-to-end example step 6 with the
  multi-round loop (no single-pass claim; the diagram already showed the reject loop).
- **T7** `VERSION` 0.5.0 → 0.6.0 (MINOR ✨); `CHANGELOG.md` `## [0.6.0]` entry.
- **T8** Created `tests/test_reviewer.sh` (POSIX sh + grep, mirrors
  test_inception.sh), one assertion per R-id R1–R13 incl. DO-NOT-TOUCH (status enum
  + builder.md/architect.md unchanged vs main). Made executable. Wired into
  `harness.config.yaml` `verification.test_command`.
- **T9** Self-check green.

## Self-check result (all green)
- `./init.sh` → exit 0.
- `sh tests/test_install.sh && sh tests/test_umbrella.sh && sh tests/test_cascade.sh
  && sh tests/test_inception.sh && sh tests/test_reviewer.sh` → exit 0.
- DO NOT TOUCH unchanged vs main: `store/tasks.schema.json`, `agents/builder.md`,
  `agents/architect.md`.

## Files changed by this feature
- `agents/reviewer.md`, `agents/orchestrator.md`, `docs/WORKFLOW.md`,
  `VERSION`, `CHANGELOG.md`, `harness.config.yaml`, `tests/test_reviewer.sh` (new).

Handing back to the Orchestrator for `in-review`. Did not commit / open a PR / mark
done — not the Builder's call.
