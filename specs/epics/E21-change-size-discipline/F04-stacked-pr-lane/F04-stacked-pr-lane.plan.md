# Stacked-PR lane for reviewability of safely-splittable features — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves.

## Stack & dependencies
- Language/framework: POSIX shell, `gh` CLI, `git`, `jq`
- New dependencies: none — `jq` is already a `/sdd-pr-loop` prerequisite
- Dependencies on: E18-F01 (pr-loop exists), E21-F03 (per-round finding trend data)

## Data model  (serves: R1, R2, R5)
N/A — no new persistent schema. The pr-loop round cache gains one field:

| Entity | Field | Type | Notes |
|---|---|---|---|
| Round cache `pr.json` | `baseRefName` | string | Added to `gh pr view --json` fetch. The PR's actual base branch. |
| Round cache `pr.json` | `baseRefOid` | string | Added to `gh pr view --json` fetch. SHA of the base branch head at fetch time, for change detection (R5). |

## API / interface  (serves: R2, R3, R4)

| Method | Path | Request | Response | R-id |
|---|---|---|---|---|
| CLI | `tools/pr-stack-guard.sh evaluate <pr.json> <open-prs.json> [--default-branch <name>]` | JSON files from `gh pr view` / `gh pr list` | Exit 0 (safe), 6 (stacked/parent open), 4 (usage/unreadable input) | R3, R4 |
| CLI (watcher) | `gh pr view $pr --json reviews,comments,statusCheckRollup,headRefOid,baseRefName,baseRefOid` | — | Watcher writes expanded `pr.json` with base branch fields into the round cache | R1, R5 |

## Files to change  (serves: R1–R9)

| File | Change | R-id |
|---|---|---|
| `tools/pr-stack-guard.sh` | Already exists on disk (resurrected from commit `1873af9`). No change needed — the implementation is correct. Verify `shellcheck` clean. | R3, R4 |
| `.claude/commands/sdd-pr-loop.md` | **Merge step (auto-merge path):** before `gh pr merge`, invoke `tools/pr-stack-guard.sh evaluate` against the cached `pr.json` and a freshly-fetched open-PR list; refuse to merge on exit 6 (R2). **Cache detection:** compare `baseRefOid` from the current round's cached `pr.json` (populated by the watcher) against the prior round's cached value; if changed, discard prior round data and restart from round 1 (R5). | R1, R2, R5 |
| `tools/wait-for-codex.sh` | Add `baseRefName,baseRefOid` to the `gh pr view --json` fields list (currently: `reviews,comments,statusCheckRollup,headRefOid`). No behavioral change — purely additive to the cached `pr.json` payload, consumed by the pr-loop command for base-branch detection (R1) and base-change detection (R5). | R1, R5 |
| `docs/WORKFLOW.md` | Add a "Stacked-PR lane" section documenting: purpose (incremental review of safely-splittable features, not atomic delivery), when to use, wave-boundary guidance, increment creation, restack procedure. | R6, R7 |
| `tests/test_pr_loop.sh` | Add test cases for: (a) pr-loop uses actual base branch for stacked PRs, (b) pr-loop refuses merge when parent is open, (c) pr-stack-guard exit codes, (d) pr-stack-guard fail-closed on unreadable input, (e) cache invalidation on base change, (f) inert when `pr_loop.enabled: false`. | R1–R5, R8 |

## DO NOT TOUCH
- `tools/next-task.mjs` — Orchestrator task selection routing; this feature does not change any gate logic.
- Single-PR default lane — stacking is additive and opt-in; the existing lane is unchanged.
- `pr_loop.max_rounds`, `pr_loop.blocking_severities`, `pr_loop.merge_strategy` semantics — these apply identically to stacked and non-stacked PRs.
- `pr_loop.auto_merge` — the merge-order guard (R2) is an additional gate before auto-merge; `auto_merge` itself remains the same boolean.
- `harness.config.yaml` `change_size` block — the budget thresholds are unchanged.
- Any file outside the listed "Files to change" above.

## Approach notes

### Sequencing
1. `tools/pr-stack-guard.sh` already exists on disk — verify it, mark done.
2. Update `tools/wait-for-codex.sh` to fetch `baseRefName` (R1 prep).
3. Update `.claude/commands/sdd-pr-loop.md` merge step to integrate the guard (R2) and add base-change detection (R5).
4. Document the lane in `docs/WORKFLOW.md` (R6, R7).
5. Write tests in `tests/test_pr_loop.sh` (R1–R5, R8).
6. Run full verification suite.

### Merge-order enforcement (R2)
The pr-loop currently has no awareness of stacking. The guard script answers one question:
"is this PR stacked on an open parent?" The pr-loop merge step calls the guard before
`gh pr merge`. On exit 6, the merge is refused and the pr-loop enters the `needs-human`
state with a diagnostic naming the open parent PR. The guard is called with JSON the
pr-loop already fetches — no additional network calls.

### Base-change detection (R5)
When a stacked PR's parent is rebased, the child's `baseRefOid` changes. The pr-loop
compares the newly-fetched `baseRefOid` against the cached value from the prior round.
A mismatch means the parent moved — the child must be rebased and re-reviewed from scratch.
The round counter resets to 1; prior round cache directories are preserved for the
handover summary but not used for merge-gate evaluation.

### Stacked-PR opt-in (R9)
No configuration flag is introduced. Stacking is detected implicitly: a PR whose
`baseRefName` is not the default branch is a stacked PR. The pr-loop handles it
transparently — the merge-order guard and base-change detection activate only when the
base is non-default. A PR targeting `main` follows the existing single-PR path unchanged.
