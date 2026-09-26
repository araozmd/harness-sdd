# Builder Checkpoint: E33-F01

- Feature: `E33-F01` (Native Antigravity invocation adapter, dynamic subagent dispatch, and documentation)
- Implementation:
  - Updated `## Invocation adapter` across all `.agents/skills/*/SKILL.md` to document Antigravity `/sdd-*` alongside Codex and OpenCode.
  - Updated `harness-install.sh` `gen_skill_body` and `$CMDDIR/sdd-next.md` to match the invocation adapter format and dynamic subagent dispatch.
  - Updated `agents/orchestrator.md` with explicit Antigravity subagent dispatch recipe using `define_subagent` and `invoke_subagent`.
  - Updated `.claude/commands/sdd-next.md` with the Antigravity dispatch note.
  - Updated `AGENTS.md`, `README.md`, and `docs/WORKFLOW.md` documenting Antigravity as a supported front end.
  - Bumped `VERSION` to `0.87.0` (MINOR capability release) and updated `CHANGELOG.md`.
  - Created `tests/test_antigravity_front.sh` covering R1–R5.
- Verification:
  - Ran `harness-install.sh --self`: clean reconciliation with zero drift warnings.
  - Ran `./tests/test_antigravity_front.sh`: all checks passed.
  - Ran `./init.sh`: passed with 0 exit code.
- Ready for Reviewer handoff.
