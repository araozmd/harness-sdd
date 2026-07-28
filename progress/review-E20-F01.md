---
feature: E20-F01
role: reviewer
date: 2026-07-28
branch: feat/E20-F01-backend-prompt
verdict: APPROVE (PR-ready) — 5 non-blocking findings
---

# Reviewer verdict — E20-F01 `execution.builder.backend` prompt

**APPROVE. PR-ready.** All 15 R-ids trace to checks that exist, pass, and — proved by my own
independent mutations — actually fail when the behavior is broken. `./init.sh` and the full
26-suite `verification.test_command` chain exit 0. The eight by-hand interactive items owed to
the Reviewer were executed over a real pty (`expect`) and all pass. Nothing on the DO-NOT-TOUCH
list moved.

Do **not** set `done` yet — this must merge first.

## 1. Environment (real output)

```
$ ./init.sh
── harness-sdd init ──────────────────────────────
✅ harness structure intact
✅ TaskStore (local) valid against schema
✅ ADR citations resolve (namespaces: specs/adr)
ℹ️  no project-specific checks (.harness/init.project.sh absent)
──────────────────────────────────────────────────
✅ environment ready — agents may proceed
```

Full `verification.test_command` chain (26 suites, run verbatim from `harness.config.yaml`):

```
CHAIN EXIT: 0
...
All agents-host tests passed.
ok - answer_mapping_unit: the answer→value mapping is pure, extractable and correct for every branch (R2)
ok - prompt_gating: the follow-up prompt is TTY-only, override-suppressed, asked after the picker, and holds no logic (R1)
ok - picker_unaffected: the front-end picker and its ladder are untouched (R3)
ok - override_precedence: flag beats env, both suppress the prompt, empty means no override (R4)
ok - illegal_override_aborts: an illegal override exits non-zero before touching the target (R5)
ok - non_interactive_is_inert: no TTY + no override asks nothing and changes nothing (R6)
ok - write_preserves_everything_else: exactly one scalar is rewritten; comments and hand-edits survive (R7)
ok - write_is_idempotent: an unchanged value leaves the config byte-identical (R8)
ok - migration_seeds_execution_block: a missing execution: block is appended once, append-only (R9)
ok - fresh_default_unchanged: a fresh install with no override seeds in-session (R10)
ok - delegate_without_cmd_warns: delegate with an empty delegate_cmd is written AND warned, never otherwise (R11)
ok - reports_once: exactly one report line per target; --print-agents stays at two stdout lines (R12)
ok - docs_document_backend_prompt: INSTALL.md and the installer's own text document the second question (R13)
ok - suite_wiring_and_hygiene: the suite is wired into verification.test_command and keeps its env discipline (R14)
ok - version_and_changelog: VERSION is semver with a matching CHANGELOG entry carrying the feature marker (R15)
All installer-toggle tests passed.
```

`lint_command` / `typecheck_command` are empty — n/a, matching `E20-F01.tests.md`.
`sh .harness/init.sh` in a freshly installed target also exits 0.

## 2. Mutation testing — mine, not the Builder's

19 mutations applied to a scratch copy of the repo, suite re-run after each, installer restored
byte-identical between runs. I deliberately targeted the **second** `elif [ -t 0 ]; then`
(harness-install.sh:1470, inside `resolve_builder_backend`) by line number after asserting
`builder_backend_prompt` appears in its context — a first-match `perl -0pi` would have hit
`resolve_agents` at line 1371 and passed vacuously, which is exactly the trap the Builder
reported.

**15 killed:**

| # | Mutation | Killed by |
|---|---|---|
| M1 | `builder_backend_answer` `*)` prints `in-session` | `R2: '' 'delegate' printed 'in-session', expected 'delegate'` |
| M2 | `1\|in-session` maps to `delegate` | `R2: '1' 'delegate' printed 'delegate', expected 'in-session'` |
| M3 | `[ -t 0 ]` → `true` **in `resolve_builder_backend` only** (line 1470) | `R1: the follow-up prompt was asked on a NON-INTERACTIVE run` |
| M4 | writer drops trailing-comment preservation | `R7: the backend line lost its indentation or its trailing comment` |
| M5 | skip-when-unchanged guard removed (always rewrite) | `R8: a no-override run TOUCHED harness.config.yaml` |
| M6 | env beats flag (precedence inverted) | `R4: --builder-backend did not beat HARNESS_BUILDER_BACKEND` |
| M7 | illegal override no longer `die`s | `R5: --builder-backend=turbo exited ZERO` |
| M8 | `delegate_cmd` warning fires unconditionally | `R11: the warning fired even though delegate_cmd is set` |
| M9 | `execution:` migration appends unconditionally | `R4: an empty override rewrote harness.config.yaml` |
| M10 | report line printed twice | `R12: printed 2 report lines, expected exactly 1` |
| M11 | empty `HARNESS_BUILDER_BACKEND` treated as an explicit `in-session` | `R6: a non-TTY run with NO override changed harness.config.yaml` |
| M12 | a `case` on the answer migrates into `builder_backend_prompt` | `R1: builder_backend_prompt contains 'case '` |
| M13 | `tui_capable` gains `BUILDER_BACKEND` | `R3: tui_capable gained builder-backend behavior` |
| M14 | writer's `mv "$1.bbtmp" "$1"` dropped | `R4: HARNESS_BUILDER_BACKEND=delegate did not resolve` |
| M15 | `HARNESS_BUILDER_BACKEND` stripped from `docs/INSTALL.md` | `R13: docs/INSTALL.md does not mention 'HARNESS_BUILDER_BACKEND'` |

