#!/bin/sh
# test_pr_loop.sh — E18-F01: the /sdd-pr-loop command, the vendored Codex watcher, the
# pr-fixer role, and the pr_loop.enabled gate.
#
# Suite conventions (non-negotiable):
#   - EVERY installer-invoking run goes through install_at(), which sandboxes CODEX_HOME
#     under this suite's own temp dir. The codex glue is machine-GLOBAL and shared across
#     targets, so an unsandboxed run could reclaim another target's prompts.
#   - No test freezes an exact VERSION string and no test diffs a file against `main`.
#     Both anti-patterns have been reverted three times in this repo; the durable
#     invariant (VERSION parses, CHANGELOG carries a heading for it) is asserted instead.
#   - Assertions that EXECUTE jq print `skip - <name> (jq not installed)` and continue.
#     Everything else runs unconditionally, so a CI box without jq still exercises the
#     whole installer surface.
# Zero dependencies beyond POSIX sh; self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SELF="$SRC/tests/test_pr_loop.sh"
W="$SRC/tools/wait-for-codex.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-prl)"
trap 'rm -rf "$T"' EXIT

# Suite-wide CODEX_HOME sandbox (belt) — install_at() also sets a per-target one (braces).
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
skip() { echo "skip - $1"; }
have_jq() { command -v jq >/dev/null 2>&1; }

# cfg_pr_loop_enabled <config-file> — print pr_loop.enabled, SECTION-SCOPED and
# comment-stripped: the test-side mirror of the installer's _cfg_pr_loop_value. An
# unscoped `grep '^  enabled:'` is wrong here — `telemetry:` carries an `enabled:` key at
# the same indent, so it would answer for the wrong section. Prints nothing when unset.
cfg_pr_loop_enabled() {
  awk '
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; next }
    p && /^[^[:space:]#]/ { p=0 }
    p && /^[[:space:]]+enabled:/ {
      sub(/^[[:space:]]+enabled:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, "")
      print; exit
    }
  ' "$1"
}

# install_at <target> [installer-args...] — the ONLY way this suite runs the installer.
# Always sandboxes CODEX_HOME to <target>/ch, so no run can touch a developer's ~/.codex.
install_at() {
  _ia_t="$1"; shift
  mkdir -p "$_ia_t"
  CODEX_HOME="$_ia_t/ch" sh "$SRC/harness-install.sh" "$@" "$_ia_t" >"$_ia_t/.out" 2>"$_ia_t/.err" \
    || { cat "$_ia_t/.err" >&2; fail "installer exited non-zero for $_ia_t"; }
}

# install_on <target> [installer-args...] — install with the pr_loop gate armed via the
# ENV override. The gate is OPT-IN (a fresh install seeds `enabled: false`), so every
# "the loop is installed" assertion has to turn it on explicitly. Tests that exercise the
# CONFIG axis use set_gate instead.
install_on() {
  HARNESS_PR_LOOP_ENABLED=true; export HARNESS_PR_LOOP_ENABLED
  install_at "$@"
  unset HARNESS_PR_LOOP_ENABLED
}

# set_gate <target> <true|false> — rewrite pr_loop.enabled in the target's config,
# section-scoped. When the target has not been installed yet, the source config is used as
# the starting point, so a test can pre-seed a preserved config whose gate is already on.
set_gate() {
  mkdir -p "$1/.harness"
  if [ -f "$1/.harness/harness.config.yaml" ]; then _sg_in="$1/.harness/harness.config.yaml"
  else _sg_in="$SRC/harness.config.yaml"; fi
  awk -v v="$2" '
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; print; next }
    p && /^[^[:space:]#]/ { p=0 }
    p && /^[[:space:]]+enabled:/ { print "  enabled: " v "  # test-set"; next }
    { print }
  ' "$_sg_in" > "$1/.cfg.tmp"
  mv "$1/.cfg.tmp" "$1/.harness/harness.config.yaml"
}

# ── shared fixtures ───────────────────────────────────────────────────────────
# BASE is the GATE-ON reference target: every body/artifact assertion reads from it. The
# gate is armed by env, so BASE's own config is still the untouched SEEDED one — which is
# what test_pr_loop_block_seeded (R15) asserts against.
BASE="$T/base"
install_on "$BASE"
BODY="$BASE/.claude/commands/sdd-pr-loop.md"
[ -f "$BODY" ] || fail "setup: gate-on install did not generate the /sdd-pr-loop body"

# ...and the DEFAULT install (no env, no config edit) must stamp nothing at all.
DEF="$T/default"
install_at "$DEF"
[ -e "$DEF/.claude/commands/sdd-pr-loop.md" ] \
  && fail "setup: a default install stamped /sdd-pr-loop — the gate must be opt-in"

# ══ Command generation, gating and removal (R1–R8) ════════════════════════════

test_command_mirrored_to_all_frontends() {           # R2
  _m="$T/mirror"
  install_on "$_m"
  for _f in "$_m/.claude/commands/sdd-pr-loop.md" \
            "$_m/.opencode/command/sdd-pr-loop.md" \
            "$_m/.agents/workflows/sdd-pr-loop.md" \
            "$_m/ch/prompts/sdd-pr-loop.md"; do
    [ -f "$_f" ] || fail "R2: /sdd-pr-loop not mirrored to $_f"
    cmp -s "$_f" "$_m/.claude/commands/sdd-pr-loop.md" \
      || fail "R2: $_f is not byte-identical to the Claude copy"
  done
  pass "R2 gate on: /sdd-pr-loop mirrored byte-identically into all four command surfaces"
}

test_gate_off_stamps_nothing() {                      # R3
  # The gate is OPT-IN, so this is the DEFAULT path: a plain fresh install, no config edit
  # and no env override, must stamp no pr_loop glue anywhere. $DEF is exactly that install.
  _o="$DEF"
  [ "$(cfg_pr_loop_enabled "$_o/.harness/harness.config.yaml")" = "false" ] \
    || fail "R3: a fresh install did not seed pr_loop.enabled: false"
  for _f in "$_o/.claude/commands/sdd-pr-loop.md" \
            "$_o/.opencode/command/sdd-pr-loop.md" \
            "$_o/.agents/workflows/sdd-pr-loop.md" \
            "$_o/ch/prompts/sdd-pr-loop.md" \
            "$_o/.claude/agents/pr-fixer.md" \
            "$_o/.opencode/agent/pr-fixer.md" \
            "$_o/.agents/agents/pr-fixer.md"; do
    [ -e "$_f" ] && fail "R3: gate off but $_f was stamped"
  done
  [ -d "$_o/.opencode/agent" ] && fail "R3: gate off must not create .opencode/agent/"
  # the ungated commands are unaffected, and the run exited 0 (install_at asserts that)
  [ -f "$_o/.claude/commands/sdd-next.md" ] || fail "R3: gate off wrongly suppressed /sdd-next"
  pass "R3 default (opt-in gate off): no /sdd-pr-loop command and no pr-fixer artifact, exit 0"
}

test_deselect_removes_pr_loop_glue() {                # R4
  _d="$T/desel"
  install_on "$_d"
  [ -f "$_d/.claude/commands/sdd-pr-loop.md" ] || fail "R4 setup: glue not stamped"
  [ -f "$_d/ch/prompts/sdd-pr-loop.md" ]       || fail "R4 setup: global prompt not stamped"
  # the gate stays ON across the re-run: this proves DESELECTION reclaims, not the gate
  install_on "$_d" --agents=gemini
  for _f in "$_d/.claude/commands/sdd-pr-loop.md" "$_d/.claude/agents/pr-fixer.md" \
            "$_d/.opencode/command/sdd-pr-loop.md" "$_d/.opencode/agent/pr-fixer.md" \
            "$_d/.agents/workflows/sdd-pr-loop.md" "$_d/.agents/agents/pr-fixer.md" \
            "$_d/ch/prompts/sdd-pr-loop.md"; do
    [ -e "$_f" ] && fail "R4: deselected front-end kept $_f"
  done
  pass "R4 deselect: every front-end's /sdd-pr-loop + pr-fixer reclaimed"
}

test_gate_flip_off_reclaims() {                       # R5
  _f="$T/flip"
  set_gate "$_f" true            # pre-seed a preserved config that opts IN
  install_at "$_f"
  [ -f "$_f/.claude/commands/sdd-pr-loop.md" ] || fail "R5 setup: glue not stamped"
  set_gate "$_f" false
  install_at "$_f"
  for _p in "$_f/.claude/commands/sdd-pr-loop.md" "$_f/.claude/agents/pr-fixer.md" \
            "$_f/.opencode/command/sdd-pr-loop.md" "$_f/.opencode/agent/pr-fixer.md" \
            "$_f/.agents/workflows/sdd-pr-loop.md" "$_f/.agents/agents/pr-fixer.md" \
            "$_f/ch/prompts/sdd-pr-loop.md"; do
    [ -e "$_p" ] && fail "R5: gate flipped off but $_p survived while the front-end is still selected"
  done
  # the still-selected front-ends keep everything else
  [ -f "$_f/.claude/commands/sdd-next.md" ]    || fail "R5: flip-off wrongly removed /sdd-next"
  [ -f "$_f/.claude/agents/orchestrator.md" ]  || fail "R5: flip-off wrongly removed a role shim"
  [ -f "$_f/ch/prompts/sdd-next.md" ]          || fail "R5: flip-off wrongly removed a global prompt"
  grep -qF 'pr_loop.enabled is not true' "$_f/.err" || fail "R5: gate-off reclamation was not announced"
  pass "R5 gate true->false while selected reclaims the glue from every front-end"
}

test_edited_copy_left_in_place_and_warns() {          # R6
  _e="$T/edited"
  set_gate "$_e" true
  install_at "$_e"
  printf '\n# my own note\n' >> "$_e/ch/prompts/sdd-pr-loop.md"
  printf '\n# my own note\n' >> "$_e/.agents/agents/pr-fixer.md"
  set_gate "$_e" false
  install_at "$_e"
  [ -f "$_e/ch/prompts/sdd-pr-loop.md" ] \
    || fail "R6: an EDITED global Codex prompt must survive reclamation"
  grep -qF 'my own note' "$_e/ch/prompts/sdd-pr-loop.md" \
    || fail "R6: the user's edit was lost"
  [ -f "$_e/.agents/agents/pr-fixer.md" ] \
    || fail "R6: an EDITED .agents/ persona must survive reclamation"
  grep -qF 'sdd-pr-loop.md' "$_e/.err" || fail "R6: surviving edited prompt was not named in a warning"
  grep -qF 'pr-fixer.md' "$_e/.err"    || fail "R6: surviving edited persona was not named in a warning"
  pass "R6 edited copies in user-owned namespaces survive, each named in a warning"
}

test_reclaim_preserves_user_files_and_prunes() {      # R7
  _u="$T/userfiles"
  set_gate "$_u" true
  install_at "$_u"
  [ -f "$_u/.opencode/agent/pr-fixer.md" ] || fail "R7 setup: opencode pr-fixer not stamped"
  printf 'mine\n' > "$_u/.opencode/agent/my-agent.md"
  set_gate "$_u" false
  install_at "$_u"
  [ -e "$_u/.opencode/agent/pr-fixer.md" ] && fail "R7: harness-owned pr-fixer not reclaimed"
  [ -f "$_u/.opencode/agent/my-agent.md" ] || fail "R7: user-authored .opencode/agent file was deleted"
  [ -d "$_u/.opencode/agent" ]             || fail "R7: dir pruned despite holding a user file"
  # and with nothing left, the dir IS pruned
  _u2="$T/prune"
  set_gate "$_u2" true
  install_at "$_u2"
  set_gate "$_u2" false
  install_at "$_u2"
  [ -d "$_u2/.opencode/agent" ] && fail "R7: empty .opencode/agent/ not pruned"
  [ -d "$_u2/.opencode/command" ] || fail "R7: .opencode/command wrongly pruned (still holds /sdd-*)"
  pass "R7 reclamation preserves user files and prunes only dirs left empty"
}

test_gate_off_then_on_restores() {                    # R8
  _r="$T/roundtrip"
  set_gate "$_r" true
  install_at "$_r"
  cp "$_r/.claude/commands/sdd-pr-loop.md" "$T/.rt-cmd"
  cp "$_r/.claude/agents/pr-fixer.md"      "$T/.rt-fixer"
  cp "$_r/.opencode/agent/pr-fixer.md"     "$T/.rt-ocfixer"
  cp "$_r/.agents/agents/pr-fixer.md"      "$T/.rt-agfixer"
  set_gate "$_r" false
  install_at "$_r"
  set_gate "$_r" true
  install_at "$_r"
  cmp -s "$_r/.claude/commands/sdd-pr-loop.md" "$T/.rt-cmd"    || fail "R8: command not byte-identical after off->on"
  cmp -s "$_r/.claude/agents/pr-fixer.md"      "$T/.rt-fixer"  || fail "R8: claude pr-fixer not byte-identical after off->on"
  cmp -s "$_r/.opencode/agent/pr-fixer.md"     "$T/.rt-ocfixer" || fail "R8: opencode pr-fixer not byte-identical after off->on"
  cmp -s "$_r/.agents/agents/pr-fixer.md"      "$T/.rt-agfixer" || fail "R8: antigravity pr-fixer not byte-identical after off->on"
  cmp -s "$_r/ch/prompts/sdd-pr-loop.md"       "$T/.rt-cmd"    || fail "R8: global prompt not byte-identical after off->on"
  pass "R8 gate off->on round-trip restores byte-identical glue"
}

test_gate_off_still_reclaims_global_codex_prompt() {  # R1
  # This is the R1 probe: the reclamation below compares the on-disk global prompt against
  # the freshly generated CMDDIR body. It can only pass if the installer generates the
  # /sdd-pr-loop body into CMDDIR on EVERY run, gate on or off. Gating GENERATION would
  # delete the reference and make an already-stamped prompt permanently unremovable.
  _g="$T/r1"
  set_gate "$_g" true
  install_at "$_g" --agents=codex
  [ -f "$_g/ch/prompts/sdd-pr-loop.md" ] || fail "R1 setup: global prompt not stamped"
  set_gate "$_g" false
  install_at "$_g" --agents=codex
  [ -e "$_g/ch/prompts/sdd-pr-loop.md" ] \
    && fail "R1: pristine global prompt not reclaimed — the CMDDIR body must be generated on EVERY run"
  [ -f "$_g/ch/prompts/sdd-next.md" ] || fail "R1: ungated global prompts must be untouched"
  pass "R1 CMDDIR body is generated on every run (pristine reference survives a gate flip)"
}

# ══ The GLOBAL prompt is CROSS-TARGET (Codex r4 P1 #3662785235) ═══════════════
# `${CODEX_HOME:-$HOME/.codex}/prompts/` is machine-global: one dir, every repo on the
# box. `pr_loop.enabled` is per-target AND opt-in, so without cross-target ownership the
# DEFAULT install of any second project deletes the prompt an enabled project depends on.
# These tests share ONE CODEX_HOME between two targets on purpose — that is the real
# topology, and it is still a sandbox under this suite's temp dir.

# install_shared <target> <shared-codex-home> <true|false> — install <target> against a
# CODEX_HOME deliberately shared with the other targets of the same test.
install_shared() {
  _is_t="$1"; _is_ch="$2"; _is_g="$3"
  mkdir -p "$_is_t" "$_is_ch"
  HARNESS_PR_LOOP_ENABLED="$_is_g" CODEX_HOME="$_is_ch" sh "$SRC/harness-install.sh" --agents=claude,codex "$_is_t" >"$_is_t/.out" 2>"$_is_t/.err" \
    || { cat "$_is_t/.err" >&2; fail "installer exited non-zero for $_is_t"; }
}

