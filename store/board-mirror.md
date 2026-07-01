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

### Assigning the person doing the work (`assignee`)

`mirror.board.assignee` is a **provider-neutral** key (like `provider` and `status_map`):
the concept — "attach the person doing the work to each mirrored item" — applies to any
board, and each provider maps it to its own field (GitHub Projects → issue **Assignees**;
Jira → assignee; Monday/Azure → owner/assigned-to). It is **implemented for
`github-projects` today**; the stub providers ignore it until wired (see *Implementing a
stub provider* below).

For `github-projects`, set it to a GitHub login and the mirror fills the issue's
**Assignees** field alongside Status/Epic. Assignment is **status-gated**: a feature's issue
gets the assignee once work has actually started (`in-progress`, `in-review`, `done`) and is
**cleared** if it regresses to a not-started state (`pending`, `spec-ready`), so the board
always reflects who is on it *right now*. Empty (the default) ⇒ the mirror never touches
assignees. Like every knob it lives in config, so an upgrade never clobbers it:

```yaml
mirror:
  board:
    provider: github-projects
    owner: my-org
    project_number: 1
    repo: my-org/specs
    assignee: "@me"       # or a literal login like "octocat"
```

Use `"@me"` (or `"self"`) to resolve **dynamically** to the authed `gh` user at sync time —
ideal for a shared-repo config where each developer's board should reflect their own
ownership without hard-coding one login. The tool resolves `@me` to the real login via
`gh api user`; if that lookup fails it degrades to "skip assignment this run" rather than
erroring. Assignment is idempotent — the add is skipped when the resolved login is already
present. Run `--dry-run` to preview the assign/clear actions without mutating the board.

When `assignee` is set, the mirror **owns** the Assignees field for the items it manages and
**reconciles it to the exact desired set** every sync: a started item (`in-progress`,
`in-review`, `done`) ends up with *exactly* the configured login — any other assignee is
removed — and a not-started item (`pending`, `spec-ready`) ends up with none. That matters
under a shared `@me` config: whoever runs the sync clears a *teammate's* stale assignment —
whether the item is still in flight or has regressed — instead of leaving it behind.
Corollary: don't hand-assign people to mirrored items; the mirror is the source of truth for
that field and will reconcile them away.

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

To wire `jira`, `azure-boards`, or any other tracker (Monday, a custom tool, …), implement
its branch in `tools/sync-board.mjs` against that tracker's CLI/API (`jira`/REST,
`az boards`, …), reading the same `tasks.json` flat list and writing one work item per
feature with the Status mapping above. Honor the same provider-neutral config keys where the
tracker has an equivalent: `status_map` → its columns/states, and `assignee` → its
assignee/owner field (status-gated the same way — set once work starts, cleared when not
started). Keep it **one-way and idempotent** — never let the board write back into
`tasks.json`.
