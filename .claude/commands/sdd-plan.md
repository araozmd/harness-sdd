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
3. **Detect the mode and branch.** If `specs/vision.md` or
   `specs/architecture.md` already exists, the project already has a plan. A
   default run that was not asked to amend STOPS and reports that, pointing the human
   at `/sdd-drill` (F03) to deepen existing epics or at an explicit **amend** run. The
   run then takes **exactly one** of two explicit branches:
   - **Greenfield branch (first run)** — entered when neither
     `specs/vision.md` nor `specs/architecture.md` exists: continue
     with steps 4–8 and write the vision, the architecture + ADRs, the repo-topology
     output, and the roadmap.
   - **Amend branch** — entered when the project already has a plan and the human asked
     for an amend: SKIP the greenfield template writes in steps 5–6 — an amend never
     rewrites `specs/vision.md` or `specs/architecture.md` and never
     renumbers an existing ADR — and append any new `draft` epics above the current
     maximum. Only when the amend detects a deployable-set change — a deployable added,
     removed, or given a new name — does it append the dated topology delta and the new
     `repo-topology ADR` and reconcile or remove the derived draft, as the repo-topology
     contract below describes; an amend that only adds epics or non-topology ADR deltas
     must not touch the topology artifacts. This amend consumes the Driller's persisted
     **topology handoff** when one exists: read `progress/<run>/topology-handoff.md`,
     which carries the full resulting deployable set the drill discovered — each
     deployable's logical key, its `path`, and why it is separate — so the amend detects
     the change from the persisted set instead of guessing. Never rewrite, re-seed, or
     renumber an existing artifact or roadmap entry.
4. Run a short, **adaptive** Q&A with the human to clarify: the problem and who it is
   for, the outcomes, the non-goals, and the roadmap shape. Where the shape forks, offer
   **at most 3** options as **text-only** (markdown/ASCII) mockups — never images. Keep
   it short; ask only what you need to write the vision and sketch the roadmap.
5. **Greenfield branch only — Write** `specs/vision.md` from `specs/_templates/vision.md`
   (north star: problem, users, outcomes, non-goals; it complements
   `specs/product.md`/`glossary.md`).
6. **Greenfield branch only — Write** `specs/architecture.md` from
   `specs/_templates/architecture.md` (system shape + stable upfront
   decisions), and one ADR per decision at `specs/adr/NNNN-<title>.md` from
   `specs/_templates/adr.md` (4-digit, above the max existing ADR number); the
   repo-topology decision is excluded here, owned by the repo-topology step;
   `architecture.md` references each ADR by its `ADR-NNNN` id. Stay at whole-system
   depth — defer per-epic deltas to `/sdd-drill` (F03).
