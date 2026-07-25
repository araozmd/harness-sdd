# ADR-0001 — next() selection moves from prose routing to a deterministic tool

- **Status:** accepted (E16 drill, 2026-07-25)
- **Context:** The Orchestrator's `next()` selection is a combinatorial routing table
  (feature status × `sdd` × `autonomous` × epic gate × `depends_on` × umbrella slices ×
  owner scope) expressed as prose in `agents/orchestrator.md` and re-interpreted by a
  model every session. The 2026-07-24 investigation identified it as the harness's most
  bug-prone surface: a misread cascades to all work, and the failure mode is a *silent*
  wrong (or absent) selection.
- **Decision:** Selection becomes deterministic code. A zero-dependency
  `tools/next-task.mjs` reads `state/tasks.json`, applies every existing gate unchanged
  (draft-epic gate, `depends_on`, human spec-approval gate, owner scoping, slice
  topology), and emits the chosen id **plus a machine-readable reason** — including,
  when nothing is selectable, the per-candidate blocking reason (gated epic, unmet
  dependency naming the blocker, parked at human gate, owner-excluded, dependency
  cycle). The Orchestrator consumes this output instead of re-deriving routing in
  prose; the prose table remains as the tool's specification, not the runtime.
- **Consequences:**
  - E16-F01 (cycle detection + diagnostic) defines the reason-string vocabulary first;
    E16-F03 (`next-task.mjs`) MUST reuse it verbatim (`depends_on: E16-F01`).
  - The routing becomes unit-testable; orchestration bugs shift from
    "model misread prose" to "failing test".
  - No behavior change is permitted at introduction: the tool must reproduce the
    documented routing exactly (the prose table is the acceptance oracle).
  - Gate policy (what the gates ARE) stays in `agents/orchestrator.md` + config;
    the tool only executes it — keeping the human-auditable contract in markdown.
