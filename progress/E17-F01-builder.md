# E17-F01 — Builder report

**Feature:** Per-role model selection — config schema + per-front-end agent stamping
**Status entering:** `in-progress` (human-approved; confirmed via `tools/next-task.mjs`
→ `route builder for E17-F01 at status in-progress`).
**Scope built:** FULL — all five front-ends, T1–T25 (the human chose one-shot over the
plan's "Recommended split", so T14–T18 are implemented, not deferred).
**Branch:** `feat/E17-F01-per-role-model-selection`
**Backend:** `execution.builder.backend: in-session` (Loop A).

---

## Tasks completed

Every task in `E17-F01.tasks.md` is ticked. All 25 rows in `E17-F01.tests.md` are ✅.

| Task | R-ids | What landed |
|---|---|---|
| T1 | R1 | `models:` block appended to `harness.config.yaml` (fresh-install source): `default: inherit`, one `inherit` line per role, commented `pin.<front-end>.<tier>` examples. |
| T2 | R2, R3 | `migrate_config` gained a `models:` stanza after `fix_lane`: presence check `^models:[[:space:]]*(#.*)?$`, appends the **byte-identical** block at EOF when absent. Both halves of the config ship together. |
| T3 | R4, R8 | `_cfg_models_value <file> <key>` beside `_cfg_telemetry_log`. Section-scoped `awk`; dotted keys have each `.` rewritten to `[.]` so `pin.codex.cheap` matches literally. Returns empty for a missing file. |
| T4 | R4, R9 | `MODEL_ROLES` + `model_tier <role>`: `models.<role>` → `models.default` → `inherit`; unknown tier warns once naming role+value, resolves `inherit`, exit 0. |
| T5 | R5–R8, R10 | `model_alias` (built-in floating-alias table) + `resolve_model <front-end> <role>`. Order: tier → pin (verbatim, wins) → alias → omission. `inherit` ⇒ empty. OpenCode `provider/model` guard. All diagnostics on **stderr**, de-duplicated to one line per (front-end, tier) via a run-scoped `MODEL_DIAG` ledger file (needed because `resolve_model` runs inside `$(...)` subshells). |
| T6 | R17, R18 | `models_any <front-end>`. |
| T7 | R12, R19, R21 | `emit_agent` emits `model:` as the **fourth, fixed-position** frontmatter key. |
| T8 | R13, R19, R21 | `gen_ag_persona` emits `model:` after `description:`. Function not forked — install and deselect share it. |
| T9 | R14, R21 | `gen_opencode_json` interpolates a `"model": "<v>", ` member before `"prompt"` per role. Heredoc switched `<<'EOF'` → `<<EOF` with `\$schema` escaped; with no models the output is byte-for-byte what it always was. |
| T10 | R20 | §6 reworked: create-if-absent unchanged; an existing file is regenerated **only** when byte-identical to `.harness/.opencode.stamp` or to a freshly generated **model-free** body, else left untouched with a stderr warning. Stamp written iff the body carries a model key; deleted when it does not. The stamp is left alone when the file was user-edited. |
| T11 | R22, R23 | §7 `opencode` deselect compares the stamp first, then a fresh body; removal deletes the stamp too. |
| T12 | R21, R22 | Verified: the §7 `antigravity` case still reclaims through `gen_ag_persona`. **No emission logic was duplicated into any deselect branch** — every artifact is emitted from exactly one hoisted function. |
| T13 | R11 | Verified empirically (see below), not assumed. |
| T14 | R15 | `gen_gemini_agent <role> <desc> <dest>` — frontmatter `name`/`description`/(`model`), pointer body at `.harness/agents/<role>.md`, never a duplicated role body. |
| T15 | R16 | `gen_codex_agent <role> <desc> <dest>` — TOML `name`/`description`/(`model`)/`instructions` pointer. |
| T16 | R15–R18 | New §5e (`gemini`) and §5f (`codex`) install blocks, each gated `agent_selected <key> && models_any <key>`. Codex writes **inside `$TARGET` only**. |
| T17 | R22, R23 | §7 `gemini` and `codex` cases extended with `remove_if_pristine` per role + `rmdir` (never `rm -rf`). The GLOBAL codex prompt reclamation and the shared-`GEMINI.md` rule are untouched. |
| T18 | R17 | Verified: a selected `gemini`/`codex` with everything on `inherit` (or unpinned) creates neither directory. |
| T19 | R24 | Manifest heredoc gained a `MODEL ROUTING` section listing `.gemini/agents/*`, `.codex/agents/*`, `.harness/.opencode.stamp`; the pre-existing `AGENT SELECTION` paragraph now names `codex`. |
| T20 | R24 | `docs/INSTALL.md`: layout tree + a full "Per-role model routing (`models:`) — opt-in" section (tier vocabulary, built-in table, pin rules incl. `provider/model` and bare-id, `agy >= 1.1.5` floor, where values land, the `opencode.json` re-stamp contract, and the host-session caveat for `models.orchestrator`). |
| T21 | R25 | `VERSION` 0.37.0 → **0.38.0** (SemVer MINOR) + `CHANGELOG.md` `## [0.38.0]` entry. |
| T22 | R1–R3, R11, R12, R18, R24, R25 | Installer-wiring assertions added to `tests/test_install.sh` **in this change**: `test_models_block_seeded`, `test_models_block_migrated`, `test_models_block_idempotent`, `test_no_models_block_is_byte_identical`, `test_claude_model_frontmatter`, `test_models_docs_and_manifest`, `test_models_changelog_entry`. Every installer invocation sandboxes `CODEX_HOME`. |
| T23 | R4–R23 | New `tests/test_model_routing.sh` — 18 groups, one `pass` line per R-id group. |
| T24 | R24 | `sh tests/test_model_routing.sh` appended to `verification.test_command` + its trailing comment. |
| T25 | — | Full chain run green (below). |

### Files touched (exactly the plan's "Files to change" list)

`harness.config.yaml`, `harness-install.sh`, `docs/INSTALL.md`, `tests/test_install.sh`,
`tests/test_model_routing.sh` (new), `VERSION`, `CHANGELOG.md`, plus the feature's own
`E17-F01.tasks.md` / `E17-F01.tests.md` checkboxes and this report.

**DO NOT TOUCH honored.** No change to `store/tasks.schema.json`, any `agents/*.md`,
`tools/next-task.mjs`, `AGENT_KEYS`/`resolve_agents`/`agent_selected`/`validate_csv`/
`normalize_keys`/`.harness/.agents`, `codex_prompts_dir` or §5d's global prompt glue,
`write_pointer`/`remove_pointer`, `remove_if_pristine`'s byte-compare contract (it is
**called** for the new artifacts, never modified), any existing test assertion (added
only), or this repo's own `.claude/agents/*.md`.

