---
id: E06-F01
title: "Epic lifecycle: draft/planned states + next() gating"
epic: E06-planning-tier
status: spec-ready       # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false        # installed-body schema + role-prose change; human reviews
depends_on: []
owner: araozmd
---

# Epic lifecycle: draft/planned states + next() gating — Functional Spec

## Context
The TaskStore's epic status enum (`pending | in-progress | done`) cannot distinguish
"barely an idea sketched during inception" from "drilled down, approved, ready to
execute". Without that distinction the planned `/sdd-plan` skill (E06-F02) cannot
safely seed a whole roadmap of sketch-level epics — the Orchestrator would treat
their features as actionable. This feature adds two epic-level statuses — `draft`
(inception sketch: title + business brief only) and `planned` (drilled down and
human-approved) — and one selection rule: `next()` never returns a feature
belonging to a `draft` epic. It is the state-machine foundation the rest of epic
E06 (F02–F06) builds on. The change is purely **additive**: existing consumer
`tasks.json` files contain no `draft`/`planned` epics and must validate and behave
exactly as today.

## Business rules
- **Epic lifecycle (canonical):** `draft → planned → in-progress → done`.
- **`pending` is a legacy alias of `planned`** at the epic level: gating-identical,
  kept indefinitely for backward compatibility (Decision D1 below). New-epic intake
  (`/sdd-new`) keeps seeding `pending` epics for now; switching intake to `draft`
  is decided when F02/F03 land.
- **Only `draft` gates.** Features of `pending`, `planned`, `in-progress`, and
  `done` epics are subject to exactly today's per-feature actionability rules; a
  `draft` epic's features are never selectable, no matter what the feature says
  (`autonomous: true` does not override the epic gate — that flag skips the
  *human approval* gate, not the *planning* gate).
- **Feature-level statuses are untouched.** No new feature or slice status values;
  the `sdd`/`autonomous` flags and slices/umbrella semantics are unchanged.
- **Portability pillar:** the gating rule is normative in the role files and store
  contract (`agents/orchestrator.md`, `store/local.md`) — portable across
  AGENTS.md-compatible CLIs — never only in `.claude/` glue.
- **Additive ⇒ one MINOR `VERSION` bump** (schema, agents, docs, templates are
  installed body), recorded in `CHANGELOG.md`.

## Decisions (resolving the intent brief's open questions)
- **D1 — epic-level `pending` is NOT deprecated.** It is documented as a legacy
  alias of `planned` (gating-equivalent), kept indefinitely. No warnings, no
  migration; removing it would be a MAJOR schema change and is explicitly not
  planned. Docs present `draft → planned → in-progress → done` as the canonical
  lifecycle and mention `pending` once as the legacy alias.
- **D2 — the draft-gate lives in prose AND gets a warn-only diagnostic.** The
  normative rule lives in `agents/orchestrator.md` + `store/local.md` (portable).
  Additionally, `init.sh` gains a **non-fatal** check: if a `draft` epic contains a
  feature whose status is not `pending`, it prints a warning and continues (exit 0).
  The JSON schema does **not** hard-enforce this invariant — a blocking failure
  would halt the whole loop over a hand-edit that the gate already neutralizes.
- **D3 — board mirror: docs note only.** The mirror projects **feature** statuses
  onto board columns; epic statuses never map to columns (the epic is a label
  field). `draft`/`planned` therefore need no provider work and no new
  `status_map` defaults — just a clarifying note in `store/board-mirror.md`.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

### Schema (additive, backward compatible)
- **R1** — The TaskStore schema (`store/tasks.schema.json`) shall accept exactly
  five epic `status` values: `draft`, `planned`, `pending`, `in-progress`, `done`
  (the enum gains `draft` and `planned`; nothing is removed).
- **R2** — If a **feature** (or slice) carries status `draft` or `planned`, then
  schema validation shall reject it (the feature and slice status enums are
  unchanged).
- **R3** — When a `tasks.json` containing no `draft`/`planned` epics (a
  pre-existing consumer file) is validated, validation shall pass unchanged — no
  migration, no new required fields.
- **R4** — The zero-dependency fallback validator embedded in `init.sh` shall
  accept the same epic status set as the schema (`draft`, `planned`, `pending`,
  `in-progress`, `done`), and `./init.sh` shall exit 0 on the untouched repo.

### `next()` gating
- **R5** — While an epic's status is `draft`, `next()` shall not return any feature
  of that epic, regardless of the feature's own `status`, `sdd`, `autonomous`, or
  `depends_on` values.
- **R6** — While an epic's status is `planned`, `next()` shall treat the epic's
  features exactly as features of a `pending` epic are treated today (the
  per-feature actionability semantics of `store/local.md` apply unchanged).
- **R7** — `store/local.md` shall document the epic-level gate in the `next()`
  contract: features of a `draft` epic are never actionable; epics in `pending`,
  `planned`, `in-progress`, or `done` impose no new gate.
- **R8** — `agents/orchestrator.md` shall instruct the Orchestrator to skip
  features of `draft` epics when selecting the next actionable task, with the rule
  expressed in the portable role file (not solely in `.claude/` glue).

### Lifecycle documentation
- **R9** — `docs/WORKFLOW.md` shall document the epic lifecycle
  `draft → planned → in-progress → done`, including that `pending` is a retained
  legacy alias of `planned` (gating-equivalent, kept for backward compatibility).
- **R10** — The epic template (`specs/_templates/epic.md`) status comment shall
  show the epic lifecycle including `draft` and `planned`, noting `pending` as the
  legacy alias.
- **R11** — `store/local.md` shall state that epic-level `pending` and `planned`
  are gating-equivalent (selection treats them identically).

### Warn-only invariant (D2)
- **R12** — If the validated TaskStore contains a `draft` epic with at least one
  feature whose status is not `pending`, then `init.sh` shall print a warning that
  names the epic (or feature) and shall still exit 0 (warn-only; schema validation
  shall not reject this state).

### Board mirror (D3)
- **R13** — `store/board-mirror.md` shall note that epic `draft`/`planned` statuses
  never map to board columns (the mirror projects feature statuses only), so no
  `status_map` change is needed for this feature.

### Versioning
- **R14** — The repository shall record this change as one MINOR `VERSION` bump
  with a matching `CHANGELOG.md` entry (a heading equal to the `VERSION` file's
  content) that describes the `draft`/`planned` epic states and the `next()` gate.

## Out of scope
- The `/sdd-plan` skill (F02), `/sdd-drill` (F03), the Architect
  `architecture.md` contract (F04), the `/sdd-fix` lane (F05), drift-check
  demotion (F06).
- Any change to feature-level statuses, the `autonomous`/`sdd` flags, or
  slices/umbrella semantics.
- Switching Inception/`/sdd-new` intake to seed `draft` epics (stays `pending`;
  revisit with F02/F03). `agents/inception.md` is untouched.
- Board-mirror provider work or `status_map` defaults (docs note only, per D3).
- Removing or warning on epic-level `pending` (per D1).
- The mechanism that flips an epic `draft → planned` and stamps
  `autonomous: true` on its features — that is F03's job; F01 only provides the
  states and the gate.

## Open questions
- None — the three questions from the intent brief are resolved as D1–D3 above.

## Constraints carried into the test contract
- Tests must not freeze the exact `VERSION` value and must not diff DO-NOT-TOUCH
  files against `main` (see the permanent-suite anti-pattern note in the repo).
- Schema stays JSON Schema draft-07; the zero-dependency validation path in
  `init.sh` keeps working without `jsonschema` installed.
