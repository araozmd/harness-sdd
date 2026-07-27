# E17-F01 — Reviewer verdict (round 1)

**Feature:** Per-role model selection — config schema + per-front-end agent stamping
**Branch:** `feat/E17-F01-per-role-model-selection` (uncommitted working tree)
**Verdict: REJECT** — two reproducible defects (both small, both mechanical). Everything
else is genuinely good work; the traceability and the load-bearing invariants hold up
under mutation testing. Fix P2-1 and P2-2, add the two named tests, and this is an
approve.

---

## What I reproduced (not taken from the Builder's report)

| check | result |
|---|---|
| `./init.sh` | exit 0, green |
| full `verification.test_command` (default locale, en_US.UTF-8) | **exit 1** — fails at `tests/test_fix_worktree.sh` |
| full `verification.test_command` under `LC_ALL=C` | **exit 0** — all 23 suites green, incl. 18 `test_model_routing.sh` groups |
| `tests/test_fix_worktree.sh` on a clean `main` worktree, UTF-8 | **fails identically** ⇒ PRE-EXISTING, not a regression from this feature (see INFO-1) |
| `sh -n` / `dash -n` on `harness-install.sh`, `tests/test_install.sh`, `tests/test_model_routing.sh` | all clean |
| R11 vs a real pre-feature `main` install (`--agents=claude,gemini,opencode,antigravity,codex`, all-inherit) | every **generated** artifact byte-identical (`.claude/`, `.agents/`, `opencode.json`, `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`, `.opencode/`, global `$CODEX_HOME/prompts`); no `.gemini/`, no `.codex/`, no `.harness/.opencode.stamp`, no model keys. Only `.harness/{docs/INSTALL.md, manifest.txt, harness.config.yaml, .harness-version}` differ — all intentional copied-body/version changes |
| R1+R2 convergence | the fresh-seeded `models:` block and the `migrate_config`-appended block are **byte-identical** (`cmp` clean) |
| E2E behaviour (`--agents=claude`, `architect: reasoning`, `scout: cheap`) | `architect.md` → `model: opus`, `scout.md` → `model: haiku`, `builder.md` → **no** `model:` key. Correct |
| advisory volume (6 roles × 5 front-ends, all `cheap`) | exactly **2** stderr lines (one per unaliased front-end), not 30. Readable |
| DO-NOT-TOUCH list | fully honored — `store/`, `agents/*.md`, `tools/`, this repo's `.claude/agents/*.md` untouched; no edit to `AGENT_KEYS`/`resolve_agents`/`agent_selected`/`validate_csv`/`normalize_keys`/`codex_prompts_dir`/`write_pointer`/`remove_pointer`/`remove_if_pristine` |
| `CODEX_HOME` sandboxing | suite-level `export CODEX_HOME` in both suites **and** a per-run `CODEX_HOME` on every new installer invocation. No test can reach `~/.codex` |
| permanent-suite anti-patterns | none — `test_models_changelog_entry` asserts a `CHANGELOG.md` heading (the sanctioned `tests/test_install.sh:91-97` precedent), never the `VERSION` file; no DO-NOT-TOUCH file is diffed against `main` |

### Mutation testing (does the suite actually bite?)

I mutated the installer seven ways and confirmed each is caught — this suite is **not**
decorative:

| mutation | caught by |
|---|---|
| `resolve_model` emits the literal `inherit` for the inherit tier | `FAIL: R4: ... must resolve to inherit (no key)` |
| `migrate_config` models stanza disabled (`if false`) | `FAIL: R2: upgrade did not append the models: block` |
| `models:` block stripped from the **source** `harness.config.yaml` | `FAIL: R1: fresh config has no top-level models: block` |
| OpenCode `*/*` pin guard removed | `FAIL: R10: no warning about the invalid provider/model form` |
| **deselect path regenerates one extra byte** (the highest-risk defect class) | `FAIL: R22: .gemini/agents/ left behind after deselect` |
| `.opencode.stamp` not deleted on deselect | `FAIL: R22: .opencode.stamp was not removed with opencode.json` |
| §6 never-clobber disabled (`if true`) | `FAIL: R20c: an edited opencode.json was modified by the installer` |

