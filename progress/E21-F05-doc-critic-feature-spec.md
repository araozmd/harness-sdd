# Doc-critic — `feature-spec` — E21-F05

- **target-type:** `feature-spec`
- **Files reviewed:** `specs/epics/E21-change-size-discipline/F05-stacked-pr-doctrine/E21-F05.{spec,plan,tasks,tests}.md`
- **Context read:** `progress/inbox/E21-F05.md`, `specs/epics/E21-change-size-discipline/epic.md`,
  `specs/epics/E21-change-size-discipline/F04-stacked-pr-lane/*`, `docs/WORKFLOW.md` (lane at
  516–597), `tools/pr-stack-guard.sh`, `.claude/commands/sdd-pr-loop.md`, `harness-install.sh`
  (`HARNESS_BODY_PROSE` 668/736/2282; restack pointer 3966; guard block 4495–4552),
  `agents/builder.md`, `agents/orchestrator.md`, `agents/reviewer.md`, `agents/architect.md`,
  `harness.config.yaml`, `store/local.md`, `store/tasks.schema.json`, `tests/test_pr_loop.sh`.
- **Posture:** advisory. **No edit was made to the four spec files.** The Architect/Orchestrator
  applies fixes.

## Verdict

**Not ready for the human approval gate as written.** The doctrine, the three carried decisions
and the scope boundary are sound; the failure is in the *test contract*, which is this feature's
whole answer to "how does a doctrine statement get a test". Three of its assertions are broken or
satisfiable without the requirement being met — verified by execution, not inspection.

## Findings (20)

Priority order; full text with quotes and recommended fixes returned to the caller.

1. **F1 (blocking)** — `sect()` truncates at `#`-prefixed comment lines inside fenced code
   (`/^#+ /`). Verified: `sect docs/WORKFLOW.md '### Creating stacked increments'` yields 5 lines
   and a `gh pr create` count of **1** against a section that contains **three**. R4's flagship
   count assertion is therefore satisfied by renaming the heading alone. R6's fenced content is
   exposed to the same truncation. `span()` (`/^## /`) is unaffected — verified, 82 lines, catches
   the `atomic` token today.
2. **F2** — F05 supersedes E21-F04's shipped **R6** (the "not atomic delivery" sentence, the
   wave-boundary guidance) and **R8** (the "no stacking documentation is stamped" claim) and
   renames R7's heading, while asserting "It changes **no** F04 behavior". No supersession record.
   (No test conflict: F04's `test_stacking_inert_when_disabled` asserts only the absent command.)
3. **F3** — anchor `ships with the body` vs the prose the plan/tasks prescribe,
   "ships with the **harness** body". A Builder following T7 fails R10.
4. **F4** — `set -eu` + `n="$(… | grep -c …)"` aborts the whole suite on **zero** matches.
   Verified `rc=1` under `/bin/sh`. That is the happy path for R9's `atomic` ban and R8's
   `"increments"` guard.
5. **F5** — R7 names no source of truth for "is this the last increment?", and the new
   orchestrator section contradicts `agents/orchestrator.md:245` ("**Approve** → `done`") and
   `agents/reviewer.md:176` in the same breath.
6. **F6** — `wave` survives as seam vocabulary (lane opening, `feat/wave-N` examples, the restack
   body kept *verbatim*) while R3 forbids a second vocabulary; the test bans only `wave structure`.
7. **F7** — the entry condition and the not-served case are stated **twice** inside
   `docs/WORKFLOW.md` (opening paragraph + `### When to use what` vs the new `### Entry condition`),
   with different alternative sets. No task touches the opening paragraph.
8. **F8** — `tools/pr-stack-guard.sh:5-7` (installed body, DO NOT TOUCH) restates the doctrine
   *including* the banned denial sentence, so R9's "exactly one place" is false on ship day and the
   ban's scope list omits it.
9. **F9** — `install_at()` sandboxes `CODEX_HOME` only, not `HOME`; the plan/tests cite it as the
   model for both.
10. **F10** — plan says "New dependencies: none"; tests.md mandates `python3 -c` for R8 with no
    skip-if-missing guard.
11. **F11** — R1's anchors do not discriminate the *safety* condition (`default branch` is generic,
    `before` is vacuous) — the condition whose violation withdrew the predecessor.
12. **F12** — tests.md R7 overclaims: "a new status value would not be reachable by these two".
13. **F13** — R6's discovery path does not exist; the loop's headline message misdiagnoses the
    unowned-base branch; "undocumented anywhere" is false (guard header 25–27).
14. **F14** — spec R4 "at most one" vs test "exactly 1" for `docs/WORKFLOW.md`.
15. **F15** — the brief's in-scope "reusing E21-F01's wave boundaries" is correctly replaced by
    `depends_on`, but the correction is buried in the plan, not surfaced in Open questions.
16. **F16** — T13 mandates a mutation check for every R-id; R8's can only be mutated inside
    DO-NOT-TOUCH `store/tasks.schema.json`.
17. **F17** — R10 duplicates F04's absent-command assertion, adding a second full installer run.
18. **F18** — `WF` shorthand collides with the R10 case's "read the installed copy" rule.
19. **F19** — R9's shim assertion is a trivially-passing regression guard, not declared as such
    (unlike R8's), and covers only `.claude/agents/`.
20. **F20** — R5's literal `^### Restack procedure$` freezes a heading the derived assertion
    already covers non-brittly.

## Dimensions that are clean

- **Atomicity language.** No surviving atomicity claim, in any form, in the four spec files — only
  meta-references to the ban. Decisions #1–#3 of the brief are all carried; #2's deviation is
  surfaced in *Open questions* for the gate, not smuggled. Residual risk is in the *shipped* prose
  only (F6/F7/F8).
- **Test anti-patterns.** No `VERSION` freeze, no diff against `main`. Prohibited in four places
  (spec Non-functional, plan Anti-patterns, T12, tests Non-functional).
- **Budget & traceability.** 10 R-ids ≤ `max_requirements: 12`; every R-id has ≥1 task and exactly
  one test row. (Vacuity is F1/F11, not coverage.)
- **Mirror drift.** `.claude/agents/*.md`, `.codex/agents/*.toml`, `.gemini/agents/*` and
  `opencode.json` are pointer stubs by construction; T11's "no edit at all" is correct. Cite-don't-
  copy is enforced by the `verification.test_command`-absence assertion. Only F8 breaches it.
- **Scope.** Nothing re-implements F04's mechanism; DO-NOT-TOUCH covers guard, loop, schema,
  selector, adapters and every shim. The only scope defect is the unrecorded supersession (F2).
- **Plan's factual claims about the repo.** All spot-checked claims hold except those in F9, F10
  and F13. Independently re-verified: `HARNESS_BODY_PROSE` is unconditional; the installer's
  `'Restack procedure'` pointer resolves to nothing today (derivation sed returns
  `Restack procedure`, only occurrence); E21-F01 contains **zero** occurrences of "wave";
  `merged` and `done-but-unmerged` are slice-scoped with no feature-level equivalent.
