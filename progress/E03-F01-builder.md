# E03-F01 Umbrella coordinator — Builder hand-off

**Status:** implementation complete, all tasks ticked, all checks green. Handing to
the Orchestrator for `in-review`. (Builder does NOT set `done`.)

## Gate / preconditions
- `./init.sh` green at start. Feature `status` in `state/tasks.json` confirmed
  `in-progress` (human-approved) before any code was written.
- Built with the three resolved open-question defaults: slice id pattern
  `^E[0-9]+-F[0-9]+@[a-z0-9-]+$`; additive "Umbrella mode" section on the
  Orchestrator (no role fork) + additive config; integration key
  `verification.integration_command`.

## Tasks completed (T1–T11, in order)
- **T1 (R1,R2)** — `store/tasks.schema.json`: added optional `slices[]` to the feature
  object. Slice item requires `id`/`repo`/`status`; optional `merged`/`spec_path`/
  `depends_on`. `slices` is NOT in any `required` list (pure superset).
- **T2 (R4,R19)** — Verified pure superset: current `state/tasks.json` (no slices)
  still validates; `./init.sh` green.
- **T3 (R3,R13)** — `store/local.md`: documented slice read semantics + rollup rule
  (feature `done` is derived, never set directly; re-evaluate dispatchable on advance).
- **T4 (R5,R6)** — created `umbrella.manifest.example.yaml` (repo → path/init/
  test_command/delegate_cmd; presence = mode switch; unknown repo undispatchable).
- **T5 (R5,R15,R18)** — `harness.config.yaml`: added `verification.integration_command`
  (default `""`) and an `umbrella.manifest` key (default `""`). No existing key changed
  meaning; single-repo defaults stay inert.
- **T6 (R7,R8)** — `docs/UMBRELLA.md`: contract artifact pinned once at a stable path,
  referenced by id; every emitted slice references it. Format left unspecified by design.
- **T7 (R9–R13)** — `docs/UMBRELLA.md` + additive "Umbrella mode" section appended to
  `agents/orchestrator.md`: select (topo, upstreams done+merged) / dispatch
  (`<delegate_cmd> <feature-id> <abs-spec-path>`, no source edits) / gate / fail-stop /
  advance. No role fork.
- **T8 (R14–R17)** — same docs/instruction: integration gate + rollup.
- **T9 (R18,R6)** — `init.sh`: added a NON-FATAL, opt-in umbrella branch. Engaged only
  when `umbrella.manifest` is non-empty AND the file exists; warns about missing child
  repo paths; never blocks the gate. Single-repo run is untouched (verified).
- **T10** — `tests/test_umbrella.sh` (POSIX sh, zero-dep) covering every R-id.
- **T11** — full verification (below).

## Files touched (all within the plan's allow-list)
- modified: `store/tasks.schema.json`, `store/local.md`, `harness.config.yaml`,
  `agents/orchestrator.md`, `init.sh`
- created: `umbrella.manifest.example.yaml`, `docs/UMBRELLA.md`,
  `tests/test_umbrella.sh`
- `state/tasks.json` NOT touched. No application/product code touched. No role file
  other than the Orchestrator touched (and that was append-only).

## Verification — exact commands and results (all PASS, exit 0)
1. `./init.sh` → `✅ environment ready` — EXIT 0
2. `sh tests/test_install.sh` (no-regression) → `All install tests passed.` — EXIT 0
3. `sh tests/test_umbrella.sh` → `All umbrella tests passed.` — EXIT 0 (20 `ok -` lines;
   every R1–R19 mapped to a passing assertion per umbrella-coordinator.tests.md)
4. Extra confidence check: ran `./init.sh` in a temp copy with a manifest configured
   (one present + one missing repo path) → printed the non-fatal warning naming
   `ghost-repo` and the `umbrella mode: manifest present` notice, EXIT 0.

`jsonschema` (Draft7) IS installed locally, so the schema tests use the real
validator. Confirmed the negative case (slice missing `repo`) fails with
`'repo' is a required property`. The fallback structural validator in both
`init.sh` and `tests/test_umbrella.sh` encodes the same slice invariants for the
zero-`jsonschema` environment.

## R-id traceability (R1–R19) — all covered by passing checks
Schema: R1, R2, R4, R19. Doc/config presence: R5, R7, R8, R15, R18. Reference
algorithm over fixtures + stub delegate/integration: R3, R6, R9–R17. See the
`[test_*]` tags echoed by each `ok -` line.

## What the Reviewer should scrutinize
- **Schema is the load-bearing contract.** Confirm `slices` was added as a pure
  superset — no `required` list tightened, existing single-repo `state/tasks.json`
  still validates. (init.sh's zero-dep fallback validator does NOT inspect `slices`;
  that is intentional leniency, not a tightening — the real validator does.)
- **No role fork.** Only `agents/orchestrator.md` changed, append-only. architect/
  builder/reviewer/scout untouched. Delegate seam reused verbatim
  (`<delegate_cmd> <feature-id> <abs-spec-path>`).
- **Test nature.** The coordinator loop is documented instruction, not shipped code.
  Per umbrella-coordinator.tests.md, `tests/test_umbrella.sh` proves the documented
  algorithm is implementable by running a small POSIX-sh reference of select/gate/
  fail-stop/advance/rollup/integration over fixtures with a stub delegate. Reviewer
  should confirm this is the intended verification strategy for a harness/structural
  feature (the .tests.md explicitly sanctions schema/doc/config-presence + fixture
  checks rather than application unit tests).
- **`verification.test_command` unchanged** (`sh tests/test_install.sh`). The .tests.md
  did not mandate changing it; `tests/test_umbrella.sh` is independently runnable. If
  the Reviewer/Orchestrator wants the umbrella suite wired into the default command,
  that is a one-line config decision left to them.

## Open concern (not blocking, needs a deliberate decision)
- **VERSION bump.** This PR changes the installed body (`store/`, `harness.config.yaml`,
  `agents/`, `docs/`, `init.sh`) and adds a new backward-compatible capability →
  per CLAUDE.md a **MINOR** bump (`0.1.0` → `0.2.0`) plus a `CHANGELOG.md` entry is
  warranted before merge. I did NOT bump it — versioning is a deliberate release call.
  Flagging for the Orchestrator/Reviewer to action before the PR merges.
