---
id: E10
title: Team coordination & ownership
status: done             # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E10 — Team coordination & ownership

## Business brief
The harness must serve a **solo developer and a team from the same install**. Today
the team story has a hole: `/sdd-next` (the Orchestrator) picks the next actionable
feature **board-wide**, and the local TaskStore feature entry has **no `owner`
concept** (only the GitHub board-mirror carries an `assignee`). In a shared-repo
umbrella the `tasks.json` is shared state, so two developers running `/sdd-next` can
pick overlapping work or race on the same file. The intended team workflow — product +
tech lead run `/sdd-plan` to lay down all epics as drafts, then **each developer takes
one epic** and owns its `/sdd-drill` + `/sdd-next` — is currently a convention with
nothing enforcing it. This epic adds the ownership primitives and (later) the team
coordination rules that make "one developer, one epic" real, without regressing the
solo experience.

## Success criteria (epic level)
- Ownership is a first-class, backward-compatible concept: with no owner set, behavior
  is exactly as today (solo).
- A developer can scope `/sdd-next` to their own work so parallel developers on a
  shared TaskStore don't collide or duplicate.
- Team coordination rules (claim an epic → drill unassigned work → claim a feature on
  `/sdd-next`) are expressible without forking any role file.
- Optional: a live, board-agnostic backend gives *atomic* claims (true
  anti-duplication) for teams that want it — added as a provider, never by making the
  one-way board mirror bidirectional.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Ownership primitive: `owner` field in TaskStore + scoped `/sdd-next` | pending | true | — |
| F02 | Team-claim rules (claim epic → drill unassigned → claim feature), gated on team mode | planned (not yet seeded) | true | F01 |
| F03 | Live board-agnostic ownership backend for atomic claims (Jira / GH Projects / …) | planned (optional/later) | true | F01, F02 |

## Notes — technical considerations & restrictions (for the driller/architect)
This epic was scoped in a design conversation. The **ownership-truth fork** was
resolved to **"owner field in tasks.json first"** (foundation-first). Record for
whoever drills F02/F03:

- **Three candidate homes for ownership truth** (increasing cost):
  1. **`owner` in `tasks.json` + board stays a one-way mirror** — chosen for F01.
     Cheap, works solo and git-shared teams, offline-friendly. Anti-duplication is
     only *eventually* consistent (simultaneous edits resolve via git merge).
  2. **A live read-authoritative store *backend*** (`store.tasks: jira` /
     `gh-projects`) — the architecturally correct home for team-shared, agent-read
     ownership; claims are **atomic**. This is F03. Belongs in the **store backend**
     abstraction (`local`/`obsidian`/`jira`, the last already stubbed), **not** the
     board mirror.
  3. **Bidirectional board mirror** — explicitly **rejected**: highest per-provider
     build cost and it muddies the mirror's "disposable one-way projection" role.
- **Keep the board mirror one-way.** `store/board-mirror.md` states `tasks.json` is the
  source of truth and agents never read the board; F01–F02 must preserve that. Live
  agent-read ownership, if built, is F03 as a *backend*, not a mirror change.
- **"Board/backend configured ⇒ team" heuristic** (for F02) is good, but pair it with
  an explicit `mode: team|solo` override — a board is not *required* to be a team
  (a git-shared umbrella + `owner` field is a valid teamless-of-board team), and a
  team may want a board while an individual works solo on a slice.
- **Two-level ownership** (F02): claim an **epic** (coarse), then claim **features**
  within it (fine). Drill produces *unassigned* features under an owned epic;
  `/sdd-next` claims a feature and syncs. Include a **release/reassign** path (a dev
  leaves, work is handed over) — assignment is not one-way.
- **Additive & non-breaking everywhere.** The `owner` field is optional; the schema
  change is backward-compatible (SemVer MINOR, not a MAJOR migration).
