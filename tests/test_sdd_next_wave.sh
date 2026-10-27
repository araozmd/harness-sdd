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

# The ONE CommonMark fence rule (tests/lib/fence.awk, E99-F131): every heading slicer below
# loads it, so a `#` line inside a fenced block is never read as a heading.
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"

# section <file> <heading-line-prefix>: the heading and everything up to the next `## `
# heading outside a fence, folded (its `###` subsections belong to it).
section() {
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (k) print; next }
    !fence && index($0, h) == 1 { k = 1; print; next }
    !fence && k && /^## / { k = 0 }
    k { print }
  ' "$1" | tr '\n' ' ' | tr -s ' \t' '  '
}

# subsection <file> <heading-line-prefix>: a `###` heading up to the next `##`/`###`, folded.
subsection() {
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (k) print; next }
    !fence && index($0, h) == 1 { k = 1; print; next }
    !fence && k && /^#+ / { k = 0 }
    k { print }
  ' "$1" | tr '\n' ' ' | tr -s ' \t' '  '
}
WF_H='### Fanning out a wave (`/sdd-next --wave`)'

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

# ── R4 — eligibility, order and cap ────────────────────────────────────────────────────
# classify <cap>: apply the spec's predicate and order rule to $SEL/out and print one
# `id=classification` per record of waves[0], in envelope order.
classify() {
  python3 - "$1" "$SEL/out" <<'PY'
import json, sys
cap = int(sys.argv[1]); x = json.load(open(sys.argv[2]))
recs = x["waves"][0]["features"]
def why(r):
    if r["runnable"] is not True: return "skipped: not-runnable"
    if r["autonomous"] is not True: return "skipped: not-autonomous"
    if r["status"] != "pending": return "skipped: status:" + r["status"]
    if r["route"] != "architect": return "skipped: route:" + str(r["route"])
    return None
eligible = [r["id"] for r in recs if why(r) is None]
cp0 = x["critical_path"][0] if x["critical_path"] else None
order = ([cp0] if cp0 in eligible else []) + [i for i in eligible if i != cp0]
sel = order[:cap]
print(" ".join(order))
for r in recs:
    w = why(r)
    print("%s=%s" % (r["id"], w if w else ("selected" if r["id"] in sel else "cap-deferred")))
PY
}

