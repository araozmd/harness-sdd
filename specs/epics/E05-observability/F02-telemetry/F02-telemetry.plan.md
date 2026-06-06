# Sub-agent & human-gate telemetry with rollup reports — Technical Plan

> Translates the .spec.md intent into design. Every decision cites the R-id(s) it
> serves. Start high-level; don't over-specify internals that might be wrong.

## Stack & dependencies
- Language: prose (agent role-file edits) + a single python3-stdlib report script.
- New dependencies: **none**. Capture uses `date -u` (POSIX) for timestamps; the report
  uses python3 stdlib (`json`, `datetime`, `statistics`, `argparse`, `sys`). Matches the
  `init.sh` zero-dependency ethos.

## Telemetry log format  (serves: R19, R20, R21, R2, R3)

**JSONL** — one JSON object per line, append-only, never rewritten/reordered (R19).
Two record `type`s share one file, discriminated by a `type` field plus `schema_version`
(R21). The reader tolerates unknown fields and absent optional fields (forward-compat).

### Phase record  (serves: R1–R7, R20, R21)
```json
{
  "schema_version": 1,
  "type": "phase",
  "feature": "E05-F02",
  "phase": "builder",
  "round": 2,
  "start": "2026-06-06T14:03:21Z",
  "end": "2026-06-06T14:41:09Z",
  "duration_s": 2268,
  "outcome": "done",
  "slice": null,
  "cost": null
}
```
- `phase` ∈ {`architect`,`builder`,`reviewer`,`scout`,`inception`,`slice-dispatch`} (R5).
- `round` present on `builder`/`reviewer` (R6); may be `1`/omitted for non-loop phases.
- `slice` carries the slice id for `slice-dispatch` phases, else `null` (R7).
- `outcome` ∈ {`done`,`reject`,`fail`} extensible (spec Definitions).
- **`cost`** — the **reserved extension slot** for future token/USD accounting (R20).
  Always `null` today; the report ignores it; a future SDK runtime populates it with no
  format migration. Shape (non-binding hint): `{"tokens_in":N,"tokens_out":N,"usd":F}`.

### Gate record  (serves: R8, R9, R10, R21)
A gate span is captured as **two lines** (open then close) keyed by `feature`, so a
crashed/cancelled session still leaves the open stamp:
```json
{"schema_version":1,"type":"gate","feature":"E05-F02","event":"spec_ready","spec_ready_at":"2026-06-06T10:00:00Z","autonomous":false}
{"schema_version":1,"type":"gate","feature":"E05-F02","event":"in_progress","in_progress_at":"2026-06-06T15:30:00Z","human_latency_s":19800,"autonomous":false}
```
- `event` = `spec_ready` (open, R8) or `in_progress` (close, R9).
- `human_latency_s` on the close line = non-negative seconds between the matching open
  and close for that feature (R9). The report can also re-derive it by pairing.
- `autonomous` (R10) lets the report exclude autonomous transitions from human-latency
  stats (they are not human review time).

### Session marker record  (serves: R22, R26, R27)
A third lightweight record `type` delimits sessions. The Orchestrator appends one when
it begins a working session; the session summary and the report's `session` view both
scope to records at or after the **most recent** marker:
```json
{"schema_version":1,"type":"session-start","started_at":"2026-06-06T09:00:00Z"}
```
- `type:"session-start"` is the discriminator (R21-compatible); the reader tolerates it
  and the existing phase/gate readers ignore it.
- Scope rule (R27): "session" = all `phase`/`gate` records whose `start` / gate stamp is
  at or after the latest `session-start.started_at`. No external session id, no
  wall-clock heuristic — deterministic from the log alone.
- Cost stays out (R27 → reuses the reserved `cost` slot, R20): the session summary shows
  duration + latency + counts only.

## Storage decision  (serves: R12, R13, R8, R9)

**`state/telemetry.jsonl`, committed/versioned** alongside `state/tasks.json`.

Resolves brief open-question #1. Rationale:
- `state/` is already the harness's durable machine-state home (`state/tasks.json`); the
  report needs **cross-session** history, which a committed file gives for free.
- Append-only, one line per phase/gate → bounded, low-noise churn (not per-keystroke).
- The report reads exactly this path; keeping it versioned means the report works on a
  fresh clone without a separate data-sync step.
- **Trade-off / human confirm:** committed = repo churn on every run. If the human
  prefers no churn, the alternative is gitignored local-only (`state/telemetry.jsonl` in
  `.gitignore`) — same path, the writer/reader are identical, only the VCS treatment
  changes. Flagged for the gate. (Do NOT add it to the installer's tracked body either
  way — it is runtime state, like `state/tasks.json`, seeded empty.)

## Single-writer model  (serves: R1, R8, R9, R11)

