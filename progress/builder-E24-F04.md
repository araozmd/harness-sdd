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


---

# Round 2 — the Reviewer's REJECT, answered

`progress/E24-F04/review.md` carried two blocking findings and one required amendment. I
reproduced all three premises before touching anything; **all three hold**, and I disagree
with none of them. Free space on the volume holding the repo and the scratchpad: **425 GiB
before the run, 425 GiB after** — no ENOSPC window, so the results below are trustworthy.
Everything scratch lives under `scratchpad/E24-F04-builder/`.

## Finding 1 (BLOCKING) — the pristine reference was unpinned

**Premise, verified end to end before implementing.** Built a full-copy child of a reachable
umbrella with the product's own steps (single-target install, then `--umbrella`), appended one
line to the **umbrella's** `.harness/agents/builder.md`, then ran single-target
`harness-install.sh --thin <umb>/kid`:

- real code → `NOT converted … differs: agents/builder.md`, child's body left in place
- `prose_tier_blockers "$H" "$SRC"` → `CONVERTED to the thin layout`, and the child's
  `agents/builder.md` line 1 became `<!-- harness:umbrella-stub -->`

So the Reviewer's account is exact: the mutant deletes a stale-but-pristine child's prose tier
and redirects it at umbrella content that child never held.

**Landed:** `tests/test_umbrella.sh::thin_reference_is_the_umbrella_body` (new block, after the
three-shape case), built on the existing `f04_fullchild` fixture in its own umbrella `f04h`. It
asserts, in order:

1. **precondition** — the child is byte-identical to the installer's `$SRC` copy (`cmp -s`), so
   the two candidate references genuinely disagree; without this the case discriminates nothing
2. the divergence really took (`cmp -s` umbrella vs child now differs)
3. single-target `--thin` exits 0 and **names** `differs: agents/builder.md`
4. no path in the tier became a stub
5. **exactly one** blocker is named — this is what stops "a reference that blocks every child"
   from satisfying (3)
6. the child's own `agents/builder.md` is still byte-identical to `$SRC` afterwards

`tests/test_umbrella.sh` is run **single-target, never as a cascade**: a cascade re-installs the
coordinator first and would erase the umbrella-side edit, collapsing the case back onto `$SRC`.

The matrix row and the mutation row are in `E24-F04.tests.md`, together with an anti-tautology
bullet saying why every other fixture in the suite is blind to this rule.

## Finding 2 (BLOCKING) — `prose_tier_blockers` failed OPEN

**Premise, verified with a shim.** Extracted the real function out of `harness-install.sh` and
ran it with a `diff` on `PATH` that exits 1 and prints nothing:

- before: `RESULT: NO BLOCKERS` — the tier reported convertible on the strength of a comparison
  that said it was not
- after: all five tier entries block

**Landed:** the one-line guard the review specified, plus the comment that says why it is not
claimed as tested — the system `diff` does not produce that combination, and a fixture that
shimmed one onto `PATH` would be testing the shim, not this installer. Same shape as the
`diff`-absent arm two lines above. The function's header comment now states the contract
correctly: *the exit status is the contract, and the parsed lines only NAME the paths.*
`.tasks.md` T5 carries the same correction.

## Finding 3 (REQUIRED) — the plan's `-q` reasoning was false

**Premise, measured.** Two directories without `-q` emit `diff -r <a>/builder.md <b>/builder.md`
ahead of the hunks — a form the parser does not recognise — so `agents/builder.md` collapses to
`agents`. Two regular files emit `1c1 / < x / --- / > y`, which the `*)` arm turns into the tier
entry, and for a regular-file entry that **is** the right answer. So `AGENTS.md` and
`specs/glossary.md` **are** named without `-q`; the plan said the opposite.

**Amended:** `E24-F04.plan.md` → *The comparison* now states both arms with the measurement, and
says explicitly why the distinction is worth the words — a reader who checks the regular-file
claim, finds it false and stops there deletes the flag protecting every nested path. The same
false reason in `.tasks.md` T4 is corrected too. `harness-install.sh:798-807` already carried the
corrected account and is unchanged.

## The Reviewer's note about `remove_if_pristine`

Agreed and acted on by **not** acting: the pristine rule stays a third byte-identity comparison.
`remove_if_pristine` is a single-file `cmp -s`-against-a-stamp deletion predicate and cannot
answer "which paths differ against a remote reference"; *Recorded decision E* sanctions the
separate rule, and `.plan.md` → DO NOT TOUCH forbids refactoring the three call-shapes into one
helper.

