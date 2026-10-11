# E99-F171 review — APPROVE

- ./init.sh exit 0. tests/test_pr_loop_hardening.sh and tests/test_pr_loop.sh pass under sh, dash and bash. I did not run the full run-tests.sh, as instructed.
- `sh harness-install.sh --self` in a scratch copy of HEAD leaves `git status` clean, so the three self-hosted bodies and the glue manifest match a fresh regeneration.
- The diff is POSIX and dash safe, and `_ci_rc` capture makes it set -e safe. The exit-code handling is right: 0 passes, 8 polls again, and any other code passes only on "no required checks reported", otherwise it fails. The final sleep is clamped to the ceiling, which bounds the wait. A dry run reads checks but labels and posts nothing, because those go through `mut`.
- The hand-back runs receipt, then CI gate, then receipt again. A CI failure labels needs-human, posts no green comment and writes no marker. On auto-merge the gate sits after the stale receipt and before `gh pr merge`; `--match-head-commit` covers a push during the CI wait. Step 5 routing and the needs-human reason prose are consistent.
- Mutations, each applied via the installer and `--self`, each killing the test:
  - gate removed from the hand-back: killed
  - gate removed from the merge block: killed
  - pending-at-ceiling returns 0: killed
  - handback marker written on CI failure: killed
  - stale marker written on merge CI failure: killed
  - label dropped from the hand-back path: killed
  - label dropped from the merge path: killed
  - "no required checks" no longer passes: killed
  - ceiling check removed: killed (the run hung, caught by timeout 124/143)

Non-blocking nit: removing the ceiling makes the test time out rather than fail cleanly. It is still detected.

## Round 2 (3161b38) — APPROVE

- `./init.sh` exits 0. `tests/test_pr_loop_hardening.sh` passes under both sh and dash.
- The diff `f1dcda0..3161b38` classifies by `--json name,bucket`, so a `cancel` bucket counts as red even though gh exits 0. It reads base-branch required contexts from classic protection and from rulesets on every poll. A missing required context counts as pending. An empty rollup is green only when the configuration read succeeded (`known=1`) and came back empty. Unreadable configuration or an unreadable rollup fails closed. `skipping` counts as pass.
- I applied each mutant in a scratch copy via the installer and `--self`. Each one made the suite fail:
  - drop the `cancel` clause: killed
  - return 0 on `ok` without `known=1`: killed
  - treat empty as green without `known=1`: killed
  - ignore `$miss`: killed
  - ignore `$pend`: killed
  - count `skipping` as pending: killed
  - ruleset source replaced with an empty string: killed
  - classic source replaced with an empty string: killed
- Nit, non-blocking: the gh stub returns pre-filtered output and ignores `--jq`. The two `gh api` jq filters are therefore not exercised by the suite. I checked them by hand against sample JSON, and they behave correctly: contexts are extracted, a missing `protection` yields nothing, and the ruleset context is extracted. A typo in either filter would not be caught by the tests.

## Round 3 (80ee692) — APPROVE

- `./init.sh` exits 0. `tests/test_pr_loop_hardening.sh` passes under both sh and dash.
- The diff `2d46bd0..80ee692` makes the gate fetch raw branch and rules JSON and parse them locally with jq, so the stub now exercises the filters. Each ruleset `workflows` entry (repository_id + path) is resolved through `repositories/<id>/actions/workflows` to a workflow name. An entry that cannot be resolved sets `known=0`, so the gate is never green. Runs of each required workflow are matched by name across ALL PR checks: no runs yet is pending, and fail or cancel is red. A required workflow with all runs passing returns green.
- I applied each mutant in a scratch copy via the installer and `--self`, one at a time:
  - drop workflow matching: killed
  - treat an unresolvable workflow as known: killed
  - drop `$wfc` from `$bad`: killed
  - drop `$wfc` from `$pend`: killed
  - drop the workflow term from `$miss`: killed
  - classic protection filter pointed at a wrong path: killed
  - `workflows` rule filter pointed at a wrong path: killed
  - ruleset `required_status_checks` filter pointed at a wrong path (`.parameters.contexts[]`): SURVIVED
  - `"ok"` condition no longer counting required workflows: survived
- The ruleset-path survivor is fail-closed. jq errors on null, so `known=0` and the gate is never green; the mutant is safe, only less useful. The suite lacks the positive case that pins it: a ruleset requires 'build', build passes, and the gate returns 0. I recommend adding it. It is non-blocking.
- The `"ok"` survivor is equivalent. `ok` and `empty` both return 0 when `known=1`, and both wait when `known=0`.
- Nit: workflow and rules lookups use `per_page=100` with no pagination. Beyond 100 they fail closed.

## Round 4 (806b6c5) — APPROVE, with unpinned guarantees to close

- `./init.sh` exits 0. `tests/test_pr_loop_hardening.sh` passes under both sh and dash.
- The code in `1ea1171..806b6c5` reads correctly:
  - Rules are read with `--paginate --slurp` and then flattened.
  - Required workflows are matched on (repository_id, path), with any `@ref` stripped.
  - The runs are taken from `actions/runs?head_sha=<head>`, and the latest run by `created_at` decides.
  - A rule whose repository_id differs from this repo's, or an unreadable repo id, sets `known=0`.
  - No run for the head is pending, not completed is pending, and success/skipped/neutral is ok. Any other conclusion is red.
