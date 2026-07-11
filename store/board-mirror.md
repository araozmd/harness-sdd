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
| `jira` | ✅ implemented (mirror) | Jira **Server/DC** REST + Bearer PAT; `mirror.board.{base_url,project_key}` + a PAT (`JIRA_PAT` env or gitignored `pat_file`) |
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

### Transport & supported surface (pinned)

- **Supported Project type: GitHub Projects (v2)** — the GraphQL-backed Projects surface
  reached through `gh project` / `gh api graphql`. **Classic Projects are NOT supported.**
- **Transport: the `gh` CLI ONLY — never MCP.** Every GitHub call goes through `gh`
  (`gh project`, `gh issue`, `gh api` / `gh api graphql`). No MCP server is used or
  required, so the mirror works inside MCP-restricted enterprises. REST/GraphQL, where
  needed, is reached via `gh api`.
- **Minimum `gh` version: `2.31.0`** — the first release that ships the stable
  `gh project` (Projects v2) subcommands. Older `gh` fails the preflight below.
- **Required auth scopes: `project` + `repo`.** Authenticate with the developer's existing
  `gh` session — no new committed secret. Add the scopes with
  `gh auth refresh -s project -s repo` (or `gh auth login` selecting them).
- **One-way invariant.** The sync is strictly one-way: `state/tasks.json` → board. Agents
  never **read** the board to decide work; `tasks.json` stays the single source of truth.
  Nothing here makes the mirror bidirectional.

**Preflight (fail-closed).** Before touching the board, `sync-board.mjs` verifies `gh` is
present, is at least `2.31.0`, and its token carries the `project` + `repo` scopes. If any
check fails the tool exits **non-zero** with an actionable message naming `gh` and the
Projects-v2 / scope requirement — **before** any board-mutating call, so a preflight failure
never leaves the board half-written.

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
`github-projects` today**; it is a recognized **no-op for `jira`** in F01 (`owner →
assignee` is deferred to E10-F03 — see the *jira contract* above), and the remaining stub
providers ignore it until wired (see *Implementing a stub provider* below).

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

## jira contract

The `jira` provider is an **implemented** mirror (not a stub): a one-way projection of
`state/tasks.json` onto a Jira project.

### Transport & supported surface (pinned)

- **Supported Jira: Server / Data Center only (F01).** Auth is a **Server/DC Personal
  Access Token (PAT)** sent as an `Authorization: Bearer <PAT>` header — the IT-approved
  scripting path. **Jira Cloud** (which authenticates with Basic `email:api-token`) is
  **out of F01 scope**, documented as a future extension (would add a
  `mirror.board.auth: bearer|basic` selector and a Basic header path).
- **Transport: the Jira REST API ONLY — never MCP.** Every Jira call is an HTTPS request to
  the configured `base_url` `/rest/api/2/…` endpoint (search / create / transition),
  authenticated by the Bearer PAT. No MCP server is used or required, so the mirror works
  inside MCP-restricted enterprises.
- **One-way invariant.** The sync is strictly one-way: `state/tasks.json` → Jira. Agents
  never **read** Jira to decide work; `tasks.json` stays the single source of truth. Nothing
  here writes back into `tasks.json` or makes the mirror bidirectional.

### The PAT — `JIRA_PAT` env / gitignored `pat_file` (never committed)

The PAT is resolved from, in order (**first hit wins**):

1. the **`JIRA_PAT`** environment variable (precedence when both are present), else
2. the gitignored **`pat_file`** (default `.harness/jira.pat`, trimmed of a trailing
   newline).

If neither resolves, the tool exits **non-zero** with an actionable message naming
`JIRA_PAT` and the `pat_file` path — **before** any Jira network call. The PAT value is
**never** written into `state/tasks.json`, `harness.config.yaml`, logs, or any committed
file; only the *path* (`pat_file`) and the env-var *name* ever appear. The installer
append-seeds the default `pat_file` path into `.gitignore` so it can't be committed by
default.

### Config + field / status mapping

```yaml
mirror:
  board:
    provider: jira
    base_url: https://jira.acme.internal   # Jira Server/DC base URL (required)
    project_key: HAR                        # target Jira project key (required)
    pat_file: .harness/jira.pat             # gitignored PAT file; JIRA_PAT env wins
    issue_type_map:                         # optional — defaults epic→Epic, feature→Story
      epic: "Epic"
      feature: "Story"
    status_map:                             # optional — harness status → Jira workflow state
      pending: "To Do"                      # (identity default; nothing hard-coded)
      in-review: "In Review"
```

- **Issue types (configurable).** Harness **epics** map to the Jira **Epic** issue type and
  **features** to the Jira **Story** issue type by default; both are overridable via
  `mirror.board.issue_type_map` (e.g. `feature: Task`). Nothing is hard-coded.
- **Status → workflow (configurable).** Each feature's `status` maps to a Jira workflow
  state via the provider-neutral `mirror.board.status_map` (identity default), and the
  reconciled issue is **transitioned** to the mapped state. Nothing about the workflow-state
  names is hard-coded.
- **Idempotent reconcile.** Each epic/feature maps to exactly one Jira issue, matched by a
  stable `harness:<id>` label (JQL `project = <KEY> AND labels = harness:<id>`). A re-run
  finds the existing issue and transitions it in place rather than creating a duplicate.
- **`assignee` is a no-op for `jira` in F01.** The provider-neutral `assignee` knob is
  recognized but **deferred to E10-F03** (`owner → assignee` projection); F01 projects
  **status only** and never wires Jira's assignee field.
- **`--dry-run`** prints the intended Jira changes (would-create / would-transition) and
  mutates nothing — neither Jira nor `tasks.json`.

**Fail-closed ordering.** Config (`base_url`/`project_key`) is validated and the PAT is
resolved **before** the first network call, so a misconfigured or unauthenticated run never
half-mutates Jira. A Jira **401/403** exits non-zero with an actionable message naming the
PAT/scope requirement and **does not echo the PAT**.

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

To wire `azure-boards` or any other tracker (Monday, a custom tool, …) — `jira` is already
implemented (see the *jira contract* above) — implement its branch in `tools/sync-board.mjs`
against that tracker's CLI/API (`az boards`, …), reading the same `tasks.json` flat list and
writing one work item per feature with the Status mapping above. Honor the same
provider-neutral config keys where the
tracker has an equivalent: `status_map` → its columns/states, and `assignee` → its
assignee/owner field (status-gated the same way — set once work starts, cleared when not
started). Keep it **one-way and idempotent** — never let the board write back into
`tasks.json`.
