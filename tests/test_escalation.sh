#!/bin/sh
# test_escalation.sh — E17-F03 deterministic escalation + E17-F05 installer-stamped arming.
#
# The RULE is a tool (tools/builder-role.sh) and the VERDICT is an installer artifact
# (.harness/.escalation-arming), so most of this suite is real behavioral coverage rather than
# the role-content-assertion pattern a prose-only feature is stuck with. What remains prose —
# the Orchestrator's call site and the telemetry record shape — is grepped, and the test
# contract names that as a gap rather than dressing it up as coverage.
#
# R-ids are qualified: `F03-Rn` is E17-F03's, `F05-Rn` is E17-F05's. They collide numerically.
#
# Zero dependencies: POSIX sh + grep + awk + sed. Self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

TOOL="$SRC/tools/builder-role.sh"
[ -f "$TOOL" ] || fail "setup: tools/builder-role.sh does not exist"

# ── fixtures ────────────────────────────────────────────────────────────────────
# Escalation needs TWO independent yeses (F05-R7): a positive `escalation.after_rejections`
# AND an `armed` verdict in `.harness/.escalation-arming`, which the tool locates BESIDE the
# config. So every fixture is its own DIRECTORY holding both files — a shared directory would
# make the arming artifact global and let one case's verdict silently decide another's.
#
# mkfix <name> <after_rejections> <arming-first-line> [detail-line…] — print the config path.
# An EMPTY <arming-first-line> writes no artifact at all: the "no verdict recorded" case.
mkfix() {
  _mf_d="$T/fix-$1"; mkdir -p "$_mf_d"
  printf 'models:\n  default: inherit\n  builder: standard\n  builder-heavy: reasoning\nescalation:\n  after_rejections: %s\n' \
    "$2" > "$_mf_d/harness.config.yaml"
  if [ -n "$3" ]; then
    _mf_first="$3"; shift 3
    { printf '%s\n' "$_mf_first"; for _mf_l in "$@"; do printf '%s\n' "$_mf_l"; done; } \
      > "$_mf_d/.escalation-arming"
  fi
  printf '%s\n' "$_mf_d/harness.config.yaml"
}

# The default fixture: opted in AND armed, i.e. escalation fully live.
ARMED="$(mkfix enabled 2 armed claude=raise)"

# role <complexity> <round> [extra args…] — stdout only.
role() { _c="$1"; _r="$2"; shift 2; sh "$TOOL" "$_c" "$_r" --config "$ARMED" "$@" 2>/dev/null; }
# err <complexity> <round> [extra args…] — stderr only.
err()  { _c="$1"; _r="$2"; shift 2; sh "$TOOL" "$_c" "$_r" --config "$ARMED" "$@" 2>&1 >/dev/null; }
# rc <complexity> <round> [extra args…] — exit status only.
# The `|| _s=$?` is load-bearing: this suite runs under `set -e`, so a bare invocation that
# exits non-zero would kill the command substitution before it could echo anything, and the
# caller would compare against an empty string instead of the status it asked for.
rc()   { _c="$1"; _r="$2"; shift 2; _s=0; sh "$TOOL" "$_c" "$_r" --config "$ARMED" "$@" >/dev/null 2>&1 || _s=$?; echo "$_s"; }

# mkcfg <name> <after_rejections> — an ARMED fixture at an explicit threshold.
mkcfg()     { mkfix "t$1" "$2" armed claude=raise; }
# mkcfg_off <name> — armed, but the operator's hard veto is in force.
mkcfg_off() { mkfix "off$1" 0 armed claude=raise; }

# install <target> <codex-home> [args…] — run the installer, failing loudly on non-zero.
# Every install fixture is a throwaway tree under $T; the installer is never pointed at a
# real target.
install_to() {
  _it_t="$1"; _it_ch="$2"; shift 2
  mkdir -p "$_it_t"
  CODEX_HOME="$_it_ch" sh "$SRC/harness-install.sh" "$@" "$_it_t" >/dev/null 2>&1 \
    || fail "setup: install into $_it_t exited non-zero"
}
# set_models <config> <key> <value> — set or append a models: key in an installed config.
set_models() {
  if grep -Eq "^  $2:" "$1"; then
    awk -v k="$2" -v v="$3" '$0 ~ "^  " k ":" { print "  " k ": " v; next } { print }' "$1" > "$1.t" \
      && mv "$1.t" "$1"
  else
    awk -v k="$2" -v v="$3" '/^models:/ { print; print "  " k ": " v; next } { print }' "$1" > "$1.t" \
      && mv "$1.t" "$1"
  fi
}
# arming_of <target> — print the target's arming artifact, or nothing when absent.
arming_of() { [ -f "$1/.harness/.escalation-arming" ] && cat "$1/.harness/.escalation-arming" || true; }
# verdict_for <target> <front-end> — print that front-end's recorded verdict, or nothing.
verdict_for() { arming_of "$1" | sed -n "s/^$2=//p"; }

# ══════════════════════════════════════════════════════════════════════════════
# E17-F03 — the rule
# ══════════════════════════════════════════════════════════════════════════════

# ── F03-R1: the vocabulary and its default ──────────────────────────────────────
vocabulary_and_default() {
  [ "$(role complex 1)" = builder-heavy ] || fail "F03-R1: complex at round 1 did not select builder-heavy"
  [ "$(role standard 1)" = builder ]      || fail "F03-R1: standard at round 1 did not select builder"
  [ "$(role '' 1)" = builder ]            || fail "F03-R1: an absent tag did not default to standard"
  # Absent must be SILENT — a spec written before this feature must not start warning.
  [ -z "$(err '' 1)" ] || fail "F03-R1/R7: an absent tag produced output on stderr"
  [ -z "$(err standard 1)" ] || fail "F03-R1: an explicit 'standard' produced output on stderr"
  pass "complex ⇒ heavy, standard/absent ⇒ builder, absent is silent (F03-R1)"
}

# ── F03-R2: an out-of-vocabulary value is coerced, reported, and never fatal ────
unknown_value_is_coerced_and_reported() {
  [ "$(role bogus 1)" = builder ] || fail "F03-R2: an unrecognized value did not resolve to standard"
  [ -n "$(err bogus 1)" ]         || fail "F03-R2: an unrecognized value produced no advisory"
  printf '%s' "$(err bogus 1)" | grep -q 'bogus' \
    || fail "F03-R2: the advisory does not name the offending value"
  [ "$(rc bogus 1)" = 0 ] || fail "F03-R2: an unrecognized value failed the build (exit $(rc bogus 1))"
  # It must be coerced to STANDARD, not to complex — the safe direction.
  [ "$(role bogus 1)" != builder-heavy ] || fail "F03-R2: an unrecognized value escalated"
  pass "an out-of-vocabulary complexity coerces to standard, reports, exits 0 (F03-R2)"
}

# ── F03-R3: the truth table, with a distinct-answers guard ──────────────────────
the_truth_table() {
  _seen_std=0; _seen_heavy=0
  for _c in '' standard complex; do
    for _r in 1 2 3 7; do
      _got="$(role "$_c" "$_r")"
      case "$_got" in
        builder)       _seen_std=1 ;;
        builder-heavy) _seen_heavy=1 ;;
        *) fail "F03-R3: unexpected answer '$_got' for complexity='$_c' round=$_r" ;;
      esac
      # The expected value, derived independently of the tool: heavy iff complex or round>2.
      if [ "$_c" = complex ] || [ "$_r" -gt 2 ]; then _want=builder-heavy; else _want=builder; fi
      [ "$_got" = "$_want" ] \
        || fail "F03-R3: complexity='$_c' round=$_r gave '$_got', expected '$_want'"
    done
  done
  # A tool that ignored its arguments and always printed `builder` would satisfy most cells.
  # Require BOTH answers to have been observed, or the table proves nothing.
  [ "$_seen_std" = 1 ] && [ "$_seen_heavy" = 1 ] \
    || fail "F03-R3: the table observed only one distinct answer — a constant implementation would pass"
  pass "the (complexity × round) truth table holds and yields both distinct answers (F03-R3)"
}