test_shared_prompt_survives_another_targets_gate_off() {
  _s="$T/xtarget"; _ch="$_s/ch"
  install_shared "$_s/A" "$_ch" true
  [ -f "$_ch/prompts/sdd-pr-loop.md" ] || fail "cross-target setup: A's global prompt not stamped"
  # B is a DIFFERENT repo taking the opt-in default (gate off) on the same machine
  install_shared "$_s/B" "$_ch" false
  [ -f "$_ch/prompts/sdd-pr-loop.md" ] \
    || fail "cross-target: B's gate-off install deleted the global prompt A still wants"
  grep -qF 'still claimed by another harness target' "$_s/B/.err" \
    || fail "cross-target: keeping another target's prompt was not announced"
  # B's OWN glue is still reclaimed — the local axis (R5) is untouched
  [ -e "$_s/B/.claude/commands/sdd-pr-loop.md" ] \
    && fail "cross-target: B kept its own gated command despite the gate being off"
  # idempotent: re-running B converges instead of oscillating
  install_shared "$_s/B" "$_ch" false
  [ -f "$_ch/prompts/sdd-pr-loop.md" ] || fail "cross-target: a second B run deleted A's prompt"
  # and A, whose gate is still on, keeps working without a repair run
  install_shared "$_s/A" "$_ch" true
  [ -f "$_ch/prompts/sdd-pr-loop.md" ] || fail "cross-target: A's re-run lost its own prompt"
  # the ledger is not itself discoverable as a Codex slash command (Codex globs *.md)
  for _l in "$_ch"/prompts/.*.owners; do
    [ -e "$_l" ] || continue
    case "$_l" in *.md) fail "cross-target: the ownership ledger is named like a prompt" ;; esac
  done
  pass "one target's gate-off never deletes the shared global prompt another target wants"
}

test_shared_prompt_reclaimed_when_last_owner_opts_out() {
  _s="$T/xtarget2"; _ch="$_s/ch"
  install_shared "$_s/A" "$_ch" true
  install_shared "$_s/B" "$_ch" true
  [ -f "$_ch/prompts/sdd-pr-loop.md" ] || fail "last-owner setup: prompt not stamped"
  install_shared "$_s/A" "$_ch" false
  [ -f "$_ch/prompts/sdd-pr-loop.md" ] || fail "last-owner: reclaimed while B still wants it"
  install_shared "$_s/B" "$_ch" false
  [ -e "$_ch/prompts/sdd-pr-loop.md" ] \
    && fail "last-owner: the prompt survived after EVERY target turned the gate off"
  [ -e "$_ch/prompts/.sdd-pr-loop.owners" ] \
    && fail "last-owner: the emptied ownership ledger was left behind as garbage"
  [ -f "$_ch/prompts/sdd-next.md" ] || fail "last-owner: an ungated global prompt was wrongly reclaimed"
  pass "the shared global prompt is reclaimed exactly when the LAST owner opts out"
}

test_dead_owner_never_pins_the_shared_prompt() {
  # A ledger entry must not outlive its target: a repo that was deleted (or un-harnessed)
  # cannot want anything, so it is garbage-collected on read rather than pinning the
  # prompt forever.
  _s="$T/xtarget3"; _ch="$_s/ch"
  install_shared "$_s/A" "$_ch" true
  install_shared "$_s/B" "$_ch" true
  rm -rf "$_s/A"                       # A's repo is gone from disk
  install_shared "$_s/B" "$_ch" false
  [ -e "$_ch/prompts/sdd-pr-loop.md" ] \
    && fail "dead owner: a deleted target's stale claim pinned the shared prompt forever"
  pass "a deleted target's stale claim is garbage-collected, never pins the prompt"
}

test_unknown_ownership_always_keeps_the_shared_prompt() {
  # Fail safe: when ownership cannot be read the prompt may belong to a target this run
  # knows nothing about. Leaving a stale prompt is a no-op; deleting another project's
  # working command is not.
  _s="$T/xtarget4"; _ch="$_s/ch"
  install_shared "$_s/A" "$_ch" true
  rm -f "$_ch/prompts/.sdd-pr-loop.owners"      # e.g. stamped by an installer that predates the ledger
  install_shared "$_s/A" "$_ch" false
  [ -f "$_ch/prompts/sdd-pr-loop.md" ] \
    || fail "unknown ownership: an ABSENT ledger authorized deleting the shared prompt"
  grep -qF 'ownership is unknown' "$_s/A/.err" \
    || fail "unknown ownership: keeping the prompt was not announced"
  # an UNREADABLE ledger gets the same verdict
  install_shared "$_s/A" "$_ch" true
  [ -f "$_ch/prompts/.sdd-pr-loop.owners" ] || fail "unknown ownership: ledger not re-created by the gate-on run"
  if [ "$(id -u)" = 0 ]; then
    skip "unreadable ledger (running as root — a mode-000 file is still readable)"
  else
    chmod 000 "$_ch/prompts/.sdd-pr-loop.owners"
    install_shared "$_s/A" "$_ch" false
    [ -f "$_ch/prompts/sdd-pr-loop.md" ] \
      || fail "unknown ownership: an UNREADABLE ledger authorized deleting the shared prompt"
    [ -f "$_ch/prompts/.sdd-pr-loop.owners" ] \
      || fail "unknown ownership: an unreadable ledger was destroyed instead of left alone"
    chmod 644 "$_ch/prompts/.sdd-pr-loop.owners"
  fi
  pass "unknown or unreadable ownership never authorizes deleting the shared global prompt"
}

# ══ The pr-fixer sub-agent (R9–R14) ═══════════════════════════════════════════

test_canonical_pr_fixer_role() {                      # R9
  [ -f "$SRC/agents/pr-fixer.md" ] || fail "R9: canonical agents/pr-fixer.md missing"
  for _n in 'One comment, one fix, one commit, one return' 'round_dir' 'comment_id' \
            'Out of scope'; do
    grep -qF "$_n" "$SRC/agents/pr-fixer.md" || fail "R9: canonical role missing '$_n'"
  done
  grep -qiF 'Pushing' "$SRC/agents/pr-fixer.md" || fail "R9: role does not exclude pushing"
  grep -qiF 'full test suite' "$SRC/agents/pr-fixer.md" || fail "R9: role does not exclude the full suite"
  # no EXISTING canonical role was forked to carry it
  for _r in orchestrator architect builder reviewer scout fixer; do
    grep -qF 'Do not refactor adjacent code' "$SRC/agents/$_r.md" \
      && fail "R9: agents/$_r.md was forked to carry the pr-fixer runbook"
  done
  [ -f "$BASE/.harness/agents/pr-fixer.md" ] || fail "R9: role not installed into the profile"
  pass "R9 one canonical front-end-neutral agents/pr-fixer.md; no existing role forked"
}

test_claude_pr_fixer_shim() {                         # R10
  _s="$BASE/.claude/agents/pr-fixer.md"
  [ -f "$_s" ] || fail "R10: .claude/agents/pr-fixer.md not emitted"
  grep -qE '^name: pr-fixer$' "$_s"        || fail "R10: shim frontmatter has no name"
  grep -qE '^description: '   "$_s"        || fail "R10: shim frontmatter has no description"
  grep -qE '^tools: '         "$_s"        || fail "R10: shim frontmatter has no tools"
  grep -qF '.harness/agents/pr-fixer.md' "$_s" || fail "R10: shim does not point at the canonical role"
  grep -qF 'Do not refactor adjacent code' "$_s" \
    && fail "R10: shim duplicates the canonical role body"
  pass "R10 .claude/agents/pr-fixer.md emitted through emit_agent, points at the canonical role"
}

test_opencode_pr_fixer_agent_file() {                 # R11
  _a="$BASE/.opencode/agent/pr-fixer.md"
  [ -f "$_a" ] || fail "R11: .opencode/agent/pr-fixer.md not emitted"
  grep -qE '^mode: subagent$' "$_a" || fail "R11: opencode pr-fixer lacks mode: subagent"
  grep -qE '^description: '   "$_a" || fail "R11: opencode pr-fixer lacks a description"
  grep -qF '.harness/agents/pr-fixer.md' "$_a" || fail "R11: opencode pr-fixer does not point at the role"
  grep -qF 'pr-fixer' "$BASE/opencode.json" \
    && fail "R11/R12: opencode.json must not gain a pr-fixer entry"
  pass "R11 .opencode/agent/pr-fixer.md carries mode: subagent; opencode.json untouched"
}

test_opencode_json_unaffected_by_pr_loop() {          # R12
  _on="$T/ocon"; _of="$T/ocoff"
  install_on "$_on"
  install_at "$_of"                 # default = gate off
  cmp -s "$_on/opencode.json" "$_of/opencode.json" \
    || fail "R12: opencode.json differs between pr_loop on and off"
  if [ -e "$_on/.harness/.opencode.stamp" ] || [ -e "$_of/.harness/.opencode.stamp" ]; then
    [ -e "$_on/.harness/.opencode.stamp" ] && [ -e "$_of/.harness/.opencode.stamp" ] \
      || fail "R12: .opencode.stamp presence differs between pr_loop on and off"
  fi
  pass "R12 opencode.json bytes + .opencode.stamp presence are independent of pr_loop"
}

test_antigravity_pr_fixer_persona() {                 # R13
  _p="$BASE/.agents/agents/pr-fixer.md"
  [ -f "$_p" ] || fail "R13: .agents/agents/pr-fixer.md not emitted"
  grep -qE '^description: ' "$_p" || fail "R13: antigravity persona lacks a description"
  grep -qF '.harness/agents/pr-fixer.md' "$_p" || fail "R13: persona does not point at the canonical role"
  pass "R13 .agents/agents/pr-fixer.md emitted through the existing persona emitter"
}

test_no_codex_gemini_pr_fixer_artifact() {            # R14
  [ -e "$BASE/.codex/agents/pr-fixer.toml" ] && fail "R14: a codex pr-fixer artifact was created"
  [ -e "$BASE/.gemini/agents/pr-fixer.md" ]  && fail "R14: a gemini pr-fixer artifact was created"
  # the role map must not have grown a pr-fixer row (it drives .gemini/ + .codex/ creation)
  grep -qE '^MODEL_ROLES=.*pr-fixer' "$SRC/harness-install.sh" \
    && fail "R14: pr-fixer was added to MODEL_ROLES"
  awk '/^  ag_personas\(\)/,/^  }/' "$SRC/harness-install.sh" | grep -q 'pr-fixer' \
    && fail "R14: pr-fixer was added to the ag_personas map"
  grep -qF 'in-session' "$BODY" || fail "R14: body does not tell a front-end without pr-fixer to fix in-session"
  grep -qF 'codex, gemini' "$BODY" || fail "R14: body does not name the front-ends without a pr-fixer sub-agent"
  pass "R14 no codex/gemini pr-fixer artifact; role map untouched; body says in-session"
}

# ══ Configuration (R15–R20) ═══════════════════════════════════════════════════

test_pr_loop_block_seeded() {                         # R15
  # BASE was installed with the gate armed by ENV, so its config is the untouched SEEDED
  # one: the seed must carry the OPT-IN default regardless of the env override, and
  # regardless of what the harness SOURCE repo sets for itself.
  _c="$BASE/.harness/harness.config.yaml"
  grep -qE '^pr_loop:[[:space:]]*(#.*)?$' "$_c" || fail "R15: fresh install seeded no pr_loop: block"
  [ "$(cfg_pr_loop_enabled "$_c")" = "false" ] \
    || fail "R15: pr_loop.enabled was not seeded as the opt-in default false (got '$(cfg_pr_loop_enabled "$_c")')"
  grep -qE '^  auto_merge: true'             "$_c" || fail "R15: pr_loop.auto_merge default not seeded"
  grep -qE '^  max_rounds: 4'                "$_c" || fail "R15: pr_loop.max_rounds default not seeded"
  grep -qE '^  blocking_severities: "P0,P1"' "$_c" || fail "R15: pr_loop.blocking_severities default not seeded"
  grep -qE '^  merge_strategy: "merge"'      "$_c" || fail "R15: pr_loop.merge_strategy default not seeded"
  # ...and the seeded block explains that turning it on is a deliberate choice
  grep -qF 'opt-in' "$_c" || fail "R15: the seeded block does not document the opt-in gate"
  grep -qF 'Codex GitHub App' "$_c" || fail "R15: the seeded block does not state the Codex App precondition"
  pass "R15 fresh install seeds the five pr_loop keys, with enabled opt-in false"
}

test_pr_loop_block_migrated_idempotent() {            # R16
  _m="$T/migrate"
  install_at "$_m"
  _cfg="$_m/.harness/harness.config.yaml"
  # strip the block (simulating a preserved pre-E18 config) + plant a sentinel value
  awk '/^# Codex PR review loop/{exit} {print}' "$_cfg" > "$_m/.cfg2"
  printf 'SENTINEL_KEEP: yes   # user comment\n' >> "$_m/.cfg2"
  mv "$_m/.cfg2" "$_cfg"
  grep -q '^pr_loop:' "$_cfg" && fail "R16 setup: block not stripped"
  install_at "$_m"
  grep -qE '^pr_loop:' "$_cfg" || fail "R16: migration did not append the pr_loop block"
  grep -qF 'SENTINEL_KEEP: yes   # user comment' "$_cfg" \
    || fail "R16: migration altered an existing value/comment"
  cp "$_cfg" "$_m/.cfg-once"
  install_at "$_m"
  cmp -s "$_cfg" "$_m/.cfg-once" || fail "R16: a second migration run was not a no-op"
  [ "$(grep -c '^pr_loop:' "$_cfg")" = "1" ] || fail "R16: the block was appended twice"
  pass "R16 migration appends the block, preserves values/comments, is idempotent"
}

test_seeded_and_migrated_block_identical() {          # R17
  _s="$T/seedblk"; _g="$T/migblk"
  install_at "$_s"
  awk '/^# Codex PR review loop/,0' "$_s/.harness/harness.config.yaml" > "$T/.blk-seeded"
  install_at "$_g"
  awk '/^# Codex PR review loop/{exit} {print}' "$_g/.harness/harness.config.yaml" > "$_g/.c"
  mv "$_g/.c" "$_g/.harness/harness.config.yaml"
  install_at "$_g"
  awk '/^# Codex PR review loop/,0' "$_g/.harness/harness.config.yaml" > "$T/.blk-migrated"
  [ -s "$T/.blk-seeded" ] || fail "R17: seeded block not captured"
  cmp -s "$T/.blk-seeded" "$T/.blk-migrated" \
    || fail "R17: the migrated pr_loop block is not byte-identical to the seeded one"
  pass "R17 seeded block == migrated block, byte for byte"
}

