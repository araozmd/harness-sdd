# Store backend: `local` (default)

Zero dependencies. State is plain files in the repo — this *is* the "harness lives
in the repo" pillar. Use this unless you have a reason not to.

## TaskStore → `state/tasks.json`
Validated by `store/tasks.schema.json` (and by `init.sh`).

- **list()** — read `state/tasks.json`, return `epics[].features[]`.
- **next()** — first feature whose `status` is actionable and whose `depends_on`
  are all `done`. Prefer lower epic/feature ids. Actionable means `pending`,
  `in-progress`, `in-review`, **or** `spec-ready` when the feature has
  `autonomous: true` (that flag skips the human gate, so the Orchestrator may move
  it straight to `in-progress` for Builder work). A `spec-ready` feature *without*
  `autonomous: true` is **not** actionable — it is parked at the human gate.
  The same gate applies to a `pending` + `sdd: false` fix: with `autonomous: true`
  it **is** actionable (the Orchestrator sets it `in-progress` and sends the Builder
  straight at it — there is no spec to gate); with `autonomous: false` (e.g.
  `/sdd-fix --gated`) it is **not** actionable — it is parked at the human gate until
  a human moves it to `in-progress` or re-stamps `autonomous: true`.
  **Epic gate:** features of a `draft` epic are **never actionable** — `next()`
  never selects them, regardless of the feature's own `status`, `sdd`,
  `autonomous`, or `depends_on` (`autonomous: true` does **not** override this
  gate; it skips the human approval gate only). Epics in `pending`, `planned`,
  `in-progress`, or `done` impose **no new gate** — their features are evaluated
  by the per-feature rules above, unchanged.
- **get(id)** — find the feature object by `id`.
- **set_status(id, status)** — set the `status` of the **object the id addresses**,
  then re-validate (`python3 -c "import json;json.load(open('state/tasks.json'))"`).
  The id selects the object kind:
  - a **feature id** (`E06-F06`) edits that feature's `status` in `epics[].features[]`;
    keep the feature's `.spec.md` frontmatter `status` in sync.
  - an **epic id** (`E06`) edits that **epic's** `status` in `epics[]`; keep the epic's
    `epic.md` frontmatter `status` in sync. Epic-status writes are required by the
    epic-done rollup and the drift-check demotion (below) — `set_status` is the **one**
    write path for both feature and epic status; backends MUST implement the epic case.

### Epic lifecycle
The canonical epic lifecycle is `draft → planned → in-progress → done`. A `draft`
epic is an inception sketch (title + business brief only) whose features are never
selectable; a `planned` epic is drilled down and human-approved. Epic-level
`pending` is a **legacy alias of `planned`**, kept indefinitely for backward
compatibility: `pending` and `planned` are **gating-equivalent** — selection
treats them identically.

## Cross-repo features → `slices[]` (umbrella mode)
A feature may optionally carry a `slices` array — one entry per child repo for a
cross-repo (umbrella) feature. Each slice has `id` (`<feature-id>@<repo>`, e.g.
`E03-F01@viernes-bff`), `repo`, `status`, optional `merged` (true once its PR is
merged in that repo), optional `spec_path` (the slice's emitted `.tasks`/`.tests`),
optional `pr` (the PR URL the child SDD loop opened — the selector used to poll the
merge, since the short `repo` key is not a `gh` repo slug), and optional cross-repo
`depends_on` (slice ids). A feature with **no** `slices`
behaves exactly as a single-repo feature does today — the field is purely additive.

- **slices(id)** — read the feature's `slices[]` (empty/absent ⇒ single-repo).
- **next_slice(feature)** — the lowest-id slice that is actionable and whose every
  `depends_on` upstream slice is `done` **and** `merged` (topological order).
- **set_slice_status(feature, slice_id, status)** / **set_slice_merged(...)** —
  edit the slice in place, then re-validate against `store/tasks.schema.json`.

### Rollup rule (feature `done` is derived, then persisted)
For a sliced feature the coordinator **derives** the feature's status from its slices
rather than declaring `done` by fiat — but it **does persist** the derived result:

- While **any** slice is not `done`+`merged`, the feature's rolled-up status is **not**
  `done`, and the coordinator must NOT write `done` onto the feature.
- A feature becomes `done` **only when every slice is `done` and `merged`** **and** the
  feature-level integration check (`verification.integration_command`) has passed.
- **When those conditions hold, the coordinator writes the derived `done` onto the
  feature** (`set_feature_status`) and re-validates. This persistence is required:
  feature-level `next()` gates `depends_on` on the *stored* feature status, so a
  dependent feature (e.g. `E03-F02` depends_on `E03-F01`) stays blocked until the
  upstream feature's `done` is actually written.
- On each slice **advance** (a slice reaching `done`+`merged`), re-evaluate which
  downstream slices have become dispatchable, then re-check the rollup condition.

"Derived, never set directly" therefore means *never set `done` prematurely* (while a
slice or the integration gate is red) — not "never written". This guarantees there is
no path to a green feature with a red slice, while still unblocking dependents. The umbrella
dispatch/gating loop that consumes these semantics is specified in
`docs/UMBRELLA.md` and the "Umbrella mode" section of `agents/orchestrator.md`.

### Epic-done rollup (all features `done` ⇒ epic `done`, derived then persisted)
Beside the sliced-feature rollup above — and **additively**, not inside it — the same
"derive, then persist" discipline rolls an **epic** up. **When every feature of an epic is
`done`, the epic's `done` status is derived and persisted** by the Orchestrator (the owner
of `set_status`): it derives `done` from the fact that **all features are `done`**, writes it
onto the epic, and **re-validates** `state/tasks.json` against `store/tasks.schema.json`. This
mirrors the feature rollup exactly — `done` is never set by fiat while any feature is still
open, but it **is persisted** once every feature is `done`. This introduces **no new status
value** and **no schema change**: `done` is already an epic-enum value (`store/tasks.schema.json`).

