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
#
# EXECUTE IT, do not `sh` it. init.sh is `#!/usr/bin/env bash` + `set -euo pipefail`, and
# on any system where /bin/sh is dash (Ubuntu CI, and this macOS box via `dash`) `sh
# .harness/init.sh` dies at line 8 with `set: Illegal option -o pipefail` — before the
# drift guard runs at all. The bash array `HARNESS_OWNED=(...)` is equally un-POSIX. So an
# `sh`-invoked suite tests the interpreter, not the gate: every case would fail for the
# same reason in CI while passing on a macOS box whose /bin/sh is bash in POSIX mode.
run_gate() {
  GATE_OUT="$(cd "$1" && ./.harness/init.sh 2>&1)" && GATE_RC=0 || GATE_RC=$?
  # Shared postcondition for EVERY case: the script must actually have executed. Without
  # this, an interpreter-level death (wrong shell, missing shebang, non-executable bit)
  # is indistinguishable from a gate that ran and failed — which is precisely how the
  # `sh`-invoked version of this suite looked green in one environment and red in another.
  case "$GATE_OUT" in
    *"harness-sdd init"*) : ;;
    *) fail "init.sh did not execute in $1 (no banner) — interpreter error, not a gate verdict: $GATE_OUT" ;;
  esac
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
GATE_OUT="$(cd "$T/hatch" && HARNESS_SKIP_DRIFT_CHECK=1 ./.harness/init.sh 2>&1)" && GATE_RC=0 || GATE_RC=$?
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

# ── R2 regression: status.showUntrackedFiles=no must not hide an unlanded file ────
# R2_untracked_hidden_by_config_still_caught
# A repo or global gitconfig can set status.showUntrackedFiles=no, and `git status
# --porcelain` silently inherits it. An upgrade that ADDS a harness-owned file leaves that
# file untracked — so without an explicit -uall the guard prints "matches the commit" over
# an unlanded file. Reported as P2 on PR #98; kept as a first-class case because a guard
# that reports clean while drift exists is worse than no guard.
mk_target "$T/hidden"
git -C "$T/hidden" config status.showUntrackedFiles no
printf '# added by an upgrade, never committed\n' > "$T/hidden/.harness/agents/unlanded-new.md"
# Precondition: without -uall this really is invisible. If git ever changes that, this
# case would silently stop testing anything.
[ -z "$(git -C "$T/hidden" status --porcelain -- .harness/)" ] \
  || fail "R2-regression: fixture precondition broken — showUntrackedFiles=no did not hide the file"
run_gate "$T/hidden"
[ "$GATE_RC" != "0" ] \
  || fail "R2-regression: an untracked harness-owned file was hidden by status.showUntrackedFiles=no — the guard needs -uall: $GATE_OUT"
pass "untracked drift is caught even under status.showUntrackedFiles=no (R2) [R2_untracked_hidden_by_config_still_caught]"

# ── R3 regression: the recovery command reproduces the ACTUAL checked path set ─────
# R3_recovery_command_matches_checked_set
# The advertised command must list the same paths the guard checked. An approximation
# drifts silently: the first version printed `.harness/ .claude/ .agents/`, omitting the
# checked .codex/agents/, .gemini/agents/ and opencode.json and dropping every :(exclude) —
# so drift confined to .codex/agents/ tripped the gate and was then invisible to the one
# command offered for inspecting it. Reported as P2 on PR #98.
mk_target "$T/reco"
i=1
while [ "$i" -le 12 ]; do
  printf '# drifted %s\n' "$i" > "$T/reco/.claude/commands/generated-$i.md"
  i=$((i + 1))
done
run_gate "$T/reco"
[ "$GATE_RC" != "0" ] || fail "R3-regression: drift confined to .claude/commands/ PASSED the gate: $GATE_OUT"
RECO="$(printf '%s\n' "$GATE_OUT" | grep 'list them:' || true)"
[ -n "$RECO" ] || fail "R3-regression: no recovery command printed: $GATE_OUT"
# `.codex/agents/`/`.gemini/agents/` are deliberately NOT expected here: since E99-F10 they
# are claimed per-file from the installer's ownership ledger, and a claude-only target has
# no such ledger — so their absence from this command is correct, not a gap.
for want in ".claude/commands/" ".opencode/command/" "opencode.json" ":(exclude).harness/state/"; do
  case "$RECO" in
    *"$want"*) : ;;
    *) fail "R3-regression: recovery command omits '$want' — it does not reproduce the checked set: $RECO" ;;
  esac
done
case "$RECO" in
  *"-uall"*) : ;;
  *) fail "R3-regression: recovery command omits -uall, so it would not show the untracked drift it is offered for: $RECO" ;;
esac
pass "recovery command reproduces the actual checked pathspec set (R3) [R3_recovery_command_matches_checked_set]"

