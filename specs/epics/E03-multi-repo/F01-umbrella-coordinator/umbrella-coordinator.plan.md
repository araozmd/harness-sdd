# Umbrella coordinator — Technical Plan

> Translates umbrella-coordinator.spec.md into design. Each decision cites the
> R-id(s) it serves. This is a harness feature: it extends existing seams (schema,
> config, the `execution.builder.delegate` hook, `depends_on`) rather than forking
> any `agents/*.md` role. Start high-level where the path is uncertain; pin the
> contracts that prevent drift.

## Stack & dependencies
- Languages: JSON Schema (draft-07, the existing `store/tasks.schema.json` dialect),
  Markdown (specs + agent instructions), YAML (`harness.config.yaml`), POSIX `sh`
  (validation in `init.sh`). Matches the existing zero-dependency ethos.
- New dependencies: none. Topological sort and rollup are expressible in the
  Orchestrator's existing read/loop logic over the TaskStore.

## Design overview
Four seams, each extended additively:

1. **Schema** — add an optional `slices[]` to a feature; each slice carries `id`,
   `repo`, `status`, `spec_path` and cross-repo `depends_on`. Absent `slices` ⇒
   today's single-repo behavior, unchanged.
2. **Manifest** — a new umbrella-only file mapping `repo` → `{ path, init, test,
   delegate }`. Present ⇒ umbrella mode engaged; absent ⇒ inert.
3. **Config** — additive keys: `verification.integration_command` and a small
   `umbrella` block pointing at the manifest. No existing key changes meaning.
4. **Loop** — an additive, umbrella-aware instruction block (read by the
   Orchestrator role) describing slice selection, gating, delegation and rollup.
   No role file is forked.

## Data model — TaskStore schema extension  (serves: R1, R2, R3, R4, R19)
Extend the per-feature object in `store/tasks.schema.json` with an **optional**
`slices` array. The feature's own `status`/`depends_on` keep their meaning.

| Entity | Field | Type | Notes |
|---|---|---|---|
| feature | `slices` | array (optional) | absent ⇒ single-repo, unchanged (R4, R19) |
| slice | `id` | string | proposed pattern `^E[0-9]+-F[0-9]+@[a-z0-9-]+$`, e.g. `E03-F01@viernes-bff` (R1) |
| slice | `repo` | string | must match a manifest `repo` key (R1, R6) |
| slice | `status` | enum | `pending\|spec-ready\|in-progress\|in-review\|done` (R3, R13) |
| slice | `merged` | boolean | true once the slice's PR is merged in its repo (R9, R11) |
| slice | `spec_path` | string | path to the slice's emitted `.tasks`/`.tests` in the child repo (R8) |
| slice | `depends_on` | array of slice ids | cross-repo upstreams (R2, R9) |

**Rollup rule (R3):** a feature is `done` ⟺ every slice is `done` **and** the
feature-level integration check has passed (see R15/R16). The coordinator never sets
a feature `done` directly; it derives it.

**Backward compatibility (R4, R19):** `slices` is not in any `required` list; the
schema must still validate today's `state/tasks.json` (no `slices`). `init.sh`'s
existing JSON-load + schema check must keep passing on a single-repo store.

## Manifest  (serves: R5, R6, R18)
New file, umbrella-only (proposed): `umbrella.manifest.yaml` at the umbrella harness
root. One entry per child repo.

```yaml
# umbrella.manifest.yaml  (PROPOSED shape — confirm key names at spec-ready)
repos:
  viernes-bff:
    path: ../viernes-bff          # filesystem path, relative to umbrella root
    init: ./init.sh               # that repo's own init
    test_command: "npm test"      # that repo's own verification
    delegate_cmd: "<executor> "   # invoked as <delegate_cmd> <feature-id> <abs-spec-path>
  lia-api:
    path: ../lia-api
    init: ./init.sh
    test_command: "pytest"
    delegate_cmd: "<executor> "
```

- Presence of this file is the **umbrella-mode switch** (R18). Absent ⇒ coordinator
  is inert and the single-repo flow is untouched.
- A slice whose `repo` is not a key here is undispatchable and reported (R6).

## Config — additive keys  (serves: R5, R15, R18)
Extend `harness.config.yaml` additively (no existing key changes meaning):

| Key | Purpose | R-id |
|---|---|---|
| `umbrella.manifest` | path to `umbrella.manifest.yaml`; unset ⇒ single-repo | R5, R18 |
| `verification.integration_command` | the stack-up integration check (e.g. `viernes-infra/dev.sh ci`); empty ⇒ no integration gate | R15, R16 |