**4 survived — all verified equivalent or covered by the by-hand checklist, none a defect:**

| # | Mutation | Why it survives |
|---|---|---|
| S1 | drop the `b &&` (builder-mapping) scope guard in `set_builder_backend` | Semantically equivalent today: `execution:` has exactly one nested mapping. Defensive depth beyond spec. See finding F4. |
| S2 | drop the `e &&` (execution-section) scope guard in `set_builder_backend` | Same: `backend:` occurs once as a key in the whole config. See finding F4. |
| S3 | `pre = substr($0,1,RLENGTH)` → hardcoded `"    backend: "` | R7's only fixture uses the canonical 4-space indent, so preserve and hardcode look identical. **The real code does preserve** — I re-indented the line to 6 spaces by hand and the write produced `······backend: delegate`. See finding F3. |
| S4 | `builder_backend_prompt "$_rbb_cur"` → `builder_backend_prompt "in-session"` | This is the documented residue: no POSIX suite can drive the prompt, so `E20-F01.tests.md` assigns "the third interactive run offers `delegate`" to the Reviewer. **I ran it over a pty and it offered `delegate`** (§4). Correctly delegated, not a hole. |

## 3. Config write — byte-level verification (§2 of the brief)

Independently exercised against real installed configs, outside the suite:

- **Value preservation.** `backend: in-session      # KEEP-THIS-TRAILING-COMMENT` →
  `backend: delegate      # KEEP-THIS-TRAILING-COMMENT`; `diff` shows exactly 1 removed / 1
  added line; all 153 comment lines survive; an unrelated hand-edited `workflow.identity`
  sentinel and an EOF `# HUMAN NOTE` line survive.
- **Idempotence, no oscillation.** Same value twice ⇒ `cmp` identical **and** `find -newer`
  proves the file was not touched at all (the writer is genuinely *skipped*, not re-run with
  identical bytes). No-override non-TTY runs ⇒ identical.
- **Append-only migration is genuinely used.** Stripping the whole `execution:` block and
  re-running restores it at EOF; `head -n <old-line-count>` of the new file `cmp`s byte-identical
  to the stripped file, i.e. nothing above the append moved. A second run appends nothing;
  a trailing comment on `execution:   # my note` does not cause a duplicate.
- **Unnamed edges (both handled correctly).**
  - `    backend:   # keep me` (empty value + comment) → `    backend:   delegate # keep me`.
    The comment survives **as a comment** (the leading space is inserted), flips back to
    `in-session` with the comment intact, and is idempotent.
  - `    backend:` (empty value, no comment) → `    backend: in-session` on a non-TTY,
    no-override run, then converges (second run byte-identical). See finding F2.
  - `backend: "in-session"` (quoted) → read correctly, non-TTY run leaves it **byte-identical**;
    an explicit override normalizes it to unquoted `delegate`. Acceptable.

## 4. By-hand interactive checklist over a pty — all 8 items PASS

Driven with `expect` on a real pty (raw picker) and again with `stty` removed from `PATH`
(numbered `toggle_select` fallback).

| Checklist item | Result |
|---|---|
| Picker first, unchanged, then a single backend prompt naming `in-session` | PASS — `agents: interactive selection (claude)` then `Which builder backend…` / `choose 1/2 [Enter keeps in-session]:` |
| Enter ⇒ `backend: in-session` | PASS |
| Re-run, answer `2` ⇒ `backend: delegate`, warning names `execution.builder.delegate_cmd`, every comment present | PASS — 1-line diff, comment count 153 → 153 |
| Third run offers **`delegate`** as the default; Enter ⇒ file unchanged | PASS — `>>> DEFAULT OFFERED = delegate`, `byte-identical after Enter` |
| Garbage `xyzzy` ⇒ current kept, proceeds, no loop/abort | PASS — exit 0, `byte-identical after garbage` |
| Ctrl-C at the backend prompt leaves the terminal usable | PASS — `INSTALLER_RC=130`, `stty -g` before/after **identical**, nothing written into the target |
| Non-raw rung (`stty` off `PATH` ⇒ `toggle_select`) shows the identical backend prompt | PASS — same three menu lines and same `choose 1/2 [Enter keeps in-session]:` |
| `tests/test_install.sh` absent from the PR diff | PASS — `git diff --name-only` = `CHANGELOG.md VERSION docs/INSTALL.md harness-install.sh harness.config.yaml state/tasks.json` |

