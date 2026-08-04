#!/bin/sh
# test_escalation.sh — E17-F03 deterministic escalation to `builder-heavy`.
#
# The RULE is a tool (tools/builder-role.sh), so most of this suite is real behavioral
# coverage rather than the role-content-assertion pattern a prose-only feature is stuck with.
# What remains prose — the Orchestrator's call site and the telemetry record shape — is
# grepped, and the test contract names that as a gap rather than dressing it up as coverage.
#
# Zero dependencies: POSIX sh + grep + awk. Self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

TOOL="$SRC/tools/builder-role.sh"
[ -f "$TOOL" ] || fail "setup: tools/builder-role.sh does not exist"

# Escalation only fires when models.builder-heavy has a tier (R12) — escalating to an
# untiered role resolves to the SESSION model, which on a target that configured
# models.builder is a DOWNGRADE. So the default config for these helpers is an ARMED one;
# `--config` passed by a caller comes later on the command line and wins (last flag wins),
# which is how the unarmed cases below opt out.
ARMED="$T/armed.yaml"
printf 'models:\n  default: inherit\n  builder: standard\n  builder-heavy: reasoning\nescalation:\n  after_rejections: 2\n' > "$ARMED"

# role <complexity> <round> [extra args…] — stdout only.
role() { _c="$1"; _r="$2"; shift 2; sh "$TOOL" "$_c" "$_r" --config "$ARMED" "$@" 2>/dev/null; }
# err <complexity> <round> [extra args…] — stderr only.
err()  { _c="$1"; _r="$2"; shift 2; sh "$TOOL" "$_c" "$_r" --config "$ARMED" "$@" 2>&1 >/dev/null; }
# rc <complexity> <round> [extra args…] — exit status only.
# The `|| _s=$?` is load-bearing: this suite runs under `set -e`, so a bare invocation that
# exits non-zero would kill the command substitution before it could echo anything, and the
# caller would compare against an empty string instead of the status it asked for.
rc()   { _c="$1"; _r="$2"; shift 2; _s=0; sh "$TOOL" "$_c" "$_r" --config "$ARMED" "$@" >/dev/null 2>&1 || _s=$?; echo "$_s"; }

# mkcfg <name> <after_rejections> — a config carrying only the escalation block.
mkcfg() {
  _p="$T/$1.yaml"
  printf 'models:\n  builder-heavy: reasoning\nescalation:\n  after_rejections: %s\n' "$2" > "$_p"
  printf '%s\n' "$_p"
}
# mkcfg_unarmed <name> — a config whose heavy role has NO tier: the shipped default, and the
# shape of Codex #3716706727's target once it set models.builder.
mkcfg_unarmed() {
  _p="$T/$1.yaml"
  printf 'models:\n  default: inherit\n  builder: standard\n  builder-heavy: inherit\nescalation:\n  after_rejections: 2\n' > "$_p"
  printf '%s\n' "$_p"
}

# ── R1: the vocabulary and its default ──────────────────────────────────────────
vocabulary_and_default() {
  [ "$(role complex 1)" = builder-heavy ] || fail "R1: complex at round 1 did not select builder-heavy"
  [ "$(role standard 1)" = builder ]      || fail "R1: standard at round 1 did not select builder"
  [ "$(role '' 1)" = builder ]            || fail "R1: an absent tag did not default to standard"
  # Absent must be SILENT — a spec written before this feature must not start warning.
  [ -z "$(err '' 1)" ] || fail "R1/R7: an absent tag produced output on stderr"
  [ -z "$(err standard 1)" ] || fail "R1: an explicit 'standard' produced output on stderr"
  pass "complex ⇒ heavy, standard/absent ⇒ builder, absent is silent (R1)"
}

# ── R2: an out-of-vocabulary value is coerced, reported, and never fatal ────────
unknown_value_is_coerced_and_reported() {
  [ "$(role bogus 1)" = builder ] || fail "R2: an unrecognized value did not resolve to standard"
  [ -n "$(err bogus 1)" ]         || fail "R2: an unrecognized value produced no advisory"
  printf '%s' "$(err bogus 1)" | grep -q 'bogus' \
    || fail "R2: the advisory does not name the offending value"
  [ "$(rc bogus 1)" = 0 ] || fail "R2: an unrecognized value failed the build (exit $(rc bogus 1))"
  # It must be coerced to STANDARD, not to complex — the safe direction.
  [ "$(role bogus 1)" != builder-heavy ] || fail "R2: an unrecognized value escalated"
  pass "an out-of-vocabulary complexity coerces to standard, reports, exits 0 (R2)"
}