# ── F03-R3: the off-by-one boundary, from both sides ────────────────────────────
threshold_boundary() {
  # `round > n` and `round >= n` differ by exactly one rejection; sampling only 1 and 9
  # would not tell them apart. Pin n=2 from both sides.
  [ "$(role '' 2)" = builder ] \
    || fail "F03-R3: round 2 escalated — the threshold is off by one (>= where > was meant)"
  [ "$(role '' 3)" = builder-heavy ] \
    || fail "F03-R3: round 3 did not escalate at the threshold of 2"
  # And at an explicit non-default threshold, so the boundary is not an artifact of the default.
  _c5="$(mkcfg 5 5)"
  [ "$(role '' 5 --config "$_c5")" = builder ]       || fail "F03-R3: round 5 escalated at threshold 5"
  [ "$(role '' 6 --config "$_c5")" = builder-heavy ] || fail "F03-R3: round 6 did not escalate at threshold 5"
  pass "the round > threshold boundary holds from both sides at n=2 and n=5 (F03-R3)"
}

# ── F03-R4 / F05-R10: the rule is pure ──────────────────────────────────────────
the_rule_is_pure() {
  _a="$(role complex 4)"; _b="$(role complex 4)"; _c="$(role complex 4)"
  [ "$_a" = "$_b" ] && [ "$_b" = "$_c" ] || fail "F03-R4: repeated identical invocations disagreed"
  # It must not consult the repository it happens to be run from: same answer from a
  # directory with no harness, no progress/, no git.
  _empty="$T/empty"; mkdir -p "$_empty"
  _out="$(cd "$_empty" && sh "$TOOL" '' 3 --config "$ARMED" 2>/dev/null)"
  [ "$_out" = builder-heavy ] || fail "F03-R4: the answer changed when run from an unrelated directory"
  # And it must not read the spec body or history. Assert on EXECUTABLE content only:
  # the tool's own comments necessarily name progress/history.md to explain that it never
  # reads it, so grepping the raw file would fail on its documentation. Strip whole-line
  # comments first, then look for an actual reference.
  sed -e 's/^[[:space:]]*#.*$//' "$TOOL" \
    | grep -qE 'progress/|history\.md|(^|[^a-zA-Z])git([^a-zA-Z]|$)' \
    && fail "F03-R4: the tool's code references progress/, history.md or git — it is not pure"
  pass "identical inputs yield identical answers; the tool reads no repo state (F03-R4/F05-R10)"
}

# ── F03-R5: no second source of truth ───────────────────────────────────────────
no_second_source_of_truth() {
  # The round counter must stay where agents/orchestrator.md already defines it. This
  # feature may not add a status value or a TaskStore field to carry it.
  grep -q 'complexity' "$SRC/store/tasks.schema.json" \
    && fail "F03-R5: complexity leaked into the TaskStore schema"
  grep -q 'after_rejections' "$SRC/store/tasks.schema.json" \
    && fail "F03-R5: the escalation threshold leaked into the TaskStore schema"
  grep -q 'round' "$SRC/store/tasks.schema.json" \
    && fail "F03-R5: a round counter leaked into the TaskStore schema"
  # The tool takes the round as an ARGUMENT — it never derives one.
  grep -q '<round>' "$SRC/agents/orchestrator.md" \
    || fail "F03-R5: orchestrator.md does not pass the existing round to the tool"
  pass "no second counter, status value, or TaskStore field was introduced (F03-R5)"
}

# ── F05-R9: the config key is seeded on BOTH paths, and an existing 0 is kept ────
config_seeded_in_both_paths() {
  _fresh="$T/fresh"
  install_to "$_fresh" "$T/ch1" --agents=claude
  grep -Eq '^escalation:[[:space:]]*(#.*)?$' "$_fresh/.harness/harness.config.yaml" \
    || fail "F05-R9: a fresh install has no top-level escalation: block"
  grep -Eq '^  after_rejections: 2' "$_fresh/.harness/harness.config.yaml" \
    || fail "F05-R9: a fresh install does not seed after_rejections: 2"

  # The UPGRADE path: strip the block and re-install. Seeding only the shipped config makes
  # a fresh target and an upgraded one diverge, and nothing else in the suite would notice —
  # this is the exact defect E17-F02's mutation battery caught one feature earlier.
  _up="$T/up"
  install_to "$_up" "$T/ch2" --agents=claude
  _c="$_up/.harness/harness.config.yaml"
  awk '/^# Deterministic Builder escalation/ { drop=1 } !drop { print }' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  grep -Eq '^escalation:' "$_c" && fail "F05-R9: setup — the escalation block was not stripped"
  CODEX_HOME="$T/ch2" sh "$SRC/harness-install.sh" --agents=claude "$_up" >/dev/null 2>&1 \
    || fail "F05-R9: re-install after stripping exited non-zero"
  grep -Eq '^  after_rejections: 2' "$_c" \
    || fail "F05-R9: migrate_config did not re-seed escalation.after_rejections: 2"

  # And the LEAVE-ALONE leg: a target carrying an operator's 0 keeps it. migrate_config seeds
  # only when the block is ABSENT, and rewriting a value the operator may have chosen
  # deliberately would be worse than the upgrade gap it leaves. Without this leg, a mutation
  # that rewrote every existing value would pass the two legs above.
  awk '/^  after_rejections:/ { print "  after_rejections: 0"; next } { print }' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  CODEX_HOME="$T/ch2" sh "$SRC/harness-install.sh" --agents=claude "$_up" >/dev/null 2>&1 \
    || fail "F05-R9: re-install over an existing 0 exited non-zero"
  grep -Eq '^  after_rejections: 0' "$_c" \
    || fail "F05-R9: the installer rewrote an operator's existing after_rejections: 0"
  pass "after_rejections: 2 seeded on fresh + upgrade; an existing 0 is left alone (F05-R9)"
}

# ── F03-R6 / F05-R9: 0 disables (both triggers), and does not invert ────────────
zero_disables_not_always_escalates() {
  _c0="$(mkcfg 0 0)"
  # `round > 0` is true for EVERY round ≥ 1, so a naive implementation turns the operator's
  # off-switch into always-escalate. Check well past any plausible threshold.
  for _r in 1 2 3 99; do
    [ "$(role '' "$_r" --config "$_c0")" = builder ] \
      || fail "F03-R6: threshold 0 escalated at round $_r — 0 must DISABLE, not invert"
  done
  # Paired control in the same run: at a positive threshold those same high rounds DO
  # escalate, so "always standard" cannot pass this case either.
  _c2="$(mkcfg 2 2)"
  [ "$(role '' 99 --config "$_c2")" = builder-heavy ] \
    || fail "F03-R6: control — round 99 at threshold 2 did not escalate, so the 0 case proves nothing"
  # 0 is the master switch, so the complexity route goes off with it — same downgrade
  # hazard, same answer.
  [ "$(role complex 1 --config "$_c0")" = builder ] \
    || fail "F03-R6: threshold 0 left the complexity route live"
  pass "threshold 0 disables both triggers without inverting the comparison (F03-R6)"
}

# ── F05-R9: 0 is a HARD veto — an armed verdict does not resurrect it ────────────
zero_still_hard_disables() {
  # Every fixture here is ARMED. Without this case, "0 disables" could be satisfied by the
  # arming gate alone once the default flipped, and the operator's veto could silently stop
  # being load-bearing.
  _c0="$(mkcfg 0 0)"
  grep -q '^armed$' "$(dirname "$_c0")/.escalation-arming" \
    || fail "F05-R9: fixture precondition — the 0-threshold fixture is not armed, so this case is vacuous"
  for _r in 1 2 3 99; do
    [ "$(role '' "$_r" --config "$_c0")" = builder ] \
      || fail "F05-R9: an armed verdict overrode the operator's 0 at round $_r"
  done
  [ "$(role complex 1 --config "$_c0")" = builder ] \
    || fail "F05-R9: an armed verdict overrode the operator's 0 on the complexity trigger"
  # Control: the SAME arming artifact escalates once the threshold is positive.
  [ "$(role '' 99 --config "$(mkcfg 2 2)")" = builder-heavy ] \
    || fail "F05-R9: control — the armed fixture never escalates, so the veto proves nothing"
  pass "0 remains a hard veto that an armed verdict cannot override (F05-R9)"
}

