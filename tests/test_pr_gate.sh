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

# ── R13-R17: the strict-shell gate (E99-F135) ─────────────────────────────────
# Every suite declares `#!/bin/sh`, and `sh` is bash on macOS and dash on Debian/Ubuntu.
# The runner therefore executes the suites under the strictest shell it can probe, parse-
# checks everything first, and NAMES the shell it used. These assertions are about all
# three, and about the allowlist failing closed.
RUN="$WORK/t/tools/run-tests.sh"
DASH="$(command -v dash 2>/dev/null || true)"

# R13: the summary names the shell — path AND identification — and stays one line.
# `all N suites passed` alone is ambiguous precisely because `sh` differs per machine.
out="$(sh "$RUN" --jobs 4 2>&1)" || fail "R13: green run exited non-zero"
[ "$(echo "$out" | wc -l | tr -d ' ')" -eq 1 ] || fail "R13: the summary is no longer one line: $out"
echo "$out" | grep -q 'all 2 suites passed' || fail "R13: the summary lost its 'all N suites passed' prefix"
# The shell must be an absolute PATH, so the reader can check it themselves.
echo "$out" | grep -q ' (/' || fail "R13: the summary names no absolute shell path: $out"
# ...and an identification, in brackets, that is either established or honestly absent.
echo "$out" | grep -qE '\[[^]]+\]' || fail "R13: the summary carries no shell identification: $out"
pass "R13 the summary names the shell it used (path + identification), in one line"

if [ -z "$DASH" ]; then
  skip_msg="dash not installed; the strict shell falls back to sh"
  echo "skip - R14-R16 ($skip_msg)"
else
  # R14: a RUNTIME bashism fails the run and NAMES the suite. `[[ ]]` PARSES under dash
  # and fails only when executed — which is the whole reason a parse gate alone is not
  # enough. Under bash-as-sh this suite passes, so it is exactly the environment-dependent
  # green the gate exists to convert into a stated one.
  printf '#!/bin/sh\n[[ -n "x" ]] && exit 0\nexit 1\n' >"$WORK/t/tests/test_runtime.sh"
  if out="$(sh "$RUN" --jobs 4 2>&1)"; then
    fail "R14: a suite using [[ ]] passed — it was not executed under a strict shell"
  fi
  echo "$out" | grep -q 'test_runtime.sh' || fail "R14: the runtime-bashism suite was not named: $out"
  rm -f "$WORK/t/tests/test_runtime.sh"
  pass "R14 a RUNTIME bashism fails the run and names the suite"

  # R15: a PARSE error is caught by the pre-flight BEFORE anything executes. Proven by
  # side effect, not by reading the message: a second suite writes a marker when it runs,
  # and the marker must not exist.
  printf '#!/bin/sh\nif true; then\n  echo hi\n' >"$WORK/t/tests/test_parse.sh"
  printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$WORK/ran.marker" >"$WORK/t/tests/test_marker.sh"
  rm -f "$WORK/ran.marker"
  _rc=0; out="$(sh "$RUN" --jobs 4 2>&1)" || _rc=$?
  [ "$_rc" -eq 3 ] || fail "R15: a parse error did not exit 3 (got $_rc)"
  echo "$out" | grep -q 'test_parse.sh' || fail "R15: the unparseable suite was not named: $out"
  [ ! -f "$WORK/ran.marker" ] || fail "R15: suites executed despite the pre-flight failing"
  pass "R15 the -n pre-flight fails the run before any suite executes"

  # R16: an ALLOWLISTED suite is exempt from EXECUTING under dash — never from parsing
  # under it. An exemption that also skipped the parse check would be the unnamed skip
  # this list exists to prevent.
  printf '# known-broken under dash: test_parse.sh — E99-F999\n' >"$WORK/t/tests/dash-allowlist.txt"
  rm -f "$WORK/ran.marker"
  _rc=0; out="$(sh "$RUN" --jobs 4 2>&1)" || _rc=$?
  [ "$_rc" -eq 3 ] || fail "R16: an allowlisted suite skipped the parse pre-flight (got $_rc)"
  echo "$out" | grep -q 'test_parse.sh' || fail "R16: the allowlisted unparseable suite was not named: $out"
  [ ! -f "$WORK/ran.marker" ] || fail "R16: suites executed despite an allowlisted parse failure"
  rm -f "$WORK/t/tests/test_parse.sh"

  # R16b: and the exemption is never silent — every run names what did not face the gate,
  # on stderr, AND counts it in the summary on STDOUT. A caller that captures only stdout
  # must not read "all N suites passed (dash)" when some of those N never faced dash.
  printf '#!/bin/sh\nexit 0\n' >"$WORK/t/tests/test_parse.sh"
  out="$(sh "$RUN" --jobs 4 2>&1)" || fail "R16b: the allowlisted green tree exited non-zero"
  echo "$out" | grep -q 'test_parse.sh' \
    || fail "R16b: an exempt suite ran without being named — that is an invisible skip: $out"
  sout="$(sh "$RUN" --jobs 4 2>/dev/null)" || fail "R16b: the allowlisted green tree exited non-zero"
  echo "$sout" | grep -q '1 exempt' \
    || fail "R16b: stdout alone does not disclose the exemption: $sout"
  rm -f "$WORK/t/tests/test_parse.sh" "$WORK/t/tests/test_marker.sh" "$WORK/ran.marker"
  pass "R16 an allowlisted suite still gets the parse pre-flight, and is named on every run"
