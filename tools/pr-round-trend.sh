#!/bin/sh
# pr-round-trend.sh — is this PR's review CONVERGING, or just being resampled? (E21-F03)
#
# `pr_loop.max_rounds` caps the loop and labels the PR needs-human. What it never said is
# what the human should CONCLUDE. In practice the conclusion drawn is "run it again": on
# viernes-ai/viernes-bookings-api PR #76 the operator posted `@codex review` twelve times by
# hand. Rounds 5–12 cost roughly 2M input tokens and 8 hours of wall clock to keep
# rediscovering that the diff was too large to review in one pass.
#
# The information that would have ended it after round 4 was already on the PR and nobody
# aggregated it — the per-round blocking-finding count:
#
#     R1 R2 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12
#      1  3  1  2  1  3  1  2  2   1   2   1     (P1 only; 20 P1 + 15 P2 total)
#
# A DECAYING count means the review is converging and one more round is rational. A FLAT
# count means the reviewer is sampling a surface larger than one pass can cover, and more
# rounds buy more samples, not more confidence. Those two look identical at the cap today.
#
# Reads only the loop's own round cache — no `gh`, no network, no new state. Everything here
# is rebuildable from `.pr-loop/<pr>/round-*/blocking.json`, which the loop already writes.
#
# Usage:
#   tools/pr-round-trend.sh --cache <.pr-loop/<pr>> [--format text|json] [--window <n>]
#
# Exit codes:
#   0  reported (any verdict)          4  usage error / unreadable cache
#
# ADVISORY. It reports a series and a verdict; it never fails a PR and never merges one.

set -eu
LC_ALL=C; export LC_ALL

WINDOW=3          # "the last N rounds each produced >=1 blocking finding" ⇒ not converging
cache=""; format="text"

usage() {
  printf 'usage: pr-round-trend.sh --cache <.pr-loop/<pr>> [--format text|json] [--window <n>]\n' >&2
  exit 4
}
while [ $# -gt 0 ]; do
  case "$1" in
    --cache)  [ $# -ge 2 ] || usage; cache="$2";  shift 2 ;;
    --format) [ $# -ge 2 ] || usage; format="$2"; shift 2 ;;
    --window) [ $# -ge 2 ] || usage; WINDOW="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) printf 'pr-round-trend.sh: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done
[ -n "$cache" ] || usage
case "$format" in text|json) : ;; *) printf 'pr-round-trend.sh: --format must be text or json\n' >&2; usage ;; esac
case "$WINDOW" in ''|*[!0-9]*) printf 'pr-round-trend.sh: --window must be a positive integer\n' >&2; usage ;; esac
[ "$WINDOW" -ge 1 ] || usage
[ -d "$cache" ] || { printf 'pr-round-trend.sh: no such cache dir: %s\n' "$cache" >&2; exit 4; }
command -v jq >/dev/null 2>&1 || { printf 'pr-round-trend.sh: jq is required (same dependency as /sdd-pr-loop)\n' >&2; exit 4; }

# ── the series ───────────────────────────────────────────────────────────────────
# Only rounds with a READABLE blocking.json count. A round that aborted before classifying
# (unreadable head oid, watcher timeout) has no finding count — treating its absence as 0
# would fake a convergence that never happened.
series=""; rounds=""; n_rounds=0
for d in "$cache"/round-*/; do
  [ -d "$d" ] || continue
  _n="$(basename "$d" | sed 's/^round-//')"
  case "$_n" in ''|*[!0-9]*) continue ;; esac
  [ -f "$d/blocking.json" ] || continue
  _c="$(jq 'length' "$d/blocking.json" 2>/dev/null || true)"
  case "${_c:-}" in ''|*[!0-9]*) continue ;; esac
  rounds="$rounds $_n"; series="$series $_c"; n_rounds=$((n_rounds + 1))
done

