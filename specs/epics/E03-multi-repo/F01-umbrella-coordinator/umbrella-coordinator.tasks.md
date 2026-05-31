# Umbrella coordinator — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom, one
> at a time. Each task names the R-id(s) it satisfies. Check off when done.
> This is a harness feature — no production/application code. Confirm the three open
> questions in the .spec.md before starting T1 (they pin schema/config key names).

- [x] **T1** (R1, R2) — In `store/tasks.schema.json`, add an **optional** `slices`
  array to the feature object. Define slice item with `id` (pattern
  `^E[0-9]+-F[0-9]+@[a-z0-9-]+$`), `repo` (string), `status` (existing feature status
  enum), `merged` (boolean), `spec_path` (string), `depends_on` (array of slice-id
  strings). Do not add `slices` to any `required` list.
- [x] **T2** (R4, R19) — Verify the schema is a pure superset: load and validate the
  existing single-repo `state/tasks.json` (no `slices`) against the edited schema and
  confirm it still passes; run `./init.sh` and confirm green.
- [x] **T3** (R3, R13) — In `store/local.md`, document the slice read semantics and
  the rollup rule: a feature is `done` only when every slice is `done` (and, per T9,
  the integration check has passed). Document that the coordinator **derives** feature
  `done`, never sets it directly, and re-evaluates dispatchable slices on each advance.
- [x] **T4** (R5, R6) — Create `umbrella.manifest.example.yaml` mapping each `repo` to
  `path`, `init`, `test_command`, `delegate_cmd`. Include a comment that presence of
  the real manifest engages umbrella mode and that a slice `repo` absent here is
  undispatchable and must be reported.
- [x] **T5** (R5, R15, R18) — In `harness.config.yaml`, add additive keys
  `umbrella.manifest` (path; unset ⇒ single-repo inert) and
  `verification.integration_command` (empty ⇒ no integration gate). Do not change the
  meaning of any existing key; keep defaults so a single-repo target stays inert.
- [x] **T6** (R7, R8) — In `docs/UMBRELLA.md`, document the **contract artifact**: it
  is pinned once at a stable umbrella path and referenced by id from the shared spec;
  every emitted slice's `.tasks`/`.tests` references it. Leave its format unspecified.
- [x] **T7** (R9, R10, R11, R12, R13) — In `docs/UMBRELLA.md` and an additive
  "Umbrella mode" section appended to `agents/orchestrator.md`, specify the dispatch
  loop: topological **select** (upstream slices `done`+`merged`), **dispatch** via
  `<delegate_cmd> <feature-id> <abs-spec-path>` (no source edits from umbrella),
  **gate** (no downstream dispatch/PR before upstream `done`+merged), **fail-stop** on
  non-zero delegate exit, **advance** on success. Do not fork the Orchestrator role —
  append only, engaged only when `umbrella.manifest` is set.
- [x] **T8** (R14, R15, R16, R17) — In the same docs/instruction, specify the
  integration gate: run `verification.integration_command` only when all slices are
  `done`+`merged`; feature `done` ⟺ all slices pass AND integration exits zero;
  non-zero integration keeps the feature out of `done` and surfaces the failure.
- [x] **T9** (R18, R6) — In `init.sh` (only if needed), keep schema validation green
  for both single-repo and sliced stores; optionally warn (non-fatal) when a manifest
  references a missing repo path. Must not break the existing single-repo run.
- [x] **T10** — Write tests per `umbrella-coordinator.tests.md` in
  `tests/test_umbrella.sh` (and any schema-validation fixtures), covering every R-id.
- [x] **T11** — Run `./init.sh` + the test command (`tests/test_umbrella.sh` and the
  existing install tests); ensure green before hand-off.
