# Reviewer verdict — E10-F01 (Ownership primitive: owner field + scoped /sdd-next)

## Verdict: REJECT (1 blocking item)

Almost everything is solid: `./init.sh` exits 0, the full `verification.test_command`
(15 suites incl. `tests/test_ownership.sh`) is green in the current uncommitted tree,
the schema change is additive (real owner-free `state/tasks.json` still VALID), R12/R13
installer wiring is asserted across all four targets, the orchestrator contract is
tool-agnostic and owner-read-only (scope boundary held; F02/F03 correctly deferred), and
docs are consistent. One blocking defect must be fixed.

## BLOCKING

1. **R15 test is a permanent-suite anti-pattern — it passes only while uncommitted and
   fails the moment this feature is committed/merged.**
   `tests/test_ownership.sh::version_bumped_minor` (tests/test_ownership.sh:198-216)
   computes its baseline as `OLD="$(git show HEAD:VERSION)"` (line 201) and then does
   `[ "$NEW" = "$OLD" ] && fail "VERSION unchanged..."` (lines 206-208).

   - Right now it passes because the change is uncommitted: `HEAD:VERSION`=0.27.3 vs
     working-tree 0.28.0.
   - Once this feature is committed (or merged), `HEAD:VERSION` becomes 0.28.0 == the
     working-tree VERSION, so the test hits `fail "VERSION unchanged (0.28.0); expected a
     MINOR bump"`. Proven by simulation: I created a throwaway commit so HEAD:VERSION=0.28.0
     and ran the suite → `FAIL: VERSION unchanged (0.28.0)`, real exit code 1. Restored the
     tree afterward.
   - `test_ownership.sh` is in `verification.test_command` (harness.config.yaml:128), i.e.
     the permanent Reviewer gate. So the NEXT feature's Reviewer will run this and be
     blocked by an unrelated, already-merged VERSION — the exact recurring anti-pattern
     (MEMORY: "must not freeze exact VERSION... recurred 3×"; and this feature's own
     tests.md:7 says "never pin the exact VERSION").

   **Fix:** make R15 a shape-only check like every other merged VERSION test in the suite
   (e.g. `tests/test_doc_critic.sh:123-133`, `tests/test_epic_lifecycle.sh` R14,
   `tests/test_sdd_plan.sh` R23): assert VERSION parses as SemVer and that CHANGELOG.md
   carries a matching entry — do NOT diff against `git show HEAD:VERSION` and do NOT
   compare OLD vs NEW across a git delta. The "MINOR increased, MAJOR unchanged" intent is
   fine to keep as a comment/doc claim, but the executable assertion in the permanent suite
   must be stable across commits (it must not depend on the working tree differing from
   HEAD). Re-run the full `verification.test_command` after committing to confirm it stays
   green post-commit.

## Verified OK (no action needed)
- init.sh exit 0; full 15-suite gate green (uncommitted tree).
- Schema additive (store/tasks.schema.json:16,29 optional string owner on epic+feature,
  not in any required[]); real owner-free store validates.
- R2/R4 backward-compat: bare selection ignores owner (orchestrator.md:71-74).
- R12/R13: installer heredoc (harness-install.sh:1023-1050) generates --mine + $ARGUMENTS;
  asserted byte-identical across Claude/OpenCode/Antigravity/Codex with sandboxed CODEX_HOME
  (tests/test_install.sh:210-217, 375-379, 557-559).
- R11: orchestrator section is tool-agnostic (orchestrator.md:68-70); mirror one-way intact.
- Scope boundary: owner-read only, "never write, claim, or mutate any owner"
  (orchestrator.md:106-108); no reassign UX. No creep.
- Anti-pattern scan otherwise clean: no DO-NOT-TOUCH-vs-main diffs, no hardcoded VERSION
  literals in tests.
