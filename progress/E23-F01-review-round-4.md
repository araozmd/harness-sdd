---
feature: E23-F01
role: reviewer
round: 4
verdict: rejected
date: 2026-07-29
---

# E23-F01 review round 4

Live Codex destination symlinks are now rejected correctly. One symmetric Important
ownership issue remains in last-written stamp paths.

Stamp creation, ownership comparison, and cleanup still follow symlinks under:

- `.harness/.codex-skills/<command>/` (including `agents/` and both leaves);
- `.harness/.model-agents/<front-end>/` (including role stamp leaves).

A symlinked stamp can receive external writes, authorize a foreign live file as owned,
or cause cleanup to remove files outside the repository.

Required fix:

- reject every symlinked writable stamp-tree component and stamp leaf before compare,
  copy, removal, directory cleanup, or use as ownership evidence;
- when stamp safety is unknown, preserve live artifacts and external stamp targets;
- create no replacement stamp through the link;
- add selected-install, routing-change, gate-off, and deselection regressions with
  symlinked stamp directories and leaves;
- prove all external bytes remain unchanged and prior live-destination/non-Codex
  regressions remain green.
