#!/bin/sh
# wait-for-codex.sh — block until a Codex review lands on the PR's head commit.
#
# WHY THIS EXISTS
#   /sdd-pr-loop is a runbook the model follows by hand inside an interactive session.
#   On its own, the model fetches the review state once, sees nothing yet, and ends
#   its turn — so a Codex review that lands minutes later goes unnoticed until a
#   human nudges "review again". This script is the missing wake mechanism: launch
#   it in the background (Claude Code's Bash tool `run_in_background: true`, or
#   `sh … &` elsewhere) and it polls every HARNESS_POLL_INTERVAL seconds. The instant
#   Codex resolves (or the ceiling is hit) it exits, and the harness re-invokes the
#   session to classify and fix. True minute-by-minute monitoring, no manual nudge,
#   survives turns.
#
# Usage (three modes, one evaluation routine):
#   wait-for-codex.sh <pr-number> <trigger-comment-id> <round-dir>   # wait (poll GitHub)
#   wait-for-codex.sh preflight <pr-number>                          # static checks only
#   wait-for-codex.sh evaluate  <round-dir>                          # offline re-evaluation
#
#   pr-number:          the open PR
#   trigger-comment-id: id of the `@codex review` issue comment (for the 👍 case)
#   round-dir:          <HARNESS_DIR>/.pr-loop/<pr>/round-<n>/ — where the 4 source
#                       files + trigger-ts.txt land
#
# Env knobs (all optional). HARNESS_* names ONLY — no other vendor prefix is read:
#   HARNESS_POLL_INTERVAL   seconds between polls, MUST be > 0        (default 60)
#   HARNESS_POLL_CEILING    max seconds to wait before timeout        (default 900 = 15 min)
#   HARNESS_FIRST_RESPONSE  seconds to wait for THIS ROUND's Codex    (default 180; 0 = off)
#                           activity (see wfc_bot_seen)
#
# Exit codes (the caller branches on these):
#   0  → a Codex review with FRESH findings landed on head (created_at >= trigger).
#   1  → `evaluate` only: no resolution yet (pending). Never returned by wait mode.
#   2  → timeout: ceiling hit with no resolution. Caller aborts round w/ needs-human.
#   3  → clean review, zero findings (summary banner on head as a review OR as an
#        issue comment, OR 👍 reaction on the trigger comment).
#   4  → usage / precondition error (includes an unresolvable trigger timestamp and a
#        non-positive HARNESS_POLL_INTERVAL).
#   5  → preflight check failed, or no Codex activity within HARNESS_FIRST_RESPONSE.
#
# Always (re)writes pr.json, review-comments.json, issue-comments.json, reactions.json
# into round-dir on every poll, so the caller reads the same sources the command body
# describes. POSIX sh, no bashisms (the harness's zero-dependency ethos); the ONLY
# runtime dependencies are `gh` (authed) and `jq`, both asserted by `preflight` (`date +%s`
# is used opportunistically for the wall-clock deadlines, with a fallback when absent).

set -eu

# The Codex bot logins. `gh pr view` (GraphQL) reports `chatgpt-codex-connector`; the REST
# API reports `chatgpt-codex-connector[bot]`. Both spellings are accepted, as EXACT literals
# and nothing else. A prefix test (the shape this shipped with) is a spoofing hole: any
# GitHub account whose login merely BEGINS with the bot name — `chatgpt-codex-connector-evil`
# — could add a 👍 to the trigger comment or post a "Reviewed commit: <head>" banner, driving
# `evaluate` to exit 3 ("clean, zero findings"), which the caller does not classify and
# auto-merges. The two literals below cover the GraphQL/REST spelling split completely, so
# there is nothing left for a prefix to buy.
WFC_BOT="chatgpt-codex-connector"
WFC_BOT_REST="chatgpt-codex-connector[bot]"

wfc_usage() {
  echo "usage: $0 <pr-number> <trigger-comment-id> <round-dir>" >&2
  echo "       $0 preflight <pr-number>" >&2
  echo "       $0 evaluate <round-dir>" >&2
}

# wfc_int <value> <default> — echo <value> when it is a non-negative integer, else <default>.
wfc_int() {
  case "$1" in
    ''|*[!0-9]*) printf '%s\n' "$2" ;;
    *)           printf '%s\n' "$1" ;;
  esac
}