# ── R3: the truth table, with a distinct-answers guard ──────────────────────────
the_truth_table() {
  _seen_std=0; _seen_heavy=0
  for _c in '' standard complex; do
    for _r in 1 2 3 7; do
      _got="$(role "$_c" "$_r")"
      case "$_got" in
        builder)       _seen_std=1 ;;
        builder-heavy) _seen_heavy=1 ;;
        *) fail "R3: unexpected answer '$_got' for complexity='$_c' round=$_r" ;;
      esac
      # The expected value, derived independently of the tool: heavy iff complex or round>2.
      if [ "$_c" = complex ] || [ "$_r" -gt 2 ]; then _want=builder-heavy; else _want=builder; fi
      [ "$_got" = "$_want" ] \
        || fail "R3: complexity='$_c' round=$_r gave '$_got', expected '$_want'"
    done
  done
  # A tool that ignored its arguments and always printed `builder` would satisfy most cells.
  # Require BOTH answers to have been observed, or the table proves nothing.
  [ "$_seen_std" = 1 ] && [ "$_seen_heavy" = 1 ] \
    || fail "R3: the table observed only one distinct answer — a constant implementation would pass"
  pass "the (complexity × round) truth table holds and yields both distinct answers (R3)"
}

# ── R3: the off-by-one boundary, from both sides ────────────────────────────────
threshold_boundary() {
  # `round > n` and `round >= n` differ by exactly one rejection; sampling only 1 and 9
  # would not tell them apart. Pin n=2 from both sides.
  [ "$(role '' 2)" = builder ] \
    || fail "R3: round 2 escalated — the threshold is off by one (>= where > was meant)"
  [ "$(role '' 3)" = builder-heavy ] \
    || fail "R3: round 3 did not escalate at the default threshold of 2"
  # And at an explicit non-default threshold, so the boundary is not an artifact of the default.
  _c5="$(mkcfg t5 5)"
  [ "$(role '' 5 --config "$_c5")" = builder ]       || fail "R3: round 5 escalated at threshold 5"
  [ "$(role '' 6 --config "$_c5")" = builder-heavy ] || fail "R3: round 6 did not escalate at threshold 5"
  pass "the round > threshold boundary holds from both sides at n=2 and n=5 (R3)"
}

# ── R4: the rule is pure ────────────────────────────────────────────────────────
the_rule_is_pure() {
  _a="$(role complex 4)"; _b="$(role complex 4)"; _c="$(role complex 4)"
  [ "$_a" = "$_b" ] && [ "$_b" = "$_c" ] || fail "R4: repeated identical invocations disagreed"
  # It must not consult the repository it happens to be run from: same answer from a
  # directory with no harness, no progress/, no git.
  _empty="$T/empty"; mkdir -p "$_empty"
  _out="$(cd "$_empty" && sh "$TOOL" '' 3 --config "$ARMED" 2>/dev/null)"
  [ "$_out" = builder-heavy ] || fail "R4: the answer changed when run from an unrelated directory"
  # And it must not read the spec body or history. Assert on EXECUTABLE content only:
  # the tool's own comments necessarily name progress/history.md to explain that it never
  # reads it, so grepping the raw file would fail on its documentation. Strip whole-line
  # comments first, then look for an actual reference.
  sed -e 's/^[[:space:]]*#.*$//' "$TOOL" \
    | grep -qE 'progress/|history\.md|(^|[^a-zA-Z])git([^a-zA-Z]|$)' \
    && fail "R4: the tool's code references progress/, history.md or git — it is not pure"
  pass "identical inputs yield identical answers; the tool reads no repo state (R4)"
}

# ── R5: no second source of truth ───────────────────────────────────────────────
no_second_source_of_truth() {
  # The round counter must stay where agents/orchestrator.md already defines it. This
  # feature may not add a status value or a TaskStore field to carry it.
  grep -q 'complexity' "$SRC/store/tasks.schema.json" \
    && fail "R5: complexity leaked into the TaskStore schema"
  grep -q 'after_rejections' "$SRC/store/tasks.schema.json" \
    && fail "R5: the escalation threshold leaked into the TaskStore schema"
  grep -q 'round' "$SRC/store/tasks.schema.json" \
    && fail "R5: a round counter leaked into the TaskStore schema"
  # The tool takes the round as an ARGUMENT — it never derives one.
  grep -q '<round>' "$SRC/agents/orchestrator.md" \
    || fail "R5: orchestrator.md does not pass the existing round to the tool"
  pass "no second counter, status value, or TaskStore field was introduced (R5)"
}

