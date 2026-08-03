#!/bin/sh
# test_init_drift_guard.sh — behavioral verification for E24-F01 (init.sh drift guard:
# refuse to run on an unlanded harness).
#
# NOT a prose-grep suite. The feature is executable logic in init.sh, so every case builds
# a REAL installed target (git init + harness-install.sh + commit), perturbs exactly one
# thing, runs the installed .harness/init.sh, and reads its exit code and output. Unlike
# the doc-and-contract features verified by required-phrase greps (test_drift_check.sh —
# unrelated E06-F06 epic-rollup drift, name collision only — or test_architect_adr.sh),
# a grep over init.sh here would assert that the source contains words, not that the gate
# stops anything.
#
# ANTI-TAUTOLOGY. Four requirements assert an ABSENCE (R6, R7: silent skip) or a PASS
# (R4, R10). Both are satisfied by a guard that does nothing at all, so each is paired
# with a POSITIVE CONTROL on the same fixture proving the guard was live and would have
# fired — only the one discriminating fact differs between the two runs. An expected value
# with more than one producing code path proves nothing (recurred in this repo, E99-F07).
#
# Suite-wide constraints (permanent-suite anti-pattern, recurred repeatedly): never assert
# an exact VERSION literal; never couple a CHANGELOG assertion to the current top version;
# never git-diff a DO-NOT-TOUCH file against main; never mutate the live state/tasks.json,
# specs/ or progress/ (every fixture is under its own mktemp -d); sandbox CODEX_HOME AND
# HOME on every harness-install.sh invocation. Zero deps: POSIX sh + git.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# mk_target <dir> — a fully installed, fully committed harness target.
mk_target() {
  _t="$1"
  mkdir -p "$_t"
  git -C "$_t" init -q .
  git -C "$_t" config user.email "test@harness.local"
  git -C "$_t" config user.name  "harness test"
  CODEX_HOME="$_t/.codex-home" HOME="$_t/.home" \
    sh "$SRC/harness-install.sh" --agents=claude "$_t" >/dev/null 2>&1 \
    || fail "harness-install.sh exited non-zero for $_t"
  [ -f "$_t/.harness/.harness-version" ] || fail "install produced no .harness-version in $_t"
  git -C "$_t" add -A
  git -C "$_t" commit -q -m "installed harness"
  # Precondition for the whole suite: a freshly committed install is clean. If this is
  # ever false the fixture is lying and every later assertion is meaningless.
  [ -z "$(git -C "$_t" status --porcelain)" ] || fail "fixture $_t is dirty right after commit"
}

# run_gate <dir> — run the installed gate, capture combined output + exit code into
# GATE_OUT / GATE_RC. Never aborts the suite (set -e safe).
run_gate() {
  GATE_OUT="$(cd "$1" && sh .harness/init.sh 2>&1)" && GATE_RC=0 || GATE_RC=$?
}

T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-drift)"
trap 'rm -rf "$T"' EXIT

# ── R1 + R10: the check runs on an installed target, and a clean one passes ───────
# R1_check_runs_on_installed_target / R10_clean_passes
mk_target "$T/clean"
run_gate "$T/clean"
[ "$GATE_RC" = "0" ] || fail "R1/R10: clean installed target failed the gate (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "installed harness matches" \
  || fail "R1/R10: clean target printed no success line — the check did not run: $GATE_OUT"
pass "clean installed target runs the check and passes (R1, R10) [R1_check_runs_on_installed_target/R10_clean_passes]"

# ── R2: an uncommitted harness-owned change fails the gate ────────────────────────
# R2_drift_fails_gate
mk_target "$T/drift"
echo "# unlanded edit" >> "$T/drift/.harness/agents/builder.md"
run_gate "$T/drift"
[ "$GATE_RC" != "0" ] || fail "R2: drifted target PASSED the gate — the guard is inert"
printf '%s' "$GATE_OUT" | grep -qi "not committed" \
  || fail "R2: failure message does not say the harness is not committed: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qE "1 harness-owned path" \
  || fail "R2: failure message does not name the drifted-path count: $GATE_OUT"
