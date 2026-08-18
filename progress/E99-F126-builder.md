# E99-F126 + E99-F116 — builder (heavy tier)

Both items are one defect surface: `round-<n>/blocking.json` was the *only* thing
`tools/pr-round-trend.sh` read, and it answers neither question the trend asks.

## What changed

| File | Change |
|---|---|
| `tools/pr-round-trend.sh` | reads `round-<n>/outcome` + `round-<n>/acted.json`; only reviewed rounds enter the rate; timeouts reported in their own block; overrides counted and named; `--diff-files/--diff-lines` condition the remedy |
| `.claude/commands/sdd-pr-loop.md` | new step **2b** (write `outcome` at every terminal state); step 3 writes `acted.json`; step 4b passes the diff width; needs-human carries the NEVER REVIEWED block; cache layout updated |
| `harness-install.sh` | the same edits mirrored into the installed heredoc (`.harness/`-resolved) |
| `tests/test_pr_round_outcome.sh` | new suite, 8 cases, parses and runs under `/bin/dash` |

## The design call (requirement 3)

Took the board's option **(b)**, a second file, over (c) `fresh-comments.json` fallback.
`acted.json` carries one row per finding the round actually treated as blocking, with
`severity` **per row** and an `override` flag. `blocking.json` is untouched and
`tools/pr-gate.sh` still reads only it — whether a P2 may block a *merge* is a separate,
deliberately conservative decision from whether it counts as review *work*.
(c) alone cannot separate "reviewed, clean" from "reviewed, findings we chose not to block
on", so it reports a converged PR as non-converging.

## Backward compatibility (requirement 4)

Derivation order per round: recorded `outcome` → non-empty finding set ⇒ `findings` →
empty set with `pr.json` present ⇒ ask `wait-for-codex.sh evaluate` (the same offline probe
the merge gate uses) → otherwise `unknown`. An `unknown` round with a readable count is
still counted so a pre-existing cache keeps trending, but it is named in
`unrecorded_rounds[]` and the text says the verdict may be optimistic. It is never silently
clean.

## Verification

- `sh tools/run-tests.sh` → **all 43 suites passed**.
- F116 **replayed** from a copy of `viernes-web/.harness/.pr-loop/85` (four rounds, four
  P2s, all in one file): before ⇒ `converging` on `0 0 0 0` (or "nothing to trend" when the
  files are absent); after ⇒ **NON-CONVERGING from round 3**, 4 overrides at P2 named.
- F126 **constructed** (the #141 cache no longer exists on disk): 2 → watcher timeout → 2.
  Before ⇒ `converging`. After ⇒ rate `2,2` with the timeout reported, both from a recorded
  `outcome` and derived from a legacy cache with no `outcome` at all.
- 7 mutations, each killed with the real symptom: fold timeouts into the rate; drop them
  from the report; ignore `acted.json`; disable the legacy derivation; drop the unrecorded
  flag; force the split remedy; revert only the installer heredoc.
- Free disk before/after the mutation campaign: 442,715,232 KB → 442,712,968 KB.
- The `viernes-web` fixture was **not** modified (no file under it has today's mtime; its
  hand-written `blocking.json` files still hold 1 finding each).

## Not done, deliberately

`VERSION` is not bumped and `CHANGELOG.md` gets no entry — this touches the installed body,
so a bump is owed, but the release stamp was scoped out of this task. Whoever cuts the
release owes a **MINOR** (new backward-compatible capability) plus a `CHANGELOG` heading.
