# E05-F02 — Builder progress (Loop A, in-session)

Feature: Sub-agent & human-gate telemetry with rollup reports. Status `in-progress`
(human-approved at the gate). Implemented strictly from the reconciled spec
(R1–R27, gate decisions 2026-06-06).

## Tasks completed (in order)
- **T1, T13, T14** — Added "## Telemetry" section to `agents/orchestrator.md`: log path
  `<HARNESS_DIR>/telemetry.jsonl` (gitignored/local-only, overridable via `telemetry.log`),
  `phase`/`gate`/`session-start` record shapes with `schema_version`, `type` discriminator,
  reserved `cost` (null today), `date -u +%FT%TZ` ISO-8601 UTC source, single-writer +
  best-effort/never-block rules, the session-start marker, and the portable
  "### End-of-session summary" subsection (invokes `python3 tools/telemetry-report.py session`).
- **T2** — "How you delegate": best-effort Telemetry paragraph (capture start before spawn,
  end on report-back, derive `duration_s`, append one `phase` record; never blocks).
- **T3** — Loop step 5 + build↔review rounds: `round`=1 on first build, +1 per
  `in-review`→`in-progress` bounce, stamped on builder/reviewer phase records.
- **T4** — Step 4 routing: gate open (`spec_ready_at`) on setting `spec-ready`, gate close
  (`in_progress_at` + derived `human_latency_s` + `autonomous` flag) on `in-progress`.
- **T5** — Umbrella dispatch: `slice-dispatch` phase record carrying the slice id.
- **T6** — `harness.config.yaml`: optional `telemetry:` block (`enabled` kill-switch,
  `log: telemetry.jsonl` under HARNESS_DIR), cost-out documented.
- **T7/T7a/T7b** — Runtime log never tracked; source `.gitignore` ignores `/telemetry.jsonl`;
  `harness-install.sh` seeds a targeted `.harness/.gitignore` (telemetry.jsonl, seed-once /
  never-clobber, verified idempotent in a real install).
- **T8/T15** — Created `tools/telemetry-report.py` (python3 stdlib only): daily/weekly/
  monthly/quarterly/semester/annual + `session` view; default all-granularity summary;
  malformed lines skipped; absent/empty ⇒ exit 0 + "no telemetry yet"; latency excludes
  autonomous; ignores `cost`.
- **T9/T16/T16a** — Created `tests/test_telemetry.sh`: R1–R27 traceability (fixture-driven
  rollups via temp `--log`, best-effort/empty no-op, schema/format, both gitignores, the
  AGENTS.md pointer, session scoping).
- **T10** — Wired `&& sh tests/test_telemetry.sh` into `verification.test_command`.
- **T11** — Bumped `VERSION` 0.6.0 → 0.7.0 (MINOR ✨) + `CHANGELOG.md` entry.
- **T14a** — One-line end-of-session-summary pointer added to `AGENTS.md`.
- **T12** — Self-check: `./init.sh` green; full `verification.test_command` chain green
  (install + umbrella + cascade + inception + reviewer + telemetry).

## Self-check result
- `./init.sh` → green.
- Full test chain → PASS (all six suites). `test_reviewer.sh::R12` confirms VERSION 0.7.0
  is coupled to its CHANGELOG entry.

## Notes / no spec drift
- DO NOT TOUCH honored: no changes to existing R1–R21 record shapes, no renumbering, no
  sub-agent role files, no `init.sh`, no `store/tasks.schema.json`, no `state/tasks.json`,
  no cost computation. `AGENTS.md` touched only for the one-line pointer.
- Did NOT commit, open a PR, or change feature status. Handing back to the Orchestrator
  for `in-review`.
