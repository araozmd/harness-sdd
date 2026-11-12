# init.sh update check + consented upgrade — Test Contract

> The traceability matrix: every R-id in the .spec.md maps to a concrete, executable test.
> The Reviewer fails the feature if any R-id lacks a passing test. All tests live in one new
> POSIX-sh suite, `tests/test_update_check.sh`, discovered by `tools/run-tests.sh`, plus
> three wiring assertions in `tests/test_install.sh`.

## Suite constraints (binding)
- **No network, ever.** The remote is a `file://` bare/plain git repository built from a copy
  of the source tree; every gate invocation passes `HARNESS_UPDATE_REMOTE=file://…` and
  `HARNESS_SKIP_UPDATE_CHECK=` (empty) to re-enable the check the runner exports off. A
  `git` shim on `PATH` (sleeps on `ls-remote`, otherwise `exec`s the real git) is the only
  way the hang cell is produced.
- **No VERSION literal.** `CUR="$(cat "$SRC/VERSION")"`; `NEXT` = `CUR` with MINOR+1 and
  PATCH 0, derived in the suite; `OLDER=0.0.1`. Assertions compare against `$CUR`/`$NEXT`.
- **No diff against `main`, no DO-NOT-TOUCH diff.** Behavioral assertions only, on fixtures
  under one `mktemp -d` with `trap … EXIT` **and** `trap 'exit 1' HUP INT TERM`
  (`tests/test_suite_hygiene.sh` R1).
