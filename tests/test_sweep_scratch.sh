#!/bin/sh
# test_sweep_scratch.sh — E34-F01: disposable-fixture behavioral suite for
# tools/sweep-scratch.sh, the automated scratch-dir sweep backstop.
#
# Every fixture is a throwaway Git repo under a system temp dir (mktemp -d), never
# this repository's own scratchpad/ or state/tasks.json. Each fixture ships its own
# copy of tools/sweep-scratch.sh and is invoked through its own shebang
# (./tools/sweep-scratch.sh), never `sh <path>` — the tool's shebang is `#!/bin/sh`,
# so this also doubles as a check that the tool runs under whatever `sh` resolves to
# on this host, consistent with every other suite tools/run-tests.sh selects.
#
# R-id coverage: R1-R8, R12 of E34-F01.spec.md, per E34-F01.tests.md's traceability table.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL_SRC="$SRC/tools/sweep-scratch.sh"
TMP_ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t sweep-scratch)"
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -x "$TOOL_SRC" ] || fail "tools/sweep-scratch.sh is missing or not executable in the source tree"
sh -n "$TOOL_SRC" || fail "tools/sweep-scratch.sh does not parse under sh -n"

# ── fixture helpers ────────────────────────────────────────────────────────────────

# make_fixture <name> — a fresh disposable Git repo with tools/sweep-scratch.sh and
# an empty scratchpad/ + state/tasks.json. Sets $PRIMARY.
make_fixture() {
  _name="$1"
  PRIMARY="$TMP_ROOT/$_name"
  mkdir -p "$PRIMARY/tools" "$PRIMARY/state" "$PRIMARY/scratchpad"
  cp "$TOOL_SRC" "$PRIMARY/tools/sweep-scratch.sh"
  chmod +x "$PRIMARY/tools/sweep-scratch.sh"
  printf '{"epics":[]}\n' > "$PRIMARY/state/tasks.json"
  git -C "$PRIMARY" init -q
  git -C "$PRIMARY" config user.name "Sweep Scratch Test"
  git -C "$PRIMARY" config user.email "sweep-scratch@example.test"
  : > "$PRIMARY/.keep"
  git -C "$PRIMARY" add -A
  git -C "$PRIMARY" commit -q -m base
}

# write_board <json> — overwrite the fixture's TaskStore verbatim.
write_board() {
  printf '%s' "$1" > "$PRIMARY/state/tasks.json"
}

# write_config <yaml> — write the fixture's harness.config.yaml verbatim (source
# layout ⇒ repo root, matching resolve_repository's "tools/" case).
write_config() {
  printf '%s' "$1" > "$PRIMARY/harness.config.yaml"
}

# scratch_dir <name> [<size-kb>] — create a scratchpad/<name>/ with a file of the
# given size (default 1 KiB), so it is always a non-empty real directory.
scratch_dir() {
  _sd_name="$1"
  _sd_kb="${2:-1}"
  mkdir -p "$PRIMARY/scratchpad/$_sd_name"
  dd if=/dev/zero of="$PRIMARY/scratchpad/$_sd_name/payload.bin" bs=1024 "count=$_sd_kb" >/dev/null 2>&1
}

# scratch_symlink <name> <target> — create scratchpad/<name> as a symlink to <target>
# (expected to resolve outside scratchpad/).
scratch_symlink() {
  ln -s "$2" "$PRIMARY/scratchpad/$1"
}

# dir_bytes <path> — the SAME measurement method the tool uses (du -sk * 1024), so a
# test's "expected size" is never computed a different way than the tool computes it.
dir_bytes() {
  du -sk "$1" | awk '{print $1 * 1024}'
}

# run_sweep [<args>...] — invoke the fixture's own copy via its own shebang, from the
# fixture's toplevel. Captures stdout+stderr to $OUT and the exit code to $RC.
#
# The tool is EXPECTED to exit non-zero in several tests here (R5, R7), and this suite
# runs under `set -eu`: a bare `OUT="$(...)"` assignment whose right-hand side fails
# aborts the whole suite right there, silently, with no FAIL: line (the exact abort
# shape progress/lessons.md's 2026-09-16 builder entry names). `set +e` / `set -e`
# brackets the substitution so $RC captures the real exit code instead.
run_sweep() {
  set +e
  OUT="$(cd "$PRIMARY" && ./tools/sweep-scratch.sh "$@" 2>&1)"
  RC=$?
  set -e
}

