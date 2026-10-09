# Parallel umbrella tests — Tasks

Execute sequentially; each item has an observable result. The Builder follows the approved SDD worklist and records evidence under `progress/parallel-umbrella-tests/`.

- [x] **T1** (R1, R9) — Confirm baseline completion in the owner's progress note, pin its original git object and preserve log/timing/environment; write the extraction range map and baseline assertion inventory.
- [x] **T2** (R2–R7) — Add `tests/test_parallel_umbrella.sh` synthetic fixture checks specified in the test contract. Run it and retain the expected initial failure for missing discovery/preflight behavior.
- [x] **T3** (R1, R5, R6) — Extract the five named helper files, retaining helper bodies and consolidating fixture cleanup without eager case setup.
- [x] **T4** (R1, R2, R5, R6) — Extract groups 01–04 at the exact plan ranges with top-level execution and explicit successful termination.
- [x] **T5** (R1, R2, R5, R6) — Extract migration groups 05–09 at the exact plan ranges, preserving mutation controls and explicit fixture prerequisites.
- [x] **T6** (R1, R2, R5, R6) — Extract migration groups 10–13 at the exact plan ranges, keeping rollback skip controls together and preserving permission cleanup.
- [x] **T7** (R2–R4, R6, R7) — Replace the old aggregate body with the ordered child loop and make only the named runner discovery/preflight changes.
- [x] **T8** (R1–R8) — Run `sh tools/run-tests.sh tests/test_parallel_umbrella.sh`; record synthetic failure-propagation/parse evidence and complete byte-level conservation review including helper adaptations.
- [x] **T9** (R8, R9) — Time one strict-runner aggregate selection and one `--jobs 8 tests/test_umbrella_[0-9][0-9]_*.sh` run; compare original result/skip multisets and the original monolith timing; save benchmark evidence and investigate any mismatch or absent speedup.
- [x] **T10** (R11) — Update README's current test-layout and invocation guidance; record the installed-runner version-contract assessment with the owner and apply any authorized patch VERSION/CHANGELOG change.
- [x] **T11** (R1–R11) — Run `./init.sh`, update this checklist and evidence statuses, and hand off to an independent Reviewer for the configured full suite and final verdict. Do not label R10 passed until that verdict exists.
