---
feature: E20-F02
role: reviewer
date: 2026-07-28
branch: feat/E20-F02-pr-loop-prompt
verdict: APPROVE — PR-ready
---

# Reviewer verdict — E20-F02 `pr_loop.enabled` prompt

**APPROVE.** No blocking defects. The feature is PR-ready. Do **not** roll `done` — it
must merge first (`chore/E20-F02-done` after the PR lands).

Everything below was verified independently. Where the Builder reported a result, I
re-derived it rather than trusting the hand-off; two of its conclusions turned out to be
under-reports in the feature's favour (§4, §5).

## 1. Environment + full chain

- `./init.sh` → rc 0.
- Full `verification.test_command` chain run **detached** (`/tmp/e20f02_chain.log`):
  **26/26 suites green, 624 `ok -` lines, `CHAIN_RC=0`, zero `FAIL`/`not ok`.**
  `lint_command` / `typecheck_command` are empty — n/a.
- `tests/test_installer_toggles.sh` alone: 29 checks green.

## 2. Traceability — R1 … R15

Every R-id in `E20-F02.tests.md` maps to a check that **exists and passes**:

| R | Check (`tests/test_installer_toggles.sh`) | Status |
|---|---|---|
| R1 | `test_pr_loop_prompt_gating` | pass |
| R2 | `test_pr_loop_answer_mapping_unit` (26-row truth table, invoked for real) | pass |
| R3 | `test_f01_and_picker_unaffected` | pass |
| R4 | `test_pr_loop_override_contract` | pass |
| R5 | `test_env_is_per_run_not_persisted` (4 directions) | pass |
| R6 | `test_pr_loop_non_interactive_is_inert` | pass |
| R7 | `test_pr_loop_write_is_surgical` | pass |
| R8 | `test_pr_loop_write_is_idempotent` | pass |
| R9 | `test_fresh_seed_interaction` | pass |
| R10 | `test_seeded_migrated_block_converge` (both values) | pass |
| R11 | `test_same_run_stamp_and_reclaim` (a–e) | pass |
| R12 | `test_pr_loop_reports_once` | pass |
| R13 | `test_docs_document_pr_loop_prompt` | pass |
| R14 | `test_suite_wiring_and_hygiene` (renamed pass label) + `test_no_install_time_preflight` | pass |
| R15 | `test_version_and_changelog` | pass |

The ⬜ Status column in `E20-F02.tests.md` matches the repo convention (E20-F01's matrix
is also all ⬜) — not a deviation.

## 3. The `&&` short-circuit class — independently verified, and the deferred ruling

**The test-side fix is real and the new guard can fail.** I re-derived the mechanism
(`set -eu` is on at `harness-install.sh:101`) and confirmed with a minimal repro that
`false > tmp && mv tmp f; echo AFTER` under `set -e` **prints AFTER** — the failing
non-final command is exempt and the shell does not abort. Then, on a scratch copy
(`/tmp/revmut`), I restored the original shape at
`tests/test_installer_toggles.sh:337-338`:

```sh
grep -vxF "$_foreign" "$_ledger" > "$_ledger.t" && mv "$_ledger.t" "$_ledger"
```

→ `FAIL: F02 R11: setup failed — the foreign claim was not removed from the ledger`.
The `{ … || :; }` form plus the setup guard is correct and load-bearing.

### RULING on `set_pr_loop_enabled`'s `awk … > "$f.prwtmp" && mv …` — NOT a defect, not in scope

The Builder was right to leave it, but for a stronger reason than "house pattern". Two
things separate it from the `grep` site:

1. **`grep -v` exit 1 is a normal outcome** ("no lines matched"), so the skipped `mv`
   produces a *silently wrong result*. **`awk` exit non-zero here is only ever a genuine
   error** — the program is static (no syntax error, no explicit `exit`), so the only
   routes are an unreadable input or a write failure (full disk / quota / read-only dir;
   a failed redirection means the command never runs at all). In every one of those,
   **skipping the `mv` is the correct behaviour** — it is what prevents a truncated tmp
   from clobbering the real config. The `&&` is a guard here, not a bug.
