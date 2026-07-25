---
id: E15
title: Parallel fix lane (concurrent E99 fixes in isolated worktrees)
status: done             # draft → planned → in-progress → done (pending = legacy alias of planned; rollup of its features)
owner: araozmd
---

# Epic E15 — Parallel fix lane (concurrent E99 fixes in isolated worktrees)

## Business brief
The harness runs work strictly one-at-a-time: the Orchestrator picks a single next
actionable task and waits for it to merge before the next begins. That gate keeps
`main` clean and `state/tasks.json` writes race-free, but it serializes even
genuinely independent work. The one place where parallelism buys real wall-clock
without moving a human bottleneck is the **E99 maintenance lane**: those fixes are
`sdd:false`, brief-only, and `autonomous:true` by default, so they carry **no
spec-approval human gate** to serialize on. This epic lets 2–3 independent E99 fixes
run **concurrently**, each in its own git worktree + branch + PR, with board writes
made safe under a lock. Scope is deliberately fenced to the E99 fix lane — this is
**not** general DAG-parallel execution of `sdd:true` features.

## Success criteria (epic level)
- Multiple independent E99 fixes build concurrently, each isolated in its own git
  worktree/branch, each producing its own PR — no interleaving on `main`.
- Concurrent writes to `state/tasks.json` never lose updates (no torn/overwritten
  board state); a serial `/sdd-next` run is behaviourally unchanged.
- Fixes whose briefs touch known shared files are detected and run **serially**, not
  in parallel — the merge-conflict tax is avoided, not merged away.
- One fix failing isolates to that fix (back to `in-progress` with feedback); the
  others proceed. No new status/enum values and no TaskStore schema change.

## Features
| id | title | status | sdd | depends_on |
|---|---|---|---|---|
| F01 | Board write lock: flock-guarded read-modify-write on tasks.json | done | true | — |
| F02 | Worktree-per-fix isolation helper for concurrent fix branches | done | true | F01 |
| F03 | /sdd-fix-parallel dispatch with shared-path conflict guard + installer wiring | done | true | F01, F02 |

## Notes — intended decomposition & restrictions
Intended feature shape for the driller (source of truth remains `state/tasks.json`;
`features: []` until drilled):

- **F01 — Board write lock (foundational).** Wrap every persisted `set_status` /
  board write in an advisory `flock` on `state/tasks.json.lock` (`cwd = HARNESS_DIR`).
  Sequence becomes: acquire lock → **re-read from disk** → mutate → validate
  (`json.load` + schema) → write → release. Re-reading *inside* the lock is the point
  — it prevents lost updates when two chains finish near-simultaneously. Must be a
  no-op for serial callers; `/sdd-next` unaffected. The best-effort `on_write_command`
  hook fires *after* release. `depends_on: []`.
- **F02 — Worktree-per-fix isolation.** Helper to `git worktree add` a fresh
  `feat/<id>-<slug>` branch off `main`, run the Builder→Reviewer loop there, and tear
  down on success/merge. Must recreate gitignored local files in the fresh worktree
  (see `docs/CONFIG-LAYERING.md`). Track active worktrees under `.claude/worktrees/`.
  `depends_on: F01`.
- **F03 — Parallel dispatch (`/sdd-fix-parallel`).** Fixer-family command that selects
  up to **N** E99 fixes matching `pending + sdd:false + autonomous:true +
  depends_on all done`, spawns N concurrent Builder→Reviewer chains (each in an F02
  worktree, each writing via the F01 lock). **Static shared-path conflict guard**:
  fixes whose briefs touch `harness-install.sh`, `tests/test_install.sh`, or `tools/*`
  are run serially, not parallelized. `N` from `harness.config.yaml`
  (`fix_lane.max_parallel`, default 3); cap it and **log what was deferred** (no silent
  truncation). Installer wiring: add to `HARNESS_SDD_CMDS`, generate
  `.claude/commands/sdd-fix-parallel.md`, assert its presence in
  `tests/test_install.sh`. `depends_on: F01, F02`.

Restrictions & non-goals:
- **Reuse existing primitives.** Build on `sdd:false` + `autonomous:true`; introduce
  **no new status/enum values and no `state/tasks.json` schema change**.
- **Fenced scope.** Do **not** parallelize `sdd:true` features (they gate on spec
  approval + Codex review — parallelizing their build phase moves no human bottleneck).
- **Single-machine locking only.** `flock` guards concurrent chains within one host;
  cross-terminal / cross-machine coordination is out of scope.
- **No auto-merge-conflict resolution.** The conflict guard *avoids* conflicts by
  serializing shared-path fixes; it does not merge conflicting hunks.
- **PR-before-done invariant holds.** Each fix parks at `in-review` until its PR
  merges; `/pr-loop` (Codex) review stays per-PR.
- **Installed-body change → VERSION bump** (MINOR); installer wiring asserted in
  `tests/test_install.sh`.
