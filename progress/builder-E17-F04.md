# Builder — E17-F04 "Worker roster: invocable CLIs as versioned data"

Branch `feat/E17-F04-worker-roster`. Feature confirmed `in-progress` in `state/tasks.json`
before any code was written. `./init.sh` green at start and at hand-off.

Source of requirements: the approved four-file spec only. The inbox brief was **not** read
as a requirements source — the spec's Context section corrects a false premise in it.

## What was built, per task

| T | What landed |
|---|---|
| T1 | `WORKER_INVOKE` table in `harness-install.sh`, **after** the closing `"` of `HOST_MARKERS`. Five rows, `<key> <command> [<capability>…]`, carrying only the non-derivable `non-interactive`. |
| T2 | Provenance comment directly above it, headed `# WORKER_INVOKE PROVENANCE` (not a bare `# PROVENANCE`). Records the verified entrypoint per claim; `gemini` recorded explicitly as unverified, no claim, with the reason. |
| T3 | `_cfg_workers_value()` (section-scoped awk, same shape as `_cfg_pr_loop_value`) + `worker_roster_enabled()` — true only on the literal `true`. |
| T4 | `worker_roster_is_symlinked()`, mirroring `escalation_arming_is_symlinked`. |
| T5 | `worker_roster_detect()` — `AGENT_KEYS` order, `command -v … >/dev/null 2>&1` as a **boolean** (stdout discarded, nothing executed), derives `harness-selected` from `SELECTED` and `host-detectable` from a `HOST_MARKERS` row, unions the table's tags, sorts. **No `agent_selected` filter.** |
| T6 | The emitter: `schema: 1`, fixed-literal `generated_by`, the sorted fixed vocabulary, `workers[]` in `AGENT_KEYS` order with `key`/`command`/`capabilities` and **no `path`**. No escaper; the harness-authored-literal invariant is recorded as a comment beside the emitter, naming `tools/change-size.sh`'s `_json_escape` as the obligation any future environment-derived field re-incurs. |
| T7 | `write_worker_roster()` wiring T4→T3→T5→T6, called from `install_one` as §6c. Reclamation is triggered by the gate and only the gate. |
| T8 | `workers.json` added to the unconditional `_ignores` list. |
| T9 | `workers:` block added to `harness.config.yaml` (tail) and to `migrate_config`, byte-identical. |
| T10 | `tests/test_install.sh`: `test_worker_roster_wiring_installed` + `test_workers_block_seeded_migrated_converge`. |
| T11 | `tests/test_worker_roster.sh`, 16 cases. |
| T12 | `VERSION` 0.61.0 → **0.62.0** (MINOR), `CHANGELOG.md` entry, docs in `docs/INSTALL.md` + `docs/CONFIG-LAYERING.md`. |
| T13 | `./init.sh` green; `sh tools/run-tests.sh` → **all 38 suites passed**. |

## Constraints honored

- **No `path` field** anywhere in the entry shape, the emitter, or the plan's deleted
  canonicalize/escape surface. `R5_one_entry_per_present_cli` asserts the entry's field set
  as an **equality** with `{capabilities, command, key}`, so an emitter that helpfully adds
  one fails.
- **No rostered CLI is executed.** `R8_never_executes_a_rostered_cli` uses stubs that record
  their own name and exit 3, and asserts the witness file does not exist — anchored to a run
  proven to have reached detection (roster exists, holds the stubbed keys).
- **DO NOT TOUCH honored**: `HOST_MARKERS` + its provenance block and everything above it
  are byte-unchanged; `AGENT_KEYS` unchanged; `detect_host`/the picker unchanged; `tools/`
  unchanged; `tests/test_install.sh` gained only the two additive assertions the plan lists.
- No R-id renumbered.

## Notes for the Reviewer

- `worker_roster_enabled` is deliberately **config-only** — there is no
  `HARNESS_WORKERS_ROSTER` env twin of `HARNESS_PR_LOOP_ENABLED`. The spec names exactly one
  gate; a per-run override would let one scripted run leave behind a file the target's own
  config says should not exist. Consequence for tests: the suite flips the gate in the
  target's config and re-runs the installer, which is the documented operator flow.
- The suite computes its base `PATH` as the real `PATH` **minus every component holding one
  of the five rostered command names**, then asserts (a) none of the five still resolve and
  (b) the tools the installer needs still do. A hard-coded `/usr/bin:/bin` would have been
  machine-specific; inheriting the raw `PATH` would have made presence a property of the
  developer's laptop.