---

## Verification (observed, not claimed)

### 1. `./init.sh`

```
── harness-sdd init ──────────────────────────────
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (specs/adr/ present)
ℹ️  no project-specific checks (.harness/init.project.sh absent)
──────────────────────────────────────────────────
✅ environment ready — agents may proceed
```

### 2. New suite — `sh tests/test_model_routing.sh`

```
ok - tier resolves role → models.default → inherit (R4)
ok - inherit compiles to key omission; the literal string is never generated (R5)
ok - built-in floating aliases for claude/antigravity/gemini; no harness-frozen model id (R6)
ok - unpinned codex/opencode omit the key and advise exactly once per (front-end, tier) (R7)
ok - models.pin.<front-end>.<tier> overrides the alias and is written verbatim (R8)
ok - unknown tier warns, resolves as inherit, exits 0 (R9)
ok - an opencode pin without '/' warns and never reaches opencode.json (R10)
ok - antigravity personas carry model: beside description (R13)
ok - opencode agent.<role> carries a "model" member (R14)
ok - gemini .gemini/agents/<role>.md created for all six roles with a pointer body (R15)
ok - codex .codex/agents/<role>.toml is project-local; $CODEX_HOME is never touched (R16)
ok - no resolvable value ⇒ .gemini/agents/ and .codex/agents/ are never created (R17)
ok - an unselected front-end is never stamped, even with a full models: block (R18)
ok - a config change re-stamps every artifact, exactly one model key per role (R19)
ok - opencode.json: pristine ⇒ regenerated, stamped ⇒ re-stamped, edited ⇒ untouched + warning (R20)
ok - two runs with an unchanged config produce byte-identical stamped artifacts (R21)
ok - deselect reclaims every stamped artifact and prunes the harness-created dirs (R22)
ok - an edited stamped artifact survives deselection with a warning (R23)
All model-routing tests passed.
```

