---
id: E06-F05
title: "/sdd-fix lightweight lane (maintenance epic, brief-only intake)"
epic: E06-planning-tier
status: done               # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false           # installed-body role + command + builder/reviewer notes + docs change; human reviews
depends_on: [E06-F01]
owner: araozmd
---

# /sdd-fix lightweight lane (maintenance epic, brief-only intake) — Functional Spec

## Context
The SDD loop is built for **features**: `/sdd-new` (or `/sdd-plan` → `/sdd-drill`) →
Architect 4-file spec → human gate → Builder → Reviewer. That ceremony is right for
net-new capability but far too heavy for a one-line bug or a hotfix. Today a small fix
either gets over-specified (a full 4-file spec for a typo) or smuggled in outside the
harness entirely (no record, no review). There is no **lightweight lane** that keeps
minor fixes inside the harness — recorded and reviewed — without the spec/drill overhead.

The planning tier (F01–F03) is complete, so this is the last piece of E06: a fast path
for maintenance work. The mechanism is **not new routing**. F01 already shipped the
primitive `/sdd-fix` rides on: the Orchestrator routes `pending + sdd: false → Builder
directly (skip full SDD), then Reviewer` (`agents/orchestrator.md` step 4 table;
`docs/WORKFLOW.md` "Selective SDD" → `sdd: false`). F05 is a thin **front-end +
convention** over that existing primitive: `/sdd-fix "<desc>"` seeds a fix as an
`sdd: false` feature under a single reserved **maintenance epic**, carrying only a
one-paragraph inbox brief — no `.spec/.plan/.tasks/.tests` and no drill ceremony — and
then hands the seeded fix to the existing `sdd: false` loop. The change is purely
**additive**: `/sdd-new`, `/sdd-plan`, `/sdd-drill`, `/sdd-next`, and the entire
`sdd: true` path are untouched; the maintenance epic only exists once `/sdd-fix` is run.

## Business rules
- **Front-end over an existing primitive, not a new lane.** `/sdd-fix` introduces **no
  new Orchestrator routing**, **no new TaskStore status**, and **no schema change**. It
  reuses the F01 `sdd: false → Builder → Reviewer` routing and the existing `autonomous`
  flag. It is a producer/seeder + a hand-off to that loop; it never writes production
  code itself.
- **Brief-only intake, never a spec.** A fix is recorded as an `sdd: false` feature plus
  exactly one fix-oriented inbox brief at `progress/inbox/<id>.md` (problem + intended
  fix + how to verify). `/sdd-fix` must **NEVER** create or modify any `.spec.md`,
  `.plan.md`, `.tasks.md`, or `.tests.md` file, never write EARS or a technical plan,
  never create a feature `spec_path` *directory*, and never spawn the Architect. (Same
  seeds-never-specs guardrail as Inception/Planner/Driller.)
- **One reserved maintenance epic, never `draft`.** All fixes collect under a single
  reserved maintenance epic (D1). Its status is a **selectable, non-`draft`** value so
  the F01 `next()` gate returns its fixes; `/sdd-fix` must never seed it as `draft` and
  never seed any other epic.
- **Create-on-first-use, identify-by-id thereafter.** `/sdd-fix` creates the maintenance
  epic on first use if absent, and on every later run re-identifies the *same* epic by
  its reserved id (D2) and appends to it — it never creates a second maintenance epic and
  never renumbers or reorders existing fixes.
- **Append-only fix ids.** Each fix is appended as a next-sequential `F##` strictly above
  the maintenance epic's current max `F##` (no reuse, no gap-refill, no reorder).
- **Re-validate before claiming success.** After every write (epic create, fix append),
  `/sdd-fix` re-validates `state/tasks.json` against `store/tasks.schema.json` via the
  zero-dependency path; it must never report a successful seed on a validation failure
  and never leave an invalid TaskStore behind as a success.
- **Additive Builder/Reviewer clarifications only.** Any clarification the lane needs so
  the existing Builder/Reviewer cleanly handle a brief-only `sdd: false` item must be
  **additive** and must not change the `sdd: true` path: the Builder works from the inbox
  brief (not a `tasks.md`); the Reviewer verifies behaviour + the fix's test
  **behaviourally**, with **no R-id traceability** for a non-SDD item.
