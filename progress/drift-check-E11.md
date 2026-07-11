# Scout drift-check — E11 (GitHub Projects board integration, gh CLI, no MCP) → done

## Question
Re-validate the remaining not-yet-built epics (E12 pending, E13 draft, E14 draft, E99 planned)
against what E11-F01 actually produced. Flag stale rolling-wave plans. READ-ONLY: no state change.

## What E11 changed (the delta to validate against)
- EXTENDED the single existing `github-projects` mirror (`tools/sync-board.mjs`) — did NOT fork,
  did NOT add a second GitHub code path.
- Added a fail-closed `gh` preflight (present, ver >= 2.31.0, `project`+`repo` scopes).
- Pinned the transport contract in `store/board-mirror.md` (Projects v2, gh-only/no-MCP, one-way).
- Asserted installer ships `tools/sync-board.mjs` executable (`tests/test_install.sh`).
- VERSION 0.28.0 -> 0.29.0.
- Deferred `owner -> assignee` / inbound ownership to E10 (E10-F03); one-way invariant preserved.
- PRESERVED: provider-per-epic decomposition, the jira / azure-boards no-op STUBS in
  `sync-board.mjs` + `store/board-mirror.md`, the `mirror.board` config shape.

## Signals checked (scout.md drift-check): S1 contradiction / S2 removed-or-renamed ref / S3 explicit supersede

| epic | state | verdict | reason (grounded in E11's delta) |
|---|---|---|---|
| E12 (Jira REST+PAT) | pending | STILL-VALID | E11 preserved the `jira` no-op stub, the `mirror.board` shape, one-way invariant, and provider-per-epic split — exactly what E12-F01 depends on. No S1/S2/S3 fired. |
| E13 (Monday) | draft | STILL-VALID | Roadmap placeholder; E11 kept the provider-adapter pattern and stubs it will fill. Stays draft regardless. No signal fired. |
| E14 (Azure Boards) | draft | STILL-VALID | E11 preserved the `azure-boards` no-op stub E14 references; provider-adapter pattern intact. Stays draft. No signal fired. |
| E99 (Maintenance) | planned | STILL-VALID | Fix-lane bucket, orthogonal to board providers; E11 touched nothing E99 references. No signal fired. |

## Contract-level confirmation (the key question)
E11 did NOT change any shared contract in a way that invalidates a remaining epic's plan:
- `mirror.board` config shape — unchanged (E11 explicitly "introduces no new committed config key", R5).
- One-way projection invariant — preserved (R10).
- Provider-per-epic decomposition — preserved (E11-F01 "Out of scope": Jira/Monday/Azure = their own epics).
- jira / azure-boards STUB contracts in `sync-board.mjs` + `store/board-mirror.md` — left as recognized
  no-op stubs (E11-F01 spec, out-of-scope: "their branches ... stay recognized no-op stubs").
  So E12's "fill the existing `jira` stub" premise and E14's `azure-boards` stub reference both still hold.
- Ownership/assignee — E11 KEPT it deferred to E10, matching E12/E13/E14's own deferral. No new contradiction.

## Note for the Orchestrator (out of E11 drift-check scope, but observed — NOT an E11 demotion trigger)
Every remaining board epic (E12/E13/E14) defers ownership to feature **E10-F03**, but E10 rolled up to
`done` with only **E10-F01** built — there is **no E10-F03** in `state/tasks.json`. This is a *stale
cross-reference introduced by the E10 rollup*, NOT by E11, and it does not invalidate E12/E13/E14's core
board-projection premise (ownership is out-of-scope for their F01s anyway). Per scout.md this does not fire
S1/S2/S3 against E11, so it warrants NO demotion here. Flagging only so the Orchestrator/human can decide
whether the E10-F03 references need a doc cleanup or a re-seed under E10.

## Verdict
All four remaining epics: STILL-VALID. **No demotions warranted from the E11 rollup.**
