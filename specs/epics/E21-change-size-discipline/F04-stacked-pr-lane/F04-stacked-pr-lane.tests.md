# Stacked-PR lane for reviewability of safely-splittable features — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete,
> executable test. The Reviewer fails the feature if any R-id lacks a passing test.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | pr-loop uses actual base branch for diff/cache/merge-gate | `tests/test_pr_loop.sh::test_stacked_pr_base_detection` | unit | ⬜ |
| R2 | pr-loop refuses to merge child when parent PR is open | `tests/test_pr_loop.sh::test_stacked_pr_refuse_child_merge` | unit | ⬜ |
| R3 | pr-stack-guard exits 6 when parent PR is open | `tests/test_pr_loop.sh::test_stack_guard_parent_open` | unit | ⬜ |
| R4 | pr-stack-guard fails closed on unreadable base | `tests/test_pr_loop.sh::test_stack_guard_unreadable_base` | unit | ⬜ |
| R5 | pr-loop invalidates round cache on base change | `tests/test_pr_loop.sh::test_stacked_pr_base_change_invalidation` | unit | ⬜ |
| R6 | Document stacked-PR lane with explicit non-atomicity statement | `tests/test_doc_critic.sh` (doc-critic with target-type=feature-spec) | manual | ⬜ |
| R7 | Document manual restack procedure | `tests/test_doc_critic.sh` (doc-critic with target-type=feature-spec) | manual | ⬜ |
| R8 | Stacking inert when pr_loop.enabled is false | `tests/test_pr_loop.sh::test_stacking_inert_when_disabled` | unit | ⬜ |
| R9 | Single-PR default unchanged (opt-in) | `tests/test_pr_loop.sh::test_stacked_pr_opt_in` | unit | ⬜ |

## Behavioral / end-to-end checks

- **pr-stack-guard parent-open scenario:** Create a mock `pr.json` with `baseRefName`
  set to a feature branch name, and a mock `open-prs.json` with an open PR whose
  `headRefName` matches. Run `pr-stack-guard.sh evaluate pr.json open-prs.json`.
  Assert exit code 6 and a diagnostic message naming the open PR.

- **pr-stack-guard safe scenario:** Same setup but with `baseRefName` set to
  `main` (the default branch). Assert exit code 0.

- **pr-stack-guard fail-closed scenario:** Provide a `pr.json` with no
  `.baseRefName` field. Assert non-zero, non-6 exit code.

- **pr-loop stacked-PR merge refusal:** Simulate a stacked PR scenario by setting
  up mock round-cache data where `baseRefName` is a non-default branch that matches
  an open PR's head. Assert the pr-loop enters `needs-human` rather than attempting
  `gh pr merge`.

- **pr-loop base-change invalidation:** Simulate two rounds where the first round's
  cached `baseRefOid` differs from the second's. Assert round-1 cache is discarded
  and the counter restarts.

- **pr-loop opt-in behavior:** Verify that a PR targeting the default branch (`main`)
  follows the existing single-PR path with no guard invocation and no base-change
  detection.

- **Inert when disabled:** With `pr_loop.enabled: false`, verify no stacking-specific
  logic is activated.

## Non-functional checks
- Lint: `shellcheck tools/pr-stack-guard.sh` — zero findings
- Lint: `shellcheck tools/wait-for-codex.sh` — zero findings (no regression)
- The pr-loop command fragment stays lint-clean (no shellcheck for embedded markdown
  code blocks, but manual review for syntax correctness)
- No frozen VERSION string in any test
- No diff against `main` in any test