test_absent_block_defaults_to_disabled() {            # R18
  _a="$T/absent"
  mkdir -p "$_a/.harness"
  # A preserved config with NO pr_loop block at all — i.e. every config written before the
  # block existed. The gate is OPT-IN, so absence must resolve to DISABLED, and the
  # migration must then append the documented defaults (which are themselves off).
  awk '/^# Codex PR review loop/{exit} {print}' "$SRC/harness.config.yaml" \
    > "$_a/.harness/harness.config.yaml"
  grep -q '^pr_loop:' "$_a/.harness/harness.config.yaml" && fail "R18 setup: block still present"
  install_at "$_a"
  [ -e "$_a/.claude/commands/sdd-pr-loop.md" ] \
    && fail "R18: an absent pr_loop block must resolve to DISABLED, not enabled"
  [ -e "$_a/.claude/agents/pr-fixer.md" ] && fail "R18: absent block must stamp no pr-fixer"
  for _k in 'enabled: false' 'auto_merge: true' 'max_rounds: 4' \
            'blocking_severities: "P0,P1"' 'merge_strategy: "merge"'; do
    grep -qF "$_k" "$_a/.harness/harness.config.yaml" || fail "R18: default '$_k' not documented after migration"
  done
  pass "R18 an absent pr_loop block resolves to DISABLED and migrates to the documented defaults"
}

