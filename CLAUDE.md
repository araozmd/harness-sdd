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

## Way of work
- Every new work, feature or bug should have its own branch
- Once all locall verifications and tests passed, create a new PR and use the 
  skill /pr-loop to invoke Codex reviews
- Once a brach is merged delete remote and local branch and go back to main 
  to keep the repo clean
