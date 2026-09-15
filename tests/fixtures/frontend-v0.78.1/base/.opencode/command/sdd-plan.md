---
description: Whole-project inception as Planner — produce vision + architecture + ADRs and seed a block of draft epics (interactive)
---

Act as **Planner** (`.harness/agents/planner.md`). That role file is the durable
contract; this command carries the interactive front-end.

The free-text whole-project idea is in `$ARGUMENTS`. If it is empty, ask the human for it.

1. Run `./.harness/init.sh`. If it exits non-zero, STOP and report — do not plan into a
   broken environment.
2. Read `.harness/harness.config.yaml` and the TaskStore (`.harness/state/tasks.json`,
   per `.harness/store/local.md`).
3. **Re-run guard.** If `.harness/specs/vision.md` or `.harness/specs/architecture.md`
   already exists, a default run STOPS and reports that the project already has a plan —
   point the human at `/sdd-drill` (F03) to deepen existing epics, or at an explicit
   amend mode that **appends** (never overwrites or renumbers). Do not silently
   overwrite.
4. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the outcomes, the non-goals, and the roadmap shape. Where the shape forks, offer
   **at most 3** options as **text-only** (markdown/ASCII) mockups — never images. Keep
   it short; ask only what you need to write the vision and sketch the roadmap.
5. **Write** `.harness/specs/vision.md` from `.harness/specs/_templates/vision.md`
   (north star: problem, users, outcomes, non-goals; it complements
   `.harness/specs/product.md`/`glossary.md`).
6. **Write** `.harness/specs/architecture.md` from
   `.harness/specs/_templates/architecture.md` (system shape + stable upfront
   decisions), and one ADR per decision at `.harness/specs/adr/NNNN-<title>.md` from
   `.harness/specs/_templates/adr.md` (4-digit, above the max existing ADR number);
   `architecture.md` references each ADR by its `ADR-NNNN` id. Stay at whole-system
   depth — defer per-epic deltas to `/sdd-drill` (F03).
7. **Seed** the roadmap: for each epic, write a `.harness/state/tasks.json` row with
   `status: "draft"` and `features: []` (ids as a next-sequential block strictly above
   the max existing `E##`, append-only, no reuse), and create
   `.harness/specs/epics/<id>-<slug>/epic.md` anchored by a one-paragraph business brief
   and carrying the **drillable-minimum five elements** (no `F01`, no feature spec, no
   EARS, no detailed technical plan):
   1. **Business brief** — one paragraph stating the problem/opportunity and the user.
   2. **Epic-level success criteria (outcomes)** — what "done" looks like for this epic.
   3. **Technical considerations / restrictions / non-goals** — constraints and explicit
      non-goals that bound the epic.
   4. **Cross-epic dependencies and boundaries** — which other epics this epic touches,
      relies on, or must stay clear of.
   5. **Pointers to relevant shared ADRs** — references in `architecture.md` / ADRs that
      constrain this epic (or an explicit note that none apply).
8. **Doc-critic checkpoint (before re-validation).** Spawn the **Doc-critic**
   (`.harness/agents/doc-critic.md`) as a sub-agent with `target-type=plan-output`,
   passing the paths just written (`specs/vision.md`, `specs/architecture.md`, each ADR,
   and every seeded `epic.md`). Apply any advisory findings inline, then proceed. If the
   critic invocation errors or times out, proceed best-effort and append a note under
   `.harness/progress/<run>/` recording the skipped/failed review.
9. **Re-validate** `.harness/state/tasks.json` against
   `.harness/store/tasks.schema.json`. If it fails, report the failure and do NOT claim
   a successful plan.
10. **Report** the artifacts written (`.harness/specs/vision.md`,
   `.harness/specs/architecture.md`, each `.harness/specs/adr/NNNN-*.md`), the seeded
   `draft` epics (ids + titles + `epic.md` paths), and tell the human to **run
   `/sdd-drill <epic-id>`** next. Do NOT spawn the Architect, do NOT write any feature
   spec, and do NOT advance any epic past `draft` — the Planner produces, never specs.