test_eligibility_order_and_cap() {
  begin test_eligibility_order_and_cap
  _w=$(section "$ORCH" "$WAVE_H")
  has "wave section" "$_w" 'Classify every record of `waves[0].features` as exactly one of `selected`, `cap-deferred` or `skipped: <reason>`.'
  has "wave section" "$_w" 'A record is eligible iff `runnable == true && autonomous == true && status == "pending" && route == "architect"` — those four envelope fields and nothing else'
  has "wave section" "$_w" '(a `pending` `sdd: false` fix routes to `builder` and belongs to `/sdd-fix-parallel`)'
  has "wave section" "$_w" 'A record that is not eligible is `skipped:` with the first failing predicate, checked in that order: `skipped: not-runnable [<code> …]` (its `blocked[]` codes), `skipped: not-autonomous`, `skipped: status:<status>`, or `skipped: route:<route>`; no record is silently dropped.'
  has "wave section" "$_w" 'Selection order is `critical_path[0]` first when it is eligible and in the wave, then the remaining eligible records in the envelope'"'"'s listed order.'
  has "wave section" "$_w" 'The first `cap` eligible records are `selected`; the rest are `cap-deferred` and stay `pending` for the operator'"'"'s next run.'
  has "wave section" "$_w" 'When the wave has no eligible record, the coordinator prints `no eligible feature in wave <N>` and exits 0 with no mutation.'
  _b=$(fold_file "$B_CLAUDE")
  has "sdd-next body" "$_b" 'It selects the runnable, autonomous, `pending`, `route: architect` records of `waves[0]` up to `cap`, `critical_path[0]` first, and reports every other record as `cap-deferred` or `skipped: <reason>`.'

  # E1-F5 is critical_path[0] (E1-F9 depends on it) and numerically LATER than eligible
  # E1-F2; E1-F3 is an autonomous sdd:false fix (route builder); E1-F4 is parked; E1-F6 is
  # not autonomous; E1-F7 is spec-ready. Listed in non-canonical order.
  _a='"autonomous":true'
  _b=$(board "E1:$(feat E1-F9 pending '["E1-F5"]' "$_a"),$(feat E1-F7 spec-ready '[]' "$_a"),$(feat E1-F6 pending),$(feat E1-F5 pending '[]' "$_a"),$(feat E1-F4 pending '[]' "$_a,\"parked\":{\"reason\":\"vendor\"}"),$(feat E1-F3 pending '[]' "$_a,\"sdd\":false"),$(feat E1-F2 pending '[]' "$_a")")
  if run_selector "$_b" --waves --json; then
    [ "$(json_field 'x["critical_path"][0]' <"$SEL/out")" = E1-F5 ] || fail "fixture: critical_path[0] is not E1-F5"
    [ "$(json_field '",".join(f["id"]+":"+str(f["route"]) for f in x["waves"][0]["features"])' <"$SEL/out")" = \
      "E1-F2:architect,E1-F3:builder,E1-F4:architect,E1-F5:architect,E1-F6:architect,E1-F7:builder" ] ||
      fail "envelope waves[0] ids/routes changed: $(json_field '[(f["id"],f["route"]) for f in x["waves"][0]["features"]]' <"$SEL/out")"
    _got=$(classify 1 | tr '\n' ' ')
    [ "$_got" = "E1-F5 E1-F2 E1-F2=cap-deferred E1-F3=skipped: route:builder E1-F4=skipped: not-runnable E1-F5=selected E1-F6=skipped: not-autonomous E1-F7=skipped: status:spec-ready " ] ||
      fail "predicate over the envelope: got [$_got]"
    [ "$(json_field '[c["code"] for f in x["waves"][0]["features"] if f["id"]=="E1-F4" for c in f["blocked"]]' <"$SEL/out")" = "['parked']" ] ||
      fail "E1-F4 blocked[] codes are not ['parked']"
  else
    fail "eligibility fixture selector run exited non-zero"
  fi
  end
}

# ── R5 — provisioning via the widened helper (the helper itself: test_fix_worktree.sh) ──
test_slug_rule_prose() {
  begin test_slug_rule_prose
  _w=$(section "$ORCH" "$WAVE_H")
  has "wave section" "$_w" 'the coordinator calls `tools/fix-worktree.sh create <id> <slug>` (installed: `.harness/tools/fix-worktree.sh`) once per selected feature, sequentially, before any manifest or board write'
  has "wave section" "$_w" 'The helper accepts any `E<digits>-F<digits>` id and creates branch `feat/<id>-<slug>` and worktree `<primary>/.claude/worktrees/<id>-<slug>`.'
  has "wave section" "$_w" 'The coordinator derives `<slug>` from the board'"'"'s `spec_path` for that feature, which it reads and never writes:'
  has "wave section" "$_w" 'take the last path component (ignoring a trailing `/`), remove the leading `F<digits>-`, lowercase it, collapse every run of characters outside `[a-z0-9]` to one `-`, trim leading and trailing `-`, and use `wave` when the result is empty.'
  has "wave section" "$_w" 'A feature whose `create` fails is classified `provisioning-failed: <helper stderr>`, stays `pending`, and does not stop its siblings.'
  end
}

