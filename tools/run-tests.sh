#!/bin/sh
# run-tests.sh — run the harness suites concurrently and report only what failed. (E99)
#
# Two costs motivated this, both measured on this repo at 27 suites:
#
#   wall clock — the suites run serially in 634s. They do not share state: every one builds
#                its fixture under its own `mktemp` dir and sandboxes HOME and CODEX_HOME
#                per case, and none writes into state/, specs/, progress/ or telemetry.jsonl.
#                Run 8-wide they finish in 183s with all 27 still passing.
#
#   tokens     — the Reviewer runs this command EVERY round and reads the result. The serial
#                suites emit ~77KB (~19k tokens) of chatter on a fully GREEN run, 32KB of it
#                from test_install.sh's per-run installer warnings. A green run tells the
#                Reviewer exactly one thing, so on success this prints one summary line.
#                On failure it prints the failing suites' output IN FULL — the diagnostic is
#                the whole point, and truncating it to save tokens would be a false economy.
#
# Usage:
#   tools/run-tests.sh [--jobs N] [--serial] [suite...]
#
#   --jobs N   concurrency (default 8). N=1 is identical to --serial.
#   --serial   run one at a time; use when bisecting a suspected cross-suite interaction.
#   suite...   specific suites to run (default: every tests/test_*.sh)
#
# Exit codes:
#   0  every suite passed
#   1  at least one suite failed (its full output is on stderr)
#   4  usage error / no suites found
#
# NOTE ON ISOLATION: concurrency here is a claim about the suites, not a wish. If a future
# suite starts writing to a shared path, it will fail intermittently under --jobs and pass
# under --serial. That asymmetry is the bug report: fix the suite's isolation rather than
# pinning the runner to serial, or the whole 3.5x goes away one suite at a time.

set -eu
LC_ALL=C; export LC_ALL

jobs=8
suites=""

usage() {
  printf 'usage: run-tests.sh [--jobs N] [--serial] [suite...]\n' >&2
  exit 4
}

while [ $# -gt 0 ]; do
  case "$1" in
    --jobs)   [ $# -ge 2 ] || usage
              case "$2" in ''|*[!0-9]*) usage ;; esac
              [ "$2" -ge 1 ] || usage
              jobs="$2"; shift 2 ;;
    --serial) jobs=1; shift ;;
    -h|--help) usage ;;
    -*) usage ;;
    *)  suites="$suites $1"; shift ;;
  esac
done

# ── grep-flavour probe (E99-F12) — WARN ONLY, once, before any suite runs ─────────────
#
# Every script here and most of the suites shell out to `grep`. On a machine where `grep`
# has been replaced — increasingly common, since it is a popular Homebrew/`cargo install`
# swap — local results can diverge from CI in a way NO SUITE HERE CAN CATCH, because the
# suites run under the same `grep` they would have to be testing. The cost is already on
# the record: two E99-F11 findings could not be reproduced or refuted locally, and both
# fixes shipped on documented `LC_ALL` semantics rather than on evidence.
#
# BEHAVIOURAL, NOT A VERSION STRING. The brand is a proxy; the divergence is the fact. A
# probe that feeds one invalid UTF-8 byte sequence through `grep` and demands the line back
# tests exactly what bites — and it costs one subprocess, needs no `--version` (some builds
# print it to stderr, some exit non-zero), and would also catch a future GNU/BSD regression
# that a name check would wave through. `--version` is read ONLY to make the message
# actionable, and its failure is silent.
#
# Run under the runner's own `LC_ALL=C`, which is the locale the suites actually see. The
# replacement that motivated this (ugrep 7.5.0) drops the line under every locale, C
# included, so this is not a locale misconfiguration the operator can dismiss.
#
# NEVER fails the run. A hard failure over a working `grep` would be a far worse false
# positive than the problem it reports, and a grep that cannot be found at all stays silent
# — the suites fail loudly on their own, and "your grep drops lines" would be a lie.
if command -v grep >/dev/null 2>&1; then
  # `if ... ; then` on the assignment: reads the same with or without `set -e`, and a grep
  # that exits non-zero here is itself a symptom, not a reason to abort the run.
  if _gf_n="$(printf 'a\303(b\n' | grep -c '' 2>/dev/null)"; then :; else _gf_n=""; fi
  if [ "$_gf_n" != "1" ]; then
    # `1{s/…/g;p;}`, NOT `1s/…/gp`: the `p` FLAG on an `s` command prints only when the
    # substitution actually matched, so a version line with no control characters — the
    # normal case — printed nothing and the warning silently lost its most useful half.
    if _gf_v="$(grep --version 2>/dev/null | sed -n '1{s/[[:cntrl:]]//g;p;}')"; then :; else _gf_v=""; fi
    _gf_sfx=""
    if [ -n "$_gf_v" ]; then _gf_sfx=" [reports: $_gf_v]"; fi
    printf '⚠️  grep (%s) drops lines containing invalid UTF-8 — it is neither GNU nor BSD grep, so suites here can pass or fail for reasons unrelated to the code (warn-only)%s\n' \
      "$(command -v grep)" "$_gf_sfx" >&2
    unset _gf_v _gf_sfx
  fi
  unset _gf_n
fi

# Resolve suites relative to the repo/harness root this script lives in, so the runner works
# from any cwd — the Reviewer does not always invoke it from the root.
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ -z "$suites" ]; then
  for s in "$root"/tests/test_*.sh; do
    [ -f "$s" ] || continue
    suites="$suites $s"
  done
fi

# shellcheck disable=SC2086
set -- $suites
[ $# -gt 0 ] || {
  printf 'run-tests: no suites found under %s/tests\n' "$root" >&2
  exit 4
}
total=$#

work="$(mktemp -d)" || { printf 'run-tests: mktemp failed\n' >&2; exit 4; }
trap 'rm -rf "$work"' EXIT INT TERM

# One child per suite, throttled by xargs -P. Each writes its own log and its own rc file,
# so nothing is interleaved and nothing is lost. `xargs` exit status is deliberately ignored
# (`|| true`): a non-zero child would abort the batch early and hide the other results — the
# rc files below are the source of truth for pass/fail.
printf '%s\n' "$@" | xargs -P "$jobs" -I _SUITE_ sh -c '
  suite="$1"; work="$2"
  base="$(basename "$suite")"
  if sh "$suite" >"$work/$base.log" 2>&1; then
    echo 0 >"$work/$base.rc"
  else
    echo $? >"$work/$base.rc"
  fi
' _ _SUITE_ "$work" || true

failed=0
failed_names=""
for suite in "$@"; do
  base="$(basename "$suite")"
  rc=1
  [ -f "$work/$base.rc" ] && rc="$(cat "$work/$base.rc")"
  # A suite that produced no rc file never ran (killed, or xargs aborted the batch). That is
  # a failure: silence must not read as success.
  if [ "$rc" -ne 0 ]; then
    failed=$((failed + 1))
    failed_names="$failed_names $base"
    {
      printf '\n===== FAILED (rc=%s): %s =====\n' "$rc" "$base"
      [ -f "$work/$base.log" ] && cat "$work/$base.log"
    } >&2
  fi
done

if [ "$failed" -eq 0 ]; then
  printf 'all %d suites passed (--jobs %d)\n' "$total" "$jobs"
  exit 0
fi

printf '\n%d of %d suites FAILED:%s\n' "$failed" "$total" "$failed_names" >&2
exit 1