# has_verdict_line — true iff $OUT contains at least one PER-ENTRY verdict line, in the
# exact "<name><TAB>(removed|eligible|unrecognized|skipped: <reason>)" shape the tool
# prints. Anchored to that line shape rather than a bare keyword grep: the tool's OWN
# die() diagnostic for R5 says "...nothing was removed" in prose, which a bare
# `grep -E 'removed'` would false-positive on and make the R5 "no verdict was printed"
# assertion vacuously fail on the tool's own correct abort message.
has_verdict_line() {
  printf '%s\n' "$OUT" | grep -qE "$(printf '\t')(removed|eligible|unrecognized|skipped:)"
}

# ── R1 ──────────────────────────────────────────────────────────────────────────────
test_default_is_dry_run_apply_mutates() {
  make_fixture r1
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -eq 0 ] || fail "R1: dry-run exited non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+eligible$' \
    || fail "R1: dry-run did not report E01-F01-builder as eligible: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R1: dry-run mutated the filesystem — the directory is gone without --apply"

  run_sweep --apply
  [ "$RC" -eq 0 ] || fail "R1: --apply exited non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R1: --apply did not report E01-F01-builder as removed: $OUT"
  [ ! -e "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R1: --apply did not remove the eligible directory"
  pass "R1 test_default_is_dry_run_apply_mutates"
}

# ── R2 ──────────────────────────────────────────────────────────────────────────────
test_classifies_feature_id_prefix_skips_unrecognized() {
  make_fixture r2
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder
  scratch_dir not-a-feature-dir
  scratch_dir e01-f01-lowercase

  run_sweep
  [ "$RC" -eq 0 ] || fail "R2: dry-run exited non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^not-a-feature-dir[[:space:]]+unrecognized$' \
    || fail "R2: not-a-feature-dir was not classified unrecognized: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^e01-f01-lowercase[[:space:]]+unrecognized$' \
    || fail "R2: a lowercase feature-id-shaped name was not classified unrecognized: $OUT"

  run_sweep --apply
  [ "$RC" -eq 0 ] || fail "R2: --apply exited non-zero: $OUT"
  [ -d "$PRIMARY/scratchpad/not-a-feature-dir" ] \
    || fail "R2: an unrecognized entry was removed under --apply — it must never be acted on in any mode"
  [ -d "$PRIMARY/scratchpad/e01-f01-lowercase" ] \
    || fail "R2: a lowercase-prefixed unrecognized entry was removed under --apply"
  pass "R2 test_classifies_feature_id_prefix_skips_unrecognized"
}

# ── R3 ──────────────────────────────────────────────────────────────────────────────
test_done_feature_removed_on_apply_reported_dry_run() {
  make_fixture r3
  write_board '{"epics":[{"id":"E02","features":[{"id":"E02-F09","status":"done"}]}]}'
  scratch_dir E02-F09-reviewer 4

  run_sweep
  [ "$RC" -eq 0 ] || fail "R3: dry-run exited non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E02-F09-reviewer[[:space:]]+eligible$' \
    || fail "R3: a done feature's entry was not reported eligible in dry-run: $OUT"
  [ -d "$PRIMARY/scratchpad/E02-F09-reviewer" ] || fail "R3: dry-run removed a directory"

  run_sweep --apply
  [ "$RC" -eq 0 ] || fail "R3: --apply exited non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E02-F09-reviewer[[:space:]]+removed$' \
    || fail "R3: --apply did not report the removal: $OUT"
  [ ! -e "$PRIMARY/scratchpad/E02-F09-reviewer" ] \
    || fail "R3: --apply did not actually remove the done-feature directory"
  pass "R3 test_done_feature_removed_on_apply_reported_dry_run"
}

# ── R4 ──────────────────────────────────────────────────────────────────────────────
test_not_found_or_non_done_skipped() {
  make_fixture r4
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F02","status":"in-review"}]}]}'
  scratch_dir E01-F02-reviewer
  scratch_dir E09-F09-builder

  run_sweep
  [ "$RC" -eq 0 ] || fail "R4: dry-run exited non-zero on nothing but skips: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F02-reviewer[[:space:]]+skipped: status:in-review$' \
    || fail "R4: a non-done entry was not skipped with its exact status reason: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E09-F09-builder[[:space:]]+skipped: not-found$' \
    || fail "R4: an entry whose feature id is absent from the TaskStore was not skipped as not-found: $OUT"

  run_sweep --apply
  [ "$RC" -eq 0 ] || fail "R4: --apply exited non-zero on nothing but skips: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F02-reviewer" ] \
    || fail "R4: --apply removed a non-done entry"
  [ -d "$PRIMARY/scratchpad/E09-F09-builder" ] \
    || fail "R4: --apply removed a not-found entry"
  pass "R4 test_not_found_or_non_done_skipped"
}

