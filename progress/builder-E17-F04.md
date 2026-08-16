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

## Mutation campaign — 27 mutations, 27 killed

Run in a detached `git worktree` at the committed tip, under
`scratchpad/E17-F04-builder/` (namespaced per `agents/builder.md`). Free disk on the repo
volume: **424 GB before, 424 GB after** — no mass-failure run, no ENOSPC.

Every mutation broke exactly one production rule a new assertion claims to protect. The
runner asserts its anchor matches **exactly once** before applying, restores the file from
git after each, and every mutation applied cleanly (no PARSE-FAIL, no NOT-APPLIED).

| # | what was broken | killed by |
|---|---|---|
| M1 | `write_worker_roster` never called | R1 |
| M2 | gate accepts any non-empty value | R2 truth table (`explicit_false`) |
| M3 | the gate also drops a second artifact | R2 inventory delta |
| M4 | reclamation does not remove | R3 |
| M5 | reclamation is silent | R3 |
| M6 | `"schema": "1"` (string) | R4 |
| M7 | entries emitted alphabetically, not in `AGENT_KEYS` order | R5 |
| M8 | **the `path` field reintroduced** | R5 field-set equality |
| M9 | `command` echoes the key | R5 (`agy`) |
| M10 | **the `agent_selected` filter copied from `write_escalation_arming`** | R5 unselected |
| M11 | presence never checked | R6 |
| M12 | a fourth tag in `capability_vocabulary` | R4/R7 closed |
| M13 | a tag outside the vocabulary on every entry | R4/R7 closed |
| M14 | `harness-selected` true for every rostered key | R5 unselected / R7 evidence |
| M15 | `host-detectable` claimed unconditionally | R7 evidence |
| M16 | an **unverified** `non-interactive` claim shipped for `gemini` | R7 evidence |
| M17 | capabilities unsorted | R7/R9 |
| M18 | `harness-selected` derived from a **write outcome** | R7 refused-write |
| M19 | **a rostered CLI executed** (`--version`) | R8 witness |
| M20 | per-run content in the file | R9 byte-identity |
| M21 | existing roster kept instead of overwritten | R10 |
| M22 | `workers.json` dropped from `_ignores` | R11 + `test_install.sh` |
| M23 | symlink guard removed | R12 |
| M24 | gate checked **before** the symlink guard | R12 gate-off control |
| M25 | trailing comma after the last entry | `roster_is_valid_json` |
| M26 | reclaim-on-empty (the `write_escalation_arming` behavior) | `roster_is_valid_json` empty half |
| M27 | migrated `workers:` block drifts from the seeded one | `test_install.sh` convergence |

**One mutation appeared to survive and did not.** M18's first form *added* a
`write_worker_roster` call ahead of the unstamped-ledger teardown without removing the §6c
one — so the original call re-ran after the ledger was gone and overwrote the mutated
output. That is a defective mutation, not a surviving one: the diagnosis was that the
mutation had not applied as intended, and confirming it required checking that the mechanism
the mutation described was the mechanism that actually ran. With the setup corrected (move
the call, remove the original), M18 is **KILLED** by
`R7_selected_tag_survives_a_refused_write` with the message that names the rule.

**Re-attribution pass.** Four mutations (M11, M21, M22, M25) were first killed by an
*earlier* case, because `fail()` aborts the suite. A kill by an unrelated assertion does not
prove the named case protects the rule, so each was re-run with every other case's
invocation neutralised. All four are killed by the case that **names** the rule, with the
right message — and the five isolated suites all **pass** unmutated, so the isolation itself
is not what made them fail.

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

---

## Round 2 — the two blocking review findings

Feature re-confirmed `in-progress` in `state/tasks.json` before any edit. Branch
`feat/E17-F04-worker-roster`, worked in the primary checkout (no worktree for the fix).
**`harness-install.sh` is unchanged** — the Reviewer was right that both findings are test
gaps, and I re-derived that myself rather than taking it on report (below).

### Both premises verified independently, before implementing

Ran the Reviewer's exact two mutations against the **round-1 tip** (`7bc7e42`) in a detached
worktree: `tests/test_worker_roster.sh` **exit 0** and `tests/test_install.sh` **exit 0** for
each. So both mutations really did survive, and each really is a defect and not a no-op:

