---
feature: E20-F01
role: builder
date: 2026-07-28
branch: feat/E20-F01-backend-prompt
version: 0.41.0 → 0.42.0
---

# Builder hand-off — E20-F01 `execution.builder.backend` prompt

Status confirmed `in-progress` in `state/tasks.json` before any code was written.
All 15 tasks in `E20-F01.tasks.md` are ticked. `./init.sh` is green and the **full**
`verification.test_command` chain (26 suites) exits 0.

## What landed

The installer's **second question**. After the front-end picker resolves, an interactive
run asks one plain line-oriented follow-up for `execution.builder.backend`, then writes it
into the target's `harness.config.yaml` by replacing one scalar on one line.

| Piece | Where | R-ids |
|---|---|---|
| `_cfg_execution_builder_value <file> <key>` | `harness-install.sh`, beside `_cfg_pr_loop_value` | R7, R8, R11, R12 |
| `builder_backend_answer <answer> <current>` — pure, `sed`-extractable | after `resolve_agents` | R2 |
| `builder_backend_prompt <current>` — menu → stderr, `read -r`, delegate | after `resolve_agents` | R1, R3 |
| `resolve_builder_backend <target>` → `BUILDER_BACKEND` + `BUILDER_BACKEND_SOURCE` | after `resolve_agents` | R1, R4, R6, R12 |
| `set_builder_backend <config> <value>` — one scalar, `$f.tmp` + `mv` | after `resolve_agents` | R7, R8 |
| `migrate_config` — one new `execution:` entry (top-level header check, EOF append) | end of `migrate_config` | R9 |
| `--builder-backend=` / `--builder-backend <v>` / `HARNESS_BUILDER_BACKEND` + validation | arg-parsing block | R4, R5 |
| `resolve_builder_backend "$TARGET"` immediately after `resolve_agents "$TARGET"` | `install_one` | R1, R6 |
| apply + `delegate_cmd` warning + one report line, after seed/preserve + `migrate_config` | `install_one` §2b | R7, R8, R10, R11, R12 |
| header comment + `BUILDER EXECUTION BACKEND` summary section | `harness-install.sh` | R13 |
| “The second question — `execution.builder.backend`” section | `docs/INSTALL.md` | R13 |
| `tests/test_installer_toggles.sh` (new) + `verification.test_command` | — | R14 |
| `VERSION` 0.42.0 + `## [0.42.0]` entry | — | R15 |

### Stable markers the suite (and any future reviewer) greps for

- prompt: `Which builder backend` (stderr, TTY only)
- report: `builder backend:` — exactly one line per target, never on `--print-agents`
- warning: `delegate_cmd is empty` — names `execution.builder.delegate_cmd` + the config path

The three are mutually non-overlapping on purpose, so the R11 negative
(“no warning when `delegate_cmd` is set”) cannot be satisfied by prose in the summary
heredoc that happens to mention the key.

## Constraints honored

- `tests/test_install.sh` is **not in the diff** (`git diff --name-only` confirms).
- The word “drift” does not appear in `harness-install.sh` (`grep -ci` ⇒ 0); the docs test
  re-asserts it locally so this suite fails before `tests/test_drift_check.sh:259` does.
- `--print-agents` stdout is still exactly two lines — the report line lives in
  `install_one`, which that flag exits before reaching.
- `tui_select`, `toggle_select`, `tui_capable`, `normalize_keys`, `validate_csv` and
  `AGENT_KEYS` are byte-unchanged, and asserted so.
- No `store/tasks.schema.json` change, no `agents/*.md` fork, POSIX `sh`, zero new deps.
- The new suite freezes no `VERSION` literal, pins no previous version and diffs nothing
  against `main`; every installer invocation goes through the single `hrun` gateway with
  `env -i` + sandboxed `HOME` and `CODEX_HOME`.

## Deviations from the plan — two, both narrowing

1. **`resolve_builder_backend` reads `$1/.harness/harness.config.yaml` rather than
   `$H/...`.** Same path (`H="$TARGET/.harness"` is set just above the call), but it makes
   the resolver a function of its argument instead of an ambient global — which is what the
   task's own `<target>` signature asks for.
2. **`version_and_changelog` does not pin a MINOR floor.** `.tests.md` names
   `tests/test_drift_check.sh`'s `R19_version_changelog` as the shape to copy, and that
   check parses semver + looks for `## [$V]` + a feature marker anywhere, with no
   hard-coded floor. Adding `-ge 42` would have been “compare against a hard-coded previous
   version”, which the same paragraph forbids. The MINOR-vs-PATCH judgement stays the
   Reviewer's, from the diff.