# ── R4 regression: `.agents/` is a USER-owned tree — do not claim all of it ───────
# R4_user_owned_agents_tree_not_claimed
# The install manifest owns only `.agents/{rules,agents,workflows}/*` and the `sdd-*` skill
# units, and calls `.agents/` itself user-owned. A blanket `.agents/` pathspec would fail
# the mandatory gate on a project's own file there — halting all agent work, which is the
# dominant risk this feature declared. Reported as P2 on PR #98 round 2.
mk_target "$T/userglue"
mkdir -p "$T/userglue/.agents/skills/mine"
printf '# our own skill, nothing to do with the harness\n' > "$T/userglue/.agents/skills/mine/SKILL.md"
printf '# our own note\n' > "$T/userglue/.agents/notes.md"
run_gate "$T/userglue"
[ "$GATE_RC" = "0" ] \
  || fail "R4-regression: a project's own files under the user-owned .agents/ tree failed the gate: $GATE_OUT"
pass "project files in the user-owned .agents/ tree do not trip the guard (R4) [R4_user_owned_agents_tree_not_claimed]"
# positive control: the sdd-* skill units in that same tree ARE harness-owned
mkdir -p "$T/userglue/.agents/skills/sdd-drill"
printf '# unlanded\n' > "$T/userglue/.agents/skills/sdd-drill/SKILL.md"
run_gate "$T/userglue"
[ "$GATE_RC" != "0" ] \
  || fail "R4-regression control: an unlanded .agents/skills/sdd-*/SKILL.md PASSED — the glob claims nothing"
pass "…while sdd-* skill units in that same tree still are (R4 control) [R4_user_owned_agents_tree_not_claimed]"

# ── R5 regression: generated OpenCode glue is in scope ────────────────────────────
# R5_opencode_glue_in_scope
# `.opencode/command/*` and the optional `.opencode/agent/pr-fixer.md` are regenerated by
# the installer, and were outside every pathspec — so an opencode target printed
# "matches the commit" over edited harness glue. Reported as P2 on PR #98 round 2.
mkdir -p "$T/oc"
git -C "$T/oc" init -q .
git -C "$T/oc" config user.email "test@harness.local"
git -C "$T/oc" config user.name "harness test"
CODEX_HOME="$T/oc/.codex-home" HOME="$T/oc/.home" \
  sh "$SRC/harness-install.sh" --agents=opencode "$T/oc" >/dev/null 2>&1 \
  || fail "R5-regression: opencode install exited non-zero"
git -C "$T/oc" add -A
git -C "$T/oc" commit -q -m "installed harness (opencode)"
OC_CMD="$(ls "$T/oc"/.opencode/command/*.md 2>/dev/null | head -n1 || true)"
[ -n "$OC_CMD" ] || fail "R5-regression: --agents=opencode generated no .opencode/command/*.md"
echo "# unlanded edit" >> "$OC_CMD"
run_gate "$T/oc"
[ "$GATE_RC" != "0" ] \
  || fail "R5-regression: drift in generated .opencode/command/ PASSED the gate: $GATE_OUT"
pass "generated OpenCode glue is inside the checked set (R5) [R5_opencode_glue_in_scope]"

# ── R9 regression: an ignored body is not rescued by tracked root glue ────────────
# R9_ignored_body_is_not_masked_by_tracked_glue
# The ls-files probe must ask about the BODY alone. A repo that gitignores `.harness/`
# while tracking `.claude/agents/` has a non-zero COMBINED count, which skipped the
# warn-only branch — and git then cannot report the ignored body either, so an edited
# `.harness/agents/builder.md` produced "✅ installed harness matches the commit". A false
# CLEAN is the worst output this feature can emit. Reported as P2 on PR #98 round 2.
mkdir -p "$T/ignored"
git -C "$T/ignored" init -q .
git -C "$T/ignored" config user.email "test@harness.local"
git -C "$T/ignored" config user.name "harness test"
printf '.harness/\n' > "$T/ignored/.gitignore"
CODEX_HOME="$T/ignored/.codex-home" HOME="$T/ignored/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$T/ignored" >/dev/null 2>&1 \
  || fail "R9-regression: install exited non-zero"
git -C "$T/ignored" add -A
git -C "$T/ignored" commit -q -m "root glue tracked, .harness/ ignored"
# Preconditions: this is the exact asymmetry that produced the false clean.
[ "$(git -C "$T/ignored" ls-files -- .harness/ | wc -l | tr -d ' ')" = "0" ] \
  || fail "R9-regression: fixture precondition broken — something under .harness/ is tracked"
[ "$(git -C "$T/ignored" ls-files -- .claude/agents/ | wc -l | tr -d ' ')" != "0" ] \
  || fail "R9-regression: fixture precondition broken — no root glue is tracked"
echo "# unlanded edit to the executable body" >> "$T/ignored/.harness/agents/builder.md"
run_gate "$T/ignored"
printf '%s' "$GATE_OUT" | grep -qi "matches the commit" \
  && fail "R9-regression: FALSE CLEAN — an edited, ignored body reported as matching the commit: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "not version-controlled" \
  || fail "R9-regression: an ignored body did not produce the warn-only branch: $GATE_OUT"
