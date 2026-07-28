---
feature: E19-F02
role: reviewer
date: 2026-07-28
branch: feat/E19-F02-fresh-baseline
verdict: REJECT (two record-level must-fixes; zero behavioral defects)
pr_ready: NO — fix F1 and F2, then yes
---

# Reviewer verdict — E19-F02 "Fresh-install pre-check baseline = the detected host"

**The implementation is correct.** I could not break it: every branch of
`precheck_baseline` behaves as R1–R5 require, on a real pty as well as through
`--print-agents`, and the upgrade-safety guarantee holds under every mutation I could
invent. All three declared deviations are legitimate and I verified each one against the
merged E19-F01 code rather than taking the Builder's word.

What I am rejecting on is the **written record inside `harness-install.sh` and the spec
package**, which now states the opposite of the shipped code in four places. Both fixes
are comment/prose only — no behavior change, no re-spec, no new test.

---

## Must-fix

### F1 (blocking) — four stale comment blocks in `harness-install.sh` contradict the change

The Builder updated the file header (R10) and `precheck_baseline`'s own docblock, but left
the two docblocks *below* it asserting the pre-F02 world. One of them explicitly instructs
a future maintainer to undo this feature.

`harness-install.sh:1167-1168`
```
# This is the SINGLE source of the undetected-fallback answer, with two callers: the
# `host` arm of resolve_agents and `--print-agents`'s `baseline=` line — which is what
```
`host_fallback_set` now has exactly **one** call site (line 1251, inside `resolve_agents`).
`--print-agents` no longer calls it.

`harness-install.sh:1170-1172` — the worst one:
```
# (R26). `baseline=` deliberately reports THIS, not precheck_baseline: on a fresh target
# holding orphan metadata (a copied or half-restored `.harness/.agents` with no stamp) the
# two differ, and the diagnostic must advertise the set that will really be installed.
```
Both clauses are now false. `baseline=` **is** `precheck_baseline` (line 3492), and on an
orphan-metadata target the two no longer differ when undetected — post-F02
`precheck_baseline` does not read `.agents` without a stamp, so both answer ALL. Left as
is, this comment reads as a standing justification for reverting the line the feature
exists to change.

`harness-install.sh:1174-1176`
```
# It cannot affect a run that never names `host`: both call sites are gated on `host` —
# resolve_agents reaches this arm only when the override value is exactly `host`, and
# --print-agents writes nothing at all.
```
"both call sites" — there is one.

`harness-install.sh:1222-1224`, the `resolve_agents` resolution-order block:
```
#   2. Interactive (R1/R9): else if stdin is a TTY → pre-check baseline is the
#      persisted .harness/.agents if present (R9) else ALL (R1), now via
#      precheck_baseline (R26).
```
"else ALL" is exactly the default this feature replaces. It is now: persisted selection →
ALL for a stamped install with none → the detected host alone → ALL when undetected.

This is the same class of defect R10 spends a whole requirement on (and which
`test_docs_document_fresh_default` polices for the header, lines 892-894 of the suite) —
one screen lower in the same file, uncaught because the R10 check only reads
`sed -n '1,60p'`. Optional hardening, your call: widen that assertion, or add one asserting
that no comment in the file still says the picker pre-checks ALL on a fresh target.

### F2 (blocking, small) — the R9 sketch was proven wrong but not corrected

Deviation 3 is empirically right — I reproduced it on this branch **and** on `main`:

```
after install --agents=claude,gemini:                    [claude gemini]
after no-override non-TTY re-run (+CLAUDECODE=1):        [antigravity claude codex gemini opencode]   # this branch
MAIN, same two steps:                                    [claude gemini] -> [antigravity claude codex gemini opencode]
```

So a no-override non-TTY re-run widens by R5, before and after this feature; the sketch's
"`.harness/.agents` is unchanged" premise is false and always was. But the contract files
were left saying it:

- `E19-F02.tests.md:68-70` — the `existing_install_never_narrows` sketch still claims
  `.harness/.agents` is unchanged and `GEMINI.md` still exists.