2. **The failure is not swallowed.** Unlike the test's top-level statement, this AND-list
   is the **last command of a function**, so `set_pr_loop_enabled` *returns* non-zero;
   its call site (`harness-install.sh` §2c, a simple command inside a `then` clause) is
   a plain simple command under `set -eu`, so the installer aborts. I verified both the
   general mechanism (a function wrapping the same shape does abort at the call site,
   rc 1, the following statement not reached) and that neither `install_one` call site
   (`harness-install.sh:4145`, `:4203`) is in a condition/AND-OR context that would
   disable `set -e` for the whole body. The same argument covers `seed_pr_loop_optin`
   and `set_builder_backend` — both are functions whose AND-list is the last command.

**Verdict: no change required, here or as a follow-up.** See N4/N5 for the two cosmetic
residues.

## 4. The owners ledger — both directions mutation-proved by me

Run on `/tmp/revmut`, one mutation at a time, restored and byte-verified after each:

| Mutation to `harness-install.sh` | Result |
|---|---|
| `_owners_release` drops its `printf … > "$_or_f"` ledger rewrite (:990) | `FAIL: F02 R11: the gate-off target's OWN claim survived in the ledger — the release write was skipped, so a stale claim now pins the shared prompt` |
| `_owners_release` ignores foreign owners (`_or_rest=""`) | `FAIL: F02 R11: the GLOBAL prompt was deleted while another live target still claimed it` |

Both directions of the cross-target hazard are genuinely asserted and genuinely able to
fail. The Builder's added assertion (the departing target must drop its **own** claim,
plus the `grep -c . == 1` ledger-size check) is the half that was missing and it is the
one that catches a skipped release write.

## 5. R9 / `seed_pr_loop_optin` — the Builder UNDER-reported; there is no hole

The hand-off records an "informative negative": neutering `seed_pr_loop_optin`'s body does
not fail `fresh_seed_interaction`. That is true of *that one check*, but the Builder only
ran that check. I neutered the body (`return 0` before the `awk`) and ran the **whole**
suite plus the untouched pr-loop suite:

- `tests/test_installer_toggles.sh` → `FAIL: F02 R7/R10: the INSERTED line differs from
  the canonical one a seeded target carries`
- `tests/test_pr_loop.sh` (unmodified, in the chain) → `FAIL: R17: the migrated pr_loop
  block is not byte-identical to the seeded one`

So `seed_pr_loop_optin`'s body **is** pinned, by two independent checks in two suites. The
triangle closes: `_spl_tail` (`harness-install.sh:1721`) is pinned to
`seed_pr_loop_optin`'s canonical line by the missing-key insert comparison, and to
`migrate_config`'s heredoc line by R10. R9's ordering check (c) pins the call site and the
`seed → writer` order. **No hole.**

Separately, the defence-in-depth the Builder describes is real and I confirmed the
mechanism: on a fresh install `resolve_pr_loop` runs before the config exists, so the
current effective value is the built-in `false`, and §2c re-normalizes whatever the seed
left. "No answer ⇒ off" is enforced twice on every path.

## 6. Byte convergence (R10 / E18-F01 R17) — independently reproduced

Outside the suite, with a sandboxed `HOME`/`CODEX_HOME`: seeded target A
(`--pr-loop=true`) vs target B (fresh → whole `pr_loop:` block stripped → re-run with
`--pr-loop=true` so `migrate_config` re-appends and the writer edits) →
**`cmp` identical.** The suite covers both `true` and `false`; a re-spaced migrate heredoc
line is proved to fail it.

I also diffed the `pr_loop:` block in `harness.config.yaml` against the `migrate_config`
heredoc copy line by line: **26 lines each, the only difference is the intended
`enabled: true` vs `enabled: false`.** All 7 new comment lines are byte-identical in both
copies, as R13/R10 require.

## 7. The env-twin ruling — verified, including the footgun case the suite does not cover

`tests/test_install.sh` and `tests/test_pr_loop.sh` are **absent from the diff** —
re-confirmed from `git status` (only `CHANGELOG.md`, `VERSION`, `docs/INSTALL.md`,
`harness-install.sh`, `harness.config.yaml`, `state/tasks.json`,
`tests/test_installer_toggles.sh` are modified).

The suite covers env-true/no-flag, env-agreeing, no-env, and env-false/flag-true. It does
**not** cover the exact footgun the spec's *Open questions* #2 names — env `false`, **no
flag**, on a target configured **on**. I ran it by hand:

