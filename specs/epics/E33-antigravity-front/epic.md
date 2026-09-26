---
id: E33
title: Native Antigravity front end via shared skills and dynamic subagent dispatch
status: planned          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E33 — Native Antigravity front end via shared skills and dynamic subagent dispatch

## Business brief
The harness currently supports Claude Code (primary), Codex (second), and OpenCode (third).
Google Antigravity is a modern AI-assisted development platform with rich customization
primitives including `.agents/skills/` and dynamic runtime subagent leasing. Prior Antigravity
support (E07) was retired in E29 because bare persona files in `.agents/agents/` were inert on disk
and required complex global plugin packaging.

This epic introduces a first-class, lightweight Antigravity front end that:
1. Reuses the existing portable `.agents/skills/` layer (piggybacking on Codex's shared surface without adding bloat to `harness-install.sh`).
2. Documents and standardizes slash-command invocation (`/sdd-*`) alongside Codex (`$sdd-*`) and OpenCode (`/sdd-*`).
3. Uses dynamic subagent registration (`define_subagent`) from canonical `agents/*.md` prompts during orchestration, guaranteeing true context isolation without requiring machine-local plugins.
4. Updates canonical documentation (`AGENTS.md`, `README.md`, `docs/WORKFLOW.md`).

## Success criteria (epic level)
- Antigravity users can run the SDD loop (`/sdd-next`, `/sdd-plan`, `/sdd-drill`, etc.) natively from `.agents/skills/`.
- Role handoffs (Orchestrator → Architect → Builder → Reviewer) maintain strict context isolation via dynamic subagents, preserving the independent Reviewer gate.
- Zero machine-global plugin installation is required: the harness remains 100% repository-local.
- Existing Claude, Codex, and OpenCode integrations and test suites continue to pass with zero regressions.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Native Antigravity invocation adapter, dynamic subagent dispatch, and documentation | pending | true | — |

## Notes
- Aligns with ADR-0003 (shared skill units) and ADR-0004 (resolved body pointers).
