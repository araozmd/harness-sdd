---
id: E99-F169
title: Parallelize isolated umbrella test groups
epic: E99-maintenance
status: in-review
sdd: true
autonomous: true
complexity: standard
depends_on: []
owner: araozmd
---

# Parallel umbrella tests — Functional Spec

## Context
Maintainers wait on a 3,206-line serial umbrella suite after other verification jobs finish. Independent suites expose its existing work to the existing eight-worker runner. The user approved isolated groups and requested implementation; the intake records autonomous authorization. This is test organization and bounded runner plumbing, with no installer behavior change.

## Business rules
- Preserve meaningful assertions, fixture setup order, mutation discriminators, permission-dependent skips, and the real installer exercises.
- Keep related cases together; give concurrent groups independent shell processes and temporary roots.
- Record measured timings under comparable conditions; a green but slower split does not satisfy the optimization.
- Architect hands off for the owner's spec-ready transition; autonomous authorization permits the subsequent implementation transition. Independent Reviewer approval remains required.

## Architecture alignment
`specs/architecture.md` is absent. `specs/product.md` is the example product constitution; this maintenance feature follows the harness intake. The platform ADR set exists and was read; the intake seeds no ADR ids.

- ADR-0004 — Preserve the existing tests of pointer stubs, local executable bodies, thin conversion, and standalone recovery without changing those contracts.

## Acceptance criteria (EARS)
- **R1** — The extracted suites shall preserve every original umbrella case body and meaningful precondition/assertion, with any necessary extraction-only adaptation individually documented.
- **R2** — When default verification discovers suites, the runner shall schedule each of the 13 umbrella groups exactly once as an independent job, excluding the compatibility aggregate.
- **R3** — When `sh tests/test_umbrella.sh` or an explicit runner selection of that file is invoked, the compatibility entrypoint shall execute all umbrella groups in their original order.
- **R4** — If an umbrella group fails, then both aggregate invocation and runner invocation shall return nonzero with the failed group's diagnostic visible.
- **R5** — While umbrella groups execute concurrently, each group shall own isolated temporary fixtures and remove its owned temporary roots on success or failure, including read-only fixture trees.
- **R6** — When verification runs umbrella groups, their execution shall retain the runner's selected strict shell and top-level errexit behavior.
- **R7** — If any extracted umbrella shell body or helper has a syntax error, then runner preflight shall fail before executing any suite.
- **R8** — When serial aggregate and eight-worker group runs complete on the same environment, they shall report the same multiset of original case results and permission-dependent skips.
- **R9** — When benchmarked under comparable conditions, the eight-worker umbrella groups shall complete faster than the recorded original monolith baseline, with elapsed times and environmental limitations recorded.
- **R10** — When final verification evaluates the completed branch, all configured verification suites shall pass under the independent Reviewer's execution.
- **R11** — The current test documentation shall describe the group layout, direct aggregate invocation, discovery exclusion, and safe benchmarking prerequisites.

## Out of scope
New scheduler, timing cache, longest-first engine, changes to concurrency defaults, installer fixes, assertion weakening, broad test rewrites, historical spec rewrites, and unrelated cleanup.

## Open questions
None requiring a product decision. Actual timings are evidence to collect, not predicted results.
