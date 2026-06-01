# Inception role + /sdd-new intake — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom,
> one at a time. Each task names the R-id(s) it satisfies. Check off when done.

- [x] **T1** (R1, R8, R10, R11, R12, R13) — Create `agents/inception.md` skeleton in
  the house style of `agents/*.md`: title "Agent: Inception (the Intake)", a "What you
  do / never do" framing. State the guardrails up front: seeds-never-specs (no
  `.spec/.plan/.tasks/.tests`, no EARS/plan), only ever `status: pending`, never
  advance status, never touch `tasks.schema.json` / `agents/orchestrator.md` /
  `agents/architect.md`, no new status value.
- [x] **T2** (R8, R9, R10) — In `agents/inception.md`, write the triage decision tree:
  inspect `state/tasks.json`, resolve to exactly one altitude (new task on existing
  not-`done` feature / new feature under existing epic / new epic). Specify
  next-sequential id allocation (epics project-wide, features within the epic) and the
  no-reuse-of-vacated-ids rule. For "new epic", create the epic entry + a
  `specs/epics/<epic-slug>/epic.md` + first `F01`.
- [x] **T3** (R3) — In `agents/inception.md`, specify the TaskStore write: a `pending`
  feature entry with `id`, `title`, `status: "pending"`, `sdd`, `autonomous`,
  `depends_on`, `spec_path` (= `specs/epics/<epic-slug>/F<NN>-<slug>/`).
- [x] **T4** (R6, R7) — In `agents/inception.md`, mandate post-write re-validation of
  `state/tasks.json` against `store/tasks.schema.json` (reuse the `python3` check from
  `store/local.md`), and require that a validation failure be reported as a
  non-success (no "seeded" claim left with an invalid TaskStore).
- [x] **T5** (R4, R5) — In `agents/inception.md`, specify the intent-brief write to
  `progress/inbox/<feature-id>.md` (filename == the new entry's `id`), with frontmatter
  (`feature`, `seeded_by: inception`, `date`) and the body sections (problem/who,
  success outcome, scope/boundaries, chosen options, constraints, open questions).
  Reference `progress/inbox/E04-F01.md` as the canonical brief template.
- [x] **T6** (R14) — In `agents/inception.md`, constrain option/mockup presentation to
  text (markdown/ASCII) only and at most 3 options.
- [x] **T7** (R15) — In `agents/inception.md`, specify the completion report: print the
  new `<feature-id>`, the tasks.json entry, the `progress/inbox/<feature-id>.md` path,
  and tell the human to run `/sdd-next` next. State explicitly that Inception does NOT
  spawn the Architect or change status.
- [x] **T8** (R2, R14, R15) — Create `.claude/commands/sdd-new.md` mirroring
  `.claude/commands/sdd-next.md`: YAML frontmatter `description:`, "Act as **Inception**
  (`agents/inception.md`)", accept the free-text idea via `$ARGUMENTS`, carry the
  interactive adaptive Q&A and the ≤3 text-only options, and defer the durable contract
  to the role file. End by reporting the seed + "run /sdd-next".
- [x] **T9** (R16) — Edit `AGENTS.md`: add Inception to the role list / `agents/*.md`
  row so the entrypoint names the intake role. Single additive line; do not restructure
  the file.
- [x] **T10** (R16) — Edit `docs/WORKFLOW.md`: add a short pre-`pending` intake step
  showing `/sdd-new` (raw idea → `pending` entry + `progress/inbox/<id>.md`) feeding the
  existing state machine. Additive; do not alter the existing state diagram's states.
- [x] **T11** — Write the verification script and manual-walkthrough doc per
  `inception.tests.md` (static file/format/grep assertions in the style of
  `tests/test_install.sh`, plus the documented `/sdd-new` walkthrough).
- [x] **T12** — Run `./init.sh` and the new verification script; ensure green before
  hand-off.
- [x] **T13** (process, not an R-id) — Bump `VERSION` by a **MINOR** increment (✨) per
  `CLAUDE.md` (this PR changes the installed body — `agents/` + `.claude/` glue + docs).
- [x] **T14** (process, not an R-id) — Add a `CHANGELOG.md` entry for the Inception role
  + `/sdd-new` intake under the new version, and tag the merge commit `vX.Y.Z` (PR
  step).