7. **Repo topology output.** Repo topology is an output of planning,
   never an input. The repo-topology decision is excluded from the generic ADR pass
   above: the repo-topology step fulfills that pass and writes exactly one
   `repo-topology ADR`, so a greenfield plan never produces a second. The topology output
   step is itself gated on an actual
   deployable-set change: Only when the amend added or removed a deployable, or gave
   one a new name, does it append the dated topology delta and the new `repo-topology
   ADR` and reconcile the draft, while a non-topology amend leaves the topology
   artifacts untouched. On a greenfield run the set is new, so when
   `specs/architecture.md` names more than one deployable, write exactly
   one `repo-topology ADR` at `specs/adr/NNNN-<title>.md` — a single decision
   that names each repository and explains why it is separate — allocated strictly
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
   one candidate key (for example `api.v2` and `api-v2` both normalize to `api-v2`),
   allocate them deterministically in the order the deployables are named in
   `specs/architecture.md`, probing the complete set of keys already assigned —
   for each deployable in that order, take its normalized name if that candidate is unused,
   otherwise append `-2`, `-3`, … and take the smallest suffix whose candidate is not
   already assigned, so `api`, `api!`, `api-2` allocate `api`, `api-2`, `api-2-2` —
   because `manifestRepos()` rejects duplicate repository keys, so a shared key would leave
   one deployable with no usable `repos:` entry. On an amend, the Planner reconciles against
   the existing draft instead of reallocating its keys: each **surviving** deployable keeps
   its already-assigned key, so a survivor is never renumbered, and a suffix is allocated
   only for a newly added deployable. A removed deployable's key is never reused by a
   different deployable in the same reconciliation, so an existing slice whose `repo` named
   the removed deployable cannot silently resolve onto a survivor. Write each `path` relative to the
   draft file's own directory (the child
   sibling). The draft's header must mark it a
   `DRAFT` and state that it is `inert`.
   The draft is inert and is not the switch: never set or change `umbrella.manifest` in
   `harness.config.yaml`, and never write `umbrella.manifest.yaml`, so
   the draft's presence alone does not engage umbrella mode. Engagement is the config key
   pointing at an existing manifest — that is E28-F03's promotion, not yours.
   On a greenfield run, when `specs/architecture.md` names exactly one deployable
   (or none), write neither a `repo-topology ADR` nor an `umbrella.manifest.draft.yaml`;
   a consolidation amend to one deployable (or none) still appends the new
   `repo-topology ADR` and removes the derived draft, per the amend contract below.
   The Planner is the single writer of the draft manifest. `/sdd-drill` never creates or
   amends `umbrella.manifest.draft.yaml`; a topology change is a `/sdd-plan`
   amend that is **append-only** and reconciles the draft.

   An amendment is **append-only**: it appends a dated `## Repo topology` delta section
   to `specs/architecture.md` and a new `repo-topology ADR` above the max
   existing ADR number, instead of rewriting the original section. Every amend that
   changes the deployable set always appends that new `repo-topology ADR`, including a
   collapse or removal that leaves one deployable (or none). An amend's delta is a
   **complete replacement snapshot**: it names the **full** effective deployable set as it
   stands after the change, and earlier deltas are superseded, so the effective
   deployables are exactly those the latest delta names (the original architecture's set
   when no delta has been appended). A delta expresses add, remove and rename identically
   — by naming the resulting set: after an original `api` + `web` set, a delta naming
   `api` removes `web`, and a delta naming `frontend` alone renames. The trigger reads
   that **effective set**, not the original section alone: when the effective set is still
   more than one, the Planner reconciles the draft to exactly that set, removing the
   entries whose deployables are gone; when it falls to one deployable (or none), the
   Planner additionally removes the derived `umbrella.manifest.draft.yaml`, while
   the already-committed repo-topology ADRs are preserved (append-only, never deleted).

   That removal is the **one carve-out** from the amend's no-deletion rule: the derived
   `umbrella.manifest.draft.yaml` is a project-owned artifact, so a consolidation
   to one deployable (or none) may delete it, while every other committed artifact stays
   append-only and is never deleted.
8. **Seed** the roadmap (a greenfield run seeds the whole block; an amend appends above
   the current maximum and never re-seeds or rewrites an existing row): for each epic,
   write a `state/tasks.json` row with
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
   (`agents/doc-critic.md`) as a sub-agent with `target-type=plan-output`.
   On a greenfield run, pass every path just written
   (`specs/vision.md`, `specs/architecture.md`, each ADR, and every
   seeded `epic.md`) and apply any advisory findings inline.
   On an amend, the doc-critic reviews only the newly written material — the dated,
   append-only `## Repo topology` delta section appended to
   `specs/architecture.md`, the new `repo-topology ADR`, and the newly seeded
   `epic.md` files.
   An amend may apply a doc-critic fix within the appended section only — the dated
   topology delta, the new `repo-topology ADR` and the newly seeded `epic.md` — and makes
   no changes outside the appended section: the committed `specs/vision.md`,
   the rest of `specs/architecture.md`, and every existing ADR stay untouched,
   because the amend is append-only and must not rewrite the committed planning baseline.
   If the critic invocation errors or
   times out, proceed best-effort and append a note under `progress/<run>/`
   recording the skipped/failed review.
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
