---
id: E06-F06
title: "Drift check on epic rollup (Scout re-validates remaining draft/planned epics)"
epic: E06-planning-tier
status: in-progress         # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false           # installed-body role + docs change; human reviews
depends_on: [E06-F03]
owner: araozmd
---

# Drift check on epic rollup (Scout re-validates remaining draft/planned epics) — Functional Spec

## Context
The planning tier (F01–F05) lets a maintainer sketch a whole roadmap of `draft` epics
(`/sdd-plan`), drill them one at a time into executable features (`/sdd-drill`), and have
each spec cite the architecture it touches (F04). But rolling-wave planning has a failure
mode it does not yet guard: **a plan made early goes stale as you learn.** When epic *N*
finishes, what its implementation taught — new ADRs (F02/F03), architecture deltas, a
removed or renamed thing — can invalidate the one-paragraph briefs behind the epics
*N+1…M* that were sketched (or even drilled and approved) **before** that learning
existed. Today nothing re-checks them: a stale `planned` epic would execute on out-of-date
assumptions, which is exactly the *"we lacked the whole picture"* refactor epic E06 set out
to kill, one level up. The parent epic's last success criterion names this gap directly:
*"Stale plans are detected: when an epic completes, remaining draft/planned epics are
re-checked against what was learned, and stale ones demote to `draft`."*

F06 closes the loop. When an epic **rolls up to `done`** (all its features are `done`), the
**Orchestrator** derives+persists the epic's `done` status, then triggers a **drift check**:
it spawns the read-only **Scout** to re-validate the remaining `draft`/`planned`/`pending`
epics against what the just-completed epic produced. The Scout writes a structured findings
file to `progress/` — per remaining epic, **still-valid** or **stale + the concrete reason**
— and makes **no** state change (its read-only contract is preserved). The Orchestrator (the
owner of `set_status`) then **demotes** any `planned`/`pending` epic the Scout judged stale
back to `draft`, re-validating `state/tasks.json` after each write. Demotion only ever moves
an epic **backward** (toward more gating); re-drilling a demoted epic back to `planned` stays
a manual `/sdd-drill` step (F03). When nothing applies — no remaining planning-state epics, or
no architecture to re-validate against — the check runs, emits a clear "nothing to
re-validate" note, and changes nothing.

The change is purely **additive**: it adds an epic-rollup→drift-check step to the
Orchestrator, a drift-check mode to the Scout, two doc edits, and one test suite. There is
**no new status value** and **no `store/tasks.schema.json` change** — demotion reuses F01's
existing `draft` state. A repo with no planning tier (no `draft`/`planned` epics) gets a
no-op drift check; existing single-feature / single-epic flows are unchanged.

## Business rules
- **Epic-done is the trigger, and F06 formalizes it.** Epic-level `done` is **not**
  derived automatically today — `store/local.md`'s rollup rule (~lines 56–70) and the
  Orchestrator's rollup section (~lines 205–218) formalize only the **sliced-feature**
  `done` rollup; nothing rolls an **epic** up to `done` when its features finish. Since the
  epic-done rollup is F06's trigger, F06 **formalizes it additively**: when every feature of
  an epic is `done`, the Orchestrator derives and persists the epic's `done` status (then
  re-validates), exactly mirroring the "derive, then persist" discipline of the existing
  feature rollup (D4).
- **Drift check fires only on an epic completing.** The drift check runs **only** when an
  epic rolls up `… → done`. It does not run on every loop iteration, on a feature `done`
  that does not complete its epic, or on any other status transition.
- **Scout flags, Orchestrator acts — the read-only contract is preserved.** The Scout does
  read-only reconnaissance and writes **only** to `progress/`; F06 must NOT give the Scout
  write authority over `state/tasks.json`. The Scout produces a structured verdict per
  remaining epic; the **Orchestrator** (owner of `set_status`) applies any demotion (D6).
