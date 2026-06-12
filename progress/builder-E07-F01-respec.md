---
feature: E07-F01
role: builder
action: re-spec implementation (.agent/ → .agents/ rename + best-effort persona + strengthened tests)
date: 2026-06-12
branch: feat/E07-F01-antigravity-support
status: implemented, self-checked green, ready for in-review (Orchestrator drives the held pr-loop)
---

# E07-F01 re-spec — Builder hand-off

Confirmed feature `status: in-progress` (spec frontmatter, human-approved re-spec) before
writing code. Worked `F01-antigravity-support.tasks.md` T1–T12 top to bottom on the existing
branch. The change is the human-approved `.agent/` (singular) → `.agents/` (plural) rename of
the Antigravity glue, plus honest best-effort persona prose and strengthened (beyond-existence)
tests. No canonical `agents/*.md` role body was forked, copied, or edited.

## Tasks completed (all 12 ticked)
- **T1** (R2,R4,R6) — §5c `mkdir -p` now creates `.agents/{rules,agents,workflows}` (plural).
- **T2** (R2,R3,R12) — `gen_ag_rule` dest → `.agents/rules/harness.md`; rule body working-model
  prose updated to plural `.agents/agents/` + `.agents/workflows/` and states R12 explicitly
  (drives via `description`-gated workflows + personas + `.harness/progress/` hand-off; NOT a
  Task-tool spawn, NOT an asserted bare-file subagent registration). No role body.
- **T3** (R4,R5) — persona loop dest → `.agents/agents/$_agr.md`; body unchanged; comment now
  marks personas best-effort (discovery unconfirmed, written-not-claimed-to-register).
- **T4** (R6,R7,R8,R9) — workflow `cp` dest → `.agents/workflows/$_w.md` (mirror from `$CMDDIR`).
- **T5** (R12) — `ok` line → `Antigravity glue (rules + agents + workflows) installed (.agents/)`.
- **T6** (R13) — §7 antigravity-deselect branch: every `remove_if_pristine` relpath →
  `.agents/...` (rule, personas loop, workflows loop) and all four `rmdir` prune targets →
  `.agents/{rules,agents,workflows}` + `.agents`. Byte-compare safety contract UNCHANGED
  (pristine-only removal, never user files, never `rm -rf`); shared-GEMINI.md logic untouched.
- **T7** (R10) — §3 manifest.txt HARNESS-OWNED glue line → `.agents/rules/*  .agents/agents/*
  .agents/workflows/*`.
- **T8** (R1,R12) — §4 GEMINI.md comment path → `.agents/rules/harness.md`. No behavioral change.
- **T9** (R10) — `CHANGELOG.md` `## [0.22.0]` Antigravity section: every `.agent/` → `.agents/`
  (plural, with a "dir its current build scans" note); added best-effort-persona clause + a
  durable-working-model bullet; R-id coverage line now reads R1–R13. **VERSION NOT bumped.**
- **T10** (R11) — `tests/test_install.sh` glue assertion group: every `$T/.agent/...` →
  `$T/.agents/...`; shape-not-existence assertions kept/confirmed; R4/R5 comment now states
  shape-only / best-effort (no registration claim).
- **T11** (R11,R13) — three Antigravity/GEMINI.md regression tests repointed to `.agents/`,
  including the negative `--agents=claude must not write .agents/` check and the user-dir
  preservation test (now places a user file under the harness-owned `.agents/` at a path the
  harness does not generate, so the dir survives non-empty).
- **T12** — full `verification.test_command` suite + `./init.sh` green; no stray singular
  `.agent/` remains.

## Exact files / lines changed
- `harness-install.sh`
  - line 11 — header comment `(.agent/, …)` → `(.agents/, …)`.
  - line 569 — manifest.txt HARNESS-OWNED glue line → plural.
  - lines ~668–703 — generator-helper comments (`gen_ag_rule`/`gen_ag_persona` headers,
    block header) → plural.
  - lines ~692–699 — rule body "Working model (R12)" prose → plural + explicit no-spawn /
    no-registration wording.
  - line ~759 — §4 GEMINI.md path comment → `.agents/rules/harness.md`.
  - lines ~1058–1094 — §5c block header + `mkdir -p` + `gen_ag_rule` dest + persona-loop dest +
    workflow-`cp` dest + `ok` line → plural; persona comment marked best-effort.
  - lines ~1097–1099 — deferred-CMDDIR NOTE comment → plural.
  - lines ~1166–1199 — §7 antigravity-deselect branch comments + `remove_if_pristine` relpaths +
    `rmdir` prune targets → plural. Safety logic byte-for-byte unchanged.