- `E19-F02.tests.md:30` — the R9 row's Behavior cell reads "no existing install narrows
  from detection alone", which is garbled and does not describe marker-independence.
- `E19-F02.tasks.md:T10` — same false premise, ticked `[x]`.

The shipped test asserts the right invariant (marker-independence, which is what
`.spec.md` R9 actually says). Correct the two sketch rows and T10 to match, with a
one-line note that the widening is R5 behavior and predates this feature. The reasoning
currently lives only in `progress/builder-E19-F02.md`, which does not survive the merge.

## Nits (non-blocking)

- `README.md:284-289` still describes the picker without the new fresh-install default. R10
  scopes the requirement to `docs/INSTALL.md`, so this is not a defect — but the README is
  the first thing a new user reads, and F01 did add a host-mode paragraph there
  (`README.md:314-326`). One sentence would close it.
- `docs/INSTALL.md` `--print-agents` paragraph: "so the preview cannot disagree with the
  install" is true for an undetected run and an overstatement for a detected one (on a
  `gemini` install inside Claude Code, `baseline=gemini` while `--agents=host` would install
  `claude`). Pre-existing wording, carried forward.
- `test_docs_document_retoggle_path`'s removal assertion is `grep -qi 'remove\|deselect'`;
  a passing mention of "deselect" satisfies it. It does catch an outright deletion and a
  semantically-inverted rewrite (I mutated both), so this is a strength nit only.

---

## What I verified

### Environment + full chain (real output)

```
$ ./init.sh
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (namespaces: specs/adr)
ℹ️  no project-specific checks (.harness/init.project.sh absent)
✅ environment ready — agents may proceed

$ <full verification.test_command, all 25 suites>
CHAIN EXIT=0
593 "ok -" assertions, zero FAIL lines
...
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

`lint_command` / `typecheck_command` are empty — n/a.

### Traceability — every R-id has a check that genuinely fails on regression

I built a solo driver (the suite's first 922 lines + a per-test dispatcher) so each check
could be judged **in isolation**, not shadowed by an earlier one, and applied my own
mutations to a byte-backed copy of the tree.

| Mutation (mine, independently written) | Result |
|---|---|
| stamp gate removed from `precheck_baseline` (naive `.agents`-first order) | caught — `R4/R9: a pre-E08 upgrade's baseline was narrowed by detection (got 'claude', want '<all five>')` |
| detected host unioned with `claude` | caught — `R1: … does not pre-check 'opencode' alone (got 'claude opencode')` |
| undetected fresh falls back to `claude` | caught — `R2: an undetected fresh target does not pre-check ALL (got 'claude')` |
| `baseline=` reverted to `host_fallback_set` | caught — `R1: … does not pre-check 'claude' alone (got '<all five>')` |
| no-TTY/no-override branch consults the helper | caught — `R5: a no-override non-TTY run no longer persists ALL (claude)` |
| detection overrides a persisted selection | caught — `R3: an upgrade's baseline is not its persisted selection (got 'claude')` |
| header keeps the stale "ALL on a fresh install" claim | caught — `R10: the harness-install.sh header still claims …` |
| docs drop the undetected case | caught — `R10: the section does not state that an undetected host still pre-checks everything` |
| re-toggle bullet deleted outright / inverted to "unchecking has no effect" | caught both — `R11: … does not say a re-run also applies REMOVALS` |
| stray file written into `$CODEX_HOME/prompts` during install | caught — `R8: … changed the shared codex prompts dir: Only in …/stray.md` |
| foreign `.sdd-pr-loop.owners` deleted during install | caught — `R8: … Only in …/prompts.before: .sdd-pr-loop.owners` |
| **marker leaks into the no-override path, routed through a wrapper so it evades R5's source grep** | R5 correctly still passes; **R9 catches it** — `R9: a marker changed what a no-override re-run resolved (claude vs <all five>)` |