- **Demotion only moves an epic BACKWARD.** The one automatic epic-status move F06
  introduces is `planned → draft` (and the gating-equivalent `pending → draft`). It is the
  **conservative** direction — it only ever *adds* a gate (the demoted epic's features become
  non-selectable behind F01's `next()` gate until re-drilled). F06 never advances an epic
  forward and never demotes `in-progress` or `done` epics (D1).
- **Re-drill stays a manual human step.** Getting a demoted epic back to `planned` is a
  human-run `/sdd-drill <epic>` (F03's job) — F06 only *detects and demotes*. It never
  re-decomposes the epic, never re-flips it forward, and never edits its feature specs (D1).
- **Concrete, testable staleness signal — no over-claimed AI judgement.** "Stale" is judged
  by **concrete, enumerable** signals the Scout can point at, not an open-ended semantic
  verdict: (a) a new ADR whose decision **contradicts** the epic's brief; (b) the brief
  **references a thing the completed epic removed or renamed**; (c) an explicit
  **`supersedes E0X`** (or "obsoletes E0X") marker in a new ADR / the completed epic's
  artifacts. Each finding names which signal fired and which artifact it points at (D2).
- **Flag, never rewrite.** F06 **flags**; it does not rewrite content. It may append a
  single flag line — `demoted on drift: <reason>` — to a demoted epic's `epic.md`, but it
  never rewrites the brief, the feature table, or any feature spec (D7).
- **Graceful / no-op when nothing applies.** A project with **no** remaining
  `draft`/`planned`/`pending` epics, or with **no** architecture/ADRs to re-validate
  against, sees the check run, emit a clear "nothing to re-validate" note, and change
  nothing — no failure, no noise (D5).
- **Backward compatible / additive ⇒ one MINOR `VERSION` bump.** No new status, no schema
  change; existing feature-level rollup is unchanged; single-epic / no-planning repos behave
  exactly as today; `./init.sh` stays green. Recorded in `CHANGELOG.md`.
- **Portability pillar.** The rollup + drift-check contract lives in the portable role files
  (`agents/orchestrator.md`, `agents/scout.md`) + the store contract (`store/local.md`) +
  docs — not in `.claude/` glue — so it holds on any AGENTS.md-compatible CLI.

## Architecture alignment
> This repository (the harness source) has **no** `specs/architecture.md` and **no**
> `specs/adr/` set — it has never run `/sdd-plan` on itself. Per the Architect contract's
> graceful-degradation rule (F04 / `agents/architect.md`), the architecture artifacts are
> **absent**, so the citation section is **not required** and this absence is recorded
> deliberately (not a silent omission). No ADRs are cited because none exist to cite. F06 is
> specced from the inbox brief + the role/store/doc contracts alone.

ADRs touched: none — the harness source carries no `specs/architecture.md`/`specs/adr/*`, so
there is no recorded decision to cite (graceful degradation, F04).

## Decisions (D1..D7, resolving the intent brief's seven open questions)
- **D1 — Auto-demote (report it), because the demotion only ever ADDS a gate — the
  least-surprising default.** *The brief's first open question.* A stale `planned`/`pending`
  epic is demoted to `draft` **automatically** by the Orchestrator and **reported**, rather
  than merely flagged for a human to confirm. This is the conservative direction of travel:
  demotion's only effect is to make the epic's features **non-selectable** behind F01's
  `next()` gate (it removes nothing, undoes no work, deletes nothing) and the only way back
  to `planned` is a deliberate human `/sdd-drill`. Auto-demote therefore cannot surprise a
  human into *losing* anything — the worst case is an extra re-drill of an epic that was, on
  reflection, still fine. Leaving a *known-stale* epic `planned` (selectable, ungated) is the
  more surprising and more dangerous default: it would let the autonomous loop execute on
  assumptions the harness already knows are wrong. So F06 demotes automatically, in the one
  and only backward direction (D1's invariant), and reports every demotion with its reason +
  the re-drill pointer (D7). Forward moves and any *content* change stay human/`/sdd-drill`
  gated.
- **D2 — Concrete staleness signals, enumerated; no open-ended semantic verdict.** *The
  brief's second open question.* The Scout judges an epic **stale** when **at least one** of
  these **concrete, pointable** signals holds between the just-completed epic's artifacts
  (its new/changed `specs/adr/NNNN-*.md`, its `epic.md`, what its features changed) and a
  remaining epic's one-paragraph brief: **(S1) Contradiction** — a new ADR's decision
  directly contradicts an assumption stated in the remaining epic's brief; **(S2)
  Removed/renamed reference** — the brief references a component, path, command, or concept
  the completed epic **removed or renamed**; **(S3) Explicit supersede** — a new ADR or the
  completed epic's artifacts carry an explicit **`supersedes E0X`** / **`obsoletes E0X`**
  marker naming the remaining epic. Each finding **names the signal (S1/S2/S3) and the
  artifact it points at**, so "stale" is always traceable to a concrete cause, never a bare
  opinion. When none of S1–S3 fires, the epic is **still-valid** (the default — F06 does not
  demote on a hunch). This keeps the verdict testable (the findings shape is checkable) and
  avoids over-claiming semantic AI judgement.
- **D3 — Legacy `pending` epics are treated like `planned` (considered for demotion).** *The
  brief's third open question.* The epic-level `pending` value is the **gating-equivalent
  legacy alias** of `planned` (F01 / `store/local.md`): selection treats them identically, so
  a `pending` epic's features are just as selectable-once-deps-met as a `planned` epic's. A
  stale `pending` epic is therefore exactly as dangerous as a stale `planned` one, and
  leaving it out would be a silent hole. So the drift check **considers `pending` epics too**
  and demotes a stale one `pending → draft` — the same single backward move. `draft` epics
  are already at the lowest planning state: a stale `draft` epic **stays `draft`** but is
  **flagged** in the findings so the next `/sdd-drill` starts from the correction (no status
  change for an already-`draft` epic). `in-progress` and `done` epics are **never** demoted
  (the check concerns *future* planned work only — out of scope, per the brief).
- **D4 — Formalize the epic-done rollup additively here (it is F06's trigger).** *The brief's
  fourth open question, resolved from the codebase.* Inspection of `agents/orchestrator.md`
  (rollup section ~205–218) and `store/local.md` (rollup rule ~56–70) shows the existing
  rollup formalizes only the **sliced-feature** `done` derivation; **no rule rolls an epic up
  to `done`** when all its features finish — the epic enum carries `done` (F01) but nothing
  *derives* it. Since the epic-done rollup is F06's trigger, F06 **adds** it, mirroring the
  feature rollup's "derive, then persist" discipline: **when every feature of an epic is
  `done`, the Orchestrator derives the epic's `done` status, writes it (`set_status` on the
  epic), and re-validates `state/tasks.json`.** This is additive and conservative — it only
  fires when **all** features are `done`, so a single-epic project reaching `done` is
  unaffected in behavior beyond gaining the (correct) `done` epic status. The drift check is
  the immediate next step after this rollup persists.
- **D5 — No-op path emits an explicit "nothing to re-validate" note.** *The brief's fifth
  open question.* When the drift check runs but finds **nothing to do** — there are **no**
  remaining `draft`/`planned`/`pending` epics (legacy single-epic repo, or every remaining
  epic already `done`), or there is **no** `specs/architecture.md`/ADR set to re-validate
  against — the check **does not fail and does not stay silent**: the Scout (or the
  Orchestrator, when the Scout is not even spawned because there is nothing to check) writes a
  short findings note stating **"nothing to re-validate"** with the reason (no remaining
  planning-state epics / no architecture), and **no status changes**. Silence is explicitly
  rejected — the human/log must be able to tell "ran and found nothing" from "never ran".
- **D6 — Audit trail: the `progress/` findings file is the primary record; a best-effort
  `phase: scout` telemetry record is additive on top.** *The brief's sixth open question.*
  The **required, durable** audit trail is the Scout's structured **findings file** under
  `progress/` (`progress/<run>/scout-drift-<completed-epic>.md`) — it lists every remaining
  epic with its verdict (still-valid / stale + signal + reason) and the demotions the
  Orchestrator then applied. **On top of that**, because the Orchestrator already wraps every
  Scout delegation in a telemetry `phase` span (`agents/orchestrator.md` Telemetry section,
  `phase ∈ {…,scout,…}`), the drift-check Scout run is recorded as a normal **`phase: scout`**
  telemetry record — **best-effort, never blocking** (a telemetry failure never blocks the
  check or a demotion). F06 introduces **no new telemetry record type and no schema-version
  bump**: it reuses the existing `phase: scout` shape, so the rollup/session report can
  already surface that a Scout drift-check ran. The findings file remains the source of truth
  for *what* was re-validated and demoted; telemetry only times *that it ran*.
- **D7 — Re-drill pointer in the report + an optional flag-only `epic.md` note (never a
  content rewrite).** *The brief's seventh open question.* When the Orchestrator demotes an
  epic, the report (and the findings file) **tells the human to run `/sdd-drill <epic>`** to
  re-validate and bring it back to `planned`. Additionally, the Orchestrator **may append a
  single flag line** — `demoted on drift: <reason>` — to the demoted epic's
  `specs/epics/<id>-<slug>/epic.md`. This is a **flag only**: it appends one line recording
  *why* the epic was demoted; it **never** rewrites the brief, the feature table, any feature
  spec, or any other content. The flag is a breadcrumb for the next `/sdd-drill`; the
  correction itself is the human's job at re-drill time (D1).

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

### Epic-done rollup formalization (the trigger) — D4
- **R1** — `store/local.md` shall formalize, additively, that **when every feature of an
  epic is `done`, the epic's `done` status is derived and persisted** (mirroring the existing
  "derive, then persist" feature-rollup discipline) and re-validated against
  `store/tasks.schema.json`, introducing **no new status value** and **no schema change**.
- **R2** — `agents/orchestrator.md` shall state that, **when** a feature transition makes
  **all** of an epic's features `done`, the Orchestrator (the owner of `set_status`) shall
  derive+persist that epic's `done` status, re-validate `state/tasks.json`, and **then**
  trigger the drift check **before** selecting the next task.

### The epic-rollup → drift-check trigger — D6
- **R3** — `agents/orchestrator.md` shall state that the drift check fires **only** when an
  epic rolls up to `done` (not on every loop iteration, nor on a feature `done` that does not
  complete its epic), and that it spawns the **read-only Scout** in a **drift-check mode** to
  re-validate the remaining `draft`/`planned`/`pending` epics against the just-completed
  epic's produced artifacts (new/changed ADRs + architecture deltas + what its features
  changed).

### The Scout drift-check mode + findings-file shape (read-only preserved) — D2, D6
- **R4** — `agents/scout.md` shall describe a **drift-check mode**: given the just-completed
  epic, the remaining `draft`/`planned`/`pending` epics, and `specs/architecture.md` /
  `specs/adr/*`, the Scout shall produce a structured findings file at
  `progress/<run>/scout-drift-<completed-epic>.md` with, **per remaining epic**, a verdict of
  **still-valid** or **stale**, and for a stale verdict the **concrete signal** that fired
  and the **artifact it points at** (the reason).
- **R5** — `agents/scout.md` shall define the concrete staleness signals the drift check uses
  — **(S1)** a new ADR's decision **contradicts** the epic's brief, **(S2)** the brief
  **references a removed/renamed** thing, **(S3)** an explicit **`supersedes E0X`** /
  `obsoletes E0X` marker — and shall state that an epic is judged **stale only when at least
  one** of these fires (otherwise **still-valid**), so the verdict is concrete and traceable
  rather than an open-ended semantic judgement.
- **R6** — `agents/scout.md` shall preserve the Scout's **read-only** contract in
  drift-check mode: the Scout **writes only to `progress/`**, makes **no** state change, and
  **never** writes `state/tasks.json` (it flags; the Orchestrator acts).

### Orchestrator applies the demotion (Scout flags / Orchestrator acts) — D1, D3, D6
- **R7** — When the Scout's findings judge a `planned` (or legacy `pending`) epic **stale**,
  the Orchestrator shall demote that epic to **`draft`** via `set_status` and **re-validate**
  `state/tasks.json` against `store/tasks.schema.json` after the write, so the demoted epic's
  features become non-selectable behind F01's `next()` gate (D1).
- **R8** — `agents/orchestrator.md` shall state that the **Scout never writes
  `state/tasks.json`**: it produces the findings file and the **Orchestrator alone** (the
  owner of `set_status`) applies the demotion based on those findings (the Scout-flags /
  Orchestrator-acts separation).
- **R9** — `agents/orchestrator.md` and `store/local.md` shall state that the drift check
  considers **`planned`, `pending`, and `draft`** epics: a stale `planned`/`pending` epic is
  demoted to `draft`; a stale `draft` epic **stays `draft`** (already the lowest planning
  state) but is **flagged** in the findings; and **`in-progress` / `done` epics are never
  demoted** (D3).

### The demotion-only-moves-backward invariant; re-drill stays manual — D1, D7
- **R10** — `agents/orchestrator.md` shall state the invariant that drift-driven demotion
  **only ever moves an epic backward** (`planned`/`pending` → `draft`) — it **never** advances
  an epic forward and **never** demotes an `in-progress` or `done` epic — and that
  re-drilling a demoted epic back to `planned` remains a **manual** `/sdd-drill` step (F03),
  not an automatic F06 move.
- **R11** — `agents/orchestrator.md` shall state that, on demoting an epic, the Orchestrator
  **reports the re-drill pointer** (`run /sdd-drill <epic>` to re-validate and restore it),
  and **may append a single flag line** `demoted on drift: <reason>` to the demoted epic's
  `epic.md` as a **flag only** — never rewriting the brief, the feature table, or any feature
  spec (D7).

### The no-op / graceful path — D5
- **R12** — If there are **no** remaining `draft`/`planned`/`pending` epics (legacy /
  single-epic repo, or every remaining epic already `done`), then the drift check shall be a
  **no-op** that emits a clear **"nothing to re-validate"** note (with the reason) and changes
  **no** status — never silence, never failure (D5).
- **R13** — If there is **no** `specs/architecture.md` / ADR set to re-validate against, then
  the drift check shall likewise emit a clear **"nothing to re-validate"** note (no
  architecture) and change **no** status, degrading gracefully exactly as the Architect
  contract does for absent architecture (D5).

### Docs
- **R14** — `store/local.md` shall document, in its rollup section, both the new **epic-done
  rollup** (all features `done` ⇒ epic `done`, derived then persisted — R1) and the
  **drift-check** that follows it (Scout re-validates remaining `draft`/`planned`/`pending`
  epics; Orchestrator demotes stale `planned`/`pending` → `draft`; `in-progress`/`done` never
  demoted).
- **R15** — `docs/WORKFLOW.md` shall document the drift check in an **additive section
  distinct from** the existing `/sdd-plan`, `/sdd-drill`, architecture-alignment, and
  `/sdd-fix` sections — where it sits (on epic rollup to `done`), that the **Scout flags** and
  the **Orchestrator demotes** stale `planned`/`pending` epics to `draft`, that re-drill
  (`/sdd-drill`) stays manual, and that demotion only ever moves an epic **backward**.

### Backward compatibility / portability / no schema change
- **R16** — `store/tasks.schema.json` shall be **unchanged** by this feature; a TaskStore
  that validated before shall validate exactly as before, and `./init.sh` shall exit 0 on the
  untouched repo (no new status value, no new field).
- **R17** — The harness shall leave the **feature-level** rollup, the F01 `next()` epic gate,
  the per-feature state machine, `/sdd-new`, `/sdd-plan`, `/sdd-drill`, `/sdd-next`,
  `/sdd-fix`, and every other agent role behaviorally **unchanged**; a repo with **no**
  planning tier (no `draft`/`planned` epics) shall get a **no-op** drift check and behave
  exactly as today.
- **R18** — The rollup + drift-check contract shall live in the **portable** role/store/doc
  files (`agents/orchestrator.md`, `agents/scout.md`, `store/local.md`, `docs/WORKFLOW.md`),
  **not** solely in `.claude/` glue (the rule's presence in the portable files is the
  contract); F06 adds **no** new slash command and **no** installer wiring.

### Versioning
- **R19** — The repository shall record this change as **one MINOR `VERSION` bump** with a
  matching `CHANGELOG.md` entry (a heading equal to the `VERSION` file's content) that
  describes the epic-done rollup, the Scout drift-check mode, and the Orchestrator-applied
  `planned`/`pending` → `draft` demotion.

## Out of scope
- **Re-drilling** a demoted epic — bringing it back to `planned` is a human-run `/sdd-drill`
  (F03), never an automatic F06 move (D1).
- **Rewriting** an epic's brief / `epic.md` (beyond the single `demoted on drift:` flag line)
  or any feature `.spec`/`.plan`/`.tasks`/`.tests` — F06 **flags**, it never rewrites content
  (D7).
- Demoting `in-progress` or `done` epics, or moving any epic **forward** — the check concerns
  *future* planned work only, and the only automatic move is one step **backward** (D1, D3).
- Changing F01–F05 behavior, the `draft`/`planned`/`pending`/`done` epic enum, the
  feature-level status enum/flags, or `store/tasks.schema.json` (R16).
- A new telemetry record **type** or `schema_version` bump — F06 reuses the existing
  `phase: scout` record (D6).
- A new slash command or any installer wiring — F06 adds none (R18).
- Validating the **correctness** of an ADR or of the Scout's stale/valid call — F06 defines
  the **concrete signals** and the **findings shape**; the human reviews the verdict at the
  next `/sdd-drill`.

## Open questions
- None — the seven questions from the intent brief are resolved as D1–D7 above.

## Constraints carried into the test contract
- Tests must **not** freeze the exact `VERSION` value (read `VERSION` at runtime) and must
  **not** couple a feature's CHANGELOG mention to the *current top* version — grep the
  CHANGELOG for the feature **marker** across the whole file, not only the
  `## [$(cat VERSION)]` section — and must **not** `git diff` a DO-NOT-TOUCH file against
  `main` (the permanent-suite anti-pattern, now recurred 4×). The genuine permanent invariant
  is the **content** of the portable contract (orchestrator + scout + store + docs), not a
  byte-freeze of any file or a version literal.
- The verification path stays **zero-dependency**: POSIX sh + grep + python3 here-docs. Any
  JSON fixture carries the **required root `project` field** and uses a **temp** store created
  with `mktemp` — it never mutates the live `state/tasks.json`. The load-bearing fixture
  proves the F06 demotion shape (an epic moving `planned → draft`, and a `done` epic whose
  features are all `done`) validates against `store/tasks.schema.json` **with no schema
  change** (jsonschema if installed, else the structural fallback that mirrors `init.sh`).
  Schema stays draft-07; `./init.sh` exits 0 afterward.
- All automated tests live in **`tests/test_drift_check.sh`** (POSIX sh; grep + python3
  here-docs; zero new deps), wired into `verification.test_command`.
