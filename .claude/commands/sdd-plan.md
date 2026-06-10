---
description: Whole-project inception as Planner — produce vision + architecture + ADRs and seed a block of draft epics (interactive)
---

Act as **Planner** (`agents/planner.md`). That role file is the durable contract; this
command carries the interactive front-end.

The free-text whole-project idea is in `$ARGUMENTS`. If it is empty, ask the human for it.

1. Run `./init.sh`. If it exits non-zero, STOP and report — do not plan into a broken
   environment.
2. Read `harness.config.yaml` and the TaskStore (`state/tasks.json`, per `store/local.md`).
3. **Re-run guard.** If `specs/vision.md` or `specs/architecture.md` already exists, a
   default run STOPS and reports that the project already has a plan — point the human at
   `/sdd-drill` (F03) to deepen existing epics, or at an explicit amend mode that
   **appends** (never overwrites or renumbers). Do not silently overwrite.
4. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the outcomes, the non-goals, and the roadmap shape. Where the shape forks, offer
   **at most 3** options as **text-only** (markdown/ASCII) mockups — never images. Keep
   it short; ask only what you need to write the vision and sketch the roadmap.
5. **Write** `specs/vision.md` from `specs/_templates/vision.md` (north star: problem,
   users, outcomes, non-goals; it complements `specs/product.md`/`glossary.md`).
6. **Write** `specs/architecture.md` from `specs/_templates/architecture.md` (system
   shape + stable upfront decisions), and one ADR per decision at
   `specs/adr/NNNN-<title>.md` from `specs/_templates/adr.md` (4-digit, above the max
   existing ADR number); `architecture.md` references each ADR by its `ADR-NNNN` id.
   Stay at whole-system depth — defer per-epic deltas to `/sdd-drill` (F03).
7. **Seed** the roadmap: for each epic, write a `state/tasks.json` row with
   `status: "draft"` and `features: []` (ids as a next-sequential block strictly above
   the max existing `E##`, append-only, no reuse), and create
   `specs/epics/<id>-<slug>/epic.md` = title + one-paragraph business brief only (no
   `F01`, no feature spec).
8. **Re-validate** `state/tasks.json` against `store/tasks.schema.json`. If it fails,
   report the failure and do NOT claim a successful plan.
9. **Report** the artifacts written (`specs/vision.md`, `specs/architecture.md`, each
   `specs/adr/NNNN-*.md`), the seeded `draft` epics (ids + titles + `epic.md` paths), and
   tell the human to **run `/sdd-drill <epic-id>`** next. Do NOT spawn the Architect, do
   NOT write any feature spec, and do NOT advance any epic past `draft` — the Planner
   produces, never specs.