### Drift check on epic rollup (Scout re-validates, Orchestrator demotes)
Immediately **after** an epic rolls up to `done`, the Orchestrator triggers a **drift check**
to guard against stale rolling-wave plans. It spawns the **read-only Scout** in a drift-check
mode (see `agents/scout.md`) to re-validate the remaining `draft`/`planned`/`pending` epics
against what the just-completed epic produced (new/changed ADRs + architecture deltas + what
its features changed). The **Scout flags, the Orchestrator acts**:

- The Scout writes a per-epic still-valid/stale findings file under `progress/` and makes
  **no** state change (its read-only contract is preserved — it never writes `state/tasks.json`).
- The **Orchestrator demotes** a stale `planned`/`pending` epic to `draft` via `set_status`,
  then re-validates `state/tasks.json`. A stale `draft` epic **stays `draft`** (already the
  lowest planning state) but is **flagged** in the findings.
- **`in-progress` and `done` epics are never demoted** — the check concerns *future* planned
  work only. Demotion only ever moves an epic **backward**; re-drilling a demoted epic back to
  `planned` stays a manual `/sdd-drill` (F03) step.

The demoted epic's features become non-selectable behind `next()`'s epic gate until it is
re-drilled. This adds **no new status value** and **no schema change** — demotion reuses the
existing `draft` state.

## DocStore → markdown
- **read_spec(feature_id)** — read the 4 files under the feature's `spec_path`.
- **write_spec** — Architect writes `<feature>.spec.md|plan.md|tasks.md|tests.md`
  from `specs/_templates/`.
- **append_progress(run, note)** — write/append under `progress/<run>/`.
- **append_history(line)** — append one line to `progress/history.md`.

## Post-write sync (opt-in)
After **any persisted write** — `set_status`, `set_slice_status`, `write_spec`, and the
done rollup — the Orchestrator runs `store.on_write_command` (from `harness.config.yaml`)
**when it is non-empty**, invoked as `<cmd> "<feature-id>" "<op>"` with cwd = `HARNESS_DIR`.
This is the harness's generic, **VCS/PM-neutral** sync seam: the harness never learns what
the command does. A team might point it at a `git push` of `state/tasks.json` + `specs/`,
at a board mirror (`node tools/sync-board.mjs` — see [`board-mirror.md`](./board-mirror.md)),
or at a wrapper doing both.

- **Empty (default) ⇒ no hook** — exactly today's behavior.
- **Best-effort, never-blocking** — a non-zero exit NEVER rolls back `tasks.json` and never
  stalls `next()`. Do the local write regardless, then report the sync gap; never block
  feature work on it. (Same discipline as telemetry.)
- `tasks.json` stays the **source of truth**; anything the hook pushes to is downstream.

## Notes
- Commit `state/tasks.json` and `specs/` so state is versioned with the code.
- This backend is fully compatible with `obsidian` — pointing a vault at the repo
  needs no migration.
