#!/bin/sh
# test_self_mode.sh — E26-F01 `--self`: the source repo's glue is installer-generated.
#
# Covers R1 (source-layout regeneration + arg guards), R2 (reconciliation sentinels),
# R3 (shim models harvested and preserved), R4 (arming from the real verdict, both
# arms), R5 (pr-loop gate mirrors the repo's own config), R6 (idempotence +
# no-collateral), R7 (target installs carry the same reconciled prose, prefixed).
#
# Fixture: a COPY of the source tree (git-tracked files only would need git; instead
# copy the files `--self`'s temp install_one actually reads), so `--self` runs never
# touch the real checkout. Zero dependencies; self-cleaning temp dir; POSIX sh.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT

# Sandbox Codex's GLOBAL prompts dir (house guard for every installer-invoking suite).
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# fixture <name> — copy the source tree into $T/<name> and print the path. cp -R of
# the whole checkout minus VCS/scratch dirs: --self's temp install copies the harness
# body from $SRC, so the fixture must carry it all.
fixture() {
  _fx="$T/$1"
  mkdir -p "$_fx"
  for _e in "$SRC"/* "$SRC"/.claude "$SRC"/.codex "$SRC"/.agents "$SRC"/.escalation-arming; do
    [ -e "$_e" ] || continue
    case "$(basename "$_e")" in .git|node_modules) continue ;; esac
    cp -R "$_e" "$_fx/" 2>/dev/null || true
  done
  printf '%s\n' "$_fx"
}

F="$(fixture main)"
# F02 falsifiability: the fixture inherits the COMMITTED `opencode.json` through the
# `"$SRC"/*` glob, and `.opencode/` is absent by construction. Delete the inherited
# artifact so the real `--self` run below must GENERATE it — otherwise the OpenCode
# assertions prove the repo's state, not the code's behavior (progress/lessons.md
# 2026-09-05, copied fixture).
rm -f "$F/opencode.json"
rm -rf "$F/.opencode"

# ── R1: arg guards refuse other modes before any write ────────────────────────
sh "$F/harness-install.sh" --self "$T/x" >/dev/null 2>&1 && fail "--self with a target path should exit non-zero (R1)"
sh "$F/harness-install.sh" --self --umbrella "$T" >/dev/null 2>&1 && fail "--self with --umbrella should exit non-zero (R1)"
sh "$F/harness-install.sh" --self --print-agents >/dev/null 2>&1 && fail "--self with --print-agents should exit non-zero (R1)"
pass "--self refuses target/--umbrella/--print-agents (R1) [self_arg_guards]"

# ── the real run ──────────────────────────────────────────────────────────────
sh "$F/harness-install.sh" --self >"$T/out1.txt" 2>&1 \
  || { cat "$T/out1.txt" >&2; fail "--self exited non-zero"; }

# ── R1: source layout — no .harness/ prefix survives outside the banner ───────
grep -q '`agents/builder.md`' "$F/.claude/agents/builder.md" \
  || fail "builder shim does not point at the source-layout agents/builder.md (R1)"
_stray="$(grep -rn '\.harness/' "$F/.claude" | grep -v 'source-layout copy' | grep -v 'resolved against' || true)"
[ -z "$_stray" ] || { echo "$_stray" >&2; fail "a .harness/ prefix survived the self transform (R1)"; }
pass "regenerated glue resolves from the repository root (R1) [self_source_layout]"

# ── R3: shim models harvested and preserved ───────────────────────────────────
grep -q "^model: sonnet\$" "$F/.claude/agents/builder.md" \
  || fail "builder lost its recorded model: sonnet (R3)"
grep -q "^model: opus\$" "$F/.claude/agents/builder-heavy.md" \
  || fail "builder-heavy lost its recorded model: opus (R3)"
grep -q "^model:" "$F/.claude/agents/scout.md" \
  && fail "scout grew a model: line it never had (R3)"
pass "recorded shim models survive regeneration; model-less shims stay model-less (R3) [self_models_preserved]"

# ── R4: arming written from the real verdict ──────────────────────────────────
[ -f "$F/.escalation-arming" ] || fail "no .escalation-arming at the repo root (R4)"
grep -q "^blocked\$" "$F/.escalation-arming" || fail "combined inherited Codex did not disarm (E29-F01 R5)"
grep -q "^claude=raise\$" "$F/.escalation-arming" || fail "claude verdict is not raise (R4)"
grep -q "^codex=neither\$" "$F/.escalation-arming" || fail "inherited Codex verdict missing"
C="$(fixture claude-only)"
sh "$C/harness-install.sh" --self --agents=claude >/dev/null 2>&1 || fail "Claude-only self failed"
grep -qx armed "$C/.escalation-arming" || fail "Claude-only sonnet→opus lost arming"
pass "combined inherited Codex is unarmed; explicit Claude-only retains arming (R4/R5) [self_arming_real]"

# Disarmed arm: with NO recorded models anywhere, nothing resolves — the verdict file
# is reclaimed, exactly as write_escalation_arming does for an unconfigured target.
D="$(fixture disarmed)"
for _sh in "$D"/.claude/agents/*.md; do
  grep -v "^model: " "$_sh" > "$_sh.t" && mv "$_sh.t" "$_sh"
done
sh "$D/harness-install.sh" --self >"$T/out-disarmed.txt" 2>&1 \
  || { cat "$T/out-disarmed.txt" >&2; fail "--self with model-less shims exited non-zero (R4)"; }
[ -f "$D/.escalation-arming" ] \
  && fail "model-less shims still produced an arming verdict — hardcoded, not computed (R4)"
pass "model-less shims reclaim the arming verdict — no hardcoded armed (R4) [self_arming_disarmed]"

# ── R2: reconciliation sentinels ──────────────────────────────────────────────
grep -q "intent brief" "$F/.claude/commands/sdd-next.md" \
  || fail "inception-brief routing did not survive into sdd-next (R2)"
grep -q "baseRefOid" "$F/.claude/commands/sdd-pr-loop.md" \
  || fail "the emitter-side baseRefOid fields did not reach the source copy (R2)"
grep -q "as this one does" "$F/.claude/commands/sdd-pr-loop.md" \
  && fail "the repo-specific severity aside survived reconciliation (R2)"
grep -q '\.pr-loop/\$pr_number' "$F/.claude/commands/sdd-pr-loop.md" \
  || fail "a .pr-loop/ cache token was damaged by the prefix strip (R2)"
grep -q "source-layout" "$F/.claude/commands/sdd-pr-loop.md" \
  || fail "the source-layout banner line is missing (R2)"
pass "reconciled content flows both directions; repo-asides dropped (R2) [self_reconciliation]"

# ── R5: pr-loop glue mirrors the repo's own gate ──────────────────────────────
[ -f "$F/.claude/commands/sdd-pr-loop.md" ] || fail "pr_loop.enabled=true but no sdd-pr-loop.md (R5)"
[ -f "$F/.claude/agents/pr-fixer.md" ] || fail "pr_loop.enabled=true but no pr-fixer shim (R5)"
G="$(fixture gated)"
sed 's/^  enabled: true/  enabled: false/' "$G/harness.config.yaml" > "$G/harness.config.yaml.t" \
  && mv "$G/harness.config.yaml.t" "$G/harness.config.yaml"
sh "$G/harness-install.sh" --self >"$T/out-gated.txt" 2>&1 \
  || { cat "$T/out-gated.txt" >&2; fail "--self with gate off exited non-zero (R5)"; }
[ -f "$G/.claude/commands/sdd-pr-loop.md" ] && fail "gate off but sdd-pr-loop.md kept (R5)"
[ -f "$G/.claude/agents/pr-fixer.md" ] && fail "gate off but pr-fixer.md kept (R5)"
pass "pr-loop glue follows the repo's own pr_loop.enabled, both directions (R5) [self_prloop_gate]"

# ── R6: idempotent + no collateral ────────────────────────────────────────────
cp -R "$F/.claude" "$T/snap"
cp -R "$F/.codex" "$T/snap-codex"
cp -R "$F/.agents" "$T/snap-skills"
# The OpenCode snapshot is conditional so that on code WITHOUT OpenCode generation this
# block does not abort the suite before the R1 assertion can name the real symptom; R1
# pins existence unconditionally.
_oc_snap=0
if [ -f "$F/opencode.json" ] && [ -d "$F/.opencode" ]; then
  _oc_snap=1
  cp -R "$F/.opencode" "$T/snap-opencode"
  cp "$F/opencode.json" "$T/snap-opencode-json"
fi
cp "$F/.escalation-arming" "$T/snap-arm"
_ver1="$(cat "$F/VERSION")"; _cfg1="$(cat "$F/harness.config.yaml")"
: > "$F/sentinel-outside-glue.txt"
sh "$F/harness-install.sh" --self >/dev/null 2>&1 || fail "second --self run exited non-zero (R6)"
diff -rq "$T/snap" "$F/.claude" >/dev/null || fail "second --self run changed glue bytes (R6)"
diff -rq "$T/snap-codex" "$F/.codex" >/dev/null || fail "second self changed Codex roles"
diff -rq "$T/snap-skills" "$F/.agents" >/dev/null || fail "second self changed Codex skill units"
if [ "$_oc_snap" = 1 ]; then
  diff -rq "$T/snap-opencode" "$F/.opencode" >/dev/null || fail "second self changed the OpenCode command/agent glue (R6)"
  cmp -s "$T/snap-opencode-json" "$F/opencode.json" || fail "second self changed opencode.json (R6)"
fi
cmp -s "$T/snap-arm" "$F/.escalation-arming" || fail "second --self run changed the arming file (R6)"
[ "$(cat "$F/VERSION")" = "$_ver1" ] || fail "--self touched VERSION (R6)"
[ "$(cat "$F/harness.config.yaml")" = "$_cfg1" ] || fail "--self touched harness.config.yaml (R6)"
[ -f "$F/sentinel-outside-glue.txt" ] && [ ! -s "$F/sentinel-outside-glue.txt" ] \
  || fail "--self touched a file outside the glue dirs (R6)"
[ -f "$F/.harness-version" ] && fail "--self stamped a .harness-version at the source root (R6)"
pass "idempotent; VERSION/config/sentinel untouched; no version stamp (R6) [self_idempotent_no_collateral]"

# ── R7: a normal target install carries the same reconciled prose, prefixed ───
TGT="$T/tgt"; mkdir -p "$TGT"
HARNESS_AGENTS=claude sh "$F/harness-install.sh" "$TGT" >/dev/null 2>&1 \
  || fail "target install exited non-zero (R7)"
grep -q "intent brief" "$TGT/.claude/commands/sdd-next.md" \
  || fail "target sdd-next lacks the upstreamed inception-brief routing (R7)"
grep -q '`\.harness/agents/builder\.md`' "$TGT/.claude/agents/builder.md" \
  || fail "target builder shim is not .harness/-prefixed (R7)"
pass "targets get the same reconciled prose with .harness/ paths (R7) [target_same_prose]"

# ══════════════════════════════════════════════════════════════════════════════
# E31-F02 — the source OpenCode glue is installer-generated.
#
# Functions are named exactly as E31-F02.tests.md maps them, so the traceability
# matrix is greppable. Each asserts GENERATED behavior on a fixture that deleted the
# inherited artifact first (the purge beside F above).
# ══════════════════════════════════════════════════════════════════════════════

# purge_opencode <dir> — remove inherited OpenCode glue so a run must regenerate it.
purge_opencode() { rm -f "$1/opencode.json"; rm -rf "$1/.opencode"; }

self_regenerates_opencode_glue() {
  [ -f "$F/opencode.json" ] || fail "bare --self did not create opencode.json (R1)"
  for _c in sdd-next sdd-new sdd-plan sdd-drill sdd-fix sdd-test-concurrency sdd-pr-loop; do
    [ -f "$F/.opencode/command/$_c.md" ] || fail "bare --self did not create .opencode/command/$_c.md (R1)"
  done
  [ -f "$F/.opencode/agent/pr-fixer.md" ] || fail "bare --self did not create .opencode/agent/pr-fixer.md (R1)"
  # Ordering assertion (2026-09-17): the default selection is recorded as an ordered
  # list, not a label. The arming detail lines follow $AGENT_KEYS order, so this proves
  # opencode is IN the default set AND that claude/codex were not dropped.
  _order="$(grep -v '^blocked$' "$F/.escalation-arming" | awk -F= '{print $1}' | tr '\n' ' ' | sed 's/ $//')"
  [ "$_order" = "claude codex opencode" ] \
    || fail "default --self selection is not the ordered set 'claude codex opencode' (got '$_order') (R1)"
  pass "bare --self regenerates opencode.json + .opencode command/agent glue (R1) [self_regenerates_opencode_glue]"
}

opencode_json_has_builder_heavy() {
  [ -f "$F/opencode.json" ] || fail "opencode.json missing (R2)"
  python3 - "$F/opencode.json" <<'PY' || fail "opencode.json does not define the six standard roles + builder-heavy in source layout (R2)"
import json, sys
with open(sys.argv[1]) as fh:
    cfg = json.load(fh)
agents = cfg.get("agent", {})
want = {"orchestrator","architect","builder","builder-heavy","reviewer","scout","doc-critic"}
missing = want - set(agents)
if missing:
    sys.stderr.write("missing roles: %s\n" % sorted(missing)); sys.exit(1)
if cfg.get("instructions") != ["AGENTS.md"]:
    sys.stderr.write("instructions is %r, expected ['AGENTS.md']\n" % (cfg.get("instructions"),)); sys.exit(1)
for role, entry in agents.items():
    want_mode = "primary" if role == "orchestrator" else "subagent"
    if entry.get("mode") != want_mode:
        sys.stderr.write("%s mode is %r, expected %r\n" % (role, entry.get("mode"), want_mode)); sys.exit(1)
    want_prompt = "{file:./agents/%s.md}" % role
    if entry.get("prompt") != want_prompt:
        sys.stderr.write("%s prompt is %r, expected %s\n" % (role, entry.get("prompt"), want_prompt)); sys.exit(1)
PY
  pass "source opencode.json defines the six roles + builder-heavy (R2) [opencode_json_has_builder_heavy]"
}

self_opencode_pr_fixer_gate() {
  # (a) gate on (the repo's own config): the generated pr-fixer surface is present.
  [ -f "$F/.opencode/agent/pr-fixer.md" ] || fail "pr_loop.enabled=true but no .opencode/agent/pr-fixer.md (R3)"
  [ -f "$F/.opencode/command/sdd-pr-loop.md" ] || fail "pr_loop.enabled=true but no .opencode/command/sdd-pr-loop.md (R3)"
  # (b) flipping the gate off reclaims a PRISTINE generated file.
  P="$(fixture oc-gateoff)"; purge_opencode "$P"
  sh "$P/harness-install.sh" --self >/dev/null 2>&1 || fail "gate-on self failed (R3)"
  [ -f "$P/.opencode/agent/pr-fixer.md" ] || fail "precondition: gate-on run wrote no pr-fixer (R3)"
  sed 's/^  enabled: true/  enabled: false/' "$P/harness.config.yaml" > "$P/harness.config.yaml.t" \
    && mv "$P/harness.config.yaml.t" "$P/harness.config.yaml"
  sh "$P/harness-install.sh" --self >"$T/oc-gateoff.log" 2>&1 \
    || { cat "$T/oc-gateoff.log" >&2; fail "gate-off self failed (R3)"; }
  [ -f "$P/.opencode/agent/pr-fixer.md" ] && fail "gate off but a pristine .opencode/agent/pr-fixer.md was kept (R3)"
  [ -f "$P/.opencode/command/sdd-pr-loop.md" ] && fail "gate off but a pristine .opencode/command/sdd-pr-loop.md was kept (R3)"
  # (c) an EDITED pr-fixer is preserved with a warning and left unclaimed.
  E="$(fixture oc-edited)"; purge_opencode "$E"
  sh "$E/harness-install.sh" --self >/dev/null 2>&1 || fail "edited-gate setup failed (R3)"
  printf '\nUSER CONTENT\n' >> "$E/.opencode/agent/pr-fixer.md"
  _edited="$(cat "$E/.opencode/agent/pr-fixer.md")"
  sed 's/^  enabled: true/  enabled: false/' "$E/harness.config.yaml" > "$E/harness.config.yaml.t" \
    && mv "$E/harness.config.yaml.t" "$E/harness.config.yaml"
  sh "$E/harness-install.sh" --self >"$T/oc-edited.log" 2>&1 || fail "edited gate-off self failed (R3)"
  grep -q "left unchanged and unclaimed" "$T/oc-edited.log" \
    || fail "no warning for a preserved edited pr-fixer (R3)"
  [ "$(cat "$E/.opencode/agent/pr-fixer.md")" = "$_edited" ] || fail "an edited pr-fixer was modified (R3)"
  # (d) a SYMLINKED pr-fixer is preserved, and its target is never overwritten.
  L="$(fixture oc-link)"; purge_opencode "$L"
  sh "$L/harness-install.sh" --self >/dev/null 2>&1 || fail "link setup failed (R3)"
  _ext="$T/oc-external-pr-fixer"; mv "$L/.opencode/agent/pr-fixer.md" "$_ext"
  ln -s "$_ext" "$L/.opencode/agent/pr-fixer.md"
  _extsum="$(cksum "$_ext")"
  sed 's/^  enabled: true/  enabled: false/' "$L/harness.config.yaml" > "$L/harness.config.yaml.t" \
    && mv "$L/harness.config.yaml.t" "$L/harness.config.yaml"
  sh "$L/harness-install.sh" --self >"$T/oc-link.log" 2>&1 || fail "link gate-off self failed (R3)"
  [ -L "$L/.opencode/agent/pr-fixer.md" ] || fail "a symlinked pr-fixer was replaced (R3)"
  [ "$(cksum "$_ext")" = "$_extsum" ] || fail "a symlinked pr-fixer's target was overwritten (R3)"
  pass "pr-fixer follows pr_loop.enabled both ways, preserving edited/symlinked files (R3) [self_opencode_pr_fixer_gate]"
}

self_opencode_capability_glue_absent() {
  [ -f "$F/.opencode/command/sdd-test-concurrency.md" ] || fail "sdd-test-concurrency.md not generated (R4)"
  [ -e "$F/.opencode/command/sdd-fix-parallel.md" ] && fail "sdd-fix-parallel.md generated into source (R4)"
  [ -e "$F/.opencode-parallel" ] && fail ".opencode-parallel appeared at the source root (R4)"
  # The CLI flag is the ONLY lever that can reach the temp install; --self must neutralise
  # it and the output must be byte-identical with and without it (a lone absence check
  # cannot prove neutralisation).
  W="$(fixture oc-parallel-flag)"; purge_opencode "$W"
  sh "$W/harness-install.sh" --self --with-opencode-parallel=true >"$T/oc-flag.log" 2>&1 \
    || { cat "$T/oc-flag.log" >&2; fail "--self with --with-opencode-parallel=true failed (R4)"; }
  [ -e "$W/.opencode/command/sdd-fix-parallel.md" ] && fail "the CLI flag reached the source output (R4)"
  [ -e "$W/.opencode-parallel" ] && fail "the CLI flag produced a source marker (R4)"
  diff -r "$W/.opencode" "$F/.opencode" >/dev/null \
    || fail "OpenCode glue differs with/without --with-opencode-parallel=true (R4)"
  cmp -s "$W/opencode.json" "$F/opencode.json" \
    || fail "opencode.json differs with/without --with-opencode-parallel=true (R4)"
  pass "capability-gated command/marker never reach source; bytes flag-independent (R4) [self_opencode_capability_glue_absent]"
}

self_opencode_ownership_guards() {
  _mf="$(cat "$F/.claude/.glue-manifest")"
  printf '%s\n' "$_mf" | grep -q ' opencode\.json$' || fail "manifest misses opencode.json (R5)"
  printf '%s\n' "$_mf" | grep -q ' \.opencode/command/sdd-next\.md$' || fail "manifest misses a command unit (R5)"
  printf '%s\n' "$_mf" | grep -q ' \.opencode/agent/pr-fixer\.md$' || fail "manifest misses pr-fixer (R5)"
  printf '%s\n' "$_mf" | grep -q '\.opencode-parallel' && fail "manifest claims .opencode-parallel (R5)"
  grep -qx 'opencode=neither' "$F/.escalation-arming" || fail "arming does not record opencode=neither (R5)"
  grep -qx 'blocked' "$F/.escalation-arming" || fail "arming first line is not blocked (R5)"
  grep -q 'opencode=unstamped' "$F/.escalation-arming" && fail "arming published a fabricated opencode=unstamped (R5)"
  # A foreign/edited opencode.json is preserved, warned about, and dropped from the ledger.
  O="$(fixture oc-foreign)"; purge_opencode "$O"
  sh "$O/harness-install.sh" --self >/dev/null 2>&1 || fail "foreign setup failed (R5)"
  printf '\nUSER\n' >> "$O/opencode.json"
  _before="$(cat "$O/opencode.json")"
  sh "$O/harness-install.sh" --self >"$T/oc-foreign.log" 2>&1 || fail "foreign self failed (R5)"
  grep -q "left unchanged and unclaimed" "$T/oc-foreign.log" || fail "no warning for an edited opencode.json (R5)"
  [ "$(cat "$O/opencode.json")" = "$_before" ] || fail "an edited opencode.json was overwritten (R5)"
  grep -q ' opencode\.json$' "$O/.claude/.glue-manifest" && fail "an edited opencode.json stayed claimed (R5)"
  # A symlinked command unit is preserved, target untouched, and unclaimed.
  S="$(fixture oc-symlink)"; purge_opencode "$S"
  sh "$S/harness-install.sh" --self >/dev/null 2>&1 || fail "symlink setup failed (R5)"
  _ext="$T/oc-external-next"; mv "$S/.opencode/command/sdd-next.md" "$_ext"
  ln -s "$_ext" "$S/.opencode/command/sdd-next.md"
  _extsum="$(cksum "$_ext")"
  sh "$S/harness-install.sh" --self >"$T/oc-symlink.log" 2>&1 || fail "symlink self failed (R5)"
  [ -L "$S/.opencode/command/sdd-next.md" ] || fail "a symlinked command unit was replaced (R5)"
  [ "$(cksum "$_ext")" = "$_extsum" ] || fail "a symlinked command unit's target was overwritten (R5)"
  pass "OpenCode paths are per-file units; foreign/edited/symlinked preserved and unclaimed; arming honest (R5) [self_opencode_ownership_guards]"
}

opencode_glue_source_layout() {
  grep -q '"instructions": \["AGENTS.md"\]' "$F/opencode.json" \
    || fail "opencode.json instructions are not source-layout (R7)"
  _stray="$(grep -rn '\.harness/' "$F/.opencode" "$F/opencode.json" \
    | grep -v 'source-layout copy' | grep -v 'resolved against' || true)"
  [ -z "$_stray" ] || { printf '%s\n' "$_stray" >&2; fail "a .harness/ prefix survived into OpenCode glue (R7)"; }
  pass "generated OpenCode glue carries the source layout (R7) [opencode_glue_source_layout]"
}

opencode_native_command_body() {
  for _c in sdd-next sdd-new sdd-plan sdd-drill sdd-fix sdd-pr-loop; do
    _oc="$F/.opencode/command/$_c.md"; _cc="$F/.claude/commands/$_c.md"
    # Length floor (`progress/lessons.md` 2026-09-16): a `cmp` of two empty/truncated files
    # passes vacuously, so require real bytes before trusting the equality.
    [ -s "$_oc" ] || fail "source .opencode/command/$_c.md is empty (R8)"
    [ "$(wc -c < "$_oc")" -ge 200 ] || fail "source .opencode/command/$_c.md is below the length floor (R8)"
    cmp -s "$_oc" "$_cc" \
      || fail ".opencode/command/$_c.md does not reuse the canonical .claude/commands body (R8)"
  done
  # sdd-test-concurrency has no Claude counterpart; compare it to the canonical body the
  # TARGET emission writes (raw $CMDDIR copy), stripped the way self_transform strips it.
  _tc="$T/tgt-oc"; mkdir -p "$_tc"
  sh "$F/harness-install.sh" --agents=opencode "$_tc" >/dev/null 2>&1 || fail "OpenCode target install failed (R8)"
  _oc="$F/.opencode/command/sdd-test-concurrency.md"
  [ -s "$_oc" ] || fail "source .opencode/command/sdd-test-concurrency.md is empty (R8)"
  [ "$(wc -c < "$_oc")" -ge 500 ] || fail "sdd-test-concurrency.md is below the length floor (R8)"
  sed 's|\.harness/||g' "$_tc/.opencode/command/sdd-test-concurrency.md" > "$T/tc-transformed.md"
  cmp -s "$T/tc-transformed.md" "$_oc" \
    || fail "sdd-test-concurrency.md does not reuse the canonical target body (R8)"
  pass ".opencode/command bodies reuse the canonical command body (R8) [opencode_native_command_body]"
}

shared_skill_adapter_reused() {
  _sk="$F/.agents/skills/sdd-next/SKILL.md"
  [ -f "$_sk" ] || fail "shared sdd-next unit missing after --self (R10)"
  # The shared fence rule (tests/lib/fence.awk) is loaded and CALLED, so a `#` line inside a
  # fenced block cannot be read as a heading and truncate the span (test_change_size R9d).
  _adapter="$(awk "$(cat "$F/tests/lib/fence.awk")"'BEGIN{h="## Invocation adapter"}
    fence_delim($0) { if (k) print; next }
    !fence && /^#+ /{k=(index($0,h)>0);next}
    k' "$_sk" | tr '\n' ' ')"
  [ -n "$_adapter" ] || fail "the shared unit has no Invocation adapter span (R10)"
  printf '%s\n' "$_adapter" | grep -qF '`$sdd-next`' || fail "adapter lost the Codex invocation (R10)"
  printf '%s\n' "$_adapter" | grep -qF '`/sdd-next`' || fail "adapter lost the OpenCode invocation (R10)"
  printf '%s\n' "$_adapter" | grep -qF '$ARGUMENTS' || fail "adapter lost the \$ARGUMENTS mapping (R10)"
  printf '%s\n' "$_adapter" | grep -qF '/skills' && fail "adapter still names /skills (R10)"
  _wf="$(awk "$(cat "$F/tests/lib/fence.awk")"'BEGIN{h="## Canonical workflow"}
    fence_delim($0) { if (k) print; next }
    !fence && /^#+ /{k=(index($0,h)>0);next}
    k' "$_sk")"
  [ -n "$_wf" ] || fail "the shared unit has no Canonical workflow span (R10)"
  printf '%s\n' "$_wf" | grep -qF '$sdd-' && fail "shared body carries the Codex-only \$sdd- spelling (R10)"
  # F01 claimant set: opencode alone installs the shared units...
  C10="$(fixture oc-claim)"; purge_opencode "$C10"; rm -rf "$C10/.agents/skills"
  sh "$C10/harness-install.sh" --self --agents=opencode >/dev/null 2>&1 || fail "opencode-only self failed (R10)"
  [ -f "$C10/.agents/skills/sdd-next/SKILL.md" ] || fail "opencode is not a claimant of the shared surface (R10)"
  # ...and claude alone reclaims them and the OpenCode glue (no claimant left).
  sh "$C10/harness-install.sh" --self --agents=claude >/dev/null 2>&1 || fail "claude-only self failed (R10)"
  find "$C10/.opencode" -type f 2>/dev/null | grep -q . \
    && fail "claude-only self left OpenCode command/agent glue (R10)"
  [ -e "$C10/opencode.json" ] && fail "claude-only self left opencode.json (R10)"
  pass "shared skill units retain F01's adapter and {codex,opencode} claiming (R10) [shared_skill_adapter_reused]"
}

version_minor_and_changelog() {
  # Compared by PARSED COMPONENTS, never by freezing the exact literal (a permanent-suite
  # anti-pattern). test_codex_native.sh pins the current literal it needs; this asserts the
  # bump direction and the matching, OpenCode-naming CHANGELOG entry.
  _v="$(cat "$F/VERSION")"
  _maj="${_v%%.*}"; _rest="${_v#*.}"; _min="${_rest%%.*}"
  [ "$_maj" -eq 0 ] || fail "unexpected MAJOR version $_maj (R11)"
  [ "$_min" -ge 84 ] || fail "VERSION $_v is not the MINOR bump this feature requires (R11)"
  # Shared fence rule again. The reset is level-2 EXACTLY (`/^## /`), so the entry's own
  # `### Added` subsection does not end the slice early; the call to fence_delim($0) is
  # what keeps test_change_size R9d's one-copy invariant satisfied.
  _sec="$(awk -v h="## [$_v]" "$(cat "$F/tests/lib/fence.awk")"'
    fence_delim($0) { if (k) print; next }
    !fence && /^## /{k=(index($0,h)>0);next}
    k' "$F/CHANGELOG.md")"
  [ -n "$_sec" ] || fail "CHANGELOG.md has no entry for $_v (R11)"
  printf '%s\n' "$_sec" | grep -q 'OpenCode' \
    || fail "the CHANGELOG entry for $_v does not mention OpenCode (R11)"
  pass "VERSION carries the MINOR bump and CHANGELOG the matching entry (R11) [version_minor_and_changelog]"
}

self_regenerates_opencode_glue
opencode_json_has_builder_heavy
self_opencode_pr_fixer_gate
self_opencode_capability_glue_absent
self_opencode_ownership_guards
opencode_glue_source_layout
opencode_native_command_body
shared_skill_adapter_reused
version_minor_and_changelog

echo "ALL PASSED (test_self_mode.sh)"