### 3. Installer suite — new groups (tail of `sh tests/test_install.sh`)

```
ok - models: block seeded on fresh install, appended on upgrade, idempotent (R1, R2, R3)
ok - no/all-inherit models: block leaves the generated tree byte-identical, no new dirs (R11)
ok - claude .claude/agents/<role>.md carries model: beside name/description/tools; unselected front-ends untouched (R12, R18)
ok - manifest.txt + docs/INSTALL.md document model routing; new suite registered; CHANGELOG entry present (R24, R25)
All install tests passed.
```

### 4. Full `verification.test_command` (all 23 suites)

```
FULL CHAIN EXIT=0
```

Per-suite confirmation:

```
1 install OK        2 umbrella OK    3 cascade OK     4 inception OK
5 reviewer OK       6 telemetry OK   7 mirror OK      8 epic OK
9 sdd_plan OK      10 sdd_drill OK  11 sdd_fix OK    12 adr OK
13 drift OK        14 doc-critic OK 15 ownership OK  16 board_lock OK
17 adr_citation OK 18 fix_worktree OK (see caveat)   19 fix_parallel OK
20 deps OK         21 rationale OK  22 next_task OK  23 model_routing OK
```

### 5. R11 sanity check — pre-feature `main` vs this branch, no `models:` configured

Installed with `--agents=claude,gemini,opencode,antigravity,codex` into two scratch
targets, one from a `git worktree` of `main`, one from this branch:

```
=== R11 (generated tree only; .harness/docs is a copied body, changed intentionally for R24) ===
GENERATED TREE BYTE-IDENTICAL ✅

absent(ok): .gemini
absent(ok): .codex
absent(ok): .harness/.opencode.stamp
absent(ok): claude model:
absent(ok): opencode model
```

The only non-identical file across the whole tree is `.harness/docs/INSTALL.md`, which is
a **copied body file changed on purpose for R24** — not a generated artifact. Every
generated artifact (`.claude/agents/*`, `.agents/**`, `opencode.json`, the entrypoint
blocks, `.opencode/command/*`, the global codex prompts) is byte-for-byte unchanged.

