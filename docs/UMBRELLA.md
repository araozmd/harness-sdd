# Umbrella coordinator (cross-repo features)

Real products span more than one git repo. The umbrella coordinator is a thin,
**opt-in** layer that lets one product feature — one intent — fan out into N child
repos as **slices**, delegates each slice to that repo's own SDD loop, enforces a
cross-repo merge order, and rolls verification up so the feature is `done` only when
every slice passes **and** an integration check passes.

This is a harness feature. The umbrella **never writes source code**: it specifies
once (the shared spec) and delegates down. **By default** no new git repo is introduced —
the umbrella lives in a non-git parent directory hosting sibling child repos.
**Optionally** (`--shared-repo`, see [below](#shared-spec-repository-opt-in)) the umbrella
root can itself be a git repo that tracks **only** `.harness/` + the umbrella docs and
git-ignores the child product repos — a *shared spec repository* a team clones so epics,
specs, and task state are versioned and shared instead of stranded on one laptop.

## Opt-in switch (single-repo stays inert)
Umbrella mode is engaged **only** when `umbrella.manifest` in `harness.config.yaml`
points at an existing manifest file. Copy the shipped template to start — it lives at
the harness root as `umbrella.manifest.example.yaml`, and an installed harness places
it at `.harness/umbrella.manifest.example.yaml` (the installer copies it with the rest
of the body). With the
key unset or the file absent, the coordinator is inert and the existing single-repo
flow — `init.sh`, `verification.test_command`, the Reviewer's `done` verdict — behaves
exactly as it does today. The presence of the manifest file (not a boolean flag) is
the switch.

## Installing the umbrella (cascade)
Stand up the whole umbrella with a single command (see
[`INSTALL.md`](./INSTALL.md#umbrella-mode-cascade-install)):

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir
```

It installs the coordinator profile into `<umbrella>/.harness/`, installs the normal
child profile into each immediate **git** child (depth 1), and auto-populates
`umbrella.manifest.yaml`. Re-run any time to pick up newly-added child repos — it is
idempotent and never clobbers a bootstrap-filled manifest entry. Bootstrap then fills
each entry's `test_command`/`delegate_cmd` and the coordinator's `integration_command`.

## Shared spec repository (opt-in)
By default the umbrella is a throwaway parent directory — the coordinator's `.harness/`
(specs, `state/tasks.json`, progress) then lives only on whoever ran the cascade. For a
team, that strands the planning state on one laptop and invites duplicated epics/features.

Pass **`--shared-repo`** to version-control the umbrella root instead:

```bash
./harness-install.sh --umbrella /path/to/umbrella-dir --shared-repo
```

After the normal cascade it:
1. **`git init`s the umbrella root** — but **only if it has no `.git` yet**. An existing
   repo is never re-initialized.
2. **Append-seeds the umbrella-root `.gitignore`** to ignore the product child repos it
   just discovered (each stays its **own** repo, never a gitlink), on top of the
   per-developer agent state every install already ignores
   (`.claude/settings.local.json`, …). Append-only — an existing `.gitignore` is never
   clobbered. See [`../umbrella.gitignore.example`](../umbrella.gitignore.example) for the
   intended shape and [`CONFIG-LAYERING.md`](./CONFIG-LAYERING.md) for shared-vs-personal.

The result is a **spec repository**: the umbrella root is a git repo that tracks `.harness/`
+ the umbrella docs (`CLAUDE.md`, `AGENTS.md`, `README.md`) and git-ignores the product
repos cloned into it. Teammates `git clone` it to get the shared specs + task state, then
clone the product repos beside the harness. `--shared-repo` only governs whether the root
is version-controlled; it is orthogonal to the manifest, which still drives slice dispatch.
The local TaskStore is now shared state — commit `.harness/` changes alongside the feature
they describe so others pull a consistent board. Omit the flag and the umbrella behaves
exactly as before (non-git parent dir).

## Concepts
- **Umbrella** — the parent directory hosting the coordinator harness. Non-git by default;
  optionally its own git repo (a *shared spec repository*) under `--shared-repo` (above).
- **Slice** — a per-repo unit of work for one cross-repo feature. In the TaskStore a
  feature carries an optional `slices[]` (see `store/local.md` and
  `store/tasks.schema.json`); each slice has `id` (`<feature-id>@<repo>`, e.g.
  `E03-F01@viernes-bff`), `repo`, `status`, `merged`, `spec_path`, optional `pr` (the
  PR URL the child loop opened — the merge-poll selector), and cross-repo
  `depends_on`. A sliced feature can only be persisted `done` when **every** slice is
  `done`+`merged` (enforced by `tasks.schema.json` cross-field validation and the
  `init.sh` fallback), so a hand-edited store cannot unblock dependents early.
- **Manifest** — `umbrella.manifest.yaml`: maps each `repo` to its `path`, `init`,
  `test_command`, and (only for `backend: delegate`) `delegate_cmd`. The coordinator
  reads it to locate and dispatch each child repo. **Two path bases, by design:** the
  `umbrella.manifest` value in `harness.config.yaml` resolves relative to the harness
  dir (`.harness/`, `init.sh`'s cwd), while each entry's `path:` resolves relative to
  **the manifest file's own directory** (the umbrella root). The cascade installer
  reconciles these by placing the manifest at the umbrella root and pointing
  `umbrella.manifest` at `../umbrella.manifest.yaml`.
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
2. **dispatch** — how a slice is dispatched is chosen by `execution.builder.backend`
   in the umbrella's `harness.config.yaml` (the same global Builder switch documented
   in `agents/builder.md`). Both modes run **from that child repo's working directory**
   (`cd` into the manifest `path` first):

   - **`in-session` builder (default, zero-dependency).** The Orchestrator drives the
     child repo's **own SDD loop** from inside it — not a bare Builder. Because Builder
     Loop A refuses to write code unless the *local* feature is `in-progress`, and the
     slice's status lives in the **parent** TaskStore, the Orchestrator first **seeds
     child-local state**: it ensures the child repo's TaskStore has a feature entry for
     the slice (pointing at the emitted slice spec) set to `in-progress`. It then spawns
     the **Builder** sub-agent (clean context, `cd`'d into the manifest `path`, handed
     only that slice's `.spec`/`.plan`/`.tasks`/`.tests` plus the pinned contract
     artifact) to implement via Loop A, lets the child repo's **Reviewer** verify, opens
     the child repo's PR, and **captures its URL** for the slice `pr`. (Builder Loop A
     only reports completion; PR creation is part of the child loop, not the Builder.)
     The per-repo `delegate_cmd` is **not used** here and may be left empty. **This is
     the natural mode for a single code-agent session driving every child repo** — it
     needs no external executor.
   - **`delegate` builder (only when an executor is wired).** Invoke that slice's repo
     `delegate_cmd` from the manifest using the existing seam contract **verbatim**:

     ```
     <delegate_cmd> <feature-id> <abs-spec-path>
     ```

     so a repo-local relative `delegate_cmd` (e.g. `./run-sdd.sh`) resolves correctly.

   In **both** modes the umbrella **never edits source files** in the child repo
   itself — the child repo's own SDD loop owns implementation, its PR, and its review.
3. **gate** — never dispatch a downstream slice's Builder, nor open that downstream
   repo's PR, while any of its upstream `depends_on` slices is not yet `done` **and**
   `merged`.
4. **fail-stop** — if a dispatched slice fails (a `delegate_cmd` non-zero exit, or —
   under `in-session` — the child loop's Builder/Reviewer reporting it cannot complete),
   set that slice's status to `failed`, halt dispatch of its downstream dependents, and
   surface the failure. Do not improvise a fix.
5. **advance** — on a slice's successful completion, record its status as `done` and
   **persist the PR URL** into the slice's `pr` field — under `delegate` the executor
   returns it; under `in-session` it is the URL captured in the dispatch step's
   Review+PR sub-step. `done` alone does not unblock dependents.
6. **observe-merge** — poll the slice's PR to merge with `gh pr view <slice.pr>
   --json state` (a PR **URL** is a valid selector and needs no `-R`; never pass the
   short manifest `repo` key to `-R`). If no `pr` was persisted, fall back to a
   default-branch landing check in the manifest `path` or require an explicit human
   `merged: true`, and surface that the slice awaits merge confirmation — never leave
   the chain silently stuck. On confirmed merge set `merged: true`, then re-run
   **select** so newly-unblocked downstream slices become dispatchable.

The dispatch step is just the existing single-repo Builder, scoped to one slice with
cross-repo gating/ordering around it. Under `in-session` it is the Builder sub-agent
run inside the child repo; under `delegate` it is the `execution.builder.delegate`
seam invoked once per slice. Nothing new is added to the Builder contract — umbrella
mode only adds the slice selection, gating, merge-poll, and rollup around it.

## Integration verification (rollup)
The feature `done` verdict is **derived** from slice state, then **persisted** (never
set `done` prematurely while a slice or the integration gate is red):

- **Gated** — while **any** slice of the feature is not `done`, the coordinator does
  **not** run the integration check.
- **Run** — only when **every** slice is `done` **and** `merged`, the coordinator runs
  the configurable `verification.integration_command` (the stack running together,
  e.g. `viernes-infra/dev.sh ci`). If `integration_command` is empty there is no
  integration gate.
- **Done** — the feature reaches `done` **only when** all per-repo slices pass their
  own verification **and** the integration command exits **zero**. When that holds the
  coordinator **writes** the derived `done` onto the feature (feature-level
  `depends_on` gates on the *stored* status, so a dependent feature stays blocked until
  the upstream `done` is actually persisted). The schema enforces this cross-field
  invariant — a feature cannot be stored `done` while any slice is not `done`+`merged`.
- **Failure** — if the integration command exits **non-zero**, keep the feature out of
  `done` and surface the integration failure.

## Manifest reference
See `umbrella.manifest.example.yaml`. One entry per child repo under `repos:`, each
with `path`, `init`, `test_command`, and `delegate_cmd`. `delegate_cmd` is **required
only under `backend: delegate`**; under the default `backend: in-session` it is unused
and may be left empty. A slice whose `repo` is absent from `repos:` is undispatchable
and must be reported.
