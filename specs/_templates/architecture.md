# Architecture — <project title>

> The whole-system architecture a `/sdd-plan` session produces: the system shape and
> the **stable, upfront, cross-cutting decisions** that constrain more than one epic.
> It captures only the decisions that hold across the roadmap — per-epic ADR *deltas*
> and refinements informed by what an earlier epic's implementation taught are
> deferred to `/sdd-drill` (F03). This file is the index/narrative; each decision is
> recorded as a one-decision ADR under `specs/adr/` and referenced here by its
> `ADR-NNNN` id.

## System shape
<The overall structure: the major components/services/layers, how they fit together,
and the seams between them. A diagram (mermaid / ASCII) is welcome.>

## Stable upfront decisions
<The cross-cutting choices that constrain more than one epic — the stable technology
and structure choices, the system seams. Each is captured as its own ADR below.>

## ADRs
> Each decision is an atomic, citable unit at `specs/adr/NNNN-<title>.md`, referenced
> here by its `ADR-NNNN` id so a later feature spec can point at the same id.

| id | title | summary |
|---|---|---|
| ADR-0001 | <decision title> | <one-line summary> |
| ADR-0002 | <decision title> | <one-line summary> |
