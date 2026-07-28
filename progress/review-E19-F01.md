---
feature: E19-F01
role: reviewer
date: 2026-07-28
branch: feat/E19-F01-agents-host
verdict: REJECT (one blocking defect — test rigor, not behavior)
pr_ready: NO (blocking fix is ~5 lines in tests/test_agents_host.sh)
---

# Reviewer verdict — E19-F01 (host detection + `--agents=host`)

**REJECT.** The implementation is correct — I could not break it. The blocker is a
**permanent-suite test that cannot fail**: `test_host_marker_rows_documented` (R8) survives
two mutations that add unverified markers, and R8 is the single guard protecting the
feature's entire reliability story. Fix that one test and this is mergeable as-is.

## Environment (real output)

`./init.sh` → exit 0:

```
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (namespaces: specs/adr)
✅ environment ready — agents may proceed
```

FULL `verification.test_command` chain (25 suites) → `CHAIN_EXIT=0`, 584 `ok` lines,
5m56s wall. Every suite printed its own "All … passed.", including
`All install tests passed.` and `All agents-host tests passed.`
`lint_command` / `typecheck_command` are empty (n/a).

## BLOCKING — B1: R8's test is mutation-blind (`tests/test_agents_host.sh:141-154`)

R8 requires: *"The marker table shall carry a row for a non-`claude` agent key **only where
that key's marker has been empirically verified**, and each such row shall record, in an
adjacent comment, **the CLI and version** it was observed on."*

The test only asserts that the **agent-key name** appears somewhere in the PROVENANCE
comment block:

```sh
printf '%s\n' "$_prov" | grep -q "^#.*$_key" \
  || fail "R8: row '$_key' has no adjacent verification comment (CLI + version)"
```

Two mutations I applied to `harness-install.sh` both **SURVIVED** (suite still exits 0):

| Mutation | Why it slips through |
|---|---|
| Add row `gemini GEMINI_CLI` to `HOST_MARKERS` with **no new provenance comment** | `gemini` already appears in the provenance block as the `NO ROW — … undetectable` note, so `grep "^#.*gemini"` matches the very comment that says gemini has *no* verified marker |
| Append `MADE_UP_VAR` to the existing `antigravity` row | the test never looks at **variable** names at all, only the leading key |

So a future change can pin an unverified marker — the exact failure the spec calls out
("getting it wrong is how a Claude Code user gets a Codex-only install") — and CI stays
green. Also, nothing checks for a version token, despite the failure message claiming
"CLI + version".

Suggested fix (keeps the same shape, ~5 lines): iterate the row's **variables**, not just
its key, require each non-`claude` variable name to appear literally in the provenance
block, and require that variable's provenance line to carry a version-shaped token
(`grep -Eq '[0-9]+\.[0-9]+'`). Re-run both mutations above to confirm they now fail.

## Non-blocking findings

- **N1 — `host_of` swallows the installer's exit status** (`tests/test_agents_host.sh:55-58`):
  `hrun … 2>/dev/null | sed -n 's/^host=//p'`. Every "undetected ⇒ `host=` is empty"
  assertion (R2, R4, R6) would also pass if the installer **crashed**. I hit this for real:
  a scratch harness that pointed `$SRC` at a nonexistent dir made `test_host_forbidden_markers`
  pass vacuously. `test_print_agents_contract` (R23) does check exit 0 + exactly two stdout
  lines, so the suite as a whole is not blind — but `host_of` should assert exit 0.
- **N2 — recorded `agy 1.1.7` vs installed `agy 1.1.8`** (`harness-install.sh:498-501`,
  `docs/INSTALL.md` marker table, `CHANGELOG.md`). Plausible auto-update between the
  Builder's run and mine, but the provenance line is a claim about a specific version;
  re-observe and correct, or note the range.
- **N3 — R15's "interactive and non-interactive alike"** is only exercised non-interactively.
  The `host` arm sits inside the override branch *before* `[ -t 0 ]`, so it is
  TTY-independent by construction, and I confirmed the TTY half of R23 by hand — but no
  automated case covers a TTY `--agents=host`.
- **N4 — weak proxies** (each passes, none would catch much): R28's
  `grep -qF 'agents=host' tests/test_install.sh` (a comment satisfies it); R27's
  `sed -n '1,60p' | grep -qF 'host'`; R30's dependency scan covers only `detect_host`, not
  `marker_present` / `precheck_baseline` / the `--print-agents` block.
- **N5 — board mirror drift.** `state/tasks.json` has E19-F01 `in-review`;
  `specs/epics/E19-single-cli-default/epic.md:54` still says `spec-ready`. Sync before merge.
- **N6 — `.tests.md` Status column is all `⬜`.** Consistent with repo practice (ticks land
  in the `done` commit), so not a defect — just do it at rollup.
- **N7 — nit:** `precheck_baseline` returns whatever `.harness/.agents` holds without
  re-validating against `AGENT_KEYS`. Pre-existing semantics, and junk keys are inert
  (`agent_selected` simply never matches), but the undetected-`host` fallback is the first
  path that turns that file's content directly into `SELECTED`.