The R21/R22 determinism invariant is structurally sound: `emit_agent`, `gen_ag_persona`,
`gen_opencode_json`, `gen_gemini_agent`, `gen_codex_agent` are each defined **once** and
called by both the install path (§5/§5e/§5f/§6) and the deselect compare (§7). No
emission logic is duplicated into any deselect branch, and the mutation above proves the
test would catch it if it were.

---

## Findings

### P2-1 (BLOCKING) — a fresh install now creates `opencode.json` with mode `0600` (was `0644`)

**File:** `harness-install.sh` §6 (the `# ── 6. opencode.json` block), both `cp` sites.

```sh
    if [ ! -f "$TARGET/opencode.json" ]; then
      cp "$_oc_new" "$TARGET/opencode.json"      # <-- $_oc_new is a mktemp file: mode 0600
```

`$_oc_new` comes from `mktemp`, which creates `0600`. `cp` to a **non-existent**
destination copies the source's permission bits, so a fresh install now yields
`-rw-------`. Pre-feature, `gen_opencode_json "$TARGET/opencode.json"` used `cat > …`,
which creates with the shell's umask ⇒ `-rw-r--r--`.

**Reproduced side by side** (same flags, same machine):

```
main   : .rw-r--r--  opencode.json
branch : .rw-------  opencode.json
```

**Why this blocks.** It contradicts the feature's own foundation, BR1 — *"an absent
block, an empty block, and an all-`inherit` block are all behaviorally identical to the
pre-feature installer"* — and it is exactly the class of silent change the deviation-4
justification ("byte-safe, proven by the R11 diff") does **not** cover: `diff -r` and
`cmp` compare content, not mode. It also creates a **fresh-vs-upgrade divergence**: `cp`
onto an *existing* file preserves that file's mode, so an upgraded target keeps `0644`
while a fresh target gets `0600` — the same divergence class R1/R2 exist to prevent. The
repo already treats file mode as a real contract elsewhere (`tests/test_board_lock.sh`,
"R14mode board file mode (0600 / 0664) preserved across the atomic `os.replace`").
`.harness/.opencode.stamp` inherits the same `0600` for the same reason.

**What would satisfy it.** Write through the shell instead of `cp`, at **both** sites in
§6 (the create-if-absent branch and the pristine-regenerate branch):

```sh
cat "$_oc_new" > "$TARGET/opencode.json"
```

`> ` creates a new file at `0666 & ~umask` (⇒ `0644`) and preserves an existing file's
mode — byte-for-byte the pre-feature behaviour on both paths. Then add a mode assertion
to `tests/test_model_routing.sh` so this cannot regress, e.g. in a new group or inside
`test_opencode_json_restamp_rules`:

```sh
[ "$(ls -l "$_ta/opencode.json" | cut -c1-10)" = "-rw-r--r--" ] \
  || fail "R20: a fresh opencode.json must be created 0644, not the mktemp 0600"
```

(or compare `stat -f '%Lp'` / `stat -c '%a'` behind a portability guard — your call, but
assert it.)

---

### P2-2 (BLOCKING) — R5 violated: a pin whose value is the literal `inherit` reaches generated artifacts

**File:** `harness-install.sh`, `resolve_model()` — the pin branch returns `$_rm_pin`
verbatim with no `inherit` check.

**R5 (spec, absolute wording):** *"the installer … shall never write the literal string
`inherit` into any generated artifact."*

**Reproduced.** With `models.builder: reasoning` and
`pin.claude.reasoning: "inherit"` / `pin.codex.reasoning: "inherit"`:

```
.claude/agents/builder.md   ->  model: inherit
.codex/agents/builder.toml  ->  model = "inherit"
```

The `opencode` path escapes only by accident (the `*/*` guard rejects it for the wrong
reason). On `codex`, `model = "inherit"` is an unknown model id — precisely the hazard
BR3 names ("it is an error on OpenCode and unknown on Codex"). This is a plausible
operator mistake, not an exotic one: the documented tier vocabulary *includes* `inherit`,
so writing it into a `pin.` field is an easy misreading.

`test_inherit_is_omission` does not exercise the pin path, so nothing catches it.

**What would satisfy it.** In `resolve_model`, immediately after reading `_rm_pin` and
before the OpenCode format guard:

```sh
  if [ "$_rm_pin" = "inherit" ]; then
    _model_warn_once "inheritpin:$_rm_fe:$_rm_tier" \
      "⚠️  models.pin.$_rm_fe.$_rm_tier = 'inherit' is a tier name, not a model id — ignored, no model key written"
    return 0
  fi
```

