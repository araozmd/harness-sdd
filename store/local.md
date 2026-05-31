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
- **get(id)** — find the feature object by `id`.
- **set_status(id, status)** — edit the feature's `status` in the JSON, then
  re-validate (`python3 -c "import json;json.load(open('state/tasks.json'))"`).
  Keep the feature's `.spec.md` frontmatter `status` in sync.

## Cross-repo features → `slices[]` (umbrella mode)
A feature may optionally carry a `slices` array — one entry per child repo for a
cross-repo (umbrella) feature. Each slice has `id` (`<feature-id>@<repo>`, e.g.
`E03-F01@viernes-bff`), `repo`, `status`, optional `merged` (true once its PR is
merged in that repo), optional `spec_path` (the slice's emitted `.tasks`/`.tests`),
and optional cross-repo `depends_on` (slice ids). A feature with **no** `slices`
behaves exactly as a single-repo feature does today — the field is purely additive.

- **slices(id)** — read the feature's `slices[]` (empty/absent ⇒ single-repo).
- **next_slice(feature)** — the lowest-id slice that is actionable and whose every
  `depends_on` upstream slice is `done` **and** `merged` (topological order).
- **set_slice_status(feature, slice_id, status)** / **set_slice_merged(...)** —
  edit the slice in place, then re-validate against `store/tasks.schema.json`.

### Rollup rule (feature `done` is derived, never set directly)
For a sliced feature the coordinator **derives** the feature's status; it does not
write `done` onto the feature manually:

- While **any** slice is not `done`, the feature's rolled-up status is **not** `done`.
- A feature is `done` **only when every slice is `done`** (and merged) **and** the
  feature-level integration check (`verification.integration_command`) has passed.
- On each slice **advance** (a slice reaching `done`), re-evaluate which downstream
  slices have become dispatchable (their upstreams are now `done`+`merged`).

This guarantees there is no path to a green feature with a red slice. The umbrella
dispatch/gating loop that consumes these semantics is specified in
`docs/UMBRELLA.md` and the "Umbrella mode" section of `agents/orchestrator.md`.

## DocStore → markdown
- **read_spec(feature_id)** — read the 4 files under the feature's `spec_path`.
- **write_spec** — Architect writes `<feature>.spec.md|plan.md|tasks.md|tests.md`
  from `specs/_templates/`.
- **append_progress(run, note)** — write/append under `progress/<run>/`.
- **append_history(line)** — append one line to `progress/history.md`.

## Notes
- Commit `state/tasks.json` and `specs/` so state is versioned with the code.
- This backend is fully compatible with `obsidian` — pointing a vault at the repo
  needs no migration.
