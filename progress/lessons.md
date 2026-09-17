# Earned lessons (append-only)

> One entry per lesson that cost a review round, a rejection, or a debugging session to
> learn. Every role reads this file at session start; any lane may append. Never rewrite
> or delete an entry — supersede it with a newer one. Format:
>
>     - [YYYY-MM-DD <lane>] <the lesson, one or two lines, imperative>

- [2026-09-04 product-queue] `command -v missing-tool` exits 1 under macOS `sh` but 127
  under CI's dash — never assert on the exact exit code of a lookup miss; assert on ≠0.
- [2026-09-04 product-queue] An `onTaskUpdate` timeout usually means a blocked event
  loop, not load — profile the loop before raising the timeout.
- [2026-09-04 product-queue] `mkdtempSync` is not a safety signal — a unique dir name
  proves nothing about who else can write inside it.
- [2026-09-04 product-queue] Account for stray processes with a pid diff (before/after
  set difference), never a global `ps | grep -c` — the global count races every other
  lane on the box.
- [2026-09-04 product-queue] A timeout cap can hide a missing cache: when a step's time
  is capped, the cap firing looks identical to the step being fast. Verify the cache
  exists, don't infer it from elapsed time.
- [2026-09-05 builder] This repo's root `harness.config.yaml` is the SEED TEMPLATE fresh
  installs copy verbatim — a repo-local choice written there silently changes the shipped
  default for every future consumer (6 suites red). Repo-local model tiering lives in the
  `.claude/agents/*.md` shim `model:` keys instead; same pattern as the pr-loop
  severities (repo raises P2 locally, seed stays P0,P1).
- [2026-09-05 builder] `run-tests.sh --jobs 8` occasionally fails 2-3 unrelated suites
  under heavy box load; each passes standalone. Before chasing a "failure" in a suite
  your diff never touched, re-run it alone — and only debug if it fails solo.
- [2026-09-05 builder] Never invoke a bash-shebang script via `sh` inside a test suite —
  under the strict runner the suite runs in dash, and `set -o pipefail` (or any bashism)
  aborts the script at startup, making the test flake by host shell. Run it through its
  own shebang (`./script`).
- [2026-09-04 pr-loop] A hand-rolled severity classifier tested `nit` before defaulting
  — substring matches inside longer words mis-tag severities. First match wins **by
  position**, and matches must be word-boundary anchored. (Now enforced in
  `tools/wait-for-codex.sh classify` — use it, never re-implement.)
- [2026-09-05 orchestrator] `tasks-lock.py set-status` SYNCS SPEC FRONTMATTER as a side
  effect — commit the touched spec files WITH the board write, never `git add
  state/tasks.json` alone. A later `reset --hard` on that branch destroyed the synced
  frontmatter and broke init.sh's consistency gate on main for every downstream lane.
