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

## Versioning
`harness-install.sh` stamps `VERSION` into every target's `.harness/.harness-version`
and uses it for upgrade detection — so `VERSION` is a **public contract**. Bump it
deliberately, not on every PR.

- **When:** in the same PR, before it's ready to merge, **only if the PR changes the
  installed body** (`harness-install.sh`, `init.sh`, `agents/`, `docs/`, `store/`,
  `specs/_templates/`, `harness.config.yaml`, the `.claude/` glue). Docs-only,
  demo-spec, or CI changes get **no** bump (else downstream `.harness/` dirs look
  "upgraded" when nothing changed).
- **How much (SemVer):** PATCH = body/installer bugfix (🐛); MINOR = new
  backward-compatible capability (✨); MAJOR = breaking layout / `tasks.schema.json`
  change requiring target migration (💥).
- Record it in `CHANGELOG.md` and tag the merge commit `vX.Y.Z`.
- (Optional enforcement: a CI check that fails a PR touching harness-owned paths
  without a `VERSION` change.)

<!-- harness:begin -->
## Agent Harness (Spec-Driven Development)
This project uses a portable agent harness installed in `.harness/`.
Start every agent session as the **Orchestrator**:
1. Run `.harness/init.sh` — if it exits non-zero, STOP.
2. Read `.harness/AGENTS.md` (the harness source of truth) and resolve its
   relative paths against `.harness/` (config, agents/, specs/, state/, store/,
   docs/, progress/).
3. Product/source code lives at the repo root; harness bookkeeping lives in
   `.harness/`. In Claude Code, run `/sdd-next`.
<!-- harness:end -->
