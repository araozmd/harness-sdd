# Parallel umbrella tests — Test Contract

## Traceability
| R-id | Concrete verification | Type | Status |
|---|---|---|---|
| R1 | `progress/parallel-umbrella-tests/conservation.md`: original git object, range/body comparisons, helper comparisons, complete line accounting, individually explained adaptations | conservation audit | Builder passed; Reviewer pending |
| R2 | `tests/test_parallel_umbrella.sh::default_discovery_once`: each synthetic group marker once, aggregate marker absent | integration | Builder passed; Reviewer pending |
| R3 | `tests/test_parallel_umbrella.sh::aggregate_order`: direct and explicit-runner aggregate produce all group markers in numeric order; real aggregate run covers original results | integration | Builder passed; Reviewer pending |
| R4 | `tests/test_parallel_umbrella.sh::failed_group`: failing child diagnostic and nonzero direct/explicit/default runner status | integration | Builder passed; Reviewer pending |
| R5 | `tests/test_parallel_umbrella.sh::fixture_cleanup`: concurrent common/audit users have distinct T/AU roots, successful and failed read-only fixtures leave none; actual focused runs leave their TMPDIR clean | integration | Builder passed; Reviewer pending |
| R6 | `tests/test_parallel_umbrella.sh::strict_child_and_errexit`: child records selected shell; an unhandled false followed by a success marker cannot produce that marker or exit zero | integration | Builder passed; Reviewer pending |
| R7 | `tests/test_parallel_umbrella.sh::parse_before_execution`: malformed helper and group, each separately, produce preflight failure and no execution canary for default and explicit aggregate selection | integration | Builder passed; Reviewer pending |
| R8 | `progress/parallel-umbrella-tests/benchmark.md`: normalized original ok/skip multiset equality for original baseline, new serial aggregate, new eight-worker groups | behavioral comparison | Builder passed; Reviewer pending |
| R9 | `progress/parallel-umbrella-tests/benchmark.md`: comparable baseline elapsed > eight-worker group elapsed, with commands/environment/exit codes and ratio | performance | Builder passed; Reviewer pending |
| R10 | Independent Reviewer log: `./init.sh` and `sh tools/run-tests.sh` on final source state | regression | pending independent Reviewer |
| R11 | Reviewer inspects README against actual paths, direct/focused/full commands, and TMPDIR/Python prerequisites | documentation audit | documentation updated; Reviewer pending |

## Cheap integration fixture
Build a temporary minimal repository containing the actual runner and aggregate plus synthetic named umbrella groups. Copy the actual common/audit helpers for cleanup checks; do not execute real installer fixtures in this meta-suite. Marker files record discovery, child order, selected interpreter, failure, and forbidden post-failure execution. Set fixture-only HOME/CODEX_HOME where needed; never mutate live test files to simulate failures. Use a separate temporary root and cleanup trap for the meta-suite itself.

Use separate success/failure tests: a plain failing child command verifies aggregate propagation; a child with `false` followed by a marker verifies errexit has not been disabled by conditional wrappers. For parse-before-execution, plant an actual syntax error in each class and a valid canary suite; require exit 3 and no canary. Exercise group syntax failure through explicit aggregate selection as well as discovery, so nested execution cannot hide a preflight omission.

For isolation run at least two helper users concurrently, capture their root paths before exit, and test both success and deliberate failure. Add a 0555 fixture directory with a file; require cleanup afterward on the current filesystem. If the host does not enforce mode bits, disclose that fact rather than claiming the permission-denial branch ran. Tests remain POSIX shell and obey the runner's existing portability contract.

## Conservation and result normalization
Create `conservation.md` using the plan's 13 original ranges. Each complete body must match its extraction; changes beyond prologue, terminal success, and explicitly reviewed fixture/cleanup adaptations fail review. Preserve fixture discriminators and skip branches, not merely result strings. Include original helper-body comparisons and account for all omitted separator/initialization lines. Reviewer independently samples the most dependency-sensitive ranges (blocker mutant/race, authority/missing entry, rollback, cleanup) and reviews every adaptation.

Capture stdout/stderr logs for serial and parallel runs. Extract original `ok - ` result lines and explicit skip lines, normalize only volatile fixture paths if present, and compare sorted multisets with counts. Exclude newly added group banners and runner timing summaries explicitly. Preserve original duplicate labels; do not turn the multiset into a set. Any new missing or added skip is investigated, not normalized away. Retain the raw logs.

## Timings and final gate
Use the owner's completed original baseline instead of rerunning the old full suite. Time the real new serial aggregate and eight-worker umbrella group selection under the same conditions. No timing threshold is added to CI: performance acceptance is measured evidence, not a flaky wall-clock unit test. Record noisy or unmatched conditions and repeat a focused comparison only if necessary. A failure, result mismatch, or missing demonstrated speedup remains open.

The independent Reviewer runs the configured full suite once on the final state and inspects the focused evidence. If subsequent source edits occur, revalidate affected behavior and the configured final gate as required; a prior verdict is not a verdict on changed code.
