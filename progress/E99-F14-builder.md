# E99-F14 — build record

`sdd: false` (quick-fix lane), so there is no four-file spec. This file carries what the
`.tests.md` contract would otherwise hold: the test contract, the anti-tautology argument
and the mutation ledger.

## What the brief got wrong, and how it was found

The brief named **two** divergences (`E17-F02`, `E17-F03`). A full sweep of the board
against disk found **26**, in three classes the brief did not distinguish:

| swept | found | why the first count was wrong |
|---|---|---|
| feature `.spec.md` status vs board | **20** | the first sweep matched `<ID>.spec.md` and missed 18 directories that predate that convention and use `<slug>.spec.md` |
| `epic.md` status vs board | **6** | the first sweep reported **19** — 13 were false, because every `epic.md` writes `status: done   # draft → planned → …` and the comparison was against the trailing YAML comment |
| `spec_path` that does not resolve | **16, all legitimate** | 13 are `sdd: false` (no Architect ever ran) and 3 are `sdd: true` still at `pending` (not authored yet) |

That third row is the one that decided the design: a naive "`spec_path` must resolve" rule
would have fail-stopped `init.sh` on 16 entries that are all correct.

## Test contract — `tests/test_board_spec_consistency.sh`

| R-id | claim |
|---|---|
| R1 | a dangling `spec_path` on an `sdd` feature past `pending` fails, naming id and path |
| R2 | a directory that exists but holds no `*.spec.md` fails — readability, not `stat` |
| R3 | `sdd: false` needs no spec; flipping **only** `sdd` to true fires |
| R4 | `pending` needs no spec; advancing **only** the status fires |
| R5 | a status disagreement names the file **and both values** |
| R6 | a legacy `<slug>.spec.md` is checked — the match is `*.spec.md` |
| R7 | inline YAML comments are stripped; a real mismatch behind one still fires |
| R8 | an undeclared status is a skip; declaring a wrong one fires |
| R9 | `epic.md` is held to the same contract |
| R10 | epic directories resolve only when unique, and `E1` never matches `E10-*` |
| R11 | the pass is opt-in — omitting `--spec-root` restores prior behaviour exactly |
| R12 | **`init.sh` is wired to it**: green on a consistent tree, fail-stop when one spec disagrees |
| R13 | schema errors stay primary and suppress the spec pass |
| R14 | quoted frontmatter values compare by their contents |
| R15 | the live board agrees with the live specs, **and a mutated copy of it fails** |
| R16 | a `draft` epic is exempt from the existence rule **only** — disagreement still fires |
| R17 | a `spec_path` naming a file reports as unresolved, not as an empty spec directory |

## Anti-tautology

`init.sh` is a MANDATORY gate: a false positive halts every agent in the repo. So a rule
that is supposed to stay **silent** is the dangerous kind to assert, because silence is
also what a broken check produces. Every silent-path R-id is therefore paired with a
control that differs in **exactly one variable** and does fire:

| silent claim | control that fires |
|---|---|
| R3 `sdd: false` is exempt | the same board with **only** `sdd: true` |
| R4 `pending` is exempt | the same board with **only** `status: spec-ready` |
| R7 comments are stripped | the same comment, genuinely different value |
| R8 no `status` key is a skip | the same file with **only** a `status:` line added |
| R10 ambiguous epic dir is skipped | one of the two directories removed |
| R11 opt-in | the same board **with** `--spec-root`, which fails |
| R16 draft epics are exempt | the same board with **only** `draft` → `planned` |

**R15 is the one assertion that could be tautological**: "the live board is consistent"
passes trivially against a validator that never reports anything. It is paired with R15b,
which mutates a *copy* of the real board (a `done` `sdd` feature flipped to `in-review`,
leaving its spec declaring `done`) and requires the same invocation to fail.

R12 checks `init.sh`'s own exit status on a fixture harness rather than grepping `init.sh`
for `--spec-root`. Grepping the source proves the flag is written, not that the gate acts
on it — the site, not the outcome.

## Mutation ledger — 18 applied, **18 killed, 0 survived**

Every mutation was confirmed applied (`git diff --quiet` on the target) **and** confirmed
to still compile (`py_compile` / `sh -n`) before its result was believed: a no-op patch
reads as a kill, and so does a syntax error.

| # | mutation | result |
|---|---|---|
| M01 | drop the `draft` epic exemption | killed (R16) |
| M02 | drop the `pending` exemption | killed (R4) |
| M03 | `sdd is True` → `sdd is not None` | killed (R3) |
| M04 | glob `*.spec.md` → `[A-Z]*.spec.md` | killed (R6) |
| M05 | stop stripping inline YAML comments | killed (R7) |
| M06 | compare even when no status is declared | killed (R8) |
| M07 | drop the "directory holds no spec" error | killed (R2) |
| M08 | default `--spec-root` to the cwd | killed (R11) |
| M09 | report spec errors alongside schema errors | killed (R13) |
| M10 | epic glob `%s-*` → `%s*` | killed (R10) |
| M11 | accept an ambiguous epic directory (`== 1` → `>= 1`) | killed (R10) |
| M12 | stop checking `epic.md` at all | killed (R9) |
| M13 | stop unwrapping quoted frontmatter values | killed (R14) |
| M14 | report the frontmatter value twice instead of the board value | killed (R5) |
| M15 | drop the "spec_path does not exist" error | killed (R1) |
| M16 | remove `--spec-root .` from `init.sh` | killed (R12) |
| M17 | iterate no epics at all | killed (R15) |
| M18 | `isdir` → `exists` | **survived at first**, then killed by R17 |

**M18 is worth recording rather than quietly re-counting.** It survived the original
16-case contract because it is verdict-equivalent: a `spec_path` naming a regular file
fails either way, just with a different message ("a directory holding no spec" instead of
"does not exist"). The response was **not** to call it equivalent and move on — at a
mandatory gate the operator acts on the message, so the message is part of the contract.
R17 pins it. No production change was needed: the shipped code already emitted the correct
diagnostic, and the mutation was uncovering a missing assertion, not a defect.

## Deliberately not done

An epic whose board status and `epic.md` **agree** but are both stale relative to their
features. `E17` reads `pending` while four of its five features are `done`. This feature
verifies **agreement between the two records**; it does not audit the rollup that produced
them. `E06` was the reverse and *was* fixed, because the two records genuinely disagreed —
and there the **board** was the stale one, so the board was rolled rather than the document
regressed.
