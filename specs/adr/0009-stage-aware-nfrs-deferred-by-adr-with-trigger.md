# ADR-0009 — Non-functional requirements are stage-aware: bolt-ons are deferred by an ADR with a trigger, sticky ones are never deferred, and an uncited plan row is a defect

- **Status:** accepted (E36 seed, 2026-10-25); decision 4's Reviewer rejection is effective on E36-F04
- **Date:** 2026-10-25

## Context

On MVP and pilot projects the Architect's `.plan.md` grows encryption at rest, a WAF, rate
limiting, retries and repository abstractions that no requirement asked for. Two causes:
the project never states what stage it is in, so the model fills the gap with a
production-grade default; and the existing rule "each design decision cites the R-id(s) it
serves" (agents/architect.md) is enforced by nobody — the doc-critic's YAGNI finding is
advisory and the Reviewer checks R-id↔test, not plan-row↔R-id.

"Park security until later" is the wrong fix. Non-functional requirements split by how
sticky they are, not by how important they sound. Bolt-ons (encryption at rest, WAF, rate
limits, backups, caching, CDN) are infrastructure toggles added later without touching the
code. Sticky ones (tenant isolation, the auth boundary, secrets out of the repo, validation at
the system edge) are architectural; retrofitting them into a pilot that got traction is a
rewrite.

## Decision

1. **The project declares a stage once** (`discovery | pilot | production`) in
   `specs/product.md` frontmatter. Planner, Driller and Architect read it; absent means
   `production` (today's behavior).
2. **Bolt-on NFRs are deferred by writing, not by omitting.** For each bolt-on the stage
   excludes, the Architect writes or cites a deferred-decision ADR (`specs/adr/NNNN-*.md`,
   `Status: deferred`) that carries a `Trigger:` line — the observable condition that
   reopens it (first regulated customer, N users, a named compliance deadline). The ADR is
   the parking lot; the plan cites it.
3. **Sticky NFRs are never deferred** at any stage. The list is short and lives in the ADR
   template's guidance; a plan that omits one is a spec defect the doc-critic raises.
4. **An uncited plan row is a defect.** Every row in a `.plan.md` data-model, API or
   files-to-change table carries an `R-id` or an `ADR-NNNN`. A tool checks it with an exit
   code; the doc-critic reports it at the spec checkpoint as advisory and the Reviewer
   treats it as a rejection.

## Consequences

- The Architect cannot add a WAF without a row that says why; it can defer one in one line.
- Deferred ADRs make Emergent Design auditable: the decision and its tripwire are recorded,
  so "we forgot" is replaced by "the trigger has not fired".
- Projects that never set a stage see no behavior change.
- The citation check is mechanical and model-independent; it survives model upgrades and
  prompt diets (docs/RATIONALE.md, structural over compliance).
