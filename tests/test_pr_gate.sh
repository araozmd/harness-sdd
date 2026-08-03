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

HEAD='aaaaaaa1111111222222233333334444444555555'
SHORT='aaaaaaa'
SINCE='2026-01-01T00:00:00Z'
LATER='2026-06-01T00:00:00Z'
BOT='chatgpt-codex-connector'

# _resolve <dir> <clean|findings> — write the watcher artifacts so `wait-for-codex.sh
# evaluate` reports a RESOLVED round. The gate refuses to look at blocking.json until a
# review has provably landed, so every verdict fixture needs these.
_resolve() {
  _d="$WORK/$1"; mkdir -p "$_d"
  printf '%s\n' "$SINCE" >"$_d/trigger-ts.txt"
  if [ "$2" = clean ]; then
    printf '[]' >"$_d/review-comments.json"
    printf '{"headRefOid":"%s","reviews":[{"author":{"login":"%s"},"submittedAt":"%s","body":"Reviewed commit: %s"}]}' \
      "$HEAD" "$BOT" "$LATER" "$SHORT" >"$_d/pr.json"
  else
    printf '[{"id":1,"user":{"login":"%s"},"commit_id":"%s","created_at":"%s","body":"P1 finding"}]' \
      "$BOT" "$HEAD" "$LATER" >"$_d/review-comments.json"
    printf '{"headRefOid":"%s","reviews":[]}' "$HEAD" >"$_d/pr.json"
  fi
}

# mk <dir> <blocking-json> [clean|findings] — a RESOLVED round with the given blocking set
mk() {
  mkdir -p "$WORK/$1"
  _resolve "$1" "${3:-clean}"
  printf '%s' "$2" >"$WORK/$1/blocking.json"
}

# ── R1: zero blocking findings ends the loop, at ANY round ────────────────────
# The regression this whole feature exists for: PR #86 rounds 6-8 were clean and the loop
# ran to 12; PR #89 was clean in all three rounds and still produced three P2 commits.
mk clean '[]'
[ "$(verdict "$WORK/clean" 1 4)" = merge ] || fail "R1: clean round-1 is not 'merge'"
[ "$(rc "$WORK/clean" 1 4)" -eq 0 ]        || fail "R1: clean round-1 exit is not 0"
[ "$(verdict "$WORK/clean" 6 4)" = merge ] || fail "R1: clean round PAST the cap must still be 'merge', not needs-human"
[ "$(verdict "$WORK/clean" 3 4)" = merge ] || fail "R1: clean round-3 is not 'merge'"
pass "R1 zero blocking findings ⇒ merge at any round"

# ── R2: a non-blocking-only PR is CLEAN, because blocking.json is already filtered ──
# Guards the exact drift: non-blocking chatter must never turn into another round of work.
# The fixture uses P2/nit because those are non-blocking under the SHIPPED default; the
# property under test is "empty blocking.json ⇒ merge whatever comments.json holds", which
# holds for any configured threshold. This tool consumes the filtered file and never
# re-derives the severity set, so a repo configuring P0,P1,P2 changes what the LOOP writes
# into blocking.json, not what this gate does with it.
mk p2only '[]'
cat >"$WORK/p2only/comments.json" <<'JSON'
[{"id":1,"severity":"P2","body":"nit: rename this"},
 {"id":2,"severity":"nit","body":"stray whitespace"}]
JSON
[ "$(verdict "$WORK/p2only" 2 4)" = merge ] \
  || fail "R2: a PR carrying only P2/nit comments must be 'merge'"
pass "R2 P2/nit-only PR ⇒ merge (never another fix round)"

# ── R3/R4/R5: with real blocking findings the verdict is a pure budget decision ──
mk blocked '[{"id":9,"severity":"P1","body":"real"}]' findings
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
# (A MISSING blocking.json is not covered here — it is legitimate on a clean round and is
# split across R6c/R6d/R6e by what the review state actually was.)
mk garbage 'not json at all'
[ "$(rc "$WORK/garbage" 1 4)" -eq 4 ] || fail "R6: unparseable blocking.json is not exit 4"

mk object '{"findings":[]}'
[ "$(rc "$WORK/object" 1 4)" -eq 4 ]  || fail "R6: a non-array blocking.json is not exit 4"
[ "$(verdict "$WORK/object" 1 4)" != merge ] || fail "R6: a non-array blocking.json returned 'merge'"

[ "$(rc "$WORK/missing-dir-xyz" 1 4)" -eq 4 ] || fail "R6: a missing round dir is not exit 4"
pass "R6 unreadable input fails closed (never 'merge')"

