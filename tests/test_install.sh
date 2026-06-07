#!/bin/sh
# test_install.sh — the harness's own product tests.
# Exercises harness-install.sh end to end: fresh install layout, idempotent
# upgrade, project-file preservation, entrypoint merge, and that the installed
# init.sh passes from the target. Zero dependencies; self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# A pre-existing entrypoint with custom prose that MUST survive.
printf '# My Project\n\nCustom instructions here.\n' > "$T/CLAUDE.md"

# ── fresh install ─────────────────────────────────────────────────────────────
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "installer exited non-zero"

[ -f "$T/.harness/AGENTS.md" ]                 || fail ".harness/AGENTS.md missing"          # R1
[ -f "$T/.harness/agents/orchestrator.md" ]    || fail "role bodies missing"                 # R1
[ -d "$T/.harness/docs" ]                      || fail "docs/ missing"                       # R1
[ -f "$T/.harness/store/tasks.schema.json" ]   || fail "schema missing"                      # R1
[ -f "$T/.harness/umbrella.manifest.example.yaml" ] || fail "umbrella manifest example not installed" # R1
[ -f "$T/.harness/tools/telemetry-report.py" ] || fail "tools/telemetry-report.py not installed (telemetry summary would fail in consumers)" # R1
[ -x "$T/.harness/init.sh" ]                   || fail ".harness/init.sh not executable"     # R1
[ -f "$T/.harness/specs/product.md" ]          || fail "product.md stub not seeded"          # R6
[ -f "$T/.harness/state/tasks.json" ]          || fail "bootstrap tasks.json missing"        # R6
pass "fresh install layout correct (R1, R6)"

# version stamp matches source VERSION                                                        # R2
[ "$(cat "$T/.harness/.harness-version")" = "$(cat "$SRC/VERSION")" ] || fail "version mismatch"
pass "version stamped (R2)"

# entrypoint: custom prose preserved AND a single harness block added                          # R3
grep -qF 'Custom instructions here.' "$T/CLAUDE.md" || fail "custom CLAUDE.md content lost"
grep -qF '<!-- harness:begin -->'     "$T/CLAUDE.md" || fail "harness block not added"
[ -f "$T/AGENTS.md" ] && [ -f "$T/GEMINI.md" ]      || fail "AGENTS.md/GEMINI.md not created"
pass "entrypoint merge preserves prose + adds block (R3)"

# Claude Code glue points at .harness/                                                         # R7
[ -f "$T/.claude/commands/sdd-next.md" ] || fail "sdd-next command missing"
[ -f "$T/.claude/commands/sdd-new.md" ]  || fail "sdd-new command missing"
grep -qF '.harness/agents/orchestrator.md' "$T/.claude/agents/orchestrator.md" \
  || fail "agent shim does not resolve against .harness/"
grep -qF '.harness/agents/inception.md' "$T/.claude/commands/sdd-new.md" \
  || fail "sdd-new does not resolve inception against .harness/"
grep -qE '(^|[^/])agents/inception\.md' "$T/.claude/commands/sdd-new.md" \
  && fail "sdd-new references a bare agents/inception.md (missing .harness/ prefix)"
# installed wrapper must mirror the source: durable template path, not the un-shipped example
grep -qF '.harness/specs/_templates/inbox-brief.md' "$T/.claude/commands/sdd-new.md" \
  || fail "sdd-new does not reference the installed inbox-brief template"
grep -qF 'E04-F01' "$T/.claude/commands/sdd-new.md" \
  && fail "sdd-new references the un-shipped E04-F01.md example brief"
[ -f "$T/.harness/specs/_templates/inbox-brief.md" ] \
  || fail "inbox-brief template not installed into profile"
# installed wrapper must carry the altitude-1 status branch
grep -qF 'pending' "$T/.claude/commands/sdd-new.md" \
  || fail "sdd-new missing altitude-1 pending branch"
