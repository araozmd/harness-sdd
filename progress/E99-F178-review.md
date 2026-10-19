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
