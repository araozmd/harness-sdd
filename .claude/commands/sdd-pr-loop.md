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

```bash
round=1
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
if [ "$round" -gt 1 ] && [ -n "$default_branch" ]; then
  prior_round_dir=".pr-loop/$pr_number/round-$(( round - 1 ))"
  prior_base_name="$(jq -r '.baseRefName // ""' "$prior_round_dir/pr.json" 2>/dev/null || echo '')"
  prior_base_oid="$(jq -r '.baseRefOid // ""' "$prior_round_dir/pr.json" 2>/dev/null || echo '')"
  if [ -n "$prior_base_name" ] && [ "$prior_base_name" != "$default_branch" ] && [ -n "$prior_base_oid" ]; then
    current_base_oid="$(gh pr view "$pr_number" --json baseRefOid --jq '.baseRefOid' 2>/dev/null || echo '')"
    if [ -n "$current_base_oid" ] && [ "$current_base_oid" != "$prior_base_oid" ]; then
      echo "baseRefOid changed (${prior_base_oid:0:7} -> ${current_base_oid:0:7}) — parent rebased; discarding prior round cache, restarting from round 1" >&2
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

When the watcher exits, the harness re-invokes you. **Branch on its exit code** — never
re-poll by hand:

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
`blocking.json`: take the `needs-human` terminal state of step 5's cap row (label, hand
over, return failure). Only `head_ok=1` with an empty `blocking.json` means "zero fresh
blocking findings".

To re-check the round files offline at any point (no `gh`, no network), run
`sh tools/wait-for-codex.sh evaluate "$round_dir"` — exit `0` findings,
`3` clean, `1` pending, applying exactly the rules above.

Then filter to the **blocking severities only** (`pr_loop.blocking_severities`, default
`P0,P1`; `P2`/`nit` never block). Save into the round dir:

```
comments.json     # all comments with a severity tag attached
blocking.json     # filtered to the blocking severities only
status.json       # statusCheckRollup snapshot
```

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
sh "$HARNESS_DIR/tools/pr-round-trend.sh" --cache ".pr-loop/$pr_number"
```

It reads only `round-*/blocking.json`, which this loop already writes — no `gh`, no network,
no new state. It reports the per-round blocking count, a verdict, and where the findings
concentrate:

| verdict | meaning | what it implies |
|---|---|---|
| `converging` | the rate is coming down | one more round is rational |
| `non-converging` | the last 3 rounds each produced a blocking finding | **split the PR — do not re-review it** |
| `insufficient` | fewer than 3 rounds with a readable `blocking.json` | no conclusion yet |

A flat rate does not mean the fixes are bad. It means the reviewer is sampling a surface
larger than one pass can cover, so another round buys another *sample*, not more confidence —
and a clean round would be indistinguishable from one that happened to land somewhere quiet.
On the PR that motivated this (17,202 additions, twelve rounds), the rate never decayed:
`1 3 1 2 1 3 1 2 2 1 2 1`. Rounds 5–12 cost roughly 2M input tokens and 8 hours to keep
rediscovering that the diff was too big.

This is **advisory and it never blocks**: the tool exits 0 at every verdict, it does not
change when the cap fires, and it never merges or fails a PR on its own. Carry the verdict
into the handover summary, and — at the cap — into the `needs-human` message.

### 5. Branch on round

| Round | Behavior |
|---|---|
| below `max_rounds - 1` | For each blocking comment, spawn one **`pr-fixer`** sub-agent, passing it the PR number, comment id, file path, line and body. It commits one fix and writes `fix-<comment_id>.md` into the round dir. After all fixers return, `git push`. |
| `max_rounds - 1` | Build **one combined fix prompt** (all blocking comments concatenated) and escalate to a **different worker** if the host CLI offers one; where no router exists, run one combined **in-session** pass instead. Then push. |
| `max_rounds` (cap) | Stop the loop. `gh pr edit "$pr_number" --add-label needs-human`. Post the handover summary listing every round, the blocking comments that survived, and the cache path — **and the step-4b trend verdict**. When it is `non-converging`, the message must say **split this PR**, not "re-review it", and must show the per-round series and the concentration list that make the case. Return failure. |

At the default `max_rounds: 4` that is rounds 1–2 per-comment, round 3 combined
escalation, round 4 `needs-human`. A `max_rounds` below `3` simply has no per-comment
fixer rounds.

**Front-ends without a `pr-fixer` sub-agent** (codex, gemini) do not spawn one: apply each
blocking comment's fix **in-session**, under the same discipline — one comment, one
targeted fix, one commit, one `fix-<comment_id>.md` note — then push once at the end of
the round.

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
- Zero unresolved blocking comments — i.e. `blocking.json` is empty

If all are green, **break the loop before advancing the round counter** and **proceed to
"ready to merge"** — do not waste another Codex round. Breaking preserves the successful
`round` value; the Ready-to-merge section then reads `round-$round/pr.json` from the
correct round, not from the advanced counter. If checks are still pending, wait for them;
if any fail, treat the failure like a blocking comment for the next round.

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
# Require a readable base. A missing or corrupt round cache that produces an empty
# base_ref must not silently authorize a merge — it is indistinguishable from
# "targeting the default branch", and that is exactly the path that would bypass
# the guard for a stacked child.
if ! base_ref="$(jq -r '.baseRefName // ""' ".pr-loop/$pr_number/round-$round/pr.json" 2>/dev/null)" || [ -z "$base_ref" ]; then
  guard_ok=0
  echo "sdd-pr-loop: merge refused — could not read baseRefName from round cache" >&2
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

**Say what the human should conclude.** Include the step-4b trend output. A `converging`
verdict means the loop simply ran out of rounds and resuming is reasonable. A
`non-converging` verdict means more rounds will not help: state plainly that the PR should
be **split**, show the per-round series, and list the files the findings concentrate on as
candidate seams. Without this, the observed human response to the cap is to post
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
    fresh-comments.json, comments.json, blocking.json, status.json
    worker, role
    fix-<comment-id>.md       # one per fix
  round-2/ ...
  handover-summary.md
  squash-message.txt          # only when merge_strategy: squash
```
