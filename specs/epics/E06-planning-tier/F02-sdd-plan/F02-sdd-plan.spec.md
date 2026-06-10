---
id: E06-F02
title: "/sdd-plan inception skill (vision + architecture + draft epics)"
epic: E06-planning-tier
status: spec-ready       # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false        # installed-body role + templates + docs change; human reviews
depends_on: [E06-F01]
owner: araozmd
---

# /sdd-plan inception skill (vision + architecture + draft epics) — Functional Spec

## Context
Today the only intake path is `/sdd-new`, which triages **one idea at a time** to one
altitude and, at the new-epic altitude, seeds a single `pending` epic plus its `F01`.
There is no way to capture the **whole-project vision** up front and sketch the full
roadmap cheaply, so architectural coherence emerges late — several epics in, the human
discovers refactors a whole-picture view would have prevented (the pain epic E06 exists
to kill). E06-F01 shipped the foundation: the `draft` epic state and the `next()` gate
that make a roadmap of sketch-level epics safe to seed (their features are never
selectable). This feature, `/sdd-plan`, is the **producer** that puts those `draft`
epics — and the durable design artifacts above them (`specs/vision.md`,
`specs/architecture.md` + ADRs) — on disk. It is a producer only: it seeds and writes
artifacts, never specs a feature, never drills an epic, and never moves anything past
`draft`. The change is purely **additive**: repos that never run `/sdd-plan` see no
behavior change, and `/sdd-new` + `/sdd-next` keep working exactly as today.

## Business rules
- **Producer, never spec.** `/sdd-plan` writes `specs/vision.md`,
  `specs/architecture.md`, the ADR file(s), and seeds `draft` epics (`state/tasks.json`
  rows with `features: []` + a per-epic `epic.md`). It must NEVER create or modify any
  `.spec.md`, `.plan.md`, `.tasks.md`, or `.tests.md` feature file, never spawn the
  Architect, and never write EARS or a technical plan. (Same guardrail as Inception.)
- **Never past `draft`.** Every epic it seeds is `status: "draft"`. It must never set or
  advance any epic or feature to `planned`, `in-progress`, `in-review`, or `done`, and
  must never stamp `autonomous: true`. Drilling a `draft` epic to `planned` is F03's
  job; F02 stops at the sketch.
- **Reuse F01's `draft` state and gate.** No new status value, no new approval
  mechanism. Seeded epics are inert because the F01 `next()` gate already prevents the
  Orchestrator from selecting their features.
- **Empty-features draft epics are the canonical shape.** Each seeded epic carries
  `features: []` — schema-valid today (`features` is required but has no `minItems`).
  No placeholder `F01` is created (this is the deliberate difference from `/sdd-new`'s
  new-epic altitude). F03 later populates `features`.
- **One decision per ADR.** `architecture.md` is the index/narrative; each ADR is an
  atomic, citable unit that a later feature's spec (F04) can point at. `/sdd-plan`
  writes the upfront, stable decisions only — per-epic ADR *deltas* are F03's job.
- **Re-validate before claiming success.** After seeding, `/sdd-plan` re-validates
  `state/tasks.json` against `store/tasks.schema.json` via the zero-dependency path; it
  must never report a successful plan on a validation failure.
- **Portability pillar.** The skill's normative contract lives in a portable role file
  (`agents/planner.md`) + AGENTS.md, not solely in `.claude/` glue; it must run on any
  AGENTS.md-compatible CLI. The Claude `/sdd-plan` slash command is just the wrapper.
- **Backward compatible / additive ⇒ one MINOR `VERSION` bump**, recorded in
  `CHANGELOG.md` (installed body changes: `agents/`, `specs/_templates/`, `docs/`,
  `.claude/` glue).

## Decisions (resolving the intent brief's open questions)
- **D1 — new `agents/planner.md` role, sibling to Inception (not an extension of
  `agents/inception.md`).** `/sdd-new`/Inception triages **one idea to one altitude**
  and seeds a single `pending` feature + brief; `/sdd-plan`/Planner is a different
  altitude of intake — whole-roadmap, producing durable architecture artifacts and a
  *block* of `draft` epics. Folding both into one role would overload Inception's
  "exactly one altitude" triage and its "never past `pending`" / "no epic.md beyond the
  new-epic path" guardrails. A clean sibling keeps each role's guardrails crisp and the
  grep-based test contract unambiguous. `agents/inception.md` is therefore a
  DO-NOT-TOUCH file for this feature.
- **D2 — re-run on an existing plan: refuse by default, amend only on an explicit
  opt-in flag; never silently overwrite.** If `specs/vision.md` or
  `specs/architecture.md` already exists, the default run STOPS and reports that the
  project already has a plan, pointing the human at `/sdd-drill` (F03) to deepen
  existing epics or at an explicit amend mode. An explicit re-plan/amend opt-in
  **appends** new ADRs and **appends** new `draft` epics (allocating ids strictly above
  the current maximum — see D5) without rewriting or renumbering existing artifacts or
  existing epics. `/sdd-plan` never deletes, renumbers, or version-forks committed
  artifacts. This keeps the greenfield path one-shot-safe while giving a first-class
  "already has a plan" answer instead of a destructive clobber.