- [2026-09-05 builder] A board chore that rolls an epic/feature `done` without syncing the spec frontmatter breaks ./init.sh for EVERY later lane (E25-F01: board `done`, spec `in-review`) — the transition write path must update both, and a red init.sh at session start is worth checking against main before blaming your own diff.
- [2026-09-05 builder] A fixture COPIED from the repo inherits the artifact under test.
  E26-F02's "does `--self` write the glue manifest?" passed with the write deleted,
  because the copy already carried a committed, correct manifest. Any assertion about a
  file the fixture also ships must DELETE it first — otherwise the test proves the
  repo's state, not the code's behavior. (Same family as "assertion reachable by
  another path".)
- [2026-09-06 builder] A two-token folded-newline anchor (`grep -qiE
  'tokenA[^.]{0,N}tokenB'`) proves co-occurrence, not polarity: "Not strictly forbidden
  as the revert, but avoid: git checkout -- <file>" still satisfies a
  forbidden/git-checkout anchor. Chasing every negation/hedge shape is open-ended with
  no provably bounded cost (a prior Reviewer campaign against this exact sentence
  reached the same conclusion and logged it, `tests/test_reviewer_mutation_mandate.sh`)
  — state the bound in the convention (`agents/builder.md` "Co-occurrence is not
  polarity") instead of pretending a green suite proves polarity it never checked.
  Placement, by contrast, IS boundable: extract the section a block is expected to live
  in and require the anchor inside that span, not the whole file — a block moved
  verbatim to a later section/appendix then reddens (E99-F154 added
  `tests/test_reviewer.sh` R18/R19 for both).
- [2026-09-06 reviewer] "The file changed" is NOT "the intended line changed". A
  `replace(old, new, 1)` mutation on a script whose HEADER COMMENT quotes the same
  sentence as the `echo` silently edits the comment, so the runner sees a landed diff,
  the suite stays green, and you record a SURVIVED that proves nothing (hit twice in one
  campaign on `tools/wait-for-codex.sh`). Anchor the mutation to the line KIND you mean
  (`lstrip().startswith('echo')`), and print the applied diff — a landed-diff check alone
  cannot tell the two apart.
- [2026-09-06 reviewer] A test suite with a `#!/bin/sh` shebang but no `+x` bit turns
  `./tests/<suite>.sh` into "Permission denied" — a NON-ZERO exit that a mutation runner
  reads as a kill. An entire campaign reported 8 confident kills without ever executing
  the suite. Require a `FAIL:`/`not ok` line in the output before calling anything a
  kill, and green the suite once before mutating; rc alone is not evidence.
- [2026-09-06 reviewer] An assertion added in the SAME change as the prose it pins can be
  satisfied by that prose's own illustration: E99-F154's R18 anchored
  `forbidden[^.]{0,60}git checkout`, and the negated example it added one bullet below
  ("Not strictly forbidden … but avoid: `git checkout`") satisfied it alone — relocating
  the real rule left the suite green. When a section gains a counter-example, re-derive
  every anchor over that section and require a token only the real rule carries.
- [2026-09-14 builder] Source self-generation must derive escalation arming after reconciling actual Builder/heavy files and current ownership, not from a successful temporary consumer install; a protected edited or symlinked source role otherwise keeps an optimistic armed verdict. Pin both blocked/unstamped Builder cases and an unaffected Scout control (`test_codex_native.sh`, E29-F01 R11).
- [2026-09-16 reviewer] `_model_tier_resolve` has TWO independent tier-recognition arms —
  the own-config one and the umbrella-cascade one — and a vocabulary edit that `sed`s both
  at once is killed by `test_model_routing.sh` through the own arm ALONE. Mutate the
  umbrella arm on its own (`test_models_cascade.sh` only ever exercises
  reasoning/standard/cheap); E99-F159's new `frontier` arm and its umbrella warning both
  survived all 47 suites while a coordinator-set tier really did stop stamping.
- [2026-09-16 reviewer] A tier/vocabulary sweep must grep the PIPE-NO-SPACE form too:
  E99-F159's brief named `reasoning | standard | cheap` and `reasoning standard cheap`, and
  both miss `harness-install.sh:1770`'s contract comment `(reasoning|standard|cheap|inherit)`
  — the docstring of the very function being edited. Grep the intent, not the sample pattern.
- [2026-09-16 reviewer] The `models:` seed block's fresh-vs-migrated byte-identity is
  UNPINNED: desyncing `harness-install.sh:271` from `harness.config.yaml:227` passes all 47
  suites. Only the `workers:` block has a convergence test
  (`test_install.sh:test_workers_block_seeded_migrated_converge`) — copy it before trusting
  a hand `diff` on any block-text edit.
- [2026-09-16 reviewer] An assertion on ONE warning must anchor that warning's distinguishing
  prefix and its payload in the SAME `grep` (one line), never as two independent greps over
  the combined output: in umbrella mode the coordinator root is itself an installed target,
  so its OWN-arm warning for the same bad value co-occurs with the umbrella-arm one and
  satisfies a payload-only grep. E99-F159 round 2 hit this live — the two-grep form passed
  against a mutant that regressed only the umbrella sentence. Probe: break the sentence under
  test, dump the output, and confirm the intact decoy is still sitting there when it reds.
- [2026-09-16 reviewer] A vocabulary sweep must CLASSIFY its hits, not just count them.
  `tests/fixtures/<component>-v<version>/**` is frozen installer output under a `SHA256SUMS`
  manifest — stale vocabulary there is the point, and editing it falsifies the snapshot and
  breaks the manifest. Same for `CHANGELOG.md` and a `done` feature's own spec/plan. A sweep
  report that lists "the only surviving hits" without these is an under-count the next sweep
  will inherit.
- [2026-09-16 reviewer] A block extractor bounded by the block's CURRENT LAST CONTENT LINE
  (`awk ... m && /^  # pin\.claude\.reasoning: ""$/ { exit }`) guards only a PREFIX: a line
  appended after that anchor but still inside the block is invisible, so the convergence test
  stays green on a real desync (E99-F160 M8/M8b survived all 47 suites). Bound blocks
  STRUCTURALLY — blank line, heredoc `EOF`, or the next top-level key — never on the line that
  happens to be last today, because "append one more entry" is the likeliest next edit.
- [2026-09-16 reviewer] "Both extracts empty ⇒ `cmp -s` passes" is the vacuous shape to probe on
  any extract-and-compare test, and a per-file `[ -s ]` guard genuinely closes it — but only for
  the START anchor. Probe the END anchor separately in BOTH directions (deleted in one file, in
  both, and content added past it): the empty-extract route and the over-run route fail loudly,
  while the past-the-anchor route is the one that passes silently.
- [2026-09-16 reviewer] A STRUCTURAL block bound (`m && (/^$/ || /^EOF$/) { exit }`) fixes the
  append-past-the-end hole but opens the mirror one: a blank line inserted INSIDE the block
  truncates the capture, and because the capture is still non-empty the `[ -s ]` guard stays
  silent. Symmetric in both copies it is a vacuous pass — E99-F160 MF2/MG/ML: one blank line
  after the anchor in both files, plus a real one-sided desync, and all 47 suites stay green.
  Any extract-and-compare test needs a LENGTH FLOOR (`[ "$(wc -l < x)" -ge N ]`), not just
  `[ -s ]`; `[ -s ]` only pins the START anchor.
- [2026-09-16 reviewer] `sed -i '270a\' -e '' <file>` does not insert a blank line — GNU sed
  reads `270a\` as a filename and exits non-zero having changed nothing. The mutant then runs
  green and looks like a SURVIVOR. Only the mandated "print the applied diff" caught it (empty
  diff = void run, not evidence). Insert blank lines with `awk 'NR==N{print; print ""; next}1'`.
- [2026-09-16 reviewer] Codex reads project-local `.codex/agents/*.toml` ONLY when the
  project is trusted (`trust_level = "trusted"` in `~/.codex/config.toml`), so a probe run
  inside a fresh temp install target sees nothing and reads as proof of absence. `codex
  doctor` DOES check agent tomls — in a trusted repo an unknown key surfaces as `startup
  warning  Ignoring malformed agent role definition: … unknown field`. Probe in the trusted
  repo, and always run the positive control (a known-good file must produce NO warning).
- [2026-09-16 reviewer] Codex 0.154.0 rejects an unknown KEY in an agent toml (whole role
  discarded) but accepts an unrecognized VALUE for a known key silently — `model_reasoning_
  effort = "totally_bogus_zz"` loads clean. Do not let "unknown keys are fatal" justify a
  value guard in prose: they are different failure modes, and the doc that conflates them
  tells the next reader a bad value is fatal when it is not.
- [2026-09-16 reviewer] `./tools/run-tests.sh` `mktemp -d`s into `/tmp`, a 32G tmpfs shared
  with every other lane on the box. Under pressure whole suites red with `Disk quota
  exceeded` / `printf: write error` — the shape of real kills. Read `df` before AND after,
  and re-run with `TMPDIR=<disk-backed path>` before believing any multi-suite failure.
- [2026-09-16 reviewer] A file-MODE regression is invisible to this suite: every test runs
  the installer as `sh "$SRC/harness-install.sh"`, so dropping `+x` keeps all 47 green while
  the README's documented `./harness-install.sh` dies with "Permission denied". Check
  `git show --stat` for `old mode/new mode` lines on every review, and pin `[ -x … ]` for any
  script a doc tells a user to execute directly.
- [2026-09-16 reviewer] "This block has no convergence test" is a claim to MUTATE, not to
  derive from the named tests. A tail-anchored extractor (`awk '/^# anchor/,0'`) silently
  covers EVERY block after its anchor: `prl_block` in test_installer_toggles.sh/test_pr_loop.sh
  pins the `escalation:` and `workers:` seed blocks too, purely because they sit after
  `# Codex PR review loop` in harness.config.yaml. Both a Reviewer (E99-F161 R1) and the
  Builder who inherited it declared the escalation block unpinned by reading; one one-sided
  desync redded two suites. Two real weaknesses remain and are what to report instead: the
  coverage is ORDERING-DEPENDENT (move the block above the anchor and it vanishes with no
  test deleted), and the failure NAMES THE ANCHOR'S BLOCK ("the migrated pr_loop block is
  NOT byte-identical") while the desync is somewhere else entirely.
- [2026-09-16 reviewer] Every `[ -x "$T/.harness/tools/…" ]` assertion in tests/test_install.sh
  is VACUOUS with respect to the source repo's git mode: harness-install.sh:3655-3668 explicitly
  `chmod +x`'s each installed copy, so the assertion tests the installer's own chmod. Only a
  `[ -x "$SRC/<file>" ]` check reads the mode that a commit can drop. Proven: `chmod -x
  tools/fix-worktree.sh` keeps all 47 suites green while agents/fixer.md:282's documented
  `tools/fix-worktree.sh create …` dies with Permission denied.
- [2026-09-16 builder] `tests/test_codex_native.sh`'s R12 check
  (`assert (src/'VERSION').read_text().strip()=='0.79.0'`) pins the repo's CURRENT top VERSION
  as a literal, not a historical one — the exact "permanent-suite anti-pattern" other suites'
  own headers warn against. It broke immediately on E30-F01's routine MINOR bump, unrelated to
  that feature's own logic. The CHANGELOG-section split on the same line
  (`split('## [0.79.0]',1)`) is SAFE — it anchors a historical heading text that stays findable
  no matter what is prepended above it — only the bare `=='0.79.0'` VERSION-file comparison is
  fragile. Whoever bumps VERSION next must grep for the CURRENT value as a literal (not just
  `grep 0\.NN\.0 CHANGELOG.md`, which misses a bare VERSION-file comparison) before trusting a
  green `tools/run-tests.sh`; the fix is a one-line literal sync, not a design change.
- [2026-09-16 reviewer] A two-stage negative (`extract | grep <shape> | grep -qF <token> && fail`)
  fails OPEN when stage 2's pattern matches nothing: the `&& fail` is then unreachable for EVERY
  input and the assertion is decoration. E30-F01 shipped `grep 'pointer .stub'` against a doc
  that says `**pointer stubs**` (one space, not two chars) — zero matches on the pristine file
  AND on main, so re-adding the forbidden path to that sentence kept all 47 suites green. The
  `[ -n "$extracted" ]` staleness guard does NOT cover this: the span extracts fine, it is the
  PREDICATE that is dead. Before trusting any such negative, run its middle grep alone against
  the pristine file and require ≥1 line — a positive control on the SHAPE, not just on the span.
- [2026-09-16 reviewer] When a spec enumerates N authorities that must agree, count the
  ASSERTIONS, not the authorities: E30-F01's R11 named six and one had an unfirable predicate
  while `docs/INSTALL.md` had three sites the plan listed and only one asserted. Mutate each
  authority — and each SITE within it — separately; three of six survived and two restored
  verbatim the false ownership sentence the feature existed to delete.
- [2026-09-16 reviewer] A YAML key sweep written as `^[[:space:]]*[A-Za-z0-9_.-]+:.*<token>`
  matches the token only in the VALUE. It misses `<token>_mode:`, `<token>:` and `seed_<token>:`
  — i.e. every key NAMED for the thing being forbidden, which is the shape an ablation check is
  actually for. Alternate the key-name branch in explicitly.
- [2026-09-16 reviewer] "Exactly one line ON STDOUT" is two claims, and a test that captures
  `2>&1` pins only the first. Moving the verdict to stderr left E30-F01's R5 green. If the
  contract names a stream, capture that stream alone (`2>/dev/null`).
- [2026-09-16 builder] Fixing E30-F01's Finding 1/2 in round 2, a bare `var="$(A | grep B)"`
  assignment where the pipeline's final command legitimately finds no match ABORTS THE WHOLE
  `set -eu` SCRIPT SILENTLY — no `FAIL:` line, no error, just early exit — because a solitary
  assignment's own exit status is the exit status of the command substitution it ran, and
  under `set -e` that is fatal exactly like any other failing simple command. It happened
  applying the OWN mutant this round exists to catch: the fixed extraction correctly found
  zero lines, and the `[ -n "$var" ] || fail …` staleness guard one line below never got a
  chance to run because the assignment line above it had already killed the process. Any
  assignment whose RHS pipeline can legitimately produce a false/empty result — which
  includes every "locate this shape, then check it" two-stage negative this file's own
  lessons recommend — needs `|| true` on that assignment, not just on the final `[ -z ]`
  check. Verify by making the RHS deliberately match nothing and confirming the SCRIPT still
  reaches the `fail()` call, not just that `sh -n` parses.
- [2026-09-16 reviewer] A `set -eu` bare-command-substitution abort is **RED, not a false green** —
  correcting the attribution in the builder line above. Measured: `sh -c 'set -eu; v="$(printf a |
  grep zzz)"; echo REACHED'` exits 1 printing nothing, and `tools/run-tests.sh` reports the suite
  `===== FAILED (rc=1)` (`:384-406` treats any non-zero child rc, and even a missing rc file, as
  failure). What the abort destroys is the DIAGNOSTIC, not the signal: you get a log that simply
  stops mid-suite with no `FAIL:` line and no reason, which is why `|| true` + a named staleness
  guard is still the right fix. The genuine false green in that round came from the OTHER half of
  the same bug — a `[^.]*` sentence boundary truncating the forbidden token out of a NON-EMPTY
  extraction, which sails through `[ -n "$var" ]` and then finds nothing to forbid. Two different
  failures, two different symptoms: a log that stops early is an abort; `all N suites passed` with
  a mutant applied is a truncating or dead predicate. Diagnose by reading the suite log's last line
  before theorising.
- [2026-09-16 reviewer] An anchor grep that searches **its own suite file** always self-matches, so
  the `[ -n "$extracted" ] || fail "…anchor is stale"` guard beside it is unreachable for every
  input. `tests/test_install.sh:2599` greps that file for the literal its own line contains: 2 hits,
  never 0. Harmless there (the real assertions below still fire, and the self-match is what makes
  the bare assignment abort-proof), but it is the round-1 dead-guard shape wearing a safety label —
  and the same idiom pointed at any OTHER file is a live abort. Before trusting a self-grep's
  staleness guard, count the matches on the pristine file and ask which one is the grep line.
- [2026-09-16 reviewer] When a two-stage negative is scoped by `grep <shape>` rather than by a
  structural span, it covers exactly the LINES the shape lands on — so the same forbidden claim
  survives a line re-wrap. E30-F01's `docs/CONFIG-LAYERING.md` negative greps the one line holding
  `pointer stub`; restoring `main`'s text there dies, but moving the identical path onto the
  sentence's OTHER line (a plain markdown re-wrap, no meaning changed) kept all suites green.
  Mutate the re-wrapped variant too, not just the verbatim revert: prose reflows on every edit, and
  a line-scoped negative silently narrows every time it does.