[ "$GATE_RC" = "0" ] || fail "R9-regression: the warn-only branch must not fail the gate: $GATE_OUT"
pass "an ignored body warns instead of falsely reporting clean (R9) [R9_ignored_body_is_not_masked_by_tracked_glue]"

# ── E99-F10 / R4: `.codex/agents/` is shared with the operator ────────────────────
# R4_codex_agents_namespace_is_shared
# The installer calls this namespace "shared with the operator" and preserves foreign or
# edited role files. A directory-wide pathspec failed the MANDATORY gate on a project's own
# role file. Owned membership now comes from the installer's ledger,
# .harness/.model-agents/codex/, so this needs no duplicated MODEL_ROLES list.
mkdir -p "$T/cx"
git -C "$T/cx" init -q .
git -C "$T/cx" config user.email "test@harness.local"
git -C "$T/cx" config user.name "harness test"
CODEX_HOME="$T/cx/.codex-home" HOME="$T/cx/.home" \
  sh "$SRC/harness-install.sh" --agents=codex "$T/cx" >/dev/null 2>&1 \
  || fail "E99-F10/R4: codex install exited non-zero"
printf 'name = "ours"\n' > "$T/cx/.codex/agents/project-role.toml"
git -C "$T/cx" add -A
git -C "$T/cx" commit -q -m "installed harness (codex) + our own role"
# Preconditions: the ledger exists, and it does NOT claim the operator's file.
[ -d "$T/cx/.harness/.model-agents/codex" ] \
  || fail "E99-F10/R4: fixture precondition broken — no codex ownership ledger was written"
[ ! -e "$T/cx/.harness/.model-agents/codex/project-role.toml" ] \
  || fail "E99-F10/R4: fixture precondition broken — the ledger claims the operator's file"
printf 'name = "ours, edited"\n' > "$T/cx/.codex/agents/project-role.toml"
run_gate "$T/cx"
[ "$GATE_RC" = "0" ] \
  || fail "E99-F10/R4: an operator's own .codex/agents/project-role.toml failed the MANDATORY gate: $GATE_OUT"
pass "an operator's own Codex role file does not trip the guard (R4) [R4_codex_agents_namespace_is_shared]"
# positive control: a role file the ledger DOES claim is still checked
echo "# unlanded" >> "$T/cx/.codex/agents/builder.toml"
run_gate "$T/cx"
[ "$GATE_RC" != "0" ] \
  || fail "E99-F10/R4 control: drift in a LEDGER-OWNED .codex/agents/builder.toml PASSED — the guard claims nothing"
pass "…while a ledger-owned Codex role file still is (R4 control) [R4_codex_agents_namespace_is_shared]"

# ── E99-F10 / R2: a huge drift must print its diagnostic, not die at 141 ───────────
# R2_large_drift_prints_diagnostic
# `printf | head -n 10` early-closes the pipe; under `set -o pipefail` + `set -e` the
# upstream printf takes SIGPIPE (141) and the gate aborts BEFORE the elision count, the
# recovery command, and the fail() message. The gate still fails closed — it just fails
# uninformatively at exactly the moment the diagnostic matters most.
mk_target "$T/huge"
i=1
while [ "$i" -le 3000 ]; do
  : > "$T/huge/.harness/agents/generated-role-with-a-deliberately-long-name-$i.md"
  i=$((i + 1))
done
# PRECONDITION, asserted rather than assumed: the porcelain output must exceed the pipe
# buffer, or `head` never early-closes and this case passes without exercising anything.
# Measured on this platform: ~70KB (1200 files) does NOT trip SIGPIPE; ~176KB (3000) does.
# A first draft of this test used 1200 and survived mutation M12 — it was asserting nothing.
DRIFT_BYTES="$(git -C "$T/huge" status --porcelain -uall -- .harness/ | wc -c | tr -d ' ')"
[ "$DRIFT_BYTES" -gt 131072 ] \
  || fail "E99-F10/R2: fixture precondition broken — drift output is only ${DRIFT_BYTES}B, below the pipe buffer, so SIGPIPE cannot occur"
run_gate "$T/huge"
[ "$GATE_RC" != "0" ] || fail "E99-F10/R2: a 1200-file drift PASSED the gate: $GATE_OUT"
[ "$GATE_RC" != "141" ] \
  || fail "E99-F10/R2: the gate died of SIGPIPE (141) while capping the sample — no diagnostic printed"
printf '%s' "$GATE_OUT" | grep -qi "not committed" \
  || fail "E99-F10/R2: no fail() diagnostic printed on a large drift (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -q "more" \
  || fail "E99-F10/R2: no elision marker printed on a large drift: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -q "list them:" \
  || fail "E99-F10/R2: no recovery command printed on a large drift: $GATE_OUT"
pass "a drift larger than the pipe buffer still prints its full diagnostic (R2) [R2_large_drift_prints_diagnostic]"

