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

echo "All init drift-guard tests passed."
