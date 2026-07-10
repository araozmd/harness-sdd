---
id: E14
title: Azure Boards integration (draft — not current use case)
status: draft            # draft → planned → in-progress → done. Roadmap placeholder; drill when it becomes a use case.
owner: araozmd
---

# Epic E14 — Azure Boards integration (draft)

## Business brief
Placeholder for integrating the harness's `tasks.json` with **Azure Boards** (Azure
DevOps work items) for teams on Azure DevOps. **Draft / roadmap only — not a current
use case.** Seeded so the provider is on the map; decompose via `/sdd-drill` when a
team actually needs it.

## Success criteria (epic level)
- (To be defined at drill.) At minimum: `tasks.json` projected onto Azure Boards work
  items, no-MCP transport (Azure DevOps REST API + PAT), idempotent reconciliation.

## Features
_None seeded yet — this epic is a `draft` roadmap placeholder. Run `/sdd-drill` to
decompose it into features when it becomes a real use case._

## Notes — technical considerations & restrictions
- **No-MCP transport** to match the org constraint driving E11/E12: Azure DevOps REST
  API + Personal Access Token, no MCP server. `store/board-mirror.md` already
  recognizes an `azure-boards` provider **stub**.
- Mirror the provider-adapter concerns worked out for GitHub (E11) and Jira (E12), and
  relate to the ownership backend E10-F03.
