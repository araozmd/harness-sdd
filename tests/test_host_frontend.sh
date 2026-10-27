#!/bin/sh
# test_host_frontend.sh — E99-F182: tools/host-frontend.sh, the producer of the host key that
# `tools/builder-role.sh --frontend` consumes (ADR-0011).
#
# Covers F182-R7 (one marker ⇒ key, none / empty ⇒ nothing, two ⇒ nothing + `ambiguous`,
# always exit 0, no files, no positional args) and F182-R8 (HARNESS_HOST_AGENT precedence
# and warning; the tool's marker rows equal the installer's HOST_MARKERS rows).
#
# ENVIRONMENT DISCIPLINE — the reason this is its own suite, copied from
# tests/test_agents_host.sh: the tool reads the AMBIENT environment, so a case that inherits
# the developer's shell tests nothing (it would pass inside a Claude Code session and fail
# outside one, or the reverse). Every run therefore goes through `frun`, the ONE place this
# suite names the tool, under `env -i` with PATH, a sandboxed HOME and exactly the named
# variables. No check freezes VERSION; no check diffs a DO-NOT-TOUCH file against `main`.
#
# Zero dependencies: POSIX sh + grep + awk + sed. Self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-hostfe)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

TOOL="$SRC/tools/host-frontend.sh"
INST="$SRC/harness-install.sh"
[ -f "$TOOL" ] || fail "setup: tools/host-frontend.sh does not exist"

# Every run executes with cwd = $T/run and HOME = $T/run/home, and writes its captured
# streams OUTSIDE $T/run, so `no_file_written` can prove the tool itself created nothing.
mkdir -p "$T/run/home" "$T/cap"

# frun [VAR=VALUE …] [-- tool-args…] — run the tool under `env -i`; stdout → $T/cap/out,
# stderr → $T/cap/err, exit status → $T/cap/rc. Arguments are rebuilt positionally, so a
# value with spaces (HARNESS_HOST_AGENT='claude codex') survives intact.
frun() {
  _fr_i=0; _fr_total=$#; _fr_seen=0
  while [ "$_fr_i" -lt "$_fr_total" ]; do
    if [ "$_fr_seen" = 0 ] && [ "$1" = "--" ]; then
      _fr_seen=1
      set -- "$@" sh "$TOOL"
    else
      set -- "$@" "$1"
    fi
    shift
    _fr_i=$((_fr_i + 1))
  done
  [ "$_fr_seen" = 1 ] || set -- "$@" sh "$TOOL"
  _fr_rc=0
  ( cd "$T/run" && env -i PATH="$PATH" HOME="$T/run/home" "$@" ) >"$T/cap/out" 2>"$T/cap/err" || _fr_rc=$?
  printf '%s\n' "$_fr_rc" > "$T/cap/rc"
}
out() { cat "$T/cap/out"; }
errs() { cat "$T/cap/err"; }
rcv() { cat "$T/cap/rc"; }

# installer_rows / tool_rows — the HOST_MARKERS rows (delimiter lines stripped), by the same
# POSITIONAL range tests/test_agents_host.sh::marker_table uses.
installer_rows() { sed -n '/^HOST_MARKERS="$/,/^"$/p' "$INST" | sed '1d;$d'; }
tool_rows()      { sed -n '/^HOST_MARKERS="$/,/^"$/p' "$TOOL" | sed '1d;$d'; }

touch "$T/stamp"

# ── F182-R7 ─────────────────────────────────────────────────────────────────────
# Every (key, variable) pair of the INSTALLER's table — the authority the tool copies — so a
# row dropped from the tool's copy reds here as well as in the parity check.
one_marker_each_row() {
  installer_rows > "$T/rows.txt"
  [ -s "$T/rows.txt" ] || fail "R7 setup: no HOST_MARKERS rows parsed from harness-install.sh"
  _pairs=0
  while read -r _key _vars; do
    [ -n "$_key" ] || continue
    for _var in $_vars; do
      frun "$_var=1"
      [ "$(out)" = "$_key" ] || fail "R7: $_var=1 alone printed '$(out)', expected '$_key'"
      [ -z "$(errs)" ]       || fail "R7: $_var=1 alone wrote to stderr: $(errs)"
      [ "$(rcv)" = 0 ]       || fail "R7: $_var=1 alone exited $(rcv)"
      _pairs=$((_pairs + 1))
    done
  done < "$T/rows.txt"
  [ "$_pairs" -ge 4 ] || fail "R7 setup: only $_pairs marker variables walked — the table did not parse"
  pass "one marker per row prints its key, for every variable of every row (F182-R7)"
}

no_marker_empty() {
  frun
  [ -z "$(out)" ]  || fail "R7: no marker printed '$(out)'"
  [ -z "$(errs)" ] || fail "R7: no marker wrote to stderr: $(errs)"
  [ "$(rcv)" = 0 ] || fail "R7: no marker exited $(rcv), not 0"
  pass "no marker prints nothing and exits 0 (F182-R7)"
}

