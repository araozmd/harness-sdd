# E23-F01 Builder handoff

## Status

DONE_WITH_CONCERNS — implementation and focused feature verification are complete.
The exact repository-wide `verification.test_command` is blocked later by the known,
out-of-scope Inception fallback validation of existing draft epic statuses.

## Scope

- Worktree: `.worktrees/feat-codex-skill-adapter`
- Builder backend: `in-session`
- Feature state confirmed `in-progress` in `state/tasks.json`.
- The approved four-file feature spec is the design gate; no role or TaskStore semantics
  are being changed.

## RED evidence

1. `sh tests/test_install.sh`
   - Exit: `1`
   - Expected feature failure:
     `FAIL: codex: project skill sdd-next/SKILL.md not installed`
   - This proves the new R1/R4 test reaches the current installer and fails because the
     repository-local Codex skill surface is missing.
   - All preceding baseline installer assertions passed.
2. `sh tests/test_install.sh` after the minimal local-skill emitter
   - Exit: `1`
   - Expected reconciliation failure:
     `FAIL: R3: deselected pristine Codex skill was not removed`
   - The new R1/R4 skill metadata/body/no-global assertions passed before this failure,
     establishing GREEN for the install path and RED for pristine-only deselection.
3. `sh tests/test_model_routing.sh`
   - Exit: `1`
   - Expected role-registration failure:
     `FAIL: R6/R7: unpinned Codex omitted registered role orchestrator`
   - Earlier tier/inherit/alias checks passed; failure is specifically the old
     `models_any codex` creation gate.

## GREEN evidence

1. `sh tests/test_install.sh`
   - Exit: `0`
   - Result: `All install tests passed.`
   - Covers local skill metadata/canonical bodies, no global write, no-HOME operation,
     pristine-only deselection, edited/Antigravity/user sibling preservation, and initial
     legacy migration cases.
2. `sh tests/test_model_routing.sh`
   - Exit: `0`
   - Result: `All model-routing tests passed.`
   - Covers exactly six selected Codex role TOMLs under inherit/unpinned routing,
     model-key omission, concrete pins, pin→inherit regeneration, and pristine-only
     deselection while Gemini remains conditional.
3. Focused feature suite group (fresh after documentation/version updates):
   - `sh tests/test_install.sh` — exit `0`, `All install tests passed.`
   - `sh tests/test_model_routing.sh` — exit `0`, `All model-routing tests passed.`
   - `sh tests/test_pr_loop.sh` — exit `0`, `All pr-loop tests passed.`
   - `sh tests/test_installer_toggles.sh` — exit `0`,
     `All installer-toggle tests passed.`
   - `sh tests/test_agents_host.sh` — exit `0`, `All agents-host tests passed.`
   - An intermediate focused run exposed one stale pre-feature assertion
     (`R11: unconfigured install created .codex/agents/`); the test was corrected to
     require six model-less selected Codex roles, then the suite passed.

## Implementation

- Replaced active machine-global Codex prompt installation with deterministic,
  repository-local `.agents/skills/<command>/SKILL.md` generation. Each skill has YAML
  `name`/`description` metadata followed by the canonical command instruction body.
- Added pristine-only skill reconciliation for Codex deselection and the
  `pr_loop.enabled` gate. Cleanup removes only the named generated files and prunes only
  empty directories, preserving edited files and Antigravity/user siblings.
- Added fail-safe migration for legacy global `sdd-*.md` prompts. Only byte-identical
  legacy prompts are eligible; `sdd-pr-loop.md` also requires a readable ownership
  ledger proving no live target still claims it.
- Made selected Codex installations always register exactly six project-local role
  TOMLs. Inherit/unpinned routing omits `model`; concrete pins add it only where
  resolved; pin-to-inherit regenerates the role without deleting the role tree.
- Updated focused installer/host/model/pr-loop/toggle tests, active-surface
  documentation, the changelog, and the public version (`0.48.0`).

## Final verification

1. Exact configured command from `harness.config.yaml`:
   - `sh tests/test_install.sh && sh tests/test_umbrella.sh && sh tests/test_cascade.sh && sh tests/test_inception.sh && ...`
   - Exit: `1`
   - Passed before stopping:
     - `All install tests passed.`
     - `All umbrella tests passed.`
     - `All cascade tests passed.`
   - Sole stopping failure:
     `FAIL: R6: state/tasks.json failed schema validation`
   - The preceding diagnostics identify the existing `epic[11].status` and
     `epic[12].status` draft-state incompatibility in the zero-dependency Inception
     fallback. This is unrelated to the Codex adapter and outside Builder ownership, so
     it was not changed.
2. Fresh mandatory `./init.sh`
   - Exit: `0`
   - Result: `✅ environment ready — agents may proceed`
3. Static checks:
   - `sh -n harness-install.sh` and all owned shell tests — exit `0`.
   - `git diff --check` — exit `0`.
   - Active documentation no longer advertises the retired global prompt surface.

## Handoff

- Review the Codex-only installer paths, especially legacy ownership-ledger migration.
- The controller owns latest-main reconciliation, PR-loop execution, merge waiting, and
  branch cleanup.
