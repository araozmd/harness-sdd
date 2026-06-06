# Reviewer cross-file consistency + explicit build↔review rounds — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. This is a **prose-only** change: two role files plus a coherence pass and
> a lightweight role-content-assertion test. No production code.

## Stack & dependencies
- Language/framework: none — Markdown role prompts + a POSIX `sh` test (grep-based),
  matching the `tests/test_inception.sh` precedent.
- New dependencies: none (POSIX sh + grep; the test must run with zero deps).

## Files to change  (serves: R#)

| File | Change | R-id |
|---|---|---|
| `agents/reviewer.md` | Add a new numbered item to the "What you check" list: **Cross-file consistency**. For any change to a role/contract/prose file, load the *collaborators the diff references* (the unchanged files it invokes) and verify the change's preconditions are satisfied by — and do not contradict — the contracts in those files. State the expansion is scoped to the diff's references (curate-don't-dump), not a whole-repo dump. | R1, R2, R3, R4 |
| `agents/reviewer.md` | In the same item, state the verdict rule: **hard reject** when a precondition is *provably violated*; otherwise **flag for the Builder to investigate and justify**. | R5, R6 |
| `agents/reviewer.md` | Add the **PR #10 worked example** inline in the cross-file item: a new in-session dispatch step in `orchestrator.md` told the Builder to open a child PR, contradicting `builder.md` Loop A's precondition that the Builder never opens a PR — a contradiction with no failing test, exactly what this check catches. | R7 |
| `agents/reviewer.md` | In the "Be honest, not generous" / "Verdict" area, reinforce that a reject emits **specific, actionable, file-based feedback** (the contradicting files + expected vs. actual). (The file already says "specific, actionable"; extend it to name the cross-file case and the file-based feedback artifact `progress/<run>/review.md`.) | R8 |
| `agents/orchestrator.md` | In the `in-review` row of the routing table and/or a short "Build↔review rounds" note, make the loop **explicit and multi-round**: reject → actionable file feedback → `in-progress` → Builder addresses → re-review, **repeating until green**, with **each round recorded** (extend the existing "append a one-line entry to `progress/history.md`" to record per-round). | R9, R10 |
| `AGENTS.md` and/or `docs/WORKFLOW.md` | Coherence pass: ensure no wording presents review as a single pass; align it with the multi-round loop. Edit only if an existing sentence contradicts R9 (minimal touch). | R11 |
| `VERSION` | Bump `0.5.0` → `0.6.0` (MINOR ✨ — new backward-compatible capability in the installed body). | R12 |
| `CHANGELOG.md` | Add a `## [0.6.0]` section describing the cross-file consistency check + explicit build↔review rounds. | R12 |
| `tests/test_reviewer.sh` | **Create** a new role-content-assertion test (POSIX sh + grep), mirroring `tests/test_inception.sh`: greps `agents/reviewer.md` and `agents/orchestrator.md` for the required clauses, and asserts the DO-NOT-TOUCH invariants (status enum unchanged in the schema). | R1–R13 |

## Approach notes
- **Scoped expansion, not a dump (R3).** The wording must keep the Reviewer's
  curated-context discipline: it loads only the files the *diff references*, e.g. if
  the diff edits `orchestrator.md` and that edit invokes Builder Loop A, the Reviewer
  loads `builder.md` — not the entire `agents/` tree.
- **Hard-reject threshold (R5/R6).** "Provably violated" = the contradiction is
  demonstrable by quoting the two files (a stated precondition vs. the change that
  breaks it). Anything softer (a *possible* tension that cannot be confirmed from the
  loaded collaborators) is a **flag**, so the Reviewer never blocks on a guess.
- **Worked example is load-bearing (R7).** Cite PR #10 concretely so the rule is
  unambiguous: `orchestrator.md` dispatch step → "open the child repo's PR" vs.
  `builder.md` Loop A → Builder reports completion, never opens a PR.
- **Multi-round recording (R10).** Keep it lightweight — one history line per round
  (e.g. `in-review → reject (round N)` / `in-review → approve`). Do **not** add a
  schema field or a new status; rounds are recorded in the existing `progress/`
  history, not in the TaskStore.
- **Test stays static (R1–R11).** The behavioral end-to-end (the Reviewer actually
  catching a planted contradiction) is a documented manual check in the `.tests.md`;
  the automated guard is grep-based role-content assertions, the right lightweight
  guard for a prose change.

## DO NOT TOUCH
- `store/tasks.schema.json` — the status enum (`"pending", "spec-ready",
  "in-progress", "in-review", "done"`) is a permanent invariant; no new status value
  may be added. (R13)
- The feature **status enum / state machine** — this feature adds no status. (R13)
- `agents/builder.md` — its Loop A preconditions (Builder never opens a PR) are the
  *contract being protected*; do not alter them. (R13)
- `agents/architect.md` — out of scope; not edited by this feature. (R13)
- The external `/pr-loop` / Codex layer (`.claude/` skills/commands for PR review) —
  it stays an independent layer; this feature only strengthens the in-loop Reviewer.
