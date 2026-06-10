# /sdd-plan inception skill (vision + architecture + draft epics) — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one at
> a time. Each task names the R-id(s) it satisfies. Check off when done.

- [ ] **T1** (R4, R18) — Create `specs/_templates/vision.md`: a vision template with
  sections for **Problem**, **Users/audience**, **Outcomes**, and **Non-goals**, plus a
  one-line note that `vision.md` **complements** (does not supersede or absorb)
  `specs/product.md` and `specs/glossary.md`.
- [ ] **T2** (R5) — Create `specs/_templates/architecture.md`: a template with a
  **System shape** section, a **Stable upfront decisions** section, and an **ADRs**
  index section that references decisions by `ADR-NNNN` id.
- [ ] **T3** (R6) — Create `specs/_templates/adr.md`: a **one-decision** ADR template
  (e.g. `ADR-NNNN` title + Context / Decision / Consequences).
- [ ] **T4** (R1, R3, R9, R10, R11, R12, R13, R14, R15, R16, R17, R18, R20) — Create
  `agents/planner.md`, the portable Planner role contract. It must state/specify:
  - It is the **producer** of `specs/vision.md`, `specs/architecture.md` + ADRs, and a
    block of `draft` epics, and is written for any **AGENTS.md-compatible** CLI
    (portable, not Claude-specific) (R1, R20).
  - A short **adaptive Q&A** front-end presenting **at most 3 text-only**
    (markdown/ASCII) option mockups where the roadmap forks; **never images** (R3).
  - ADR location/numbering: `specs/adr/NNNN-<title>.md`, 4-digit zero-padded, allocated
    strictly above the max existing ADR number, no reuse (R9, D4).
  - Architecture **depth boundary**: only stable, whole-system upfront decisions; defer
    per-epic ADR **deltas** to F03 (`/sdd-drill`); never author feature-level design
    (R10, D6).
  - Draft-epic seeding: write each new epic with `status: "draft"` and `features: []`;
    allocate ids as a next-sequential block strictly above max existing `E##`,
    append-only, no reuse (R11, D5).
  - Per seeded epic, create `specs/epics/<id>-<slug>/epic.md` = **title + one-paragraph
    business brief only** (no feature specs, no `F01`, no EARS, no plan) (R12).
  - **Re-validate** `state/tasks.json` against `store/tasks.schema.json` (zero-dependency
    path) after seeding; on failure, **report it and do not claim a successful plan**
    (R13).
  - **Seeds-never-specs**: never create/modify any `.spec.md`/`.plan.md`/`.tasks.md`/
    `.tests.md`, never write EARS or a plan, never spawn the Architect (R14).
  - **Never past `draft`**: every seeded epic is `status: "draft"`; never advance any
    epic/feature to `planned`/`in-progress`/`in-review`/`done`, never stamp
    `autonomous: true`; name F03 (`/sdd-drill`) as the `draft → planned` step (R15).
  - **Reuse F01's `draft` state and gate**: no new status, no new approval mechanism;
    seeded epics are inert because the `next()` draft gate already blocks selection
    (R16).
  - **Re-run behavior**: if `specs/vision.md` or `specs/architecture.md` already exists,
    a default run STOPS and reports the project already has a plan (pointing at
    `/sdd-drill` or an explicit amend mode); an explicit amend mode **appends** new ADRs
    and new `draft` epics (ids above the current max) without rewriting or renumbering
    existing artifacts or epics (R17, D2).
  - `vision.md` **complements** `product.md`/`glossary.md` and the Planner does not
    rewrite or delete them (R18, D3).
- [ ] **T5** (R2, R3) — Create `.claude/commands/sdd-plan.md`: a slash-command wrapper
  that acts as **Planner**, points at `agents/planner.md` as the durable contract, reads
  the idea from `$ARGUMENTS`, runs `./init.sh` first (STOP on non-zero), carries the
  **≤3 text-only options** rule, and reports the seeded epics + artifact paths without
  spawning the Architect or advancing any status.
- [ ] **T6** (R21) — Edit `docs/WORKFLOW.md`: add a short "Whole-project inception
  (`/sdd-plan`)" note placing `/sdd-plan` upstream of `/sdd-drill` (F03) and the
  `/sdd-next` loop — a producer that writes `vision.md`/`architecture.md` + ADRs and
  seeds `draft` epics, never writes feature specs, and never advances an epic past
  `draft`.
- [ ] **T7** (R22) — Edit `README.md`: add a one-line `/sdd-plan` description (the
  whole-project inception skill) beside the existing `/sdd-new` / `/sdd-next` mentions.
- [ ] **T8** (R1–R23) — Create `tests/test_sdd_plan.sh` per `F02-sdd-plan.tests.md`
  (POSIX sh; grep contract assertions over the role/command/templates/docs + one python
  fixture that seeds a synthetic `draft` epic with `features: []` into a temp store and
  asserts it validates against `store/tasks.schema.json` + one `./init.sh` exit-0 run).
  Constraints: read `VERSION` dynamically (never assert a literal version), never
  `git diff` against `main`, zero new dependencies, never mutate the live
  `state/tasks.json`.
- [ ] **T9** (wiring) — Edit `harness.config.yaml`: append `&& sh tests/test_sdd_plan.sh`
  to `verification.test_command` and extend its trailing comment (e.g. `+ sdd-plan`).
- [ ] **T10** (R23) — Bump `VERSION` by one MINOR (read the current value first; do not
  hard-code). Add a `CHANGELOG.md` entry under `## [<new version>]` describing
  `/sdd-plan`, the vision/architecture/ADR artifacts, and the `features: []` draft-epic
  seeding.
- [ ] **T11** — Write/finish tests per `F02-sdd-plan.tests.md`, then run `./init.sh` and
  the full `verification.test_command`; ensure green before hand-off. Do **not** change
  any status in `state/tasks.json`, and do **not** touch any DO-NOT-TOUCH file.
