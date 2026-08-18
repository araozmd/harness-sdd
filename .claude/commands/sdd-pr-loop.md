---
description: Drive the Codex review cycle on an open PR — trigger @codex review, watch in the background, classify severities, fix blocking findings, merge when every gate is green
---

Drive the Codex review cycle on an open PR until every gate is green or the round cap is
hit. This is the harness **source-layout** copy: paths resolve from the repository root
(an installed consumer gets the same body with everything resolved against `.harness/`).

The PR number is in `$ARGUMENTS`. If `$ARGUMENTS` is empty, resolve the current branch's
PR with `gh pr view --json number --jq '.number'`; if that fails, STOP and ask which PR.

> **Preconditions.** This loop only works on a repository with the **Codex GitHub App**
> installed, an **authed `gh`**, and **`jq`** on PATH. Step 0 verifies all of them and
> fails fast with a named remedy — never post first and discover it later.

## Configuration

Policy lives in `harness.config.yaml` under `pr_loop:`. Precedence for every
knob is **env override → config value → built-in default**; an absent block or an absent
key behaves exactly as the default.

| Config key | Env override | Default |
|---|---|---|
| `pr_loop.enabled` | `HARNESS_PR_LOOP_ENABLED` | `false` (opt-in) |
| `pr_loop.auto_merge` | `HARNESS_AUTO_MERGE` | `true` |
| `pr_loop.max_rounds` | `HARNESS_MAX_ROUNDS` | `4` |
| `pr_loop.blocking_severities` | `HARNESS_BLOCKING_SEVERITIES` | `P0,P1` |
| `pr_loop.merge_strategy` | `HARNESS_MERGE_STRATEGY` | `merge` |

`pr_loop.enabled` is the **opt-in** master gate: this command is only installed at all
because it reads exactly `true`. Anything else — an absent block, an absent key, an empty
or malformed value — means off, and the installer stamps no `/sdd-pr-loop` glue.

Execution knobs are **env-only** (never config): `HARNESS_POLL_INTERVAL` (60),
`HARNESS_POLL_CEILING` (900), `HARNESS_FIRST_RESPONSE` (180), `HARNESS_DRY_RUN`.

Round cache: `.pr-loop/<pr>/round-<n>/` — gitignored and best-effort; if it is
missing or corrupt, reconstruct it from the `gh` API.

## Per-round runbook

Use a `while` loop so the round counter can be restarted. `round_dir=.pr-loop/<pr>/round-<round>`;
`max_rounds` is read from `pr_loop.max_rounds` (default 4).

`max_rounds` is a budget for the **PR**, not for one invocation of this command. Resume the
counter from the highest round already in the cache, so re-running `/sdd-pr-loop` cannot
silently grant a fresh budget — PR #86 reached round 12 against `max_rounds: 4` exactly that
way, and the `needs-human` hand-off that should have fired at round 4 never did. The
base-change restart below moves the stale rounds to `stale-<ts>/`, so it correctly
re-derives round 1 on its own.

```bash
round=1
for _d in .pr-loop/$pr_number/round-*/; do
  [ -d "$_d" ] || continue                       # unmatched glob — no cache yet
  _n="${_d%/}"; _n="${_n##*/round-}"
  case "$_n" in ''|*[!0-9]*) continue ;; esac
  [ "$_n" -ge "$round" ] && round=$((_n + 1))
done
while [ "$round" -le "$max_rounds" ]; do
  round_dir=".pr-loop/$pr_number/round-$round"
  mkdir -p "$round_dir"
```

### 0. Preflight — BEFORE posting anything

```bash
sh tools/wait-for-codex.sh preflight "$pr_number"
```

It checks `gh` on PATH, `gh auth status`, `jq` on PATH, a resolvable repo slug, and that
the PR exists and is OPEN. It posts **nothing**. On a non-zero exit (`5`), **STOP** and
report its one-line diagnostic verbatim — do not post `@codex review`, do not poll, do
not fall back to a hand-rolled check. A repo without the Codex GitHub App should leave
`pr_loop.enabled` at its opt-in default of `false` rather than run this loop.

### 0b. Base-change detection (stacked PRs only)

On round 2+, before triggering a new Codex review, check whether the base branch has
changed since the last round — when a stacked PR's parent is rebased (review fixes), the
child's `baseRefOid` moves, and the child must be re-reviewed from scratch (R5).

