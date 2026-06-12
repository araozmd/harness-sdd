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
[ -f "$T/.harness/umbrella.gitignore.example" ] || fail "umbrella .gitignore example not installed"    # R1
[ -f "$T/.harness/tools/telemetry-report.py" ] || fail "tools/telemetry-report.py not installed (telemetry summary would fail in consumers)" # R1
[ -x "$T/.harness/init.sh" ]                   || fail ".harness/init.sh not executable"     # R1
[ -f "$T/.harness/specs/product.md" ]          || fail "product.md stub not seeded"          # R6
[ -f "$T/.harness/state/tasks.json" ]          || fail "bootstrap tasks.json missing"        # R6
pass "fresh install layout correct (R1, R6)"

# project-root .gitignore append-seeded with personal/runtime agent state, ignoring
# SPECIFIC .claude/ files (never the whole dir, so generated agents/commands stay tracked).
[ -f "$T/.gitignore" ]                                  || fail "project-root .gitignore not seeded"
grep -qF '.claude/settings.local.json' "$T/.gitignore"  || fail "root .gitignore missing settings.local.json"
grep -qF '.claude/scheduled_tasks.lock' "$T/.gitignore" || fail "root .gitignore missing scheduler-lock"
grep -qxF '.claude/' "$T/.gitignore"                    && fail "root .gitignore over-ignores the whole .claude/ dir"
[ -f "$T/.harness/docs/CONFIG-LAYERING.md" ]            || fail "CONFIG-LAYERING.md not installed"
pass "project-root .gitignore seeds personal/runtime ignores (config layering)"

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
[ -f "$T/.claude/commands/sdd-plan.md" ] || fail "sdd-plan command missing"
# installed /sdd-plan must act as Planner, resolved against .harness/, and carry args
grep -qF '.harness/agents/planner.md' "$T/.claude/commands/sdd-plan.md" \
  || fail "sdd-plan does not resolve planner against .harness/"
grep -qF '$ARGUMENTS' "$T/.claude/commands/sdd-plan.md" \
  || fail "sdd-plan does not carry \$ARGUMENTS"
[ -f "$T/.claude/commands/sdd-drill.md" ] || fail "sdd-drill command missing"
# installed /sdd-drill must act as Driller, resolved against .harness/, and carry args
grep -qF '.harness/agents/driller.md' "$T/.claude/commands/sdd-drill.md" \
  || fail "sdd-drill does not resolve driller against .harness/"
grep -qF '$ARGUMENTS' "$T/.claude/commands/sdd-drill.md" \
  || fail "sdd-drill does not carry \$ARGUMENTS"
[ -f "$T/.harness/agents/driller.md" ] \
  || fail "driller role not installed into profile"
# R15/R16: installed /sdd-fix must act as Fixer, resolved against .harness/, carry args
[ -f "$T/.claude/commands/sdd-fix.md" ] || fail "sdd-fix command missing"
grep -qF '.harness/agents/fixer.md' "$T/.claude/commands/sdd-fix.md" \
  || fail "sdd-fix does not resolve fixer against .harness/"
grep -qF '$ARGUMENTS' "$T/.claude/commands/sdd-fix.md" \
  || fail "sdd-fix does not carry \$ARGUMENTS"
[ -f "$T/.harness/agents/fixer.md" ] \
  || fail "fixer role not installed into profile"
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
[ -f "$T/.opencode/command/sdd-plan.md" ] || fail "opencode sdd-plan command missing"
[ -f "$T/.opencode/command/sdd-drill.md" ] || fail "opencode sdd-drill command missing"
[ -f "$T/.opencode/command/sdd-fix.md" ] || fail "opencode sdd-fix command missing"
cmp -s "$T/.claude/commands/sdd-next.md" "$T/.opencode/command/sdd-next.md" \
  || fail "opencode sdd-next differs from claude sdd-next"
cmp -s "$T/.claude/commands/sdd-new.md" "$T/.opencode/command/sdd-new.md" \
  || fail "opencode sdd-new differs from claude sdd-new"
cmp -s "$T/.claude/commands/sdd-plan.md" "$T/.opencode/command/sdd-plan.md" \
  || fail "opencode sdd-plan differs from claude sdd-plan"
cmp -s "$T/.claude/commands/sdd-drill.md" "$T/.opencode/command/sdd-drill.md" \
  || fail "opencode sdd-drill differs from claude sdd-drill"
