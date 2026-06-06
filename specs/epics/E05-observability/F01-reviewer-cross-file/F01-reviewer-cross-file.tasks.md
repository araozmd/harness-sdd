# Reviewer cross-file consistency + explicit build↔review rounds — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one
> at a time. Each task names the R-id(s) it satisfies. Check off when done.
> This feature is **prose only** — no production code. Honor the DO NOT TOUCH list
> in `.plan.md`.

- [x] **T1** (R1, R2, R3, R4) — In `agents/reviewer.md`, add a new numbered item to
  the "What you check" list titled **Cross-file consistency**: for any change to a
  role/contract/prose file, load the *collaborators the diff references* (unchanged
  files the change invokes) and verify the change's preconditions are satisfied by —
  and do not contradict — the contracts in those files. Explicitly state the
  expansion is **scoped to the diff's references (curate-don't-dump)**, not a
  whole-repo dump.
- [x] **T2** (R5, R6) — In that same item, add the verdict rule: **hard reject** when
  a precondition is *provably violated* (contradiction demonstrable from the loaded
  files); otherwise **flag for the Builder to investigate and justify** rather than
  blocking.
- [x] **T3** (R7) — In that same item, add the **PR #10 worked example**: a new
  in-session dispatch step in `orchestrator.md` told the Builder to open a child
  repo's PR, contradicting `builder.md` Loop A's precondition that the Builder never
  opens a PR — a contradiction with no failing test.
- [x] **T4** (R8) — In `agents/reviewer.md` (Verdict / "Be honest, not generous"),
  reinforce that a reject emits **specific, actionable, file-based feedback** naming
  the contradicting files and expected vs. actual behavior, written to
  `progress/<run>/review.md`.
- [x] **T5** (R9, R10) — In `agents/orchestrator.md`, make the build↔review loop
  **explicit and multi-round**: reject → actionable file feedback → `in-progress` →
  Builder addresses → re-review, **repeating until green**, and state each **round is
  recorded** (one history line per round in `progress/history.md`).
- [x] **T6** (R11) — Coherence pass: scan `AGENTS.md` and `docs/WORKFLOW.md`; if any
  sentence presents review as a single pass, align it with the multi-round loop.
  Minimal touch — edit only on a real contradiction.
- [x] **T7** (R12) — Bump `VERSION` `0.5.0` → `0.6.0` and add a `## [0.6.0]` entry to
  `CHANGELOG.md` describing the cross-file consistency check + explicit build↔review
  rounds.
- [x] **T8** (R1–R13) — Create `tests/test_reviewer.sh` (POSIX sh + grep, mirroring
  `tests/test_inception.sh`): assert each required clause exists in
  `agents/reviewer.md` / `agents/orchestrator.md`, and assert the DO-NOT-TOUCH
  invariant (the status enum string in `store/tasks.schema.json` is unchanged). Make
  it executable.
- [x] **T9** (R1–R13) — Run `./init.sh`, then `tests/test_reviewer.sh` and the rest
  of the test suite; ensure green before hand-off.
