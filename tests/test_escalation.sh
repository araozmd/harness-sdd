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

# Escalation is OPT-IN and off by default (R12). So the default config for these helpers is
# one that has opted IN; `--config` passed by a caller comes later on the command line and
# wins (last flag wins), which is how the off cases below opt out.
ARMED="$T/enabled.yaml"
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
# mkcfg_off <name> — escalation NOT opted into: the shipped default.
mkcfg_off() {
  _p="$T/$1.yaml"
  printf 'models:\n  default: inherit\n  builder: standard\n  builder-heavy: reasoning\nescalation:\n  after_rejections: 0\n' > "$_p"
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
  grep -Eq '^  after_rejections: 0' "$_fresh/.harness/harness.config.yaml" \
    || fail "R6: a fresh install does not seed after_rejections: 0 (escalation must ship OFF)"

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
  grep -Eq '^  after_rejections: 0' "$_c" \
    || fail "R6: migrate_config did not re-seed escalation.after_rejections: 0"
  pass "escalation.after_rejections: 0 is seeded on both the fresh and the upgrade path (R6)"
}

# ── R6: 0 disables (both triggers), and does not invert ─────────────────────────
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
  # 0 is the master switch, so the complexity route goes off with it — same downgrade
  # hazard, same answer. (This assertion was the OPPOSITE before review: escalating a
  # `complex` spec into an unresolvable heavy role is exactly the downgrade #3716706727 and
  # #3716777878 describe, so 0 must silence both triggers.)
  [ "$(role complex 1 --config "$_c0")" = builder ] \
    || fail "R6: threshold 0 left the complexity route live"
  pass "threshold 0 disables both triggers without inverting the comparison (R6)"
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
  # A config with no escalation block has not opted in, so escalation is OFF (R12) — the
  # default is 0, not 2. Proven both ways: off here, on once the key is present.
  [ "$(role '' 3 --config "$_bare")" = builder ] \
    || fail "R7: a config with no escalation block escalated"
  _bare_on="$T/bare-on.yaml"
  printf 'store:\n  tasks: local\nescalation:\n  after_rejections: 2\n' > "$_bare_on"
  [ "$(role '' 3 --config "$_bare_on")" = builder-heavy ] \
    || fail "R7: control — opting in did not enable escalation, so the off case proves nothing"
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

# ── R12: escalation is opt-in, and off by default ───────────────────────────────
# Two review rounds killed two attempts to INFER whether escalating would help:
#   #3716706727  "builder-heavy: inherit resolves like builder" — false once models.builder
#                is set: the Builder shim gets a model, the heavy role gets none.
#   #3716777878  "arm on a non-inherit tier" — false on codex/opencode, where a tier stamps
#                NOTHING without a matching pin.<front-end>.<tier>.
# Both were this tool re-deriving the installer's resolve_model. It no longer tries: enabling
# escalation is an explicit operator act, which cannot be wrong on any front-end.
escalation_is_opt_in_and_off_by_default() {
  _off="$(mkcfg_off o1)"
  # POSITIVE CONTROL FIRST: these very inputs escalate once opted in, in this run. Without
  # it, "returns builder" would also be satisfied by escalation being broken outright.
  [ "$(role '' 3)" = builder-heavy ]      || fail "R12: control — round 3 is not heavy when opted in"
  [ "$(role complex 1)" = builder-heavy ] || fail "R12: control — complex is not heavy when opted in"
  # 0 disables BOTH triggers — not just the round arm.
  [ "$(role '' 3 --config "$_off")" = builder ] \
    || fail "R12: the round trigger escalated while escalation was off"
  [ "$(role complex 1 --config "$_off")" = builder ] \
    || fail "R12: the complexity trigger escalated while escalation was off"
  [ "$(role '' 99 --config "$_off")" = builder ] \
    || fail "R12: a very high round escalated while escalation was off"
  # A declined COMPLEXITY tag must say so — the operator expressed intent and would
  # otherwise get a silent no-op.
  printf '%s' "$(err complex 1 --config "$_off")" | grep -qi 'after_rejections' \
    || fail "R12: a declined complexity trigger produced no advisory naming the key to set"
  [ "$(rc complex 1 --config "$_off")" = 0 ] || fail "R12: declining to escalate failed the build"
  # The ROUND arm stays silent while escalation is off, deliberately: with no threshold
  # configured there is no round it "would have" exceeded, and warning anyway would put a
  # line on every build of every target that never opted in.
  [ -z "$(err '' 3 --config "$_off")" ] \
    || fail "R12: the round arm warned while escalation was off — that is noise, not signal"
  [ -z "$(err '' 99 --config "$_off")" ] \
    || fail "R12: the round arm warned at a high round while escalation was off"
  # And a non-matching trigger is silent when escalation is ON, too.
  [ -z "$(err '' 1)" ] || fail "R12: warned on a round that would not have escalated anyway"
  # The shipped default is off: a config with the block but no opt-in behaves like $_off.
  [ "$(role '' 99 --config "$(mkcfg z0 0)")" = builder ] \
    || fail "R12: an explicit 0 escalated"
  pass "escalation is opt-in; 0 disables both triggers and declines are reported (R12)"
}

