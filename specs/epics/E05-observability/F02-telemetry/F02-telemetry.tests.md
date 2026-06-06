# Sub-agent & human-gate telemetry with rollup reports — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete, executable
> test. The Reviewer fails the feature if any R-id lacks a passing test.
>
> This feature ships PROSE (Orchestrator role edits) + ONE python3-stdlib script + a
> config block. Verification is therefore a mix of: (a) **behavioral** assertions
> against `tools/telemetry-report.py` driven by fixture JSONL the test writes, and
> (b) **static** greps that the capture contract is present in `agents/orchestrator.md`.
> Zero deps: POSIX sh + grep + python3. All assertions live in `tests/test_telemetry.sh`.

| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | one phase record appended per finished phase | `tests/test_telemetry.sh::report_counts_phase_records` (fixture with N phase lines → report phase count = N) | behavioral | ⬜ |
| R2 | phase record has all required fields | `tests/test_telemetry.sh::phase_schema_fields` (assert feature, phase, start, end, duration_s, outcome, round present in fixture/schema doc) | static+behavioral | ⬜ |
| R3 | timestamps are ISO-8601 UTC | `tests/test_telemetry.sh::iso8601_utc_timestamps` (regex `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$`; orchestrator prose mentions `date -u`) | static | ⬜ |
| R4 | duration_s = end − start, non-negative | `tests/test_telemetry.sh::duration_derivation` (fixture with known start/end → report's summed time matches; report rejects/ignores negative) | behavioral | ⬜ |
| R5 | phase ∈ enumerated roles | `tests/test_telemetry.sh::phase_enum` (report buckets architect/builder/reviewer/scout/inception/slice-dispatch in per-phase breakdown) | behavioral | ⬜ |
| R6 | round increments on review bounce | `tests/test_telemetry.sh::round_counter_prose` (grep `agents/orchestrator.md` for round-increment on `in-review`→`in-progress`); fixture with round 1/2 reported | static+behavioral | ⬜ |
| R7 | slice-dispatch record carries slice id | `tests/test_telemetry.sh::slice_dispatch_record` (fixture `slice-dispatch` line w/ slice id appears in breakdown; orchestrator umbrella prose mentions it) | static+behavioral | ⬜ |
| R8 | spec_ready open record stamped | `tests/test_telemetry.sh::gate_open_record` (orchestrator prose stamps `spec_ready_at`; fixture gate-open line parsed) | static+behavioral | ⬜ |
| R9 | in_progress close + human_latency_s | `tests/test_telemetry.sh::gate_latency` (fixture open 10:00 + close 15:30 → report mean latency = 19800s) | behavioral | ⬜ |
| R10 | autonomous distinguishable / excluded | `tests/test_telemetry.sh::autonomous_excluded` (fixture has 1 autonomous + 1 human gate close → human-latency stats use only the human one) | behavioral | ⬜ |
| R11 | unwritable log never blocks | `tests/test_telemetry.sh::best_effort_prose` (grep orchestrator for best-effort/never-block); report run against read-only/garbage path exits 0 | static+behavioral | ⬜ |
| R12 | absent log auto-handled, not an error | `tests/test_telemetry.sh::absent_log_noop` (run report with a non-existent log → exit 0 + "no telemetry" notice) | behavioral | ⬜ |
| R13 | zero-dep report script exists | `tests/test_telemetry.sh::report_script_exists` (`tools/telemetry-report.py` present; `python3` runs it; no non-stdlib imports grep) | static+behavioral | ⬜ |
| R14 | all six granularities supported | `tests/test_telemetry.sh::granularities` (loop daily weekly monthly quarterly semester annual → each exits 0 + emits a table) | behavioral | ⬜ |
| R15 | no-arg default summary | `tests/test_telemetry.sh::default_summary` (run with no granularity → exit 0, prints all-granularity summary, no traceback) | behavioral | ⬜ |
| R16 | per-period metrics present | `tests/test_telemetry.sh::report_metrics` (output contains total autonomous time, per-phase breakdown, count, mean+median latency for a fixture) | behavioral | ⬜ |
| R17 | empty/absent log → exit 0 + notice | `tests/test_telemetry.sh::empty_log_notice` (empty file → exit 0, "no telemetry yet") | behavioral | ⬜ |
| R18 | malformed line skipped, not aborted | `tests/test_telemetry.sh::malformed_line_skipped` (fixture: good, garbage, good lines → report aggregates the 2 good, exit 0) | behavioral | ⬜ |
| R19 | append-only JSONL, no rewrite | `tests/test_telemetry.sh::jsonl_append_only` (one JSON object per line; orchestrator prose says append-only / never rewrite) | static | ⬜ |
| R20 | reserved cost extension tolerated | `tests/test_telemetry.sh::cost_extension` (fixture line WITH a populated `cost` and one withOUT both parse; report ignores `cost`; orchestrator prose marks it reserved/null today) | static+behavioral | ⬜ |
| R21 | type + schema_version discriminator | `tests/test_telemetry.sh::record_discriminator` (fixture records carry `type` ∈ {phase,gate} and `schema_version`; report routes by `type`) | static+behavioral | ⬜ |
| R22 | end-of-session summary printed on wrap | `tests/test_telemetry.sh::session_summary_prose` (grep `agents/orchestrator.md` for an end-of-session/hand-back summary instruction that prints a session telemetry table) | static | ⬜ |
| R23 | summary is text/markdown table, no image | `tests/test_telemetry.sh::session_summary_text_only` (`session` report output is a markdown table; grep orchestrator prose for "table"/"text-only"/no-image; assert no image/binary directive) | static+behavioral | ⬜ |
| R24 | summary = per-phase durations + round count + gate latency, no tokens/USD | `tests/test_telemetry.sh::session_metrics` (fixture session → `session` view shows per-phase durations, build↔review round count, human-gate latency; assert output contains NO token/USD/cost figure) | behavioral | ⬜ |
| R25 | instruction is portable, no Claude-only dep | `tests/test_telemetry.sh::session_summary_portable` (the instruction lives in `agents/orchestrator.md`; grep that it invokes `python3 tools/telemetry-report.py session` and does NOT depend on a Claude-Code-only feature — no Task tool / `.claude/` / slash command on the path) | static | ⬜ |
| R26 | `session` report view reproduces the summary numbers | `tests/test_telemetry.sh::session_view_reproducible` (fixture with a session-start marker + known phase/gate records → `telemetry-report.py session` exits 0 and emits per-phase durations, round count, mean/observed latency matching hand-computed values) | behavioral | ⬜ |
| R27 | session-start marker scopes the session | `tests/test_telemetry.sh::session_marker_scope` (fixture with records before AND after the latest `session-start` marker → `session` view counts only at/after the marker; orchestrator prose appends the marker at session start; reuses reserved `cost` slot, no token/USD) | static+behavioral | ⬜ |

## Behavioral / end-to-end checks
- **Fixture-driven rollup:** the test writes a deterministic `state/telemetry.jsonl`
  fixture (or a temp log via `--log`) containing several phase records across known
  dates and a gate open/close pair, runs `tools/telemetry-report.py weekly` (and the
  other granularities), and asserts the totals, counts, per-phase breakdown, and
  mean/median human latency match hand-computed values.
- **No-op safety:** run the report against (a) a missing path and (b) an empty file;
  both exit 0 with the "no telemetry yet" notice. Confirm no fixture write is required
  for the loop to proceed (best-effort).
- **Prose contract:** grep `agents/orchestrator.md` for the capture insertion points —
  the "## Telemetry" section, the delegate-boundary phase capture, the
  `spec-ready`/`in-progress` gate stamps, the `slice-dispatch` record, the
  round-increment rule, `date -u`, the best-effort/never-block wording, the
  `session-start` marker (R27), and the portable "### End-of-session summary"
  instruction (R22–R25) invoking `python3 tools/telemetry-report.py session`.
- **Session view (R26, R27):** the test writes a fixture log containing an older
  `session-start` marker + stale records, a newer `session-start` marker, then phase
  records (across phases, with a round-2 builder/reviewer pair) and a gate open/close
  pair after the newer marker; running `tools/telemetry-report.py session` returns only
  the post-marker records, and the per-phase durations, build↔review round count, and
  human-gate latency match the live end-of-session summary's hand-computed values. The
  output contains no token/USD/cost figure (R24).

## Non-functional checks
- Zero new runtime dependencies: `tools/telemetry-report.py` imports python3 stdlib only
  (grep for disallowed third-party imports).
- `./init.sh` stays green and is NOT extended with telemetry capture (best-effort, off
  the critical path).
- New suite wired into `harness.config.yaml` → `verification.test_command`.
- Lint: `<lint_command>` clean (none configured).
- Types: `<typecheck_command>` clean (none configured).
