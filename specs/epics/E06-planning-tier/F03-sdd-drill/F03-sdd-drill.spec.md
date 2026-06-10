---
id: E06-F03
title: "/sdd-drill skill (decompose draft epic, ADR deltas, epic-level approval)"
epic: E06-planning-tier
status: spec-ready         # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false          # installed-body role + command + docs change; human reviews
depends_on: [E06-F01, E06-F02]
owner: araozmd
---

# /sdd-drill skill (decompose draft epic, ADR deltas, epic-level approval) — Functional Spec

## Context
F02 (`/sdd-plan`) now produces a roadmap of `draft` epics — each a one-paragraph brief
with `features: []`, inert behind F01's `next()` gate. But there is no way to **deepen**
one of those sketches into executable work: a `draft` epic can never be selected, and
nothing today decomposes it into features, records the design decisions that
decomposition forces, or moves it past `draft`. F02's `agents/planner.md` is explicit
that the Planner **never advances past `draft`** and names `/sdd-drill` (F03) as the only
step that flips `draft → planned` — so F03 is the closing half of the rolling-wave loop.

`/sdd-drill <epic-id>` is the **consumer** of one `draft` epic at a time. It reads the
target epic plus the durable design artifacts F02 produced (`specs/vision.md`,
`specs/architecture.md`, the ADRs), runs a short adaptive Q&A to settle the feature
breakdown, and then **writes** the decomposition: it seeds `pending` feature entries into
the epic (ids, one-line intents, `depends_on`), fills the epic's `epic.md` feature table,
writes a per-feature inbox brief under `progress/inbox/`, and appends any **ADR deltas**
this epic forces (F02's `specs/adr/NNNN` convention). It ends in **exactly one human
decision at the epic granularity**: *approve* (flip the epic `draft → planned` and stamp
`autonomous: true` on its features, so the existing loop runs end-to-end with no
per-feature gate) or *keep gated* (the epic still advances to `planned`, but features stay
`autonomous: false` and park at the normal per-feature spec-approval gate).

It reuses F01's `draft`/`planned` states and the existing `autonomous` flag — **no new
status, no schema change for approval**. It does **not** write the four feature spec files:
the existing **Architect** specs each feature just-in-time during the autonomous run, so
specs stay just-in-time and no second spec-writer is introduced. The change is purely
**additive**: `/sdd-new`, `/sdd-plan`, and `/sdd-next` are untouched, and a repo that
never runs `/sdd-drill` behaves exactly as today.

## Business rules
- **Consumer, never producer.** `/sdd-drill` consumes a `draft` epic that F02 already
  seeded. It never creates epics, never writes `specs/vision.md` or
  `specs/architecture.md`, and operates on exactly **one** epic per session.
- **Decompose, never spec.** `/sdd-drill` seeds `pending` feature **entries** (ids,
  one-line intents, `depends_on`) + per-feature inbox briefs + the epic's feature table.
  It must **NEVER** create or modify any `.spec.md`, `.plan.md`, `.tasks.md`, or
  `.tests.md` feature file, never write EARS or a technical plan, and never spawn the
  Architect — the existing Architect specs each feature just-in-time during the
  autonomous run.
- **The only path past `draft`.** F03 is the single mechanism that advances an epic out
  of `draft`. It must not contradict the Planner's "never past draft" invariant; on
  approval it flips the **epic** `draft → planned` (never any other epic, never a feature
  status).
- **Reuse F01 + the existing `autonomous` flag for approval.** No new status value, no
  new approval mechanism, no schema change for approval. The single human gate is
  expressed through the existing `autonomous: true` feature flag (the same flag that
  skips the per-feature spec-approval gate today). The `planned` epic state is F01's.
- **Re-validate before claiming success.** After every write (seeding, table fill,
  state flip + stamp), `/sdd-drill` re-validates `state/tasks.json` against
  `store/tasks.schema.json` via the zero-dependency path; it must never report a
  successful drill on a validation failure, and must never leave an invalid TaskStore
  behind as a success.
- **Portability pillar.** The skill's normative contract lives in a portable role file
  (`agents/driller.md`) + AGENTS.md, not solely in `.claude/` glue; it must run on any
  AGENTS.md-compatible CLI. The Claude `/sdd-drill` slash command is just the wrapper.
- **Backward compatible / additive ⇒ one MINOR `VERSION` bump**, recorded in
  `CHANGELOG.md` (installed body changes: `agents/`, `.claude/` glue, `docs/`).

## Decisions (D1..D7, resolving the intent brief's open questions)
- **D1 — new `agents/driller.md` role, sibling to Planner and Architect (not an extension
  of either).** Mirroring F02-D1's portability reasoning: the Planner produces a *block*
  of `draft` epics and stops at the sketch; the Architect writes the *four-file spec* for
  *one feature*. The Driller sits between them at its own altitude — decomposing *one
  draft epic* into a *list of feature entries + briefs* and driving the single epic-level
  approval — and must never spec. Folding decomposition into the Architect would overload
  the Architect's "one feature, four files, never code" guardrails and its grep-based test
  contract; folding it into the Planner would contradict the Planner's "never past draft"
  invariant (R15 there). A clean sibling keeps each role's guardrails crisp and the
  contract portable. `agents/planner.md` and `agents/architect.md` are therefore
  DO-NOT-TOUCH files for this feature.
- **D2 — non-`draft` / missing target: refuse hard by default; re-drill is an explicit
  amend opt-in (parallels F02-D2).** `<epic-id>` is required. If it is missing, does not
  resolve to an existing epic, or resolves to an epic whose status is not `draft`
  (`planned` / `in-progress` / `done` / legacy `pending`), the default run **STOPS** and
  reports why — it never silently drills the wrong epic or re-drills a live one. Re-running
  `/sdd-drill` on an already-`planned` epic is an explicit **amend** opt-in that
  **appends** new feature entries (ids strictly above the epic's current max `F##`,
  append-only — see D3) and **appends** new ADR deltas, without renumbering or deleting
  existing features or re-flipping epic state. This keeps the one-shot drill safe and
  gives a first-class "already drilled" answer instead of a destructive re-run.
- **D3 — the Driller allocates the epic's `F##` block and the intra-epic `depends_on`
  graph: next-sequential within the epic, append-only, no reuse.** Reading the epic's
  current `features`, the Driller allocates new feature ids strictly above the epic's max
  existing `F##` (`F01`, `F02`, … for a fresh epic; `max + 1` upward on amend) — never
  refilling a gap left by a removed feature. Each new feature carries
  `id: "<E##>-F<NN>"`, `title`, `status: "pending"`, `sdd: true` (default), `spec_path:
  "specs/epics/<id>-<slug>/F<NN>-<slug>/"`, and an intra-epic `depends_on` array
  referencing only sibling features of the same epic (or cross-epic ids that already
  exist). The id+slug directory matches the `spec_path`. Features are **appended** to the
  epic's `features` array; existing features are never reordered or renumbered.
- **D4 — "keep gated" advances the epic to `planned` with `autonomous: false` features
  (the least-surprising default).** Both branches advance the **epic** to `planned` —
  the epic *has been drilled*, so leaving it `draft` would falsely re-gate it behind the
  planning gate and force a re-drill. The branches differ only in the feature
  `autonomous` flag: *approve* stamps `autonomous: true` (the loop runs end-to-end, no
  per-feature gate); *keep gated* leaves features `autonomous: false` so each parks at the
  normal per-feature spec-approval gate (`require_spec_approval`). Keeping a drilled epic
  `draft` is explicitly rejected as surprising — `planned` + gated features is the
  faithful "drilled but I still want to review each spec" state.
- **D5 — ADR-delta boundary (one level below F02-D6).** F02 writes the *stable, upfront,
  whole-system* decisions. F03 writes the **per-epic ADR deltas** this epic's
  decomposition forces — decisions that constrain more than one *feature within this
  epic*, or refinements informed by what an earlier epic's implementation taught — using
  F02's exact convention (`specs/adr/NNNN-<title>.md`, 4-digit zero-padded, allocated
  strictly above the max existing ADR number, no reuse; one decision per ADR; referenced
  by `ADR-NNNN`). The Driller must **not** rewrite or renumber F02's existing ADRs, and
  must **not** author feature-level design that belongs in a feature's own four-file spec
  (the F04/Architect boundary). Decisions local to a single feature are deferred to that
  feature's spec.
