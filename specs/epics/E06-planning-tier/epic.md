---
id: E06
title: Planning tier (rolling-wave inception + per-epic drill-down)
status: in-progress      # pending → in-progress → done (rollup of its features)
owner: araozmd
---

# Epic E06 — Planning tier (rolling-wave inception + per-epic drill-down)

## Business brief
Today the harness plans one idea at a time (`/sdd-new` → epic → sequential
features), so architectural coherence emerges late: several epics in, the human
discovers refactors that a whole-project view would have prevented. This epic adds
a **planning tier above features**: a cheap inception session that captures the
whole vision and sketches all epics as drafts, followed by per-epic drill-down
sessions that deepen one epic at a time — each informed by what the previous
epic's implementation taught. Approval granularity moves up from per-feature to
per-epic, flowing through the existing `autonomous` flag, so an approved epic runs
to completion without per-task human gating. A lightweight lane keeps small
fixes/hotfixes out of the ceremony entirely.

Two outcomes for the human: (1) whole-picture design before implementation begins,
without a tiring big-bang planning session; (2) once an epic's business need is
clear and approved, the coding agent runs and validates autonomously.

## Success criteria (epic level)
- An idea-to-roadmap session produces `specs/vision.md`, `specs/architecture.md`
  (+ ADRs) and N `draft` epics — each a one-paragraph brief, no feature specs.
- The Orchestrator never selects work from a `draft` epic; drilled (`planned`)
  epics execute autonomously end-to-end through the existing loop.
- Drill-down of one epic is a short session (single epic, not the whole roadmap)
  ending in one human decision: approve for autonomous execution or keep gated.
- Specs written after inception cite the architecture decisions they touch;
  "we lacked the whole picture" refactors stop recurring.
- A minor bug/hotfix can be seeded and executed with no 4-file spec and no
  drill-down ceremony.
- Stale plans are detected: when an epic completes, remaining draft/planned epics
  are re-checked against what was learned, and stale ones demote to `draft`.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Epic lifecycle: `draft`/`planned` states + `next()` gating | done | true | — |
| F02 | `/sdd-plan` inception skill (vision + architecture + draft epics) | done | true | F01 |
| F03 | `/sdd-drill <epic>` skill (decompose, ADR deltas, epic-level approval) | done | true | F01, F02 |
| F04 | Architect contract: `architecture.md` mandatory input, specs cite ADRs | done | true | F02 |
| F05 | `/sdd-fix` lightweight lane (maintenance epic, brief-only intake) | done | true | F01 |
| F06 | Drift check on epic rollup (Scout re-validates remaining epics) | pending | true | F03 |

F02–F06 are the planned roadmap, listed here deliberately **without** TaskStore
entries: they get seeded as F01 lands and the shape firms up — the same
rolling-wave discipline this epic introduces. Do not seed them all upfront.

## Notes
- All changes are **additive**: new enum values (`draft`, `planned`) on the epic
  status, new skills, new docs. Existing `tasks.json` files (no draft epics)
  remain valid; existing single-feature flow (`/sdd-new` → `/sdd-next`) is
  unchanged. One MINOR version bump for the installed-body change.
- Epic-level approval reuses the existing `autonomous: true` gate-skip flag on
  features — no new approval mechanism, no schema change for approval itself.
- Origin: design discussion 2026-06-09/10 (rolling-wave vs BDUF; architecture
  decisions are the stable upfront artifact, feature specs stay just-in-time).
