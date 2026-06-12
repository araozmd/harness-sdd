# Architect run — E07-F01 Antigravity native support

## What I specced
The 4-file spec for **E07-F01** (entrypoint + installer wiring + role/command glue),
written into `specs/epics/E07-antigravity/F01-antigravity-support/`:
- `F01-antigravity-support.spec.md` — 12 EARS requirements (R1–R12), architecture-absence
  note, researched-facts section, open questions.
- `F01-antigravity-support.plan.md` — one additive §5c block in `harness-install.sh`,
  exact file list, DO-NOT-TOUCH list, each decision cites its R-id.
- `F01-antigravity-support.tasks.md` — 11 atomic Builder tasks (T1–T11).
- `F01-antigravity-support.tests.md` — R1–R12 traceability table, all checks as
  `tests/test_install.sh`-style POSIX-sh assertions plugged into `verification.test_command`.

No production code written. No canonical `agents/*.md` touched. No `state/tasks.json`
status changed.

## Design in one line
Mirror the existing per-tool pattern: add a §5c block to `install_one()` that stamps a
workspace-local `.agent/` tree (`rules/harness.md` entrypoint rule, `agents/<role>.md`
personas, `workflows/<name>.md` slash commands), where the workflow bodies are `cp`'d
from the already-generated `.claude/commands/*.md` (same anti-drift trick OpenCode uses).
MINOR `VERSION` bump 0.20.0 → 0.21.0 + CHANGELOG entry + `tests/test_install.sh` assertion.

## Architecture artifacts: absent (recorded, not a defect)
Confirmed no `specs/architecture.md`, `specs/vision.md`, or `specs/adr/` — repo never ran
`/sdd-plan`. Applied graceful degradation: noted the absence in the spec, specced from the
inbox brief alone, fabricated no ADR citation, omitted the `## Architecture alignment`
section.

## Antigravity facts: CONFIRMED vs OPEN
I could not call Context7/web-search MCP tools from this sub-agent context (only
Read/Write/Edit/Bash were exposed), but the sandbox had network access, so I grounded the
integration surface directly from current sources:
- antigravity.google/docs (SPA shell) + its `/docs/rules-workflows` and `/docs/cli-subagents` paths,
- Mete Atamel (Google DevRel), atamel.dev 2025-11-25 "Customize Antigravity with rules and workflows",
- aiengineerguide.com TIL "make Antigravity use AGENTS.md automatically",
- community `.agent/` workflow repos (e.g. OleynikAleksandr/antigravity-subagents, yusufcmg/Antigravity-Agents-Workflows).

**Confirmed (drive the design):**
- Antigravity natively loads root `GEMINI.md` rules and `<workspace>/.agent/{rules,agents,workflows}/*.md`; new `.agent/` content loads on app restart.
- It does NOT reliably auto-load a project-root `AGENTS.md` (symlinking `GEMINI.md`→`AGENTS.md` reported not to work); documented workaround is a *rule* pointing at it — hence R2's `.agent/rules/harness.md`.
- A workflow `.agent/workflows/<name>.md` registers as the `/<name>` slash command ONLY if its frontmatter has a `description` (R7).
- `.agent/agents/<name>.md` define named personas (with `description`) — the role-isolation primitive used by R4/R5.

**Left open (flagged at the gate):**
- Whether Antigravity exposes a FIRST-PARTY isolated-context sub-agent spawn (Task-tool
  equivalent). Evidence shows native personas + delegation-by-reference; strict per-agent
  process isolation is currently provided by a THIRD-PARTY VS Code extension, not a
  confirmed built-in API. So the glue is specced to the confirmed primitives with
  `progress/`-file hand-off as the isolation boundary (R12); the first-party-spawn path is
  an open question, not fabricated.

## Decisions for the human at the spec gate
1. **Isolation primitive (R12).** Accept "personas + slash workflows + `progress/` hand-off"
   as the Antigravity orchestration model now; upgrade to true per-role process isolation
   later only if/when a first-party Antigravity spawn API is confirmed.
2. **Entrypoint reuse.** The spec reuses the existing `GEMINI.md` managed block (R1) and adds
   `.agent/rules/harness.md` (R2) as the Antigravity-specific hook. Confirm vs. a separate
   appended Antigravity note in the same block.
3. **New `.agent/` dir.** Confirm a new top-level `.agent/` glue dir in target repos (beside
   `.claude/` and `.opencode/`) is acceptable — it is Antigravity's documented convention.
4. **Command breadth.** The spec ships all FIVE SDD workflows for uniform parity (R6) rather
   than the brief's minimum `/sdd-next` + `/sdd-new`. Confirm the wider surface.

## Status
All four files persisted. Did NOT change `state/tasks.json`. Ready for the Orchestrator to
move E07-F01 to `spec-ready` and pause at the human gate.