cmp -s "$T/.claude/commands/sdd-fix.md" "$T/.opencode/command/sdd-fix.md" \
  || fail "opencode sdd-fix differs from claude sdd-fix"
pass "OpenCode commands generated (R7)"

# ── Antigravity glue (.agent/, E07-F01 R1–R12) ───────────────────────────────────────────────
# Mirrors the .claude/ + .opencode/ assertions above. A sentinel of canonical orchestrator
# prose proves the glue POINTS at the roles and never forks a body (R3/R5). The default
# install (no override) stamps ALL agents, so antigravity glue is present here.
AG_SENTINEL='You are the **Orchestrator**. You are the project manager of the harness.'

# R1: GEMINI.md managed block boots the Orchestrator against .harness/AGENTS.md.
grep -qF '<!-- harness:begin -->' "$T/GEMINI.md" || fail "GEMINI.md missing harness block (R1)"
grep -qF '.harness/AGENTS.md' "$T/GEMINI.md"     || fail "GEMINI.md block does not point at .harness/AGENTS.md (R1)"

# R2: Antigravity entrypoint rule written + points at the harness source of truth + entry role.
[ -f "$T/.agent/rules/harness.md" ]                                  || fail "antigravity rule .agent/rules/harness.md missing (R2)"
grep -qF '.harness/AGENTS.md' "$T/.agent/rules/harness.md"           || fail "antigravity rule does not point at .harness/AGENTS.md (R2)"
grep -qF '.harness/agents/orchestrator.md' "$T/.agent/rules/harness.md" || fail "antigravity rule does not point at the orchestrator role (R2)"
# R3: rule points at canonical roles, no copied role body (sentinel must be ABSENT).
grep -qF "$AG_SENTINEL" "$T/.agent/rules/harness.md" && fail "antigravity rule embeds a copied role body (R3)"

# R4/R5: one persona per role, each with a `description`, deferring to .harness/agents/<role>.md,
# mandating init.sh + progress/ hand-off, with no copied role body.
for r in orchestrator architect builder reviewer scout; do
  [ -f "$T/.agent/agents/$r.md" ]                       || fail "antigravity persona $r missing (R4)"
  grep -qE '^description:' "$T/.agent/agents/$r.md"      || fail "antigravity persona $r has no description (R4)"
  grep -qF ".harness/agents/$r.md" "$T/.agent/agents/$r.md" || fail "antigravity persona $r does not defer to .harness/agents/$r.md (R5)"
  grep -qF '.harness/init.sh' "$T/.agent/agents/$r.md"  || fail "antigravity persona $r does not mandate .harness/init.sh (R5)"
  grep -qF '.harness/progress/' "$T/.agent/agents/$r.md" || fail "antigravity persona $r does not hand off via .harness/progress/ (R5)"
  grep -qF "$AG_SENTINEL" "$T/.agent/agents/$r.md"      && fail "antigravity persona $r embeds a copied role body (R5)"
done

# R6/R7: all five workflows generated, each carrying a `description` (slash-command registration).
for w in sdd-next sdd-new sdd-plan sdd-drill sdd-fix; do
  [ -f "$T/.agent/workflows/$w.md" ]                    || fail "antigravity workflow $w missing (R6)"
  grep -qE '^description:' "$T/.agent/workflows/$w.md"   || fail "antigravity workflow $w has no description (R7)"
  grep -qF '$ARGUMENTS' "$T/.agent/workflows/$w.md"      || fail "antigravity workflow $w does not carry \$ARGUMENTS (R8)"
done

# R8: each workflow acts as its role, resolved against .harness/agents/*.md.
grep -qF '.harness/agents/orchestrator.md' "$T/.agent/workflows/sdd-next.md" || fail "sdd-next workflow does not resolve orchestrator against .harness/ (R8)"
grep -qF '.harness/agents/inception.md'    "$T/.agent/workflows/sdd-new.md"  || fail "sdd-new workflow does not resolve inception against .harness/ (R8)"
grep -qF '.harness/agents/planner.md'      "$T/.agent/workflows/sdd-plan.md" || fail "sdd-plan workflow does not resolve planner against .harness/ (R8)"
grep -qF '.harness/agents/driller.md'      "$T/.agent/workflows/sdd-drill.md" || fail "sdd-drill workflow does not resolve driller against .harness/ (R8)"
grep -qF '.harness/agents/fixer.md'        "$T/.agent/workflows/sdd-fix.md"  || fail "sdd-fix workflow does not resolve fixer against .harness/ (R8)"

