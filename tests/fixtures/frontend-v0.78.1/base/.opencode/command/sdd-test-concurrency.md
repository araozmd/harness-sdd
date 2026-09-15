---
description: Probe whether this OpenCode session can run subagents concurrently
---

Run a concurrency probe. This command spawns two trivial subagents and measures whether
OpenCode executes them in parallel.

1. Run `./.harness/init.sh` from the project root. If it exits non-zero, STOP: the harness
   considers this environment broken and the probe must not write a capability marker.
2. Prepare a temp directory under `.harness/progress/opencode-concurrency-probe/`
   (remove any previous probe first). This lives in the Scout role's allowed output area
   so the subagents do not have to violate their read-only contract.
3. Spawn **two** identical `scout` subagents **in the same response / at the same time**
   using the `task` tool. Give each subagent this exact job, with its own index `N` (1 or
   2) and the temp directory `DIR`:

   - Write `date -u +%FT%T` to `DIR/start-N.txt`
   - Sleep for 5 seconds
   - Write `date -u +%FT%T` to `DIR/end-N.txt`
   - Report completion

   Do not read files, do not run tests, do not modify source code. The only output must
   be the four timestamp files.
4. Wait until **both** subagents finish.
5. Read the four timestamps and compute the wall-clock span from the earliest start to
   the latest end.
   - If the span is **less than 8 seconds**, OpenCode ran the subagents concurrently.
   - Otherwise, OpenCode ran them sequentially.
6. Write the result to `.harness/.opencode-parallel` as exactly one word:
   - `supported`   (concurrent)
   - `sequential`  (sequential)
7. Report the result to the human:
    - **concurrent**: `/sdd-fix-parallel` is supported. Re-run the installer with
      `--with-opencode-parallel=true` to stamp it, or just re-run the installer if the marker
      already says `supported`.
   - **sequential**: `/sdd-fix-parallel` is NOT supported on this OpenCode setup. Use
     serial `/sdd-fix` for bounded fix batches.

This command changes no TaskStore state, no feature status, and no source code.