```bash
# Only stacked PRs (base != default branch) get base-change detection. A PR targeting the
# default branch naturally sees baseRefOid move as other PRs merge; restarting review on
# every such change would destroy the ordinary single-PR lane.
default_branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo '')"
# Fetch the current baseRefName fresh — a stacked child may have been retargeted before
# the first review round, and round 1 must validate stack ancestry too.
base_ref="$(gh pr view "$pr_number" --json baseRefName --jq '.baseRefName' 2>/dev/null || echo '')"
if [ -n "$default_branch" ] && [ -n "$base_ref" ] && [ "$base_ref" != "$default_branch" ]; then
  prior_round_dir=".pr-loop/$pr_number/round-$(( round - 1 ))"
  prior_base_name="$(jq -r '.baseRefName // ""' "$prior_round_dir/pr.json" 2>/dev/null || echo '')"
  prior_base_oid="$(jq -r '.baseRefOid // ""' "$prior_round_dir/pr.json" 2>/dev/null || echo '')"
  if [ -n "$prior_base_name" ] && [ "$prior_base_name" != "$default_branch" ] && [ -n "$prior_base_oid" ]; then
    current_base_oid="$(gh pr view "$pr_number" --json baseRefOid --jq '.baseRefOid' 2>/dev/null || echo '')"
    # Fail closed on either side of the comparison being unreadable — a missing
    # prior cache or a transient API failure must not silently bypass the detection.
    if [ -z "$current_base_oid" ]; then
      echo "base-change detection: could not read current baseRefOid — restarting from round 1" >&2
      stale_dir=".pr-loop/$pr_number/stale-$(date -u +%s)"
      mkdir -p "$stale_dir"
      for d in .pr-loop/$pr_number/round-*/; do
        [ -d "$d" ] && mv "$d" "$stale_dir/"
      done
      round=1
      continue
    elif [ "$current_base_oid" != "$prior_base_oid" ]; then
      echo "baseRefOid changed (${prior_base_oid:0:7} -> ${current_base_oid:0:7}) — parent rebased" >&2
      # Verify the child has actually been restacked onto the new parent tip before
      # restarting review. An unrestacked child would be reviewed with superseded parent
      # commits in its diff. The restack procedure is in docs/WORKFLOW.md.
      head_ref_oid="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid' 2>/dev/null || echo '')"
      # Fail closed when the head OID is unreadable — an empty head OID must not bypass
      # the ancestry check, because an unrestacked child could then be reviewed with
      # superseded parent commits and merged after its parent lands.
      if [ -z "$head_ref_oid" ]; then
        echo "base-change detection: could not read headRefOid — refusing to restart review" >&2
        gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
        return 1
      fi
      if command -v git >/dev/null 2>&1; then
        # Fetch the refs before checking ancestry — in a fresh or shallow clone, or
        # after a force-push, the OIDs from GitHub may not exist locally and
        # `git merge-base` would exit 128 (error) instead of 1 (non-ancestor).
        git fetch origin --no-tags --depth=50 2>/dev/null || true
        if ! git merge-base --is-ancestor "$current_base_oid" "$head_ref_oid" 2>/dev/null; then
          echo "child has not been restacked onto the new parent tip — restack before restarting review" >&2
          echo "See docs/WORKFLOW.md 'Restack procedure'" >&2
          # Archive the cache and pause, not restart. The child needs a manual rebase.
          stale_dir=".pr-loop/$pr_number/stale-$(date -u +%s)"
          mkdir -p "$stale_dir"
          for d in .pr-loop/$pr_number/round-*/; do
            [ -d "$d" ] && mv "$d" "$stale_dir/"
          done
          # Do not continue the loop — the child needs human intervention to restack.
          # Set needs-human and exit.
          gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
          return 1
        fi
      fi
      echo "parent rebased; discarding prior round cache, restarting from round 1" >&2
      # Move the stale round directories out of the active cache path so stall/trend
      # evaluation cannot accidentally consume them. The handover summary still reports
      # their existence, but the active round-1 starts fresh.
      stale_dir=".pr-loop/$pr_number/stale-$(date -u +%s)"
      mkdir -p "$stale_dir"
      for d in .pr-loop/$pr_number/round-*/; do
        [ -d "$d" ] && mv "$d" "$stale_dir/"
      done
      round=1
      continue
    fi
  fi
fi
```

If the base changed, discard prior round-cache data for merge-gate evaluation and restart
the round counter from 1. This detection activates only when the PR's `baseRefName` is
not the default branch — a PR targeting `main` has `baseRefOid` that tracks the default
branch's head, which changes on every merge anyway, so the check is inert there.

### 1. Trigger the review

Resolve the repo slug once (the `gh api` calls below need it):

```bash
slug=$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"')
owner=${slug%% *}; repo=${slug##* }
```

- **Round 1:** mark the PR ready for review (`gh pr ready <pr>`), then comment `@codex review`.
- **Round 2+:** comment `@codex review` again to request a re-review of the new commits.

**Capture the triggering comment's id straight from the post response.** Step 2 uses it
both to poll reactions (the 👍-only clean case) and as the **freshness anchor**
(`trigger-ts.txt`, the `created_at >= trigger` filter). Derive it from the URL
`gh pr comment` prints, **never from a separate comment-list call**: a non-paginated
`GET issues/<n>/comments` returns only the first 30 (oldest) comments, so on a busy PR
the just-posted `@codex review` is on a later page and the lookup returns a stale id or
`null` — which silently disables the freshness filter.

```bash
trigger_url=$(gh pr comment "$pr_number" --body "@codex review")   # this IS the round's trigger post
trigger_comment_id="${trigger_url##*issuecomment-}"                # .../pull/N#issuecomment-<id>
```

(The "comment `@codex review`" step and this capture are a single action — do not post twice.)

If `HARNESS_DRY_RUN=1`, **skip the real `gh pr comment` post** entirely and synthesize
stub review data in `$round_dir` for downstream testing.

### 2. Poll for the review (background watcher)

Wait for a Codex review to land on the latest commit. **Do not poll by hand.** A by-hand
poll is why landed Codex comments get missed: in an interactive session you fetch the
review state once, see nothing yet, and the turn ends — so a review that lands minutes
later goes unnoticed until a human nudges "review again". Foreground `sleep` is also
blocked in this harness, so an inline "sleep 30; check; repeat" cannot run either.

Instead, launch the harness watcher **in the background** and let the harness wake you
when it exits:

```bash
# Claude Code: Bash tool with run_in_background: true. Elsewhere: `… &` or the host's
# equivalent. It keeps polling across turns and re-invokes you on exit.
sh tools/wait-for-codex.sh "$pr_number" "$trigger_comment_id" "$round_dir"
```