# ── R5 ──────────────────────────────────────────────────────────────────────────────
test_corrupt_taskstore_aborts_whole_scan_no_changes() {
  make_fixture r5
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder
  scratch_dir not-a-feature-dir
  # Corrupt AFTER seeding the board-derived fixture, so this is a targeted regression:
  # the same layout that worked in R1 now has an unparseable TaskStore.
  printf 'not valid json {' > "$PRIMARY/state/tasks.json"

  run_sweep
  [ "$RC" -ne 0 ] || fail "R5: a corrupt/unparseable TaskStore did not make the tool exit non-zero"
  printf '%s\n' "$OUT" | grep -qiE 'cannot read or parse the TaskStore' \
    || fail "R5: the abort does not name the TaskStore read/parse failure: $OUT"
  # A DISTINCT outcome from R4: no per-entry verdict of any kind was printed — the
  # scan never reached classification.
  has_verdict_line \
    && fail "R5: a per-entry verdict was printed despite the TaskStore being unreadable — the scan must abort BEFORE classifying anything: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] || fail "R5: a directory vanished on a dry (non --apply) run"
  [ -d "$PRIMARY/scratchpad/not-a-feature-dir" ] || fail "R5: a directory vanished on a dry (non --apply) run"

  run_sweep --apply
  [ "$RC" -ne 0 ] || fail "R5: --apply against a corrupt TaskStore did not exit non-zero"
  has_verdict_line \
    && fail "R5: --apply against a corrupt TaskStore printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R5: --apply removed a directory despite the whole scan being required to abort first"
  [ -d "$PRIMARY/scratchpad/not-a-feature-dir" ] \
    || fail "R5: --apply removed a directory despite the whole scan being required to abort first"
  pass "R5 test_corrupt_taskstore_aborts_whole_scan_no_changes"
}

# ── R6 ──────────────────────────────────────────────────────────────────────────────
test_symlink_escape_skipped() {
  make_fixture r6
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  mkdir -p "$TMP_ROOT/r6-outside"
  : > "$TMP_ROOT/r6-outside/canary.txt"
  scratch_symlink E01-F01-escape "$TMP_ROOT/r6-outside"

  run_sweep
  [ "$RC" -eq 0 ] || fail "R6: dry-run exited non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-escape[[:space:]]+skipped: symlink-escape$' \
    || fail "R6: a symlink escaping scratchpad/ was not reported as a skipped anomaly: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-escape[[:space:]]+eligible$' \
    && fail "R6: a symlink escaping scratchpad/ was reported eligible instead of skipped"

  run_sweep --apply
  [ "$RC" -eq 0 ] || fail "R6: --apply exited non-zero: $OUT"
  [ -e "$PRIMARY/scratchpad/E01-F01-escape" ] \
    || fail "R6: --apply deleted the symlink entry instead of skipping it"
  [ -f "$TMP_ROOT/r6-outside/canary.txt" ] \
    || fail "R6: the escape target's contents were deleted — the tool deleted THROUGH the symlink"
  pass "R6 test_symlink_escape_skipped"
}

# ── R7 ──────────────────────────────────────────────────────────────────────────────
test_exit_code_reflects_tool_errors_only() {
  make_fixture r7a
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F02","status":"in-review"}]}]}'
  scratch_dir E01-F02-reviewer
  scratch_dir stray-file

  run_sweep
  [ "$RC" -eq 0 ] \
    || fail "R7: a run with only per-entry skips and unrecognized entries exited non-zero: $OUT"

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R7: --apply with only per-entry skips and unrecognized entries exited non-zero: $OUT"

  # Invalid arguments ARE a tool-level error and must flip the exit code.
  run_sweep --this-flag-does-not-exist
  [ "$RC" -ne 0 ] || fail "R7: an unrecognized flag did not exit non-zero"

  run_sweep E01-F02 E09-F09
  [ "$RC" -ne 0 ] || fail "R7: two positional feature-id arguments did not exit non-zero"

  run_sweep not-a-valid-feature-id
  [ "$RC" -ne 0 ] || fail "R7: a malformed feature-id argument did not exit non-zero"
  pass "R7 test_exit_code_reflects_tool_errors_only"
}