pass "uncommitted harness-owned change fails the gate with a counted message (R2) [R2_drift_fails_gate]"

# ── R3: the message lists paths, caps the list, and hands over the full command ───
# R3_message_lists_and_caps
mk_target "$T/many"
i=1
while [ "$i" -le 14 ]; do
  echo "# unlanded edit $i" >> "$T/many/.harness/docs/HARNESS.md"
  printf '# drifted %s\n' "$i" > "$T/many/.harness/agents/extra-$i.md"
  i=$((i + 1))
done
run_gate "$T/many"
[ "$GATE_RC" != "0" ] || fail "R3: 14-file drift PASSED the gate"
# At most 10 sample lines are printed (they are the indented ones carrying a git status
# XY code). Counting them pins the cap; without this a future 'print everything' regression
# is invisible.
SAMPLE_N="$(printf '%s\n' "$GATE_OUT" | grep -cE '^     [ MARCDU?][ MARCDU?] ' || true)"
[ "$SAMPLE_N" -le 10 ] || fail "R3: printed $SAMPLE_N sample paths, cap is 10: $GATE_OUT"
[ "$SAMPLE_N" -gt 0 ]  || fail "R3: printed no sample paths at all: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -q "more" \
  || fail "R3: elided paths but printed no '… N more …' marker: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -q "status --porcelain" \
  || fail "R3: no command offered to list the remaining paths: $GATE_OUT"
pass "message lists a capped sample and offers the listing command (R3) [R3_message_lists_and_caps]"

# ── R4: project-owned paths are excluded — with a positive control ────────────────
# R4_project_owned_excluded
# ONE fixture, TWO perturbations. A guard that excluded everything would pass the first
# assertion; a guard that excluded nothing would fail it. Only correct scoping passes both.
mk_target "$T/owned"
printf '\n# local project tweak\n' >> "$T/owned/.harness/harness.config.yaml"
printf '{"note":"local"}\n' > "$T/owned/.harness/progress/scratch.md"
run_gate "$T/owned"
[ "$GATE_RC" = "0" ] \
  || fail "R4: project-owned changes (harness.config.yaml, progress/) failed the gate: $GATE_OUT"
pass "project-owned changes alone do not trip the guard (R4) [R4_project_owned_excluded]"
# positive control on the SAME tree
echo "# unlanded edit" >> "$T/owned/.harness/agents/reviewer.md"
run_gate "$T/owned"
[ "$GATE_RC" != "0" ] \
  || fail "R4 control: a harness-owned change in the same tree PASSED — the guard excludes everything"
pass "…and a harness-owned change in that same tree still fails (R4 control) [R4_project_owned_excluded]"

# ── R5: root-level generated glue is in scope ─────────────────────────────────────
# R5_root_glue_in_scope
mk_target "$T/glue"
[ -f "$T/glue/.claude/agents/builder.md" ] \
  || fail "R5: fixture has no .claude/agents/builder.md — --agents=claude did not generate the glue"
echo "# unlanded edit" >> "$T/glue/.claude/agents/builder.md"
run_gate "$T/glue"
[ "$GATE_RC" != "0" ] \
  || fail "R5: drift in root-level .claude/agents/ PASSED — the guard only looks inside .harness/"
pass "root-level generated glue is inside the checked set (R5) [R5_root_glue_in_scope]"

# ── R6: no install stamp ⇒ silent skip — with a positive control ──────────────────
# R6_uninstalled_is_silent
# Same target, same perturbation, asserted twice; ONLY .harness-version differs. A guard
# keyed on the `*/.harness` directory suffix instead of the stamp passes the second
# assertion and fails this pair.
mk_target "$T/stamp"
echo "# unlanded edit" >> "$T/stamp/.harness/agents/builder.md"
run_gate "$T/stamp"
[ "$GATE_RC" != "0" ] || fail "R6 control: drifted target with a stamp PASSED — guard inert"
pass "with .harness-version present the drift fails (R6 control) [R6_uninstalled_is_silent]"
rm -f "$T/stamp/.harness/.harness-version"
run_gate "$T/stamp"
[ "$GATE_RC" = "0" ] \
  || fail "R6: target with no .harness-version failed the gate (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "drift\|not committed\|matches the commit" \
  && fail "R6: uninstalled target mentioned the drift check — must be silent: $GATE_OUT"