if [ "$n_rounds" -eq 0 ]; then
  if [ "$format" = json ]; then
    printf '{"verdict":"insufficient","rounds":0,"series":[],"window":%d,"top_files":[]}\n' "$WINDOW"
  else
    printf 'no round with a readable blocking.json under %s — nothing to trend\n' "$cache"
  fi
  exit 0
fi

# ── the verdict ──────────────────────────────────────────────────────────────────
# Deliberately the SIMPLEST rule that separates the two cases, because it has to be
# explainable inside a needs-human message: "the last N rounds each produced at least one
# blocking finding". A least-squares slope would be defensible and unreadable.
#
# A converging PR (3 → 1 → 0) does not trip it: the last round is 0.
# PR #76 (1 3 1 2 1 3 …) trips it at round 3 and never stops tripping it.
verdict="converging"
if [ "$n_rounds" -lt "$WINDOW" ]; then
  verdict="insufficient"
else
  _tail="$(printf '%s\n' $series | tail -n "$WINDOW")"
  _allnz=1
  for _v in $_tail; do [ "$_v" -ge 1 ] || _allnz=0; done
  [ "$_allnz" -eq 1 ] && verdict="non-converging"
fi

# ── concentration ────────────────────────────────────────────────────────────────
# Where the findings are, across every round. `blocking.json` already carries `.path`, so
# this is one jq pass over files the loop wrote anyway. It turns "split this PR" from advice
# into a pointer: on PR #76 the same grouping put 11 of 33 findings on ONE file that was
# 5.4% of the diff.
top="$(cat "$cache"/round-*/blocking.json 2>/dev/null \
  | jq -r -s 'add // [] | map(.path // "(no path)") | group_by(.) | map({p:.[0], n:length})
              | sort_by(-.n) | .[:5] | .[] | "\(.n)\t\(.p)"' 2>/dev/null || true)"

if [ "$format" = json ]; then
  printf '{"verdict":"%s","rounds":%d,"window":%d,"series":[' "$verdict" "$n_rounds" "$WINDOW"
  _f=1; for _v in $series; do [ "$_f" = 1 ] || printf ','; printf '%s' "$_v"; _f=0; done
  printf '],"round_ids":['
  _f=1; for _v in $rounds; do [ "$_f" = 1 ] || printf ','; printf '%s' "$_v"; _f=0; done
  printf '],"top_files":['
  _f=1
  printf '%s\n' "$top" | while IFS="$(printf '\t')" read -r _n _p; do
    [ -n "${_p:-}" ] || continue
    [ "$_f" = 1 ] || printf ','
    printf '{"path":"%s","findings":%d}' "$_p" "$_n"; _f=0
  done
  printf ']}\n'
  exit 0
fi

printf 'blocking findings per round (%s):\n' "$cache"
printf '  round '; for _r in $rounds; do printf '%4s' "$_r"; done; printf '\n'
printf '  count '; for _c in $series; do printf '%4s' "$_c"; done; printf '\n\n'
case "$verdict" in
  insufficient)
    printf '  verdict: insufficient — fewer than %d rounds with a readable blocking.json.\n' "$WINDOW" ;;
  converging)
    printf '  verdict: converging — the finding rate is coming down. One more round is rational.\n' ;;
  non-converging)
    printf '  verdict: NON-CONVERGING — the last %d rounds each produced a blocking finding.\n' "$WINDOW"
    printf '\n  SPLIT THIS PR. Do not re-review it. A flat rate means the reviewer is sampling a\n'
    printf '  surface larger than one pass can cover, so another round buys another sample, not\n'
    printf '  more confidence — and a clean round would be indistinguishable from a round that\n'
    printf '  happened to land somewhere quiet.\n'
    if [ -n "$top" ]; then
      printf '\n  findings concentrate here — cut along these seams:\n'
      printf '%s\n' "$top" | while IFS="$(printf '\t')" read -r _n _p; do
        [ -n "${_p:-}" ] || continue
        printf '    %3d  %s\n' "$_n" "$_p"
      done
    fi ;;
esac
exit 0
