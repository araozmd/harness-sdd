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

# ── prose helpers: fence-aware slicers (fence.awk), never the bare /^#+ / idiom ───────────
unfenced() { awk "$FENCE_AWK"'fence_delim($0) { next } !fence' "$1"; }   # unfenced <file>
slice() { # slice <file> <heading-prefix>: one section up to the next "## " heading, delimiters kept
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^## / { keep = (index($0, h) == 1); next }
    keep' "$1"
}
folded() { tr '\n' ' ' | tr -s ' '; }
# anch <text-file> <regex> <row> <what>
anch() { folded < "$1" | grep -qiE "$2" || fail "$3: missing anchor: $4"; }

# ── R1: the shipped template is pair form ─────────────────────────────────────────────────
run_lint "$ROOT/specs/_templates/feature.tasks.md" --spec "$ROOT/specs/_templates/feature.spec.md"
[ "$rc" -eq 0 ] || fail "R1_template_passes_lint: rc $rc ($(cat "$T/out" "$T/err"))"
grep -qE '^tasks-pair-check: ok' "$T/out" || fail "R1_template_passes_lint: no ok line"
pass "R1_template_passes_lint"
unfenced "$ROOT/specs/_templates/feature.tasks.md" > "$T/tpl.txt"
for n in 1 2 3 4 5; do
  _a="$(grep -n "\*\*T${n}a\*\* (R${n})" "$T/tpl.txt" | head -n1)"
  _b="$(grep -n "\*\*T${n}b\*\* (R${n})" "$T/tpl.txt" | head -n1)"
  [ -n "$_a" ] && [ -n "$_b" ] || fail "R1_template_shape: T${n}a/T${n}b missing"
  [ "${_a%%:*}" -lt "${_b%%:*}" ] || fail "R1_template_shape: T${n}a does not precede T${n}b"
  printf '%s\n' "$_a" | grep -q 'RED' || fail "R1_template_shape: T${n}a does not name RED"
  printf '%s\n' "$_b" | grep -q 'GREEN' || fail "R1_template_shape: T${n}b does not name GREEN"
done
grep -qE '\*\*T6\*\* \(R1, R2\) — refactor' "$T/tpl.txt" || fail "R1_template_shape: no explicit refactor task citing R-ids"
grep -q 'Write tests per' "$ROOT/specs/_templates/feature.tasks.md" && fail "R1_template_shape: old 'Write tests per' task survives"
pass "R1_template_shape"

# ── R2: architect item 3 ──────────────────────────────────────────────────────────────────
slice "$ROOT/agents/architect.md" '## Your output (the 4-file spec)' > "$T/arch.txt"
[ -s "$T/arch.txt" ] || fail "R2_architect_item3_pairs: section not found"
anch "$T/arch.txt" 'T<n>a.{0,160}RED' R2_architect_item3_pairs 'T<n>a ... RED'
anch "$T/arch.txt" 'T<n>b.{0,160}GREEN' R2_architect_item3_pairs 'T<n>b ... GREEN'
anch "$T/arch.txt" 'walking.{0,160}first' R2_architect_item3_pairs 'walking ... first'
anch "$T/arch.txt" 'refactor.{0,160}R-id' R2_architect_item3_pairs 'refactor ... R-id'
anch "$T/arch.txt" 'tasks-pair-check\.py.{0,160}hand-off' R2_architect_item3_pairs 'tasks-pair-check.py ... hand-off'
grep -qF 'Sequential, independent, small steps' "$T/arch.txt" && fail "R2_architect_item3_pairs: old item-3 text survives"
pass "R2_architect_item3_pairs"

# ── R3: SPEC-FORMAT section + table row, WORKFLOW step 5 ──────────────────────────────────
slice "$ROOT/docs/SPEC-FORMAT.md" '## Tasks — red/green pairs per requirement' > "$T/sf.txt"
[ -s "$T/sf.txt" ] || fail "R3_spec_format_pairs_section: section '## Tasks — red/green pairs per requirement' not found"
grep -qE '^ *(```|~~~)' "$T/sf.txt" || fail "R3_spec_format_pairs_section: slice has no fence delimiter — it did not read through the fenced example"
for a in 'T<n>a.{0,160}RED' 'T<n>b.{0,160}GREEN' 'write.{0,160}tests.{0,160}reject' \
         'fenced.{0,160}ignored' 'range.{0,160}not expanded' 'own pair' \
         'co-cit.{0,160}`a` task' 'never.{0,160}code-only'; do
  anch "$T/sf.txt" "$a" R3_spec_format_pairs_section "$a"
done
pass "R3_spec_format_pairs_section"
slice "$ROOT/docs/SPEC-FORMAT.md" '## The four files' | grep -F '| `.tasks.md`' | grep -qi 'red/green pair' \
  || fail "R3_spec_format_table_row: .tasks.md row lacks 'red/green pair'"
pass "R3_spec_format_table_row"
slice "$ROOT/docs/WORKFLOW.md" '## One run, end to end' | grep -E '^5\.' | grep -i 'pair' | grep -qi 'commit' \
  || fail "R3_workflow_step5: step 5 lacks pair/commit"
pass "R3_workflow_step5"

# ── R4: builder Loop A ────────────────────────────────────────────────────────────────────
slice "$ROOT/agents/builder.md" '## Loop A — in-session (you implement)' > "$T/la.txt"
[ -s "$T/la.txt" ] || fail "R4_builder_loop_a_pairs: Loop A section not found"
if ! folded < "$T/la.txt" | grep -qiE 'never.{0,160}code.{0,160}RED|RED.{0,160}before.{0,160}code'; then
  fail "R4_builder_loop_a_pairs: no 'no code before RED' rule"
fi
anch "$T/la.txt" 'commit.{0,160}GREEN' R4_builder_loop_a_pairs 'commit ... GREEN'
for a in 'in-progress' 'DO NOT TOUCH' './init.sh' 'tasks.md'; do
  grep -qF "$a" "$T/la.txt" || fail "R4_builder_loop_a_pairs: retained anchor missing: $a"
done
pass "R4_builder_loop_a_pairs"

# ── R9: reviewer item 7 inside "What you check" ───────────────────────────────────────────
slice "$ROOT/agents/reviewer.md" '## What you check' > "$T/rv.txt"
[ -s "$T/rv.txt" ] || fail "R9_reviewer_item7_in_what_you_check: section not found"
grep -qE '^7\. ' "$T/rv.txt" || fail "R9_reviewer_item7_in_what_you_check: no item 7 inside '## What you check'"
anch "$T/rv.txt" '7\. \*\*Task-pair shape' R9_reviewer_item7_in_what_you_check 'Task-pair shape'
anch "$T/rv.txt" 'tasks-pair-check\.py.{0,160}--spec' R9_reviewer_item7_in_what_you_check 'tasks-pair-check.py ... --spec'
anch "$T/rv.txt" 'non-zero.{0,160}reject' R9_reviewer_item7_in_what_you_check 'non-zero ... reject'
anch "$T/rv.txt" 'predates.{0,160}flag' R9_reviewer_item7_in_what_you_check 'predates ... flag'
anch "$T/rv.txt" 'diff-filter=A' R9_reviewer_item7_in_what_you_check 'diff-filter=A'
anch "$T/rv.txt" 'sdd: false.{0,160}exempt' R9_reviewer_item7_in_what_you_check 'sdd: false ... exempt'
anch "$T/rv.txt" 'confirm +`<feature>\.tests\.md` has a test' R9_reviewer_item7_in_what_you_check 'check #2 text retained'
pass "R9_reviewer_item7_in_what_you_check"

echo "all tasks-pairs checks passed"
