#!/bin/sh
# test_waves.sh — E36-F05 derived waves and critical path (`next-task.mjs --waves`).
#
# The `--waves --json` envelope is the contract E36-F07 consumes, so it is asserted field
# by field. Every fixture lists its features in NON-canonical input order, so an
# implementation that leaks input order reds. Fixtures live under mktemp; the live board
# is never read by a `--waves` case.
#
# Notation: `A -> B` means "B depends on A" (A unblocks B; chains read root first).
#
# Suite-wide constraints (permanent-suite anti-pattern): no literal VERSION, no `git diff`
# of a DO-NOT-TOUCH file against main — protected files are cksum'd before and after.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TOOL="$ROOT/tools/next-task.mjs"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-waves.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); echo "PASS: $*"; }

protected_cksums() {
  cksum "$ROOT/store/tasks.schema.json" "$ROOT/tools/task-diagnostics.py" "$ROOT/init.sh"
}
PROTECTED_BEFORE=$(protected_cksums)
# R9: every run_tool call records the fixture board's cksum before and after itself; a
# mismatch is appended to WRITES and asserted empty by test_read_only_and_builtins.
WRITES="$TMP/writes.log"
RUNS="$TMP/runs.log"
: >"$WRITES"
: >"$RUNS"

write_config() {
  approval=$1 identity=${2-} manifest=${3-}
  cat >"$TMP/config.yaml" <<EOF
workflow:
  require_spec_approval: $approval
  identity: "$identity"
umbrella:
  manifest: "$manifest"
EOF
}

write_board() {
  cat >"$TMP/tasks.json"
}

run_tool() {
  _before=$(cksum <"$TMP/tasks.json")
  _rc=0
  node "$TOOL" --tasks "$TMP/tasks.json" --config "$TMP/config.yaml" "$@" || _rc=$?
  _after=$(cksum <"$TMP/tasks.json")
  echo "$*" >>"$RUNS"
  [ "$_before" = "$_after" ] || echo "board changed by: $*" >>"$WRITES"
  return "$_rc"
}

json_field() {
  python3 -c 'import json,sys; x=json.load(sys.stdin); print(eval(sys.argv[1], {"x":x}))' "$1"
}

# expect_usage_error <case-label> <detail-substring> <args...>: exit 2, usage-error
# envelope on stdout, non-empty stderr, and reason.detail names THIS case's rule — so
# each row is rejected by exactly one parse rule, not by whichever fires first.
expect_usage_error() {
  _label=$1 _want=$2
  shift 2
  _rc=0
  run_tool "$@" >"$TMP/usage.out" 2>"$TMP/usage.err" || _rc=$?
  [ "$_rc" = 2 ] || fail "R1 [$_label]: expected exit 2, got $_rc"
  [ "$(json_field 'x["outcome"]' <"$TMP/usage.out")" = error ] || fail "R1 [$_label]: outcome is not error"
  [ "$(json_field 'x["reason"]["code"]' <"$TMP/usage.out")" = usage-error ] ||
    fail "R1 [$_label]: reason.code is not usage-error"
  [ -s "$TMP/usage.err" ] || fail "R1 [$_label]: no stderr diagnostic"
  _detail=$(json_field 'x["reason"]["detail"]' <"$TMP/usage.out")
  case $_detail in
    *"$_want"*) ;;
    *) fail "R1 [$_label]: detail '$_detail' does not name '$_want'" ;;
  esac
}

# A valid acyclic board containing epic E1 (E1-F2 depends on E1-F1), listed in reverse.
ACYCLIC='{"project":"fixture","epics":[{"id":"E1","title":"one","status":"planned","features":[
  {"id":"E1-F2","title":"second","status":"pending","sdd":true,"spec_path":"specs/f2/","depends_on":["E1-F1"]},
  {"id":"E1-F1","title":"first","status":"pending","sdd":true,"spec_path":"specs/f1/"}
]}]}'

test_cli_contract() {
  write_config true
  printf '%s\n' "$ACYCLIC" | write_board
  run_tool --waves >/dev/null 2>&1 || fail "R1: --waves rejected"
  run_tool --waves --json >/dev/null 2>&1 || fail "R1: --waves --json rejected"
  run_tool --waves --epic E1 >/dev/null 2>&1 || fail "R1: --waves --epic E1 rejected"
  run_tool --json --epic E1 --waves >/dev/null 2>&1 || fail "R1: flag order --json --epic E1 --waves rejected"
  expect_usage_error waves+feature 'mutually exclusive' --waves --feature E1-F1
  expect_usage_error feature+waves 'mutually exclusive' --feature E1-F1 --waves
  expect_usage_error waves+mine 'mutually exclusive' --waves --mine
  expect_usage_error epic-alone '--epic requires --waves' --epic E1
  expect_usage_error epic-with-mine '--epic requires --waves' --mine --epic E1
  expect_usage_error epic-no-value '--epic requires a non-empty value' --waves --epic
  expect_usage_error epic-empty '--epic requires a non-empty value' --waves --epic ''
  expect_usage_error epic-flag-value '--epic requires a non-empty value' --waves --epic --json
  expect_usage_error epic-foo 'invalid epic id foo' --waves --epic foo
  expect_usage_error epic-feature-id 'invalid epic id E1-F1' --waves --epic E1-F1
  expect_usage_error epic-lowercase 'invalid epic id e1' --waves --epic e1
  expect_usage_error epic-trailing 'invalid epic id E1x' --waves --epic E1x
  expect_usage_error waves-dup 'duplicate option --waves' --waves --waves
  expect_usage_error epic-dup 'duplicate option --epic' --waves --epic E1 --epic E1
  # Regression: --json stays an exact no-op in board, mine and target modes.
  a=$(run_tool) || fail "R1: board mode failed"
  b=$(run_tool --json) || fail "R1: board mode --json failed"
  [ "$a" = "$b" ] || fail "R1: --json is not a no-op in board mode"
  [ "$(printf '%s' "$a" | json_field 'x["mode"]')" = board ] || fail "R1: board mode envelope mode changed"
  a=$(run_tool --feature E1-F1) || fail "R1: target mode failed"
  b=$(run_tool --json --feature E1-F1) || fail "R1: target mode --json failed"
  [ "$a" = "$b" ] || fail "R1: --json is not a no-op in target mode"
  [ "$(printf '%s' "$a" | json_field 'x["mode"]')" = target ] || fail "R1: target mode envelope mode changed"
  a=$(run_tool --mine) || fail "R1: mine mode failed"
  b=$(run_tool --mine --json) || fail "R1: mine mode --json failed"
  [ "$a" = "$b" ] || fail "R1: --json is not a no-op in mine mode"
  [ "$(printf '%s' "$a" | json_field 'x["mode"]')" = mine ] || fail "R1: mine mode envelope mode changed"
  pass "R1 cli_contract: --waves/--epic accepted, every rejecting rule exits 2, --json no-op elsewhere"
}

