---
id: E00-F00
title: <feature title>
epic: E00-<epic-slug>
status: pending          # pending → spec-ready → in-progress → in-review → done
sdd: true                # false = quick task, skip full SDD
autonomous: false        # true = may bypass the human approval gate
depends_on: []
owner: <handle>
---

# <Feature title> — Functional Spec

## Context
<The problem this solves, who the user is, why it matters. 2–5 sentences.>

## Business rules
- <rule>
- <rule>

## Architecture alignment
> Cite the architecture decisions (ADRs) this feature touches. Required whenever
> `specs/architecture.md` + `specs/adr/*` exist; omit only when the repo has no
> architecture (legacy / `/sdd-new` altitude-3). See docs/SPEC-FORMAT.md.

- ADR-NNNN — <decision title>: <one line on how this feature honors that decision>.
- ADR-NNNN — <decision title>: <one line on how this feature honors it>.

<!-- If this feature genuinely touches no recorded decision, replace the list with the
     explicit line below (it is a legitimate state, not a silent omission): -->
<!-- ADRs touched: none — <one-line why this feature constrains no recorded decision>. -->

## Acceptance criteria (EARS)
> Each is one testable behavior with a stable id. See docs/SPEC-FORMAT.md.

- **R1** — When <trigger>, the system shall <response>.
- **R2** — While <state>, the system shall <response>.
- **R3** — If <error condition>, then the system shall <response>.
- **R4** — The system shall <ubiquitous behavior>.
- **R5** — Where <optional feature>, the system shall <response>.

## Out of scope
- <explicitly not doing>

## Open questions
- <anything the human should resolve before approval>
