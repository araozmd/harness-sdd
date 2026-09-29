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
# R-id coverage: R1-R8, R12, R13, R14 of E34-F01.spec.md, per E34-F01.tests.md's traceability table.

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
  # A real install always seeds harness.config.yaml (harness-install.sh); most
  # fixtures here don't care about R12's store.tasks resolution at all, so give
  # them an explicit, ordinary local backend by default. R12 tests that DO care
  # override this with their own write_config, and the one test exercising a
  # genuinely absent config file (Codex #4130253950) removes it after this call.
  printf 'store:\n  tasks: local\n' > "$PRIMARY/harness.config.yaml"
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

# modes_bind_this_uid — true when THIS user is actually constrained by directory mode
# bits. A BEHAVIOURAL PROBE, deliberately not `id -u`: root never gets a real filesystem
# refusal from `chmod 0555`, so the R13 fixture below (which NEEDS `rm -rf` to actually
# fail) would run mistakenly as root and prove nothing. Mirrors
# tests/test_umbrella.sh's own `modes_bind_this_uid` probe (Codex #3805383759) rather than
# re-deriving a second, divergent copy of the same idiom.
modes_bind_this_uid() {
  _mbu="$TMP_ROOT/.mode-probe.$$"
  rm -rf "$_mbu" 2>/dev/null || :
  mkdir -p "$_mbu/ro" || return 1
  : > "$_mbu/ro/f" || return 1
  chmod 0555 "$_mbu/ro" || return 1
  if rm -rf "$_mbu" 2>/dev/null; then
    return 1
  fi
  chmod -R u+w "$_mbu" 2>/dev/null || :
  rm -rf "$_mbu" 2>/dev/null || :
  return 0
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

# ── R14 ─────────────────────────────────────────────────────────────────────────────
# Codex #4130566648: a `status` value that is syntactically valid JSON but embeds a tab
# and newline can be split by the shell's tab-delimited parsing into a forged second
# `id\tstatus` row naming a feature that does not exist. The whole scan must abort
# exactly like R5, and nothing — including a directory namespaced for the forged id —
# may be removed.
test_schema_invalid_status_forged_row_aborts_whole_scan_no_changes() {
  make_fixture r14a
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"pending\nE99-F99\tdone"}]}]}'
  scratch_dir E01-F01-builder
  # E99-F99 is not a real feature anywhere in the board above — only the forged row
  # (if the injection worked) would ever call it "done".
  scratch_dir E99-F99-builder

  run_sweep
  [ "$RC" -ne 0 ] \
    || fail "R14: a schema-invalid status (forged row) did not make the tool exit non-zero"
  has_verdict_line \
    && fail "R14: a per-entry verdict was printed despite a schema-invalid TaskStore record — the scan must abort BEFORE classifying anything: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] || fail "R14: a directory vanished on a dry (non --apply) run"
  [ -d "$PRIMARY/scratchpad/E99-F99-builder" ] || fail "R14: a directory vanished on a dry (non --apply) run"

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R14: --apply against a schema-invalid status did not exit non-zero"
  has_verdict_line \
    && fail "R14: --apply against a schema-invalid status printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R14: --apply removed a directory despite the whole scan being required to abort first"
  [ -d "$PRIMARY/scratchpad/E99-F99-builder" ] \
    || fail "R14: --apply removed the FORGED entry — a row-injection via an embedded tab/newline let a non-existent feature be treated as done"
  pass "R14 test_schema_invalid_status_forged_row_aborts_whole_scan_no_changes"
}

test_schema_invalid_id_aborts_whole_scan_no_changes() {
  make_fixture r14b
  write_board '{"epics":[{"id":"E01","features":[{"id":"not-an-id","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -ne 0 ] \
    || fail "R14: a schema-invalid feature id did not make the tool exit non-zero"
  has_verdict_line \
    && fail "R14: a per-entry verdict was printed despite a schema-invalid feature id: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] || fail "R14: a directory vanished on a dry (non --apply) run"

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R14: --apply against a schema-invalid feature id did not exit non-zero"
  has_verdict_line \
    && fail "R14: --apply against a schema-invalid feature id printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R14: --apply removed a directory despite the whole scan being required to abort first"
  pass "R14 test_schema_invalid_id_aborts_whole_scan_no_changes"
}

# Codex #4131060237: R14's own guard only validated the SHAPE of a present string
# value — a record whose id/status is missing entirely, JSON null, or a non-string
# type (number, list, object) fell through the `isinstance(..., str)` check and was
# silently skipped rather than aborting the whole scan. Each case below pairs the
# malformed record with a SECOND, otherwise-valid `done` feature that owns real
# scratch, so a silent-skip regression would still show it removed.
test_schema_invalid_status_null_aborts_whole_scan_no_changes() {
  make_fixture r14c
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":null},{"id":"E01-F02","status":"done"}]}]}'
  scratch_dir E01-F02-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R14: a null status did not make --apply exit non-zero"
  has_verdict_line \
    && fail "R14: --apply against a null status printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F02-builder" ] \
    || fail "R14: --apply removed a valid done feature's scratch despite an unrelated record having a null status — the whole scan must abort instead of silently skipping the null record"
  pass "R14 test_schema_invalid_status_null_aborts_whole_scan_no_changes"
}

test_schema_invalid_status_missing_aborts_whole_scan_no_changes() {
  make_fixture r14d
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01"},{"id":"E01-F02","status":"done"}]}]}'
  scratch_dir E01-F02-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R14: a missing status key did not make --apply exit non-zero"
  has_verdict_line \
    && fail "R14: --apply against a missing status key printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F02-builder" ] \
    || fail "R14: --apply removed a valid done feature's scratch despite an unrelated record having no status key — the whole scan must abort instead of silently skipping the record"
  pass "R14 test_schema_invalid_status_missing_aborts_whole_scan_no_changes"
}

