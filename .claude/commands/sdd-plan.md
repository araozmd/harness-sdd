---
description: Whole-project inception as Planner — produce vision + architecture + ADRs and seed a block of draft epics (interactive)
---

Act as **Planner** (`agents/planner.md`). That role file is the durable
contract; this command carries the interactive front-end.

The free-text whole-project idea is in `$ARGUMENTS`. If it is empty, ask the human for it.

1. Run `./init.sh`. If it exits non-zero, STOP and report — do not plan into a
   broken environment.
2. Read `harness.config.yaml` and the TaskStore (`state/tasks.json`,
   per `store/local.md`).
3. **Re-run guard.** If `specs/vision.md` or `specs/architecture.md`
   already exists, a default run STOPS and reports that the project already has a plan —
   point the human at `/sdd-drill` (F03) to deepen existing epics, or at an explicit
   amend mode that **appends** (never overwrites or renumbers). Do not silently
   overwrite.
4. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the outcomes, the non-goals, and the roadmap shape. Where the shape forks, offer
   **at most 3** options as **text-only** (markdown/ASCII) mockups — never images. Keep
   it short; ask only what you need to write the vision and sketch the roadmap.
5. **Write** `specs/vision.md` from `specs/_templates/vision.md`
   (north star: problem, users, outcomes, non-goals; it complements
   `specs/product.md`/`glossary.md`).
6. **Write** `specs/architecture.md` from
   `specs/_templates/architecture.md` (system shape + stable upfront
   decisions), and one ADR per decision at `specs/adr/NNNN-<title>.md` from
   `specs/_templates/adr.md` (4-digit, above the max existing ADR number);
   `architecture.md` references each ADR by its `ADR-NNNN` id. Stay at whole-system
   depth — defer per-epic deltas to `/sdd-drill` (F03).
7. **Repo topology output.** Repo topology is an output of planning, never an input.
   When `specs/architecture.md` names more than one deployable, write exactly
   one `repo-topology ADR` at `specs/adr/NNNN-<title>.md`, allocated strictly
   above the max existing ADR number (4-digit, no reuse), and reference it from
   `specs/architecture.md`'s ADR index by its `ADR-NNNN` id. Also write a draft
   manifest at `umbrella.manifest.draft.yaml` with one `repos:` entry per
   deployable, each with a coordinator-safe logical key, `path`, `init`, `test_command`,
   `delegate_cmd` (empty string), and optionally the `scaffold_cmd` runner key that is
   optional and opaque: the harness never interprets it and only the E28-F03 promotion
   runs it. The entry key is a logical name, not the directory name: it must match
   `[a-z0-9-]+` (the slice-id suffix grammar, so a valid slice's `repo` can equal the
   key; normalize a dotted dir such as `api.v2` to `api-v2`) while `path`
   carries the actual directory (`path: ../api.v2`). After normalizing every deployable
   name to `[a-z0-9-]+`, the keys must be **unique**: when two deployable names collide on
   one key (for example `api.v2` and `api-v2` both normalize to `api-v2`), disambiguate
   deterministically in the order the deployables are named in
   `specs/architecture.md` — the first keeps the bare key and each later
   collision appends `-2`, `-3`, … (`api-v2`, then `api-v2-2`) — because
   `manifestRepos()` rejects duplicate repository keys, so a shared key would leave one
   deployable with no usable `repos:` entry. Write each `path` relative to the
   draft file's own directory (the child
   sibling). The draft's header must mark it a
   `DRAFT` and state that it is `inert`.
   The draft is inert and is not the switch: never set or change `umbrella.manifest` in
   `harness.config.yaml`, and never write `umbrella.manifest.yaml`, so
   the draft's presence alone does not engage umbrella mode. Engagement is the config key
   pointing at an existing manifest — that is E28-F03's promotion, not yours.
   When `specs/architecture.md` names exactly one deployable (or none), write
   neither a `repo-topology ADR` nor an `umbrella.manifest.draft.yaml`.
   The Planner is the single writer of the draft manifest. `/sdd-drill` never creates or
   amends `umbrella.manifest.draft.yaml`; a topology change is a `/sdd-plan`
   amend that is **append-only** and reconciles the draft.

   An amendment is **append-only**: it appends a dated `## Repo topology` delta section
   to `specs/architecture.md` and a new `repo-topology ADR` above the max
   existing ADR number, instead of rewriting the original section. An amend's delta is
   **authoritative for every deployable it names**: the effective deployable set is the
   union of the original architecture and every appended topology delta with the **latest
   delta winning per deployable**, so a later delta that renames or removes a deployable
   drops the obsolete name from the effective deployable set instead of preserving it.
   The trigger reads that **effective set**, not the original section alone: when the
   effective set
   falls to one deployable (or none), the Planner removes the derived
   `umbrella.manifest.draft.yaml` and writes no new `repo-topology ADR` — the
   already-committed repo-topology ADRs are preserved (append-only, never deleted) — and
   when it is still more than one, the Planner reconciles the draft to exactly the
   effective set, removing the entries whose deployables are gone.
8. **Seed** the roadmap: for each epic, write a `state/tasks.json` row with
   `status: "draft"` and `features: []` (ids as a next-sequential block strictly above
   the max existing `E##`, append-only, no reuse), and create
   `specs/epics/<id>-<slug>/epic.md` anchored by a one-paragraph business brief
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
9. **Doc-critic checkpoint (before re-validation).** Spawn the **Doc-critic**
   (`agents/doc-critic.md`) as a sub-agent with `target-type=plan-output`,
   passing the paths just written (`specs/vision.md`, `specs/architecture.md`, each ADR,
   and every seeded `epic.md`). Apply any advisory findings inline, then proceed. If the
   critic invocation errors or times out, proceed best-effort and append a note under
   `progress/<run>/` recording the skipped/failed review.
10. **Re-validate** `state/tasks.json` against
   `store/tasks.schema.json`. If it fails, report the failure and do NOT claim
   a successful plan.
11. **Report** the artifacts written (`specs/vision.md`,
   `specs/architecture.md`, each `specs/adr/NNNN-*.md`, and, when
   the plan names multiple deployables, the draft manifest at
   `umbrella.manifest.draft.yaml`), the seeded
   `draft` epics (ids + titles + `epic.md` paths), and tell the human to **run
   `/sdd-drill <epic-id>`** next. Do NOT spawn the Architect, do NOT write any feature
   spec, and do NOT advance any epic past `draft` — the Planner produces, never specs.