# ── F03-R7: an unconfigured target is standard and silent ───────────────────────
unconfigured_is_silent_and_standard() {
  # No escalation: block at all — the shape of a config that predates this feature. Its own
  # directory, so no stray arming artifact can decide it.
  _bd="$T/bare"; mkdir -p "$_bd"; _bare="$_bd/harness.config.yaml"
  printf 'store:\n  tasks: local\n' > "$_bare"
  [ "$(role '' 1 --config "$_bare")" = builder ] \
    || fail "F03-R7: a config with no escalation block did not route to builder"
  [ -z "$(err '' 1 --config "$_bare")" ] \
    || fail "F03-R7: a config with no escalation block produced a warning"
  # A missing config FILE is the same story.
  [ "$(role '' 1 --config "$T/does-not-exist.yaml")" = builder ] \
    || fail "F03-R7: a missing config did not route to builder"
  [ -z "$(err '' 1 --config "$T/does-not-exist.yaml")" ] \
    || fail "F03-R7: a missing config produced a warning"
  [ "$(role '' 3 --config "$_bare")" = builder ] \
    || fail "F03-R7: a config with no escalation block escalated"
  # Control: the same shape with the key present AND armed does escalate, so the silence
  # above is a decline and not a broken tool.
  _bod="$T/bare-on"; mkdir -p "$_bod"
  printf 'store:\n  tasks: local\nescalation:\n  after_rejections: 2\n' > "$_bod/harness.config.yaml"
  printf 'armed\nclaude=raise\n' > "$_bod/.escalation-arming"
  [ "$(role '' 3 --config "$_bod/harness.config.yaml")" = builder-heavy ] \
    || fail "F03-R7: control — an armed, opted-in config did not escalate, so the off case proves nothing"
  pass "no escalation block ⇒ builder, silently (F03-R7)"
}

# ── F03-R8: durable state only ──────────────────────────────────────────────────
durable_state_only() {
  # The rule takes the round as an argument, so a feature whose earlier rounds ran in a
  # previous session resolves identically — there is no session memory to lose. Prove the
  # tool keeps none: same inputs, run from a directory with no progress/ and no git.
  _iso="$T/iso"; mkdir -p "$_iso"
  _first="$(cd "$_iso" && sh "$TOOL" '' 3 --config "$ARMED" 2>/dev/null)"
  _second="$(cd "$_iso" && sh "$TOOL" '' 3 --config "$ARMED" 2>/dev/null)"
  [ "$_first" = builder-heavy ] && [ "$_second" = builder-heavy ] \
    || fail "F03-R8: a round-3 build did not escalate outside a harness tree"
  [ -d "$_iso/progress" ] && fail "F03-R8: the tool created state next to itself"
  pass "the rule reads durable inputs only and keeps no session state (F03-R8)"
}

# ── F03-R9: delegate never escalates ────────────────────────────────────────────
delegate_never_escalates() {
  # Asserting `delegate ⇒ builder` proves nothing unless the same inputs are REACHABLY
  # heavy. Establish that first, in this run.
  [ "$(role complex 99)" = builder-heavy ] \
    || fail "F03-R9: control — complex/99 is not heavy under in-session, so the delegate case is vacuous"
  [ "$(role complex 99 --backend delegate)" = builder ] \
    || fail "F03-R9: delegate escalated despite the executor choosing its own model"
  [ "$(role '' 99 --backend delegate)" = builder ] \
    || fail "F03-R9: delegate escalated on the round arm"
  printf '%s' "$(err complex 99 --backend delegate)" | grep -qi 'inapplicable' \
    || fail "F03-R9: delegate did not report escalation as inapplicable"
  [ "$(rc complex 99 --backend delegate)" = 0 ] \
    || fail "F03-R9: the delegate path exited non-zero"
  # in-session is the default when --backend is omitted.
  [ "$(role complex 99 --backend in-session)" = builder-heavy ] \
    || fail "F03-R9: an explicit in-session backend did not behave like the default"
  pass "delegate returns builder and reports inapplicable, over reachably-heavy inputs (F03-R9)"
}

# ── F03-R10/R11: the recorded choice (prose — see the contract's named gap) ─────
prose_records_the_choice() {
  _o="$SRC/agents/orchestrator.md"
  grep -q 'builder-role.sh' "$_o" || fail "F03-R10: orchestrator.md never calls builder-role.sh"
  grep -q 'builder-heavy round 3' "$_o" \
    || fail "F03-R10: orchestrator.md shows no history line naming the role and the trigger"
  grep -qi 'never override the answer' "$_o" \
    || fail "F03-R10: orchestrator.md does not forbid overriding the tool's answer"
  pass "orchestrator.md calls the tool, records role + trigger, forbids overriding it (F03-R10)"
}

telemetry_contract_intact() {
  _o="$SRC/agents/orchestrator.md"
  grep -q '"phase":"builder","role":"builder-heavy"' "$_o" \
    || fail "F03-R11: orchestrator.md does not show phase staying 'builder' with a separate role key"
  grep -qi 'Do not write .*phase.*builder-heavy' "$_o" \
    || fail "F03-R11: orchestrator.md does not forbid phase: builder-heavy"
  # The reason it must not: PHASES is a whitelist and the round count reads builder/reviewer.
  _t="$SRC/tools/telemetry-report.py"
  grep -q 'PHASES = \["architect", "builder", "reviewer", "scout", "inception", "slice-dispatch"\]' "$_t" \
    || fail "F03-R11: the PHASES whitelist changed — re-check whether phase: builder-heavy would now be dropped"
  grep -q 'p\["phase"\] in ("builder", "reviewer")' "$_t" \
    || fail "F03-R11: the max-round computation changed — re-check the under-reporting hazard"
  pass "telemetry keeps phase=builder with a separate role key; the whitelist is unchanged (F03-R11)"
}

# ── F03-R12 / F05-R10: the tool still does not predict model resolution ─────────
# The regression guard for BOTH E17-F03 review findings: a tier name alone must not be
# treated as evidence that escalating would upgrade anything. E17-F05 did not relax this —
# it moved the question to the component that owns the answer. The tool still must not parse
# the models: section.
the_tool_does_not_infer_resolution() {
  # A codex-shaped config: builder pinned, heavy tier named but UNPINNED — so the installer
  # stamps a model for builder and none for builder-heavy. The tool must not work that out;
  # it must read the recorded verdict.
  _cd="$T/codexish"; mkdir -p "$_cd"; _codexish="$_cd/harness.config.yaml"
  printf 'models:\n  default: inherit\n  builder: standard\n  builder-heavy: reasoning\n  pin.codex.standard: "gpt-5"\nescalation:\n  after_rejections: 2\n' > "$_codexish"
  # No verdict recorded ⇒ off, regardless of how the models: block reads.
  [ "$(role '' 99 --config "$_codexish")" = builder ] \
    || fail "F05-R6: a config with no recorded verdict escalated"
  # And the decisive half: with an ARMED verdict the tool obeys — it does not second-guess
  # the pin. Re-deriving resolve_model here is what produced two defects.
  printf 'armed\ncodex=raise\n' > "$_cd/.escalation-arming"
  [ "$(role '' 99 --config "$_codexish")" = builder-heavy ] \
    || fail "F03-R12: the tool refused an armed escalation by inferring resolution itself"
  # The rule must never READ the models: section. Assert on that precisely rather than on
  # any mention of the words: the tool legitimately PRINTS `builder-heavy` (it is the answer)
  # and legitimately names models.builder-heavy and pin.<front-end>.<tier> in the advisory it
  # writes for the operator. What it may not do is parse them and decide.
  grep -q '_cfg_scalar models' "$TOOL" \
    && fail "F03-R12: the tool reads the models: section — it is inferring model resolution again"
  grep -qE '_cfg_scalar +(escalation)' "$TOOL" \
    || fail "F03-R12: control — the tool no longer reads escalation config, so the check above is vacuous"
  # Nor may it re-implement the alias table the installer owns.
  sed -e 's/^[[:space:]]*#.*$//' "$TOOL" | grep -qE 'model_alias|opus|sonnet|haiku|flash' \
    && fail "F05-R10: the tool names concrete model ids or the alias table — it is resolving models again"
  pass "the rule never infers model resolution; it reads the installer's verdict (F03-R12/F05-R10)"
}