test_schema_invalid_id_null_aborts_whole_scan_no_changes() {
  make_fixture r14e
  write_board '{"epics":[{"id":"E01","features":[{"id":null,"status":"done"},{"id":"E01-F02","status":"done"}]}]}'
  scratch_dir E01-F02-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R14: a null id did not make --apply exit non-zero"
  has_verdict_line \
    && fail "R14: --apply against a null id printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F02-builder" ] \
    || fail "R14: --apply removed a valid done feature's scratch despite an unrelated record having a null id — the whole scan must abort instead of silently skipping the null record"
  pass "R14 test_schema_invalid_id_null_aborts_whole_scan_no_changes"
}

test_schema_invalid_id_missing_aborts_whole_scan_no_changes() {
  make_fixture r14f
  write_board '{"epics":[{"id":"E01","features":[{"status":"done"},{"id":"E01-F02","status":"done"}]}]}'
  scratch_dir E01-F02-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R14: a missing id key did not make --apply exit non-zero"
  has_verdict_line \
    && fail "R14: --apply against a missing id key printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F02-builder" ] \
    || fail "R14: --apply removed a valid done feature's scratch despite an unrelated record having no id key — the whole scan must abort instead of silently skipping the record"
  pass "R14 test_schema_invalid_id_missing_aborts_whole_scan_no_changes"
}

test_schema_invalid_non_string_types_abort_whole_scan_no_changes() {
  make_fixture r14g
  write_board '{"epics":[{"id":"E01","features":[{"id":["E01","F01"],"status":42},{"id":"E01-F02","status":"done"}]}]}'
  scratch_dir E01-F02-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R14: a non-string id/status (list/number) did not make --apply exit non-zero"
  has_verdict_line \
    && fail "R14: --apply against a non-string id/status printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F02-builder" ] \
    || fail "R14: --apply removed a valid done feature's scratch despite an unrelated record having a non-string id/status — the whole scan must abort instead of silently skipping the record"
  pass "R14 test_schema_invalid_non_string_types_abort_whole_scan_no_changes"
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

# ── dotglob (Codex #4129683699) ─────────────────────────────────────────────────────
# POSIX `*` alone never matches a dot-prefixed name. A dot-prefixed directory, a
# double-dot-prefixed directory, and a dangling dot-prefixed symlink must all still be
# enumerated by an unscoped scan: counted in `total` and given a verdict, never
# silently dropped. None of the three ever matches a real `E##-F##-` feature-id
# prefix, so all three are `unrecognized`, alongside one ordinary matching entry, to
# also confirm no entry is double-counted across the three glob patterns the fix adds.
test_dotglob_entries_included_in_unscoped_scan() {
  make_fixture r-dotglob
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder
  scratch_dir .hidden-dir
  scratch_dir ..double-dot-dir
  scratch_symlink .dangling-link "$TMP_ROOT/r-dotglob-target-does-not-exist"

  run_sweep
  [ "$RC" -eq 0 ] || fail "dotglob: unscoped dry-run exited non-zero: $OUT"

  printf '%s\n' "$OUT" | grep -qE '^\.hidden-dir[[:space:]]+unrecognized$' \
    || fail "dotglob: a dot-prefixed directory was omitted or misclassified by the unscoped scan: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^\.\.double-dot-dir[[:space:]]+unrecognized$' \
    || fail "dotglob: a double-dot-prefixed directory was omitted or misclassified by the unscoped scan: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^\.dangling-link[[:space:]]+unrecognized$' \
    || fail "dotglob: a dangling dot-prefixed symlink was omitted or misclassified by the unscoped scan: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+eligible$' \
    || fail "dotglob: the ordinary recognized entry was not still reported alongside the dot entries: $OUT"

  _n_hidden=$(printf '%s\n' "$OUT" | grep -cE '^\.hidden-dir[[:space:]]')
  [ "$_n_hidden" = "1" ] \
    || fail "dotglob: .hidden-dir was reported $_n_hidden times — the three glob patterns must not overlap: $OUT"

  _summary="$(printf '%s\n' "$OUT" | grep '^summary:' || :)"
  [ -n "$_summary" ] || fail "dotglob: no summary line was printed: $OUT"
  _total=$(printf '%s\n' "$_summary" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  _unrecognized=$(printf '%s\n' "$_summary" | sed -n 's/.*unrecognized=\([0-9]*\).*/\1/p')
  [ "$_total" = "4" ] \
    || fail "dotglob: summary total is '$_total', expected 4 (1 ordinary + 3 dot-prefixed entries): $_summary"
  [ "$_unrecognized" = "3" ] \
    || fail "dotglob: summary unrecognized is '$_unrecognized', expected 3: $_summary"
  pass "dotglob test_dotglob_entries_included_in_unscoped_scan"
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

# ── R12 (flow-style, unparseable) ──────────────────────────────────────────────────
test_unparseable_flow_style_store_block_refuses() {
  make_fixture r12-flow
  write_config 'store: {tasks: obsidian, docs: local}
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -ne 0 ] \
    || fail "R12: a flow-style store: block that the parser cannot read did not exit non-zero: $OUT"
  has_verdict_line \
    && fail "R12: a per-entry verdict was printed despite an unparseable store: block — the scan must refuse BEFORE classifying anything: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: a scratch directory vanished on a dry (non --apply) run against an unparseable store: block"

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: --apply against an unparseable flow-style store: block did not exit non-zero: $OUT"
  has_verdict_line \
    && fail "R12: --apply against an unparseable store: block printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply removed a scratch directory despite an unparseable store: block that must have refused first — this is the exact 'obsidian mirror says done, real backend is not local' repro"
  pass "R12 test_unparseable_flow_style_store_block_refuses"
}

# ── R12 (broad YAML-shape matrix for `_cfg_store_tasks`) ──────────────────────────
# Round-3 escalation: Codex found a THIRD unrecognized `store:` shape (indented
# top-level block) after the flow-style hole above, so `_cfg_store_tasks` was
# rewritten around a python3 reader instead of another awk special-case. This
# matrix pins the reader's real scope directly, rather than one shape at a time.

# ── R12: a store: block PRESENT but omitting tasks: still defaults to local ───────
test_absent_store_block_defaults_local() {
  make_fixture r12-absent
  write_config 'store:
  docs: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -eq 0 ] || fail "R12: a store: block present but omitting tasks: did not default to local: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+eligible$' \
    || fail "R12: a store: block omitting tasks: did not scan normally (local default): $OUT"
  pass "R12 test_absent_store_block_defaults_local"
}

