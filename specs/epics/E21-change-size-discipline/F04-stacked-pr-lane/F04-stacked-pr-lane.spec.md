---
id: E21-F04
title: Stacked-PR lane for reviewability of safely-splittable features
epic: E21-change-size-discipline
status: done             # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false        # re-gated after WITHDRAWN (PR #78) — goes through the human gate
depends_on: [E18-F01, E21-F03]
owner: araozmd
---

# Stacked-PR lane for reviewability of safely-splittable features — Functional Spec

## Context

E21-F01 splits features at drill time and E21-F02 catches what slips through. Both assume
the work can be split into independently-mergeable units. Sometimes a feature legitimately
exceeds the single-PR review budget yet its intermediate increments are **safely
shippable** — each wave can land on `main` without breaking anything, and only the combined
work delivers the full capability.

Stacking PRs addresses this by letting each increment be a separate PR whose base is the
previous increment's branch, so the reviewer reads only that increment's own diff (budget-sized).
The stack merges in **order** — increment 1, then 2, then 3 — but each merge publishes that
wave to `main` independently. Stacking provides **incremental review**; it does **not**
provide atomic delivery. A feature whose intermediate states are unsafe to ship needs a
different mechanism (feature flags, aggregate landing strategy) and is explicitly out of
scope for this lane.

This feature was **withdrawn** during review of PR #78 (2026-07-28) because the original
spec falsely claimed stacking provides atomic delivery. Four `@codex review` rounds
produced five blocking findings, every one on this feature's surface. The
`tools/pr-stack-guard.sh` guard script — an offline merge-order check — is independently
sound and recoverable. This re-spec removes the atomicity language, scopes the lane to
reviewability only, and integrates the guard into `/sdd-pr-loop`.

## Business rules

- Stacking is strictly for **reviewability** of features whose intermediate increments are
  safe to merge to `main` independently. It is never a mechanism for atomic delivery.
- A child PR must not merge before its parent (base) PR. Merge order is enforced.
- When the parent PR is rebased (review fixes), each child must be manually rebased onto
  the updated parent. The pr-loop detects the base change and restarts review from round 1.
- The stacked-PR lane is opt-in. A feature that does not explicitly opt into stacking
  follows the existing single-PR default lane.
- The lane is inert when `pr_loop.enabled` is `false`.

## Architecture alignment

ADRs touched: none — this feature modifies `/sdd-pr-loop` merge-step glue and adds an
offline guard script; it does not constrain or depend on the Orchestrator's deterministic
task selection routing (ADR-0001).

## Acceptance criteria (EARS)

- **R1** — When `/sdd-pr-loop` evaluates a stacked PR, the system shall use the PR's actual
  base branch (fetched via `gh pr view --json baseRefName`) for diff computation,
  round-cache keying, and merge-gate evaluation, rather than assuming the default branch.

- **R2** — When `/sdd-pr-loop` evaluates merge eligibility for a stacked PR, the system
  shall not merge a child PR whose parent (base) PR is still open, regardless of the child
  PR's own gate status.

- **R3** — When `tools/pr-stack-guard.sh evaluate <pr.json> <open-prs.json>` is invoked
  and the PR's base branch matches the head of an open PR, the system shall exit 6.

- **R4** — If the PR's `.baseRefName` is unreadable or the open-PR list is unparseable,
  then `tools/pr-stack-guard.sh` shall fail closed (exit non-zero and not 6).

- **R5** — When the base branch head of a stacked PR has changed since the last pr-loop
  round (detected by comparing a cached `baseRefOid` to the current value), the system
  shall invalidate prior round-cache data and restart the round counter from 1.

- **R6** — The system shall document the stacked-PR lane in `docs/WORKFLOW.md`, including:
  the lane's purpose (incremental review of safely-splittable features only), when to use
  it, wave-boundary guidance, and an explicit statement that stacking provides incremental
  review, **not** atomic delivery — merging increment A publishes wave 1 to `main` while B
  and C are still open.

- **R7** — The system shall document the manual restack procedure in `docs/WORKFLOW.md`:
  when an earlier increment takes review fixes, the Builder shall rebase each child
  increment onto the updated parent branch.

