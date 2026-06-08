# Store backend: `jira`  — ⏳ STUB (not yet wired)

This adapter is **defined but not implemented**. The contract below is fixed so JIRA
drops in without re-architecting anything. Do not set `tasks: jira` in
`harness.config.yaml` until the MCP wiring section is completed.

> **Backend, not mirror.** This makes Jira the **source of truth** (`next()` queries Jira).
> If instead you want to keep local `tasks.json` authoritative and just *project* it onto a
> Jira board, that's a **mirror** — see [`board-mirror.md`](./board-mirror.md), not this file.

## Intended mapping
| harness concept | Jira object |
|---|---|
| Epic (`E01`) | Jira Epic |
| Feature (`E01-F01`) | Jira Story |
| Task (`T1`) | Jira Sub-task |
| `status` | Jira workflow status (mapped, see below) |
| Requirement (`R1`) | label / custom field on the Story for traceability |

### Status mapping (harness → Jira)
| harness | Jira (example) |
|---|---|
| pending | To Do |
| spec-ready | Spec Review |
| in-progress | In Progress |
| in-review | In Review |
| done | Done |

## TaskStore contract (to implement)
Implement these over the Jira MCP, same signatures the Orchestrator already uses:
- `list()` → JQL `project = <KEY> ORDER BY rank` → map issues to epics/features.
- `next()` → first Story in an actionable status whose blocking links are Done.
- `get(id)` → fetch issue by the stored Jira key (keep a `jira_key` on each feature).
- `set_status(id, status)` → transition the issue via the mapped workflow id.

## DocStore (optional)
Specs can stay local markdown (recommended) even when tasks live in Jira, OR be
mirrored into the Story description / linked Confluence pages.

## TODO to enable (follow-up session)
1. Choose/confirm the Jira MCP server and add it to the CLI config.
2. Store project key + status-id mapping in `harness.config.yaml` under `store.jira`.
3. Implement the four TaskStore operations against the MCP tools.
4. Add a `tasks: jira` branch + auth check to `init.sh`.
5. Keep `state/tasks.json` as an offline cache/fallback.
