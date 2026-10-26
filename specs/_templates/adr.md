# ADR-NNNN — <decision title>

> One architecture decision per ADR. This is an atomic, citable unit: a later
> feature spec (F04) can point at this `ADR-NNNN` id. Filename:
> `specs/adr/NNNN-<title>.md`, with `NNNN` zero-padded to 4 digits and allocated
> strictly above the maximum existing ADR number (no reuse). Referenced from
> `specs/architecture.md` by its `ADR-NNNN` id.

- **Status:** <proposed | accepted | deferred>
- **Date:** <YYYY-MM-DD>
- **Trigger:** <observable condition that reopens this decision — mandatory when Status is deferred; omit otherwise>

> ## Stage-aware NFRs (ADR-0009)
> A **deferred** ADR parks a bolt-on NFR the product's stage excludes
> (`stage:` in `specs/product.md` frontmatter — `discovery | pilot | production`,
> `production` when absent). It is an ordinary ADR with `Status: deferred` and a
> **mandatory** `Trigger:` line — the observable condition that reopens it (first regulated
> customer, N users, a named compliance deadline). The feature plan cites it from its
> `## Deferred` subsection.
>
> **Sticky NFRs are never deferred at any stage:** tenant isolation, the auth boundary,
> secrets out of the repo, validation at the system edge. This list is ADR-0009's;
> extending it is a change to that ADR (a spec change), not a role's judgment call.
> **Bolt-on examples** (deferrable by a deferred ADR): encryption at rest, WAF,
> rate limits, backups, caching.

## Context
<The forces at play — what makes this decision necessary, the constraints and the
options considered. Keep it to the one decision this ADR records.>

## Decision
<The single decision taken, stated plainly.>

## Consequences
<What becomes easier and what becomes harder as a result — the trade-offs this
decision locks in.>
