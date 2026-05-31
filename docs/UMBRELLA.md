# Umbrella coordinator (cross-repo features)

Real products span more than one git repo. The umbrella coordinator is a thin,
**opt-in** layer that lets one product feature — one intent — fan out into N child
repos as **slices**, delegates each slice to that repo's own SDD loop, enforces a
cross-repo merge order, and rolls verification up so the feature is `done` only when
every slice passes **and** an integration check passes.

This is a harness feature. The umbrella **never writes source code**: it specifies
once (the shared spec) and delegates down. No new git repo is introduced — the
umbrella lives in a non-git parent directory hosting sibling child repos.

## Opt-in switch (single-repo stays inert)
Umbrella mode is engaged **only** when `umbrella.manifest` in `harness.config.yaml`
points at an existing manifest file (see `umbrella.manifest.example.yaml`). With the
key unset or the file absent, the coordinator is inert and the existing single-repo
flow — `init.sh`, `verification.test_command`, the Reviewer's `done` verdict — behaves
exactly as it does today. The presence of the manifest file (not a boolean flag) is
the switch.

## Concepts
- **Umbrella** — the non-git parent directory hosting the coordinator harness.
- **Slice** — a per-repo unit of work for one cross-repo feature. In the TaskStore a
  feature carries an optional `slices[]` (see `store/local.md` and
  `store/tasks.schema.json`); each slice has `id` (`<feature-id>@<repo>`, e.g.
  `E03-F01@viernes-bff`), `repo`, `status`, `merged`, `spec_path`, and cross-repo
  `depends_on`.
- **Manifest** — `umbrella.manifest.yaml`: maps each `repo` to its `path`, `init`,
  `test_command`, and `delegate_cmd`. The coordinator reads it to locate and dispatch
  each child repo.
- **Contract artifact** — the single pinned inter-repo seam (see below).

## Spec home = umbrella; slices = child repos
The shared `.spec`/`.plan` live in the umbrella harness. Per-repo `.tasks`/`.tests`
**slices** are emitted into each child repo. Each slice maps to one child-repo feature
that runs its own SDD loop.

## Contract artifact (one contract, no drift)
The shared spec pins **exactly one** contract artifact — the inter-repo seam (an
OpenAPI fragment, an event schema, shared types, …) — at a **stable path** in the
umbrella and references it **by a stable id** from the `.spec.md`/`.plan.md`.

- Proposed stable location: `specs/epics/<epic>/<feature>/contract/`.
- The artifact's concrete **format is intentionally unspecified** — only its
  existence, its single-pin location, and its traceability are required. Over-pinning
  the format would cascade errors into every child repo's slice.
- **Every emitted slice's `.tasks`/`.tests` references the pinned contract artifact**
  (by the same path/id), so the traceability matrix links every slice back to the one
  shared seam. Parallel Builders in different repos therefore agree on the wire/shape.

## The coordinator loop (dispatch + gating)
This loop is an **additive** behavior of the Orchestrator (see the "Umbrella mode"
section of `agents/orchestrator.md`); no role file is forked. It is engaged only when
`umbrella.manifest` is set. For each cross-repo feature:

1. **select** — among the feature's slices, pick the lowest-id slice that is
   actionable and whose **every** `depends_on` upstream slice is `done` **and**
   `merged`. Repeatedly applying this rule yields a topological order. If a slice
   names a `repo` that is **not** a key in the manifest, refuse to dispatch it and
   report an error that names the missing repo.
2. **dispatch** — invoke that slice's repo `delegate_cmd` from the manifest using the
   existing seam contract **verbatim**:

   ```
   <delegate_cmd> <feature-id> <abs-spec-path>
   ```

   run in/for that child repo. The umbrella **never edits source files** in the child
   repo itself — the child repo's own SDD loop owns implementation, its PR, and its
   review.
3. **gate** — never dispatch a downstream slice's Builder, nor open that downstream
   repo's PR, while any of its upstream `depends_on` slices is not yet `done` **and**
   `merged`.
4. **fail-stop** — if a dispatched slice's `delegate_cmd` exits **non-zero**, mark
   that slice **failed**, halt dispatch of its downstream dependents, and surface the
   failure. Do not improvise a fix.
5. **advance** — on a slice's successful (zero-exit) completion, record its status as
   `done` and **re-evaluate** which downstream slices have become dispatchable (their
   upstreams are now `done`+`merged`), then re-run **select**.

This reuses the existing `execution.builder.delegate` contract exactly — the umbrella
Builder is just that delegate seam invoked once per slice, with gating/ordering around
it. Nothing new is added to the seam.

## Integration verification (rollup)
The feature `done` verdict is **derived**, never set directly:

- **Gated** — while **any** slice of the feature is not `done`, the coordinator does
  **not** run the integration check.
- **Run** — only when **every** slice is `done` **and** `merged`, the coordinator runs
  the configurable `verification.integration_command` (the stack running together,
  e.g. `viernes-infra/dev.sh ci`). If `integration_command` is empty there is no
  integration gate.
- **Done** — the feature reaches `done` **only when** all per-repo slices pass their
  own verification **and** the integration command exits **zero**.
- **Failure** — if the integration command exits **non-zero**, keep the feature out of
  `done` and surface the integration failure.

## Manifest reference
See `umbrella.manifest.example.yaml`. One entry per child repo under `repos:`, each
with `path`, `init`, `test_command`, `delegate_cmd`. A slice whose `repo` is absent
from `repos:` is undispatchable and must be reported.
