---
id: E05-F01
title: Reviewer cross-file consistency + explicit build↔review rounds
epic: E05-observability
status: done              # pending → spec-ready → in-progress → in-review → done
sdd: true                 # false = quick task, skip full SDD
autonomous: true          # pre-approved in-session by the human at intake
depends_on: []
owner: araozmd
---

# Reviewer cross-file consistency + explicit build↔review rounds — Functional Spec

## Context
The in-loop Reviewer (`agents/reviewer.md`) serves the Orchestrator's `in-review`
phase. It is handed a curated, minimal set of feature files and anchors on tests
passing, so it is strong at spec→test traceability but blind to **cross-file
consistency**: a change to one role/contract/prose file can silently violate a
precondition declared in an *unchanged* file it invokes, and no test fails. On
PR #10 the external reviewer (Codex) caught exactly this — a new in-session
dispatch step added to `agents/orchestrator.md` told the Builder to open a child
repo's PR, contradicting `agents/builder.md`'s Loop A precondition ("Builder never
opens a PR; it only reports completion"). The harness maintainer wants the in-loop
Reviewer to catch this class itself, and wants the build↔review iteration made an
explicit, named, multi-round loop (per Anthropic's long-running-harness guidance:
the evaluator sends specific feedback and several build↔review rounds run until
green).

This feature edits **prose only** — two role files (`agents/reviewer.md`,
`agents/orchestrator.md`) plus any wording in `AGENTS.md`/docs needed for
coherence. It does not change the schema, add a status value, or build telemetry
(that is E05-F02), and it does not replace the external `/pr-loop` (Codex) pass,
which stays an independent layer.

## Business rules
- The Reviewer expands context to the **collaborators the diff references**, not the
  whole repo. Scoped expansion, curate-don't-dump — never a context dump.
- A cross-file inconsistency is a **hard reject only when a precondition is provably
  violated** by the change (a contradiction is demonstrable from the two files'
  text). Otherwise — when consistency is uncertain or unverifiable from the loaded
  collaborators — the Reviewer **flags it for justification** rather than blocking.
  (Resolves open question 1.)
- The build↔review loop is multi-round: a reject produces actionable, file-based
  feedback, returns the feature to `in-progress`, the Builder addresses it, and the
  feature is re-reviewed — repeating until green, with each round recorded.
- `agents/*.md` is installed body, so this feature requires a `VERSION` bump
  (MINOR ✨, 0.5.0 → 0.6.0) and a `CHANGELOG.md` entry.
- The verification for this prose-only change is the lightweight **role-content
  assertion** pattern (grep the role file to assert a required clause exists), as in
  `tests/test_inception.sh`. (Resolves open question 2: yes, a small test is
  warranted.)

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

### Reviewer — cross-file consistency check

- **R1** — `agents/reviewer.md` shall define a **cross-file consistency** check as a
  named item in its "What you check" list.
- **R2** — Where a change under review touches a role/contract/prose file, the
  cross-file consistency check shall direct the Reviewer to load the **collaborators
  the change references** (the unchanged files the diff invokes), not only the
  curated feature files.
- **R3** — `agents/reviewer.md` shall state that the collaborator expansion is
  **scoped to the diff's references** (curate-don't-dump), not a whole-repo context
  dump.
- **R4** — The cross-file consistency check shall require the Reviewer to verify the
  change's **preconditions are satisfied by, and do not contradict, the contracts it
  invokes** in those collaborator files.
- **R5** — If a precondition is **provably violated** by the change (a contradiction
  demonstrable from the loaded files), then the Reviewer shall **reject** (hard
  reject).
- **R6** — Where a cross-file inconsistency is **suspected but not provably violated**
  from the loaded collaborators, the Reviewer shall **flag it for the Builder to
  investigate and justify** rather than hard-rejecting.
- **R7** — `agents/reviewer.md` shall include the **PR #10 worked example**
  (a new in-session dispatch step in `orchestrator.md` contradicting `builder.md`'s
  Loop A precondition that the Builder never opens a PR) as the canonical illustration
  of the cross-file consistency check.

### Build↔review multi-round loop

- **R8** — `agents/reviewer.md` shall state that a reject produces **specific,
  actionable, file-based feedback** (the contradicting files and the expected vs.
  actual behavior), not vague disapproval.
- **R9** — `agents/orchestrator.md` shall make the build↔review loop **explicit and
  multi-round**: reject → actionable file feedback → `in-progress` → Builder
  addresses → re-review, repeating **until green**.
- **R10** — `agents/orchestrator.md` shall state that each build↔review **round is
  recorded** (an entry per round) so the iteration is observable.

### Coherence & versioning

- **R11** — Where `AGENTS.md` or `docs/` describe the review phase, that wording
  shall remain coherent with the multi-round build↔review loop (no doc states review
  is a single pass).
- **R12** — `VERSION` shall be bumped MINOR (0.5.0 → 0.6.0) and `CHANGELOG.md` shall
  carry an entry for this feature, because this feature changes the installed body
  (`agents/*.md`).
- **R13** — This feature shall not change `store/tasks.schema.json`, shall not add or
  alter any feature `status` value, and shall not modify the Builder/Architect role
  contracts (`agents/builder.md`, `agents/architect.md`); the five-value status enum
  remains unchanged.

## Out of scope
- Telemetry / duration capture (that is E05-F02).
- Replacing or modifying the external `/pr-loop` (Codex) pass — it stays independent.
- Any schema change, new status value, or change to `agents/builder.md` /
  `agents/architect.md`.

## Open questions
- Both intake open questions are resolved in this spec (R5/R6 hard-reject-when-proven
  vs. otherwise-flag; R1+test traceability for the role-content assertion test).
  None remain for the human gate.
