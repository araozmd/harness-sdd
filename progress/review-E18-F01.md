---
feature: E18-F01
role: reviewer
date: 2026-07-27
branch: feat/E18-F01-sdd-pr-loop
verdict: APPROVE (implementation) — PR-ready AFTER two artifact fixes (B1, B2)
status_left_at: in-review
---

# Reviewer verdict — E18-F01 `/sdd-pr-loop` + vendored Codex watcher

**Implementation: APPROVE.** All 54 R-ids have a genuinely passing test, proven by
mutation testing rather than by reading the matrix. Environment, portability, hygiene,
dependency surface and source fidelity all verified independently of the Builder's
claims.

**Two committed-artifact defects must be fixed in the same PR (B1, B2 below).** Neither
is a code defect; both are one-command fixes in the spec artifacts.

---

## 1. Environment + full verification chain (real output)

`./init.sh` → **exit 0**

```
── harness-sdd init ──────────────────────────────
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (namespaces: specs/adr)
ℹ️  no project-specific checks (.harness/init.project.sh absent)
──────────────────────────────────────────────────
✅ environment ready — agents may proceed
```

Full `verification.test_command` chain (24 suites, one `&&` chain) → **CHAIN EXIT=0**,
**545 `ok -` assertions, 0 skips, 0 FAIL lines** (jq present on this box):

```
All install tests passed.            All umbrella tests passed.
All cascade tests passed.            All inception tests passed.
All reviewer tests passed.           All telemetry tests passed.
All mirror tests passed.             All epic-lifecycle tests passed.
All sdd-plan tests passed.           All sdd-drill tests passed.
All sdd-fix tests passed.            All architect-adr tests passed.
All drift-check tests passed.        All doc-critic contract tests passed.
All ownership tests passed.          All adr-citation tests passed.
All sdd-fix-parallel tests passed.   All dependency-diagnostics tests passed (17 checks).
All next-task selector checks passed. All model-routing tests passed.
All pr-loop tests passed.
CHAIN EXIT=0
```

`tests/test_pr_loop.sh` alone emitted 55 `ok -` lines covering R1–R51, R53, R54; R52 is
covered by the additive assertions in `tests/test_install.sh` (which passed).
`lint_command` / `typecheck_command` are empty in `harness.config.yaml` — nothing to run.

## 2. Traceability — verified by MUTATION, not by reading the matrix

Every R-id maps to a test that exists and passes. To prove the tests are not asserting on
strings that pass trivially, I copied the tree to a scratch dir and broke the
implementation seven ways. **Every mutation was caught:**

| # | Mutation | Test that killed it |
|---|---|---|
| 1 | Delete `$CMDDIR/sdd-pr-loop.md` when the gate is off (i.e. "generation is gated") | `FAIL: R1: pristine global prompt not reclaimed — the CMDDIR body must be generated on EVERY run` |
| 2 | Disable the §7b gate-off pass (`if ! pr_loop_enabled` → `if false`) | `FAIL: R5: gate flipped off but …/.claude/commands/sdd-pr-loop.md survived while the front-end is still selected` |
| 3 | Drop `select($since == "" or ((.created_at // "") >= $since))` from condition 1 | `FAIL: R25: a stale thread re-anchored to head must NOT count as this round's finding` |
| 4 | Remove clean-signal 2b (the issue-comment banner) | `FAIL: R26: the head banner delivered as an ISSUE comment must exit 3` |
| 5 | Remove the `jq` check from `preflight` | `FAIL: R31: missing jq must exit 5 (got 0)` |
| 6 | Freeze `0.39.0` in the suite | `FAIL: R51: the suite freezes an exact version-shaped literal` |
| 7 | Add an installer call without `CODEX_HOME=` | `FAIL: R51: an installer invocation does not sandbox CODEX_HOME` |

Weakest class: R36–R47 are `grep` assertions over the generated prompt body. That is
inherent — those requirements *are* about what the prose instructs — and the strongest of
them is substantive (R36 runs a `python3` ordering check proving `preflight` appears
before the `@codex review` post, not merely that both strings exist). Accepted as
spec-faithful.

## 3. Areas the Orchestrator asked me to scrutinize hardest