Fresh-vs-upgraded convergence (both halves of the config, `fix_lane`'s 2-file precedent):

```
=== fresh-vs-upgraded config convergence ===
MIGRATED BLOCK == SEEDED BLOCK ✅
```

### 6. POSIX portability

`sh -n harness-install.sh`, `dash -n harness-install.sh` both clean. A full
install → configure tiers+pin → re-stamp → deselect cycle was also driven end to end
under `/bin/dash` with identical results (no bashisms introduced).

---

## Deviations from the plan, and why

1. **R5 test scope.** `E17-F01.tests.md` suggested asserting `grep -rn 'inherit' "$T"`
   matches nothing outside `.harness/harness.config.yaml`, `.harness/docs/` and
   `.harness/specs/`. In reality `.harness/agents/*.md`, `.harness/tools/tasks-lock.py`,
   `.harness/init.sh` and `.harness/manifest.txt` also legitimately contain the word
   "inherit" in prose/code. Those are **copied body files, not generated artifacts**, and
   R5 constrains what the installer *writes*. The test therefore scopes the search to the
   five generated agent-definition artifacts (`.claude/agents`, `.agents/agents`,
   `.gemini/agents`, `.codex/agents`, `opencode.json`), which is the actual contract. The
   reason is documented inline in the test.

2. **R11 test — the genuinely block-less config.** The tests file asked to strip the
   `models:` block from `$TB` and diff `$TA` vs `$TB`. That still runs, but note that
   `migrate_config` re-seeds the block at §2, **before** any stamping at §5 — so on its
   own that diff only proves seeding is inert (still valuable). To actually exercise a
   config with **no** `models:` block, the test additionally extracts `_cfg_models_value`
   into a probe script (the existing `tui_capable` probe idiom, `test_install.sh`) and
   asserts it returns empty ⇒ `inherit` ⇒ omission. Both checks are in
   `test_no_models_block_is_byte_identical`.

3. **`.opencode.stamp` is not deleted when the file is user-edited.** T10 says "delete a
   stale stamp otherwise". Implemented as: refresh/delete the stamp only on a run that
   actually **wrote** `opencode.json`. If the file is user-edited (we wrote nothing), the
   stamp is left alone rather than destroyed — deleting it would discard information
   about a body we really did generate, and it can never cause a wrong removal because a
   deselect compares the *on-disk* file against that stamp. Strictly safer, same
   observable contract.

4. **§6 now regenerates a pristine `opencode.json`.** Pre-feature the installer *never*
   touched an existing `opencode.json` (info: "left untouched"). R20 requires re-stamping
   a pristine one, so a plain re-run with no `models:` block now rewrites the file with
   byte-identical content. This is required by R20 and is byte-safe (proven by the R11
   diff above); the "left untouched + warn" path is preserved for any file that is not
   byte-identical to a harness-generated body.

## Pre-existing issue found (NOT caused by this change, NOT fixed here)

`tests/test_fix_worktree.sh` fails under a UTF-8 locale on this machine:

```
FAIL: expected failure: create E99-F107 Bad-Slug
```

Cause: `tools/fix-worktree.sh:19` guards the slug with `*[!a-z0-9-]*`, and under
`LANG=en_US.UTF-8` that bracket range collates case-insensitively on this shell, so
`Bad-Slug` is wrongly accepted. It reproduces **identically on a clean `main` worktree**,
and passes under `LC_ALL=C`. `tools/fix-worktree.sh` is not in this feature's
"Files to change" list, so per the Builder contract I recorded it here rather than
improvising a fix outside the spec. Suggested follow-up: seed it as an E99 fix
(`[!a-zA-Z0-9-]` or an explicit `LC_ALL=C` in the helper). The full chain above was run
with `LC_ALL=C` to get a clean signal; every other suite passes under both locales.

## Hand-off

All tasks ticked, self-check green. Reporting to the Orchestrator for `in-review`.
Not declaring `done` — that is the Reviewer's call.

---

# E17-F01 — Builder report, ROUND 2 (Reviewer REJECT → fixes)

**Entering status:** `in-progress` (confirmed in `state/tasks.json`: `E17-F01 in-progress
sdd:true`). Worklist this round is `progress/E17-F01-review.md`, not `tasks.md` (all 25
tasks stayed ticked; the spec contract is unchanged).

**Scope:** exactly the three findings. Nothing that passed round 1 was re-architected;
the R21/R22 shared-emitter determinism invariant is untouched — no emission logic was
duplicated, and `emit_agent` / `gen_ag_persona` / `gen_opencode_json` / `gen_gemini_agent`
/ `gen_codex_agent` are still each defined once and shared by install + deselect.

## P2-1 (blocking) — `opencode.json` fresh-install mode regressed 0644 → 0600 — FIXED

`harness-install.sh` §6, both write sites: `cp "$_oc_new" …` → `cat "$_oc_new" > …`.
`$_oc_new` is a `mktemp` file (0600) and `cp` to a **non-existent** destination copies the
source's permission bits; `>` creates at `0666 & ~umask` and preserves an existing file's
mode, which is byte-for-byte the pre-feature `gen_opencode_json "$TARGET/opencode.json"`
behaviour on **both** paths. A comment at the top of §6 records why `cp` must never come
back.

**New test — `tests/test_model_routing.sh::test_opencode_json_file_mode`** (its own `pass`
line, R20/R11). Three cases: (a) fresh create with no `models:` configured, (b) fresh
create of a *stamped* body plus `.harness/.opencode.stamp`, (c) the pristine-regenerate
branch must preserve an operator's `chmod 640`. The expectation is not the frozen literal
`-rw-r--r--` but the mode of a reference file the test itself creates with `: > ref` — the
same `>` redirect the pre-feature installer used — so the assertion is umask-independent
rather than passing only under `umask 022`. Portability: `ls -ld | cut -c1-10` (drops
macOS's xattr `@`/`+`), not `stat`, whose flags differ between BSD and GNU.

**Mutation-proved.** Reverting site (a) to `cp` in a sandbox copy:
`FAIL: R20mode: a fresh opencode.json is -rw-------, expected -rw-r--r-- (mktemp's 0600
leaked through a cp)`.

## P2-2 (blocking) — R5 violated on the pin path — FIXED

`resolve_model` now checks the pin **before** the OpenCode format guard, so it covers all
five front-ends:

```sh
if [ "$_rm_pin" = "inherit" ]; then
  _model_warn_once "inheritpin:$_rm_fe:$_rm_tier" \
    "⚠️  models.pin.$_rm_fe.$_rm_tier = 'inherit' is a tier name, not a model id — ignored, no model key written"
  return 0
fi
```

`return 0` with no stdout = the **same compilation as the `inherit` tier** (omission), not
a fall-through to the built-in alias — so a `pin.claude.reasoning: "inherit"` yields *no*
`model:` key, not `model: opus`.

**Test extended — `test_inherit_is_omission` now exercises the pin path on every
front-end.** New target `r5pin`: `builder` on `reasoning` with
`pin.{claude,antigravity,gemini,codex,opencode}.reasoning: "inherit"`, while `scout` is on
`cheap` with real pins so the conditional `.gemini/` and `.codex/` trees actually exist
and the builder artifacts are there to inspect. Asserts: zero model keys on all five
builder artifacts, `scout` still resolves (proving omission, not a dead run), no literal
`inherit` in any generated artifact, the advisory reaches stderr, and exit 0.

**Mutation-proved.** Disabling the guard (`if false; then`) in a sandbox copy:
`FAIL: R5pin: a pin of 'inherit' produced a model: key (claude)`.

## P3 (non-blocking) — R11 diff over-exclusion — FIXED

`tests/test_install.sh::test_no_models_block_is_byte_identical`: dropped
`-x 'manifest.txt'`. The diff is now
`diff -r -x 'harness.config.yaml' -x '__pycache__' "$_ta" "$_tb"`, with a comment stating
that R11 permits exactly one exclusion and that `manifest.txt` **must** be compared.
Suite still green, so the two manifests are indeed identical.

## Docs / CHANGELOG accuracy (the new pin rule)

`docs/INSTALL.md` said a pin is "written **verbatim**" and that the `opencode` `/` check
was "the only value check the installer makes". Both are now false, so the pin section
gained the `"inherit"` rule and the "only value check" claim became "the only **two**
value checks". `CHANGELOG.md`'s `[0.38.0]` entry got the same correction. `VERSION` stays
**0.38.0** — no re-bump, per the Reviewer.

## Files touched this round

`harness-install.sh`, `tests/test_model_routing.sh`, `tests/test_install.sh`,
`docs/INSTALL.md`, `CHANGELOG.md`, plus `E17-F01.tests.md` traceability rows and this
report. All inside the plan's "Files to change" list. **No DO-NOT-TOUCH file was touched**
— no `agents/*.md`, no `tools/`, no `store/tasks.schema.json`, no `.claude/agents/` in
this repo, no change to `AGENT_KEYS`/`resolve_agents`/`agent_selected`/`validate_csv`/
`normalize_keys`/`codex_prompts_dir`/`write_pointer`/`remove_pointer`/`remove_if_pristine`.
`tools/fix-worktree.sh` (INFO-1) was deliberately **not** touched.

---

## Verification, round 2 (observed)

### 1. `./init.sh` → exit 0

```
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (specs/adr/ present)
✅ environment ready — agents may proceed
```

### 2. Full `verification.test_command`

| run | result |
|---|---|
| `LC_ALL=C` (all 23 suites) | **exit 0** — 478 `ok -` assertions |
| default locale (`LANG=en_US.UTF-8`) | **exit 1**, at suite 18 `tests/test_fix_worktree.sh`: `FAIL: expected failure: create E99-F107 Bad-Slug` |

The default-locale failure is **INFO-1, pre-existing and not this feature**. Re-confirmed
this round on a clean `main` worktree: `test_fix_worktree.sh on clean main (UTF-8) EXIT=1`
— identical failure. Both of this feature's own suites pass under **either** locale:
`test_install.sh (UTF-8) EXIT=0`, `test_model_routing.sh (UTF-8) EXIT=0`.

`tests/test_model_routing.sh` is now **19 groups** (was 18):

```
ok - inherit compiles to key omission on the tier AND the pin path; the literal string is never generated (R5)
ok - opencode.json is written at the umask default, never mktemp's 0600; an existing mode is preserved (R20, R11)
```

POSIX: `sh -n` and `dash -n` clean on `harness-install.sh`, `tests/test_install.sh`,
`tests/test_model_routing.sh`.

### 3. R11 re-verified vs a `main` worktree — content **and file modes**

`--agents=claude,gemini,opencode,antigravity,codex`, no `models:` configured, one target
installed by a `git worktree` of `main`, one by this branch:

```
=== content diff (generated tree) ===
GENERATED TREE CONTENT: BYTE-IDENTICAL

=== mode+path listing diff, WHOLE tree (97 vs 97 entries, __pycache__ excluded) ===
>>> IDENTICAL FILE MODES AND PATHS ACROSS THE ENTIRE INSTALLED TREE <<<

opencode.json                    main=-rw-r--r--  branch=-rw-r--r--
.claude/agents/builder.md        main=-rw-r--r--  branch=-rw-r--r--
.agents/agents/builder.md        main=-rw-r--r--  branch=-rw-r--r--
CLAUDE.md / AGENTS.md            main=-rw-r--r--  branch=-rw-r--r--
.harness/.opencode.stamp         main=absent      branch=absent

codex global prompts ($CODEX_HOME): content identical + modes identical
```

The only listing delta before excluding it was `.harness/tools/__pycache__/*.pyc` — a
python runtime artifact present in the working repo's `tools/` and absent from a fresh
worktree, not an installer difference.

**Fresh-vs-upgrade convergence** (the divergence class P2-1 named) — a target installed by
`main`, then upgraded with the branch installer:

```
TA installed by MAIN, opencode.json before upgrade: -rw-r--r--
after upgrading TA with the BRANCH installer:       -rw-r--r--
a FRESH branch install (TB):                        -rw-r--r--
```

### 4. P2-2 proved end to end — a real `inherit` pin on all five front-ends

`builder: reasoning` with `pin.{claude,antigravity,gemini,codex,opencode}.reasoning:
"inherit"`; `scout: cheap` with real `pin.codex.cheap`/`pin.opencode.cheap`.

```
=== install stderr ===                                    (exit 0)
⚠️  models.pin.claude.reasoning = 'inherit' is a tier name, not a model id — ignored, no model key written
⚠️  models.pin.antigravity.reasoning = 'inherit' …
⚠️  models.pin.gemini.reasoning = 'inherit' …
⚠️  models.pin.codex.reasoning = 'inherit' …
⚠️  models.pin.opencode.reasoning = 'inherit' …
   (exactly 5 lines for 30 resolutions — de-duplication intact)

=== the literal string 'inherit' in ANY generated artifact ===
>>> NONE — R5 holds on the pin path <<<

=== builder (pinned to 'inherit' on all 5) ===
  claude      model: lines = 0        antigravity model: lines = 0
  gemini      model: lines = 0        codex       model  lines = 0
  opencode    model  members = 0

=== scout (real values) — still resolves, so this is omission, not a dead run ===
model: haiku            (claude)
model: flash            (gemini)
model: flash            (antigravity)
model = "gpt-5-mini"    (codex)
"model": "openai/gpt-5-mini"   (opencode)
```

Round 1 emitted `model: inherit` / `model = "inherit"` here; it now emits nothing.

## Hand-off

Round-2 fixes complete, self-check green. Reporting to the Orchestrator for `in-review`.
Not declaring `done` — that is the Reviewer's call.