## 5. Blast radius on merged work — clean

Function bodies extracted from `HEAD` and from the working tree and hashed:
`tui_select`, `toggle_select`, `tui_capable`, `normalize_keys`, `validate_csv`, `resolve_agents`,
`detect_host`, `precheck_baseline`, `seed_pr_loop_optin`, `pr_loop_enabled`, `_cfg_pr_loop_value`
— **all byte-identical**. `AGENT_KEYS="claude gemini opencode antigravity codex"` unchanged.
The `.sdd-pr-loop.owners` ledger text is unchanged (line number shift only).
`git diff -U0` removes exactly **one** line from the installer — a usage comment.
`--print-agents` stdout is still exactly 2 lines (`host=`, `baseline=claude`) and carries no
report marker. Umbrella cascade prints exactly one report line per target (3 targets ⇒ 3 lines)
and applies the override to each. An illegal override aborts before target resolution, even under
`--umbrella --dry-run`.

## 6. Hygiene (R14) — clean

`grep -ci drift harness-install.sh` = **0**. No `0.42.0` literal in the new suite. No `git diff`
in the new suite. `tests/test_install.sh` out of the diff. Suite wired into
`verification.test_command`. Every installer invocation goes through the single `hrun` gateway
(`env -i PATH … HOME=$_hr_dir/home CODEX_HOME=$_hr_dir/ch`) — the only other `harness-install`
mentions in the file are the read-only `INST=`, two `grep` targets and a message string.

## 7. The two declared deviations — both accepted

**(a) `resolve_builder_backend` reads `$1/.harness/harness.config.yaml` instead of `$H`.**
Accepted. `H="$TARGET/.harness"` is set unconditionally at `harness-install.sh:1518`, the single
place `H` is ever assigned, and `resolve_builder_backend "$TARGET"` is called 46 lines later in
the same function — the paths are provably identical, and taking the target as an argument makes
the resolver a function of its input rather than of an ambient global. No behavior difference.

**(b) `version_and_changelog` pins no MINOR floor.** Accepted, and the judgement is made here:
`VERSION` is now **0.42.0** (was 0.41.0). `AGENTS.md` → Versioning: *"MINOR = new
backward-compatible capability (✨)"*. This PR adds a new interactive prompt, a new CLI flag, a
new env var, and a new `migrate_config` entry to the **installed body**, with no breaking change
and no `tasks.schema.json` touch. **MINOR is correct.** The CHANGELOG entry is `## [0.42.0]` with
an `### Added — ✨` heading, consistent. The Builder is right that pinning `-ge 42` would have been
the "compare against a hard-coded previous version" anti-pattern `E20-F01.tests.md` forbids.

## 8. Traceability matrix — verified R-id by R-id

| R-id | Check | Exists | Passes | Fails when broken |
|---|---|---|---|---|
| R1 | `prompt_gating` | ✅ | ✅ | ✅ M3, M12 |
| R2 | `answer_mapping_unit` | ✅ | ✅ | ✅ M1, M2 |
| R3 | `picker_unaffected` | ✅ | ✅ | ✅ M13 + byte-hash diff vs HEAD |
| R4 | `override_precedence` | ✅ | ✅ | ✅ M6, M9, M14 |
| R5 | `illegal_override_aborts` | ✅ | ✅ | ✅ M7 |
| R6 | `non_interactive_is_inert` | ✅ | ✅ | ✅ M11 |
| R7 | `write_preserves_everything_else` | ✅ | ✅ | ✅ M4 (see F3) |
| R8 | `write_is_idempotent` | ✅ | ✅ | ✅ M5 (`find -newer`, not just `cmp`) |
| R9 | `migration_seeds_execution_block` | ✅ | ✅ | ✅ M9 |
| R10 | `fresh_default_unchanged` | ✅ | ✅ | ✅ + pty Enter run |
| R11 | `delegate_without_cmd_warns` | ✅ | ✅ | ✅ M8 kills the **negative** direction |
| R12 | `reports_once` | ✅ | ✅ | ✅ M10 + `--print-agents` 2-line freeze |
| R13 | `docs_document_backend_prompt` | ✅ | ✅ | ✅ M15 |
| R14 | `suite_wiring_and_hygiene` | ✅ | ✅ | ✅ re-verified by hand |
| R15 | `version_and_changelog` | ✅ | ✅ | ✅ judgement made in §7 |