# ── R6 — manifest before dispatch ──────────────────────────────────────────────────────
test_manifest_contract() {
  begin test_manifest_contract
  _w=$(section "$ORCH" "$WAVE_H")
  has "wave section" "$_w" 'After every selected `create` has settled and before the first worker is spawned, the coordinator writes `progress/wave-<YYYYMMDDTHHMMSSZ>/summary.md`'
  has "wave section" "$_w" 'Its header carries `wave: <N>`, `cap: <n> (<source>)` where the source is `--max`, `workflow.max_wave` or `default`,'
  has "wave section" "$_w" 'one line per record of `waves[0]` — every record, none absent — with the record'"'"'s classification and, for a provisioned feature, its exact branch and worktree.'
  _d=$(subsection "$WORKFLOW" "$WF_H")
  has "WORKFLOW wave subsection" "$_d" 'the coordinator writes the manifest `progress/wave-<YYYYMMDDTHHMMSSZ>/summary.md` with every record of the wave'
  end
}

# ── R7 — worker identity and board writes ──────────────────────────────────────────────
# status_of <board> <id>: the feature's status in that board file.
status_of() {
  python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print([f["status"] for e in d["epics"] for f in e["features"] if f["id"]==sys.argv[2]][0])' "$1" "$2"
}

test_worker_identity_and_harness_dir() {
  begin test_worker_identity_and_harness_dir
  _w=$(section "$ORCH" "$WAVE_H")
  has "wave section" "$_w" 'The coordinator spawns every provisioned worker before awaiting any one of them, up to `cap`'
  has "wave section" "$_w" 'given exactly: its feature id; the primary'"'"'s absolute path to its inbox brief, or `-` when `progress/inbox/<id>.md` is absent'
  has "wave section" "$_w" 'its pre-provisioned branch and worktree; `HARNESS_DIR` set to that worktree; and the manifest path.'
  has "wave section" "$_w" 'It starts at the Architect: `pending → spec-ready → in-progress`; `autonomous: true` skips the human gate but still records the gate-span pair'
  has "wave section" "$_w" 'A wave worker writes every board transition through `HARNESS_DIR="<its worktree>" python3 "$HARNESS_DIR/tools/tasks-lock.py"` and commits those transitions on its own feature branch'
  has "wave section" "$_w" 'where the targeted mode above says canonical main `HARNESS_DIR`, a wave worker uses its own worktree instead.'
  has "wave section" "$_w" 'On entry it reads the feature'"'"'s status from its own worktree board and resumes at that phase, so a re-spawned worker never restarts the Architect.'
  has "wave section" "$_w" 'A wave worker never stages, commits, switches, stashes, resets or cleans the primary.'
  has "wave section" "$_w" 'It stops after opening its PR, with the feature left `in-review`: it never merges, never runs `/sdd-pr-loop`, never writes `done` and never tears down its worktree.'
  _g=$(section "$ORCH" '## Targeted parallel-fix worker mode')
  has "targeted worker section" "$_g" 'or when `/sdd-next --wave` supplies one exact autonomous `sdd: true` feature at `pending`'

  # Executed: a real linked worktree from the widened helper; the explicit HARNESS_DIR
  # write lands on the worktree's board and leaves the primary's byte-identical.
  _p="$TMP/r7/primary"
  mkdir -p "$_p/state" "$_p/store"
  safe_git init -q -b main "$_p" || { fail "r7 git init"; end; return 0; }
  cp -R "$ROOT/tools" "$_p/tools"
  cp "$ROOT/store/tasks.schema.json" "$_p/store/tasks.schema.json"
  printf '#!/bin/sh\nexit 0\n' >"$_p/init.sh"
  chmod +x "$_p/init.sh"
  printf '.claude/worktrees/\n' >"$_p/.gitignore"
  board "E1:$(feat E1-F1 pending '[]' '"autonomous":true'),$(feat E1-F2 pending '[]' '"autonomous":true')" >"$_p/state/tasks.json"
  safe_git -C "$_p" add -A && safe_git -C "$_p" -c user.name=t -c user.email=t@example.test commit -qm base ||
    { fail "r7 fixture commit"; end; return 0; }
  _wt=$(cd "$_p" && env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 sh tools/fix-worktree.sh create E1-F1 one 2>"$TMP/r7.err") ||
    { fail "r7 create E1-F1 failed: $(cat "$TMP/r7.err")"; end; return 0; }
  [ -f "$_wt/state/tasks.json" ] || { fail "r7 worktree has no board: $_wt"; end; return 0; }
  _prim_before=$(cksum <"$_p/state/tasks.json")
  _wt_before=$(cksum <"$_wt/state/tasks.json")
  (cd "$_wt" && HARNESS_DIR="$_wt" python3 "$_wt/tools/tasks-lock.py" set-status E1-F1 spec-ready) >"$TMP/r7.out" 2>&1 ||
    fail "explicit HARNESS_DIR set-status failed: $(cat "$TMP/r7.out")"
  [ "$(cksum <"$_p/state/tasks.json")" = "$_prim_before" ] || fail "explicit HARNESS_DIR write changed the PRIMARY board"
  [ "$(cksum <"$_wt/state/tasks.json")" != "$_wt_before" ] || fail "explicit HARNESS_DIR write left the worktree board unchanged"
  [ "$(status_of "$_wt/state/tasks.json" E1-F1)" = spec-ready ] || fail "worktree board E1-F1 is not spec-ready"
  # Control: without the override the linked-worktree remap writes the PRIMARY board, so
  # the explicit HARNESS_DIR is what keeps a worker's transitions on its own branch.
  _wt_mid=$(cksum <"$_wt/state/tasks.json")
  (cd "$_wt" && env -u HARNESS_DIR python3 "$_wt/tools/tasks-lock.py" set-status E1-F2 spec-ready) >"$TMP/r7c.out" 2>&1 ||
    fail "control set-status failed: $(cat "$TMP/r7c.out")"
  [ "$(status_of "$_p/state/tasks.json" E1-F2)" = spec-ready ] || fail "control: the remap did not write the primary board"
  [ "$(cksum <"$_wt/state/tasks.json")" = "$_wt_mid" ] || fail "control: the remapped write also changed the worktree board"
  end
}

