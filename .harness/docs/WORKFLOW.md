# The Workflow

## State machine

A feature moves through these states. The Orchestrator routes on the current state;
the human gate sits between `spec-ready` and `in-progress`.

```
                 ┌─────────┐
                 │ pending │
                 └────┬────┘
        sdd:true      │      sdd:false (quick task)
        ┌─────────────┴──────────────┐
        ▼                            ▼
   [Architect]                  [Builder] ──► in-review
        │ writes 4 spec files
        ▼
  ┌────────────┐
  │ spec-ready │ ⏸  HUMAN GATE  (unless autonomous:true)
  └─────┬──────┘
        │ human approves
        ▼
  ┌─────────────┐
  │ in-progress │ ──► [Builder] writes code from approved specs
  └─────┬───────┘
        ▼
  ┌───────────┐         reject (feedback → progress/)
  │ in-review │ ──► [Reviewer] ───────────────┐
  └─────┬─────┘                               │
        │ approve                             ▼
        ▼                              back to in-progress
    ┌──────┐
    │ done │  (Reviewer verdict only) → append to progress/history.md
    └──────┘
```

## The human-in-the-loop gate

When `harness.config.yaml` has `require_spec_approval: true` (default), the
Orchestrator **pauses** at `spec-ready`. A human:

1. Reads the four spec files for the feature.
2. Requests changes if needed (the Architect revises; stays `spec-ready`).
3. Moves the feature to `in-progress` to authorize coding.

A task with `autonomous: true` in its frontmatter / TaskStore entry skips this gate
— use it only for low-risk work. The point of the gate is that you keep ownership
of *what the AI is building* before hours of code get written on a wrong premise.

## Selective SDD (the `sdd` flag)

Full SDD for a one-line tweak is overkill. Each task carries `sdd: true|false`:

- `sdd: true` → full flow: Architect → gate → Builder → Reviewer.
- `sdd: false` → Orchestrator sends the Builder straight at it, then Reviewer.

## Context hygiene

Agents degrade as their context fills (noticeably past ~20%, badly past ~40%).
So:

- Each sub-agent runs with a **fresh, minimal context** — only the files it needs.
- Results go to `progress/<run>/` so the next agent resumes from files, not chat.
- When an agent nears `context_reset_threshold`, it should write a structured
  hand-off to `progress/` and let a fresh agent continue ("context reset").
- `progress/history.md` is the durable changelog across the whole project.

## One run, end to end (example)

1. `./init.sh` → green.
2. Orchestrator reads TaskStore → `E02-F01 handoff-screen` is `pending`, `sdd:true`.
3. Architect writes the 4 files → `spec-ready`. **Pause.**
4. Human reads specs, approves → `in-progress`.
5. Builder implements `tasks.md`, writes tests from `tests.md`, self-checks → `in-review`.
6. Reviewer runs tests + Playwright, verifies every R-id → **approve** → `done`.
7. History updated. Orchestrator picks the next task.