# ── E99-F10 / R3: the recovery command survives a path containing whitespace ───────
# R3_recovery_command_quotes_the_root
# An unquoted -C value reaches git as its first word only, so the printed command exits 128
# when pasted — on the one PR where the operator most needs to paste it.
WS="$T/with space/repo"
mkdir -p "$WS"
mk_target "$WS"
echo "# unlanded edit" >> "$WS/.harness/agents/builder.md"
run_gate "$WS"
[ "$GATE_RC" != "0" ] || fail "E99-F10/R3: drift in a whitespace path PASSED the gate: $GATE_OUT"
RECO="$(printf '%s\n' "$GATE_OUT" | sed -n 's/^   list them:  //p')"
[ -n "$RECO" ] || fail "E99-F10/R3: no recovery command printed: $GATE_OUT"
# The real assertion: the printed command must actually RUN. Anything less tests the string,
# not the promise — and the promise is that this line can be copied and pasted.
RECO_OUT="$(cd / && eval "$RECO" 2>&1)" && RECO_RC=0 || RECO_RC=$?
[ "$RECO_RC" = "0" ] \
  || fail "E99-F10/R3: the printed recovery command failed to run (rc=$RECO_RC) from a whitespace path: $RECO_OUT"
printf '%s' "$RECO_OUT" | grep -q "builder.md" \
  || fail "E99-F10/R3: the recovery command ran but did not list the drifted file: $RECO_OUT"
pass "the recovery command runs verbatim from a path containing whitespace (R3) [R3_recovery_command_quotes_the_root]"

# ── E99-F10 / R4: a SYMLINKED ownership ledger is not a ledger ────────────────────
# R4_symlinked_ledger_is_rejected
# `-d` and the glob both follow symlinks, so a symlinked .model-agents/<tool> enumerates an
# EXTERNAL directory and turns arbitrary basenames there into "owned" pathspecs — failing
# the mandatory gate on an operator role file no valid stamp claims. The installer already
# refuses to trust these components; the guard must inherit that boundary.
mkdir -p "$T/symledger"
git -C "$T/symledger" init -q .
git -C "$T/symledger" config user.email "test@harness.local"
git -C "$T/symledger" config user.name "harness test"
CODEX_HOME="$T/symledger/.codex-home" HOME="$T/symledger/.home" \
  sh "$SRC/harness-install.sh" --agents=codex "$T/symledger" >/dev/null 2>&1 \
  || fail "E99-F10/R4-symlink: codex install exited non-zero"
printf 'name = "ours"\n' > "$T/symledger/.codex/agents/project-role.toml"
git -C "$T/symledger" add -A
git -C "$T/symledger" commit -q -m "installed harness (codex) + our own role"
# An external directory whose basenames collide with the operator's own role file.
mkdir -p "$T/evil-ledger"
: > "$T/evil-ledger/project-role.toml"
rm -rf "$T/symledger/.harness/.model-agents/codex"
ln -s "$T/evil-ledger" "$T/symledger/.harness/.model-agents/codex"
# Preconditions: the ledger really is a symlink, and the external dir really does name the
# operator's file — otherwise this case cannot reproduce the escalation it exists for.
[ -L "$T/symledger/.harness/.model-agents/codex" ] \
  || fail "E99-F10/R4-symlink: fixture precondition broken — the ledger is not a symlink"
[ -e "$T/evil-ledger/project-role.toml" ] \
  || fail "E99-F10/R4-symlink: fixture precondition broken — the external dir does not name the operator's file"
# The ledger swap is itself drift under .harness/, so commit it: the question under test is
# whether the OPERATOR'S file gets claimed through the symlink, not whether the swap shows.
git -C "$T/symledger" add -A
git -C "$T/symledger" commit -q -m "symlinked ledger"
printf 'name = "ours, edited"\n' > "$T/symledger/.codex/agents/project-role.toml"
run_gate "$T/symledger"
[ "$GATE_RC" = "0" ] \
  || fail "E99-F10/R4-symlink: an operator's role file was claimed through a SYMLINKED ledger and failed the mandatory gate: $GATE_OUT"
pass "a symlinked ownership ledger claims nothing (R4) [R4_symlinked_ledger_is_rejected]"

# ── E99-F10 / R4: a ledger entry must be a REGULAR FILE ───────────────────────────
# R4_non_regular_ledger_entry_is_rejected
# The installer writes byte copies and nothing else, so anything that is not a regular file
# is not a stamp. `-e` accepted a DIRECTORY, whose basename was then promoted to an owned
# pathspec — failing the mandatory gate on the operator's own role file of that name. `-f`
# is the general form: it rejects directory, fifo, socket and device in one test.
mkdir -p "$T/dirstamp"
git -C "$T/dirstamp" init -q .
git -C "$T/dirstamp" config user.email "test@harness.local"
git -C "$T/dirstamp" config user.name "harness test"
CODEX_HOME="$T/dirstamp/.codex-home" HOME="$T/dirstamp/.home" \
  sh "$SRC/harness-install.sh" --agents=codex "$T/dirstamp" >/dev/null 2>&1 \
  || fail "E99-F10/R4-regular: codex install exited non-zero"
