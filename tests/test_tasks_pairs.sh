#!/bin/sh
# test_tasks_pairs.sh — E36-F01: per-requirement red/green task pairs.
#
# Drives tools/tasks-pair-check.py against fixtures (behavioral), and pins the prose/template
# surfaces with fence-aware section slices (tests/lib/fence.awk, never the bare /^#+ / idiom).
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never git-diff a DO-NOT-TOUCH file against main; never write state/ or a live spec.
# Exit codes are asserted as `rc -eq N`, never a shell-dependent code.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/tools/tasks-pair-check.py"
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
T="$(mktemp -d 2>/dev/null || mktemp -d -t taskspairs)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v python3 >/dev/null 2>&1 || fail "python3 is a hard harness dependency and is absent"

# ── fixture writers ───────────────────────────────────────────────────────────────────────
# fx_spec <path> [--decoys] [ids...]: includes a blank and a whitespace-only line so a fence
# port that spins on empty lines hangs here, not in the Reviewer.
fx_spec() {
  _p="$1"; shift
  _dec=0; [ "${1:-}" = "--decoys" ] && { _dec=1; shift; }
  [ "$#" -gt 0 ] || set -- R1 R2 R3
  { printf '# Fixture spec\n\n   \n## Acceptance criteria\n\n'
    for _i in "$@"; do printf -- '- **%s** — the system shall do %s.\n' "$_i" "$_i"; done
    if [ "$_dec" -eq 1 ]; then
      printf '\n```\n- **R9** — decoy\n```\n\n~~~\n- **R8** — decoy\n~~~\n\n   ```\n- **R7** — decoy\n   ```\n'
    fi
  } > "$_p"
}
# fx_tasks_good <path> [--decoys]
fx_tasks_good() {
  _p="$1"
  { printf '# Fixture tasks\n\n'
    if [ "${2:-}" = "--decoys" ]; then
      printf '```\n- [ ] **T9b** (R1) — decoy code task before T1a\n- [ ] **T5** — Write tests per feature.tests.md\n```\n\n'
    fi
    printf -- '- [ ] **T1a** (R1) — write failing test; observe RED\n'
    printf -- '- [ ] **T1b** (R1) — minimal code; observe GREEN\n'
    printf -- '- [ ] **T2a** (R2, R3) — write failing test; observe RED\n'
    printf -- '- [ ] **T2b** (R2, R3) — minimal code; observe GREEN\n'
    printf -- '- [ ] **T3** (R1) — refactor\n'
    printf -- '- [ ] **T4** — Run ./init.sh + sh tools/run-tests.sh\n'
  } > "$_p"
}
run_lint() { set +e; python3 "$TOOL" "$@" >"$T/out" 2>"$T/err"; rc=$?; set -e; }

# ── R5: ok path, fenced decoys ignored ────────────────────────────────────────────────────
fx_spec "$T/s.md"; fx_tasks_good "$T/t.md"
run_lint "$T/t.md" --spec "$T/s.md"
[ "$rc" -eq 0 ] || fail "R5_ok_exit0: expected rc 0, got $rc ($(cat "$T/out" "$T/err" 2>/dev/null))"
tail -n 1 "$T/out" | grep -qE '^tasks-pair-check: ok 3 R-ids, 6 tasks$' \
  || fail "R5_ok_exit0: last stdout line is not 'ok 3 R-ids, 6 tasks': $(tail -n1 "$T/out")"
pass "R5_ok_exit0"

fx_spec "$T/sd.md" --decoys; fx_tasks_good "$T/td.md" --decoys
run_lint "$T/td.md" --spec "$T/sd.md"
[ "$rc" -eq 0 ] || fail "R5_fenced_decoys_ignored: decoys not ignored, rc $rc ($(cat "$T/out"))"
grep -qE '^tasks-pair-check: ok 3 R-ids, 6 tasks$' "$T/out" \
  || fail "R5_fenced_decoys_ignored: counts changed by decoys: $(tail -n1 "$T/out")"
# control: strip the fence delimiter lines -> decoys become live -> must fail
grep -vE '^ *(```|~~~)' "$T/sd.md" > "$T/sd-live.md"
grep -vE '^ *(```|~~~)' "$T/td.md" > "$T/td-live.md"
run_lint "$T/td-live.md" --spec "$T/sd-live.md"
[ "$rc" -eq 1 ] || fail "R5_fenced_decoys_ignored control: unfenced decoys should give rc 1, got $rc"
pass "R5_fenced_decoys_ignored"

