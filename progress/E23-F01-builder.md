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

---

## Review round 2

### Status

DONE_WITH_CONCERNS — all round-2 focused behavior/docs suites, cross-version non-Codex
byte checks, static checks, and the environment gate are green. The unchanged
repository-wide Inception fallback concern recorded in round 1 remains out of scope.

### Feedback diagnosis

1. Selected skill and role generation redirected into live files before consulting the
   existing last-written role stamps, and skills had no stamps at all.
2. Byte identity proved content, not cross-target ownership, for ungated legacy global
   prompts.
3. Copying the canonical `$ARGUMENTS` token did not define how Codex text accompanying
   an explicit `$skill` invocation supplies that value.
4. A lone `SKILL.md` left these mutating workflows implicitly invocable because Codex's
   documented default is `true` without `agents/openai.yaml`.

### RED evidence

1. `sh tests/test_install.sh`
   - Exit: `1`
   - Expected first failure:
     `FAIL: codex: project skill sdd-next has no agents/openai.yaml`
   - The same new block asserts explicit-only policy, `$skill` → `$ARGUMENTS` mapping,
     two-file ownership stamps, foreign/edited preservation, stamped update/reclaim,
     and ownership-unknown ungated legacy preservation.
2. `sh tests/test_model_routing.sh`
   - Exit: `1`
   - Expected failure:
     `FAIL: E23 review: selected Codex install overwrote a foreign orchestrator role`
3. Focused legacy migration reproduction
   - Exit: `1`
   - Expected failure:
     `FAIL: ownership-unknown ungated legacy prompt deleted`
4. `tests/test_pr_loop.sh` gained explicit-only two-file unit assertions while retaining
   its existing ledger matrix: live owner preserves, last/cleared owner reclaims, and
   missing/unreadable ownership fails closed.

### Implementation

- Each Codex skill now consists of `SKILL.md` plus `agents/openai.yaml`; the latter sets
  `policy.allow_implicit_invocation: false`.
- The skill adapter explicitly maps all text accompanying `$<skill>` to `$ARGUMENTS`,
  then preserves the canonical command body byte-for-byte under a named boundary.
- `.harness/.codex-skills/<command>/` stores the last-written two-file unit. Selected
  install, gate-off, and deselection update/reclaim only absent, current-generated, or
  stamp-matching units; foreign/edited units remain byte-identical with diagnostics.
- Selected Codex role writes now consult `.harness/.model-agents/codex/` before
  replacement. Foreign/edited standard role files survive; stamp-matching files still
  update across routing changes and reclaim on deselection.
- Ungated legacy prompts are always preserved as ownership-unknown. Only byte-pristine
  `sdd-pr-loop` with a readable ledger proving no live owners is reclaimed.
- README, HARNESS/INSTALL docs, manifest text, and CHANGELOG now state these boundaries.

### Focused GREEN evidence

- `sh tests/test_install.sh` — exit `0`, `All install tests passed.`
- `sh tests/test_model_routing.sh` — exit `0`,
  `All model-routing tests passed.`
- `sh tests/test_pr_loop.sh` — exit `0`, `All pr-loop tests passed.`
- `sh tests/test_installer_toggles.sh` — exit `0`,
  `All installer-toggle tests passed.`
- `sh tests/test_agents_host.sh` — exit `0`, `All agents-host tests passed.`

### Final round-2 verification

- Fresh parallel rerun:
  - `sh tests/test_model_routing.sh` — exit `0`.
  - `sh tests/test_pr_loop.sh` — exit `0`.
  - `sh tests/test_installer_toggles.sh` — exit `0`.
  - `sh tests/test_agents_host.sh` — exit `0`.
- Fresh `sh tests/test_install.sh` after documentation/manifest updates — exit `0`.
- Cross-version non-Codex byte comparison:
  - Generated the Claude, OpenCode, Antigravity, and Gemini surfaces with the
    round-1 installer (`77d5184`) and the round-2 installer under identical selected
    front-ends, PR-loop gate, and model routing.
  - `diff -r` passed for `.claude`, `.opencode`, `.agents/{rules,agents,workflows}`,
    `.gemini`, `opencode.json`, `CLAUDE.md`, `GEMINI.md`, and `AGENTS.md`.
- `./init.sh` — exit `0`, `✅ environment ready — agents may proceed`.
- `sh -n` on the installer and all five owned shell suites — exit `0`.
- `git diff --check` — exit `0`.
- Unsafe active-surface claim scan — no stale claim that ungated legacy prompts are
  reclaimed or that Codex still writes the retired global prompt surface.

---

## Review round 3

### Status

DONE_WITH_CONCERNS — the narrow partial-state fix, focused suites, non-Codex byte check,
environment gate, and static checks are green. The unchanged out-of-scope Inception
fallback concern from round 1 remains.

### Root cause

`reclaim_codex_skills` required both live paths and both last-written stamps to match
before deleting either path. If `agents/openai.yaml` was missing or edited, the helper
left a separately stamp-owned `SKILL.md` discoverable after gate-off or Codex
deselection.

### RED evidence

- `sh tests/test_install.sh`
  - Exit: `1`
  - Expected failure:
    `FAIL: R3 partial: missing companion stranded a stamp-owned SKILL.md on deselect`
- `sh tests/test_pr_loop.sh`
  - Exit: `1`
  - Expected failure:
    `FAIL: R5 partial: missing companion stranded a stamp-owned gated SKILL.md`
- Both suites also include the edited-companion variant. The existing edited-`SKILL.md`
  case continues to require its explicit-only policy companion to survive.

### Fix

- Reconciliation now proves and reclaims `SKILL.md` and `agents/openai.yaml`
  individually from their respective last-written stamps.
- A stamp-owned `SKILL.md` is removed even when companion metadata is missing or edited.
- Unproven individual paths are preserved.
- If an edited/foreign `SKILL.md` survives, its policy companion is deliberately retained
  even when the policy itself matches its stamp, preventing the surviving mutating skill
  from becoming implicitly invocable.
- Directory cleanup remains `rmdir`-only.

### Focused GREEN evidence

- `sh tests/test_install.sh` — exit `0`, `All install tests passed.`
- `sh tests/test_pr_loop.sh` — exit `0`, `All pr-loop tests passed.`
- The model-agent helper was not changed, so no model-routing behavior was in the patch.
- Cross-version generation against round-2 commit `5f0bd97` passed byte-for-byte for
  Claude, OpenCode, Antigravity, and Gemini surfaces.
- Fresh `./init.sh` — exit `0`, `✅ environment ready — agents may proceed`.
- `sh -n harness-install.sh tests/test_install.sh tests/test_pr_loop.sh` — exit `0`.
- `git diff --check` — exit `0`.
