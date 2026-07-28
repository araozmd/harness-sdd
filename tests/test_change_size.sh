#!/bin/sh
# test_change_size.sh — E21-F02: the advisory pre-PR change-size check.
#
# Behavioral, not textual: every assertion drives tools/change-size.sh against a REAL
# throwaway git repo with a known diff, because the whole value of this tool is the number
# it produces. A grep over the script would prove nothing about whether a test file is
# counted as production — which is the failure mode that makes the number meaningless.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never git-diff a DO-NOT-TOUCH file against main; never mutate the live
# state/tasks.json.
#
# Zero deps: POSIX sh + git + awk.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/tools/change-size.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t chgsize)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v git >/dev/null 2>&1 || { echo "skip - git unavailable"; exit 0; }

# ── fixture: a repo with main + a feature branch carrying a known, classified diff ──────
mkrepo() { # mkrepo <dir>
  _r="$1"; mkdir -p "$_r"
  git -C "$_r" init -q
  git -C "$_r" config user.email t@example.com
  git -C "$_r" config user.name  T
  git -C "$_r" checkout -q -b main
  printf 'seed\n' > "$_r/seed.txt"
  # The fixture rewrites .harness/harness.config.yaml between assertions to vary the budget.
  # Ignore it here so those rewrites never land IN the measured diff — otherwise the tool
  # would (correctly) count the config as production and every expected count would drift.
  printf '.harness/\n' > "$_r/.gitignore"
  git -C "$_r" add -A && git -C "$_r" commit -qm seed
}

# n_lines <count> — emit <count> distinct lines
n_lines() { i=1; while [ "$i" -le "$1" ]; do printf 'line %d\n' "$i"; i=$((i+1)); done; }

R="$T/repo"; mkrepo "$R"
git -C "$R" checkout -q -b feature
mkdir -p "$R/src" "$R/tests" "$R/specs" "$R/vendor"
n_lines 40  > "$R/src/app.js"        # production
n_lines 10  > "$R/src/util.js"       # production
n_lines 300 > "$R/tests/app.test.js" # test  — must NOT count as production
n_lines 200 > "$R/specs/design.md"   # doc   — must NOT count as production
n_lines 900 > "$R/vendor/lib.js"     # generated — excluded entirely
git -C "$R" add -A && git -C "$R" commit -qm work

# ── R1: classification — tests/docs/generated never inflate the production number ────────
out="$("$TOOL" --repo "$R" --base main --format json)"
_get() { printf '%s' "$out" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }
[ "$(_get production_lines)" = "50" ] \
  || fail "R1: production_lines=$(_get production_lines), expected 50 (tests/docs/generated must not count)"
[ "$(_get production_files)" = "2" ] \
  || fail "R1: production_files=$(_get production_files), expected 2"
[ "$(_get test_lines)" = "300" ]      || fail "R1: test_lines=$(_get test_lines), expected 300"
[ "$(_get doc_lines)" = "200" ]       || fail "R1: doc_lines=$(_get doc_lines), expected 200"
[ "$(_get generated_lines)" = "900" ] || fail "R1: generated_lines=$(_get generated_lines), expected 900"
[ "$(_get total_lines)" = "1450" ]    || fail "R1: total_lines=$(_get total_lines), expected 1450"
pass "R1 classification: production excludes tests, docs and generated files"

# ── R2: tiers come from config, and the tool NEVER blocks ────────────────────────────────
# 50 production lines against a tiny budget must reach every tier, and exit 0 every time.
mkdir -p "$R/.harness"
cfgw() { printf 'change_size:\n  advise_lines: %s\n  escalate_lines: %s\n  advise_files: %s\n  escalate_files: %s\n' \
           "$1" "$2" "$3" "$4" > "$R/.harness/harness.config.yaml"; }