# ── R8: usage / input errors => exit 2 ────────────────────────────────────────────────────
chk_exit2() { # chk_exit2 <row>
  [ "$rc" -eq 2 ] || fail "$1: expected rc 2, got $rc"
  grep -qF 'tasks-pair-check: error:' "$T/err" || fail "$1: stderr lacks 'tasks-pair-check: error:'"
  grep -qi 'usage' "$T/err" || fail "$1: stderr lacks usage"
  grep -qF 'tasks-pair-check: ok' "$T/out" && fail "$1: printed an ok line"
  pass "$1"
}
run_lint "$T/t.md"; chk_exit2 R8_missing_spec_flag_exit2
run_lint "$T/nonexistent.md" --spec "$T/s.md"
grep -qF 'tasks-pair-check: error:' "$T/err" || fail "R8_unreadable_file_exit2: tasks path"
chk_exit2 R8_unreadable_file_exit2
run_lint "$T/t.md" --spec "$T/nonexistent-spec.md"; chk_exit2 R8_unreadable_file_exit2
printf '# spec\n\n```\n- **R1** — only in a fence\n```\n' > "$T/s-zero.md"
run_lint "$T/t.md" --spec "$T/s-zero.md"; chk_exit2 R8_zero_rids_exit2

# ── R6: first task not a test task / no task ──────────────────────────────────────────────
chk_exit1() { # chk_exit1 <row> <expected-line>
  [ "$rc" -eq 1 ] || fail "$1: expected rc 1, got $rc ($(cat "$T/out" "$T/err"))"
  grep -qxF "$2" "$T/out" || fail "$1: missing line '$2' in: $(cat "$T/out")"
  [ "$(tail -n 1 "$T/out")" = "tasks-pair-check: FAIL 1 violation(s)" ] || fail "$1: last line is not FAIL 1: $(tail -n1 "$T/out")"
  grep -qF 'tasks-pair-check: ok' "$T/out" && fail "$1: printed an ok line"
  pass "$1"
}
{ printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2b** (R2) — code first\n- [ ] **T2a** (R2) — t\n- [ ] **T3a** (R3) — t\n'; } > "$T/t6a.md"
run_lint "$T/t6a.md" --spec "$T/s.md"
chk_exit1 R6_first_task_code_exit1 'tasks-pair-check: first-task-not-test R2 T2b'
printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2** (R2) — add code\n- [ ] **T3a** (R3) — t\n' > "$T/t6b.md"
run_lint "$T/t6b.md" --spec "$T/s.md"
chk_exit1 R6_first_task_unsuffixed_exit1 'tasks-pair-check: first-task-not-test R2 T2'
printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2c** (R2) — odd suffix\n- [ ] **T3a** (R3) — t\n' > "$T/t6c.md"
run_lint "$T/t6c.md" --spec "$T/s.md"
chk_exit1 R6_first_task_unsuffixed_exit1 'tasks-pair-check: first-task-not-test R2 T2c'
printf -- '- [ ] **T1a** (R1) — t\n- [ ] **T2a** (R2) — t\n' > "$T/t6d.md"
run_lint "$T/t6d.md" --spec "$T/s.md"
chk_exit1 R6_no_task_exit1 'tasks-pair-check: no-task R3'

# ── R7: un-cited "write ... tests" task ───────────────────────────────────────────────────
{ cat "$T/t.md"; printf -- '- [ ] **T5** — Write tests per feature.tests.md\n'; } > "$T/t7a.md"
run_lint "$T/t7a.md" --spec "$T/s.md"
chk_exit1 R7_trailing_write_tests_exit1 'tasks-pair-check: write-tests-task T5'
{ printf -- '- [ ] **T0** — Write tests per feature.tests.md\n'; cat "$T/t.md"; } > "$T/t7b.md"
run_lint "$T/t7b.md" --spec "$T/s.md"
chk_exit1 R7_leading_write_tests_exit1 'tasks-pair-check: write-tests-task T0'
{ printf -- '- [ ] **T1a** (R1) — write the failing tests; observe RED\n'; sed 1d "$T/t.md" | grep -v 'T1a'; } > "$T/t7c.md"
run_lint "$T/t7c.md" --spec "$T/s.md"
[ "$rc" -eq 0 ] || fail "R7_cited_write_test_passes: rc $rc ($(cat "$T/out"))"
pass "R7_cited_write_test_passes"

echo "all tasks-pairs checks passed"