# ══════════════════════════════════════════════════════════════════════════════
# E17-F05 — the installer-stamped verdict
# ══════════════════════════════════════════════════════════════════════════════

# ── F05-R1: the verdict tracks resolve_model, including its pin rules ───────────
# A grep for `model_alias` in the diff would prove nothing about a hand-rolled copy. So this
# case changes ONLY a `pin.codex.<tier>` between installs — a value no independent verdict
# logic could get right without going through resolve_model's per-front-end pin handling —
# and asserts the verdict flips. Both directions, so a hardcoded answer fails one of them.
verdict_comes_from_resolve_model() {
  _t="$T/rm"; install_to "$_t" "$T/ch-rm" --agents=codex
  _c="$_t/.harness/harness.config.yaml"
  # builder resolves (pinned), builder-heavy names a tier that codex does NOT alias and that
  # carries no pin ⇒ `none`, the exact downgrade #3716777878 described.
  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.codex.standard' '"gpt-5"'
  install_to "$_t" "$T/ch-rm" --agents=codex
  # Fixture precondition: a pin key that lands OUTSIDE the models: block resolves nothing for
  # either role, and the downgrade could not appear — which would read as "not reproducible".
  [ "$(verdict_for "$_t" codex)" = none ] \
    || fail "F05-R1: precondition — expected codex=none with builder pinned and reasoning unpinned, got '$(verdict_for "$_t" codex)'"

  # Add ONLY the reasoning pin. Nothing else about the config changes.
  set_models "$_c" 'pin.codex.reasoning' '"gpt-5-codex"'
  install_to "$_t" "$T/ch-rm" --agents=codex
  [ "$(verdict_for "$_t" codex)" = raise ] \
    || fail "F05-R1: adding pin.codex.reasoning did not flip the verdict to raise (got '$(verdict_for "$_t" codex)')"

  # And back: removing it must restore `none`, so the `raise` above is not a one-way latch.
  grep -v '^  pin\.codex\.reasoning:' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  install_to "$_t" "$T/ch-rm" --agents=codex
  [ "$(verdict_for "$_t" codex)" = none ] \
    || fail "F05-R1: removing pin.codex.reasoning did not restore none (got '$(verdict_for "$_t" codex)')"
  pass "the verdict follows resolve_model's pin rules in both directions (F05-R1)"
}

# ── F05-R2: the artifact's shape ────────────────────────────────────────────────
arming_artifact_shape() {
  _t="$T/shape"; install_to "$_t" "$T/ch-shape" --agents=claude,codex
  _c="$_t/.harness/harness.config.yaml"
  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  install_to "$_t" "$T/ch-shape" --agents=claude,codex
  _f="$_t/.harness/.escalation-arming"
  [ -f "$_f" ] || fail "F05-R2: no artifact was written for a configured target"
  head -n 1 "$_f" | grep -Eq '^(armed|blocked)$' \
    || fail "F05-R2: the first line is not exactly 'armed' or 'blocked': $(head -n 1 "$_f")"
  # Every remaining line is <front-end>=<verdict>, and there is one per SELECTED front-end.
  _bad="$(sed -n '2,$p' "$_f" | grep -Ev '^(claude|gemini|opencode|antigravity|codex)=(raise|none|same|neither|unstamped)$' || true)"
  [ -z "$_bad" ] || fail "F05-R2: malformed detail line(s): $_bad"
  [ "$(sed -n '2,$p' "$_f" | wc -l | tr -d ' ')" = 2 ] \
    || fail "F05-R2: expected one detail line per selected front-end (2), got $(sed -n '2,$p' "$_f" | wc -l | tr -d ' ')"
  sed -n '2,$p' "$_f" | grep -q '^claude=' || fail "F05-R2: the selected claude front-end has no line"
  sed -n '2,$p' "$_f" | grep -q '^codex='  || fail "F05-R2: the selected codex front-end has no line"
  # Deterministic content: the same target re-installed yields byte-identical bytes.
  cp "$_f" "$T/shape-first"
  install_to "$_t" "$T/ch-shape" --agents=claude,codex
  cmp -s "$T/shape-first" "$_f" || fail "F05-R2: re-installing the same target changed the artifact"
  pass "the artifact is a verdict line plus one line per selected front-end, and is stable (F05-R2)"
}

# ── F05-R3: all four verdict cells, and only all-raise arms ─────────────────────
# `same` is the cell a lazy implementation merges into `raise` (checking only "heavy resolves
# to something"), and `neither` is the cell it merges into `none`. Both are produced here
# from real configs, and the distinct-verdict set is asserted so a constant cannot pass.
verdict_truth_table() {
  _t="$T/tt"; install_to "$_t" "$T/ch-tt" --agents=claude
  _c="$_t/.harness/harness.config.yaml"
  _seen=""

  # raise — builder ⇒ sonnet, heavy ⇒ opus (two different built-in aliases).
  set_models "$_c" builder standard; set_models "$_c" builder-heavy reasoning
  install_to "$_t" "$T/ch-tt" --agents=claude
  [ "$(verdict_for "$_t" claude)" = raise ] || fail "F05-R3: expected raise, got '$(verdict_for "$_t" claude)'"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = armed ] \
    || fail "F05-R3: an all-raise target was not armed"
  _seen="$_seen raise"

  # none — builder resolves, heavy inherits ⇒ THE DOWNGRADE (#3716706727 exactly).
  set_models "$_c" builder-heavy inherit
  install_to "$_t" "$T/ch-tt" --agents=claude
  [ "$(verdict_for "$_t" claude)" = none ] || fail "F05-R3: expected none, got '$(verdict_for "$_t" claude)'"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R3: a none verdict did not block"
  _seen="$_seen none"

  # same — both resolve to the IDENTICAL value by DIFFERENT routes: builder via the built-in
  # `standard` alias (sonnet), heavy via an explicit pin that spells the same model. An
  # implementation testing only non-emptiness reports raise here and fails.
  set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.claude.reasoning' 'sonnet'
  install_to "$_t" "$T/ch-tt" --agents=claude
  [ "$(verdict_for "$_t" claude)" = same ] \
    || fail "F05-R3: expected same when both roles resolve to sonnet by different routes, got '$(verdict_for "$_t" claude)'"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R3: a same verdict armed — escalation would be a no-op that still records a role change"
  _seen="$_seen same"

  # neither — both roles inherit, while ANOTHER role still resolves so the artifact is
  # written at all. Distinguished from `none` only by the detail line, which is what the
  # operator acts on.
  grep -v '^  pin\.claude\.reasoning:' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  set_models "$_c" builder inherit; set_models "$_c" builder-heavy inherit
  set_models "$_c" reviewer standard
  install_to "$_t" "$T/ch-tt" --agents=claude
  [ "$(verdict_for "$_t" claude)" = neither ] \
    || fail "F05-R3: expected neither when both roles inherit, got '$(verdict_for "$_t" claude)'"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R3: a neither verdict armed"
  _seen="$_seen neither"

  # A constant implementation, or one collapsing two cells, cannot produce all four.
  for _w in raise none same neither; do
    printf '%s' "$_seen" | grep -q "$_w" || fail "F05-R3: the verdict '$_w' was never observed"
  done
  pass "all four verdict cells are produced from real configs; only all-raise arms (F05-R3)"
}