empty_string_marker_not_present() {
  frun CLAUDECODE=
  [ -z "$(out)" ]  || fail "R7: CLAUDECODE set to the empty string printed '$(out)'"
  [ "$(rcv)" = 0 ] || fail "R7: an empty-string marker exited $(rcv)"
  # …and an empty marker beside a real one is not a second hit.
  frun CLAUDECODE= CODEX_THREAD_ID=x
  [ "$(out)" = codex ] || fail "R7: an empty CLAUDECODE beside CODEX_THREAD_ID printed '$(out)', not codex"
  [ -z "$(errs)" ]     || fail "R7: an empty CLAUDECODE counted as a hit: $(errs)"
  pass "a marker set to the empty string is not present (F182-R7)"
}

two_rows_ambiguous() {
  frun CLAUDECODE=1 CODEX_THREAD_ID=x
  [ -z "$(out)" ]  || fail "R7: two front-ends' markers printed '$(out)' — ambiguity must print nothing"
  [ "$(rcv)" = 0 ] || fail "R7: ambiguity exited $(rcv), not 0"
  [ "$(errs | grep -c .)" = 1 ] || fail "R7: ambiguity wrote not exactly one stderr line: $(errs)"
  errs | grep -q 'ambiguous' || fail "R7: the ambiguity warning does not say 'ambiguous': $(errs)"
  errs | grep -qw claude     || fail "R7: the ambiguity warning does not name claude: $(errs)"
  errs | grep -qw codex      || fail "R7: the ambiguity warning does not name codex: $(errs)"
  # Order-independent: the hit set is sorted, whatever order the table walks it in.
  frun PI_CODING_AGENT=true OPENCODE=1
  [ -z "$(out)" ] || fail "R7: opencode+pi markers printed '$(out)'"
  errs | grep -q 'opencode pi' || fail "R7: the ambiguity warning does not list the hits sorted: $(errs)"
  pass "two front-ends' markers print nothing and one sorted 'ambiguous' warning, exit 0 (F182-R7)"
}

same_row_two_vars_is_one_hit() {
  frun OPENCODE=1 OPENCODE_PID=2
  [ "$(out)" = opencode ] || fail "R7: two opencode markers printed '$(out)', not opencode"
  [ -z "$(errs)" ]        || fail "R7: two markers of ONE row warned: $(errs)"
  pass "two markers of one row are one hit (F182-R7)"
}

stdout_clean() {
  for _case in "CLAUDECODE=1 CODEX_THREAD_ID=x" "OPENCODE=1 PI_CODING_AGENT=true" "HARNESS_HOST_AGENT=bogus" "HARNESS_HOST_AGENT=bogus PI_CODING_AGENT=true"; do
    # shellcheck disable=SC2086  # each case is a list of VAR=VALUE words
    frun $_case
    [ -n "$(errs)" ] || fail "R7 setup: '$_case' produced no diagnostic, so it proves nothing about stdout"
    out | grep -q '⚠️' && fail "R7: '$_case' put a diagnostic on stdout: $(out)"
    out | grep -qi 'ambiguous\|ignoring' && fail "R7: '$_case' put diagnostic text on stdout: $(out)"
  done
  pass "diagnostics go to stderr only; stdout carries at most a key (F182-R7)"
}

positional_arg_usage() {
  for _a in --bogus claude -x; do
    frun -- "$_a"
    [ "$(rcv)" = 4 ] || fail "R7: argument '$_a' exited $(rcv), not 4"
    [ -z "$(out)" ]  || fail "R7: argument '$_a' printed '$(out)' on stdout"
    errs | grep -qi usage || fail "R7: argument '$_a' wrote no usage line to stderr"
  done
  frun CLAUDECODE=1 -- claude
  [ "$(rcv)" = 4 ] || fail "R7: a positional argument beside a marker exited $(rcv), not 4"
  for _h in --help -h; do
    frun -- "$_h"
    [ "$(rcv)" = 0 ]      || fail "R7: $_h exited $(rcv), not 0"
    out | grep -qi usage  || fail "R7: $_h printed no usage on stdout"
  done
  pass "positional / unknown arguments exit 4; --help / -h print usage and exit 0 (F182-R7)"
}

# ── F182-R8 ─────────────────────────────────────────────────────────────────────
declared_known_key_wins() {
  frun HARNESS_HOST_AGENT=codex CLAUDECODE=1
  [ "$(out)" = codex ] || fail "R8: HARNESS_HOST_AGENT=codex beside CLAUDECODE=1 printed '$(out)', not codex"
  [ -z "$(errs)" ]     || fail "R8: a valid declaration warned: $(errs)"
  # Every marker-row key is accepted as a declaration on its own, and beats ambiguity.
  for _k in claude codex opencode pi; do
    frun HARNESS_HOST_AGENT="$_k" CLAUDECODE=1 CODEX_THREAD_ID=x
    [ "$(out)" = "$_k" ] || fail "R8: HARNESS_HOST_AGENT=$_k over two markers printed '$(out)'"
    [ -z "$(errs)" ]     || fail "R8: HARNESS_HOST_AGENT=$_k still reported ambiguity: $(errs)"
  done
  # An EMPTY declaration is no declaration: markers decide, silently.
  frun HARNESS_HOST_AGENT= CLAUDECODE=1
  [ "$(out)" = claude ] || fail "R8: an empty HARNESS_HOST_AGENT did not fall through to markers"
  [ -z "$(errs)" ]      || fail "R8: an empty HARNESS_HOST_AGENT warned: $(errs)"
  pass "a declared marker-row key wins over markers and over ambiguity (F182-R8)"
}