- **D3 — `vision.md` complements `product.md`/`glossary.md`; it does not supersede or
  absorb them.** `product.md` stays Layer-0 constitution (audience, domain model,
  principles); `glossary.md` stays the term index. `vision.md` is the whole-project
  north star a `/sdd-plan` session produces (problem, users, outcomes, non-goals) and
  is the document the roadmap of `draft` epics rolls up to. `vision.md` references
  `product.md`/`glossary.md` rather than duplicating them; no existing file is rewritten
  or removed by F02.
- **D4 — ADRs live at `specs/adr/NNNN-title.md`, zero-padded to 4 digits, referenced
  from `architecture.md` by id.** Sitting under `specs/` (not `docs/`) keeps every
  design artifact in the spec tree the agents already read, beside `product.md` and the
  epics. Numbering is `0001`, `0002`, … allocated strictly above the current maximum
  existing ADR number (no reuse, mirroring the id policy). `architecture.md` cites each
  ADR by its `ADR-NNNN` id so F04 can make feature specs point at the same ids.
- **D5 — draft-epic id/slug allocation: next-sequential block, append-only, no reuse.**
  `/sdd-plan` reads `state/tasks.json`, finds the max existing `E##`, and allocates the
  whole new block strictly above it (`max + 1`, `max + 2`, …) — never refilling a gap
  left by a deleted epic. Slugs are derived from each epic title (`E07-<slug>`), the
  `spec_path`/`epic.md` directory matching the id+slug. New epics are **appended** to
  the existing epic list; existing epics are never reordered or renumbered.
- **D6 — F02-vs-F03 architecture-depth boundary: F02 writes only the *stable, upfront,
  whole-system* decisions; F03 owns per-epic ADR *deltas*.** "Enough" architecture for
  a sketch session = the cross-cutting decisions that constrain more than one epic (the
  system shape, the seams, the stable technology/structure choices) — captured as
  `architecture.md` + a small set of ADRs. Decisions local to a single epic, and
  refinements informed by what an earlier epic's implementation taught, are deferred to
  F03's drill-down (per-epic ADR deltas). F02 must not author per-epic feature-level
  design.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

### The skill + portable role contract
- **R1** — The harness shall provide a portable Planner role file
  (`agents/planner.md`) that states it is the producer of `specs/vision.md`,
  `specs/architecture.md` + ADRs, and a block of `draft` epics, and that it is written
  for any AGENTS.md-compatible CLI (portable, not Claude-specific).
- **R2** — The harness shall provide a `/sdd-plan` slash command
  (`.claude/commands/sdd-plan.md`) that acts as **Planner** by pointing at
  `agents/planner.md` as the durable contract and that reads the free-text idea from
  `$ARGUMENTS`.
- **R3** — `agents/planner.md` shall require a short, **adaptive** Q&A front-end that
  presents at most 3 **text-only** (markdown/ASCII) option mockups where the roadmap
  shape forks, and shall never generate images (honoring the AGENTS.md portability
  rule); the `/sdd-plan` command shall carry the same text-only, ≤3-options rule.

### Artifact templates
- **R4** — The harness shall add a vision template (`specs/_templates/vision.md`) whose
  shape covers problem, users, outcomes, and non-goals.
- **R5** — The harness shall add an architecture template
  (`specs/_templates/architecture.md`) that covers the system shape, the stable upfront
  decisions, and an index that references its ADRs by id.
- **R6** — The harness shall add an ADR template (`specs/_templates/adr.md`) shaped for
  **one decision** (e.g. context / decision / consequences) so each ADR is an atomic,
  citable unit.

### Vision / architecture / ADR production
- **R7** — When `/sdd-plan` completes a greenfield session, the Planner shall write
  `specs/vision.md` (north star: problem, users, outcomes, non-goals) from the vision
  template.
- **R8** — When `/sdd-plan` completes a greenfield session, the Planner shall write
  `specs/architecture.md` (system shape + stable upfront decisions) from the
  architecture template, and it shall reference each ADR it produced by that ADR's id.
- **R9** — When `/sdd-plan` records a design decision, the Planner shall write it as a
  one-decision ADR at `specs/adr/NNNN-<title>.md` (4-digit zero-padded `NNNN`),
  allocating `NNNN` strictly above the maximum existing ADR number (no reuse) (D4).
- **R10** — `agents/planner.md` shall scope `architecture.md`/ADR depth to the stable,
  whole-system upfront decisions only and shall defer per-epic ADR *deltas* to F03
  (`/sdd-drill`), and shall state it never authors feature-level design (D6).

### Draft-epic seeding
- **R11** — When `/sdd-plan` seeds the roadmap, the Planner shall write each new epic
  into `state/tasks.json` with `status: "draft"` and `features: []`, allocating epic
  ids as a next-sequential block strictly above the maximum existing `E##` (append-only,
  no id reuse) (D5).