fi

# R17: the allowlist fails CLOSED. An entry that names no issue, or names a suite that
# does not exist, is a usage error — never a silent exemption.
printf '# known-broken under dash: test_a.sh\n' >"$WORK/t/tests/dash-allowlist.txt"
_rc=0; sh "$RUN" --jobs 4 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 4 ] || fail "R17: an allowlist entry with no issue id was accepted (got $_rc)"
printf '# known-broken under dash: test_ghost.sh — E99-F999\n' >"$WORK/t/tests/dash-allowlist.txt"
_rc=0; sh "$RUN" --jobs 4 >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 4 ] || fail "R17: an allowlist entry naming a non-existent suite was accepted (got $_rc)"
# ...and VALIDATION IS FILE-WIDE, so a subset run catches the stale entry too. Narrowing
# this to the selection would let the list rot: only a full run would ever complain.
_rc=0; sh "$RUN" --jobs 4 "$WORK/t/tests/test_a.sh" >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 4 ] \
  || fail "R17: a stale allowlist entry went unreported on a subset run (got $_rc) — the list can rot"
rm -f "$WORK/t/tests/dash-allowlist.txt"
pass "R17 the dash allowlist fails closed: no unnamed and no stale exemptions"

# ── R17b: the exemption set is the allowlist INTERSECTED WITH THE SELECTION ───
# Applied file-wide, the warning does not merely miscount — it asserts "ran under
# /bin/sh" about a suite that never ran at all, in the one line this feature exists to
# make trustworthy. Asserted on the ABSENCE OF THE SUITE'S NAME, not on the number: a
# count-based guard passes for the wrong reason too easily.
printf '# known-broken under dash: test_b.sh — E99-F999\n' >"$WORK/t/tests/dash-allowlist.txt"
out="$(sh "$RUN" --jobs 4 "$WORK/t/tests/test_a.sh" 2>&1)" \
  || fail "R17b: selecting one suite with another allowlisted exited non-zero"
echo "$out" | grep -q 'test_b.sh' \
  && fail "R17b: reported an UNSELECTED suite as exempt — it never ran: $out"
echo "$out" | grep -q 'exempt' \
  && fail "R17b: claimed an exemption on a run where no selected suite was exempt: $out"
# Positive control — without it, the two assertions above would also pass if the warning
# had simply been broken or removed. A selected exempt suite must still be named AND
# counted, so the silence above is specifically about the intersection.
out="$(sh "$RUN" --jobs 4 "$WORK/t/tests/test_b.sh" 2>&1)" \
  || fail "R17b control: selecting the allowlisted suite exited non-zero"
echo "$out" | grep -q 'test_b.sh' \
  || fail "R17b control: a SELECTED exempt suite was not named — the warning is broken: $out"
echo "$out" | grep -q '1 exempt' \
  || fail "R17b control: a SELECTED exempt suite was not counted: $out"