## Mutation proof for the new case

Mutation: `prose_tier_blockers "$H" "$_umb_body"` → `prose_tier_blockers "$H" "$SRC"`, applied to
a `cp -R` copy of the repo (`scratchpad/E24-F04-builder/srcmut`) — **the repo's own
`harness-install.sh` was never edited to test it**. Confirmed applied by re-reading the line and
`sh -n`.

Attribution was arranged in both directions, since a single suite run cannot tell a kill from a
mask:

| Suite variant | Installer | Result |
|---|---|---|
| trimmed: every other F04 case's invocations **and their `pass` echoes** removed, new case only | pristine | green (`ok - R2 thin_reference_is_the_umbrella_body`) |
| trimmed: same | `$SRC` mutant | **exit 1 — killed** |
| complement: the whole F04 suite with **only** the new case removed | `$SRC` mutant | **green, all 40 assertions** |

The killing message, verbatim:

```
FAIL: R2: the child is byte-identical to the installer's $SRC but NOT to the umbrella body,
and --thin did not block on agents/builder.md — the conversion's pristine reference is $SRC,
not the umbrella's copy, so a child that is merely STALE is converted and redirected at
content it never held: …
```

The complement row is the important one: it reproduces the Reviewer's finding exactly (the
mutant survives everything that existed before) and proves the kill is attributable to the new
case alone rather than to a fixture it shares.

Restored (the mutant only ever existed in the scratch copy) and re-confirmed green.

## Verification, round 2

- `./init.sh` → `environment ready — agents may proceed`
- `sh tools/run-tests.sh` → **all 40 suites passed (--jobs 8)**
- `sh tests/test_umbrella.sh` → 24 `ok` lines including the new case; also green under `dash`
- `sh -n harness-install.sh`, `bash -n init.sh` clean; `harness-install.sh` still contains no
  case-insensitive "drift" (`grep -ci` → 0)
- `sh tools/change-size.sh` → production 269 lines / 4 files, tier **ok**
- `VERSION` unchanged at 0.64.0 — this round adds one guard line, one test and doc corrections,
  all inside the feature 0.64.0 already describes. No test asserts the literal value.

## Anything I disagree with

Nothing. Each finding's stated mechanism was probed before it was implemented, and each one
behaved as the review described — including Finding 3, where the review's correction confirms
round 1's own code comment against round 1's plan.

---

# Round 3 — the two new findings

Both are round 1's species again: the suite green while the destructive path stubs a child that
is **not** pristine. Both premises were probed on a `cp -R` copy **before** anything was written,
and both held exactly as the review described.

## Finding 4 — `specs/glossary.md` had no differential test, and byte-strictness was pinned nowhere

Two survivors, each a one-line edit, each leaving 71 `ok` green:

- the prose sweep iterating a hardcoded `AGENTS.md agents docs specs/_templates` instead of
  `$HARNESS_BODY_PROSE` — the dropped entry is never compared, so a child that edited it converts
- `diff -rq` → `diff -rqw` — byte identity relaxed to identity-modulo-whitespace, so a child whose
  edit is a CRLF round-trip converts

**Premise check (my own, `scratchpad/E24-F04-builder/probe.head.sh`).** A full-copy child of a
reachable umbrella whose **only** difference is a trailing space on line 1 of
`specs/glossary.md`, converted single-target:

| Installer | `differs:` lines | On disk |
|---|---|---|
| pristine | `differs: specs/glossary.md` | NOT-converted |
| `diff -rqw` | *(none at all)* | **CONVERTED — prose tier deleted and stubbed** |
| hardcoded sweep | *(none at all)* | **CONVERTED — prose tier deleted and stubbed** |

So the finding's premise holds, including the data-loss half.

**Fix** (`tests/test_umbrella.sh`, the existing `shapes` child — one seeded line):

```sh
awk 'NR == 1 { printf "%s \n", $0; next } { print }' "$KS4/specs/glossary.md" > "$AU/f04c-glossary.tmp"
cat "$AU/f04c-glossary.tmp" > "$KS4/specs/glossary.md"
```

A **trailing space on line 1**, never new text: new text differs under `-w` too and would kill
only one of the two mutations. Two preconditions guard the fixture against silently degrading
into the `AGENTS.md` shape — the edit must be a real byte difference (`cmp -s` must fail) **and**
invisible to `diff -qw` — both measured against the umbrella's own copy, which is the reference
the conversion uses.

