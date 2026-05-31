---
id: E03
title: Multi-repo coordination
status: pending          # pending → in-progress → done (rollup of its features)
owner: araozmd
---

# Epic E03 — Multi-repo coordination

## Business brief
Real products span more than one git repo. The motivating case is `viernes/`: a
non-git umbrella directory holding five sibling repos — `viernes-web` (front),
`viernes-bff`, `lia-api`, `lia-bff`, and `viernes-infra`. A single product feature
(e.g. a new onboarding step) is **one intent** that fans out into a contract change
in the API, passthroughs in the BFFs, and UI in the front — N implementations, N
verifications, N pull requests that must merge in dependency order.

Today the harness is repo-scoped: `init.sh`, `verification.test_command`, and the
Reviewer's `done` verdict all assume a single repo root. This epic adds a thin
**umbrella coordinator** layer that owns the shared spec and a feature-level
TaskStore, decomposes a cross-repo feature into per-repo slices, delegates each
slice down to that repo's own harness, enforces a `depends_on` merge order, and
rolls verification up so a feature is `done` only when every slice passes in
isolation AND an integration check passes.

## Success criteria (epic level)
- A cross-repo feature is specified once (one shared `.spec`/`.plan`) and tracked as
  a single rollup status across all participating repos.
- Each repo's slice is implemented and verified by that repo's own harness
  (its own `init.sh` / tests), in a clean context — no role files are forked.
- Slices merge in a declared dependency order; a downstream repo's PR is never
  opened/merged before its upstream contract slice is `done` and merged.
- The feature reaches `done` only after all per-repo slices pass AND an integration
  check (the stack running together) passes.
- Adding the umbrella requires **no change to the existing single-repo flow** — a
  lone repo keeps working exactly as it does today.

## Design decisions (locked with the user, 2026-05-30)
- **Spec home:** umbrella harness installed in the non-git `viernes/` directory.
  Shared `.spec`/`.plan` live there; per-repo `.tasks`/`.tests` slices are emitted
  into each child repo. No new git repo is introduced.
- **Execution:** the umbrella Builder uses the existing `execution.builder.delegate`
  seam (`delegate_cmd <feature-id> <abs-spec-path>`) to run each child repo's own
  SDD loop. The umbrella never writes source code.
- **Merge order:** enforced via the `depends_on` graph already in
  `tasks.schema.json` — promoted from intra-repo to cross-repo. The coordinator
  topologically sorts slices and gates dispatch/merge on upstream completion.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Umbrella coordinator | done | true | — |
| F02 | Cascade installer | pending | true | F01 |

## Notes
- **F02 cascade installer (design intent, to be specified at its own gate):** the
  current `harness-install.sh` is single-target with no git detection. F02 extends it
  so installing into the umbrella dir (a) writes a *coordinator* profile there
  (manifest + integration command, no per-repo test wiring) and (b) scans immediate
  children, installs the normal `.harness/` into each that contains `.git`, and
  auto-populates `umbrella.manifest.yaml`. One level deep by default (deeper =
  opt-in), detect `.git` as dir *or* file (worktrees/submodules), idempotent and
  additive on re-run (rediscover new repos, never clobber project-owned content).
- Two genuinely net-new artifacts the Architect must define:
  1. **Contract artifact** — the inter-repo seam (OpenAPI fragment / event payload /
     shared types) pinned in the shared spec so parallel Builders don't drift.
  2. **Integration verification** — a coordinator-level check (likely via
     `viernes-infra` + `dev.sh`) gated behind all per-repo greens.
- Reuse over invention: lean on `execution.builder.delegate`, swappable store
  backends, and `depends_on`. Prefer extending the schema (a per-slice `repo` field)
  over forking role prompts.
- Versioning: this changes the installed body (schema, agents glue, config), so it
  warrants a SemVer MINOR bump per CLAUDE.md when the F01 PR is ready to merge.