# ── R12 (Codex #4130253950): a genuinely MISSING config file must fail closed,
# not silently default to local — an absent file cannot establish which TaskStore
# backend is authoritative, so proceeding is not safe. Before this fix, this exact
# fixture let --apply exit 0 and delete a done-marked scratch directory.
test_missing_config_file_refuses() {
  make_fixture r12-missing-config
  rm -f "$PRIMARY/harness.config.yaml"
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -ne 0 ] \
    || fail "R12: a missing harness.config.yaml did not exit non-zero: $OUT"
  has_verdict_line \
    && fail "R12: a per-entry verdict was printed despite a missing config file: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: a scratch directory vanished on a dry (non --apply) run against a missing config file"

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: --apply against a missing config file did not exit non-zero: $OUT"
  has_verdict_line \
    && fail "R12: --apply against a missing config file printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply removed a scratch directory despite a missing config file that must have refused first — Codex #4130253950"
  pass "R12 test_missing_config_file_refuses"
}

# ── R12 (Codex #4130253947): an explicit-key YAML mapping entry inside store:'s own
# block (`? tasks` / `: obsidian`) is genuinely unclassifiable by this reader — not an
# ordinary `key:` entry, not a list item, not disqualifying-char content — so it must
# refuse rather than silently conclude tasks: is absent and default to local. Full
# YAML explicit-key support is intentionally NOT implemented here.
test_explicit_key_mapping_at_top_level_refuses() {
  make_fixture r12-explicit-key
  write_config 'store:
  ? tasks
  : obsidian
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -ne 0 ] \
    || fail "R12: a top-level explicit-key mapping entry did not exit non-zero: $OUT"
  has_verdict_line \
    && fail "R12: a per-entry verdict was printed despite an unclassifiable explicit-key entry: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: a scratch directory vanished on a dry (non --apply) run against an explicit-key store: block"

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: --apply against an explicit-key store: block did not exit non-zero: $OUT"
  has_verdict_line \
    && fail "R12: --apply against an explicit-key store: block printed a per-entry verdict: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply removed a scratch directory despite an explicit-key store.tasks: obsidian block that must have refused first — Codex #4130253947"
  pass "R12 test_explicit_key_mapping_at_top_level_refuses"
}

# ── R12: block-style tasks: local, explicit — scans normally, no refusal ─────────
test_block_style_explicit_local_scans_normally() {
  make_fixture r12-explicit-local
  write_config 'store:
  tasks: local
  docs: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] || fail "R12: explicit block-style 'tasks: local' was refused: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12: explicit block-style 'tasks: local' did not scan/remove normally: $OUT"
  pass "R12 test_block_style_explicit_local_scans_normally"
}

# ── R12: block-style non-local (jira) refuses, same as the existing obsidian case ─
test_block_style_non_local_jira_refuses() {
  make_fixture r12-jira
  write_config 'store:
  tasks: jira
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -ne 0 ] \
    || fail "R12: a block-style 'tasks: jira' backend did not exit non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'unsupported TaskStore backend.*jira' \
    || fail "R12: the refusal does not name the jira backend: $OUT"
  has_verdict_line \
    && fail "R12: a per-entry verdict was printed despite an unsupported jira backend: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: a scratch directory vanished against an unsupported jira backend"
  pass "R12 test_block_style_non_local_jira_refuses"
}

