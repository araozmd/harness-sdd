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
| `set_status(id, status)` | move through the state machine |

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