tier_of() { "$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"tier":"\([a-z]*\)".*/\1/p'; }

cfgw 1000 2000 50 100
"$TOOL" --repo "$R" --base main >/dev/null || fail "R2: exit non-zero at tier ok — the check must never block"
[ "$(tier_of)" = "ok" ]       || fail "R2: expected tier ok under a generous budget, got $(tier_of)"
cfgw 20 2000 50 100
"$TOOL" --repo "$R" --base main >/dev/null || fail "R2: exit non-zero at tier advise — the check must never block"
[ "$(tier_of)" = "advise" ]   || fail "R2: expected tier advise (50 > advise_lines 20), got $(tier_of)"
cfgw 20 30 50 100
"$TOOL" --repo "$R" --base main >/dev/null || fail "R2: exit non-zero at tier escalate — the check must never block"
[ "$(tier_of)" = "escalate" ] || fail "R2: expected tier escalate (50 > escalate_lines 30), got $(tier_of)"
pass "R2 tiers read from config; exit 0 at ok, advise AND escalate (never blocks)"

# ── R3: the FILE budget trips independently of the line budget ───────────────────────────
# 60 one-line edits is a different review object than one 600-line file; a lines-only budget
# would wave the first one through.
cfgw 100000 200000 1 2
[ "$(tier_of)" = "advise" ] \
  || fail "R3: file budget did not trip on its own (2 production files > advise_files 1), got $(tier_of)"
pass "R3 file budget trips independently of the line budget"

# ── R4: an ABSENT change_size block falls back to the documented defaults ────────────────
rm -f "$R/.harness/harness.config.yaml"
out="$("$TOOL" --repo "$R" --base main --format json)"
printf '%s' "$out" | grep -qF '"advise_lines":1500'   || fail "R4: absent block did not default advise_lines to 1500"
printf '%s' "$out" | grep -qF '"escalate_lines":3000' || fail "R4: absent block did not default escalate_lines to 3000"
printf '%s' "$out" | grep -qF '"advise_files":25'     || fail "R4: absent block did not default advise_files to 25"
printf '%s' "$out" | grep -qF '"escalate_files":50'   || fail "R4: absent block did not default escalate_files to 50"
[ "$(tier_of)" = "ok" ] || fail "R4: 50 production lines should be ok under the defaults"
pass "R4 absent change_size block ⇒ documented defaults (1500/3000/25/50)"

# ── R5: measured against the MERGE BASE, not the base tip ────────────────────────────────
# Advance main after branching. A `git diff main...HEAD` (merge base) sees only the branch's
# own work; a `git diff main HEAD` would also report main's new commit as a deletion.
git -C "$R" checkout -q main
n_lines 500 > "$R/unrelated.js"        # repo root: src/ exists only on the feature branch
git -C "$R" add -A && git -C "$R" commit -qm "main moves on"
git -C "$R" checkout -q feature
[ "$("$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "50" ] \
  || fail "R5: production count changed after main advanced — not measuring from the merge base"
pass "R5 measures from the merge base, so an advanced base ref does not distort the count"

# ── R6: concentration is reported when over budget (where to cut, not just how big) ──────
cfgw 20 30 50 100
txt="$("$TOOL" --repo "$R" --base main)"
printf '%s' "$txt" | grep -q 'src/app.js'  || fail "R6: over-budget report does not name the top production file"
printf '%s' "$txt" | grep -qi 'escalate'   || fail "R6: over-budget report does not name the tier"
printf '%s' "$txt" | grep -qi 'advisory'   || fail "R6: report does not state that the check is advisory"
cfgw 1000 2000 50 100
printf '%s' "$("$TOOL" --repo "$R" --base main)" | grep -q 'src/app.js' \
  && fail "R6: in-budget report should not print the concentration list" || :
pass "R6 concentration list printed only when over budget, and names the heaviest file"

# ── R7: extra classifier patterns are ADDITIVE to the built-ins ──────────────────────────
mkdir -p "$R/spec"
# Deliberately NOT `thing_spec.rb` — that already matches the built-in `[._-]spec.<ext>`
# pattern, so it would prove nothing about the config hook. `spec/thing.rb` is a real shape
# (a Ruby/RSpec tree keyed on the DIRECTORY) that the built-ins miss by design.
n_lines 70 > "$R/spec/thing.rb"
git -C "$R" add -A && git -C "$R" commit -qm "ruby-style specs"
[ "$("$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "120" ] \
  || fail "R7 fixture: an unclassified spec/ dir should count as production before configuring"
{ printf 'change_size:\n  advise_lines: 1000\n  escalate_lines: 2000\n  advise_files: 50\n  escalate_files: 100\n'
  printf '  test_paths:\n    - "(^|/)spec/"\n'; } > "$R/.harness/harness.config.yaml"
[ "$("$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "50" ] \
  || fail "R7: change_size.test_paths did not reclassify spec/ out of the production count"
[ "$("$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"test_lines":\([0-9]*\).*/\1/p')" = "370" ] \
  || fail "R7: extra test_paths REPLACED the built-ins instead of extending them (tests/app.test.js lost)"
pass "R7 change_size.test_paths extends the built-in classifiers, never replaces them"

# ── R8: usage errors are the ONLY non-zero exit, and they measure nothing ────────────────
if "$TOOL" --repo "$T/definitely-not-a-repo" --base main >/dev/null 2>&1; then
  fail "R8: a non-git directory should exit 4"
fi
"$TOOL" --repo "$T/definitely-not-a-repo" --base main >/dev/null 2>&1 || _rc=$?
[ "${_rc:-0}" = "4" ] || fail "R8: non-git directory exited ${_rc:-0}, expected 4"
"$TOOL" --repo "$R" --base no/such/ref >/dev/null 2>&1 || _rc2=$?
[ "${_rc2:-0}" = "4" ] || fail "R8: unresolvable base ref exited ${_rc2:-0}, expected 4"
"$TOOL" --format bogus --repo "$R" >/dev/null 2>&1 || _rc3=$?
[ "${_rc3:-0}" = "4" ] || fail "R8: bad --format exited ${_rc3:-0}, expected 4"
pass "R8 exit 4 for not-a-repo / unresolvable base / bad --format; never for a large diff"

# ── R9: the Reviewer and Orchestrator carry the handoff rule ─────────────────────────────
grep -qF 'tools/change-size.sh' "$ROOT/agents/reviewer.md" \
  || fail "R9: reviewer.md does not run the change-size check before the PR handoff"
grep -qF 'tools/change-size.sh' "$ROOT/agents/orchestrator.md" \
  || fail "R9: orchestrator.md does not run the change-size check before opening the PR"
grep -qi 'never blocks' "$ROOT/agents/reviewer.md" \
  || fail "R9: reviewer.md does not state that the change-size check never blocks"
grep -qi 'recorded decision\|record one line\|split plan' "$ROOT/agents/reviewer.md" \
  || fail "R9: reviewer.md does not require a recorded decision at advise/escalate"
pass "R9 reviewer + orchestrator carry the advisory handoff rule"

echo "All change-size tests passed."