- **B1** — `generated_by` ← `"$0"`: the same script reached by two invocation paths emitted
  `"/abs/…/harness-install.sh"` vs `"./harness-install.sh"` from **identical roster inputs**.
  That is R9 byte-identity broken by something that is not one of R9's three inputs, and it
  also falsifies the emitter's own stated reason for shipping no JSON escaper ("every value
  is a harness-authored literal"). Premise holds, mechanism as stated.
- **B2** — `: > "$H/workers.stamp"` as the first line of `write_worker_roster`: a **gate-off**
  install measurably landed `.harness/workers.stamp`. The stated mechanism holds exactly:
  `comm`-ing the gate-off inventory against the gate-**on** one can only see what the *gate*
  adds, so an artifact written on both paths cancels out of the delta. Nothing I disagreed
  with; the Reviewer had already ruled out the direct comparison for the right reason (it
  would mean diffing against `main`, banned here).

### What changed (tests + docs only)

| finding | change |
|---|---|
| B1 | `rq.py` gained a `generated_by` query; `test_roster_is_valid_json` asserts the **value** equals the fixed literal, with a message naming the no-escaper decision it underwrites. |
| B1 | `test_R9_rerun_is_byte_identical`'s two identical-input installs now reach the same file by **different invocation paths** — `sh <abs>/harness-install.sh` vs `cd <src> && sh ./harness-install.sh`. Pinned in two places on purpose: either case can be rewritten without silently voiding the guarantee. |
| B1 | `hrun` and the new `hrun_relative` funnel into one `sandbox_run <invocation> …`, so the suite still spawns processes in exactly one place. **Anchored**: R9 proves the two shapes really produce different `$0` (probe script through the same `sandbox_run`), so a later "simplification" of the `rel` branch fails loudly instead of quietly making R9 compare two identical command lines. |
| B2 | `test_R2_absent_key_writes_nothing` gained a positive, self-contained assertion on the gate-off target **alone**: `find "$_off" -iname '*worker*'` must be empty. The `comm` delta is kept — the two measurements are blind to different things, and the comment now says which is which. |
| nit | `docs/INSTALL.md`'s illustrative `antigravity` entry was **unreachable** (it has a `HOST_MARKERS` row, so it always earns `host-detectable`, which the tag table two paragraphs below states); the example now carries `["host-detectable", "non-interactive"]`. |
| nit | `E17-F04.tests.md` Status column: 18 × ⬜ → ✅, per E17-F02/F03/F05. Nothing else in the contract touched. |

### Mutation results — attributable kills

Detached `git worktree add --detach` at the **committed** round-2 tip (`d5d6a38`), runner
under `scratchpad/E17-F04-builder/` (namespaced). Every mutation asserts its anchor matches
**exactly once** before applying, and every run neutralises **every other case's invocation**
so a kill cannot come from an earlier `fail()`. Free disk on the repo volume: **424 GB
before, 423 GB after** — no mass-failure run, no ENOSPC. Worktree removed after.

| mutation | isolated case | result |
|---|---|---|
| *(none — control)* | `roster_is_valid_json` | **PASS** |
| *(none — control)* | `R9_rerun_is_byte_identical` | **PASS** |
| *(none — control)* | `R2_absent_key_writes_nothing` | **PASS** |
| `generated_by` → `"$0"` | `roster_is_valid_json` | **KILLED** — `FAIL: json: generated_by is '/…/harness-install.sh', expected the fixed literal 'harness-install.sh' — an invocation-dependent value such as $0 makes the roster carry environment-derived content…` |
| `generated_by` → `"$0"` | `R9_rerun_is_byte_identical` | **KILLED** — `FAIL: R9: two runs with identical roster inputs produced different bytes — the only thing that differed was HOW the same installer was invoked…`, diff showing `"/…/harness-install.sh"` vs `"./harness-install.sh"` |
| `: > "$H/workers.stamp"` first line of `write_worker_roster` | `R2_absent_key_writes_nothing` | **KILLED** — `FAIL: R2: the roster gate is off but the target carries roster-named artifacts: …/tgt-r2off/.harness/workers.stamp` |

The three unmutated isolated runs pass, so the isolation itself is not what made the mutated
runs fail.

### Self-check

`./init.sh` green. `sh tools/run-tests.sh` → **all 38 suites passed**.
`tests/test_worker_roster.sh` alone: 16/16 ok (no new case names — the `.tests.md` matrix
stays 1:1, the new assertions live inside the cases that already claim those rules).
No test freezes an exact `VERSION` string; no test diffs a DO-NOT-TOUCH file against `main`.