and extend `tests/test_model_routing.sh::test_inherit_is_omission` (or add
`test_inherit_pin_is_rejected`) to set a `pin.claude.<tier>` and a `pin.codex.<tier>` to
`inherit` and assert the artifacts carry no model key and the run still exits 0.

---

### P3 (non-blocking, fix while you are in there) — the R11 test excludes `manifest.txt` without spec authority

**File:** `tests/test_install.sh::test_no_models_block_is_byte_identical`

```sh
diff -r -x 'harness.config.yaml' -x 'manifest.txt' -x '__pycache__' "$_ta" "$_tb"
```

R11 permits exactly one exclusion — `.harness/harness.config.yaml`. I checked: `TA` and
`TB` produce **identical** `manifest.txt` files, so the exclusion hides nothing today —
it just permanently blinds the strongest test in the suite to any future leak of model
state into the manifest. Drop `-x 'manifest.txt'` (keep `-x '__pycache__'`, which is a
genuine python runtime artifact). If it turns out something in the manifest legitimately
varies, say so in a comment rather than excluding the file silently.

---

### INFO-1 (pre-existing, NOT this feature, do not fix here) — `tests/test_fix_worktree.sh` fails under a UTF-8 locale

Confirmed the Builder's report: `FAIL: expected failure: create E99-F107 Bad-Slug`.
It reproduces **identically on a clean `main` worktree** and passes under `LC_ALL=C`, so
it is not a regression and does not affect this verdict.

Cause: `tools/fix-worktree.sh:19`

```sh
    ''|*[!a-z0-9-]*|-*|*-) die "invalid slug: $FIX_SLUG" ;;
```

Under `LANG=en_US.UTF-8` the bracket range collates case-insensitively, so `Bad-Slug` is
wrongly accepted. Seed as an **E99 fix** (`[!a-zA-Z0-9-]`, or an explicit `LC_ALL=C` in
the helper). Note that `verification.test_command` is therefore **red in a default
developer shell** today — worth fixing soon regardless of this feature.

### INFO-2 (pre-existing) — deselect prints bare relative paths to stdout

`remove_if_pristine` `printf`s the removed path to **stdout**, so a deselect now emits 12
bare lines like `.gemini/agents/architect.md` / `.codex/agents/builder.toml` amid the
`✅`/`ℹ️` output. `main` already does this for antigravity's 13 files, so this feature
amplifies rather than introduces it — out of scope here, but a candidate for an E99
cleanup (route it to stderr, or aggregate as the `remove_owned` branch does).

---

## Traceability — per-R-id status

All 25 rows in `E17-F01.tests.md` map to a test that exists, runs, and (per the mutation
matrix) actually bites.

