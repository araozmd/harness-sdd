#!/bin/sh
# test_models_cascade.sh — E27-F01 umbrella `models:` cascade.
#
# Covers R1–R7 of E27-F01: a child config key that resolves to `inherit` (or is absent)
# takes the COORDINATOR's `models:` value before the built-in default; a child's own
# explicit non-inherit value always wins; absent child pins fall back to the
# coordinator's pin; escalation verdicts are recomputed from the cascaded resolution;
# one report line per child names each role's source; single-repo installs are
# untouched; coordinator garbage warns and never blocks. R8 (VERSION/CHANGELOG) is
# covered by the repo's existing changelog conventions.
#
# Zero dependencies; self-cleaning temp dir; POSIX sh.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT

# Sandbox Codex's GLOBAL prompts dir so installer runs never touch the developer's
# real ~/.codex (same guard as test_install.sh).
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# set_cfg_line <cfg> <key> <value> — rewrite one `  <key>: …` line inside the config.
set_cfg_line() {
  sed "s/^  $2: .*/  $2: $3/" "$1" > "$1.t" && mv "$1.t" "$1"
  grep -q "^  $2: $3\$" "$1" || fail "setup: could not set models.$2 = $3 in $1"
}

# seed_cfg <dir> — pre-seed a target's .harness/harness.config.yaml from the source
# template (the installer preserves an existing config, so the cascade's very first
# run already sees these values).
seed_cfg() {
  mkdir -p "$1/.harness"
  cp "$SRC/harness.config.yaml" "$1/.harness/harness.config.yaml"
}

U="$T/umb"
mkdir -p "$U/child-a/.git" "$U/child-b/.git"
seed_cfg "$U"
COORD_CFG="$U/.harness/harness.config.yaml"
set_cfg_line "$COORD_CFG" builder standard
set_cfg_line "$COORD_CFG" builder-heavy reasoning
seed_cfg "$U/child-b"
set_cfg_line "$U/child-b/.harness/harness.config.yaml" builder cheap

OUT="$T/out1.txt"
HARNESS_AGENTS=claude sh "$SRC/harness-install.sh" --umbrella "$U" >"$OUT" 2>&1 \
  || { cat "$OUT" >&2; fail "cascade run 1 exited non-zero"; }

# ── R1: absent child keys resolve from the coordinator ────────────────────────
grep -q "^model: sonnet\$" "$U/child-a/.claude/agents/builder.md" \
  || fail "child-a builder did not cascade coordinator standard→sonnet (R1)"
grep -q "^model: opus\$" "$U/child-a/.claude/agents/builder-heavy.md" \
  || fail "child-a builder-heavy did not cascade coordinator reasoning→opus (R1)"
pass "coordinator tiers cascade into an all-inherit child (R1) [cascade_resolves]"

# ── R2: a child's own explicit non-inherit value wins ─────────────────────────
grep -q "^model: haiku\$" "$U/child-b/.claude/agents/builder.md" \
  || fail "child-b's own builder=cheap did not beat the coordinator's standard (R2)"
grep -q "^model: opus\$" "$U/child-b/.claude/agents/builder-heavy.md" \
  || fail "child-b's absent builder-heavy did not cascade (R2)"
pass "own explicit tier wins; absent keys still cascade (R2) [child_wins]"

# ── R4: escalation verdict recomputed from the cascaded resolution ────────────
[ -f "$U/child-a/.harness/.escalation-arming" ] \
  || fail "child-a has no .escalation-arming file (R4)"
grep -q "^armed\$" "$U/child-a/.harness/.escalation-arming" \
  || fail "child-a not ARMED from coordinator-only tiers (R4)"
grep -q "^claude=raise\$" "$U/child-a/.harness/.escalation-arming" \
  || fail "child-a claude verdict is not 'raise' (R4)"
pass "escalation verdict recomputed from cascaded tiers (R4) [verdict_recomputed]"

# ── R5: per-child report line names each role's tier and source ───────────────
grep -q "models cascade: builder=standard(umbrella) builder-heavy=reasoning(umbrella)" "$OUT" \
  || fail "child-a report line missing or wrong (R5)"
grep -q "models cascade: builder=cheap(own) builder-heavy=reasoning(umbrella)" "$OUT" \
  || fail "child-b report line missing or wrong (R5)"
pass "report lines name tier and source per child (R5) [report_line]"

# ── R3: absent child pin falls back to the coordinator's pin ──────────────────
awk -v line='  pin.claude.standard: "sonnet-pinned"' '
  { print }
  !done && /^models:[[:space:]]*(#.*)?$/ { print line; done=1 }
' "$COORD_CFG" > "$COORD_CFG.t" && mv "$COORD_CFG.t" "$COORD_CFG"
grep -q '^  pin\.claude\.standard: ' "$COORD_CFG" || fail "setup: pin insert failed"
HARNESS_AGENTS=claude sh "$SRC/harness-install.sh" --umbrella "$U" >"$T/out2.txt" 2>&1 \
  || { cat "$T/out2.txt" >&2; fail "cascade run 2 exited non-zero"; }
grep -q "^model: sonnet-pinned\$" "$U/child-a/.claude/agents/builder.md" \
  || fail "coordinator pin did not reach child-a's builder (R3)"
grep -q "^model: haiku\$" "$U/child-b/.claude/agents/builder.md" \
  || fail "child-b's own resolution was disturbed by the coordinator pin (R3)"
pass "coordinator pin fills an absent child pin; own resolution untouched (R3) [pin_cascade]"

# ── R7: coordinator garbage tier warns, resolves inherit, never blocks ────────
set_cfg_line "$COORD_CFG" builder turbo9
HARNESS_AGENTS=claude sh "$SRC/harness-install.sh" --umbrella "$U" >"$T/out3.txt" 2>&1 \
  || { cat "$T/out3.txt" >&2; fail "cascade with coordinator garbage tier exited non-zero (R7)"; }
grep -q "umbrella models.builder: unrecognized tier 'turbo9'" "$T/out3.txt" \
  || fail "no warning naming the coordinator as the garbage source (R7)"
grep -q "^model:" "$U/child-a/.claude/agents/builder.md" \
  && fail "child-a builder stamped a model from a garbage coordinator tier (R7)"
grep -q "^model: opus\$" "$U/child-a/.claude/agents/builder-heavy.md" \
  || fail "child-a builder-heavy lost its valid cascade beside the garbage key (R7)"
pass "coordinator garbage tier warns once and resolves inherit (R7) [coordinator_garbage]"

# ── R6: single-repo install is byte-identical in behavior — no cascade ────────
ST="$T/single"; mkdir -p "$ST"
HARNESS_AGENTS=claude sh "$SRC/harness-install.sh" "$ST" >"$T/out4.txt" 2>&1 \
  || { cat "$T/out4.txt" >&2; fail "single-repo install exited non-zero (R6)"; }
grep -q "^model:" "$ST/.claude/agents/builder.md" \
  && fail "single-repo all-inherit target stamped a model key (R6)"
grep -q "models cascade" "$T/out4.txt" \
  && fail "single-repo install printed a cascade report line (R6)"
pass "single-repo install untouched: no cascade lookup, no report line (R6) [single_repo_unchanged]"

echo "ALL PASSED (test_models_cascade.sh)"