# R9: each workflow body is byte-identical to the Claude command of the same name (no drift).
for w in sdd-next sdd-new sdd-plan sdd-drill sdd-fix; do
  cmp -s "$T/.claude/commands/$w.md" "$T/.agent/workflows/$w.md" || fail "antigravity workflow $w differs from claude $w (R9)"
done
pass "Antigravity glue generated (R11)"

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

# root .gitignore is append-only: a user-added entry survives upgrade, and a re-run does
# not duplicate the seeded entries (idempotent — the default/inert path is a no-op).
printf 'my-secret-dir/\n' >> "$T/.gitignore"
sh "$SRC/harness-install.sh" "$T" >/dev/null || fail "upgrade run (root .gitignore) failed"
grep -qF 'my-secret-dir/' "$T/.gitignore" || fail "user entry in root .gitignore clobbered on upgrade"
[ "$(grep -cF '.claude/settings.local.json' "$T/.gitignore")" = "1" ] \
  || fail "root .gitignore seed duplicated on upgrade (not idempotent)"
pass "project-root .gitignore is append-only + idempotent on upgrade"

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

# ── E08-F01: interactive agent-target selection (non-TTY drives via --agents) ──
# All installer invocations here run via `sh …` with non-TTY stdin, so selection is
# driven deterministically by --agents / HARNESS_AGENTS (never the interactive prompt).

# default_all_when_no_persisted (R1) + all_four_front_ends_present (R6): a no-override,
# no-TTY run resolves to ALL four agents (back-compat: this is the historical behavior,
# and the proxy for "fresh install pre-checks ALL when .harness/.agents is absent").
TA="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" "$TA" >/dev/null || fail "no-override install exited non-zero"
[ -f "$TA/CLAUDE.md" ]       || fail "R6: no-override run did not stamp claude (CLAUDE.md)"
[ -f "$TA/GEMINI.md" ]       || fail "R6: no-override run did not stamp gemini (GEMINI.md)"
[ -f "$TA/opencode.json" ]   || fail "R6: no-override run did not stamp opencode (opencode.json)"
[ -d "$TA/.claude/commands" ] || fail "R6: no-override run did not stamp claude glue"
[ -d "$TA/.opencode/command" ] || fail "R6: no-override run did not stamp opencode glue"
[ -f "$TA/.harness/.agents" ] || fail "R8: .harness/.agents not written on no-override run"
for _k in claude gemini opencode antigravity; do
  grep -qx "$_k" "$TA/.harness/.agents" || fail "R1/R6: .harness/.agents missing '$_k' on ALL default"
done
rm -rf "$TA"
pass "no-TTY no-override run stamps ALL four agents + persists ALL (R1, R6)"

# agents_claude_only_stamps_claude (R2, R3, R4): --agents=claude stamps only Claude.
TB="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude "$TB" >/dev/null || fail "--agents=claude exited non-zero"
[ -f "$TB/CLAUDE.md" ]        || fail "R2/R3: --agents=claude did not write CLAUDE.md"
[ -d "$TB/.claude/agents" ]   || fail "R2/R3: --agents=claude did not write .claude/agents"
[ -d "$TB/.claude/commands" ] || fail "R2/R3: --agents=claude did not write .claude/commands"
[ -f "$TB/AGENTS.md" ]        || fail "R2: AGENTS.md (shared entrypoint) must always be written"
[ -f "$TB/GEMINI.md" ]        && fail "R4: --agents=claude must not write GEMINI.md"
[ -f "$TB/opencode.json" ]    && fail "R4: --agents=claude must not write opencode.json"
[ -d "$TB/.opencode" ]        && fail "R4: --agents=claude must not write .opencode/"
[ -d "$TB/.agent" ]           && fail "R4: --agents=claude must not write .agent/"
rm -rf "$TB"
pass "--agents=claude stamps only Claude, no other front-ends (R2, R3, R4)"