printf 'name = "ours"\n' > "$T/dirstamp/.codex/agents/project-role.toml"
mkdir -p "$T/dirstamp/.harness/.model-agents/codex/project-role.toml"
: > "$T/dirstamp/.harness/.model-agents/codex/project-role.toml/keep"
git -C "$T/dirstamp" add -A
git -C "$T/dirstamp" commit -q -m "installed harness (codex), our own role, a directory ledger entry"
# Preconditions: the entry really is a directory, and a real stamp file still exists beside
# it — so a fix that rejected the WHOLE ledger would be caught by the control below.
[ -d "$T/dirstamp/.harness/.model-agents/codex/project-role.toml" ] \
  || fail "E99-F10/R4-regular: fixture precondition broken — the ledger entry is not a directory"
[ -f "$T/dirstamp/.harness/.model-agents/codex/builder.toml" ] \
  || fail "E99-F10/R4-regular: fixture precondition broken — no real stamp file beside it"
printf 'name = "ours, edited"\n' > "$T/dirstamp/.codex/agents/project-role.toml"
run_gate "$T/dirstamp"
[ "$GATE_RC" = "0" ] \
  || fail "E99-F10/R4-regular: a DIRECTORY ledger entry claimed the operator's role file and failed the mandatory gate: $GATE_OUT"
pass "a non-regular ledger entry claims nothing (R4) [R4_non_regular_ledger_entry_is_rejected]"
# positive control: the real stamp beside it still claims its role file
echo "# unlanded" >> "$T/dirstamp/.codex/agents/builder.toml"
run_gate "$T/dirstamp"
[ "$GATE_RC" != "0" ] \
  || fail "E99-F10/R4-regular control: a REAL stamp's role file PASSED — the fix rejected the whole ledger"
pass "…while a real stamp beside it still does (R4 control) [R4_non_regular_ledger_entry_is_rejected]"

# ── E99-F10 / R4: a ledger basename is DATA, not a git pattern ────────────────────
# R4_ledger_basename_is_a_literal_pathspec
# A stamp named `project-*.toml` was appended as a bare pathspec, which git reads as an
# fnmatch wildcard — claiming every `.codex/agents/project-*.toml`, so the operator's own
# `project-role.toml` failed the mandatory gate although no stamp of that name exists.
mkdir -p "$T/wildcard"
git -C "$T/wildcard" init -q .
git -C "$T/wildcard" config user.email "test@harness.local"
git -C "$T/wildcard" config user.name "harness test"
CODEX_HOME="$T/wildcard/.codex-home" HOME="$T/wildcard/.home" \
  sh "$SRC/harness-install.sh" --agents=codex "$T/wildcard" >/dev/null 2>&1 \
  || fail "E99-F10/R4-literal: codex install exited non-zero"
printf 'name = "ours"\n' > "$T/wildcard/.codex/agents/project-role.toml"
: > "$T/wildcard/.harness/.model-agents/codex/project-*.toml"
git -C "$T/wildcard" add -A
git -C "$T/wildcard" commit -q -m "installed harness (codex), our own role, a wildcard-named stamp"
# Preconditions: the wildcard stamp is a real regular file (so it clears the -f gate and the
# case actually exercises pattern-vs-literal), and no stamp names the operator's file.
[ -f "$T/wildcard/.harness/.model-agents/codex/project-*.toml" ] \
  || fail "E99-F10/R4-literal: fixture precondition broken — the wildcard stamp is not a regular file"
[ ! -e "$T/wildcard/.harness/.model-agents/codex/project-role.toml" ] \
  || fail "E99-F10/R4-literal: fixture precondition broken — a stamp names the operator's file"
printf 'name = "ours, edited"\n' > "$T/wildcard/.codex/agents/project-role.toml"
run_gate "$T/wildcard"
[ "$GATE_RC" = "0" ] \
  || fail "E99-F10/R4-literal: a wildcard-named stamp claimed the operator's role file and failed the mandatory gate: $GATE_OUT"
pass "a ledger basename is matched literally, not as a pattern (R4) [R4_ledger_basename_is_a_literal_pathspec]"

# ── E99-F10 / R3: every derived pathspec is shell-escaped, not just the root ───────
# R3_recovery_command_escapes_derived_pathspecs
# A ledger-derived entry carries an operator-chosen basename. A stamp named
# `operator's-role.toml` closed the quote early, so the advertised command died with
# `unexpected EOF while looking for matching quote` — on the one line meant to be pasted.
mkdir -p "$T/quote"
git -C "$T/quote" init -q .
git -C "$T/quote" config user.email "test@harness.local"
git -C "$T/quote" config user.name "harness test"
CODEX_HOME="$T/quote/.codex-home" HOME="$T/quote/.home" \
  sh "$SRC/harness-install.sh" --agents=codex "$T/quote" >/dev/null 2>&1 \
  || fail "E99-F10/R3-quote: codex install exited non-zero"