# usage_line <stderr-file>: the stderr line beginning `usage:` (empty when absent).
usage_line() {
  sed -n '/^usage: /p' "$1"
}

test_usage_synopsis() {
  write_config true
  printf '%s\n' "$ACYCLIC" | write_board
  for argv in '--wat' '--waves --mine'; do
    # shellcheck disable=SC2086 # argv is a deliberate word list
    _rc=0
    run_tool $argv >"$TMP/syn.out" 2>"$TMP/syn.err" || _rc=$?
    [ "$_rc" = 2 ] || fail "R2 [$argv]: expected exit 2, got $_rc"
    [ "$(usage_line "$TMP/syn.err" | wc -l | tr -d ' ')" = 1 ] ||
      fail "R2 [$argv]: stderr has no single line beginning 'usage:'"
    usage_line "$TMP/syn.err" | grep -qF -- '--waves [--epic E##]' ||
      fail "R2 [$argv]: usage line lacks the literal '--waves [--epic E##]'"
    grep -q '^next-task: ' "$TMP/syn.err" || fail "R2 [$argv]: the specific next-task: diagnostic line is gone"
  done
  [ "$(json_field 'x["reason"]["detail"]' <"$TMP/syn.out")" = '--waves and --mine are mutually exclusive' ] ||
    fail "R2: reason.detail is no longer the specific message"
  run_tool --wat >"$TMP/syn.out" 2>/dev/null || :
  [ "$(json_field 'x["reason"]["detail"]' <"$TMP/syn.out")" = 'unknown or positional argument "--wat"' ] ||
    fail "R2: reason.detail for --wat is no longer the specific message"
  # The synopsis rides on usage-error ONLY: an input-error keeps its single diagnostic.
  run_tool --waves --epic E9 >"$TMP/syn.out" 2>"$TMP/syn.err" || :
  [ -z "$(usage_line "$TMP/syn.err")" ] || fail "R2: a non-usage error printed the usage synopsis"
  pass "R2 usage_synopsis: usage-error stderr carries the synopsis; detail unchanged"
}

# Compact, ORDER-PRESERVING renderings of the wave fields: `1:E1-F2|2:E1-F3`. Comparing
# the whole string pins wave numbers, wave order, membership and in-wave order at once.
WAVES_SHAPE='"|".join("%s:%s" % (w["wave"], ",".join(f["id"] for f in w["features"])) for w in x["waves"])'
WAVE0='",".join(x["wave0"])'
CRIT='",".join(x["critical_path"])'

# feat <id> <status> [deps-json] [extra-json-members]: one feature object.
feat() {
  printf '{"id":"%s","title":"%s","status":"%s","sdd":true,"spec_path":"specs/%s/","depends_on":%s%s}' \
    "$1" "$1" "$2" "$1" "${3:-[]}" "${4:+,$4}"
}
# board1 <feature-json>...: a one-epic (E1) board, features in the order given.
board1() {
  _f=$(printf '%s,' "$@")
  printf '{"project":"fixture","epics":[{"id":"E1","title":"one","status":"planned","features":[%s]}]}\n' "${_f%,}" | write_board
}

# assert_waves_envelope <label> <out-file>: the R3 fixed fields of a valid-graph envelope.
assert_waves_envelope() {
  _o=$2
  [ "$(json_field 'x["schema_version"]' <"$_o")" = 1 ] || fail "R3 [$1]: schema_version is not 1"
  [ "$(json_field 'type(x["schema_version"]).__name__' <"$_o")" = int ] || fail "R3 [$1]: schema_version is not an integer"
  [ "$(json_field 'x["mode"]' <"$_o")" = waves ] || fail "R3 [$1]: mode is not waves"
  [ "$(json_field 'x["outcome"]' <"$_o")" = waves ] || fail "R3 [$1]: outcome is not waves"
  [ "$(json_field 'x["selected"] is None' <"$_o")" = True ] || fail "R3 [$1]: selected is not null"
  [ "$(json_field 'x["reason"]["code"]' <"$_o")" = waves-derived ] || fail "R3 [$1]: reason.code is not waves-derived"
  [ -n "$(json_field 'x["summary"] or ""' <"$_o")" ] || fail "R3 [$1]: summary is empty"
  [ "$(json_field 'x["reason"]["detail"] == x["summary"]' <"$_o")" = True ] || fail "R3 [$1]: reason.detail != summary"
  [ "$(json_field 'x["blocked"]' <"$_o")" = '[]' ] || fail "R3 [$1]: blocked is not []"
  [ "$(json_field 'x["scope"]' <"$_o")" = "{'epic': None}" ] || fail "R3 [$1]: scope is not {epic: null}"
  [ "$(json_field 'all(type(w["wave"]).__name__ == "int" for w in x["waves"])' <"$_o")" = True ] ||
    fail "R3 [$1]: a waves[].wave is not an integer"
  [ "$(json_field 'list(x)' <"$_o")" = "['schema_version', 'mode', 'outcome', 'selected', 'reason', 'blocked', 'summary', 'scope', 'wave0', 'waves', 'critical_path']" ] ||
    fail "R3 [$1]: envelope key list is not the seven envelope keys plus scope, wave0, waves, critical_path"
}

