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

`$ARGUMENTS` may carry either a specific feature id or a scope token; forward it verbatim
to the Orchestrator:
- a specific feature id (e.g. `E01-F01`) → operate on that feature (unchanged).
- `--mine` → **scoped selection**: consider only features whose **effective owner**
  (feature `owner` else parent epic `owner`) equals the identity resolved from
  `workflow.identity` in `harness.config.yaml` (`@me`/`self` → authed `gh` user via
  `gh api user`; else literal). This is **owned-only** — it never claims unassigned work
  and never writes an `owner`; if the identity is unresolved or no owned actionable
  feature exists, it **fails closed** (selects nothing, reports, changes no state) and
  does **not** widen to board-wide selection. Bare `/sdd-next` (no `--mine`) is unchanged
  board-wide selection and ignores `owner`. The scoping semantics live in the
  **Orchestrator contract** (`agents/orchestrator.md` → "Ownership & scoped selection");
  this command only forwards the token.
