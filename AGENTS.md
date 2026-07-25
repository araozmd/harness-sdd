# AGENTS.md — harness-sdd

> This file is the **entrypoint** of the harness. It is the first thing any agent
> reads before doing anything. Keep it short — it is loaded into context every
> session. Detailed rules live in the files it points to.
>
> `AGENTS.md` is an open standard. Claude Code, Codex, Gemini CLI, OpenCode and
> Antigravity all read it (directly or via a one-line pointer). **The model is
> interchangeable; the harness is not.**

## What this is

A portable **Spec-Driven Development (SDD)** harness. Work flows through four roles
that each run with a *clean, curated context* and hand off through **files on disk**,
never through chat history. **Inception** is the front door *before* the loop: it
turns a raw idea into a `pending` TaskStore entry + an intent brief (via `/sdd-new`).

```
Inception ─► Orchestrator → Architect → Builder → Reviewer    (Scout assists, read-only)
 (intake)      (state)       (specs)     (code)    (verify)
```

## The non-negotiable rules

1. **Run `./init.sh` before any work.** If it exits non-zero, STOP. Do not "fix and
   continue" — a broken environment means hallucinated work. Report and halt.
   The local backend requires **`python3` with the stdlib `fcntl` module** — since
   `v0.31.0` the only supported board write path is the lock helper
   `python3 tools/tasks-lock.py`, so `init.sh` hard-fails (rather than warning)
   when it is missing. Install python3 or point the harness at another backend.
2. **Memory lives in files, not in your context.** Read only what you need. Write
   what you did to `progress/`. Never carry another agent's chat history.
3. **A task is `done` only when the Reviewer verifies it** — tests pass via
   `init.sh`, behavior matches the spec. "I think it works" is not done.
4. **Respect the human-in-the-loop gate.** A spec moves `pending → spec-ready` and
   then **pauses**. A human (or an explicitly autonomous task) moves it to
   `in-progress`. Only then may the Builder write code. See `docs/WORKFLOW.md`.
5. **Minimal tools.** Prefer Bash/grep/cat/ls and the file system. Do not invent
   specialized tooling; a lean harness beats an inflated one.

> **Telemetry:** the Orchestrator prints an end-of-session telemetry summary (per-phase
> durations, build↔review rounds, human-gate latency — text-only, no tokens/USD) when it
> wraps up; the full instruction lives in `agents/orchestrator.md` "## Telemetry".

## Where things live

| Path | Purpose |
|---|---|
| `harness.config.yaml` | Store backend selection + settings (read this first after init) |
| `agents/*.md` | The role prompts (Inception, Orchestrator, Architect, Builder, Reviewer, Scout) |
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

- Every new work, feature or bug should have its own branch.
- If a feature is completed make sure the README and docs are up to date.
- Once all local verifications and tests passed, create a new PR for review.
- Once a branch is merged delete remote and local branch and go back to main
  to keep the repo clean.
- After every feature is finished in its own branch and before continuing with
  another feature, wait for it to be merged. Only continue autonomously if the
  next task is explicitly marked as autonomous.
