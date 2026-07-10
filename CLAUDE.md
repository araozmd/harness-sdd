# CLAUDE.md

Claude Code entrypoint. **Read [`AGENTS.md`](./AGENTS.md) first.** Everything below
is Claude Code–specific glue.

## Sub-agents

The role prompts in `agents/*.md` are mirrored as Claude Code sub-agents in
`.claude/agents/` so the Orchestrator can spawn them with the Task tool, each in a
clean context. The `agents/*.md` files remain canonical — the `.claude/agents/`
versions just point at them.

## Slash commands

- `/sdd-next` — run the Orchestrator loop on the next actionable task
  (see `.claude/commands/sdd-next.md`).

## PR reviews

Once local tests pass, create a PR and use the `/pr-loop` skill to invoke Codex
reviews. Wait for the feature to merge before starting the next one unless the
next task is explicitly marked as autonomous.
