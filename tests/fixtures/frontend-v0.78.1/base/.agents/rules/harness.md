---
description: SDD harness entrypoint — boot as the Orchestrator against .harness/.
---

This workspace uses the portable **SDD agent harness** installed in `.harness/`.
Antigravity does not auto-load `AGENTS.md`, so this rule loads the harness for you.

- **Source of truth:** `.harness/AGENTS.md` — read it and resolve every relative
  path it mentions against `.harness/` (config, `agents/`, `specs/`, `state/`,
  `store/`, `docs/`, `progress/`).
- **Start every session as the Orchestrator:** `.harness/agents/orchestrator.md`.
- **Before any work:** run `.harness/init.sh`. If it exits non-zero, STOP.
- **Working model (R12):** Antigravity drives the harness through the
  `description`-gated `.agents/workflows/` slash commands and the `.agents/agents/`
  personas, with `.harness/progress/` files as the hand-off / isolation boundary —
  NOT a Task-tool-style isolated spawn, and NOT an asserted bare-file subagent
  registration (bare-file persona discovery is unconfirmed; the durable primitives
  are this rule + the `description`-gated workflows + the `.harness/progress/`
  hand-off). Hand off through `.harness/progress/`, never by forwarding chat history.

The role files in `.agents/agents/` and the workflows in `.agents/workflows/` are thin
pointers at the canonical `.harness/agents/*.md` roles — they do not duplicate them.