pass "no .harness-version ⇒ check skipped silently (R6) [R6_uninstalled_is_silent]"

# ── R7: not a git work tree ⇒ silent skip — with a positive control ───────────────
# R7_non_git_is_silent
mk_target "$T/nogit"
echo "# unlanded edit" >> "$T/nogit/.harness/agents/builder.md"
run_gate "$T/nogit"
[ "$GATE_RC" != "0" ] || fail "R7 control: drifted git target PASSED — guard inert"
pass "with git present the drift fails (R7 control) [R7_non_git_is_silent]"
rm -rf "$T/nogit/.git"
run_gate "$T/nogit"
[ "$GATE_RC" = "0" ] || fail "R7: non-git target failed the gate (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "drift\|not committed\|matches the commit" \
  && fail "R7: non-git target mentioned the drift check — must be silent: $GATE_OUT"
pass "no git work tree ⇒ check skipped silently (R7) [R7_non_git_is_silent]"

# ── R8: the escape hatch works and is LOUD ────────────────────────────────────────
# R8_escape_hatch_is_loud
mk_target "$T/hatch"
echo "# unlanded edit" >> "$T/hatch/.harness/agents/builder.md"
run_gate "$T/hatch"
[ "$GATE_RC" != "0" ] || fail "R8 control: drifted target PASSED before the override was applied"
GATE_OUT="$(cd "$T/hatch" && HARNESS_SKIP_DRIFT_CHECK=1 sh .harness/init.sh 2>&1)" && GATE_RC=0 || GATE_RC=$?
[ "$GATE_RC" = "0" ] || fail "R8: HARNESS_SKIP_DRIFT_CHECK=1 did not let the drifted target through: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "skip" \
  || fail "R8: the override was silent — an overridden gate must say so: $GATE_OUT"
pass "HARNESS_SKIP_DRIFT_CHECK skips the check and announces it (R8) [R8_escape_hatch_is_loud]"

# ── R9: an un-version-controlled body warns, never fails ──────────────────────────
# R9_untracked_body_warns_not_fails
# THE ORDER TEST. `git status --porcelain -- .harness/` reports `?? .harness/` when nothing
# is tracked — non-empty. An implementation that ran status BEFORE ls-files would read this
# as drift and hard-fail, which is the exact false positive R9 exists to prevent. This case
# fails loudly if a refactor ever swaps the two git calls.
mkdir -p "$T/untracked"
git -C "$T/untracked" init -q .
CODEX_HOME="$T/untracked/.codex-home" HOME="$T/untracked/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$T/untracked" >/dev/null 2>&1 \
  || fail "R9: harness-install.sh exited non-zero"
# deliberately never `git add`
[ "$(git -C "$T/untracked" ls-files -- .harness/ | wc -l | tr -d ' ')" = "0" ] \
  || fail "R9: fixture precondition broken — something is tracked under .harness/"
[ -n "$(git -C "$T/untracked" status --porcelain -- .harness/)" ] \
  || fail "R9: fixture precondition broken — git status reports nothing for an untracked .harness/"
run_gate "$T/untracked"
[ "$GATE_RC" = "0" ] \
  || fail "R9: an untracked (never-committed) harness body FAILED the gate — status ran before ls-files: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "not version-controlled" \
  || fail "R9: no warning that drift cannot be verified: $GATE_OUT"
pass "un-version-controlled body warns and does not fail (R9) [R9_untracked_body_warns_not_fails]"

echo "All init drift-guard tests passed."
