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
WAVE_H='## Wave coordinator mode (/sdd-next --wave)'

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

# ── R10 — workflow.max_wave config key ─────────────────────────────────────────────────
# in_section <file> <top-level-key>: the lines inside that top-level YAML section.
in_section() {
  awk -v k="$2" '$0 ~ "^" k ":[[:space:]]*(#.*)?$" { s = 1; next } s && /^[^[:space:]#]/ { s = 0 } s { print }' "$1"
}

# upgrade_with <config-text-file>: install fresh once into $TU (lazily), replace its config
# with the given text, re-run the installer (the upgrade path), leave the result in $TU.
TU="$TMP/upgrade"
upgrade_with() {
  if [ ! -d "$TU/.harness" ]; then
    mkdir -p "$TU"
    safe_git init -q "$TU" || { fail "upgrade fixture git init"; return 1; }
    HOME="$TMP/home" CODEX_HOME="$TMP/codex" HARNESS_AGENTS="claude" \
      sh "$ROOT/harness-install.sh" "$TU" >"$TMP/upgrade-fresh.log" 2>&1 ||
      { fail "upgrade fixture fresh install failed"; return 1; }
  fi
  cp "$1" "$TU/.harness/harness.config.yaml"
  HOME="$TMP/home" CODEX_HOME="$TMP/codex" HARNESS_AGENTS="claude" \
    sh "$ROOT/harness-install.sh" "$TU" >"$TMP/upgrade.log" 2>&1 ||
    { fail "upgrade run failed: $(tail -3 "$TMP/upgrade.log")"; return 1; }
}

test_max_wave_config_seed() {
  begin test_max_wave_config_seed
  # The source key line, which the installer must seed byte-for-byte.
  _src_line=$(in_section "$ROOT/harness.config.yaml" workflow | grep -E '^[[:space:]]+max_wave:' || :)
  [ "$(printf '%s\n' "$_src_line" | grep -c .)" = 1 ] || fail "source workflow: does not carry exactly one max_wave line"
  printf '%s\n' "$_src_line" | grep -Eq '^[[:space:]]+max_wave:[[:space:]]+3([[:space:]]|$)' ||
    fail "source max_wave is not 3: $_src_line"
  has "source max_wave line" "$_src_line" '/sdd-next --wave'
  # Fresh install.
  in_section "$CFG" workflow | grep -Eq '^[[:space:]]+max_wave:[[:space:]]+3([[:space:]]|$)' ||
    fail "fresh install: workflow: lacks max_wave: 3"

  # Preserved config with workflow: but no max_wave gains exactly one, inside workflow:.
  printf 'store:\n  tasks: local\nworkflow:\n  identity: ""\n  require_spec_approval: true\n' >"$TMP/cfg-lacks"
  if upgrade_with "$TMP/cfg-lacks"; then
    _got=$(in_section "$TU/.harness/harness.config.yaml" workflow | grep -E '^[[:space:]]+max_wave:' || :)
    [ "$_got" = "$_src_line" ] || fail "preserved config lacking max_wave: workflow: got [$_got], want the source line"
    [ "$(grep -cE '^[[:space:]]+max_wave:' "$TU/.harness/harness.config.yaml")" = 1 ] ||
      fail "preserved config lacking max_wave: not exactly one max_wave line after upgrade"
  fi
  # A preserved config that already has it keeps its value and gains no second line.
  printf 'workflow:\n  identity: ""\n  max_wave: 5   # mine\n' >"$TMP/cfg-has"
  if upgrade_with "$TMP/cfg-has"; then
    grep -qxF '  max_wave: 5   # mine' "$TU/.harness/harness.config.yaml" || fail "preserved max_wave: 5 was not kept verbatim"
    [ "$(grep -cE '^[[:space:]]+max_wave:' "$TU/.harness/harness.config.yaml")" = 1 ] ||
      fail "preserved config with max_wave gained a second max_wave line"
  fi
  # A same-named key under another top-level section never suppresses the workflow seed.
  printf 'other:\n  max_wave: 9\nworkflow:\n  identity: ""\n' >"$TMP/cfg-other"
  if upgrade_with "$TMP/cfg-other"; then
    _got=$(in_section "$TU/.harness/harness.config.yaml" workflow | grep -E '^[[:space:]]+max_wave:' || :)
    [ "$_got" = "$_src_line" ] || fail "an other.max_wave suppressed the workflow seed: got [$_got]"
    in_section "$TU/.harness/harness.config.yaml" other | grep -qxF '  max_wave: 9' || fail "other.max_wave was altered"
  fi
  # No workflow: section at all: a new workflow: header carries the seed.
  printf 'store:\n  tasks: local\n' >"$TMP/cfg-none"
  if upgrade_with "$TMP/cfg-none"; then
    [ "$(grep -cE '^workflow:' "$TU/.harness/harness.config.yaml")" = 1 ] || fail "no-workflow config: not exactly one workflow: header"
    in_section "$TU/.harness/harness.config.yaml" workflow | grep -qxF -- "$_src_line" ||
      fail "no-workflow config: the appended workflow: lacks the seed line"
  fi
  end
}