# ── F05-R3: the conservative AND, asserted in BOTH orders ───────────────────────
# A first-wins or last-wins bug passes exactly one of these two. $AGENT_KEYS orders claude
# first and codex last, so one config puts the raising front-end first and the other last.
and_across_front_ends() {
  # A: claude=raise (first), codex=none (last).
  _a="$T/and-a"; install_to "$_a" "$T/ch-and-a" --agents=claude,codex
  _c="$_a/.harness/harness.config.yaml"
  set_models "$_c" builder standard; set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.codex.standard' '"gpt-5"'
  install_to "$_a" "$T/ch-and-a" --agents=claude,codex
  [ "$(verdict_for "$_a" claude)" = raise ] \
    || fail "F05-R3: precondition A — claude is '$(verdict_for "$_a" claude)', not raise"
  [ "$(verdict_for "$_a" codex)" = none ] \
    || fail "F05-R3: precondition A — codex is '$(verdict_for "$_a" codex)', not none"
  [ "$(head -n 1 "$_a/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R3: raise-first + none-last armed — the AND became an OR"

  # B: claude=same (first), codex=raise (last).
  _b="$T/and-b"; install_to "$_b" "$T/ch-and-b" --agents=claude,codex
  _c="$_b/.harness/harness.config.yaml"
  set_models "$_c" builder standard; set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.claude.reasoning' 'sonnet'
  set_models "$_c" 'pin.codex.standard' '"gpt-5"'
  set_models "$_c" 'pin.codex.reasoning' '"gpt-5-codex"'
  install_to "$_b" "$T/ch-and-b" --agents=claude,codex
  [ "$(verdict_for "$_b" claude)" = same ] \
    || fail "F05-R3: precondition B — claude is '$(verdict_for "$_b" claude)', not same"
  [ "$(verdict_for "$_b" codex)" = raise ] \
    || fail "F05-R3: precondition B — codex is '$(verdict_for "$_b" codex)', not raise"
  [ "$(head -n 1 "$_b/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R3: same-first + raise-last armed — the AND reads only one front-end"

  # Control: all-raise on the SAME two front-ends does arm, so "always blocked" cannot pass.
  grep -v '^  pin\.claude\.reasoning:' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  install_to "$_b" "$T/ch-and-b" --agents=claude,codex
  [ "$(head -n 1 "$_b/.harness/.escalation-arming")" = armed ] \
    || fail "F05-R3: control — an all-raise two-front-end target did not arm"
  pass "the verdict is a conservative AND, in both front-end orders (F05-R3)"
}

# ── F05-R12: a front-end whose live artifact was NOT rewritten is `unstamped` ───
# The verdict must describe what the front-end WILL RUN, not what the config asks for.
# Whenever the installer declines to rewrite an artifact it does not own, those diverge:
# `resolve_model` reports the desired model while the role on disk keeps whatever it had.
# (Codex #3717508457 — reproduced on an opencode target where the installer printed
# "model routing changes were NOT applied" and the verdict still read `armed`.)
unstamped_artifacts_block_arming() {
  # ── leg 1: an edited opencode.json the installer refuses to rewrite ──────────
  _t="$T/unstamped-oc"; install_to "$_t" "$T/ch-uoc" --agents=opencode
  _c="$_t/.harness/harness.config.yaml"
  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.opencode.standard' '"anthropic/claude-sonnet-4"'
  set_models "$_c" 'pin.opencode.reasoning' '"anthropic/claude-opus-4"'
  install_to "$_t" "$T/ch-uoc" --agents=opencode
  # POSITIVE CONTROL FIRST: this very target arms while the artifact IS being written.
  # Without it, "blocked" below is also satisfied by opencode never arming at all.
  [ "$(verdict_for "$_t" opencode)" = raise ] \
    || fail "F05-R12: control — a pristine opencode target is '$(verdict_for "$_t" opencode)', not raise"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = armed ] \
    || fail "F05-R12: control — a pristine opencode target did not arm"

  # Edit it, so the installer declines to rewrite it and the on-disk models go stale.
  printf '{ "_operator_edited": true }\n' > "$_t/opencode.json"
  _out="$(CODEX_HOME="$T/ch-uoc" sh "$SRC/harness-install.sh" --agents=opencode "$_t" 2>&1)" \
    || fail "F05-R12: install over an edited opencode.json exited non-zero"
  # Fixture precondition: the installer must actually have DECLINED. If it rewrote the file
  # there is no divergence to detect and the case proves nothing.
  printf '%s' "$_out" | grep -q 'model routing changes were NOT applied' \
    || fail "F05-R12: precondition — the installer did not decline to rewrite opencode.json"
  [ "$(verdict_for "$_t" opencode)" = unstamped ] \
    || fail "F05-R12: an unrewritten opencode.json gave '$(verdict_for "$_t" opencode)', not unstamped"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R12: an unstamped opencode front-end still armed — the config's model is not the one it will run"

  # ── leg 2: a foreign .codex/agents/builder-heavy.toml ────────────────────────
  _t="$T/unstamped-cx"; install_to "$_t" "$T/ch-ucx" --agents=codex
  _c="$_t/.harness/harness.config.yaml"
  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.codex.standard' '"gpt-5"'
  set_models "$_c" 'pin.codex.reasoning' '"gpt-5-codex"'
  install_to "$_t" "$T/ch-ucx" --agents=codex
  [ "$(verdict_for "$_t" codex)" = raise ] \
    || fail "F05-R12: control — a pristine codex target is '$(verdict_for "$_t" codex)', not raise"

  printf 'name = "builder-heavy"\n# hand-edited by the operator\n' > "$_t/.codex/agents/builder-heavy.toml"
  _out="$(CODEX_HOME="$T/ch-ucx" sh "$SRC/harness-install.sh" --agents=codex "$_t" 2>&1)" \
    || fail "F05-R12: install over a foreign builder-heavy.toml exited non-zero"
  printf '%s' "$_out" | grep -q 'builder-heavy.toml is foreign or edited' \
    || fail "F05-R12: precondition — the installer did not decline to rewrite builder-heavy.toml"
  [ "$(verdict_for "$_t" codex)" = unstamped ] \
    || fail "F05-R12: a foreign builder-heavy.toml gave '$(verdict_for "$_t" codex)', not unstamped"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R12: an unstamped codex front-end still armed"

  # ── leg 2b: a SYMLINKED builder-heavy.toml ──────────────────────────────────
  # §5f's own per-file pre-check `continue`s BEFORE install_codex_agent is reached, so a
  # guard that marked `unstamped` at each refusal site inside that function missed this path
  # entirely and still produced `armed` over a live role with no model (Codex #3717604849).
  # The check is now outcome-based — live file vs a freshly generated one — which is what
  # makes this leg and leg 2 the same question rather than two special cases.
  _t="$T/unstamped-sym"; install_to "$_t" "$T/ch-usy" --agents=codex
  _c="$_t/.harness/harness.config.yaml"
  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.codex.standard' '"gpt-5"'
  set_models "$_c" 'pin.codex.reasoning' '"gpt-5-codex"'
  install_to "$_t" "$T/ch-usy" --agents=codex
  [ "$(verdict_for "$_t" codex)" = raise ] \
    || fail "F05-R12: control — a pristine codex target is '$(verdict_for "$_t" codex)', not raise"
  _foreign="$T/foreign-builder-heavy.toml"
  printf 'name = "builder-heavy"\n# foreign, no model key\n' > "$_foreign"
  rm -f "$_t/.codex/agents/builder-heavy.toml"
  ln -s "$_foreign" "$_t/.codex/agents/builder-heavy.toml"
  _out="$(CODEX_HOME="$T/ch-usy" sh "$SRC/harness-install.sh" --agents=codex "$_t" 2>&1)" \
    || fail "F05-R12: install over a symlinked builder-heavy.toml exited non-zero"
  printf '%s' "$_out" | grep -q 'builder-heavy.toml is a symlinked destination' \
    || fail "F05-R12: precondition — the installer did not decline the symlinked builder-heavy.toml"
  [ "$(verdict_for "$_t" codex)" = unstamped ] \
    || fail "F05-R12: a symlinked builder-heavy.toml gave '$(verdict_for "$_t" codex)', not unstamped"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R12: a symlinked builder-heavy role still armed"
  # The symlink and its target must be untouched — the comparison must not follow the link.
  [ -L "$_t/.codex/agents/builder-heavy.toml" ] \
    || fail "F05-R12: the symlinked role was replaced"
  [ "$(cat "$_foreign")" = "$(printf 'name = "builder-heavy"\n# foreign, no model key')" ] \
    || fail "F05-R12: the symlink's target was written through"

  # ── leg 3: the ledger is SCOPED — a foreign non-Builder role must not block ──
  # Over-blocking is a real failure mode too: a hand-edited scout.toml says nothing about
  # whether escalating raises the *Builder's* model, and disabling escalation over it would
  # be a guard that fires on the wrong signal.
  _t="$T/unstamped-scope"; install_to "$_t" "$T/ch-usc" --agents=codex
  _c="$_t/.harness/harness.config.yaml"
  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.codex.standard' '"gpt-5"'
  set_models "$_c" 'pin.codex.reasoning' '"gpt-5-codex"'
  install_to "$_t" "$T/ch-usc" --agents=codex
  printf 'name = "scout"\n# hand-edited by the operator\n' > "$_t/.codex/agents/scout.toml"
  _out="$(CODEX_HOME="$T/ch-usc" sh "$SRC/harness-install.sh" --agents=codex "$_t" 2>&1)" \
    || fail "F05-R12: install over a foreign scout.toml exited non-zero"
  printf '%s' "$_out" | grep -q 'scout.toml is foreign or edited' \
    || fail "F05-R12: precondition — the installer did not decline to rewrite scout.toml"
  [ "$(verdict_for "$_t" codex)" = raise ] \
    || fail "F05-R12: a foreign scout.toml blocked arming — the ledger is not scoped to the Builder roles"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = armed ] \
    || fail "F05-R12: a foreign non-Builder role disarmed the target"
  pass "a front-end whose live artifact was not rewritten reads unstamped and blocks (F05-R12)"
}