: > "$T/quote/.harness/.model-agents/codex/operator's-role.toml"
printf 'name = "ours"\n' > "$T/quote/.codex/agents/operator's-role.toml"
git -C "$T/quote" add -A
git -C "$T/quote" commit -q -m "installed harness (codex) + an apostrophe in a stamp name"
[ -f "$T/quote/.harness/.model-agents/codex/operator's-role.toml" ] \
  || fail "E99-F3-quote: fixture precondition broken — the apostrophe stamp is not a regular file"
echo "# unlanded" >> "$T/quote/.harness/agents/builder.md"
run_gate "$T/quote"
[ "$GATE_RC" != "0" ] || fail "E99-F10/R3-quote: drift PASSED the gate: $GATE_OUT"
RECO="$(printf '%s\n' "$GATE_OUT" | sed -n 's/^   list them:  //p')"
[ -n "$RECO" ] || fail "E99-F10/R3-quote: no recovery command printed: $GATE_OUT"
# The assertion is that it RUNS. String-matching would pass on a command that cannot parse.
RECO_OUT="$(cd / && eval "$RECO" 2>&1)" && RECO_RC=0 || RECO_RC=$?
[ "$RECO_RC" = "0" ] \
  || fail "E99-F10/R3-quote: the printed recovery command failed to run (rc=$RECO_RC) with an apostrophe in a ledger name: $RECO_OUT"
printf '%s' "$RECO_OUT" | grep -q "builder.md" \
  || fail "E99-F10/R3-quote: the recovery command ran but did not list the drifted file: $RECO_OUT"
pass "every derived pathspec is shell-escaped, so the command still runs (R3) [R3_recovery_command_escapes_derived_pathspecs]"

# ── E24-F02 / R8: init.sh and the cascade audit resolve the SAME path set ─────────────
# R8_shared_ownership_is_differential
# Asserting that both files MENTION tools/harness-owned-paths.sh proves nothing about
# agreement — a stale inline copy could sit beside the reference and still drift. This is
# DIFFERENTIAL: perturb one path at a time and require the two verdicts to match across a
# matrix that includes both answers. A second definition that drifts fails the matrix even
# though both callers still reference the helper.
mk_target "$T/diff"
# The cascade audit is the installer's; drive the same question directly through the shared
# helper the way harness-install.sh does, from the same project root init.sh uses.
audit_verdict() {   # -> "drift" | "clean"
  # `_av_t` is captured BEFORE the subshell: `set --` there replaces the positional
  # parameters with the pathspecs, so a `git -C "$1"` inside would target a pathspec rather
  # than the repo. (This exact slip is why harness-install.sh's audit_one saves `_t="$1"`
  # on its first line — and why this differential is worth having: it caught the mistake.)
  _av_t="$1"
  _spec="$(sh "$SRC/tools/harness-owned-paths.sh" all "$_av_t/.harness")"
  _n=$(
    set --
    while IFS= read -r _p; do [ -n "$_p" ] && set -- "$@" "$_p"; done <<SPEC
$_spec
SPEC
    git -C "$_av_t" status --porcelain -uall -- "$@" 2>/dev/null | grep -c '' || true
  )
  [ "${_n:-0}" -gt 0 ] && echo drift || echo clean
}
gate_verdict() {    # -> "drift" | "clean"
  run_gate "$1"
  [ "$GATE_RC" = "0" ] && echo clean || echo drift
}
# path                                   expected
# --------------------------------------------------------
#  a project-owned file                  both must IGNORE
#  a body file                           both must FLAG
#  root generated glue                   both must FLAG
#  a user file in the .agents/ tree      both must IGNORE
mkdir -p "$T/diff/.agents/skills/mine"
_dm_paths=".harness/harness.config.yaml .harness/agents/builder.md .claude/agents/builder.md .agents/skills/mine/SKILL.md"
_dm_want="clean drift drift clean"
_i=1
for _p in $_dm_paths; do
  _want="$(printf '%s' "$_dm_want" | cut -d' ' -f"$_i")"
  git -C "$T/diff" checkout -q -- . 2>/dev/null || true
  rm -rf "$T/diff/.agents/skills/mine"; mkdir -p "$T/diff/.agents/skills/mine"
  mkdir -p "$(dirname "$T/diff/$_p")"
  printf '# perturbed\n' >> "$T/diff/$_p"
  _g="$(gate_verdict "$T/diff")"
  _a="$(audit_verdict "$T/diff")"
  [ "$_g" = "$_a" ] \
    || fail "R8: init.sh says '$_g' and the cascade audit says '$_a' for $_p — the two definitions have diverged"
  [ "$_g" = "$_want" ] \
    || fail "R8: for $_p both agreed on '$_g' but the correct answer is '$_want' — they agree on the WRONG set"
  _i=$((_i + 1))
done
git -C "$T/diff" checkout -q -- . 2>/dev/null || true
rm -rf "$T/diff/.agents/skills/mine"
pass "init.sh and the cascade audit agree across the ownership matrix (R8) [R8_shared_ownership_is_differential]"

