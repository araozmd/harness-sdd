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
