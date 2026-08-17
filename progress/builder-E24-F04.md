# Builder run — E24-F04 "Migrate existing children to the thin layout (+ `--standalone`)"

Branch `spec/E24-F04-thin-migration`, worktree `/Users/araozmd/repos/harness-sdd-E24F04`.
Feature status confirmed `in-progress` in `state/tasks.json` before any code was written.
Execution backend: `execution.builder.backend: in-session` (Loop A).

## What landed, per task

| Task | Where | Note |
|---|---|---|
| T1 | `harness-install.sh` arg loop + globals | `--thin` → `THIN_OPT_IN=1`, `--standalone` → `STANDALONE=1`, both default `0`. `--thin` accepted in both modes, `--standalone` single-target. |
| T2 | after the parse loop, beside the other override validations | `--standalone` + `--umbrella` and `--standalone` + `--thin` both `die` there — before target resolution, umbrella discovery and any `install_one`. |
| T3 | installer header comment | usage lines + a `Body layout (--thin / --standalone)` block. |
| T4/T5 | new `prose_tier_blockers <harness-dir> <umbrella-body-dir>` beside `child_is_full_copy` | one `diff -rq` per `HARNESS_BODY_PROSE` entry, captured inside an `if` (never a bare `$( )` under `set -eu`), `2>&1` so diff's exit-2 stderr is folded in. `Only in <dir>: <name>` is rejoined to `<dir>/<name>`; `Files <a> and <b> differ` yields `<a>`; anything unparseable falls back to the tier entry. Every emitted line is then made harness-dir-relative. Missing on either side, and `diff` absent from `PATH`, both block. |
| T6 | `install_one` §1 arm (1) | `STANDALONE=1` takes the ordinary full-copy branch unconditionally, ahead of the umbrella check. |
| T7 | `install_one` §1 arm (2) | deliberate non-change: the F03 maintenance branch is still `[ -n "$_umb_body" ] && ! child_is_full_copy`, with **no** flag in the condition. |
| T8 | `install_one` §1 arm (3) | `prose_tier_blockers` called once, identically with and without the flag; empty + `--thin` ⇒ `stub_tree` per prose entry + `BODY_LAYOUT=thin`; otherwise `copy`. No line needed in `tools/harness-owned-paths.sh` or `init.sh`. |
| T9 | same arm | blocker report (`differs: <path>` per blocker) with the same content flagged and unflagged, plus the "re-installed from source by this run … `git diff` still shows what they held" sentence; `WOULD convert … re-run with --thin` when convertible and unflagged. No count is printed. |
| T9b | same arm | the stale `child already holds a full body — left as-is (converting it is E24-F04)` notice is **replaced** by T9's report. The phrase `already holds a full body` is kept verbatim so E24-F03 R9's existing assertion stays green with no edit, per the regression contract. |
| T10 | `install_one` §1 arm (4) | warns only when `--thin` **and** a non-empty recorded `umbrella.root`; exit status untouched. |
| T11 | §2a | `set_umbrella_root … ""` under `--standalone`, skipped when already empty. |
| T12 | `docs/UMBRELLA.md` | new `## Migrating an existing child (--thin)` (procedure = `--umbrella … --thin` run until it converges; pristine/all-or-nothing; the stale-child case; unreachable umbrella) and `## --standalone — the way back`. No unflagged "preview pass" is presented as a step. |
| T13 | `docs/INSTALL.md` | `### Body layout — --thin and --standalone` flag table + examples. |
| T14 | `harness.config.yaml` | comment block **above** `umbrella.root` extended; the `  root: ""` line is byte-identical (verified with `cat -A`). |
| T15 | installer manifest `BODY LAYOUT` block | documents `full -> thin` and `thin -> full`. |
| T16 | tests, below | |
| T17 | `VERSION` `0.63.1` → `0.64.0` (MINOR), `CHANGELOG.md` `### Added` | no test asserts either literal. |

