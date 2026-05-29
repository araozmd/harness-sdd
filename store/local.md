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
