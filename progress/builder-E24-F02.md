# Builder — E24-F02 (the cascade lands the upgrade)

## What shipped
A post-cascade landing audit in `harness-install.sh` (exit **3** when any target is
unlanded), and the extraction of the harness-owned path set into
`tools/harness-owned-paths.sh`, which both `init.sh` and the audit now call.
`VERSION` 0.51.2 → **0.52.0** (MINOR — new capability).

## Decisions taken during implementation

**The commit path does not ship.** The brief left it open. Report-and-exit fully fixes the
reported defect — the operator was *told* the upgrade was complete when it was not — and
committing into N repos on their behalf is a much larger claim on their working tree.

**Extraction, not reimplementation.** The 27 existing drift-guard assertions had to pass
untouched; that was the contract. They did, first run.

## Four things the tests caught that I had wrong

1. **`$1` inside `$( set -- … )`.** My differential test helper ran `git -C "$1"` inside a
   subshell where `set --` had already replaced the positional parameters with pathspecs, so
   it audited a pathspec instead of the repo. The differential reported a genuine
   disagreement — in the test harness, not production (`audit_one` saves `_t="$1"` first).
   Exactly what a differential is for.
2. **A forbidden word.** `harness-install.sh` must not contain "drift" (case-insensitive):
   `test_drift_check.sh` R18 and `test_installer_toggles.sh` R13 both enforce it, because
   E06-F06 asserts the installer was never wired for *its* drift check. My audit comments
   used it throughout. Rewritten to "diverge"/"divergent"/"uncommitted".
3. **Two existing cascade assertions encoded the old exit contract.** `test_cascade.sh`
   expected exit 0 from `--shared-repo` runs whose children are freshly installed and
   therefore unlanded. Updated to accept 0 **or** 3 and reject everything else — `|| true`
   would have let a genuine install failure pass silently.
4. **The `-uall` mutation survived.** My first R4 assertion matched any count, so dropping
   `-uall` changed the number without changing the verdict. The added case pins it — and its
   first fixture was also wrong: `install_one` **prunes** unknown files from the body dirs,
   so a stray file in `.harness/agents/` does not survive the re-install the case performs.
   Moved to `.claude/commands/`, which is equally owned and not pruned.

## Verification
- `tests/test_umbrella.sh` — 7 new cases (R1–R7, R9 + the `-uall` case).
- `tests/test_init_drift_guard.sh` — R8 differential + helper-missing degradation; 27 → 29.
- `sh tools/run-tests.sh` — **all 29 suites pass**. `tools/change-size.sh` — tier `ok`
  (224 production lines / 4 files).
- Mutations: M19 (audit never exits non-zero) → R2/R3; M20 (helper drops the `.agents`
  narrowing) → R4-regression; M21 (drop `-uall`) → the new case, after being strengthened.

## Corrected
The v0.51.1 CHANGELOG claimed "19 → 30 assertions" for the drift-guard suite. The real
figures are **18 → 27**; corrected in place. I had asserted counts from memory instead of
counting them.

## Not done here
`.harness/agents/` pruning behaviour was observed, not changed. `test_next_task.sh:542`
still fails on any uncommitted `init.sh` (the permanent-suite anti-pattern, now a fourth
recurrence) — out of scope, still worth its own E99 item.
