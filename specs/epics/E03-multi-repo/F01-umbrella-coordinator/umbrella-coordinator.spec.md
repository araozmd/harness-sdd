---
id: E03-F01
title: Umbrella coordinator
epic: E03
status: pending          # pending → spec-ready → in-progress → in-review → done
sdd: true                # false = quick task, skip full SDD
autonomous: false        # true = may bypass the human approval gate
depends_on: []
owner: araozmd
---

# Umbrella coordinator — Functional Spec

## Context
Real products span more than one git repo. The motivating case is `viernes/`: a
**non-git umbrella directory** holding sibling repos — `viernes-web`, `viernes-bff`,
`lia-api`, `lia-bff`, `viernes-infra`. One product feature is **one intent** that
fans out into a contract change in the API, passthroughs in the BFFs, and UI in the
front: N implementations, N verifications, N pull requests that must merge in
dependency order. Today the harness is repo-scoped — `init.sh`,
`verification.test_command`, and the Reviewer's `done` verdict all assume a single
repo root. This feature adds a thin **umbrella coordinator** layer that owns the
shared spec and a feature-level TaskStore, decomposes a cross-repo feature into
per-repo **slices**, delegates each slice to that repo's own harness, enforces a
`depends_on` merge order across repos, and rolls verification up so a feature is
`done` only when every slice passes in isolation **and** an integration check passes.

This is a **harness feature** — it changes the harness's own structure (schema,
config, agent glue), not application code. The umbrella never writes source code: it
specifies once and delegates down.

## Business rules
- **Spec home = umbrella.** The shared `.spec`/`.plan` live in a harness installed in
  the non-git umbrella directory. Per-repo `.tasks`/`.tests` slices are emitted into
  each child repo. No new git repo is introduced.
- **Execution = delegate.** The umbrella Builder uses the existing
  `execution.builder.delegate` seam (`<delegate_cmd> <feature-id> <abs-spec-path>`)
  to run each child repo's own SDD loop in a clean context. The umbrella never edits
  source files itself.
- **Merge order = `depends_on` graph.** The existing `depends_on` field is promoted
  from intra-repo to cross-repo. Slices are topologically sorted; a downstream repo's
  Builder is not dispatched and its PR is not opened until every upstream slice it
  depends on is `done` and merged.
- **One contract, no drift.** A single contract artifact (the inter-repo seam) is
  pinned in the shared spec; every slice references it so parallel Builders agree on
  the wire/shape.
- **Additive / opt-in.** A single-repo project must keep working unchanged. The
  umbrella layer is only engaged when an umbrella manifest is present.

## Definitions
- **Umbrella** — the non-git parent directory hosting the coordinator harness.
- **Slice** — a per-repo unit of work for one cross-repo feature; carries a `repo`
  field and its own cross-repo `depends_on`. Each slice maps to one child-repo
  feature with its own `.tasks`/`.tests`.
- **Manifest** — the umbrella's map from feature/slice to the child repos (path,
  `init.sh`, `test_command`, delegate command).
- **Contract artifact** — the pinned inter-repo seam (OpenAPI fragment / event
  schema / shared types) referenced by every slice.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.
> "Coordinator" denotes the umbrella-level harness (TaskStore + Orchestrator loop).

### TaskStore model for cross-repo features
- **R1** — The TaskStore schema shall allow a feature to declare one or more
  **slices**, where each slice has a `repo` identifier and its own slice id.
- **R2** — The TaskStore schema shall allow each slice to declare a cross-repo
  `depends_on` listing the slice ids (and/or feature ids) that must be `done` before it.
- **R3** — While any slice of a feature is not `done`, the coordinator shall report
  the feature's rolled-up status as not `done` (i.e. a feature is `done` only when
  **every** slice is `done`).
- **R4** — The TaskStore schema as extended shall remain **backward compatible**: a
  feature with no `slices` field shall validate and behave exactly as it does today
  (single-repo, no slices).

