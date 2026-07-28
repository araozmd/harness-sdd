# What a harness is (and why this one is built this way)

A **harness** is the environment you build *around* a model: the context, tools,
memory, and verification that help a model work within a repeatable process.
The model is the engine (or the horse); the harness is the chassis (or the reins).

**The core bet:** models and runtimes change, while repository-owned intent and
evidence can remain portable. Files you own let this project support Claude, Gemini,
Codex, or a local model and multiple CLIs without adopting one vendor wrapper.
Read the deeper [rationale and deletion ledger](RATIONALE.md) for the limits of
that claim, the distinction between current-model compensation and durable process
value, and the evidence required before removing a mechanism.

## The four components

1. **Context** — what the model is told. Kept minimal and curated per agent.
2. **Tools** — what it can do. Minimal beats inflated (Bash + filesystem first).
3. **Memory** — what it remembers across sessions. Externalized to files.
4. **Verification** — proof the work is actually correct. `init.sh` + tests + Reviewer.

## The five principles this harness enforces

1. **The harness lives in the repo.** It's `AGENTS.md` + `agents/` + `specs/` +
   `progress/` + `init.sh`. No external app, no magic — just files that reference
   each other.

2. **Minimal tooling.** Every tool adds context and another failure surface. This
   project starts with Bash and the filesystem, then adds a tool only when a task
   and its verification show a need.

3. **Externalize memory.** Keep resumable state in `state/`, `specs/`, and
   `progress/`; read only what is needed and resume from files when a session or
   context changes.

4. **Separate roles.** Inception (intake), Orchestrator, Architect, Builder,
   Reviewer, and Scout have bounded responsibilities so planning, implementation,
   and independent challenge leave distinct evidence.

5. **Verify autonomously.** Never trust "done." The harness proves it: `init.sh`,
   tests, type/lint checks, and behavioral checks (e.g. Playwright clicking the live
   app). The Reviewer can even improve the harness so a failure can't recur — a
   correction loop.

## The commands this harness ships

One body per command, mirrored byte-identically into every selected front-end
(`.claude/commands/`, `.opencode/command/`, `.agents/workflows/`, and the global
`${CODEX_HOME:-~/.codex}/prompts/`). See [WORKFLOW.md](WORKFLOW.md) for the loop each
one drives.

| Command | Role it runs | Gate |
|---|---|---|
| `/sdd-new "<idea>"` | Inception — triage an idea into a `pending` entry + intent brief | always |
| `/sdd-plan "<idea>"` | Planner — whole-project vision/architecture + ADRs + draft epics | always |
| `/sdd-drill <epic-id>` | Driller — decompose one draft epic into features | always |
| `/sdd-next` | Orchestrator — route and delegate the next actionable task | always |
| `/sdd-fix "<desc>"` | Fixer — the lightweight `sdd:false` maintenance lane | always |
| `/sdd-fix-parallel` | Fixer — bounded parallel batch of ready E99 fixes | always |
| `/sdd-pr-loop <pr>` | the Codex review cycle on one open PR (spawns `pr-fixer`) | `pr_loop.enabled` |

`/sdd-pr-loop` is the one **gated** command: it is stamped only while
`pr_loop.enabled` is `true` (the default), because it works only on a repository with
the **Codex GitHub App** installed plus an **authed `gh`** and **`jq`** on `PATH`. Those
are loop-runtime dependencies alone — `init.sh` never checks for them, so a target
without either still passes the environment gate. Turning the key off reclaims the
command and its `pr-fixer` sub-agent from every front-end.

## Where the ideas come from

The [rationale and deletion ledger](RATIONALE.md) attributes the primary source
reports that motivated specific design hypotheses and states their limits. See
[`specs/product.md`](../specs/product.md) for how to adapt the harness to a specific
project.