# agents_multi_stamps_each (R3): --agents=claude,opencode stamps both.
TC="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude,opencode "$TC" >/dev/null || fail "--agents=claude,opencode exited non-zero"
[ -f "$TC/CLAUDE.md" ]      || fail "R3: claude not stamped in multi-select"
[ -f "$TC/opencode.json" ] || fail "R3: opencode not stamped in multi-select"
[ -d "$TC/.opencode/command" ] || fail "R3: opencode commands not stamped in multi-select"
[ -f "$TC/GEMINI.md" ]     && fail "R4: gemini must be skipped in claude,opencode select"
rm -rf "$TC"
pass "--agents=claude,opencode stamps each selected agent (R3)"

# env_override_selects (R5): HARNESS_AGENTS resolves the set, and --agents wins too.
TD="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
HARNESS_AGENTS=gemini sh "$SRC/harness-install.sh" "$TD" >/dev/null || fail "HARNESS_AGENTS=gemini exited non-zero"
[ -f "$TD/GEMINI.md" ]   || fail "R5: HARNESS_AGENTS=gemini did not stamp gemini"
[ -f "$TD/CLAUDE.md" ]   && fail "R5: HARNESS_AGENTS=gemini must not stamp claude"
[ -f "$TD/opencode.json" ] && fail "R5: HARNESS_AGENTS=gemini must not stamp opencode"
rm -rf "$TD"
# --agents wins over an HARNESS_AGENTS env value at the same time
TD2="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
HARNESS_AGENTS=gemini sh "$SRC/harness-install.sh" --agents=claude "$TD2" >/dev/null || fail "override precedence run failed"
[ -f "$TD2/CLAUDE.md" ]  || fail "R5: --agents=claude must win over HARNESS_AGENTS=gemini"
[ -f "$TD2/GEMINI.md" ]  && fail "R5: --agents must override HARNESS_AGENTS (gemini should be skipped)"
rm -rf "$TD2"
pass "explicit --agents / HARNESS_AGENTS override resolves the set, --agents wins (R5)"

# registry_keys (R10): every registry key is individually selectable.
for _k in claude gemini opencode antigravity; do
  TK="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
  sh "$SRC/harness-install.sh" --agents="$_k" "$TK" >/dev/null || fail "R10: --agents=$_k exited non-zero"
  grep -qx "$_k" "$TK/.harness/.agents" || fail "R10: '$_k' not selectable/persisted"
  rm -rf "$TK"
done
pass "every registry key is individually selectable (R10)"

# antigravity_only_writes_gemini_entrypoint (E07-F01 R1, Codex r1 P2 #3404185446):
# GEMINI.md is Antigravity's in-repo bootstrap entrypoint, so an antigravity-only
# install (no gemini) MUST still write GEMINI.md with the harness managed block.
TAG="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=antigravity "$TAG" >/dev/null || fail "--agents=antigravity exited non-zero"
[ -f "$TAG/GEMINI.md" ]                              || fail "R1: --agents=antigravity must write GEMINI.md entrypoint (Codex r1 P2)"
grep -qF '<!-- harness:begin -->' "$TAG/GEMINI.md"   || fail "R1: antigravity-only GEMINI.md missing harness managed block (Codex r1 P2)"
grep -qF '.harness/AGENTS.md' "$TAG/GEMINI.md"       || fail "R1: antigravity-only GEMINI.md does not point at .harness/AGENTS.md"
[ -f "$TAG/.agent/rules/harness.md" ]                || fail "R1: antigravity-only install missing .agent/ glue"
[ -f "$TAG/CLAUDE.md" ]    && fail "R4: antigravity-only must not write CLAUDE.md"
[ -f "$TAG/opencode.json" ] && fail "R4: antigravity-only must not write opencode.json"
rm -rf "$TAG"
pass "--agents=antigravity writes GEMINI.md entrypoint (R1, Codex r1 P2)"

# unknown_agent_key_rejected (R7): an unknown override exits non-zero, names it, no changes.
TE="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
_err="$(sh "$SRC/harness-install.sh" --agents=claude,bogus "$TE" 2>&1 >/dev/null)" && fail "R7: unknown key must exit non-zero"
printf '%s' "$_err" | grep -qF 'bogus' || fail "R7: error must name the unknown token 'bogus'"
[ -d "$TE/.harness" ] && fail "R7: unknown-key run must make no changes (no .harness/ written)"
[ -f "$TE/CLAUDE.md" ] && fail "R7: unknown-key run must not stamp any front-end"
rm -rf "$TE"
pass "unknown override key exits non-zero, names it, makes no changes (R7)"

