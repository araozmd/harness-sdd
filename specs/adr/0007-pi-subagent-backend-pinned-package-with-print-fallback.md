# ADR-0007 — pi role sub-agents: pinned `pi-subagents` package, `pi -p` dispatcher as the always-available fallback

- **Status:** accepted (E35 seed, 2026-10-13)
- **Date:** 2026-10-13

## Context

The harness loop depends on role isolation: each of architect, builder, builder-heavy,
reviewer, scout, doc-critic and pr-fixer runs in a clean context with its own model,
reasoning level and tool allowlist (AGENTS.md "Never forward another agent's chat
history"; ADR-0002 tiers). Claude Code has a Task tool, Codex and OpenCode have native role
files, and Antigravity registers subagents dynamically.

pi core deliberately ships **no** sub-agents. Three options exist:

| option | isolation | per-role model/thinking/tools | dependency | headless |
|---|---|---|---|---|
| A. pi's bundled *example* `subagent` extension | yes | model + tools only | copy an example file into `~/.pi/agent/extensions/`; unversioned | yes |
| B. community `pi-subagents` npm package | yes (foreground in-process, background detached runner) | `model`, `thinking`, `tools`, `excludeTools`, `inheritProjectContext`, … | 0.x, releases every 1–5 days; executes third-party code | yes (`pi -p`) |
| C. shell `pi -p --no-session -a --model … --thinking … --tools … --append-system-prompt <role.md>` | yes (separate process) | all three, natively | none (pi itself) | yes |

## Decision

1. **Generated role files target B.** The installer emits `.pi/agents/<role>.md` in the
   `pi-subagents` format, each a thin pointer to the canonical `agents/<role>.md` (ADR-0004
   resolved body pointer) carrying the role's resolved `model`, `thinking` and `tools`.
2. **C is the always-available fallback and the contract.** `tools/pi-dispatch.sh` runs a
   role through option C. The Orchestrator prose on pi says: use the `subagent` tool when
   it is available, otherwise run `pi-dispatch.sh`. The harness never *requires* B.
3. **B is pinned and approval-gated.** The installer never installs B silently: it validates
   read-only by default and runs `pi install -l npm:pi-subagents@<pin>` only on an explicit
   interactive yes or an explicit flag. The pin is a single installer constant, bumped
   deliberately.
4. **A is not supported** and is reported as a conflict when detected, because it
   registers the same `subagent` tool name and shares `~/.pi/agent/extensions/subagent/`.
   The installer reports; it never edits `~/.pi/agent`.

## Consequences

- A 0.x third-party regression degrades pi to the C path instead of breaking the loop.
- Model routing (ADR-0002) has one resolver feeding both the role-file frontmatter and the
  dispatcher flags, so B and C cannot drift.
- Project trust is a hard prerequisite for B and for skills/prompts; C passes `-a`
  explicitly. Preflight reports untrusted targets.
