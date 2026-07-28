---
feature: E18-F01
role: builder
date: 2026-07-27
branch: feat/E18-F01-sdd-pr-loop
status: implemented, self-checked green — ready for in-review (Orchestrator's call)
---

# Builder handover — E18-F01 `/sdd-pr-loop` + vendored Codex watcher

Precondition confirmed before writing any code: `state/tasks.json` had `E18-F01` at
`status: in-progress` (human-approved), `sdd: true`, `autonomous: false`.

All **36 tasks** in `E18-F01.tasks.md` are implemented and ticked. All **54 R-ids** have a
passing check in `tests/test_pr_loop.sh` (plus the additive `tests/test_install.sh`
assertions for R52).

## What landed

**Block A — config + watcher**
- `harness.config.yaml`: new top-level `pr_loop:` block (`enabled`/`auto_merge`/
  `max_rounds`/`blocking_severities`/`merge_strategy`), placed at the tail after `models:`.
- `harness-install.sh`: `_cfg_pr_loop_value` (section-scoped `awk`, modeled exactly on
  `_cfg_models_value`) + a `pr_loop_enabled` helper whose precedence is
  **`HARNESS_PR_LOOP_ENABLED` env → config → built-in default `true`**; a `pr_loop:` arm in
  `migrate_config` whose block text is byte-identical to the source config tail (asserted).
- `tools/wait-for-codex.sh`: the vendored watcher, ported to POSIX `sh`. Three modes
  (`wait` / `preflight <pr>` / `evaluate <round-dir>`) sharing **one** evaluation routine.
  All four source files, the `--paginate --slurp | jq 'add // []'` fetches, the four
  evaluation conditions and their jq predicate shapes are preserved verbatim. Exit
  contract: `0` findings · `1` pending (`evaluate` only) · `2` timeout · `3` clean ·
  `4` usage/unresolvable trigger ts · `5` preflight failure / no first response.
- `chmod +x` in the installer; `.pr-loop/` in the seeded `.harness/.gitignore`;
  `/.pr-loop/` in the repo-root `.gitignore` (the dead `.mco-cache/` entry is gone).

**Block B — command, mirroring, gate**
- The `sdd-pr-loop.md` heredoc is written into `CMDDIR` **unconditionally** (R1) and only
  the per-front-end mirroring is gated. Comment in the installer states why.
- New ledgers: `HARNESS_PR_LOOP_CMDS` (emission, gated) and
  `HARNESS_OWNED_CMDS = $HARNESS_SDD_CMDS $HARNESS_PR_LOOP_CMDS` (removal, always).
  `pr-fixer` joins `HARNESS_CLAUDE_SHIMS` as a **removal-ledger entry only**.
- §7 deselect: every reclamation loop widened to `$HARNESS_OWNED_CMDS`, plus each
  front-end's `pr-fixer` artifact (by name in `.claude`/`.opencode`, `remove_if_pristine`
  in `.agents/`).
- **§7b (new)** — the gate-off reconciliation pass, placed after the deselect loop and
  **before** `rm -rf "$CMDDIR"`. It walks every *still-selected* front-end, which is the
  axis the `PRIOR_AGENTS` vs `SELECTED` loop structurally cannot reach.

**Block C — the `pr-fixer` role**
- Canonical, front-end-neutral `agents/pr-fixer.md` (the four vendored bodies collapsed to
  one). No existing canonical role was forked.
- Gated shims: `emit_agent pr-fixer` (Claude), a new hoisted `gen_oc_agent` writing
  `.opencode/agent/pr-fixer.md` with `mode: subagent`, and `gen_ag_persona pr-fixer` called
  **outside** the `ag_personas` loop. `MODEL_ROLES`, `ag_personas`, `gen_opencode_json` and
  the `.opencode.stamp` machinery are untouched — no codex/gemini artifact is created.

**Block D — de-MCO, docs, tests, version**
- The three `/pr-loop` references are now availability-phrased `/sdd-pr-loop` with an
  explicit "otherwise, by hand" alternative. No prose-templating mechanism was introduced.
