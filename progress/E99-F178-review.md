# E99-F178 review — REJECT (one required doc fix)

Reviewed: c1fd569 on 13cba00, branch fix/E99-F178-opencode2-pin-host. 2026-10-19.

## Evidence
- `./init.sh` rc=0. Full suite rc=0: `all 78 suites passed (/usr/bin/sh [GNU bash 5.3.15], --jobs 16)`.
  No dash on this host, so the green comes from bash in sh mode, not dash.
- Guard equivalence: `opencode_pin_valid` was compared with Python `re.fullmatch(r'[^/#]+/[^#]+', s)`
  over 7394 strings. The corpus was every string up to length 4 over {a / # space é \n \t * \\}, plus extras
  (multi-slash ids, `//`, `a//b`, unicode, leading and trailing newline). The run used sh and bash, under
  en_US.UTF-8, C and C.UTF-8. **0 divergences** (906 accepted).
- Reachability: the only sources for `_rm_pin` are `_cfg_models_value` on the target config and
  `$UMB_MODELS_CFG` (the umbrella fallback). There is no env override for pins: no `HARNESS_*` variable
  feeds them. Both reads apply `sub(/[[:space:]]*#.*$/, "")`, so `#` is unreachable. The
  CHANGELOG, docs/INSTALL.md and the code comment are honest that it is defence in depth only.
- Mutation campaign: 19 mutants, each in its own git-archive copy, with a `.mutbak` restore verified by `cmp`.
  All 19 were KILLED, and each was killed by the assertion its label names (see the verdict message).
- Change-size: tier `ok` (56 prod lines / 3 files).

## Required fix
1. **docs/INSTALL.md:398** — the operator-facing "Which markers are trusted" table still reads
   `| opencode | OPENCODE, OPENCODE_PID | opencode 1.18.5 |`. The shipped row is now
   `OPENCODE OPENCODE_PID OPENCODE_SESSION_ID OPENCODE_TERMINAL` with a 2.0.32 baseline. A reader
   who is debugging an unexpected `opencode` detection, or an ambiguity warning, gets an incomplete
   marker list and stops looking. That makes this a 3c prose defect. Expected: list all four markers,
   and give the baseline as "opencode 1.18.5; 2.0.32".

## Required in the same edit (documentation of the nesting trade-off)
2. Adding OPENCODE_TERMINAL changes one realistic nesting case. Any CLI session started from an
   opencode 2.x `!` shell or PTY terminal inherits `OPENCODE_TERMINAL=1`. This includes Claude Code
   (CLAUDECODE), codex and pi. Until now that session resolved to the inner CLI, because the `!`
   shell carried no opencode marker. It now resolves as ambiguous: undetected, plus a warning.
   This is acceptable under R5: the fallback is inert, and `HARNESS_HOST_AGENT` overrides the
   markers. The test pins the tie (CLAUDECODE=1 + OPENCODE_TERMINAL=1 → undetected). But nothing
   says the trade-off was made. Add one sentence to the opencode provenance entry
   (harness-install.sh ~1739-1742) and one to INSTALL.md near the table. The sentence should
   say that a CLI launched from an opencode 2.x terminal now ties, and that the fix is
   `HARNESS_HOST_AGENT=<key>`.

## Advisory (non-blocking)
- The REJECTED list rejects `CODEX_CI` as "a mode flag, not a session id". OPENCODE_TERMINAL is
  also a `=1` flag. One clause in the provenance entry would stop the next contributor
  re-litigating it. The clause should say why it differs: opencode sets it on every shell and PTY
  it creates, in every mode, while CODEX_CI depends on the mode.

---

# E99-F178 review, round 2: REJECT (one required test fix)

Reviewed: 4002f50 on c1fd569 on 13cba00. 2026-10-19.

## Evidence
- `./init.sh` rc=0. Full suite rc=0: `all 78 suites passed (/usr/bin/sh [GNU bash 5.3.15], --jobs 16)`,
  TMPDIR=/var/tmp/E99-F178-review2 (removed afterwards).
- Round-1 fixes verified. docs/INSTALL.md:398 lists all four markers with the baseline `opencode 1.18.5; 2.0.32`.
  The nesting trade-off is recorded in INSTALL.md:405-408 and in the harness-install.sh provenance entry (~1742-1747).
  The CODEX_CI clause is present. Outside progress/, specs/ and the 0.75-era CHANGELOG history (CHANGELOG.md:3692),
  no stale two-marker row is left.
- Mutants, each in a git-archive copy, restored with cp and checked with cmp. All were KILLED, each by its named assertion:
  - guard back to `*/*`: killed by test_model_routing ("pin '/m' was not warned about");
  - OPENCODE_TERMINAL dropped from the row: killed by test_agents_host ("OPENCODE_TERMINAL=1 alone did not resolve")
    and by test_worker_roster;
  - OPENCODE_TERMINAL dropped from the provenance: killed by test_agents_host R8;
  - the qualification reason dropped: killed by test_agents_host ("does not record why OPENCODE_TERMINAL qualifies");
  - the whole 2.0.32 provenance dropped: killed by test_agents_host R8.
- The test_codex_native.sh pop-list change has NO observable effect. Its c1fd569 version passes with
  OPENCODE_TERMINAL=1 or OPENCODE_SESSION_ID exported (rc=0), because every host-mode run there sets
  HARNESS_HOST_AGENT. So it is correct hygiene, but it is unpinned.
- Change-size: tier `ok`.

## Required fix
1. **tests/test_frontend_retirement.sh:21.** This env-pop list is the same class as the one fixed in
   test_codex_native.sh, and it was missed. It still pops only `OPENCODE`, `OPENCODE_PID`. Line 47 runs
   `--agents=host` and expects the fallback `claude\n`, so any ambient OPENCODE_SESSION_ID or OPENCODE_TERMINAL
   now makes the installer detect `opencode`, and the assertion fails.
   - Observed at HEAD: `OPENCODE_TERMINAL=1 sh tests/test_frontend_retirement.sh` gives rc=1 (AssertionError, heredoc
     line 39). `OPENCODE_SESSION_ID=ses_x` gives rc=1. A clean env gives rc=0, and `OPENCODE=1` gives rc=0.
   - Base 51c318c with both variables exported gives rc=0. **This is a regression introduced by this branch.**
   - Full suite under a simulated opencode 2.x agent-shell env (`AGENT=1 AI_AGENT=opencode OPENCODE=1
     OPENCODE_SESSION_ID=… OPENCODE_TERMINAL=1`): test_frontend_retirement.sh is the only env-caused failure.
     (test_feedback_labeler also failed, but only because the archive copy has no git history; it passes in the
     repo under the same env.) So the suite goes red when a Builder runs it from an opencode 2.x session or a `!`
     shell, which is exactly the host this item targets.
   - Expected: add 'OPENCODE_SESSION_ID','OPENCODE_TERMINAL' to that tuple. Re-run the command above and get rc=0.

## Advisory (non-blocking)
- Pin the pop lists so the next marker can't slip again. For example, a check in test_agents_host.sh
  could assert that every HOST_MARKERS variable appears in each test that clears host markers with `env.pop`, or
  the two tests could derive their list from the table.
- The CHANGELOG 0.97.1 entry mentions only the upside (`!sh harness-install.sh` is now detected). It doesn't
  mention the operator-visible downside: claude, codex or pi nested in an opencode 2.x terminal now resolves as
  ambiguous and warns. One clause would help. The provenance header ("on 2026-07-28", "against a plain login
  shell") and the "Caveat recorded honestly" paragraph (exec/run/-p only) are now slightly stale for the 2.x
  serve and `!` observation. The 2.x entry carries its own date and method, so this is not misleading.