# ── F05-R4: written when something resolves, absent otherwise, reclaimed ────────
artifact_written_and_reclaimed() {
  _t="$T/reclaim"
  # A fully-`inherit` target — the shipped default — must not grow a file a never-configured
  # target lacks. install_to already fails the case if the install exits non-zero, so
  # "absent" cannot be satisfied by the installer dying.
  install_to "$_t" "$T/ch-rec" --agents=claude
  [ -f "$_t/.harness/.escalation-arming" ] \
    && fail "F05-R4: a fully-inherit install grew an arming artifact"

  # Configure ⇒ it appears. Presence must be demonstrated on the same code path, or the
  # absence above proves nothing.
  _c="$_t/.harness/harness.config.yaml"
  set_models "$_c" builder standard; set_models "$_c" builder-heavy reasoning
  install_to "$_t" "$T/ch-rec" --agents=claude
  [ -f "$_t/.harness/.escalation-arming" ] \
    || fail "F05-R4: control — a configured install wrote no artifact, so the absence legs are vacuous"

  # Switch everything back ⇒ it is REMOVED, not left stale. Asserting only the final absence
  # would pass against an installer that never wrote it at all.
  set_models "$_c" builder inherit; set_models "$_c" builder-heavy inherit
  install_to "$_t" "$T/ch-rec" --agents=claude
  [ -f "$_t/.harness/.escalation-arming" ] \
    && fail "F05-R4: switching every role back to inherit left a stale arming artifact"
  pass "the artifact is written only while a model resolves, and reclaimed when none does (F05-R4)"
}

# ── F05-R5: a symlinked artifact is never followed, on either side ──────────────
symlinked_arming_is_refused() {
  _t="$T/symlink"; install_to "$_t" "$T/ch-sym" --agents=claude
  _c="$_t/.harness/harness.config.yaml"
  set_models "$_c" builder standard; set_models "$_c" builder-heavy reasoning

  _sentinel="$T/sym-target"; printf 'DO-NOT-TOUCH\n' > "$_sentinel"
  ln -s "$_sentinel" "$_t/.harness/.escalation-arming"
  _out="$(CODEX_HOME="$T/ch-sym" sh "$SRC/harness-install.sh" --agents=claude "$_t" 2>&1)" \
    || fail "F05-R5: the install exited non-zero on a symlinked artifact"
  [ -L "$_t/.harness/.escalation-arming" ] \
    || fail "F05-R5: the symlink was replaced or unlinked — rm -f went through it"
  [ "$(readlink "$_t/.harness/.escalation-arming")" = "$_sentinel" ] \
    || fail "F05-R5: the symlink now points somewhere else"
  [ "$(cat "$_sentinel")" = "DO-NOT-TOUCH" ] \
    || fail "F05-R5: the symlink's TARGET was written through"
  printf '%s' "$_out" | grep -q 'escalation-arming is a symlink' \
    || fail "F05-R5: no warning was emitted for the symlinked artifact"

  # Control in the same test: with the symlink gone, this very target DOES get an artifact
  # written. "The sentinel survived" is otherwise also satisfied by the installer never
  # writing anything at all.
  rm -f "$_t/.harness/.escalation-arming"
  install_to "$_t" "$T/ch-sym" --agents=claude
  [ -f "$_t/.harness/.escalation-arming" ] && [ ! -L "$_t/.harness/.escalation-arming" ] \
    || fail "F05-R5: control — the same target wrote no regular artifact once the symlink was removed"

  # And the READ side: the rule treats a symlinked artifact as absent, never following it.
  _sd="$T/sym-read"; mkdir -p "$_sd"
  printf 'models:\n  builder-heavy: reasoning\nescalation:\n  after_rejections: 2\n' > "$_sd/harness.config.yaml"
  printf 'armed\nclaude=raise\n' > "$T/sym-armed-source"
  ln -s "$T/sym-armed-source" "$_sd/.escalation-arming"
  [ "$(role '' 99 --config "$_sd/harness.config.yaml")" = builder ] \
    || fail "F05-R5: the rule followed a symlinked artifact and armed from it"
  # Control: the identical bytes as a REGULAR file do arm, so the refusal is about the link.
  rm -f "$_sd/.escalation-arming"; cp "$T/sym-armed-source" "$_sd/.escalation-arming"
  [ "$(role '' 99 --config "$_sd/harness.config.yaml")" = builder-heavy ] \
    || fail "F05-R5: control — the same bytes as a regular file did not arm"
  pass "a symlinked artifact is neither written, removed, nor read through (F05-R5)"
}

# ── F05-R6: the rule escalates only on an exact `armed` ─────────────────────────
rule_requires_armed_artifact() {
  # POSITIVE CONTROL FIRST, in this run: these very inputs escalate when armed. Without it
  # every leg below is also satisfied by escalation being broken outright.
  [ "$(role '' 99)" = builder-heavy ] || fail "F05-R6: control — an armed fixture did not escalate"

  [ "$(role '' 99 --config "$(mkfix blocked 2 blocked claude=none)")" = builder ] \
    || fail "F05-R6: a blocked verdict escalated"
  [ "$(role '' 99 --config "$(mkfix novrd 2 '')")" = builder ] \
    || fail "F05-R6: an absent verdict escalated"

  # An empty file, garbage, and the substring bait: `disarmed` CONTAINS `armed`, so a
  # `case … *armed*)` or a `grep armed` implementation arms on it.
  # The whitespace variants are the fail-open a `tr -d '[:space:]'` normalization allows:
  # `armed `, ` armed` and even `a r m e d` / `ar med` all collapse to `armed`, so a file the
  # installer could not have written would arm the target (Codex #3723207550). The first line
  # is compared RAW. Tabs included — `[:space:]` covers them and a space-only test would miss
  # a tab-normalizing implementation.
  for _bad in '' 'garbage' 'disarmed' 'ARMED' 'armed extra' 'armed ' ' armed' 'a r m e d' 'ar med' '	armed'; do
    _d="$T/fix-bad$(printf '%s' "$_bad" | tr -cd '[:alnum:]')x"; mkdir -p "$_d"
    printf 'models:\n  builder-heavy: reasoning\nescalation:\n  after_rejections: 2\n' > "$_d/harness.config.yaml"
    printf '%s\n' "$_bad" > "$_d/.escalation-arming"
    [ "$(role '' 99 --config "$_d/harness.config.yaml")" = builder ] \
      || fail "F05-R6: a first line of '$_bad' armed the rule"
  done
  # Positive control LAST, so the loop above cannot have passed by the tool losing the ability
  # to arm at all: the exact string still works.
  _okd="$T/fix-exact-ok"; mkdir -p "$_okd"
  printf 'models:\n  builder-heavy: reasoning\nescalation:\n  after_rejections: 2\n' > "$_okd/harness.config.yaml"
  printf 'armed\n' > "$_okd/.escalation-arming"
  [ "$(role '' 99 --config "$_okd/harness.config.yaml")" = builder-heavy ] \
    || fail "F05-R6: control — an exact 'armed' stopped arming, so the reject cases prove nothing"
  pass "only an exact 'armed' first line escalates; whitespace variants and garbage do not (F05-R6)"
}

