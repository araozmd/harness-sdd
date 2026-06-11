# Architect contract: architecture.md mandatory input, specs cite ADRs — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one at a
> time. Each task names the R-id(s) it satisfies. Check off when done. There is no
> application code — this feature ships prose (role + template + docs) + one test suite.

- [ ] **T1** (R1, R2, R3, R4, R5, R7, R8, R9, R10, R18) — Amend `agents/architect.md`,
  the consumer contract. It must add/state:
  - **Read these first** — add `specs/architecture.md` and the relevant
    `specs/adr/NNNN-*.md` as a **mandatory input** alongside the inbox brief **whenever
    those artifacts are present** (R1); state the Architect reuses the **F03-D7 hook** —
    reading the `ADR-NNNN` ids the inbox brief already records as the seed for which
    decisions the feature touches (R2).
  - **Output contract** — require every feature `.spec.md` (when architecture artifacts are
    present) to carry a **`## Architecture alignment`** section citing each touched
    `ADR-NNNN` + a one-line "how this honors it" (R3); when present-but-nothing-touched,
    record **`ADRs touched: none`** with a one-line why — explicit, not silent (R4); when a
    feature must **diverge**, state the divergence in that section (which ADR, how it
    departs, why) and **never** author an ADR delta or invoke `/sdd-drill` (R5).
  - **Graceful degradation** — `specs/architecture.md` is **present** only when it exists
    **and** carries real content (not empty, not the untouched template stub); the ADR set
    is present only when `specs/adr/` holds ≥1 real `NNNN-*.md` (R7). If **absent** (legacy
    repo or `/sdd-new` altitude-3), note the absence and proceed from the brief alone — no
    fabricated citation, no failure, section not required (R8). Existing pre-F04 specs
    (without the section) remain valid; the rule applies only to specs written after F04
    (R9).
  - **Umbrella** — the ADR-citation rule applies to a shared umbrella `.spec.md` too (when
    the umbrella repo has architecture artifacts), **orthogonal to** the existing
    contract-artifact reference; slices follow the ADR set of the repo they live in (R10).
  - State the contract is portable (lives in the role file, runs on any AGENTS.md CLI)
    (R18).
- [ ] **T2** (R6) — Edit `specs/_templates/feature.spec.md`: add a `## Architecture
  alignment` section (between `## Business rules` and `## Acceptance criteria (EARS)`) that
  lists each touched `ADR-NNNN` + a one-line "how this honors it" and documents the
  `ADRs touched: none` fallback, so every new spec has a consistent, checkable slot.
- [ ] **T3** (R11, R12) — Amend `agents/reviewer.md` with a **new, additive** section
  (distinct heading, e.g. `## ADR-citation check (architecture-aligned specs)`): **where**
  `specs/architecture.md` + ≥1 ADR exist **and** the feature carries a four-file spec
  (`sdd: true`), confirm the `.spec.md` has a `## Architecture alignment` section citing ≥1
  `ADR-NNNN` or stating `ADRs touched: none` (R11); a **missing/empty** section is a
  **soft flag** for the Builder/Architect to justify, **not** a hard reject, and the clause
  **does not fire** for a legacy/no-architecture feature or an `sdd: false` brief-only item
  (R12). Place it **distinct from and non-overlapping with** F05's `## sdd: false items…`
  section (see `.plan.md` → F05 coordination).
- [ ] **T4** (R13) — Edit `docs/SPEC-FORMAT.md`: document the `## Architecture alignment`
  section and the cite-your-ADRs rule (cite touched `ADR-NNNN` when architecture artifacts
  exist; `ADRs touched: none` when nothing applies; graceful degradation when absent).
- [ ] **T5** (R14) — Edit `docs/WORKFLOW.md`: add a **new** `## Architecture-aligned specs
  (the Architect cites ADRs)` section placing the contract relative to `/sdd-plan`
  (produces `architecture.md` + ADRs) and `/sdd-drill` (records touched ADR ids in the
  brief). Keep it **distinct from** the existing `/sdd-plan`, `/sdd-drill`, and F05
  `/sdd-fix` sections (additive, non-overlapping — see `.plan.md` → F05 coordination).
- [ ] **T6** (R15) — Edit `README.md`: one-line note that feature specs cite the
  architecture decisions (ADRs) they touch, beside the existing SDD-contract / `/sdd-*`
  mentions.
- [ ] **T7** (R1–R19) — Create `tests/test_architect_adr.sh` per
  `F04-architect-adr-contract.tests.md` (POSIX sh; grep contract assertions over
  `agents/architect.md`, `agents/reviewer.md`, `specs/_templates/feature.spec.md`, and the
  three docs; one **temp-dir markdown** fixture for the `## Architecture alignment` shape;
  one **temp JSON store** fixture — carrying the required root `project` field — proving no
  schema change is needed; one `./init.sh` exit-0 run). Constraints: read `VERSION`
  dynamically (never assert a literal version), never `git diff` against `main`, zero new
  dependencies, never mutate the live `state/tasks.json` or any live spec.
- [ ] **T8** (wiring) — Edit `harness.config.yaml`: append `&& sh
  tests/test_architect_adr.sh` to `verification.test_command` and extend its trailing
  comment (e.g. `+ architect-adr`).
- [ ] **T9** (R19) — Bump `VERSION` by one MINOR (read the current value first; do not
  hard-code). Add a `CHANGELOG.md` entry under `## [<new version>]` describing the
  Architect ADR-citation contract, the `## Architecture alignment` template section, and
  the additive Reviewer clause.
- [ ] **T10** — Run `./init.sh` and the full `verification.test_command`; ensure green
  before hand-off. Do **not** change any status in `state/tasks.json` beyond the
  Orchestrator-owned transition for this feature, and do **not** touch any DO-NOT-TOUCH
  file (notably `agents/planner.md`, `agents/driller.md`,
  `specs/_templates/architecture.md`/`adr.md`, `store/tasks.schema.json`).