### Manifest
- **R5** — The coordinator shall read an umbrella **manifest** that maps each child
  repo to its filesystem path, its `init.sh`, its `test_command`, and its delegate
  command.
- **R6** — If a slice names a `repo` that is absent from the manifest, then the
  coordinator shall refuse to dispatch that slice and report an error identifying the
  missing repo.

### Contract artifact (inter-repo seam)
- **R7** — The shared `.spec`/`.plan` shall pin exactly one **contract artifact**
  (the inter-repo seam) at a stable path in the umbrella, referenced by id from the
  spec.
- **R8** — Each slice's emitted `.tasks`/`.tests` shall reference the pinned contract
  artifact, so the traceability matrix links every slice back to the shared seam.

### Dispatch + gating
- **R9** — When selecting the next actionable slice, the coordinator shall choose a
  slice in topological order whose upstream `depends_on` slices are all `done` **and**
  merged.
- **R10** — When a slice is dispatched, the coordinator shall invoke that repo's
  delegate command using the existing seam contract `<delegate_cmd> <feature-id>
  <abs-spec-path>` and shall not write source code in the child repo itself.
- **R11** — If an upstream slice is not yet `done` and merged, then the coordinator
  shall not dispatch a downstream slice's Builder nor open that downstream repo's PR.
- **R12** — If a dispatched slice's delegate command exits non-zero, then the
  coordinator shall mark that slice failed, halt dispatch of its downstream
  dependents, and surface the failure.
- **R13** — When a slice completes successfully, the coordinator shall record its
  status as `done` and re-evaluate which downstream slices have become dispatchable.

### Integration verification
- **R14** — While not every slice of a feature is `done`, the coordinator shall not
  run the feature-level integration check.
- **R15** — When every slice of a feature is `done` and merged, the coordinator shall
  run a configurable **integration command** (the stack running together, e.g. via
  `viernes-infra`/`dev.sh`) before declaring the feature `done`.
- **R16** — The feature shall reach `done` only after all per-repo slices pass their
  own verification **and** the integration command exits zero.
- **R17** — If the integration command exits non-zero, then the coordinator shall keep
  the feature out of `done` and surface the integration failure.

### Non-regression (additive / opt-in)
- **R18** — Where no umbrella manifest is present, the coordinator behavior shall be
  inert and the existing single-repo flow (`init.sh`, `verification.test_command`,
  Reviewer `done` verdict) shall behave exactly as it does today.
- **R19** — The existing `tasks.schema.json` consumers (the `local` store,
  `init.sh` validation) shall continue to validate today's single-repo
  `state/tasks.json` after the schema extension.

## Out of scope
- The concrete format of the contract artifact (OpenAPI vs event schema vs shared
  types) — only its existence, single-pin location, and traceability are required.
- Implementing any child repo's slice (that is each repo's own SDD loop via delegate).
- A real `delegate_cmd` executor — this feature targets the existing seam contract;
  wiring a specific executor is the target project's concern.
- Cross-repo PR automation beyond the gating order (the act of opening/merging a PR is
  owned by each child repo's delegate; the coordinator only gates it).
- Multi-umbrella / nested-umbrella topologies.
- Converting the umbrella directory into a git repo.

## Open questions
- Should slice `depends_on` reference **slice ids** (`E03-F01@viernes-bff`) or
  **feature+repo** pairs? Plan proposes slice ids of the form `<feature-id>@<repo>`;
  confirm before locking the schema.
- Where the coordinator loop lives: a small additive `umbrella` section in
  `harness.config.yaml` plus an additive instruction block read by the Orchestrator
  role, vs. a separate `agents/umbrella.md`. Plan proposes **additive config +
  instruction**, not a forked role — confirm.
- The integration command's key name/location: proposed `verification.integration_command`
  in the umbrella's config (sibling of `test_command`). Confirm naming.