**The Orchestrator is the sole writer** (resolves brief open-question #2). It already
owns every delegation boundary (loop step "How you delegate") and every status
transition (loop step 4 routing table + step 5 record). Sub-agents do NOT self-stamp —
fewer places to get the format wrong, and one writer means no interleaving/locking
concern. The Orchestrator opens a phase span (capture `date -u`) immediately before it
spawns a sub-agent and closes it (capture `date -u`, compute duration, append) when the
agent reports back — co-located with the existing "append one line to history.md" step.

## Capture wiring — exact prompt/loop edits  (serves: R1–R12)

These are **prose edits to role files** (the installed body), not code. Each edit must
say capture is best-effort and non-blocking (R11, R12).

| File | Edit | R-id |
|---|---|---|
| `agents/orchestrator.md` — "Your loop" step 4 routing table, `spec-ready` row | Add: when the Orchestrator *sets* a feature to `spec-ready`, append a `gate`/`spec_ready_at` open record. When it moves `spec-ready`→`in-progress`, append a `gate`/`in_progress_at` close record with derived `human_latency_s`. Best-effort. | R8, R9, R10 |
| `agents/orchestrator.md` — "How you delegate" section | Add a "Telemetry (best-effort)" paragraph: before spawning any sub-agent, capture `start=$(date -u +%FT%TZ)`; when it reports back, capture `end`, derive `duration_s`, and append one `phase` record (feature, phase/role, round, outcome). Never block the delegation on a telemetry write failure. | R1–R5, R11, R12 |
| `agents/orchestrator.md` — "Your loop" step 5 (Record) | Note that the telemetry append is a sibling of the `progress/history.md` append, and that for build↔review cycles the `round` increments each `in-review`→`in-progress` bounce. | R6 |
| `agents/orchestrator.md` — Umbrella "dispatch" step | Add: each dispatched slice gets a `slice-dispatch` phase record carrying the slice id. | R7 |
| `agents/orchestrator.md` — a new short "## Telemetry" section | Define the JSONL record shapes (link the schema), the `state/telemetry.jsonl` path, the `date -u` source, the best-effort rule, and the `tools/telemetry-report.py` reader. Single source of the contract the loop edits reference. | R2, R3, R19, R20, R21 |
| `agents/orchestrator.md` — "Your loop" step 1 (Verify) **or** the new "## Telemetry" section | Add: at the **start** of a session, append one `session-start` marker record (`date -u` stamp). Best-effort. This delimits the session scope used by the end-of-session summary and the report's `session` view. | R27 |
| `agents/orchestrator.md` — a new "### End-of-session summary" subsection under "## Telemetry" (portable surface) | Add: when the Orchestrator **wraps / hands back at the end of a session**, it prints a **text/markdown table** summarizing this session — per-phase durations, build↔review round count, human-gate latency observed — derived from telemetry records since the most recent `session-start` marker. **Duration + latency + counts only; no tokens/USD (reuses the reserved `cost` slot, R20).** Phrase it portably (plain prose + `python3 tools/telemetry-report.py session`), with **no** dependency on any Claude-Code-specific feature, so every AGENTS.md-compatible CLI surfaces the same summary. No images. | R22, R23, R24, R25, R26 |

No edits are required to `agents/architect.md`, `agents/builder.md`, `agents/reviewer.md`,
`agents/scout.md`, `agents/inception.md` — sub-agents do not self-stamp (single-writer).
A one-line cross-reference may be added to each only if the Builder finds it necessary;
prefer leaving them untouched.

## Report script  (serves: R13–R18)

**`tools/telemetry-report.py`** — python3 stdlib only (R13). New `tools/` directory.

| Aspect | Decision | R-id |
|---|---|---|
| Invocation | `python3 tools/telemetry-report.py [granularity] [--log PATH]`; default log `state/telemetry.jsonl`. | R13, R14 |
| Granularity arg | One of `daily weekly monthly quarterly semester annual`; `semester` = half-year (H1 Jan–Jun, H2 Jul–Dec); `quarterly` = calendar quarters. | R14 |
| No arg | Print an all-granularity summary (each granularity's latest period or a documented default), exit 0. | R15 |
| Per-period rows | Total autonomous agent time (sum `duration_s` over phase records), per-phase breakdown, phase count, mean + median `human_latency_s` (over gate close records, excluding `autonomous:true`). | R16, R10 |
| Empty/absent log | Print "no telemetry yet", exit 0. | R17 |
| Malformed line | `try/except` per line; skip + continue; never abort. | R18 |
| Period bucketing | Group by the phase record's `start` date (UTC) / gate close date into the requested calendar bucket. | R14, R16 |
| Output | Markdown tables to stdout (text-only). | R13, R16 |
| `session` view | Accept `session` as a granularity/mode arg: scope to records at or after the most recent `session-start` marker (R27) and emit per-phase durations, build↔review round count, and mean/observed human-gate latency — **the same numbers the Orchestrator prints at end-of-session** (R26). Duration + latency + counts only; ignore `cost`. | R26, R22, R24, R27 |

### Portability note  (serves: R25)
The end-of-session summary instruction lives in `agents/orchestrator.md` — a **portable
role prompt** read by every AGENTS.md-compatible CLI — and is phrased in plain prose +
`python3 tools/telemetry-report.py session`, with **no** Claude-Code-specific feature
(no Task tool, no `.claude/` glue, no slash command) on the critical path. `AGENTS.md`
already names `agents/*.md` as the canonical portable role prompts, so no `AGENTS.md`
edit is required; the instruction is portable by virtue of living in `orchestrator.md`.

## Config  (serves: R11, R13)

Add an **optional** `telemetry:` block to `harness.config.yaml` (read by the
Orchestrator; safe defaults so existing targets are unaffected):
```yaml
telemetry:
  enabled: true                 # false ⇒ Orchestrator skips capture entirely
  log: state/telemetry.jsonl    # writer + report default path
  # cost accounting is OUT of scope; the `cost` record field is reserved for a future
  # instrumented SDK runtime and is null today.
```
`enabled: false` is the documented kill-switch; absence of the block ⇒ defaults above
(enabled). The report script accepts `--log` so it never hard-codes the path.

## Files to change / create  (serves: R#)
| File | Change | R-id |
|---|---|---|
| `agents/orchestrator.md` | modify: add "## Telemetry" section + the capture edits in the loop/delegate/umbrella sections (table above), the `session-start` marker, and the portable "### End-of-session summary" subsection | R1–R12, R19–R27 |
| `tools/telemetry-report.py` | create: zero-dep JSONL rollup reporter, incl. the `session` view (R26) | R13–R18, R26 |
| `harness.config.yaml` | modify: add optional `telemetry:` block | R11, R13 |
| `state/telemetry.jsonl` | create (seed empty, or rely on best-effort create-on-first-write) | R12 |
| `tests/test_telemetry.sh` | create: full R-id traceability suite | all |
| `harness.config.yaml` `verification.test_command` | modify: append `&& sh tests/test_telemetry.sh` | all (CI wiring) |
| `VERSION` | modify: MINOR bump (new backward-compatible capability ✨) | — |
| `CHANGELOG.md` | modify: record the bump | — |

## DO NOT TOUCH
- The existing R1–R21 requirements and their resolved decisions, record shapes
  (`phase`/`gate`), the `state/telemetry.jsonl` path, the single-writer model, and the
  granularity arg set (`daily…annual`). The session work (R22–R27) is **additive**:
  add a `session-start` record type and a `session` report mode; do NOT renumber,
  rewrite, or alter any existing R-id, record field, or report granularity.
- `AGENTS.md` — no edit required for R25. The portable surface for the summary
  instruction is `agents/orchestrator.md` (which `AGENTS.md` already names canonical);
  do NOT duplicate the instruction into `AGENTS.md`. Only touch `AGENTS.md` if the
  Builder finds the portability claim genuinely needs a one-line pointer there.
- The reserved `cost` slot (R20) — the session summary reuses it as-is (null today);
  do NOT add token/USD computation for the session view (R24, R27 keep cost OUT).
- `state/tasks.json` — TaskStore routing state; telemetry is a *separate* file.
- `store/tasks.schema.json` and the `init.sh` schema validator — telemetry has its own
  format; do NOT route it through the TaskStore schema.
- `init.sh` — telemetry capture must NOT be added to the init gate (best-effort, never a
  blocker; init runs before every step and must stay fast — R11).
- Sub-agent role files (`architect/builder/reviewer/scout/inception.md`) — single-writer
  model keeps them out of the capture path; prefer leaving them untouched.
- The existing `progress/history.md` append step — telemetry is additive beside it, not
  a replacement.
- The umbrella manifest / cross-repo dispatch contract — only add the `slice-dispatch`
  *record*, do not change dispatch behavior (R7).

## Approach notes
- **Best-effort everywhere (R11, R12):** every write is "append if you can, else carry
  on." The prose must phrase capture as a side-effect that is never on the critical path
  of a gate/build. No locking is needed — single writer, append-only.
- **Round derivation (R6):** the Orchestrator already routes `in-review`→`in-progress`
  on a Reviewer reject; that bounce is the round increment. Phrase it so round=1 on the
  first build.
- **Latency excludes autonomous (R10):** an `autonomous:true` feature's gate close is
  not human review time; the report records the pair but excludes it from human-latency
  stats and reports it separately/labeled.
- **Tasks for the Builder include the VERSION bump + CHANGELOG entry** (installed-body
  change per CLAUDE.md versioning policy: MINOR, ✨) and wiring the new test into
  `verification.test_command`.