# ── R8 — test-runner lock behaviour ────────────────────────────────────────────────────
test_runner_lock_contract() {
  begin test_runner_lock_contract
  _w=$(section "$ORCH" "$WAVE_H")
  has "wave section" "$_w" 'A worker runs the full `verification.test_command` at most once per role phase, as a gate, and touched suites while iterating'
  has "wave section" "$_w" 'When the runner refuses with exit 5, the worker records `runner-busy`, does not re-invoke the runner, leaves the feature at its current status (the Reviewer never approves without a green gate) and returns.'
  has "wave section" "$_w" 'Nothing here raises `--jobs`'
  has "wave section" "$_w" 'A worker whose sub-agent or tool call was cancelled or killed, or that returned without a verdict, is `interrupted`: a stop, never relaunched, never queued.'
  has "wave section" "$_w" 'A runner exit of 1 is a red suite and is never reclassified as a signal'
  has "wave section" "$_w" 'the distinction is observed at the worker boundary, not from the exit code.'
  has "wave section" "$_w" 'After the parallel wave settles, the coordinator re-spawns each `runner-busy` worker one at a time in selection order'
  has "wave section" "$_w" 'with the same inputs; the worker resumes from its worktree board'"'"'s status.'
  has "wave section" "$_w" 'This pass runs at most once per feature: a second `runner-busy` is the terminal verdict `stopped: runner-busy twice`.'
  _d=$(subsection "$WORKFLOW" "$WF_H")
  has "WORKFLOW wave subsection" "$_d" 'A worker whose full test gate is refused (exit 5) returns `runner-busy` and is re-run once, alone, after the wave settles; a cancelled or killed worker is `interrupted` and is never relaunched.'

  # Executed: a live-pid lock in a PRIVATE TMPDIR makes the runner refuse with exit 5
  # before any suite runs. The probe suite is a dummy (never this suite: a broken lock
  # must not recurse into it), and the nested marker is unset for this one call.
  _l="$TMP/lock"
  mkdir -p "$_l"
  printf '#!/bin/sh\necho "PROBE-SUITE-RAN"\n' >"$_l/test_lock_probe.sh"
  printf '%s\n' "$$" >"$_l/harness-run-tests.lock"
  _rc=0
  env -u HARNESS_RUN_TESTS_NESTED TMPDIR="$_l" sh "$ROOT/tools/run-tests.sh" "$_l/test_lock_probe.sh" \
    >"$_l/out" 2>"$_l/err" || _rc=$?
  [ "$_rc" = 5 ] || fail "runner with a live-pid lock exited $_rc, not 5"
  grep -qF 'another run-tests.sh' "$_l/err" || fail "runner refusal does not name another run-tests.sh: $(cat "$_l/err")"
  grep -qF 'PROBE-SUITE-RAN' "$_l/out" "$_l/err" && fail "the runner ran a suite despite the lock"
  [ "$(cat "$_l/harness-run-tests.lock")" = "$$" ] || fail "the refused runner disturbed the holder's lock"
  rm -f "$_l/harness-run-tests.lock"
  end
}

