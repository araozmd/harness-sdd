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
