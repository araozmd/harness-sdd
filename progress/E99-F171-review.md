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