# ── R6b: a round where NO REVIEW LANDED is never a merge ──────────────────────
# Found on this tool's own PR #90: Codex replied 54s inside the 900s ceiling and the
# 60s-interval watcher missed it, so the round timed out with blocking.json = []. The
# first version of the gate answered `merge` there — an empty blocking set read as a
# clean review when it actually meant "no review at all".
mkdir -p "$WORK/timedout"
printf '%s\n' "$SINCE" >"$WORK/timedout/trigger-ts.txt"
printf '[]' >"$WORK/timedout/review-comments.json"
printf '{"headRefOid":"%s","reviews":[]}' "$HEAD" >"$WORK/timedout/pr.json"   # no banner ⇒ pending
printf '[]' >"$WORK/timedout/blocking.json"
[ "$(verdict "$WORK/timedout" 1 4)" = unresolved ] \
  || fail "R6b: a timed-out round with an empty blocking.json must be 'unresolved', not 'merge'"
[ "$(rc "$WORK/timedout" 1 4)" -eq 9 ] || fail "R6b: 'unresolved' exit is not 9"
[ "$(verdict "$WORK/timedout" 1 4)" != merge ] || fail "R6b: a round with no review returned 'merge'"
pass "R6b no review landed ⇒ unresolved (never merge)"

# ── R6c/R6d/R6e: the three P1s Codex raised on PR #90 round 2 ────────────────
# R6c — a clean review has NO blocking.json. The runbook tells the driver to skip
# classification on watcher exit 3, so requiring the file sent every banner/reaction
# clean review to needs-human instead of merging.
mkdir -p "$WORK/cleannofile"; _resolve cleannofile clean      # deliberately no blocking.json
[ "$(verdict "$WORK/cleannofile" 1 4)" = merge ] \
  || fail "R6c: a resolved CLEAN round without blocking.json must be 'merge'"
[ "$(verdict "$WORK/cleannofile" 4 4)" = merge ] \
  || fail "R6c: a clean round AT THE CAP must be 'merge', not needs-human"
pass "R6c clean review without blocking.json ⇒ merge (incl. at the cap)"

# R6d — inline findings but no blocking.json: severities were never determined, so
# nothing proves they are non-blocking. Fail closed rather than merge.
mkdir -p "$WORK/unclassified"; _resolve unclassified findings  # deliberately no blocking.json
[ "$(rc "$WORK/unclassified" 1 4)" -eq 4 ] \
  || fail "R6d: findings with no blocking.json must fail closed (exit 4)"
[ "$(verdict "$WORK/unclassified" 1 4)" != merge ] \
  || fail "R6d: unclassified findings returned 'merge'"
pass "R6d inline findings, unclassified ⇒ fail closed"

# R6e — a blocking round must NOT probe review state. After a fixer pushes, step 6
# re-fetches pr.json, so the cached head moves past the head the findings were filed
# against and the evaluator reports `pending`. Probing there returned `unresolved` for
# every ordinary blocking round.
mkdir -p "$WORK/movedhead"
printf '%s\n' "$SINCE" >"$WORK/movedhead/trigger-ts.txt"
printf '[{"id":1,"user":{"login":"%s"},"commit_id":"OLDHEAD","created_at":"%s","body":"P1"}]' \
  "$BOT" "$LATER" >"$WORK/movedhead/review-comments.json"
printf '{"headRefOid":"NEWHEAD","reviews":[]}' >"$WORK/movedhead/pr.json"
printf '[{"id":1,"severity":"P1"}]' >"$WORK/movedhead/blocking.json"
[ "$(verdict "$WORK/movedhead" 1 4)" = fix ] \
  || fail "R6e: a blocking round whose cached head moved must still be 'fix', not 'unresolved'"
[ "$(verdict "$WORK/movedhead" 4 4)" = needs-human ] \
  || fail "R6e: a blocking round at the cap must be 'needs-human'"
pass "R6e blocking round never probes review state (survives the post-fix head refresh)"

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
  # EXACTLY ONE call per round. A second call (step 6, after the fixers push) re-reads the
  # SAME blocking.json — the fix commits do not rewrite it — so it returns fix/escalate
  # again and routes the driver back through step 5 on the stale set, forever.
  _calls="$(grep -cF 'tools/pr-gate.sh evaluate' "$f")"
  [ "$_calls" -eq 1 ] \
    || fail "R8: $f calls the pr-gate $_calls times — it must be asked exactly once per round"
done
pass "R8 both pr-loop copies call the gate exactly once and resume the round counter"

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
