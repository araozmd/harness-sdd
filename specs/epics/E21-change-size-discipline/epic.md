---
id: E21
title: "Change-size discipline: keep the review a gate"
status: pending          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
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
| F04 | Stacked-PR lane for an atomic feature that exceeds the budget | pending (**withdrawn — needs re-spec**) | true | E18-F01, E21-F03 |

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