# ── R12 (Codex #4130742436): an EXPLICIT empty `tasks:` scalar must refuse, not
# silently default to local — `tasks: ""`, `tasks: ''`, and a bare `tasks:` with
# nothing after the colon are all present-but-unresolvable, which is a DIFFERENT
# case than `tasks:` being genuinely absent from the block (the ONE case that may
# default to local); the shell caller's `${STORE_TASKS:-local}` expansion cannot
# tell "unset" from "set to empty string" apart on its own, so `_cfg_store_tasks`
# itself must refuse (non-zero exit) rather than print empty stdout for this case.
test_explicit_empty_tasks_value_refuses() {
  for _label_variant in 'double-quoted:tasks: ""' "single-quoted:tasks: ''" 'bare:tasks:'; do
    _label="${_label_variant%%:*}"
    _line="${_label_variant#*:}"
    make_fixture "r12-empty-$_label"
    write_config "store:
  $_line
"
    write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
    scratch_dir E01-F01-builder

    run_sweep
    [ "$RC" -ne 0 ] \
      || fail "R12: an explicit empty tasks: value ($_label) did NOT refuse on a dry run: $OUT"
    has_verdict_line \
      && fail "R12: a per-entry verdict was printed despite an explicit empty tasks: value ($_label): $OUT"
    [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
      || fail "R12: a scratch directory vanished on a dry run against an explicit empty tasks: value ($_label)"

    run_sweep --apply
    [ "$RC" -ne 0 ] \
      || fail "R12: --apply against an explicit empty tasks: value ($_label) did not exit non-zero: $OUT"
    [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
      || fail "R12: --apply deleted a done-marked scratch dir despite an explicit empty tasks: value ($_label) — Codex #4130742436's exact repro"
  done
  pass "R12 test_explicit_empty_tasks_value_refuses"
}

# ── R12: INDENTED top-level block-style non-local — this round's exact repro ──────
test_indented_top_level_block_non_local_refuses() {
  make_fixture r12-indented
  write_config '  store:
    tasks: obsidian
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep
  [ "$RC" -ne 0 ] \
    || fail "R12: an indented top-level 'store:' block selecting obsidian did NOT refuse — the exact repro that let --apply delete a live done-in-obsidian scratch dir: $OUT"
  has_verdict_line \
    && fail "R12: a per-entry verdict was printed despite an indented top-level store: block: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: a scratch directory vanished on a dry run against an indented store: block"

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: --apply against an indented top-level store: block did not exit non-zero: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply deleted E01-F01-builder despite an indented store: block selecting a non-local backend — this is the exact round-3 repro"
  pass "R12 test_indented_top_level_block_non_local_refuses"
}

# ── R12: tab-indented block-style non-local — mixed-indentation-character shape ───
test_tab_indented_block_non_local_refuses() {
  make_fixture r12-tabs
  printf 'store:\n\ttasks: jira\n' > "$PRIMARY/harness.config.yaml"
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: a tab-indented 'tasks:' line under a non-local backend did not refuse: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply deleted a scratch dir despite a tab-indented non-local store: block"
  pass "R12 test_tab_indented_block_non_local_refuses"
}

# ── R12: a `tasks:` key under a DIFFERENT top-level block must never be mistaken
# for `store.tasks` — the store: block here genuinely omits tasks:, so this must
# default to local, not pick up the unrelated key.
test_tasks_key_in_other_top_level_block_not_mistaken() {
  make_fixture r12-other-block
  write_config 'store:
  docs: local
other:
  tasks: obsidian
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12: a 'tasks:' key under an unrelated top-level block was mistaken for store.tasks: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12: the store: block (which genuinely omits tasks:) did not default to local: $OUT"
  pass "R12 test_tasks_key_in_other_top_level_block_not_mistaken"
}

# ── R12: DOUBLE-quoted top-level 'store:' key, flow-style value — round-4 repro ───
# Codex's exact reproduction: a quoted top-level key hid the store: block from the
# matcher entirely, so it defaulted to local and let --apply delete a done-in-name
# scratch dir whose real backend was obsidian. Round 5 (the allowlist rewrite)
# now refuses ANY flow-style mapping outright, up front, before ever trying to
# resolve a backend name from it — so the refusal message names the shape
# problem generically rather than the specific backend; the load-bearing
# assertion is that it refuses and touches nothing, not the message's wording.
test_double_quoted_top_level_key_flow_style_refuses() {
  make_fixture r12-dquote-top-flow
  write_config '"store": {"tasks": obsidian, "docs": local}
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: a double-quoted top-level 'store:' key with a flow-style non-local value did not refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'cannot recognize' \
    || fail "R12: the refusal does not report an unrecognized document shape for a flow-style value: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply deleted E01-F01-builder despite a double-quoted top-level store: key selecting a non-local backend — the exact round-4 repro"
  pass "R12 test_double_quoted_top_level_key_flow_style_refuses"
}

# ── R12: SINGLE-quoted top-level 'store:' key, block-style value ──────────────────
test_single_quoted_top_level_key_block_style_refuses() {
  make_fixture r12-squote-top-block
  write_config "'store':
  tasks: jira
"
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: a single-quoted top-level 'store:' key with a block-style non-local value did not refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'unsupported TaskStore backend.*jira' \
    || fail "R12: the refusal does not name the jira backend for a single-quoted top-level key: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply deleted E01-F01-builder despite a single-quoted top-level store: key selecting a non-local backend"
  pass "R12 test_single_quoted_top_level_key_block_style_refuses"
}

# ── R12: bare top-level 'store:' key, QUOTED nested 'tasks:' key (block-style) ────
test_quoted_nested_tasks_key_block_style_refuses() {
  make_fixture r12-quoted-nested-block
  write_config 'store:
  "tasks": obsidian
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: a quoted nested 'tasks:' key (block-style) with a non-local value did not refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'unsupported TaskStore backend.*obsidian' \
    || fail "R12: the refusal does not name the obsidian backend for a quoted nested tasks: key: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply deleted E01-F01-builder despite a quoted nested tasks: key selecting a non-local backend"
  pass "R12 test_quoted_nested_tasks_key_block_style_refuses"
}

# ── R12: quoted top-level key + quoted nested key + quoted value, all at once ─────
test_quoted_key_and_quoted_value_combination_refuses() {
  make_fixture r12-quoted-key-and-value
  write_config '"store":
  "tasks": "obsidian"
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: a quoted top-level key + quoted nested key + quoted value did not refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'unsupported TaskStore backend.*obsidian' \
    || fail "R12: the refusal does not name the obsidian backend for the quoted key + quoted value combination: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply deleted E01-F01-builder despite a fully-quoted key/value store: shape selecting a non-local backend"
  pass "R12 test_quoted_key_and_quoted_value_combination_refuses"
}

# ── R12: quoted top-level key, explicit 'local' value still scans normally ────────
test_quoted_top_level_key_explicit_local_scans_normally() {
  make_fixture r12-quoted-top-local
  write_config '"store":
  tasks: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] || fail "R12: a quoted top-level 'store:' key with explicit 'tasks: local' was refused: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12: a quoted top-level 'store:' key with explicit 'tasks: local' did not scan/remove normally: $OUT"
  pass "R12 test_quoted_top_level_key_explicit_local_scans_normally"
}

# ── R12 (round-5 allowlist rewrite: exact repro + adversarial stress matrix) ──────
# This was the FIFTH consecutive round in which Codex found a distinct unrecognized
# store: shape in this exact function (block-only baseline -> flow-style value ->
# indented block -> quoted keys -> whole-document flow mapping). Round 5 stops
# enumerating accepted shapes and instead validates the WHOLE document against ONE
# canonical shape up front (validate_canonical_shape), refusing everything else.
# The exact repro pins the reported bug; the stress cases below are adversarial
# shapes no prior round tried, each asserting the parser either resolves the ONE
# canonical case correctly or refuses — never silently defaults to local when the
# real answer is unknown.

# ── R12: the exact round-5 repro — a whole-document flow mapping ──────────────────
test_whole_document_flow_mapping_refuses() {
  make_fixture r12-whole-doc-flow
  write_config '{store: {tasks: obsidian, docs: local}}
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12: a whole-document flow mapping did not refuse — the exact round-5 repro (Codex #4128053695): $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'cannot recognize' \
    || fail "R12: the refusal does not report an unrecognized document shape for a whole-document flow mapping: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12: --apply deleted E01-F01-builder despite a whole-document flow mapping whose real backend (obsidian) is unknown to this parser — the exact round-5 repro"
  pass "R12 test_whole_document_flow_mapping_refuses"
}

# ── R12 stress: multi-document YAML ('---' separator) refuses ────────────────────
test_multi_document_separator_refuses() {
  make_fixture r12-multidoc
  write_config '---
store:
  tasks: obsidian
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 stress: a multi-document '---' separator did not refuse: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 stress: --apply deleted E01-F01-builder despite a multi-document YAML file"
  pass "R12 stress test_multi_document_separator_refuses"
}

# ── R12 stress: an anchor on the store: key refuses ───────────────────────────────
test_anchor_on_store_key_refuses() {
  make_fixture r12-anchor
  write_config 'store: &store_anchor
  tasks: obsidian
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 stress: an anchor (&store_anchor) on the store: key did not refuse: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 stress: --apply deleted E01-F01-builder despite an anchored store: key selecting a non-local backend"
  pass "R12 stress test_anchor_on_store_key_refuses"
}

# ── R12 stress: a store: value that is itself a bare scalar (not a mapping) ──────
test_store_scalar_value_refuses() {
  make_fixture r12-store-scalar
  write_config 'store: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 stress: a bare scalar value directly on the store: line did not refuse: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 stress: --apply deleted E01-F01-builder despite a store: line whose own value is a scalar, not a resolvable mapping"
  pass "R12 stress test_store_scalar_value_refuses"
}

# ── R12 stress: deeply nested flow-style value refuses ────────────────────────────
test_deeply_nested_flow_refuses() {
  make_fixture r12-deep-flow
  write_config 'store: {tasks: {nested: obsidian}}
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 stress: a deeply nested flow-style store: value did not refuse: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 stress: --apply deleted E01-F01-builder despite a deeply nested flow-style store: value"
  pass "R12 stress test_deeply_nested_flow_refuses"
}

# ── R12 stress: a 'tasks:' key repeated at multiple indentation levels in different
# blocks resolves correctly (store's own block genuinely omits tasks:, so it must
# default to local rather than picking up a same-named key from an unrelated block).
test_tasks_key_at_multiple_levels_resolves_correctly() {
  make_fixture r12-multi-level-tasks
  write_config 'store:
  docs: local
other:
  tasks: obsidian
  nested:
    tasks: jira
tasks: attop
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 stress: a 'tasks:' key repeated at multiple indentation levels made the store's own (tasks-less) block unresolvable: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 stress: the store: block (which genuinely omits tasks:) did not default to local despite unrelated 'tasks:' keys elsewhere: $OUT"
  pass "R12 stress test_tasks_key_at_multiple_levels_resolves_correctly"
}

# ── R12 stress: 'store:' appearing only inside a comment resolves correctly ──────
test_store_mentioned_only_in_comment_resolves_correctly() {
  make_fixture r12-store-in-comment
  write_config '# store:
#   tasks: obsidian
other: value
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 stress: a 'store:' key mentioned only inside a comment was treated as a real store: block: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 stress: a commented-out store: mention did not default to local: $OUT"
  pass "R12 stress test_store_mentioned_only_in_comment_resolves_correctly"
}

# ── R12 stress: trailing/leading whitespace variations do not confuse the parser ──
test_whitespace_variations_resolve_correctly() {
  make_fixture r12-whitespace
  printf 'store:   \n  tasks:   jira   \n' > "$PRIMARY/harness.config.yaml"
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 stress: trailing whitespace around store:/tasks: lines did not refuse the correctly-resolved non-local (jira) backend: $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'unsupported TaskStore backend.*jira' \
    || fail "R12 stress: trailing/leading whitespace prevented correctly identifying the jira backend: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 stress: --apply deleted E01-F01-builder despite a whitespace-padded non-local store: block"
  pass "R12 stress test_whitespace_variations_resolve_correctly"
}

# ── R12 stress: a store: block indented under a key that already has a scalar
# value (invalid nesting) refuses rather than silently treating store: as absent ──
test_store_indented_under_scalar_valued_key_refuses() {
  make_fixture r12-invalid-nesting
  write_config 'foo: bar
    store:
      tasks: obsidian
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 stress: a store: block indented under a key that already carries a scalar value did not refuse: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 stress: --apply deleted E01-F01-builder despite an invalidly-nested store: block whose real backend is unknown"
  pass "R12 stress test_store_indented_under_scalar_valued_key_refuses"
}

# ── R12 stress: a leading UTF-8 BOM must not make a real store: block invisible ──
# A BOM'd first line reads as "﻿store:" to a naive line-prefix match, which
# would never match "store:" and silently conclude the block is absent -> default
# local, on a config that in fact selects a non-local backend. Round-5 residual gap,
# closed with encoding="utf-8-sig" (transparently strips a BOM if present).
test_leading_utf8_bom_does_not_hide_store_block() {
  make_fixture r12-utf8-bom
  printf '\357\273\277store:\n  tasks: obsidian\n' > "$PRIMARY/harness.config.yaml"
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 stress: a leading UTF-8 BOM hid a real non-local store: block instead of refusing: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 stress: --apply deleted E01-F01-builder despite a BOM'd config selecting a non-local backend"
  pass "R12 stress test_leading_utf8_bom_does_not_hide_store_block"
}

# ── R12 (round-6: unrelated block-style YAML sequences must not disqualify the
# document) ────────────────────────────────────────────────────────────────────────
# Codex #4128378011's exact repro: a real `store: tasks: local` block coexists with
# an unrelated top-level block-style list (`fix_lane.shared_paths:` written as
# `- item` lines, not `[]`). Round 5's whole-document validator rejected any line
# that was not a recognized `key:` mapping entry, including a legitimate list item
# nested under a key it never needed to resolve — the opposite failure class from
# rounds 1-5 (too permissive): this is a false refusal on a supported config shape.

test_unrelated_block_sequence_does_not_disqualify_document() {
  make_fixture r12-unrelated-sequence
  write_config 'store:
  tasks: local
fix_lane:
  shared_paths:
    - docs/generated/*
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-6: an unrelated block-style sequence (fix_lane.shared_paths) made a document with an explicit store.tasks: local refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-6: store.tasks: local did not scan/remove normally despite the unrelated sequence: $OUT"
  pass "R12 round-6 test_unrelated_block_sequence_does_not_disqualify_document"
}

test_unrelated_block_sequence_multiple_items_does_not_disqualify_document() {
  make_fixture r12-unrelated-sequence-multi
  write_config 'store:
  tasks: local
fix_lane:
  shared_paths:
    - docs/generated/*
    - another/generated/path
    - a/third/path
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-6: a multi-item unrelated block-style sequence made the document refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-6: store.tasks: local did not scan/remove normally despite a multi-item unrelated sequence: $OUT"
  pass "R12 round-6 test_unrelated_block_sequence_multiple_items_does_not_disqualify_document"
}

test_unrelated_empty_block_sequence_does_not_disqualify_document() {
  make_fixture r12-unrelated-sequence-empty-block
  write_config 'store:
  tasks: local
fix_lane:
  shared_paths:
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-6: an unrelated key with an empty block value (no list items at all) made the document refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-6: store.tasks: local did not scan/remove normally despite an unrelated empty-valued key: $OUT"
  pass "R12 round-6 test_unrelated_empty_block_sequence_does_not_disqualify_document"
}

test_unrelated_flow_style_empty_list_still_resolves_correctly() {
  make_fixture r12-unrelated-sequence-flow-empty
  write_config 'store:
  tasks: local
fix_lane:
  shared_paths: []
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-6: an unrelated flow-style empty list ([]) regressed — it must already have worked before this round's fix: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-6: store.tasks: local did not scan/remove normally with an unrelated flow-style empty list: $OUT"
  pass "R12 round-6 test_unrelated_flow_style_empty_list_still_resolves_correctly"
}

# ── R12 (round-6): a sequence item INSIDE the store: block itself is a different,
# more suspicious case — store:'s schema is a scalar or plain mapping, never a
# list, so this stays disqualifying rather than being skipped like an unrelated
# list elsewhere in the document (see tools/sweep-scratch.sh's
# find_store_key for the scoping rationale).
test_sequence_item_inside_store_block_still_refuses() {
  make_fixture r12-sequence-inside-store
  write_config 'store:
  tasks: local
  - unexpected
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 round-6: a sequence item nested inside the store: block itself did not refuse: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 round-6: --apply deleted E01-F01-builder despite an unrecognized sequence item inside the store: block"
  pass "R12 round-6 test_sequence_item_inside_store_block_still_refuses"
}

# ── R12 (round-7: a YAML feature nested under an UNRELATED top-level key must not
# disqualify the document, no matter which feature it is) ─────────────────────────
# Round 6 closed this gap for block-sequences specifically; Codex #4128789217 found
# the exact same false-refusal class one YAML feature over: a legitimate block
# scalar (`key: |` + indented continuation lines) under a top-level key this tool
# never reads. Round 7 stops enumerating tolerated features one at a time and
# narrows _cfg_store_tasks's scope instead (see find_store_key in
# tools/sweep-scratch.sh): content nested under any OTHER top-level key is walked
# past by indentation alone and never classified, so no YAML feature used there —
# block scalar, anchor/alias, flow mapping, or a literal '---'/'...' line embedded
# as ordinary block-scalar content — can ever trigger a refusal.

# ── the exact repro: a block scalar under an unrelated top-level key ─────────────
test_block_scalar_in_unrelated_section_does_not_disqualify_document() {
  make_fixture r12-block-scalar-unrelated
  write_config 'verification:
  test_command: |
    some command here
    another line
store:
  tasks: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-7: a block scalar under an unrelated top-level key (verification.test_command) made a document with an explicit store.tasks: local refuse — the exact repro (Codex #4128789217): $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-7: store.tasks: local did not scan/remove normally despite the unrelated block scalar: $OUT"
  pass "R12 round-7 test_block_scalar_in_unrelated_section_does_not_disqualify_document"
}

# ── adversarial: an anchor AND an alias, both nested under an unrelated key ───────
test_anchor_and_alias_in_unrelated_section_does_not_disqualify_document() {
  make_fixture r12-anchor-alias-unrelated
  write_config 'store:
  tasks: local
other:
  primary: &base_value hello
  secondary: *base_value
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-7: an anchor/alias pair nested under an unrelated top-level key made the document refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-7: store.tasks: local did not scan/remove normally despite the unrelated anchor/alias: $OUT"
  pass "R12 round-7 test_anchor_and_alias_in_unrelated_section_does_not_disqualify_document"
}

# ── adversarial: a flow mapping nested under an unrelated key ────────────────────
test_flow_mapping_in_unrelated_section_does_not_disqualify_document() {
  make_fixture r12-flow-mapping-unrelated
  write_config 'store:
  tasks: local
other:
  nested: {a: 1, b: 2}
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-7: a flow mapping nested under an unrelated top-level key made the document refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-7: store.tasks: local did not scan/remove normally despite the unrelated flow mapping: $OUT"
  pass "R12 round-7 test_flow_mapping_in_unrelated_section_does_not_disqualify_document"
}

# ── adversarial: literal '---'/'...' lines as block-scalar CONTENT under an
# unrelated key — not real document-separator markers, just text that happens to
# look like one, deep inside a section this tool never reads ──────────────────────
test_document_marker_lookalike_in_unrelated_block_scalar_does_not_disqualify_document() {
  make_fixture r12-marker-lookalike-unrelated
  write_config 'store:
  tasks: local
notes:
  changelog: |
    ---
    entry one
    ...
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-7: '---'/'...' lines inside an unrelated block scalar's own content made the document refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-7: store.tasks: local did not scan/remove normally despite the unrelated block-scalar content resembling document markers: $OUT"
  pass "R12 round-7 test_document_marker_lookalike_in_unrelated_block_scalar_does_not_disqualify_document"
}

# ── R12 (round-8: a block scalar's own CONTENT must stay opaque, even when that
# content itself reads like a `store:` line) ──────────────────────────────────────
# Round 7 stopped an unrelated block scalar's mere PRESENCE from disqualifying the
# document, but its header line (`key: |`) was still recorded as a "closed" frame
# (non-empty inline value), so a later content line that happened to start with
# `store:` was still key-matched against that closed frame and wrongly refused as
# `store:` invalidly nested under a scalar-valued key — Codex #4129040215. Round 8
# makes block-scalar content genuinely opaque: find_store_key() now recognizes the
# block-scalar header itself and skips every more-indented line after it
# unconditionally, never key-matching it at all.

# ── Codex's exact repro: block-scalar content containing a `store:`-shaped line,
# alongside a REAL top-level store: elsewhere in the document ────────────────────
test_block_scalar_content_shaped_like_store_key_does_not_disqualify_document() {
  make_fixture r12-block-scalar-content-looks-like-store
  write_config 'verification:
  test_command: |
    echo setup
    store: local
    echo teardown
store:
  tasks: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-8: block-scalar CONTENT that itself reads like 'store: local' made a document with a real top-level store: block refuse — Codex #4129040215: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-8: store.tasks: local did not scan/remove normally despite the store:-shaped block-scalar content: $OUT"
  pass "R12 round-8 test_block_scalar_content_shaped_like_store_key_does_not_disqualify_document"
}

# ── adversarial: block-scalar content interrupted by blank lines ─────────────────
test_block_scalar_with_blank_lines_in_content_does_not_disqualify_document() {
  make_fixture r12-block-scalar-blank-lines
  write_config 'verification:
  test_command: |
    echo one

    store: local

    echo two
store:
  tasks: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-8: blank lines inside an unrelated block scalar's content made the document refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-8: store.tasks: local did not scan/remove normally despite blank lines inside the block scalar: $OUT"
  pass "R12 round-8 test_block_scalar_with_blank_lines_in_content_does_not_disqualify_document"
}

# ── adversarial: a folded ('>') block scalar, not literal ('|') ──────────────────
test_folded_block_scalar_content_does_not_disqualify_document() {
  make_fixture r12-folded-block-scalar
  write_config 'notes:
  summary: >
    store: local
    this is folded text
store:
  tasks: local
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-8: a folded ('>') block scalar's content made the document refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-8: store.tasks: local did not scan/remove normally despite the folded block scalar: $OUT"
  pass "R12 round-8 test_folded_block_scalar_content_does_not_disqualify_document"
}

# ── adversarial: the block scalar is the LAST thing in the document — no trailing
# dedent line ever closes it; EOF must close it correctly, and the real store:
# block must still resolve because it appears BEFORE the trailing block scalar ────
test_block_scalar_at_end_of_document_closes_at_eof() {
  make_fixture r12-block-scalar-eof
  write_config 'store:
  tasks: local
verification:
  test_command: |
    store: local
    echo done
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -eq 0 ] \
    || fail "R12 round-8: a trailing block scalar with no closing dedent line (EOF) made the document refuse: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+removed$' \
    || fail "R12 round-8: store.tasks: local did not scan/remove normally despite the trailing, EOF-closed block scalar: $OUT"
  pass "R12 round-8 test_block_scalar_at_end_of_document_closes_at_eof"
}

# ── adversarial: a block scalar opening genuinely INSIDE store:'s own block is a
# different case — store:'s schema is a scalar or plain mapping, never a block
# scalar, so this stays disqualifying per the existing "ambiguous content inside
# store: refuses" contract, rather than being newly exempted like the cases above
# (see tools/sweep-scratch.sh's parse_store_tasks block-scanning loop, which this
# round's find_store_key change does not touch: find_store_key returns as soon as
# it finds the top-level store: line, before ever walking store:'s own children) ──
test_block_scalar_inside_store_block_still_refuses() {
  make_fixture r12-block-scalar-inside-store
  write_config 'store:
  tasks: local
  notes: |
    [not actually a list, just content]
'
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"}]}]}'
  scratch_dir E01-F01-builder

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R12 round-8: a block scalar nested inside the store: block itself, with disqualifying-looking content, did not refuse: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R12 round-8: --apply deleted E01-F01-builder despite an ambiguous block scalar inside the store: block"
  pass "R12 round-8 test_block_scalar_inside_store_block_still_refuses"
}

# ── R13 ─────────────────────────────────────────────────────────────────────────────
test_remove_failure_reported_and_exits_nonzero() {
  if ! modes_bind_this_uid; then
    echo "skip - R13 test_remove_failure_reported_and_exits_nonzero: mode bits do not bind this user (uid $(id -u)), so \`rm -rf\` cannot be made to fail here and this case cannot occur" >&2
    return 0
  fi

  make_fixture r13
  write_board '{"epics":[{"id":"E01","features":[{"id":"E01-F01","status":"done"},{"id":"E01-F09","status":"done"}]}]}'
  scratch_dir E01-F01-builder
  scratch_dir E01-F09-reviewer
  # E01-F01-builder sorts first (glob order) and is made unremovable: rm -rf cannot
  # empty it (0555, contains a file it cannot unlink), so this exercises BOTH "a
  # removal failure is reported and flips the exit code" and "the scan still
  # continues to the entry after it" in one fixture.
  chmod 0555 "$PRIMARY/scratchpad/E01-F01-builder"

  run_sweep --apply
  [ "$RC" -ne 0 ] \
    || fail "R13: an rm -rf failure on an eligible entry did not make --apply exit non-zero: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F01-builder[[:space:]]+skipped: remove-failed$' \
    || fail "R13: the failed removal was not reported as skipped: remove-failed: $OUT"
  printf '%s\n' "$OUT" | grep -qE '^E01-F09-reviewer[[:space:]]+removed$' \
    || fail "R13: a later eligible entry was not still removed after an earlier removal failed — the scan must not stop early: $OUT"
  printf '%s\n' "$OUT" | grep -q '^summary:' \
    || fail "R13: no summary line was printed despite a removal failure: $OUT"
  [ -d "$PRIMARY/scratchpad/E01-F01-builder" ] \
    || fail "R13: the entry rm -rf failed to remove no longer exists on disk"

  chmod 0755 "$PRIMARY/scratchpad/E01-F01-builder" 2>/dev/null || :
  pass "R13 test_remove_failure_reported_and_exits_nonzero"
}

test_default_is_dry_run_apply_mutates
test_classifies_feature_id_prefix_skips_unrecognized
test_done_feature_removed_on_apply_reported_dry_run
test_not_found_or_non_done_skipped
test_corrupt_taskstore_aborts_whole_scan_no_changes
test_schema_invalid_status_forged_row_aborts_whole_scan_no_changes
test_schema_invalid_id_aborts_whole_scan_no_changes
test_schema_invalid_status_null_aborts_whole_scan_no_changes
test_schema_invalid_status_missing_aborts_whole_scan_no_changes
test_schema_invalid_id_null_aborts_whole_scan_no_changes
test_schema_invalid_id_missing_aborts_whole_scan_no_changes
test_schema_invalid_non_string_types_abort_whole_scan_no_changes
test_symlink_escape_skipped
test_exit_code_reflects_tool_errors_only
test_report_has_summary_verdicts_and_bytes_reclaimed
test_scoped_vs_full_scan
test_dotglob_entries_included_in_unscoped_scan
test_unsupported_backend_refuses_before_touching_anything
test_unparseable_flow_style_store_block_refuses
test_absent_store_block_defaults_local
test_missing_config_file_refuses
test_explicit_key_mapping_at_top_level_refuses
test_block_style_explicit_local_scans_normally
test_block_style_non_local_jira_refuses
test_explicit_empty_tasks_value_refuses
test_indented_top_level_block_non_local_refuses
test_tab_indented_block_non_local_refuses
test_tasks_key_in_other_top_level_block_not_mistaken
test_double_quoted_top_level_key_flow_style_refuses
test_single_quoted_top_level_key_block_style_refuses
test_quoted_nested_tasks_key_block_style_refuses
test_quoted_key_and_quoted_value_combination_refuses
test_quoted_top_level_key_explicit_local_scans_normally
test_whole_document_flow_mapping_refuses
test_multi_document_separator_refuses
test_anchor_on_store_key_refuses
test_store_scalar_value_refuses
test_deeply_nested_flow_refuses
test_tasks_key_at_multiple_levels_resolves_correctly
test_store_mentioned_only_in_comment_resolves_correctly
test_whitespace_variations_resolve_correctly
test_store_indented_under_scalar_valued_key_refuses
test_leading_utf8_bom_does_not_hide_store_block
test_unrelated_block_sequence_does_not_disqualify_document
test_unrelated_block_sequence_multiple_items_does_not_disqualify_document
test_unrelated_empty_block_sequence_does_not_disqualify_document
test_unrelated_flow_style_empty_list_still_resolves_correctly
test_sequence_item_inside_store_block_still_refuses
test_block_scalar_in_unrelated_section_does_not_disqualify_document
test_anchor_and_alias_in_unrelated_section_does_not_disqualify_document
test_flow_mapping_in_unrelated_section_does_not_disqualify_document
test_document_marker_lookalike_in_unrelated_block_scalar_does_not_disqualify_document
test_block_scalar_content_shaped_like_store_key_does_not_disqualify_document
test_block_scalar_with_blank_lines_in_content_does_not_disqualify_document
test_folded_block_scalar_content_does_not_disqualify_document
test_block_scalar_at_end_of_document_closes_at_eof
test_block_scalar_inside_store_block_still_refuses
test_remove_failure_reported_and_exits_nonzero

echo "all sweep-scratch tests passed"