# persists_selection (R8): --agents=claude,opencode persists exactly those, sorted, 1/line.
TF="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=opencode,claude "$TF" >/dev/null || fail "persist run failed"
[ -f "$TF/.harness/.agents" ] || fail "R8: .harness/.agents not created"
[ "$(cat "$TF/.harness/.agents")" = "$(printf 'claude\nopencode')" ] \
  || fail "R8: .harness/.agents not exactly {claude,opencode} sorted one-per-line (got: $(cat "$TF/.harness/.agents" | tr '\n' ',' ))"
# .harness/agents/ (the role-bodies DIR) must coexist with the .harness/.agents state FILE
[ -d "$TF/.harness/agents" ] || fail "R8: role-bodies .harness/agents/ dir clobbered by state file"
[ -f "$TF/.harness/agents/orchestrator.md" ] || fail "R8: role bodies missing alongside state file"
rm -rf "$TF"
pass ".harness/.agents persists the selection sorted, coexists with the roles dir (R8)"

# reconcile_add + reconcile_remove + reprompt_baseline_is_persisted +
# reconcile_without_version_bump (R9, R11, R12, R13): a re-run at the SAME version that
# both adds and removes an agent, using the persisted set as the baseline.
TG="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude,gemini "$TG" >/dev/null || fail "reconcile install1 failed"
[ -f "$TG/GEMINI.md" ] || fail "reconcile setup: gemini not stamped in install1"
[ -f "$TG/opencode.json" ] && fail "reconcile setup: opencode should be absent after install1"
# Re-run at the SAME VERSION (R11): drop gemini, add opencode.
_warn="$(sh "$SRC/harness-install.sh" --agents=claude,opencode "$TG" 2>&1 >/dev/null)" \
  || fail "reconcile install2 exited non-zero"
# add applied (R12)
[ -f "$TG/opencode.json" ]     || fail "R12: re-run did not add opencode glue (opencode.json)"
[ -d "$TG/.opencode/command" ] || fail "R12: re-run did not add opencode commands"
# remove applied (R13): gemini glue gone, warning printed
[ -f "$TG/GEMINI.md" ] && fail "R13: deselected gemini glue (GEMINI.md) not removed"
printf '%s' "$_warn" | grep -qiF 'gemini' || fail "R13: removal of gemini was not warned about"
# claude kept, AGENTS.md survives, .harness/ body intact (R13 never-touch invariants)
[ -d "$TG/.claude" ]          || fail "R13: still-selected claude glue must survive"
[ -f "$TG/AGENTS.md" ]        || fail "R13: shared AGENTS.md entrypoint must never be removed"
[ -f "$TG/.harness/AGENTS.md" ] || fail "R13: .harness/ body must never be touched by removal"
# .harness/.agents reflects the new baseline (R9): claude,opencode (not the old set, not ALL)
[ "$(cat "$TG/.harness/.agents")" = "$(printf 'claude\nopencode')" ] \
  || fail "R9: persisted baseline not updated to {claude,opencode} after reconcile"
rm -rf "$TG"
pass "re-run adds + removes agents at same VERSION, persisted baseline updated (R9, R11, R12, R13)"

# legacy_upgrade_baseline_removes_deselected (R12/R13, Codex P2 #3400941300): an
# existing install with NO persisted .harness/.agents (a pre-E08 install that
# stamped ALL front-ends) must be treated as the all-agents baseline, so the first
# selective upgrade actually removes the now-deselected glue rather than leaving it.
TL="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" "$TL" >/dev/null || fail "legacy setup install failed"   # no-override ⇒ ALL
[ -f "$TL/GEMINI.md" ]   || fail "legacy setup: gemini not stamped by ALL default"
[ -f "$TL/opencode.json" ] || fail "legacy setup: opencode not stamped by ALL default"
rm -f "$TL/.harness/.agents"   # simulate a pre-E08 install: stamped all, persisted none
[ -f "$TL/.harness/.harness-version" ] || fail "legacy setup: not detected as an upgrade"
_warn="$(sh "$SRC/harness-install.sh" --agents=claude "$TL" 2>&1 >/dev/null)" \
  || fail "legacy upgrade run exited non-zero"