**Where the assertion went, and why not in the `:1510` loop.** The review's remedy said to add
`specs/glossary.md` to that naming loop. The predicate is identical either way, but the loop's
failure message is *"diff's own wording never contains it"* — true of the three shapes it covers,
**false** of this one, since `Files <a> and <b> differ` carries this path already. A message that
misdiagnoses is how the next maintainer stops looking, so it is asserted immediately after the
loop as its own case, `thin_comparison_is_byte_identity`, with a message that names both
mechanisms it can fail by. Same fixture, same segment, same kill.

## Finding 5 — the umbrella-side one-sided path was unpinned

**Premise check (probe 2).** Same fixture, umbrella given `agents/newfile.md` that the child has
never held:

| Installer | refusal names | On disk |
|---|---|---|
| pristine | `differs: agents/newfile.md` | NOT-converted |
| umbrella arm deleted | `differs: agents` | NOT-converted (**fails closed** — naming precision, not data loss) |

Exactly as described.

**Fix:** a new case, `thin_umbrella_side_path_is_named`, in **its own umbrella** (`$AU/f04i`).
`$F04C`'s umbrella serves both `extra` and `shapes`, and `extra`'s whole value is that a
child-local one-sided path is its **only** difference — an umbrella-side file seeded there would
block `extra` for a second reason and dissolve that case. Single-target, like
`thin_reference_is_the_umbrella_body` and for the same reason. Two controls: the path must **not**
exist in the child (or the umbrella arm is never reached), and **exactly one** blocker must be
named (or "the path was named" is equally explained by a run that names every tier entry it
walks).

## Mutation proof — all three, attributed in both directions

Applied with `sed` to a `tar`-cloned copy under `scratchpad/E24-F04-builder/`; **the repo's own
`harness-install.sh` was never edited to test it**. Each mutant was confirmed applied by `diff`
against the base copy and `sh -n`. Free space on the volume: **425 GiB before the campaign,
431 GiB after** — no ENOSPC, so the failures below are real kills, not an outage.

| # | Mutation | Full suite | Killing assertion |
|---|---|---|---|
| M1 | `842: diff -rq` → `diff -rqw` | **exit 1 — killed**, after 63 `ok` | `thin_comparison_is_byte_identity` |
| M2 | `830: for _ptb_rel in $HARNESS_BODY_PROSE` → hardcoded `AGENTS.md agents docs specs/_templates` | **exit 1 — killed**, after 63 `ok` | `thin_comparison_is_byte_identity` |
| M3 | `880:` the `"$_ptb_u"/*)` arm deleted (falls through to the fail-closed `*)`) | **exit 1 — killed**, after 65 `ok` | `thin_umbrella_side_path_is_named` |

Killing messages, verbatim:

```
FAIL: R2/R3: a WHITESPACE-ONLY edit to specs/glossary.md was not reported as a blocker —
either the comparison is identity-modulo-whitespace rather than BYTE identity, or the prose
sweep never compared that entry at all; under either, a child whose ONLY difference is that
edit CONVERTS and its prose tier is deleted: …

FAIL: R3: a path the UMBRELLA holds and the child does not was not named as a tier-relative
path — the refusal names the tier entry `agents`, pointing the operator at a directory
instead of the file: …
```

**Attribution.** A single failing run cannot tell a kill from a mask, so both directions were
run:

| Suite variant | M1 | M2 | M3 |
|---|---|---|---|
| control, pristine installer | green, 73 `ok` | green, 73 `ok` | green, 73 `ok` |
| full suite | **killed** at the new case, every earlier case `ok` | **killed** at the new case | **killed** at the new case |
| complement — the whole F04 suite with **only the two new cases** removed, fixtures left in place | **green, 71 `ok`** | **green, 71 `ok`** | **green, 71 `ok`** |

The complement row reproduces the review's finding exactly (each mutant survives everything that
existed before) and proves each kill is attributable to the new case alone. The full-suite row's
`ok` prefix proves no earlier case masks it. The mutants only ever existed in the scratch copies.

## Also in this round

- `harness-install.sh:850-853` — narrowed the round-2 guard's disclosure, per the review's note.
  `diff` is invoked in exactly one place, so "a shim would be testing the shim" was weaker than
  it read. The honest reason is a **weak control**: a shim that always exits non-zero with no
  output is indistinguishable from an installer that blocks everything, which is the outcome such
  a fixture would assert. Comment only; no code change.
