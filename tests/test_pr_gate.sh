#!/bin/sh
# test_pr_gate.sh — the deterministic pr-loop verdict + the concurrent suite runner (E99)
#
# Both tools exist to remove a judgement call that the loop kept getting wrong, so the
# assertions here are about the VERDICT and the EXIT CODE, never about phrasing.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
GATE="$SRC/tools/pr-gate.sh"
RUNNER="$SRC/tools/run-tests.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

# rc <round-dir> <round> <max> — echo the exit code, never abort under `set -e`
rc() {
  _d="$1"; _r="$2"; _m="$3"
  sh "$GATE" evaluate "$_d" --round "$_r" --max-rounds "$_m" >/dev/null 2>&1 && echo 0 || echo $?
}
verdict() {
  _d="$1"; _r="$2"; _m="$3"
  sh "$GATE" evaluate "$_d" --round "$_r" --max-rounds "$_m" 2>/dev/null || true
}

mk() { mkdir -p "$WORK/$1"; printf '%s' "$2" >"$WORK/$1/blocking.json"; }

# ── R1: zero blocking findings ends the loop, at ANY round ────────────────────
# The regression this whole feature exists for: PR #86 rounds 6-8 were clean and the loop
# ran to 12; PR #89 was clean in all three rounds and still produced three P2 commits.
mk clean '[]'
[ "$(verdict "$WORK/clean" 1 4)" = merge ] || fail "R1: clean round-1 is not 'merge'"
[ "$(rc "$WORK/clean" 1 4)" -eq 0 ]        || fail "R1: clean round-1 exit is not 0"
[ "$(verdict "$WORK/clean" 6 4)" = merge ] || fail "R1: clean round PAST the cap must still be 'merge', not needs-human"
[ "$(verdict "$WORK/clean" 3 4)" = merge ] || fail "R1: clean round-3 is not 'merge'"
pass "R1 zero blocking findings ⇒ merge at any round"

# ── R2: a P2-only PR is CLEAN, because blocking.json is already severity-filtered ──
# Guards the exact drift: non-blocking chatter must never turn into another round of work.
mkdir -p "$WORK/p2only"
printf '%s' '[]' >"$WORK/p2only/blocking.json"
cat >"$WORK/p2only/comments.json" <<'JSON'
[{"id":1,"severity":"P2","body":"nit: rename this"},
 {"id":2,"severity":"nit","body":"stray whitespace"}]
JSON
[ "$(verdict "$WORK/p2only" 2 4)" = merge ] \
  || fail "R2: a PR carrying only P2/nit comments must be 'merge'"
pass "R2 P2/nit-only PR ⇒ merge (never another fix round)"

# ── R3/R4/R5: with real blocking findings the verdict is a pure budget decision ──
mk blocked '[{"id":9,"severity":"P1","body":"real"}]'
[ "$(verdict "$WORK/blocked" 1 4)" = fix ]          || fail "R3: round 1 of 4 is not 'fix'"
[ "$(rc "$WORK/blocked" 1 4)" -eq 6 ]               || fail "R3: 'fix' exit is not 6"
[ "$(verdict "$WORK/blocked" 2 4)" = fix ]          || fail "R3: round 2 of 4 is not 'fix'"
[ "$(verdict "$WORK/blocked" 3 4)" = escalate ]     || fail "R4: round max-1 is not 'escalate'"
[ "$(rc "$WORK/blocked" 3 4)" -eq 7 ]               || fail "R4: 'escalate' exit is not 7"
[ "$(verdict "$WORK/blocked" 4 4)" = needs-human ]  || fail "R5: the cap round is not 'needs-human'"
[ "$(rc "$WORK/blocked" 4 4)" -eq 8 ]               || fail "R5: 'needs-human' exit is not 8"
[ "$(verdict "$WORK/blocked" 9 4)" = needs-human ]  || fail "R5: past the cap is not 'needs-human'"
pass "R3-R5 blocking findings ⇒ fix / escalate / needs-human by budget"

# ── R6: fail closed. Nothing unreadable may ever come back 'merge' ────────────
mkdir -p "$WORK/nofile"
[ "$(rc "$WORK/nofile" 1 4)" -eq 4 ]  || fail "R6: a missing blocking.json is not exit 4"
[ "$(verdict "$WORK/nofile" 1 4)" != merge ] || fail "R6: a missing blocking.json returned 'merge'"

mk garbage 'not json at all'
[ "$(rc "$WORK/garbage" 1 4)" -eq 4 ] || fail "R6: unparseable blocking.json is not exit 4"

mk object '{"findings":[]}'
[ "$(rc "$WORK/object" 1 4)" -eq 4 ]  || fail "R6: a non-array blocking.json is not exit 4"
[ "$(verdict "$WORK/object" 1 4)" != merge ] || fail "R6: a non-array blocking.json returned 'merge'"

