---
id: E34
title: "Resource hygiene: automated scratch-dir sweep for finished features"
status: done             # closed with its one delivered feature; deferred ideas route through a future /sdd-new, not a drill of this epic
owner: araozmd
---

# Epic E34 — Resource hygiene: automated scratch-dir sweep for finished features

**Scope note (2026-09-29, post-rollup correction):** this epic's original brief and
success criteria below covered three artifact kinds — scratch files, `progress/`
handoff files, and git worktrees/branches. Only the scratch-directory sweep was ever
seeded, specced, and built (E34-F01); the other two were explicitly deferred (see
Notes) and never became board features. Closing this epic `done` while its stated
success criteria still named undelivered work was flagged as misleading by Codex
review on the done-rollup PR (#234) — title and success criteria below are corrected
to describe only what `E34-F01` actually shipped. The deferred handoff-file and
worktree/branch sweeps are **not** carried forward as open scope on this epic; they
are ideas for a **separate, future `/sdd-new` intake** (a new epic or feature, seeded
fresh when someone wants to build them), not unfinished work blocking this one's
closure.

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

This epic makes scratch-file cleanup a **standing discipline** instead of a per-prompt
ask: a defined, bounded automated sweep for stale scratch dirs, plus explicit hand-off
rules in the relevant role files (`agents/builder.md`, `agents/reviewer.md`,
`agents/fixer.md`, `agents/pr-fixer.md`, `agents/orchestrator.md`) naming *when* each
role's own scratch becomes eligible for cleanup and who is expected to sweep it.
(The original brief also named `progress/` handoff files and merged worktrees/branches
as accumulating in the same way — see the scope note above for why those are not part
of this epic's delivered or remaining scope.)

## Success criteria (epic level)

- A sweep — tool-invoked, not re-typed into every prompt — reclaims `scratchpad/`
  entries whose feature is `done` and no longer being read by any in-flight role.
  **Delivered** as `tools/sweep-scratch.sh` (E34-F01).
- The sweep is **never destructive to in-flight work**: it must not delete a scratch
  dir tied to a feature that is not `done`, and it must fail closed (skip, don't
  guess) when it can't determine that. **Delivered.**
- Each relevant role file states, at its own hand-off point, that it never removes its
  own `scratchpad/<feature-id>-<role>/` directory itself — only the sweep does, once
  the owning feature is `done`. **Delivered** across `agents/builder.md`,
  `agents/reviewer.md`, `agents/fixer.md`, `agents/pr-fixer.md`, with invocation hooks
  in `agents/orchestrator.md`'s main-path and umbrella-rollup `done` writes and in the
  parallel-fix lane's P7 finalizer.
- ~~`progress/` handoff-file sweep~~ and ~~git worktree/branch sweep~~ — **not
  delivered, not carried forward as open scope on this epic.** See the scope note
  above and Notes below.

## Features

| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| E34-F01 | Automated scratch-dir sweep + role hand-off rules for finished features | done | true | — |

This epic is closed with exactly the one feature above. The two ideas named in Notes
below (`progress/` handoff-file sweep; git worktree + local-branch sweep) were never
seeded on the TaskStore and are **not** open scope on this epic — see the scope note
under the title. They remain documented here only as a pointer for whoever picks them
up later via a fresh `/sdd-new`.

## Notes

- **Split decided at spec time (E34-F01 Architect pass, 2026-09-28).** The full epic
  scope, specced as one feature, produced 14+ candidate requirements before role-file
  edits were even counted — over the `max_requirements: 12` budget. The seam this
  epic's own notes anticipated (split by artifact kind) is the one taken: E34-F01 specs
  only the scratch-directory sweep (the largest measured cost — 654M, entirely scratch —
  and the simplest liveness signal, TaskStore status). A `progress/` handoff-file sweep
  and a git worktree + local-branch sweep (general backstop outside E15's lane; remote-
  branch deletion deferred further, needing its own confirmation gate) are the two
  follow-on ideas this seam implies — **not seeded on the TaskStore, drilled, or
  specced, and not open scope on this now-closed epic** (see the scope note under the
  title). Whoever picks either one up later seeds it fresh via `/sdd-new`, which
  triages it to a new epic or feature on its own merits rather than reopening this
  one. See
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
