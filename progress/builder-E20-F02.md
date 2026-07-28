---
feature: E20-F02
role: builder
date: 2026-07-28
branch: feat/E20-F02-pr-loop-prompt
version: 0.42.0 → 0.43.0
---

# Builder hand-off — E20-F02 `pr_loop.enabled` prompt

Status confirmed `in-progress` in `state/tasks.json` before any code was written (this
feature is `autonomous: false`, so that value is the human gate having been passed).
All **36** tasks in `E20-F02.tasks.md` are ticked. `./init.sh` is green and the **full**
`verification.test_command` chain (26 suites) exits 0.

> This session **picked up an interrupted Builder run**. Most of the implementation was
> already on disk; the work recorded here is the finish: the `&&` short-circuit
> investigation, one new regression check, a mode-bit repair, one docs-heading fix, the
> mutation proofs, the task ticks and the end-to-end chain run.

## What landed

The installer's **third question**. After the E20-F01 backend prompt resolves, an
interactive run asks one plain line-oriented follow-up for `pr_loop.enabled`, then writes
it into the target's `harness.config.yaml` by replacing one scalar on one line — early
enough that E18-F01's existing §5 stamping and §7b reclamation reconcile the flip inside
the same run.

| Piece | Where | R-ids |
|---|---|---|
| `pr_loop_answer <answer> <current>` — pure, `sed`-extractable | `harness-install.sh` ~:1615, beside the E20-F01 helpers | R2 |
| `pr_loop_prompt <current>` — menu → stderr, `read -r`, delegate | ~:1635 | R1 |
| `resolve_pr_loop <target>` → `PR_LOOP_CHOICE` + `PR_LOOP_CHOICE_SOURCE` | ~:1674 | R1, R4, R5, R6, R12 |
| `set_pr_loop_enabled <config> <value>` — one scalar, or canonical insert; `$f.prwtmp` + `mv` | ~:1718 | R7, R10 |
| `resolve_pr_loop "$TARGET"` immediately after `resolve_builder_backend "$TARGET"` | `install_one` | R1, R3 |
| apply + `PER-RUN override` warning + one report line | `install_one` **§2c** (after §2b) | R5, R7, R8, R9, R11, R12 |
| `--pr-loop=<v>` / `--pr-loop <v>`, `PR_LOOP_OVERRIDE=""` (no env seed) + validation | arg-parsing block | R4 |
| header comment + `PR REVIEW LOOP` summary section | `harness-install.sh` | R13 |
| “The third question — `pr_loop.enabled`” section (+ `/sdd-pr-loop` cross-link) | `docs/INSTALL.md` | R13 |
| 7 comment lines in the `pr_loop:` block, **byte-identical in both copies** | `harness.config.yaml` + the `migrate_config` heredoc | R10, R13 |
| 14 new `test_*` functions + helpers | `tests/test_installer_toggles.sh` | R1–R15 |
| `VERSION` 0.43.0 + `## [0.43.0]` entry | — | R15 |

`migrate_config` gained **no** new entry (the `pr_loop:` one already existed).
`seed_pr_loop_optin` is unmodified. `tests/test_install.sh` and `tests/test_pr_loop.sh`
are **not** in the diff (R14 / T35, verified against `git status`).

### Stable markers the suite greps for

- prompt: `Enable the Codex PR review loop` (stderr, TTY only)
- report: `pr_loop.enabled: ` — with the colon, so it cannot collide with §7b's stderr
  `pr_loop.enabled is not true — reclaimed …`; counted on **stdout only**
- env warning: `PER-RUN override` — names `HARNESS_PR_LOOP_ENABLED` and says “NOT persisted”

## The `&&` short-circuit — what it was, and where it is now

**Where.** `tests/test_installer_toggles.sh`, `test_same_run_stamp_and_reclaim` step (d) —
the setup that removes the *foreign* owner from `$CODEX_HOME/prompts/.sdd-pr-loop.owners`
so the “now nobody claims it ⇒ it IS reclaimed” direction can run. It was written as:

```sh
grep -vxF "$_foreign" "$_ledger" > "$_ledger.t" && mv "$_ledger.t" "$_ledger"
```

Dropping the *only remaining* line leaves `grep` with nothing to print, i.e. exit 1. Under
`set -e` a failing **non-final** command of an AND-OR list is exempt, and the list's own
non-zero status is not a pipeline, so the shell neither runs the `mv` nor aborts: the
ledger edit is skipped **silently**.

**Status: the fix had landed** in the working tree I inherited —

```sh
{ grep -vxF "$_foreign" "$_ledger" || :; } > "$_ledger.t"
mv "$_ledger.t" "$_ledger"
```

— plus a setup guard on the next line. I confirmed it by mutation (below) rather than by
reading, and left it as-is.

**What I added (the regression test asked for).** The existing (d) block asserted only that
the *foreign* line survives a gate-off run. That cannot catch a skipped ledger write at all:
a ledger that was **never rewritten** still carries that line. So the release's other half
is now asserted — the departing target must have dropped **its own** claim:

