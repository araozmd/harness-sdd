---
id: E21
title: "Change-size discipline: keep the review a gate"
status: done             # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E21 — Change-size discipline: keep the review a gate

## Business brief
The harness has no opinion about how large a feature may be. `agents/driller.md` decomposes
an epic into features and `agents/architect.md` writes the four-file spec; neither mentions
size, and nothing downstream measures it. Feature size is therefore decided implicitly, at
drill time, hours before anyone sees a diff — and never revisited.

A target repo (`viernes-ai/viernes-bookings-api` PR #76, E14-F05) shows where that leads. One
feature carried R1–R36 and T1–T25 and produced a single PR of **17,202 additions / 77 files /
40 commits** — 43× that repo's median PR (396 additions) and 2.5× its next largest.

The failure mode is not "the PR was big and slow". It is that **the review never converged**.
Blocking findings per round, across twelve `@codex review` rounds and 10h45m:

```
R1  R2  R3  R4  R5  R6  R7  R8  R9  R10 R11 R12
 1   3   1   2   1   3   1   2   2   1   2   1     ← 20 P1 + 15 P2 = 35 findings
```

The P1 rate is flat. At ~260k tokens of diff a review pass stops being an exhaustive gate and
becomes a *sample*: each round covers a different region and finds new real bugs. A clean
round would have been indistinguishable from a round that happened to sample a quiet region —
so the merge signal the whole SDD loop depends on had silently stopped meaning anything.

Two further measurements shape the response:

- **Risk concentrates; review cost does not.** `runtime.ts` was 924 added lines (5.4% of the
  diff) and drew 11 of the 33 file-anchored findings (33%). Three files — 1,716 lines, 10% of
  the diff — drew 22 (67%). The remaining ~15,500 lines drew 11. Every round paid full price
  to re-read all of it.
- **Cost.** ~260k input tokens per full-diff pass × 12 rounds ≈ **3.1M tokens for review
  alone** — a floor that excludes the file context the reviewer pulls in and all 40 commits of
  builder work.

The lever is upstream. Once a 17k-line branch exists, every option is bad; the cheap fix is to
never let the *unit of work* get there. This epic bounds the delivery unit where it is actually
chosen (F01), measures it at the one point where it can still be acted on before a reviewer is
paid (F02), makes non-convergence legible instead of inviting more rounds (F03), and — originally — gave a
genuinely atomic feature a way to ship reviewably anyway (F04). **F04 was withdrawn during
review; see Notes.**

## Why this is not "adopt micro-specs"
The [micro-specs pattern](https://www.augmentcode.com/guides/micro-specs-pattern-ai-agent-test-coverage)
— atomic single-behavior specs, one `When` clause each, one mandated test per spec, organised
into dependency waves — is the obvious candidate. **The harness already implements it.** An
EARS `R-id` in a `.spec.md` *is* a micro-spec; `agents/reviewer.md` already enforces a passing
test per `R-id`; `depends_on` already models the DAG and `/sdd-fix-parallel` already runs waves.

E14-F05 was not under-micro-specced. It had **36** of them, each with tests, each guarantee
dying to its own mutation. Requirement-level atomicity worked exactly as advertised — and
produced an unreviewable PR anyway, because **nothing maps a micro-spec to a deliverable**.
Thirty-six micro-specs collapsed into one branch, one PR, one review surface.

So the gap is one layer up: the harness has no rule for **grouping micro-specs into shippable
increments**. That is what this epic adds, and it borrows the pattern's own DAG/wave vocabulary
to do it — applied to *delivery* rather than to parallel authoring.

Two things from the pattern are deliberately **rejected**:

- **Universal application.** The pattern's own guidance is selective — "for simple CRUD paths
  with few branching conditions, the overhead rarely justifies the structure". Our measurement
  agrees: 10% of PR #76's files drew 67% of the findings. Risk is concentrated, so ceremony
  should be too.
- **More spec ceremony as the answer.** Birgitta Böckeler's
  [survey of SDD tools](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)
  records the failure mode directly: a small bug fix became "4 user stories with 16 acceptance
  criteria" — "a sledgehammer to crack a nut" — and reviewers concluded "I'd rather review code
  than all these markdown files". Adding markdown does not shrink a diff. This epic adds a
  grouping rule and a measurement, not another authoring phase.

## Success criteria (epic level)
- A feature whose brief implies work beyond the budget is **split at drill time**, by a rule
  written in the Driller, not by anyone's judgement on the day.
- The Architect refuses to spec a feature it can see is over budget, and says so, rather than
  emitting a 36-requirement spec. A requirement count is a first-class size signal, because an
  `R-id` is the harness's micro-spec and each one costs a test.
- The branch's actual change size is measured and surfaced **before** the PR is opened — the
  last moment splitting is still cheap.
- A PR that reaches the `/sdd-pr-loop` round cap while its blocking-finding rate is *flat*
  reports "split this PR", not "review it again". The trend is shown, not asserted.
- ~~A feature that genuinely cannot be split into independently-mergeable PRs can still be
  reviewed in budget-sized increments.~~ **Withdrawn with F04** — the mechanism proposed for it
  (stacked PRs) delivers incremental *review*, not atomic delivery, so it never satisfied this
  criterion. The criterion itself stands as an open problem; nothing in this epic meets it.

## Success criteria — non-goals
- **No hard wall.** The budget is two soft tiers (advise / escalate) that produce a *recorded
  decision*, never a refusal to open a PR. A single hard cap is the wrong instrument twice
  over: an agent-written change is legitimately denser than a hand-written one, and a rename
  sweep, a generated contract or a vendored file can be thousands of lines at near-zero review
  risk per line. The defaults are calibrated from one 60-PR sample and live in config so a repo
  with a different test ratio can move them.
- **No line-counting of tests as a defect.** Tests were 59% of PR #76 and that is a deliberate
  quality choice. The budget is expressed in *production* lines, with tests following.
- Not a change to how Codex is invoked, or to `pr_loop.blocking_severities` / `max_rounds`
  semantics. F03 adds reporting and a message at the cap; it does not change when the cap fires.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Feature-size budget in the Driller and Architect (split at decomposition time) | done | true | — |
| F02 | Pre-PR change-size check on the Reviewer → PR handoff | done | true | E21-F01 |
| F03 | `/sdd-pr-loop`: per-round finding trend + "split, don't re-review" at the round cap | done | true | E18-F01 |
| F04 | Stacked-PR lane for an atomic feature that exceeds the budget | done (re-spec'd as **merge-order safety**) | true | E18-F01, E21-F03 |
| F05 | The stacked-PR lane's doctrine document | pending (gated) | true | E21-F04 |
| F06 | The increment contract: delimitation, ownership, review scope | pending (**parked — DECIDED NO, 2026-08-17**; superseded by F07, will not be built) | true | E21-F05 |

## Notes
- **F04 was withdrawn during review of PR #78 (2026-07-28).** Its premise was wrong. The lane
  claimed a stacked feature "lands atomically with respect to `main`"; it does not — merging
  increment A publishes wave 1 while B and C are still open. Stacking buys incremental
  **review**, never atomic delivery, so it does not solve the case F04 was seeded for: a
  capability whose intermediate states are unsafe. That needs a feature flag or an aggregate
  landing strategy, and remains **unsolved**.

  Four `@codex review` rounds produced **five blocking findings, every one of them on F04's
  surface**, each largely created by the previous round's fix — a cascade, not a review that
  needed more rounds. F01/F02/F03 and E99-F06 produced zero blocking findings on their own
  surface. Per this repo's rule, a finding that contradicts approved architecture goes back
  through the human gate as a re-spec rather than a pr-fixer patch, so F04's implementation was
  removed from PR #78 and the feature re-gated to `autonomous: false`.

  The one genuinely valuable artifact — `tools/pr-stack-guard.sh`, a tested offline merge-order
  guard — is recoverable from git history (`git show 1873af9:tools/pr-stack-guard.sh`) if the
  re-spec keeps a stacked lane. It was removed rather than kept because without the lane it has
  no caller.

  **Resolved (2026-07-29).** The re-spec went back through the human gate and chose lane (a):
  stacking is a **review-size tool** for work that is *already safely splittable*, never a
  delivery-atomicity mechanism. At that scope the feature specced to **19 R-ids** against
  `change_size.max_requirements: 12`, so the Architect stopped and reported the seam — E21-F01's
  own budget applied to E21-F01's own epic. The split follows the review history: every blocking
  finding had landed on the **claim/doctrine** surface, while the guard was independently sound.
  So the mechanism shipped first and alone as **F04** (merged PR #86, `tools/pr-stack-guard.sh`
  restored with a caller), and the doctrine behind it became **F05**.
- **F05 is gated (`autonomous: false`) on purpose.** Its surface is exactly where all five of
  PR #78's blocking findings landed, so it does not skip the human spec-approval gate. Its
  intent brief is `progress/inbox/E21-F05.md`, salvaged from the abandoned PR #81 — that PR's
  F04 specs were superseded by the re-spec merged as #86, but the F05 brief had never landed
  anywhere and would have been lost when #81 was closed.

- **F05 was re-drilled on 2026-08-13 and split into F05 + F06 — the SECOND time this epic's own
  budget rule fired on this epic.** Specced completely, F05 came to **13 R-ids** against
  `change_size.max_requirements: 12`, so the Architect stopped and reported the seams rather
  than emitting an over-budget spec.

  Codex's round-1 review of PR #129 returned **three P1 findings**, all verified against the
  cited files and none disputed — and **all three, plus every role-file contradiction, lived in
  the increment contract**: the spec told the **Builder** to open an increment's PR (which
  `agents/reviewer.md:34-38` uses as its *worked example* of a contract violation and says to
  hard reject); it left **no path for the Reviewer to approve a non-final increment**, since the
  traceability rule rejects until every `R-id` has a passing test and the approve verdict sets
  the whole feature `done`; and it named **`depends_on` as the seam rule**, which sequences
  *sibling board features* and therefore cannot delimit increments inside one feature.

  **None of the three touched the doctrine.** So the cut follows the findings, exactly as it did
  for F04 — with the halves reversed. There the mechanism was independently sound and the
  doctrine burned; here the doctrine is sound and the contracts burn. **F05** keeps its id and
  narrows to the doctrine document (`docs/WORKFLOW.md` only, ~6 R-ids); **F06** carries the
  increment contract (~7 R-ids, four role files) and depends on F05.

  **F05 ships regardless of what happens to the lane**, which is why it was kept first: the lane
  section currently states things that are *false on `main`* — that no stacking documentation is
  stamped when the loop is disabled (`HARNESS_BODY_PROSE` copies `docs/` unconditionally), a
  pointer to a `'Restack procedure'` heading that does not exist, and a citation to a "wave
  structure" that E21-F01 never defined. Even a decision to *deprecate* the lane needs that
  section to read accurately first.

- **F06 is seeded and PARKED — the board has the vocabulary for exactly this.**
  `store/tasks.schema.json` defines a feature-level `parked` object (`reason`, optional
  `unblocked_by`), and `featureBlockers()` in `tools/next-task.mjs` emits a `parked` blocker
  and never selects the feature **while leaving `featureRoute` untouched, so unparking restores
  the prior routing exactly**. Verified: `node tools/next-task.mjs --feature E21-F06` reports
  `parked` with `[route when unparked: architect]`.

  This corrects an earlier claim in this file that the board had no park vocabulary. It does.
  Un-seeding F06 on that mistaken basis would have removed the follow-up from the TaskStore
  entirely, so `/sdd-next` could never surface this half of the split and the decision could
  have been silently forgotten — which is the failure the park exists to prevent.

  Seeding it *unparked* would have been the opposite error: `next-task.mjs` returns any
  `pending`/`sdd: true` feature whose `depends_on` is met, so the moment F05 reached `done` it
  would have routed F06 to the Architect — while F06's brief says do not spec it until the
  product decision is answered. `autonomous: false` cannot supply that gate, because the human
  gate fires at `spec-ready`, i.e. *after* the spec the brief says not to write.

  **Release condition** (recorded in the park's `unblocked_by`): answered *yes* ⇒ unpark and the
  routing resumes; answered *no* ⇒ replace it with a small feature that deprecates the lane in
  `docs/WORKFLOW.md` — which F05 will already have made accurate — and decides what becomes of
  `tools/pr-stack-guard.sh`. Note the residual: a park says *not yet workable*, not *declined*;
  the status set still has no terminal disposition for a feature the project decides against,
  which is the same gap that made re-spec-in-place the right call for F05 above.

- **The question F06 waits on, and it decides whether F06 exists at all.** The **sibling-feature
  model already delivers budget-sized reviews** — this epic's actual goal — with zero new
  machinery, via the `depends_on` split F01 already specifies. Stacking adds exactly one thing
  over it: **wall-clock overlap**. And the corollary cuts the other way: under siblings *no PR
  ever targets a non-default base*, so `tools/pr-stack-guard.sh` never fires and **F04's merged
  mechanism has no caller** — the state it was withdrawn for once already. Whether that
  serialisation is worth a delimiter convention, four role contracts, a manual restack burden
  and a merge-order guard is a **product judgement**, recorded here rather than settled by an
  Architect.

- **The board decision (no `increments[]`) is under pressure and was deliberately NOT reversed.**
  Adding it would make the delimiter, the review scope and the `done` trigger directly
  expressible and would likely bring F06 under budget — but it duplicates ~80% of `slices[]`
  across `store/tasks.schema.json`, `store/local.md`, both mirror adapters,
  `tools/sync-board.mjs` and `tools/next-task.mjs`, and selection is *code* now (**ADR-0001**),
  so it lands in the surface that ADR exists to protect. Reversing it is a **re-drill**, not a
  spec edit.
- **Ordering.** F01 defines the budget; F02 consumes it, so F02 depends on F01 to avoid two
  sources of truth for the same numbers. F03 and F04 edit `/sdd-pr-loop` glue that **E18-F01
  has not merged yet** — they are correctly blocked, and must not be started against a `main`
  where `.claude/commands/sdd-pr-loop.md` does not exist.
- **The budget belongs in `harness.config.yaml`, not in a prompt.** Prompts are copied into
  every target; a per-repo budget that can only be changed by editing a harness-owned agent
  file would be clobbered on the next upgrade (see the upstream-a-drifted-tool failure mode).
- **Why not just cap the diff and reject.** The measured data says review *yield per line* is
  wildly non-uniform — 10% of PR #76 carried 67% of the findings. A pure line cap would have
  blocked the 15,500 low-risk lines just as hard as the 1,716 dangerous ones. The budget is a
  prompt to split along risk, which is why F01 puts the rule at decomposition time where the
  risk structure is still visible, rather than at the diff where only lines are.
- **`.harness/progress/` leakage is out of scope here** and is seeded as its own maintenance
  fix (`E99-F06`): 796 lines of per-round pr-loop scratch (5% of PR #76's diff) were committed
  into the product diff and re-read by the reviewer every round.

## Epic closed 2026-09-06

Rolled `done` with F06 left `pending`+parked on purpose. The 2026-08-17 gate decided
F06 **will not be built** (superseded by F07, which deprecated the stacked lane
instead), and the board has no `declined` terminal status — so the row stays parked
with its rationale rather than being deleted or faked as `done`. The selector already
skips it; do not read the pending row as unfinished work.