| R-id | test | status |
|---|---|---|
| R1 | `test_install.sh::test_models_block_seeded` | ✅ verified (mutation-caught) |
| R2 | `test_install.sh::test_models_block_migrated` | ✅ verified (mutation-caught); block byte-identical to the fresh seed |
| R3 | `test_install.sh::test_models_block_idempotent` | ✅ verified, incl. the trailing-comment case |
| R4 | `test_model_routing.sh::test_tier_resolution_order` | ✅ verified (mutation-caught) |
| R5 | `test_model_routing.sh::test_inherit_is_omission` | ⚠️ **partial — see P2-2.** The inherit-tier path is correct and covered; the **pin** path is not covered and is violated |
| R6 | `::test_builtin_tier_aliases` | ✅ verified |
| R7 | `::test_unpinned_codex_opencode_omits` | ✅ verified; de-dup to exactly one line per (front-end, tier) confirmed live |
| R8 | `::test_pin_overrides_verbatim` | ✅ verified |
| R9 | `::test_unknown_tier_warns_and_inherits` | ✅ verified (stderr, exit 0) |
| R10 | `::test_opencode_pin_format_guard` | ✅ verified (mutation-caught) |
| R11 | `test_install.sh::test_no_models_block_is_byte_identical` | ✅ content-verified independently against a real `main` install. ⚠️ over-excludes `manifest.txt` (P3); **does not cover file mode** — which is how P2-1 slipped through |
| R12 | `test_install.sh::test_claude_model_frontmatter` | ✅ verified live |
| R13 | `::test_antigravity_model_frontmatter` | ✅ verified |
| R14 | `::test_opencode_json_model_member` | ✅ verified |
| R15 | `::test_gemini_agent_files` | ✅ verified (all six roles, pointer body, <30 lines) |
| R16 | `::test_codex_agent_files_project_local` | ✅ verified; asserts both `$CODEX_HOME/agents` **and** the per-run `ch/agents` are absent |
| R17 | `::test_new_trees_conditional` | ✅ verified (all-inherit **and** unpinned-tier cases) |
| R18 | `::test_selection_gating` + `test_install.sh::test_claude_model_frontmatter` | ✅ verified |
| R19 | `::test_restamp_after_config_change` | ✅ verified, one model key per role on all five artifacts |
| R20 | `::test_opencode_json_restamp_rules` | ✅ verified (a/b/c) (mutation-caught) |
| R21 | `::test_stamping_is_deterministic` | ✅ verified (content). ⚠️ compares bytes only, not mode |
| R22 | `::test_deselect_reclaims_stamped` | ✅ verified (mutation-caught, twice) |
| R23 | `::test_deselect_preserves_user_edits` | ✅ verified, incl. "pristine siblings still reclaimed" |
| R24 | `test_install.sh::test_models_docs_and_manifest` | ✅ verified; asserts the **installed** `.harness/docs/INSTALL.md`, not just the source |
| R25 | `test_install.sh::test_models_changelog_entry` | ✅ verified; `VERSION` 0.37.0 → 0.38.0 (MINOR), `CHANGELOG.md` `## [0.38.0]` present |

## The Builder's four declared deviations — assessment

1. **R5 test scoping to the five generated artifacts.** **Justified.** `.harness/` is a
   verbatim copy of the source body, and R5 constrains what the installer *writes*, not
   what it *copies*. The chosen scope is the correct contract. Note, however, that P2-2
   is a leak **inside** that correct scope — the scoping is right, the coverage within it
   is incomplete.
2. **R11 block-less config probe.** **Justified and a genuine strengthening.** The
   `diff -r` alone only proves seeding is inert (because `migrate_config` re-seeds before
   §5); extracting `_cfg_models_value` into a probe is the only way to exercise a truly
   block-less config, and it reuses the established `tui_capable` probe idiom.
3. **`.opencode.stamp` retained when the file was user-edited.** **Justified and strictly
   safer.** I walked the state machine: the stamp is only ever a *comparison reference*,
   never a source of truth for what to write, so keeping stale-but-real bytes can only
   ever make a later reclaim *more* correct, never wrongly delete. Deleting it would
   discard information about a body the installer genuinely generated.
