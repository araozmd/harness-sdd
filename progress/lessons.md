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
- [2026-09-17 builder] A branch reaching the end of the §7 `printf | while read` reclaim loop is the
  LOOP BODY's last command, so its exit status becomes the loop's. Ending it on
  `[ -n "$var" ] && echo …` makes the loop return 1 whenever the list is empty (the common
  no-op case), and `set -e` then aborts the whole installer mid-run with no message and no
  diagnosis — the run simply stops after the previous `ok` line. Use
  `if [ -n "$var" ]; then echo …; fi` (a false `if` still returns 0), and pin it by running the
  no-op path (a target already reclaimed by an earlier phase). Same family as the bare-assignment
  abort lesson, one shell construct over.
- [2026-09-17 reviewer] Before trusting a `run-tests.sh` green on THIS box, read the shell it
  names AND check the fallback: `command -v dash posh ash` returns nothing here, so the
  runner falls back to `/usr/bin/sh` = **bash**. "all N suites passed (/usr/bin/sh [GNU bash …])"
  is a bash claim about `#!/bin/sh` suites, and a dash-only construct added in the diff would
  pass un-caught. Either install dash or report the green as bash-scoped, never as POSIX-sh-scoped.
- [2026-09-17 reviewer] Renumbering a numbered list is NOT reordering it: an E28-F01 mutant that
  changed the banner's step numbers (`2. /sdd-plan` → `3. /sdd-plan`, `/sdd-next` → `2.`) left the
  `/sdd-plan` line PHYSICALLY first, so the suite stayed green and read as a survivor. Reorder by
  moving the lines the assertion measures (`index($0, n)` scans output order, not the label), and
  let the mandated applied-diff print show the swap — it is what caught this as an instrument
  failure rather than a hole in R5.
- [2026-09-17 builder] A folded two-token anchor over markdown BLOCKQUOTE prose must account for
  the `> ` continuation prefix: re-wrapping a line inside `> …` inserts `> ` between its words, so
  `tr '\n' ' '` turns `draft\n> epics` into `draft > epics` and the `sdd-plan[^.]{0,60}draft epics`
  pair the anchor greps no longer exists (E28-F01 round 7 — the seeded `product.md` stub reddened
  R8b until both tokens were kept on one physical line). Keep the pair on one line, or strip the
  quote markers before folding.
- [2026-09-17 builder] The generated entrypoint block is a DOUBLE-QUOTED `_block="…"` string, so
  any `$sdd-*` token added to it is command-expanded before it is written; under `set -u` the
  installer aborts mid-run with `sdd: unbound variable` (no `FAIL:` line, just a broken install).
  Escape the dollar (`\$sdd-plan`), exactly as the surrounding backticks are escaped (E28-F01
  round 8, finding 4042015445). A host-neutral pointer edit therefore needs a green single-host
  install before any test run — R8c alone would have caught it, but only after the banner tests.
- [2026-09-17 reviewer] A per-surface anchor list that omits the very anchors a role-only test
  checks lets a semantic divergence survive on the executable surface: E28-F02's R8 asserted
  five tokens on the emitted `/sdd-plan` body + both source-mode artifacts but not
  `specs/adr/`, `ADR-` or the allocation phrase, even though the plan's content contract said
  those "must appear in `agents/planner.md` AND the emitted `/sdd-plan` body" — so
  `.harness/spects/adr/…` (M24) and a dropped allocation clause (M2b) stayed green while the
  role kept them, and R8's own residual claimed it "catches a missing/renamed rule on a
  surface". When a spec says N surfaces carry "the same step", assert the FULL pinned-anchor
  set on every surface, not a convenient subset; and a two-clause attribution joined by `;`
  plus `amend` matching `amends` let R10's "a topology change is a `/sdd-plan` amend" clause be
  deleted outright (M23) with the suite green — assert the re-plan clause as its own phrase.
- [2026-09-17 builder] Fixing that R8 hole, adding the three anchors to the whole-span
  `require_tokens` list did **not** kill the Reviewer's own M2b/M24 mutants: the emitted body
  carries `specs/adr/`/`ADR-`/the allocation phrase in the EARLIER generic architecture-ADR
  step too, so a topology-step-only rename/drop is still satisfied elsewhere in the span.
  Adding a token to a whole-span check is not the same as pinning the STEP: bound it to the
  sentence/step that carries the rule (`every_naming_sentence_carries … "more than one
  deployable" …`) and prove the kill by replaying the exact mutant. Replaying the Reviewer's
  byte-for-byte mutants against the fixed suite is the cheapest way to catch that a
  "required fix" is itself subsumed (`scratchpad/E28-F02-builder/mut.py`, all three RED,
  both no-op controls green).