# ── E24-F02: a torn install (no ownership helper) warns instead of hard-failing ────────
# R8_missing_helper_degrades
# init.sh runs before every agent step, so a missing helper must not halt the harness every
# session. Control: the same target WITH the helper still fails on the same perturbation.
mk_target "$T/nohelper"
echo "# unlanded edit" >> "$T/nohelper/.harness/agents/builder.md"
run_gate "$T/nohelper"
[ "$GATE_RC" != "0" ] || fail "R8-degrade control: the drifted target PASSED before the helper was removed"
rm -f "$T/nohelper/.harness/tools/harness-owned-paths.sh"
run_gate "$T/nohelper"
[ "$GATE_RC" = "0" ] \
  || fail "R8-degrade: a missing ownership helper hard-failed the gate (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "harness-owned-paths.sh missing" \
  || fail "R8-degrade: the missing helper was not reported: $GATE_OUT"
pass "a missing ownership helper warns and does not halt the gate (R8) [R8_missing_helper_degrades]"

# ── E24-F03 R6: a thin child stands alone, with or without its umbrella ──────────
# The acceptance bar of the whole feature. Both cases run on the SAME fixture so "exit 0"
# cannot come from a check that never executed — and the umbrella is MOVED AWAY rather
# than the key omitted, because omitting it exercises the full-copy path (R5) instead and
# would pass with R6 unimplemented.
U6="$T/thin"
mkdir -p "$U6/kid"
git -C "$U6/kid" init -q .
git -C "$U6/kid" config user.email "test@harness.local"
git -C "$U6/kid" config user.name  "harness test"
echo seed > "$U6/kid/README.md"
git -C "$U6/kid" add -A
git -C "$U6/kid" commit -q -m init
CODEX_HOME="$U6/.ch" HOME="$U6/.home" \
  sh "$SRC/harness-install.sh" --umbrella "$U6" --agents=claude >/dev/null 2>&1 || true
# Fixture preconditions: this really is a THIN child of a resolvable umbrella.
head -n 1 "$U6/kid/.harness/agents/builder.md" | grep -qxF '<!-- harness:umbrella-stub -->' \
  || fail "R6 setup: the cascade did not produce a thin child"
[ -f "$U6/.harness/.harness-version" ] || fail "R6 setup: the umbrella body is missing"
git -C "$U6/kid" add -A
git -C "$U6/kid" commit -q -m "installed harness"

run_gate "$U6/kid"
[ "$GATE_RC" = 0 ] || fail "R6: a thin child with its umbrella PRESENT failed the gate (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "resolves from the umbrella" \
  || fail "R6: the reachable umbrella was not reported: $GATE_OUT"
pass "a thin child reports its resolved umbrella and passes (E24-F03 R6) [thin_child_with_umbrella_reports]"

# Now separate it from its umbrella — the lone clone / CI / PR-reviewer case.
mv "$U6/.harness" "$U6/.harness-detached"
run_gate "$U6/kid"
[ "$GATE_RC" = 0 ] \
  || fail "R6: a thin child whose umbrella is unreachable FAILED the gate — standalone entry is the acceptance bar (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "not reachable" \
  || fail "R6: an unreachable umbrella was not reported: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "environment ready" \
  || fail "R6: the gate did not reach its ready verdict with the umbrella gone: $GATE_OUT"
pass "a thin child passes with its umbrella unreachable, and says so (E24-F03 R6) [thin_child_without_umbrella_passes]"

# ── E24-F03 R6 (cont.): a FULL-COPY child must never claim its prose is remote ───
# The cascade records umbrella.root on a child it left full-copy (converting one is E24-F04),
# so "umbrella.root is set" does NOT mean "the body is remote". Reporting it as remote here
# would be false with agents/, docs/ and the templates sitting locally. (Codex r1 P2 #3705599510.)
U6F="$T/fullchild"
mkdir -p "$U6F/kid"
git -C "$U6F/kid" init -q .
git -C "$U6F/kid" config user.email "test@harness.local"
git -C "$U6F/kid" config user.name  "harness test"
echo seed > "$U6F/kid/README.md"
git -C "$U6F/kid" add -A
git -C "$U6F/kid" commit -q -m init
# Install standalone FIRST so the child owns a real body, then cascade over it.
CODEX_HOME="$U6F/.ch" HOME="$U6F/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$U6F/kid" >/dev/null 2>&1 \
  || fail "R6-full setup: standalone install failed"
CODEX_HOME="$U6F/.ch" HOME="$U6F/.home" \
  sh "$SRC/harness-install.sh" --umbrella "$U6F" --agents=claude >/dev/null 2>&1 || true
# Fixture preconditions: real prose AND a recorded umbrella. Without BOTH this case is vacuous.
head -n 1 "$U6F/kid/.harness/AGENTS.md" | grep -qxF '<!-- harness:umbrella-stub -->' \
  && fail "R6-full setup: the cascade converted the full-copy child (that is E24-F04's job)"
grep -q '^  root: "\.\./\.\./"' "$U6F/kid/.harness/harness.config.yaml" \
  || fail "R6-full setup: umbrella.root was not recorded on the full-copy child"