# `antigravity` is a known INSTALLER key with no marker row — so it is never a host key.
declared_invalid_warns_then_detects() {
  for _v in 'claude codex' host gemini antigravity Claude 'claude pi'; do
    frun HARNESS_HOST_AGENT="$_v" PI_CODING_AGENT=true
    [ "$(out)" = pi ] || fail "R8: HARNESS_HOST_AGENT='$_v' + PI_CODING_AGENT printed '$(out)', not pi"
    [ "$(rcv)" = 0 ]  || fail "R8: HARNESS_HOST_AGENT='$_v' exited $(rcv)"
    [ "$(errs | grep -c .)" = 1 ] || fail "R8: HARNESS_HOST_AGENT='$_v' wrote not exactly one warning: $(errs)"
    errs | grep -qF "ignoring HARNESS_HOST_AGENT='$_v'" \
      || fail "R8: the warning for HARNESS_HOST_AGENT='$_v' does not name the value: $(errs)"
  done
  pass "an unusable HARNESS_HOST_AGENT warns once naming the value, then markers decide (F182-R8)"
}

declared_antigravity_alone_empty() {
  frun HARNESS_HOST_AGENT=antigravity
  [ -z "$(out)" ]  || fail "R8: HARNESS_HOST_AGENT=antigravity alone printed '$(out)' — it has no marker row"
  [ "$(rcv)" = 0 ] || fail "R8: HARNESS_HOST_AGENT=antigravity alone exited $(rcv)"
  errs | grep -qF "ignoring HARNESS_HOST_AGENT='antigravity'" \
    || fail "R8: HARNESS_HOST_AGENT=antigravity alone did not warn: $(errs)"
  pass "HARNESS_HOST_AGENT=antigravity alone is no key, warned (F182-R8)"
}

declared_invalid_no_marker_empty() {
  frun HARNESS_HOST_AGENT=gemini
  [ -z "$(out)" ]  || fail "R8: HARNESS_HOST_AGENT=gemini alone printed '$(out)'"
  [ "$(rcv)" = 0 ] || fail "R8: HARNESS_HOST_AGENT=gemini alone exited $(rcv) — the tool must never die"
  errs | grep -qF "ignoring HARNESS_HOST_AGENT='gemini'" \
    || fail "R8: HARNESS_HOST_AGENT=gemini alone did not warn: $(errs)"
  pass "a retired / unknown declaration with no marker prints nothing, warns, exits 0 (F182-R8)"
}

# The second copy stays ONE table: same keys, same variables, same order, byte for byte.
marker_rows_parity() {
  installer_rows > "$T/inst-rows.txt"
  tool_rows > "$T/tool-rows.txt"
  [ -s "$T/inst-rows.txt" ] || fail "R8: no HOST_MARKERS rows extracted from harness-install.sh — the block moved"
  [ -s "$T/tool-rows.txt" ] || fail "R8: no HOST_MARKERS rows extracted from tools/host-frontend.sh — the block moved"
  cmp -s "$T/inst-rows.txt" "$T/tool-rows.txt" \
    || fail "R8: tools/host-frontend.sh's HOST_MARKERS rows differ from harness-install.sh's: $(diff "$T/inst-rows.txt" "$T/tool-rows.txt" || true)"
  pass "the tool's marker rows equal the installer's HOST_MARKERS rows (F182-R8)"
}

# Must run LAST among the R7/R8 cases: it audits every run above.
no_file_written() {
  _new="$(find "$T/run" -newer "$T/stamp" 2>/dev/null)"
  [ -z "$_new" ] || fail "R7: the tool wrote into its cwd / HOME: $_new"
  [ -z "$(find "$T/run" -mindepth 1 ! -path "$T/run/home" 2>/dev/null)" ] \
    || fail "R7: the tool left files in its cwd: $(find "$T/run" -mindepth 1 ! -path "$T/run/home")"
  pass "no run created or touched a file in its cwd or HOME (F182-R7)"
}

one_marker_each_row
no_marker_empty
empty_string_marker_not_present
two_rows_ambiguous
same_row_two_vars_is_one_hit
stdout_clean
positional_arg_usage
declared_known_key_wins
declared_invalid_warns_then_detects
declared_antigravity_alone_empty
declared_invalid_no_marker_empty
marker_rows_parity
no_file_written

echo "test_host_frontend.sh: ALL PASSED"