# ── R12: the tool does not try to predict model resolution ──────────────────────
# The regression guard for BOTH review findings: a tier name alone must not be treated as
# evidence that escalating would upgrade anything. This is what a third attempt to infer
# would break.
the_tool_does_not_infer_resolution() {
  # A codex-shaped config: builder pinned, heavy tier named but UNPINNED — so the installer
  # stamps a model for builder and none for builder-heavy. Escalation stays off because
  # nobody opted in, NOT because the tool worked out that the pin was missing.
  _codexish="$T/codexish.yaml"
  printf 'models:\n  default: inherit\n  builder: standard\n  builder-heavy: reasoning\n  pin.codex.standard: "gpt-5"\n' > "$_codexish"
  [ "$(role '' 99 --config "$_codexish")" = builder ] \
    || fail "R12: a config that never opted in escalated"
  # And the decisive half: once the operator DOES opt in, the tool obeys — it does not
  # second-guess the pin. Re-deriving resolve_model here is what produced two defects.
  printf 'escalation:\n  after_rejections: 2\n' >> "$_codexish"
  [ "$(role '' 99 --config "$_codexish")" = builder-heavy ] \
    || fail "R12: the tool refused an opted-in escalation by inferring resolution"
  # The rule must never READ the models: section. Assert on that precisely rather than on
  # any mention of the words: the tool legitimately PRINTS `builder-heavy` (it is the answer)
  # and legitimately names models.builder-heavy and pin.<front-end>.<tier> in the advisory it
  # writes for the operator. What it may not do is parse them and decide.
  grep -q '_cfg_scalar models' "$TOOL" \
    && fail "R12: the tool reads the models: section — it is inferring model resolution again"
  grep -qE '_cfg_scalar +(escalation)' "$TOOL" \
    || fail "R12: control — the tool no longer reads escalation config, so the check above is vacuous"
  pass "the rule never infers model resolution; the opt-in is the operator's assertion (R12)"
}

# ── R6: the docs and the shipped config must agree on the default ───────────────
# Three review rounds in, the recurring defect on this PR was not the code — it was PROSE
# describing an older version of the rule. #3716846165 caught docs/WORKFLOW.md still telling
# operators that `0` left `complexity: complex` live, which the tool had stopped doing two
# commits earlier. A doc that contradicts the tool is worse than a missing doc: the operator
# acts on it. So pin the one fact most likely to drift.
docs_agree_with_the_shipped_default() {
  _shipped="$(awk '/^escalation:/{e=1;next} e&&/^[^ #]/{e=0} e&&/^  after_rejections:/{sub(/^  after_rejections:[[:space:]]*/,"");sub(/[[:space:]]*#.*$/,"");print;exit}' "$SRC/harness.config.yaml")"
  [ -n "$_shipped" ] || fail "R6: could not read the shipped escalation.after_rejections"
  [ "$_shipped" = 0 ]     || fail "R6: the shipped default is '$_shipped' — escalation must ship OFF (0)"
  # The tool must actually behave that way with the shipped config, not merely record it.
  [ "$(role '' 99 --config "$SRC/harness.config.yaml")" = builder ]     || fail "R6: the shipped config escalated — the default is not off in practice"
  [ "$(role complex 1 --config "$SRC/harness.config.yaml")" = builder ]     || fail "R6: the shipped config escalated a complex tag — 0 must disable BOTH triggers"
  # And no operator-facing doc may still claim 0 leaves a trigger live.
  for _d in "$SRC/docs/WORKFLOW.md" "$SRC/harness.config.yaml" "$SRC/agents/orchestrator.md"; do
    grep -qi 'disables rejection-based\|leaving `complexity: complex` as the only route' "$_d"       && fail "R6: $_d still documents the pre-opt-in meaning of 0"
  done
  # Positive control: the docs DO describe the current meaning, so the sweep above is not
  # passing merely because escalation went undocumented.
  grep -qi 'disables BOTH triggers' "$SRC/docs/WORKFLOW.md"     || fail "R6: docs/WORKFLOW.md does not state that 0 disables both triggers"
  # The FIRST version of this guard checked only the pre-opt-in *phrasing* and missed three
  # docs still calling the default `2` — caught a round later (#3716898786). So also pin the
  # VALUE: any line mentioning both `after_rejections` and "default" must say 0. The docs
  # legitimately suggest 2 as an opt-in, which is why this keys off "default", not the digit.
  for _d in "$SRC/docs/WORKFLOW.md" "$SRC/CHANGELOG.md" "$SRC/harness.config.yaml" \
            "$SRC/agents/orchestrator.md" "$SRC/harness-install.sh"; do
    _bad="$(grep -i 'after_rejections' "$_d" | grep -i 'default' | grep -v '0' || true)"
    [ -z "$_bad" ] || fail "R6: $_d states a non-zero default for after_rejections: $_bad"
  done
  pass "the shipped default is off, behaves off, and the docs say so (R6)"
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
escalation_is_opt_in_and_off_by_default
the_tool_does_not_infer_resolution
docs_agree_with_the_shipped_default
usage_errors_are_loud

echo "test_escalation.sh: all cases passed"