- [2026-09-17 reviewer] A mutation runner that restores with `shutil.copyfile(path, bak)` + `shutil.move(bak, path)` silently drops the exec bit: `copyfile` creates the backup at 0644 and `move` puts that mode back, so a 755 script comes back 644 while `diff -q` on content reports "restored". On E28-F02 round 2 this turned the scratch clone's `harness-install.sh` non-executable and the next `./harness-install.sh --self` exited 126 — a mode-only delta invisible to a content diff. Verify the restore with `diff -qr`/`stat`, not just `diff -q`, or restore with `cp -p`/`shutil.copy2`; and never run a post-campaign probe that executes a file a mutation touched without first re-checking its mode.
- [2026-09-18 builder] A helper whose OUTPUT the flow never consumes cannot be pinned by
  mutating it: E28-F03's promotion seed step wrote `"./$key"` as a literal beside
  `promotion_rebase_path`, so the R3 mutant (`print ../<key>`) survived a green
  `test_paths_rebased_to_umbrella_root` until the seed step was rewired to consume the
  helper. Before trusting a contract test on a helper, grep the flow for the helper's NAME
  — if the value is reconstructed at the call site, the helper is decoration and the test
  proves nothing about it.
- [2026-09-18 reviewer] A fail-closed negative fixture that can be satisfied by a DIFFERENT guard is not discriminating: E28-F03's R1 "target holds no existing install" test put the draft OUTSIDE the target, so deleting the `.harness-version` refusal still aborted at the path-resolution gate and stayed green. Place the fixture so only the guard under test can produce the refusal (draft inside `<target>/.harness/` with `path: ../<key>`), and assert the refusal NAMES the target — rc≠0 alone is not the requirement.
- [2026-09-18 reviewer] A carried-field assertion is vacuous when the fixture value equals the code default: E28-F03's R3 draft used `init: ./init.sh` and `delegate_cmd: ""`, identical to the defaults, so deleting either field from the seeded block left all 50 suites green. Use a distinctive value per field and assert each field the contract enumerates (same family as "count the assertions, not the authorities").
- [2026-09-18 reviewer] A per-clause guard can be unpinned while a combined mutant is killed: deleting only the `^[a-z0-9-]+$` key-grammar arm survived all suites because the fixture (`api-v2`/`../api.v2`) is caught by the basename≠key arm. Mutation-test each ARM of a compound guard separately; the combined deletion certifies only the stronger arm.
- [2026-09-18 builder] Point `TMPDIR` OUTSIDE any git work tree for a test run: `tests/test_promote.sh`'s R9 non-git fixture (`build_single_nogit`) proves the coordinator reports `no git` via `git -C <fixture> rev-parse --is-inside-work-tree`, which walks ANCESTORS — a `TMPDIR` under the harness repo makes the fixture a work tree, reds that assertion, and turns a no-op mutation control into a phantom kill (it cost a discarded campaign here). Run with a neutral disk-backed `TMPDIR` (`/var/tmp/...`), read `df` before and after, and have the runner refuse a `TMPDIR` where that probe succeeds.
- [2026-09-18 reviewer] A supplementary mutant can read SURVIVED because the suite was never the one under mutation: `tools/run-tests.sh` resolves its DEFAULT glob against its own root, but an explicit RELATIVE suite argument is executed verbatim against the CALLER's cwd (`"$run" "$suite"`, run-tests.sh:384), so `sh <clone>/tools/run-tests.sh tests/x.sh` run from another directory tests THAT directory's suite and installer (its `SRC` is `dirname $0/..` of the cwd-resolved path). Pass ABSOLUTE suite paths, or run with cwd at the repo under test; the runner's own "works from any cwd" comment (run-tests.sh:116) is true only for the no-argument case.
- [2026-09-18 builder] A negative gate test can KILL its mutant while still naming the wrong
  guarantee: the first draft of E28-F03's symlink regression asserted `rc != 0` before the
  external-write check, and the unfixed run reached the landing audit (`rc=3`), so the mutant
  red at a secondary wording assertion instead of "promotion wrote outside the umbrella".
  In a flow with more than one non-zero exit (gate `1` vs audit `3`), assert the REAL symptom
  first and pin the gate's own exit code distinct from the other, or the suite's failure
  message will misdirect the next maintainer to a cosmetic mismatch.