test_wave_assignment() {
  write_config true
  # Linear chain F1 -> F2 -> F3, F1 done; input order reversed.
  board1 "$(feat E1-F3 pending '["E1-F2"]')" "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 done)"
  run_tool --waves --json >"$TMP/w.out" || fail "R3 linear: --waves --json failed"
  assert_waves_envelope linear "$TMP/w.out"
  [ "$(json_field "$WAVE0" <"$TMP/w.out")" = E1-F1 ] || fail "R3 linear: wave0 is not [E1-F1]"
  [ "$(json_field "$WAVES_SHAPE" <"$TMP/w.out")" = '1:E1-F2|2:E1-F3' ] ||
    fail "R3 linear: waves are $(json_field "$WAVES_SHAPE" <"$TMP/w.out"), want 1:E1-F2|2:E1-F3 (a done dependency counts as wave 0)"
  # Diamond F1 -> {F2, F3} -> F4; input order reversed.
  board1 "$(feat E1-F4 pending '["E1-F3","E1-F2"]')" "$(feat E1-F3 pending '["E1-F1"]')" \
    "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 pending)"
  run_tool --waves --json >"$TMP/w.out" || fail "R3 diamond: --waves --json failed"
  assert_waves_envelope diamond "$TMP/w.out"
  [ "$(json_field "$WAVE0" <"$TMP/w.out")" = '' ] || fail "R3 diamond: wave0 is not []"
  [ "$(json_field "$WAVES_SHAPE" <"$TMP/w.out")" = '1:E1-F1|2:E1-F2,E1-F3|3:E1-F4' ] ||
    fail "R3 diamond: waves are $(json_field "$WAVES_SHAPE" <"$TMP/w.out")"
  # Two components {F1 -> F2}, {F5 -> F6 -> F7}; input order interleaved and reversed.
  board1 "$(feat E1-F7 pending '["E1-F6"]')" "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F6 pending '["E1-F5"]')" \
    "$(feat E1-F5 pending)" "$(feat E1-F1 pending)"
  run_tool --waves --json >"$TMP/w.out" || fail "R3 components: --waves --json failed"
  assert_waves_envelope components "$TMP/w.out"
  [ "$(json_field "$WAVES_SHAPE" <"$TMP/w.out")" = '1:E1-F1,E1-F5|2:E1-F2,E1-F6|3:E1-F7' ] ||
    fail "R3 components: waves are $(json_field "$WAVES_SHAPE" <"$TMP/w.out")"
  # MAX, not first/last/min dependency: F3 and F4 each depend on F1 (wave 1) and F2
  # (wave 2), listed in opposite orders; done features sorted in wave0 (F12 after F9).
  board1 "$(feat E1-F4 pending '["E1-F2","E1-F1"]')" "$(feat E1-F12 done)" "$(feat E1-F3 pending '["E1-F1","E1-F2"]')" \
    "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F9 done)" "$(feat E1-F1 pending '["E1-F12"]')"
  run_tool --waves --json >"$TMP/w.out" || fail "R3 max: --waves --json failed"
  assert_waves_envelope max "$TMP/w.out"
  [ "$(json_field "$WAVE0" <"$TMP/w.out")" = 'E1-F9,E1-F12' ] ||
    fail "R3 max: wave0 is $(json_field "$WAVE0" <"$TMP/w.out"), want E1-F9,E1-F12 (ADR-0001 order, not string order)"
  [ "$(json_field "$WAVES_SHAPE" <"$TMP/w.out")" = '1:E1-F1|2:E1-F2|3:E1-F3,E1-F4' ] ||
    fail "R3 max: waves are $(json_field "$WAVES_SHAPE" <"$TMP/w.out"), want a feature's wave = 1 + MAX of its dependencies"
  # Error envelopes keep the seven-key shape: mode board when parseArgs threw, mode waves
  # for an input-error raised after parsing.
  run_tool --waves --wat >"$TMP/e.out" 2>/dev/null || :
  [ "$(json_field 'list(x)' <"$TMP/e.out")" = "['schema_version', 'mode', 'outcome', 'selected', 'reason', 'blocked', 'summary']" ] ||
    fail "R3: usage-error envelope is not the seven-key shape"
  [ "$(json_field 'x["mode"]' <"$TMP/e.out")" = board ] || fail "R3: usage-error envelope mode is not board"
  _rc=0
  node "$TOOL" --waves --json --tasks "$TMP/absent.json" --config "$TMP/config.yaml" >"$TMP/e.out" 2>/dev/null || _rc=$?
  [ "$_rc" = 1 ] || fail "R3: unreadable board under --waves exited $_rc, want 1"
  [ "$(json_field 'list(x)' <"$TMP/e.out")" = "['schema_version', 'mode', 'outcome', 'selected', 'reason', 'blocked', 'summary']" ] ||
    fail "R3: input-error envelope is not the seven-key shape"
  [ "$(json_field 'x["mode"] + "/" + x["outcome"] + "/" + x["reason"]["code"]' <"$TMP/e.out")" = waves/error/input-error ] ||
    fail "R3: post-parse input-error envelope is not mode=waves outcome=error code=input-error"
  pass "R3 wave_assignment: linear, diamond, two components, max-of-deps; error envelopes keep seven keys"
}