## Contract artifact (inter-repo seam)  (serves: R7, R8)
- The shared spec pins **one** contract artifact at a stable umbrella path
  (proposed: `specs/epics/<epic>/<feature>/contract/`), referenced from the
  `.spec.md`/`.plan.md` by a stable id. Format is intentionally unspecified (R7).
- When slices are emitted, each child repo's `.tasks`/`.tests` references the pinned
  artifact (by path/id) so the traceability matrix links every slice to the seam (R8).

## Coordinator loop — additive instruction, not a forked role  (serves: R9–R17)
Specified as an **additive umbrella-aware instruction block** the Orchestrator reads
when `umbrella.manifest` is set. It does not replace `agents/orchestrator.md`; it
extends its `next()`/dispatch behavior for slices:

1. **select** (R9) — among feature slices, pick the lowest-id slice that is actionable
   and whose every `depends_on` upstream slice is `done` **and** `merged`. Topological
   order falls out of repeatedly applying this rule.
2. **dispatch** (R10) — invoke the slice repo's `delegate_cmd` from the manifest as
   `<delegate_cmd> <feature-id> <abs-spec-path>`, in that repo. Never edit source in
   the child repo from the umbrella.
3. **gate** (R11) — never dispatch a downstream Builder nor open its PR while an
   upstream slice is not `done`+`merged`.
4. **fail-stop** (R12) — non-zero delegate exit ⇒ mark slice failed, halt its
   downstream dependents, surface the failure.
5. **advance** (R13) — on success, set slice `done` and re-run select.
6. **integration gate** (R14, R15, R16, R17) — only when all slices are `done`+`merged`,
   run `verification.integration_command`; zero ⇒ feature `done`; non-zero ⇒ keep
   feature out of `done` and surface the failure.

This reuses the existing `execution.builder.delegate` contract verbatim (R10) — the
umbrella Builder is just the delegate seam invoked once per slice.

## Files to change  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `store/tasks.schema.json` | modify — add optional `slices[]` (id, repo, status, merged, spec_path, depends_on); keep `slices` non-required | R1, R2, R3, R4, R19 |
| `store/local.md` | modify — document slice/rollup read semantics and the `done`-only-when-all-slices-done rule | R3, R13 |
| `harness.config.yaml` | modify — add `umbrella.manifest` and `verification.integration_command` (defaults keep single-repo inert) | R5, R15, R18 |
| `umbrella.manifest.example.yaml` | create — documented example manifest (repo → path/init/test/delegate) | R5, R6 |
| `docs/UMBRELLA.md` | create — the coordinator model: spec-home, slices, contract pin, dispatch/gating order, integration gate, opt-in switch | R7, R8, R9–R17, R18 |
| `agents/orchestrator.md` | modify — append an additive "Umbrella mode" section (engaged only when `umbrella.manifest` set) describing select/dispatch/gate/advance/integration; no fork | R9–R17, R18 |
| `init.sh` | modify (if needed) — keep schema validation green for both single-repo and sliced stores; optionally warn if a manifest references a missing repo path | R6, R19 |
| `tests/test_umbrella.sh` | create — executable test contract for all R-ids (see .tests.md) | all |

## DO NOT TOUCH
- `agents/architect.md`, `agents/builder.md`, `agents/reviewer.md`, `agents/scout.md`
  — no role is forked; umbrella behavior is additive config/instruction on the
  Orchestrator only.
- The existing single-repo semantics of `verification.test_command`,
  `execution.builder.delegate` / `delegate_cmd`, and `init.sh`'s self-locate — these
  are reused, not redefined.
- Any `state/tasks.json` for a single-repo target — the schema change must be a pure
  superset (R4, R19).

## Approach notes
- **Pure superset schema:** add fields, never tighten `required`. The single
  guarantee that protects every downstream consumer (R4, R19).
- **Opt-in by presence:** the manifest file (not a boolean flag) is the switch, so a
  repo with no manifest is provably inert (R18).
- **Reuse the delegate contract exactly:** `<delegate_cmd> <feature-id> <abs-spec-path>`
  — the umbrella adds gating/ordering around it, nothing new in the seam (R10).
- **Derive, don't set, feature `done`:** rollup + integration are computed from slice
  state, so there is no path to a green feature with a red slice (R3, R16).
- Leave the contract-artifact format unspecified on purpose (R7); over-specifying it
  would cascade errors into every child repo's slice.