### (1) The DO-NOT-TOUCH edit to `tests/test_sdd_fix_parallel.sh` — ACCEPTED, minimal

`tests/test_sdd_fix_parallel.sh:550` changed exactly one needle:

```
-need "$ORCH" 'per-PR `/pr-loop`'      "R14: per-PR review loop missing"
+need "$ORCH" 'per-PR `/sdd-pr-loop`'  "R14: per-PR review loop missing"
```

- **Genuinely forced.** R48 renames the token, and `test_pr_loop.sh::test_prose_references_are_availability_phrased` actively asserts that **no bare `/pr-loop`** survives in `agents/orchestrator.md`. Keeping the old needle satisfiable would require violating R48. The two requirements are in direct conflict; the plan's DO-NOT-TOUCH entry is the one that had to yield.
- **Meaning unchanged.** `agents/orchestrator.md:102` now reads "run the per-PR `/sdd-pr-loop` for that PR alone"; the assertion still proves E15-F03 R14 ("the targeted worker runs a per-PR review loop"). The failure message is untouched.
- **Minimum.** `git diff main -- tests/test_sdd_fix_parallel.sh` is a 1-line change. `git diff main --stat` confirms the only other `tests/` file touched is `tests/test_install.sh`, which the plan explicitly allows ("additive assertions in `tests/test_install.sh`"). No third suite was touched.

### (2) R1's non-obvious invariant — CONFIRMED

`harness-install.sh:1892` writes `cat > "$CMDDIR/sdd-pr-loop.md" <<'EOF'` **unconditionally**, immediately after the `sdd-fix-parallel` heredoc, with an in-file comment stating why. Only the per-front-end mirroring (§5a/§5b/§5c/§5d) is wrapped in `pr_loop_enabled`.

Proven, not assumed: mutation #1 above deletes the CMDDIR copy on a gate-off run and `test_gate_off_still_reclaims_global_codex_prompt` fails immediately — a gate-off run then **cannot** reclaim an already-stamped `$CODEX_HOME/prompts/sdd-pr-loop.md`, exactly the orphan the invariant prevents.

### (3) The §7b gate-off reconciliation pass — CONFIRMED, and round-tripped by hand

- §7b sits at `harness-install.sh:2689`, **outside** the `if [ -n "$PRIOR_AGENTS" ]` block that closes at line 2687, and **before** `rm -rf "$CMDDIR"` at line 2769. The pristine references (`$CMDDIR/<name>.md`) are therefore still on disk when the compare runs. Mutation #2 proves the pass is load-bearing: the `PRIOR_AGENTS` vs `SELECTED` loop indeed never reaches a still-selected front-end.
- **Behavioral off→on→off round trip I ran myself** (scratch target, sandboxed `CODEX_HOME`, all 5 front-ends): install (7 artifacts stamped) → gate off (all 7 reclaimed, one aggregate warning naming each path) → gate on (all 7 restored) → gate off again → **zero residue**. Ungated glue (`/sdd-next`, role shims, global `sdd-next.md` prompt) survived every flip.
- Ownership rules honored per surface: by-name in `.claude/`, `.opencode/`; `remove_if_pristine` in `.agents/`; byte-`cmp` in the global `$CODEX_HOME/prompts/`. `rmdir` (never `rm -rf`) prunes, so a non-empty dir survives — verified live and by `test_reclaim_preserves_user_files_and_prunes`.

### (4) Test-suite hygiene — CLEAN, and the guards are live

