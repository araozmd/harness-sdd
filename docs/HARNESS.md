# What a harness is (and why this one is built this way)

A **harness** is the environment you build *around* a model: the context, tools,
memory, and verification that turn a powerful-but-wild model into a reliable worker.
The model is the engine (or the horse); the harness is the chassis (or the reins).

**The core bet:** *models change every few months; your harness does not.* Build on
files you own and you can swap the brain — Claude today, Gemini or a local model
tomorrow — and swap the CLI — Claude Code, Codex, Gemini CLI, OpenCode — without
rewriting your system. That portability is the whole point of using `AGENTS.md` and
plain files instead of a vendor wrapper.

## The four components

1. **Context** — what the model is told. Kept minimal and curated per agent.
2. **Tools** — what it can do. Minimal beats inflated (Bash + filesystem first).
3. **Memory** — what it remembers across sessions. Externalized to files.
4. **Verification** — proof the work is actually correct. `init.sh` + tests + Reviewer.

## The five principles this harness enforces

1. **The harness lives in the repo.** It's `AGENTS.md` + `agents/` + `specs/` +
   `progress/` + `init.sh`. No external app, no magic — just files that reference
   each other.

2. **Minimal tooling.** Specialized tools degrade agents. (Vercel cut 80% of D0's
   tools, left it Bash + filesystem → 3× faster, ~47% fewer tokens, 80%→100%
   success.) Add a tool only when a real task proves it's needed.

3. **Externalize memory.** Models degrade well before the context window is full.
   Keep state in `state/`, `specs/`, `progress/`; read only what's needed; reset
   context and resume from files.

4. **Separate roles.** One agent that plans + codes + reviews saturates its context
   and reasons worse. A team — Orchestrator, Architect, Builder, Reviewer, Scout —
   each with a clean context, beats it.

5. **Verify autonomously.** Never trust "done." The harness proves it: `init.sh`,
   tests, type/lint checks, and behavioral checks (e.g. Playwright clicking the live
   app). The Reviewer can even improve the harness so a failure can't recur — a
   self-improving loop.

## Where the ideas come from

Synthesized from the *Harnessing Engineering* research: the BettaTech harness-
engineering and SDD-for-Claude-Code videos, Anthropic's "Harness design for
long-running application development" (Planner/Generator/Evaluator + sprint
contracts), and the Harness Engineering knowledge graph. See `specs/product.md` for
how to adapt the harness to a specific project.