# ── F05-R7: both gates are required, on both triggers ───────────────────────────
both_gates_required() {
  _armed_on="$(mkfix g-both 2 armed claude=raise)"      # threshold ✓ verdict ✓
  _armed_off="$(mkfix g-thr 0 armed claude=raise)"      # threshold ✗ verdict ✓
  _block_on="$(mkfix g-vrd 2 blocked claude=none)"      # threshold ✓ verdict ✗

  # ROUND trigger.
  [ "$(role '' 99 --config "$_armed_on")" = builder-heavy ] \
    || fail "F05-R7: control — both gates open did not escalate on the round trigger"
  [ "$(role '' 99 --config "$_armed_off")" = builder ] \
    || fail "F05-R7: an armed verdict alone escalated (threshold 0)"
  [ "$(role '' 99 --config "$_block_on")" = builder ] \
    || fail "F05-R7: a positive threshold alone escalated (verdict blocked)"

  # COMPLEXITY trigger — it must not bypass the arming gate. This is the leg a fix that only
  # guarded the round arm would fail, and it is the same asymmetry E17-F03 had to close for 0.
  [ "$(role complex 1 --config "$_armed_on")" = builder-heavy ] \
    || fail "F05-R7: control — both gates open did not escalate on the complexity trigger"
  [ "$(role complex 1 --config "$_armed_off")" = builder ] \
    || fail "F05-R7: the complexity trigger bypassed the threshold veto"
  [ "$(role complex 1 --config "$_block_on")" = builder ] \
    || fail "F05-R7: the complexity trigger bypassed the arming gate"
  pass "escalation requires a positive threshold AND an armed verdict, on both triggers (F05-R7)"
}

# ── F05-R8: the three declines are distinguishable, and none is fatal ───────────
decline_reasons_are_distinguishable() {
  _none="$(mkfix d-none 2 '')"                                  # no verdict recorded
  _blk="$(mkfix d-blk 2 blocked codex=none opencode=same)"      # blocked, with detail
  _off="$(mkfix d-off 0 armed claude=raise)"                    # operator's veto

  _m_none="$(err complex 1 --config "$_none")"
  _m_blk="$(err complex 1 --config "$_blk")"
  _m_off="$(err complex 1 --config "$_off")"

  for _m in "$_m_none" "$_m_blk" "$_m_off"; do
    [ -n "$_m" ] || fail "F05-R8: a declined complexity trigger produced no advisory at all"
  done
  # Collapsing any two into one message would leave the operator unable to tell "re-run the
  # installer" from "fix a named front-end" from "you turned this off".
  [ "$_m_none" != "$_m_blk" ] || fail "F05-R8: the no-verdict and blocked advisories are identical"
  [ "$_m_none" != "$_m_off" ] || fail "F05-R8: the no-verdict and threshold-veto advisories are identical"
  [ "$_m_blk"  != "$_m_off" ] || fail "F05-R8: the blocked and threshold-veto advisories are identical"

  printf '%s' "$_m_blk" | grep -q 'codex=none' \
    || fail "F05-R8: the blocked advisory does not name the offending front-end"
  printf '%s' "$_m_blk" | grep -q 'opencode=same' \
    || fail "F05-R8: the blocked advisory names only the first offender"
  printf '%s' "$_m_none" | grep -q 'escalation-arming' \
    || fail "F05-R8: the no-verdict advisory does not name the missing artifact"
  printf '%s' "$_m_off" | grep -q 'after_rejections' \
    || fail "F05-R8: the threshold-veto advisory does not name the key the operator set"

  # A blocked artifact must not list a raising front-end as the blocker.
  _mixed="$(err complex 1 --config "$(mkfix d-mix 2 blocked claude=raise codex=none)")"
  printf '%s' "$_mixed" | grep -q 'codex=none' || fail "F05-R8: the blocker was not named"
  printf '%s' "$_mixed" | grep -q 'claude=raise' \
    && fail "F05-R8: a front-end that DID raise was reported as blocking"

  # None of them fails the build.
  for _cfg in "$_none" "$_blk" "$_off"; do
    [ "$(rc complex 1 --config "$_cfg")" = 0 ] || fail "F05-R8: a declined escalation exited non-zero"
  done

  # The ROUND arm reports too, but only once the threshold is real and exceeded — that is
  # the one moment the information is actionable. It stays SILENT under the operator's 0,
  # where there is no round anything "would have" exceeded (F03-R12's noise argument).
  [ -n "$(err '' 99 --config "$_blk")" ] \
    || fail "F05-R8: a blocked round-trigger decline was silent at the moment it mattered"
  [ -z "$(err '' 99 --config "$_off")" ] \
    || fail "F05-R8: the round arm warned under the operator's 0 — that is noise on every build"
  [ -z "$(err '' 1 --config "$_blk")" ] \
    || fail "F05-R8: warned on a round that would not have escalated anyway"
  pass "the three declines are distinct, name what to fix, and never fail the build (F05-R8)"
}

# ── F05-R11: the docs and the shipped config agree on the default ──────────────
# Three review rounds into E17-F03, the recurring defect was not the code — it was PROSE
# describing an older version of the rule. A doc that contradicts the tool is worse than a
# missing doc: the operator acts on it. So pin the facts most likely to move.
docs_agree_with_the_shipped_default() {
  _shipped="$(awk '/^escalation:/{e=1;next} e&&/^[^ #]/{e=0} e&&/^  after_rejections:/{sub(/^  after_rejections:[[:space:]]*/,"");sub(/[[:space:]]*#.*$/,"");print;exit}' "$SRC/harness.config.yaml")"
  [ -n "$_shipped" ] || fail "F05-R11: could not read the shipped escalation.after_rejections"
  [ "$_shipped" = 2 ] || fail "F05-R11: the shipped default is '$_shipped', not 2"

  # The tool must actually BEHAVE that way with the shipped config, not merely record it. A
  # doc-only change cannot satisfy both halves. The arming artifact is passed explicitly:
  # the repo root is not an installed target and has none.
  printf 'armed\nclaude=raise\n' > "$T/shipped-armed"
  [ "$(sh "$TOOL" '' 3 --config "$SRC/harness.config.yaml" --arming "$T/shipped-armed" 2>/dev/null)" = builder-heavy ] \
    || fail "F05-R11: the shipped config did not escalate at round 3 with an armed verdict"
  [ "$(sh "$TOOL" '' 2 --config "$SRC/harness.config.yaml" --arming "$T/shipped-armed" 2>/dev/null)" = builder ] \
    || fail "F05-R11: the shipped config escalated at round 2 — the threshold is not 2"
  # And with NO verdict, the same shipped config declines — the second gate is real.
  [ "$(sh "$TOOL" '' 3 --config "$SRC/harness.config.yaml" --arming "$T/nope" 2>/dev/null)" = builder ] \
    || fail "F05-R11: the shipped config escalated with no recorded verdict"

  # No operator-facing doc may still claim the pre-opt-in meaning of 0.
  for _d in "$SRC/docs/WORKFLOW.md" "$SRC/harness.config.yaml" "$SRC/agents/orchestrator.md"; do
    grep -qi 'disables rejection-based\|leaving `complexity: complex` as the only route' "$_d" \
      && fail "F05-R11: $_d still documents the pre-opt-in meaning of 0"
  done
  # Nor may any line stating the DEFAULT still say 0. The docs legitimately mention 0 as the
  # off-switch, which is why this keys off "default"/"shipped" rather than the digit alone.
  for _d in "$SRC/docs/WORKFLOW.md" "$SRC/CHANGELOG.md" "$SRC/harness.config.yaml" \
            "$SRC/agents/orchestrator.md" "$SRC/harness-install.sh" "$SRC/docs/INSTALL.md"; do
    _bad="$(grep -i 'after_rejections' "$_d" | grep -iE 'default|shipped value' | grep -v '2' || true)"
    [ -z "$_bad" ] || fail "F05-R11: $_d states a non-2 default for after_rejections: $_bad"
  done
  # Positive control: the docs DO describe the current rule, so the sweeps above are not
  # passing merely because escalation went undocumented.
  grep -qi 'disables BOTH triggers\|turns escalation OFF ENTIRELY' "$SRC/docs/WORKFLOW.md" \
    || fail "F05-R11: docs/WORKFLOW.md does not state what 0 does"
  pass "the shipped default is 2, behaves that way, and the docs say so (F05-R11)"
}