# epic_json <epic-id> <feature-json>...: one epic object.
epic_json() {
  _e=$1
  shift
  _f=$(printf '%s,' "$@")
  printf '{"id":"%s","title":"%s","status":"planned","features":[%s]}' "$_e" "$_e" "${_f%,}"
}
# boardN <epic-json>...: a multi-epic board, epics in the order given.
boardN() {
  _x=$(printf '%s,' "$@")
  printf '{"project":"fixture","epics":[%s]}\n' "${_x%,}" | write_board
}

test_epic_scope() {
  write_config true
  # E2-F1 depends on pending E1-F2 (wave 1), so E2-F1 is wave 2 board-wide. E3 is an
  # existing epic with no features. Epics and features listed out of order.
  boardN "$(epic_json E3)" \
    "$(epic_json E2 "$(feat E2-F3 pending)" "$(feat E2-F1 pending '["E1-F2"]')" "$(feat E2-F2 done)")" \
    "$(epic_json E1 "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 done)")"
  run_tool --waves --json >"$TMP/s.out" || fail "R4: whole-board --waves failed"
  [ "$(json_field 'x["scope"]["epic"] is None' <"$TMP/s.out")" = True ] || fail "R4: whole board scope.epic is not null"
  [ "$(json_field "$WAVE0" <"$TMP/s.out")" = 'E1-F1,E2-F2' ] || fail "R4: whole board wave0 is $(json_field "$WAVE0" <"$TMP/s.out")"
  [ "$(json_field "$WAVES_SHAPE" <"$TMP/s.out")" = '1:E1-F2,E2-F3|2:E2-F1' ] ||
    fail "R4: whole board waves are $(json_field "$WAVES_SHAPE" <"$TMP/s.out")"
  run_tool --waves --epic E2 --json >"$TMP/s.out" || fail "R4: --epic E2 failed"
  [ "$(json_field 'x["outcome"]' <"$TMP/s.out")" = waves ] || fail "R4: --epic E2 outcome is not waves"
  [ "$(json_field 'x["scope"]' <"$TMP/s.out")" = "{'epic': 'E2'}" ] || fail "R4: --epic E2 scope is not {epic: E2}"
  [ "$(json_field "$WAVE0" <"$TMP/s.out")" = 'E2-F2' ] || fail "R4: --epic E2 wave0 is $(json_field "$WAVE0" <"$TMP/s.out"), want only E2's done ids"
  [ "$(json_field "$WAVES_SHAPE" <"$TMP/s.out")" = '1:E2-F3|2:E2-F1' ] ||
    fail "R4: --epic E2 waves are $(json_field "$WAVES_SHAPE" <"$TMP/s.out"), want 1:E2-F3|2:E2-F1 (board-wide numbers, E1 filtered out)"
  run_tool --waves --epic E3 --json >"$TMP/s.out" || fail "R4: an existing epic with no features was rejected"
  [ "$(json_field 'x["scope"]["epic"] + "/" + str(x["wave0"]) + "/" + str(x["waves"]) + "/" + str(x["critical_path"])' <"$TMP/s.out")" = 'E3/[]/[]/[]' ] ||
    fail "R4: an empty epic does not give empty wave0/waves/critical_path"
  # Missing epic: input-error, exit 1, stderr names it.
  _rc=0
  run_tool --waves --epic E9 --json >"$TMP/s.out" 2>"$TMP/s.err" || _rc=$?
  [ "$_rc" = 1 ] || fail "R4: --epic E9 exited $_rc, want 1"
  [ "$(json_field 'x["outcome"] + "/" + x["reason"]["code"] + "/" + x["mode"]' <"$TMP/s.out")" = error/input-error/waves ] ||
    fail "R4: --epic E9 is not an input-error envelope in mode waves"
  grep -q 'E9' "$TMP/s.err" || fail "R4: stderr does not name the missing epic E9"
  # ... and a missing epic wins over a live cycle (checked before the graph).
  boardN "$(epic_json E1 "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 pending '["E1-F2"]')")"
  _rc=0
  run_tool --waves --epic E9 --json >"$TMP/s.out" 2>"$TMP/s.err" || _rc=$?
  [ "$_rc" = 1 ] || fail "R4: --epic E9 on a live-cycle board exited $_rc, want 1"
  [ "$(json_field 'x["outcome"] + "/" + x["reason"]["code"]' <"$TMP/s.out")" = error/input-error ] ||
    fail "R4: on a live-cycle board --epic E9 did not win over invalid-graph"
  [ "$(json_field 'x["reason"]["detail"]' <"$TMP/s.out")" = 'epic E9 does not exist' ] ||
    fail "R4: missing-epic detail is '$(json_field 'x["reason"]["detail"]' <"$TMP/s.out")'"
  pass "R4 epic_scope: whole board by default; --epic filters, keeps board-wide waves; missing epic = input-error first"
}

# record_of <id> <expr-over-r>: evaluate an expression over the wave record of <id>.
record_of() {
  python3 -c 'import json,sys
x=json.load(sys.stdin)
r=[f for w in x["waves"] for f in w["features"] if f["id"]==sys.argv[1]]
assert len(r)==1, "%s listed %d times" % (sys.argv[1], len(r))
r=r[0]
print(eval(sys.argv[2], {"r":r}))' "$1" "$2"
}

