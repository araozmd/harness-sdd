# Sub-agent & human-gate telemetry with rollup reports — Tasks

> Atomic, sequential, independent steps. The Builder works these top to bottom,
> one at a time. Each task names the R-id(s) it satisfies. Check off when done.

- [x] **T1** (R19, R20, R21, R2, R3) — Add a new "## Telemetry" section to
  `agents/orchestrator.md` defining: the `<HARNESS_DIR>/telemetry.jsonl` JSONL log
  (gitignored / local-only, overridable via the `telemetry.log` config key), the `phase`
  and `gate` record shapes (with `schema_version`, `type` discriminator, and the
  reserved `cost` extension field, null today), and the `date -u +%FT%TZ` ISO-8601 UTC
  timestamp source. State the single-writer (Orchestrator) and best-effort rules here.
- [x] **T2** (R1, R2, R3, R4, R5, R11, R12) — In `agents/orchestrator.md` "How you
  delegate", add a best-effort "Telemetry" paragraph: capture `start` before spawning a
  sub-agent; on report-back capture `end`, derive `duration_s`, append one `phase`
  record with feature, phase/role, outcome. Phrase write as never-blocking.
- [x] **T3** (R6) — In `agents/orchestrator.md` "Your loop" step 5 + the `in-review`
  routing, define the `round` counter: 1 on first build, +1 on each
  `in-review`→`in-progress` bounce; stamp it on `builder`/`reviewer` phase records.
- [x] **T4** (R8, R9, R10) — In `agents/orchestrator.md` step 4 `spec-ready` routing,
  add the gate-span capture: append a `spec_ready` open record on setting `spec-ready`;
  append an `in_progress` close record with derived `human_latency_s` and the
  `autonomous` flag on moving to `in-progress`.
- [x] **T5** (R7) — In `agents/orchestrator.md` umbrella "dispatch" step, add a
  `slice-dispatch` phase record per dispatched slice, carrying the slice id.
- [x] **T6** (R11, R13) — Add the optional `telemetry:` block (`enabled`,
  `log: telemetry.jsonl`) to `harness.config.yaml` with safe defaults; document
  `enabled: false` as the kill-switch, that absence ⇒ enabled defaults, and that `log:`
  resolves under `HARNESS_DIR` (the value `init.sh` computes).
- [x] **T7** (R12) — Do NOT add the log to the tracked body: rely on best-effort
  create-on-first-write at `<HARNESS_DIR>/telemetry.jsonl`; ensure absence is never an
  error. (Path is gitignored / local-only — see T7a/T7b.)
- [x] **T7a** (R11) — In the harness **source** `.gitignore`, add an explicit ignore for
  the source telemetry log path (`/telemetry.jsonl`) — the source runs from the repo
  root, where `.harness/` is already ignored but a root-level log is not — so the log is
  never committed to the harness source.
- [x] **T7b** (R11) — In `harness-install.sh` (the "project workspace seed-once"
  section), seed a **targeted ignore** for consumers: write/ensure `.harness/.gitignore`
  contains `telemetry.jsonl` (seed-once, never clobber — like `init.project.sh`), so a
  consumer's committed, shared harness body coexists with a local-only telemetry log.
- [x] **T8** (R13, R14, R15, R16, R17, R18, R10) — Create `tools/telemetry-report.py`
  (python3 stdlib only): read JSONL, accept a granularity arg
  (daily/weekly/monthly/quarterly/semester/annual) with `--log` override, default to an
  all-granularity summary, emit per-period markdown tables (total autonomous time,
  per-phase breakdown, counts, mean+median human-gate latency excluding `autonomous`),
  skip malformed lines, exit 0 with a notice on empty/absent log.
- [x] **T9** (all R-ids) — Create `tests/test_telemetry.sh` per `F02-telemetry.tests.md`
  (sample-record fixtures, rollup assertions, best-effort/empty no-op, schema/format,
  prose greps on `agents/orchestrator.md`).
- [x] **T10** — Wire `&& sh tests/test_telemetry.sh` into
  `harness.config.yaml` → `verification.test_command`.
- [x] **T11** — Bump `VERSION` (MINOR / ✨, new backward-compatible capability) and add
  a `CHANGELOG.md` entry (installed-body change per CLAUDE.md versioning policy).
- [x] **T13** (R27) — In `agents/orchestrator.md` (loop step 1 / "## Telemetry"), add
  the **session-start marker**: at the start of a session append one
  `{"type":"session-start","started_at":<date -u>}` record (best-effort), and document
  that "session" scope = records at or after the most recent `session-start` marker.
- [x] **T14** (R22, R23, R24, R25) — In `agents/orchestrator.md`, add a portable
  "### End-of-session summary" subsection under "## Telemetry": when the Orchestrator
  wraps/hands back, print a **text/markdown table** for the session — per-phase
  durations, build↔review round count, human-gate latency — duration+latency+counts
  only (no tokens/USD), no images. Phrase it portably (plain prose +
  `python3 tools/telemetry-report.py session`), with NO Claude-Code-specific dependency.
- [x] **T14a** (R25) — Add a **one-line pointer** to `AGENTS.md`: note that the
  Orchestrator prints an end-of-session telemetry summary, with the full instruction in
  `agents/orchestrator.md` "## Telemetry". One line only — do NOT duplicate the
  instruction; the authoritative copy stays in `orchestrator.md`. (Gate decision
  2026-06-06: portability surface = orchestrator.md + AGENTS.md pointer.)
- [x] **T15** (R26, R27) — Extend `tools/telemetry-report.py` with a `session` mode:
  scope to records at/after the latest `session-start` marker; emit per-phase
  durations, round count, and human-gate latency matching the Orchestrator's
  end-of-session summary; ignore `cost`; exit 0 with the "no telemetry yet" notice when
  empty/absent.
- [x] **T16** (R22–R27) — Extend `tests/test_telemetry.sh` per the new
  `F02-telemetry.tests.md` rows: assert the portable summary instruction is present in
  `agents/orchestrator.md` (and not gated on a Claude-only feature), fixture-drive the
  `session` report view (session-start marker scoping, per-phase durations, round count,
  latency), and assert no tokens/USD in the session output.
- [x] **T16a** (R11, R25) — Extend `tests/test_telemetry.sh` with the storage/portability
  rows: (a) assert the source `.gitignore` ignores the telemetry log path
  (`/telemetry.jsonl`); (b) assert `harness-install.sh` seeds `telemetry.jsonl` into a
  `.harness/.gitignore` (grep the installer for the seed); (c) assert `AGENTS.md` contains
  the one-line end-of-session-summary pointer to `agents/orchestrator.md`.
- [x] **T12** — Run `./init.sh` + the full test command; ensure green before hand-off.
