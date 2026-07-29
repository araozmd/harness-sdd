# Modern Codex skills and inherited role registration — Tasks

> Execute sequentially. For each behavioral change, add or update the named test first,
> run it to observe the expected failure, then implement the smallest passing change.

- [ ] **T1** (R1, R4) — Update `tests/test_install.sh` with failing Codex-only
  assertions for six repository skills with valid metadata/shared bodies and no newly
  written global prompts.
- [ ] **T2** (R1, R3, R4) — Add the Codex skill emitter/install/reclamation
  helpers and replace the normal global-prompt install block in `harness-install.sh`;
  make the T1 cases pass without changing other front-end emitters.
- [ ] **T3** (R2, R3) — Add failing PR-loop on/off, deselection, edited-skill, and
  Antigravity-coexistence cases in `tests/test_pr_loop.sh`,
  `tests/test_installer_toggles.sh`, and `tests/test_install.sh`.
- [ ] **T4** (R2, R3) — Route gated Codex skill installation and all skill cleanup
  through the shared emitter/reference; prune only empty skill directories and make T3
  pass.
- [ ] **T5** (R4, R5) — Add failing legacy-migration cases covering pristine ungated
  prompts, edited prompts, ledger-protected `sdd-pr-loop`, and absent
  `HOME`/`CODEX_HOME` in `tests/test_install.sh`, `tests/test_pr_loop.sh`, and
  `tests/test_agents_host.sh`.
- [ ] **T6** (R4, R5) — Refactor the old global prompt/ledger code into a legacy-only,
  fail-safe migration path and make T5 pass without creating or claiming global prompts.
- [ ] **T7** (R6, R7, R8) — Update `tests/test_model_routing.sh` with failing cases for
  six all-inherit/unpinned Codex roles and pin→inherit role retention, while preserving
  Gemini's conditional expectations and Codex deselection/edit guards.
- [ ] **T8** (R6, R7, R8) — Always generate/stamp the six selected Codex role TOMLs,
  omit only unresolved `model` keys, and reserve `reclaim_model_agents codex` for
  deselection; make T7 pass.
- [ ] **T9** (R9) — Run the focused installer, model-routing, PR-loop,
  installer-toggle, and host-detection suites; fix only regressions attributable to the
  Codex adapter and confirm non-Codex artifact assertions remain green.
- [ ] **T10** (R10) — Update `README.md`, `docs/HARNESS.md`, `docs/INSTALL.md`, the
  installer-generated manifest/help text, `CHANGELOG.md`, and `VERSION` to `0.48.0`.
- [ ] **T11** (R1–R10) — Run `./init.sh` and the complete
  `verification.test_command`; record the exact commands/results for Reviewer hand-off.