test_feature_records() {
  write_config true
  # Records fixture (require_spec_approval: true), listed out of order. E1 is owned by
  # alice; E3 is a draft epic.
  boardN \
    "$(printf '{"id":"E3","title":"E3","status":"draft","features":[%s]}' "$(feat E3-F1 pending '[]' '"autonomous":true')")" \
    "$(epic_json E2 "$(feat E2-F1 pending '[]' '"autonomous":false')")" \
    "$(printf '{"id":"E1","title":"E1","status":"planned","owner":"alice","features":[%s]}' "$(printf '%s,' \
      "$(feat E1-F7 pending '[]' '"owner":""')" \
      "$(feat E1-F6 in-review '[]' '"autonomous":true,"parked":{"reason":"PR 12 open","gate":"merge","pr":"12"}')" \
      "$(feat E1-F5 pending '["E1-F2"]' '"autonomous":true')" \
      "$(feat E1-F4 spec-ready '[]')" \
      "$(feat E1-F3 pending '[]' '"parked":{"reason":"console attestation","gate":"owner"}')" \
      "$(feat E1-F2 pending '[]' '"owner":"bob","autonomous":true,"parked":{"reason":"vendor keys pending"}')" \
      "$(feat E1-F1 in-progress '[]' '"autonomous":true')" | sed 's/,$//')")"
  run_tool --waves --json >"$TMP/r.out" || fail "R5: --waves --json failed"
  [ "$(json_field 'x["outcome"]' <"$TMP/r.out")" = waves ] || fail "R5: outcome is not waves"
  [ "$(json_field 'sorted({",".join(sorted(f)) for w in x["waves"] for f in w["features"]})' <"$TMP/r.out")" = "['autonomous,blocked,id,owner,route,runnable,status']" ] ||
    fail "R5: a feature record's key set is not exactly id,status,route,autonomous,owner,runnable,blocked"
  # id status route autonomous owner runnable first-code — one row per feature.
  while read -r id status route auto owner runnable code; do
    got=$(record_of "$id" '" ".join([r["id"], r["status"], str(r["route"]), str(r["autonomous"]), repr(r["owner"]), str(r["runnable"]), r["blocked"][0]["code"] if r["blocked"] else "-"])' <"$TMP/r.out")
    want="$id $status $route $auto $owner $runnable $code"
    [ "$got" = "$want" ] || fail "R5 [$id]: record is '$got', want '$want'"
  done <<'ROWS'
E1-F1 in-progress builder True 'alice' True -
E1-F2 pending architect True 'bob' False parked
E1-F3 pending architect False 'alice' False gated-owner
E1-F4 spec-ready None False 'alice' False human-gate
E1-F5 pending architect True 'alice' False unmet-dependency
E1-F6 in-review reviewer True 'alice' False awaiting-merge
E1-F7 pending architect False '' True -
E2-F1 pending architect False None True -
E3-F1 pending architect True None False gated-epic
ROWS
  case $(record_of E1-F2 'r["blocked"][0]["detail"]' <"$TMP/r.out") in
    *'[route when unparked: architect]') ;;
    *) fail "R5: parked detail does not end with [route when unparked: architect]" ;;
  esac
  # The blocked records ARE the selector's: target mode on the same fixture is the oracle.
  for id in E1-F2 E1-F3 E1-F4 E1-F5 E1-F6 E3-F1; do
    run_tool --feature "$id" >"$TMP/t.out" || fail "R5: target mode for $id failed"
    [ "$(json_field '[[b["code"], b["detail"]] for b in x["blocked"]]' <"$TMP/t.out")" = \
      "$(record_of "$id" '[[b["code"], b["detail"]] for b in r["blocked"]]' <"$TMP/r.out")" ] ||
      fail "R5 [$id]: wave record blocked != the selector's target-mode blocked records"
    [ "$(record_of "$id" 'all(b["subject"] == r["id"] for b in r["blocked"])' <"$TMP/r.out")" = True ] ||
      fail "R5 [$id]: a blocked record's subject is not the feature"
  done
  for id in E1-F1 E1-F7 E2-F1; do
    run_tool --feature "$id" >"$TMP/t.out" || fail "R5: target mode for $id failed"
    [ "$(json_field 'x["outcome"]' <"$TMP/t.out")" = selected ] || fail "R5 [$id]: runnable in waves but not selected in target mode"
    [ "$(record_of "$id" 'r["blocked"]' <"$TMP/r.out")" = '[]' ] || fail "R5 [$id]: runnable record has non-empty blocked"
  done
  pass "R5 feature_records: exact key set; route/autonomous/owner/runnable; blocked == selector records"
}

# BLOCKED_SHAPE: every blocked record as `subject code detail`, `;`-joined, in order.
BLOCKED_SHAPE='";".join("%s %s %s" % (b["subject"], b["code"], b["detail"]) for b in x["blocked"])'

# assert_invalid <label> <out-file> <scope-repr> <blocked-shape>
assert_invalid() {
  [ "$(json_field 'x["mode"] + "/" + x["outcome"] + "/" + x["reason"]["code"] + "/" + str(x["selected"])' <"$2")" = waves/blocked/invalid-graph/None ] ||
    fail "R6 [$1]: not mode=waves outcome=blocked reason=invalid-graph selected=null"
  [ "$(json_field 'x["scope"]' <"$2")" = "$3" ] || fail "R6 [$1]: scope is $(json_field 'x["scope"]' <"$2"), want $3"
  [ "$(json_field 'str(x["wave0"]) + str(x["waves"]) + str(x["critical_path"])' <"$2")" = '[][][]' ] ||
    fail "R6 [$1]: wave0/waves/critical_path are not all empty on an invalid graph"
  [ -n "$(json_field 'x["summary"] or ""' <"$2")" ] || fail "R6 [$1]: summary is empty"
  [ "$(json_field 'list(x)' <"$2")" = "['schema_version', 'mode', 'outcome', 'selected', 'reason', 'blocked', 'summary', 'scope', 'wave0', 'waves', 'critical_path']" ] ||
    fail "R6 [$1]: envelope key list differs from the valid-graph envelope"
  _got=$(json_field "$BLOCKED_SHAPE" <"$2")
  [ "$_got" = "$4" ] || fail "R6 [$1]: blocked is
  $_got
want
  $4"
}