# ── R6: the config key is seeded on BOTH paths ──────────────────────────────────
config_seeded_in_both_paths() {
  _fresh="$T/fresh"; mkdir -p "$_fresh"
  CODEX_HOME="$T/ch1" sh "$SRC/harness-install.sh" --agents=claude "$_fresh" >/dev/null 2>&1 \
    || fail "R6: fresh install exited non-zero"
  grep -Eq '^escalation:[[:space:]]*(#.*)?$' "$_fresh/.harness/harness.config.yaml" \
    || fail "R6: a fresh install has no top-level escalation: block"
  grep -Eq '^  after_rejections: 2' "$_fresh/.harness/harness.config.yaml" \
    || fail "R6: a fresh install does not seed after_rejections: 2"

  # The UPGRADE path: strip the block and re-install. Seeding only the shipped config makes
  # a fresh target and an upgraded one diverge, and nothing else in the suite would notice —
  # this is the exact defect E17-F02's mutation battery caught one feature earlier.
  _up="$T/up"; mkdir -p "$_up"
  CODEX_HOME="$T/ch2" sh "$SRC/harness-install.sh" --agents=claude "$_up" >/dev/null 2>&1 \
    || fail "R6: upgrade-fixture install exited non-zero"
  _c="$_up/.harness/harness.config.yaml"
  awk '/^# Deterministic Builder escalation/ { drop=1 } !drop { print }' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  grep -Eq '^escalation:' "$_c" && fail "R6: setup — the escalation block was not stripped"
  CODEX_HOME="$T/ch2" sh "$SRC/harness-install.sh" --agents=claude "$_up" >/dev/null 2>&1 \
    || fail "R6: re-install after stripping exited non-zero"
  grep -Eq '^  after_rejections: 2' "$_c" \
    || fail "R6: migrate_config did not re-seed escalation.after_rejections"
  pass "escalation.after_rejections: 2 is seeded on both the fresh and the upgrade path (R6)"
}

# ── R6: 0 disables, and does not invert ─────────────────────────────────────────
zero_disables_not_always_escalates() {
  _c0="$(mkcfg t0 0)"
  # `round > 0` is true for EVERY round ≥ 1, so a naive implementation turns the operator's
  # off-switch into always-escalate. Check well past any plausible threshold.
  for _r in 1 2 3 99; do
    [ "$(role '' "$_r" --config "$_c0")" = builder ] \
      || fail "R6: threshold 0 escalated at round $_r — 0 must DISABLE, not invert"
  done
  # Paired control in the same run: at the default threshold those same high rounds DO
  # escalate, so "always standard" cannot pass this case either.
  _c2="$(mkcfg t2 2)"
  [ "$(role '' 99 --config "$_c2")" = builder-heavy ] \
    || fail "R6: control — round 99 at threshold 2 did not escalate, so the 0 case proves nothing"
  # `complexity: complex` remains a live route even with the round arm disabled.
  [ "$(role complex 1 --config "$_c0")" = builder-heavy ] \
    || fail "R6: threshold 0 also disabled the complexity route"
  pass "threshold 0 disables the round arm without inverting it; complex still routes (R6)"
}

# ── R7: an unconfigured target is standard and silent ───────────────────────────
unconfigured_is_silent_and_standard() {
  # No escalation: block at all — the shape of a config that predates this feature.
  _bare="$T/bare.yaml"; printf 'store:\n  tasks: local\n' > "$_bare"
  [ "$(role '' 1 --config "$_bare")" = builder ] \
    || fail "R7: a config with no escalation block did not route to builder"
  [ -z "$(err '' 1 --config "$_bare")" ] \
    || fail "R7: a config with no escalation block produced a warning"
  # A missing config FILE is the same story.
  [ "$(role '' 1 --config "$T/does-not-exist.yaml")" = builder ] \
    || fail "R7: a missing config did not route to builder"
  [ -z "$(err '' 1 --config "$T/does-not-exist.yaml")" ] \
    || fail "R7: a missing config produced a warning"
  # A bare config has no models: block either, so the heavy role has no tier and escalation
  # correctly declines (R12). The default THRESHOLD still applies — proven by arming the same
  # config's heavy role and watching round 3 escalate while round 2 does not.
  [ "$(role '' 3 --config "$_bare")" = builder ] \
    || fail "R7: an untiered heavy role escalated"
  _bare_armed="$T/bare-armed.yaml"
  printf 'store:\n  tasks: local\nmodels:\n  builder-heavy: reasoning\n' > "$_bare_armed"
  [ "$(role '' 3 --config "$_bare_armed")" = builder-heavy ] \
    || fail "R7: the default threshold did not apply when the escalation block is absent"
  [ "$(role '' 2 --config "$_bare_armed")" = builder ] \
    || fail "R7: the default threshold was not 2 when the escalation block is absent"
  pass "no escalation block ⇒ builder, silently, with the default still in force (R7)"
}

