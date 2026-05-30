---
id: E00-F01
title: Installer script
epic: E00-harness-install
status: in-review
sdd: true
autonomous: false
depends_on: []
owner: araozmd
---

# Installer script — Functional Spec

## Context
To use this harness on a real project you must get its files into that repo. Doing
it by hand is error-prone, and a pre-existing `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`
makes a naive copy destructive. `harness-install.sh <target>` installs the harness
body into `<target>/.harness/`, merges a delimited pointer block into existing
entrypoint files, and seeds a runnable workspace. Re-running it upgrades the body in
place. The intelligent, project-specific adaptation (product constitution, test
commands, first epics) is deferred to a first-run bootstrap driven by the harness
itself, so the installer stays deterministic.

## Business rules
- Deterministic and idempotent: install and upgrade are the same command.
- Never destroy user-authored content — neither their entrypoint prose nor their specs.
- Zero dependencies (POSIX sh only), matching `init.sh`'s ethos.
- The harness body is the stable chassis (overwritten on upgrade); project content is sacred (never clobbered).

## Acceptance criteria (EARS)
- **R1** — When the installer is run with a target path, the system shall copy the harness body (`AGENTS.md`, `harness.config.yaml`, `init.sh`, `agents/`, `docs/`, `store/`, `specs/_templates/`, `specs/glossary.md`) into `<target>/.harness/`.
- **R2** — When the installer runs, the system shall write `<target>/.harness/.harness-version` equal to the source `VERSION`.
- **R3** — When an entrypoint file (`CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`) already exists in the target, the system shall preserve its existing content and append exactly one delimited harness pointer block.
- **R4** — When the installer is re-run on a target that already has the harness, the system shall replace the existing pointer block in place rather than duplicate it.
- **R5** — While upgrading, the system shall not overwrite project-authored files (`.harness/specs/product.md`, `.harness/state/tasks.json`, `.harness/specs/epics/`, `.harness/progress/`).
- **R6** — When installing into a target with no prior harness, the system shall seed stub project files (`product.md`, a schema-valid bootstrap `tasks.json`, `progress/history.md`) so the harness is immediately runnable.
- **R7** — When the installer runs, the system shall generate Claude Code glue (`.claude/agents/*.md` and `.claude/commands/sdd-next.md`) whose paths resolve against `.harness/`.
- **R8** — When copying the config into the target, the system shall reset the verification commands (`test_command`, `lint_command`, `typecheck_command`) to empty.
- **R9** — If invoked with no target, or with a target equal to the harness source, then the system shall exit non-zero and make no changes.
- **R10** — The installed `.harness/init.sh` shall exit zero (structural + schema checks pass) when run from the target repo root.

## Out of scope
- Intelligent merge/rewrite of the user's existing instruction prose (only a marked block is added).
- Auto-detecting the target's test/lint/typecheck commands — deferred to first-run bootstrap.
- Wiring non-default store backends (obsidian/jira) at install time.

## Open questions
- Should `opencode.json` be merged (not just created-if-absent) when one already exists?
  (Current assumption: leave an existing one untouched and tell the user.)