- [2026-09-18 builder] `[ -e "$p" ]` FOLLOWS a symlink, so a DANGLING symlink reads as
  "missing" — a fail-before-write pre-pass that only tests `-e` accepts it, and the apply
  phase then `mkdir`s over the link AFTER an earlier missing child has already been created
  and `git init`-ed, yielding a partial promotion (E28-F03 finding 4045131033). Test the
  link explicitly (`-L`, true even when `-e` is false) in the pre-pass. `-L` does not
  replace the physical `cd`/`pwd -P` parent check: keep them as separate guards in separate
  places (resolve owns symlink-to-OUTSIDE, existing-child owns dangling and inside) so each
  mutant has its own assertion that reds.
- [2026-09-18 builder] `opencode debug config` truncates its JSON at exactly 64 KiB when
  stdout is a PIPE and silently drops everything past that — including the `command`
  section (the resolved `/sdd-*` commands). Capture such CLI output through a FILE
  (`stdout=open(tmp,'w')`), never `subprocess.PIPE`; the R9 live probe failed on a
  complete config until this was fixed.
- [2026-09-18 builder] Running the OpenCode CLI with cwd inside the harness source repo
  installs its runtime deps into the tracked `.opencode/` (`package.json`,
  `package-lock.json`, `node_modules/`, plus a generated `.opencode/.gitignore`). A live
  "does OpenCode resolve the source glue?" probe MUST run against an isolated COPY of the
  source layout (opencode.json + AGENTS.md + `.opencode/` + `agents/`), or the test dirties
  the very working tree it is asserting on — and those artifacts must never be committed
  as glue.
