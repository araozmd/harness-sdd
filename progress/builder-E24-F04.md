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

Run **after** committing `3c15e10`, in a throwaway `git worktree add --detach` at that
commit (`scratchpad/E24-F04-builder/wt`, created by this run and removed after it — no
other worktree was touched). Every mutation was applied by an anchor-count-checked patcher
that **exits non-zero unless the anchor occurs exactly once and the file changed**, so no
result below was read from an unapplied mutation. Free space on the volume holding both the
repo and the scratchpad: **425 GiB before the campaign, 425 GiB after** — no ENOSPC window.

`tests/test_umbrella.sh` is a straight-line suite: it aborts at the first failing case, so
a row *after* the killer is unobserved in that run. Where that happened I ran a **direct
probe** (`probe-unreached.sh`) against the same mutant, and I ran that probe against the
**unmutated tip first** — all three of its lines read PASS there, so it is a valid
instrument and not a generator of the answer I wanted.

| # | Mutation | Killed by | Message | Stayed green |
|---|---|---|---|---|
| M1 | `prose_tier_blockers` always prints nothing | `thin_all_or_nothing_on_edit` (R2) | `R2 (one edited file must block the WHOLE tier): 30 prose-tier path(s) were converted to stubs` | R1 ×3, R8, **R5**, **R7** all printed `ok` before the abort. R3's kill confirmed by probe: `R3-probe: SILENT` (no `differs: agents/builder.md`) |
| M2 | a path present on only one side is ignored (both the whole-entry pre-check and the `Only in` branch) | `thin_extra_file_blocks` (R2) | `R2 (a child-only extra prose file must block the tier ON ITS OWN): 30 prose-tier path(s) were converted to stubs` | R1 ×3, R5, R7, **R2 edit-case**, **R3 names-case** |
| M3 | the `Only in <dir>: <name>` normalisation removed, diff's raw wording emitted | the one-sided-blocker assertion inside `thin_extra_file_blocks` | `R2: the one-sided path was not reported as the blocker — the tier may have been blocked for another reason` | R1 ×3, R5, R7, R2 edit-case, R3 names-case. The on-disk R2 claim still held (the tier stayed unconverted); what died is the *naming*, which is R3's contract |
| M4 | `diff -rq` loses its `-q` | `thin_names_every_blocker` (R3) | `R3: the refusal did not name the differing path agents/builder.md` | R1 ×3, R5, R7, R2 edit-case |
| M5 | the E24-F03 maintenance branch gated behind `THIN_OPT_IN` | E24-F03's own `thin_child_prose_tier_is_stubbed` | `R2: prose-tier AGENTS.md is not a stub in a fresh cascade child` | R1's kill-freedom confirmed by probe: `R1-probe: CONVERTED`. R5's kill confirmed by probe: `R5-probe: UN-THINNED` |
| M6 | `--thin` converts one path at a time, skipping only the blocking entries | `thin_all_or_nothing_on_edit` (R2) | `R2 (one edited file must block the WHOLE tier): 11 prose-tier path(s) were converted to stubs` | R1 ×3, R8, R5, R7 |
| M7 | the unflagged path converts anyway | E24-F03's own `existing_full_copy_child_untouched` | `R9: the cascade converted an existing full-copy child's body to stubs` | R1's kill-freedom confirmed by probe: `R1-probe: CONVERTED` |
| M8 | the unreachable-umbrella path calls `die` | `thin_unreachable_umbrella_is_not_fatal` (R6) | `R6: --thin with an unreachable umbrella exited 1 — refusing to convert is a warning, never an install failure` | everything before it, including R1 ×3, R5, R7, R2 ×2, R3 ×2, R4 ×2 |
| M9 | `--standalone` leaves `umbrella.root` set | `standalone_clears_umbrella_root` (R10) | `R10: --standalone did not clear umbrella.root:   root: "../../"` | **R9** (`standalone_materialises_body`) printed `ok` immediately before |
| M10 | the `--standalone` + `--umbrella` / `--thin` rejections removed | `standalone_flag_conflicts` (R12, `test_install.sh`) | `E24-F04 R12: --standalone with --umbrella was accepted` | R6's negative control green in the same suite; `test_umbrella.sh` **fully green, 70 `ok`** — R9 and R1 unaffected |
| M11 | the conversion writes its own stub text instead of calling `stub_tree` | `converted_equals_fresh_thin` (R1) | `R1: converted AGENTS.md differs from a FRESHLY cascaded thin child's — a converted child must be byte-indistinguishable from a fresh one` | `thin_converts_pristine_child` printed `ok` first — i.e. the sentinel sweep passed and only the byte-equality caught it, which is exactly why that control exists |

**No mutation survived.** Three findings worth passing on:

1. **M6's first run was invalid and was re-run.** The mutant also changed the conversion's
   `ok` line, so it killed R1's output assertion for a reason unrelated to all-or-nothing.
   Rewritten to reproduce that line byte-for-byte; the corrected mutant is the row above.
2. **M4's kill is the nested-path shape, not the regular-file shape the `.plan.md`
   predicts.** Measured on this box, `diff -r` on two *directories* prints
   `diff --color -r <a> <b>` before the hunks, and my parser's fail-closed `*)` arm turns
   that into the *tier entry* (`agents`) — so `agents/builder.md` is lost and R3 dies. But
   `diff -r` on two *regular files* prints hunks with no filename, and there the same
   fail-closed arm synthesises `AGENTS.md`, which **is** the right answer for a
   regular-file tier entry. So `-q` is load-bearing for **paths nested inside a directory
   tier entry**; the plan's stated reason (the two regular-file entries "could never be
   named") is narrower than written, because the fallback covers them. `-q` is still
   required and still tested — the reason recorded in the code comment is the plan's, and a
   reviewer may want it corrected to this one.
3. **Two mutations (M5, M7) are caught by E24-F03's assertions before F04's own.** That is
   the correct and stronger outcome — both mutations break a guarantee F03 already shipped
   — but it means R5's and R4's own cases are unobserved in those runs, which is why the
   probe rows are recorded above rather than left implicit.

## Anything I could not satisfy

- Nothing in the spec was skipped or narrowed. All 19 tasks are ticked and all 12 R-ids
  have a passing test.
- One constraint from `.plan.md` is **deliberately untested and says so in the code**:
  `prose_tier_blockers`' "fail closed when `diff` is not on `PATH`". `.plan.md` already
  records that a portable fixture cannot remove `diff` from `PATH` without removing it from
  the harness running the test, so it is defence in depth in the same spirit as
  `stub_files_in`'s write checks.
- One incidental repo rule bit this feature and is worth knowing: **`harness-install.sh` may
  not contain the word "drift"** (case-insensitively) — `tests/test_drift_check.sh` R18 and
  `tests/test_installer_toggles.sh` R13 both fail the chain on it. Two comments used it in
  its ordinary English sense; they say "diverge" now.