- **R12** — When `/sdd-plan` seeds an epic, the Planner shall create a matching
  `specs/epics/<id>-<slug>/epic.md` that is **title + a one-paragraph business brief
  only** — no feature specs, no `F01`, no EARS, no plan.
- **R13** — After seeding, the Planner shall re-validate `state/tasks.json` against
  `store/tasks.schema.json` via the zero-dependency path, and **if** validation fails
  **then** the Planner shall report the failure and shall not claim a successful plan
  (it must not leave an invalid TaskStore behind as a success).

### The producer invariant (seeds-never-specs / never past draft)
- **R14** — `agents/planner.md` shall state that the Planner must NEVER create or
  modify any `.spec.md`, `.plan.md`, `.tasks.md`, or `.tests.md` feature file, never
  write EARS or a technical plan, and never spawn the Architect (seeds/produces, never
  specs).
- **R15** — `agents/planner.md` shall state that every epic it seeds is `status:
  "draft"` and that it must never advance any epic or feature to `planned`,
  `in-progress`, `in-review`, or `done`, nor stamp `autonomous: true` (never past
  `draft`); it shall name F03 (`/sdd-drill`) as the step that flips `draft → planned`.
- **R16** — `agents/planner.md` shall reuse F01's `draft` state and gate — it shall
  introduce no new status value and no new approval mechanism, and shall note that
  seeded epics are inert because the `next()` draft gate already prevents selection of
  their features.

### Re-run behavior (D2)
- **R17** — If `specs/vision.md` or `specs/architecture.md` already exists, then a
  default `/sdd-plan` run shall STOP and report that the project already has a plan
  (pointing the human at `/sdd-drill` or an explicit amend mode) rather than silently
  overwriting; an explicit amend/re-plan opt-in shall append new ADRs and new `draft`
  epics (ids above the current maximum) without rewriting or renumbering existing
  artifacts or epics.

### Relationship to existing constitution (D3)
- **R18** — `agents/planner.md` and the vision template shall state that `vision.md`
  **complements** (does not supersede or absorb) the existing `specs/product.md` and
  `specs/glossary.md`, and the Planner shall not rewrite or delete `product.md` or
  `glossary.md`.

### Backward compatibility / portability
- **R19** — The harness shall leave `/sdd-new`, `/sdd-next`,
  `.claude/commands/sdd-new.md`, `.claude/commands/sdd-next.md`, and
  `agents/inception.md` behaviorally unchanged; a repo that never runs `/sdd-plan` (no
  `specs/vision.md`/`architecture.md`, no `draft` epics) shall validate and behave
  exactly as today, and `./init.sh` shall exit 0 on the untouched repo.
- **R20** — The Planner's normative contract shall live in the portable role file
  (`agents/planner.md`), not solely in `.claude/` glue (the rule's presence in the
  portable file is the contract).

### Docs
- **R21** — `docs/WORKFLOW.md` shall document where `/sdd-plan` sits — a whole-project
  inception step that produces `vision.md`, `architecture.md` + ADRs, and `draft` epics,
  upstream of the per-epic `/sdd-drill` (F03) and the `/sdd-next` loop — and shall state
  that it is a producer that never writes feature specs and never advances an epic past
  `draft`.
- **R22** — `README.md` shall carry a one-line description of `/sdd-plan` (the
  whole-project inception skill) alongside the existing `/sdd-new` / `/sdd-next`
  mentions.

### Versioning
- **R23** — The repository shall record this change as one MINOR `VERSION` bump with a
  matching `CHANGELOG.md` entry (a heading equal to the `VERSION` file's content) that
  describes `/sdd-plan`, the vision/architecture/ADR artifacts, and draft-epic seeding.

## Out of scope
- F03 `/sdd-drill` — decomposing a `draft` epic into features, ADR *deltas*, and the
  approval that flips it `draft → planned` + stamps `autonomous: true`. F02 only
  **produces** draft epics; it never drills, never writes feature specs, never moves an
  epic past `draft`.
- F04 — the Architect contract that makes `architecture.md` a mandatory input and makes
  feature specs cite ADRs. F02 produces the artifacts; F04 makes downstream specs
  consume them.
- F05 `/sdd-fix` and F06 drift-check.
- Any change to F01's schema enums, `next()` gating, feature-level statuses, or the
  `autonomous`/`sdd` flags.
- Switching `/sdd-new`/Inception intake to seed `draft` epics — Inception is untouched
  (D1, out of scope).
- Executing or selecting any seeded work (the F01 `draft` gate already prevents it).

## Open questions
- None — the six questions from the intent brief are resolved as D1–D6 above.

## Constraints carried into the test contract
- Tests must not freeze the exact `VERSION` value and must not diff DO-NOT-TOUCH files
  against `main` (see the permanent-suite anti-pattern note in the repo). The genuine
  permanent invariant is the **content** of the portable contract (role + command +
  templates + docs), not a byte-freeze of any file.
- The verification path stays zero-dependency: POSIX sh + grep + python3 here-docs, with
  the `jsonschema`-absent fallback still validating a seeded store. Schema stays
  draft-07; `./init.sh` exits 0 afterward.
