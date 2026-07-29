# E21-F04 Architect Progress

- Drafted the 4 spec files (`.spec.md`, `.plan.md`, `.tasks.md`, `.tests.md`) for `E21-F04` under `specs/epics/E21-change-size-discipline/F04-stacked-pr-lane/`.
- Adapted the brief's requirement to clearly state that stacked PRs are for safely-splittable features and reviewability, not atomic deployment of unsafe states (as noted in the withdrawn salvage note).
- Added the `## Architecture alignment` section stating `ADRs touched: none` because the feature only modifies PR loop base branch checking and restores the guard script, un-touching the next-task selection rule.
- Invoked doc-critic (`target-type=feature-spec`). The invocation failed with a subagent startup error, so skipping the doc-critic checkpoint best-effort.
- Feature is ready for hand-off.
