# E99-F170 review — APPROVE (at HEAD c09fb03)

Commands / results
- ./init.sh -> exit 0 (only the known builder-heavy DISARMED warning).
- Generated glue: in a private worktree (scratchpad/E99-F170-reviewer/wt) `sh harness-install.sh --self` -> `git status` clean, so the 3 generated bodies + manifest are in sync, not hand-edited.
- Focused suites (private worktree, HEAD c09fb03): hardening, pr_loop, pr_round_outcome, self_mode, self_drift, codex_native -> "all 6 suites passed (/bin/dash ...)".
- Initial run at e7198eb: test_pr_loop.sh FAILED (R42d: extracted resolve snippet calls undefined `mut` -> resolve_ok=0 -> merge_ok=0). Builder fixed in c09fb03 (sources body's own mut(); R47 prose updated); re-verified green. Note the brief said extend tests/test_pr_loop.sh; new tests live in tests/test_pr_loop_hardening.sh instead (acceptable, covers all 4 bodies).
- Full `tools/run-tests.sh` not run by me (Builder runs it).
- Disk free before/after: 434 GiB.
- VERSION 0.91.2, CHANGELOG `## [0.91.2]` present.

Defects
- P1 hand-back: `merge-verify pre` runs before the green post and the `handback` marker; refused head -> needs-human label, no post, `disposed=stale`. Resume scan treats any disposed round as finished, so stale advances to a fresh round (costs one round of budget; acceptable). Auto-merge path unchanged except wrapped by mut and stale marker added.
- P1 dry run: all gh pr ready/comment/edit/checkout/merge, resolveReviewThread, git checkout/pull/branch -D/remote prune, push go through mut (swept in test); dry-run merge branch stops before merging; dry-run cache root separate; fixers not dispatched (prose rule).
- P2: fix_done (note, or `(#id)` commit after reviewed head) + idempotent acted_append, executed in tests against a scratch git repo.

Mutation probes (private worktree, one at a time, via harness-install.sh + --self)
- acted_append idempotence removed: killed. stale marker removed: killed. mut no-skip: killed. fix_done commit range widened: killed. fix_done note check removed: killed. dry-run cache root removed: killed (grep-level).
- SURVIVED: removing the `HARNESS_DRY_RUN` guard on `echo handback > disposed` (hand-back, dry-run). Unpinned but low risk since dry-run cache is isolated; non-blocking suggestion: add a dry-run hand-back execution case.

Non-blocking notes
- Earlier prose paragraph still says "write handback" before the revalidation block; the later block governs. The hand-back block is scoped to auto_merge:false only by prose.
- A stale disposition at the final round (round+1 > max_rounds) falls out of the loop, same as any disposed cap round.
- Change-size: see tool output in the verdict message.

Verdict: APPROVE. Orchestrator may set done once the Builder's full suite is green.
- Change-size tier: ok (165 production lines, 4 files).