- `tests/test_install.sh`
  - lines ~116–162 — Antigravity glue assertion group (R1–R11) → plural; R4/R5 comment now
    shape-only/best-effort.
  - line 248 — `[ -d "$TB/.agents" ]` negative check (claude-only must not write the glue dir).
  - line 294 — `--agents=antigravity` test → `$TAG/.agents/rules/harness.md`.
  - lines ~404–416 — user-dir-preservation test → `.agents/` (user file at harness-owned
    `.agents/user-config.md`, a path the harness never generates; dir survives non-empty).
  - lines ~418–442 — byte-exact deselect regression → `.agents/` throughout.
- `CHANGELOG.md` — `## [0.22.0]` Antigravity section reworded to `.agents/` plural + best-effort
  persona + durable-working-model bullet; R1–R13. (The historical `## [0.21.0]` entry's
  placeholder reference is released-behavior prose and left untouched.)
- `specs/.../F01-antigravity-support.tasks.md` — T1–T12 ticked.

## VERSION confirmation
`VERSION` = **0.22.0** — NOT re-bumped (same MINOR capability; the re-spec corrects the
unreleased feature path). `tests/test_install.sh` version-stamp assertion (R10) passes against
the source VERSION.

## Strengthened assertions (R-ids) — shape, not file-existence
- **R2** — rule exists under `.agents/rules/` AND points at `.harness/AGENTS.md` AND
  `.harness/agents/orchestrator.md`.
- **R3** — `$AG_SENTINEL` (canonical orchestrator body) is ABSENT from the rule (no fork).
- **R4** — each persona under `.agents/agents/` exists AND carries `^description:`.
- **R5** — each persona defers to `.harness/agents/<role>.md`, mandates `.harness/init.sh`,
  hands off via `.harness/progress/`, AND `$AG_SENTINEL` ABSENT (no fork). Best-effort:
  no registration claim.
- **R6/R7** — five workflows under `.agents/workflows/` each carry `^description:`.
- **R8** — each workflow resolves its role against `.harness/agents/<role>.md` AND carries
  `$ARGUMENTS`.
- **R9** — each workflow `cmp -s` byte-identical to its `.claude/commands/<name>.md`.
- **R11** — the group prints `pass "Antigravity glue generated (R11)"`; full suite exits 0.
- **R13** — deselect: user-overwritten `.agents/agents/builder.md` SURVIVES with content;
  pristine `reviewer.md` / `sdd-next.md` / `rules/harness.md` REMOVED; `.agents/` dir survives
  (user file keeps it non-empty); GEMINI.md kept until both `gemini`+`antigravity` deselected.

## Stray-`.agent/` grep (required — returns nothing)
```
$ grep -n "\.agent/" harness-install.sh tests/test_install.sh | grep -v "\.agents/"
(no output)
```
Also: `grep -n "drift" harness-install.sh` → none (R18 drift-guard intact; "diverge" kept).

## Verbatim final suite output (all green)
`./init.sh` → `✅ environment ready — agents may proceed` (exit 0).

The full chain ran clean; final per-suite footers:
- All install tests passed.
- All umbrella tests passed.
- All cascade tests passed.
- All inception tests passed.
- All reviewer tests passed.
- All telemetry tests passed.
- All mirror tests passed.
- All epic-lifecycle tests passed.
- All sdd-plan tests passed.
- All sdd-drill tests passed.
- All sdd-fix tests passed.
- All architect-adr tests passed.
- All drift-check tests passed.

Antigravity-relevant pass lines:
- `ok - Antigravity glue generated (R11)`
- `ok - --agents=antigravity writes GEMINI.md entrypoint (R1, Codex r1 P2)`
- `ok - antigravity deselect is a no-op, never deletes a user-authored .agents/ (Codex r3 P1)`
- `ok - antigravity deselect deletes only byte-pristine .agents/ glue, keeps user files (Codex r2 P1)`
- `ok - GEMINI.md shared by gemini+antigravity: kept until both deselected (R1, R13, Codex r1 P2)`

## Hand-off
Implementation complete and self-checked. Not declaring `done` (Reviewer's call). Did NOT push
and did NOT open/modify PR #31 — the Orchestrator drives push + the held pr-loop. Reporting to
the Orchestrator for `in-review`.
