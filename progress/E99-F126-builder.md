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

## Round 2 — Codex findings on PR #152

**P1 — `VERSION`.** Stamped **0.66.0** (MINOR: the `outcome`/`acted.json` cache files, the new
JSON fields, `--diff-files`/`--diff-lines`) with the matching `CHANGELOG.md` entry.

**P2 — the ordering, and it was right.** The first cut had step 3 pre-compute `acted.json`
from `blocking.json` at classification time and then "append an override row for every
finding you hand to a fixer". A *compliant* loop can never reach that append: the gate reads
the empty `blocking.json`, answers `merge`, and step 5 forbids fixing non-blocking findings.
So the override record could not be produced by a loop obeying its own rules, and F116 stayed
broken in practice while the runbook read as though it were fixed.

Fixed by moving the record to the **disposal** path and by making the override reachable:

- step 3 now says **do not write `acted.json` here**, and says why (the gate has not been
  asked; a set written here records *intent*, and the round can contradict it two steps later);
- a new `#### Record what this round acted on — at DISPATCH, never in advance` defines
  `acted_append <id> <path> <line> <severity> <configured|override>`, called at the moment a
  finding is disposed of as blocking;
- all three dispatch rows call it — per-comment fixer, combined escalation, and the **cap
  row**, because a finding *declared* blocking in the hand-over is acted on whether or not it
  was fixed. Without the cap row the last round reads as a quiet zero, which is precisely the
  trailing zero that flips a flat series back to `converging`;
- a new `#### When you judge the badge wrong` names the two honest moves — raise
  `pr_loop.blocking_severities`, or override this one finding **and record it** — and states
  that recording is not permission, it is what makes the work countable;
- step 4b now says this round's `acted.json` does not exist yet (it runs before dispatch), and
  the handover section **re-runs the trend** once every round has disposed of its findings.

Both runbook copies carry it; the drift check (normalise the `.harness/` paths, diff the two)
shows only the pre-existing deltas.