- **D6 — stamping scope at approval is all-or-nothing across the epic's features.**
  Epic-level approval is exactly **one** human decision at the **epic** granularity (not
  per feature). On *approve*, the Driller stamps `autonomous: true` on **every** feature
  it seeded for that epic; on *keep gated*, **every** seeded feature stays `autonomous:
  false`. There is no per-feature subset approval in F03 — a human who wants finer control
  uses the *keep gated* branch and approves each feature at the existing per-feature gate
  during the run.
- **D7 — forward-compat hook for F04: per-feature inbox briefs record the ADR ids each
  feature touches (a note now, consumed later).** Each per-feature inbox brief written by
  the Driller records, under its constraints/decisions section, the `ADR-NNNN` ids
  (F02's upfront ADRs and/or this drill's deltas) that the feature is expected to honor.
  This is a forward-compatible note that costs nothing today and gives F04 (the Architect
  contract that makes specs *cite* ADRs) a ready hook; F03 does not itself make any spec
  cite an ADR (that is F04's job and out of scope here).

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

### The skill + portable role contract
- **R1** — The harness shall provide a portable Driller role file (`agents/driller.md`)
  that states it is the consumer that decomposes exactly **one** `draft` epic into a
  feature list, appends ADR deltas, and drives the single epic-level approval, and that
  it is written for any AGENTS.md-compatible CLI (portable, not Claude-specific).
- **R2** — The harness shall provide a `/sdd-drill` slash command
  (`.claude/commands/sdd-drill.md`) that acts as **Driller** by pointing at
  `agents/driller.md` as the durable contract and that reads the target `<epic-id>` from
  `$ARGUMENTS`.
- **R3** — `agents/driller.md` shall require a short, **adaptive** Q&A front-end that
  presents at most 3 **text-only** (markdown/ASCII) option mockups where the feature
  breakdown forks, and shall never generate images (honoring the AGENTS.md portability
  rule); the `/sdd-drill` command shall carry the same text-only, ≤3-options rule.

### Argument / precondition guards (D2)
- **R4** — `agents/driller.md` and the `/sdd-drill` command shall require a `<epic-id>`
  argument, and **if** `$ARGUMENTS` is empty **then** the run shall STOP and ask the
  human for the epic id rather than drilling an arbitrary epic.
- **R5** — If `<epic-id>` does not resolve to an existing epic in `state/tasks.json`, or
  resolves to an epic whose status is **not** `draft`, then a default `/sdd-drill` run
  shall STOP and report why (missing / not-`draft`), and shall not seed features, append
  ADRs, or change any status; an explicit **amend** opt-in on an already-`planned` epic
  shall append new feature entries (ids strictly above the epic's max `F##`) and new ADR
  deltas without renumbering or deleting existing features or re-flipping epic state (D2).

### Reading the draft epic + design artifacts as input
- **R6** — `agents/driller.md` shall state that, before decomposing, the Driller reads
  the target `draft` epic (its `epic.md` and `state/tasks.json` row) and the durable
  design artifacts F02 produced (`specs/vision.md`, `specs/architecture.md`, and the
  `specs/adr/NNNN-*.md` ADRs) as inputs to the feature breakdown.

### Feature decomposition (D3)
- **R7** — When `/sdd-drill` decomposes an epic, the Driller shall write each new feature
  into that epic's `features` array in `state/tasks.json` with `status: "pending"`,
  `sdd: true`, a one-line `title`, a `spec_path`, and an intra-epic `depends_on` array,
  allocating feature ids as a next-sequential block strictly above the epic's max
  existing `F##` (append-only, no id reuse) (D3).
- **R8** — When `/sdd-drill` decomposes an epic, the Driller shall fill that epic's
  `specs/epics/<id>-<slug>/epic.md` **feature table** with one row per seeded feature
  (id, title, status, sdd, depends_on) matching the `state/tasks.json` entries.
- **R9** — When `/sdd-drill` seeds a feature, the Driller shall write a per-feature inbox
  brief at `progress/inbox/<E##>-F<NN>.md` (from `specs/_templates/inbox-brief.md`) so the
  existing Architect can spec that feature just-in-time, and that brief shall record the
  `ADR-NNNN` ids the feature is expected to honor (D7).
- **R10** — After seeding, the Driller shall re-validate `state/tasks.json` against
  `store/tasks.schema.json` via the zero-dependency path, and **if** validation fails
  **then** the Driller shall report the failure and shall not claim a successful drill
  (it must not leave an invalid TaskStore behind as a success).

### ADR deltas (D5)
- **R11** — When `/sdd-drill` records a per-epic design decision the decomposition forces,
  the Driller shall append it as a one-decision ADR at `specs/adr/NNNN-<title>.md`
  (4-digit zero-padded `NNNN`), allocating `NNNN` strictly above the maximum existing ADR
  number (no reuse), and shall **not** rewrite or renumber F02's existing ADRs (D5).
- **R12** — `agents/driller.md` shall scope its ADR deltas to **per-epic** decisions
  (one level below F02's whole-system upfront ADRs) and shall state it never authors the
  feature-level design that belongs in a feature's own four-file spec (the Architect/F04
  boundary) (D5).

### Approve branch (D4, D6)
- **R13** — When the human **approves** the epic for autonomous execution, the Driller
  shall flip that **epic**'s status `draft → planned` and stamp `autonomous: true` on
  **every** feature it seeded for that epic (all-or-nothing), so the existing loop runs
  end-to-end with no per-feature gate (D4, D6).

### Keep-gated branch (D4, D6)
- **R14** — When the human chooses **keep gated**, the Driller shall flip that **epic**'s
  status `draft → planned` (the epic is drilled) while leaving **every** seeded feature
  `autonomous: false`, so each feature parks at the normal per-feature spec-approval gate;
  the Driller shall not leave a drilled epic in `draft` (D4, D6).

### The single epic-level human gate (reuse, no new mechanism)
- **R15** — `agents/driller.md` shall express the drill as ending in **exactly one**
  human decision at the **epic** granularity (approve vs keep gated), realized solely
  through F01's `planned` state and the existing `autonomous` feature flag — introducing
  **no new status value** and **no new approval mechanism**, and making **no schema
  change** for approval.

### Invariants
- **R16** — `agents/driller.md` shall state that F03 is the **only** path that advances an
  epic out of `draft` (consistent with `agents/planner.md`'s "never past draft"
  invariant), and that the Driller advances only the **epic** to `planned` (never any
  other epic, and never a feature's own status).
- **R17** — `agents/driller.md` shall state that the Driller **decomposes, never specs**:
  it must NEVER create or modify any `.spec.md`, `.plan.md`, `.tasks.md`, or `.tests.md`
  feature file, never write EARS or a technical plan, and never spawn the Architect — the
  existing Architect writes each feature's four-file spec just-in-time during the
  autonomous run.

### Backward compatibility / portability
- **R18** — The harness shall leave `/sdd-new`, `/sdd-plan`, `/sdd-next`,
  `.claude/commands/sdd-new.md`, `.claude/commands/sdd-plan.md`,
  `.claude/commands/sdd-next.md`, `agents/inception.md`, and `agents/planner.md`
  behaviorally unchanged; a repo that never runs `/sdd-drill` shall validate and behave
  exactly as today, and `./init.sh` shall exit 0 on the untouched repo.
- **R19** — The Driller's normative contract shall live in the portable role file
  (`agents/driller.md`), not solely in `.claude/` glue (the rule's presence in the
  portable file is the contract).

### Docs
- **R20** — `docs/WORKFLOW.md` shall document where `/sdd-drill` sits — the per-epic
  drill-down between `/sdd-plan` and `/sdd-next` that decomposes a `draft` epic into
  features + ADR deltas and ends in one epic-level approval (approve → `planned` +
  `autonomous: true`; keep gated → `planned`, features gated) — and shall state that it is
  the only step that flips an epic `draft → planned` and that it never writes feature
  specs.
- **R21** — `README.md` shall carry a one-line description of `/sdd-drill` (the per-epic
  drill-down skill) alongside the existing `/sdd-new` / `/sdd-plan` / `/sdd-next`
  mentions.

### Versioning
- **R22** — The repository shall record this change as one MINOR `VERSION` bump with a
  matching `CHANGELOG.md` entry (a heading equal to the `VERSION` file's content) that
  describes `/sdd-drill`, the feature decomposition + ADR deltas, and the epic-level
  approve / keep-gated branches.

## Out of scope
- F02 `/sdd-plan` — producing `draft` epics, the vision/architecture/ADR artifacts. F03
  **consumes** F02's draft epics; it never produces an epic and never writes
  `vision.md`/`architecture.md`.
- F04 — the Architect contract that makes `architecture.md`/ADRs a mandatory input and
  makes feature specs **cite** ADRs. F03 emits ADR deltas and records touched ADR ids in
  the briefs (D7), but does not make any spec cite an ADR.
- F05 `/sdd-fix` and F06 drift-check demotion.
- Writing the four-file feature specs themselves — the existing Architect specs each
  feature just-in-time during the autonomous run (F03 only seeds feature entries +
  briefs).
- Any change to F01's epic enum, the `next()` gate, feature-level status values, the
  `sdd`/`autonomous` flag semantics, or `store/tasks.schema.json`.
- Changing `/sdd-new`/Inception or `/sdd-plan`/Planner — both are untouched (D1, out of
  scope).

## Open questions
- None — the seven questions from the intent brief are resolved as D1–D7 above.

## Constraints carried into the test contract
- Tests must not freeze the exact `VERSION` value and must not diff DO-NOT-TOUCH files
  against `main` (see the permanent-suite anti-pattern note in the repo). The genuine
  permanent invariant is the **content** of the portable contract (role + command +
  docs), not a byte-freeze of any file.
- The verification path stays zero-dependency: POSIX sh + grep + python3 here-docs, with
  the `jsonschema`-absent fallback still validating a fixture store. Any fixture uses a
  **temp** store carrying the required root `project` field and a seeded `pending` feature
  in a `planned` epic; it never mutates the live `state/tasks.json`. Schema stays
  draft-07; `./init.sh` exits 0 afterward.
