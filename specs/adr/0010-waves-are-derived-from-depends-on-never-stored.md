# ADR-0010 — Waves and the critical path are derived from `depends_on`; the harness stores no second plan

- **Status:** accepted (E36 seed, 2026-10-25)
- **Date:** 2026-10-25

## Context

Operators want to build in waves: start the critical path, fan the independent leaves out
to sub-agents or to other machines, and see what is safe to run in parallel. Today the
information exists only as `depends_on` edges in `state/tasks.json`, consumed one feature at
a time by the deterministic selector (ADR-0001). So the operator re-derives the roadmap in a
prompt every session and hand-assigns features to machines.

Options: (a) store a wave plan or lane assignment on the board — a second source of truth
that drifts from `depends_on` the moment a feature is added or parked; (b) compute waves on
demand from the graph the selector already validates, print them, and let fan-out consume
the computed set; (c) a cross-clone lease protocol so two machines never pick the same
feature — needs state outside git or a service, and `/sdd-next <id>` plus `--mine` already
give an operator an exact, conflict-free handle per machine.

## Decision

Option (b). Waves are a **projection**: `done` features are wave 0; wave N is the set of
non-done features whose every dependency is in a wave below N; a feature with no
dependencies is wave 1; the critical path is the longest dependency
chain by feature count (ties broken by ADR-0001 order). One function in `tools/next-task.mjs`
computes both; `--waves` prints them; the Driller's report ends with the same view for the
epic it just seeded; `/sdd-next --wave` consumes wave 1's independent autonomous features
and fans them out through the existing parallel-fix coordinator discipline (isolated
worktrees, board lock, one PR per feature). Nothing about a wave is written to the board.
Multi-machine distribution stays `/sdd-next <id>` per machine, chosen from the printed wave;
a lease field is explicitly out of scope.

## Consequences

- The roadmap view can never contradict the board, because it is the board.
- Adding, parking or re-sequencing a feature changes the waves immediately.
- Fan-out inherits every safety property of the parallel-fix lane (worktree isolation,
  HARNESS_DIR board writes, serialized merges) and adds none of its own state.
- Two machines running bare `/sdd-next` on identical boards still pick the same feature;
  that is a known, documented limitation, not a bug this ADR hides.