- config **byte-identical** before/after (`cmp`), gate still reads `true`;
- the run itself was still gated off (glue reclaimed) — E18-F01 R20 intact;
- exactly **one** stderr warning, naming the variable and saying "NOT persisted";
- one stdout report line: `pr_loop.enabled: true (unchanged)`.

Correct in every respect. Note (not a defect, and pre-existing E18-F01 behaviour): a
per-run env override still has a *persistent filesystem* effect — it reclaims the stamped
glue while the config keeps saying `true`. This feature does not introduce that; the new
R5 warning is the first thing that ever announced it, so this is strictly an improvement.

## 8. Blast radius

- `harness-install.sh` diff hunks are: header comment, the `pr_loop:` heredoc comment,
  a **pure addition** after `set_builder_backend` (`@@ -1538,6 +1567,183 @@`), the
  `resolve_pr_loop` call in `install_one`, §2c, the summary heredoc, and arg parsing.
  **`tui_select`, `toggle_select`, `tui_capable`, `normalize_keys`, `validate_csv`,
  `AGENT_KEYS`, `seed_pr_loop_optin`, `set_builder_backend` are untouched** — asserted
  structurally by `test_f01_and_picker_unaffected` and visible in the diff.
- `--print-agents` still prints **exactly two** stdout lines (asserted; `test_agents_host.sh`
  green).
- E18-F01 R1 (unconditional `CMDDIR` body) intact — pinned by the guard-slice + indentation
  check in `test_same_run_stamp_and_reclaim` (e), and `tests/test_pr_loop.sh` green
  unmodified.
- E19 / E20-F01 behaviour untouched: the F01 half of the suite and `test_agents_host.sh`
  both green; `builder_backend_answer`'s contract is re-asserted from F02's own suite.
- A non-TTY run with no override leaves `harness.config.yaml` byte-identical *and does not
  touch it* (`find -newer` marker check), both fresh and on upgrade.
- Files changed match the `.plan.md` "Files to change" table exactly; nothing on
  DO NOT TOUCH moved.

## 9. Interactive (pty) checks — the untestable residue, all 8 done by hand

Driven over a real pty (`pty.fork`) with sandboxed `HOME`/`CODEX_HOME`:

| Check | Result |
|---|---|
| Order: front-end picker → builder-backend → PR-loop | offsets 19 → 268 → 599, exit 0 |
| Same order via the **numbered `toggle_select` fallback** (stubbed failing `stty`) | offsets 40 → 288 → 619, both follow-ups identical, exit 0 |
| Enter on a fresh install | `enabled: false`, **no** glue anywhere incl. `$CODEX_HOME/prompts` |
| Answer `2` | `enabled: true`; `/sdd-pr-loop`, `pr-fixer` **and** the global codex prompt stamped; **all 167 comment lines survive** |
| Re-run, Enter | prompt now reads `[Enter keeps true]`, config **byte-identical**, glue kept |
| Answer `xyzzy` | current value kept, asked **exactly once** (no loop), exit 0, config byte-identical |
| Answer `1` | `enabled: false`, all three artifacts reclaimed **in that run**, reclamation announced |
| Ctrl-C safety | `pr_loop_prompt` contains no `stty` and never enters raw mode (echo is on at the prompt, confirmed in the captured pty output) |

Report lines observed: `pr_loop.enabled: false (interactive prompt)` /
`… true (interactive prompt)` / `… true (unchanged)` / `… true (explicit --pr-loop)`.

## 10. Hygiene

- `grep -ci drift harness-install.sh` → **0**.
- No frozen `VERSION` literal in the suite; no `git diff`/`origin/main`/`git show`.
- `CODEX_HOME` sandboxed in the single `hrun` gateway (`env -i … CODEX_HOME="$_hr_dir/ch"`),
  and the `_named <= 1` check proves every new invocation goes through it.
- `VERSION` 0.42.0 → **0.43.0**: **MINOR is correct** — the installed body changes
  (`harness.config.yaml` comment block, the installer itself) and the change is a new,
  backward-compatible capability with an unchanged default. `CHANGELOG.md` carries a
  matching `## [0.43.0]` entry naming the feature.
- Executable bit: `100755` in the index, `rwxr-xr-x` on disk, `git diff --summary` empty
  (no mode change in the PR).
