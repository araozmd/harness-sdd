# E03-F01 Umbrella coordinator — Architect hand-off

Date: 2026-05-30
Author: Architect
Status: spec drafted, ready for `spec-ready` gate (awaiting Orchestrator + human approval)

## Produced (4-file spec)
- specs/epics/E03-multi-repo/F01-umbrella-coordinator/umbrella-coordinator.spec.md
- specs/epics/E03-multi-repo/F01-umbrella-coordinator/umbrella-coordinator.plan.md
- specs/epics/E03-multi-repo/F01-umbrella-coordinator/umbrella-coordinator.tasks.md
- specs/epics/E03-multi-repo/F01-umbrella-coordinator/umbrella-coordinator.tests.md

Frontmatter: id E03-F01, epic E03, status pending, sdd true, depends_on [].

## Shape of the design (all additive, no role forks)
- 19 EARS requirements (R1–R19), each mapped to a concrete check in .tests.md.
- TaskStore: optional `slices[]` on a feature (id `<feature-id>@<repo>`, plus repo,
  status, merged, spec_path, cross-repo depends_on). Pure superset — single-repo
  stores validate unchanged (R4, R19).
- Manifest: new umbrella-only `umbrella.manifest.yaml` (repo -> path/init/test/delegate);
  its presence is the opt-in switch (R18).
- Config: additive `umbrella.manifest` + `verification.integration_command`.
- Execution: reuses the existing `execution.builder.delegate` seam verbatim
  (`<delegate_cmd> <feature-id> <abs-spec-path>`); umbrella never writes source (R10).
- Gating: topological select on `depends_on`, no downstream dispatch/PR until upstream
  done+merged (R9, R11), fail-stop on non-zero delegate (R12).
- Rollup: feature `done` is derived, never set — all slices done AND integration
  command green (R3, R16).
- Contract artifact pinned once, format intentionally unspecified (R7, R8).

## Open questions for the human gate (do not lock schema until resolved)
1. Slice id form: proposed `<feature-id>@<repo>` (e.g. `E03-F01@viernes-bff`). Confirm.
2. Coordinator loop home: proposed additive "Umbrella mode" section appended to
   agents/orchestrator.md + additive config, NOT a forked role. Confirm.
3. Integration command key name: proposed `verification.integration_command`. Confirm.

## Notes
- No production/application code written (Architect scope).
- I did NOT change state/tasks.json status — that is the Orchestrator's call.
- Per epic.md, the implementing PR warrants a SemVer MINOR bump (changes schema +
  config + orchestrator glue).
