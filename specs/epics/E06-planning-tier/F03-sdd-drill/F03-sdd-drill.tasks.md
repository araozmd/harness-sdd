# /sdd-drill skill (decompose draft epic, ADR deltas, epic-level approval) — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one at
> a time. Each task names the R-id(s) it satisfies. Check off when done.

- [x] **T1** (R1, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15, R16, R17,
  R19) — Create `agents/driller.md`, the portable Driller role contract. It must
  state/specify:
  - It is the **consumer** that decomposes exactly **one** `draft` epic into a feature
    list, appends ADR deltas, and drives the single epic-level approval, written for any
    **AGENTS.md-compatible** CLI (portable, not Claude-specific) (R1, R19).
  - A short **adaptive Q&A** front-end presenting **at most 3 text-only**
    (markdown/ASCII) option mockups where the feature breakdown forks; **never images**
    (R3).
  - `<epic-id>` is **required**; on empty argument, STOP and ask for it (R4). If the id
    is missing or the epic is not `draft`, a default run **STOPS** and reports why; an
    explicit **amend** opt-in on an already-`planned` epic appends new features/ADRs
    above the current max without renumbering or re-flipping (R5, D2).
  - Before decomposing, the Driller **reads** the target `draft` epic (`epic.md` +
    `state/tasks.json` row) and F02's design artifacts (`specs/vision.md`,
    `specs/architecture.md`, `specs/adr/NNNN-*.md`) as inputs (R6).
  - **Feature seeding**: write each new feature into the epic's `features` array with
    `status: "pending"`, `sdd: true`, a one-line `title`, a `spec_path`
    (`specs/epics/<id>-<slug>/F<NN>-<slug>/`), and an intra-epic `depends_on`; allocate
    ids as a next-sequential block strictly above the epic's max `F##`, append-only, no
    reuse (R7, D3).
  - Fill the epic's `specs/epics/<id>-<slug>/epic.md` **feature table** with one row per
    seeded feature matching `state/tasks.json` (R8).
  - Write a per-feature inbox brief at `progress/inbox/<E##>-F<NN>.md` from
    `specs/_templates/inbox-brief.md`, recording the `ADR-NNNN` ids each feature is
    expected to honor (R9, D7).
  - **Re-validate** `state/tasks.json` against `store/tasks.schema.json` (zero-dependency
    path) after seeding/flipping; on failure, **report it and do not claim a successful
    drill** (R10).
  - **ADR deltas**: append per-epic decisions as one-decision ADRs at
    `specs/adr/NNNN-<title>.md` (4-digit, above the max existing ADR number, no reuse),
    and **do not rewrite or renumber F02's existing ADRs** (R11); scope deltas to
    per-epic decisions and never author feature-level design (the Architect/F04 boundary)
    (R12, D5).
  - **Approve branch**: flip the **epic** `draft → planned` and stamp `autonomous: true`
    on **every** seeded feature (all-or-nothing) (R13, D4, D6).
  - **Keep-gated branch**: flip the **epic** `draft → planned` while leaving **every**
    seeded feature `autonomous: false`; never leave a drilled epic in `draft` (R14, D4,
    D6).
  - The drill ends in **exactly one** epic-level human decision realized solely through
    F01's `planned` state + the existing `autonomous` flag — **no new status, no new
    approval mechanism, no schema change** (R15).
  - F03 is the **only** path past `draft` (consistent with `agents/planner.md`'s "never
    past draft"); the Driller advances only the **epic** to `planned`, never another epic
    and never a feature's own status (R16).
  - **Decomposes-never-specs**: never create/modify any `.spec.md`/`.plan.md`/`.tasks.md`/
    `.tests.md`, never write EARS or a plan, never spawn the Architect — the existing
    Architect specs each feature just-in-time during the autonomous run (R17).
- [x] **T2** (R2, R3, R4, R5) — Create `.claude/commands/sdd-drill.md`: a slash-command
  wrapper that acts as **Driller**, points at `agents/driller.md` as the durable
  contract, reads `<epic-id>` from `$ARGUMENTS`, runs `./init.sh` first (STOP on
  non-zero), STOPs on empty/missing/non-`draft` target (R4, R5), carries the **≤3
  text-only options** rule (R3), and presents the single approve / keep-gated decision —
  without spawning the Architect or writing any feature spec.
- [x] **T3** (R20) — Edit `docs/WORKFLOW.md`: add a short "Per-epic drill-down
  (`/sdd-drill`)" note (adjacent to the existing `/sdd-plan` note) placing `/sdd-drill`
  between `/sdd-plan` and `/sdd-next` — it decomposes a `draft` epic into features + ADR
  deltas and ends in one epic-level approval (approve → `planned` + `autonomous: true`;
  keep gated → `planned`, features gated), is the only step that flips `draft → planned`,
  and never writes feature specs.
- [x] **T4** (R21) — Edit `README.md`: add a one-line `/sdd-drill` description (the
  per-epic drill-down skill) beside the existing `/sdd-new` / `/sdd-plan` / `/sdd-next`
  mentions.
- [x] **T5** (R1–R22) — Create `tests/test_sdd_drill.sh` per `F03-sdd-drill.tests.md`
  (POSIX sh; grep contract assertions over the role/command/docs + one python fixture
  that seeds a synthetic `pending` feature inside a `planned` epic — stamped `autonomous:
  true`, with the required root `project` field — into a TEMP store and asserts it
  validates against `store/tasks.schema.json` + one `./init.sh` exit-0 run). Constraints:
  read `VERSION` dynamically (never assert a literal version), never `git diff` against
  `main`, zero new dependencies, never mutate the live `state/tasks.json`.
- [x] **T6** (wiring) — Edit `harness.config.yaml`: append `&& sh tests/test_sdd_drill.sh`
  to `verification.test_command` and extend its trailing comment (e.g. `+ sdd-drill`).
- [x] **T7** (R22) — Bump `VERSION` by one MINOR (read the current value first; do not
  hard-code). Add a `CHANGELOG.md` entry under `## [<new version>]` describing
  `/sdd-drill`, the feature decomposition + ADR deltas, and the approve / keep-gated
  branches.
- [x] **T8** — Run `./init.sh` and the full `verification.test_command`; ensure green
  before hand-off. Do **not** change any status in `state/tasks.json` beyond the
  Orchestrator-owned transition for this feature, and do **not** touch any DO-NOT-TOUCH
  file.
