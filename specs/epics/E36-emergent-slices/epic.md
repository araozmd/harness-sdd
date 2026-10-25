---
id: E36
title: "Emergent design: vertical slices, stage-aware NFRs, and derived waves"
status: planned              # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E36 — Emergent design: vertical slices, stage-aware NFRs, and derived waves

## Business brief

The harness is used to build MVPs and pilot products, where the product is still being
discovered. Three failure modes recur on those projects. The Architect's plan grows
non-functional machinery nobody asked for (encryption at rest, WAF, repository patterns)
because nothing records the product's stage and nothing enforces the existing "every plan
row cites an R-id" rule. Features and tasks come out in horizontal layers (model, then
API, then UI; code first, tests last) because the Driller sizes by count, not by shape, and
the tasks template literally puts "write tests" at the end. And the roadmap's parallelism
exists only as `depends_on` data: the operator re-types "build this in waves, critical
path first" into every session and hand-distributes features across machines. This epic
makes the harness produce vertical, test-first slices by construction, lets the operator
park bolt-on NFRs as ADRs with tripwires instead of ignoring them, and turns the
dependency graph into a visible, executable wave plan.

## Success criteria (epic level)

- A generated `.tasks.md` orders work as one failing test followed by the minimal code per
  requirement; "write tests" no longer appears as a trailing task.
- Every feature the Driller seeds names one behavior observable at the product boundary,
  and the first feature of an epic is the walking skeleton; the doc-critic flags a
  decomposition that violates either.
- A project declares its stage once; the Architect defers bolt-on NFRs by writing a
  deferred-decision ADR with a trigger, never by silently omitting or silently adding them;
  sticky NFRs (tenant isolation, auth boundary, secrets, edge validation) are never deferred.
- A `.plan.md` row with no `R-id` and no `ADR-NNNN` citation is a deterministic, tool-detected
  rejection, not an advisory.
- `node tools/next-task.mjs --waves` prints the topological waves and the critical path of
  the pending work; the Driller's report ends with that view.
- A test assertion that went green at a pair commit and is weakened or removed by head is
  detected by a tool the Reviewer runs, independent of which model built the feature.
- `/sdd-next --wave` fans out one wave's independent autonomous features into isolated
  worktrees, reusing the parallel-fix coordinator discipline.

## Technical considerations / restrictions / non-goals

- Structural over compliance (docs/RATIONALE.md): each rule ships as a template shape, a
  schema field, or a tool with an exit code; prose is the pointer, not the mechanism.
- Every new `/sdd-*` surface or flag is emitted by `harness-install.sh` and asserted in
  `tests/test_install.sh`; every new tool under `tools/` ships through the installer.
- Code over prose: prefer extending `tools/next-task.mjs`, `tools/task-diagnostics.py` and
  the Fixer parallel coordinator over new state. No second scheduler, no stored wave plan.
- Non-goals: a cross-clone lease/claim protocol (git branches plus `/sdd-next <id>` and
  `--mine` remain the multi-machine primitive); a security checklist product; changing
  `pr_loop` or the Reviewer's R-id↔test traceability rule.
- The harness's own suite (`sh tools/run-tests.sh`) stays green under dash; no test freezes
  VERSION or diffs DO-NOT-TOUCH files against main.

## Cross-epic dependencies and boundaries

- Builds on E21 (change-size discipline: `max_requirements` stays the Driller's size proxy;
  the observable-slice rule is a shape rule beside it).
- Builds on E10-F01 ownership scoping and E15/E99 parallel-fix worktrees; F07 reuses the
  Fixer parallel coordinator rather than forking it.
- Stays clear of E28 umbrella topology: slices here are intra-repo vertical slices, not the
  cross-repo `slices[]` array.

## Pointers to relevant shared ADRs

- ADR-0001 deterministic next selection — waves are a projection of the same selector.
- ADR-0002 builder-heavy is a tier — F06's drift check is model-independent by design.
- ADR-0008, ADR-0009, ADR-0010 — this epic's deltas (seeded with it).

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Per-requirement red/green task pairs replace the layered tasks template | pending | true | — |
| F02 | Driller observable-slice rule and walking skeleton; doc-critic checks both | pending | true | — |
| F03 | Product stage and deferred-decision ADRs with triggers; sticky vs bolt-on NFRs | pending | true | — |
| F04 | Uncited plan rows block: plan-cite-check tool + Reviewer gate | pending | true | F03 |
| F05 | Derived waves and critical path: next-task --waves + Driller report | pending | true | — |
| F06 | Test-assertion drift check across the feature branch: tool + Reviewer gate | pending | true | — |
| F07 | /sdd-next --wave fans out one wave into isolated worktrees | pending | true | F05 |

## Notes

- Waves: W1 = F01, F02, F03, F05, F06 (independent); W2 = F04 (after F03), F07 (after F05).
- Doc-critic checkpoint (2026-10-25) applied: F06's F01 dependency dropped (merge-base mode is
  the contract); F03's sweep and doc-critic flags moved to F04; `--epic`/`--waves` flags and
  the wave-0 rule for done work made explicit; F07's config key moved out of the inert
  `workers:` block.
- Size: each candidate was sketched under `max_requirements: 12`. F07 was split off from
  F05 on the seam "read-only view" vs "the operation that spawns workers and writes
  state"; F04 was split from F03 on the seam "declare and record" vs "enforce".
- Seeded by Inception in one chore commit (house pattern, see E35 seed `bd19502`), all
  features `autonomous: true`.