# ── R8: durable state only ──────────────────────────────────────────────────────
durable_state_only() {
  # The rule takes the round as an argument, so a feature whose earlier rounds ran in a
  # previous session resolves identically — there is no session memory to lose. Prove the
  # tool keeps none: same inputs, run from a directory with no progress/ and no git.
  _iso="$T/iso"; mkdir -p "$_iso"
  _first="$(cd "$_iso" && sh "$TOOL" '' 3 --config "$ARMED" 2>/dev/null)"
  _second="$(cd "$_iso" && sh "$TOOL" '' 3 --config "$ARMED" 2>/dev/null)"
  [ "$_first" = builder-heavy ] && [ "$_second" = builder-heavy ] \
    || fail "R8: a round-3 build did not escalate outside a harness tree"
  [ -d "$_iso/progress" ] && fail "R8: the tool created state next to itself"
  pass "the rule reads durable inputs only and keeps no session state (R8)"
}

# ── R9: delegate never escalates ────────────────────────────────────────────────
delegate_never_escalates() {
  # Asserting `delegate ⇒ builder` proves nothing unless the same inputs are REACHABLY
  # heavy. Establish that first, in this run.
  [ "$(role complex 99)" = builder-heavy ] \
    || fail "R9: control — complex/99 is not heavy under in-session, so the delegate case is vacuous"
  [ "$(role complex 99 --backend delegate)" = builder ] \
    || fail "R9: delegate escalated despite the executor choosing its own model"
  [ "$(role '' 99 --backend delegate)" = builder ] \
    || fail "R9: delegate escalated on the round arm"
  printf '%s' "$(err complex 99 --backend delegate)" | grep -qi 'inapplicable' \
    || fail "R9: delegate did not report escalation as inapplicable"
  [ "$(rc complex 99 --backend delegate)" = 0 ] \
    || fail "R9: the delegate path exited non-zero"
  # in-session is the default when --backend is omitted.
  [ "$(role complex 99 --backend in-session)" = builder-heavy ] \
    || fail "R9: an explicit in-session backend did not behave like the default"
  pass "delegate returns builder and reports inapplicable, over reachably-heavy inputs (R9)"
}

# ── R10/R11: the recorded choice (prose — see the contract's named gap) ─────────
prose_records_the_choice() {
  _o="$SRC/agents/orchestrator.md"
  grep -q 'builder-role.sh' "$_o" || fail "R10: orchestrator.md never calls builder-role.sh"
  grep -q 'builder-heavy round 3' "$_o" \
    || fail "R10: orchestrator.md shows no history line naming the role and the trigger"
  grep -qi 'never override the answer' "$_o" \
    || fail "R10: orchestrator.md does not forbid overriding the tool's answer"
  pass "orchestrator.md calls the tool, records role + trigger, forbids overriding it (R10)"
}

telemetry_contract_intact() {
  _o="$SRC/agents/orchestrator.md"
  grep -q '"phase":"builder","role":"builder-heavy"' "$_o" \
    || fail "R11: orchestrator.md does not show phase staying 'builder' with a separate role key"
  grep -qi 'Do not write .*phase.*builder-heavy' "$_o" \
    || fail "R11: orchestrator.md does not forbid phase: builder-heavy"
  # The reason it must not: PHASES is a whitelist and the round count reads builder/reviewer.
  _t="$SRC/tools/telemetry-report.py"
  grep -q 'PHASES = \["architect", "builder", "reviewer", "scout", "inception", "slice-dispatch"\]' "$_t" \
    || fail "R11: the PHASES whitelist changed — re-check whether phase: builder-heavy would now be dropped"
  grep -q 'p\["phase"\] in ("builder", "reviewer")' "$_t" \
    || fail "R11: the max-round computation changed — re-check the under-reporting hazard"
  pass "telemetry keeps phase=builder with a separate role key; the whitelist is unchanged (R11)"
}

