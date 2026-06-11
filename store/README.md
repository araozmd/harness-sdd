# Store — the pluggable memory layer

Agents never talk to a backend directly. They go through a **contract** with two
faces, and `harness.config.yaml` decides which backend fulfills each. Swap a
backend value → memory moves → **no agent prompt changes.** This is the same
"swap the brain, keep the harness" idea applied to where state lives.

## The two faces

### TaskStore — high-level project state
The epic/feature/task tree the Orchestrator reads to decide what's next.

| Operation | Meaning |
|---|---|
| `list()` | all epics → features with status |
| `next()` | highest-priority actionable feature (respecting `depends_on`) |
| `get(id)` | one feature's state |
| `set_status(id, status)` | move a **feature** *or* **epic** through the state machine (a feature id edits the feature; an epic id edits the epic — see each backend doc) |

Backends: `local` (✅), `obsidian` (✅), `jira` (⏳ stub).

### DocStore — externalized memory (specs, progress, history)
The markdown the agents read/write for context.

| Operation | Meaning |
|---|---|
| `read_spec(feature_id)` | the 4 spec files |
| `write_spec(feature_id, files)` | Architect output |
| `append_progress(run, note)` | run output |
| `append_history(line)` | the durable changelog |

Backends: `local` (✅), `obsidian` (✅).

## Backend matrix

| Backend | TaskStore | DocStore | Deps | File |
|---|---|---|---|---|
| local | `state/tasks.json` | markdown in `specs/`, `progress/` | none | `store/local.md` |
| obsidian | feature frontmatter | same files, vault-flavored | Obsidian (optional) | `store/obsidian.md` |
| jira | Jira issues | Jira/Confluence | MCP + auth | `store/jira.md` (stub) |

Each adapter doc tells the agents exactly how to perform the operations above on
that backend. To add a backend, write a new `store/<name>.md` implementing the
contract and add it to `harness.config.yaml`.

## Mirrors vs backends

A **backend** is *where state lives* — what `next()` reads and `set_status` writes. A
**mirror** is different: a one-way **projection** of `state/tasks.json` onto an external
board (GitHub Projects, Jira, Azure Boards) for human visibility. `tasks.json` stays the
source of truth; the board is downstream and disposable, and the agents never read it — so
a mirror, unlike a backend, never has to be reachable for the loop to function. See
[`board-mirror.md`](./board-mirror.md) (driven by `tools/sync-board.mjs`, opt-in via
`mirror.board`). The generic, VCS/PM-neutral way to run a mirror after each write is the
`store.on_write_command` hook — see [`local.md`](./local.md) → "Post-write sync".

> A board can appear in *both* roles: `tasks: jira` (backend, Jira *is* the truth) is a
> different choice from a Jira mirror (`tasks.json` is the truth, projected to Jira). Don't
> conflate them.
