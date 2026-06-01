---
id: E04
title: Idea intake
status: done
owner: araozmd
---

# Epic E04 — Idea intake

## Business brief
The harness today has no owned step *before* `pending`: a raw idea is hand-edited
into `state/tasks.json`, with the human personally doing triage (epic vs. feature
vs. task), id allocation, dependency wiring, and intent capture. This epic adds the
missing front door — an interactive **Inception** role that turns a free-text idea
into a well-formed `pending` entry plus an intent brief the Architect can spec from.
It seeds; it never specs (that stays the Architect's job) and never skips the human
gate.

## Success criteria (epic level)
- A human can go from a one-line idea to a valid, schema-passing `pending` entry
  without hand-editing JSON.
- Inception correctly triages altitude (new task on an existing feature / new
  feature under an existing epic / new epic) and allocates ids in order.
- The handoff is files-only: a TaskStore entry + `progress/inbox/<id>.md`. Running
  `/sdd-next` afterwards drives the unchanged Architect → gate → Builder → Reviewer
  flow.
- No change to `tasks.schema.json`, no new status, no change to the Orchestrator or
  Architect contracts — the addition is purely additive.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Inception role + /sdd-new intake | pending | true | — |

## Notes
- The Inception role is the **only** interactive, human-facing role; every other
  role is batch/file-driven. The `/sdd-new` slash command carries the interactivity;
  `agents/inception.md` is the portable contract (model-interchangeable, per
  `AGENTS.md`).
- Mockups/options are **text-only** (markdown/ASCII) to honor the minimal-tools rule
  (`AGENTS.md` rule 5) and stay portable across Claude/Codex/Gemini/OpenCode.
- This epic touches `agents/` and the `.claude/` glue, so merging F01 warrants a
  **MINOR** `VERSION` bump (✨) per the repo versioning policy in `CLAUDE.md`.
</content>
</invoke>