# ── R9 — summary table and serialized merge plan ───────────────────────────────────────
test_summary_and_merge_plan() {
  begin test_summary_and_merge_plan
  _w=$(section "$ORCH" "$WAVE_H")
  _b=$(fold_file "$B_CLAUDE")
  _d=$(subsection "$WORKFLOW" "$WF_H")
  for _lit in pr-opened runner-busy interrupted 'next MINOR' 'merge order'; do
    has "wave section" "$_w" "$_lit"
    has "sdd-next body" "$_b" "$_lit"
    has "WORKFLOW wave subsection" "$_d" "$_lit"
  done
  has "wave section" "$_w" 'When every worker has settled, the coordinator prints a summary table with one row per selected feature, `feature | branch | PR | verdict`, where the verdict is one of `pr-opened`, `interrupted` or `stopped: <reason>`'
  has "wave section" "$_w" '`runner-busy` is a worker-return value consumed by W6 and never a final-table verdict.'
  has "wave section" "$_w" 'a `merge order:` line listing the PRs in selection order'
  has "wave section" "$_w" 'Before `/sdd-pr-loop` on each PR after the first, integrate the updated `main` into that branch with one merge commit;'
  has "wave section" "$_w" '`VERSION` becomes the next MINOR over the then-current `main`;'
  has "wave section" "$_w" 'place this feature'"'"'s `CHANGELOG.md` entry above main'"'"'s newest entry under that version;'
  has "wave section" "$_w" 'keep both sides of `progress/history.md` and of `state/tasks.json`.'
  has "wave section" "$_w" 'The coordinator runs no `/sdd-pr-loop`, performs no merge, writes no `done`, and tears down no worktree;'
  has "wave section" "$_w" 'It exits 0 iff every selected feature'"'"'s verdict is `pr-opened`.'
  has "wave section" "$_w" 'Wave 2 is not automatic: after wave 1 merges, the operator re-runs `/sdd-next --wave`, which derives the next wave from the updated board.'
  has "sdd-next body" "$_b" 'it prints the summary table (verdicts `pr-opened`, `interrupted` or `stopped: <reason>`; a `runner-busy` worker is re-run once, alone)'
  has "sdd-next body" "$_b" 'and the `merge order:` plan, in which each later PR takes the next MINOR `VERSION` over the then-current `main`.'
  has "sdd-next body" "$_b" 'It runs no `/sdd-pr-loop`, merges nothing, writes no `done` and tears down no worktree.'
  has "WORKFLOW wave subsection" "$_d" 'Each worker opens its PR and leaves the feature `in-review` with verdict `pr-opened`; it never runs `/sdd-pr-loop` and never merges.'
  has "WORKFLOW wave subsection" "$_d" 'The coordinator prints a `merge order:` line (the selection order).'
  has "WORKFLOW wave subsection" "$_d" 'The operator runs `/sdd-pr-loop` per PR in that order;'
  has "WORKFLOW wave subsection" "$_d" 'set `VERSION` to the next MINOR over the then-current `main`'
  has "WORKFLOW wave subsection" "$_d" 'the operator retires the worktree with `tools/fix-worktree.sh teardown <id> <slug>` from a clean primary.'
  end
}