That last one is the important one: it proves `existing_install_never_narrows` has teeth
**independent** of R5's source-level guard, which is the whole point of the reshaped R9
check. Every R-id in `.spec.md` maps to a check I saw fail on a real regression. R6/R7/R12
are source-level and land inside the F01 checks they extend, which is the right call — a
second copy could disagree.

### Deviation 1 — `--print-agents` repointed: verified, and required by R6

The Builder's claim about the plan is accurate. Merged `main` at `harness-install.sh:3460`:

```
printf 'baseline=%s\n' "$(host_fallback_set "$TGT" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
```

So the `.plan.md`'s premise was wrong and R1's required `baseline=claude` assertion was
unreachable — confirmed by mutation ("`baseline=` reverted to `host_fallback_set`" ⇒ all
five). Note that `.spec.md`'s own glossary (lines 76-77) already *defines* `baseline=` as
the picker's pre-check set, so this repoint implements R6 as written; the `.plan.md`
DO-NOT-TOUCH bullet and the "Out of scope" bullet naming `--print-agents` are what were
wrong. Worth recording, but nothing to fix here.

**Compatibility argument holds.** Reading both helpers: for an undetected target
`host_fallback_set` → persisted (stamp + `.agents`) / ALL otherwise, and `precheck_baseline`
→ persisted / ALL / ALL. Identical in all three shapes. `test_print_agents_matches_host_install`
is **unmodified** (I checked the diff hunk-by-hunk — the test file's only three content
hunks are in `test_print_agents_contract`, `test_baseline_single_helper` and
`test_version_and_changelog`) and it passes, covering both the orphan-metadata corner and a
real stamped install under `env -i` with no marker.

### Deviation 2 — the 7 deleted lines were forced; no test was bent

`git diff --numstat` → `tests/test_agents_host.sh  293 7`; `tests/test_install.sh` is not in
the diff at all (zero deletions), as claimed. The 7:

- 2 in `test_print_agents_contract` case (a): the literal
  `baseline=antigravity claude codex gemini opencode` for a **fresh dir with `CLAUDECODE=1`**
  — the exact default R1 replaces. Genuinely forced.
  **Coverage preserved:** the re-added case (a2) re-runs `--print-agents` on the *same fresh
  dir* with no marker and asserts the identical sorted five-key line, plus repeats the
  "target untouched" `find` comparison. The multi-key sorted rendering the old assertion
  proved is intact; only the fixture's marker moved.
- 2 in `test_baseline_single_helper`: the `host_fallback_set "$TGT"` source grep, forced by
  deviation 1. Its other four assertions — including the "no inline baseline computation"
  guard and the `precheck_baseline "$_t"` picker grep — are unchanged, and the new grep is
  strictly equivalent in strength.
- 3 are `pass "…"` label strings, re-emitted with F02 R-ids appended. No assertion lost.

Not design drift. Both edits assert the old default by construction and cannot survive the
feature.

### Deviation 3 — premise confirmed false; see F2 for what is still owed.

### Upgrades never silently narrow — checked three ways

- Automated: `test_baseline_legacy_upgrade_is_all` (pre-E08 shape) and
  `test_existing_install_never_narrows`, both with teeth (table above).
- **By hand, on a real pty**, the case that matters most: a pre-E08 install (stamp present,
  `.harness/.agents` deleted, all five front-ends on disk) re-run **interactively inside a
  detected Claude Code session**, pressing Enter immediately:
  ```
  first frame:   > [x] claude  [x] gemini  [x] opencode  [x] antigravity  [x] codex
  removal lines: []
  persisted:     antigravity claude codex gemini opencode
  CLAUDE.md True  GEMINI.md True  opencode.json True  AGENTS.md True  .agents/ True
  ```
  Nothing narrowed, nothing deleted.

### No-TTY / CI unchanged — a no-override non-interactive run with `CLAUDECODE=1` stamps all five and persists all five (behavioral + source assertion, both mutation-proven).