# ── F05-R11: no doc still claims the harness cannot check this ─────────────────
no_doc_claims_the_harness_cannot_check() {
  # The claim that CHANGED. E17-F03 told operators, in six places, that the harness
  # deliberately does not work out whether escalating would help and that they must verify it
  # themselves. It now does work it out. A claim repeated in six files is six defects.
  for _d in "$SRC/harness.config.yaml" "$SRC/harness-install.sh" "$SRC/tools/builder-role.sh" \
            "$SRC/agents/orchestrator.md" "$SRC/docs/WORKFLOW.md" "$SRC/CHANGELOG.md" \
            "$SRC/docs/INSTALL.md"; do
    # Several phrasings of the same superseded claim, because it was written differently in
    # each of the six files — matching only one spelling is how a sweep misses five sites.
    _bad="$(grep -in 'deliberately does .*infer\|does not try to infer\|not infer this for you\|cannot verify that assertion\|BEFORE YOU ENABLE IT\|the opt-in is your assertion' "$_d" || true)"
    [ -z "$_bad" ] || fail "F05-R11: $_d still says the harness cannot check whether escalating helps: $_bad"
  done
  # A SECOND superseded claim, and the one the round-4 review caught: E17-F02's docs said
  # nothing routed to `builder-heavy` automatically. E17-F03 falsified that (the rule shipped)
  # and E17-F05 doubly so (it is on by default when armed). The first version of this sweep
  # knew only the "harness cannot check" phrasing, so docs/INSTALL.md kept telling operators
  # to invoke the heavy Builder by hand while the test stayed green. One sweep, both classes.
  for _d in "$SRC/harness.config.yaml" "$SRC/agents/orchestrator.md" "$SRC/docs/WORKFLOW.md" \
            "$SRC/docs/INSTALL.md" "$SRC/tools/builder-role.sh"; do
    _bad="$(grep -in 'Nothing routes to it automatically\|you invoke it by hand\|is a separate feature' "$_d" || true)"
    [ -z "$_bad" ] || fail "F05-R11: $_d still says escalation is manual-only: $_bad"
  done

  # The CHANGELOG is deliberately NOT in either sweep above: it is a dated historical record,
  # and an entry describing what v0.56.0 shipped is *correct* even when superseded. Sweeping
  # the whole file would fire on every accurate historical entry — the "guard that has to
  # special-case a disclaimer" shape, which the E17-F03 review already established loses.
  # What DOES matter is that the NEWEST entry never reads as a stale current statement, so
  # scope the check to it: everything above the second `## [` heading.
  _newest="$T/changelog-newest"
  awk '/^## \[/ { n++ } n == 1' "$SRC/CHANGELOG.md" > "$_newest"
  [ -s "$_newest" ] || fail "F05-R11: could not extract the newest CHANGELOG entry"
  # The control proves the awk above really grabbed the CURRENT release's entry rather than
  # an empty or stale slice. It is derived from VERSION, never a frozen literal: a hardcoded
  # version here fails on the next release for a reason that has nothing to do with
  # escalation, which is exactly what it did when v0.59.0 landed (it read `0.58.0`).
  _cl_expect="$(tr -d ' \t\r\n' < "$SRC/VERSION")"
  [ -n "$_cl_expect" ] || fail "F05-R11: VERSION is empty — cannot anchor the CHANGELOG control"
  _cl_actual="$(awk 'match($0, /^## \[[^]]+\]/) { print substr($0, RSTART + 4, RLENGTH - 5); exit }' "$SRC/CHANGELOG.md")"
  [ "$_cl_actual" = "$_cl_expect" ] \
    || fail "F05-R11: control — newest CHANGELOG entry is [$_cl_actual], VERSION is [$_cl_expect]"
  _bad="$(grep -in 'Nothing routes to it automatically\|you invoke it by hand\|deliberately does .*infer\|the opt-in is your assertion' "$_newest" || true)"
  [ -z "$_bad" ] || fail "F05-R11: the newest CHANGELOG entry carries a superseded claim: $_bad"

  # Positive control #1: the docs describe the mechanism that replaced it.
  _seen=0
  for _d in "$SRC/harness.config.yaml" "$SRC/docs/WORKFLOW.md" "$SRC/agents/orchestrator.md" \
            "$SRC/docs/INSTALL.md"; do
    grep -q 'escalation-arming' "$_d" && _seen=$((_seen + 1))
  done
  [ "$_seen" -ge 4 ] \
    || fail "F05-R11: only $_seen of 4 operator-facing docs mention .harness/.escalation-arming"
  # Positive control #2: the STATED LIMIT is documented. The verdict proves the model
  # changes, not that it is stronger — over-claiming that is the failure mode this feature
  # is one round away from, so the honest sentence is pinned rather than trusted.
  for _d in "$SRC/harness.config.yaml" "$SRC/docs/WORKFLOW.md"; do
    grep -qi 'not check.*STRONGER\|DOES NOT CHECK' "$_d" \
      || fail "F05-R11: $_d does not state that the verdict proves change, not strength"
  done
  pass "both superseded claims are gone from all seven operator-facing sites (F05-R11)"
}

# ── usage errors ────────────────────────────────────────────────────────────────
usage_errors_are_loud() {
  # A malformed COMPLEXITY is a human typo and must never fail a build (F03-R2). A malformed
  # ROUND means the CALLER is broken — coercing it would hide that while changing models.
  [ "$(rc '' notanumber)" = 4 ] || fail "usage: a non-numeric round did not exit 4"
  sh "$TOOL" only-one >/dev/null 2>&1 && fail "usage: a missing round did not exit non-zero"
  sh "$TOOL" a 1 b >/dev/null 2>&1 && fail "usage: an extra positional did not exit non-zero"
  sh "$TOOL" '' 1 --nope >/dev/null 2>&1 && fail "usage: an unknown option did not exit non-zero"
  sh "$TOOL" '' 1 --arming >/dev/null 2>&1 && fail "usage: --arming with no value did not exit non-zero"
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
zero_still_hard_disables
unconfigured_is_silent_and_standard
durable_state_only
delegate_never_escalates
prose_records_the_choice
telemetry_contract_intact
the_tool_does_not_infer_resolution
verdict_comes_from_resolve_model
arming_artifact_shape
verdict_truth_table
and_across_front_ends
unstamped_artifacts_block_arming
artifact_written_and_reclaimed
symlinked_arming_is_refused
rule_requires_armed_artifact
both_gates_required
decline_reasons_are_distinguishable
docs_agree_with_the_shipped_default
no_doc_claims_the_harness_cannot_check
usage_errors_are_loud

echo "test_escalation.sh: all cases passed"
