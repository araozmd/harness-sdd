# Modern Codex skills and inherited role registration — Technical Plan

## Stack & dependencies

- Language/runtime: POSIX `sh`, existing Python-backed test/validation helpers, Markdown,
  and TOML emitted as text.
- New dependencies: none.
- Native contracts: Codex project skills live at
  `.agents/skills/<skill-name>/SKILL.md`; project custom agents live at
  `.codex/agents/<role>.toml`, where `model` is optional but `name`, `description`, and
  `developer_instructions` are required.

## Data model (serves: R1, R2, R6, R7)

No product data or TaskStore schema changes.

| Artifact | Required fields/content | Ownership rule |
|---|---|---|
| `.agents/skills/<command>/SKILL.md` | YAML `name`, YAML `description`, shared command instructions | Project-local; remove only when byte-pristine |
| `.codex/agents/<role>.toml` | `name`, `description`, `developer_instructions`; optional resolved `model` | Project-local; existing model-agent stamp guards reclamation |
| `${CODEX_HOME:-$HOME/.codex}/prompts/<command>.md` | Legacy artifact only; never newly installed | Migrate only under R5's byte/ledger proof |

## API / interface (serves: R1, R2, R6, R7)

| Interface | Input | Output | R-id |
|---|---|---|---|
| `harness-install.sh --agents=codex <target>` | selected target and resolved config | project-local skills plus six named role TOMLs | R1, R6, R7 |
| Codex explicit skill invocation | `$sdd-next`, `$sdd-new`, `$sdd-plan`, `$sdd-drill`, `$sdd-fix`, `$sdd-fix-parallel` and gated `$sdd-pr-loop` | the corresponding shared SDD workflow | R1, R2 |
| Installer reconciliation | prior selection, current selection, `pr_loop.enabled`, legacy prompt bytes/ledger | pristine-only cleanup and diagnostics | R2, R3, R5, R8 |

## Files to change (serves: R1–R10)

| File | Change | R-id |
|---|---|---|
| `harness-install.sh` | Add a deterministic Codex skill emitter based on the existing `CMDDIR` command bodies; install/reconcile `.agents/skills`; stop global prompt installation/advertising; retain a legacy-only prompt resolver and consolidate safe migration; always emit selected Codex role TOMLs while keeping `model` optional; update the generated manifest/help text | R1–R8, R10 |
| `tests/test_install.sh` | Replace global-prompt command-surface assertions with skill layout/frontmatter/body assertions; cover selection/deselection, edited-skill preservation, legacy pristine/edited prompt migration, no-HOME operation, and coexistence with Antigravity | R1–R6, R9 |
| `tests/test_model_routing.sh` | Change the Codex all-inherit/unpinned expectations to six model-less role TOMLs; verify pin→inherit retains roles and removes only the model key; retain project-local and deselection/edit guards; leave Gemini expectations unchanged | R6–R9 |
| `tests/test_pr_loop.sh` | Move Codex gate assertions from the global prompt to `.agents/skills/sdd-pr-loop/SKILL.md`; retain legacy owners-ledger migration cases separately; continue asserting no Codex `pr-fixer` role | R2–R5, R9 |
| `tests/test_installer_toggles.sh` | Update same-run PR-loop on/off reconciliation and artifact comparisons to the repository skill while retaining legacy-ledger safety coverage | R2–R5, R9 |
| `tests/test_agents_host.sh` | Update host-selection expectations so current Codex glue is project-local and legacy global prompts are migration-only, without weakening foreign/edited prompt preservation cases | R3–R5, R9 |
| `README.md` | Replace `/prompts:sdd-*` and global-path instructions with `.agents/skills` and `$sdd-*`; update the compatibility/layout tables | R10 |
| `docs/HARNESS.md` | Document Codex skills alongside the unchanged command mirrors for the other front-ends | R10 |
| `docs/INSTALL.md` | Document the installed skill/role layout, selection/reclamation behavior, legacy prompt migration, model omission under inherit, and project trust | R10 |
| `CHANGELOG.md` | Add the `0.48.0` E23-F01 release entry | R10 |
| `VERSION` | Bump `0.47.0` to `0.48.0` because the installed body gains a backward-compatible current-Codex adapter capability | R10 |

## DO NOT TOUCH

- `.claude/commands/`, `.claude/agents/`, `.opencode/command/`,
  `.opencode/agent/`, `opencode.json`, `.agents/rules/`, `.agents/agents/`,
  `.agents/workflows/`, and `.gemini/agents/` generated semantics — regression
  assertions may change only to prove they remain unaffected.
- `agents/*.md`, `tools/wait-for-codex.sh`, `tools/next-task.mjs`,
  `harness.config.yaml`, `store/tasks.schema.json`, and the TaskStore/state machine.
- The shared command bodies emitted into `CMDDIR`; Codex skills adapt metadata/location,
  not workflow behavior.
- Any user-edited or foreign file in `.agents/`, `.codex/`, or the legacy global prompts
  directory.

## Approach notes

1. Generate each Codex `SKILL.md` from the corresponding already-generated `CMDDIR`
   command. Replace only its command frontmatter with the skill's required stable
   `name`/`description`; copy the instruction body without re-authoring it.
2. Centralize skill install and reclamation so deselection and PR-loop gate-off call the
   same deterministic emitter/reference. Use named paths and `rmdir`, never recursive
   deletion of `.agents`, because Antigravity and user skills share that parent.
3. Keep global-path resolution only for legacy migration. The normal Codex install path
   never requires `CODEX_HOME` or `HOME`, never claims a prompt ledger, and never writes a
   prompt. Compare ungated legacy files to the generated command reference; apply the
   existing `_owners_release` fail-safe before considering `sdd-pr-loop`.
4. Decouple Codex roles from `models_any codex`: always iterate `ag_personas` when Codex
   is selected and stamp the generated bytes. Keep Gemini's conditional path unchanged.
   Returning to inherit regenerates the same required role with no `model`; only
   deselection calls `reclaim_model_agents codex`.
5. Write failing behavioral tests first for each changed contract, then make the smallest
   installer change. Preserve existing tests that establish other front-end behavior.