- I applied each mutant in a scratch copy via the installer and `--self`, one at a time. These were killed:
  - name or any-path match: killed
  - earliest run instead of latest: killed
  - cross-repo rule treated as matchable: killed
  - failure or cancelled treated as ok: killed
  - the "missing" term dropped from `$miss`: killed
  - a missing run counted as pass: killed
  - `head_sha` filter dropped: killed
  - `--paginate` dropped from the rules read: killed
- Survivors, none of which make the current code wrong:
  1. **`timed_out` treated as ok.** This is a safety guarantee with no pin. Add a case with a `timed_out` latest run that expects a non-zero return.
  2. **`@ref` suffix stripping removed.** Runs of ruleset-required workflows carry `path@refs/...`. With no test case, a regression would fail closed everywhere and produce false needs-human outcomes. Add a case with an `@refs/heads/main` run path that expects green.
  3. **In-progress run treated as red instead of pending.** The mutant `status != "completed"` → false still gave non-green results. A case where an in-progress run turns completed/success on a later poll would pin the wait-then-pass behaviour.
- The `--paginate` kill comes from a textual assertion in the suite, plus the stub's page-2 rule. Both are acceptable.

## Round 5 (abf2a0f) — APPROVE

- `./init.sh` exits 0. `tests/test_pr_loop_hardening.sh` passes under both sh and dash.
- The diff `52cbf7f..abf2a0f` keeps `event` in the runs projection and counts only pull_request, pull_request_target and merge_group runs when deciding a required workflow.
- I applied each mutant in a scratch copy via the installer and `--self`, one at a time:
  - event filter removed: killed
  - `merge_group` dropped: killed
  - `push` added to the allowed list: killed
  - `workflow_dispatch` added to the allowed list: killed
  - `pull_request_target` dropped: SURVIVED
- Non-blocking nit: the `pull_request_target`-only success path has no pin. Dropping it fails closed, as a false needs-human for such workflows. A case with a `pull_request_target` success run that expects green would pin it.

## Round 6 (03a2fc7) — APPROVE

- `./init.sh` exits 0. `tests/test_pr_loop_hardening.sh` passes under both sh and dash.
- The diff `071a442..03a2fc7` removes all the runs-matching code. A ruleset `workflows` rule on any page of the rules returns 1 with the message "requires ruleset workflows … confirm required CI by hand — needs-human". The rules are still read with `--paginate --slurp` and flattened. Cancel, missing-is-pending and known-only-empty-green are unchanged.
- The prose, CHANGELOG, comments and test stub are consistent, with no stale references to name, path or run matching. The self-hosted copies match what `--self` regenerates, since the scratch `--self` run left `git status` clean.
- I applied each mutant in a scratch copy via the installer and `--self`, one at a time:
  - fail-closed check dropped: killed
  - workflows counted on page 1 only: killed
  - flatten dropped: killed
  - missing context treated as ok: killed
  - `known` check dropped on `ok`: killed
  - `cancel` removed from `red`: SURVIVED
- The `cancel` survivor is equivalent for green/not-green. A cancelled check now falls into `$pend` and waits to the ceiling, so it is never green. Only the fail-fast, an immediate red, is unpinned. Non-blocking.
- Behavioural note: any base with a ruleset `workflows` rule will always go to needs-human on both terminal paths. That is the intended trade-off, and it is documented.

## Round 7 (9b52f4f) — APPROVE

- `./init.sh` exits 0. `tests/test_pr_loop_hardening.sh` passes under both sh and dash.
- The diff `62f98e0..9b52f4f` encodes the base with `jq -sRr @uri` before both the `branches/` and `rules/branches/` reads. I checked that `release#1` becomes `release%231`. The fail-closed path stays: `[ -n "$_ci_benc" ]` guards the reads.
- I applied each mutant in a scratch copy via the installer and `--self`, one at a time:
  - raw base in both URLs: killed (the failure message is from a static "without URL-encoding" check in the suite)
  - raw base in the rules URL only: killed (same static check)
- Caveat, non-blocking: the encoding also turns `/` into `%2F` for names like `feat/x`. GitHub accepts this for the branch endpoints, but I did not verify it live.

## Round 8 (ebdec3f) — APPROVE

- `./init.sh` exits 0. `tests/test_pr_loop_hardening.sh` passes under both sh and dash.
- The diff `47cbf93..ebdec3f` moves the `ci_required_gate` branch to just after the `merge_ok` check. It still sits before the dry-run and merge branches and after the stale-head receipt. A thread blocker is no longer delayed or masked by the CI wait.
- The mutant that restores the old order (the `merge_ok` branch moved back to after the CI gate) made the suite fail.
- Non-blocking observation: the `merge_ok` refusal branch only echoes and does not label needs-human. That was already the case and is unchanged by this commit.
