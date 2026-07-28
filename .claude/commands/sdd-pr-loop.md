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
| `pr_loop.auto_merge` | `HARNESS_AUTO_MERGE` | `true` |
| `pr_loop.max_rounds` | `HARNESS_MAX_ROUNDS` | `4` |
| `pr_loop.blocking_severities` | `HARNESS_BLOCKING_SEVERITIES` | `P0,P1` |
| `pr_loop.merge_strategy` | `HARNESS_MERGE_STRATEGY` | `merge` |

Execution knobs are **env-only** (never config): `HARNESS_POLL_INTERVAL` (60),
`HARNESS_POLL_CEILING` (900), `HARNESS_FIRST_RESPONSE` (180), `HARNESS_DRY_RUN`.

Round cache: `.pr-loop/<pr>/round-<n>/` — gitignored and best-effort; if it is
missing or corrupt, reconstruct it from the `gh` API.

## Per-round runbook

For `round` from 1 to `max_rounds`, with `round_dir=.pr-loop/<pr>/round-<round>`:

### 0. Preflight — BEFORE posting anything

```bash
sh tools/wait-for-codex.sh preflight "$pr_number"
```

It checks `gh` on PATH, `gh auth status`, `jq` on PATH, a resolvable repo slug, and that
the PR exists and is OPEN. It posts **nothing**. On a non-zero exit (`5`), **STOP** and
report its one-line diagnostic verbatim — do not post `@codex review`, do not poll, do
not fall back to a hand-rolled check. A repo without the Codex GitHub App should set
`pr_loop.enabled: false` rather than run this loop.

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

**Codex bot identity.** Match the author login `chatgpt-codex-connector` by **prefix**,
with an optional `[bot]` suffix — `gh pr view` (GraphQL) reports
`chatgpt-codex-connector`, the REST API reports `chatgpt-codex-connector[bot]`. Never use
an exact literal.

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

```bash
since=$(cat "$round_dir/trigger-ts.txt" 2>/dev/null)
head=$(jq -r '.headRefOid' "$round_dir/pr.json")
jq --arg h "$head" --arg since "$since" '
  [ .[] | select((.commit_id // "") == $h)
        | select($since == "" or ((.created_at // "") >= $since)) ]' \
  "$round_dir/review-comments.json" > "$round_dir/fresh-comments.json"
# classify severities from fresh-comments.json (not the raw review-comments.json)
```

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

### 5. Branch on round

| Round | Behavior |
|---|---|
| below `max_rounds - 1` | For each blocking comment, spawn one **`pr-fixer`** sub-agent, passing it the PR number, comment id, file path, line and body. It commits one fix and writes `fix-<comment_id>.md` into the round dir. After all fixers return, `git push`. |
| `max_rounds - 1` | Build **one combined fix prompt** (all blocking comments concatenated) and escalate to a **different worker** if the host CLI offers one; where no router exists, run one combined **in-session** pass instead. Then push. |
| `max_rounds` (cap) | Stop the loop. `gh pr edit "$pr_number" --add-label needs-human`. Post the handover summary listing every round, the blocking comments that survived, and the cache path. Return failure. |

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

If all are green, **proceed to "ready to merge"** — do not waste another Codex round. If
checks are still pending, wait for them; if any fail, treat the failure like a blocking
comment for the next round.

#### Squash-merge prep (only when `merge_strategy` is `squash`)

Ask Codex for the commit message once, then save it:

```bash
gh pr comment "$pr_number" --body "@codex summarize: generate a high-signal squash commit message. Include the core implementation goal, which workers were used for which rounds, and a list of key blocking fixes resolved. Output raw text only."
```

Poll for that summary the same way (background watcher), then save it to
`.pr-loop/<pr>/squash-message.txt`.

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

```bash
# Per unresolved thread emit "<allcodex> <id>", where <allcodex> is true only when EVERY
# participant is the Codex bot (a human reply on a Codex-opened thread makes it false).
# The all-participants test runs in jq — no shell word-splitting. The bot login is inlined
# because `gh api --jq` takes no --arg.
unresolved=$(gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100,after:$endCursor){
          nodes{ id isResolved comments(first:100){ nodes{ author{ login } } } }
          pageInfo{ hasNextPage endCursor }
        }}}}' \
  -f owner="$owner" -f repo="$repo" -F pr="$pr_number" --paginate \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved | not)
        | "\(([.comments.nodes[].author.login // ""] | all(startswith("chatgpt-codex-connector")))) \(.id)"')

merge_ok=1
if printf '%s\n' "$unresolved" | grep -q '^false '; then
  merge_ok=0                                                 # → needs-human, resolve NOTHING
else
  printf '%s\n' "$unresolved" | while read -r _allcodex tid; do
    [ -z "$tid" ] && continue
    gh api graphql -f query='
      mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } } }' \
      -f id="$tid" >/dev/null
  done
fi
```

**If `merge_ok=0`, stop here** — go straight to the needs-human terminal state and run
**none** of the merge commands below.

While `pr_loop.auto_merge` is **false**, stop after posting the all-gates-green summary
and hand back to the human — resolve threads if you like, but **do not merge**.

Where `pr_loop.auto_merge` is **true**, merge with the configured `merge_strategy`,
deleting the remote branch in the same call. Track whether the merge command itself
**succeeded** (`merged`) — separate from `merge_ok`, which only recorded thread
eligibility — so cleanup never runs on a failed or pending merge:

```bash
merged=0
if [ "${merge_ok:-0}" != "1" ]; then
  echo "unresolved non-Codex threads remain — needs-human, not merging" >&2
elif [ "${merge_strategy:-merge}" = "squash" ]; then
  gh pr merge "$pr_number" --squash --delete-branch \
    --body-file ".pr-loop/$pr_number/squash-message.txt" && merged=1
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
re-opened thread), retry once after 30s. If it still fails, fall back to labeling
`needs-human` and posting the error. Return success to the caller.

### Needs-human (failure)

Apply the `needs-human` label, post the **same handover summary** block (so the human sees
exactly which workers tried and where they got stuck), and return failure. Reached by: the
`max_rounds` cap, a watcher timeout (exit `2`), an unresolved non-Codex thread, or a merge
that would not land.

## Cache layout

```
.pr-loop/<pr>/
  round-1/
    pr.json                   # reviews summary, issue comments, checks, head oid
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
