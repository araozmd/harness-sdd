# E99-F179 review: REJECT (two required fixes, both small)

Reviewed: e543f23 on 23a61c7 on c5f7af3, branch fix/E99-F179-host-marker-advisories. 2026-10-20.

## Evidence
- `./init.sh` rc=0. Full suite rc=0: `all 78 suites passed (/usr/bin/sh [GNU bash 5.3.15], --jobs 16)`,
  TMPDIR=/var/tmp/E99-F179-review (removed afterwards). No dash on this host, so this is bash in sh mode.
- Free space: 642G on / before and after the probes.
- HOST_MARKERS value is byte-identical to c5f7af3. The harness-install.sh diff touches only `#` lines. R8 is green.
- Change-size: tier `ok` (158 lines / 6 files, 0 production lines).
- Probes ran in a private `git archive` copy. They used a driver that runs only `test_host_scrub_lists_cover_table`
  against a temporary tests/zz_probe.sh. Each case had a missing variable:
  - KILLED: single-quoted list, double-quoted list, `unset` (also indented, and after `;`), `env -u`, a list
    split across lines (including one name per line), and an `env -u` list continued with `\`.
  - The failure text names the owner correctly (pi, claude, opencode).
  - Documented blind spots stay unseen, as stated: `startswith('OPENCODE')`, a list interrupted by a comment
    line, and a list with no CLAUDECODE/CODEX_THREAD_ID anchor.

## Required fixes
1. **`unset` with a `\` continuation is mishandled, and the guard comment does not name it.**
   This affects tests/test_agents_host.sh:295. `sc` is computed per line, so a continuation line
   (one with no `unset` on it) hits nothing.
   - A CORRECT scrub `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CODEX_THREAD_ID \` followed by
     `  OPENCODE OPENCODE_PID OPENCODE_SESSION_ID OPENCODE_TERMINAL PI_CODING_AGENT` goes RED:
     "omits OPENCODE". That is a false positive on an idiomatic shell scrub.
   - `unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT \` followed by `  CODEX_THREAD_ID OPENCODE` (PI and the others
     missing) passes silently. The list is never recognised.
   - The guard comment says "a list split across lines is one list", and the CHANGELOG says lists split across
     lines "are checked too". Neither is true for this form. The STILL NOT SEEN list omits it, and the brief
     requires that list to "name any form it still does not see". Under reviewer 3c this is a defect.
   - Expected: carry `sc` across a line that ends in `\` (about one line of awk), or name the form under STILL
     NOT SEEN and narrow the CHANGELOG wording. Re-run both probes above.
2. **The new guard capabilities are unpinned (3b).** In a private copy, one mutation at a time, the full
   tests/test_agents_host.sh stays GREEN when:
   - X1: the double-quote clause `|| index($0, "\"" V[i] "\"")` is deleted (rc=0);
   - X2: `sc = (...unset... || ...-u...)` becomes `sc = 0` (rc=0);
   - X4: the failure text goes back to "it would fail under an opencode session" (rc=0).

   The reason is that no real tests/*.sh uses those forms. The Builder's M1–M6 could only be killed by rewriting
   the real scrub lists, and nothing permanent in the suite does that. The brief requires that "any new guard
   capability has a mutant that the suite kills".
   - Expected: factor the awk into a function that takes a file. Add a self-test that writes synthetic
     fixtures to `$T`, one per supported form (sq, dq, unset, env -u, multi-line), each missing one
     variable. It should assert one LIST plus a MISS that names the variable and its owner, and assert that
     a complete fixture gives no MISS. Then show X1, X2 and X4 going red.

## Advisory (non-blocking)
- **New false-positive shapes (they fail loud, and none exists today).**
  - Consecutive lines that each quote one anchor are now treated as a scrub list and go red with the text
    "scrubs host markers but its list omits CLAUDE_CODE_ENTRYPOINT". For example:
    - `assert 'CLAUDECODE' in out` / `assert 'CODEX_THREAD_ID' in out`;
    - `grep -q "CLAUDECODE" f` / `grep -q "CODEX_THREAD_ID" f`;
    - `env['CLAUDECODE']='1'` / `env['CODEX_THREAD_ID']='x'`.
  - Any line containing ` -u ` with both bare words is also a scrub list, for example
    `printf … CLAUDECODE CODEX_THREAD_ID | sort -u`. So is `env -i -u X CLAUDECODE=1 CODEX_THREAD_ID=t`.
  - The single-line quoted case already existed before this change. Its double-quoted and multi-line variants
    are new.
  - Suggested fix: add one sentence to the guard comment ("lines that merely MENTION both anchors are treated as a
    scrub list; keep such assertions apart or out of tests/"). Alternatively, tighten the `-u` match to
    `env`-anchored.
- **Date attribution.**
  - "2026-07-28" is supported by the contemporaneous record. 5395e3c (E19-F01) introduced the claim and all
    three rows (claude, codex, opencode 1.x). Its author and commit date are 2026-07-28 01:40 -0600, and
    progress/builder-E19-F01.md is dated 2026-07-28 and says the `comm -13` procedure "was actually executed".
  - The work window ran from the 2026-07-27 19:30 seed (60001ef) to 01:40 on 07-28. The claude markers were
    first seen on 2026-07-27 (E19-F01.spec.md:82), but inside a live session, not as a `comm -13` delta.
  - The pi row (f0bd77b, 2026-10-13) and the opencode 2.x method (progress/inbox/E99-F178.md "Evidence") match
    the new prose.
  - Optional precision: "recorded 2026-07-28 (E19-F01)".
- **CHANGELOG 0.97.2** lists only prefix scrubs as unseen. The guard documents three forms (four after fix 1).
  Align them when fixing 1.
- Pre-existing and out of scope: CHANGELOG.md:5 points at "`CLAUDE.md` → Versioning", which does not exist.
  The bump rule lives at AGENTS.md:113-117 and covers harness-install.sh with no comment-only exemption, so
  PATCH 0.97.2 is correct.