# wfc_elapsed <start-epoch> <fallback> — seconds since <start-epoch> by WALL CLOCK, or
# <fallback> when the clock is unusable (absent/odd `date`, or a backwards step). Advancing
# the deadlines by the poll interval alone UNDERSTATES real time — every poll makes several
# `gh` calls — so both the ceiling and the first-response window silently stretch past their
# configured budgets. `date +%s` is deliberately NOT a hard dependency: without it the caller
# falls back to the accumulator, which is bounded because the interval is validated positive.
wfc_elapsed() {
  case "$1" in
    ''|*[!0-9]*) printf '%s\n' "$2"; return 0 ;;
  esac
  _wfce_now="$(date +%s 2>/dev/null || true)"
  case "$_wfce_now" in
    ''|*[!0-9]*) printf '%s\n' "$2"; return 0 ;;
  esac
  if [ "$_wfce_now" -lt "$1" ]; then printf '%s\n' "$2"; return 0; fi
  printf '%s\n' "$(( _wfce_now - $1 ))"
}

# wfc_count <value> — normalize a jq `length` result to a plain integer (0 on anything else).
wfc_count() {
  case "$1" in
    ''|*[!0-9]*) printf '0\n' ;;
    *)           printf '%s\n' "$1" ;;
  esac
}

