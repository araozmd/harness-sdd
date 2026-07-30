# Modern Codex skills and inherited role registration — Test Contract

| R-id | Behavior | Test (file::name/section) | Type | Status |
|---|---|---|---|---|
| R1 | Codex selection installs six valid repository-local skills containing the shared command instructions | `tests/test_install.sh::codex skill command surface and metadata` | integration | ⬜ |
| R2 | `sdd-pr-loop` skill follows `pr_loop.enabled` in the same run | `tests/test_pr_loop.sh::gate on/off Codex skill`; `tests/test_installer_toggles.sh::test_same_run_stamp_and_reclaim` | integration | ⬜ |
| R3 | Reconciliation removes pristine skills, preserves edited/user/Antigravity siblings, and prunes safely | `tests/test_install.sh::codex skill deselection/edit/coexistence`; `tests/test_pr_loop.sh::edited gated skill preservation` | integration | ⬜ |
| R4 | Current installs never write or advertise global Codex prompts | `tests/test_install.sh::codex no-global-write and no-HOME cases`; `tests/test_agents_host.sh::current Codex host output` | regression | ⬜ |
| R5 | Legacy cleanup requires pristine bytes and, for PR loop, an empty known ledger | `tests/test_install.sh::legacy prompt migration`; `tests/test_pr_loop.sh::legacy cross-target ownership`; `tests/test_agents_host.sh::foreign/edited prompt preservation` | integration | ⬜ |
| R6 | Selected Codex always has exactly six valid project-local role TOMLs | `tests/test_model_routing.sh::test_codex_agent_files_project_local`; `tests/test_model_routing.sh::all-inherit Codex roles` | integration | ⬜ |
| R7 | Inherited/unpinned roles omit `model`; pinned roles carry only their resolved value | `tests/test_model_routing.sh::test_inherit_is_omission`; `tests/test_model_routing.sh::Codex mixed pin assertions` | integration | ⬜ |
| R8 | Pin→inherit retains model-less roles; deselection preserves edited roles and reclaims pristine siblings | `tests/test_model_routing.sh::test_return_to_inherit_reconciles`; `tests/test_model_routing.sh::Codex deselection edit guard` | regression | ⬜ |
| R9 | Non-Codex adapter output contracts remain unchanged | `tests/test_install.sh::Claude/OpenCode/Antigravity command parity`; `tests/test_model_routing.sh::Gemini conditional tree`; full focused suite group | regression | ⬜ |
| R10 | Docs, manifest, changelog, and version expose the new contract | `tests/test_install.sh::manifest/docs contract`; `./init.sh` version/structure checks | static/integration | ⬜ |

## Behavioral / end-to-end checks

- Install with `--agents=codex` into an empty temporary target and verify `$sdd-next`
  resolves from `.agents/skills/sdd-next/SKILL.md`, all six named roles exist, no role
  contains a literal `model = "inherit"`, and the sandboxed `CODEX_HOME/prompts/`
  remains absent.
- Reinstall the same target with `pr_loop.enabled` toggled on then off; verify only the
  `sdd-pr-loop` skill changes and the six ungated skills remain byte-identical.
- Install `antigravity,codex`, then deselect each in turn; verify the remaining adapter's
  `.agents` subtrees survive and an edited skill/workflow is never removed.
- Seed legacy pristine and edited global prompts in a sandboxed `CODEX_HOME`, run an
  upgrade, and verify only the artifacts satisfying R5's proof are reclaimed.
- Configure one pinned Codex role among inherited roles, then return it to inherit;
  verify all six roles remain registered and every inherited TOML omits `model`.

## Non-functional checks

- Initialization: `./init.sh` clean.
- Focused suites: `sh tests/test_install.sh`; `sh tests/test_model_routing.sh`;
  `sh tests/test_pr_loop.sh`; `sh tests/test_installer_toggles.sh`;
  `sh tests/test_agents_host.sh`.
- Full gate: execute `verification.test_command` from `harness.config.yaml`.
- New external dependencies: none.
