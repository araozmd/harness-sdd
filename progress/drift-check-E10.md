# Drift check — post E10 rollup (Scout, read-only)

**Completed epic:** E10 "Team coordination & ownership" (only feature E10-F01, merged PR #40).
**E10-F01 outputs re-validated against:** additive optional `owner` field (`store/tasks.schema.json`);
tool-agnostic "Ownership & scoped selection" Orchestrator contract (`/sdd-next --mine`, effective owner,
owned-only, no claim-on-select, `workflow.identity`, fail-closed/no-widen); **one-way board mirror
reaffirmed** (agents never read the board); installer glue (`--mine`, `workflow.identity`, `migrate_config`);
docs (`docs/WORKFLOW.md`, `store/local.md`). **No ADR, no `specs/architecture.md`, no rename/removal,
no `supersedes`/`obsoletes` marker.** Deferred to future E10 features: E10-F02 (team-claim rules) and
E10-F03 (live board-agnostic ownership *backend* for atomic claims) — NOT yet seeded in tasks.json.

Staleness signals (per `agents/scout.md`): **S1** contradiction, **S2** removed/renamed reference,
**S3** explicit supersede. Verdict is STALE only if ≥1 fires; STILL-VALID is the conservative default.

---

## E11 — GitHub Projects board integration (gh CLI, no MCP) — status `pending`
**Verdict: STILL-VALID**
- No signal fires. E11's brief/epic.md already scope inbound agent-read/ownership/atomic claims **out**
  and defer them to E10-F03 (`progress/inbox/E11-F01.md` Out-of-scope; `epic.md:41-42`), and they
  explicitly preserve the **one-way mirror** invariant — the exact invariant E10-F01 reaffirmed. E10-F01
  added an *additive* `owner` field and a selection filter; it renamed/removed nothing E11 references and
  emitted no ADR or supersede marker.
- E11 stands as a one-way projection that may *also* project the new `owner` field later; its own open
  question already recommends leaving ownership semantics to E10. No conflict, no collision with E10-F03
  (F03 is a *store backend*, not the mirror) — the boundary E11 assumes is exactly the one E10 kept.

## E12 — Jira board integration (REST + PAT, no MCP) — status `pending`
**Verdict: STILL-VALID**
- No signal fires. Same shape as E11: `progress/inbox/E12-F01.md` and `epic.md:39-40` put inbound
  ownership/atomic claims out-of-scope and defer to E10-F03; the `jira` mirror stub it fills stays
  one-way. E10-F01's additive `owner` field + `workflow.identity` config touch nothing E12 depends on
  and introduce no contradiction, removal, or supersede.
- The E10-F03↔E12 relationship is noted as future reuse of a REST+PAT client (`epic.md:40`), not a
  collision — E10 explicitly placed F03 in the store-backend abstraction, distinct from the mirror.

## E13 — Monday board integration (draft — not current use case) — status `draft`
**Verdict: STILL-VALID** (and already lowest planning state — would not be demoted regardless)
- No signal fires. Roadmap placeholder, no features seeded; mirrors E11/E12 concerns and already
  references relating to ownership backend E10-F03 (`epic.md:28`). E10-F01 changed no assumption here.

## E14 — Azure Boards integration (draft — not current use case) — status `draft`
**Verdict: STILL-VALID** (already lowest planning state)
- No signal fires. Same as E13: placeholder, no features, one-way `azure-boards` stub, defers ownership
  to E10-F03 (`epic.md:29`). E10-F01 introduced nothing that contradicts or removes anything it references.

## E99 — Maintenance (hotfixes & minor fixes) — status `planned`
**Verdict: STILL-VALID** (drift concept does not meaningfully apply)
- No signal fires. E99 is the reserved ad-hoc fix bucket; it carries **no plan/assumptions** to
  invalidate — its features are seeded on demand by `/sdd-fix`, not a rolling-wave plan
  (`epic.md`). E10-F01 produced nothing that touches the fix lane. Not a re-drill candidate.

---

## Summary for the Orchestrator
- **STALE: none.** All five remaining planning-state epics are **STILL-VALID**.
- No demotion action required. E10-F01's outputs were purely additive and its deferred F02/F03 boundary
  is precisely the boundary E11–E14 already assume; E99 carries no plan to drift.
