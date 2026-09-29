---
id: E34
title: "Resource hygiene: bounded cleanup of scratch files, handoff files, and merged worktrees/branches"
status: done             # legacy alias of planned; drill when ready to decompose further
owner: araozmd
---

# Epic E34 — Resource hygiene: bounded cleanup of scratch files, handoff files, and merged worktrees/branches

## Business brief

Every agent and sub-agent that works this harness writes local state as it goes:
namespaced scratch files under `scratchpad/<feature-id>-<role>/` (`agents/builder.md`,
`agents/reviewer.md`), per-run handoff files under `progress/` (inbox briefs,
`topology-handoff.md`, PR-loop round caches), and — when work runs in isolated
worktrees (E15's parallel fix lane, or an `isolation: worktree` sub-agent) — local
worktrees and branches. None of this is garbage-collected once the work it belonged
to is done. Measured in this repo at seed time: `scratchpad/` alone is 654M, with the
largest entries (`E31-F02-reviewer` at 212M, `E31-F02-builder` at 168M,
`E28-F02-builder` at 92M) belonging to features that finished weeks ago; there is a
`prunable` worktree sitting under `/tmp`; and both a local and several remote branches
already merged into `main` were never deleted. The existing discipline —
"namespace your scratch file" in `agents/builder.md`/`agents/reviewer.md` — says where
to *write*, not when to *remove*, and today the only mitigation is a human manually
telling agents in-prompt to clean up after themselves every time. That doesn't scale:
it's easy to forget, it's per-prompt rather than durable, and on a machine running many
sub-agents concurrently it exhausts disk quota. The users are anyone running this
harness with multiple concurrent sub-agents/worktrees, and, secondarily, the harness
maintainer who has to explain the same cleanup instruction over and over.

This epic makes cleanup a **standing discipline** instead of a per-prompt ask: a
defined, bounded automated sweep for what accumulates (stale scratch dirs, consumed/
superseded handoff files, merged worktrees and branches), plus explicit hand-off rules
in the relevant role files (`agents/builder.md`, `agents/reviewer.md`, `agents/fixer.md`,
`agents/pr-fixer.md`, `agents/orchestrator.md`) naming *when* each role's own artifacts
become eligible for cleanup and who is expected to remove or sweep them.

## Success criteria (epic level)

- A sweep — tool-invoked, not re-typed into every prompt — reclaims: `scratchpad/`
  entries whose feature is `done` (or otherwise terminal) and no longer being read by
  any in-flight role; `progress/` handoff files that carry a `consumed`/superseded
  marker (the pattern `agents/driller.md`/`agents/planner.md` already use for
  `topology-handoff.md`) or otherwise belong to a completed run; and git worktrees/
  local+remote branches already merged into the default branch, excluding anything
  still checked out or referenced by an open PR.
- The sweep is **never destructive to in-flight work**: it must not delete a scratch
  dir, handoff file, worktree, or branch tied to a feature that is not in a terminal
  state, and it must fail closed (skip, don't guess) when it can't determine that.
- Each relevant role file states, at its own hand-off point, what it is responsible for
  leaving cleanly behind (or removing itself) versus what the sweep will catch later —
  so cleanup timing is a defined contract, not an implicit hope.
- (To be defined at drill/spec time, informed by the mechanism choice already made
  during intake — see the inbox brief: an automated sweep tool backed by explicit
  role hand-off rules, not role-file discipline alone and not tooling alone.)

## Features

| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| E34-F01 | Automated scratch-dir sweep + role hand-off rules for finished features | done | true | — |

Not yet seeded on the TaskStore (`state/tasks.json`) — the two follow-on features named
in Notes below (`progress/` handoff-file sweep; git worktree + local-branch sweep) have
no board row yet. Seeding one is an Orchestrator/`tasks-lock.py add-feature` action, not
a Doc-only edit, so this table intentionally does not list them as rows until then.

## Notes

- **Split decided at spec time (E34-F01 Architect pass, 2026-09-28).** The full epic
  scope, specced as one feature, produced 14+ candidate requirements before role-file
  edits were even counted — over the `max_requirements: 12` budget. The seam this
  epic's own notes anticipated (split by artifact kind) is the one taken: E34-F01 specs
  only the scratch-directory sweep (the largest measured cost — 654M, entirely scratch —
  and the simplest liveness signal, TaskStore status). A `progress/` handoff-file sweep
  and a git worktree + local-branch sweep (general backstop outside E15's lane; remote-
  branch deletion deferred further, needing its own confirmation gate) are the two
  follow-on E34 features this seam implies — **not yet seeded on the TaskStore, drilled,
  or specced**. Each needs a board row (`tasks-lock.py add-feature`) and its own
  `/sdd-drill` or direct Architect pass before it is workable. See
  `specs/epics/E34-resource-hygiene/F01-cleanup-discipline/E34-F01.spec.md`'s Context and
  Out-of-scope sections for the full reasoning.
- E34-F01 also decided: no new `/sdd-*` slash command (the sweep is a standalone
  `tools/*.sh` helper invoked directly, matching E15-F02's `tools/fix-worktree.sh`
  precedent); the Orchestrator's existing "Writing `done`" step invokes it, scoped to the
  one feature that just landed, best-effort; it is also directly runnable on demand
  (unscoped, to backfill already-`done` features' scratch — including the 654M that
  predates this feature).
- Related, but distinct in scope: E15 (`Worktree-per-fix isolation helper`) already
  tears down the parallel-fix lane's *own* worktrees on that lane's exit path. The
  not-yet-seeded worktree/branch follow-on feature above is the general backstop outside
  that one lane (e.g. sub-agent sessions run with `isolation: worktree`, or ad hoc
  branches from manual work) — not a rewrite of it. Remote-branch deletion is flagged by
  the inbox brief as needing its own confirmation gate; that follow-on feature's own
  Architect pass decides that gate, not this note.