test_absent_enabled_key_resolves_off() {              # R18b
  # The narrower, load-bearing case for the OPT-IN inversion: the block EXISTS (so
  # migrate_config leaves it alone) but `enabled` is absent, empty, or some near-miss
  # token. Under the old opt-out logic every one of these resolved to ENABLED and stamped
  # the glue; under the opt-in gate only the literal `true` may.
  _k="$T/keyoff"
  # 1. block present, `enabled:` key removed entirely
  mkdir -p "$_k/.harness"
  awk '
    /^pr_loop:[[:space:]]*(#.*)?$/ { p=1; print; next }
    p && /^[^[:space:]#]/ { p=0 }
    p && /^[[:space:]]+enabled:/ { next }
    { print }
  ' "$SRC/harness.config.yaml" > "$_k/.harness/harness.config.yaml"
  grep -q '^pr_loop:' "$_k/.harness/harness.config.yaml" || fail "R18b setup: block was lost"
  [ -z "$(cfg_pr_loop_enabled "$_k/.harness/harness.config.yaml")" ] \
    || fail "R18b setup: the enabled key is still present under pr_loop:"
  install_at "$_k"
  [ -e "$_k/.claude/commands/sdd-pr-loop.md" ] \
    && fail "R18b: an absent pr_loop.enabled key must resolve OFF"
  [ -e "$_k/.claude/agents/pr-fixer.md" ] && fail "R18b: absent key must stamp no pr-fixer"
  # the migration must NOT re-add the key (the block is present; it is append-only)
  [ -z "$(cfg_pr_loop_enabled "$_k/.harness/harness.config.yaml")" ] \
    || fail "R18b: migration rewrote an existing pr_loop block"
  # 2. present but empty / near-miss values — each must stay OFF
  for _v in '' 'yes' '1' 'True' 'TRUE' 'on' 'false'; do
    _n="$T/keyval$(printf '%s' "$_v" | tr -cd 'A-Za-z0-9')x"
    set_gate "$_n" "$_v"
    install_at "$_n"
    [ -e "$_n/.claude/commands/sdd-pr-loop.md" ] \
      && fail "R18b: pr_loop.enabled='$_v' must not arm the gate — only the literal true may"
  done
  # ...and the literal `true` still does arm it, from the very same code path
  _y="$T/keyyes"
  set_gate "$_y" true
  install_at "$_y"
  [ -f "$_y/.claude/commands/sdd-pr-loop.md" ] \
    || fail "R18b: the literal pr_loop.enabled: true failed to arm the gate"
  pass "R18b absent/empty/malformed pr_loop.enabled resolves OFF; only the literal true arms it"
}

test_pr_loop_key_is_section_scoped() {                # R19
  _s="$T/scoped"
  set_gate "$_s" true
  install_at "$_s"
  _cfg="$_s/.harness/harness.config.yaml"
  # A same-named key under ANOTHER top-level section must never be read as pr_loop.enabled.
  { printf '\nsome_other_section:\n'; printf '  enabled: false\n'; } >> "$_cfg"
  install_at "$_s"
  [ -f "$_s/.claude/commands/sdd-pr-loop.md" ] \
    || fail "R19: a foreign section's 'enabled: false' disabled the pr_loop gate"
  # ...and the real key still wins when it IS under pr_loop:
  set_gate "$_s" false
  install_at "$_s"
  [ -e "$_s/.claude/commands/sdd-pr-loop.md" ] && fail "R19: the top-level pr_loop.enabled was not honored"
  # The inverse direction matters more now that the gate is opt-in: a foreign section's
  # 'enabled: true' must not ARM a gate whose own key says otherwise.
  _s2="$T/scoped2"
  install_at "$_s2"
  { printf '\nsome_other_section:\n'; printf '  enabled: true\n'; } \
    >> "$_s2/.harness/harness.config.yaml"
  install_at "$_s2"
  [ -e "$_s2/.claude/commands/sdd-pr-loop.md" ] \
    && fail "R19: a foreign section's 'enabled: true' armed the pr_loop gate"
  pass "R19 pr_loop keys are read only from the top-level pr_loop: section (both directions)"
}

test_no_mco_tokens_in_body() {                        # R20
  # Sweeps the INSTALLED body only. progress/ and specs/epics/ are historical records and
  # are deliberately excluded; so is tests/, which must be able to name the banned tokens.
  _paths="$SRC/agents $SRC/docs $SRC/store $SRC/tools $SRC/specs/_templates \
          $SRC/AGENTS.md $SRC/CLAUDE.md $SRC/README.md $SRC/harness-install.sh \
          $SRC/harness.config.yaml $SRC/.claude"
  for _tok in 'MCO_' '.mco-cache' '/.agents/skills' 'route-task' 'start-feature'; do
    # shellcheck disable=SC2086 -- intentional word split of the path list
    if grep -rlF "$_tok" $_paths 2>/dev/null | grep -q .; then
      # shellcheck disable=SC2086
      grep -rlF "$_tok" $_paths 2>/dev/null >&2
      fail "R20: banned token '$_tok' still present in the harness body"
    fi
  done
  # The loop reads HARNESS_* names only.
  for _v in HARNESS_POLL_INTERVAL HARNESS_POLL_CEILING HARNESS_FIRST_RESPONSE; do
    grep -qF "$_v" "$W" || fail "R20: watcher does not read $_v"
  done
  grep -qF 'HARNESS_DRY_RUN' "$BODY" || fail "R20: body does not honor HARNESS_DRY_RUN"
  pass "R20 no MCO/skills/route-task/start-feature token in the body; HARNESS_* names only"
}

test_env_overrides_config() {                         # R20 precedence
  _e="$T/envprec"
  set_gate "$_e" true
  install_at "$_e"
  [ -f "$_e/.claude/commands/sdd-pr-loop.md" ] || fail "R20 setup: glue not stamped"
  # env override beats a config value of true
  mkdir -p "$_e"
  HARNESS_PR_LOOP_ENABLED=false CODEX_HOME="$_e/ch" sh "$SRC/harness-install.sh" "$_e" \
    >"$_e/.out" 2>"$_e/.err" || { cat "$_e/.err" >&2; fail "R20: env-override run exited non-zero"; }
  [ -e "$_e/.claude/commands/sdd-pr-loop.md" ] \
    && fail "R20: HARNESS_PR_LOOP_ENABLED=false did not override config enabled: true"
  # ...and it beats a config value of false in the other direction
  set_gate "$_e" false
  HARNESS_PR_LOOP_ENABLED=true CODEX_HOME="$_e/ch" sh "$SRC/harness-install.sh" "$_e" \
    >"$_e/.out" 2>"$_e/.err" || { cat "$_e/.err" >&2; fail "R20: env-override run exited non-zero"; }
  [ -f "$_e/.claude/commands/sdd-pr-loop.md" ] \
    || fail "R20: HARNESS_PR_LOOP_ENABLED=true did not override config enabled: false"
  pass "R20 precedence: env override wins over the config value"
}

# ══ The vendored watcher (R21–R35) ════════════════════════════════════════════

test_watcher_installed_executable_posix() {           # R21
  [ -f "$W" ] || fail "R21: tools/wait-for-codex.sh missing from the source tree"
  head -n 1 "$W" | grep -qx '#!/bin/sh' || fail "R21: watcher is not a #!/bin/sh script"
  sh -n "$W" || fail "R21: watcher does not parse under POSIX sh"
  if command -v dash >/dev/null 2>&1; then
    dash -n "$W" || fail "R21: watcher does not parse under dash"
  fi
  grep -qF '[[' "$W"        && fail "R21: watcher uses a bash [[ ]] test"
  grep -qF '< <(' "$W"      && fail "R21: watcher uses process substitution"
  grep -qE '\$\{[A-Za-z_]+:[0-9]+:[0-9]+\}' "$W" && fail "R21: watcher uses bash substring expansion"
  # a BASH arithmetic COMMAND appears in COMMAND position (line start, or after if/while).
  # POSIX `$(( ))` expansion and jq's nested `select((...))` filters are fine.
  grep -qE '^[[:space:]]*\(\(|(if|while|until|elif)[[:space:]]+\(\(' "$W" \
    && fail "R21: watcher uses a bash (( )) arithmetic command"
  [ -x "$BASE/.harness/tools/wait-for-codex.sh" ] || fail "R21: installed watcher is not executable"
  cmp -s "$W" "$BASE/.harness/tools/wait-for-codex.sh" || fail "R21: installed watcher differs from source"
  grep -qF '.harness/tools/wait-for-codex.sh' "$BODY" \
    || fail "R21: the command body does not use a harness-relative watcher path"
  pass "R21 watcher is POSIX sh, installed executable, referenced harness-relatively"
}

# ── stubbed-gh + sandboxed-PATH helpers ───────────────────────────────────────
# mk_sandbox_bin <dir> — a PATH dir holding ONLY the utilities the watcher needs, so a
# test can prove `gh`/`jq` are genuinely absent instead of asserting it in prose.
mk_sandbox_bin() {
  mkdir -p "$1"
  for _u in sh dash bash env mkdir rm cat cut sleep grep sed date basename dirname \
            cmp ls touch mv cp sort uniq head tail tr wc printf; do
    _p="$(command -v "$_u" 2>/dev/null || true)"
    if [ -n "$_p" ]; then ln -sf "$_p" "$1/$_u"; fi
  done
}

# mk_gh_stub <bin-dir> — a `gh` whose behavior is chosen by $STUB_MODE and whose canned
# payloads come from $STUB_DIR. Hermetic: no network, no real repo, no live PR.
mk_gh_stub() {
  cat > "$1/gh" <<'STUB'
#!/bin/sh
mode="${STUB_MODE:-pending}"
sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  auth)
    [ "$mode" = "missing-auth" ] && exit 1
    echo "Logged in to github.com"; exit 0 ;;
  repo)
    [ "$mode" = "no-repo" ] && exit 1
    echo "acme widgets"; exit 0 ;;
  pr)
    [ $# -gt 0 ] && shift          # the action (view/comment/...)
    _json=""
    while [ $# -gt 0 ]; do
      case "$1" in --json) _json="${2:-}"; shift 2 ;; *) shift ;; esac
    done
    case "$_json" in
      state)
        case "$mode" in
          closed-pr) echo CLOSED ;;
          no-pr)     exit 1 ;;
          *)         echo OPEN ;;
        esac
        exit 0 ;;
      *)
        [ "$mode" = "fetch-fail" ] && exit 1
        cat "$STUB_DIR/pr.json"; exit 0 ;;
    esac ;;
  api)
    _ep=""
    for _a in "$@"; do
      case "$_a" in
        -*) ;;
        *) [ -z "$_ep" ] && _ep="$_a" ;;
      esac
    done
    case "$_ep" in
      */issues/comments/*/reactions) cat "$STUB_DIR/reactions.json" ;;
      */pulls/*/comments)
        # `comments-fetch-fail` = the pull-review-comments endpoint alone fails, while
        # everything else (including a clean banner in `gh pr view`) still answers.
        [ "$mode" = "comments-fetch-fail" ] && exit 1
        cat "$STUB_DIR/review-comments.page.json" ;;
      */issues/comments/*)
        [ "$mode" = "no-trigger-ts" ] && exit 1
        printf '%s\n' "${STUB_TRIGGER_TS:-2026-01-01T00:00:00Z}" ;;
      */issues/*/comments)           cat "$STUB_DIR/issue-comments.page.json" ;;
      *) echo '[]' ;;
    esac
    exit 0 ;;
esac
exit 0
STUB
  chmod +x "$1/gh"
}

# mk_dummy_jq <bin-dir> — a `jq` that only has to EXIST (preflight does `command -v jq`).
mk_dummy_jq() { printf '#!/bin/sh\nexit 0\n' > "$1/jq"; chmod +x "$1/jq"; }
# link_real_jq <bin-dir> — the real jq, for the wait-mode tests that actually run filters.
link_real_jq() { ln -sf "$(command -v jq)" "$1/jq"; }

# mk_stub_payload <dir> <kind> — canned GitHub responses. `.page.json` files are what a
# `--paginate --slurp` fetch returns (an array of pages), which the watcher flattens.
mk_stub_payload() {
  _d="$1"; _kind="$2"; mkdir -p "$_d"
  _head='abcdef1234567890abcdef1234567890abcdef12'
  echo '[[]]' > "$_d/issue-comments.page.json"
  echo '[[]]' > "$_d/review-comments.page.json"
  echo '[]'   > "$_d/reactions.json"
  printf '{"headRefOid":"%s","reviews":[],"comments":[],"statusCheckRollup":[]}\n' "$_head" > "$_d/pr.json"
  case "$_kind" in
    findings)
      printf '[[{"id":11,"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"%s","created_at":"2026-06-01T00:00:00Z","body":"P1 broken"}]]\n' \
        "$_head" > "$_d/review-comments.page.json" ;;
    clean)
      printf '{"headRefOid":"%s","reviews":[{"author":{"login":"chatgpt-codex-connector"},"body":"Reviewed commit: abcdef1 — no findings","submittedAt":"2026-06-01T00:00:00Z"}],"comments":[],"statusCheckRollup":[]}\n' \
        "$_head" > "$_d/pr.json" ;;
    pending) : ;;
  esac
}

test_preflight_success() {                            # R30
  _b="$T/pfok/bin"; mk_sandbox_bin "$_b"; mk_gh_stub "$_b"; mk_dummy_jq "$_b"
  ( PATH="$_b" STUB_MODE=ok sh "$W" preflight 7 ) >/dev/null 2>"$T/.pfok.err" \
    || fail "R30: preflight failed when gh+auth+jq+repo+open PR all hold (exit $?)"
  pass "R30 preflight exits 0 when gh, auth, jq, the repo slug and an OPEN PR all hold"
}

test_preflight_failure_matrix() {                     # R31
  # gh missing
  _b="$T/pf1/bin"; mk_sandbox_bin "$_b"; mk_dummy_jq "$_b"
  _rc=0; ( PATH="$_b" sh "$W" preflight 7 ) >/dev/null 2>"$T/.pf1" || _rc=$?
  [ "$_rc" = 5 ] || fail "R31: gh missing must exit 5 (got $_rc)"
  grep -qF 'gh' "$T/.pf1" || fail "R31: gh-missing diagnostic does not name gh"
  [ "$(wc -l < "$T/.pf1" | tr -d ' ')" = "1" ] || fail "R31: gh-missing diagnostic is not one line"
  # unauthed
  _b="$T/pf2/bin"; mk_sandbox_bin "$_b"; mk_gh_stub "$_b"; mk_dummy_jq "$_b"
  _rc=0; ( PATH="$_b" STUB_MODE=missing-auth sh "$W" preflight 7 ) >/dev/null 2>"$T/.pf2" || _rc=$?
  [ "$_rc" = 5 ] || fail "R31: unauthed gh must exit 5 (got $_rc)"
  grep -qiF 'auth' "$T/.pf2" || fail "R31: unauthed diagnostic does not name auth"
  # jq missing
  _b="$T/pf3/bin"; mk_sandbox_bin "$_b"; mk_gh_stub "$_b"
  _rc=0; ( PATH="$_b" STUB_MODE=ok sh "$W" preflight 7 ) >/dev/null 2>"$T/.pf3" || _rc=$?
  [ "$_rc" = 5 ] || fail "R31: missing jq must exit 5 (got $_rc)"
  grep -qF 'jq' "$T/.pf3" || fail "R31: jq-missing diagnostic does not name jq"
  # repo slug unresolvable
  _b="$T/pf4/bin"; mk_sandbox_bin "$_b"; mk_gh_stub "$_b"; mk_dummy_jq "$_b"
  _rc=0; ( PATH="$_b" STUB_MODE=no-repo sh "$W" preflight 7 ) >/dev/null 2>"$T/.pf4" || _rc=$?
  [ "$_rc" = 5 ] || fail "R31: unresolvable repo must exit 5 (got $_rc)"
  grep -qiF 'repo' "$T/.pf4" || fail "R31: repo diagnostic does not name the repo slug"
  # PR not open
  _b="$T/pf5/bin"; mk_sandbox_bin "$_b"; mk_gh_stub "$_b"; mk_dummy_jq "$_b"
  _rc=0; ( PATH="$_b" STUB_MODE=closed-pr sh "$W" preflight 7 ) >/dev/null 2>"$T/.pf5" || _rc=$?
  [ "$_rc" = 5 ] || fail "R31: a closed PR must exit 5 (got $_rc)"
  grep -qF 'OPEN' "$T/.pf5" || fail "R31: closed-PR diagnostic does not mention OPEN"
  # nothing was posted: the stub records no `pr comment` because preflight never calls it
  grep -rqF 'pr comment' "$T/.pf1" "$T/.pf2" "$T/.pf3" "$T/.pf4" "$T/.pf5" \
    && fail "R31: preflight posted to GitHub"
  pass "R31 each failed precondition exits 5 with a one-line diagnostic; nothing posted"
}

# run_wait <name> <stub-kind> <mode> <extra-env...> — helper for the wait-mode tests.
# Echoes the exit code; stderr lands in $T/.<name>.err, the round dir is $T/<name>/round.
run_wait() {
  _rw_name="$1"; _rw_kind="$2"; _rw_mode="$3"; shift 3
  _rw_b="$T/$_rw_name/bin"; _rw_r="$T/$_rw_name/round"
  mk_sandbox_bin "$_rw_b"; mk_gh_stub "$_rw_b"; link_real_jq "$_rw_b"
  mk_stub_payload "$T/$_rw_name/stub" "$_rw_kind"
  _rw_rc=0
  ( PATH="$_rw_b" STUB_DIR="$T/$_rw_name/stub" STUB_MODE="$_rw_mode" \
    env "$@" sh "$W" 7 999 "$_rw_r" ) >/dev/null 2>"$T/.$_rw_name.err" || _rw_rc=$?
  printf '%s\n' "$_rw_rc"
}

test_wait_mode_exit_codes() {                         # R22
  if ! have_jq; then skip "test_wait_mode_exit_codes (jq not installed)"; return 0; fi
  _rc="$(run_wait wfind findings ok HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=3)"
  [ "$_rc" = 0 ] || fail "R22: fresh findings on head must exit 0 (got $_rc)"
  _rc="$(run_wait wclean clean ok HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=3)"
  [ "$_rc" = 3 ] || fail "R22: a clean review must exit 3 (got $_rc)"
  _rc="$(run_wait wtime pending ok HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 HARNESS_FIRST_RESPONSE=0)"
  [ "$_rc" = 2 ] || fail "R22: the ceiling must exit 2 (got $_rc)"
  _rc=0; sh "$W" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" = 4 ] || fail "R22: a usage error must exit 4 (got $_rc)"
  _rc=0; sh "$W" 7 >/dev/null 2>&1 || _rc=$?
  [ "$_rc" = 4 ] || fail "R22: a missing round-dir must exit 4 (got $_rc)"
  pass "R22 wait-mode exit contract preserved: 0 findings / 3 clean / 2 timeout / 4 usage"
}

test_round_dir_sources_written() {                    # R23
  if ! have_jq; then skip "test_round_dir_sources_written (jq not installed)"; return 0; fi
  _rc="$(run_wait wsrc findings ok HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=3)"
  [ "$_rc" = 0 ] || fail "R23 setup: watcher exited $_rc"
  for _f in pr.json review-comments.json issue-comments.json reactions.json trigger-ts.txt; do
    [ -f "$T/wsrc/round/$_f" ] || fail "R23: $_f not written into the round dir"
  done
  [ "$(cat "$T/wsrc/round/trigger-ts.txt")" = "2026-01-01T00:00:00Z" ] \
    || fail "R23: trigger-ts.txt does not hold the resolved trigger timestamp"
  # the slurped pages are flattened to a single array
  jq -e 'type == "array"' "$T/wsrc/round/review-comments.json" >/dev/null \
    || fail "R23: review-comments.json is not a flattened array"
  pass "R23 four sources + trigger-ts.txt written into the round dir"
}

test_unresolvable_trigger_ts_exits_4() {              # R24
  if ! have_jq; then skip "test_unresolvable_trigger_ts_exits_4 (jq not installed)"; return 0; fi
  _rc="$(run_wait wts findings no-trigger-ts HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=3)"
  [ "$_rc" = 4 ] || fail "R24: an unresolvable trigger timestamp must exit 4 (got $_rc)"
  grep -qiF 'freshness filter' "$T/.wts.err" \
    || fail "R24: the diagnostic does not explain the freshness filter is not silently disabled"
  pass "R24 an unresolvable trigger timestamp exits 4, never a silent filter bypass"
}

test_timeout_exits_2_not_clean() {                    # R28
  if ! have_jq; then skip "test_timeout_exits_2_not_clean (jq not installed)"; return 0; fi
  _rc="$(run_wait wto pending ok HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 HARNESS_FIRST_RESPONSE=0)"
  [ "$_rc" = 2 ] || fail "R28: the ceiling must exit 2, never 3 (got $_rc)"
  grep -qiF 'timeout' "$T/.wto.err" || fail "R28: the ceiling exit is not reported as a timeout"
  grep -qiF 'clean review' "$T/.wto.err" && fail "R28: a timeout was reported as clean"
  pass "R28 the ceiling exits 2 and is never reported as clean"
}

test_first_response_window_fails_fast() {             # R32
  if ! have_jq; then skip "test_first_response_window_fails_fast (jq not installed)"; return 0; fi
  _rc="$(run_wait wfr pending ok HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=60 HARNESS_FIRST_RESPONSE=1)"
  [ "$_rc" = 5 ] || fail "R32: no bot activity inside the window must exit 5 (got $_rc)"
  grep -qF 'GitHub App' "$T/.wfr.err" || fail "R32: the diagnostic does not name the Codex GitHub App"
  pass "R32 no Codex activity in the first-response window exits 5 naming the GitHub App"
}

test_first_response_probe_disabled() {                # R33
  if ! have_jq; then skip "test_first_response_probe_disabled (jq not installed)"; return 0; fi
  _rc="$(run_wait wfr0 pending ok HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 HARNESS_FIRST_RESPONSE=0)"
  [ "$_rc" = 2 ] || fail "R33: HARNESS_FIRST_RESPONSE=0 must disable the probe (expected 2, got $_rc)"
  grep -qF 'GitHub App' "$T/.wfr0.err" && fail "R33: the probe fired although it was disabled"
  pass "R33 HARNESS_FIRST_RESPONSE=0 disables the first-response probe entirely"
}

test_poll_env_knobs_honored() {                       # R34
  if ! have_jq; then skip "test_poll_env_knobs_honored (jq not installed)"; return 0; fi
  _t0="$(date +%s)"
  _rc="$(run_wait wknob pending ok HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=2 HARNESS_FIRST_RESPONSE=0)"
  _t1="$(date +%s)"
  [ "$_rc" = 2 ] || fail "R34: expected the ceiling exit 2 (got $_rc)"
  [ "$(( _t1 - _t0 ))" -ge 1 ] || fail "R34: HARNESS_POLL_INTERVAL was not honored (ran too fast)"
  [ "$(( _t1 - _t0 ))" -lt 30 ] || fail "R34: HARNESS_POLL_CEILING was not honored (ran too long)"
  grep -qF 'ceiling 2s' "$T/.wknob.err" || fail "R34: the configured ceiling is not the one reported"
  grep -qF 'MCO' "$W" && fail "R34: the watcher reads a non-HARNESS_ vendor variable"
  pass "R34 HARNESS_POLL_INTERVAL + HARNESS_POLL_CEILING honored; no foreign env name read"
}

# ── offline fixtures for the evaluation rules (R25–R27, R29) ──────────────────
FX_HEAD='abcdef1234567890abcdef1234567890abcdef12'
FX_ANCHOR='2026-06-01T00:00:00Z'

# mk_fixture <name> — build a round dir under $T/fx/<name>; echoes its path.
mk_fixture() {
  _fx="$T/fx/$1"; mkdir -p "$_fx"
  printf '%s' "$FX_ANCHOR" > "$_fx/trigger-ts.txt"
  printf '{"headRefOid":"%s","reviews":[],"comments":[]}\n' "$FX_HEAD" > "$_fx/pr.json"
  echo '[]' > "$_fx/review-comments.json"
  echo '[]' > "$_fx/issue-comments.json"
  echo '[]' > "$_fx/reactions.json"
  printf '%s\n' "$_fx"
}

# eval_fixture <dir> — run `evaluate` with a PATH that has NO gh, echo the exit code.
eval_fixture() {
  _eb="$T/fx/bin"
  if [ ! -x "$_eb/jq" ]; then mk_sandbox_bin "$_eb"; link_real_jq "$_eb"; fi
  [ -x "$_eb/gh" ] && fail "fixture sandbox must not contain gh"
  _erc=0
  ( PATH="$_eb" sh "$W" evaluate "$1" ) >/dev/null 2>&1 || _erc=$?
  printf '%s\n' "$_erc"
}

test_non_positive_interval_cannot_spin() {            # R56
  # Codex #68 P2 (id 3662643325): `0` is a numeric value the knob parser accepts, and with
  # it `sleep 0` returns instantly while a summed-interval `elapsed` never advances — so
  # NEITHER deadline is ever reached and the watcher hammers the GitHub API forever. A
  # non-positive interval must fail closed as a usage error, before any polling happens.
  if ! have_jq; then skip "test_non_positive_interval_cannot_spin (jq not installed)"; return 0; fi
  for _iv in 0 00; do
    _t0="$(date +%s)"
    _rc="$(run_wait "wspin$_iv" pending ok \
           "HARNESS_POLL_INTERVAL=$_iv" HARNESS_POLL_CEILING=60 HARNESS_FIRST_RESPONSE=0)"
    _t1="$(date +%s)"
    [ "$_rc" = 4 ] \
      || fail "R56: HARNESS_POLL_INTERVAL=$_iv must exit 4, not poll (got $_rc)"
    [ "$(( _t1 - _t0 ))" -lt 20 ] \
      || fail "R56: HARNESS_POLL_INTERVAL=$_iv kept the watcher running instead of failing fast"
    grep -qF 'HARNESS_POLL_INTERVAL' "$T/.wspin$_iv.err" \
      || fail "R56: the diagnostic for interval $_iv does not name the knob"
    # nothing was fetched: the round dir was never populated, so no API call was made
    if [ -f "$T/wspin$_iv/round/pr.json" ]; then
      fail "R56: the watcher polled the GitHub API with a $_iv-second interval"
    fi
  done
  # the deadlines are advanced by WALL CLOCK, not by summing the interval, so a poll that
  # itself takes time counts against the ceiling instead of inflating it
  grep -qF 'date +%s' "$W" || fail "R56: the watcher no longer measures elapsed time by wall clock"
  pass "R56 a non-positive HARNESS_POLL_INTERVAL exits 4 before polling — no unbounded loop"
}

test_stale_reanchored_thread_is_not_a_finding() {     # R25
  if ! have_jq; then skip "test_stale_reanchored_thread_is_not_a_finding (jq not installed)"; return 0; fi
  _f="$(mk_fixture stale-reanchored)"
  printf '[{"id":1,"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"%s","created_at":"2026-05-01T00:00:00Z","body":"P1 old"}]\n' \
    "$FX_HEAD" > "$_f/review-comments.json"
  [ "$(eval_fixture "$_f")" = 1 ] \
    || fail "R25: a stale thread re-anchored to head must NOT count as this round's finding"
  _f="$(mk_fixture fresh-finding)"
  printf '[{"id":2,"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"%s","created_at":"2026-06-02T00:00:00Z","body":"P1 new"}]\n' \
    "$FX_HEAD" > "$_f/review-comments.json"
  [ "$(eval_fixture "$_f")" = 0 ] || fail "R25: a fresh finding on head must exit 0"
  # commit_id must ALSO match head — a fresh comment on an older commit is not this round's
  _f="$(mk_fixture fresh-wrong-commit)"
  printf '[{"id":3,"user":{"login":"chatgpt-codex-connector[bot]"},"commit_id":"deadbeef","created_at":"2026-06-02T00:00:00Z","body":"P1"}]\n' \
    > "$_f/review-comments.json"
  [ "$(eval_fixture "$_f")" = 1 ] || fail "R25: a comment whose commit_id != head must not count"
  pass "R25 freshness needs commit_id == head AND created_at >= trigger"
}

test_clean_via_review_banner() {                      # R26a
  if ! have_jq; then skip "test_clean_via_review_banner (jq not installed)"; return 0; fi
  _f="$(mk_fixture clean-review-banner)"
  printf '{"headRefOid":"%s","reviews":[{"author":{"login":"chatgpt-codex-connector"},"body":"Reviewed commit: abcdef1 — all good","submittedAt":"2026-06-02T00:00:00Z"}],"comments":[]}\n' \
    "$FX_HEAD" > "$_f/pr.json"
  [ "$(eval_fixture "$_f")" = 3 ] || fail "R26: a fresh review banner naming head must exit 3"
  _f="$(mk_fixture stale-banner)"
  printf '{"headRefOid":"%s","reviews":[{"author":{"login":"chatgpt-codex-connector"},"body":"Reviewed commit: abcdef1 — all good","submittedAt":"2026-05-01T00:00:00Z"}],"comments":[]}\n' \
    "$FX_HEAD" > "$_f/pr.json"
  [ "$(eval_fixture "$_f")" = 1 ] || fail "R26: a banner predating the anchor must stay pending"
  pass "R26a clean via a fresh review summary banner naming the head commit"
}

test_clean_via_issue_comment_banner() {               # R26b
  if ! have_jq; then skip "test_clean_via_issue_comment_banner (jq not installed)"; return 0; fi
  _f="$(mk_fixture clean-issue-banner)"
  printf '[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-06-02T00:00:00Z","body":"Didnt find any major issues. Breezy! Reviewed commit: abcdef1"}]\n' \
    > "$_f/issue-comments.json"
  [ "$(eval_fixture "$_f")" = 3 ] || fail "R26: the head banner delivered as an ISSUE comment must exit 3"
  pass "R26b clean via the same banner delivered as an issue comment"
}

test_clean_via_thumbs_reaction() {                    # R26c
  if ! have_jq; then skip "test_clean_via_thumbs_reaction (jq not installed)"; return 0; fi
  _f="$(mk_fixture clean-thumbs)"
  printf '[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]\n' > "$_f/reactions.json"
  [ "$(eval_fixture "$_f")" = 3 ] || fail "R26: a Codex +1 reaction on the trigger comment must exit 3"
  # a +1 from a HUMAN is not a clean signal
  _f="$(mk_fixture human-thumbs)"
  printf '[{"content":"+1","user":{"login":"some-human"}}]\n' > "$_f/reactions.json"
  [ "$(eval_fixture "$_f")" = 1 ] || fail "R26: a human +1 must not be read as a clean review"
  pass "R26c clean via a Codex 👍 reaction on the trigger comment"
}

test_bot_login_exact_match() {                        # R27
  if ! have_jq; then skip "test_bot_login_exact_match (jq not installed)"; return 0; fi
  for _login in 'chatgpt-codex-connector' 'chatgpt-codex-connector[bot]'; do
    _f="$(mk_fixture "bot-$(printf '%s' "$_login" | tr -d '[]')")"
    printf '[{"id":4,"user":{"login":"%s"},"commit_id":"%s","created_at":"2026-06-02T00:00:00Z","body":"P1"}]\n' \
      "$_login" "$FX_HEAD" > "$_f/review-comments.json"
    [ "$(eval_fixture "$_f")" = 0 ] || fail "R27: legitimate login '$_login' was not recognised"
  done
  # an unrelated login is not the bot
  _f="$(mk_fixture bot-other)"
  printf '[{"id":5,"user":{"login":"dependabot[bot]"},"commit_id":"%s","created_at":"2026-06-02T00:00:00Z","body":"P1"}]\n' \
    "$FX_HEAD" > "$_f/review-comments.json"
  [ "$(eval_fixture "$_f")" = 1 ] || fail "R27: a non-Codex bot must not count as a Codex finding"
  grep -qF 'startswith($bot)' "$W" \
    && fail "R27: the bot identity is still a prefix test — a lookalike login can impersonate Codex"
  pass "R27 both legitimate Codex logins are matched, exactly, and no prefix test remains"
}

test_bot_login_lookalike_cannot_signal_clean() {      # R27 (Codex #68 P1, id 3663040307)
  # A prefix predicate (`startswith("chatgpt-codex-connector")`) made every ordinary GitHub
  # account whose login merely BEGINS with the bot name a valid Codex identity. Such an
  # account could 👍 the trigger comment or post a "Reviewed commit: <head>" banner; the
  # watcher exits 3 = "clean, zero findings", which the caller does not classify and (auto
  # merge on) merges — a PR shipped with no Codex review at all. Lock all three signal
  # paths, plus thread ownership, against the near-miss logins.
  if ! have_jq; then
    skip "test_bot_login_lookalike_cannot_signal_clean (jq not installed)"; return 0
  fi
  _tag=0
  for _evil in 'chatgpt-codex-connector-evil' 'chatgpt-codex-connectorX'; do
    _tag=$(( _tag + 1 ))
    # (a) reaction path — the cheapest spoof: one +1 on the trigger comment
    _f="$(mk_fixture "lookalike-thumbs-$_tag")"
    printf '[{"content":"+1","user":{"login":"%s"}}]\n' "$_evil" > "$_f/reactions.json"
    [ "$(eval_fixture "$_f")" = 1 ] \
      || fail "R27: a +1 from lookalike '$_evil' was accepted as a clean Codex review"
    # (b) banner path — as a review, and as an issue comment
    _f="$(mk_fixture "lookalike-review-$_tag")"
    printf '{"headRefOid":"%s","reviews":[{"author":{"login":"%s"},"body":"Reviewed commit: abcdef1 — all good","submittedAt":"2026-06-02T00:00:00Z"}],"comments":[]}\n' \
      "$FX_HEAD" "$_evil" > "$_f/pr.json"
    [ "$(eval_fixture "$_f")" = 1 ] \
      || fail "R27: a review banner from lookalike '$_evil' was accepted as clean"
    _f="$(mk_fixture "lookalike-issue-$_tag")"
    printf '[{"user":{"login":"%s"},"created_at":"2026-06-02T00:00:00Z","body":"Didnt find any major issues. Breezy! Reviewed commit: abcdef1"}]\n' \
      "$_evil" > "$_f/issue-comments.json"
    [ "$(eval_fixture "$_f")" = 1 ] \
      || fail "R27: an issue-comment banner from lookalike '$_evil' was accepted as clean"
    # (c) findings path — a lookalike's inline comment is not a Codex finding either
    _f="$(mk_fixture "lookalike-finding-$_tag")"
    printf '[{"id":9,"user":{"login":"%s"},"commit_id":"%s","created_at":"2026-06-02T00:00:00Z","body":"P1"}]\n' \
      "$_evil" "$FX_HEAD" > "$_f/review-comments.json"
    [ "$(eval_fixture "$_f")" = 1 ] \
      || fail "R27: an inline comment from lookalike '$_evil' counted as a Codex finding"
  done
  # (d) thread ownership, run through the command body's OWN --jq program (extracted
  # verbatim), so the resolve/merge gate is locked against the same impersonation.
  need_body "R27: the body no longer states that the bot logins are exact literals" \
    'Never prefix-match'
  grep -qF 'all(startswith("chatgpt-codex-connector"))' "$BODY" \
    && fail "R27: the body's thread-ownership test is still a prefix match"
  _lt="$T/lookalike-threads"; mkdir -p "$_lt"
  awk '/^  --jq .\.data\.repository\.pullRequest\.reviewThreads\.nodes\[\]$/ { f=1 }
       f { print }
       f && /\\\(\$whole and \$codex\) \\\(\.id\)"..$/ { exit }' "$BODY" \
    | sed -e "1s/^  --jq '//" -e "\$s/')\$//" > "$_lt/filter.jq"
  [ -s "$_lt/filter.jq" ] || fail "R27: could not extract the thread-classifier jq from the body"
  cat > "$_lt/threads.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"id":"T_real","isResolved":false,"comments":{"totalCount":2,"nodes":[
   {"author":{"login":"chatgpt-codex-connector"}},{"author":{"login":"chatgpt-codex-connector[bot]"}}]}},
 {"id":"T_evil","isResolved":false,"comments":{"totalCount":1,"nodes":[
   {"author":{"login":"chatgpt-codex-connector-evil"}}]}},
 {"id":"T_evilX","isResolved":false,"comments":{"totalCount":1,"nodes":[
   {"author":{"login":"chatgpt-codex-connectorX"}}]}}
]}}}}}
JSON
  jq -r -f "$_lt/filter.jq" "$_lt/threads.json" > "$_lt/out" \
    || fail "R27: the body's thread-classifier jq does not run"
  grep -qxF 'true T_real' "$_lt/out" \
    || fail "R27: a genuine Codex-only thread is no longer resolvable"
  grep -qxF 'false T_evil' "$_lt/out" \
    || fail "R27: a thread owned by 'chatgpt-codex-connector-evil' was treated as Codex-owned"
  grep -qxF 'false T_evilX' "$_lt/out" \
    || fail "R27: a thread owned by 'chatgpt-codex-connectorX' was treated as Codex-owned"
  pass "R27b a lookalike login cannot signal clean, file a finding, or own a thread"
}

test_evaluate_is_offline() {                          # R29
  if ! have_jq; then skip "test_evaluate_is_offline (jq not installed)"; return 0; fi
  _f="$(mk_fixture empty)"
  [ "$(eval_fixture "$_f")" = 1 ] || fail "R29: an empty round dir must exit 1 (pending)"
  # eval_fixture runs with a PATH that has no gh at all, so `evaluate` is offline by
  # construction — a gh call would abort the run rather than silently pass.
  _eb="$T/fx/bin"
  [ -e "$_eb/gh" ] && fail "R29: the offline sandbox leaked a gh binary"
  pass "R29 evaluate is offline (PATH without gh) and exits 0/1/3"
}

test_failed_findings_fetch_is_never_clean() {         # R55
  if ! have_jq; then skip "test_failed_findings_fetch_is_never_clean (jq not installed)"; return 0; fi
  # review-comments.json is the authoritative findings stream. If its fetch fails while a
  # FRESH clean banner is already visible, an empty-but-valid `[]` would satisfy condition
  # 2 and exit 3 — and 3 means "clean, zero findings", which the caller does not classify
  # and (auto_merge defaults on) merges. A failed required-source fetch must RETRY.
  _rc="$(run_wait wcfail clean comments-fetch-fail \
         HARNESS_POLL_INTERVAL=1 HARNESS_POLL_CEILING=1 HARNESS_FIRST_RESPONSE=0)"
  [ "$_rc" = 3 ] && fail "R55: a failed findings fetch alongside a fresh banner was reported clean"
  [ "$_rc" = 2 ] || fail "R55: a failed findings fetch must keep polling to the ceiling (got $_rc)"
  grep -qiF 'fetch failed' "$T/.wcfail.err" || fail "R55: the failed fetch is not reported as a retry"
  [ -f "$T/wcfail/round/review-comments.json" ] \
    && fail "R55: a failed fetch published an empty findings stream"
  # …and offline, the same shape must evaluate as pending, never clean.
  _f="$(mk_fixture no-findings-stream)"
  printf '{"headRefOid":"%s","reviews":[{"author":{"login":"chatgpt-codex-connector"},"body":"Reviewed commit: abcdef1 — all good","submittedAt":"2026-06-02T00:00:00Z"}],"comments":[]}\n' \
    "$FX_HEAD" > "$_f/pr.json"
  rm -f "$_f/review-comments.json"
  [ "$(eval_fixture "$_f")" = 1 ] \
    || fail "R55: a MISSING findings stream must stay pending, never clean"
  printf 'not json\n' > "$_f/review-comments.json"
  [ "$(eval_fixture "$_f")" = 1 ] \
    || fail "R55: an UNREADABLE findings stream must stay pending, never clean"
  # a genuinely fetched empty stream is still allowed to be clean
  echo '[]' > "$_f/review-comments.json"
  [ "$(eval_fixture "$_f")" = 3 ] \
    || fail "R55: a successfully fetched zero-findings stream must still read as clean"
  pass "R55 a failed/unreadable findings fetch retries and is never reported as a clean review"
}

test_cache_root_and_gitignore() {                     # R35
  grep -qF '.harness/.pr-loop/' "$BODY" || fail "R35: the body does not pin the cache under .harness/.pr-loop/"
  grep -qF 'round-' "$BODY"             || fail "R35: the body does not use a round-<n> cache dir"
  grep -qxF '.pr-loop/' "$BASE/.harness/.gitignore" \
    || fail "R35: the seeded .harness/.gitignore does not ignore .pr-loop/"
  grep -qxF '/.pr-loop/' "$SRC/.gitignore" \
    || fail "R35: the harness source .gitignore does not ignore /.pr-loop/"
  pass "R35 cache root is <HARNESS_DIR>/.pr-loop/<pr>/round-<n>/ and is gitignored both places"
}

# ══ The generated command body (R36–R47) ══════════════════════════════════════

need_body() { grep -qF -- "$2" "$BODY" || fail "$1"; }

test_body_preflight_before_trigger() {                # R36
  need_body "R36: body does not run the watcher's preflight mode" \
    'wait-for-codex.sh preflight'
  need_body "R36: body does not STOP on a non-zero preflight" 'STOP'
  # preflight must be described BEFORE the trigger post
  python3 - "$BODY" <<'PY' || fail "R36: preflight is not ordered before the @codex review post"
import sys
s = open(sys.argv[1]).read()
assert s.index("wait-for-codex.sh preflight") < s.index('gh pr comment "$pr_number" --body "@codex review"')
PY
  pass "R36 body preflights before posting anything and stops on a non-zero exit"
}

test_body_trigger_id_from_url() {                     # R37
  need_body "R37: body does not derive the trigger id from the printed URL" 'issuecomment-'
  need_body "R37: body does not forbid a separate comment-list call" 'never from a separate'
  need_body "R37: body does not state the pagination reason" 'first 30 (oldest) comments'
  pass "R37 body derives the trigger id from the printed URL and forbids a list call"
}

test_body_background_watcher_and_exit_branching() {   # R38
  need_body "R38: body does not launch the harness-relative watcher" \
    '.harness/tools/wait-for-codex.sh "$pr_number" "$trigger_comment_id" "$round_dir"'
  need_body "R38: body does not launch the watcher in the background" 'background'
  need_body "R38: body does not forbid hand-polling" 'Do not poll by hand'
  for _code in '| `0` |' '| `3` |' '| `2` |' '| `4` |' '| `5` |'; do
    need_body "R38: body does not branch on exit code $_code" "$_code"
  done
  pass "R38 body launches the watcher in the background and branches on 0/2/3/4/5"
}

test_body_classification_rules() {                    # R39
  need_body "R39: body does not match the four severities" 'P0|P1|P2|nit'
  need_body "R39: body does not match case-insensitively" 'case-insensitively'
  need_body "R39: body does not mention the badge form" 'badge'
  need_body "R39: body does not state first-match-wins" 'first match wins'
  need_body "R39: body does not default to P2" 'default to `P2`'
  need_body "R39: body does not filter to the configured blocking severities" \
    'pr_loop.blocking_severities'
  need_body "R39: body does not classify from the inline findings" 'review-comments.json'
  need_body "R39: body does not classify from review bodies" 'reviews[*].body'
  need_body "R39: body does not classify from issue comments" 'issue-comments.json'
  pass "R39 body classifies from all three sources, badge-aware, first match wins, defaults P2"
}

test_body_unreadable_head_fails_closed() {            # R39 (fail-closed head oid)
  # `pr.json` missing or truncated makes jq exit non-zero with empty output; a `pr.json`
  # with no `headRefOid` makes `jq -r` print `null` and exit 0. Either way the freshness
  # filter matches NOTHING, so fresh-comments.json — hence blocking.json — comes out `[]`,
  # which step 6 reads as "zero blocking findings ⇒ all gates green ⇒ merge".
  need_body "R39: the body does not test the head-oid read's exit status" \
    'if ! head=$(jq -r'
  need_body "R39: the body does not guard the head-oid VALUE as well as the status" \
    '|| [ -z "$head" ]; then'
  need_body "R39: head_ok no longer starts fail-closed at 0" \
    'head_ok=0            # fail closed'
  need_body "R39: the body does not state that an unreadable head is not a clean round" \
    'A head oid you could not read is not a head oid.'
  if ! have_jq; then
    skip "test_body_unreadable_head_fails_closed classifier (jq not installed)"
    return 0
  fi
  # Run the body's OWN snippet (extracted verbatim from its fenced block), so this locks
  # the shipped shell and not a paraphrase of it, under both `sh -u` and `sh -e -u`.
  _hd="$T/headoid"; mkdir -p "$_hd"
  awk '/^```bash$/                 { buf=""; inblk=1; next }
       inblk && /^```$/            { if (buf ~ /head_ok=0/) {
                                       printf "%s", buf; exit } inblk=0; next }
       inblk                       { buf = buf $0 "\n" }' "$BODY" > "$_hd/snippet.sh"
  grep -q 'headRefOid' "$_hd/snippet.sh" \
    || fail "R39: could not extract the freshness-filter snippet from the body"
  cat > "$_hd/harness.sh" <<'SH'
. "$SNIPPET"
printf 'head_ok=%s\n' "${head_ok:-unset}"
if [ -f "$round_dir/fresh-comments.json" ]; then
  printf 'fresh=%s\n' "$(tr -d ' \n' < "$round_dir/fresh-comments.json")"
else
  printf 'fresh=ABSENT\n'
fi
SH
  # One genuinely fresh P1, plus the two the freshness rule must keep dropping: a stale
  # thread GitHub re-anchored to head, and a comment filed on an older commit.
  cat > "$_hd/findings.json" <<'JSON'
[{"id":1,"commit_id":"deadbeef","created_at":"2026-07-02T00:00:00Z","body":"![P1 Badge](u) boom"},
 {"id":2,"commit_id":"deadbeef","created_at":"2026-06-01T00:00:00Z","body":"P1 stale, re-anchored"},
 {"id":3,"commit_id":"c0ffee00","created_at":"2026-07-02T00:00:00Z","body":"P1 on an older commit"}]
JSON
  # _mk_head_round <dir> <pr.json contents, or @none> — plus a stale fresh-comments.json from an
  # earlier poll, which a failed read must clear rather than hand on as "zero findings".
  _mk_head_round() {
    rm -rf "$1"; mkdir -p "$1"
    printf '2026-07-01T00:00:00Z\n' > "$1/trigger-ts.txt"
    cp "$_hd/findings.json" "$1/review-comments.json"
    printf '[]\n' > "$1/fresh-comments.json"
    [ "$2" = '@none' ] || printf '%s' "$2" > "$1/pr.json"
  }
  for _c in missing truncated nokey nullkey; do
    case "$_c" in
      missing)   _pr='@none' ;;                          # watcher never wrote it
      truncated) _pr='{"headRefOid":"deadbe' ;;          # half-written / corrupt
      nokey)     _pr='{"reviews":[],"comments":[]}' ;;   # parses, no headRefOid
      nullkey)   _pr='{"headRefOid":null}' ;;            # jq -r prints "null", exits 0
    esac
    for _opt in '' '-e'; do
      _mk_head_round "$_hd/r" "$_pr"
      SNIPPET="$_hd/snippet.sh" round_dir="$_hd/r" \
        sh $_opt -u "$_hd/harness.sh" > "$_hd/out" 2>"$_hd/err" \
        || fail "R39: the snippet aborted under 'sh $_opt -u' on a $_c pr.json instead of failing closed"
      grep -qxF 'head_ok=0' "$_hd/out" \
        || fail "R39: a $_c pr.json passed as a readable head under 'sh $_opt -u' ($(cat "$_hd/out"))"
      grep -qxF 'fresh=ABSENT' "$_hd/out" \
        || fail "R39: a $_c pr.json still produced a fresh-comments.json ($(cat "$_hd/out")) — an empty one reads as a merge"
    done
  done
  # …and both sides of the distinction on a head oid that WAS read: zero fresh findings
  # must still read as a genuine zero, and a fresh finding must survive intact.
  _mk_head_round "$_hd/r" '{"headRefOid":"deadbeef"}'
  SNIPPET="$_hd/snippet.sh" round_dir="$_hd/r" sh -u "$_hd/harness.sh" > "$_hd/out" 2>/dev/null \
    || fail "R39: the snippet failed on a valid pr.json"
  grep -qxF 'head_ok=1' "$_hd/out" || fail "R39: a readable head was rejected ($(cat "$_hd/out"))"
  grep -qF '"id":1' "$_hd/out"  || fail "R39: the fresh head finding was dropped ($(cat "$_hd/out"))"
  grep -qF '"id":2' "$_hd/out"  && fail "R39: a stale re-anchored thread leaked back in"
  grep -qF '"id":3' "$_hd/out"  && fail "R39: a comment filed on an older commit leaked in"
  _mk_head_round "$_hd/r" '{"headRefOid":"feedface"}'          # head nobody filed against
  SNIPPET="$_hd/snippet.sh" round_dir="$_hd/r" sh -u "$_hd/harness.sh" > "$_hd/out" 2>/dev/null \
    || fail "R39: the snippet failed on a valid pr.json with zero fresh findings"
  grep -qxF 'head_ok=1' "$_hd/out" || fail "R39: a readable head with zero findings was rejected"
  grep -qxF 'fresh=[]' "$_hd/out" \
    || fail "R39: zero fresh findings must stay readable as zero ($(cat "$_hd/out"))"
  pass "R39b an unreadable/headless pr.json fails closed ⇒ no empty blocking.json authorizes a merge"
}

test_body_stall_detection() {                         # R40
  need_body "R40: body has no stall-detection step" 'Stall detection'
  need_body "R40: body does not compare against the previous round" 'round-<n-1>/blocking.json'
  need_body "R40: body does not escalate immediately on a repeat" 'immediately'
  pass "R40 body detects a repeated blocking comment and escalates immediately"
}

test_body_round_branching() {                         # R41
  need_body "R41: body does not branch against max_rounds" 'max_rounds'
  need_body "R41: body has no per-comment fixer round" 'below `max_rounds - 1`'
  need_body "R41: body has no combined escalation round" 'one combined fix prompt'
  need_body "R41: body does not label the cap round needs-human" '--add-label needs-human'
  need_body "R41: body does not spawn one pr-fixer per blocking comment" 'pr-fixer'
  pass "R41 body branches by round against max_rounds and ends at needs-human"
}

test_body_never_resolves_human_threads() {            # R42
  need_body "R42: body does not guard non-Codex threads" 'non-Codex participant'
  need_body "R42: body does not route them to needs-human" 'needs-human terminal state'
  need_body "R42: body does not forbid resolving them" 'resolve
nothing and do not merge'
  pass "R42 an unresolved non-Codex thread routes to needs-human, resolves nothing, no merge"
}

test_body_truncated_thread_is_not_codex_only() {      # R42 (fail-closed pagination)
  # `--paginate` walks the OUTER reviewThreads connection only; each thread's nested
  # comments connection is fetched once, capped at 100. A human reply at position 101 is
  # therefore unread — and an unread author must never be assumed to be the bot, or the
  # loop resolves a human's thread and (auto_merge on) merges over the feedback.
  need_body "R42: the thread query does not ask how many comments the thread really has" \
    'comments(first:100){ totalCount nodes{ author{ login } } }'
  need_body "R42: the body does not compare totalCount against the authors it read" \
    '(.comments.totalCount == (.comments.nodes | length)) as $whole'
  need_body "R42: the body does not state that a truncated thread fails closed" \
    'a truncated thread is *not* provably'
  if ! have_jq; then
    skip "test_body_truncated_thread_is_not_codex_only classifier (jq not installed)"
    return 0
  fi
  # Run the body's OWN --jq program (extracted verbatim) over a fixture in the shape the
  # GraphQL query returns, so this locks the classifier and not a paraphrase of it.
  _tt="$T/threads"; mkdir -p "$_tt"
  awk '/^  --jq .\.data\.repository\.pullRequest\.reviewThreads\.nodes\[\]$/ { f=1 }
       f { print }
       f && /\\\(\$whole and \$codex\) \\\(\.id\)"..$/ { exit }' "$BODY" \
    | sed -e "1s/^  --jq '//" -e "\$s/')\$//" > "$_tt/filter.jq"
  [ -s "$_tt/filter.jq" ] || fail "R42: could not extract the thread-classifier jq from the body"
  cat > "$_tt/threads.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
 {"id":"T_whole","isResolved":false,"comments":{"totalCount":2,"nodes":[
   {"author":{"login":"chatgpt-codex-connector"}},{"author":{"login":"chatgpt-codex-connector[bot]"}}]}},
 {"id":"T_human","isResolved":false,"comments":{"totalCount":2,"nodes":[
   {"author":{"login":"chatgpt-codex-connector"}},{"author":{"login":"some-human"}}]}},
 {"id":"T_truncated","isResolved":false,"comments":{"totalCount":101,"nodes":[
   {"author":{"login":"chatgpt-codex-connector"}}]}},
 {"id":"T_no_count","isResolved":false,"comments":{"nodes":[
   {"author":{"login":"chatgpt-codex-connector"}}]}},
 {"id":"T_resolved","isResolved":true,"comments":{"totalCount":1,"nodes":[
   {"author":{"login":"some-human"}}]}}
]}}}}}
JSON
  jq -r -f "$_tt/filter.jq" "$_tt/threads.json" > "$_tt/out" \
    || fail "R42: the body's thread-classifier jq does not run"
  grep -qxF 'true T_whole' "$_tt/out" \
    || fail "R42: a fully-read Codex-only thread is no longer resolvable"
  grep -qxF 'false T_human' "$_tt/out" \
    || fail "R42: a human reply no longer makes the thread non-Codex"
  grep -qxF 'false T_truncated' "$_tt/out" \
    || fail "R42: a thread with another page of comments was treated as Codex-only"
  grep -qxF 'false T_no_count' "$_tt/out" \
    || fail "R42: a thread with no totalCount must fail closed, not open"
  grep -q 'T_resolved' "$_tt/out" && fail "R42: a resolved thread leaked into the unresolved set"
  # …and the merge gate the classifier feeds still trips on any `false` line.
  _mo=1; grep -q '^false ' "$_tt/out" && _mo=0
  [ "$_mo" = 0 ] || fail "R42: a non-Codex/truncated thread did not set merge_ok=0"
  pass "R42b a thread with unread comments is not Codex-only ⇒ needs-human, nothing resolved"
}

test_body_failed_enumeration_never_merges() {         # R42 (fail-closed enumeration)
  # An enumeration that ERRORS prints nothing, which is byte-identical to "no unresolved
  # threads". If the body ignores the exit status and starts from merge_ok=1, a transient
  # API/auth/pagination failure authorizes a merge over review feedback nobody read.
  need_body "R42: the body does not test the enumeration's exit status" \
    'if ! unresolved=$(gh api graphql'
  need_body "R42: merge_ok no longer starts fail-closed at 0" \
    'merge_ok=0            # fail closed'
  need_body "R42: the body does not state that a failed enumeration is not an empty one" \
    'An enumeration you could not finish is not an empty enumeration.'
  # Run the body's OWN snippet (extracted verbatim from its fenced block) against a stub
  # `gh`, so this locks the shipped shell and not a paraphrase of it. Twice, with and
  # without `set -e`: the guard must not depend on the reader's shell options.
  _fe="$T/enum"; mkdir -p "$_fe"
  awk '/^```bash$/                 { buf=""; inblk=1; next }
       inblk && /^```$/            { if (buf ~ /unresolved=\$\(gh api graphql/) {
                                       printf "%s", buf; exit } inblk=0; next }
       inblk                       { buf = buf $0 "\n" }' "$BODY" > "$_fe/snippet.sh"
  grep -q 'gh api graphql' "$_fe/snippet.sh" \
    || fail "R42: could not extract the thread-enumeration snippet from the body"
  cat > "$_fe/harness.sh" <<'SH'
gh() {
  printf '%s\n' "$*" >> "$GH_LOG"
  [ "${GH_MODE:-fail}" = "fail" ] || return 0     # ok: a PR with zero unresolved threads
  echo "gh: HTTP 502 Bad Gateway" >&2; return 1   # transient enumeration failure
}
owner=o; repo=r; pr_number=1
. "$SNIPPET"
echo "merge_ok=${merge_ok:-unset}"
SH
  for _opt in '' '-e'; do
    GH_LOG="$_fe/calls" GH_MODE=fail SNIPPET="$_fe/snippet.sh" \
      sh $_opt -u "$_fe/harness.sh" > "$_fe/out" 2>"$_fe/err" \
      || fail "R42: the enumeration snippet aborted under 'sh $_opt -u' instead of failing closed"
    grep -qxF 'merge_ok=0' "$_fe/out" \
      || fail "R42: a FAILED enumeration authorized the merge under 'sh $_opt -u' ($(cat "$_fe/out"))"
    grep -q 'resolveReviewThread' "$_fe/calls" \
      && fail "R42: a failed enumeration still tried to resolve a thread"
    rm -f "$_fe/calls"
  done
  # …and the other side of the distinction: a SUCCESSFUL enumeration returning zero
  # unresolved threads is clean and still merges, so the guard is not a blanket stop.
  GH_LOG="$_fe/calls" GH_MODE=empty SNIPPET="$_fe/snippet.sh" \
    sh -u "$_fe/harness.sh" > "$_fe/out" 2>/dev/null \
    || fail "R42: the snippet failed on a clean, successful enumeration"
  grep -qxF 'merge_ok=1' "$_fe/out" \
    || fail "R42: zero unresolved threads must stay mergeable ($(cat "$_fe/out"))"
  pass "R42c a review-thread enumeration failure fails closed ⇒ needs-human, nothing merged"
}

test_body_failed_resolve_never_merges() {             # R42 (fail-closed resolve mutation)
  # The query side is guarded; so is the MUTATION side. A `resolveReviewThread` that fails
  # (transient 5xx, a token without write access) leaves Codex feedback unresolved, and if
  # its status is ignored the auto-merge path still merges — whenever branch protection
  # does not independently block it. `merge_ok` must therefore be raised only after EVERY
  # requested mutation succeeded. Note the trap this guards against: `... | while read`
  # runs in a SUBSHELL, so a flag cleared inside a piped loop never reaches the merge test.
  need_body "R42: the body does not check the resolve mutation's status" \
    '-f id="$tid" >/dev/null || resolve_ok=0'
  need_body "R42: merge_ok is no longer raised behind the all-resolved test" \
    'if [ "$resolve_ok" = 1 ]; then'
  need_body "R42: the body does not state that a failed resolve is not a resolve" \
    'A resolve you could not complete is not a resolve.'
  grep -qF 'printf '"'"'%s\n'"'"' "$unresolved" | while read' "$BODY" \
    && fail "R42: the resolve loop pipes into \`while\` again — its flag dies in the subshell"
  # Execute the body's OWN snippet (same extraction as R42c) against a stub `gh` whose
  # enumeration succeeds with two Codex-only threads and whose mutation fails. Twice, with
  # and without `set -e`, since the guard must not depend on the reader's shell options.
  _fr="$T/resolve"; mkdir -p "$_fr"
  awk '/^```bash$/                 { buf=""; inblk=1; next }
       inblk && /^```$/            { if (buf ~ /unresolved=\$\(gh api graphql/) {
                                       printf "%s", buf; exit } inblk=0; next }
       inblk                       { buf = buf $0 "\n" }' "$BODY" > "$_fr/snippet.sh"
  grep -q 'resolveReviewThread' "$_fr/snippet.sh" \
    || fail "R42: could not extract the thread-resolve snippet from the body"
  cat > "$_fr/harness.sh" <<'SH'
gh() {
  printf '%s\n' "$*" >> "$GH_LOG"
  case "$*" in
    *resolveReviewThread*)                          # the mutation
      [ "${RESOLVE_MODE:-ok}" = "ok" ] && return 0
      echo "gh: HTTP 502 Bad Gateway" >&2; return 1 ;;
    *) printf 'true T_codex_1\ntrue T_codex_2\n' ;; # the enumeration: two Codex-only threads
  esac
}
owner=o; repo=r; pr_number=1
. "$SNIPPET"
echo "merge_ok=${merge_ok:-unset}"
SH
  for _opt in '' '-e'; do
    RESOLVE_MODE=fail GH_LOG="$_fr/calls" SNIPPET="$_fr/snippet.sh" \
      sh $_opt -u "$_fr/harness.sh" > "$_fr/out" 2>"$_fr/err" \
      || fail "R42: the resolve snippet aborted under 'sh $_opt -u' instead of failing closed"
    grep -qxF 'merge_ok=0' "$_fr/out" \
      || fail "R42: a FAILED resolve authorized the merge under 'sh $_opt -u' ($(cat "$_fr/out"))"
    rm -f "$_fr/calls" "$_fr/out"
    # …and the all-succeed path still merges, so the guard is not a blanket stop.
    RESOLVE_MODE=ok GH_LOG="$_fr/calls" SNIPPET="$_fr/snippet.sh" \
      sh $_opt -u "$_fr/harness.sh" > "$_fr/out" 2>/dev/null \
      || fail "R42: the snippet failed under 'sh $_opt -u' when every resolve succeeded"
    grep -qxF 'merge_ok=1' "$_fr/out" \
      || fail "R42: fully resolved Codex threads must stay mergeable ($(cat "$_fr/out"))"
    [ "$(grep -c 'resolveReviewThread' "$_fr/calls")" = 2 ] \
      || fail "R42: the loop did not request a mutation for each unresolved Codex thread"
    rm -f "$_fr/calls" "$_fr/out"
  done
  pass "R42d a failed resolveReviewThread fails closed ⇒ needs-human, nothing merged"
}

test_body_auto_merge_path() {                         # R43
  need_body "R43: body does not resolve Codex threads via GraphQL" 'resolveReviewThread'
  need_body "R43: body does not merge" 'gh pr merge'
  need_body "R43: body does not honor the configured strategy" 'merge_strategy'
  need_body "R43: body does not delete the remote branch in the same call" '--delete-branch'
  need_body "R43: body does not gate the merge on auto_merge" 'pr_loop.auto_merge'
  pass "R43 auto_merge + green + Codex-only threads ⇒ resolve then merge with the strategy"
}

test_body_squash_prep_cannot_hang() {                 # R43 (squash path)
  # PREMISE, proven offline: wfc_evaluate resolves on three signals only (fresh inline
  # findings on head, a fresh `Reviewed commit <sha>` banner, a Codex +1 on the trigger).
  # A raw-text reply to an `@codex summarize` request matches NONE of them, so a body that
  # polled for one would run to the ceiling, exit 2 and land in needs-human — with
  # squash-message.txt never written and `merge_strategy: squash` unable to reach its
  # merge command. Lock the premise, then lock the body that no longer depends on it.
  if have_jq; then
    _f="$(mk_fixture summarize-reply)"
    printf '[{"user":{"login":"chatgpt-codex-connector[bot]"},"created_at":"2026-06-02T00:00:00Z","body":"feat: vendor the review loop\\n\\nA high-signal squash message with no banner text in it."}]\n' \
      > "$_f/issue-comments.json"
    [ "$(eval_fixture "$_f")" = 1 ] \
      || fail "R43: a raw-text Codex summary now resolves the watcher — this premise changed"
  else
    skip "test_body_squash_prep_cannot_hang premise (jq not installed)"
  fi
  # The body may NAME `@codex summarize` (it explains why that round-trip was dropped);
  # what it must never do again is POST one and wait for the reply.
  grep -qF 'gh pr comment "$pr_number" --body "@codex summarize' "$BODY" \
    && fail "R43: the body still posts an @codex summarize request the watcher cannot detect"
  need_body "R43: body does not compose the squash message locally" \
    'Compose the message locally'
  need_body "R43: body does not forbid asking Codex for the squash message" \
    'never ask Codex for it'
  need_body "R43: body does not write the squash message itself" 'squash-message.txt'
  need_body "R43: the squash merge is not guarded on a non-empty message" 'if [ -s "$msg" ]'
  need_body "R43: the squash merge has no default-body fallback" \
    'gh pr merge "$pr_number" --squash --delete-branch && merged=1'
  pass "R43 squash prep composes the message locally and degrades to the default body"
}

test_body_auto_merge_false_stops() {                  # R44
  need_body "R44: body does not stop when auto_merge is false" \
    'stop after posting the all-gates-green summary'
  need_body "R44: body does not forbid merging when auto_merge is false" 'do not merge'
  pass "R44 auto_merge false stops after the green summary without merging"
}

test_body_terminal_return_values_agree() {            # R41/R42/R44 — cross-state contract
  # The two terminal states must not disagree about what the loop returns. A merge that
  # will not land IS the needs-human state and returns failure; the auto_merge:false
  # hand-back is a completed loop and returns success even though nothing merged.
  grep -qF -- 'Return success to the caller' "$BODY" \
    && fail "R41: a merge that would not land still tells the caller to return success"
  need_body "R41: the failed-merge fallback does not return failure" \
    'handover summary, and **return failure**'
  need_body "R41: the failed-merge fallback does not route to the needs-human state" \
    'needs-human terminal state below'
  need_body "R41: a merge that did not land is not barred from reporting success" \
    'is never reported as success'
  need_body "R44: the auto_merge-false hand-back does not return success" \
    'hand-back **completes** the loop: **return success**'
  need_body "R44: the auto_merge-false hand-back is not kept out of needs-human" \
    'never route it to needs-human'
  need_body "R42: the needs-human state does not claim every path returns failure" \
    '**Every path into this state returns failure**'
  # Placement: both statements must sit on the right side of the terminal-state heading,
  # so neither section can be read as contradicting the other.
  python3 - "$BODY" <<'PY' || fail "R41/R44: the terminal-state return values are misplaced"
import sys
s = open(sys.argv[1]).read()
ok_hdr, nh_hdr = s.index("### Ready to merge (success)"), s.index("### Needs-human (failure)")
ok_ret = s.index("hand-back **completes** the loop: **return success**")
fail_ret = s.index("handover summary, and **return failure**")
# the auto_merge:false success and the failed-merge failure are both stated in the
# success section (that is where the merge is attempted) ...
assert ok_hdr < ok_ret < nh_hdr, "auto_merge:false success is not in the success section"
assert ok_hdr < fail_ret < nh_hdr, "failed-merge failure is not in the success section"
# ... and nothing after the needs-human heading walks the failure back to a success.
assert "return success" not in s[nh_hdr:].lower(), "needs-human section returns success"
PY
  pass "R41/R42/R44 terminal states agree: a merge that will not land fails, the auto_merge-false hand-back succeeds"
}

test_body_cleanup_gated_on_merged() {                 # R45
  need_body "R45: body does not track whether the merge itself succeeded" 'merged=1'
  need_body "R45: body does not gate cleanup on the merge succeeding" \
    'only if the merge command itself succeeded'
  need_body "R45: body does not separate merge success from thread eligibility" \
    'never merely because thread eligibility was satisfied'
  pass "R45 local cleanup runs only after the merge command itself succeeded"
}

test_body_handover_summary() {                        # R46
  need_body "R46: body does not build a handover summary" 'Handover summary'
  need_body "R46: body does not persist it in the cache" 'handover-summary.md'
  need_body "R46: body does not post it on both terminal states" '**both** terminal states'
  need_body "R46: summary lacks the rounds-run line" 'Rounds run'
  need_body "R46: summary lacks worker totals" 'Worker totals'
  need_body "R46: summary lacks the round-by-round breakdown" 'Round-by-round'
  need_body "R46: summary lacks the resolved count" 'Blocking comments resolved'
  need_body "R46: summary lacks the cache path" 'Cache:'
  pass "R46 a handover summary is written to the cache and posted on both terminal states"
}

test_body_dry_run() {                                 # R47
  need_body "R47: body does not honor HARNESS_DRY_RUN" 'HARNESS_DRY_RUN=1'
  need_body "R47: body does not skip the real post under dry run" \
    'skip the real `gh pr comment` post'
  need_body "R47: body does not synthesize stub review data" 'synthesize'
  pass "R47 HARNESS_DRY_RUN=1 skips the real comment post and synthesizes stub data"
}

# ══ Documentation, prose and wiring (R48–R54) ═════════════════════════════════

test_prose_references_are_availability_phrased() {    # R48
  for _f in "$SRC/agents/orchestrator.md" "$SRC/CLAUDE.md" "$SRC/docs/WORKFLOW.md"; do
    grep -qF '/sdd-pr-loop' "$_f" || fail "R48: $_f does not name /sdd-pr-loop"
    # no bare `/pr-loop` reference survives (the token always carries the sdd- prefix)
    grep -oE '(^|[^-])/pr-loop' "$_f" | grep -q . \
      && fail "R48: $_f still carries a bare /pr-loop reference"
    grep -qiE 'is installed|installed only while' "$_f" \
      || fail "R48: $_f does not phrase /sdd-pr-loop by availability"
  done
  grep -qiF 'by hand' "$SRC/agents/orchestrator.md" \
    || fail "R48: orchestrator prose gives no alternative when the command is absent"
  grep -qiF 'by hand' "$SRC/CLAUDE.md" \
    || fail "R48: CLAUDE.md gives no alternative when the command is absent"
  pass "R48 the three prose references name /sdd-pr-loop and are availability-phrased"
}

test_source_layout_glue_present() {                   # R49
  [ -f "$SRC/.claude/commands/sdd-pr-loop.md" ] || fail "R49: source-layout command copy missing"
  [ -f "$SRC/.claude/agents/pr-fixer.md" ]      || fail "R49: source-layout pr-fixer shim missing"
  # source-layout paths resolve from the REPO ROOT, not from .harness/
  grep -qF 'tools/wait-for-codex.sh' "$SRC/.claude/commands/sdd-pr-loop.md" \
    || fail "R49: source-layout command does not reference tools/wait-for-codex.sh"
  grep -qF '.harness/tools/wait-for-codex.sh' "$SRC/.claude/commands/sdd-pr-loop.md" \
    && fail "R49: source-layout command resolves against .harness/ instead of the repo root"
  grep -qF 'agents/pr-fixer.md' "$SRC/.claude/agents/pr-fixer.md" \
    || fail "R49: source-layout shim does not point at agents/pr-fixer.md"
  grep -qF '.harness/agents/pr-fixer.md' "$SRC/.claude/agents/pr-fixer.md" \
    && fail "R49: source-layout shim resolves against .harness/ instead of the repo root"
  pass "R49 source-layout .claude/ glue exists and resolves from the repository root"
}

test_docs_document_pr_loop() {                        # R50
  for _d in "$SRC/README.md" "$SRC/docs/INSTALL.md" "$SRC/docs/WORKFLOW.md" "$SRC/docs/HARNESS.md"; do
    grep -qF '/sdd-pr-loop' "$_d" || fail "R50: $_d does not list /sdd-pr-loop"
    grep -qF 'Codex GitHub App' "$_d" || fail "R50: $_d does not state the Codex GitHub App precondition"
  done
  grep -qF 'pr_loop.enabled' "$SRC/docs/INSTALL.md" || fail "R50: INSTALL.md does not document the gate"
  # the OPT-IN default is a documented contract, not an implementation detail
  for _d in "$SRC/README.md" "$SRC/docs/INSTALL.md" "$SRC/docs/WORKFLOW.md" "$SRC/docs/HARNESS.md"; do
    grep -qiF 'opt-in' "$_d" || fail "R50: $_d does not state that pr_loop.enabled is opt-in"
  done
  grep -qF 'enabled: false' "$SRC/docs/INSTALL.md" \
    || fail "R50: INSTALL.md does not show the seeded opt-in default"
  for _k in auto_merge max_rounds blocking_severities merge_strategy; do
    grep -qF "$_k" "$SRC/docs/INSTALL.md" || fail "R50: INSTALL.md does not document pr_loop.$_k"
  done
  for _v in HARNESS_POLL_INTERVAL HARNESS_POLL_CEILING HARNESS_FIRST_RESPONSE HARNESS_DRY_RUN; do
    grep -qF "$_v" "$SRC/docs/INSTALL.md" || fail "R50: INSTALL.md does not document $_v"
  done
  grep -qF 'jq' "$SRC/docs/INSTALL.md" || fail "R50: INSTALL.md does not state the jq precondition"
  pass "R50 README + INSTALL + WORKFLOW + HARNESS document the command, gate, knobs, preconditions"
}

test_suite_is_wired_and_hygienic() {                  # R51
  grep -qF 'sh tests/test_pr_loop.sh' "$SRC/harness.config.yaml" \
    || fail "R51: this suite is not wired into verification.test_command"
  grep -q '^export CODEX_HOME=' "$SELF" || fail "R51: the suite does not sandbox CODEX_HOME"
  # every installer invocation in this file must carry a sandboxed CODEX_HOME
  if grep -n 'sh "$SRC/harness-install\.sh"' "$SELF" | grep -v 'CODEX_HOME' | grep -q .; then
    grep -n 'sh "$SRC/harness-install\.sh"' "$SELF" | grep -v 'CODEX_HOME' >&2
    fail "R51: an installer invocation does not sandbox CODEX_HOME"
  fi
  # no frozen VERSION literal anywhere in this suite (a released bump must not break it)
  if grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' "$SELF"; then
    grep -En '[0-9]+\.[0-9]+\.[0-9]+' "$SELF" >&2
    fail "R51: the suite freezes an exact version-shaped literal"
  fi
  # nothing is diffed against the default branch. The needles are SPLIT so this very
  # check never matches its own source line.
  _vcs="origin/""main|git ""diff|git ""show|git ""rev-parse"
  if grep -Eq "$_vcs" "$SELF"; then
    grep -En "$_vcs" "$SELF" >&2
    fail "R51: the suite compares a file against the default branch"
  fi
  pass "R51 suite is wired into verification.test_command and hygienic (no VERSION freeze, no main diff)"
}

test_init_has_no_new_dependency() {                   # R53
  # A PATH mirror of the real one with `gh` and `jq` removed: init.sh must still pass.
  _nb="$T/nodep-bin"; mkdir -p "$_nb"
  _oifs="$IFS"; IFS=:
  for _p in $PATH; do
    IFS="$_oifs"
    if [ -d "$_p" ]; then
      for _f in "$_p"/*; do
        if [ -f "$_f" ] || [ -L "$_f" ]; then
          _b="${_f##*/}"
          case "$_b" in gh|jq) continue ;; esac
          if [ ! -e "$_nb/$_b" ]; then ln -s "$_f" "$_nb/$_b" 2>/dev/null || true; fi
        fi
      done
    fi
    IFS=:
  done
  IFS="$_oifs"
  [ -e "$_nb/gh" ] && fail "R53 setup: gh leaked into the stripped PATH"
  [ -e "$_nb/jq" ] && fail "R53 setup: jq leaked into the stripped PATH"
  ( cd "$SRC" && PATH="$_nb" ./init.sh ) >/dev/null 2>"$T/.init.err" \
    || { cat "$T/.init.err" >&2; fail "R53: init.sh failed with neither gh nor jq on PATH"; }
  grep -qE '\bgh\b|\bjq\b' "$SRC/init.sh" && fail "R53: init.sh gained a gh/jq gate"
  pass "R53 init.sh passes with neither gh nor jq on PATH (no new hard dependency)"
}