- **Sandbox `HOME` and `CODEX_HOME`** on every `harness-install.sh` call (fixture install and
  the upgrade's installer run inherit the env the suite sets).
- **Execute the gate** (`./.harness/init.sh`), never `sh` it (it is bash); assert the banner
  `harness-sdd init` is present in every captured output (interpreter death ≠ verdict).
- **Anti-tautology.** Every "prints nothing / does not prompt / does not contact" cell is
  paired with a positive control on the same fixture that differs in exactly one input and
  does print / prompt / contact. Remote contact is observed via the git shim's call log
  (`$T/git-calls`), not inferred from output.
- **TTY cells** use `HARNESS_UPDATE_ASSUME_TTY=1` with stdin from `printf`; exactly one cell
  (C21) uses a real pseudo-terminal through a small python `pty` runner (the shape of
  `tests/lib/pi_stub.sh`'s `ptyrun.py`, copied into the suite's temp dir) to prove the real
  `-t` detection, and C22 proves a real stdout-TTY with piped stdin does not prompt.
- The suite must pass under `dash` (the runner's strict shell); no bashisms in the suite or
  in `tools/harness-update.sh`.

## Fixtures
- `mk_remote <dir> <kind>` — copies `$SRC` (minus `.git`, `.worktrees`, `node_modules`,
  `scratchpad`), `git init`, commits, then by kind: `newer` tags `v$CUR` on the base commit,
  then writes `VERSION=$NEXT` and appends `# E38 marker` to `agents/scout.md`, commits, tags
  `v$NEXT`; `same` tags only `v$CUR`; `older` tags only `v$OLDER`; `junk` tags `nightly`,
  `v1.2`, `v9.9.9-rc1` and `v$CUR` (so a parser that accepts suffixes would wrongly report
  9.9.9); `newer+junk` = `newer` plus the junk tags; `newer2` = `newer` plus a third commit
  tagged `v$NEXT2` (`NEXT` with MINOR+1); `newer-nobase` = `newer` with the `v$CUR` tag
  deleted (baseline absent); `newer-argvlog` = `newer` whose `v$NEXT` `harness-install.sh`
  has one line inserted after `set -eu` that appends `$*` to `$E38_ARGV_LOG` when that env is
  set (C19 reads it); `newer-badinstaller-config` / `newer-badinstaller-claude` = `newer` whose
  `v$NEXT` `harness-install.sh` additionally rewrites `test_command:` in the target config /
  appends a line to the target's `CLAUDE.md` outside the block (C15b, C16b). Returns
  `file://<dir>`.
- `mk_target <dir> [agents]` — `git init` + `harness-install.sh --agents=claude` + commit
  (verbatim shape of `tests/test_init_drift_guard.sh`). Precondition asserted: clean tree.
- `mk_coordinator <dir>` — umbrella with two git children (`api`, `web`), cascade installed
  with `--agents=claude`, child `api` given `test_command: "pytest -q"` and
  `models: builder: standard` (explicit override differing from the coordinator), child `web`
  converted with `--thin`; every repo committed (`land`).
- `run_gate <dir> [typed]` — `cd <dir> && printf '%s' "$typed" | env <cell env>
  ./.harness/init.sh`, capturing `GATE_OUT`, `GATE_RC`, wall time `GATE_SECS`.
- `git_shim <mode>` — a dir prepended to `PATH` holding `git` that appends `$*` to
  `$T/git-calls` and then, by mode: `log` `exec`s the real git (resolved once, before `PATH`
  is changed); `hang` sleeps 30 s when `$1 = ls-remote`, else real git; `fail-fetch` lets
  `ls-remote` through and exits 128 for `clone` / `fetch` (C14b). Every cell uses at least
  `log`, so "contacts remote?" is always read from the call log.

## Traceability
| R-id | Behavior | Test (file::name) | Type | Status |
|---|---|---|---|---|
| R1 | newer tag ⇒ exactly one `🔔 harness v$NEXT available (installed v$CUR)` line, exit code and other lines unchanged | `tests/test_update_check.sh::R1_notice_when_newer` (C10) | behavioral | ⬜ |
| R2 | source layout, env opt-out, config opt-out, umbrella child, no git ⇒ no contact, no line, output identical to a disabled run; positive control = same fixture without the skip reason prints the notice | `tests/test_update_check.sh::R2_silent_skips_table` (C1–C5 + controls) | behavioral | ⬜ |
| R3 | failing remote and hanging remote ⇒ no line, exit unchanged, gate ends within `HARNESS_UPDATE_TIMEOUT`+gate time, failure cached (second run makes no `ls-remote` call) | `tests/test_update_check.sh::R3_failure_silent_bounded_cached` (C7, C8, C8b) | behavioral | ⬜ |
| R4 | same / older / junk-only tags ⇒ no line; `newer+junk` still reports `v$NEXT`, never `9.9.9` | `tests/test_update_check.sh::R4_same_older_junk_silent` (C9, C9b, C9c, C9d) | behavioral | ⬜ |
| R5 | record written at `<target>/.harness/progress/update-check/last`; fresh record ⇒ no `ls-remote` call yet the notice prints from it; stale (`HARNESS_UPDATE_TTL=0`) ⇒ one call and a rewritten record; dir is git-ignored (`git check-ignore`) | `tests/test_update_check.sh::R5_cache_ttl` (C4b, C6, C6b) | behavioral | ⬜ |
| R6 | interactive + newer ⇒ prompt after notice; `n`/empty ⇒ `declined=v$NEXT` recorded, gate continues rc 0; re-run ⇒ notice, no prompt; a higher tag ⇒ prompts again; non-interactive with `y` on stdin ⇒ no prompt, `y` not consumed (no upgrade, stamp unchanged) | `tests/test_update_check.sh::R6_prompt_only_interactive` (C11, C12, C12b, C13, C21, C22) | behavioral | ⬜ |
| R7 | `y` + `y` ⇒ tag fetched under `progress/update-check/repo`, installed stamp = `$NEXT`, `agents/scout.md` carries the marker, `.harness/.agents` byte-identical, `execution.builder.backend` / `pr_loop.enabled` values unchanged, report names `v$CUR → v$NEXT`, the backup dir, "commit" and "re-run"; gate rc 3; broken remote at fetch time ⇒ rc 5 with message | `tests/test_update_check.sh::R7_consented_upgrade_runs_installer` (C14, C14b) | behavioral | ⬜ |
| R8 | single target with a hand-edited `test_command` and an extra comment line ⇒ `✅ preserved root harness.config.yaml` and both lines still present in order; coordinator ⇒ one `✅` per child incl. `api`'s override; forced violation (a shim installer that rewrites a value) ⇒ `❌ changed`, snapshot path printed, rc 4 | `tests/test_update_check.sh::R8_config_preserved_proof` (C15, C15b, C19) | behavioral | ⬜ |
| R9 | `CLAUDE.md` with prose above and below the block, `AGENTS.md` without a block ⇒ `✅ preserved root CLAUDE.md` / `AGENTS.md`, bytes outside the block identical; forced violation ⇒ `❌ changed`, rc 4 | `tests/test_update_check.sh::R9_entrypoints_preserved_proof` (C16, C16b) | behavioral | ⬜ |
| R10 | coordinator ⇒ installer invoked with `--umbrella <umbrella-dir>` (the manifest file's parent; argv read from `$E38_ARGV_LOG`); `api` and `web` stamps = `$NEXT`; `web`'s prose tier still stubs (sentinel line 1); installer exit 3 reported as success, gate rc 3 | `tests/test_update_check.sh::R10_coordinator_cascades` (C19, C19b) | behavioral | ⬜ |
| R11 | edited `agents/reviewer.md` + added `<target>/.harness/agents/extra.md` ⇒ preview lists both (counts for the edit, `local addition` label for the add), names the remote and `v$NEXT`, before any write; `n` at preview ⇒ rc 2, every file under the target byte-identical (`git status --porcelain` empty after a pre-prompt commit), no backup dir; clean body ⇒ `(no local edits to harness-owned files)` and still asks; baseline tag absent (remote without `v$CUR`) ⇒ stated fallback line | `tests/test_update_check.sh::R11_preview_then_consent` (C17, C17b, C17c, C17d) | behavioral | ⬜ |
| R12 | after a consented upgrade: `upgrade-backup/$CUR/agents/reviewer.md` and `…/agents/extra.md` are `cmp`-identical to the pre-upgrade originals, `…/preservation/root/{harness.config.yaml,CLAUDE.md,AGENTS.md}` present and identical; `git check-ignore` accepts the dir; a second upgrade from the same old version does not overwrite the first dir | `tests/test_update_check.sh::R12_backups_precede_replacement` (C18, C18b) | behavioral | ⬜ |
| R7, R2 | installer wiring: `tools/harness-update.sh` in `_sse_expected`; installed `<target>/.harness/tools/harness-update.sh` exists, `-x`, `cmp`-identical; shipped config has `update.check: true` / `update.remote: ""`; a stripped config gains the `update:` block on upgrade with every prior line intact | `tests/test_install.sh::test_source_scripts_are_executable` (extended) and `tests/test_install.sh::update_tool_and_config_wired` (new) | contract | ⬜ |

## Decision table — every cell pinned (`check` side)
`src` = source layout (no stamp); `inst` = installed single target; `child` = `umbrella.root`
set; `coord` = manifest present. `cache` values: `-` absent, `F+` fresh with `latest=$NEXT`,
`F=` fresh with `latest=` empty, `D` fresh + `declined=$NEXT`. `tty`: `n` none, `h` env hook,
`p` real pty (stdin+stdout), `o` real pty on stdout only, stdin a pipe.

| Cell | layout | opt-out | cache | remote kind | tty | typed | ls-remote calls | 🔔 line | prompt | gate rc | extra assertion |
|---|---|---|---|---|---|---|---|---|---|---|---|
| C1 | src | none | - | newer | h | `y\n` | 0 | no | no | unchanged | source `./init.sh` output has no `harness v` line |
| C2 | inst | env | - | newer | h | `y\n` | 0 | no | no | 0 | stamp unchanged; control: same run with env empty ⇒ 🔔 |
| C3 | inst | config `check: false` | - | newer | h | `y\n` | 0 | no | no | 0 | control: `check: true` ⇒ 🔔 |
| C4 | child | none | - | newer | h | `y\n` | 0 | no | no | 0 | child config has `umbrella.root` set; control: clear it ⇒ 🔔 |
| C4b | inst | none | - | newer | n | – | 1 | yes | no | 0 | record now exists with `latest=$NEXT`; `git check-ignore -q .harness/progress/update-check/last` |
| C5 | inst | none | - | newer | n | – | 0 | no | no | 0 | `git` absent from `PATH` (sandbox PATH minus git dirs) ⇒ gate still ends 0 with no update line; control: real PATH ⇒ 🔔 |
| C6 | inst | none | F+ | **unreachable** (`file:///nonexistent`) | n | – | 0 | yes | no | 0 | the notice came from the record (remote is `file:///nonexistent`) |
| C6b | inst | none | F+ (stale by `TTL=0`) | same (reachable, only `v$CUR`) | n | – | 1 | no | no | 0 | record rewritten with `latest=$CUR` |
| C7 | inst | none | - | fail (`file:///nonexistent`) | h | `y\n` | 1 | no | no | 0 | record written with empty `latest`; no stdin consumed |
| C8 | inst | none | - | hang (shim, `TIMEOUT=2`) | n | – | 1 (killed) | no | no | 0 | `GATE_SECS` ≤ 2 + baseline gate time + 3 s margin; no orphan `sleep` after exit |
| C8b | inst | none | after C7 | fail | n | – | 0 | no | no | 0 | failure cached: second run within TTL makes no call |
| C9 | inst | none | - | same | n | – | 1 | no | no | 0 | – |
| C9b | inst | none | - | older | n | – | 1 | no | no | 0 | – |
| C9c | inst | none | - | junk | n | – | 1 | no | no | 0 | no `9.9.9` anywhere in output |
| C9d | inst | none | - | newer+junk | n | – | 1 | yes (`v$NEXT`) | no | 0 | notice names `$NEXT`, not `9.9.9` |
| C10 | inst | none | - | newer | n | – | 1 | yes, exactly 1 | no | 0 | every non-🔔 line equals the C2 (disabled) output |
| C11 | inst | none | - | newer | h | `n\n` | 1 | yes | yes | 0 | `declined=$NEXT` recorded; gate printed `environment ready` |
| C12 | inst | none | D | newer | h | `y\n` | 0 | yes | no | 0 | `y` not consumed: stamp unchanged |
| C12b | inst | none | D | `newer2` | h | `n\n` | 1 (TTL=0) | yes (`v$NEXT2`) | yes | 0 | higher version prompts again |
| C13 | inst | none | - | newer | n | `y\ny\n` | 1 | yes | no | 0 | stdin `y` ignored off a TTY: stamp = `$CUR`, no backup dir |
| C14 | inst | none | - | newer | h | `y\ny\n` | 1 | yes | yes ×2 | **3** | stamp = `$NEXT`; marker in `.harness/agents/scout.md`; `.harness/.agents` identical; report lines; `update-check/repo` is a git checkout at `v$NEXT` |
| C14b | inst | none | - | newer + `git_shim fail-fetch` | h | `y\ny\n` | 1 | yes | yes | **5** | message names the failure; stamp unchanged |
| C21 | inst | none | - | newer | p | `n\n` | 1 | yes | yes | 0 | real `-t 0 && -t 1` detection, no env hook |
| C22 | inst | none | - | newer | o | `y\n` (pipe) | 1 | yes | no | 0 | stdout-TTY alone never prompts |

## Decision table — `upgrade` side (interactive hook, remote `newer`, after `y` at R6)
| Cell | fixture | preview expectation | typed at preview | rc | post-conditions |
|---|---|---|---|---|---|
| C17 | inst + edited `reviewer.md` (+2 lines) + added `<target>/.harness/agents/extra.md` | exactly two file lines: `M agents/reviewer.md (+2 -0)` form, `A agents/extra.md local addition` form (no counts); the remote URL and `v$NEXT` named; R8/R9 guarantee sentence; `Proceed with the upgrade? [y/N]` | `n\n` | 2 | tree byte-identical (`git status --porcelain` empty vs a commit made right before the run); no `upgrade-backup/`; `declined=$NEXT` recorded; the next gate run prints the notice without a prompt |
| C17b | inst, clean body | `(no local edits to harness-owned files)` and the question | `n\n` | 2 | as above |
| C17c | inst, remote `newer-nobase` | a line stating the fallback to `v$NEXT`; `agents/scout.md` listed (it differs in the incoming tag) | `n\n` | 2 | – |
| C17d | inst + edited `reviewer.md` | preview printed **before** any write: a `find -newer` sentinel touched before the run shows no changed file under the target at the moment of the prompt (assert via `n` + identical tree) | `n\n` | 2 | – |
| C18 | C17 fixture | – | `y\n` | 3 | `upgrade-backup/$CUR/agents/reviewer.md` and `…/agents/extra.md` `cmp` pre-upgrade copies; `…/preservation/root/{harness.config.yaml,CLAUDE.md,AGENTS.md}` identical; `git check-ignore -q .harness/progress/upgrade-backup`; `<target>/.harness/agents/extra.md` no longer present (the installer removed it — which is why it was backed up) |
| C18b | C18, then re-install `v$CUR` by hand and upgrade again | – | `y\n` | 3 | the first backup dir's `reviewer.md` still has the first content; the second run used a sibling name |
| C15 | inst, config with `test_command: "pytest -q"` + `# my note` line | – | `y\n` | 3 | `✅ preserved root harness.config.yaml`; both lines present, order kept; `update:` block appended |
| C15b | inst, remote `newer-badinstaller-config` | – | `y\n` | **4** | `❌ changed root harness.config.yaml`; snapshot path printed and exists |
| C16 | inst, `CLAUDE.md` = prose + block + prose, `AGENTS.md` = prose only | – | `y\n` | 3 | `✅ preserved root CLAUDE.md` / `AGENTS.md`; bytes outside the block identical |
| C16b | inst, remote `newer-badinstaller-claude` | – | `y\n` | **4** | `❌ changed root CLAUDE.md`, rc 4 |
| C19 | `mk_coordinator`, remote `newer-argvlog`, `E38_ARGV_LOG=$T/argv` | – | `y\n` | 3 | `$T/argv` holds `--umbrella <umbrella-dir>` where `<umbrella-dir>` is the manifest file's parent; `api`/`web` stamps = `$NEXT`; `✅ preserved api harness.config.yaml` with `pytest -q` and `builder: standard` intact; `✅ preserved web …`; `web` prose tier still stubs |
| C19b | C19 output | – | – | 3 | the installer's own `❌ … NOT COMMITTED` audit line is present **and** the tool's report says the upgrade succeeded and must be committed (exit 3 interpreted as success) |

## Behavioral / end-to-end checks
- Reviewer runs `tools/run-tests.sh tests/test_update_check.sh` under the runner (one run
  per machine) and once `sh tests/test_update_check.sh` directly, to prove the suite's own
  `HARNESS_SKIP_UPDATE_CHECK=` re-enable does not depend on the runner's export.
- Reviewer runs the whole suite tree once serially and confirms no pre-existing suite now
  takes longer by more than the `HARNESS_UPDATE_TIMEOUT` bound (the runner export must make
  them skip; a slowdown means the export is missing).
- Mutation mandate samples (the Reviewer picks at least three): (a) remove the `exec` in
  `init.sh` — informational, not a kill: C14 is expected to still pass through the second
  layer (functions + final `main`), and the Reviewer confirms the `exec` is present by
  inspection and records the outcome; (b) make the opt-out loud — C2's "output identical to a disabled
  run" fails; (c) accept `v9.9.9-rc1` in the tag regex — C9c/C9d fail; (d) swap the
  preservation rule from subsequence to equality — C15 fails on the appended `update:`
  block; (e) read the baseline from the incoming tag unconditionally — C17 lists
  `agents/scout.md` and fails the exact-list assertion.

## Non-functional checks
- Lint: `sh -n tools/harness-update.sh` and `dash -n tools/harness-update.sh` clean (where
  `dash` exists); `tools/run-tests.sh` reports the suite under its strict shell.
- `tests/test_suite_hygiene.sh` stays green (both traps present in the new suite).
- `tests/test_install.sh` green with the three new assertions; `tests/test_init_drift_guard.sh`,
  `tests/test_cascade.sh`, `tests/test_umbrella_*.sh` green and not slower.
- `python3 tools/readiness-check.py <feature-dir>`, `tools/plan-cite-check.py`,
  `tools/tasks-pair-check.py` exit 0 (Architect ran them at hand-off; Reviewer re-runs).