# ── R2 — preflight and cap ─────────────────────────────────────────────────────────────
test_preflight_contract() {
  begin test_preflight_contract
  _w=$(section "$ORCH" "$WAVE_H")
  has "wave section" "$_w" 'W1 runs entirely before any mutation.'
  has "wave section" "$_w" 'The coordinator runs init, requires native in-session concurrent sub-agent delegation (otherwise it stops and names the missing native concurrency capability)'
  has "wave section" "$_w" 'requires `execution.builder.backend: in-session` (otherwise it stops and names the incompatible backend — `delegate` or any unknown value)'
  has "wave section" "$_w" 'and requires `umbrella.manifest` to be empty'
  has "wave section" "$_w" 'It then resolves `cap`: `--max N` when given, else `workflow.max_wave` from `harness.config.yaml`, else `3`.'
  has "wave section" "$_w" 'When `workflow.max_wave` is present but not a positive integer, the coordinator stops and names the key `workflow.max_wave`.'
  has "wave section" "$_w" '`cap` is the only brake on concurrent workers: there is no hard ceiling, and the operator owns any value above the default.'
  has "wave section" "$_w" 'Every W1 stop names its cause, points the operator to `/sdd-next <id>` and makes the coordinator exit non-zero with no worktree, branch, manifest or board change.'
  _b=$(fold_file "$B_CLAUDE")
  has "sdd-next body" "$_b" 'Its preflight stops before any mutation — naming the cause, pointing to `/sdd-next <id>` and exiting non-zero —'
  has "sdd-next body" "$_b" 'on an `execution.builder.backend` other than `in-session` (`delegate` or any unknown value)'
  end
}

# ── selector fixtures (the INSTALLED selector; the live board is never read) ───────────
SEL="$TMP/sel"
mkdir -p "$SEL"
printf 'workflow:\n  require_spec_approval: true\n  identity: ""\numbrella:\n  manifest: ""\n' >"$SEL/config.yaml"
json_field() {
  python3 -c 'import json,sys; x=json.load(sys.stdin); print(eval(sys.argv[1], {"x":x}))' "$1"
}
# run_selector <board-json> <args...>: writes the board, runs the installed selector into
# $SEL/out, returns the selector's exit status.
run_selector() {
  printf '%s\n' "$1" >"$SEL/tasks.json"
  shift
  _rc=0
  node "$T/.harness/tools/next-task.mjs" --tasks "$SEL/tasks.json" --config "$SEL/config.yaml" "$@" \
    >"$SEL/out" 2>"$SEL/err" || _rc=$?
  return "$_rc"
}
# feat <id> <status> [deps-json] [extra-json-members]
feat() {
  printf '{"id":"%s","title":"%s","status":"%s","sdd":true,"spec_path":"specs/%s/","depends_on":%s%s}' \
    "$1" "$1" "$2" "$1" "${3:-[]}" "${4:+,$4}"
}
# board <epic-json>...: epics given as `E1:<features-json>`.
board() {
  _e=
  for _x in "$@"; do
    _e="$_e{\"id\":\"${_x%%:*}\",\"title\":\"t\",\"status\":\"planned\",\"features\":[${_x#*:}]},"
  done
  printf '{"project":"fixture","epics":[%s]}' "${_e%,}"
}

