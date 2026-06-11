# Drift check on epic rollup (Scout re-validates remaining epics) — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one at
> a time. Each task names the R-id(s) it satisfies. Check off when done.

- [x] **T1** (R1, R9, R14) — Edit `store/local.md`: in the rollup section (beside the
  existing sliced-feature rollup, **additively**, not inside it), document:
  - **Epic-done rollup** — *when every feature of an epic is `done`, the epic's `done`
    status is **derived and persisted** (mirroring the existing "derive, then persist"
    feature-rollup discipline) and **re-validated** against `store/tasks.schema.json`* —
    introducing **no new status value** and **no schema change** (R1).
  - **Drift check on that rollup** — after an epic rolls up to `done`, the Scout
    re-validates the remaining `draft`/`planned`/`pending` epics; the Orchestrator demotes a
    stale `planned`/`pending` epic to `draft`; a stale `draft` epic stays `draft` but is
    flagged; **`in-progress`/`done` epics are never demoted** (R9, R14).

- [x] **T2** (R2, R3, R7, R8, R9, R10, R11, R12, R13) — Edit `agents/orchestrator.md`: in
  or beside the rollup section (~205–218), add the epic-rollup → drift-check step. It must
  state:
  - When a feature transition makes **all** of an epic's features `done`, the Orchestrator
    (owner of `set_status`) **derives+persists** that epic's `done` status, **re-validates**
    `state/tasks.json`, and **then triggers the drift check before selecting the next task**
    (R2).
  - The drift check fires **only** on an epic rolling up to `done` (not every loop, not a
    feature `done` that does not complete its epic), and spawns the **read-only Scout** in a
    **drift-check mode** to re-validate the remaining `draft`/`planned`/`pending` epics
    against the just-completed epic's produced artifacts (new/changed ADRs + architecture
    deltas + what its features changed) (R3).
  - The **Scout never writes `state/tasks.json`** — it produces the findings file and the
    **Orchestrator alone** applies the demotion (Scout-flags / Orchestrator-acts) (R8).
  - On a stale `planned`/`pending` epic, demote it to **`draft`** via `set_status` and
    **re-validate** `state/tasks.json` (R7); the check considers `planned`/`pending`/`draft`
    and **never** `in-progress`/`done` (R9).
  - The **backward-only** invariant: drift-driven demotion **only ever moves an epic
    backward** (`planned`/`pending` → `draft`), never advances one and never demotes
    `in-progress`/`done`; re-drilling a demoted epic stays a **manual** `/sdd-drill` (F03)
    (R10).
  - On demoting, **report the re-drill pointer** (`run /sdd-drill <epic>`) and **may append
    a single flag line** `demoted on drift: <reason>` to the demoted epic's `epic.md` —
    **flag only**, never a content rewrite (R11).
  - The **no-op note** "nothing to re-validate" when there are no remaining
    `draft`/`planned`/`pending` epics (R12) or no architecture to re-validate against (R13).

- [x] **T3** (R4, R5, R6, R12, R13) — Edit `agents/scout.md`: add a **drift-check mode**
  section that **preserves the read-only contract**. It must state:
  - **Inputs**: the just-completed epic, the remaining `draft`/`planned`/`pending` epics,
    and `specs/architecture.md` / `specs/adr/*`.
  - **Findings file**: `progress/<run>/scout-drift-<completed-epic>.md`, with **per remaining
    epic** a verdict of **still-valid** or **stale**, and for a stale verdict the **concrete
    signal** that fired + the **artifact it points at** (R4).
  - **Concrete staleness signals**: **(S1)** a new ADR's decision **contradicts** the epic's
    brief; **(S2)** the brief **references a removed/renamed** thing; **(S3)** an explicit
    **`supersedes E0X`** / `obsoletes E0X` marker — and an epic is **stale only when ≥1
    fires**, otherwise **still-valid** (R5).
  - **Read-only preserved**: in drift-check mode the Scout **writes only to `progress/`**,
    makes **no** state change, and **never** writes `state/tasks.json` (it flags; the
    Orchestrator acts) (R6).
  - The **"nothing to re-validate"** note for the no-remaining-epic / no-architecture no-op
    (R12, R13).

- [x] **T4** (R15) — Edit `docs/WORKFLOW.md`: add a **new, distinct** "Drift check on epic
  rollup" section (separate from the existing `/sdd-plan`, `/sdd-drill`,
  architecture-alignment, and `/sdd-fix` sections) — it fires on epic rollup to `done`, the
  **Scout flags** and the **Orchestrator demotes** stale `planned`/`pending` epics to
  `draft`, re-drill (`/sdd-drill`) stays **manual**, and demotion only ever moves an epic
  **backward**.

- [x] **T5** (R1–R19) — Create `tests/test_drift_check.sh` per `F06-drift-check.tests.md`
  (POSIX sh; grep contract assertions over the orchestrator/scout/store/doc prose + one
  python fixture that seeds, into a **temp** store carrying the required root `project`
  field, (a) a `done` epic whose features are all `done` and (b) a `draft` epic — the
  post-demotion shape — and asserts both validate against `store/tasks.schema.json` + one
  `./init.sh` exit-0 run). Constraints: read `VERSION` dynamically (never a literal
  version); grep the CHANGELOG **drift-check marker across the whole file** (never coupled to
  the current-top-version section); never `git diff` against `main`; zero new dependencies;
  never mutate the live `state/tasks.json`.

- [x] **T6** (wiring) — Edit `harness.config.yaml`: append `&& sh tests/test_drift_check.sh`
  to `verification.test_command` and extend its trailing comment (e.g. `+ drift-check`).

- [x] **T7** (R19) — Bump `VERSION` by one MINOR (read the current value first; do **not**
  hard-code). Add a `CHANGELOG.md` entry under `## [<new version>]` describing the epic-done
  rollup, the Scout drift-check mode, and the `planned`/`pending` → `draft` demotion.

- [x] **T8** — Run `./init.sh` and the **full** `verification.test_command`; ensure green
  before hand-off. Do **not** change any status in `state/tasks.json` beyond the
  Orchestrator-owned transition for this feature, and do **not** touch any DO-NOT-TOUCH file
  (especially `store/tasks.schema.json`, the existing feature-level rollup, and the Scout's
  read-only contract).