### Host-only, not host-plus-claude — `test_baseline_fresh_is_host_only` asserts full-line equality on three different hosts (`claude`, `opencode`, and a declared `gemini`), so any superset fails; my union mutation was caught on the `opencode` case, i.e. the hardcoded-`claude` escape is closed too.

### Cross-target codex safety
`PRIOR_AGENTS` (incl. `grep -vx codex`) is untouched — the `harness-install.sh` diff is
exactly three hunks (header comment, `precheck_baseline`, the `baseline=` line); nothing
near lines 1300-1320 moved. Beyond the automated R8 check I ran the **interactive** version
on a pty: a shared `$CODEX_HOME/prompts` pre-seeded with a foreign `someone-elses.md`, a
`.sdd-pr-loop.owners` naming another target and another target's `sdd-pr-loop.md`, then a
fresh host-narrowed install confirmed at the picker →
`only in before: []  only in after: []  diff files: []`, ledger and body byte-identical, no
removal lines.

### Hygiene
- `grep -ci 'drift' harness-install.sh` → **0**.
- No frozen `VERSION` literal in the suite (`test_suite_hygiene` enforces it and I grepped
  independently); `test_version_and_changelog` compares parsed components with a `>= 41`
  floor. `VERSION` 0.40.0 → **0.41.0** (MINOR, R13) with a matching `## [0.41.0]` CHANGELOG
  section.
- No `git diff` against `main` anywhere in the suite; every installer invocation goes
  through `hrun` (`env -i` + sandboxed `HOME` + sandboxed `CODEX_HOME`) — the suite is the
  single named invocation site and `test_suite_hygiene` enforces it.
- No new suite, so no `verification.test_command` wiring needed; `test_suite_wired_into_verification` passes.
- `ALL_KEYS` is derived from the installer's own `AGENT_KEYS` with a non-empty ≥5 guard, so
  no baseline comparison can pass against an empty string.

### The five by-hand TTY checks — all pass (driven over a real pty)

| Check | Result |
|---|---|
| fresh scratch repo inside Claude Code ⇒ picker pre-checks `claude` alone | `> [x] claude / [ ] gemini / [ ] opencode / [ ] antigravity / [ ] codex`; confirmed ⇒ `AGENTS.md CLAUDE.md .claude` only, persisted `claude` |
| toggle `gemini` on before confirming ⇒ `GEMINI.md` appears | selection `(claude gemini)`, persisted `claude gemini`, `GEMINI.md` present |
| re-run interactively ⇒ pre-checks `claude gemini`, not `claude` | `> [x] claude / [x] gemini / [ ] …` |
| toggle `gemini` off, confirm ⇒ `GEMINI.md` removed | `⚠️  removed deselected agent 'gemini' glue: GEMINI.md harness block`; persisted `claude`; `GEMINI.md` gone, `CLAUDE.md`/`AGENTS.md` intact |
| plain terminal, no marker, fresh repo ⇒ all five pre-checked | `> [x] claude / [x] gemini / [x] opencode / [x] antigravity / [x] codex` |

Conventions and DO-NOT-TOUCH: honored (`HOST_MARKERS`, `detect_host`, `AGENT_KEYS`, the
`host` override arm, `PRIOR_AGENTS`, §7/§7b reclamation, `remove_if_pristine`, the
`_owners_*` ledger, `tui_select`/`toggle_select`, `AGENTS.md`, `agents/*.md`,
`store/tasks.schema.json`, `init.sh`, `tools/*` — all unmodified). ADR-citation check: the
spec carries `## Architecture alignment` stating `ADRs touched: none` with rationale —
passes. Board status left at `in-review`; nothing committed; **do not set `done` before the
PR merges.**

---

## Verdict

**REJECT — F1 and F2 only.** Zero behavioral defects; I could not find a way to make the
installer narrow something it should not, on a pty or off one. Fix the four comment blocks
and the two contract sketches (both comment/prose, no code path moves, no test needs to
change) and this is PR-ready. Re-review is a diff read plus one chain run.