Two edge cases the plan did not name, handled in `set_builder_backend`: a `backend:` line
with an **empty value** gets a separating space (`backend: delegate`, not
`backend:delegate`), and a `backend:   # note` line (empty value, trailing comment) keeps a
space before the `#` so it stays a comment. Both are exercised by hand; neither occurs in a
harness-seeded config.

## Verification

```
$ ./init.sh                    → exit 0
$ <full verification.test_command, 26 suites>  → exit 0, 647 ok/PASS assertions
  All install / umbrella / cascade / inception / reviewer / telemetry / mirror /
  epic-lifecycle / sdd-plan / sdd-drill / sdd-fix / architect-adr / drift-check /
  doc-critic / ownership / board-lock / adr-citation / fix-worktree / sdd-fix-parallel /
  dependency-diagnostics / rationale-docs / next-task / model-routing / pr-loop /
  agents-host / installer-toggle tests passed.
```

### Mutation proofs (each applied, suite run, reverted; installer restored byte-identical)

| # | Mutation | Caught by |
|---|---|---|
| M1 | `builder_backend_answer`'s `*)` prints `in-session` (Enter always resets) | R2 — `'' 'delegate'` printed `in-session` |
| M2 | writer rewrites the whole `backend:` line, dropping the trailing comment | R7 — line lost its indentation/trailing comment |
| M3 | `[ -t 0 ]` guard dropped in `resolve_builder_backend` | R1 — prompt asked on a non-interactive run |
| M4 | the `delegate_cmd` warning fires unconditionally | R11 — warning fired although `delegate_cmd` is set |
| M5 | report line added to `--print-agents` stdout | R12 — printed 3 stdout lines, expected 2 |
| M6 | illegal override no longer `die`s | R5 — `--builder-backend=turbo` exited zero |
| M7 | writer always runs (no skip-when-unchanged) | R8 — a no-override run TOUCHED the config |
| M8 | env var beats the flag (precedence inverted) | R4 — flag did not beat `HARNESS_BUILDER_BACKEND` |
| M9 | `execution:` migration appends unconditionally | R4 — an empty override rewrote the config (duplicate block) |
| M10 | a `case` on the answer migrates into `builder_backend_prompt` | R1 structural — decision logic in the untestable half |
| M11 | backend logic added to `tui_select` | R3 — the picker gained builder-backend behavior |
| M12 | the forbidden word written into `harness-install.sh` | R13 — forbidden word present |
| M13 | the suite un-wired from `verification.test_command` | R14 — not named in `test_command` |

M7 is the reason `write_is_idempotent` also compares against a reference marker with
`find -newer`: a byte comparison alone cannot distinguish “skipped the writer” from
“rewrote identical bytes”, so R8's actual requirement would have been unfalsifiable.

## Left for the Reviewer

- The by-hand interactive checklist at the bottom of `E20-F01.tests.md` — the `read -r`
  plumbing and the two menu `printf`s are the only residue no POSIX suite can drive.
- Confirm from the PR diff that `tests/test_install.sh` is absent (R14 leaves this out of
  the permanent suite deliberately).
- The MINOR-vs-PATCH call on `0.41.0 → 0.42.0`.

## Seam left for E20-F02

`pr_loop.enabled` becomes one more `<name>_prompt` + `<name>_answer` pair called from the
same resolve block in `install_one` (right after `resolve_builder_backend "$TARGET"`) and
one more apply in the §2b config block. No framework was built for it, per the spec.

---

# Round 2 — Reviewer findings F1/F2 (coordinator's N1/N2) closed

Directed by the Orchestrator after the APPROVE verdict, before the PR opens. F3/F4 (N3/N4)
deferred as instructed; F5 (N5) got the requested in-code note rather than a fixture.

## N1 — the `execution:` migration block now converges with the source config

`migrate_config` states the convergence rule twice in its own body (for `models:` and for
`pr_loop:`) and my `execution:` entry broke it: same YAML values, different comment text
depending on whether the target was seeded or migrated.

Fixed by authoring the block **once** and splicing the identical bytes into both places —
`harness.config.yaml`'s `execution:` section and the `migrate_config` heredoc — rather than
hand-aligning two copies and hoping. The entry's comment now carries the same "keep this
byte-identical / if you edit one, edit the other" warning the `models:` and `pr_loop:`
entries do, plus the note that only the POSITION can differ (the source block sits mid-file;
migration can only append at EOF), which is why the check compares the extracted block.

Hand-verified end to end, the way the Reviewer verified the defect:

```
fresh block lines:  30   migrated block lines:  30
BY HAND: fresh block == migrated block, byte for byte
```

## N2 — the fresh path is now the documented one

