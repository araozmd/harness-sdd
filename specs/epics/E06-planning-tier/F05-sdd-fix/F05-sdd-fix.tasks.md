# /sdd-fix lightweight lane (maintenance epic, brief-only intake) — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one at a
> time. Each task names the R-id(s) it satisfies. Check off when done.

- [x] **T1** (R1, R3, R4, R5, R6, R7, R8, R9, R10, R11, R14, R18) — Create
  `agents/fixer.md`, the portable Fixer role contract. It must state/specify:
  - It is the **brief-only intake** that seeds **one** `sdd: false` fix under the reserved
    maintenance epic and **hands it to the existing `sdd: false → Builder → Reviewer`
    loop**, written for any **AGENTS.md-compatible** CLI (portable, not Claude-specific)
    (R1, R18).
  - A short **adaptive Q&A** front-end presenting **at most 3 text-only** (markdown/ASCII)
    options where the fix's shape forks; **never images** (R3).
  - The lane **reuses the existing** `pending + sdd: false → Builder → Reviewer` routing
    (`agents/orchestrator.md` / `docs/WORKFLOW.md`) and introduces **no new Orchestrator
    routing rule, no new TaskStore status, and no `store/tasks.schema.json` change** (R4).
  - **Maintenance epic, create-on-first-use:** if epic `E99` is **absent**, create it with
    `id: "E99"`, slug `maintenance`, title `"Maintenance (hotfixes & minor fixes)"`,
    `status: "planned"`, `features: []`, and write `specs/epics/E99-maintenance/epic.md`
    (title + one-paragraph brief only — no feature spec) (R5).
  - **Reuse-by-id thereafter:** if epic `E99` is **present**, reuse that same epic
    (re-identified **by id `E99`**, not by marker or title); never create a second
    maintenance epic; never renumber/reorder existing fixes (R6).
  - The maintenance epic's status is a **selectable, non-`draft`** value (`planned`) so the
    F01 `next()` gate returns its fixes; never seed it (or any epic) as `draft` (R7).
  - **Fix seeding:** append one feature to `E99`'s `features` array with `sdd: false`,
    `status: "pending"`, a one-line `title`, a `spec_path`
    (`specs/epics/E99-maintenance/F<NN>-<slug>/`), and a fix `id` allocated next-sequential
    strictly **above** the epic's max existing `F##` (append-only, no reuse) (R8).
  - Stamp the fix **`autonomous: true` by default** (runs end-to-end, no per-feature
    spec-approval pause) and honor an explicit **`--gated` opt-out** that seeds it
    `autonomous: false`; reuse the existing `autonomous` flag — **no new approval
    mechanism** (R9).
  - Write **exactly one** fix-oriented inbox brief at `progress/inbox/<id>.md` (problem +
    intended fix + how to verify) from `specs/_templates/inbox-brief.md`; **never** create
    any feature `.spec.md`/`.plan.md`/`.tasks.md`/`.tests.md`, **never** create a
    `spec_path` directory, **never** spawn the Architect (brief-only, never a spec) (R10).
  - **Re-validate** `state/tasks.json` against `store/tasks.schema.json` (zero-dependency
    path) after the epic create and after the fix append; on failure, **report it and do
    not claim a successful seed** (R11).
  - After seeding + re-validation, **hand the seeded fix off to the existing `sdd: false →
    Builder → Reviewer` loop in-session** (do not stop at seeding), reusing the existing
    Orchestrator routing rather than re-implementing it; the Fixer itself writes no
    production code (R14).
- [x] **T2** (R2, R3, R14) — Create `.claude/commands/sdd-fix.md`: a slash-command wrapper
  that acts as **Fixer**, points at `agents/fixer.md` as the durable contract, reads the
  fix description from `$ARGUMENTS` (STOP and ask if empty), runs `./init.sh` first (STOP
  on non-zero), carries the **≤3 text-only options** rule (R3), seeds the `E99` fix,
  re-validates, then hands off to the existing `sdd: false` loop in-session (R14) — without
  writing any spec or spawning the Architect.