[ -f "$TL/GEMINI.md" ]     && fail "Codex P2: legacy upgrade must remove deselected GEMINI.md"
[ -f "$TL/opencode.json" ] && fail "Codex P2: legacy upgrade must remove deselected opencode.json"
[ -d "$TL/.claude" ]       || fail "Codex P2: still-selected claude glue must survive legacy upgrade"
[ "$(cat "$TL/.harness/.agents")" = "claude" ] \
  || fail "Codex P2: legacy upgrade must persist the new {claude} baseline"
rm -rf "$TL"
pass "legacy upgrade (no persisted .agents) treats prior set as ALL, removes deselected glue (Codex P2)"

# deselect_preserves_user_authored_files (R13, Codex r2 P1 #3400965003/#3400965008):
# deselecting an agent must delete ONLY harness-generated files, never wipe whole
# .claude/.opencode dirs that also hold the user's own agents/commands.
TM="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude,opencode "$TM" >/dev/null || fail "scoped-remove install1 failed"
[ -f "$TM/.claude/agents/orchestrator.md" ] || fail "scoped-remove setup: claude shims not stamped"
[ -f "$TM/.opencode/command/sdd-next.md" ]  || fail "scoped-remove setup: opencode cmds not stamped"
# user-authored artifacts the harness does NOT own, placed in the same dirs:
printf 'mine\n' > "$TM/.claude/agents/my-custom.md"
printf 'mine\n' > "$TM/.claude/commands/my-cmd.md"
printf 'mine\n' > "$TM/.opencode/command/my-oc.md"
# re-run dropping BOTH claude and opencode:
sh "$SRC/harness-install.sh" --agents=gemini "$TM" >/dev/null 2>&1 || fail "scoped-remove rerun failed"
# harness-owned glue removed:
[ -f "$TM/.claude/agents/orchestrator.md" ] && fail "P1: harness claude shim not removed on deselect"
[ -f "$TM/.claude/commands/sdd-next.md" ]   && fail "P1: harness claude command not removed on deselect"
[ -f "$TM/.opencode/command/sdd-next.md" ]  && fail "P1: harness opencode command not removed on deselect"
# user-authored files PRESERVED (the whole point):
[ -f "$TM/.claude/agents/my-custom.md" ]   || fail "P1: user-authored .claude/agents/my-custom.md was wrongly deleted"
[ -f "$TM/.claude/commands/my-cmd.md" ]     || fail "P1: user-authored .claude/commands/my-cmd.md was wrongly deleted"
[ -f "$TM/.opencode/command/my-oc.md" ]     || fail "P1: user-authored .opencode/command/my-oc.md was wrongly deleted"
# dirs survive because they still hold user files:
[ -d "$TM/.claude/agents" ]   || fail "P1: .claude/agents removed despite user files present"
[ -d "$TM/.opencode/command" ] || fail "P1: .opencode/command removed despite user files present"
rm -rf "$TM"
pass "deselect removes only harness-owned files, preserves user-authored agents/commands (Codex r2 P1)"

# deselect_prunes_empty_dirs (R13): when NO user files remain, the now-empty harness
# dirs are pruned (no stale empty .claude/.opencode left behind).
TN="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=claude,opencode "$TN" >/dev/null || fail "prune setup install failed"
sh "$SRC/harness-install.sh" --agents=gemini "$TN" >/dev/null 2>&1 || fail "prune rerun failed"
[ -d "$TN/.claude" ]   && fail "R13: empty .claude/ not pruned after full claude deselect"
[ -d "$TN/.opencode" ] && fail "R13: empty .opencode/ not pruned after full opencode deselect"
rm -rf "$TN"
pass "deselect prunes harness dirs only when left empty (R13)"

