---
id: E13
title: Monday board integration (draft — not current use case)
status: draft            # draft → planned → in-progress → done. Roadmap placeholder; drill when it becomes a use case.
owner: araozmd
---

# Epic E13 — Monday board integration (draft)

## Business brief
Placeholder for integrating the harness's `tasks.json` with **monday.com** boards for
teams that use Monday. **Draft / roadmap only — not a current use case.** Seeded so the
provider is on the map; decompose via `/sdd-drill` when a team actually needs it.

## Success criteria (epic level)
- (To be defined at drill.) At minimum: `tasks.json` projected onto a Monday board,
  no-MCP transport (Monday GraphQL API + API token), idempotent reconciliation.

## Features
_None seeded yet — this epic is a `draft` roadmap placeholder. Run `/sdd-drill` to
decompose it into features when it becomes a real use case._

## Notes — technical considerations & restrictions
- **No-MCP transport** to match the org constraint driving E11/E12: Monday's GraphQL
  API + API token, no MCP server.
- Mirror the provider-adapter concerns already worked out for GitHub (E11) and Jira
  (E12) — auth, outbound projection, idempotent reconcile — and relate to the
  ownership backend E10-F03.