- [x] **T3** (R12) — Edit `agents/builder.md` (**additive**): add an `sdd: false` clause
  stating that, for an `sdd: false` item with no `tasks.md`, the Builder works from the
  inbox brief (`progress/inbox/<id>.md`) as its worklist and still writes at least one test
  proving the fix. Do **not** change the `sdd: true` four-file-spec path — it must read
  identically after the edit.
- [x] **T4** (R13) — Edit `agents/reviewer.md` (**additive**): add an `sdd: false` clause
  stating that, for an `sdd: false` item, the Reviewer verifies the fix behaviourally plus
  the fix's test, and that the R-id **traceability** check (its check #2) does **not apply**
  when there are no R-ids (a brief-only fix is not rejected for lacking an R-id↔test table).
  Do **not** change the `sdd: true` path.
- [x] **T5** (R15, R16) — Edit `harness-install.sh`: add a `cat >
  "$TARGET/.claude/commands/sdd-fix.md"` generation block (acts as **Fixer**, resolves the
  role against `.harness/agents/fixer.md`, carries `$ARGUMENTS`, runs `.harness/init.sh`
  first, ≤3 text-only options, seeds the `E99` fix, re-validates, hands off to the existing
  loop); add the `.opencode/command/sdd-fix.md` mirror `cp`; and extend the two "installed"
  `ok` lines to also mention `/sdd-fix`. (The Fixer **role** installs automatically via the
  existing `agents/` bulk copy — no per-file emit block needed.)
- [x] **T6** (R16) — Edit `tests/test_install.sh`: assert `.claude/commands/sdd-fix.md`
  exists, `grep -qF '.harness/agents/fixer.md'`, and `grep -qF '$ARGUMENTS'`; assert
  `.opencode/command/sdd-fix.md` exists and `cmp -s` equals the `.claude/` copy; assert
  `[ -f "$T/.harness/agents/fixer.md" ]` (role installed into the profile).
- [x] **T7** (R19) — Edit `docs/WORKFLOW.md`: extend the "Selective SDD (`sdd` flag)"
  section with a short "Lightweight fix lane (`/sdd-fix`)" note — `/sdd-fix` seeds an
  `sdd: false` fix under the reserved maintenance epic with only an inbox brief (no 4-file
  spec, no drill) and runs the existing `sdd: false → Builder → Reviewer` path; it adds no
  new status and no new routing.
- [x] **T8** (R20) — Edit `README.md`: add a one-line `/sdd-fix` description (the
  lightweight fix lane) beside the existing `/sdd-new` / `/sdd-plan` / `/sdd-drill` /
  `/sdd-next` mentions.
- [x] **T9** (R1–R21) — Create `tests/test_sdd_fix.sh` per `F05-sdd-fix.tests.md` (POSIX
  sh; grep contract assertions over the role/command/builder/reviewer/docs + one python
  fixture that seeds a synthetic `sdd: false`, `autonomous: true` fix inside a `planned`
  `E99` maintenance epic — with the required root `project` field — into a TEMP store and
  asserts it validates against `store/tasks.schema.json` + one `./init.sh` exit-0 run).
  Constraints: read `VERSION` dynamically (never assert a literal version), never `git
  diff` against `main`, zero new dependencies, never mutate the live `state/tasks.json`.
- [x] **T10** (wiring) — Edit `harness.config.yaml`: append `&& sh tests/test_sdd_fix.sh`
  to `verification.test_command` and extend its trailing comment (e.g. `+ sdd-fix`).
- [x] **T11** (R21) — Bump `VERSION` by one MINOR (read the current value first; do not
  hard-code). Add a `CHANGELOG.md` entry under `## [<new version>]` describing `/sdd-fix`,
  the maintenance-epic convention, the brief-only `sdd: false` seeding, and the additive
  Builder/Reviewer clarifications.
- [x] **T12** — Run `./init.sh` and the full `verification.test_command`; ensure green
  before hand-off. Do **not** change any status in `state/tasks.json` beyond the
  Orchestrator-owned transition for this feature, and do **not** touch any DO-NOT-TOUCH
  file (especially `agents/orchestrator.md`, `store/tasks.schema.json`, and the `sdd: true`
  path inside `agents/builder.md` / `agents/reviewer.md`).
