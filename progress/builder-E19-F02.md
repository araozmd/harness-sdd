---
feature: E19-F02
role: builder
date: 2026-07-28
branch: feat/E19-F02-fresh-baseline
status_at_handoff: in-progress   # the Orchestrator moves this to in-review
---

# Builder hand-off — E19-F02 "Fresh-install pre-check baseline = the detected host"

## What shipped

`precheck_baseline <target>` gained the two branches the plan specifies, and `--print-agents`'
`baseline=` line was repointed at it so the diagnostic reports the new default (R6). Nothing
else in `resolve_agents` moved.

```
EXISTING INSTALL (.harness/.harness-version present)
  ├─ .harness/.agents present → that persisted selection            (R3)
  └─ no .harness/.agents      → ALL keys                            (R4)
NO existing install
  ├─ detect_host resolves     → that key ALONE, never a union       (R1)
  └─ undetected               → ALL keys                            (R2)
```

The version STAMP — not the presence of `.agents` — is the existing-install test; that is the
entire "an upgrade must not silently narrow" guarantee (R4/R9), and it is also what keeps
orphan metadata from being read as an install (E19-F01 R13).

Files touched (exactly the `.plan.md` list, plus the one deviation below):

- `harness-install.sh` — `precheck_baseline` body + comment; the header-comment line that
  claimed the interactive path pre-checks "ALL on a fresh install"; the `--print-agents`
  `baseline=` line + its comment.
- `docs/INSTALL.md` — new `### The fresh-install default` (R10) and
  `### Changing the selection later` (R11) sections; the `--print-agents` block's description
  of `baseline=`; the now-false sentence "the interactive picker still pre-checks what it
  always did".
- `tests/test_agents_host.sh` — nine new checks + three extensions.
- `VERSION` 0.40.0 → **0.41.0**; `CHANGELOG.md` entry for exactly that value.

DO NOT TOUCH honored: `HOST_MARKERS`, `marker_present`, `detect_host`, `HARNESS_HOST_AGENT`,
the `host` override branch of `resolve_agents`, `host_fallback_set` /
`host_fallback_keeps_selection`, `AGENT_KEYS`, the `PRIOR_AGENTS` block (incl. `grep -vx
codex`), §7/§7b reclamation, `remove_if_pristine`, the `_owners_*` ledger, the
no-TTY/no-override branch, `tui_select`/`toggle_select`, `AGENTS.md`, `agents/*.md`,
`store/tasks.schema.json`, `init.sh`, `tools/*`.

## Deviations from the plan — read these

**1. `--print-agents` had to be repointed (one line + comment).** The `.plan.md` states
E19-F01 pointed the diagnostic at `precheck_baseline`; it did not — F01 shipped
`baseline=%s "$(host_fallback_set "$TGT" …)"`, which is the *if-undetected fallback*. With
`--print-agents` left untouched, a fresh dir with `CLAUDECODE=1` still printed all five, so
R1's required assertion (`baseline=claude`) was unreachable and R6 ("the diagnostic reports
the new default rather than the old one") unimplementable. The `.spec.md` R6 outranks the
plan's DO-NOT-TOUCH bullet, so `baseline=` now reports `precheck_baseline`.