# deselect_antigravity_preserves_user_agent_dir (R13, Codex r3 P1 #3400997183): with the
# E07-F01 .agent/ glue in place, deselecting antigravity removes ONLY the harness-owned
# files (scoped remove_owned) and must NEVER delete a user-authored file or `rm -rf` the
# user's .agent/ dir — the dir survives because it still holds the user's own content.
TP="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" "$TP" >/dev/null || fail "antigravity-noop setup install failed"  # ALL ⇒ persists antigravity
grep -qx antigravity "$TP/.harness/.agents" || fail "setup: antigravity not in persisted baseline"
mkdir -p "$TP/.agent"; printf 'mine\n' > "$TP/.agent/user-config.md"   # user-authored, not harness-owned
sh "$SRC/harness-install.sh" --agents=claude "$TP" >/dev/null 2>&1 || fail "antigravity deselect rerun failed"
[ -d "$TP/.agent" ]                  || fail "Codex r3 P1: user-authored .agent/ dir was wrongly deleted on antigravity deselect"
[ -f "$TP/.agent/user-config.md" ]   || fail "Codex r3 P1: user-authored .agent/user-config.md was wrongly deleted"
rm -rf "$TP"
pass "antigravity deselect is a no-op, never deletes a user-authored .agent/ (Codex r3 P1)"

# opencode_json_removal_is_byte_exact (R13, Codex r4 P2 #3401025100): on opencode
# deselect, a PRISTINE generated opencode.json is removed, but one the user edited
# (e.g. added a "model" key to the generated file) is preserved.
TQ="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=opencode "$TQ" >/dev/null || fail "oc-exact setup1 failed"
[ -f "$TQ/opencode.json" ] || fail "oc-exact setup: generated opencode.json missing"
sh "$SRC/harness-install.sh" --agents=claude "$TQ" >/dev/null 2>&1 || fail "oc-exact rerun1 failed"
[ -f "$TQ/opencode.json" ] && fail "Codex r4 P2: pristine generated opencode.json must be removed on deselect"
# now the edited-file case: regenerate, then a user adds project settings to it
sh "$SRC/harness-install.sh" --agents=opencode "$TQ" >/dev/null || fail "oc-exact setup2 failed"
# insert a user "model" line after the schema line (started from the generated file)
awk 'NR==2{print "  \"model\": \"anthropic/claude\","} {print}' "$TQ/opencode.json" > "$TQ/opencode.json.tmp" \
  && mv "$TQ/opencode.json.tmp" "$TQ/opencode.json"
grep -q '"model"' "$TQ/opencode.json" || fail "oc-exact setup: user edit not applied"
sh "$SRC/harness-install.sh" --agents=claude "$TQ" >/dev/null 2>&1 || fail "oc-exact rerun2 failed"
[ -f "$TQ/opencode.json" ] || fail "Codex r4 P2: user-edited opencode.json was wrongly deleted on deselect"
grep -q '"model"' "$TQ/opencode.json" || fail "Codex r4 P2: user-edited opencode.json content not preserved"
rm -rf "$TQ"
pass "opencode.json deselect deletes only a byte-pristine generated file, keeps edits (Codex r4 P2)"

# gemini_deselect_keeps_gemini_when_antigravity_remains (E07-F01 R1, Codex r1 P2
# #3404185446): GEMINI.md is SHARED by gemini and antigravity. Deselecting gemini
# while antigravity stays selected must KEEP GEMINI.md (antigravity still owns it),
# and conversely deselecting antigravity-only orphan removal happens only when both
# owners are gone.
TR="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$SRC/harness-install.sh" --agents=gemini,antigravity "$TR" >/dev/null || fail "shared-gemini setup install failed"
[ -f "$TR/GEMINI.md" ] || fail "shared-gemini setup: GEMINI.md not stamped for gemini,antigravity"
# Drop gemini, keep antigravity: GEMINI.md must survive (antigravity owns it).
sh "$SRC/harness-install.sh" --agents=antigravity "$TR" >/dev/null 2>&1 || fail "shared-gemini deselect-gemini rerun failed"
[ -f "$TR/GEMINI.md" ]                || fail "R1: deselecting gemini while antigravity remains must KEEP GEMINI.md (Codex r1 P2)"
grep -qF '<!-- harness:begin -->' "$TR/GEMINI.md" || fail "R1: GEMINI.md harness block stripped despite antigravity still selected"
# Now drop antigravity too (last owner gone): GEMINI.md must finally be removed.
sh "$SRC/harness-install.sh" --agents=claude "$TR" >/dev/null 2>&1 || fail "shared-gemini deselect-antigravity rerun failed"
[ -f "$TR/GEMINI.md" ] && fail "R13: GEMINI.md must be removed once NEITHER gemini nor antigravity is selected"
rm -rf "$TR"
pass "GEMINI.md shared by gemini+antigravity: kept until both deselected (R1, R13, Codex r1 P2)"

echo "All install tests passed."
