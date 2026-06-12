---
description: Run the Orchestrator loop on the next actionable task (init → route → delegate)
---

Act as the **Orchestrator** (`agents/orchestrator.md`).

1. Run `./init.sh`. If it exits non-zero, STOP and report — do not work on a broken
   environment.
2. Read `harness.config.yaml` and the TaskStore (per `store/local.md`).
3. Find the next actionable feature and route it by status per `docs/WORKFLOW.md`:
   - `pending` + sdd:true → spawn **architect**, then set `spec-ready` and PAUSE for
     the human gate (unless `autonomous`). When spawning the Architect, pass the
     feature's intent brief `progress/inbox/<feature-id>.md` (when it exists) as a
     primary input alongside the spec templates, so Inception's captured intent,
     constraints, and open questions reach spec generation.
   - `spec-ready` + `autonomous:true` → human gate is skipped: set `in-progress`,
     spawn **builder** with the specs, then `in-review`. (A `spec-ready` feature
     *without* `autonomous:true` is parked at the human gate — not actionable.)
   - `in-progress` → spawn **builder** with the approved specs only, then `in-review`.
   - `in-review` → spawn **reviewer**; approve → `done`, reject → back to `in-progress`.
4. Append what happened to `progress/history.md`.

$ARGUMENTS may name a specific feature id (e.g. `E01-F01`); if given, operate on it.