- **N8 — nit:** `for _dh_t in $_dh_decl` (`harness-install.sh:~700`) is an unquoted expansion,
  so `HARNESS_HOST_AGENT='*'` glob-expands against `$PWD`. Harmless (it lands in the R10
  warn-and-continue path) but it makes the warning text odd.

## What I verified, and how

### 1. R22 additivity — PROVEN, three independent ways

- **Diff audit.** `git diff main --numstat harness-install.sh` = `254 9`. All **nine**
  deletions accounted for: 2 reflowed comment lines (a `resolve_agents` header line and one
  `manifest.txt` heredoc line), `_persisted="$_t/.harness/.agents"`, the 4-line inline
  `if [ -f "$_persisted" ]` baseline, and `SELECTED="$(validate_csv …)"` + its `info` line
  **moved verbatim** into the new `else` arm (re-added byte-identically modulo indentation).
  The Builder's handover says "six lines + two comments"; it is actually nine, but nothing
  is unaccounted for. `_persisted` had no other reader in `main` (`git show main:… | grep`
  → only lines 960/965/966, all inside `resolve_agents`), so dropping it is safe.
- **`precheck_baseline` is a faithful extraction.** Old and new both reduce to
  `[ -f <t>/.harness/.agents ] ? normalize_keys(cat) : normalize_keys(AGENT_KEYS)` — same
  helper, same order, same command-substitution capture. Identical for *every* pre-existing
  path, not just the common one.
- **Byte-level install comparison, `main` worktree vs branch.** Four override shapes
  (no-override, `--agents=claude`, `--agents=claude,codex`, `--agents=gemini,antigravity`),
  each under `env -i` with sandboxed `HOME`/`CODEX_HOME`: target file lists **identical**,
  `$CODEX_HOME` file lists **identical**, `.harness/.agents` **identical**. (The only diff
  was `.harness/tools/__pycache__` — a gitignored artifact of my own test runs in the source
  checkout, absent from the clean worktree.)
- **Interactive picker over a pty**, `main` vs branch, fresh dir and a `claude`-pinned
  target — pre-check state identical, and only the five real keys render (no `host` row):

  ```
  [MAIN] FRESH: [x] claude [x] gemini [x] opencode [x] antigravity [x] codex
  [BRANCH] FRESH: [x] claude [x] gemini [x] opencode [x] antigravity [x] codex
  [MAIN] PINNED: [x] claude [ ] gemini [ ] opencode [ ] antigravity [ ] codex
  [BRANCH] PINNED: [x] claude [ ] gemini [ ] opencode [ ] antigravity [ ] codex
  ```
- **Mutation:** forcing the no-TTY default to `claude` fails **both** the new R22 test and
  the pre-existing `tests/test_install.sh`.
- `tests/test_install.sh` diff is `22 0` — confirmed, no pre-existing assertion touched.

### 2. `host` never persisted, never selectable — PROVEN

`AGENT_KEYS` byte-identical (`harness-install.sh:435`). `validate_csv` byte-identical, with
exactly **one** call site (`:1180`), reachable only when `override_host_kind` returns 1
(no `host` token). Both pickers build rows from `$AGENT_KEYS`. `--agents=host,gemini`,
`gemini,host`, `"host, claude"` and `HARNESS_AGENTS=host,codex` all exit non-zero and write
nothing — including in **umbrella** mode, where the rejection fires before any child or
coordinator install lands (I checked: `find` for `.harness` after the failed cascade = empty).

Mutations caught: `host` added to `AGENT_KEYS`; `SELECTED="host"` persisted; mixed-token
classification neutered.

### 3. Marker rows — four rows justified; no forbidden ambient marker

Independently corroborated each shipped variable name against the **real binaries** on this
machine:

| Row | Marker(s) | Present in binary? | Version claimed vs installed |
|---|---|---|---|
| `claude` | `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` | set in this live session | 2.1.220 |
| `codex` | `CODEX_THREAD_ID` | 3 hits in `codex-aarch64-apple-darwin` | 0.145.0 vs **0.145.0** ✓ |
| `opencode` | `OPENCODE`, `OPENCODE_PID` | both present | 1.18.5 vs **1.18.5** ✓ |
| `antigravity` | `ANTIGRAVITY_AGENT`, `ANTIGRAVITY_CONVERSATION_ID` | both present in `agy` | 1.1.7 vs **1.1.8** (N2) |
| `gemini` | none | gemini CLI not installed here — consistent with the "no row" claim | — |

No forbidden marker: table body contains no `CODEX_HOME`, no `HOME`, no `TERM_PROGRAM`, no
`*_API_KEY`. This matters concretely — my live shell exports `GEMINI_API_KEY`,
`OPENCODE_API_KEY`, `TERM_PROGRAM` **and** `CODEX_COMPANION_SESSION_ID` (set to the *Claude
Code* session id), and `tests/test_install.sh:17` exports `CODEX_HOME` suite-wide.
**Mutation:** adding `CODEX_HOME` to the `codex` row is caught —
`FAIL: R6: the ambient variable CODEX_HOME acted as a marker (resolved 'codex')`.

