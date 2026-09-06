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