[ "$(rc "$WORK/missing-dir-xyz" 1 4)" -eq 4 ] || fail "R6: a missing round dir is not exit 4"
pass "R6 unreadable input fails closed (never 'merge')"

# ── R7: both counters are required and must be numeric ────────────────────────
sh "$GATE" evaluate "$WORK/clean" --round 1 >/dev/null 2>&1 && fail "R7: missing --max-rounds accepted"
sh "$GATE" evaluate "$WORK/clean" --max-rounds 4 >/dev/null 2>&1 && fail "R7: missing --round accepted"
sh "$GATE" evaluate "$WORK/clean" --round x --max-rounds 4 >/dev/null 2>&1 && fail "R7: non-numeric --round accepted"
sh "$GATE" evaluate "$WORK/clean" --round 0 --max-rounds 4 >/dev/null 2>&1 && fail "R7: --round 0 accepted"
sh "$GATE" >/dev/null 2>&1 && fail "R7: no arguments accepted"
pass "R7 usage errors rejected"

# ── R8: the runbook must actually CALL the gate, in BOTH maintained copies ────
# The source-layout command and the installer heredoc are hand-synced; a fix applied to one
# and not the other ships broken to either the harness itself or to every consumer.
for f in "$SRC/.claude/commands/sdd-pr-loop.md" "$SRC/harness-install.sh"; do
  grep -qF 'tools/pr-gate.sh evaluate' "$f" || fail "R8: $f does not invoke the pr-gate"
  grep -qF 'budget for the **PR**' "$f"     || fail "R8: $f does not resume the round counter"
done
pass "R8 both maintained pr-loop copies call the gate and resume the round counter"

# ── R9: the suite runner reports green quietly and red loudly ─────────────────
mkdir -p "$WORK/t/tests" "$WORK/t/tools"
cp "$RUNNER" "$WORK/t/tools/run-tests.sh"
printf '#!/bin/sh\necho "chatty green output"\nexit 0\n' >"$WORK/t/tests/test_a.sh"
printf '#!/bin/sh\necho "more chatter"\nexit 0\n'        >"$WORK/t/tests/test_b.sh"

out="$(sh "$WORK/t/tools/run-tests.sh" --jobs 4 2>&1)" || fail "R9: green run exited non-zero"
echo "$out" | grep -q 'all 2 suites passed' || fail "R9: green run did not print the summary"
echo "$out" | grep -q 'chatty green output' && fail "R9: green run leaked a passing suite's output"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 1 ] || fail "R9: green run printed more than one line"
pass "R9 green run: one summary line, no per-suite chatter"

printf '#!/bin/sh\necho "DIAGNOSTIC-NEEDLE"\nexit 3\n' >"$WORK/t/tests/test_c.sh"
if out="$(sh "$WORK/t/tools/run-tests.sh" --jobs 4 2>&1)"; then
  fail "R10: a failing suite did not fail the run"
fi
echo "$out" | grep -q 'DIAGNOSTIC-NEEDLE' || fail "R10: the failing suite's output was not surfaced"
echo "$out" | grep -q 'rc=3'              || fail "R10: the failing suite's exit code was not reported"
echo "$out" | grep -q 'test_c.sh'         || fail "R10: the failing suite was not named"
echo "$out" | grep -q 'chatty green output' && fail "R10: a PASSING suite's output leaked on a red run"
pass "R10 red run: fails, names the suite, surfaces its output in full"

# ── R11: --serial and --jobs agree on the verdict ─────────────────────────────
rm -f "$WORK/t/tests/test_c.sh"
sh "$WORK/t/tools/run-tests.sh" --serial >/dev/null 2>&1 || fail "R11: --serial disagreed with --jobs on a green tree"
printf '#!/bin/sh\nexit 1\n' >"$WORK/t/tests/test_c.sh"
sh "$WORK/t/tools/run-tests.sh" --serial >/dev/null 2>&1 && fail "R11: --serial passed a red tree"
pass "R11 --serial and --jobs agree"

# ── R12: an explicit suite list overrides discovery ───────────────────────────
rm -f "$WORK/t/tests/test_c.sh"
sh "$WORK/t/tools/run-tests.sh" "$WORK/t/tests/test_a.sh" >/dev/null 2>&1 \
  || fail "R12: an explicit suite list was not honoured"
sh "$WORK/t/tools/run-tests.sh" --jobs 0 >/dev/null 2>&1 && fail "R12: --jobs 0 accepted"
pass "R12 explicit suite list honoured; bad --jobs rejected"

echo "test_pr_gate.sh: all assertions passed"