# ── the ONE evaluation routine ────────────────────────────────────────────────
# wfc_evaluate <round-dir> <trigger-ts> — echo findings | clean | pending.
# PURE and OFFLINE: it reads only the already-written round files and invokes no `gh`
# and no network, which is what lets `evaluate` mode and the test fixtures apply the
# exact same freshness rules the live wait loop applies (R29).
wfc_evaluate() {
  _ev_dir="$1"; _ev_since="$2"

  [ -f "$_ev_dir/pr.json" ] || { echo pending; return 0; }
  _ev_head="$(jq -r '.headRefOid // ""' "$_ev_dir/pr.json" 2>/dev/null || echo '')"
  [ -n "$_ev_head" ] || { echo pending; return 0; }
  _ev_short="$(printf '%s' "$_ev_head" | cut -c1-7)"

  # Condition 1: FRESH inline findings filed by the Codex bot against the head commit.
  # The created_at >= trigger filter excludes stale threads that GitHub re-anchored to
  # head (their commit_id matches but they predate this round's trigger). No-op when
  # the anchor is empty. ISO-8601 timestamps compare correctly as lexical strings.
  # review-comments.json is a REQUIRED source, not an optional one: it is the only
  # stream that carries inline findings. Absent (a failed fetch never staged it) or
  # unreadable means "we do not know", NOT "zero findings" — falling through to the
  # clean-banner conditions there would report a PR with fresh blocking findings as
  # clean (exit 3), which the caller skips classification on and auto-merges. Stay
  # pending so the poll retries.
  [ -f "$_ev_dir/review-comments.json" ] || { echo pending; return 0; }
  _ev_findings="$(jq --arg bot "$WFC_BOT" --arg botr "$WFC_BOT_REST" \
                     --arg head "$_ev_head" --arg since "$_ev_since" '
    [ .[]? | select((.user.login // "") == $bot or (.user.login // "") == $botr)
           | select((.commit_id // "") == $head)
           | select($since == "" or ((.created_at // "") >= $since)) ] | length' \
    "$_ev_dir/review-comments.json" 2>/dev/null || printf 'unreadable')"
  case "$_ev_findings" in
    ''|*[!0-9]*) echo pending; return 0 ;;
  esac
  if [ "$_ev_findings" -gt 0 ]; then echo findings; return 0; fi

  # Condition 2: FRESH review summary banner naming the head commit, with zero findings.
  # submittedAt >= trigger excludes a banner from a PRIOR review of the same head (e.g. a
  # re-request without a new commit), which would otherwise flag the new round clean early.
  _ev_banner="$(jq --arg bot "$WFC_BOT" --arg botr "$WFC_BOT_REST" \
                   --arg sh "$_ev_short" --arg since "$_ev_since" '
    [ .reviews[]? | select((.author.login // "") == $bot or (.author.login // "") == $botr)
                  | select((.body // "") | contains("Reviewed commit") and contains($sh))
                  | select($since == "" or ((.submittedAt // "") >= $since)) ]
    | length' "$_ev_dir/pr.json" 2>/dev/null || echo 0)"
  if [ "$(wfc_count "$_ev_banner")" -gt 0 ]; then echo clean; return 0; fi

  # Condition 2b: the zero-findings banner delivered as an ISSUE comment, not a review.
  # Codex's clean result ("Didn't find any major issues. Breezy!" + "Reviewed commit:
  # <head>") posts to the issue-comment stream, which conditions 1/2 never scan — so a
  # genuinely clean PR would stall until the ceiling. Scan the PAGINATED issue-comments
  # file (REST ⇒ .user.login) so a banner past the first 100 comments is still caught.
  # Same created_at >= trigger freshness guard as condition 1 — a stale banner from a
  # prior review of this head must not flag the new round clean before Codex responds.
  if [ -f "$_ev_dir/issue-comments.json" ]; then
    _ev_banner_issue="$(jq --arg bot "$WFC_BOT" --arg botr "$WFC_BOT_REST" \
                           --arg sh "$_ev_short" --arg since "$_ev_since" '
      [ .[]? | select((.user.login // "") == $bot or (.user.login // "") == $botr)
             | select((.body // "") | contains("Reviewed commit") and contains($sh))
             | select($since == "" or ((.created_at // "") >= $since)) ]
      | length' "$_ev_dir/issue-comments.json" 2>/dev/null || echo 0)"
    if [ "$(wfc_count "$_ev_banner_issue")" -gt 0 ]; then echo clean; return 0; fi
  fi

  # Condition 3: Codex bot reacted 👍 (+1) on the triggering comment.
  if [ -f "$_ev_dir/reactions.json" ]; then
    _ev_thumbs="$(jq --arg bot "$WFC_BOT" --arg botr "$WFC_BOT_REST" '
      [ .[]? | select((.content // "") == "+1")
             | select((.user.login // "") == $bot or (.user.login // "") == $botr) ] | length' \
      "$_ev_dir/reactions.json" 2>/dev/null || echo 0)"
    if [ "$(wfc_count "$_ev_thumbs")" -gt 0 ]; then echo clean; return 0; fi
  fi

  echo pending
}

# wfc_bot_seen <round-dir> <trigger-ts> — exit 0 when Codex activity for THIS ROUND is
# visible: any reaction on the trigger comment (Codex adds 👀 on pickup), any bot issue
# comment or bot review created at/after the trigger. This is deliberately broader than
# the resolution conditions — it answers "did the app respond at all", not "did it
# finish" (R32).
#
# The comment/review counts MUST be scoped by <trigger-ts>, exactly like the resolution
# conditions above. Unscoped, every round after the first sees the PRIOR rounds' Codex
# comments and reviews still sitting on the PR, disarms the probe on the very first poll,
# and a repo where the App can no longer answer waits out the full ceiling and reports a
# plain timeout (exit 2) instead of the missing-App diagnostic (exit 5). ISO-8601
# timestamps compare correctly as lexical strings; an empty anchor (the no-trigger-id
# compat path) makes the filter a no-op, preserving the pre-scoping behaviour there.
#
# reactions.json needs NO timestamp filter: it is fetched per poll from THIS round's
# trigger comment id (`issues/comments/$TRIGGER_COMMENT_ID/reactions`), so it is already
# round-scoped by construction — a reaction there can only have been left in response to
# the current `@codex review`.
wfc_bot_seen() {
  _bs_dir="$1"; _bs_since="${2:-}"
  if [ -f "$_bs_dir/reactions.json" ]; then
    _bs_n="$(jq '[ .[]? ] | length' "$_bs_dir/reactions.json" 2>/dev/null || echo 0)"
    [ "$(wfc_count "$_bs_n")" -gt 0 ] && return 0
  fi
  if [ -f "$_bs_dir/issue-comments.json" ]; then
    _bs_n="$(jq --arg bot "$WFC_BOT" --arg botr "$WFC_BOT_REST" --arg since "$_bs_since" \
      '[ .[]? | select((.user.login // "") == $bot or (.user.login // "") == $botr)
              | select($since == "" or ((.created_at // "") >= $since)) ] | length' \
      "$_bs_dir/issue-comments.json" 2>/dev/null || echo 0)"
    [ "$(wfc_count "$_bs_n")" -gt 0 ] && return 0
  fi
  if [ -f "$_bs_dir/pr.json" ]; then
    _bs_n="$(jq --arg bot "$WFC_BOT" --arg botr "$WFC_BOT_REST" --arg since "$_bs_since" \
      '[ .reviews[]? | select((.author.login // "") == $bot or (.author.login // "") == $botr)
                     | select($since == "" or ((.submittedAt // "") >= $since)) ] | length' \
      "$_bs_dir/pr.json" 2>/dev/null || echo 0)"
    [ "$(wfc_count "$_bs_n")" -gt 0 ] && return 0
  fi
  return 1
}

# ── preflight mode ────────────────────────────────────────────────────────────
# Static, read-only checks run BEFORE the command body posts anything to GitHub, so a
# repo without the Codex GitHub App (or without an authed gh) fails in a second with a
# named remedy instead of polling to the ceiling. Posts NOTHING (R30/R31).
wfc_preflight() {
  _pf_pr="$1"
  if ! command -v gh >/dev/null 2>&1; then
    echo "wait-for-codex preflight: \`gh\` is not on PATH — install the GitHub CLI (https://cli.github.com) or set pr_loop.enabled: false" >&2
    return 5
  fi
  if ! gh auth status >/dev/null 2>&1; then
    echo "wait-for-codex preflight: \`gh\` is not authenticated — run \`gh auth login\`" >&2
    return 5
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "wait-for-codex preflight: \`jq\` is not on PATH — install jq (https://jqlang.github.io/jq/) or set pr_loop.enabled: false" >&2
    return 5
  fi
  if ! _pf_slug="$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"' 2>/dev/null)" \
     || [ -z "$_pf_slug" ]; then
    echo "wait-for-codex preflight: repo slug unresolvable — run from a git repo with a GitHub remote (\`gh repo set-default\`)" >&2
    return 5
  fi
  if ! _pf_state="$(gh pr view "$_pf_pr" --json state --jq '.state' 2>/dev/null)" \
     || [ -z "$_pf_state" ]; then
    echo "wait-for-codex preflight: PR #$_pf_pr not found in $_pf_slug — pass an existing PR number" >&2
    return 5
  fi
  if [ "$_pf_state" != "OPEN" ]; then
    echo "wait-for-codex preflight: PR #$_pf_pr is $_pf_state, not OPEN — reopen it or pass an open PR" >&2
    return 5
  fi
  echo "wait-for-codex preflight: ok (gh authed, jq present, $_pf_slug PR #$_pf_pr open)" >&2
  return 0
}

# ── mode dispatch ─────────────────────────────────────────────────────────────
case "${1:-}" in
  preflight)
    if [ -z "${2:-}" ]; then wfc_usage; exit 4; fi
    if wfc_preflight "$2"; then exit 0; else exit 5; fi
    ;;
  evaluate)
    if [ -z "${2:-}" ]; then wfc_usage; exit 4; fi
    EV_DIR="$2"
    if [ ! -d "$EV_DIR" ]; then
      echo "wait-for-codex evaluate: round dir not found: $EV_DIR" >&2
      exit 4
    fi
    if ! command -v jq >/dev/null 2>&1; then
      echo "wait-for-codex evaluate: \`jq\` is not on PATH — install jq (https://jqlang.github.io/jq/)" >&2
      exit 4
    fi
    # The freshness anchor is read from the round dir, never re-fetched — `evaluate`
    # invokes no `gh` and touches no network, by construction.
    EV_TS=""
    if [ -f "$EV_DIR/trigger-ts.txt" ]; then EV_TS="$(cat "$EV_DIR/trigger-ts.txt")"; fi
    case "$(wfc_evaluate "$EV_DIR" "$EV_TS")" in
      findings) exit 0 ;;
      clean)    exit 3 ;;
      *)        exit 1 ;;
    esac
    ;;
  ''|-h|--help)
    wfc_usage; exit 4 ;;
esac

# ── wait mode (the source contract: <pr> <trigger-comment-id> <round-dir>) ────
PR_NUMBER="${1:-}"
TRIGGER_COMMENT_ID="${2:-}"
ROUND_DIR="${3:-}"

if [ -z "$PR_NUMBER" ] || [ -z "$ROUND_DIR" ]; then
  wfc_usage
  exit 4
fi

INTERVAL="$(wfc_int "${HARNESS_POLL_INTERVAL:-60}" 60)"
CEILING="$(wfc_int "${HARNESS_POLL_CEILING:-900}" 900)"
FIRST_RESPONSE="$(wfc_int "${HARNESS_FIRST_RESPONSE:-180}" 180)"

# A ZERO interval is the one numeric value wfc_int accepts that makes this loop unbounded:
# `sleep 0` returns instantly, so the watcher would hammer the GitHub API at full rate until
# killed from outside. (Wall-clock deadlines below would cap it at the ceiling, but a
# rate-limit burn is still not a mode we ship.) Fail closed as a usage error instead —
# 0 has no useful meaning for this knob, unlike HARNESS_FIRST_RESPONSE=0 (probe off).
if [ "$INTERVAL" -le 0 ]; then
  echo "wait-for-codex: HARNESS_POLL_INTERVAL must be a positive number of seconds" \
       "(got '${HARNESS_POLL_INTERVAL:-}') — refusing to poll the GitHub API without a delay" >&2
  exit 4
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "wait-for-codex: \`gh\` is not on PATH — run \`$0 preflight $PR_NUMBER\` for the full diagnostic" >&2
  exit 4
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "wait-for-codex: \`jq\` is not on PATH — run \`$0 preflight $PR_NUMBER\` for the full diagnostic" >&2
  exit 4
fi

mkdir -p "$ROUND_DIR"

# POSIX: no process substitution. One command substitution + parameter expansion.
if ! SLUG="$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"' 2>/dev/null)" \
   || [ -z "$SLUG" ]; then
  echo "wait-for-codex: could not resolve the repo slug (gh repo view) — aborting" >&2
  exit 4
fi
owner="${SLUG%% *}"
repo="${SLUG##* }"

# Freshness anchor: only inline comments created at/after the trigger count as this
# round's findings. GitHub re-stamps old unresolved threads' commit_id to each new
# head, so without this filter re-anchored stale threads masquerade as fresh findings
# and the clean path is never reached. Resolved once at startup (the trigger comment
# is immutable). Empty when no trigger id is passed → the filter is a no-op.
TRIGGER_TS=""
if [ -n "$TRIGGER_COMMENT_ID" ]; then
  # An id was provided → we MUST resolve its timestamp. An empty TS here would silently
  # disable the freshness filter for the whole wait and recreate the stale re-anchored-
  # thread bug this guard prevents. So retry a few times, then abort with a usage error
  # rather than proceeding blind. (Empty TS is reserved for the no-id compat path above.)
  _attempt=1
  while [ "$_attempt" -le 3 ]; do
    TRIGGER_TS="$(gh api "repos/$owner/$repo/issues/comments/$TRIGGER_COMMENT_ID" \
      --jq '.created_at' 2>/dev/null || echo '')"
    [ -n "$TRIGGER_TS" ] && break
    [ "$_attempt" -lt 3 ] && sleep 2
    _attempt=$(( _attempt + 1 ))
  done
  if [ -z "$TRIGGER_TS" ]; then
    echo "wait-for-codex: could not resolve trigger comment $TRIGGER_COMMENT_ID timestamp" \
         "— aborting so the freshness filter is not silently disabled" >&2
    exit 4
  fi
fi
# Persist the anchor so the command body's classification step can apply the SAME
# freshness filter. The watcher only uses it for its exit decision; review-comments.json
# is written unfiltered (it's the raw source of truth), so without this the classifier
# would re-admit stale re-anchored threads into blocking.json — defeating the guard.
printf '%s' "$TRIGGER_TS" > "$ROUND_DIR/trigger-ts.txt"

# Fetch the sources into the round dir for this poll.
fetch_sources() {
  gh pr view "$PR_NUMBER" --json reviews,comments,statusCheckRollup,headRefOid,baseRefName,baseRefOid \
    > "$ROUND_DIR/pr.json" 2>/dev/null || return 1
  # `--paginate --slurp` then `jq 'add // []'`: --slurp is required so paginated REST
  # results remain parseable past page 1, and --paginate is required so a finding past
  # page 1 is seen at all. Neither may be dropped.
  #
  # A FAILED fetch is NOT an empty result. This is the authoritative findings stream, so
  # writing `[]` on failure lets a fresh clean banner be read as a clean review (exit 3),
  # which the caller does not classify and auto-merges — a PR with blocking findings
  # merged on a transient API error. Stage into a temp file and only publish it when the
  # fetch AND the flatten both succeeded; otherwise keep the last good copy untouched and
  # return 1 so the poll retries. (Piping straight into jq cannot detect this: jq reads
  # gh's empty stdout, exits 0 and truncates the file, so the `||` branch never fires.)
  _fs_raw="$ROUND_DIR/.review-comments.raw"
  _fs_tmp="$ROUND_DIR/.review-comments.tmp"
  if gh api "repos/$owner/$repo/pulls/$PR_NUMBER/comments" --paginate --slurp \
       > "$_fs_raw" 2>/dev/null \
     && jq 'add // []' < "$_fs_raw" > "$_fs_tmp" 2>/dev/null \
     && [ -s "$_fs_tmp" ]; then
    rm -f "$_fs_raw"
    mv "$_fs_tmp" "$ROUND_DIR/review-comments.json"
  else
    rm -f "$_fs_raw" "$_fs_tmp"
    return 1
  fi
  # Issue comments via the PAGINATED REST endpoint. gh pr view --json comments caps at
  # first:100, so a clean banner (condition 2b) posted past page 1 would be missed and
  # an otherwise-clean PR would time out. This file is what condition 2b scans.
  gh api "repos/$owner/$repo/issues/$PR_NUMBER/comments" --paginate --slurp 2>/dev/null \
    | jq 'add // []' > "$ROUND_DIR/issue-comments.json" \
    || echo '[]' > "$ROUND_DIR/issue-comments.json"
  if [ -n "$TRIGGER_COMMENT_ID" ]; then
    gh api "repos/$owner/$repo/issues/comments/$TRIGGER_COMMENT_ID/reactions" \
      > "$ROUND_DIR/reactions.json" 2>/dev/null || echo '[]' > "$ROUND_DIR/reactions.json"
  else
    echo '[]' > "$ROUND_DIR/reactions.json"
  fi
  # A truncated/failed write must never poison the evaluation. review-comments.json is
  # deliberately NOT defaulted here: for the findings stream, an empty-but-valid `[]` is
  # indistinguishable from a successful zero-findings fetch, so it is retried above.
  [ -s "$ROUND_DIR/issue-comments.json" ]  || echo '[]' > "$ROUND_DIR/issue-comments.json"
  [ -s "$ROUND_DIR/reactions.json" ]       || echo '[]' > "$ROUND_DIR/reactions.json"
  return 0
}

# First-response probe (R32/R33): the failure this catches is "the Codex GitHub App is
# not installed on this repo", where `@codex review` is posted and NOTHING ever answers.
# Without it that costs the full ceiling. Armed only while no bot activity FOR THIS ROUND
# has been seen (wfc_bot_seen scopes by the trigger anchor, so an earlier round's comments
# and reviews cannot disarm it), disarmed PERMANENTLY on first sighting (so a slow review
# is never mistaken for a dead app), skipped entirely at 0 (R33) or when the window is not
# below the ceiling (which already covers that case).
PROBE=1
if [ "$FIRST_RESPONSE" -eq 0 ]; then PROBE=0; fi
if [ "$FIRST_RESPONSE" -ge "$CEILING" ]; then PROBE=0; fi

# Deadline clock. WFC_START anchors the wall-clock measurement; `ticks` is the summed-
# interval fallback used only when `date` is unusable.
WFC_START="$(date +%s 2>/dev/null || true)"
case "$WFC_START" in ''|*[!0-9]*) WFC_START='' ;; esac

elapsed=0
ticks=0
while :; do
  if fetch_sources; then
    case "$(wfc_evaluate "$ROUND_DIR" "$TRIGGER_TS")" in
      findings) echo "wait-for-codex: review with findings landed on head (${elapsed}s)" >&2; exit 0 ;;
      clean)    echo "wait-for-codex: clean review, 0 findings (${elapsed}s)" >&2; exit 3 ;;
    esac
    if [ "$PROBE" = 1 ] && wfc_bot_seen "$ROUND_DIR" "$TRIGGER_TS"; then
      PROBE=0   # disarm permanently — Codex is awake, let the ceiling govern from here
    fi
  else
    echo "wait-for-codex: gh fetch failed, retrying (${elapsed}s)" >&2
  fi

  # Re-measure BEFORE the two deadline checks, so the time this poll's `gh` calls actually
  # took counts against them rather than being rounded away.
  elapsed="$(wfc_elapsed "$WFC_START" "$ticks")"

  if [ "$PROBE" = 1 ] && [ "$elapsed" -ge "$FIRST_RESPONSE" ]; then
    echo "wait-for-codex: no Codex activity of any kind within ${FIRST_RESPONSE}s —" \
         "the Codex GitHub App is most likely not installed on this repository (or has no" \
         "access to it). Install/authorize it, or set pr_loop.enabled: false in" \
         "harness.config.yaml. Set HARNESS_FIRST_RESPONSE=0 to disable this probe." >&2
    exit 5
  fi

  if [ $(( elapsed + INTERVAL )) -gt "$CEILING" ]; then
    echo "wait-for-codex: ceiling ${CEILING}s reached with no resolution — timeout" >&2
    exit 2
  fi
  sleep "$INTERVAL"
  ticks=$(( ticks + INTERVAL ))
done
