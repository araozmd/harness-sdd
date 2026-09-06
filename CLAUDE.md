# CLAUDE.md

Claude Code entrypoint. **Read [`AGENTS.md`](./AGENTS.md) first.** Everything below
is Claude Code–specific glue.

## Sub-agents

The role prompts in `agents/*.md` are mirrored as Claude Code sub-agents in
`.claude/agents/` so the Orchestrator can spawn them with the Task tool, each in a
clean context. The `agents/*.md` files remain canonical — the `.claude/agents/`
versions just point at them.

**Do not hand-edit `.claude/agents/*` or `.claude/commands/*`** (E26-F01): they are
GENERATED — run `sh harness-install.sh --self` after changing an emitter (or a shim's
`model:` line, which `--self` harvests and preserves) and commit the regenerated
files. Hand edits are clobbered by the next `--self` run.

## Slash commands

- `/sdd-next` — run the Orchestrator loop on the next actionable task
  (see `.claude/commands/sdd-next.md`).
- `/sdd-pr-loop` — drive the Codex review cycle on an open PR
  (see `.claude/commands/sdd-pr-loop.md`). Installed only while `pr_loop.enabled`
  is true in `harness.config.yaml` — an **opt-in** gate that a fresh install seeds
  `false`; this repo sets it `true` because it has the Codex GitHub App.

## PR reviews

Once local tests pass, create a PR. If `/sdd-pr-loop` is installed, run it to drive
the Codex review cycle (trigger, background watch, classify, fix, merge). If it is
not installed — `pr_loop.enabled` left at its opt-in default of `false`, or the repo
has no Codex GitHub App —
request the review and address the blocking findings by hand instead. Either way,
wait for the feature to merge before starting the next one unless the next task is
explicitly marked as autonomous.
