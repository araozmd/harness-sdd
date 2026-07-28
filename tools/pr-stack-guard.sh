#!/bin/sh
# pr-stack-guard.sh — is this PR safe to merge, or is it stacked on an unmerged parent? (E21-F04)
#
# The stacked-PR lane lets an atomic feature ship reviewably: increment B is opened against
# increment A's branch instead of the default branch, so the reviewer reads only B's own diff.
# The feature stays atomic with respect to the default branch; the REVIEW does not.
#
# That buys reviewability and introduces exactly one new way to corrupt a branch: merging B
# before A. It is not a race — it is a correctness bug, and `pr_loop.auto_merge` would walk
# straight into it, because the loop's gates only ever asked "are the checks green and the
# threads resolved", never "is my base branch itself still an open PR".
#
# This guard answers that one question, OFFLINE, from JSON the caller already fetched — so it
# is testable without `gh`, without a network, and without a real stack.
#
# Usage:
#   tools/pr-stack-guard.sh evaluate <pr.json> <open-prs.json> [--default-branch <name>]
#
#   pr.json        an object with .baseRefName (what `gh pr view --json baseRefName` returns)
#   open-prs.json  an array of open PRs with .headRefName and .number
#                  (`gh pr list --state open --json number,headRefName`)
#
# Exit codes:
#   0  safe to merge — the base IS the default branch
#   6  STACKED: not safe yet — the base is another OPEN PR's head, or it is a non-default
#      branch nobody owns (the child has not been retargeted). Merge/await the parent.
#   4  usage error / unreadable input
#
# Exit 6 is deliberately its own code and NOT a generic failure: "wait for the parent" is a
# normal, expected state in a stack, not an error. A loop that treated it as a failure would
# label a perfectly healthy child PR needs-human on every round.

set -eu
LC_ALL=C; export LC_ALL

usage() {
  printf 'usage: pr-stack-guard.sh evaluate <pr.json> <open-prs.json> [--default-branch <name>]\n' >&2
  exit 4
}

[ $# -ge 3 ] || usage
[ "$1" = evaluate ] || usage
shift
pr_json="$1"; open_json="$2"; shift 2
default_branch="main"
while [ $# -gt 0 ]; do
  case "$1" in
    --default-branch) [ $# -ge 2 ] || usage; default_branch="$2"; shift 2 ;;
    *) printf 'pr-stack-guard.sh: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

[ -f "$pr_json" ]   || { printf 'pr-stack-guard.sh: no such file: %s\n' "$pr_json" >&2; exit 4; }
[ -f "$open_json" ] || { printf 'pr-stack-guard.sh: no such file: %s\n' "$open_json" >&2; exit 4; }
command -v jq >/dev/null 2>&1 || { printf 'pr-stack-guard.sh: jq is required (same dependency as /sdd-pr-loop)\n' >&2; exit 4; }

# Fail CLOSED on an unreadable base, exactly as step 3 does for headRefOid. A base we could
# not read is not "the default branch" — treating it as such is how a child PR gets merged
# ahead of its parent by a guard that was supposed to prevent it.
if ! base="$(jq -r '.baseRefName // ""' "$pr_json" 2>/dev/null)" || [ -z "$base" ]; then
  printf 'pr-stack-guard.sh: could not read .baseRefName from %s — not merging\n' "$pr_json" >&2
  exit 4
fi

if [ "$base" = "$default_branch" ]; then
  printf 'base=%s (default branch) — not stacked, safe to merge\n' "$base"
  exit 0
fi

if ! parent="$(jq -r --arg b "$base" 'map(select((.headRefName // "") == $b)) | (.[0].number // "")' "$open_json" 2>/dev/null)"; then
  printf 'pr-stack-guard.sh: could not parse %s — not merging\n' "$open_json" >&2
  exit 4
fi

if [ -n "$parent" ] && [ "$parent" != "null" ]; then
  printf 'STACKED: base=%s is the head of open PR #%s — merge the parent first\n' "$base" "$parent"
  exit 6
fi

# A non-default base with NO open PR owning it is NOT proof that merging is safe, and an
# earlier draft of this guard cleared it — wrongly. Two ways it goes bad, both ending with
# the loop reporting success while the child's commits are nowhere near the default branch:
#
#   1. The parent merged but GitHub has not retargeted the child yet. The parent is already
#      gone from the open-PR list while `baseRefName` still names the old feature branch, so
#      merging now lands the child in a branch that is itself already merged — the child's
#      changes never reach the default branch.
#   2. The parent merged WITHOUT deleting its branch. Then no retarget ever happens, and the
#      stale base persists indefinitely.
#
# So the only state this guard will clear is `base == default_branch`. Everything else waits.
# A caller that legitimately targets a release or integration branch declares it with
# --default-branch; that is an explicit statement of intent, which "no open PR owns the base"
# is not. Waiting costs a round; merging into a dead branch costs the feature.
printf 'STACKED: base=%s is not the default branch (%s) and no open PR owns it — the child has not been retargeted yet; waiting\n' "$base" "$default_branch"
exit 6