test_invalid_graph() {
  write_config true
  # (a) live cycle F1 <-> F2, F3 depends on F2 (a mere dependent: no record); F4 done.
  board1 "$(feat E1-F4 done)" "$(feat E1-F3 pending '["E1-F2"]')" "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 pending '["E1-F2"]')"
  _rc=0
  run_tool --waves --json >"$TMP/g.out" || _rc=$?
  [ "$_rc" = 0 ] || fail "R6 (a): an invalid graph exited $_rc, want 0"
  assert_invalid a "$TMP/g.out" "{'epic': None}" \
    'E1-F1 dependency-cycle dependency cycle (feature): E1-F1 -> E1-F2 -> E1-F1;E1-F1 unmet-dependency blocking dependencies: E1-F2=pending;E1-F2 dependency-cycle dependency cycle (feature): E1-F1 -> E1-F2 -> E1-F1;E1-F2 unmet-dependency blocking dependencies: E1-F1=pending'
  # (b) dangling depends_on, two offenders in non-canonical order (F10 before F9 as text
  # and in input); F10 is ALSO parked: only its unmet-dependency record appears. F2 is a
  # mere dependent of F9. F5 is DONE and names a missing id: not an offender.
  board1 "$(feat E1-F10 pending '["E1-F8","E1-F1"]' '"parked":{"reason":"hold"}')" "$(feat E1-F2 pending '["E1-F9"]')" \
    "$(feat E1-F9 pending '["E1-F7"]')" "$(feat E1-F5 done '["E1-F6"]')" "$(feat E1-F1 pending)"
  run_tool --waves --json >"$TMP/g.out" || fail "R6 (b): exited non-zero"
  assert_invalid b "$TMP/g.out" "{'epic': None}" \
    'E1-F9 unmet-dependency blocking dependencies: E1-F7=missing;E1-F10 unmet-dependency blocking dependencies: E1-F1=pending, E1-F8=missing'
  # (c) the dangling edge in E1 while --epic E2: validity is judged board-wide.
  boardN "$(epic_json E2 "$(feat E2-F1 pending)")" "$(epic_json E1 "$(feat E1-F1 pending '["E1-F9"]')")"
  run_tool --waves --epic E2 --json >"$TMP/g.out" || fail "R6 (c): exited non-zero"
  assert_invalid c "$TMP/g.out" "{'epic': 'E2'}" 'E1-F1 unmet-dependency blocking dependencies: E1-F9=missing'
  # (d) stale cycle: F1 done, F2 pending, mutual edges -> valid, F2 in wave 1. A done
  # feature naming a missing id is not an offender either.
  board1 "$(feat E1-F3 done '["E1-F9"]')" "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 done '["E1-F2"]')"
  run_tool --waves --json >"$TMP/g.out" || fail "R6 (d): exited non-zero"
  [ "$(json_field 'x["outcome"]' <"$TMP/g.out")" = waves ] || fail "R6 (d): a stale cycle made the graph invalid"
  [ "$(json_field "$WAVES_SHAPE" <"$TMP/g.out")" = '1:E1-F2' ] || fail "R6 (d): stale-cycle feature is not alone in wave 1"
  [ "$(record_of E1-F2 '[b["code"] for b in r["blocked"]]' <"$TMP/g.out")" = '[]' ] ||
    fail "R6 (d): stale-cycle feature carries a blocker record"
  # (e) live cycle where F1 is spec-ready non-autonomous under approval and F2 is parked:
  # no human-gate and no parked record — only the two graph codes per feature.
  board1 "$(feat E1-F2 pending '["E1-F1"]' '"parked":{"reason":"hold"}')" "$(feat E1-F1 spec-ready '["E1-F2"]')"
  run_tool --waves --json >"$TMP/g.out" || fail "R6 (e): exited non-zero"
  assert_invalid e "$TMP/g.out" "{'epic': None}" \
    'E1-F1 dependency-cycle dependency cycle (feature): E1-F1 -> E1-F2 -> E1-F1;E1-F1 unmet-dependency blocking dependencies: E1-F2=pending (parked: hold);E1-F2 dependency-cycle dependency cycle (feature): E1-F1 -> E1-F2 -> E1-F1;E1-F2 unmet-dependency blocking dependencies: E1-F1=spec-ready'
  pass "R6 invalid_graph: live cycle / dangling id -> invalid-graph with only graph records; stale cycle valid"
}

# crit_is <label> <want> [extra args]: --waves --json critical_path equals <want>.
crit_is() {
  _l=$1 _w=$2
  shift 2
  run_tool --waves --json "$@" >"$TMP/c.out" || fail "R7 [$_l]: --waves failed"
  [ "$(json_field 'x["outcome"]' <"$TMP/c.out")" = waves ] || fail "R7 [$_l]: outcome is not waves"
  _g=$(json_field "$CRIT" <"$TMP/c.out")
  [ "$_g" = "$_w" ] || fail "R7 [$_l]: critical_path is [$_g], want [$_w]"
}