test_version_has_changelog_entry() {                  # R54
  _v="$(cat "$SRC/VERSION")"
  printf '%s' "$_v" | grep -qE '^[0-9]+[.][0-9]+[.][0-9]+$' \
    || fail "R54: VERSION does not parse as X.Y.Z"
  grep -qF "## [$_v]" "$SRC/CHANGELOG.md" \
    || fail "R54: CHANGELOG.md has no heading for the current VERSION"
  pass "R54 VERSION parses and CHANGELOG.md carries a heading for exactly that value"
}

# ── run ───────────────────────────────────────────────────────────────────────
test_gate_off_still_reclaims_global_codex_prompt
test_command_mirrored_to_all_frontends
test_gate_off_stamps_nothing
test_deselect_removes_pr_loop_glue
test_gate_flip_off_reclaims
test_edited_copy_left_in_place_and_warns
test_reclaim_preserves_user_files_and_prunes
test_gate_off_then_on_restores
test_shared_prompt_survives_another_targets_gate_off
test_shared_prompt_reclaimed_when_last_owner_opts_out
test_dead_owner_never_pins_the_shared_prompt
test_unknown_ownership_always_keeps_the_shared_prompt

test_canonical_pr_fixer_role
test_claude_pr_fixer_shim
test_opencode_pr_fixer_agent_file
test_opencode_json_unaffected_by_pr_loop
test_antigravity_pr_fixer_persona
test_no_codex_gemini_pr_fixer_artifact

