---
id: E05
title: Harness observability & review quality
status: done             # pending → in-progress → done (rollup of its features)
owner: araozmd
---

# Epic E05 — Harness observability & review quality

## Problem
The harness drives long-running, multi-agent work but is **blind to itself**. Two
gaps surfaced in real use:

1. **Review quality.** The in-loop Reviewer is handed a curated, minimal context and
   anchors on tests passing. That makes it strong at spec→test traceability but blind
   to *cross-file consistency* — e.g. a change to one agent/role prose contract that
   silently violates a precondition in a contract it invokes. An external reviewer
   (Codex via `/pr-loop`) catches these, but the in-loop Reviewer should too, and the
   build↔review iteration that fixes them should be a first-class, named loop (as in
   Anthropic's "harness design for long-running apps").

2. **No telemetry.** We cannot answer "how long does each sub-agent run autonomously?"
   or "how long does a human spend at the spec-approval gate?" The article surfaces
   per-agent Duration + Cost; we have neither. Without this we can't tune the harness,
   budget human attention, or report on autonomy over time.

## Success criteria
- The in-loop Reviewer reliably catches cross-file/contract-precondition inconsistencies
  introduced by a change, and the build↔review multi-round loop is explicit in the role
  prompts so rejected work cycles back with actionable feedback until green.
- Every sub-agent phase records its wall-clock duration, and the human spec-approval
  latency (spec-ready → in-progress) is captured automatically, into a zero-dependency
  telemetry log that a script rolls up into daily / weekly / monthly / quarterly /
  semester / annual reports.

## Features
- **E05-F01** — Reviewer cross-file consistency check + explicit build↔review rounds.
- **E05-F02** — Sub-agent & human-gate telemetry with rollup reports.

## Out of scope
- Per-token / per-USD cost accounting: a markdown-prompt agent cannot observe its own
  token usage (unlike the Agent-SDK harness in the article). Deferred until/unless the
  harness runs under an instrumented SDK runtime. Telemetry is duration + latency only.