Cross-file consistency: R11's rationale depends on `agents/builder.md` Loop B step 2 —
*"Read `execution.builder.delegate_cmd`. If it is empty, STOP and report the misconfiguration —
do NOT silently fall back to writing code yourself."* — which is present and unmodified. No
contradiction. ADR check: `specs/architecture.md` is absent, so the ADR-citation clause does not
fire; the spec nonetheless carries `## Architecture alignment` with `ADRs touched: none` and
`init.sh` reports ADR citations clean. `E20-F01.tests.md` leaving the matrix Status column as ⬜
matches the merged E19 features (45/45 ⬜ there).

## 9. Findings — all NON-BLOCKING, none gates this PR

**F1 — the new `execution:` migration block does not converge with the source config's, breaking
a documented invariant of the function it was added to.** `harness-install.sh` `migrate_config`
states this rule twice, for `models:` and for `pr_loop:`: *"Keep this block byte-identical to the
tail of the source `harness.config.yaml`, so a FRESH install (which copies the config verbatim and
never migrates) and an UPGRADED install (which only migrates) converge on the same text."*
The new E20-F01 entry does not. Verified empirically — a fresh install gets
`harness.config.yaml:48-70` ("The harness's single extension point for plugging in an EXTERNAL
executor…"), while a migrated install gets the new heredoc ("Builder execution backend. Asked by
the installer's follow-up prompt; also settable with `--builder-backend=…`"). Same YAML values,
different comment text. Not a spec violation (no R-id requires convergence; E18-F01's R17 was
scoped to `pr_loop`), and positional convergence is impossible here because the source block sits
mid-file rather than at the tail — but the **text** could still be aligned. Cheap fix: make the
two comment bodies identical.

**F2 — the most consequential half of F1: a fresh install, the majority path, gets the *less*
discoverable comment.** The feature's stated value is discoverability, and the migrated block is
the only one that names `--builder-backend=` / `HARNESS_BUILDER_BACKEND` and the prompt. A fresh
target's `harness.config.yaml` — the file the human actually edits — mentions neither. R13 is
satisfied (`docs/INSTALL.md` + the installer's own summary text both document it), so this is a
nit, but adding the two-line header comment to `harness.config.yaml:48` would close it and F1 at
the same time.

**F3 — `set_builder_backend` silently no-ops when `execution:` exists but the `backend:` key does
not, while still reporting success.** Reproduced: delete only the `backend:` line from an installed
config, then `--builder-backend=delegate`. The installer prints
`builder backend: delegate (explicit --builder-backend/HARNESS_BUILDER_BACKEND)` and the
`delegate_cmd` warning, writes nothing, and the next run reports `in-session (unchanged)` — the
report line lies. `migrate_config`'s header-only presence check is deliberate and well argued (a
second `builder:` mapping would be invalid YAML), and I confirmed from `git show 47f2d1d` that the
`execution:` block has carried `builder.backend` since the day it was introduced, so **no real
upgrade path produces this shape** — it needs a hand-mangled config. Worth hardening in E20-F02
(read the value back after the write and warn if it did not take), not worth blocking.

**F4 — R7's indentation assertion cannot distinguish "preserve" from "hardcode".** Mutation S3
replaced `pre = substr($0,1,RLENGTH)` with a literal `"    backend: "` and the suite stayed green,
because the only fixture uses the canonical 4-space indent. The production code **is** correct — I
re-indented the key to 6 spaces and the writer emitted `······backend: delegate`. One extra fixture
at a non-canonical indent would close it.

**F5 — the writer's and reader's scope guards are currently unreachable, so untested.** Mutations
S1/S2 removed the `b &&` (inside-`builder:`) and `e &&` (inside-`execution:`) guards from
`set_builder_backend` and the suite stayed green, because `backend:` appears exactly once as a key
in the whole config. The guards are correct and worth keeping — they are what makes a future
sibling (`architect:`) or a `backend:` key under another section safe — but they become
load-bearing the moment E20-F02 adds a second toggle. A fixture with a decoy `backend:` under a
different top-level section would make them falsifiable.

**Observation, not a finding.** `HARNESS_BUILDER_BACKEND=turbo ./harness-install.sh --print-agents <t>`
now aborts non-zero. That is consistent with R5 ("before creating or modifying any file") and with
how `--agents` behaves, and it is a user error either way — flagging only so it is a conscious
choice rather than a surprise.

## 10. Verdict

**APPROVE — PR-ready.** Open the PR and run the Codex `/pr-loop`. Orchestrator: do **not** set
`done` until it merges. F1–F5 are follow-up material; F1/F2 are a two-line edit if you want them
in this PR, and F4/F5 are natural fixtures to add when E20-F02 lands the second toggle on the same
machinery.
