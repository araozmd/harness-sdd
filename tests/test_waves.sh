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

test_cli_contract

echo "test_waves: $PASS passed"
