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

---

## Amendment (human-directed, arrived during review): `pr_loop.enabled` becomes OPT-IN

The human overruled the spec's opt-out default at the review gate. `/sdd-pr-loop` only
works on a repo with the Codex GitHub App installed plus an authed `gh`, so an opt-out
default meant every fresh install grew a command that could do nothing but fail its own
preflight. Recorded as a spec-level decision (spec Open questions → "Flagged for the human
gate — decided: `false`"), then implemented across spec, plan, tasks, tests, code and docs
— tasks T37–T42 in `E18-F01.tasks.md`.

### What changed

- **`pr_loop_enabled()` inverted** (`harness-install.sh`): exit 0 **only** when the
  resolved value is the literal `true`. Absent block, absent key, empty value and any
  other token (`yes`, `1`, `True`, `on`) all resolve **off**. Precedence is unchanged:
  `HARNESS_PR_LOOP_ENABLED` env → config value → built-in default (now `false`).
- **Seeded block flipped to `enabled: false`**, with a comment block explaining the opt-in
  and naming the Codex-GitHub-App + authed-`gh` precondition. Applied in BOTH places that
  must agree: the `migrate_config` heredoc, and a new **`seed_pr_loop_optin`** helper the
  fresh-seed path runs right after the `sed` that blanks the verification commands.
- **`R18b`** added to the spec: present-but-not-`true` ⇒ off, exactly as for an absent key.
- Docs restated: `README.md`, `docs/INSTALL.md`, `docs/HARNESS.md`, `docs/WORKFLOW.md`,
  `CLAUDE.md`, `agents/orchestrator.md`, `manifest.txt`, and the generated command body
  (new `pr_loop.enabled` row in its Configuration table) plus its source-layout mirror
  `.claude/commands/sdd-pr-loop.md`.
- `CHANGELOG.md` amended **under the existing unreleased `0.39.0` heading**; `VERSION` was
  NOT bumped again.

### Non-obvious consequences

1. **The seed could not simply copy this repo's config.** A fresh install `cp`s the source
   `harness.config.yaml` verbatim, and this repo legitimately keeps `enabled: true` (it has
   the Codex App and an active review loop). Without intervention the opt-in would leak
   `true` into every target. Hence `seed_pr_loop_optin` — a section-scoped `awk` rewrite of
   the `enabled:` line only, mirroring the existing "blank the verification commands on
   seed" pattern. Its replacement line is byte-identical to the one `migrate_config`
   appends, which is what keeps R17 (seeded block == migrated block) true; the R17 test
   still passes and the only difference between the source config's block and the migrate
   heredoc is that one value.
2. **The header comment above `pr_loop:` is inside the R17-compared region.** A "this repo
   opts in" note added only to `harness.config.yaml` would have broken byte-identity. The
   note is therefore worded so it is true in both contexts and lives in both copies:
   `# (The harness's own source repo opts in; every fresh install is seeded with false.)`
3. **`tools/wait-for-codex.sh` needed no change and was NOT touched** (verified: `git diff`
   empty). It is env-only and never parses YAML — its only `pr_loop.enabled` mentions are
   two remedy strings inside preflight/first-response diagnostics, which stay correct.
4. **The gate-off reclamation warning was reworded** from `pr_loop.enabled is false` to
   `pr_loop.enabled is not true`, because that pass now also fires for an absent or
   malformed key. The R5 assertion follows it.
5. **Test polarity flipped everywhere.** A plain `install_at` is now a *gate-off* run, so
   every "the loop is installed" assertion has to arm the gate first. Two idioms:
   `install_on` (env override — for rows that only need the glue present, and which keeps
   the target's config the untouched *seeded* one so R15 can assert against it) and
   `set_gate <t> true` (config axis — `set_gate` now falls back to the source config when
   the target has not been installed yet, so a preserved opt-in config can be pre-seeded).
6. **`tests/test_install.sh` exports `HARNESS_PR_LOOP_ENABLED=true` suite-wide.** Its R52
   job is the command-surface contract (generated per front-end, reclaimed on deselect),
   which has no subject when the loop is off. The opt-in default itself is owned by
   `tests/test_pr_loop.sh` (R3/R15/R18/R18b), which never sets that variable.
7. **`telemetry:` also has an `enabled:` key at the same indent.** The first cut of the R15
   assertion used a bare `grep '^  enabled: true'` and matched the telemetry one. Added a
   `cfg_pr_loop_enabled` helper to the suite — the test-side mirror of the installer's
   section-scoped `_cfg_pr_loop_value` — and every gate-value assertion now goes through it.
8. **`.harness/agents/pr-fixer.md` is still installed on a gate-off target.** That is the
   canonical role *body*, part of the harness body copied verbatim, and R9 asserts it is
   present in the profile. R3 forbids only front-end *artifacts* (`.claude/agents/`,
   `.opencode/agent/`, `.agents/agents/`) and the command copies — none of which appear.

### New test (the regression probe)

`tests/test_pr_loop.sh::test_absent_enabled_key_resolves_off` (R18b): a config whose
`pr_loop:` block exists but has no `enabled:` key, plus empty / `yes` / `1` / `True` /
`TRUE` / `on` / `false` values, must all stamp nothing; the literal `true` must still arm
the gate through the same path. **Verified to fail against the old opt-out logic**: with
`pr_loop_enabled()` temporarily restored to `[ "$_prl_v" = "false" ] && return 1; return 0`
the test reports `FAIL: R18b: an absent pr_loop.enabled key must resolve OFF`; the file was
restored immediately afterwards.

### Verification

- `./init.sh` → `environment ready — agents may proceed`.
- Full `verification.test_command` chain (24 suites) green, 548 `ok -` lines, zero `FAIL`.
- Live demo: a fresh install seeds `pr_loop.enabled -> false` and stamps **no**
  `sdd-pr-loop.md` and **no** front-end `pr-fixer.md`; a preserved pre-E18 config with no
  `pr_loop:` block at all behaves identically; a target carrying this repo's own config
  (explicit `enabled: true`) stamps all four command surfaces plus the three `pr-fixer`
  shims.
