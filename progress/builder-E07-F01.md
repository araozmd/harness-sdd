# Builder hand-off — E07-F01 Antigravity native support

Status: implementation complete, full verification suite green. Ready for the
Orchestrator to move the feature to `in-review`. (Builder does NOT declare `done`.)

## Tasks completed (T1–T11)
- **T1 (R1)** — Added a comment at the `agent_selected gemini && write_pointer GEMINI.md`
  call in §4 noting the `GEMINI.md` managed block (already boots the Orchestrator against
  `.harness/AGENTS.md`) also serves Antigravity. No behavioral change.
- **T2 (R2,R4,R6)** — New §5c block in `install_one()`, placed AFTER §5b's
  `ok "OpenCode commands …"` and BEFORE the `rm -rf "$CMDDIR"` cleanup / §6, gated on the
  `antigravity` agent key. Does `mkdir -p .agent/{rules,agents,workflows}`.
- **T3 (R2,R3)** — Writes `.agent/rules/harness.md`: points at `.harness/AGENTS.md` (source
  of truth) + `.harness/agents/orchestrator.md` (entry role), mandates `.harness/init.sh`
  first, documents the R12 working model. No copied role body.
- **T4 (R4,R5)** — `emit_ag_agent` loop over `orchestrator architect builder reviewer scout`
  writes `.agent/agents/<role>.md`: `description:` frontmatter (descriptions reused verbatim
  from the `.claude/agents` `emit_agent` calls) + a body that defers to
  `.harness/agents/<role>.md`, runs `.harness/init.sh` first (halt on non-zero), hands off via
  `.harness/progress/`. No copied role body.
- **T5 (R6,R7,R8,R9)** — Loop over `sdd-next sdd-new sdd-plan sdd-drill sdd-fix` copying each
  body from the shared `$CMDDIR/<name>.md` (the same source the §5b OpenCode block copies) into
  `.agent/workflows/<name>.md`. Byte-identical to the Claude/OpenCode copies; the existing
  `description:` frontmatter is preserved (satisfies slash-command registration). Sourcing from
  `$CMDDIR` (not `.claude/commands/`) keeps Antigravity working even when `claude` is deselected.
- **T6 (R12)** — `ok "Antigravity glue (rules + agents + workflows) installed (.agent/)"`.
- **T7 (R10)** — Extended the §3 `manifest.txt` HARNESS-OWNED list with
  `.agent/rules/*  .agent/agents/*  .agent/workflows/*   (repo root, regenerated; Antigravity glue)`.
- **T8 (R10)** — Bumped `VERSION`. See deviation note below.
- **T9 (R10)** — Added a `## [0.22.0]` CHANGELOG section under
  `### Added — ✨ Antigravity native support`.
- **T10 (R11)** — Antigravity assertion group in `tests/test_install.sh`, after the OpenCode
  group, ending `pass "Antigravity glue generated (R11)"`. Covers every check in tests.md.
- **T11** — Ran `./init.sh` + the full `verification.test_command` suite. All green (output below).

## Files changed (absolute paths)
- `/Users/araozmd/repos/harness-sdd/harness-install.sh` — §4 comment (T1); new §5c glue block
  (T2–T6); §3 manifest list (T7); updated the §7 antigravity DESELECT reconciliation case from
  the E08-F01 no-op placeholder to scoped `remove_owned` of the new `.agent/` glue (see note).
- `/Users/araozmd/repos/harness-sdd/tests/test_install.sh` — Antigravity assertion group (T10);
  refreshed the now-stale comment on the pre-existing "antigravity deselect" test (comment only,
  assertions unchanged).
- `/Users/araozmd/repos/harness-sdd/VERSION` — `0.21.0` → `0.22.0`.
- `/Users/araozmd/repos/harness-sdd/CHANGELOG.md` — new `## [0.22.0]` Antigravity section.
- `/Users/araozmd/repos/harness-sdd/specs/epics/E07-antigravity/F01-antigravity-support/F01-antigravity-support.tasks.md`
  — ticked T1–T11.

## New test assertions (R-ids) added to tests/test_install.sh
- R1 — `GEMINI.md` has the harness block AND references `.harness/AGENTS.md`.
- R2 — `.agent/rules/harness.md` exists AND references `.harness/AGENTS.md` AND
  `.harness/agents/orchestrator.md`.
