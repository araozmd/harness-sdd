---
id: E01-F01
title: Overview widgets
epic: E01-dashboard
status: pending
sdd: true
autonomous: false
depends_on: []
owner: araozmd
---

# Overview widgets — Functional Spec

## Context
The dashboard's top section shows summary widgets so an operator immediately
understands the current conversation load and what needs attention.

## Business rules
- Counts reflect live data; stale numbers are worse than slightly delayed ones.

## Acceptance criteria (EARS)
- **R1** — The system shall display the count of active conversations.
- **R2** — The system shall display the count of conversations currently bot-handled.
- **R3** — The system shall display the count of conversations awaiting a human (needs_human).
- **R4** — When the underlying counts change, the system shall refresh the widgets within 30 seconds.
- **R5** — If the metrics request fails, then the system shall show a non-blocking error state and a retry control on the affected widget.

## Out of scope
- Charts / historical trends — later feature.

## Open questions
- Polling vs. websocket for R4? (Default assumption: polling every 30s for v1.)

<!-- This feature is intentionally left at `pending` as a second worked example;
     run the Architect to expand its .plan / .tasks / .tests when ready. -->
