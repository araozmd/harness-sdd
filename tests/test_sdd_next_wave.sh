#!/bin/sh
# test_sdd_next_wave.sh — E36-F07 `/sdd-next --wave` fans out one wave into isolated worktrees.
#
# Prose contracts are asserted on the INSTALLED files (one sandboxed install into a mktemp
# target), never on the source tree, and each is pinned as an exact clause — subject, verb
# and object in one folded substring — inside the SECTION it belongs to, so a mutant that
# flips the subject, the quantifier or the direction of a rule reds the case that claims it.
# Executable seams (the selector, fix-worktree.sh, tasks-lock.py, run-tests.sh, the
# installer) are run, not grepped.
#
# Failures are COLLECTED per case (every case runs; the suite exits 1 at the end when any
# failed), so a mutation campaign can read exactly which cases a mutant reds.
#
# Suite-wide constraints (permanent-suite anti-pattern): no literal VERSION, no `git diff`
# of a DO-NOT-TOUCH file against main — protected files are cksum'd before and after.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-sdd-next-wave.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

FAILS=0
CASE=-
CASE_FAILS=0
fail() { FAILS=$((FAILS + 1)); CASE_FAILS=$((CASE_FAILS + 1)); echo "FAIL: [$CASE] $*" >&2; }
begin() { CASE=$1; CASE_FAILS=0; }
end() { [ "$CASE_FAILS" -eq 0 ] && echo "ok - $CASE" || echo "not ok - $CASE ($CASE_FAILS)"; }

# No ambient git config reaches a fixture repo (hooks, signing, templates, diff drivers).
safe_git() { env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TEMPLATE_DIR= git "$@"; }

protected_cksums() {
  cksum "$ROOT/tools/next-task.mjs" "$ROOT/tools/tasks-lock.py" "$ROOT/tools/run-tests.sh" \
    "$ROOT/agents/fixer.md" "$ROOT/store/tasks.schema.json"
}
PROTECTED_BEFORE=$(protected_cksums)

# ── one sandboxed install (HOME and CODEX_HOME never reach the real ones) ──────────────
T="$TMP/target"
mkdir -p "$T" "$TMP/home" "$TMP/codex"
safe_git init -q "$T" || { echo "FAIL: fixture git init" >&2; exit 1; }
if ! HOME="$TMP/home" CODEX_HOME="$TMP/codex" HARNESS_AGENTS="claude,codex,opencode" \
  sh "$ROOT/harness-install.sh" "$T" >"$TMP/install.log" 2>&1; then
  cat "$TMP/install.log" >&2
  echo "FAIL: sandboxed install exited non-zero" >&2
  exit 1
fi
ORCH="$T/.harness/agents/orchestrator.md"
WORKFLOW="$T/.harness/docs/WORKFLOW.md"
CFG="$T/.harness/harness.config.yaml"
B_CLAUDE="$T/.claude/commands/sdd-next.md"
B_OPENCODE="$T/.opencode/command/sdd-next.md"
B_SKILL="$T/.agents/skills/sdd-next/SKILL.md"

# fold <file>: the whole file on one line, runs of blanks squeezed (wrapped prose folds).
fold_file() { tr '\n' ' ' <"$1" | tr -s ' \t' '  '; }

# section <file> <heading-line-prefix>: the heading and everything up to the next `## `
# heading, folded. The wave section carries no fenced `## ` line, so a heading-bounded
# extract reads all of it (the house extractor's fence-blindness cannot truncate it).
section() {
  awk -v h="$2" 'index($0, h) == 1 { k = 1; print; next } k && /^## / { k = 0 } k { print }' "$1" |
    tr '\n' ' ' | tr -s ' \t' '  '
}

# has <label> <text> <exact clause>: the clause appears verbatim in the folded text.
has() {
  case "$2" in
    *"$3"*) ;;
    *) fail "$1 lacks: $3" ;;
  esac
}

# ── R1 — scope token in every generated body ───────────────────────────────────────────
test_wave_token_in_generated_bodies() {
  begin test_wave_token_in_generated_bodies
  for _b in "$B_CLAUDE" "$B_OPENCODE" "$B_SKILL"; do
    [ -f "$_b" ] || { fail "missing generated body $_b"; continue; }
    _t=$(fold_file "$_b")
    _n=${_b#"$T"/}
    has "$_n" "$_t" '- `--wave`, optionally followed by `--max N` and/or `--epic E##` in either order → **wave coordinator mode**'
    has "$_n" "$_t" '`--wave` is a closed-scope token beside `--mine` and `E##-F##`: it cannot be combined with either.'
    has "$_n" "$_t" '`--max` and `--epic` are valid only after `--wave`, each at most once;'
    has "$_n" "$_t" '`N` must match `^[1-9][0-9]*$` and `E##` must match `^E[0-9]+$`.'
    has "$_n" "$_t" 'Any other argument shape'
    has "$_n" "$_t" 'selects nothing, changes no state, and prints `usage: /sdd-next [--mine | E##-F## | --wave [--max N] [--epic E##]]`.'
    has "$_n" "$_t" 'Under `--wave`, act as the wave coordinator in'
    has "$_n" "$_t" '"## Wave coordinator mode (/sdd-next --wave)"'
    # The existing closed-scope rows keep their wiring.
    has "$_n" "$_t" '- the exact token `--mine` →'
    has "$_n" "$_t" '- anything else is invalid and selects or changes nothing.'
  done
  cmp -s "$B_CLAUDE" "$B_OPENCODE" || fail "claude and opencode sdd-next bodies differ"
  end
}

test_wave_token_in_generated_bodies

_after=$(protected_cksums)
[ "$PROTECTED_BEFORE" = "$_after" ] || { FAILS=$((FAILS + 1)); echo "FAIL: [suite] a DO-NOT-TOUCH file changed during the suite" >&2; }

if [ "$FAILS" -ne 0 ]; then
  echo "test_sdd_next_wave: $FAILS failure(s)" >&2
  exit 1
fi
echo "test_sdd_next_wave: all cases passed"