test_pr_loop_block_seeded
test_pr_loop_block_migrated_idempotent
test_seeded_and_migrated_block_identical
test_absent_block_defaults_to_disabled
test_absent_enabled_key_resolves_off
test_pr_loop_key_is_section_scoped
test_no_mco_tokens_in_body
test_env_overrides_config

test_watcher_installed_executable_posix
test_preflight_success
test_preflight_failure_matrix
test_wait_mode_exit_codes
test_round_dir_sources_written
test_unresolvable_trigger_ts_exits_4
test_timeout_exits_2_not_clean
test_first_response_window_fails_fast
test_first_response_probe_disabled
test_poll_env_knobs_honored
test_non_positive_interval_cannot_spin
test_stale_reanchored_thread_is_not_a_finding
test_clean_via_review_banner
test_clean_via_issue_comment_banner
test_clean_via_thumbs_reaction
test_bot_login_exact_match
test_bot_login_lookalike_cannot_signal_clean
test_evaluate_is_offline
test_failed_findings_fetch_is_never_clean
test_cache_root_and_gitignore

test_body_preflight_before_trigger
test_body_trigger_id_from_url
test_body_background_watcher_and_exit_branching
test_body_classification_rules
test_body_unreadable_head_fails_closed
test_body_stall_detection
test_body_round_branching
test_body_never_resolves_human_threads
test_body_truncated_thread_is_not_codex_only
test_body_failed_enumeration_never_merges
test_body_failed_resolve_never_merges
test_body_auto_merge_path
test_body_squash_prep_cannot_hang
test_body_auto_merge_false_stops
test_body_terminal_return_values_agree
test_body_cleanup_gated_on_merged
test_body_handover_summary
test_body_dry_run