- **R8** — Where `pr_loop.enabled` is `false`, the stacking lane shall be inert: no guard
  invocation, no stacking-specific merge logic, no stacking documentation is stamped.

- **R9** — The stacked-PR lane shall be opt-in. The single-PR default lane shall be
  unchanged, and a feature that does not explicitly opt into stacking shall follow today's
  behavior.

## Out of scope

- Automating the split of an existing branch into stacked increments. Choosing the seams
  is a human/Architect decision informed by the dependency DAG.
- Any third-party stacked-PR tool (Graphite, `git-branchless`, `spr`). The harness uses
  POSIX sh + `git` + `gh`.
- Atomic delivery of a feature whose intermediate states are unsafe to ship. That requires
  feature flags or an aggregate landing strategy — a different feature.
- Changing `max_rounds`, `blocking_severities`, or clean-signal semantics for any PR lane.

## Open questions

- Whether the stack is created up front (Builder emits N branches) or grown as the Builder
  finishes each wave. Growing it matches the existing one-task-at-a-time Builder loop and
  gets increment 1 into review while increment 3 is still being written.
- Whether the harness should hold the `done` rollup until the whole stack merges, or roll
  each increment individually. The increments are independently shippable by definition, so
  per-increment rollup is likely correct — but this interacts with the Orchestrator's
  `done-but-unmerged` slice logic.

## Re-spec notes

This spec replaces the **withdrawn** version from PR #78 (2026-07-28). The original
claimed a stacked feature "lands atomically with respect to `main`"; it does not. Stacking
enforces merge **order**, not atomicity. This version:

- Removes all atomicity language.
- States plainly that stacking provides incremental **review**, not atomic delivery.
- Scopes the lane to safely-splittable features only.
- Explicitly calls out the unsolved case (atomic delivery of unsafely-intermediate
  capabilities) as out of scope.

**Superseded by E21-F05 (2026-08-17).** (Kept as a paragraph rather than a subheading on
purpose: the section-extraction helper that reads this record stops at the next heading of
any level, so a subheading here would hide the note from its own test.)

**E21-F05** ("The stacked-PR lane's doctrine document") rewrote the `## Stacked-PR lane`
section of `docs/WORKFLOW.md` that this feature shipped. Nothing below edits F04's
requirement text — a `done` feature's requirements are a historical record. This note
records which of them the shipped document no longer matches, so a reader of F04 is not
left with a spec its own deliverable contradicts.

- **R6** — *superseded, in two parts.* The denial sentence R6 asked for is replaced by a
  mechanical statement of the outcome (merging an increment publishes that increment's
  work to the default branch while the later increments are still open), and R6's
  wave-boundary guidance is deleted: it attributed a decomposition structure to E21-F01,
  which defines none. The replacement subsection is `### Where to cut`.
- **R7** — *retained in substance, heading renamed.* The manual restack procedure itself
  is unchanged — the `git rebase --onto` steps and the warning against the bare two-arg
  form stand exactly as F04 shipped them. Only the heading changed, to the section name
  `harness-install.sh`'s shipped diagnostic already points readers at.
- **R8's documentation clause** — *superseded as factually wrong.* R8 stated that with
  `pr_loop.enabled: false` no stacking documentation is stamped. `docs/` is part of
  `HARNESS_BODY_PROSE` and is copied with no `pr_loop` condition, so every install has
  always carried this section. The document now says so.

**F04-R8's behavioral half is untouched and still holds:** where `pr_loop.enabled` is
`false` there is no guard invocation and no stacking-specific merge logic, and
`tests/test_pr_loop.sh::test_stacking_inert_when_disabled` still asserts it. E21-F05
changed no behavior at all — it changed one shipped document.

---

## Superseded (append-only) — E21-F07, 2026-09-05

This spec describes the stacked-PR lane as shipped. **E21-F07 removed the lane**: the
E21-F06 gate answered "does the lane earn its keep?" with NO (the guard never fired in
100 PRs; the sibling-feature split covers the need with zero machinery).
`tools/pr-stack-guard.sh`, the `/sdd-pr-loop` base-change and merge-order blocks, and
the WORKFLOW.md lane how-to are gone from the installed body as of v0.70.0. This spec
stays as the historical record of what shipped; nothing below this line was edited.
