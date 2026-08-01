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
#   9  unresolved   NO REVIEW HAS LANDED for this round — hand over, never merge
#   4  usage error / unreadable input
#
# SCOPE — read this before wiring it into a merge. A `merge` verdict answers ONE question:
# "are there blocking findings left, and is there budget?" It is NOT a merge authorization.
# The CI-green check and the stacked-PR guard (tools/pr-stack-guard.sh) are separate gates
# and still apply before `gh pr merge`. This tool can only ever say "the review is done".
#
# Fails CLOSED: a missing, empty or unparseable blocking.json is never a `merge`. A gate that
# cannot prove the review converged must not be the reason a PR merged.
#
# AN EMPTY blocking.json IS NOT BY ITSELF EVIDENCE OF A CLEAN REVIEW. A round where the
# watcher timed out has an empty blocking.json for the opposite reason: no review landed at
# all. The first version of this tool answered `merge` in exactly that state, and it was
# caught on this tool's OWN pull request, where Codex replied 54s inside the 900s ceiling
# and the 60s-interval watcher missed it. So before reading blocking.json at all, the gate
# re-derives the round's review state with `wait-for-codex.sh evaluate`, which is offline,
# needs no network, and is the same logic the watcher resolves on. Only a round that
# provably RESOLVED — clean, or findings that were then severity-filtered — can reach a
# `merge`. This verification is deliberately independent rather than a caller-supplied
# flag: the whole purpose of the gate is to not take the loop's word for it.

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
have_blocking=0
n_blocking=0
if [ -f "$blocking" ]; then
  # `length` on a non-array is an error, which is exactly the fail-closed behaviour we want:
  # a blocking.json that is not a JSON array is unreadable input, not "zero findings".
  n_blocking="$(jq -e 'if type == "array" then length else error("not an array") end' \
    "$blocking" 2>/dev/null)" || {
    printf 'pr-gate: blocking.json in %s is not a readable JSON array\n' "$round_dir" >&2
    exit 4
  }
  have_blocking=1
fi

# ── Blocking findings present ⇒ a pure budget decision ───────────────────────
# Deliberately BEFORE any review-state probe. The findings are themselves proof that a
# review landed, and after a fixer pushes, step 6 re-fetches pr.json — so the cached head
# has moved on from the head those findings were filed against, and the evaluator would
# report `pending`. Probing here would hand every ordinary blocking round to a human.
if [ "$have_blocking" = 1 ] && [ "$n_blocking" -gt 0 ]; then
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
fi

# ── Zero blocking findings ⇒ only now must a landed review be PROVEN ─────────
# An empty (or absent) blocking set means two opposite things — "reviewed, nothing
# blocking" and "no review landed" — and only the first may merge. Delegated to the
# watcher's offline evaluator so there is exactly one implementation of "a resolved Codex
# review". Exit 0 findings, 3 clean, 1 pending, 4 error.
watcher="$(dirname -- "$0")/wait-for-codex.sh"
[ -f "$watcher" ] || {
  printf 'pr-gate: cannot find wait-for-codex.sh next to this script — cannot prove a review landed\n' >&2
  exit 4
}
ev_rc=0
sh "$watcher" evaluate "$round_dir" >/dev/null 2>&1 || ev_rc=$?

case "$ev_rc" in
  3)
    # Clean review. The runbook tells the driver to SKIP classification on a watcher exit
    # 3, so a banner- or reaction-based clean round legitimately has no blocking.json at
    # all. Exit 3 IS the authoritative empty blocking set; demanding the file here would
    # send every clean review to needs-human instead of merging.
    printf 'merge\n'
    exit 0
    ;;
  0)
    # Inline findings exist. Merging is right only if they were classified and none were
    # blocking (the P2-only case). With no blocking.json their severities were never
    # determined, so there is nothing proving they are non-blocking — fail closed.
    if [ "$have_blocking" = 1 ]; then
      printf 'merge\n'
      exit 0
    fi
    printf 'pr-gate: %s has inline findings but no blocking.json — severities unclassified, not a merge\n' \
      "$round_dir" >&2
    exit 4
    ;;
  1)
    printf 'unresolved\n'
    printf 'pr-gate: no Codex review has resolved for %s (watcher pending/timed out) — not a merge\n' \
      "$round_dir" >&2
    exit 9
    ;;
  *)
    printf 'pr-gate: could not evaluate the review state of %s (wait-for-codex exit %s)\n' \
      "$round_dir" "$ev_rc" >&2
    exit 4
    ;;
esac

# Unreachable — every branch of the case above exits.
