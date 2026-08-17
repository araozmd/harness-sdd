# E21-F05 — Builder run notes

**Feature:** The stacked-PR lane's doctrine document
**Branch:** `spec/E21-F05-doctrine-redrill` (worktree `/Users/araozmd/repos/harness-sdd-E21F05`)
**Status precondition confirmed before any code:** `state/tasks.json` → E21-F05 `in-progress`
(human-approved gate, `autonomous: false`). `./init.sh` green before starting.
**Backend:** `execution.builder.backend` absent → `in-session`, Loop A.

Scope held exactly as specced: `docs/WORKFLOW.md`'s `## Stacked-PR lane` section, one
append-only note in E21-F04's shipped spec, one new test suite, `VERSION` + `CHANGELOG.md`.
**No `agents/` file, no production code, no `harness-install.sh`, no
`tools/pr-stack-guard.sh`, no `verification.test_command`, no board write.**

## Tasks

| Task | What was done |
|---|---|
| T1 | Lane opening paragraphs rewritten: what the lane is for (bounding the size of each review), the mechanical outcome (merging an increment publishes that increment's work to the **default branch** while the later increments are **still open**), and a pointer to `Entry condition`. States no condition and names no alternative of its own; "only the combined work delivers the full capability" deleted; says `default branch`, not `main`. |
| T2 | New `### Entry condition`, the lane's first subsection: both conditions checked **before the first increment PR** is opened (`independently safe` on the default branch; passes `verification.test_command` on its own), then the refusal (`not a candidate`), the alternatives (`feature flags`, an aggregate landing strategy) and `an open problem this epic does not solve`. |
| T3 | `### When to use what` row 3 → refusal + pointer to `Entry condition`. Row now contains neither `feature flag` nor `separate independent features`. Rows 1, 2, 4 untouched (they carried no `wave`); table not restructured. |
| T4 | `### Creating stacked increments`: identifiers only — `feat/wave-1/2/3` → `feat/increment-1/2/3`, PR titles `wave N` → `increment N`. The three-`gh pr create` block, its heading and its prose are otherwise byte-identical; nothing about who opens a PR or when was added (that is E21-F06's). |
| T5 | `### Wave-boundary guidance` → `### Where to cut`. The E21-F01 attribution is gone; the guidance now points at the lane's own `Entry condition` and the `change_size` budget thresholds (naming the `Change-size discipline` **section**, not an epic id), and states plainly that the harness records no stacking-specific seam vocabulary. |
| T6 | `### Manual restack procedure (R7)` → `### Restack procedure` — the name `harness-install.sh:4325`'s shipped diagnostic already points at. Procedure body unchanged (the `git rebase --onto` steps and the warning against the bare two-arg form); only the leaked id and the branch identifiers changed. `harness-install.sh` NOT edited. |
| T7 | New `### What the board shows` after `### Restack procedure`: one feature record, order in `baseRefName`, **no per-increment** board record. Says nothing about when `done` is written (that obliges an `agents/orchestrator.md` exception line — E21-F06's). |
| T8 | `### Opt-in and inert-when-disabled` body rewritten: opt-in statement kept, `(R9)` and `(R8)` dropped, the false "no stacking documentation is stamped" claim replaced with `ships with the harness body` regardless of `pr_loop.enabled`, plus what the flag does gate (`/sdd-pr-loop` not installed → the guard has no caller, no stacking-specific merge logic). |
| T9 | Lane sweep, `grep -o … \| wc -l` (occurrences, not lines). Before → after, against the spec's own baselines: `atomic` 1→0, `wave` 16→0, `E21-F01` 1→0, `(R[0-9][0-9]*)` 3→0, `separate independent features` 1→0, `documentation is stamped` 1→0, `feature flag` 2→**1**, `independently safe` 0→**1**, `verification.test_command` 0→**1**. Every baseline the spec recorded was re-measured on this tree first and matched. |
| T10 | Append-only supersession note under F04's existing `## Re-spec notes`: R6 (two parts), R7 (retained in substance, renamed), R8's documentation clause, and an explicit statement that **F04-R8's behavioral half is untouched and still holds**. No requirement text edited, no F04 prose reworded, no frontmatter touched. Written as a paragraph, **not** a `###` subheading, on purpose: `sect()` stops at the next heading of any level, so a subheading there would hide the note from its own test — the note says so inline. |
| T11 | `tests/test_stacked_doctrine.sh`, executable, auto-discovered. One function per `R-id`, `set -eu`, house `fail`/`pass`, fence-aware `sect()`/`span()` copied verbatim with their comments, per-suite `mktemp` fixture + cleanup `trap`, `HOME` **and** `CODEX_HOME` sandboxed on the one installer-invoking case. No `grep -c` anywhere, no `VERSION` assertion, no diff against `main`, no whole-file grep. `shellcheck` clean apart from SC1007, which is the house `CDPATH= cd` idiom that `tests/test_pr_loop.sh:19` also trips. |
| T12 | Mutation campaign — below. |
| T13 | `VERSION` `0.63.0` → **`0.63.1`** (PATCH), `CHANGELOG.md` `### Fixed` entry. |
| T14 | `./init.sh` green; `sh tools/run-tests.sh` → **all 40 suites passed** (`--jobs 8`, 3m46s); `sh tests/test_stacked_doctrine.sh` green standalone. |

## R-id → test

| R-id | Test |
|---|---|
| R1 | `tests/test_stacked_doctrine.sh::test_entry_condition_stated_once` |
| R2 | `tests/test_stacked_doctrine.sh::test_not_served_case_refused_once` |
| R3 | `tests/test_stacked_doctrine.sh::test_outcome_stated_mechanically` |
| R4 | `tests/test_stacked_doctrine.sh::test_board_shows_one_feature` |
| R5 | `tests/test_stacked_doctrine.sh::test_seam_guidance_has_no_dangling_citation` |
| R6 | `tests/test_stacked_doctrine.sh::test_installer_restack_pointer_resolves` |
| R7 | `tests/test_stacked_doctrine.sh::test_lane_leaks_no_spec_ids` |
| R8 | `tests/test_stacked_doctrine.sh::test_lane_ships_when_pr_loop_disabled` |
| R9 | `tests/test_stacked_doctrine.sh::test_f04_supersession_recorded` |

## T12 — mutation campaign

**Environment, read before and after (`agents/builder.md` → *Scratch files and campaign
preconditions*):** 429 GiB free on `/System/Volumes/Data` before the first mutation and
429 GiB free after the last. No mass-failure run; every run below produced a single
attributable `FAIL:` line. Scratch namespaced under
`scratchpad/E21-F05-builder/` (runner `mutate.py`, mechanics `mechanics.sh`, fixtures).

**Method.** Mutations run in **my own** detached worktree (`git worktree add --detach`,
created and removed by this run), never in the primary checkout and never in any worktree I
did not create. The worktree checks out the **committed tip**, so each suite change was
committed before being mutated. `git checkout -- .` restores between mutations; the runner
asserts each mutation's text was actually found before applying it, so a mutation that
silently failed to apply cannot be scored as a survivor-free pass. The suite prints each
`pass` line **inside** the case that earns it, so a case that never ran cannot emit one —
each run below records which cases passed before the kill, and in every case the killed
requirement is the next one in sequence.

### Two surviving mutations — both were real defects, both fixed

**M7 survived the first form of R3.** `default branch` and `still open` were two
independent presence checks over the lane's whole opening. Rewriting the outcome sentence
back to `main` still passed, because a *different* sentence in the same opening mentions
the default branch. Fixed by asserting the two anchors as a conjunction over one paragraph
(commit `4be2e84`).

**M7 survived that too.** The mutated paragraph keeps a later sentence — "The lane changes
nothing else about how or when work reaches the default branch" — so the paragraph-scoped
conjunction was still reachable by a second path. Fixed by unwrapping the opening and
splitting it into **sentences**: no sentence may state the outcome (`still open`) without
naming the `default branch`. The plan's explicit instruction (say `default branch`, not
`main`) is asserted as a separate anti-anchor, matched in its backticked form so
`remains`/`domain` cannot satisfy it (commit `abe2c4c`). `M7b` — which renames the branch
without using the token `main` — proves the sentence conjunction kills on its own, and
`M7c` proves the anti-anchor is not dead code.

### Full result: 26 mutations, 26 killed, 0 survivors

| # | Mutation | R-id | Killing assertion (message, abridged) |
|---|---|---|---|
| M1 | drop `verification.test_command` from `### Entry condition` | R1 | `R1: '### Entry condition' does not name the config key [verification.test_command] …` |
| M2 | a **second** `independently safe` elsewhere in the lane | R1 | `R1: the anchor [independently safe] occurs 2 time(s) …, want exactly 1 — a condition stated twice will disagree with itself` |
| M22 | drop `first increment PR` | R1 | `R1: … does not contain the load-bearing phrase [first increment PR] … reword the sentence around it, not the phrase` |
| M21 | **heading-misfile**: the correct entry-condition prose filed under `### When to use what` | R1 | `R1: docs/WORKFLOW.md has no '### Entry condition' subsection … this suite extracts it by that heading` |
| M3 | drop `this epic does not solve` | R2 | `R2: … does not contain the load-bearing phrase [this epic does not solve] … the unsolved case must be recorded as unsolved` |
| M4 | drop both refusal tokens | R2 | `R2: '### Entry condition' carries no refusal token — it must say [not a candidate] or [do not stack]` |
| M5 | name feature flags a **second** time, in row 3 | R2 | `R2: [feature flag] occurs 2 time(s) …, want exactly 1 — the alternatives are listed in '### Entry condition' and nowhere else` |
| M6 | reinstate `separate independent features` | R2 | `R2: … still carries the competing alternative list [separate independent features] …` |
| M7 | outcome sentence says `main` again | R3 | `R3: 1 sentence(s) … state the outcome ([still open]) WITHOUT naming the [default branch] — the two belong in ONE sentence …` |
| M7b | outcome sentence says `**trunk**` (no `main` token) | R3 | same assertion — proves the conjunction, not the anti-anchor, is what kills |
| M7c | `main` named in a **separate** sentence of the opening | R3 | ``R3: the lane's opening paragraphs name the branch `main` … say [default branch]`` |
| M23 | outcome paragraph no longer says `still open` | R3 | `R3: no sentence in the lane's opening says [still open] …` |
| M8 | reinstate the withdrawn denial sentence | R3 | `R3: the '…' section contains the banned token [atomic] — this vocabulary got the predecessor spec withdrawn after four review rounds` |
| M9 | drop `baseRefName` | R4 | `R4: '### What the board shows' does not name the GitHub field [baseRefName] …` |
| M10 | drop `per-increment` | R4 | `R4: … does not contain the load-bearing phrase [per-increment] …` |
| M11 | rename `### Where to cut` back to `### Wave-boundary guidance` | R5 | `R5: docs/WORKFLOW.md has no '### Where to cut' subsection …` |
| M12 | seam guidance stops pointing at `Entry condition` | R5 | `R5: '### Where to cut' does not point at [Entry condition] …` |
| M13 | one `feat/wave-2` survives **inside a fenced block** | R5 | `R5: … still contains [wave] vocabulary … the example branches and PR titles are part of this sweep` |
| M14 | the dangling `E21-F01` attribution returns, without the word `wave` | R5 | `R5: … still cites [E21-F01] — deleting the word 'wave' while keeping the attribution leaves the same dangling claim` |
| M15 | heading drifts from the installer's diagnostic | R6 | `R6: harness-install.sh points readers at docs/WORKFLOW.md 'Restack procedure', but no '### ' heading … contains that name` |
| M16 | a bare `(R9)` leaks back into a lane heading | R7 | `R7: … leaks bare spec-requirement id(s) [ (R9) ] into a user-facing document …` |
| M17 | drop `ships with the harness body` | R8 | `R8: … does not contain the load-bearing phrase [ships with the harness body] …` |
| M24 | drop `pr_loop.enabled` from that subsection | R8 | `R8: … does not name the config key [pr_loop.enabled] …` |
| M18 | the false claim **migrates one subsection over** | R8 | `R8: … still claims that stacking [documentation is stamped] conditionally …` — proves the ban is lane-scoped, not subsection-scoped |
| M19 | the supersession block is removed from F04's spec | R9 | `R9: E21-F04's '## Re-spec notes' does not name [E21-F05] …` |
| M20 | the ids stay, the verb `supersede` goes | R9 | `R9: … never says [supersede] — the verb is load-bearing: a note that merely MENTIONS R6/R7/R8 records nothing` |

### The R8 carve-out — proved, not skipped

R8's *installed* half passes on an unedited tree by construction, and its only mutation
lives in DO-NOT-TOUCH `harness-install.sh`. It was proved against **fixture copies** of the
installer (`cp -R` of the detached worktree, `.git` removed); the repo's own installer was
never edited, in any worktree.

- **Copy 1** — `docs` removed from `HARNESS_BODY_PROSE`. **KILLED:** `R8: a gate-off
  install produced no …/.harness/docs/WORKFLOW.md at all — docs/ is part of
  HARNESS_BODY_PROSE and must be stamped whatever pr_loop.enabled says`.
- **Copy 3** — the prose copy still runs, but the installed `docs/WORKFLOW.md` loses the
  lane section. **KILLED:** `R8: the installed docs/WORKFLOW.md of a gate-off install
  carries no 'Stacked-PR lane' section — the lane's documentation ships with the harness
  body regardless of the flag; only its behavior is gated`. (This is the assertion the
  first copy did not reach, so both branches of the installed half are shown to
  discriminate.)
- **Copy 2** — R6 non-vacuity: the `See docs/WORKFLOW.md '…'` message removed from the
  installer. **KILLED:** `R6: no "See docs/WORKFLOW.md '<section>'" diagnostic was found …
  the derivation yielded nothing, so this test would assert over an empty list and prove
  nothing`. Without this, R6's derived form could have been silently empty.

### Fence regression check

`### Creating stacked increments`, counting `gh pr create`:

| extractor | unedited `main@189af66` | this feature's tip |
|---|---|---|
| bare house idiom (`agents/builder.md:87`) | **1** | **1** |
| fence-aware `sect()` | **4** | **4** |

They disagree on both trees. An assertion built on the house idiom counts inside a section
it never read — which is why `sect()` and `span()` both carry the `` /^``` /{f=!f} ``
toggle, and why M13 (a `wave` token surviving *inside* a fence) is a real kill rather than
a lucky one.

## Versioning

`VERSION` `0.63.0` → **`0.63.1`**. `docs/` is listed in `HARNESS_BODY_PROSE` and is stamped
into every target, so the installed body changed and a bump is owed. **PATCH** per
`E21-F05.plan.md` → *Versioning*: every change corrects a shipped statement that was false
or dangling; a target that upgrades gains no capability, no key, no command and no behavior
it can call. `CHANGELOG.md` carries a `### Fixed` entry, not `### Added`. No test asserts a
`VERSION` value in any form. The current value was read from this tree rather than assumed.

## Vocabulary bans

No atomicity language in `docs/WORKFLOW.md`, in the suite's prose, in `CHANGELOG.md`, in
these notes, or in any commit message on this branch. The token appears only as the literal
string R3's sweep bans and in quoted failure messages about that ban. No `wave` and no bare
`(R<n>)` inside the lane.

## Nothing was narrowed

Every item in `E21-F05.tasks.md` was completed as written. Nothing in the spec was found
unsatisfiable, and no requirement was reinterpreted to fit. Two spec items are recorded
here because they were judgement calls the spec left to the Builder:

1. **T10's note is a paragraph, not a `###` subheading.** `sect()` stops at the next
   heading of *any* level, so a subheading under `## Re-spec notes` would have placed the
   note outside its own test's extraction — the test would have passed only if it failed to
   read what it asserts. The note records the reason inline.
2. **R3's assertion is stronger than `E21-F05.tests.md` sketched it.** The contract
   described two presence checks; measurement showed that form survives the mutation it
   exists to catch, twice. The requirement's text is unchanged and the "fails today"
   property still holds (the pre-feature outcome sentence says `main`), so this is a
   strengthening within the requirement, not a change to it.

## Hand-off

Reporting to the Orchestrator for `in-review`. Not declaring `done` — that is the
Reviewer's call. No board write performed; no push; no PR.
