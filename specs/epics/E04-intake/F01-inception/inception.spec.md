---
id: E04-F01
title: Inception role + /sdd-new intake
epic: E04-intake
status: done             # pending → spec-ready → in-progress → in-review → done
sdd: true                # false = quick task, skip full SDD
autonomous: false        # true = may bypass the human approval gate
depends_on: []
owner: araozmd
---

# Inception role + /sdd-new intake — Functional Spec

## Context
Nothing in the harness owns the step *before* `pending`. The Orchestrator loop
(`agents/orchestrator.md`) and the state machine (`docs/WORKFLOW.md`) both begin at
`pending`, presuming `state/tasks.json` is already populated. Today, getting a raw
idea into the TaskStore is a manual hand-edit: the human personally triages altitude
(epic vs. feature vs. task), allocates `E##-F##` ids, wires `depends_on`, sets the
`sdd`/`autonomous` flags, and writes enough intent for the Architect to spec from.
That step is unstaffed, fiddly, and error-prone.

This feature adds the missing front door: a portable **Inception** role
(`agents/inception.md`) plus a thin Claude slash wrapper (`.claude/commands/sdd-new.md`).
A human runs `/sdd-new "<idea>"`, answers a short adaptive Q&A (optionally choosing
among 1–3 text-only mockup options where the shape is forked), and ends with (a) a
valid, schema-passing `pending` entry in `state/tasks.json` and (b) an intent brief
at `progress/inbox/<feature-id>.md`. From there `/sdd-next` works unchanged — it
spawns the Architect, which specs from the brief, then the normal human gate applies.
Inception **seeds; it never specs** (that stays the Architect's job) and never moves a
feature past `pending`.

The user is the human seeding work — typically the repo owner with a half-formed idea
who is not yet sure whether it is a new epic, a new feature, or another task on
something already in flight.

## Business rules
- **Seeds, never specs.** Inception must never write any `.spec.md` / `.plan.md` /
  `.tasks.md` / `.tests.md` file, and must never write EARS or a technical plan. That
  is the Architect's exclusive job.
- **Never past `pending`.** Inception may only create entries at `status: pending`.
  It must never set `spec-ready`, `in-progress`, `in-review`, or `done`, and must
  never advance an existing entry's status.
- **Purely additive contract.** Inception must not change `store/tasks.schema.json`,
  must not introduce a new status value, and must not alter the Orchestrator or
  Architect role contracts. The only new structural artifact is the
  `progress/inbox/<feature-id>.md` brief file type.
- **One writer per file.** Handoff to the Architect is the brief in `progress/inbox/`,
  not a fifth spec file — matching the "hand off through files in `progress/`" rule.
- **Triage to exactly one altitude.** Every run resolves to exactly one of: a new task
  on an existing not-`done` feature / a new feature under an existing epic / a new
  epic (which creates `epic.md` + a first `F01`).
- **Text-only mockups.** Any options or mockups Inception presents are markdown/ASCII
  text only — no image generation (honors `AGENTS.md` rule 5; stays portable).
- **Interactivity lives in the wrapper.** The interactive Q&A is carried by
  `/sdd-new`; `agents/inception.md` is the portable, model-interchangeable role
  contract.
- **Id allocation is next-sequential.** New ids are the next sequential number within
  scope; gaps left by deleted ids are not reused.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

- **R1** — The harness shall provide a portable Inception role file at
  `agents/inception.md` that defines the intake contract (seed a `pending` TaskStore
  entry plus an intent brief) and is written for any AGENTS.md-compatible CLI, not
  Claude-specific.
- **R2** — The harness shall provide a Claude slash command at
  `.claude/commands/sdd-new.md` that acts as Inception, accepts a free-text idea as
  its argument, and points at `agents/inception.md` as the canonical contract.
- **R3** — When Inception finishes intake for an idea, the system shall write a valid
  `pending` feature entry into `state/tasks.json` carrying `id`, `title`, `status:
  "pending"`, `sdd`, `autonomous`, `depends_on`, and `spec_path`.
- **R4** — When Inception finishes intake for an idea, the system shall write an intent
  brief at `progress/inbox/<feature-id>.md` whose `<feature-id>` equals the `id` of the
  entry written to `state/tasks.json`.
- **R5** — The intent brief shall contain YAML frontmatter with `feature`,
  `seeded_by: inception`, and `date`, followed by sections capturing the problem/who,
  the success outcome, the scope/boundaries, any chosen options, the constraints, and
  the open questions for the Architect.
- **R6** — When Inception has written to `state/tasks.json`, the system shall
  re-validate the file against `store/tasks.schema.json` (e.g. via
  `python3 -c "import json; json.load(open('state/tasks.json'))"` plus a schema check)
  before reporting completion.
- **R7** — If the post-write validation of `state/tasks.json` fails, then the system
  shall report the failure and not report a successful seed (it must not leave an
  invalid TaskStore as a "done" result).
- **R8** — When Inception triages an idea, the system shall resolve it to exactly one
  altitude: a new task on an existing not-`done` feature, a new feature under an
  existing epic, or a new epic.
- **R9** — Where the triaged altitude is "new epic", the system shall create the epic
  entry in `state/tasks.json` and a `specs/epics/<epic-slug>/epic.md` file, and seed
  the epic's first feature `F01`.
- **R10** — When Inception allocates a new `epic` or `feature` id, the system shall use
  the next sequential number within scope (epics across the project; features within
  the chosen epic) and shall not reuse an id left vacant by a deletion.
- **R11** — The Inception role shall not create or modify any `.spec.md`, `.plan.md`,
  `.tasks.md`, or `.tests.md` file.
- **R12** — The Inception role shall only ever write feature/epic entries at
  `status: "pending"` and shall not set or advance any entry to `spec-ready`,
  `in-progress`, `in-review`, or `done`.
- **R13** — The Inception role shall not modify `store/tasks.schema.json`,
  `agents/orchestrator.md`, or `agents/architect.md`, and shall not introduce a new
  status value.
- **R14** — Where Inception offers design options or mockups during intake, the system
  shall present them as text (markdown/ASCII) only and shall present at most 3 options.
- **R15** — When the seed completes, the system shall report the new `<feature-id>`,
  the `state/tasks.json` entry, and the `progress/inbox/<feature-id>.md` path, and
  shall instruct the human that `/sdd-next` is the next step (Inception itself does not
  spawn the Architect).
- **R16** — The harness documentation shall describe the pre-`pending` intake step:
  the role list in `AGENTS.md` shall name Inception, and `docs/WORKFLOW.md` shall show
  the `/sdd-new` → `pending` step that precedes the existing state machine.

## Out of scope
- A non-interactive `--from-file` / batch-seed mode for `/sdd-new` — **deferred for
  v1**; `/sdd-new` is interactive-only. (See Open questions.)
- Image-based mockups or any image generation — text-only by rule.
- Writing any of the four spec files, EARS, or a technical plan (Architect's job).
- Advancing a feature past `pending`, spawning the Architect, or any change to the
  Orchestrator/Architect contracts or `tasks.schema.json`.
- Slash-command wrappers for non-Claude CLIs (Codex/Gemini/OpenCode) — the portable
  role file covers them; CLI-specific wrappers are not part of v1.

## Open questions
- Should `/sdd-new` later support a non-interactive `--from-file` mode to batch-seed
  many ideas at once? **Deferred for v1 (interactive-only).** Flagged so the spec
  leaves room for it without building it.
- Id allocation when ids are non-contiguous (a deleted epic/feature leaves a gap):
  next-sequential (chosen, R10) vs. fill-the-gap. Confirm next-sequential is the
  desired long-term policy before this ships.
