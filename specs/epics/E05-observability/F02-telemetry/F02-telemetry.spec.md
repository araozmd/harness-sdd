---
id: E05-F02
title: Sub-agent & human-gate telemetry with rollup reports
epic: E05-observability
status: spec-ready          # pending → spec-ready → in-progress → in-review → done
sdd: true
autonomous: false           # ships installed-body prose + a tool script + tests; human reviews the prompt edits
depends_on: []
owner: araozmd
---

# Sub-agent & human-gate telemetry with rollup reports — Functional Spec

## Context
The harness drives long-running, multi-agent work but is **blind to its own timing**.
It records narrative history (`progress/history.md`) but no structured durations. The
maintainer wants Anthropic-article-style observability: **how long each sub-agent runs
autonomously**, plus a dimension the article does not measure — **human spec-approval
latency**, inferred from the gap between a feature becoming `spec-ready` and a human
moving it to `in-progress`. This feature adds a zero-dependency structured telemetry
log, the prompt/loop instructions that append records automatically at phase boundaries
and the two gate transitions, and a report script that rolls the log up into
daily/weekly/monthly/quarterly/semester/annual tables. Token/USD cost is explicitly out
of scope (a markdown-prompt agent cannot observe its own token usage); a reserved
extension field lets a future SDK runtime populate it without reworking the format.

## Business rules
- The single writer of telemetry records is the **Orchestrator** (it owns every
  delegation boundary and every gate transition). Sub-agents do not self-stamp.
- Telemetry capture is **best-effort**: a failed or impossible telemetry write must
  never block, delay, or alter a delegation, a gate transition, or a build. Same ethos
  as the `/pr-loop` cache.
- Timestamps are recorded in **ISO-8601 UTC** read from the system clock (`date -u`),
  so records are timezone-stable and comparable across sessions.
- The log is **append-only JSONL**; one JSON object per line; the format is forward-
  compatible (unknown fields ignored by the reader; missing optional fields tolerated).
- Token/USD accounting is **out**, but the record schema reserves an extension slot so
  it can be added later without a format migration.

## Definitions
- **Phase span** — one sub-agent invocation (Architect, Builder, Reviewer, Scout,
  Inception, or an umbrella slice dispatch), from the moment the Orchestrator delegates
  to the moment that agent reports back.
- **Gate span** — the human spec-approval interval: from a feature being stamped
  `spec-ready` to the same feature being moved to `in-progress`.
- **Outcome** — the terminal result of a phase: one of `done`, `reject`, `fail`
  (extensible). For the build↔review loop, a rejected Builder/Reviewer round is `reject`.
- **Round** — the build↔review iteration counter for a feature, starting at 1 and
  incrementing each time work cycles back from `in-review` to `in-progress`.
- **Session** — one Orchestrator working session. Its telemetry scope is the set of
  telemetry records produced **since the session started**, delimited by an explicit
  `session` marker record the Orchestrator appends when it begins (see R27). The
  session summary (R22–R26) aggregates exactly the records at or after the most recent
  `session-start` marker.

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

### Phase-span capture
- **R1** — When the Orchestrator finishes a sub-agent phase (the agent reports back),
  the system shall append exactly one telemetry record for that phase to the telemetry
  log.
- **R2** — The system shall record, in every phase record, at least these fields:
  feature id, phase/role, start timestamp, end timestamp, derived duration (seconds),
  outcome, and round number.
- **R3** — The system shall record `start` and `end` timestamps as ISO-8601 UTC strings
  (e.g. `2026-06-06T14:03:21Z`) read from the system clock.
- **R4** — The system shall set a phase record's `duration_s` to the non-negative
  difference in seconds between its `end` and `start` timestamps.
- **R5** — The system shall record `phase` as one of `architect`, `builder`,
  `reviewer`, `scout`, `inception`, or `slice-dispatch` for the corresponding sub-agent
  invocation.
- **R6** — While the build↔review loop iterates for a feature, the system shall record a
  monotonically increasing `round` (starting at 1) on each `builder` and `reviewer`
  phase record, incrementing the round each time the feature cycles from `in-review`
  back to `in-progress`.
- **R7** — Where a feature is an umbrella feature with `slices[]`, the system shall
  record a `slice-dispatch` phase span per dispatched slice, carrying the slice id in
  the record.

### Human-gate latency capture
- **R8** — When the Orchestrator sets a feature's status to `spec-ready`, the system
  shall append a telemetry record marking the open of that feature's gate span with an
  ISO-8601 UTC `spec_ready_at` timestamp.
- **R9** — When the Orchestrator moves a feature from `spec-ready` to `in-progress`,
  the system shall append a telemetry record marking the close of that feature's gate
  span with an ISO-8601 UTC `in_progress_at` timestamp and a derived
  `human_latency_s` equal to the non-negative seconds between gate open and close.
- **R10** — If a feature is marked `autonomous: true` (bypassing the human gate), then
  the system shall still record the gate open/close pair, and the report shall be able
  to distinguish autonomous transitions from human-reviewed ones.

### Best-effort, non-blocking
- **R11** — If the telemetry log cannot be written (unwritable path, missing parent
  directory, full disk, or any I/O error), then the system shall continue the
  delegation, gate transition, or build unaffected and shall not surface a failure that
  blocks the loop.
- **R12** — If the telemetry log is absent when a write is attempted, then the system
  shall create it (best-effort) and proceed; absence shall never be treated as an error
  that halts the loop.

### Report script
- **R13** — The system shall provide a zero-dependency report script
  (`tools/telemetry-report.py`, python3 stdlib only) that reads the JSONL log and emits
  text/markdown rollup tables.
