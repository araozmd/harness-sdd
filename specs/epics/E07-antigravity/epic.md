---
id: E07
title: Antigravity support
status: done             # pending → in-progress → done (rollup of its features)
owner: araozmd
---

# Epic E07 — Antigravity support

## Business brief
The harness is model-agnostic by design: `AGENTS.md` is the source of truth, and
the repo already fronts Claude Code (`CLAUDE.md`), Gemini CLI (`GEMINI.md`), and
OpenCode (`opencode.json`). Google **Antigravity** — the Gemini-based agentic IDE
— is a new target with its own agent/subagent model and its own context/rules
convention. Today an Antigravity user can read `AGENTS.md` and work the roles by
hand, but gets none of the one-command orchestration (isolated sub-agents,
`/sdd-*` commands) that Claude Code users get from the `.claude/` glue.

This epic makes Antigravity a **first-class harness target**: an Antigravity
entrypoint, installer wiring that stamps it into target repos (parity with the
other tools), and a native orchestration glue layer that maps the harness roles
(Orchestrator → Architect → Builder → Reviewer, plus Scout/Inception) onto
Antigravity's subagent + command primitives, wired through `harness.config.yaml`.

The portable core (role prompts, `init.sh`, the markdown TaskStore, `progress/`
handoffs) is reused unchanged — this epic only adds the Antigravity-specific
front-end and glue, forking no canonical role file.

## Success criteria (epic level)
- An Antigravity user can open a harness-equipped repo and have the SDD loop run
  with native orchestration (role isolation + command equivalents to `/sdd-next`,
  `/sdd-new`), not just by manually driving `AGENTS.md`.
- `harness-install.sh` stamps the Antigravity entrypoint/glue into target repos,
  with a `tests/test_install.sh` assertion (parity with how Claude/Gemini/OpenCode
  targets are handled).
- No canonical `agents/*.md` role file is forked; the glue points at them, the way
  `.claude/agents/` does.
- `harness.config.yaml` continues to drive backend/role selection unchanged.

## Features
- **E07-F01** — Antigravity native support (entrypoint + installer wiring +
  role/command glue). The full scope above as a single feature; the Architect may
  recommend decomposing it into sub-features during specification.
