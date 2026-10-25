# ADR-0008 — Vertical slices are the unit of decomposition; tasks pair one failing test with the code that passes it

- **Status:** accepted (E36 seed, 2026-10-25)
- **Date:** 2026-10-25

## Context

LLM decomposition defaults to horizontal layers: data model, then API, then UI, then the
seed script; inside a feature, code first and tests last. The harness reinforced both. The
Driller's only size signal is `change_size.max_requirements`, a count with no shape, so
"F01 schema, F02 endpoints, F03 screen" is a legal epic. The tasks template orders `T1..T4`
as code steps and `T5 — Write tests`, so even a well-shaped feature is built as a layered
chunk and verified by reading. Nothing works until the last task, review is a 3,000-line
read, and a wrong assumption surfaces days late instead of minutes late.

Options considered: (a) prose asking roles to "prefer vertical slices" — compliance, ablates
badly across model generations; (b) a shape rule enforced where decomposition happens (the
Driller) and a template whose order makes layering impossible to express (the tasks file),
each with a doc-critic or Reviewer check; (c) adopt a story-backlog workflow in place of
specs — discards the R-id traceability that the Reviewer depends on.

## Decision

Option (b), two parts that constrain every feature in this epic and every epic drilled
after it:

1. **A feature is a vertical slice.** Its brief names at least one behavior observable at
   the product boundary (HTTP, CLI, UI, file output, exit code). The first feature of an
   epic is the walking skeleton: the thinnest end-to-end path, deployable and exercisable.
   A candidate whose outcome is only internal (a table, a module, an interface) is merged
   into the slice that consumes it. `max_requirements` remains the size proxy; this is the
   shape rule beside it.
2. **Tasks are per-requirement red/green pairs.** For each `R-id`, `.tasks.md` lists one
   task that writes the failing test named in `.tests.md`, then one task that writes the
   minimal code to pass it. Refactor tasks are explicit and cite the R-ids whose tests keep
   them honest. There is no trailing "write tests" task. Each pair ends in a commit, so a
   later weakening of that test is a diff the Reviewer can detect.

## Consequences

- Something runs after the first pair; review is "use it", then "read it".
- Cross-cutting setup (migrations framework, CI, auth middleware) is still legitimate as the
  walking skeleton's content, not as its own horizontal feature.
- Parallelism inside one epic gets harder, because vertical slices touch shared seams.
  Parallelize across epics or across independent waves (ADR-0010), not by re-layering.
- The Reviewer gains a model-independent signal for test tampering (E36-F06).