- **R14** — The report script shall accept a granularity argument and support each of:
  `daily`, `weekly`, `monthly`, `quarterly`, `semester`, `annual`.
- **R15** — When run without a granularity argument, the report script shall print a
  default summary covering all granularities (or a documented default), not error out.
- **R16** — For each period in the requested granularity, the report shall include:
  total autonomous agent time, a per-phase time breakdown, the count of phases, and the
  mean and median human-gate latency.
- **R17** — If the telemetry log is absent or empty, then the report script shall exit
  zero and print an explicit "no telemetry yet" notice rather than crashing.
- **R18** — If a line in the log is malformed (not parseable JSON or missing required
  fields), then the report script shall skip that line, continue aggregating the rest,
  and not abort.

### Format & extension point
- **R19** — The system shall record each telemetry entry as a single-line JSON object
  (JSONL); appending a record shall never rewrite or reorder existing lines.
- **R20** — The system shall reserve an extension field for future token/USD accounting
  (e.g. a `cost` object, omitted/null today) that the reader tolerates as absent and
  that can be populated later by an instrumented runtime without a format migration.
- **R21** — Each telemetry record shall carry a `type` discriminator (`phase` or
  `gate`) and a `schema_version` so the reader can evolve the format compatibly.

### End-of-session summary (portable)
- **R22** — When the Orchestrator wraps up or hands back at the end of a working
  session, the system shall print a telemetry summary for that session, derived from
  the telemetry log records produced during the session (see Session definition / R27).
- **R23** — The session summary shall be rendered as a text/markdown table only and
  shall never emit an image or chart (honors the AGENTS.md text-only rule).
- **R24** — The session summary shall report, for that session: per-phase durations
  (Architect / Builder / Reviewer / Scout / Inception / slice-dispatch), the build↔
  review round count, and any human-gate latency observed — and shall report duration,
  latency, and counts only (no token/USD figures).
- **R25** — The system shall place the end-of-session summary instruction in the
  **portable role-prompt surface** (`agents/orchestrator.md`) **and** add a one-line
  pointer to it in `AGENTS.md` (the portable contract every AGENTS.md-compatible CLI
  reads), and shall express it without depending on any Claude-Code-specific feature, so
  that Claude Code, Gemini, OpenCode, Codex, and Antigravity all surface the same
  summary. *(Gate decision 2026-06-06: orchestrator.md + AGENTS.md pointer.)*
- **R26** — The report script shall provide a `session` view (a granularity/mode
  argument) that reproduces the same per-phase durations, round count, and human-gate
  latency as the Orchestrator's end-of-session summary, so the numbers are reproducible
  after the fact from the log alone.
- **R27** — When the Orchestrator begins a working session, the system shall append a
  `session-start` marker record (carrying an ISO-8601 UTC timestamp) to the telemetry
  log; the session summary (R22, R26) shall scope to records at or after the most
  recent `session-start` marker. The session view shall reuse the same reserved `cost`
  extension point (R20) and shall not surface token/USD figures.

## Out of scope
- **Token / USD cost accounting (hard out).** A markdown-prompt agent cannot observe
  its own token usage. Only the reserved extension field (R20) is delivered — no
  population logic.
- Dashboards / charts / images. Text and markdown tables only (matches AGENTS.md
  "text-only, never generate images").
- Backfilling telemetry for historical runs that predate this feature.
- Real-time streaming or alerting on telemetry.

## Gate decisions — human-approved 2026-06-06
The human resolved the two load-bearing open questions at the spec-ready gate; these
**override** the Architect's tentative picks below:
- **Storage (overrides Q1):** the telemetry log is **gitignored runtime data under the
  harness dir** — `<HARNESS_DIR>/telemetry.jsonl` (resolved by `init.sh`: the repo root
  in the harness source, `.harness/` in an installed consumer), path overridable via the
  `telemetry:` config block. It is **local-only, never committed**. The installer seeds a
  targeted ignore (a `.harness/.gitignore` holding `telemetry.jsonl`) so a consumer's
  shared, committed harness body coexists with a local-only log. Telemetry is operational
  data, not source. Accepted trade-off: reports are **per-clone**, not team-aggregated;
  an opt-in export is deferred (out of scope).
- **Portability surface (R25):** orchestrator.md **plus** a one-line `AGENTS.md` pointer.

## Open questions (resolved by the Architect — confirm at the gate)
1. **Storage location & VCS** — ~~`state/telemetry.jsonl`, committed~~ **SUPERSEDED by the
   gate decision above:** gitignored `<HARNESS_DIR>/telemetry.jsonl`, local-only.
2. **Single writer** — RESOLVED: the Orchestrator is the sole writer (phase spans + gate
   stamps). Sub-agents do not self-stamp (fewer places to get it wrong). See plan.
3. **Wall-clock source** — RESOLVED: system clock via `date -u` at span open/close,
   stored ISO-8601 UTC. Confirm there is no harness-provided monotonic time to prefer.
4. **Report output shape** — RESOLVED: a granularity argument
   (`telemetry-report.py weekly`) defaulting to an all-granularity summary (R14, R15).
5. **Session boundary** (new, R27) — RESOLVED: scope by an explicit `session-start`
   marker record the Orchestrator appends when it begins a session; the summary
   aggregates records at or after the **most recent** marker. Rationale: deterministic
   and self-contained in the log (no wall-clock "since N minutes" heuristic, no
   external session id needed); survives the single-writer model; the report's
   `session` view (R26) reads the same marker so the after-the-fact numbers match the
   live summary exactly. Alternative considered — "records since the last summary" —
   rejected because printing a summary is read-only and should not mutate scope.
   *Human may prefer a different boundary (e.g. per-day) — confirm at the gate.*
