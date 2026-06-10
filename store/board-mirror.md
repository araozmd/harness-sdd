# Board mirror — project state, projected for humans

A **mirror** is a one-way projection of `state/tasks.json` onto an external project
board (GitHub Projects, Jira, Azure Boards, …) so humans get a familiar Kanban view.
It is driven by [`tools/sync-board.mjs`](../tools/sync-board.mjs) and configured under
`mirror.board` in `harness.config.yaml`. **Opt-in and inert by default.**

## Mirror ≠ store backend

This is the key distinction (see also [`README.md`](./README.md)):

| | **Mirror** (`tools/sync-board.mjs`) | **Store backend** (`tasks: jira`, see [`jira.md`](./jira.md)) |
|---|---|---|
| Direction | one-way: `tasks.json` → board | the tracker *is* the state |
| Source of truth | `tasks.json` | the tracker |
| Agents need it reachable? | **No** — they read local `tasks.json` | Yes — `next()` queries the tracker |
| Failure impact | a stale board; the loop is unaffected | the loop can't read state |

Pick the **mirror** when you want local-first task state plus a human-visible board.
Pick the **backend** only when your team genuinely *lives* in the tracker. They are
independent axes — you can run the `local` backend with a GitHub-Projects mirror.

## Providers

`mirror.board.provider` selects the target. Empty/`none` ⇒ the tool prints a notice and
exits 0 (the default — no board, no dependency).

| provider | status | needs |
|---|---|---|
| `github-projects` | ✅ implemented | `gh` authed with `project` + `repo` scopes; `mirror.board.{owner,project_number,repo}` |
| `jira` | ⏳ stub (no-op) | — (recognized; prints "not implemented", exits 0) |
| `azure-boards` | ⏳ stub (no-op) | — (recognized; prints "not implemented", exits 0) |

```bash
node .harness/tools/sync-board.mjs            # sync the configured provider
node .harness/tools/sync-board.mjs --dry-run  # print intended changes, mutate nothing
```

The status columns default to the **harness status names verbatim** (`pending`,
`spec-ready`, `in-progress`, `in-review`, `done`) — an identity map, so the mirror is not
tied to any one team's column naming. The tool owns the board's Status/Epic field options
and derives them from `tasks.json`, so new epics/states appear automatically.

The mirror projects **feature** statuses onto board columns — **epic** statuses never map
to columns (the epic is a label/single-select field, not a column). The epic-lifecycle
states `draft` and `planned` therefore need no provider work and no new `status_map`
entries: a `draft` or `planned` epic's features simply appear in whatever column their
own feature status maps to.

### Keeping your existing columns (`status_map`)

The tool **owns** the Status field's options, so by default it will rename an existing
board's columns to the identity names on first sync. To keep columns you already use,
map each harness status to your column name under `mirror.board.status_map` — **no edit to
`sync-board.mjs` needed**, so an upgrade never clobbers it:

```yaml
mirror:
  board:
    provider: github-projects
    owner: my-org
    project_number: 1
    repo: my-org/specs
    status_map:                 # omit entirely for identity columns
      pending: "Todo"
      spec-ready: "Spec ready"
      in-progress: "In Progress"
      in-review: "In review"
      done: "Done"
```

Any status you leave out falls back to its identity name. Run `--dry-run` after changing
the map to confirm the tool won't rewrite options you didn't intend.

## github-projects contract

`tasks.json` is the source of truth; the script makes the board match it, idempotently:
one **issue per feature** in `repo` (matched by exact title), each added as a **project
item**, with the **Status** (mapped from the feature state machine) and **Epic**
single-select fields set, closing `done` issues and reopening regressed ones. Re-runs are
no-ops when nothing changed. Config lives entirely in `harness.config.yaml`:

```yaml
mirror:
  board:
    provider: github-projects
    owner: my-org                 # owns the Project + the issues repo
    project_number: 1
    repo: my-org/specs            # where the mirrored issues live
```

## Driving it from the post-write hook

A mirror is most useful run automatically after every status change. Wire it through the
generic, VCS/PM-neutral `store.on_write_command` hook (see [`local.md`](./local.md) →
"Post-write sync") rather than hard-coding it into the loop:

```yaml
store:
  on_write_command: "node tools/sync-board.mjs"   # or a wrapper that also `git push`es
```

The Orchestrator runs that command best-effort after each persisted write; a failure is
reported as a sync gap and never blocks feature work.

## Implementing a stub provider

To wire `jira` or `azure-boards`, implement its branch in `tools/sync-board.mjs` against
that tracker's CLI/API (`jira`/REST, or `az boards`), reading the same `tasks.json` flat
list and writing one work item per feature with the Status mapping above. Keep it
**one-way and idempotent** — never let the board write back into `tasks.json`.
