# E16 — Harness robustness & rationale (harness-engineering investigation follow-ups)

## Problem

A 2026-07-24 investigation (full repo analysis + external harness-engineering research)
confirmed the harness's architecture is sound but surfaced three gaps: (1) a `depends_on`
cycle — between features or umbrella slices — silently makes work unselectable with no
diagnostic (the Orchestrator no-ops without saying why); (2) the harness never states
*why it exists* — which mechanisms compensate for current model weaknesses (candidates
for deletion as models improve) versus which encode durable process value (specs,
traceability, human gates) — so users can't reason about what to keep, and newcomers
lack a "why a harness at all" rationale; (3) the Orchestrator's `next()` selection is a
combinatorial prose routing table (status × sdd × autonomous × epic gate × depends_on ×
slices) re-interpreted by a model every session — the single most bug-prone surface in
the harness.

## Success criteria

- A dependency cycle is detected structurally (warn at `init.sh`, refuse at selection
  time with a named cycle) and the Orchestrator always reports *why* nothing was
  selectable instead of a silent no-op.
- A "why a harness" rationale doc exists for users, built on the two-layer model
  (temporary capability-compensation vs durable trust-and-intent), plus a deletion
  ledger classifying each mechanism with a re-test note per model generation.
- `next()` selection is deterministic, zero-dep, and testable (`tools/next-task.mjs`),
  emitting the chosen id + machine-readable reason; the Orchestrator consumes its
  output instead of re-deriving the routing in prose.

## Features

| id | title | depends_on |
|----|-------|------------|
| E16-F01 | depends_on cycle detection (features + slices) + Orchestrator "why nothing selectable" diagnostic | — |
| E16-F02 | Deletion ledger + why-a-harness rationale docs (compensation vs durable two-layer model) | — |
| E16-F03 | Deterministic next() selection: zero-dep tools/next-task.mjs emitting chosen id + reason | E16-F01 |

ADRs: [ADR-0001](../../adr/0001-deterministic-next-selection.md) — next() routing
moves from prose to a deterministic tool; F01's diagnostic reason strings are the
shared vocabulary F03 must reuse.
