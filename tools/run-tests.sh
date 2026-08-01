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
