# E99-F09: Update Antigravity integration to use Skills architecture

## Context
The current Antigravity integration in the harness uses obsolete `workflows` and `agents` (personas) directories. Antigravity has migrated to a new `skills` architecture where capabilities are defined as skills with YAML frontmatter containing `name` and `description`.

## Requirements
- `harness-install.sh` must install Antigravity support into `.agents/skills/` instead of `.agents/workflows/` and `.agents/agents/`.
- Each installed skill must include YAML frontmatter with a `name` and `description`.
- Unused persona files (like `coder.md`) should no longer be generated for Antigravity.
- The `deselect` logic in `harness-install.sh` must cleanly remove the new `skills` directory and leave no orphaned files, using the `remove_if_pristine` mechanism.
- Backward compatibility with other CLI tools (Claude Code, OpenCode, Codex) must be maintained.

## Constraints
- The source files for commands are shared among CLIs. The YAML frontmatter for Antigravity skills must be dynamically injected during the copy/install process in `harness-install.sh`, not added to the source templates, to avoid breaking other tools.
- The removal logic must only remove directories that were created by the harness and have not been modified by the user in ways that violate the pristine condition.
