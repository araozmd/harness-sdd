---
id: E23-F01
title: Modern Codex skills and inherited role registration
epic: E23-codex-native-compatibility
status: done
sdd: true
autonomous: true
depends_on: []
---

# Modern Codex skills and inherited role registration — Functional Spec

## Context

The portable SDD lifecycle is compatible with Codex, but the installer still targets
Codex's deprecated global custom-prompt surface, which is not the supported
project-workflow surface, and makes named role registration depend on an optional model
pin. Engineers selecting Codex need current, repository-scoped workflow discovery and
named agents under the default inherited-model configuration, without changing any other
front-end adapter.

## Business rules

- Codex workflow commands are project artifacts, not machine-global preferences.
- The canonical workflow content remains the installer-generated command body shared by
  all front-ends; only Codex's native skill metadata and location differ.
- Command discovery and role registration are independent from model routing.
- Installer-owned artifacts may be reclaimed only when they are byte-pristine; edited or
  ownership-ambiguous legacy files survive with a diagnostic.
- `sdd-pr-loop` remains opt-in and its Codex skill follows the existing
  `pr_loop.enabled` gate.
- Claude Code, OpenCode, Antigravity, and Gemini keep their existing paths, generated
  bytes, selection gates, and invocation semantics.

## Architecture input

`specs/architecture.md` is absent, so this feature proceeds from the inception brief
without an architecture citation. The repository's existing platform ADR-0001 governs
deterministic task selection and is not touched by this installer-adapter change.

## Acceptance criteria (EARS)

- **R1** — When `codex` is selected, the installer shall create one repository-local
  Codex skill at `.agents/skills/<command>/SKILL.md` for each command in
  `sdd-next`, `sdd-new`, `sdd-plan`, `sdd-drill`, `sdd-fix`, and
  `sdd-fix-parallel`, with valid `name`/`description` frontmatter and the shared
  argument-forwarding, installed-layout command instructions.
- **R2** — Where `pr_loop.enabled` resolves to `true`, the installer shall create
  `.agents/skills/sdd-pr-loop/SKILL.md`; where it does not resolve to `true`, the
  installer shall not leave a byte-pristine `sdd-pr-loop` Codex skill discoverable.
- **R3** — When Codex is deselected or a Codex skill becomes gated off, the installer
  shall remove only byte-pristine harness skill artifacts, preserve edited skill files,
  prune only directories that are empty, and preserve Antigravity's sibling `.agents`
  subtrees and user-owned files.
- **R4** — When any install or upgrade runs, the installer shall not create, overwrite,
  or advertise `${CODEX_HOME:-$HOME/.codex}/prompts/sdd-*.md` as the active Codex
  command surface.
- **R5** — When a legacy global Codex prompt is considered for migration, the installer
  shall delete it only when it is byte-identical to the generated legacy command
  reference and, for `sdd-pr-loop`, the existing owners ledger proves that no live
  target still claims it; otherwise it shall preserve the prompt and report why.
- **R6** — When `codex` is selected, the installer shall generate project-local TOML
  definitions for exactly the six standard roles under `.codex/agents/`, each with
  `name`, `description`, and `developer_instructions`, regardless of whether any model
  pin resolves.
- **R7** — While a Codex role resolves to `inherit` or to an unpinned tier, its TOML
  definition shall omit `model`; when a concrete Codex model pin resolves, only that
  role's TOML definition shall contain the resolved `model` value.
- **R8** — When a selected Codex target moves between pinned and inherited model
  routing, the installer shall regenerate its harness-owned role definitions without
  deleting the role tree, and when Codex is deselected it shall preserve edited role
  files while reclaiming byte-pristine role files.
- **R9** — The installer regression suite shall demonstrate that Codex-only selection
  produces only the new Codex-owned project glue and that Claude Code, OpenCode,
  Antigravity, and Gemini retain their pre-feature generated command/persona behavior.
- **R10** — When this feature ships, the installed manifest, README, installation
  guide, harness guide, changelog, and public version shall describe repository-local
  `$sdd-*` Codex skills, always-present selected Codex roles, legacy prompt migration,
  and release version `0.49.0`.

## Out of scope

- Changing the SDD state machine, role responsibilities, TaskStore schema, human gate,
  Reviewer verdict, or command instruction bodies.
- Adding a Codex plugin package, changing Codex runtime concurrency, or creating a Codex
  `pr-fixer` role.
- Changing model-tier resolution or model artifacts for Claude Code, OpenCode,
  Antigravity, or Gemini.
- Deleting an edited or ownership-ambiguous legacy global prompt.

## Open questions

- None. The autonomous brief selects repository-local skills and preserves the existing
  PR-loop/model-routing policies.