Multiple markers ⇒ undetected, not a tie-break. **Mutation:** relaxing `-eq 1` to `-ge 1`
is caught (`R5: competing markers did not resolve to undetected (got: host=claude)`), and
the diagnostic goes to stderr only.

### 4. Asymmetric fallback R13/R14 — PROVEN

The anti-widening test is genuine, not a tautology. **Mutation:** replacing the undetected
fallback `SELECTED="$(precheck_baseline "$_t")"` with `normalize_keys "$AGENT_KEYS"` →
`FAIL: R14: an undetected host run WIDENED a claude-only install`. The test asserts both
`.harness/.agents` == exactly `claude` **and** that `GEMINI.md` / `opencode.json` / `.agents/`
were never created. **Mutation:** narrowing the fresh case to `claude` → `FAIL: R13`.
Legacy shape (install present, `.agents` deleted) ⇒ ALL, also asserted.

### 5. Cross-target codex safety — intact

The `PRIOR_AGENTS` block (incl. `grep -vx codex`) and the whole E18-F01 ledger surface
(`_owners_file` / `_owners_live` / `_owners_claim` / `_owners_release` / `_is_pr_loop_cmd`,
§7 / §7b reclamation) are **byte-identical to `main`** — no diff hunk touches them.
Mutations caught bidirectionally:

- drop `grep -vx codex` → `FAIL: R19`
- let a **fresh** install claim prior codex ownership → `FAIL: R20: a fresh host install
  deleted the .sdd-pr-loop.owners ledger`
- defeat the pristine `cmp -s` → `FAIL: R21: a hand-edited global prompt was destroyed`
- never reclaim → `FAIL: R21: a byte-pristine deselected global prompt was not reclaimed`

### 6. Test hygiene — clean

`tests/test_agents_host.sh` is wired into `verification.test_command`
(`harness.config.yaml:150`). No frozen `VERSION` (R31 compares parsed MAJOR/MINOR). No
`git diff … main`. Every installer invocation goes through the single `hrun` gateway under
`env -i` with sandboxed `HOME` + `CODEX_HOME`; the new `tests/test_install.sh` block does
the same inline.

### 7. Behavioral checks (the `.tests.md` "Reviewer, by hand" list) — all pass

From **this live Claude Code session**, with the real ambient environment (which includes
`GEMINI_API_KEY`, `OPENCODE_API_KEY`, `TERM_PROGRAM`, `CODEX_COMPANION_SESSION_ID`):

```
$ CODEX_HOME=<sandbox> ./harness-install.sh --print-agents <scratch>
host=claude
baseline=antigravity claude codex gemini opencode
exit=0                      (target file list unchanged)

$ env -i … ./harness-install.sh --print-agents <scratch>     # plain, no CLI
host=
baseline=antigravity claude codex gemini opencode

$ CODEX_HOME=<sandbox> ./harness-install.sh --agents=host <scratch>
   agents: host detected — selecting 'claude' only
scratch/  ->  .claude  .gitignore  .harness  AGENTS.md  CLAUDE.md
.agents: claude          sandboxed CODEX_HOME: 1 entry (dir only)
real ~/.codex/prompts: untouched
```

Also verified by hand (not covered by the suite): `--print-agents` **on a TTY** (via a pty),
fresh dir and installed target — two lines, exit 0, nothing written either time. And
`--agents=host` under `--umbrella` cascades sanely (coordinator + both children each resolve
to `claude`).

## Deviations — both judged in-scope

1. **Four marker rows instead of one.** Justified. R8 permits a row wherever the marker is
   empirically verified; the spec's "one row is an acceptable floor" was a floor, not a cap.
   It genuinely strengthens R5 (the ambiguity case now uses two *shipped* rows,
   `CLAUDECODE` + `OPENCODE`, instead of the `HARNESS_HOST_AGENT` stand-in the `.tests.md`
   allowed for a one-row table). Provenance comments exist and name real, matching versions
   (one nit, N2). **The cost is that R8's test now has three rows to police and does not
   police them — B1.**
2. **`override_host_kind`.** Justified, not scope creep. The `.plan.md` describes exactly
   this classifier in prose (R16); factoring it out is what keeps `host` from ever entering
   `validate_csv`'s token grammar — the structural guarantee behind R17/R18 — and makes the
   mixed-token error specific instead of "unknown agent key 'host'". 22 lines, one caller.

## Traceability

All 31 R-ids map to a check that exists and passes. **30 of 31** also fail under a plausible
regression (verified by mutation for R2, R5, R6, R12, R13, R14, R16, R17, R18, R19, R20,
R21, R22, R23, R24, R25; by construction/inspection for the rest). **R8 does not** — see B1.

## To clear the reject

1. Fix B1 in `tests/test_agents_host.sh:141-154`; prove it by re-running both mutations
   listed above and showing the suite now fails.
2. N1 (assert exit 0 in `host_of`) and N5 (epic.md ↔ tasks.json status) before opening the PR.
3. N2/N3/N4/N7/N8 are your call — a one-line answer each is fine.

Nothing else needs to change. `./init.sh` + the full 25-suite chain, the `main`-vs-branch
byte comparison and the live-session behavioral checks are all green.