- **Portability pillar.** The lane's normative contract lives in a portable role file
  (`agents/fixer.md`) + AGENTS.md, not solely in `.claude/` glue; it must run on any
  AGENTS.md-compatible CLI. The Claude `/sdd-fix` slash command is just the wrapper.
- **Backward compatible / additive ⇒ one MINOR `VERSION` bump**, recorded in
  `CHANGELOG.md` (installed body changes: `agents/`, `.claude/` glue, `docs/`).

## Decisions (D1..D6, resolving the intent brief's open questions)
- **D1 — Maintenance-epic identity: reserved id `E99`, slug `maintenance`, title
  "Maintenance (hotfixes & minor fixes)", status `planned`.** The id is a deliberately
  **high reserved number** (`E99`) so it satisfies the existing `^E[0-9]+$` schema pattern
  (no special non-numeric id, no schema change) while sitting clearly *above* any
  realistic feature-epic block — `/sdd-plan`/`/sdd-drill` allocate epics `max + 1` upward
  from low numbers (E01, E02, …), so reserving the top of the space keeps the maintenance
  bucket out of their append path and unambiguous to grep. Status is **`planned`**, not
  `pending`/`in-progress`/`draft`: `planned` is a first-class F01 epic value whose
  features are **selectable** by `next()` (the epic gate skips only `draft` epics; a
  `planned` epic is treated exactly like a `pending` epic — `agents/orchestrator.md`
  step 3), and it reads truthfully as "a standing, approved bucket" rather than a
  one-shot in-flight epic. `draft` is explicitly rejected (its features would never be
  selectable, defeating the lane); `in-progress` is rejected (a standing bucket is never
  "in progress" — it never completes). The epic carries `features: []` on creation
  (schema-valid; F02 established the empty-features shape).
- **D2 — Create-on-first-use; re-identify by the reserved id `E99` (not by marker, not by
  title).** `/sdd-fix` is the **only** seeder of the maintenance epic — there is no
  installer/init pre-seed, so a repo that never runs `/sdd-fix` carries no maintenance
  epic (backward-compat). On each run it looks up epic `E99` in `state/tasks.json`: if
  absent it creates it (D1 shape) + `specs/epics/E99-maintenance/epic.md`; if present it
  reuses it and appends. Re-identification is **by id**, not by a new marker field (a
  marker would be a schema change, which is out of scope) and not by title (titles are
  mutable/typo-prone). Lazy-create keeps the convention zero-footprint until first used;
  id-based lookup makes reuse deterministic and idempotent (re-running `/sdd-fix` never
  forks a second bucket).
- **D3 — Fix features are stamped `autonomous: true` by default (run end-to-end), with an
  explicit opt-out to stay gated.** A hotfix's value is speed: the least-surprising
  behaviour is that `/sdd-fix "<desc>"` seeds **and runs** the fix through Builder →
  Reviewer without parking at the per-feature spec-approval gate — there is no spec to
  approve for an `sdd: false` item, so a human spec-gate would be a pause with nothing to
  review. So each seeded fix carries `sdd: false` **and** `autonomous: true` by default.
  This reuses the existing `autonomous` flag (no new approval mechanism); `autonomous:
  true` skips the *human spec-approval* gate but **not** the Reviewer — the fix is still
  verified before `done`. An explicit opt-out (e.g. a `--gated` intent) seeds the fix
  `autonomous: false` so it parks at the normal gate for the rare fix a human wants to
  eyeball first. Note `sdd: false` features bypass the `spec-ready` state entirely
  (Orchestrator routes `pending + sdd:false` straight to the Builder), so the
  `autonomous` flag here governs only whether the human is *asked to confirm* before the
  Builder runs in-session.
