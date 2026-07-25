# Builder progress — E15-F01 (Board write lock: flock-guarded read-modify-write on tasks.json)

Date: 2026-07-24
Status entering: `in-progress` (human-approved, confirmed in state/tasks.json).
Backend: `execution.builder.backend = in-session` (Loop A — I implemented in-session).

## What was built (all 11 tasks ticked)

- **T1–T4 — `tools/tasks-lock.py` (new, installed body, executable).** Portable advisory
  lock over the board write path. One process owns the whole critical section:
  bounded `fcntl.flock` acquire on the sibling lockfile `state/tasks.json.lock`
  (resolved with `cwd = HARNESS_DIR`) → **re-read `state/tasks.json` from disk inside
  the lock** → apply the single mutation → validate (`json` parse + `store/tasks.schema.json`
  schema check, via `jsonschema` when present, else a stdlib structural fallback) →
  atomic write (temp + `os.replace`) → release. Bounded timeout constant
  `DEFAULT_TIMEOUT_SECONDS = 10.0`; on timeout it exits non-zero with an error naming the
  lockfile + the timeout (never blocks, never writes unlocked). Two CLIs: `set-status <id>
  <status>` (the real `set_status` mutation, feature or epic id) and `apply --mutator <path>`
  (external mutator hook used by the tests to drive concurrent + invalid mutations).
- **T5 — `store/local.md`.** Amended the `set_status` contract to mandate the lock protocol
  (acquire → re-read → mutate → validate → write → release), pointing it at
  `.harness/tools/tasks-lock.py`; documented no-op-for-serial-callers, single-host scope,
  no new status / no schema change, and that `on_write_command` fires **after** release.
  Added an after-release note to the "Post-write sync" section.
- **T6 — `harness-install.sh`.** `chmod +x`'d the new helper beside `sync-board.mjs` /
  `telemetry-report.py`; the existing `copy tools` already ships it. Added
  `state/tasks.json.lock` to the seeded `.harness/.gitignore` `_ignores` list (append-only,
  idempotent via the existing `grep -qF` loop).
- **T7 — `tests/test_install.sh`.** Added the `# R10` assertion (mirrors the sync-board.mjs
  pattern): a fresh install ships `.harness/tools/tasks-lock.py` as an executable.
- **T8 — no schema/status change.** `git diff` confirms `store/tasks.schema.json` and the
  status enums are untouched; the serial write is byte-equivalent to a plain read-modify-write
  (proven by `test_serial_caller_result_unchanged`).
- **T9 — VERSION 0.30.0 → 0.31.0 (MINOR)** + matching `CHANGELOG.md` entry.
- **T10 — `tests/test_board_lock.sh` (new)** covering R1–R9 + R11; appended
  `&& sh tests/test_board_lock.sh` to `verification.test_command` in `harness.config.yaml`.
- **T11 — self-check green** (see below).

## Self-check

- `./init.sh` → exit 0 (`environment ready`).
- Full `verification.test_command` (16 suites incl. the new `test_board_lock.sh`) → **exit 0**.
  `test_doc_critic.sh` and `test_ownership.sh` auto-picked up the new `0.31.0` VERSION via
  their runtime-read (non-frozen) assertions — expected, confirms the anti-pattern is avoided.

## Notes / deviations

- **No deviations from the spec.** Built exactly what the four-file spec asked.
- The `state/tasks.json` diff (E15 epic seed + E15-F01 → `in-progress`) is pre-existing
  Orchestrator/Driller state, NOT a Builder change — the lock behaviour is exercised only
  against temp-dir fixtures, never the live board (per DO NOT TOUCH + the permanent-suite
  anti-pattern).
- Status transition to `in-review` is deliberately **not** done here — the Orchestrator owns it.
- No PR opened (Orchestrator/Reviewer's job).

## Files created / changed

- created: `tools/tasks-lock.py`
- created: `tests/test_board_lock.sh`
- changed: `store/local.md`, `harness-install.sh`, `tests/test_install.sh`,
  `harness.config.yaml`, `VERSION`, `CHANGELOG.md`
- ticked: `specs/epics/E15-parallel-fix-lane/F01-board-write-lock/E15-F01.tasks.md`,
  `…/E15-F01.tests.md`
