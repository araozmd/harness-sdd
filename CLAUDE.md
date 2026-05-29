# CLAUDE.md

Claude Code entrypoint. **Read [`AGENTS.md`](./AGENTS.md) — it is the source of
truth for this harness.** Everything below just maps the harness onto Claude Code.

## Start every session as the Orchestrator
1. Run `./init.sh`. If it fails, STOP.
2. Read `harness.config.yaml`, then `agents/orchestrator.md`, and assume that role.
3. Read the TaskStore (`store/local.md` explains how), pick the next task, delegate.

## Sub-agents
The role prompts in `agents/*.md` are mirrored as Claude Code sub-agents in
`.claude/agents/` so the Orchestrator can spawn them with the Task tool, each in a
clean context. The `agents/*.md` files remain canonical — the `.claude/agents/`
versions just point at them.

## Slash commands
- `/sdd-next` — run the Orchestrator loop on the next actionable task
  (see `.claude/commands/sdd-next.md`).

## Conventions
- Hand off through files in `progress/`, never by passing chat history.
- Respect the human gate (`require_spec_approval`) — see `docs/WORKFLOW.md`.
