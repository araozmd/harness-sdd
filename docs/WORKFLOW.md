# The Workflow

## Intake — the step before `pending` (`/sdd-new`)

Before a feature is `pending`, a raw idea has to become a well-formed TaskStore
entry. That is **Inception**'s job (`agents/inception.md`), driven by the `/sdd-new`
slash command. A human runs `/sdd-new "<idea>"`, answers a short adaptive Q&A, and
Inception seeds the state machine below:

```
  /sdd-new "<idea>"  ─►  [Inception]  ─►  pending entry in state/tasks.json
   (raw idea)           (triage +          + progress/inbox/<id>.md brief
                         allocate id)              │
                                                   ▼
                                          (state machine below)
```

Inception **seeds; it never specs** — it writes only a `pending` entry plus the
intent brief, never the four spec files, and never advances status past `pending`.
From there `/sdd-next` (the Orchestrator) drives the flow below, including the human
gate. Inception does not spawn the Architect — but the brief is not inert: when the
Orchestrator spawns the Architect for that feature, it passes
`progress/inbox/<feature-id>.md` as a primary input, and the Architect reads it
first and specs from it. That read is what wires the captured intent into spec
generation.

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
3. Orchestrator spawns the Architect, passing `progress/inbox/E02-F01.md` (the
   Inception brief); the Architect reads it first and writes the 4 files from it →
   `spec-ready`. **Pause.**
4. Human reads specs, approves → `in-progress`.
5. Builder implements `tasks.md`, writes tests from `tests.md`, self-checks → `in-review`.
6. Reviewer runs tests + Playwright, verifies every R-id. On **reject** it writes
   file-based feedback to `progress/<run>/review.md` → `in-progress` → Builder
   addresses → re-review; this build↔review loop repeats until green. On **approve**
   → `done`. Each round is recorded in `progress/history.md`.
7. History updated. Orchestrator picks the next task.