# ── R11 — role, command and docs prose surfaces ────────────────────────────────────────
test_prose_surfaces() {
  begin test_prose_surfaces
  grep -qxF "$WAVE_H" "$ORCH" || fail "installed orchestrator.md lacks the heading line: $WAVE_H"
  # Placement: the wave section is the next `## ` section after the targeted worker mode.
  _next=$(awk "$FENCE_AWK"'
    fence_delim($0) { next }
    !fence && /^## Targeted parallel-fix worker mode$/ { k = 1; next }
    !fence && k && /^## / { print; exit }
  ' "$ORCH")
  [ "$_next" = "$WAVE_H" ] || fail "the wave section does not directly follow the targeted worker mode (next: $_next)"
  _w=$(section "$ORCH" "$WAVE_H")
  has "wave section" "$_w" 'It reuses the fix lane by reference, not by copy: provisioning, manifest completeness and fan-out discipline are `agents/fixer.md`'"'"'s "Parallel dispatch mode"'
  for _f in "$B_CLAUDE" "$B_OPENCODE" "$B_SKILL" "$ORCH" "$WORKFLOW"; do
    grep -qF '/sdd-next --wave' "$_f" || fail "${_f#"$T"/} lacks /sdd-next --wave"
  done
  _r=$(section "$WORKFLOW" '## Running in waves and across machines')
  has "WORKFLOW waves section" "$_r" "$WF_H"
  _l=$(subsection "$WORKFLOW" '### Bounded parallel fix lane (`/sdd-fix-parallel`)')
  has "WORKFLOW fix-lane subsection" "$_l" 'The helper `tools/fix-worktree.sh` accepts any `E##-F##` id, so `/sdd-next --wave` provisions `sdd: true` features with it too; the E99 lane itself is unchanged.'
  end
}

# ── R12 — release record (durable facts only; never a literal VERSION, never "the top entry")
test_release_record() {
  begin test_release_record
  _v=$(tr -d '[:space:]' <"$ROOT/VERSION")
  _newest=$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "$ROOT/CHANGELOG.md" | head -1)
  [ -n "$_v" ] && [ "$_v" = "$_newest" ] || fail "VERSION ($_v) is not the newest CHANGELOG heading ($_newest)"
  # Some `## [x.y.z]` entry body names both --wave and workflow.max_wave.
  awk '/^## \[[0-9]/ { if (h && b ~ /--wave/ && b ~ /workflow\.max_wave/) f = 1; b = ""; h = 1; next } { b = b " " $0 }
       END { if (h && b ~ /--wave/ && b ~ /workflow\.max_wave/) f = 1; exit f ? 0 : 1 }' "$ROOT/CHANGELOG.md" ||
    fail "no CHANGELOG entry names both --wave and workflow.max_wave"
  end
}

test_wave_token_in_generated_bodies
test_max_wave_config_seed
test_preflight_contract
test_wave_read_consumes_envelope
test_eligibility_order_and_cap
test_slug_rule_prose
test_manifest_contract
test_worker_identity_and_harness_dir
test_runner_lock_contract
test_summary_and_merge_plan
test_prose_surfaces
test_release_record

_after=$(protected_cksums)
[ "$PROTECTED_BEFORE" = "$_after" ] || { FAILS=$((FAILS + 1)); echo "FAIL: [suite] a DO-NOT-TOUCH file changed during the suite" >&2; }

if [ "$FAILS" -ne 0 ]; then
  echo "test_sdd_next_wave: $FAILS failure(s)" >&2
  exit 1
fi
echo "test_sdd_next_wave: all cases passed"
