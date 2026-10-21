# Round 1 review: APPROVE

Reviewed: 056ffd0 on 53a76c7 (vs main fda0485), 2026-10-20. Contract: progress/inbox/E99-F181.md (sdd: false, no spec).
Scratch: scratchpad/mut/ (private git-archive copy of HEAD).

## Evidence
- `./init.sh` rc=0. Full suite rc=0: `all 78 suites passed (/usr/bin/sh [GNU bash 5.3.15], --jobs 16)`, TMPDIR under
  /var/tmp (removed afterwards, confirmed absent).
- Comment-only: `git diff main -- tests/test_agents_host.sh | grep '^[+-][^+-]' | grep -v '^[+-]\s*#'` prints nothing.
  The awk, the fixtures, scrub_check_dir and the assertions are byte-identical.
- Other files in the diff: the inbox contract, the history line, and state/tasks.json (E99-F181 entry plus a cosmetic
  re-indent of E99-F180's `landed` object by the lock tool, with identical values). No VERSION or CHANGELOG change, which is
  correct: tests/ is not part of the installed body.
- The new comment's claims were checked by mutating them, one at a time, in the archive copy. Each diff was printed, each
  file was restored from .mutbak, and each restore was confirmed with cmp against the working tree.
  - W3: `scrub_check_dir "$SRC/tests" 2` -> `:` SURVIVES (rc=0), as the comment says.
  - W4: real-call floor `2` -> `0` SURVIVES (rc=0), as the comment says.
  - `MISS) fail …` -> `MISS) : ;;` KILLED by test_host_scrub_wiring ("accepted an incomplete list"). So MISS->fail is pinned.
  - floor `[ "$_n" -ge "$2" ]` -> `-ge 0` KILLED by test_host_scrub_wiring ("accepted fewer lists than its floor"). The
    floor-comparison line deleted outright is also KILLED. So the floor comparison is pinned.
- Quoted false-positive claim, probed with a fixture tests/zz_probe.sh in the private copy:
  - `echo "unset CLAUDECODE CODEX_THREAD_ID"` -> RED (`zz_probe.sh scrubs host markers but its list omits
    CLAUDE_CODE_ENTRYPOINT …`).
  - `echo "env -u CLAUDECODE -u CODEX_THREAD_ID x"` -> RED, same message. This confirms the `env -u` half of the claim too.
  - With the probe removed the file is green again. The real tests/ tree has no such line (the suite is green).
- Style: `#` block comments in the same voice as the surrounding guard text. "MISS->fail" uses the ASCII arrow already used in
  history and reviews. Line width is within the surrounding block.

## Advisory (non-blocking)
- None.
