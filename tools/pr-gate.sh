#!/bin/sh
# pr-gate.sh — given the round cache and the round budget, what is the next action? (E99)
#
# The pr-loop already classifies every Codex finding by severity and filters it down to
# `blocking.json` using `pr_loop.blocking_severities` (default P0,P1 — P2 and nit NEVER
# block). That classification was correct. What was missing is that the ACTION taken on
# the result was left to the driving agent's prose reading of the runbook, and the agent
# drifted: on PR #89 every round reported zero blocking findings and the loop still spent
# three rounds and three commits "fixing" P2s, and on PR #86 rounds 6-8 were clean and the
# loop ran to round 12. Across the repo 20 of 43 Codex-fix commits addressed P2s — work the
# configuration explicitly declares non-blocking.
#
# A rule that lives only in prose is a rule an agent can talk itself out of. This tool moves
# the decision into code: it reads the same files the loop already wrote and prints exactly
# one verdict. The loop obeys the verdict; it does not re-litigate it.
#
# Usage:
#   tools/pr-gate.sh evaluate <round-dir> --round <n> --max-rounds <m>
#
#   <round-dir>  a round cache dir holding blocking.json (the SEVERITY-FILTERED findings)
#
# Verdicts (printed on stdout, one word) and exit codes:
#   0  merge        zero blocking findings — STOP. Do not open another round, do not fix
#                   non-blocking findings. (Remaining P2/nit comments are advisory: they may
#                   be answered in a LATER PR, never by extending this loop.)
#   6  fix          blocking findings remain and there is budget — fix them per-comment
#   7  escalate     blocking findings remain and this is the last productive round —
#                   one combined pass (the `max_rounds - 1` behavior)
#   8  needs-human  the round budget is exhausted — label and hand over
#   4  usage error / unreadable input
#
# SCOPE — read this before wiring it into a merge. A `merge` verdict answers ONE question:
# "are there blocking findings left, and is there budget?" It is NOT a merge authorization.
# The CI-green check and the stacked-PR guard (tools/pr-stack-guard.sh) are separate gates
# and still apply before `gh pr merge`. This tool can only ever say "the review is done".
#
# Fails CLOSED: a missing, empty or unparseable blocking.json is never a `merge`. A gate that
# cannot prove the review converged must not be the reason a PR merged.

set -eu
LC_ALL=C; export LC_ALL

usage() {
  printf 'usage: pr-gate.sh evaluate <round-dir> --round <n> --max-rounds <m>\n' >&2
  exit 4
}

[ $# -ge 1 ] || usage
[ "$1" = evaluate ] || usage
shift
[ $# -ge 1 ] || usage
round_dir="$1"; shift

round=""
max_rounds=""
while [ $# -gt 0 ]; do
  case "$1" in
    --round)      [ $# -ge 2 ] || usage; round="$2"; shift 2 ;;
    --max-rounds) [ $# -ge 2 ] || usage; max_rounds="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# Both counters are required: a budget decision with a guessed budget is not a decision.
case "$round" in ''|*[!0-9]*) usage ;; esac
case "$max_rounds" in ''|*[!0-9]*) usage ;; esac
[ "$round" -ge 1 ] || usage
[ "$max_rounds" -ge 1 ] || usage

[ -d "$round_dir" ] || {
  printf 'pr-gate: round dir not found: %s\n' "$round_dir" >&2
  exit 4
}

command -v jq >/dev/null 2>&1 || {
  printf 'pr-gate: `jq` is not on PATH — install jq (https://jqlang.github.io/jq/)\n' >&2
  exit 4
}

blocking="$round_dir/blocking.json"
[ -f "$blocking" ] || {
  printf 'pr-gate: no blocking.json in %s — cannot prove the review converged\n' "$round_dir" >&2
  exit 4
}

# `length` on a non-array is an error, which is exactly the fail-closed behaviour we want:
# a blocking.json that is not a JSON array is unreadable input, not "zero findings".
n_blocking="$(jq -e 'if type == "array" then length else error("not an array") end' \
  "$blocking" 2>/dev/null)" || {
  printf 'pr-gate: blocking.json in %s is not a readable JSON array\n' "$round_dir" >&2
  exit 4
}

if [ "$n_blocking" -eq 0 ]; then
  # The whole point of the tool. Zero BLOCKING findings ends the loop, whatever
  # non-blocking chatter is still on the PR.
  printf 'merge\n'
  exit 0
fi

# Findings remain — the verdict is now purely a budget question.
if [ "$round" -ge "$max_rounds" ]; then
  printf 'needs-human\n'
  exit 8
fi

if [ "$round" -eq $((max_rounds - 1)) ]; then
  printf 'escalate\n'
  exit 7
fi

printf 'fix\n'
exit 6
