# Stacked-PR lane for reviewability of safely-splittable features — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom,
> one at a time. Each task names the R-id(s) it satisfies. Check off when done.

- [x] **T1** (R3, R4) — Verify `tools/pr-stack-guard.sh` is on disk, `shellcheck` clean,
  and its behavior matches the spec: exit 6 when parent PR is open, exit non-zero on
  unreadable input. The script was resurrected from commit `1873af9` and should already be
  present. Run `shellcheck tools/pr-stack-guard.sh` and confirm zero findings.

- [x] **T2** (R1, R5) — Update `tools/wait-for-codex.sh` to add `baseRefName` and
  `baseRefOid` to the `gh pr view --json` field list. The current list is
  `reviews,comments,statusCheckRollup,headRefOid`; add `baseRefName,baseRefOid` so the
  round cache's `pr.json` always carries the actual base branch name and its head SHA
  (needed for base-change detection in R5). No behavioral change to the watcher —
  purely additive to the cached payload.

- [x] **T3** (R1, R2, R5) — Update `.claude/commands/sdd-pr-loop.md` to:
  - In the merge step (auto-merge path, section "### Merge"), before the `gh pr merge`
    call: fetch the open-PR list (`gh pr list --state open --json number,headRefName`),
    invoke `tools/pr-stack-guard.sh evaluate <pr.json> <open-prs.json>`, and refuse the
    merge on exit 6. On exit 6, POST the guard's diagnostic message and enter the
    `needs-human` terminal state (R2).
  - Add base-change detection: before starting a new round, read `baseRefOid` from the
    current round's cached `pr.json` (populated by the watcher per T2) and compare it
    against the cached value from the prior round's `pr.json`. If they differ, discard
    prior round cache data and restart the round counter from 1 (R5).
  - The `default_branch` variable used for the squash-message `git log` range (line 312)
    and post-merge cleanup (line 493) shall remain as-is — those uses are about the
    target, not the base, and are correct for both stacked and non-stacked PRs.

- [x] **T4** (R6, R7) — Add a "Stacked-PR lane" section to `docs/WORKFLOW.md`. Document:
  - The lane's purpose: incremental review of safely-splittable features whose
    intermediate increments are safe to merge to `main` independently.
  - Explicit statement: stacking provides incremental **review**, not atomic delivery —
    merging increment A publishes wave 1 to `main` while B and C are still open.
  - When to use stacking vs. when to split into separate features vs. when to use feature
    flags for atomic delivery.
  - How to create stacked increments: set each PR's base to the previous increment's
    branch using `gh pr create --base <parent-branch>`.
  - Wave-boundary guidance: align increments with the wave structure from E21-F01's
    decomposition.
  - Manual restack procedure (R7): when an earlier increment takes review fixes, the
    Builder rebases each child increment onto the updated parent branch.

- [x] **T5** (R1–R5, R8, R9) — Add test cases to `tests/test_pr_loop.sh`:
  - `test_stacked_pr_base_detection` — verify the pr-loop fetches and uses
    `baseRefName` when evaluating a stacked PR (R1).
  - `test_stacked_pr_refuse_child_merge` — verify the pr-loop refuses to merge a child
    PR whose parent is still open, entering `needs-human` with a diagnostic naming the
    parent (R2).
  - `test_stack_guard_parent_open` — verify `pr-stack-guard.sh` exits 6 when the base
    branch matches an open PR's head (R3).
  - `test_stack_guard_unreadable_base` — verify `pr-stack-guard.sh` fails closed
    (exit non-zero, not 6) when `.baseRefName` is unreadable or the open-PR list is
    unparseable (R4).
  - `test_stacked_pr_base_change_invalidation` — verify that when `baseRefOid` changes
    between rounds, prior round cache data is discarded and the round counter restarts
    from 1 (R5).
  - `test_stacking_inert_when_disabled` — verify that when `pr_loop.enabled` is `false`,
    no stacking-specific merge logic or guard invocation runs (R8).
  - `test_stacked_pr_opt_in` — verify a PR targeting the default branch (`main`) follows
    the existing single-PR path with no guard invocation and no base-change detection (R9).
  - Follow suite conventions: no frozen VERSION string, no diff against `main`, use
    `install_at()`/`install_on()` for sandboxed installs.

- [x] **T6** — Write tests per `F04-stacked-pr-lane.tests.md` traceability table. Ensure
  every R-id in the table maps to at least one test assertion.

- [x] **T7** — Run `./init.sh` and the full verification suite (`sh tests/test_pr_loop.sh`
  plus any other affected suites). Ensure all tests pass and the pr-loop test suite is
  green before hand-off.
