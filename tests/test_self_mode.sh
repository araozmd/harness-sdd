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
  for _e in "$SRC"/* "$SRC"/.claude "$SRC"/.escalation-arming; do
    [ -e "$_e" ] || continue
    case "$(basename "$_e")" in .git|node_modules) continue ;; esac
    cp -R "$_e" "$_fx/" 2>/dev/null || true
  done
  printf '%s\n' "$_fx"
}

F="$(fixture main)"

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
grep -q "^armed\$" "$F/.escalation-arming" || fail "sonnet→opus did not arm (R4)"
grep -q "^claude=raise\$" "$F/.escalation-arming" || fail "claude verdict is not raise (R4)"
pass "arming verdict computed from harvested models (R4) [self_arming_real]"

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
cp -R "$F/.claude" "$T/snap" && cp "$F/.escalation-arming" "$T/snap-arm"
_ver1="$(cat "$F/VERSION")"; _cfg1="$(cat "$F/harness.config.yaml")"
: > "$F/sentinel-outside-glue.txt"
sh "$F/harness-install.sh" --self >/dev/null 2>&1 || fail "second --self run exited non-zero (R6)"
diff -rq "$T/snap" "$F/.claude" >/dev/null || fail "second --self run changed glue bytes (R6)"
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

echo "ALL PASSED (test_self_mode.sh)"