Resolved by N1, in the direction the coordinator asked for: the block that won is the one
that documents the surface. A fresh install's `harness.config.yaml` now opens the
`execution:` section with

```
# Builder execution backend. The installer ASKS for this — a follow-up prompt right after
# the front-end picker, on a TTY — and takes --builder-backend=<in-session|delegate> or
# HARNESS_BUILDER_BACKEND=<value> for scripted runs (the flag wins). RE-RUN the installer
# to change it later, or edit the value below: only that one scalar is ever rewritten, so
# every comment and hand-edit in this file survives.
```

## New assertions (in `migration_seeds_execution_block`, R9)

Modeled on `tests/test_pr_loop.sh`'s `test_seeded_and_migrated_block_identical` (E18-F01
R17), bounded at both ends because — unlike `pr_loop`'s — this block is not the tail of the
source config:

1. **convergence** — a seeded install's `execution:` block `cmp`s byte-identical to a
   migrated one, via the shared `exec_block` extractor;
2. **discoverability** — the block a FRESH install seeds must mention `--builder-backend`,
   `HARNESS_BUILDER_BACKEND`, `in-session` and `delegate_cmd`.

The R9 fixture was also corrected: it stripped the block but left its comment header
orphaned mid-file, which is not what a pre-E20 config looks like and gave the extractor a
second, bogus anchor. It now removes the whole span, and asserts the header is gone.

## N5 — noted in code, not fixed

A `DO NOT "SIMPLIFY" THE SCOPE GUARDS` block sits on `_cfg_execution_builder_value` (and
names `set_builder_backend`), recording that mutations S1/S2 pass today because `builder:`
is the only mapping under `execution:`, that the guards become load-bearing the moment
E20-F02 adds a second one, and that the fixture which would make them falsifiable is a
decoy `backend:` under a sibling section. Placed where the next implementer reads before
touching the reader.

## Verification (real output)

```
$ ./init.sh
── harness-sdd init ──────────────────────────────
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (namespaces: specs/adr)
ℹ️  no project-specific checks (.harness/init.project.sh absent)
──────────────────────────────────────────────────
✅ environment ready — agents may proceed
INIT_EXIT=0

$ suites in chain: 26        (re-extracted verbatim from harness.config.yaml, not cached)
$ CHAIN_EXIT=0
$ 647 ok-/PASS assertions
  All install / umbrella / cascade / inception / reviewer / telemetry / mirror /
  epic-lifecycle / sdd-plan / sdd-drill / sdd-fix / architect-adr / drift-check /
  doc-critic / ownership / board-lock / adr-citation / fix-worktree / sdd-fix-parallel /
  dependency-diagnostics / rationale-docs / next-task / model-routing / pr-loop /
  agents-host / installer-toggle tests passed.
```

### Mutation proofs for the new assertions

| # | Mutation | Caught by |
|---|---|---|
| M14 | migration heredoc reverted to the pre-fix (divergent) text | R9 convergence — `1,5c1,2` |
| M15 | **one character** changed in the heredoc (`survives.` → `survive.`) | R9 convergence — `5c5` |
| M17 | flag/env docs removed from **both** copies (convergence intact, N2 regressed) | R9/R13 — “the block a FRESH install seeds does not mention '--builder-backend'” |

M17 is the one that matters for N2: it keeps the anchor and keeps the two copies identical,
so only the discoverability assertion can fire — proving that check is not riding on the
convergence `cmp`. (An earlier attempt, M16, deleted the source header outright and tripped
the fixture guard first; it proves nothing about N2, so it was replaced by M17.)

### DO-NOT-TOUCH re-verified after the round-2 edits

13 protected function bodies hashed against `HEAD` — `tui_select`, `toggle_select`,
`tui_capable`, `normalize_keys`, `validate_csv`, `resolve_agents`, `detect_host`,
`precheck_baseline`, `host_fallback_set`, `override_host_kind`, `seed_pr_loop_optin`,
`_cfg_pr_loop_value`, `pr_loop_enabled` — **all identical**.
`AGENT_KEYS="claude gemini opencode antigravity codex"` unchanged.
`grep -ci drift harness-install.sh` ⇒ 0. `tests/test_install.sh` still absent from the diff.
`--print-agents` still exactly two stdout lines (asserted in `reports_once`).

## Scope note

`harness.config.yaml`'s `execution:` comment block was edited. The `.plan.md` lists that
file only for the `verification.test_command` append, so this is a **directed** deviation:
closing N1/N2 is not possible without changing the text on one side or the other, and the
coordinator asked for the documented block to be the one that wins. No value changed — the
diff is comments plus the four-line trailing-comment extension on the `delegate` bullet.