test_prose_references_are_availability_phrased
test_source_layout_glue_present
test_docs_document_pr_loop
test_suite_is_wired_and_hygienic
test_init_has_no_new_dependency
test_version_has_changelog_entry

# ── E21-F03: convergence trend — "split, don't re-review" at the cap ─────────────────────
# The cap already stops the loop; what it never said is what the human should CONCLUDE. The
# observed response is to post `@codex review` again — twelve times on the PR that motivated
# this. These assertions drive the real tool against fixture round dirs, because the verdict
# is the whole feature: a grep over the script cannot tell a converging series from a flat one.

mk_rounds() { # mk_rounds <cache-dir> <count>... — one round dir per count, N findings each
  _c="$1"; shift; _i=1
  for _n in "$@"; do
    mkdir -p "$_c/round-$_i"
    _j=0; printf '[' > "$_c/round-$_i/blocking.json"
    while [ "$_j" -lt "$_n" ]; do
      [ "$_j" -eq 0 ] || printf ',' >> "$_c/round-$_i/blocking.json"
      printf '{"path":"src/runtime.ts","id":%d}' "$_j" >> "$_c/round-$_i/blocking.json"
      _j=$((_j + 1))
    done
    printf ']' >> "$_c/round-$_i/blocking.json"
    _i=$((_i + 1))
  done
}
verdict_of() { sh "$SRC/tools/pr-round-trend.sh" --cache "$1" --format json | sed -n 's/.*"verdict":"\([a-z-]*\)".*/\1/p'; }