- R3 — the rule does NOT embed the canonical orchestrator body (sentinel absent).
- R4 — each of `orchestrator architect builder reviewer scout` persona file exists AND has
  a `^description:` line.
- R5 — each persona references `.harness/agents/<role>.md`, `.harness/init.sh`,
  `.harness/progress/`, and does NOT embed the canonical body.
- R6 — all five `.agent/workflows/<name>.md` exist.
- R7 — each workflow has a `^description:` line.
- R8 — each workflow carries `$ARGUMENTS`; `sdd-next`→orchestrator, `sdd-new`→inception,
  `sdd-plan`→planner, `sdd-drill`→driller, `sdd-fix`→fixer, each resolved against
  `.harness/agents/*.md`.
- R9 — each workflow is `cmp -s` byte-identical to the matching `.claude/commands/<name>.md`.
- group ends with `pass "Antigravity glue generated (R11)"` (R11).
- R10/R12 — covered jointly: R10 by the existing version-stamp assertion (still green) +
  VERSION/CHANGELOG (Reviewer manual); R12 by the joint presence of personas + workflows + the
  `.agent/rules/harness.md` hand-off rule.

### No-fork sentinel
tests.md suggested `## The non-negotiable rules` as the canonical-body sentinel, but that string
does NOT exist in `agents/orchestrator.md` (a grep-absent test on a never-present string would be
vacuous). I used the real, distinctive canonical line
`You are the **Orchestrator**. You are the project manager of the harness.` instead, which only
appears if a role body is forked. The persona/rule shims use "You are the **<role>** for this
project's agent harness", which does not match — so the no-fork assertion is meaningful.

## Deviations from the spec (recorded per Builder principle — no silent drift)
1. **VERSION 0.22.0, not 0.21.0.** T8/the plan say bump `0.20.0 → 0.21.0`. By the time this
   feature was built, the dependency-free sibling feature E08-F01 (selectable agent targets) had
   already merged to `main` and consumed `0.21.0` (its `VERSION` + `## [0.21.0]` CHANGELOG section
   are present). Per the repo `CLAUDE.md` SemVer policy this MINOR capability needs its own next
   increment, so I bumped to `0.22.0` and added a distinct `## [0.22.0]` section. This preserves
   the spec's intent (one MINOR bump for this capability) given the real version state.
2. **Antigravity deselect is now scoped removal, not a no-op.** E08-F01 left the §7 `antigravity)`
   reconciliation case an explicit no-op placeholder with the comment "When E07-F01 lands it adds
   scoped removal of its known `.agent/` paths." Now that §5c owns a real `.agent/` glue tree, a
   no-op would leave stale glue on deselection — contradicting the harness-owned/regenerated
   contract the spec mandates for `.agent/` (business rule: regenerated each run like `.claude/` /
   `.opencode/`). I replaced the no-op with scoped `remove_owned .agent/{rules,agents,workflows}`
   + an empty-only `rmdir .agent` (mirroring the Claude/OpenCode removal). This still honors Codex
   r3 P1 (#3400997183): only harness-owned stems are removed, a user-authored `.agent/` file/dir
   is never deleted and `.agent/` is never `rm -rf`'d. The pre-existing E08-F01 test at
   `tests/test_install.sh` "antigravity deselect …" still passes (it asserts the user file/dir
   survive); I refreshed only its stale descriptive comment, leaving its assertions intact.

## Constraints honored
- No canonical `agents/*.md` role body forked, copied, or edited — glue only points at
  `.harness/agents/*.md`.
- No change to `store/tasks.schema.json`, status values, `init.sh`, the markdown TaskStore,
  `progress/` mechanics, the 4-file spec format, or the umbrella/cascade machinery.
- Existing §4/§5/§5b/§6 blocks and the existing R1–R11 install assertions are unmodified — §5c and
  the Antigravity test group are additive.
- `.agent/` glue is harness-owned / regenerated every run; NOT added to any seed-once set.

## Verification evidence — final pass/fail lines
`./init.sh` → `✅ environment ready — agents may proceed`

Full `verification.test_command` chain (every suite green):
```
All install tests passed.            (includes: ok - Antigravity glue generated (R11))
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
```
