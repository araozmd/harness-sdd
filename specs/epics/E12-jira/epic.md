---
id: E12
title: Jira board integration (REST + Personal Access Token, no MCP)
status: pending          # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E12 — Jira board integration (REST + Personal Access Token, no MCP)

## Business brief
Teams on Jira want the harness's `tasks.json` reflected as Jira issues for visibility
and (with E10) assignment sync. This epic delivers the Jira integration using the
**Jira REST API authenticated with a Personal Access Token (PAT)** — explicitly **no
MCP**, because many enterprises block MCP servers. A PAT is the standard, IT-approved
way to script Jira, so the integration works in locked-down environments.

## Success criteria (epic level)
- `tasks.json` state is projected onto a Jira project via the REST API + PAT, no MCP.
- The PAT is read from a documented, gitignored location (never committed) — personal
  layer, per `docs/CONFIG-LAYERING.md`.
- Idempotent reconciliation: re-running maps harness features to existing Jira issues
  without creating duplicates.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Jira sync via REST API + Personal Access Token (no MCP) | pending | true | — |

## Notes — technical considerations & restrictions
- **Transport = Jira REST + PAT, never MCP.** Hard constraint (enterprise MCP blocks).
- **Secret handling.** The PAT is a personal secret: read from an env var or a
  gitignored file (align with the E09-F02 personal-overrides / `CONFIG-LAYERING.md`
  layer). Never write it to `tasks.json`, the mirror config, or any committed file.
- **Cloud vs Server/DC auth differ.** Jira Cloud typically uses an API token with
  Basic auth (email:token); Jira Server/Data Center uses a Bearer PAT. The
  driller/architect must pin which target(s) F01 supports and how auth is configured.
- **Overlap to reconcile:** `store/board-mirror.md` already recognizes a `jira`
  provider **stub** (no-op today). F01 should fill that stub rather than invent a
  parallel path, and relate to the ownership backend **E10-F03** (which may later use
  the same REST+PAT client for atomic claims).
- **Installed-body change** → **VERSION bump** (MINOR). Installer wiring asserted in
  `tests/test_install.sh`.