test_report_has_summary_verdicts_and_bytes_reclaimed() {
  make_fixture r7b
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"},{"id":"E01-F03","status":"done"},{"id":"E01-F02","status":"in-review"}]}]}'
  scratch_dir E01-F01-builder 3
  scratch_dir E01-F03-reviewer 5
  scratch_dir E01-F02-reviewer 1
  scratch_dir stray-file 1

  _expect_bytes=$(( $(dir_bytes "$PRIMARY/scratchpad/E01-F01-builder") + $(dir_bytes "$PRIMARY/scratchpad/E01-F03-reviewer") ))

  run_sweep --apply
  [ "$RC" -eq 0 ] || fail "R7: --apply exited non-zero on a mixed-verdict run: $OUT"

  _summary="$(printf '%s\n' "$OUT" | grep '^summary:' || :)"
  [ -n "$_summary" ] || fail "R7: no summary line was printed: $OUT"

  _total=$(printf '%s\n' "$_summary" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  _removed=$(printf '%s\n' "$_summary" | sed -n 's/.*removed=\([0-9]*\).*/\1/p')
  _eligible=$(printf '%s\n' "$_summary" | sed -n 's/.*eligible=\([0-9]*\).*/\1/p')
  _skipped=$(printf '%s\n' "$_summary" | sed -n 's/.*skipped=\([0-9]*\).*/\1/p')
  _unrecognized=$(printf '%s\n' "$_summary" | sed -n 's/.*unrecognized=\([0-9]*\).*/\1/p')
  _bytes=$(printf '%s\n' "$_summary" | sed -n 's/.*bytes_reclaimed=\([0-9]*\).*/\1/p')

  [ "$_total" = "4" ]        || fail "R7: summary total is '$_total', expected 4: $_summary"
  [ "$_removed" = "2" ]      || fail "R7: summary removed is '$_removed', expected 2: $_summary"
  [ "$_eligible" = "0" ]     || fail "R7: summary eligible is '$_eligible', expected 0 under --apply: $_summary"
  [ "$_skipped" = "1" ]      || fail "R7: summary skipped is '$_skipped', expected 1: $_summary"
  [ "$_unrecognized" = "1" ] || fail "R7: summary unrecognized is '$_unrecognized', expected 1: $_summary"
  [ "$_bytes" = "$_expect_bytes" ] \
    || fail "R7: bytes_reclaimed is '$_bytes', expected '$_expect_bytes' (sum of the two removed directories, measured the same way the tool measures them): $_summary"
  pass "R7 test_report_has_summary_verdicts_and_bytes_reclaimed"
}

# ── R8 ──────────────────────────────────────────────────────────────────────────────
test_scoped_vs_full_scan() {
  make_fixture r8
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"},{"id":"E01-F02","status":"in-review"}]}]}'
  scratch_dir E01-F01-builder
  scratch_dir E01-F02-reviewer

  run_sweep E01-F01
  [ "$RC" -eq 0 ] || fail "R8: scoped dry-run exited non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+eligible$' \
    || fail "R8: the scoped entry was not reported: $OUT"
  printf '%s\n' "$OUT" | grep -qF 'E01-F02-reviewer' \
    && fail "R8: an out-of-scope entry was reported despite the scope argument: $OUT"

  run_sweep
  [ "$RC" -eq 0 ] || fail "R8: unscoped dry-run exited non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qF 'E01-F01-builder' \
    || fail "R8: unscoped run did not report the first entry: $OUT"
  printf '%s\n' "$OUT" | grep -qF 'E01-F02-reviewer' \
    || fail "R8: unscoped run did not report the second entry: $OUT"
  pass "R8 test_scoped_vs_full_scan"
}

# ── R12 ─────────────────────────────────────────────────────────────────────────────
test_unsupported_backend_refuses_before_touching_anything() {
  make_fixture r12
  write_config 'store:
  tasks: obsidian
  docs: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -ne 0 ] \
    || fail "R12: an unsupported store.tasks backend (obsidian) did not exit non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'unsupported TaskStore backend.*obsidian' \
    || fail "R12: the refusal does not name the unsupported backend: $OUT"
  has_verdict_line \
    && fail "R12: a per-entry verdict was printed despite the backend being unsupported — the scan must refuse BEFORE classifying anything: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: a scratch directory vanished on a dry (non --apply) run against an unsupported backend"

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: --apply against an unsupported backend did not exit non-zero: $OUT"
  has_verdict_line \
    && fail "R12: --apply against an unsupported backend printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply removed a scratch directory despite the tool being required to refuse first"
  pass "R12 test_unsupported_backend_refuses_before_touching_anything"
}

test_default_is_dry_run_apply_mutates
test_classifies_feature_id_prefix_skips_unrecognized
test_done_feature_removed_on_apply_reported_dry_run
test_not_found_or_non_done_skipped
test_corrupt_taskstore_aborts_whole_scan_no_changes
test_symlink_escape_skipped
test_exit_code_reflects_tool_errors_only
test_report_has_summary_verdicts_and_bytes_reclaimed
test_scoped_vs_full_scan
test_unsupported_backend_refuses_before_touching_anything

echo "all sweep-scratch tests passed"
