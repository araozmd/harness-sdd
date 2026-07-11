# Scout drift-check — E12 (Jira board integration, REST + PAT, no MCP) → done

## Question
Re-validate the remaining not-yet-built epics (E13 draft, E14 draft, E99 planned) against what
E12-F01 actually produced. Flag stale rolling-wave plans. READ-ONLY: no state change.

## Re-validation basis (graceful degradation)
There is **no `specs/architecture.md` and no ADR set** in this repo — the drift check therefore runs
in the degraded mode the contract defines: re-validate against the just-completed epic's produced
artifacts (the code/config/doc delta below) rather than an architecture/ADR diff. This is the
documented no-arch no-op basis, not a skipped check.

## What E12 changed (the delta to validate against)
- FILLED the recognized `jira` no-op stub in `tools/sync-board.mjs` with a real one-way projection
  over Jira Server/DC REST + `Authorization: Bearer <PAT>` (Node built-in fetch, **no MCP**). Split the
  shared jira/azure-boards stub so `azure-boards` **stays a no-op**.
- Added Jira `mirror.board` config keys (`base_url`, `project_key`, `pat_file` default `jira.pat`
  resolved under HARNESS_DIR, `issue_type_map`, optional inert `epic_name_field`); reused provider-neutral
  `provider`/`status_map`/`assignee`. Inert-by-default (empty `provider` ⇒ no-op).
- PAT secret hygiene: `JIRA_PAT` env precedence else gitignored `pat_file`; scrubbed from error logs.
- Installer ships the tool executable + gitignores the PAT file; asserted in `tests/test_install.sh`.
- VERSION 0.29.0 -> 0.30.0.
- Deferred `owner -> assignee` / inbound ownership to E10 (E10-F03); one-way invariant preserved.
- PRESERVED: provider-per-epic decomposition, the `azure-boards` no-op stub in `sync-board.mjs` +
  `store/board-mirror.md`, the `mirror.board` config shape (additive keys only).

## Signals checked (scout.md drift-check): S1 contradiction / S2 removed-or-renamed ref / S3 explicit supersede

| epic | state | verdict | reason (grounded in E12's delta) |
|---|---|---|---|
| E13 (Monday) | draft | STILL-VALID | Roadmap placeholder; E12 kept the provider-adapter pattern and added keys additively. Stays draft regardless. No S1/S2/S3 fired. |
| E14 (Azure Boards) | draft | STILL-VALID | E12 preserved the `azure-boards` no-op stub E14 references (explicitly split it out to stay a no-op); provider-adapter pattern intact. Stays draft. No signal fired. |
| E99 (Maintenance) | planned | STILL-VALID | Fix-lane bucket, orthogonal to board providers; E12 touched nothing E99 references. No signal fired. |

## Contract-level confirmation (the key question)
E12 did NOT change any shared contract in a way that invalidates a remaining epic's plan:
- `mirror.board` config shape — extended **additively** only (new jira keys); no existing key removed/renamed.
- One-way projection invariant — preserved (agents never read the board; `state/tasks.json` source of truth).
- Provider-per-epic decomposition — preserved (E12-F01 "Out of scope": GitHub/Monday/Azure = their own epics; no MCP).
- `azure-boards` STUB contract in `sync-board.mjs` + `store/board-mirror.md` — left as a recognized no-op
  stub, so E14's `azure-boards` stub reference still holds.
- Ownership/assignee — E12 KEPT it deferred to E10, matching E13/E14's own deferral. No new contradiction.

## Note for the Orchestrator (carried forward, NOT an E12 demotion trigger)
The pre-existing stale cross-reference flagged at the E10/E11 rollups persists: E13/E14 (and the now-done
E12) reference feature **E10-F03** for ownership, but E10 rolled up `done` with only **E10-F01** built —
there is **no E10-F03** in `state/tasks.json`. This does not fire S1/S2/S3 against E12 (ownership is
out-of-scope for these F01s), so it warrants **no demotion** here. Flagged only so a human can decide
whether the E10-F03 references need a doc cleanup or a re-seed under E10.

## Verdict
All three remaining epics (E13, E14, E99): STILL-VALID. **No demotions warranted from the E12 rollup.**
