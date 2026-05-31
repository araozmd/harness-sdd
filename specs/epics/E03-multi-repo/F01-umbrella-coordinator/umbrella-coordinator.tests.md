# Umbrella coordinator — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete, executable
> check. The Reviewer fails the feature if any R-id lacks a passing test. Tests live
> in `tests/test_umbrella.sh` (POSIX sh, zero-dep, matching the existing
> `tests/test_install.sh` style) plus JSON-schema validation fixtures. Because this
> is a harness/structural feature, several checks are schema-validation assertions
> and document/config-presence assertions rather than application unit tests.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | Feature may declare `slices[]` each with `id` + `repo` | `tests/test_umbrella.sh::test_schema_accepts_slices` | schema | ⬜ |
| R2 | Slice may declare cross-repo `depends_on` | `tests/test_umbrella.sh::test_schema_slice_depends_on` | schema | ⬜ |
| R3 | Feature is `done` only when all slices `done` (rollup) | `tests/test_umbrella.sh::test_rollup_feature_done_requires_all_slices` | unit | ⬜ |
| R4 | Schema is a pure superset (no-`slices` feature still valid) | `tests/test_umbrella.sh::test_schema_backward_compat_no_slices` | schema | ⬜ |
| R5 | Coordinator reads manifest (path/init/test/delegate per repo) | `tests/test_umbrella.sh::test_manifest_example_parses_all_fields` | unit | ⬜ |
| R6 | Slice with unknown `repo` is undispatchable + reported | `tests/test_umbrella.sh::test_unknown_repo_slice_rejected` | unit | ⬜ |
| R7 | Shared spec pins exactly one contract artifact, referenced by id | `tests/test_umbrella.sh::test_contract_artifact_pinned_once` | doc | ⬜ |
| R8 | Each emitted slice references the pinned contract artifact | `tests/test_umbrella.sh::test_slice_references_contract` | doc | ⬜ |
| R9 | Next slice chosen in topo order (upstreams `done`+merged) | `tests/test_umbrella.sh::test_select_topological_upstream_done_merged` | unit | ⬜ |
| R10 | Dispatch uses `<delegate_cmd> <feature-id> <abs-spec-path>`, no source edits | `tests/test_umbrella.sh::test_dispatch_uses_delegate_seam` | unit | ⬜ |
| R11 | No downstream dispatch/PR before upstream `done`+merged | `tests/test_umbrella.sh::test_gate_blocks_downstream` | unit | ⬜ |
| R12 | Non-zero delegate exit ⇒ slice failed, dependents halted, surfaced | `tests/test_umbrella.sh::test_failstop_on_delegate_nonzero` | unit | ⬜ |
| R13 | Slice success ⇒ `done` recorded, dispatchable set re-evaluated | `tests/test_umbrella.sh::test_advance_reevaluates_dispatchable` | unit | ⬜ |
| R14 | Integration check not run while any slice not `done` | `tests/test_umbrella.sh::test_integration_gated_until_all_done` | unit | ⬜ |
| R15 | All slices `done`+merged ⇒ integration command runs | `tests/test_umbrella.sh::test_integration_runs_when_all_done` | unit | ⬜ |
| R16 | Feature `done` only if all slices pass AND integration exits zero | `tests/test_umbrella.sh::test_feature_done_requires_integration_pass` | unit | ⬜ |
| R17 | Non-zero integration ⇒ feature kept out of `done`, surfaced | `tests/test_umbrella.sh::test_integration_failure_blocks_done` | unit | ⬜ |
| R18 | No manifest ⇒ coordinator inert, single-repo flow unchanged | `tests/test_umbrella.sh::test_no_manifest_single_repo_unchanged` | unit | ⬜ |
| R19 | Existing single-repo `state/tasks.json` still validates | `tests/test_umbrella.sh::test_existing_tasks_json_still_valid` | schema | ⬜ |

## Behavioral / end-to-end checks
The Reviewer runs `tests/test_umbrella.sh` and confirms, using temp fixtures (no real
child repos required — delegate is stubbed by a fake exit-coded script):

1. **Backward compatibility (R4, R18, R19):** validate the repo's current
   `state/tasks.json` against the edited schema and run `./init.sh` — both green with
   no manifest present.
2. **Slice schema (R1, R2):** a fixture feature with `slices[]` (each with `id`,
   `repo`, `depends_on`) validates; a malformed slice (missing `repo`) fails.
3. **Rollup (R3, R16):** with one slice not `done`, the derived feature status is not
   `done`; flip all slices to `done` AND a passing integration stub ⇒ feature `done`.
4. **Dispatch order + gating (R9–R13):** a fixture A→B→C dependency chain dispatches
   only A first; a stub delegate that exits 0 advances to B; a stub that exits non-zero
   on A halts B and C (R12) and the failure is surfaced; downstream is never dispatched
   before its upstream is `done`+merged (R11).
5. **Delegate seam (R10):** assert the coordinator invokes the manifest's
   `delegate_cmd` with exactly `<feature-id> <abs-spec-path>` and writes no source
   files in the (stub) child repo dir.
6. **Manifest (R5, R6):** the example manifest parses all four fields per repo; a slice
   naming a repo absent from the manifest is rejected with an error naming the repo.
7. **Integration gate (R14, R15, R17):** integration stub is not invoked until all
   slices `done`+merged; once invoked, a non-zero exit keeps the feature out of `done`
   and surfaces the failure.
8. **Contract pin (R7, R8):** the shared spec references exactly one contract-artifact
   id at a stable path; a sample emitted slice's `.tasks`/`.tests` references that id.

## Non-functional checks
- Lint: `<lint_command>` clean (none configured for this harness — n/a).
- Types: `<typecheck_command>` clean (none configured — n/a).
- Schema: `store/tasks.schema.json` remains valid draft-07 and a pure superset of the
  prior version (no field removed, no `required` tightened).
- Zero new runtime dependencies; `tests/test_umbrella.sh` runs under POSIX `sh`.