# ── R3 — wave read consumes the F05 envelope ───────────────────────────────────────────
test_wave_read_consumes_envelope() {
  begin test_wave_read_consumes_envelope
  _w=$(section "$ORCH" "$WAVE_H")
  has "wave section" "$_w" 'The coordinator runs `node tools/next-task.mjs --waves --json` (installed: `node .harness/tools/next-task.mjs --waves --json`), forwarding `--epic E##` when given, and consumes that envelope exactly: it never re-derives a wave, a route or a blocker.'
  has "wave section" "$_w" 'It branches on `outcome` first.'
  has "wave section" "$_w" 'When `outcome` is `"error"` or `"blocked"`, the coordinator prints the envelope'"'"'s `reason.detail` and every `blocked[]` record, mutates nothing and exits non-zero.'
  has "wave section" "$_w" 'When `outcome` is `"waves"` and `waves` is empty, it prints exactly `no runnable wave` and exits 0 with no mutation.'
  has "wave section" "$_w" 'Otherwise it fans out `waves[0]` — the first listed wave — and prints that wave'"'"'s `wave` number, which can be above 1 under `--epic`; it never assumes wave 1.'

  # The first LISTED wave under --epic is wave 2 here: a consumer that assumed wave 1
  # would find nothing. Features are listed in non-canonical order.
  _b=$(board "E2:$(feat E2-F2 pending '["E2-F1"]'),$(feat E2-F1 pending '["E1-F1"]')" \
    "E1:$(feat E1-F1 pending),$(feat E1-F0 done)")
  if run_selector "$_b" --waves --json --epic E2; then
    [ "$(json_field 'x["outcome"]' <"$SEL/out")" = waves ] || fail "--epic E2: outcome is not waves"
    [ "$(json_field 'x["waves"][0]["wave"]' <"$SEL/out")" = 2 ] || fail "--epic E2: waves[0].wave is not 2"
    [ "$(json_field '",".join(f["id"] for f in x["waves"][0]["features"])' <"$SEL/out")" = E2-F1 ] ||
      fail "--epic E2: waves[0] is not exactly E2-F1"
  else
    fail "--epic E2 selector run exited non-zero"
  fi
  # An invalid graph (dangling depends_on) is outcome blocked with blocked[] records.
  _b=$(board "E1:$(feat E1-F2 pending '["E1-F9"]'),$(feat E1-F1 pending)")
  run_selector "$_b" --waves --json || :
  [ "$(json_field 'x["outcome"]' <"$SEL/out")" = blocked ] || fail "dangling depends_on: outcome is not blocked"
  [ "$(json_field 'len(x["blocked"]) > 0' <"$SEL/out")" = True ] || fail "dangling depends_on: blocked[] is empty"
  [ -n "$(json_field 'x["reason"]["detail"]' <"$SEL/out")" ] || fail "dangling depends_on: reason.detail is empty"
  # A missing epic is outcome error and carries no waves key at all.
  _b=$(board "E1:$(feat E1-F1 pending)")
  run_selector "$_b" --waves --json --epic E9 || :
  [ "$(json_field 'x["outcome"]' <"$SEL/out")" = error ] || fail "--epic E9: outcome is not error"
  [ "$(json_field '"waves" in x' <"$SEL/out")" = False ] || fail "--epic E9: an error envelope carries waves"
  end
}

test_wave_token_in_generated_bodies
test_max_wave_config_seed
test_preflight_contract
test_wave_read_consumes_envelope

_after=$(protected_cksums)
[ "$PROTECTED_BEFORE" = "$_after" ] || { FAILS=$((FAILS + 1)); echo "FAIL: [suite] a DO-NOT-TOUCH file changed during the suite" >&2; }

if [ "$FAILS" -ne 0 ]; then
  echo "test_sdd_next_wave: $FAILS failure(s)" >&2
  exit 1
fi
echo "test_sdd_next_wave: all cases passed"