- All **36** tasks ticked, **0** unticked. Spot-checked T25, T26, T27, T28, T29, T29b,
  T30, T31, T32, T33, T34, T35 against the actual artifacts — all genuine.

## 11. The three declared deviations — all accepted

- **(a) mode bit repaired 100644 → 755.** Correct and necessary; `docs/INSTALL.md`
  documents `./harness-install.sh`. No mode change appears in the PR diff.
- **(b) `### Changing it later` → `### Changing either answer later`.** Correct: inserting
  `## The third question` reparented that `###` under the wrong toggle. The added scope
  sentence names both keys. No stale references to the old heading anywhere in the repo.
  The new intra-doc anchor `#the-third-question--pr_loopenabled` resolves correctly.
- **(c) R14 implemented as an extension of `test_suite_wiring_and_hygiene` per T29 rather
  than a separate `pr_loop_suite_hygiene`.** Accepted — following the task over the
  matrix's section label is the right call (one function, no duplicated `hrun`-only
  logic), and traceability is preserved verbatim in the `pass` line:
  `suite_wiring_and_hygiene / pr_loop_suite_hygiene … (R14, F02 R14)`.

## 12. Cross-file consistency

Collaborators the diff invokes were loaded and checked for contradiction:
`E18-F01`'s `seed_pr_loop_optin` / `migrate_config` / `_owners_*` / `_cfg_pr_loop_value`
(preconditions satisfied — the writer runs strictly after seed+migrate and strictly before
§5/§7b), `E20-F01`'s resolver/writer pair (extended, not modified), `docs/INSTALL.md`'s
"`init.sh` gains no new gate" promise (honored — no install-time `gh`/`jq`, proved
behaviourally by the stub check). `## Architecture alignment` is present and states
`ADRs touched: none` with a rationale — the ADR-citation check passes.

## Non-blocking observations (do NOT fix in this PR)

- **N1 — weak assertion.** `tests/test_installer_toggles.sh` R1 check (c3) uses
  `grep -qF 'gh' "$_x/prompt.sh"`, a bare substring that would match many words. It is
  non-vacuous today only by luck of the current menu wording. `grep -qF '`gh`'` would be
  the falsifiable form. The substantive assertion (`grep -qF 'Codex GitHub App'`) is fine.
- **N2 — fragile forbidden-token list.** The same check's structural loop forbids the
  literals `'gh '` and `'jq '` inside `pr_loop_prompt`'s body. Since the menu is prose, a
  benign reword ("an authed gh CLI") would fail the suite for no real reason.
- **N3 — cosmetic column drift.** `set_pr_loop_enabled` replaces only the value token, so
  the trailing comment shifts one column between `true` and `false`, and an installed
  target's gate line (17 spaces) does not align with the source repo's own (18). Fully
  deterministic, reversible and idempotent; byte convergence is unaffected. Not worth
  changing — realigning would risk R7's "trailing comment text verbatim".
- **N4 — silent abort.** When a config writer's `awk` genuinely fails, `set -e` aborts the
  installer with no message and leaves an orphan `$f.prwtmp`. Repo-wide across six writers;
  a cosmetic follow-up at most.
- **N5 — the one place the function-wrapper argument does not apply.**
  `harness-install.sh:4226` (the umbrella `manifest:` writer) uses the same
  `awk … && mv` shape at **top-level statement position**, not inside a function, so a
  failure there neither aborts nor reports. Pre-existing, DO NOT TOUCH, and skipping the
  `mv` is still the safe outcome — noted only for completeness.
- **N6 — process.** `state/tasks.json` shows `pending → in-review` directly; the
  intermediate `in-progress` the Builder reports is not visible in the diff (the work was
  never committed mid-flight). No action.

## Recommendation to the Orchestrator

1. Commit and open the PR. Run `/sdd-pr-loop` (this repo has `pr_loop.enabled: true`).
2. **Do not set `done` until the PR merges**, then roll it via `chore/E20-F02-done`.
3. Optional, as a separate item — not this PR: a one-line rule in `AGENTS.md` /
   `agents/builder.md` on the `cmd > tmp && mv tmp file` hazard, scoped precisely
   ("dangerous only when the producer's non-zero exit is an *expected* outcome, e.g.
   `grep -v` / `diff`"), so the next Builder does not re-derive it or over-correct the
   safe `awk` cases. Deliberately not added here to keep the PR inside the plan's
   "Files to change" table.