git -C "$U6F/kid" add -A
git -C "$U6F/kid" commit -q -m "installed harness"

mv "$U6F/.harness" "$U6F/.harness-detached"
run_gate "$U6F/kid"
[ "$GATE_RC" = 0 ] || fail "R6-full: a full-copy child failed the gate (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "remote and unavailable" \
  && fail "R6-full: init.sh called the prose body remote on a child that holds it locally: $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "full local body" \
  || fail "R6-full: the full-copy layout was not reported: $GATE_OUT"
grep -qF 'You are the **Builder**' "$U6F/kid/.harness/agents/builder.md" \
  || fail "R6-full: the child's local prose body is not actually present — the case is vacuous"
pass "a full-copy child with an unreachable umbrella is not reported as remote (E24-F03 R6) [full_copy_child_not_reported_remote]"

# ── E24-F04 R8: a CONVERTED child is committable, and the guard sees it either way ──────
# converted_child_is_committable.
#
# E24-F01's drift guard is this feature's observability: a conversion that went wrong shows
# up as drift at the top of the next session. That only works if the converted tree is one a
# `git commit` can land WHOLE — stubs are ordinary tracked files at the same pathspecs, so
# nothing is added to or removed from the harness-owned set.
#
# BOTH HALVES ARE ASSERTED. Without the "dirty before the commit" half, a guard that never
# runs at all also passes the "clean after" half.
U7="$T/f04-converted"
mkdir -p "$U7/kid"
git -C "$U7/kid" init -q .
git -C "$U7/kid" config user.email "test@harness.local"
git -C "$U7/kid" config user.name  "harness test"
echo seed > "$U7/kid/README.md"
git -C "$U7/kid" add -A
git -C "$U7/kid" commit -q -m init
# FULL-COPY CHILD OF A REACHABLE UMBRELLA — single-target FIRST (no umbrella.root, complete
# local body), THEN the cascade (records the root, leaves the full body alone). Inverting
# these two steps yields a THIN child and the conversion below would never run.
CODEX_HOME="$U7/.ch" HOME="$U7/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$U7/kid" >/dev/null 2>&1 \
  || fail "R8 setup: the single-target install into the child failed"
CODEX_HOME="$U7/.ch" HOME="$U7/.home" \
  sh "$SRC/harness-install.sh" --umbrella "$U7" --agents=claude >/dev/null 2>&1 || true
head -n 1 "$U7/kid/.harness/agents/builder.md" | grep -qxF '<!-- harness:umbrella-stub -->' \
  && fail "R8 setup: the fixture is not a full-copy child — the conversion below is vacuous"
git -C "$U7/kid" add -A
git -C "$U7/kid" commit -q -m "installed harness (full copy)"
[ -z "$(git -C "$U7/kid" status --porcelain)" ] || fail "R8 setup: the child is dirty right after its commit"
run_gate "$U7/kid"
[ "$GATE_RC" = 0 ] || fail "R8 setup: the committed full-copy child failed the gate before any conversion (rc=$GATE_RC): $GATE_OUT"

# Convert it. Single-target, so the coordinator is not re-installed in the same breath.
CODEX_HOME="$U7/.ch" HOME="$U7/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$U7/kid" >/dev/null 2>&1 \
  || fail "R8: the --thin conversion exited non-zero"
head -n 1 "$U7/kid/.harness/agents/builder.md" | grep -qxF '<!-- harness:umbrella-stub -->' \
  || fail "R8: the child was not converted — every assertion below would be about the wrong layout"

# Half one: the conversion is UNCOMMITTED work, and the guard says so.
[ -n "$(git -C "$U7/kid" status --porcelain)" ] \
  || fail "R8: the conversion left no git-visible change — the 'clean after commit' half below proves nothing"
run_gate "$U7/kid"
[ "$GATE_RC" != 0 ] \
  || fail "R8: an UNCOMMITTED conversion passed the drift guard — the guard is inert across the transition: $GATE_OUT"

# Half two: committing it makes the same gate pass, with no drift and no new machinery.
git -C "$U7/kid" add -A
git -C "$U7/kid" commit -q -m "converted to the thin layout"
[ -z "$(git -C "$U7/kid" status --porcelain)" ] \
  || fail "R8: the converted tree is not committable whole — add+commit left it dirty"
run_gate "$U7/kid"
[ "$GATE_RC" = 0 ] || fail "R8: a COMMITTED conversion failed the drift guard (rc=$GATE_RC): $GATE_OUT"
printf '%s' "$GATE_OUT" | grep -qi "environment ready" \
  || fail "R8: the gate did not reach its ready verdict on a committed converted child: $GATE_OUT"
grep -q 'This target holds the thin body layout' "$U7/kid/.harness/manifest.txt" \
  || fail "R8: the converted child's manifest does not record the thin body layout"
pass "a converted child is committable and drift-clean, dirty before the commit (E24-F04 R8) [converted_child_is_committable]"

echo "All init drift-guard tests passed."