4. **§6 regenerating a pristine `opencode.json`.** **Justified in principle** (R20
   requires it, and the content is byte-safe — I verified the regenerated body is
   identical to `main`'s on an unconfigured target) **but this is the deviation that
   introduced P2-1.** "Byte-safe" was established with `diff`/`cmp`, which do not compare
   permissions. Fix the write method and the deviation stands.

## Other checks

- **Cross-file consistency:** the six `MODEL_ROLES` match `HARNESS_CLAUDE_SHIMS`,
  `ag_personas`, and the six `agents/<role>.md` bodies exactly. No `agents/*.md` contract
  is invoked or contradicted — the feature is entirely installer-side config→artifact
  stamping, and the spec correctly scopes out the host-session model.
- **ADR citation:** `specs/adr/` exists and the spec carries an
  `## Architecture alignment` section stating **ADRs touched: none** with a one-line
  justification. Passes.
- **Docs:** `docs/INSTALL.md` documents the block, the tier vocabulary, the built-in
  table, both pin rules (`provider/model` and bare id), the `agy >= 1.1.5` floor, where
  each value lands, the `opencode.json` re-stamp contract, and the `models.orchestrator`
  host-session caveat. Thorough.
- **Asymmetric deselect** (operator edits `models:` then deselects without re-installing):
  verified live — the pristine siblings are reclaimed and only the affected file is left
  in place with the correct warning. Matches the plan's documented, accepted degradation.
- **Install output readability:** confirmed at most one advisory line per (front-end,
  tier), exactly as the test contract's behavioural check requires.

## To get to approve

1. Fix **P2-1** (`cp` → `cat >` at both §6 sites) **+ add the mode assertion**.
2. Fix **P2-2** (reject an `inherit` pin in `resolve_model`) **+ extend the R5 test**.
3. Drop `-x 'manifest.txt'` from the R11 diff (**P3**).
4. No `VERSION` re-bump needed — 0.38.0 already covers this feature; just keep the
   `CHANGELOG.md` entry accurate if the pin behaviour wording changes.
5. Re-run the full `verification.test_command` (`LC_ALL=C` until INFO-1 is fixed
   separately) and hand back for round 2.

---

# E17-F01 — Reviewer verdict (round 2)

**Verdict: APPROVE.** All three round-1 findings are fixed and each fix is
mutation-proved. Re-verified independently, not taken from the Builder's report.

| check | result |
|---|---|
| `./init.sh` | exit 0 |
| full `verification.test_command`, `LC_ALL=C` | **exit 0**, 478 `ok -` assertions, 23 suites |
| full chain, `LC_ALL=en_US.UTF-8` | exit 1 at `tests/test_fix_worktree.sh` — INFO-1, **reproduced identically on a clean `main` worktree**, not this feature |
| `sh -n` + `dash -n` (installer, both suites) | clean |

**P2-1 fixed.** Both §6 sites are `cat "$_oc_new" > …`. Fresh install → `-rw-r--r--`;
`main`-installed then branch-upgraded → `-rw-r--r--`; fresh branch → `-rw-r--r--`.
The umask-independent reference-file assertion (`: > ref`) is the **correct** choice, not a
weakening: at `umask 002` a real install produces `-rw-rw-r--`, so the literal
`-rw-r--r--` I suggested in round 1 would have been a false failure. Mutation
(site (a) → `cp`) is caught at `umask 022` **and** `umask 002`. Suite passes at umask
002/027/077.

**P2-2 fixed.** The `inherit` guard sits before the OpenCode format guard and `return 0`s
with no stdout. Live, all five front-ends pinned to `"inherit"`: zero model keys, zero
literal `inherit` in any generated artifact, 5 advisory lines for 30 resolutions, exit 0;
`scout` still resolves (`opus`/`pro`/`gpt-5-mini`/…), proving omission rather than a dead
run. Mutations *disable-guard* and *fall-through-to-alias* are both caught.

**P3 fixed.** `-x 'manifest.txt'` gone; R11 green with only `harness.config.yaml` +
`__pycache__` excluded.

**Regression re-checks (all re-run after the round-2 edits).** R21/R22 shared emitters
still single-definition and shared by install + deselect — three fresh mutations
(gemini deselect drift, codex deselect drift, stamp not removed) all caught; R21
non-determinism mutation caught. R11 vs a `main` worktree: 111 paths, **identical modes
and paths**, and the only content differences are `.harness/{.harness-version,
docs/INSTALL.md, harness.config.yaml, manifest.txt}` — all copied-body/version files.
R5 tier-path mutation caught. R20/R23 live: an edited `opencode.json` survives install
*and* deselect byte-for-byte, with the correct warnings.

**Docs/CHANGELOG edits** are accurate and in scope: the "written verbatim" claim now
carries the `"inherit"` exception and "the only value check" became "the only two value
checks", matching the implementation.

## Non-blocking nits (fix opportunistically, not a re-review)

1. `harness-install.sh:1849` — the §6 comment says the mode contract is
   "Asserted by tests/test_model_routing.sh::test_opencode_json_restamp_rules"; the mode
   assertions actually live in `test_opencode_json_file_mode`. Stale pointer.
2. `E17-F01.tests.md`, "R11 — the universality invariant" prose still says to diff
   "excluding `.harness/harness.config.yaml` **and** `.harness/manifest.txt`". The
   implemented test is now stricter (P3). Contract prose should be tightened to match.
3. Reverting §6 site (b) to `cp` is *not* caught by the suite — correctly so: that
   destination always exists, and `cp` preserves an existing file's mode, so it is
   mode-equivalent. Noted only so nobody mistakes it for a coverage hole.
4. INFO-1 (`tools/fix-worktree.sh:19` UTF-8 collation) and INFO-2 (deselect prints bare
   paths to stdout) remain open, both pre-existing — seed as E99 fixes.

All 25 R-ids have a test that exists, passes, and bites under mutation. Recommend the
Orchestrator set `E17-F01` to `done` and proceed to PR.