grep -qE 'spec-ready|in-review' "$T/.claude/commands/sdd-new.md" \
  || fail "sdd-new missing altitude-1 consumed-status branch"
pass "Claude Code glue generated (R7)"

# OpenCode glue: same slash commands installed under .opencode/command/                        # R7
[ -f "$T/.opencode/command/sdd-next.md" ] || fail "opencode sdd-next command missing"
[ -f "$T/.opencode/command/sdd-new.md" ]  || fail "opencode sdd-new command missing"
cmp -s "$T/.claude/commands/sdd-next.md" "$T/.opencode/command/sdd-next.md" \
  || fail "opencode sdd-next differs from claude sdd-next"
cmp -s "$T/.claude/commands/sdd-new.md" "$T/.opencode/command/sdd-new.md" \
  || fail "opencode sdd-new differs from claude sdd-new"
pass "OpenCode commands generated (R7)"

# target verification commands reset to blank                                                  # R8
grep -q 'test_command: ""' "$T/.harness/harness.config.yaml" || fail "test_command not blanked"
pass "target verification commands reset (R8)"

# installed init.sh passes from the target root (self-locating + valid stub schema).           # R10
# Invoke the executable directly (its bash shebang) — NOT via `sh`, which would force
# bash-only `init.sh` through dash on Debian/Ubuntu where /bin/sh is dash.
( cd "$T" && ./.harness/init.sh >/dev/null 2>&1 ) || fail "installed init.sh failed"
pass "installed init.sh passes (R10)"

# ── upgrade: mutate project files, re-run, assert preserved + idempotent ──────
echo 'SENTINEL-PRODUCT' >> "$T/.harness/specs/product.md"
cp "$T/.harness/state/tasks.json" "$T/.harness/state/tasks.json.orig"

sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade run failed"

grep -qF 'SENTINEL-PRODUCT' "$T/.harness/specs/product.md" || fail "product.md clobbered on upgrade"  # R5
cmp -s "$T/.harness/state/tasks.json" "$T/.harness/state/tasks.json.orig" \
  || fail "tasks.json clobbered on upgrade"                                                          # R5
[ "$(grep -cF '<!-- harness:begin -->' "$T/CLAUDE.md")" = "1" ] \
  || fail "harness block duplicated on upgrade"                                                      # R4
pass "upgrade preserves project files + is idempotent (R4, R5)"

# user content placed AFTER the block must keep its position on upgrade (in-place replace)    # R4
printf 'TRAILING-USER-NOTE\n' >> "$T/CLAUDE.md"
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade-with-suffix run failed"
grep -qF 'TRAILING-USER-NOTE' "$T/CLAUDE.md" || fail "trailing user content lost on upgrade"
awk '/<!-- harness:end -->/{seen=1} /TRAILING-USER-NOTE/{print (seen?"AFTER":"BEFORE")}' "$T/CLAUDE.md" \
  | grep -q AFTER || fail "trailing user content reordered before the block on upgrade"
pass "in-place block replacement preserves surrounding order (R4)"

# verification commands set at bootstrap must survive an upgrade (not be reset)                # R11
sed -e 's|^\( *test_command:\).*|\1 "pytest -q"|' "$T/.harness/harness.config.yaml" > "$T/.harness/cfg.b" \
  && mv "$T/.harness/cfg.b" "$T/.harness/harness.config.yaml"
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade after bootstrap-config failed"
grep -q 'test_command: "pytest -q"' "$T/.harness/harness.config.yaml" \
  || fail "bootstrap test_command erased on upgrade"
pass "upgrade preserves bootstrap-configured verification commands (R11)"

# ── arg guards make no changes ────────────────────────────────────────────────
sh "$SRC/harness-install.sh"            >/dev/null 2>&1 && fail "missing-arg should exit non-zero"   # R9
sh "$SRC/harness-install.sh" "$SRC"     >/dev/null 2>&1 && fail "self-target should exit non-zero"   # R9
pass "arg guards reject bad invocations (R9)"

echo "All install tests passed."