One incidental fix the suite forced: `harness-install.sh` may not contain the word
"drift" (case-insensitive) — `tests/test_drift_check.sh` R18 and
`tests/test_installer_toggles.sh` R13 both fail the chain on it. Two of my new comments
used it; they say "diverge" now.

## R-id → test mapping

| R-id | Test | File |
|---|---|---|
| R1 | `thin_converts_pristine_child` | `tests/test_umbrella.sh` |
| R1 | `converted_equals_fresh_thin` | `tests/test_umbrella.sh` |
| R1 | `thin_leaves_coordinator_full` | `tests/test_umbrella.sh` |
| R2 | `thin_all_or_nothing_on_edit` | `tests/test_umbrella.sh` |
| R2 | `thin_extra_file_blocks` | `tests/test_umbrella.sh` |
| R3 | `thin_names_every_blocker` | `tests/test_umbrella.sh` |
| R3 | `thin_blocker_paths_are_normalised` | `tests/test_umbrella.sh` |
| R4 | `unflagged_previews_only` | `tests/test_umbrella.sh` |
| R4 | `unflagged_preview_names_blockers` | `tests/test_umbrella.sh` |
| R5 | `thin_maintained_without_flag` | `tests/test_umbrella.sh` |
| R6 | `thin_unreachable_umbrella_is_not_fatal` | `tests/test_umbrella.sh` |
| R6 | `thin_on_single_repo_is_silent_noop` (negative control) | `tests/test_install.sh` |
| R7 | `thin_is_idempotent` | `tests/test_umbrella.sh` |
| R8 | `converted_child_is_committable` | `tests/test_init_drift_guard.sh` |
| R8 | `converted_manifest_says_thin` | `tests/test_umbrella.sh` |
| R9 | `standalone_materialises_body` | `tests/test_umbrella.sh` |
| R10 | `standalone_clears_umbrella_root` | `tests/test_umbrella.sh` |
| R11 | `standalone_is_idempotent` | `tests/test_umbrella.sh` |
| R12 | `standalone_flag_conflicts` | `tests/test_install.sh` |
| — | `f04_docs_contract` | `tests/test_umbrella.sh` |

Fixture discipline actually applied:

- **Full-copy child built single-target FIRST, then cascaded** (`f04_fullchild`), never the
  other way round — the inverted order yields a *thin* child because `umbrella_body_dir`
  falls back to the child's own config, which §2a already persisted.
- `f04_seg` slices a cascade's output **per target** by the `harness install v… → <path>`
  banner, so a per-child assertion cannot be satisfied by a sibling's line. Paths are
  resolved with `pwd -P` first (`f04_phys`): the cascade prints physical paths and
  `mktemp -d` hands the suite the symlinked `/var/...` form, so the naive match silently
  matched nothing (this cost one debugging round).
- R6's umbrella is made unreachable by deleting `<umb>/.harness/.harness-version` —
  **not** by renaming the umbrella dir, which does nothing because the recorded root is
  relative.
- Both blocked-conversion cases carry a **pristine sibling in the same umbrella and the
  same run**, so "nothing converted" cannot be explained by a `--thin` that does not work.
- `f04_no_stub_in_tier` / `f04_all_stubs_in_tier` **sweep the whole tier** with `find`;
  nothing is sampled.
- Prose assertions over `docs/UMBRELLA.md` use a **fence-aware** `f04_span`; counts use
  `grep -o … | wc -l | tr -d ' '`, never `grep -c`.

## Verification

- `sh -n harness-install.sh`, `dash -n harness-install.sh`, `bash -n init.sh` — clean.
- `./init.sh` — `environment ready`.
- `sh tools/run-tests.sh` — **all 40 suites passed (--jobs 8)**.
- `dash tests/test_umbrella.sh`, `dash tests/test_install.sh`,
  `dash tests/test_init_drift_guard.sh` — all exit 0.
- `sh tools/change-size.sh` — `tier: ok`, production 248 / tests 815 / docs 710, total 1773
  lines across 14 files.

## Mutation proof

Recorded below in "Mutation results" after the first commit.