test_critical_path() {
  write_config true
  # Every fixture lists its features in REVERSE canonical order.
  board1 "$(feat E1-F4 pending '["E1-F3","E1-F2"]')" "$(feat E1-F3 pending '["E1-F1"]')" "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 pending)"
  crit_is diamond 'E1-F1,E1-F2,E1-F4'
  # Longer beats a smaller root.
  board1 "$(feat E1-F7 pending '["E1-F6"]')" "$(feat E1-F6 pending '["E1-F5"]')" "$(feat E1-F5 pending)" "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 pending)"
  crit_is longer-later-root 'E1-F5,E1-F6,E1-F7'
  # Equal length, tie decided at position 0.
  board1 "$(feat E1-F4 pending '["E1-F2"]')" "$(feat E1-F3 pending '["E1-F1"]')" "$(feat E1-F2 pending)" "$(feat E1-F1 pending)"
  crit_is tie-position-0 'E1-F1,E1-F3'
  # Equal length, tie decided at position 1.
  board1 "$(feat E1-F3 pending '["E1-F1"]')" "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 pending)"
  crit_is tie-position-1 'E1-F1,E1-F2'
  # Tie broken by ADR-0001 (numeric) order, not string order: F9 < F10.
  board1 "$(feat E1-F12 pending '["E1-F9"]')" "$(feat E1-F11 pending '["E1-F10"]')" "$(feat E1-F10 pending)" "$(feat E1-F9 pending)"
  crit_is tie-numeric 'E1-F9,E1-F12'
  # A done feature is wave 0 and never part of the chain.
  board1 "$(feat E1-F3 pending '["E1-F2"]')" "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 done)"
  crit_is through-done 'E1-F2,E1-F3'
  # Single pending feature; all-done board.
  board1 "$(feat E1-F2 done)" "$(feat E1-F1 pending)"
  crit_is single 'E1-F1'
  board1 "$(feat E1-F2 done '["E1-F1"]')" "$(feat E1-F1 done)"
  crit_is all-done ''
  # --epic restricts the chain to in-scope features: E2-F1 -> E1-F1 -> E2-F2 -> E2-F3.
  # Board-wide the chain runs through E1-F1; under --epic E2 an out-of-scope link breaks
  # it, leaving E2-F2 -> E2-F3 (longer than E2-F1 alone); under --epic E1 it is E1-F1.
  boardN "$(epic_json E2 "$(feat E2-F3 pending '["E2-F2"]')" "$(feat E2-F2 pending '["E1-F1"]')" "$(feat E2-F1 pending)")" \
    "$(epic_json E1 "$(feat E1-F1 pending '["E2-F1"]')")"
  crit_is board-wide 'E2-F1,E1-F1,E2-F2,E2-F3'
  crit_is epic-E2 'E2-F2,E2-F3' --epic E2
  crit_is epic-E1 'E1-F1' --epic E1
  pass "R7 critical_path: longest non-done in-scope chain, ties by ADR-0001 order position by position"
}

# row_fields <id> <file>: the whitespace-delimited fields of the report row for <id>.
row_fields() {
  awk -v id="$1" 'index($0, "  " id " ") == 1 { $1 = $1; print }' "$2"
}