rm -f "$WORK/t/tests/dash-allowlist.txt"
pass "R17b exemptions follow the selection; validation stays file-wide"

# ── R17c: an exemption must go INTO a genuinely different interpreter ─────────
# Falling back to the host `sh` unconditionally was wrong in both directions, and the
# second one is the case that matters:
#   * macOS with no dash → the strict shell IS /bin/sh, so the warning read
#     "ran under /bin/sh, not /bin/sh" — a self-contradiction printed as a finding.
#   * Debian/Ubuntu → /bin/sh IS dash, so an allowlisted, genuinely dash-incompatible
#     suite still ran under dash and still failed while being reported exempt. The one
#     host where the exemption exists to help is the one where it did nothing.
# Assert the INVARIANT rather than a specific shell, because which shells exist is a
# property of the host and this must hold on all of them: the warning may never name the
# same interpreter on both sides of "ran under X, not Y".
#
# ⚠️ THIS TESTS THE RULE, NOT THIS HOST — and the first version of it did the opposite.
# Asserting the invariant against a plain run passes here for an irrelevant reason: on
# macOS `/bin/sh` is bash, so even the WRONG selection yields a fallback that differs from
# dash, and the mutation survived. The defect only manifests where the host `sh` IS the
# strict shell, so the test has to CREATE that condition rather than hope for it.
#
# So: drive the selection block itself under a PATH whose only shell is dash. `sh` then
# resolves to the strict shell, and a correct selector must refuse it — either finding a
# genuinely more permissive shell or reporting none.
_sel="$WORK/sel.sh"
sed -n '/^_realsh() {/,/^# .fallback_sh. may legitimately/p' "$RUN" >"$_sel" \
  || fail "R17c: could not extract the fallback-selection block from run-tests.sh"
[ -s "$_sel" ] || fail "R17c: the extracted fallback-selection block is empty — the anchors moved"
_onlydash="$WORK/onlydash"
mkdir -p "$_onlydash"
_dash="$(command -v dash 2>/dev/null)" || _dash=""
if [ -n "$_dash" ]; then
  ln -sf "$_dash" "$_onlydash/sh"
  {
    echo 'strict_sh="$(command -v sh)"'
    cat "$_sel"
    echo 'printf "%s|%s\n" "$strict_sh" "$fallback_sh"'
  } >"$WORK/probe.sh"
  _got="$(PATH="$_onlydash:/usr/bin:/bin/NO_SHELLS" "$_dash" "$WORK/probe.sh" 2>/dev/null)" || _got=""
  _s="${_got%%|*}"; _f="${_got##*|}"
  [ -n "$_s" ] || fail "R17c: the selection probe produced no strict shell"
  [ "$_f" = "$_s" ] \
    && fail "R17c: on a host whose only shell IS the strict one, the selector still chose it as the FALLBACK ($_f) — an allowlisted suite would run under the very shell it is exempt from, while being reported exempt"
  if [ -n "$_f" ]; then
    _fr="$(readlink -f "$_f" 2>/dev/null || printf '%s' "$_f")"
    _sr="$(readlink -f "$_s" 2>/dev/null || printf '%s' "$_s")"
    [ "$_fr" = "$_sr" ] \
      && fail "R17c: the fallback resolves to the SAME interpreter as the strict shell ($_fr) under a different name — comparing spellings is not comparing interpreters"
  fi
fi
rm -f "$WORK/t/tests/dash-allowlist.txt"
pass "R17c an exemption goes into a genuinely different shell, or is reported unhonourable"

# R18: the shipped allowlist is EMPTY of entries. Every suite in this repo runs under the
# strict shell today; if that ever changes, the entry — and this assertion — must be
# changed deliberately, with an issue id attached.
if [ -f "$SRC/tests/dash-allowlist.txt" ]; then
  _entries="$(grep -c '^# known-broken under dash:' "$SRC/tests/dash-allowlist.txt" || true)"
  [ "$_entries" = "0" ] \
    || fail "R18: the shipped dash allowlist carries $_entries entr(y|ies) — every one is a suite not facing the gate"
fi
pass "R18 the shipped dash allowlist is empty"

echo "test_pr_gate.sh: all assertions passed"
