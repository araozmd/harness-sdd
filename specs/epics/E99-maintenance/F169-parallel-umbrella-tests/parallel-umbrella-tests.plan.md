# Parallel umbrella tests — Technical Plan

## Stack & dependencies
POSIX shell, the existing runner and its strict-shell shim, existing installer fixtures. No new dependency, data model, or network API.

## Interface and design (R2–R7)
Create top-level executable suites named `tests/test_umbrella_01_coordinator.sh` through the explicit names below. Their case bodies execute at shell top level, after sourcing narrowly extracted helpers from `tests/lib/umbrella/`. Each suite finishes with an explicit successful statement, so a benign final false probe does not accidentally become its exit code.

Retain `tests/test_umbrella.sh` as a small sequential aggregate over `test_umbrella_[0-9][0-9]_*.sh`. It launches each using PATH-resolved `sh`, preserving the runner's shim when explicitly selected. `set -eu` plus a plain child invocation propagates failures. Do not source cases inside conditional functions or `if`/`||` contexts that suppress errexit. No nested runner invocation.

Make only two bounded runner changes: exclude exactly its own compatibility aggregate path from **default** discovery; include the aggregate, umbrella group files, and `tests/lib/umbrella/*.sh` in the existing strict-shell preflight (glob misses skipped). Explicit selections remain honored. Parsing all umbrella files even on a focused selection is cheap and guarantees that explicit aggregate selection covers its children before any execution. Keep concurrency, scheduling order, logs, strict-shell probes/shim, exemptions, and result aggregation unchanged.

Alternatives considered: aggregate under a different name breaks the old direct interface; a nested dispatcher/scheduler adds unnecessary machinery. The chosen exact discovery exclusion is smaller and preserves the old path.

## Files to change (R1–R11)
| File | Responsibility |
|---|---|
| `tests/test_umbrella.sh` | Compatibility aggregate |
| `tests/lib/umbrella/common.sh` | Common environment, SRC/SCHEMA, pass/fail/have_py, fixture allocation and one cleanup owner |
| `tests/lib/umbrella/schema.sh` | Original validate helper |
| `tests/lib/umbrella/audit.sh` | Original mk_umb/cascade/land helpers and AU setup |
| `tests/lib/umbrella/thin.sh` | Sentinel, tier constants, is_stub |
| `tests/lib/umbrella/migration.sh` | Original migration tier equality and helpers |
| `tools/run-tests.sh` | Exact aggregate discovery exclusion and umbrella parse coverage |
| `tests/test_parallel_umbrella.sh` | Cheap integration regressions using synthetic suites in an isolated runner fixture |
| `README.md` | Short current verification/layout documentation |
| `progress/parallel-umbrella-tests/` | Conservation manifest/report, focused results, timing evidence and handoffs |
| `VERSION`, `CHANGELOG.md` | Only if the owner determines the installed runner change requires a patch release; record that decision before changing |

Group files below contain the original inclusive case ranges from the unchanged 3,206-line baseline. The Scout's `progress/parallel-umbrella-tests/scout.md` explains each dependency. Record the baseline git object before extraction; line references are to that object, not later edits.

| New file under `tests/` | Original case lines | Helpers beyond common |
|---|---|---|
| `test_umbrella_01_coordinator.sh` | 84–499 | schema |
| `test_umbrella_02_audit.sh` | 531–896 | audit |
| `test_umbrella_03_thin.sh` | 910–1193 | audit, thin |
| `test_umbrella_04_quoted_roots.sh` | 1195–1346 | audit, thin |
| `test_umbrella_05_conversion.sh` | 1475–1734 | audit, thin, migration |
| `test_umbrella_06_blocker_paths.sh` | 1736–1926 | audit, thin, migration |
| `test_umbrella_07_symlink_compare.sh` | 1928–2105 | audit, thin, migration |
| `test_umbrella_08_symlink_writes.sh` | 2107–2260 | audit, thin, migration |
| `test_umbrella_09_authority.sh` | 2262–2455 | audit, thin, migration |
| `test_umbrella_10_preview.sh` | 2457–2580 | audit, thin, migration |
| `test_umbrella_11_rollback.sh` | 2582–2813 | audit, thin, migration |
| `test_umbrella_12_cleanup.sh` | 2815–2963 | audit, thin, migration |
| `test_umbrella_13_standalone.sh` | 2965–3204 | audit, thin, migration |

## Extraction and isolation (R1, R5, R6, R8)
Move body ranges verbatim; keep comments and assertions. Extract helper ranges 13–28, 31–82, 505–529, 901–908, 1348–1473, separating allocation/traps from functions only as necessary. A single cleanup path owns all roots actually allocated by its suite; do not retain the old audit trap that overwrites T cleanup. Preserve permission widening before AU removal. Allocate roots via mktemp per process, never from a shared fixed path. Common SRC resolution must use the top-level entrypoint location, not a nested helper's inferred location. Preserve all environment overrides and avoid eager construction of case fixtures in helpers.

Keep full-copy installation before cascade, exact F04_TIER source equality, output segmentation, race/mutant controls, and both rollback skip controls. The former repeated AU/f04n pathname has fresh state in separate groups: verify its explicit setup and document any required prerequisite recreation rather than relying on the old incidental leftover child. Do not change product expectations to get a green split.

Conservation proof compares each original case range to its destination body byte-for-byte after stripping only the newly added prologue/terminal line. Record exact approved substitutions individually if any, and separately compare extracted helper bodies. Account for the remaining baseline lines as section comments, blank separators, shebang, replaced initialization/traps, or replaced final banner. A pass-label count alone is insufficient.

## Verification and benchmark (R4–R10)
Do not modify test/source files until the owner's baseline process has completed. Coordinate through progress notes. Use an existing external TMPDIR with no ancestor relationship to this repository, adequate disk headroom, and a real Python interpreter directory first on PATH (the known mise recursion is outside scope). Keep those conditions, shell, source state, and HARNESS_AGENTS comparable.

Builder runs the cheap integration suite, serial aggregate once, and the 13 explicit groups with `--jobs 8` once, retaining original result lines and timings. Use original baseline log `progress/parallel-umbrella-tests/baseline-umbrella.log`; record all compared commands, exit codes, wall seconds, strict shell and host/load caveats. Compare multiset results, not order. Report baseline/parallel speed ratio and absolute seconds saved. If no speedup is observed, diagnose the grouping or confounder and repeat only the necessary comparison; do not claim R9 passes.

Reviewer independently runs `./init.sh` and configured `sh tools/run-tests.sh` on the final source state after examining conservation and focused evidence. Builder need not duplicate that full run. Additional full runs require a change, failure, or unresolved evidence gap. Reviewers still own their verdict.

## DO NOT TOUCH
- `harness-install.sh`, umbrella behavior tools, schema, host glue, workflow/config policy, ADRs, product constitution, unrelated tests and historical specs.
- No new dependency, timing database, scheduling algorithm, or broad runner refactor.
- Board/status changes belong to the owner; this plan grants none to the Architect.
