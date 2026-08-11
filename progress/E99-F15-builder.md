---
feature: E99-F15
agent: builder
date: 2026-08-11
---
# E99-F15 — one choke point for every spec/epic filesystem read

## What changed

`tools/validate-board.py` gained `_read_contained(root_real, path)`: it resolves the path,
containment-checks it against the harness root, and only then opens it. It is the ONLY
function in either tool that opens a spec or epic document.

- `_frontmatter(root_real, path)` now goes through it and returns a new `_ESCAPED` sentinel
  alongside the existing `_UNREADABLE`. The pure parse split out as `_parse_frontmatter(text)`
  so the writer can reuse text it already read.
- `spec_consistency_errors` read sites both call it. The per-file `_contains` check written
  inline in round 4 is gone — the site gets containment by construction now.
- **The `epic.md` site is closed** (Codex #3741652119). New message, modelled on the R25
  spec-file one: `epic.md escapes the harness root: <path> — it resolves outside the
  repository, so the gate would certify an epic document that is not in it`.
- `tools/tasks-lock.py::_frontmatter_targets` dropped its own copy of the containment check
  and its own `io.open`; it reads once through `vb._read_contained` and carries the original
  text into the targets list.

## The two open questions in the brief, answered

**1. Opened handle or checked path?** Neither — the helper returns the CONTENT. A handle
would still let a caller hold something it opened for itself, and a checked path is
skippable by construction. Returning text means the check and the `open()` are the same
call, and the caller never possesses a path it could open unchecked. Cost was low: both
call sites already wanted frontmatter, not a path.

**2. Does the writer share the helper, or need a write-side twin?** A twin —
`tasks-lock.py::_write_contained`. The read helper answers "may I open this"; a writer that
borrowed it would be asking the wrong question a moment before doing something the answer
does not cover. The writer's READ routes through the shared entry point; its WRITE
re-establishes containment at the moment it writes, because a write is a second resolution
of the same name and this whole rule exists because a path is contained when it is resolved,
not once and forever. `_apply_frontmatter`/`_rollback_frontmatter` are the only writers and
both go through it; `_apply_frontmatter` no longer re-reads the original for rollback (that
would have been a read site the rule never sees) — the text comes from the targets list.

## Verification

- All **28 existing R-ids pass unchanged** — no test edited, so no behaviour change was
  smuggled in. The constraint in the brief is met literally.
- **R29** (new): an `epic.md` reached through a symlinked epic directory is an escape, the
  message names the path as the tree spells it, an in-repo symlinked epic dir stays green,
  and the writer refuses it without moving the board.
- **R30** (new): replaces `_read_contained` and requires the verdict to change for BOTH
  documents. A read site that kept its own `open()` would go on comparing statuses and the
  expected error would not appear — the assertion is not reachable by another path.
- Mutation-checked: with `tools/` reverted to main, R29 fails ("the epic.md escape was not
  reported") and R30's probe cannot even run (`_ESCAPED`/`_read_contained` absent).
- `sh tools/run-tests.sh` → all 34 suites pass. `sh init.sh` green.

## Out of scope, deliberately

- WHAT is contained (root, not `specs/`) — settled in E99-F14 round 2.
- The status/ownership/ambiguity rules.
- The JS tools (`tools/next-task.mjs`, `tools/sync-board.mjs`) do not read spec documents.
