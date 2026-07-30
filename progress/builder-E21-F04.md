# Builder — E21-F04 (Stacked-PR lane) — Build Report

**Date:** 2026-07-29
**Run:** builder-E21-F04
**Outcome:** All 7 tasks complete, 83 tests pass (7 new), 0 regressions

## Files changed

| File | Change |
|---|---|
| `tools/pr-stack-guard.sh` | Resurrected from commit `7bc86d7`, comments updated to remove atomicity language (stacking provides incremental review, not atomic delivery). Shellcheck clean. |
| `tools/wait-for-codex.sh` | Added `baseRefName,baseRefOid` to the `gh pr view --json` field list (line 361). Shellcheck clean. |
| `.claude/commands/sdd-pr-loop.md` | Added step 0b (base-change detection, R5), merge-order guard before `gh pr merge` (R2). Updated cache layout and needs-human description. |
| `harness-install.sh` | Mirrored all three pr-loop body changes into the HEREDOC. Added `chmod +x` for `pr-stack-guard.sh`. |
| `docs/WORKFLOW.md` | Added "Stacked-PR lane" section documenting purpose, when-to-use table, increment creation, wave-boundary guidance, and manual restack procedure (R6, R7). |
| `tests/test_pr_loop.sh` | Added 7 new tests covering R1–R5, R8, R9. All pass. |

## Test coverage

| R-id | Test | Status |
|---|---|---|
| R1 | `test_stacked_pr_base_detection` | ✅ pass |
| R2 | `test_stacked_pr_refuse_child_merge` | ✅ pass |
| R3 | `test_stack_guard_parent_open` | ✅ pass |
| R4 | `test_stack_guard_unreadable_base` | ✅ pass |
| R5 | `test_stacked_pr_base_change_invalidation` | ✅ pass |
| R8 | `test_stacking_inert_when_disabled` | ✅ pass |
| R9 | `test_stacked_pr_opt_in` | ✅ pass |

R6 and R7 are documentation requirements — covered by the "Stacked-PR lane" section added to `docs/WORKFLOW.md`, verified by the doc-critic (manual check per traceability table).

## Verification

- `./init.sh` — ✅ green
- `sh tests/test_pr_loop.sh` — ✅ All 83 tests pass (76 existing + 7 new)
- `shellcheck tools/pr-stack-guard.sh` — ✅ zero findings
- `shellcheck tools/wait-for-codex.sh` — ✅ zero findings

## Notes

- The HEREDOC copy in `harness-install.sh` uses `.harness/tools/` paths (installed consumer paths), while the source-layout copy at `.claude/commands/sdd-pr-loop.md` uses `tools/` paths (repo-root-relative). Both were updated identically.
- The pr-stack-guard.sh exit-0 and exit-6 diagnostic messages go to stdout (not stderr) — this is by design: informational output for the successful cases, while error cases (missing files, unreadable JSON) go to stderr.
- The `default_branch` variable for squash-message git log range and post-merge cleanup was left unchanged per the spec.
- The `change_size` block and `max_requirements` threshold were not touched.