test_human_report() {
  write_config true
  board1 "$(feat E1-F6 pending)" "$(feat E1-F5 spec-ready)" \
    "$(feat E1-F4 pending '[]' '"parked":{"reason":"keys pending; runnable-later"}')" \
    "$(feat E1-F3 pending '["E1-F2"]' '"autonomous":true')" "$(feat E1-F2 pending '["E1-F1"]' '"autonomous":true')" "$(feat E1-F1 done)"
  run_tool --waves >"$TMP/h.out" || fail "R8: text --waves failed"
  sed -n 1p "$TMP/h.out" | grep -qF 'whole board' || fail "R8: line 1 does not name the whole-board scope"
  [ "$(sed -n 2p "$TMP/h.out" | grep -c '^Wave 0 (done): 1 ')" = 1 ] || fail "R8: line 2 is not 'Wave 0 (done): 1 ...'"
  grep -q '^Wave 1 (' "$TMP/h.out" || fail "R8: no 'Wave 1 (' heading"
  # shellcheck disable=SC2046 # field splitting is the point
  set -- $(row_fields E1-F2 "$TMP/h.out")
  [ "$#" = 5 ] && [ "$1/$2/$3/$4/$5" = E1-F2/pending/architect/auto/runnable ] ||
    fail "R8: runnable autonomous row fields are '$*'"
  # shellcheck disable=SC2046
  set -- $(row_fields E1-F4 "$TMP/h.out")
  [ "$1/$2/$3/$4/$5" = E1-F4/pending/architect/-/'[parked]' ] || fail "R8: parked row fields are '$*'"
  for _f in "$@"; do [ "$_f" != runnable ] || fail "R8: the parked row has a 'runnable' field"; done
  # shellcheck disable=SC2046
  set -- $(row_fields E1-F5 "$TMP/h.out")
  [ "$1/$2/$3/$4/$5" = E1-F5/spec-ready/-/-/'[human-gate]' ] || fail "R8: route-null row fields are '$*'"
  # shellcheck disable=SC2046
  set -- $(row_fields E1-F6 "$TMP/h.out")
  [ "$#" = 5 ] && [ "$1/$2/$3/$4/$5" = E1-F6/pending/architect/-/runnable ] || fail "R8: runnable non-autonomous row fields are '$*'"
  [ "$(tail -n 1 "$TMP/h.out")" = 'Critical path (2): E1-F2 -> E1-F3' ] || fail "R8: last line is not the critical path"
  # The full report, byte for byte (the anchors above are the spec; this pins the rest).
  cat >"$TMP/h.want" <<'TXT'
Waves — whole board
Wave 0 (done): 1 feature(s)
Wave 1 (4 feature(s), 1 autonomous)
  E1-F2  pending  architect  auto  runnable
  E1-F4  pending  architect  -  [parked] keys pending; runnable-later [route when unparked: architect]
  E1-F5  spec-ready  -  -  [human-gate] spec-ready requires approval
  E1-F6  pending  architect  -  runnable
Wave 2 (1 feature(s), 1 autonomous)
  E1-F3  pending  architect  auto  [unmet-dependency] blocking dependencies: E1-F2=pending
Critical path (2): E1-F2 -> E1-F3
TXT
  cmp -s "$TMP/h.out" "$TMP/h.want" || fail "R8: text report differs from the golden report:
$(diff "$TMP/h.want" "$TMP/h.out" || :)"
  run_tool --waves --epic E1 >"$TMP/h.out" || fail "R8: text --waves --epic E1 failed"
  [ "$(sed -n 1p "$TMP/h.out")" = 'Waves — epic E1' ] || fail "R8: --epic E1 line 1 is '$(sed -n 1p "$TMP/h.out")'"
  # --json: exactly one stdout line, valid JSON.
  run_tool --waves --json >"$TMP/h.out" || fail "R8: --waves --json failed"
  [ "$(wc -l <"$TMP/h.out" | tr -d ' ')" = 1 ] || fail "R8: --json printed more than one line"
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/h.out" || fail "R8: --json output does not parse"
  # Blocker fields: two blockers render as two [code] fields.
  board1 "$(feat E1-F2 pending '["E1-F1"]' '"parked":{"reason":"hold"}')" "$(feat E1-F1 pending)"
  run_tool --waves >"$TMP/h.out" || fail "R8: two-blocker text failed"
  [ "$(row_fields E1-F2 "$TMP/h.out")" = 'E1-F2 pending architect - [parked] hold [route when unparked: architect] [unmet-dependency] blocking dependencies: E1-F1=pending' ] ||
    fail "R8: two-blocker row is '$(row_fields E1-F2 "$TMP/h.out")'"
  # Edge lines: all done; one pending feature.
  board1 "$(feat E1-F2 done)" "$(feat E1-F1 done)"
  run_tool --waves >"$TMP/h.out" || fail "R8: all-done text failed"
  [ "$(tail -n 1 "$TMP/h.out")" = 'Critical path (0): none' ] || fail "R8: all-done board last line is '$(tail -n 1 "$TMP/h.out")'"
  [ "$(sed -n 2p "$TMP/h.out")" = 'Wave 0 (done): 2 feature(s)' ] || fail "R8: all-done Wave 0 line is '$(sed -n 2p "$TMP/h.out")'"
  [ "$(wc -l <"$TMP/h.out" | tr -d ' ')" = 3 ] || fail "R8: all-done board printed a wave heading"
  board1 "$(feat E1-F1 pending)"
  run_tool --waves >"$TMP/h.out" || fail "R8: single text failed"
  [ "$(tail -n 1 "$TMP/h.out")" = 'Critical path (1): E1-F1' ] || fail "R8: one-feature path line is '$(tail -n 1 "$TMP/h.out")'"
  # Invalid graph in text mode: exit 0, `Waves undefined` first, one blocked line per record.
  board1 "$(feat E1-F2 pending '["E1-F1"]')" "$(feat E1-F1 pending '["E1-F2"]')"
  _rc=0
  run_tool --waves >"$TMP/h.out" || _rc=$?
  [ "$_rc" = 0 ] || fail "R8: invalid-graph text exited $_rc"
  sed -n 1p "$TMP/h.out" | grep -q '^Waves undefined' || fail "R8: invalid-graph first line is '$(sed -n 1p "$TMP/h.out")'"
  grep -q '^blocked E1-F1 \[dependency-cycle\]: ' "$TMP/h.out" || fail "R8: no 'blocked E1-F1 [dependency-cycle]: ' line"
  cat >"$TMP/h.want" <<'TXT'
Waves undefined: dependency graph is invalid
blocked E1-F1 [dependency-cycle]: dependency cycle (feature): E1-F1 -> E1-F2 -> E1-F1
blocked E1-F1 [unmet-dependency]: blocking dependencies: E1-F2=pending
blocked E1-F2 [dependency-cycle]: dependency cycle (feature): E1-F1 -> E1-F2 -> E1-F1
blocked E1-F2 [unmet-dependency]: blocking dependencies: E1-F1=pending
TXT
  cmp -s "$TMP/h.out" "$TMP/h.want" || fail "R8: invalid-graph report differs:
$(diff "$TMP/h.want" "$TMP/h.out" || :)"
  # Input error in text mode: still the JSON error envelope on stdout, exit 1.
  _rc=0
  run_tool --waves --epic E9 >"$TMP/h.out" 2>/dev/null || _rc=$?
  [ "$_rc" = 1 ] || fail "R8: text --epic E9 exited $_rc, want 1"
  [ "$(json_field 'x["outcome"] + "/" + x["reason"]["code"]' <"$TMP/h.out")" = error/input-error ] ||
    fail "R8: text-mode input error is not the JSON error envelope"
  pass "R8 human_report: scope line, Wave 0, wave rows by field, critical path; invalid graph; errors stay JSON"
}

# Runs LAST: it audits every run_tool call the suite made.
test_read_only_and_builtins() {
  _n=$(grep -c -- '--waves' "$RUNS" || :)
  [ "$_n" -ge 40 ] || fail "R9: only $_n --waves runs were recorded; the read-only audit is not covering the suite"
  [ ! -s "$WRITES" ] || fail "R9: a run changed the fixture board:
$(cat "$WRITES")"
  [ "$(protected_cksums)" = "$PROTECTED_BEFORE" ] ||
    fail "R9: store/tasks.schema.json, tools/task-diagnostics.py or init.sh changed during the suite"
  # Statement lines only: a comment in the selector contains `from "..."`.
  grep -E "^import .* from ['\"]|^import ['\"]" "$TOOL" >"$TMP/imports" || :
  [ -s "$TMP/imports" ] || fail "R9: found no import statement lines (the scan pattern is broken)"
  while IFS= read -r _line; do
    case $_line in
      *" from 'node:"* | *' from "node:'* | "import 'node:"* | 'import "node:'*) ;;
      *) fail "R9: non-builtin import: $_line" ;;
    esac
  done <"$TMP/imports"
  ! grep -qF 'import(' "$TOOL" || fail "R9: tools/next-task.mjs contains a dynamic import("
  ! grep -qF 'require(' "$TOOL" || fail "R9: tools/next-task.mjs contains require("
  pass "R9 read_only_and_builtins: no --waves run wrote the board or a protected file; node: imports only"
}

test_cli_contract
test_usage_synopsis
test_wave_assignment
test_epic_scope
test_feature_records
test_invalid_graph
test_critical_path
test_human_report
test_read_only_and_builtins

echo "test_waves: $PASS passed"