```sh
_tphys="$( CDPATH= cd -- "$_t" && pwd -P )"
grep -qxF "$_tphys" "$_ledger" && fail "…the release write was skipped, so a stale claim now pins the shared prompt…"
[ "$(grep -c . "$_ledger" || :)" = "1" ] || fail "…expected exactly the 1 foreign owner…"
```

This is the product-side twin of the same defect class: a stale self-claim pins a *shared*
global prompt for every other target forever, and the mirror bug (a release write that runs
when it must not) is what deletes another target's prompt.

**Other candidate sites checked and cleared.** `harness-install.sh:3801`
(`if _is_pr_loop_cmd … && ! _owners_release …`) is an `if` condition, not a guarded edit.
`_owners_claim` / `_owners_release` / `_owners_live` already use `|| :` / `|| return`.
No other `&&`-guarded ledger edit exists in either file.

**One deliberate non-change.** `set_pr_loop_enabled` ends with
`awk … > "$f.prwtmp" && mv "$f.prwtmp" "$f"`. That is the *same* `&&` shape, and if the
redirection or `awk` failed the `mv` would be skipped silently. I left it: it is
byte-for-byte the house pattern of its two DO-NOT-TOUCH neighbours (`seed_pr_loop_optin`
~:413 and `set_builder_backend` ~:1567) and of `migrate_config`/`_mc_insert_after`, the
`.plan.md` explicitly specifies “`$f.tmp` + `mv`, like `seed_pr_loop_optin` /
`set_builder_backend`”, and hardening only this one would leave the file inconsistent while
the identical hazard stayed in five other writers. **Flagged for the Reviewer** as a
repo-wide question, not something this feature should settle unilaterally.

## Mutation proofs

Every load-bearing check was proved able to fail, by mutating a **copy** of the repo
(`/tmp/mutrepo`, so the concurrent chain run was untouched) and running the single affected
check. Restored and re-verified byte-identical after each.

| Mutation | Check that fired |
|---|---|
| restore the `&&` short-circuit on the ledger edit | `F02 R11: setup failed — the foreign claim was not removed from the ledger` |
| `_owners_release` drops its ledger rewrite | `F02 R11: the gate-off target's OWN claim survived in the ledger — the release write was skipped` **(the new check)** |
| `pr_loop_answer` `*)` prints `false` instead of `$2` | `F02 R2: pr_loop_answer '' 'true' printed 'false', expected 'true'` |
| writer rewrites **every** `enabled:` line (section scope dropped) | `F02 R7: the decoy section's own enabled: key was rewritten` |
| §2c always calls the writer | `F02 R8: a no-override run TOUCHED harness.config.yaml` |
| warn unconditionally | `F02 R5: a warning fired even though the env and the resolved value AGREE` |
| never warn | `F02 R5: the disagreeing env printed 0 'PER-RUN override' warnings` |
| `PR_LOOP_OVERRIDE="${HARNESS_PR_LOOP_ENABLED:-}"` (the rejected env twin) | `F02 R5: HARNESS_PR_LOOP_ENABLED PERSISTED into the config` |
| `resolve_pr_loop` fresh default `true` | `F02 R9: a fresh install INHERITED the source repo's gate` |
| `: seed_pr_loop_optin …` (call removed) | `F02 R9: install_one no longer calls seed_pr_loop_optin on the fresh-seed branch` |
| migrate heredoc's gate line re-spaced | `F02 R10: … the migrated pr_loop block is NOT byte-identical to the seeded one` |
| `set_pr_loop_enabled` a no-op | `F02 R11: --pr-loop=true did not stamp …/sdd-pr-loop.md` |
| report line printed twice | `F02 R12: a single-target install printed 2 report lines on stdout` |
| `gh --version` / `jq --version` at install time | `F02 R14: the installer executed gh or jq at INSTALL time` |
| `--pr-loop=maybe` accepted | `F02 R4: --pr-loop=maybe exited ZERO` |
| prompt asked without `[ -t 0 ]` | `F02 R1: the third prompt was asked on a NON-INTERACTIVE run` |
| `PR_LOOP_CHOICE` referenced inside `tui_capable` | `F02 R3: tui_capable gained pr_loop behavior` |
| non-TTY branch resolves `false` instead of the current value | `F02 R6: a non-TTY run with NO override changed harness.config.yaml` |

### One informative negative

Neutering **`seed_pr_loop_optin`'s body** (leaving the call in place) does **not** fail
`fresh_seed_interaction`. That is correct, not a gap: on a fresh install `resolve_pr_loop`
runs before the config exists, so the current effective value is the built-in `false`, and
§2c then normalizes the inherited `true` back down. “No answer ⇒ off” really is enforced
**twice**, exactly as the `.plan.md` says. What pins the seed itself is check (c)'s source
ordering — plus `tests/test_pr_loop.sh` R15, which this feature does not touch.

## Deviations from the plan / spec

