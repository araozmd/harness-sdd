# AGENTS.md — harness-sdd

> This file is the **entrypoint** of the harness. It is the first thing any agent
> reads before doing anything. Keep it short — it is loaded into context every
> session. Detailed rules live in the files it points to.
>
> `AGENTS.md` is an open standard. Claude Code, Codex, Gemini CLI and OpenCode all
> read it (directly or via a one-line pointer). **The model is interchangeable; the
> harness is not.**

## What this is

A portable **Spec-Driven Development (SDD)** harness. Work flows through four roles
that each run with a *clean, curated context* and hand off through **files on disk**,
never through chat history.

```
Orchestrator → Architect → Builder → Reviewer        (Scout assists, read-only)
   (state)      (specs)     (code)    (verify)
```

## The non-negotiable rules

1. **Run `./init.sh` before any work.** If it exits non-zero, STOP. Do not "fix and
   continue" — a broken environment means hallucinated work. Report and halt.
2. **Memory lives in files, not in your context.** Read only what you need. Write
   what you did to `progress/`. Never carry another agent's chat history.
3. **A task is `done` only when the Reviewer verifies it** — tests pass via
   `init.sh`, behavior matches the spec. "I think it works" is not done.
4. **Respect the human-in-the-loop gate.** A spec moves `pending → spec-ready` and
   then **pauses**. A human (or an explicitly autonomous task) moves it to
   `in-progress`. Only then may the Builder write code. See `docs/WORKFLOW.md`.
5. **Minimal tools.** Prefer Bash/grep/cat/ls and the file system. Do not invent
   specialized tooling; a lean harness beats an inflated one.

## Where things live

| Path | Purpose |
|---|---|
| `harness.config.yaml` | Store backend selection + settings (read this first after init) |
| `agents/*.md` | The role prompts (Orchestrator, Architect, Builder, Reviewer, Scout) |
| `specs/product.md` | Layer 0 — product constitution (stable, high-level) |
| `specs/epics/<E>/<F>/*.md` | The 4-file feature specs (`.spec` `.plan` `.tasks` `.tests`) |
| `state/tasks.json` | The TaskStore (local backend) — epic/feature/task state |
| `progress/` | Per-run agent output + `history.md` changelog |
| `store/` | Store contract + backend adapters (local, obsidian, jira) |
| `docs/SPEC-FORMAT.md` | The spec standard: EARS + the 4 files + traceability |
| `docs/WORKFLOW.md` | The loop, the states, the human gates |

## Start here

1. Run `./init.sh`. Halt on failure.
2. Read `harness.config.yaml` to learn which store backends are active.
3. Read `agents/orchestrator.md` and assume the Orchestrator role.
4. Read the TaskStore, find the next actionable task, and delegate per the workflow.