- **D4 — New portable `agents/fixer.md` role, sibling to Inception/Planner/Driller (not a
  mode of Inception, not a bare command wrapper over the Builder).** Mirroring F02-D1 /
  F03-D1 portability reasoning: the lane's normative contract must live in a portable role
  file so it runs on any AGENTS.md-compatible CLI, not solely in `.claude/` glue. The
  Fixer is its own altitude of brief-only intake — *seed one `sdd: false` fix under the
  reserved maintenance epic, then hand off to the existing loop* — distinct from
  Inception (triages **one idea to one of three altitudes**, defaults to `sdd: true`,
  never touches a reserved epic) and from the Builder (which **implements**, and must not
  also own seeding/epic-creation). Folding fix-seeding into Inception would overload its
  three-altitude triage and its "default `sdd: true`" intake; making `/sdd-fix` a bare
  wrapper over the Builder would leave the seeding/epic-create/`autonomous`-stamp contract
  unwritten in any portable file (the F02 portability defect). A clean sibling keeps each
  role's guardrails crisp and the grep-based test contract unambiguous. `agents/inception.md`,
  `agents/planner.md`, and `agents/driller.md` are therefore DO-NOT-TOUCH files for F05.
- **D5 — Builder & Reviewer get minimal *additive* clarifications for a brief-only
  `sdd: false` item; the `sdd: true` path is untouched.** The existing roles already
  *route* `sdd: false` (Orchestrator) but do not state how the Builder/Reviewer handle an
  item that has a brief and **no** `tasks.md`/`R-ids`. F05 adds a small additive note to
  each: `agents/builder.md` states that for an `sdd: false` item it works from the
  **inbox brief** (`progress/inbox/<id>.md`) as its worklist rather than a `tasks.md`, and
  still writes at least one test proving the fix; `agents/reviewer.md` states that for an
  `sdd: false` item it verifies the fix **behaviourally** plus the fix's test, and that
  the R-id **traceability** check (its check #2) **does not apply** when there are no
  R-ids (a brief-only fix is not failed for lacking an R-id↔test table). Both notes are
  strictly additive — they add an `sdd: false` clause and change **nothing** about the
  `sdd: true` four-file path. (This keeps the lane's full contract in portable role files,
  not in `.claude/` glue.)
- **D6 — `/sdd-fix` seeds *and* hands off to the loop in-session (it does not stop at
  seeding like `/sdd-new`).** The brief promises "found a small bug → reviewed, merged fix
  without opening the Architect"; stopping at a seed (then requiring a separate
  `/sdd-next`) would re-introduce ceremony the lane exists to remove. So after seeding +
  re-validation, `/sdd-fix` invokes the existing `sdd: false → Builder → Reviewer` loop on
  the just-seeded fix **in the same session** (it does not re-implement routing — it hands
  the seeded fix to the existing Orchestrator routing / `/sdd-next` behaviour). It still
  writes no production code itself (the Builder does) and creates no spec. The seam stays
  the existing primitive; F05 only triggers it. (Contrast: Inception/Planner stop at
  seeding because their downstream is a human-gated Architect; the fix lane's downstream
  is the autonomous `sdd: false` loop, so an in-session hand-off is the faithful "fast
  path".)

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

### The skill + portable role contract
- **R1** — The harness shall provide a portable Fixer role file (`agents/fixer.md`) that
  states it is the brief-only intake that seeds an `sdd: false` fix under the reserved
  maintenance epic and hands it to the existing `sdd: false → Builder → Reviewer` loop,
  and that it is written for any AGENTS.md-compatible CLI (portable, not Claude-specific).
- **R2** — The harness shall provide a `/sdd-fix` slash command
  (`.claude/commands/sdd-fix.md`) that acts as **Fixer** by pointing at `agents/fixer.md`
  as the durable contract and that reads the free-text fix description from `$ARGUMENTS`
  (STOP and ask if empty).
- **R3** — `agents/fixer.md` and the `/sdd-fix` command shall require a short, **adaptive**
  Q&A front-end whose forks are presented as at most 3 **text-only** (markdown/ASCII)
  options and shall **never generate images** (honoring the AGENTS.md portability rule).

### Reuse of the existing primitive (no new routing / status / schema)
- **R4** — `agents/fixer.md` shall state that the lane reuses the **existing**
  `pending + sdd: false → Builder → Reviewer` routing
  (`agents/orchestrator.md` / `docs/WORKFLOW.md`) and shall introduce **no new
  Orchestrator routing rule**, **no new TaskStore status value**, and **no
  `store/tasks.schema.json` change**.

### Maintenance-epic create / identify / reuse (D1, D2)
- **R5** — When `/sdd-fix` runs and epic id `E99` is **absent** from `state/tasks.json`,
  the Fixer shall create the reserved maintenance epic with `id: "E99"`, slug
  `maintenance`, title "Maintenance (hotfixes & minor fixes)", `status: "planned"`, and
  `features: []`, and create `specs/epics/E99-maintenance/epic.md` (title + one-paragraph
  brief only — no feature spec) (D1).
- **R6** — When `/sdd-fix` runs and epic id `E99` is **present**, the Fixer shall reuse
  that **same** epic (re-identified **by id `E99`**, not by marker or title) and shall not
  create a second maintenance epic nor renumber/reorder its existing fixes (D2).
- **R7** — `agents/fixer.md` shall state that the maintenance epic's status is a
  **selectable, non-`draft`** value (`planned`) so the F01 `next()` gate returns its
  fixes, and that the Fixer must never seed it (or any epic) as `draft`.

### Brief-only `sdd: false` fix seeding (D3)
- **R8** — When `/sdd-fix` seeds a fix, the Fixer shall append one feature to epic `E99`'s
  `features` array with `sdd: false`, `status: "pending"`, a one-line `title`, a
  `spec_path`, and a fix `id` allocated next-sequential strictly **above** the epic's max
  existing `F##` (append-only, no reuse).
- **R9** — When `/sdd-fix` seeds a fix, the Fixer shall stamp it `autonomous: true` by
  default (so it runs end-to-end with no per-feature spec-approval pause), and shall
  honor an explicit **opt-out** that seeds the fix `autonomous: false` (parks at the
  normal gate) — reusing the existing `autonomous` flag, introducing no new approval
  mechanism (D3).
- **R10** — When `/sdd-fix` seeds a fix, the Fixer shall write exactly one fix-oriented
  inbox brief at `progress/inbox/<id>.md` (problem + intended fix + how to verify) from
  `specs/_templates/inbox-brief.md`, and shall **not** create any feature
  `.spec.md`/`.plan.md`/`.tasks.md`/`.tests.md`, shall not create a `spec_path`
  directory, and shall not spawn the Architect (brief-only, never a spec).
- **R11** — After each write (epic create and fix append), the Fixer shall re-validate
  `state/tasks.json` against `store/tasks.schema.json` via the zero-dependency path, and
  **if** validation fails **then** the Fixer shall report the failure and shall not claim
  a successful seed (it must not leave an invalid TaskStore behind as a success).

### Builder-from-brief + Reviewer-behavioural (D5)
- **R12** — `agents/builder.md` shall state (additively, for an `sdd: false` item only)
  that the Builder works from the **inbox brief** (`progress/inbox/<id>.md`) as its
  worklist when there is no `tasks.md`, and still writes at least one test proving the
  fix — without changing the `sdd: true` four-file-spec path.
- **R13** — `agents/reviewer.md` shall state (additively, for an `sdd: false` item only)
  that the Reviewer verifies the fix **behaviourally** plus the fix's test, and that its
  **R-id traceability** check does **not apply** when the item carries no R-ids (a
  brief-only fix is not rejected for lacking an R-id↔test table) — without changing the
  `sdd: true` path.

### Hand-off to the loop (D6)
- **R14** — `agents/fixer.md` and the `/sdd-fix` command shall state that, after seeding +
  re-validation, the lane **hands the seeded fix off to the existing `sdd: false → Builder
  → Reviewer` loop in-session** (it does not stop at seeding), reusing the existing
  Orchestrator routing rather than re-implementing it, and that the Fixer itself writes no
  production code.

### Installer wiring
- **R15** — `harness-install.sh` shall generate `.claude/commands/sdd-fix.md` into target
  repos that acts as **Fixer**, resolves the role against `.harness/`
  (`.harness/agents/fixer.md`), and carries `$ARGUMENTS`; and shall mirror the same
  command to `.opencode/command/sdd-fix.md` (byte-identical to the `.claude/` copy).
- **R16** — The installer shall install the portable Fixer role into the target profile
  at `.harness/agents/fixer.md` (carried by the existing `agents/` copy), and
  `tests/test_install.sh` shall assert: `.claude/commands/sdd-fix.md` exists, resolves
  `.harness/agents/fixer.md`, carries `$ARGUMENTS`; `.opencode/command/sdd-fix.md` exists
  and equals the `.claude/` copy; and `.harness/agents/fixer.md` is installed.

### Backward compatibility / portability
- **R17** — The harness shall leave `/sdd-new`, `/sdd-plan`, `/sdd-drill`, `/sdd-next`,
  their command files, `agents/inception.md`, `agents/planner.md`, `agents/driller.md`,
  and the entire `sdd: true` path behaviorally unchanged; a repo that never runs
  `/sdd-fix` shall carry **no** maintenance epic and shall validate and behave exactly as
  today, and `./init.sh` shall exit 0 on the untouched repo.
- **R18** — The Fixer's normative contract (seed `sdd: false` under the reserved
  maintenance epic, `autonomous`-by-default, brief-only-never-spec, hand off to the
  existing loop) shall live in the portable role file `agents/fixer.md`, not solely in
  `.claude/` glue (the rule's presence in the portable file is the contract).

### Docs
- **R19** — `docs/WORKFLOW.md` shall document the lightweight lane — `/sdd-fix` seeds an
  `sdd: false` fix under the reserved maintenance epic with only an inbox brief (no
  4-file spec, no drill) and runs it through the existing `sdd: false → Builder →
  Reviewer` path — placed alongside the "Selective SDD (`sdd` flag)" / full-SDD-flow
  description, and shall state it adds no new status and no new routing.
- **R20** — `README.md` shall carry a one-line description of `/sdd-fix` (the lightweight
  fix lane) alongside the existing `/sdd-new` / `/sdd-plan` / `/sdd-drill` / `/sdd-next`
  mentions.

### Versioning
- **R21** — The repository shall record this change as one MINOR `VERSION` bump with a
  matching `CHANGELOG.md` entry (a heading equal to the `VERSION` file's content) that
  describes `/sdd-fix`, the maintenance-epic convention, the brief-only `sdd: false`
  seeding, and the additive Builder/Reviewer clarifications.

## Out of scope
- Any new Orchestrator **routing** rule, any new TaskStore **status** value, or any
  `store/tasks.schema.json` change — F05 reuses the existing `sdd: false` primitive and
  the existing `autonomous` flag (D3, R4).
- **Triage intelligence** about whether a fix is "minor enough" — `/sdd-fix` trusts the
  human's choice of lane; deciding a fix is actually a feature is the human's call
  (re-run `/sdd-new`).
- Changing the `sdd: true` four-file path, the Architect, the `draft`/`planned` epic gate,
  or `/sdd-plan` / `/sdd-drill` (those are touched only additively, per D5/R12/R13, and
  never on the `sdd: true` branch).
- An installer/`init.sh` **pre-seed** of the maintenance epic — it is created lazily on
  first `/sdd-fix` use only (D2).
- F04 (Architect ADR-citation contract) and F06 (drift check) — separate features.

## Open questions
- None — the six questions from the intent brief are resolved as D1–D6 above.

## Constraints carried into the test contract
- Tests must not freeze the exact `VERSION` value and must not diff DO-NOT-TOUCH files
  against `main` (the permanent-suite anti-pattern in the repo memory). The genuine
  permanent invariant is the **content** of the portable contract (role + command +
  builder/reviewer notes + docs), not a byte-freeze of any file.
- The verification path stays zero-dependency: POSIX sh + grep + python3 here-docs, with
  the `jsonschema`-absent fallback still validating a fixture store. Any JSON fixture is a
  **temp** store carrying the required root `project` field and an `sdd: false` /
  `autonomous: true` fix inside a **`planned`** `E99` maintenance epic; it **never** mutates
  the live `state/tasks.json`. Schema stays draft-07 (id `E99` matches `^E[0-9]+$`);
  `./init.sh` exits 0 afterward.