# ── R12: escalation is armed only by a configured heavy tier ────────────────────
# The regression this closes: with `models.builder: standard` and `models.builder-heavy:
# inherit` (the shipped default), escalating spawns a role with NO model key — so the build
# abandons the operator's configured Builder model for the session default, exactly when it
# was struggling. A downgrade wearing an escalation's name. (Codex #3716706727.)
escalation_requires_a_configured_heavy_tier() {
  _un="$(mkcfg_unarmed u1)"
  # POSITIVE CONTROL FIRST: these very inputs escalate on an ARMED config, in this run.
  # Without it, "returns builder" would also be satisfied by escalation being broken outright.
  [ "$(role '' 3)" = builder-heavy ]        || fail "R12: control — round 3 is not heavy on an armed config"
  [ "$(role complex 1)" = builder-heavy ]   || fail "R12: control — complex is not heavy on an armed config"
  # Both triggers must decline while the heavy role has no tier.
  [ "$(role '' 3 --config "$_un")" = builder ] \
    || fail "R12: the round trigger escalated to an untiered heavy role (a downgrade)"
  [ "$(role complex 1 --config "$_un")" = builder ] \
    || fail "R12: the complexity trigger escalated to an untiered heavy role (a downgrade)"
  [ "$(role '' 99 --config "$_un")" = builder ] \
    || fail "R12: a very high round escalated to an untiered heavy role"
  # A declined trigger must SAY so — the operator expressed intent and gets no silent no-op.
  printf '%s' "$(err '' 3 --config "$_un")" | grep -qi 'builder-heavy' \
    || fail "R12: declining to escalate produced no advisory naming models.builder-heavy"
  printf '%s' "$(err complex 1 --config "$_un")" | grep -qi 'builder-heavy' \
    || fail "R12: a declined complexity trigger produced no advisory"
  [ "$(rc '' 3 --config "$_un")" = 0 ] || fail "R12: declining to escalate failed the build"
  # A trigger that did NOT match stays silent — the advisory is about a declined escalation,
  # not about the tier being unset.
  [ -z "$(err '' 1 --config "$_un")" ] \
    || fail "R12: an untiered config warned on a round that would not have escalated anyway"
  # models.default arms it too: the heavy role falls through to it like any other role.
  _viadefault="$T/viadefault.yaml"
  printf 'models:\n  default: reasoning\n  builder: standard\n' > "$_viadefault"
  [ "$(role '' 3 --config "$_viadefault")" = builder-heavy ] \
    || fail "R12: a heavy tier inherited from models.default did not arm escalation"
  # And a fully all-inherit target is now LITERALLY inert, which is what the feature claims.
  _allinherit="$T/allinherit.yaml"
  printf 'models:\n  default: inherit\n  builder: inherit\n  builder-heavy: inherit\n' > "$_allinherit"
  [ "$(role '' 99 --config "$_allinherit")" = builder ] \
    || fail "R12: an all-inherit target escalated — 'inert until configured' is not true"
  [ "$(role complex 9 --config "$_allinherit")" = builder ] \
    || fail "R12: an all-inherit target escalated on the complexity tag"
  pass "escalation fires only when models.builder-heavy has a tier; declines are reported (R12)"
}

# ── usage errors ────────────────────────────────────────────────────────────────
usage_errors_are_loud() {
  # A malformed COMPLEXITY is a human typo and must never fail a build (R2). A malformed
  # ROUND means the CALLER is broken — coercing it would hide that while changing models.
  [ "$(rc '' notanumber)" = 4 ] || fail "usage: a non-numeric round did not exit 4"
  sh "$TOOL" only-one >/dev/null 2>&1 && fail "usage: a missing round did not exit non-zero"
  sh "$TOOL" a 1 b >/dev/null 2>&1 && fail "usage: an extra positional did not exit non-zero"
  sh "$TOOL" '' 1 --nope >/dev/null 2>&1 && fail "usage: an unknown option did not exit non-zero"
  pass "usage errors exit 4; a bad round is loud where a bad tag is not"
}

vocabulary_and_default
unknown_value_is_coerced_and_reported
the_truth_table
threshold_boundary
the_rule_is_pure
no_second_source_of_truth
config_seeded_in_both_paths
zero_disables_not_always_escalates
unconfigured_is_silent_and_standard
durable_state_only
delegate_never_escalates
prose_records_the_choice
telemetry_contract_intact
escalation_requires_a_configured_heavy_tier
usage_errors_are_loud

echo "test_escalation.sh: all cases passed"