1. **Mode bit repaired.** The inherited working tree had `harness-install.sh` at `100644`
   (the exec bit lost mid-edit). `chmod 755` restored it; `git diff --summary` is now empty.
   `docs/INSTALL.md` documents `./harness-install.sh …`, so this mattered.
2. **`docs/INSTALL.md` heading widened.** Inserting “## The third question” pushed the
   pre-existing `### Changing it later` out from under the second question and under the
   third. Retitled to `### Changing either answer later` with a one-line scope sentence, so
   it reads for both toggles. Nothing greps that heading.
3. **R14 hygiene section name.** `E20-F02.tests.md`'s matrix names a section
   `pr_loop_suite_hygiene`; **T29** says to *extend* `test_suite_wiring_and_hygiene`
   instead. I followed the task (one function, no duplication) and made the traceability
   visible in its `pass` line: `suite_wiring_and_hygiene / pr_loop_suite_hygiene … (R14,
   F02 R14)`. Its `_named <= 1` assertion already covers every invocation E20-F02 added.
4. **Nothing else.** No file outside the `.plan.md`'s “Files to change” table was touched;
   no DO-NOT-TOUCH function was modified.

## Verification — real output

`./init.sh` → rc 0:

```
── harness-sdd init ──────────────────────────────
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (namespaces: specs/adr)
ℹ️  no project-specific checks (.harness/init.project.sh absent)
──────────────────────────────────────────────────
✅ environment ready — agents may proceed
```

Full `verification.test_command` chain — **all 26 suites, `CHAIN_RC=0`**, 625 `ok -` lines.
(Run detached to a log: the chain has outgrown a 10-minute foreground cap, and a timeout
there reads exactly like a failure. It is neither hanging nor flaky.)

```
All install tests passed.
All umbrella tests passed.
All cascade tests passed.
All inception tests passed.
All reviewer tests passed.
All telemetry tests passed.
All mirror tests passed.
All epic-lifecycle tests passed.
All sdd-plan tests passed.
All sdd-drill tests passed.
All sdd-fix tests passed.
All architect-adr tests passed.
All drift-check tests passed.
All doc-critic contract tests passed.
All ownership tests passed.
PASS: test_board_lock.sh (R1-R9, R10a/R10b, R11, R12/R12b, R13, R12wt, R12src, R12sgd, R13struct, R14py3, R14mode, role/store contracts)
All adr-citation tests passed.
All sdd-fix-parallel tests passed.
All dependency-diagnostics tests passed (17 checks).
PASS: rationale documentation contracts
All next-task selector checks passed.
All model-routing tests passed.
All pr-loop tests passed.
All agents-host tests passed.
All installer-toggle tests passed.
CHAIN_RC=0
```

The three suites this feature was most likely to disturb all pass **unmodified**:
`test_install.sh`, `test_pr_loop.sh`, `test_drift_check.sh` (T34).

`tests/test_installer_toggles.sh` alone — 29 checks, 35s:

```
ok - pr_loop_answer_mapping_unit: … never passes the raw answer through (F02 R2)
ok - pr_loop_prompt_gating: … names its precondition, and holds no logic (F02 R1)
ok - f01_and_picker_unaffected: … gain no pr_loop behavior (F02 R3)
ok - pr_loop_override_contract: … illegal aborts before touching the target (F02 R4)
ok - env_is_per_run_not_persisted: … warns exactly once when it disagrees (F02 R5)
ok - pr_loop_non_interactive_is_inert: … leaves the config byte-identical (F02 R6)
ok - pr_loop_write_is_surgical: … a missing enabled: key gets the canonical line (F02 R7)
ok - pr_loop_write_is_idempotent: an unchanged value never touches the config (F02 R8)
ok - fresh_seed_interaction: … a fresh install can only reach true explicitly (F02 R9)
ok - seeded_migrated_block_converge: … byte-identical after the writer, for both values (F02 R10)
ok - same_run_stamp_and_reclaim: … honors the owners ledger … (F02 R11)
ok - pr_loop_reports_once: … --print-agents stays at two (F02 R12)
ok - docs_document_pr_loop_prompt: … document the third question (F02 R13)
ok - no_install_time_preflight: … neither gh nor jq at install time (F02 R14)
All installer-toggle tests passed.
```

## Left for the Reviewer

- The **by-hand interactive checklist** at the bottom of `E20-F02.tests.md` — the `read -r`
  plumbing no POSIX suite can drive (Enter-default on a re-run, `xyzzy` keeps the current
  value, Ctrl-C leaves the terminal usable, the numbered-fallback terminal).
- **Read the PR diff** and confirm `tests/test_install.sh` and `tests/test_pr_loop.sh` are
  absent — the check deliberately kept out of the permanent suite (R14).
- The **MINOR-vs-PATCH judgement** on `0.43.0` (new installer capability, backward
  compatible; the default is unchanged).
- The `&&`-guarded `awk … && mv` pattern shared by six config writers (see above) — a
  repo-wide hardening question, deliberately not settled here.

Nothing committed, nothing pushed, status left `in-progress`. Ready for the Orchestrator to
move E20-F02 to `in-review`.