The watcher polls every `HARNESS_POLL_INTERVAL` seconds (default **60**) up to
`HARNESS_POLL_CEILING` (default **900** = 15 min) and writes the **four sources** into
`$round_dir` on every poll (`gh pr view` alone does NOT return Codex's findings):

- `pr.json` — `gh pr view --json reviews,comments,statusCheckRollup,headRefOid`
- `review-comments.json` — `repos/<o>/<r>/pulls/<n>/comments`, paginated + flattened —
  **the inline findings**, anchored to file/line. Returned by neither `--json comments`
  (issue comments only) nor `reviews[*].body` (summary banner only).
- `issue-comments.json` — `repos/<o>/<r>/issues/<n>/comments`, paginated, scanned for a
  clean banner posted past the first 100 comments.
- `reactions.json` — reactions on the `@codex review` comment (Codex reacts 👍 when it
  has nothing to say).
- `trigger-ts.txt` — the freshness anchor, resolved once at startup.

When the watcher exits, the harness re-invokes you. **Record its exit code as the round's
`outcome` (step 2b) and then branch on it** — never re-poll by hand:

| Exit | Meaning | Next |
|---|---|---|
| `0` | Review **with findings** landed on the head commit | Step 3, classify `review-comments.json` |
| `3` | **Clean review, 0 findings** (head banner as a review **or** an issue comment, or a 👍 reaction) | Skip classification; treat the round as zero blocking |
| `2` | **Timeout** — ceiling hit, no resolution | Abort the round with `needs-human`. Never treat a timeout as "clean". |
| `4` | Usage / precondition error (incl. an unresolvable trigger timestamp) | Fix the args and relaunch; do not disable the freshness filter |
| `5` | No Codex activity inside `HARNESS_FIRST_RESPONSE` (default 180s) | Report the diagnostic: the Codex GitHub App is most likely not installed. Do NOT wait out the ceiling. |

The exit codes encode the freshness conditions the watcher checks: (1) Codex-bot inline
comments filed against `headRefOid` **and created at/after the trigger comment** →
findings; (2) a summary banner containing `Reviewed commit: <short headRefOid>` with zero
head findings → clean; (2b) that same head banner delivered as an **issue comment** →
clean; (3) a Codex-bot 👍 (`+1`) on the trigger comment → clean.

**Two freshness pitfalls the watcher guards against** (both previously stalled clean PRs):

- **Re-anchored stale threads.** GitHub re-stamps old unresolved threads' `commit_id` to
  each new head, so a stale thread's `commit_id` matches `headRefOid` even though it
  predates this round. An inline comment counts only when `created_at >= trigger.created_at`.
- **Clean banner as an issue comment.** Codex's zero-findings result ("Didn't find any
  major issues." + `Reviewed commit: <head>`) posts to `.comments[]`, which conditions
  1/2 never scan.

**Codex bot identity.** Accept **exactly two** author logins and nothing else:
`chatgpt-codex-connector` (what `gh pr view` / GraphQL reports) and
`chatgpt-codex-connector[bot]` (what the REST API reports). Never prefix-match: any account
whose login merely *begins* with the bot name (`chatgpt-codex-connector-evil`) could then
👍 the trigger comment or post a `Reviewed commit: <head>` banner and be read as a clean
Codex review — zero findings, no classification, auto-merge. The two literals cover the
GraphQL/REST spelling split completely.

> **No background tool available?** The watcher still runs in the foreground and exits
> with the same codes — it just blocks until resolution or ceiling.

### 2b. Record the round's OUTCOME — at every terminal state, including the aborts

The moment the watcher exits, write **one word** to `$round_dir/outcome`. Do it on **every**
path out of step 2, including the ones that abort the round without classifying anything.

```bash
case "$watcher_rc" in
  0)   echo findings   > "$round_dir/outcome" ;;   # review landed WITH findings
  3)   echo clean      > "$round_dir/outcome" ;;   # review landed, zero findings
  2|5) echo timeout    > "$round_dir/outcome" ;;   # ceiling hit / no Codex activity at all
  *)   echo unresolved > "$round_dir/outcome" ;;   # usage / precondition error (exit 4)
esac
```

Write `unresolved` on the two **later** aborts that never reach a classification either: the
unreadable-`headRefOid` path in step 3 (`head_ok=0`) and a `pr-gate.sh` `unresolved` verdict
(exit `9`). Every round in the cache ends with exactly one of `findings`, `clean`, `timeout`,
`unresolved` on disk.

**Why a file for something the length of `blocking.json` seemed to imply.** It did not imply
it. "Reviewed, nothing blocked" and "no review ever landed" are both `[]`, byte for byte.
Measured on araozmd/harness-sdd#141: the rounds went 2 blocking → round 2 **watcher timeout**
(exit `2`, zero Codex activity) → 2 blocking, the timed-out round was recorded as `[]`, and
`pr-round-trend.sh` answered *"converging — the finding rate is coming down. One more round is
rational."* Deleting that one file changed the verdict. The flat 2,2 was the honest signal and
the tool never saw it — so the bias ran toward "spend another round" exactly when review was
**not landing**, and recording a timeout as a clean round was silently rewarded.

**Do NOT "solve" that by omitting `blocking.json` on a timeout.** Then *absent* means two
things as well ("timed out" and "aborted before classifying"), and the trend would answer
`insufficient` — quietly hiding a run that is failing to get reviewed at all. **A timeout is
information: it is recorded, and it is reported.** `tools/pr-round-trend.sh` keeps `timeout`
and `unresolved` rounds out of the finding **rate** and prints them in their own block.

### 3. Parse and classify comments

Walk **`review-comments.json` (the inline findings)** + `pr.json` `reviews[*].body` +
`issue-comments.json` looking for severity tags. Codex tags severity as a **badge image**,
not bare text — e.g. `![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)`.
Match `P0|P1|P2|nit` **case-insensitively anywhere in the body** (this catches both the
badge alt-text/URL form and any bare-text form); **first match wins**; **default to `P2`**
when nothing matches.

**Only FRESH inline comments count for this round** — the same freshness guard the watcher
applies (see step 2). An inline comment counts only when it is filed against the head
commit **and** its `created_at >= trigger.created_at`; otherwise a stale thread GitHub
re-anchored to head slips back into `blocking.json` and defeats the guard. The watcher
persists the anchor to `trigger-ts.txt`; apply it when reading the unfiltered
`review-comments.json`:

**A head oid you could not read is not a head oid.** A `pr.json` that is missing or
truncated makes `jq` exit non-zero with empty output; a `pr.json` that parses but carries
no `headRefOid` makes `jq -r` print `null` and exit **0**. Either way `$head` is not the
head commit, every comment fails `commit_id == $h`, and `fresh-comments.json` — hence
`blocking.json` — comes out `[]`, which step 6 reads as "zero blocking findings ⇒ all
gates green ⇒ merge". So guard the **value** as well as the exit status and fail closed:
an unreadable head aborts the round as `needs-human`, it is not a clean round. (`since`
needs no such guard — an empty `since` disables the freshness filter and admits *more*
findings, which errs toward review rather than toward the merge.)

```bash
since=$(cat "$round_dir/trigger-ts.txt" 2>/dev/null)  # empty ⇒ filter off ⇒ admits MORE
head_ok=0            # fail closed: only a head oid we actually READ may filter findings
if ! head=$(jq -r '.headRefOid // ""' "$round_dir/pr.json") || [ -z "$head" ]; then
  # Head oid UNKNOWN: pr.json missing, truncated, or without a headRefOid. Filtering on ""
  # would match nothing and hand the gate an empty blocking.json. Testing the status on the
  # `if` itself reads the same whether or not the host shell runs with `set -e`, and
  # `[ -z "$head" ]` catches the absent/null key that `jq -r` reports with exit status 0.
  rm -f "$round_dir/fresh-comments.json"   # never leave a previous round's file standing
  echo "could not read headRefOid from pr.json — needs-human, not merging" >&2
else
  head_ok=1          # the filter below is anchored to a head oid that was really read
  jq --arg h "$head" --arg since "$since" '
    [ .[] | select((.commit_id // "") == $h)
          | select($since == "" or ((.created_at // "") >= $since)) ]' \
    "$round_dir/review-comments.json" > "$round_dir/fresh-comments.json"
fi
# classify severities from fresh-comments.json (not the raw review-comments.json)
```

With `head_ok=0` there is no `fresh-comments.json` to classify and therefore no
`blocking.json` and no `acted.json`: write `echo unresolved > "$round_dir/outcome"` and take
the `needs-human` terminal state of step 5's cap row (label, hand over, return failure). Only
`head_ok=1` with an empty `blocking.json` means "zero fresh blocking findings".

To re-check the round files offline at any point (no `gh`, no network), run
`sh tools/wait-for-codex.sh evaluate "$round_dir"` — exit `0` findings,
`3` clean, `1` pending, applying exactly the rules above.

Then filter to the **blocking severities only**. The set is whatever
`pr_loop.blocking_severities` lists — **read it, do not assume it**. The shipped default is
`P0,P1`, but a repo may raise it (a harness that ships *gates* has good reason to: there, a
finding tagged P2 can still mean the gate vouching for something it never checked). Whatever
is NOT in that list is non-blocking for this repo; `nit` is not in any default. Save into the
round dir:

```
comments.json     # all comments with a severity tag attached
blocking.json     # filtered to the CONFIGURED blocking severities — the MERGE GATE reads this
status.json       # statusCheckRollup snapshot
```

**Do NOT write `acted.json` here.** The round's acted-on set is recorded at **dispatch**, in
step 5, and this step must not pre-compute it. Classification answers "what did the
configuration block?"; that answer is `blocking.json` and it is complete. Whether any finding
is *acted on* is not known yet — the gate has not been asked, and its answer can be `merge`,
in which case the round acts on nothing at all. A set written here would record **intent**,
and the round can contradict it two steps later. `acted.json` has to mean *these findings
were acted on* or it is not an honest input to a convergence rate.

### 4. Stall detection

Compare `blocking.json` to the **previous round**'s (`round-<n-1>/blocking.json`) by
comment id (or, if ids are unstable, by `(path, line, severity, body-hash)`). If **any**
blocking comment id appears in both rounds, the fixes are not landing: **escalate to the
`max_rounds - 1` behavior immediately**, even if the current round is 1 or 2.

### 4b. Convergence trend — is the review converging, or just resampling? (E21-F03)

Stall detection above catches the *same* finding surviving a fix. This catches the other
failure: *different* findings arriving at a steady rate, round after round, because the diff
is larger than one review pass can cover.

```bash
# Pass the diff width when it is measurable — see "which remedy" below. Both flags are
# optional; without them the tool keeps its default (split) remedy.
_cs="$(sh tools/change-size.sh --format json 2>/dev/null || echo '{}')"
_df="$(printf '%s' "$_cs" | jq -r '.total_files // empty' 2>/dev/null || true)"
_dl="$(printf '%s' "$_cs" | jq -r '.total_lines // empty' 2>/dev/null || true)"
sh "$HARNESS_DIR/tools/pr-round-trend.sh" --cache ".pr-loop/$pr_number" \
   ${_df:+--diff-files "$_df"} ${_dl:+--diff-lines "$_dl"}
```

It reads only `round-*/outcome`, `round-*/acted.json` and `round-*/blocking.json` — files
this loop already writes — no `gh`, no network, no new state. It reports the per-round count,
a verdict, the rounds that were never reviewed, and where the findings concentrate:

| verdict | meaning | what it implies |
|---|---|---|
| `converging` | the rate is coming down | one more round is rational |
| `non-converging` | the last 3 **reviewed** rounds each produced a blocking finding | more rounds will not help — see the remedy it prints |
| `insufficient` | fewer than 3 **reviewed** rounds with a readable count | no conclusion yet |

**Only rounds that were actually reviewed enter the rate.** A round whose `outcome` is
`timeout` or `unresolved` is neither counted nor dropped: it is printed in its own
`NEVER REVIEWED` block (and `not_reviewed[]` under `--format json`). Read that block first —
a PR that is failing to get reviewed does not need another round, it needs the watcher or the
Codex App fixed. A round with **no** `outcome` on disk (a cache written before this file
existed) is named under `unrecorded_rounds[]`: it is still counted so an old cache still
trends, but its verdict is flagged as possibly optimistic rather than quietly trusted.

**Severity overrides show up as overrides.** The count comes from `acted.json`, so a P2 you
judged blocking is in the rate — and the report says how many of the findings were overrides
and at which severity. The merge gate is unaffected: it still reads `blocking.json`.

**This round's `acted.json` does not exist yet.** It is written at dispatch, in step 5, which
has not run — so the trend sees earlier rounds through what they *acted on* and the current
round through its `blocking.json`. That is the right reading here (nothing has been acted on
yet), and it means the verdict at this point is final for every earlier round and provisional
for this one. **Re-run the trend when you build the handover summary**, after the round has
disposed of its findings; that later verdict is the one that goes into a terminal message.

A flat rate does not mean the fixes are bad. It means the reviewer is sampling a surface
larger than one pass can cover, so another round buys another *sample*, not more confidence —
and a clean round would be indistinguishable from one that happened to land somewhere quiet.
On the PR that motivated this (17,202 additions, twelve rounds), the rate never decayed:
`1 3 1 2 1 3 1 2 2 1 2 1`. Rounds 5–12 cost roughly 2M input tokens and 8 hours to keep
rediscovering that the diff was too big.

**Which remedy a non-converging verdict prints.** "Split this PR" is right for a 17,202-line
diff and unfollowable on a small one — and unfollowable advice teaches operators to ignore the
tool. When the caller supplies `--diff-files` **and** every finding sits in a single file, the
tool says so and recommends changing the region's shape instead of splitting. Without
`--diff-files` it cannot know how wide the diff is, so it keeps the split remedy. (viernes-web
PR #85: 2 files, ~150 lines, all four findings in one function, `SPLIT THIS PR` — the operator
overrode it by hand and wrote the reasoning into the handover.)

This is **advisory and it never blocks**: the tool exits 0 at every verdict, it does not
change when the cap fires, and it never merges or fails a PR on its own. Carry the verdict
into the handover summary, and — at the cap — into the `needs-human` message.

### 5. Branch on round

**Ask the gate FIRST — before branching on the budget.** The verdict already folds the
round budget in, so the table below is a rendering of the gate's answer, not a second
opinion beside it:

```bash
sh tools/pr-gate.sh evaluate "$round_dir" --round "$round" --max-rounds "$max_rounds"
gate_rc=$?
```

**The gate's verdict is binding, and it is asked exactly ONCE per round.** `merge` (0) means
the review is finished: leave this step entirely, **break the loop before advancing the round
counter**, and go to step 6 then "ready to merge". Breaking preserves the successful `round`
value, so the Ready-to-merge section reads `round-$round/pr.json` from the correct round.
(The one thing that may follow a `merge` verdict without merging is an explicit, recorded
**override** — see "When you judge the badge wrong" below. It does not change what the gate
said, only what this round does about one finding, and it is never taken silently.)
`fix` (6), `escalate` (7) and `needs-human` (8) select the rows below. `unresolved` (9) — no
Codex review landed for this round — and unreadable input (4) both take the `needs-human`
terminal state **after `echo unresolved > "$round_dir/outcome"`**; never read an empty
`blocking.json` as clean.

The gate answers the budget question from `blocking.json` alone when findings remain, and
proves a review actually landed (via `wait-for-codex.sh evaluate`) only when the blocking set
is empty — because an empty set means two opposite things, "reviewed, nothing blocking" and
"no review landed", and only the first may merge.

**Do not fix non-blocking findings to make the PR look clean.** `blocking.json` is already
filtered to `pr_loop.blocking_severities`; whatever that key omits is excluded **by
configuration, not by oversight**. A non-blocking comment sitting on a PR the gate calls
`merge` is not unfinished work — it is work this loop was told not to do. If it deserves
attention it deserves its own PR, where it gets reviewed on its own diff instead of extending
a review that already converged.

**Which severities those are is a per-repo fact, so read the key.** Under the default `P0,P1`
this rule is about P2 and nit. In a repo that configures `P0,P1,P2` — as this one does — P2
findings **are** blocking and this paragraph does not apply to them; treating them as excluded
would silently defeat the configured threshold and could authorize a merge over real blocking
work.

That instruction exists because the loop stopped honouring it. On PR #89 every round reported zero
blocking findings and the loop still spent three rounds and three commits on P2s; on PR #86
rounds 6-8 were clean and it ran to round 12. Across this repo 20 of 43 Codex-fix commits
addressed P2s — roughly half the fix budget spent on findings that never blocked anything.

#### When you judge the badge wrong

`pr_loop.blocking_severities` is a **threshold**, and a threshold can be wrong about one
finding. On viernes-ai/viernes-web PR #85 a Codex **P2** was a live claim-steal race;
merging on the gate's word would have shipped it. That is not the paragraph above — you are
not making the PR look clean, you are answering a defect — and there are exactly **two**
honest moves. *Fix it quietly and say nothing* is neither, and it is what actually happened.

1. **Raise the threshold.** Add the severity to `pr_loop.blocking_severities` and re-run the
   round. The gate then blocks on its own authority and nothing is overridden. Prefer this
   whenever the repo will keep producing findings at that severity — a threshold you override
   every round is a threshold that is simply set wrong.
2. **Override this one finding.** Act on it despite the `merge` verdict, and record it with
   `acted_append … override` below. You are declining the gate's verdict **for this round's
   fix work only**: the gate is asked again next round with the same conservative filter, and
   `blocking.json` is never edited to dress an override up as configuration.

**Recording is not permission.** An `override` row does not authorize the work — it makes the
work *countable*. That is the entire point: three **unrecorded** overrides is how PR #85 spent
four rounds while `pr-round-trend.sh` reported *"no round with a readable blocking.json —
nothing to trend"*, and the one tool built to detect non-convergence stayed silent through a
textbook non-converging run. A non-zero `overrides:` line in that report is a question for the
configuration, not a licence to keep going.

Branching on the budget first is the ordering bug this replaces: at the cap round the
`max_rounds` row stopped with `needs-human` before anything consulted the findings, so a
**clean final round could never merge** — the loop handed a green PR to a human. Only a cap
round that still has blocking findings is a hand-over.

#### Record what this round acted on — at DISPATCH, never in advance

```bash
# acted_append <id> <path> <line> <severity> <configured|override>
#
# Call it at the MOMENT a finding is disposed of as blocking: immediately before handing it
# to a pr-fixer, before starting an in-session fix, or as the cap row lists it as a surviving
# blocking comment. One call, one row, one finding.
acted_append() {
  _a="$round_dir/acted.json"
  [ -s "$_a" ] || printf '[]\n' > "$_a"
  case "${5:-configured}" in override) _ov=true ;; *) _ov=false ;; esac
  jq --argjson id "$1" --arg p "$2" --argjson l "${3:-0}" --arg s "$4" --argjson o "$_ov" \
     '. + [{id:$id, path:$p, line:$l, severity:$s, override:$o}]' "$_a" > "$_a.tmp" \
    && mv "$_a.tmp" "$_a"
}
```

`acted.json` means **these findings were acted on**, and `tools/pr-round-trend.sh` uses it as
the round's finding count precisely because that is a claim about what happened rather than
about what a filter would have kept. So it is appended by the code paths that *do* the acting
— the three rows below and the in-session variant under them — and by nothing else. A round
that disposes of no finding writes no `acted.json`, and the trend reads its `blocking.json`
instead; a round that acted writes one row per finding, `override: true` on each one whose
severity `pr_loop.blocking_severities` excludes.

**A finding declared blocking is acted on whether or not it was fixed.** The cap row does not
fix anything, but naming a comment in the `needs-human` hand-over is this round's disposition
of it, and leaving those rows out would make the cap round read as a quiet zero — the trailing
zero that turns a flat series back into `converging` on exactly the report that exists to stop
that.

| Round | Behavior |
|---|---|
| below `max_rounds - 1` | For each blocking comment: **`acted_append` it first**, then spawn one **`pr-fixer`** sub-agent, passing it the PR number, comment id, file path, line and body. It commits one fix and writes `fix-<comment_id>.md` into the round dir. After all fixers return, `git push`. |
| `max_rounds - 1` | **`acted_append` every comment going into the prompt**, then build **one combined fix prompt** (all blocking comments concatenated) and escalate to a **different worker** if the host CLI offers one; where no router exists, run one combined **in-session** pass instead. Then push. |
| `max_rounds` (cap) | Stop the loop. `gh pr edit "$pr_number" --add-label needs-human`. **`acted_append` every blocking comment that survived** — the cap round disposes of them by declaring them, not by fixing them. Post the handover summary listing every round, the surviving comments, and the cache path — **and the trend verdict, re-run after these rows exist**. When it is `non-converging`, the message must say what the tool's remedy line says, and must show the per-round series and the concentration list that make the case. Return failure. |

At the default `max_rounds: 4` that is rounds 1–2 per-comment, round 3 combined
escalation, round 4 `needs-human`. A `max_rounds` below `3` simply has no per-comment
fixer rounds.

**Front-ends without a `pr-fixer` sub-agent** (codex, gemini) do not spawn one: apply each
blocking comment's fix **in-session**, under the same discipline — one `acted_append` call,
one comment, one targeted fix, one commit, one `fix-<comment_id>.md` note — then push once at
the end of the round. The absence of a sub-agent changes who writes the code; it does not
change what the round records about the work it did.

**Always write the worker file for this round** so the handover summary stays
reconstructible from cache:

```bash
echo "<worker>" > "$round_dir/worker"   # e.g. claude | opencode | agy | codex
echo "<role>"   > "$round_dir/role"     # implementation | fix | escalation
```

### 6. Re-check the gates

After the fix commits land, re-fetch the PR JSON and check the gates **before** triggering
another Codex round:

- CI green (`statusCheckRollup[*].conclusion == "SUCCESS"` for required checks)
- Tests / typecheck / lint green (subsets of CI)

**Do not ask the gate again.** It was asked once, at step 5, and its verdict is what routed
you here. `blocking.json` still holds THIS round's findings — the fixer commits do not rewrite
it — so a second call necessarily returns `fix`/`escalate` again and sends you back through
step 5 on the same stale set, forever. One round, one verdict.

What remains is to confirm the fix commits did not break anything, then **advance**: bump the
round counter and trigger a fresh `@codex review` (step 1). The new review is what produces
the next round's blocking set.

If checks are still pending, wait for them; if any fail, treat the failure like a blocking
comment for the next round.

#### Squash-merge prep (only when `merge_strategy` is `squash`)

**Compose the message locally — never ask Codex for it.** The watcher resolves on exactly
three signals (fresh inline findings on head, a fresh `Reviewed commit <sha>` banner as a
review or an issue comment, a `+1` reaction on the trigger comment), and a raw-text reply
to an `@codex summarize` request is none of them: polling for one runs to the ceiling,
exits `2`, and strands the squash path in `needs-human` with no `squash-message.txt` ever
written. Everything the message needs is already in the round cache, so write it yourself
— no post, no poll, nothing that can hang:

```bash
msg=".pr-loop/$pr_number/squash-message.txt"
default_branch=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
{
  gh pr view "$pr_number" --json title --jq '.title'
  echo
  echo "<2-4 lines, in your own words: the core implementation goal>"
  echo
  git log --reverse --format='- %s' "origin/$default_branch..HEAD"
  echo
  echo "Blocking fixes resolved:"
  for f in .pr-loop/"$pr_number"/round-*/fix-*.md; do
    [ -f "$f" ] && sed -n 's/^- One-line: //p' "$f"
  done
} > "$msg"
[ -s "$msg" ] || rm -f "$msg"   # empty ⇒ the merge below uses GitHub's default body
```

A missing or empty `$msg` is **not** a failure: the merge command below falls back to
GitHub's default squash body, so the squash path always reaches its merge.

### Round advance

After the per-round gates and fixes complete:

```bash
round=$(( round + 1 ))
done
```

A green round breaks **before** this increment — see step 6. The terminal states below
run with `round` pointing at the round that just verified, not one past it.

## Handover summary

Before posting **either** terminal-state comment, build the handover summary by walking
the cache:

```bash
for d in .pr-loop/"$pr_number"/round-*/; do
  n=$(basename "$d" | sed 's/round-//')
  worker=$(cat "$d/worker" 2>/dev/null || echo "?")
  role=$(cat "$d/role" 2>/dev/null || echo "?")
  echo "- round-$n: $worker ($role)"
done
for d in .pr-loop/"$pr_number"/round-*/; do cat "$d/worker" 2>/dev/null; done \
  | sort | uniq -c
```

**Re-run the trend here**, not just at step 4b. Every round has now disposed of its findings,
so every `acted.json` that is ever going to exist exists — including the current round's, which
step 4b could not see. The verdict that goes into either terminal message is this one:

```bash
sh "$HARNESS_DIR/tools/pr-round-trend.sh" --cache ".pr-loop/$pr_number" \
   ${_df:+--diff-files "$_df"} ${_dl:+--diff-lines "$_dl"}
```

Save the rendered summary to `.pr-loop/<pr>/handover-summary.md` and post it on
**both** terminal states.

## Terminal states

### Ready to merge (success)

Post a summary comment on the PR:

```
sdd-pr-loop: all gates green ✅

Handover summary:
- Rounds run: <n>
- Worker totals: <worker>=<count>, ...
- Round-by-round:
  • round-1: <worker> (fix x<count>)
  • ...
- Blocking comments resolved: <count>
- Cache: .pr-loop/<pr>/
```

**Resolve Codex threads first — never human ones.** A repo ruleset may require every
review thread resolved before merge, but this loop may only auto-resolve threads **it
owns** (opened by the Codex bot). Auto-resolving a human reviewer's unresolved
conversation would silently bypass the merge gate that keeps human feedback meaningful.
So: fetch each unresolved thread with its participants; if **any** non-Codex participant
appears on an unresolved thread, **stop and go to the needs-human terminal state — resolve
nothing and do not merge**. Only when every remaining unresolved thread is Codex-owned do
you resolve them (via the GraphQL `resolveReviewThread` mutation — there is no REST/`gh pr`
equivalent) and proceed.

**A thread you could not read in full is not Codex-owned.** `--paginate` walks the outer
`reviewThreads` connection, but each thread's nested `comments` connection is fetched
once and capped at 100 — a human reply at position 101 would be invisible and the thread
would look Codex-only, which is exactly the auto-merge-over-human-feedback hole this rule
exists to close. So compare each thread's `comments.totalCount` against the number of
authors actually returned and **fail closed**: a truncated thread is *not* provably
Codex-only and takes the same needs-human path as a human reply. (`totalCount` rather
than a nested `pageInfo`, because a second `pageInfo` in the same response is precisely
what `gh api --paginate` scans when it looks for the next cursor.)

**An enumeration you could not finish is not an empty enumeration.** If the thread query
itself fails — transient API error, expired auth, a pagination hiccup — `gh` exits non-zero
having printed nothing, and that empty output is byte-identical to "this PR has no
unresolved threads". No inspection of the output can tell the two apart, so check the
command's **exit status** and fail closed: a failed enumeration is a needs-human terminal
state that resolves nothing and merges nothing. Hence `merge_ok` starts at `0` and is
raised only on the branch that actually *proved* every unresolved thread Codex-owned.

**A resolve you could not complete is not a resolve.** The `resolveReviewThread` mutation
can fail on its own — a transient 5xx, a token without write access — and a thread that
stayed unresolved is exactly the review feedback the merge gate exists to protect. So
check **every** mutation's exit status and raise `merge_ok` only once they have **all**
succeeded; branch protection may or may not catch the leftover thread, and this loop must
not depend on it. Mind the shape of the loop while you do: `... | while read` runs its
body in a **subshell** in POSIX sh, so a failure recorded there dies at the `done` and is
silently forgotten. Feed the loop from a here-document instead and it runs in the current
shell, where the flag survives.

```bash
# Per unresolved thread emit "<allcodex> <id>", where <allcodex> is true only when the
# thread was read in FULL and EVERY participant is the Codex bot. A human reply on a
# Codex-opened thread makes it false — and so does a comment list longer than the 100
# fetched here, since an author you never read must never be assumed to be the bot.
# Both tests run in jq — no shell word-splitting. The two bot logins are inlined because
# `gh api --jq` takes no --arg, and are compared as EXACT literals: a prefix test would
# let `chatgpt-codex-connector-evil` pass as the thread's only participant, so the loop
# would resolve an impostor's thread and merge over it.
merge_ok=0            # fail closed: only a COMPLETED, clean enumeration may raise this
if ! unresolved=$(gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100,after:$endCursor){
          nodes{ id isResolved comments(first:100){ totalCount nodes{ author{ login } } } }
          pageInfo{ hasNextPage endCursor }
        }}}}' \
  -f owner="$owner" -f repo="$repo" -F pr="$pr_number" --paginate \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved | not)
        | (.comments.totalCount == (.comments.nodes | length)) as $whole
        | ([.comments.nodes[].author.login // ""]
             | all(. == "chatgpt-codex-connector"
                or . == "chatgpt-codex-connector[bot]")) as $codex
        | "\($whole and $codex) \(.id)"')
then
  # Enumeration FAILED: `unresolved` is empty because gh errored, not because the PR is
  # clean. Testing the status on the `if` itself (rather than after the assignment) reads
  # the same whether or not the host shell runs with `set -e`.
  echo "could not enumerate review threads — needs-human, not merging" >&2
elif printf '%s\n' "$unresolved" | grep -q '^false '; then
  echo "a thread is non-Codex or was not read in full — needs-human" >&2  # resolve NOTHING
else
  # Enumeration completed; every unresolved thread is provably Codex's — resolve them,
  # and raise `merge_ok` only if every mutation actually reported success. The loop reads
  # from a here-document rather than from `printf ... | while`, because a piped loop body
  # is a subshell: `resolve_ok=0` set in there would never reach this shell.
  resolve_ok=1
  while read -r _allcodex tid; do
    [ -z "$tid" ] && continue
    gh api graphql -f query='
      mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } } }' \
      -f id="$tid" >/dev/null || resolve_ok=0   # try the rest, but remember the failure
  done <<UNRESOLVED
$unresolved
UNRESOLVED
  if [ "$resolve_ok" = 1 ]; then
    merge_ok=1        # all requested threads resolved; nothing is left to merge over
  else
    echo "a Codex thread could not be resolved — needs-human, not merging" >&2
  fi
fi
```

**If `merge_ok=0`, stop here** — go straight to the needs-human terminal state and run
**none** of the merge commands below.

While `pr_loop.auto_merge` is **false**, stop after posting the all-gates-green summary
and hand back to the human — resolve threads if you like, but **do not merge**. That
hand-back **completes** the loop: **return success**. It is the one terminal state where an
unmerged PR is the intended outcome, so never route it to needs-human.

Where `pr_loop.auto_merge` is **true**, merge with the configured `merge_strategy`,
deleting the remote branch in the same call. **First, invoke the stacked-PR merge-order
guard (R2):** before `gh pr merge`, fetch the open-PR list and call the offline guard to
verify this PR is not stacked on an unmerged parent. On exit 6, refuse the merge and
enter the `needs-human` terminal state with the guard's diagnostic naming the parent PR.
The guard is called with JSON the pr-loop already fetches; the only additional network
call is a lightweight `gh pr list`.

```bash
# Stacked-PR merge-order guard (E21-F04 R2). Fail closed on every error: a guard that
# cannot prove safety must not authorize a merge.
default_branch="${default_branch:-$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo '')}"
guard_ok=1
guard_deferred=0
# Fetch the current baseRefName immediately before authorizing the merge — the PR may
# have been retargeted after the round cache was written, and a stale cached default-
# branch value would bypass the guard entirely for a newly stacked child.
if ! base_ref="$(gh pr view "$pr_number" --json baseRefName --jq '.baseRefName' 2>/dev/null)" || [ -z "$base_ref" ]; then
  guard_ok=0
  echo "sdd-pr-loop: merge refused — could not read current baseRefName" >&2
  gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
elif [ "$base_ref" = "$default_branch" ]; then
  : # targeting the default branch — not stacked, guard_ok stays 1
elif [ -n "$base_ref" ]; then
  open_prs_json=".pr-loop/$pr_number/open-prs.json"
  if ! gh pr list --state open --json number,headRefName --limit 1000 > "$open_prs_json" 2>/dev/null; then
    guard_ok=0
    echo "sdd-pr-loop: merge refused — could not fetch open PR list" >&2
    gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
  else
    # Refresh pr.json with the current base before evaluating the guard — a PR
    # retargeted after the round cache was written would otherwise be evaluated
    # with stale data.
    gh pr view "$pr_number" --json reviews,comments,statusCheckRollup,headRefOid,baseRefName,baseRefOid > ".pr-loop/$pr_number/round-$round/pr.json" 2>/dev/null || echo '{}' > ".pr-loop/$pr_number/round-$round/pr.json"
    guard_rc=0
    sh tools/pr-stack-guard.sh evaluate ".pr-loop/$pr_number/round-$round/pr.json" "$open_prs_json" --default-branch "$default_branch" || guard_rc=$?
    if [ "$guard_rc" = 0 ]; then
      : # guard_ok stays 1
    elif [ "$guard_rc" = 6 ]; then
      guard_ok=0
      guard_deferred=1
      echo "sdd-pr-loop: merge deferred — parent PR is still open (guard exit 6)" >&2
      sh tools/pr-stack-guard.sh evaluate ".pr-loop/$pr_number/round-$round/pr.json" "$open_prs_json" --default-branch "$default_branch" 2>&1 >&2
    else
      guard_ok=0
      echo "sdd-pr-loop: merge refused — stack guard returned exit $guard_rc" >&2
      sh tools/pr-stack-guard.sh evaluate ".pr-loop/$pr_number/round-$round/pr.json" "$open_prs_json" --default-branch "$default_branch" 2>&1 >&2
      gh pr edit "$pr_number" --add-label needs-human >/dev/null 2>&1 || true
    fi
  fi
fi
```

Track whether the merge command itself
**succeeded** (`merged`) — separate from `merge_ok`, which only recorded thread
eligibility — so cleanup never runs on a failed or pending merge:

```bash
merged=0
if [ "${guard_ok:-1}" != "1" ]; then
  if [ "${guard_deferred:-0}" = "1" ]; then
    # Exit 6 from pr-stack-guard.sh — parent is still open, which is a normal
    # waiting state in a healthy stack. Report it and exit gracefully without
    # needs-human; the child retries after the parent lands.
    echo "sdd-pr-loop: merge deferred — parent PR is still open" >&2
  else
    echo "merge-order guard refused — needs-human, not merging" >&2
  fi
elif [ "${merge_ok:-0}" != "1" ]; then
  echo "unresolved non-Codex threads remain — needs-human, not merging" >&2
elif [ "${merge_strategy:-merge}" = "squash" ]; then
  msg=".pr-loop/$pr_number/squash-message.txt"
  if [ -s "$msg" ]; then
    gh pr merge "$pr_number" --squash --delete-branch --body-file "$msg" && merged=1
  else                        # no message composed — squash with GitHub's default body
    gh pr merge "$pr_number" --squash --delete-branch && merged=1
  fi
else
  gh pr merge "$pr_number" --merge --delete-branch && merged=1
fi
```

`--delete-branch` removes the remote branch and the local tracking branch. Clean up any
lingering local branch **only if the merge command itself succeeded** (`merged=1`) —
never merely because thread eligibility was satisfied:

```bash
if [ "${merged:-0}" = "1" ]; then
  default_branch=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
  branch=$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')
  git checkout "$default_branch" >/dev/null 2>&1 || true
  git pull --ff-only >/dev/null 2>&1 || true
  git branch -D "$branch" 2>/dev/null || true          # local
  git remote prune origin >/dev/null 2>&1 || true      # drop the stale remote-tracking ref
fi
```

If `gh pr merge` fails (branch-protection race, a required review not yet registered, a
re-opened thread), retry once after 30s. If it still fails the PR will not land: take the
needs-human terminal state below — label `needs-human`, post the error alongside the
handover summary, and **return failure**. A merge that auto-merge was asked to land and did
not land is never reported as success.

### Needs-human (failure)

Apply the `needs-human` label, post the **same handover summary** block (so the human sees
exactly which workers tried and where they got stuck), and return failure. Reached by: the
`max_rounds` cap, a watcher timeout (exit `2`), an unresolved non-Codex thread, a
stacked-PR merge-order guard refusal (exit `6`), or a merge that would not land.

**Say what the human should conclude.** Include the step-4b trend output **verbatim,
including its `NEVER REVIEWED` block** — a cap reached because reviews kept timing out is a
completely different hand-over from a cap reached on a flat finding rate, and the human cannot
tell them apart from the round count. A `converging` verdict means the loop simply ran out of
rounds and resuming is reasonable. A `non-converging` verdict means more rounds will not help:
state plainly what the tool's remedy line says — **split** the PR when the findings spread
across files, or change the shape of the one region they all land in when they do not — show
the per-round series, and list the files the findings concentrate on. Without this, the
observed human response to the cap is to post
`@codex review` again — which on the PR that motivated this feature happened eight more
times, for roughly 2M input tokens and 8 hours, before anyone concluded the diff was too
large to review in one pass.

**Every path into this state returns failure**, whatever the reason — the only successes
are a merge that actually landed and the `auto_merge: false` hand-back above. So an
unmerged PR is a success **only** when auto-merge was off; when auto-merge was on and the
merge did not land, that is this state, and it is a failure.

## Cache layout

```
.pr-loop/<pr>/
  round-1/
    pr.json                   # reviews summary, issue comments, checks, head oid, base branch + oid
    review-comments.json      # the inline findings (source of truth)
    issue-comments.json       # paginated issue-comment stream (clean-banner scan)
    reactions.json            # reactions on the @codex trigger comment (👍 = clean)
    trigger-ts.txt            # freshness anchor
    outcome                   # ONE WORD: findings | clean | timeout | unresolved (step 2b)
    fresh-comments.json, comments.json, blocking.json, status.json
    acted.json                # appended at DISPATCH (step 5): one row per finding this round
                              # acted on, severity + override per row. Absent when the round
                              # acted on nothing.
    worker, role
    fix-<comment-id>.md       # one per fix
  round-2/ ...
  handover-summary.md
  squash-message.txt          # only when merge_strategy: squash
```