test_round_trend_verdicts() {
  [ -x "$SRC/tools/pr-round-trend.sh" ] || fail "E21-F03: tools/pr-round-trend.sh missing or not executable"
  if ! command -v jq >/dev/null 2>&1; then skip "round_trend_verdicts (jq not installed)"; return 0; fi

  # The real PR #76 shape: never decays. Must read as non-converging.
  _f="$T/trend-flat"; mkdir -p "$_f"; mk_rounds "$_f" 1 3 1 2 1 3
  [ "$(verdict_of "$_f")" = "non-converging" ] \
    || fail "E21-F03: a flat series (1 3 1 2 1 3) read as $(verdict_of "$_f"), expected non-converging"

  # A converging PR must NOT be told to split — this is the assertion that keeps the rule
  # from degenerating into "any PR with several rounds is too big".
  _c="$T/trend-conv"; mkdir -p "$_c"; mk_rounds "$_c" 3 1 0
  [ "$(verdict_of "$_c")" = "converging" ] \
    || fail "E21-F03: a converging series (3 1 0) read as $(verdict_of "$_c"), expected converging"

  # Too little evidence is its own answer, not a default to either verdict.
  _s="$T/trend-short"; mkdir -p "$_s"; mk_rounds "$_s" 2 1
  [ "$(verdict_of "$_s")" = "insufficient" ] \
    || fail "E21-F03: 2 rounds read as $(verdict_of "$_s"), expected insufficient"

  # A round that aborted before classifying has NO blocking.json. Counting its absence as
  # zero would fake a convergence that never happened.
  _a="$T/trend-abort"; mkdir -p "$_a"; mk_rounds "$_a" 1 2 3; mkdir -p "$_a/round-4"
  [ "$(verdict_of "$_a")" = "non-converging" ] \
    || fail "E21-F03: an aborted round without blocking.json was counted as a zero finding round"

  # 12-round ordering. A shell glob is lexicographic, so round-10..12 sort BEFORE round-2 and
  # the last-3 window would trend rounds 7-9 while calling them the latest. Here rounds 1-9
  # are flat and 10-12 decay to zero: with the numeric sort the verdict is `converging`; with
  # the glob order it inverts and tells the human to keep reviewing the wrong evidence.
  _o="$T/trend-order"; mkdir -p "$_o"; mk_rounds "$_o" 1 3 1 2 1 3 1 2 2 1 1 0
  [ "$(verdict_of "$_o")" = "converging" ] \
    || fail "E21-F03: 12 rounds ending 1,1,0 read as $(verdict_of "$_o") — round dirs are not sorted numerically"
  sh "$SRC/tools/pr-round-trend.sh" --cache "$_o" | grep -q 'round *1 *2 *3 *4 *5 *6 *7 *8 *9 *10 *11 *12' \
    || fail "E21-F03: the printed round series is not in numeric order"

  # Advisory: exit 0 at every verdict, including the one that says split.
  sh "$SRC/tools/pr-round-trend.sh" --cache "$_f" >/dev/null \
    || fail "E21-F03: the tool exited non-zero on a non-converging verdict — it must never block"
  pass "E21-F03 round_trend_verdicts: flat ⇒ non-converging, decaying ⇒ converging, exit 0 always"
}

test_round_trend_names_the_seams() {
  if ! command -v jq >/dev/null 2>&1; then skip "round_trend_names_the_seams (jq not installed)"; return 0; fi
  _f="$T/trend-seams"; mkdir -p "$_f"; mk_rounds "$_f" 1 3 1 2 1 3
  _out="$(sh "$SRC/tools/pr-round-trend.sh" --cache "$_f")"
  printf '%s' "$_out" | grep -qi 'SPLIT THIS PR' \
    || fail "E21-F03: a non-converging verdict does not tell the human to split the PR"
  printf '%s' "$_out" | grep -qF 'src/runtime.ts' \
    || fail "E21-F03: the non-converging report does not name where findings concentrate"
  printf '%s' "$(sh "$SRC/tools/pr-round-trend.sh" --cache "$T/trend-conv")" | grep -qi 'SPLIT THIS PR' \
    && fail "E21-F03: a CONVERGING verdict told the human to split — the advice must be earned" || :
  pass "E21-F03 round_trend_names_the_seams: split advice only when non-converging, with seams"
}

test_round_trend_usage_errors() {
  sh "$SRC/tools/pr-round-trend.sh" --cache "$T/no-such-cache" >/dev/null 2>&1 && _rc=0 || _rc=$?
  [ "$_rc" = "4" ] || fail "E21-F03: a missing cache dir exited $_rc, expected 4"
  sh "$SRC/tools/pr-round-trend.sh" >/dev/null 2>&1 && _rc=0 || _rc=$?
  [ "$_rc" = "4" ] || fail "E21-F03: a missing --cache exited $_rc, expected 4"
  pass "E21-F03 round_trend_usage_errors: exit 4 only for usage, never for a verdict"
}

test_installed_command_carries_the_trend() {
  _t="$T/trend-install"
  install_on "$_t" --agents=claude
  _cmd="$_t/.claude/commands/sdd-pr-loop.md"
  [ -f "$_cmd" ] || fail "E21-F03: /sdd-pr-loop not installed with the gate on"
  grep -qF 'pr-round-trend.sh' "$_cmd" \
    || fail "E21-F03: the INSTALLED /sdd-pr-loop does not run the convergence trend (source-layout copy edited but not the installer heredoc)"
  grep -qi 'split the PR\|split this PR' "$_cmd" \
    || fail "E21-F03: the installed command never tells the human to split at a non-converging cap"
  grep -qi 'advisory and it never blocks\|never blocks' "$_cmd" \
    || fail "E21-F03: the installed command does not state that the trend never blocks"
  [ -x "$_t/.harness/tools/pr-round-trend.sh" ] \
    || fail "E21-F03: installed tools/pr-round-trend.sh missing or not executable"
  pass "E21-F03 installed_command_carries_the_trend"
}

# ── E21-F04: stacked-PR lane — never merge a child ahead of its parent ───────────────────
# Merging increment B before increment A is a correctness bug, not a race, and auto_merge
# would walk into it: the existing gates ask "checks green, threads resolved", never "is my
# base branch itself still an open PR". Driven offline against fixture JSON so the guard is
# testable without gh, a network, or a real stack.

test_stack_guard_verdicts() {
  [ -x "$SRC/tools/pr-stack-guard.sh" ] || fail "E21-F04: tools/pr-stack-guard.sh missing or not executable"
  if ! command -v jq >/dev/null 2>&1; then skip "stack_guard_verdicts (jq not installed)"; return 0; fi
  _d="$T/stack"; mkdir -p "$_d"
  printf '{"baseRefName":"main"}\n'             > "$_d/base-main.json"
  printf '{"baseRefName":"feat/wave-a"}\n'      > "$_d/base-stacked.json"
  printf '{"headRefOid":"abc"}\n'               > "$_d/base-missing.json"
  printf '[{"number":80,"headRefName":"feat/wave-a"}]\n' > "$_d/open-parent.json"
  printf '[]\n'                                 > "$_d/open-none.json"

  sh "$SRC/tools/pr-stack-guard.sh" evaluate "$_d/base-main.json" "$_d/open-parent.json" >/dev/null 2>&1 \
    || fail "E21-F04: a PR based on the default branch was not cleared to merge"

  sh "$SRC/tools/pr-stack-guard.sh" evaluate "$_d/base-stacked.json" "$_d/open-parent.json" >/dev/null 2>&1 && _rc=0 || _rc=$?
  [ "$_rc" = "6" ] \
    || fail "E21-F04: a child whose base is an OPEN parent PR exited $_rc, expected 6 (would have merged out of order)"

  # A non-default base that NO open PR owns is not proof of safety: the parent may have
  # merged without GitHub having retargeted the child yet (or without deleting its branch at
  # all), in which case merging lands the child in an already-merged branch and its commits
  # never reach the default branch — while the loop reports success. Must keep waiting.
  sh "$SRC/tools/pr-stack-guard.sh" evaluate "$_d/base-stacked.json" "$_d/open-none.json" >/dev/null 2>&1 && _rc=0 || _rc=$?
  [ "$_rc" = "6" ] \
    || fail "E21-F04: a non-default base with no open PR owning it exited $_rc, expected 6 (un-retargeted child would merge into a dead branch)"

  # Fail CLOSED: a base we could not read is NOT the default branch. Treating it as one is
  # exactly how a guard meant to prevent out-of-order merges permits one.
  sh "$SRC/tools/pr-stack-guard.sh" evaluate "$_d/base-missing.json" "$_d/open-parent.json" >/dev/null 2>&1 && _rc=0 || _rc=$?
  [ "$_rc" = "4" ] || fail "E21-F04: an unreadable baseRefName exited $_rc, expected 4 (must fail closed)"
  pass "E21-F04 stack_guard_verdicts: parent-open ⇒ 6, default base ⇒ 0, unreadable base ⇒ 4"
}

test_stack_guard_exit6_is_not_a_failure_state() {
  if ! command -v jq >/dev/null 2>&1; then skip "stack_guard_exit6_is_not_a_failure_state (jq not installed)"; return 0; fi
  # Exit 6 must be distinct from the loop's existing failure codes, or a healthy child PR
  # gets labelled needs-human on every round while its parent is still in review.
  for _bad in 1 2 3 4 5; do
    [ "$_bad" != "6" ] || fail "E21-F04: exit 6 collides with an existing pr-loop exit code"
  done
  _out="$(sh "$SRC/tools/pr-stack-guard.sh" evaluate "$T/stack/base-stacked.json" "$T/stack/open-parent.json" 2>&1 || true)"
  printf '%s' "$_out" | grep -qF '#80' \
    || fail "E21-F04: the stacked verdict does not name the parent PR number to wait on"
  pass "E21-F04 stack_guard_exit6_is_not_a_failure_state: names the parent, distinct exit code"
}

test_installed_command_carries_the_stack_guard() {
  _t="$T/stack-install"
  install_on "$_t" --agents=claude
  _cmd="$_t/.claude/commands/sdd-pr-loop.md"
  grep -qF 'pr-stack-guard.sh' "$_cmd" \
    || fail "E21-F04: the INSTALLED /sdd-pr-loop does not run the stack guard (installer heredoc not updated)"
  grep -qi 'merge the parent first\|never merge a child' "$_cmd" \
    || fail "E21-F04: the installed command does not state the merge-order rule"
  grep -qi 'retarget' "$_cmd" \
    || fail "E21-F04: the installed command does not warn that a parent-merge retarget is not a review event"
  [ -x "$_t/.harness/tools/pr-stack-guard.sh" ] \
    || fail "E21-F04: installed tools/pr-stack-guard.sh missing or not executable"
  grep -qi 'stacked' "$_t/.harness/docs/WORKFLOW.md" \
    || fail "E21-F04: installed docs/WORKFLOW.md does not document the stacked-PR lane"
  pass "E21-F04 installed_command_carries_the_stack_guard"
}

test_round_trend_verdicts
test_round_trend_names_the_seams
test_round_trend_usage_errors
test_installed_command_carries_the_trend
test_stack_guard_verdicts
test_stack_guard_exit6_is_not_a_failure_state
test_installed_command_carries_the_stack_guard

echo "All pr-loop tests passed."