- `tests/test_pr_loop.sh` freezes **no** `VERSION` string: `test_suite_is_wired_and_hygienic` greps its own source for `[0-9]+\.[0-9]+\.[0-9]+` and fails on a hit (mutation #6 confirms it fires). R54 asserts only the durable invariant — `VERSION` parses as `X.Y.Z` and `CHANGELOG.md` carries a heading for exactly that value.
- It diffs **nothing** against `main`: the same self-check greps for `origin/main|git diff|git show|git rev-parse`, with the needles string-split so the check never matches its own source line.
- **`CODEX_HOME` sandboxing is mechanically enforced, not just claimed.** Every installer run goes through `install_at()`, which sets `CODEX_HOME="$_ia_t/ch"`; there is also a suite-wide `export CODEX_HOME="$T/codex-home"` belt at line 26; and the self-check greps for any `sh "$SRC/harness-install.sh"` line lacking `CODEX_HOME` (mutation #7 confirms it fires). `tests/test_install.sh` already carries the same suite-wide export at line 17, so the new R52 assertions inherit it. No test can reach a developer's real `~/.codex/prompts`.

### (5) Dependency surface — CORRECT, and `gh --jq` genuinely cannot replace the one standalone use

- **`init.sh` is unmodified** (`git diff main -- init.sh` is empty). `test_init_has_no_new_dependency` builds a symlink mirror of the real `PATH` with `gh` and `jq` stripped and runs `./init.sh` in it → exit 0; it also greps `init.sh` for a `gh`/`jq` token. I ran `./init.sh` directly → exit 0.
- **Preflight checks exactly what the loop needs**, in order: `command -v gh` → `gh auth status` → `command -v jq` → repo slug → PR exists → PR is `OPEN`. Each has its own exit-5 branch with a one-line remedy; `test_preflight_failure_matrix` covers all five.
- **Every `gh`-sourced scalar already uses `gh --jq`**: `gh repo view --json owner,name --jq`, `gh api …/issues/comments/<id> --jq '.created_at'`, `gh pr view --json state --jq '.state'`; in the command body, `gh pr view --json number --jq`, `gh api graphql … --jq`, `gh repo view --json defaultBranchRef --jq`, `gh pr view --json headRefName --jq`.
- The **only** standalone `jq` in a `gh` pipeline is the `--paginate --slurp | jq 'add // []'` flatten — and `gh --jq` **cannot** do it. Verified on this box (gh 2.96.0):
  ```
  $ gh api --paginate --slurp --jq '.' …
  the `--slurp` option is not supported with `--jq` or `--template`
  ```
  The remaining standalone `jq` uses are over already-materialized local files (`evaluate` mode, the body's `fresh-comments.json` filter), where `gh --jq` is not applicable at all. **No misuse to flag.** `jq` is a genuine hard runtime dependency of the loop regardless, so `preflight` requiring it is exactly right.

### (6) Fidelity to the vendored source — HIGH; all four load-bearing behaviors survived

Compared `tools/wait-for-codex.sh` against `/Users/araozmd/repos/multi-cli-orchestrator/skills/pr-loop/scripts/wait-for-codex.sh` and `.claude/commands/sdd-pr-loop.md` against that skill's `SKILL.md`:

- **Three independent clean signals** — condition 2 (review banner `Reviewed commit` + 7-char head, `submittedAt >= trigger`), condition 2b (same banner as an **issue comment**, `.user.login`, `created_at >= trigger`), condition 3 (`+1` reaction by the bot). All three preserved with their jq predicates unchanged in shape, each with its own fixture test (R26a/b/c) and each individually mutation-killable (#4).
- **Freshness by `created_at`/`submittedAt`, never `commit_id` alone** — preserved verbatim, including the "GitHub re-stamps stale threads' commit_id" comment. `test_stale_reanchored_thread_is_not_a_finding` proves a `commit_id == head` comment predating the anchor stays *pending*, and `fresh-wrong-commit` proves the conjunction (both conditions required). Mutation #3 kills it.
- **Trigger id from the URL `gh pr comment` prints** — `trigger_url=$(gh pr comment …)`, `trigger_comment_id="${trigger_url##*issuecomment-}"`, carried over character-for-character, with the pagination rationale ("only the first 30 (oldest) comments") intact and an explicit prohibition on a separate list call.
- **All three comment sources fetched** (+ reactions = 4 files) — `pr.json`, `review-comments.json` (paginated `pulls/<n>/comments`), `issue-comments.json` (paginated `issues/<n>/comments`), `reactions.json`, plus `trigger-ts.txt`. The "`gh pr view` alone does NOT return Codex's findings" warning survives in both the watcher header and the command body.
- Correct bash→POSIX ports: `read -r owner repo < <(…)` → one command substitution + `${SLUG%% *}`/`${SLUG##* }`; `${head:0:7}` → `cut -c1-7`; `(( ))` → `[ … ]`/`$(( ))`; `while read … <<< "$unresolved"` → `printf | while read` (a subshell, but the loop body only calls `gh api`, so behaviour is identical). `merged` vs `merge_ok` separation, `--delete-branch`, the retry-once-after-30s fallback and the `resolveReviewThread` human-thread guard are all carried over.
- Deliberate, spec-sanctioned divergences: `MCO_*` → `HARNESS_*`, `route-task` → "a different worker if the host CLI offers one, else one combined in-session pass" (R41), `MCO_TOKEN_BUDGET_USD` dropped (out of scope), plus two **additions** — `preflight`, `evaluate` and the first-response probe.

### (7) Portability — VERIFIED by execution, not just by parse

`dash` **is** installed on this box, so R21's `dash -n` arm actually runs. Beyond the parse checks I executed the script under `dash` end to end:

```
sh -n tools/wait-for-codex.sh        → OK
dash -n tools/wait-for-codex.sh      → OK
bash -n tools/wait-for-codex.sh      → OK
dash … evaluate <pending fixture>    → rc=1
dash … evaluate <thumbs fixture>     → rc=3
dash … preflight 7 (no gh on PATH)   → rc=5, one-line diagnostic
dash … <pr> <trigger> <round> (stubbed gh, FIRST_RESPONSE=1) → rc=5, names the Codex GitHub App
dash … <pr> <trigger> <round> (stubbed gh, FIRST_RESPONSE=0, CEILING=1) → rc=2, "timeout"
```

This matters because `wfc_bot_seen` ends in a bare `return 1` under `set -eu` and uses
`[ … ] && return 0` inside `if` bodies — exercised live under `dash` and correct.

## 4. Conventions, cross-file consistency, ADR check

- **Nothing else on the plan's DO-NOT-TOUCH list was touched.** `git diff main --stat` confirms: `init.sh`, `store/tasks.schema.json`, `tools/next-task.mjs`, `tools/fix-worktree.sh`, `tools/sync-board.mjs`, `tools/tasks-lock.py`, `tools/validate-board.py`, `tools/task-diagnostics.py` — all unchanged. `MODEL_ROLES` and `ag_personas` gained no `pr-fixer` row (asserted mechanically by R14). `HARNESS_SDD_CMDS` is unchanged; the gated command lives in a separate `HARNESS_PR_LOOP_CMDS`, with `HARNESS_OWNED_CMDS` as the removal union.
- **`opencode.json` / `.opencode.stamp` byte-contract intact** (R12) — asserted by comparing two targets that differ only in `pr_loop.enabled`.
- **Cross-file consistency.** The `agents/orchestrator.md` change dispatches `/sdd-pr-loop`, which spawns `pr-fixer`. Loaded `agents/pr-fixer.md` and the generated body: `pr-fixer.md` "Out of scope" forbids pushing, thread resolution, merging and the full suite; the body has the **coordinator** push after all fixers return and resolve threads only at the terminal state. No contradiction. The E15-F03 parallel-worker precondition ("create only its dedicated PR ... never cancel siblings") is preserved verbatim around the reworded sentence.
- **ADR-citation check does not fire**: `specs/architecture.md` is absent in this repo. The spec records this explicitly under `## Architecture alignment` and states `ADRs touched: none` with a justification against ADR-0001. That satisfies the clause even if it had fired.
- `E18-F01.tasks.md`: **all 36 tasks ticked.**

---

## BLOCKING (fix in this PR, before merge)

**B1 — Tool-call residue committed at the end of all four E18-F01 spec artifacts.**

```
specs/epics/E18-vendored-pr-loop/F01-sdd-pr-loop-command/E18-F01.spec.md   ends: </content>\n</invoke>
specs/epics/E18-vendored-pr-loop/F01-sdd-pr-loop-command/E18-F01.plan.md   ends: </content>
specs/epics/E18-vendored-pr-loop/F01-sdd-pr-loop-command/E18-F01.tasks.md  ends: </content>
specs/epics/E18-vendored-pr-loop/F01-sdd-pr-loop-command/E18-F01.tests.md  ends: </content>
```

These are stray closing tags from the writing agent's tool call, not content. `E18-F01.spec.md`
is the **approved** artifact for a human gate, so shipping literal `</invoke>` in it is
corruption of the deliverable. Strip the trailing tag lines from all four files.
(Repo-wide scan: the only other instance is `specs/epics/E04-intake/epic.md`, i.e. this has
leaked once before — worth a harness guard, see H1.)

**B2 — `E18-F01.tests.md` traceability matrix is entirely unticked (54 × `⬜`).**

The repo convention is a fully-ticked matrix once the suite is green — `E17-F01.tests.md`
is 27/27 `✅`, `E16-F03.tests.md` is 17/17 `✅`. Every one of the 54 rows now has a
verified passing test (§2 above), so set the Status column to `✅`. Leaving it `⬜` means
the traceability artifact this harness's whole review contract keys on says the opposite
of the truth.

## ADVISORY (non-blocking — your call)

- **A1 — Word-boundary drift in the severity match.** The source SKILL specifies
  `\b(P0|P1|P2|nit)\b` (case-insensitive); the generated body and R39 say "match
  `P0|P1|P2|nit` case-insensitively **anywhere in the body**". Dropping `\b` means a
  substring hit (a path, a hash, `p10`) can classify a comment as P1 and make it blocking.
  The stated reason for dropping it — "so the shields.io badge form matches" — does not
  require it: `![P2 Badge](https://img.shields.io/badge/P2-yellow…)` matches `\bP2\b`
  fine (bounded by `[`/` ` and `/`/`-`). Restoring `\b(P0|P1|P2|nit)\b` in the body would
  keep R39 satisfied and remove an over-blocking failure mode. Spec-sanctioned as written,
  so flagged rather than blocked.
- **A2 — Misleading diagnostic on the §7b `.agents/` path.** `remove_if_pristine`
  (`harness-install.sh:1445`) prints "…left in place (**deselected** 'antigravity' not
  removed)". §7b calls it when the front-end is still **selected** and only the gate
  flipped, so the user is told a front-end was deselected when it wasn't. R6 is satisfied
  (the file is named), but the message is wrong. The `$CODEX_HOME` arm in §7b already
  emits the correct "(pr_loop disabled, not removed)" wording — consider a label/message
  parameter so the `.agents/` arm matches.
- **A3 — R31's "nothing was posted" assertion is weak.** It greps the five stderr files
  for the string `pr comment`; a stub that logged its argv would prove it positively. I
  verified by reading `wfc_preflight` that it invokes only `command -v`, `gh auth status`,
  `gh repo view` and `gh pr view --json state`, so the requirement genuinely holds — but
  the test would not catch a regression that added a post.
- **A4 — Trailing whitespace** on two added lines in `tests/test_install.sh` (the
  antigravity `pr-fixer` persona assertion and the codex `pr-fixer.toml` assertion).
- **A5 — Frontmatter drift (Orchestrator's, not the Builder's).** `E18-F01.spec.md`
  frontmatter still says `status: pending` while `state/tasks.json` says `in-review`.
  Prior features show `done` mirrored into the frontmatter at rollup; worth mirroring
  `in-review` too, or at least at the `done` transition.

## HARNESS IMPROVEMENT PROPOSED (not applied — needs a human)

- **H1 —** B1 is the second occurrence of tool-call residue leaking into a committed spec
  artifact. A cheap permanent guard: a check in `init.sh`'s structure sweep (warn-only, in
  the spirit of the ADR-citation sweep) that flags any `specs/**/*.md` whose last non-empty
  line matches `^</[a-z_]+>$`. I did **not** apply it — `init.sh` is on this feature's
  DO-NOT-TOUCH list (R53 forbids new gates), so it belongs in its own E99 fix rather than
  smuggled into this PR.

---

## Verdict

**APPROVE the implementation. Leave `E18-F01` at `in-review` — this is not the `done`
transition, the feature must merge first.**

**PR-ready: YES, once B1 and B2 land on this branch.** Both are edits to the four spec
artifacts only; no code, no test and no installer change is required, so the green chain
above still stands after they are applied. Re-running the chain after those edits is
prudent but not expected to be load-bearing (no suite reads the spec artifacts).

Behavioral end-to-end checks in `E18-F01.tests.md` that need live GitHub — running
`/sdd-pr-loop` against a real open PR with the MCO skills absent, and against a repo
without the Codex GitHub App — are **not** performed here and are best exercised on this
feature's own PR, which is the natural first live run.