- Body sweep is clean: no `MCO_`, `.mco-cache`, `~/.agents/skills`, `route-task` or
  `start-feature` token remains anywhere in the installed body.
- Source-layout `.claude/commands/sdd-pr-loop.md` + `.claude/agents/pr-fixer.md` (paths
  resolve from the repo root, asserted both ways).
- `README.md`, `docs/INSTALL.md`, `docs/WORKFLOW.md`, `docs/HARNESS.md` updated.
- `VERSION` `0.38.1 → 0.39.0` (MINOR — new backward-compatible capability) + a matching
  `CHANGELOG.md` entry.

## Self-check (real output)

`./init.sh` → exit 0.

Full `verification.test_command` chain (24 suites, run as one `&&` chain):

```
FULL CHAIN EXIT=0
545          # count of `ok - ` assertions
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
All adr-citation tests passed.
All sdd-fix-parallel tests passed.
All dependency-diagnostics tests passed (17 checks).
All next-task selector checks passed.
All model-routing tests passed.
All pr-loop tests passed.
```

`tests/test_pr_loop.sh` alone: 56 assertions, 0 skips on this box (jq present), ~45s.
`sh -n` and `dash -n` both parse `tools/wait-for-codex.sh` clean.

## Spec deviations (2, both minimal — please confirm at review)

1. **`tests/test_sdd_fix_parallel.sh:550` needle updated.** The `.plan.md` DO-NOT-TOUCH list
   says "existing `tests/*.sh` other than the additive assertions in `tests/test_install.sh`",
   but that suite asserts the literal string ``per-PR `/pr-loop` `` inside
   `agents/orchestrator.md`, which **R48 mandates renaming**. The two requirements are in
   direct conflict. I changed exactly one needle to ``per-PR `/sdd-pr-loop` `` — the
   assertion's meaning (E15-F03 R14: the targeted worker runs a per-PR review loop) is
   unchanged. No other existing suite was touched.
2. **`docs/HARNESS.md` had no command inventory to modify.** The plan says "modify: command
   inventory"; the file is a short conceptual doc with no such section. I added a
   "## The commands this harness ships" table (all seven commands, with `/sdd-pr-loop`
   marked as the one gated on `pr_loop.enabled`) rather than bolting the requirement onto
   unrelated prose.

Two smaller implementation choices worth naming:

- **`gh --jq` vs standalone `jq`** (per the Orchestrator's note): every gh-sourced *scalar*
  read (repo slug, trigger timestamp, PR state) uses `gh`'s built-in `--jq`, so no extra
  binary is needed there. Standalone `jq` remains for (a) the `--paginate --slurp |
  jq 'add // []'` flatten, which T5 mandates preserving unchanged in shape, and (b) the
  offline `evaluate` mode over already-materialized local files, which `gh --jq` cannot
  produce. The `preflight` check therefore genuinely matches what the loop requires.
- **`.opencode/agent/pr-fixer.md` keeps the vendored `permission: {edit, bash}` block**
  alongside `description` + `mode: subagent`. The plan named only the latter two; dropping
  the permissions would leave the sub-agent unable to edit or commit, which is its whole job.

## Notes for the Reviewer

- `init.sh` and `store/tasks.schema.json` are **unmodified** (`git diff --stat` empty for both).
- `test_gate_off_still_reclaims_global_codex_prompt` is the R1 probe: it fails iff CMDDIR
  generation is ever gated, because the pristine reference would be gone.
- Every installer-invoking run in the new suite goes through one `install_at()` helper that
  sandboxes `CODEX_HOME` under the suite's temp dir; `test_suite_is_wired_and_hygienic`
  asserts that mechanically, plus "no frozen version-shaped literal" and "nothing compared
  against the default branch" over the suite's own source.
- The behavioral end-to-end checks in `E18-F01.tests.md` (running the loop against a real
  open PR, and against a repo without the Codex GitHub App) are the Reviewer's to perform —
  they need live GitHub and are not automatable here.

Reporting to the Orchestrator for `in-review`. Not declaring `done`, and no PR opened.
