---
id: E11
title: GitHub Projects board integration (gh CLI, no MCP)
status: pending          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E11 — GitHub Projects board integration (gh CLI, no MCP)

## Business brief
Teams that live in GitHub Projects want the harness's `tasks.json` reflected on their
board for human visibility, and — for the team-ownership model (E10) — a way to sync
assignment/state so parallel developers don't duplicate work. This epic delivers that
integration for **GitHub Projects specifically**, using the **`gh` CLI** as the
transport. No MCP server is used or required: many organizations block MCPs, so the
`gh` CLI (which developers already authenticate) is the safe, portable path.

## Success criteria (epic level)
- `tasks.json` state is projected onto a GitHub Project via `gh` with no MCP
  dependency.
- Authentication uses the developer's existing `gh auth` session (or a token `gh`
  accepts) — nothing new to provision.
- The integration is idempotent: re-running reconciles without creating duplicates.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | GitHub Projects sync via `gh` CLI (no MCP) | pending | true | — |

## Notes — technical considerations & restrictions
- **Transport = `gh` CLI, never MCP.** This is a hard constraint (enterprise MCP
  blocks). REST calls, if needed, go through `gh api`.
- **Overlap to reconcile (do not blindly duplicate):** a one-way board **mirror** for
  GitHub Projects already exists (`store/board-mirror.md`, `tools/sync-board.mjs`,
  `mirror.board.provider: github-projects`). Before building, the driller/architect
  must decide whether F01 *extends* that existing mirror (preferred) or supersedes it,
  and how it relates to the ownership backend **E10-F03**. The user chose a
  provider-per-epic structure deliberately; the shared code question is an
  implementation detail to resolve at drill, not a reason to fork the mirror's
  one-way-projection invariant.
- **Direction:** default is outbound projection (mirror). Any inbound read for
  dedup/ownership belongs to the E10 ownership model, not a bidirectional mirror.
- **Installed-body change** (tools/glue/docs) → **VERSION bump** (MINOR). Installer
  wiring asserted in `tests/test_install.sh`.
