#!/bin/sh
# test_suite_hygiene.sh — the suite tree's own resource discipline (2026-10-25 incident).
#
# Two concurrent `tools/run-tests.sh` runs at --jobs 16 and 8 in sibling worktrees took a
# 10-core laptop to load 100, and the suites they killed left ~500 mktemp dirs (1 GB) under
# $TMPDIR, some a week old. Three properties keep that from recurring, and each is checked
# here structurally rather than asked for in prose:
#   R1 every suite (and tests/lib helper) that creates a temp dir traps EXIT *and* HUP/INT/TERM,
#      so a kill still runs the cleanup (an EXIT-only trap does not fire on signal death in dash)
#   R2 run-tests.sh defaults to --jobs 4 and clamps a higher request to HARNESS_TEST_JOBS_MAX
#      (default 4), with a warning naming the clamp
#   R3 run-tests.sh refuses to start while another run holds the per-machine lock (exit 5,
#      names the holder pid, does not wait), and reclaims a stale lock whose pid is gone
#
# Constraints (permanent-suite anti-pattern): no VERSION literal, no diff against main.
# The runner marks the suites it starts as NESTED (HARNESS_RUN_TESTS_NESTED=1) so a suite that
# calls the runner does not trip the machine lock; this suite tests that lock, so it unsets
# the marker on every runner call below.
# Zero deps: POSIX sh + grep + awk. Self-cleaning; never touches the real $TMPDIR lock.

set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RUNNER="$ROOT/tools/run-tests.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-hyg)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: temp-dir creators trap EXIT and HUP/INT/TERM ─────────────────────────────────────
_bad=""
for f in "$ROOT"/tests/*.sh "$ROOT"/tests/lib/*.sh; do
  [ -f "$f" ] || continue
  # a real mktemp CALL (not a comment that mentions mktemp)
  grep -q '^[^#]*mktemp' "$f" || continue
  grep -qE '^[[:space:]]*trap .*EXIT' "$f" || { _bad="$_bad ${f#$ROOT/}(no-EXIT-trap)"; continue; }
  grep -qE '^[[:space:]]*trap .*(INT|TERM)' "$f" || _bad="$_bad ${f#$ROOT/}(no-signal-trap)"
done
[ -z "$_bad" ] || fail "R1: mktemp users without full cleanup traps:$_bad"
pass "R1 every mktemp-using suite/helper traps EXIT and HUP/INT/TERM [trap_coverage]"

# ── R2: default jobs 4; higher request clamped to HARNESS_TEST_JOBS_MAX with a warning ────
grep -q '^jobs=4$' "$RUNNER" || fail "R2: run-tests.sh default is not jobs=4"
grep -q 'HARNESS_TEST_JOBS_MAX' "$RUNNER" || fail "R2: run-tests.sh does not read HARNESS_TEST_JOBS_MAX"
# Behavioural: a bogus suite path makes the runner stop at discovery (exit 4) — AFTER the
# clamp has printed, so the warning is observable without running any suite. The sandboxed
# TMPDIR keeps this run's machine lock away from the real one.
mkdir -p "$T/tmp"
_rc=0
env -u HARNESS_RUN_TESTS_NESTED TMPDIR="$T/tmp" HARNESS_TEST_JOBS_MAX=2 sh "$RUNNER" --jobs 9 "$T/no-such-suite.sh" >"$T/o2.txt" 2>"$T/e2.txt" || _rc=$?
grep -q 'exceeds HARNESS_TEST_JOBS_MAX=2' "$T/e2.txt" \
  || { cat "$T/e2.txt" >&2; fail "R2: --jobs 9 under HARNESS_TEST_JOBS_MAX=2 printed no clamp warning"; }
grep -q 'clamped to 2' "$T/e2.txt" || fail "R2: clamp warning does not name the clamped value"
[ "$_rc" -ne 0 ] || fail "R2: a bogus suite path exited zero"
_rc=0
env -u HARNESS_RUN_TESTS_NESTED TMPDIR="$T/tmp" sh "$RUNNER" --jobs 4 "$T/no-such-suite.sh" >/dev/null 2>"$T/e2b.txt" || _rc=$?
grep -q 'HARNESS_TEST_JOBS_MAX' "$T/e2b.txt" && fail "R2: --jobs 4 at the default cap was clamped (warning printed)"
pass "R2 default --jobs 4; a higher request is clamped to HARNESS_TEST_JOBS_MAX with a warning [jobs_cap]"

# ── R3: one run per machine — a live holder refuses (exit 5, names pid); a stale lock clears ─
_lock="$T/tmp/harness-run-tests.lock"
mkdir -p "$_lock"; printf '%s\n' "$$" >"$_lock/pid"      # this shell IS alive ⇒ live holder
_rc=0
env -u HARNESS_RUN_TESTS_NESTED TMPDIR="$T/tmp" sh "$RUNNER" --jobs 1 "$T/no-such-suite.sh" >"$T/o3.txt" 2>"$T/e3.txt" || _rc=$?
[ "$_rc" -eq 5 ] || { cat "$T/e3.txt" >&2; fail "R3: a held lock did not exit 5 (got $_rc)"; }
grep -q "pid $$" "$T/e3.txt" || fail "R3: refusal does not name the holder pid"
grep -qi 'not waiting' "$T/e3.txt" || fail "R3: refusal does not say it will not wait"
[ -d "$_lock" ] || fail "R3: the refused run removed the live holder's lock"
# stale: a pid that cannot be alive
printf '%s\n' 999999999 >"$_lock/pid"
_rc=0
env -u HARNESS_RUN_TESTS_NESTED TMPDIR="$T/tmp" sh "$RUNNER" --jobs 1 "$T/no-such-suite.sh" >/dev/null 2>"$T/e3b.txt" || _rc=$?
[ "$_rc" -ne 5 ] || { cat "$T/e3b.txt" >&2; fail "R3: a stale lock (dead pid) was treated as held"; }
[ ! -d "$_lock" ] || fail "R3: the runner left its own lock behind after exiting ($_rc)"
pass "R3 live holder ⇒ exit 5 naming the pid, no wait; stale lock reclaimed and released [machine_lock]"

echo "ALL PASSED (test_suite_hygiene.sh)"
