# Builder report — E06-F06 (Drift check on epic rollup)

Branch: `feat/drift-check-rollup` · status stays `in-progress` for the Reviewer.

## Tasks completed (all 8)
- **T1** (R1, R9, R14) — `store/local.md`: added "Epic-done rollup" + "Drift check on epic rollup"
  subsections beside (not inside) the existing sliced-feature rollup.
- **T2** (R2, R3, R7, R8, R9, R10, R11, R12, R13) — `agents/orchestrator.md`: added the
  "Epic-done rollup + drift check" section (derive+persist epic `done`, re-validate, trigger
  drift before selecting next; read-only Scout; Scout-flags/Orchestrator-acts demotion;
  backward-only invariant; re-drill pointer + flag-only note; no-op note).
- **T3** (R4, R5, R6, R12, R13) — `agents/scout.md`: added a read-only "Drift-check mode"
  (inputs, findings file `progress/<run>/scout-drift-<epic>.md`, S1/S2/S3 signals, ≥1-fires gate,
  "nothing to re-validate" no-op). Read-only contract preserved — no `state/tasks.json` write.
- **T4** (R15) — `docs/WORKFLOW.md`: added a distinct "Drift check on epic rollup" section.
- **T5** (R1–R19) — created `tests/test_drift_check.sh` (19 assertions; temp-store schema
  fixture for the `done`-epic + `draft`-epic shapes; VERSION read at runtime; CHANGELOG marker
  grepped across the whole file).
- **T6** (wiring) — `harness.config.yaml`: appended `&& sh tests/test_drift_check.sh`.
- **T7** (R19) — `VERSION` 0.19.0 → 0.20.0; matching `CHANGELOG.md` `## [0.20.0]` entry.
- **T8** — full `verification.test_command` green (271 ok / 0 FAIL / EXIT 0); `./init.sh` exit 0.

## Anti-pattern repair (recurred again on this MINOR bump)
The 0.20.0 bump tripped the recorded permanent-suite anti-pattern in two prior suites that
grepped the `## [$V]` (current-top) CHANGELOG section for a feature marker:
- `tests/test_sdd_plan.sh::R23` (was FAILING) and `tests/test_sdd_drill.sh::R22` (latent).
De-coupled both to grep the `/sdd-plan` / `/sdd-drill` marker across the WHOLE CHANGELOG, per
the spec's "Constraints carried into the test contract" and the project memory. No behavior of
F02/F03 changed — only the brittle version-coupling in their test assertions.

## Invariants confirmed
- `agents/scout.md` stays **read-only**: the drift-check mode writes only to `progress/`,
  makes no state change, never writes `state/tasks.json`. The demotion `set_status` write is
  the **Orchestrator's** alone (Scout flags / Orchestrator acts).
- No `store/tasks.schema.json` change — `draft`/`planned`/`pending`/`done` reused as-is.
- Non-tautology spot-check: removing the `demoted on drift` marker fails R11; restoring passes.
