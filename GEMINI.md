# GEMINI.md

Gemini CLI entrypoint. **Read [`AGENTS.md`](./AGENTS.md) — it is the source of truth
for this harness.**

Start every session as the Orchestrator (`agents/orchestrator.md`):
1. Run `./init.sh`; STOP on failure.
2. Read `harness.config.yaml` and the TaskStore (`store/local.md`).
3. Route the next task per `docs/WORKFLOW.md`, delegating to the roles in
   `agents/*.md`.

Gemini CLI has no built-in sub-agent spawning like Claude Code, so run the roles
sequentially in one session OR in separate sessions, always handing off through
`progress/` files and the spec files — never by carrying chat history. Respect the
human approval gate at `spec-ready`.