- `E24-F04.tests.md` — the R3 row at `:16` no longer claims `specs/glossary.md`; that entry now
  has its own row, and a third row covers the umbrella-side one-sided path. Three mutation rows
  added (`-w`, the hardcoded sweep, the umbrella arm), and the pre-existing `diff -rq loses its
  -q` row was corrected to name the case it actually kills — the **nested** path
  `agents/builder.md` in `thin_names_every_blocker`, not the regular-file entries, which round 2
  measured as still named via the fail-closed arm. Two anti-tautology bullets record why a
  whitespace-only edit is the only thing that pins byte identity and why the umbrella-side case
  needs its own umbrella.

## Verification, round 3

- `./init.sh` → `environment ready — agents may proceed`
- `sh tools/run-tests.sh` → **all 40 suites passed (--jobs 8)**
- `sh tests/test_umbrella.sh` → **73 `ok`** (71 + the two new cases); also green under `dash`,
  and `dash -n` clean
- `sh -n harness-install.sh`, `bash -n init.sh` clean; `harness-install.sh` still contains no
  case-insensitive "drift"
- `sh tools/change-size.sh` → production **270** lines / 4 files, tier **ok** (round 2 was 269;
  the +1 is the narrowed comment)
- `VERSION` unchanged at **0.64.0** — this round adds two tests and doc corrections inside the
  feature 0.64.0 already describes. No test asserts the literal value, and none diffs against
  `main`.
- Counting idiom: the new "exactly one blocker" control uses `grep -o … | wc -l | tr -d ' '`,
  never a possibly-zero `grep -c` bound under `set -eu`. BSD `awk`/`grep`/`diff` only.

## Anything I disagree with

Nothing substantive. One deviation, stated above and deliberate: the `specs/glossary.md`
assertion is its own case rather than an entry in the `:1510` loop, because that loop's failure
message would misdiagnose this shape. The predicate, the fixture and the measured kills are
exactly the ones the review verified.

## PR repair checkpoint — 2026-08-18

Four live Codex threads were audited against the branch, not inferred from their unresolved
state. The self-referential `umbrella.root` refusal and the `--standalone` recovery instruction
were already present and covered. The remaining two portability gaps were closed in
`be8d160`: harness-owned cleanup now makes its own tree writable before removal, and the
mid-swap rollback test asserts the structural outcome even when uid 0 makes mode bits
non-binding.

Two fresh mutations pin those changes:

- deleting `chmod -R u+w` from `rm_owned_tree` makes the read-only reinstall case fail at the
  expected permission-denied cleanup, while the pristine installer passes;
- neutralising the swap-back helper while forcing the test's mode probe to report non-binding
  makes the structural rollback marker fail because `AGENTS.md` loses the operator bytes.

Both mutants were restored byte-clean. `aa9eaaa` also repairs a pre-existing red baseline in
`tests/test_inception.sh`: its zero-dependency fallback now accepts the same five epic states as
the authoritative schema. The failure reproduced on `origin/main` before that one-line test-only
change.

Latest-main integration was repeated after PRs #148, #154, and #153 landed. Their releases remain
0.67.0 and 0.68.0; E24-F04 is restamped **0.69.0**. Final local verification at `60aed02` plus the
repair commits: `./init.sh` green, `sh -n harness-install.sh` green, `tests/test_inception.sh`
green, and `sh tools/run-tests.sh` reports **all 43 suites passed** under
`/bin/dash [PROGRAM:dash PROJECT:dash-16]` with `--jobs 8`. Change-size versus the latest
`origin/main`: **799 production lines / 4 files**, tier **ok**.

### Independent-review repair

The final read-only review found one P2: `diff -rq` was forced to fail closed, but its exact-path
diagnostics still split English prose at the first ` and ` / `: `. A parent path containing those
legal strings reduced `agents/builder.md` and `docs/extra-local.md` to the tier roots `agents` and
`docs`. A new integration fixture reproduced that exact output before the fix. The parser now
runs `diff` under `LC_ALL=C` and anchors both recognised message forms on the two exact roots it
passed to `diff`; the same fixture and the complete umbrella suite pass. The review's P3 was also
correct: the changelog named the removed `stub_tree` helper and now names `thin_prose_tier`.