- [2026-09-18 builder] A generic prefix-strip transform (`s|prefix/||g`) that is correct for
  POINTER paths leaves an EMPTY root when it strips PROSE that named the prefix as its base
  ("resolve paths against `<prefix>/`"): the source shim then resolves against nothing, which
  is worse than the installed form. The bug is a positive ABSENCE, so a "no surviving prefix"
  assertion (E31-F02 R7's original `opencode_glue_source_layout`) stays green on it. Rewrite
  the prose to an explicit root BEFORE the strip, and pin both halves — a two-token positive
  anchor (`mentions … repository root`) plus a no-empty-inline-code-span negative with a
  planted positive control (E31-F02 finding 4045793773; `test_self_mode.sh::
  opencode_pr_fixer_root_explicit`, `test_source_shims.sh`).
- [2026-09-18 builder] A length floor on an extract-and-compare test fires **before** the
  byte comparison, so a mutant that layers a real one-sided desync on top of a truncation
  reports TRUNCATION, not the desync — the desync is unreachable below the point extraction
  stopped. Don't promise "the mutant names the desync" for that layered shape; the floor
  names the root cause it is there to catch, and the truncation and `cmp` messages must stay
  textually distinct so the two failures are never conflated (E99-F162 MF2/MG/ML).
- [2026-09-18 builder] A "structural minimum" floor for a comment-heavy block is the
  physical line of its LAST REQUIRED key, which can coincide with the block's final line
  (workers: `roster:` = 19 = today's length). That is a contract, not a snapshot — a line
  added after the key never moves it — so verify the distinguishing mutant instead of the
  number: a symmetric blank AFTER the top-level key truncates both copies to 18 lines, and
  only a floor above 18 sees it; a floor chosen one below the last required key to *look*
  "not exact" silently misses that shape (E99-F162 MW).
- [2026-09-18 reviewer] A per-block length floor must be the block's last **content** line,
  not its last required **key**, whenever later lines are still inside the compared span:
  E99-F162's models floor 18 = `doc-critic:` while the models block runs to 35 lines of
  escape-hatch documentation, so a symmetric blank after `doc-critic:` truncates both copies
  to 18, clears the floor, and a one-sided desync in the 17-line tail passes (MTAIL green;
  floor 35 kills it). Workers got the shape right (19 = `roster:` = the block's final line);
  apply the same rule to every extract-and-compare block.
- [2026-09-18 builder] Fixing that finding, a "next top-level key" END bound was NOT a clean
  substitute for the first-blank bound on the models block: the `harness.config.yaml` copy is
  followed by a 20-line `# Codex PR review loop …` comment header before `pr_loop:`, while the
  install-side heredoc stops at its `EOF` before that header — so the two bounds capture
  different spans for a reason the test never intends to compare. When a block's tail is a
  fixed documentation run with no next-key signal at matching offsets, floor at the last
  CONTENT line (models 35; workers 19) instead of re-bounding; prove it with a symmetric
  blank AFTER the last required key (MTAIL), which must red with "TRUNCATED", and a one-sided
  tail desync (MTAILD), which must red via `cmp` at `35c35`.
- [2026-09-18 builder] A length floor is a lower bound on DEPTH, not proof the extractor reached
  the block's END: a line appended past the floor's last content line GROWS the compared span
  while the floor keeps passing, so a one-sided desync in the new tail compares equal (E99-F162
  finding 4046240133 — the constant-floor shape Codex rejected). Pair every extract-and-compare
  floor with an END MARKER: assert the capture's LAST line IS the block's structural last content
  line, and that marker occurs exactly ONCE in its source (`grep -cF == 1`), so a future append
  reds and forces the maintainer to advance it. A desync that touches the marker line now reds at
  the END MARKER rather than via `cmp`; pin a separate non-marker tail desync if the `cmp`
  diagnostic is the contract. Pin BOTH new claims with neutered-guard controls — marker neutered
  + append-past-marker must go GREEN (`control-marker.py` A), uniqueness neutered + duplicated
  marker must go GREEN (`control-unique.py`) — or the guard is decoration beside a check that
  already covers it.
- [2026-09-18 builder] Replacing a first-blank block bound with a "next column-0 line" bound
  has two traps (E99-F162 finding 4046384380): (1) the block's own top-level key must be
  identified by KEY grammar (`^[A-Za-z0-9_.-]+:`), not by "first column-0 line after the
  anchor" — the workers block's own comment header is *also* column-0, so that rule ends the
  capture on the header; (2) do NOT also strip trailing comment-only lines to reconcile an
  asymmetric next-block header — that drops the block's own `# pin…` documentation and
  reopens E99-F160 M8/M8b. Stop at the next block's column-0 header (exclude it by the BOUND)
  and trim only trailing blanks; the pin comments stay in the compared span. A structural
  bound that reaches the mapping boundary makes a constant length floor redundant — retire it
  rather than leave an unpinned constant, and prove the bound with a pre-fix old-test control
  (the finding's mutant is GREEN on the old bound, RED on the new one).
- [2026-09-18 builder] Superseding the previous entry's "stop at the next block's column-0
  header": that header test must require the line be **NON-COMMENT** (`/^[^[:space:]#]/`),
  because a column-0 comment does NOT end a YAML mapping. With any-column-0 it, appending
  `# extra model documentation` then an indented `pin.claude.frontier` to one copy stops the
  capture AT the comment, so both extracts stay byte-identical while the config reader walks
  through the comment and reads the child (E99-F162 finding 4046520085; the pre-fix test was
  GREEN on it). Pair the byte `cmp` with a SEMANTIC `key=value` comparison (comment-only and
  blank lines dropped, matching `_cfg_models_value`) but keep BOTH: each is uniquely
  load-bearing — byte owns the block's comment-byte identity (E99-F160 MC/MD), semantic owns
  reader-visible keys; only the next block's trailing column-0 comment header is trimmed, so
  indented `# pin…` comment appends still red (E99-F162 round-5 controls).
- [2026-09-18 builder] Widening a comparison is a TWO-SITE change: the comparison and the
  GATE that decides whether the artifact recording it is written at all. E99-F163 widened
  `escalation_verdict` to model+effort but `write_escalation_arming` gated artifact creation
  on `models_any`, which still read only `resolve_model` — so a codex effort-only target had
  its widened `raise` reclaimed as "nothing configured". Mutate the gate separately from the
  comparison; deleting just the `models_any` effort arm gives an empty verdict line, not a
  wrong verdict.
- [2026-09-18 builder] The E99 brief-only fix lane ships WITHOUT a VERSION/CHANGELOG bump even
  when it edits `harness-install.sh` / `harness.config.yaml` / `docs/` — E99-F159 and E99-F161
  did exactly that at 0.79.0 — and the brief's file list omits both. A bump here is not free:
  `tests/test_self_mode.sh` R11 asserts the NEWEST CHANGELOG entry mentions OpenCode, which
  only E31-F02's 0.84.0 entry does, so any later release reds it until R11 is re-anchored on
  E31-F02's version instead of the current one. Check the lane's precedent before bumping, and
  if a bump is required, grep the CURRENT VERSION literal (`test_codex_native.sh:279`) AND the
  newest-entry-coupled suites.
- [2026-09-18 reviewer] Widening a contract's semantics must sweep the GENERATED operator-facing
  docs, not just the sites the brief enumerates. E99-F163 updated the seed block and the two named
  docs but left the `.harness/manifest.txt` heredoc (`harness-install.sh:4252-4262`) saying `armed`
  means "change the model, computed from resolve_model" — now false, shipped to every target, and
  unpinned by any test. Also stale: the reclaim `info` line (`:4743`), `docs/INSTALL.md:867-873`,
  and `docs/WORKFLOW.md:811/837`. Before approving a semantics change, grep every surface that
  NAMES the artifact (`escalation-arming`, the verdict words) and each doc's EARLIER sections, not
  only the section the diff touched.
- [2026-09-18 reviewer] The same sweep must also cover the EMITTED ROLE DESCRIPTIONS, which name no
  artifact: `harness-install.sh` writes `builder-heavy`'s description ("differs only by the model
  it resolves to") into every target's agent shim, and after E99-F163 a codex effort-only pair
  differs by `model_reasoning_effort` alone — stale, shipped, and pinned by no test (E99-F163 N4).
  When a verdict's axes move, grep the `emit_agent` strings alongside the docs.
- [2026-09-18 builder] `git ls-files -s` reads the INDEX, so a bare `chmod -x` on a tracked
  script leaves it reporting `100755` — a source-mode check built on the tracked mode ALONE
  stays green on the exact E99-F161 reproduction. Assert BOTH the tracked mode (the committed
  contract) and the worktree `[ -x ]` bit (what `./script` needs), and kill each arm with its
  own mutant: bare `chmod -x` for the worktree arm, `git update-index --chmod=-x` for the
  tracked arm. (E99-F164)
- [2026-09-18 builder] A per-file executable-bit check rots the moment a script is added;
  derive the required set by RULE (every tracked `*.sh` with a shebang outside `tests/`) so a
  new script is covered on commit, and add a fail-closed canary list of the `./`-documented
  entrypoints so widening the exemption to drop one reds naming it. Prove the guard by
  mutating the exemption, not by reading it. (E99-F164)
- [2026-09-18 builder] A list-membership guard where every element is space-delimited must be
  mutated on the FIRST element too: `sed 's# token##'` silently no-ops there because the first
  token has no leading space (`_sse_expected="first …`), so the suite runs unmutated, stays
  green, and reads as a SURVIVOR. Anchor the deletion on the delimiter (`s#="first #="#`) or
  require the applied diff to be non-empty before recording any result — the "print the applied
  diff" rule is what turns this void run back into a kill. (E99-F164 F2b)
- [2026-09-25 reviewer] On a host where `python3` is a **mise shim**, two suites fail or hang for host reasons: `test_umbrella.sh`'s `exec "$REALPY" -S` wrapper loops forever (the shim re-resolves `python3` to the wrapper, giving `python3 -S -S -S …`), and `test_pr_loop.sh` R53's symlink-mirror PATH makes init report "python3 lacks fcntl". Re-run those suites with the real interpreter dir first on PATH (`~/.local/share/mise/installs/python/<v>/bin`) before blaming the branch. Also, the session scratchpad under `/tmp` may be tmpfs (RAM-backed), so under memory pressure put TMPDIR on disk (`/var/tmp/<feature>-<role>/`). (E32-F01)
- [2026-09-25 reviewer] When a feature widens a presence check, the SAME pattern usually appears at more than one site (here the migrate_config append guard AND install_one's before-probe for the notice). Mutate EACH site on its own. A fixture that pins only the file-content side (no duplicate block) leaves the stdout side (no spurious notice) unpinned. (E32-F01 M4)
- [2026-09-25 builder] A newly authored test suite must also satisfy OTHER suites' repo-wide conventions, not just its own R-ids: `tests/test_feedback_config.sh`'s `_section` heading-slicer (added in round 1) violated `tests/test_change_size.sh` R9d (every heading slicer must call the shared `fence_delim()` from `tests/lib/fence.awk`) from the moment it was created, and this was real and 100% reproducible standalone (`sh tests/test_change_size.sh`) — not a host artifact. The round-1 Reviewer's full-suite run somehow reported it green regardless (50/51 passed, a different suite named as the one failure); do not trust one green full-suite run as proof a new test file is convention-clean — grep the new file for the cross-suite pattern (`/^#+ /` or `/^## /` heading resets with no `fence_delim(` call) yourself, or run the specific convention-enforcing suite (here `test_change_size.sh`) standalone right after authoring any new markdown-slicing test helper. (E32-F01 round 2)
- [2026-09-25 reviewer] Correction to the builder line above: the round-1 green on `test_change_size.sh` R9d was ACCURATE for the check as written. R9d's per-slicer scan pairs single quotes file-wide (`re.finditer(r"'([^']*)'", src)`), so an odd apostrophe anywhere earlier in a suite hides every later awk program from it. At de207c5 the non-fence `_section` was invisible to it (green). Round 2's comment "the operator's opt-out" flipped the parity and exposed it (red). At HEAD it is invisible again: deleting the `fence_delim($0)` call stays green (M17). Lesson: a structural scan's green is only evidence if a mutant of the thing it scans goes red. Before you cite a repo-wide check as the enforcer of a new file's convention, mutate that file and watch the check go red. (E32-F01 round 2 F3)
- [2026-09-25 builder] `${2:-default}` treats an EXPLICIT empty argument as unset, so a fixture-helper call like `make_fixture true '' …` meant to exercise "an empty value resolves to the code default" silently WROTE the default into the fixture config instead — and a mutation that changed the code's own `DEFAULT_REPO` survived. When an empty argument is meaningful, use `${2-default}` (no colon), and prove it by mutating the default constant: only the no-colon form reds. (E32-F02)
- [2026-09-25 builder] An installed target has NO `VERSION` file: `harness-install.sh` writes the version stamp to `.harness/.harness-version` and `HARNESS_BODY_LOCAL` does not include `VERSION`. Any tool that must report "the harness version" at runtime has to resolve `$H/VERSION` (source layout) with a `.harness-version` fallback (installed layout); a spec sentence saying "the resolved VERSION" should be read as the governing harness's version, or every installed report fails the semver guard and silently downgrades to a local copy. (E32-F02)
- [2026-09-25 reviewer] An allow-list arm that checks **presence at a project-writable path** is not ownership, and a "shipped" qualifier in the spec/plan/comment is a guarantee to MUTATE, not to read. E32-F02 F1: `_valid_command`'s `sdd-*` arm accepted any `sdd-<secret>` file under the project's `.agents/skills/` or `.claude/commands/`, so a project-specific string rode upstream in `Command:` while the tool comment claimed it "must resolve to something the installed body ships". Probe the arm by planting a project-authored unit and asserting it rejects; if the design truly intends presence-at-path, amend the claim instead — never leave "cannot ride" beside a path-existence check. (E32-F02)
- [2026-09-25 reviewer] A spec R-id can have a passing test and still be unpinned at one of its clauses: E32-F02 R11 says "any `gh` call fails ⇒ local copy only", but no test set `SH_LIST_RC`, so deleting the `gh issue list` → `_finish fallback gh-list` branch left all 52 suites green. A `SH_*` control that `use_fx` unsets and the runner defaults but no case ever sets is the signature of a dropped fallback case — grep every such control for an actual assignment, and mutate each call site of the guarantee separately. (E32-F02 F2)
- [2026-09-25 reviewer] A `printf '%s' "$v" | grep -qE '^[A-Za-z0-9._-]+$'` charset guard is **line-based**: `grep` matches per line, so a value embedding `\n` passes as soon as ANY one line is a bare token. E32-F02 round 2 F5: `--command` = `sneaky\nharness-feedback:evil` sailed through once a newline-named file existed under `.harness/tools/`, emitting a SECOND body marker token (`creates=1`, `grep -c 'harness-feedback:'`=2) while round 1 had reported F5 closed by rejecting only the single-line colon form. Validate whole-string with POSIX `case "$v" in ''|*[!CLASS]*) return 1 ;; esac` (glob classes match a newline), and plant the embedded-newline fixture — a line-oriented grep is not a token validator, and a "must be a bare basename" comment beside one is an over-claim. (E32-F02 F5 round 2)
- [2026-09-25 reviewer] A canary fixture proves "the body is not executed" only for the lines the interpreter actually reaches. E32-F04 R7's named mutation was "pipe the body into `sh -c`", but the injection fixture's first line is the valid marker `<!-- … -->`, which is itself a shell **syntax error**: `sh -c "$(cat body)"` aborts at line 1 and never runs the canary line, so the mutant survives a suite that claims to pin non-execution. Construct the fixture so the interpreter would have to reach a canary: put shell-parseable command text on the **first** line (the forged case already has no valid marker, so its line 1 can be `` `touch "$CANARY"` ``), and keep the `${{ }}`-shaped text on a later line. A mutant that reaches the injection lines (`sed -n '2,$p' | sh -c`) does red — which is exactly why "the canary arm is live" is not the same claim as "the named mutation is killed": mutate the whole body, not just the part you know is dangerous. (E32-F04 F1)
- [2026-09-25 reviewer] `tests/test_umbrella.sh` self-recurses when the first `python3` on `PATH` is the mise shim: line 187 `REALPY="$(command -v python3)"` captures the shim, line 188 writes `$BIN/python3` = `exec "$REALPY" -S "$@"`, and line 190's `PATH="$BIN:$PATH" python3 ...` re-enters the wrapper — the shim re-resolves `python3` back to `$BIN/python3` and appends `-S` forever (`/bin/sh $BIN/python3 -S -S -S ...`, 100% CPU, never terminates, no summary printed). A whole `tools/run-tests.sh` run hangs silently on the default developer `PATH`; a stale instance was seen at 06:59:43 elapsed. Resolve the real interpreter before prepending `$BIN` (or run with the managed interpreter dir first on `PATH`) so `$REALPY` cannot be the wrapper, and treat a missing `run-tests.sh` summary as a host hang, not a mass failure. (E32-F04 round 2)
- [2026-09-25 reviewer] `test_self_drift.sh`'s "regenerated == committed" arm is blind to a hand-edited file in `.claude/commands/` (and `.claude/agents/`): `--self` deliberately LEAVES an edited file "unchanged and unclaimed" and the fixture inherits `.claude/` (it only purges `.codex/agents`, `.agents/skills` and opencode), so the diff compares the hand edit to itself. Only the hardcoded `_must` manifest list catches it — which means a NEW committed `.claude/commands/*.md` that is not added to `_must` is unguarded. E32-F03 added `.claude/commands/sdd-report.md`, appended `STALE HAND EDIT` to it, and the full 54-suite run stayed green (the same edit to `.agents/skills/sdd-report/SKILL.md` or `.opencode/command/sdd-report.md` reds, because those dirs ARE purged). Lesson: when a feature adds a committed glue file under a dir the drift fixture inherits, mutate that exact file against the FULL suite; "a hand-edited `.claude/*` reds `test_self_drift.sh`" is an over-claim until the file is in `_must`. (E32-F03)
- [2026-09-25 reviewer] The round-1 E32-F03 lesson ("a NEW committed `.claude/commands/*.md` not added to `_must` is unguarded") understates it: `test_self_drift.sh`'s ledger is a SPOT-CHECK, not a completeness check — it lists 2 of 8 committed `.claude/commands/*.md` (`sdd-next.md`, `sdd-report.md`) and 1 of 8 `.claude/agents/*.md` (`builder.md`; `scout.md` only incidentally via R3). A committed stale hand edit to any unlisted unit survives `test_self_drift.sh` AND the full 54-suite run (M8 `.claude/commands/sdd-new.md`, M9 `sdd-plan.md`, M16 `.claude/agents/reviewer.md`, all green), because the fixture inherits those dirs and `--self` leaves an edited file "unchanged and unclaimed". The round-2 fix then added a comment asserting "Every committed command unit must therefore be listed here" — an over-claim (3c) that hides exactly this fail-open. Lesson: when a hand-editable class is named in a gate comment, audit the class's completeness, not just the newly added member; and never write "every X must be listed" above a list you have not made exhaustive. (E32-F03 round 2)