This is safe, and narrower than it sounds: **for every undetected target the two helpers
return the identical set** (`host_fallback_set` defers to `precheck_baseline` on an existing
install and both answer ALL otherwise), so F01's preview-matches-install regression test
(`test_print_agents_matches_host_install`, the Codex P2 from PR #70) passes **unmodified**.
The value changes only on a *detected* run, where the old number was a hypothetical — a fresh
target inside Claude Code used to advertise all five while `--agents=host` installed one.
`host_fallback_set` itself is unchanged and still owns the `--agents=host` fallback.

**2. Two pre-existing assertions in `tests/test_agents_host.sh` were updated** (nothing was
deleted; `tests/test_install.sh` is untouched at zero deletions):

- `test_print_agents_contract` case (a) expected `baseline=<all five>` for a fresh dir with
  `CLAUDECODE=1` — *the exact default this feature replaces*. It now expects
  `baseline=claude`, and a new case (a2) re-runs the same fresh dir with no marker so the
  sorted multi-key rendering that assertion also proved is still covered.
- `test_baseline_single_helper` asserted `--print-agents` computes `baseline=` through
  `host_fallback_set`; it now asserts `precheck_baseline` (deviation 1). Its other four
  assertions, including the "no inline baseline computation" guard, are unchanged.

**3. `existing_install_never_narrows` (R9) is shaped differently from the `.tests.md`
sketch.** The sketch says a no-override non-TTY re-run leaves `.harness/.agents` unchanged.
It does not — that path resolves to ALL by R5, so it *widens* a `claude,gemini` install to
five today, before and after this feature. The invariant R9 actually states is
marker-independence, so the check installs two identical targets and re-runs one with
`CLAUDECODE=1` and one without, asserting the resolved sets are identical, that `GEMINI.md`
and `CLAUDE.md` survive, and that the offered *baseline* for that install is also
marker-independent. Mutation M14 below proves it fails when a marker does leak in.

## Test coverage (all in `tests/test_agents_host.sh`)

| R-id | Check | Where |
|---|---|---|
| R1 | `test_baseline_fresh_is_host_only` — exact single-key line for `claude`, `opencode` and a declared `gemini` | new |
| R2 | `test_baseline_fresh_undetected_is_all` — no marker, and ambiguous markers, ⇒ ALL | new |
| R3 | `test_baseline_upgrade_keeps_persisted` — `gemini` install previewed under `CLAUDECODE=1` | new |
| R4, R9 | `test_baseline_legacy_upgrade_is_all` — pre-E08 shape (stamp, no `.agents`) ⇒ ALL | new (written first, per T1) |
| R5 | `test_no_tty_default_unchanged` — behavior + source: that branch assigns ALL and never consults the helper | new |
| R6 | `test_baseline_single_helper` | extended |
| R7 | `test_prior_agents_unchanged` (F01 R19 — same requirement, one copy) | label only |
| R8 | `test_baseline_fresh_removes_nothing` — `diff -r` of the whole sandboxed `$CODEX_HOME/prompts` before/after, plus the `.sdd-pr-loop.owners` claim and "no removal reported" | new |
| R9 | `test_existing_install_never_narrows` | new |
| R10 | `test_docs_document_fresh_default` — section-scoped, plus the header no longer claims the old default | new |
| R11 | `test_docs_document_retoggle_path` — section-scoped + the *installed* copy carries it | new |
| R12 | `test_suite_hygiene` (F01 R29) polices the whole file, new cases included | label only |
| R13 | `test_version_and_changelog` — MINOR floor ≥ 41 by parsed components, CHANGELOG marker file-wide | extended |

Suite discipline kept: every installer invocation goes through `hrun` (`env -i` + sandboxed
`HOME`/`CODEX_HOME`), no frozen `VERSION` literal, no DO-NOT-TOUCH file diffed against `main`,
and `ALL_KEYS` is derived from the installer's own `AGENT_KEYS` (with a non-empty guard) so no
baseline comparison can pass against an empty string. The suite was already wired into
`verification.test_command`; no new suite was added.

## Mutation proofs (every one caught)

| # | Mutation | Caught by |
|---|---|---|
| M1b | existing-install stamp gate removed (the plan's naive `.agents`-first order) | `R4/R9: a pre-E08 upgrade's baseline was narrowed by detection (got 'claude')` |
| M2 | detected host unioned with `claude` | `R1: … does not pre-check 'opencode' alone (got 'claude opencode')` |
| M3 | detection branch deleted (pre-F02 behavior) | `R23/F02 R1: line 2 is not the detected-host baseline` |
| M4 | `baseline=` reverted to `host_fallback_set` | `R1: … does not pre-check 'claude' alone (got '<all five>')` |
| M5 | no-TTY/no-override branch made to consult the helper | `R5: a no-override non-TTY run no longer persists ALL (claude)` |
| M7 | detection consulted before the existing-install branch | `R4/R9: … narrowed by detection` |
| M8 | install leaves a stray file in the shared `$CODEX_HOME/prompts` | `R8: the narrowed fresh install changed the shared codex prompts dir: Only in …/stray.md` |
| M9 | detection overrides a persisted selection (legacy case left correct) | `R3: an upgrade's baseline is not its persisted selection (got 'claude')` |
| M10 | docs drop the undetected case | `R10: the section does not state that an undetected host still pre-checks everything` |
| M11 | docs drop "a re-run also removes" | `R11: the re-toggle section does not say a re-run also applies REMOVALS` |
| M12 | header keeps the stale "ALL on a fresh install" claim | `R10: the harness-install.sh header still claims …` |
| M13 | undetected fresh falls back to `claude` | `R2: an undetected fresh target does not pre-check ALL` |
| M14 | a marker narrows a no-override re-run of an existing install | `R9: a marker changed what a no-override re-run resolved` |

All mutations were applied to a working copy and reverted from a byte backup; the suite is
green on the restored tree.

## Verification

- `./init.sh` → `✅ environment ready — agents may proceed`.
- Full `verification.test_command` (read from `harness.config.yaml`, all 25 suites):
  **`CHAIN EXIT=0`**, 593 `ok -` assertions, zero `FAIL` lines.
- `grep -ci drift harness-install.sh` → `0` (the word stays out of the installer; the code
  comments say "diverge").

## Left for the Reviewer / human

The `.tests.md` behavioral checks need a real TTY and are by hand: install interactively into
a new scratch repo from inside a Claude Code session (picker pre-checks `claude` alone, others
togglable), toggle `gemini` on and confirm `GEMINI.md` appears, re-run and confirm it
pre-checks `claude gemini`, toggle `gemini` off and confirm `GEMINI.md` is removed, and repeat
the first step from a plain terminal (all five pre-checked).

Status not changed, nothing committed, no PR — per the Builder contract.

---

# Round 2 — Reviewer REJECT (F1, F2) addressed

Both must-fixes were record-level; the Reviewer found zero behavioral defects and I changed
**no code path**. `harness-install.sh`'s three functional hunks (header comment,
`precheck_baseline`, the `baseline=` line) are byte-identical to what was reviewed; every
round-2 edit to that file is inside a comment block. No test was weakened or removed,
`tests/test_install.sh` is still absent from the diff, and `tests/test_agents_host.sh` is
still at **7 deletions** (the same three hunks reviewed in round 1) — round 2 is purely
additive there.

## F1 — the four stale comment blocks

| Was | Now |
|---|---|
| `host_fallback_set` docblock: "with two callers … `baseline=` deliberately reports THIS, **not precheck_baseline**" | states it has exactly **one** caller (the undetected `host` arm), that `baseline=` reports `precheck_baseline` per R6, and — in place of the old revert-instruction — an explicit **"DO NOT POINT IT BACK HERE"** with the reason (on a fresh *detected* target this helper answers ALL while the run installs one key), plus why nothing is lost (the two agree for every *undetected* target, orphan-metadata corner included) |
| `host_fallback_set` docblock: "both call sites are gated on `host`" | "its one call site is gated on `host`" |
| `resolve_agents` resolution-order item 2: "pre-check baseline is the persisted `.harness/.agents` if present else ALL" | the three current cases, naming the detected-host branch for a target with no existing install and why the narrowing is confined to the picker |
| *(not on the Reviewer's list — same class, found while fixing)* the comment inside the undetected `host` arm claiming "`--print-agents` reports precisely what this line resolves" | now says `baseline=` reports `precheck_baseline`, and that the two agree for every undetected target, which is the only kind that reaches that line |

### R10's assertion was widened — deliberately, and only where it is safe

The Reviewer was right that this slipped because `test_docs_document_fresh_default` reads
only `sed -n '1,60p'`. New helper `comment_block_above <literal def-line prefix>` extracts
the run of `#` lines immediately above a definition (literal prefix match, no regex escaping
of `()`), and the R10 check now also asserts:

- **`resolve_agents`' resolution-order block** names the detected host, scopes it to "no
  existing install", and still names `precheck_baseline` — **positive** assertions, which are
  what would have caught today's defect (the stale block mentioned detection nowhere) and
  which no accurate description of the current behavior can fail.
- **`host_fallback_set` has exactly one non-comment call site**, and its docblock neither
  claims "two callers"/"both call sites" nor says "not precheck_baseline". The caller claim is
  pinned to the *real count*, so a future feature that legitimately re-adds a caller trips the
  count first and updates both together.

**What I deliberately did NOT do:** a file-wide ban on the phrase "ALL on a fresh install".
That sentence is **true** of the no-TTY branch (which does stamp ALL on a fresh install), so a
file-wide ban would fire on a correct future comment about R5 — brittle, and it buys no catch
the scoped checks miss. Recorded here so the omission is a decision, not an oversight.

### Mutation proofs for the widened assertions

| # | Mutation | Caught by |
|---|---|---|
| M15 | the **exact** stale `host_fallback_set` docblock from `main` restored | `R10: the host_fallback_set docblock still claims two callers — --print-agents stopped calling it in E19-F02` |
| M15b | only the revert-instruction clause left stale ("`baseline=` deliberately reports THIS, not precheck_baseline") | `R10: … still instructs a maintainer to keep baseline= off precheck_baseline — that is the change this feature exists to make` |
| M16 | the **exact** stale `resolve_agents` item 2 restored | `R10: resolve_agents' resolution-order block does not scope the new pre-check to a target with no existing install` |
| M17 | `--print-agents` re-added as a second `host_fallback_set` caller | behaviorally caught by `R23/F02 R1`; **and**, isolated in a per-test driver, `R10: host_fallback_set has 2 non-comment call sites, expected exactly 1` |

All four applied to a byte-backed copy and reverted; suite green on the restored tree.

## F2 — the false R9 premise removed from the contract files

The correction now lives in the files that survive the merge, not only in this progress note:

- `E19-F02.tests.md:30` — the R9 Behavior cell now reads "an existing install's resolved set
  is independent of every marker — detection can never narrow an upgrade".
- `E19-F02.tests.md` sketch — rewritten to the two-target marker-independence check, with a
  blockquote recording **why** the original was wrong (a no-override **non-TTY** re-run
  resolves to ALL by R5 and widens `claude,gemini` to five, on `main` as well as this branch)
  and an explicit "do not restore the unchanged-bytes wording — a check written to it would
  fail on correct code, and asserting the widening away would contradict R5".
- `E19-F02.tasks.md` T10 — rewritten to describe the shipped check, carrying the same
  correction note. Left ticked: the task is done, as reshaped.

## Nits (non-blocking) — two taken, one is now accurate prose

- `README.md` — one sentence added to the agent-selection paragraph: a first interactive
  install pre-checks the CLI you are in, all five when undetected, others one keystroke away.
- `docs/INSTALL.md` `--print-agents` — the "cannot disagree with the install" overstatement is
  gone. It now says the preview cannot disagree with **what the picker will offer**, plus a
  short paragraph spelling out the one case where `baseline=` and a *detected* `--agents=host`
  run differ (`host=claude` / `baseline=gemini` on a `gemini` install read from Claude Code).
- `test_docs_document_retoggle_path`'s `grep -qi 'remove\|deselect'` left as is — the Reviewer
  confirmed it catches both deletion and semantic inversion, and tightening it to a phrase
  would make it brittle against legitimate rewording.

## Verification (round 2, real output)

```
$ grep -ci 'drift' harness-install.sh
0

$ ./init.sh
✅ ADR citations resolve (namespaces: specs/adr)
ℹ️  no project-specific checks (.harness/init.project.sh absent)
──────────────────────────────────────────────────
✅ environment ready — agents may proceed

$ sh -c "<verification.test_command, read from harness.config.yaml>"
CHAIN EXIT=0
suites in chain: 25
ok- assertions: 593
FAIL lines: 0
...
All pr-loop tests passed.
ok - F02 baseline_legacy_upgrade_is_all: a pre-E08 upgrade pre-checks ALL, detection ignored (F02 R4, R9)
ok - F02 baseline_fresh_is_host_only: a fresh install pre-checks the detected host ALONE (F02 R1)
ok - F02 baseline_fresh_undetected_is_all: an undetected fresh install still pre-checks ALL (F02 R2)
ok - F02 baseline_upgrade_keeps_persisted: an upgrade pre-checks its persisted selection (F02 R3)
ok - F02 no_tty_default_unchanged: no TTY + no override still stamps ALL (F02 R5)
ok - F02 baseline_fresh_removes_nothing: the narrowed fresh install is byte-inert in the shared codex prompts (F02 R8)
ok - F02 existing_install_never_narrows: an existing install's resolution ignores every marker (F02 R9)
ok - F02 docs_document_fresh_default: INSTALL.md and the installer header state the new default (F02 R10)
ok - F02 docs_document_retoggle_path: INSTALL.md documents the re-run re-toggle path (F02 R11)
All agents-host tests passed.
```

(The full chain is 25 suites; 22 print "All … passed" and three — `test_board_lock.sh`,
`test_fix_worktree.sh`, `test_rationale_docs.sh` — print a `PASS:` banner instead. All 25 ran:
the chain is `&&`-joined and exited 0.)

`git diff --numstat`: `tests/test_agents_host.sh 339 7` (deletions unchanged from round 1),
`tests/test_install.sh` **not in the diff**. Nothing committed, no PR, status untouched.
