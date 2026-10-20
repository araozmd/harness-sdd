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

---

# Round 2 review: REJECT (one required fix plus one small pin)

Reviewed: 6f4f73b on e543f23 on 23a61c7, 2026-10-20. Scratch: scratchpad/E99-F179-review2/.

## Evidence
- `./init.sh` rc=0. Full suite rc=0: `all 78 suites passed (/usr/bin/sh [GNU bash 5.3.15], --jobs 16)`,
  run with TMPDIR=/var/tmp/E99-F179-review2, which was removed afterwards. Free space was 642G on / before and after.
- Mutants were run in a private `git archive` copy, one at a time, with each diff printed and each restore checked with cmp:
  - KILLED: X1 (dq clause), X2 (`sc = 0`), unset clause only, env -u clause only, bare `-u` (killed by the sort -u fixture),
    X4 (owner text), `cont` dropped from `sc`, `cont = 0`, per-line flush (multiline), and the sq clause (killed by the floor).
  - SURVIVED: see fix 2 and the advisories.
- Round-1 probes: the correct `unset … \` continuation now gives LIST with no MISS, and the broken one is caught.
- Edge cases:
  - Continuation into a non-scrub line: OK.
  - Next statement after a continuation: no leak.
  - Trailing `\` at EOF: OK.
  - CRLF: `\`+CR is not a continuation. sh agrees (it runs the next line as a command), and no tests/*.sh has CR, so this does not matter.
- Real lists: test_codex_native.sh and test_frontend_retirement.sh each give one LIST, so the floor holds.
- HOST_MARKERS is unchanged, and the harness-install.sh diff is comment-only.
- Change-size: tier `ok`.

## Required fixes
1. **An `env -u` list written one flag per line is invisible.** This is at tests/test_agents_host.sh:296.
   - The cause: `/(^|[ \t;])env[ \t].*[ \t]-u[ \t]/` needs whitespace both after `env` and before `-u`, so the
     first `-u` in `env -u X` never matches. A line matches only when it has a second `-u`.
   - The effect: this idiomatic scrub is not recognised, whether complete or missing PI (no LIST, silent pass):
     ```
     env -u CLAUDECODE \
         -u CLAUDE_CODE_ENTRYPOINT \
         -u CODEX_THREAD_ID \
         -u OPENCODE -u OPENCODE_PID -u OPENCODE_SESSION_ID -u OPENCODE_TERMINAL \
         cmd
     ```
   - Why the self-test misses it: the `envu_cont` fixture puts three `-u` on its first line.
   - The CHANGELOG says "`env -u` lists (including backslash-continued ones) … are checked", and the 6f4f73b
     subject says the same. Under 3c that is an over-claim.
   - Expected: change the regex to `/(^|[ \t;])env[ \t](.*[ \t])?-u[ \t]/`. In the reviewer's private copy this made
     the form above give `LIST|MISS PI_CODING_AGENT pi`; the complete form gave `LIST`, `sort -u` was still ignored,
     and the suite stayed green. Add an `envu_perline` fixture (one `-u` per line) and show that reverting the regex
     goes red.
2. **Word-boundary matching is unpinned (XW survived).** Replacing the `(^|[^A-Za-z0-9_])V([^A-Za-z0-9_]|$)` test
   with `index($0, V[i])` leaves the suite green.
   - Under that mutant, `unset … OPENCODE_PID …` with OPENCODE missing passes silently, because OPENCODE matches
     inside OPENCODE_PID.
   - The comment claims "naming V as a word" and "The matcher is pinned".
   - Expected: add OPENCODE to the `_miss` loop (`for _miss in PI_CODING_AGENT OPENCODE_TERMINAL OPENCODE`). Its
     unset/envu fixtures still contain OPENCODE_PID, so they kill XW.

## Advisory (non-blocking; both fail loud, not silent)
- XG survived: `cont = ($0 ~ /\\$/)`, which drops the `sc &&` gate.
- XA survived: dropping the CODEX_THREAD_ID anchor requirement. The anchor rule predates this feature.

---

# Round 3 review: REJECT (two small required fixes)

Reviewed: 070847b on 6f4f73b on e543f23 on 23a61c7, 2026-10-20. Scratch: scratchpad/E99-F179-review3/.

## Evidence
- `./init.sh` rc=0. Full suite rc=0: `all 78 suites passed (/usr/bin/sh [GNU bash 5.3.15], --jobs 16)`, run with
  TMPDIR=/var/tmp/E99-F179-review3, which was removed afterwards. Free space was 642G on / before and after.
- change-size tier: `ok`.
- HOST_MARKERS is byte-identical to c5f7af3. The harness-install.sh diff is comment-only, and the provenance and caveat
  prose matches the per-front-end entries.
- Mutants were run in a private `git archive` copy of the full tests/test_agents_host.sh, one at a time. Each diff
  was printed and each restore checked with cmp.
  - KILLED: R (old env regex, by envu_perline), XW (index), XW-trailing boundary, XG, XA (CODEX anchor), XA2 (CLAUDE
    anchor), X1, X2, X4, X4b (owner lookup), unset clause only, env -u clause only, bare `-u` (sort -u), cont dropped
    from sc, `cont=0`, per-line flush, and the sq clause (killed by the floor).
  - SURVIVED: XW-leading boundary (fix 2), `n &&` in flush (an equivalent mutant), the floor set to `-ge 0`, and the
    guard's `MISS) fail` set to `:` (see advisories).
- Reviewer fixtures that the self-test does not cover, each run as complete / missing PI / missing OPENCODE:
  - All correct (LIST, plus the right MISS and owner): `env -u A -u B cmd` on one line, `unset` with TAB separators,
    tab-indented `unset … \` continuation, `unset` one per line with `\`, Python `for k in ("…",\n "…",\n):
    env.pop(k, None)`, a `del env['…']` sequence, `os.environ.pop("…", None)` per line, `unset -v`,
    `HOME=x env PATH=… -u …`, `cd x && unset …`, and `if ! env -u …`.

## Required fixes
1. **Silent miss: an `unset` / `env -u` list that opens a subshell or command substitution is invisible.**
   This is at tests/test_agents_host.sh:296. The leading class `(^|[ \t;])` does not admit `(`, `` ` `` or `|`.
   - These shapes give no LIST and no MISS, so they pass silently whether the list is complete or missing a variable:
     - `(unset CLAUDECODE … ; sh x)`, the canonical one-command scrub;
     - `out="$(env -u CLAUDECODE … sh x)"`, the shape this repo already uses at tests/test_install.sh:1824
       (`"$(env -u HOME -u CODEX_HOME sh …)"`);
     - `` out=`env -u …` ``;
     - `echo y |env -u …`.
   - These are `unset` / `env -u` lists. The guard comment and the CHANGELOG 0.97.2 say such lists "are checked", and
     STILL NOT SEEN does not name these shapes. Under 3c that is a silent miss of a claimed form.
   - Expected: change both leading classes to `(^|[^A-Za-z0-9_.$-])`.
     - In the reviewer's private copy this fixed all four shapes (LIST, plus `MISS PI_CODING_AGENT pi` /
       `MISS OPENCODE opencode`).
     - `sort -u CLAUDECODE CODEX_THREAD_ID x` was still ignored, and the full test_agents_host.sh stayed green on the
       real tests/*.sh.
   - Add a `subshell` form to the fixture loop (for example `(unset <vars>; cmd)` or `x="$(env -u … cmd)"`), and show
     that reverting the class goes red.
   - Alternatively, name the form under STILL NOT SEEN and in CHANGELOG. The fix is cheaper than that.
2. **The leading word boundary is unpinned, yet 070847b says "pin whole-word".**
   - Mutant: `("(^|[^A-Za-z0-9_])" V[i] "([^A-Za-z0-9_]|$)")` becomes `(V[i] "([^A-Za-z0-9_]|$)")`. rc=0, SURVIVED.
   - Why the suite misses it: no HOST_MARKERS variable is a suffix of another, so fixtures built only from table names
     cannot kill it.
   - What it lets through: under the mutant, `unset X_CLAUDECODE CODEX_THREAD_ID` is read as a scrub list, and
     `unset MY_OPENCODE …` would mask a missing OPENCODE.
   - Expected: add a negative fixture, `printf 'unset X_CLAUDECODE CODEX_THREAD_ID\n'`, and assert that it gives no
     LIST. The reviewer checked that it gives LIST under the mutant and nothing at HEAD.

## Advisory (non-blocking)
- The real-file wiring is unpinned. `MISS) fail …` set to `MISS) :` survives, and so does the floor set to `-ge 0`.
  This was true before the feature: the F178 grep loop was equally unpinned, because the real lists are correct.
  - A cheap pin: let test_host_scrub_lists_cover_table take a directory, and run it in a subshell on a synthetic dir
    with one missing variable, expecting a non-zero exit.
- Unclaimed forms, each silent: `env --unset=VAR` and glued `env -uVAR`. Also, `unset … ; echo PI_CODING_AGENT` on the
  same line counts a non-scrubbed word, because sc is per line, not per statement. None exists in tests/.
- `n &&` in flush is redundant: h is non-empty only when n > 0. The mutant is equivalent, so this is not a finding.
- Pre-existing: CHANGELOG.md:5 still points at a non-existent "`CLAUDE.md` → Versioning".
