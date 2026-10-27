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
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)
export CODEX_HOME="$T/codex-home"
# E25-F01: non-Claude front-ends are parked by default on FRESH targets, so a bare
# installer run now stamps claude only. This suite's fixtures predate the flip and
# assert artifacts across the full matrix; pin the pre-flip selection explicitly
# (an explicit --agents in any call still wins over this env seed).
export HARNESS_AGENTS="claude,codex,opencode"

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
# case changes ONLY a `pin.<front-end>.<tier>` between installs — a value no independent
# verdict logic could get right without going through resolve_model's per-front-end pin
# handling — and asserts the verdict flips. Both directions, so a hardcoded answer fails one
# of them.
#
# The front-end is `opencode`, not `codex`: since E99-F163 the Codex verdict also weighs
# `model_reasoning_effort`. Two roles on the SAME tier necessarily share both a pin key and
# an effort, while two roles on DIFFERENT tiers already differ by effort with no pin at all —
# so on codex a pin change can no longer be the SOLE flip this case needs. OpenCode has no
# effort axis, so its verdict remains a pure function of `resolve_model`'s pin table, which is
# exactly what this case isolates. Codex's effort path is covered by
# `effort_only_differentiation_arms`.
verdict_comes_from_resolve_model() {
  _t="$T/rm"; install_to "$_t" "$T/ch-rm" --agents=opencode
  _c="$_t/.harness/harness.config.yaml"
  # builder resolves (pinned), builder-heavy names a tier that opencode does NOT alias and that
  # carries no pin ⇒ `none`, the exact downgrade #3716777878 described.
  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.opencode.standard' '"anthropic/claude-sonnet-4"'
  install_to "$_t" "$T/ch-rm" --agents=opencode
  # Fixture precondition: a pin key that lands OUTSIDE the models: block resolves nothing for
  # either role, and the downgrade could not appear — which would read as "not reproducible".
  [ "$(verdict_for "$_t" opencode)" = none ] \
    || fail "F05-R1: precondition — expected opencode=none with builder pinned and reasoning unpinned, got '$(verdict_for "$_t" opencode)'"

  # Add ONLY the reasoning pin. Nothing else about the config changes.
  set_models "$_c" 'pin.opencode.reasoning' '"anthropic/claude-opus-4"'
  install_to "$_t" "$T/ch-rm" --agents=opencode
  [ "$(verdict_for "$_t" opencode)" = raise ] \
    || fail "F05-R1: adding pin.opencode.reasoning did not flip the verdict to raise (got '$(verdict_for "$_t" opencode)')"

  # And back: removing it must restore `none`, so the `raise` above is not a one-way latch.
  grep -v '^  pin\.opencode\.reasoning:' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  install_to "$_t" "$T/ch-rm" --agents=opencode
  [ "$(verdict_for "$_t" opencode)" = none ] \
    || fail "F05-R1: removing pin.opencode.reasoning did not restore none (got '$(verdict_for "$_t" opencode)')"
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
  _bad="$(sed -n '2,$p' "$_f" | grep -Ev '^(claude|codex|opencode)=(raise|none|same|neither|unstamped)$' || true)"
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

# ── F05-R13 / E99-F163: a Codex effort difference alone arms ────────────────────
# The deferred gap: `builder: standard` / `builder-heavy: reasoning` on codex stamps NO
# `model` (neither tier is pinned) but DOES stamp `medium`/`high` `model_reasoning_effort`
# (E99-F161), so the roles on disk genuinely differ while a model-only comparison read them
# as `same` and disarmed the target. Verified behaviourally, not by grepping the resolver:
# the installer is run and the target's own `.codex/agents/*.toml` + `.harness/.escalation-arming`
# are read back. The keep-cases come from the brief: identical stamps are still `same`, and a
# role resolving to nothing on either axis is still `none`/`neither`.
effort_only_differentiation_arms() {
  _t="$T/effort"; install_to "$_t" "$T/ch-effort" --agents=codex
  _c="$_t/.harness/harness.config.yaml"
  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  install_to "$_t" "$T/ch-effort" --agents=codex

  # Precondition: the target really is effort-ONLY — no `model` key on EITHER Builder role, but
  # distinct efforts. Without this the case could pass on a model pin set elsewhere.
  grep -q '^model_reasoning_effort = "medium"$' "$_t/.codex/agents/builder.toml" \
    || fail "E99-F163: builder.toml did not stamp medium effort"
  grep -q '^model_reasoning_effort = "high"$' "$_t/.codex/agents/builder-heavy.toml" \
    || fail "E99-F163: builder-heavy.toml did not stamp high effort"
  grep -q '^model = ' "$_t/.codex/agents/builder.toml" \
    && fail "E99-F163 precondition: builder.toml carries a model, so the effort axis is not isolated"
  grep -q '^model = ' "$_t/.codex/agents/builder-heavy.toml" \
    && fail "E99-F163 precondition: builder-heavy.toml carries a model, so the effort axis is not isolated"

  # The verdict and the artifact that gates the actual escalation.
  [ "$(verdict_for "$_t" codex)" = raise ] \
    || fail "E99-F163: an effort-only Codex difference gave '$(verdict_for "$_t" codex)', not raise"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = armed ] \
    || fail "E99-F163: an effort-only Codex difference did not arm"

  # SAME effort is still `same`: the widened comparison must not collapse into "any pair of
  # tiers raises". Both roles on the SAME tier share their effort, so only a `model` pin could
  # differ, and neither is pinned.
  set_models "$_c" builder-heavy standard
  install_to "$_t" "$T/ch-effort" --agents=codex
  [ "$(verdict_for "$_t" codex)" = same ] \
    || fail "E99-F163: identical effort stamps gave '$(verdict_for "$_t" codex)', not same"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = blocked ] \
    || fail "E99-F163: an identical-effort Codex pair armed"

  # NOTHING on either axis is still `none`/`neither`. `builder` resolves only through effort,
  # so an `inherit` heavy role is the downgrade (`none`); with BOTH Builder roles inherited but
  # another role still resolving, the target writes an artifact and the cell is `neither`.
  set_models "$_c" builder-heavy inherit
  install_to "$_t" "$T/ch-effort" --agents=codex
  [ "$(verdict_for "$_t" codex)" = none ] \
    || fail "E99-F163: an inherit heavy role gave '$(verdict_for "$_t" codex)', not none"
  set_models "$_c" builder inherit
  set_models "$_c" reviewer standard
  install_to "$_t" "$T/ch-effort" --agents=codex
  [ "$(verdict_for "$_t" codex)" = neither ] \
    || fail "E99-F163: both roles resolving nothing gave '$(verdict_for "$_t" codex)', not neither"
  [ "$(head -n 1 "$_t/.harness/.escalation-arming")" = blocked ] \
    || fail "E99-F163: a neither verdict armed"

  pass "a Codex effort-only difference arms; same effort stays same; nothing on either axis stays none/neither (E99-F163)"
}

# ── F05-R3: the conservative AND, asserted in BOTH orders ───────────────────────
# A first-wins or last-wins bug passes exactly one of these two. $AGENT_KEYS orders claude
# first and opencode last, so one config puts the raising front-end first and the other last.
# The blocking front-end is `opencode` rather than `codex`: on codex, a role with a
# non-`inherit` tier resolves an effort even unpinned, so a `none` codex role is no longer
# reachable beside a raising claude role (different tiers ⇒ effort differs ⇒ raise). OpenCode
# has no effort axis, so `pin.opencode.standard` without `pin.opencode.reasoning` is still the
# `none` downgrade.
and_across_front_ends() {
  # A: claude=raise (first), opencode=none (last).
  _a="$T/and-a"; install_to "$_a" "$T/ch-and-a" --agents=claude,opencode
  _c="$_a/.harness/harness.config.yaml"
  set_models "$_c" builder standard; set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.opencode.standard' '"anthropic/claude-sonnet-4"'
  install_to "$_a" "$T/ch-and-a" --agents=claude,opencode
  [ "$(verdict_for "$_a" claude)" = raise ] \
    || fail "F05-R3: precondition A — claude is '$(verdict_for "$_a" claude)', not raise"
  [ "$(verdict_for "$_a" opencode)" = none ] \
    || fail "F05-R3: precondition A — opencode is '$(verdict_for "$_a" opencode)', not none"
  [ "$(head -n 1 "$_a/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R3: raise-first + none-last armed — the AND became an OR"

  # B: claude=same (first), opencode=raise (last).
  _b="$T/and-b"; install_to "$_b" "$T/ch-and-b" --agents=claude,opencode
  _c="$_b/.harness/harness.config.yaml"
  set_models "$_c" builder standard; set_models "$_c" builder-heavy reasoning
  set_models "$_c" 'pin.claude.reasoning' 'sonnet'
  set_models "$_c" 'pin.opencode.standard' '"anthropic/claude-sonnet-4"'
  set_models "$_c" 'pin.opencode.reasoning' '"anthropic/claude-opus-4"'
  install_to "$_b" "$T/ch-and-b" --agents=claude,opencode
  [ "$(verdict_for "$_b" claude)" = same ] \
    || fail "F05-R3: precondition B — claude is '$(verdict_for "$_b" claude)', not same"
  [ "$(verdict_for "$_b" opencode)" = raise ] \
    || fail "F05-R3: precondition B — opencode is '$(verdict_for "$_b" opencode)', not raise"
  [ "$(head -n 1 "$_b/.harness/.escalation-arming")" = blocked ] \
    || fail "F05-R3: same-first + raise-last armed — the AND reads only one front-end"

  # Control: all-raise on the SAME two front-ends does arm, so "always blocked" cannot pass.
  grep -v '^  pin\.claude\.reasoning:' "$_c" > "$_c.t" && mv "$_c.t" "$_c"
  install_to "$_b" "$T/ch-and-b" --agents=claude,opencode
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
  # would pass against an installer that never wrote it at all. Capture stdout here (not
  # install_to's /dev/null) so the reclaim MESSAGE is pinned too: the gate is model-or-effort
  # now, so a message still naming the model alone understates the remedy (E99-F163 F1b).
  set_models "$_c" builder inherit; set_models "$_c" builder-heavy inherit
  _out="$(CODEX_HOME="$T/ch-rec" sh "$SRC/harness-install.sh" --agents=claude "$_t" 2>&1)" \
    || fail "F05-R4: the reclaim install exited non-zero"
  printf '%s' "$_out" | grep -q 'no role resolves on either axis any more' \
    || fail "E99-F163 F1b: the reclaim message still says the verdict is model-only"
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

# ── F05-R13: the operator docs say the verdict weighs effort (E99-F163) ──────────
# The prose that named the gap ("`escalation_verdict` still compares `model` only") had to move
# with the code. These are section-scoped POSITIVE anchors: a whole-file grep for
# `escalation_verdict`/`model_reasoning_effort` co-occurrence stays green on the PRE-change
# blob (the old sentence carries both tokens, inverted), so each anchor is a phrase only the
# new text has, extracted from the section that owns the rule.
effort_is_named_in_the_operator_docs() {
  _inst="$T/doc-install"
  awk 'BEGIN{h="### Codex reasoning effort"} /^#{2,} /{k=(index($0,h)>0);next} k' \
    "$SRC/docs/INSTALL.md" | tr '\n' ' ' > "$_inst"
  [ -s "$_inst" ] || fail "E99-F163: the Codex reasoning effort section did not extract — the heading moved"
  grep -qiE 'effort difference alone' "$_inst" \
    || fail "E99-F163: docs/INSTALL.md's Codex effort section does not say an effort difference alone arms"

  # F1c: the EARLIER `builder-heavy` section (INSTALL.md:864-873) describes the same mechanism
  # and had to move with it. Pin it section-scoped: the "Codex reasoning effort" section above
  # also names the whole stamp, so a whole-file anchor would stay green while this earlier
  # section kept saying a single "own resolver" checks whether "the model" is stronger.
  _bh="$T/doc-builder-heavy"
  awk 'BEGIN{h="### `builder-heavy`"} /^#{2,} /{k=(index($0,h)>0);next} k' \
    "$SRC/docs/INSTALL.md" | tr '\n' ' ' > "$_bh"
  [ -s "$_bh" ] || fail "E99-F163 F1c: the builder-heavy section did not extract — the heading moved"
  grep -qiE 'own[[:space:]]+resolvers' "$_bh" \
    || fail "E99-F163 F1c: docs/INSTALL.md still says a single 'own resolver'"
  grep -qiE 'whole[[:space:]]+resolved[[:space:]]+stamp' "$_bh" \
    || fail "E99-F163 F1c: docs/INSTALL.md's builder-heavy section does not name the whole resolved stamp"
  grep -qiE '\*\*stamp\*\*[[:space:]]+is[[:space:]]+\*stronger\*' "$_bh" \
    || fail "E99-F163 F1c: docs/INSTALL.md still says the check is about the 'model' being stronger"

  _wf="$T/doc-workflow"
  awk 'BEGIN{h="### Which Builder runs"} /^#{2,} /{k=(index($0,h)>0);next} k' \
    "$SRC/docs/WORKFLOW.md" | tr '\n' ' ' > "$_wf"
  [ -s "$_wf" ] || fail "E99-F163: the 'Which Builder runs' section did not extract — the heading moved"
  grep -qiE 'different[[:space:]]+resolved[[:space:]]+stamp' "$_wf" \
    || fail "E99-F163: docs/WORKFLOW.md's escalation section does not say the verdict compares the whole resolved stamp"
  # F1d: the `unstamped` clause and the absent-verdict clause named a "resolved model" only.
  # Both live in this same section, so scope to $_wf and use DISTINCT anchors: a lone
  # "either axis" anchor would be satisfied by the `none` bullet below while the absent clause
  # still said "to a model".
  grep -qiE 'resolved[[:space:]]+stamp[[:space:]]+then[[:space:]]+describes' "$_wf" \
    || fail "E99-F163 F1d: docs/WORKFLOW.md's unstamped clause still says 'resolved model'"
  grep -qiE 'no[[:space:]]+role[[:space:]]+resolves[[:space:]]+on[[:space:]]+either[[:space:]]+axis' "$_wf" \
    || fail "E99-F163 F1d: docs/WORKFLOW.md's absent clause still says 'no role resolves to a model'"
  # F1e(2): the `none` bullet's "nothing on either axis" is its own claim — R11 reverted it to
  # "nothing", and all suites stayed green because only "different resolved stamp" was anchored.
  grep -qiE 'nothing[[:space:]]+on[[:space:]]+either[[:space:]]+axis' "$_wf" \
    || fail "E99-F163 F1e: docs/WORKFLOW.md's 'none' clause does not say nothing resolves on either axis"

  # And the superseded gap statement is gone. The positive anchors above prove the current rule
  # IS documented, so this negative cannot pass merely because escalation went undocumented.
  for _d in "$SRC/docs/INSTALL.md" "$SRC/docs/WORKFLOW.md"; do
    grep -qi 'compares `model` only' "$_d" \
      && fail "E99-F163: $_d still says the verdict compares model only"
  done

  # The seed block in BOTH copies names effort in the comparison. The byte-identity of the two
  # copies is pinned by prl_block()/the install convergence tests; this pins the SEMANTIC the
  # identical bytes carry, so a symmetric revert in both files cannot slip through.
  for _b in "$SRC/harness.config.yaml" "$SRC/harness-install.sh"; do
    grep -q 'whole resolved stamp, `model` plus' "$_b" \
      || fail "E99-F163: $_b's escalation seed block does not name the model+effort stamp"
  done

  # F1e(1): the stamp phrase above does NOT pin the codex BULLET three lines below it. R8
  # reverted that bullet's verdict ("arms" → "does NOT arm") in BOTH copies — byte-identically,
  # so prl_block passed — and every suite stayed green. Extract the escalation seed block
  # structurally from each copy and anchor the bullet's OWN claim; a whole-file grep for the
  # phrase would be satisfied by the docs, which say the same thing in other words.
  _seed_n=0
  for _b in "$SRC/harness.config.yaml" "$SRC/harness-install.sh"; do
    _seed_n=$((_seed_n + 1))
    _seed="$T/seed-codex-bullet-$_seed_n"
    awk '/# ESCALATION NEEDS A SECOND YES/ {k=1} k {print} k && /^  after_rejections:/ {exit}' \
      "$_b" | tr '\n' ' ' > "$_seed"
    [ -s "$_seed" ] || fail "E99-F163 F1e: the escalation seed block did not extract from $_b"
    grep -qiE 'effort[[:space:]]+difference[[:space:]]+alone[[:space:]]+arms' "$_seed" \
      || fail "E99-F163 F1e: $_b's seed block does not say a codex effort difference alone arms"
  done
  pass "the operator docs and both seed-block copies name effort in the verdict and drop the deferred-gap wording (E99-F163)"
}

# ── F1a (E99-F163): the GENERATED manifest describes the widened verdict ────────
# The heredoc at harness-install.sh:4252 is shipped into every target's
# .harness/manifest.txt, and until this fix it told operators `armed` meant a changed
# MODEL computed from `resolve_model` — false since E99-F163 (an effort-only Codex pair
# arms with no `model` key on either role). Read the INSTALLED artifact, not the source
# heredoc: a whole-file grep for the corrected phrase could be satisfied by another
# occurrence in the installer, and the manifest is what the operator actually reads.
widened_verdict_is_named_in_the_generated_manifest() {
  _mv="$T/manifest"; install_to "$_mv" "$T/ch-manifest" --agents=claude
  _mf="$_mv/.harness/manifest.txt"
  [ -f "$_mf" ] || fail "E99-F163 F1a: the installer wrote no .harness/manifest.txt"
  # Scope to the .escalation-arming entry: from its line through its final clause.
  awk '/\.harness\/\.escalation-arming/ {k=1} k {print} k && /Written only while/ {exit}' \
    "$_mf" | tr '\n' ' ' > "$T/manifest-entry"
  [ -s "$T/manifest-entry" ] \
    || fail "E99-F163 F1a: the .escalation-arming manifest entry did not extract — its shape moved"
  grep -qiE 'change[[:space:]]+the[[:space:]]+resolved[[:space:]]+stamp' "$T/manifest-entry" \
    || fail "E99-F163 F1a: the generated manifest still says escalating changes only the model"
  grep -qF 'resolve_codex_effort' "$T/manifest-entry" \
    || fail "E99-F163 F1a: the generated manifest does not name resolve_codex_effort"
  grep -qiE 'resolved[[:space:]]+stamp[[:space:]]+is[[:space:]]+not[[:space:]]+the[[:space:]]+one[[:space:]]+it[[:space:]]+will[[:space:]]+run' "$T/manifest-entry" \
    || fail "E99-F163 F1a: the generated manifest still calls the unstamped case a 'resolved model'"
  grep -qiE 'no[[:space:]]+role[[:space:]]+resolves[[:space:]]+on[[:space:]]+either[[:space:]]+axis' "$T/manifest-entry" \
    || fail "E99-F163 F1a: the generated manifest still says ABSENT is 'no role resolves to a model'"
  pass "the generated .harness/manifest.txt describes the widened model+effort stamp (E99-F163 F1a)"
}

# ── E99-F163 finding 4047253492: the release records the widened verdict ────────
# The installer body changed (widened `escalation_verdict`) and the shipped config/docs
# changed with it, so the release must be recorded. The exact VERSION literal is pinned by
# tests/test_codex_native.sh; this pins the CHANGELOG entry that gives it meaning and the
# generic VERSION<->newest-heading agreement (never a frozen future value).
release_records_the_widened_verdict() {
  _cl="$SRC/CHANGELOG.md"
  grep -qF '## [0.84.1]' "$_cl" \
    || fail "E99-F163: CHANGELOG.md has no 0.84.1 entry for the widened escalation verdict"
  # Fence-aware section extraction, then positive two-token anchors. The pre-change blob has
  # no 0.84.1 heading at all, so the section is EMPTY and the first assertion reds; the
  # content anchors below stay discriminating against an entry whose heading survives but
  # whose body is reverted to the model-only wording.
  _s="$(awk -v h='## [0.84.1]' "$(cat "$SRC/tests/lib/fence.awk")"'
    fence_delim($0) { if (k) print; next }
    !fence && /^## /{k=(index($0,h)>0);next}
    k' "$_cl" | tr '\n' ' ')"
  [ -n "$_s" ] || fail "E99-F163: the 0.84.1 CHANGELOG section is empty"
  printf '%s' "$_s" | grep -qiE 'escalation_verdict.{0,200}model_reasoning_effort' \
    || fail "E99-F163: the 0.84.1 entry does not record the model+effort verdict"
  printf '%s' "$_s" | grep -qiE 'model_reasoning_effort.{0,80}alone[[:space:]]+arms' \
    || fail "E99-F163: the 0.84.1 entry does not record that a codex effort difference alone arms"
  printf '%s' "$_s" | grep -qiE 'pin\.opencode' \
    || fail "E99-F163: the 0.84.1 entry does not record opencode's matching-pin requirement"
  # The release is coherent: VERSION equals the newest heading (generic, not a literal).
  _vh="$(awk 'match($0, /^## \[[^]]+\]/) { print substr($0, RSTART + 4, RLENGTH - 5); exit }' "$_cl")"
  [ "$_vh" = "$(tr -d ' \t\r\n' < "$SRC/VERSION")" ] \
    || fail "E99-F163: VERSION $(cat "$SRC/VERSION") does not match the newest CHANGELOG heading [$_vh]"
  pass "the 0.84.1 release records the widened escalation verdict and its remediation (E99-F163)"
}

# ── E99-F163 finding 4047253495: the remediation names the widened stamp ────────
# The reviewer found `tools/builder-role.sh` still told operators that Codex needs BOTH a
# different model AND a matching `pin.codex.<tier>`, which is false since the verdict weighs
# effort: a different tier alone (⇒ a different `model_reasoning_effort`) arms with no pin.
# OpenCode's pin requirement is real and must survive. These are BEHAVIORAL assertions on the
# tool's stderr (the operator reads that line), plus section-scoped anchors on the role doc
# and the EMITTED builder-heavy descriptions (N4), read from a real install rather than the
# source strings.
remediation_distinguishes_codex_effort_from_opencode_pin() {
  # A blocked verdict naming codex, so the blocking branch's advisory is what we read.
  _blk="$(mkfix rblk 2 blocked codex=none opencode=same)"
  _m="$(err complex 1 --config "$_blk" | tr '\n' ' ')"
  [ -n "$_m" ] || fail "E99-F163 N1: the blocked advisory was empty"
  # Positive two-token anchors. `model_reasoning_effort` occurs NOWHERE in the pre-change
  # message, so the first is RED on the old text; the concrete `pin.opencode` (not the generic
  # `pin.<front-end>`) is likewise new.
  printf '%s' "$_m" | grep -qiE 'model_reasoning_effort.{0,40}alone[[:space:]]+arms' \
    || fail "E99-F163 N1: the blocked advisory does not say a codex reasoning-effort difference alone arms"
  printf '%s' "$_m" | grep -qiE 'opencode.{0,40}pin\.opencode' \
    || fail "E99-F163 N1: the blocked advisory dropped opencode's matching-pin requirement"
  # The superseded blanket claim is GONE: codex and opencode are no longer told one remedy.
  printf '%s' "$_m" | grep -q 'codex/opencode need a matching pin' \
    && fail "E99-F163 N1: the blocked advisory still prescribes one pin rule for codex AND opencode"

  # The threshold-veto advisory (the OTHER remediation string) carries the same correction.
  _offmsg="$(err complex 1 --config "$(mkfix roff 0 armed claude=raise)" | tr '\n' ' ')"
  printf '%s' "$_offmsg" | grep -qiE 'model_reasoning_effort.{0,40}alone[[:space:]]+arms' \
    || fail "E99-F163 N1: the after_rejections=0 advisory does not explain a codex effort-only escalation"
  printf '%s' "$_offmsg" | grep -qiE 'opencode.{0,40}pin\.opencode' \
    || fail "E99-F163 N1: the after_rejections=0 advisory dropped opencode's matching-pin requirement"

  # agents/orchestrator.md — section-scoped. "its own resolver" (singular) is the stale
  # wording; "own resolvers" (plural) + "whole resolved stamp" is the correction.
  _orch="$T/orch-stamp"
  awk -v h='### Which Builder — ask the tool, do not decide (E17-F03)' \
    '/^#{2,} /{k=(index($0,h)>0);next} k' "$SRC/agents/orchestrator.md" | tr '\n' ' ' > "$_orch"
  [ -s "$_orch" ] || fail "E99-F163 N1: the orchestrator's 'Which Builder' section did not extract — the heading moved"
  grep -qiE 'own[[:space:]]+resolvers' "$_orch" \
    || fail "E99-F163 N1: agents/orchestrator.md still says a single 'own resolver'"
  grep -qiE 'whole[[:space:]]+resolved[[:space:]]+stamp' "$_orch" \
    || fail "E99-F163 N1: agents/orchestrator.md does not name the whole resolved stamp"

  # The EMITTED builder-heavy descriptions: read the artifacts a real install writes, not the
  # source strings. claude reads `emit_agent`; codex reads `ag_personas`; the installed seed
  # comment reads the models heredoc — so all three corrected sites are exercised.
  _bt="$T/n4-target"; install_to "$_bt" "$T/ch-n4" --agents=claude,codex
  for _f in "$_bt/.claude/agents/builder-heavy.md" "$_bt/.codex/agents/builder-heavy.toml"; do
    [ -f "$_f" ] || fail "E99-F163 N4: setup — no emitted builder-heavy description at $_f"
    grep -qiE 'resolved[[:space:]]+stamp' "$_f" \
      || fail "E99-F163 N4: $_f still says the Builders differ only by the model"
    grep -qiE 'reasoning[[:space:]]+effort' "$_f" \
      || fail "E99-F163 N4: $_f does not name codex reasoning effort"
  done
  _seed="$T/n4-seed"
  awk '/builder-heavy: inherit/ {k=1} k {print} k && /NOT heavier than/ {exit}' \
    "$_bt/.harness/harness.config.yaml" | tr '\n' ' ' > "$_seed"
  [ -s "$_seed" ] || fail "E99-F163 N4: the installed models seed comment did not extract"
  grep -qiE 'resolved[[:space:]]+stamp' "$_seed" \
    || fail "E99-F163 N4: the installed builder-heavy seed comment still says 'only by the model'"

  pass "the remediation distinguishes codex effort-only arming from opencode's pin, and every emitted builder-heavy description names the resolved stamp (E99-F163 N1/N4)"
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
effort_only_differentiation_arms
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
effort_is_named_in_the_operator_docs
widened_verdict_is_named_in_the_generated_manifest
release_records_the_widened_verdict
remediation_distinguishes_codex_effort_from_opencode_pin
usage_errors_are_loud

# ── init.sh visibility line: quoted thresholds normalize like _cfg_scalar ────────────
# `after_rejections: "2"` is valid YAML that builder-role.sh accepts; an unstripped
# quote in init.sh's own extraction silently took the malformed-value branch and the
# mandatory startup check printed NOTHING for an active threshold — recreating the
# invisible escalation state the line exists to name (Codex #160 P2).
init_visibility_strips_quotes() {
  _iv="$T/init-vis"
  install_to "$_iv" "$T/ch-iv" --agents=claude
  for _q in '"2"' "'2'" '2'; do
    if grep -q '^  after_rejections:' "$_iv/.harness/harness.config.yaml"; then
      awk -v v="$_q" '/^  after_rejections:/ { print "  after_rejections: " v; next } { print }' \
        "$_iv/.harness/harness.config.yaml" > "$_iv/.harness/harness.config.yaml.t" \
        && mv "$_iv/.harness/harness.config.yaml.t" "$_iv/.harness/harness.config.yaml"
    else
      printf 'escalation:\n  after_rejections: %s\n' "$_q" >> "$_iv/.harness/harness.config.yaml"
    fi
    # Through its own shebang (bash): init.sh declares `set -o pipefail`, which a
    # POSIX `sh` (dash under the strict runner) rejects at line 1 — the run would
    # abort before ever reaching the escalation block and this test would flake by
    # host shell rather than test the extraction.
    _out="$(cd "$_iv" && ./.harness/init.sh 2>&1 || true)"
    printf '%s\n' "$_out" | grep -q 'escalation:' \
      || fail "init.sh printed no escalation line for after_rejections: $_q — output was: $_out"
  done
}
init_visibility_strips_quotes
pass "init.sh escalation line fires for quoted and bare thresholds alike"

# ══ E99-F182 — per-front-end gate ══
# ADR-0011: with `--frontend <key>` the gate reads that front-end's OWN `<key>=raise` line;
# with no key (or an empty one) it reads the first line exactly as before. R-ids `F182-Rn`.
#
# THIS_REPO_ARMING — the bytes `--self` writes in this repository today: Claude Code tiers
# from its committed shims, the other three inherit the all-`inherit` seed.
THIS_REPO_ARMING="claude=raise codex=neither opencode=neither pi=neither"

# ── F182-R1: the host's own raise line opens the gate, even on a `blocked` first line ──
F182_R1_key_raise_opens_on_blocked_first_line() {
  # shellcheck disable=SC2086  # word-splitting THIS_REPO_ARMING into detail lines is the point
  _f="$(mkfix f182-r1b 2 blocked $THIS_REPO_ARMING)"
  [ "$(role complex 1 --config "$_f" --frontend claude)" = builder-heavy ] \
    || fail "F182-R1: --frontend claude on this repo's own blocked/claude=raise file did not escalate a complex spec"
  [ "$(role standard 3 --config "$_f" --frontend claude)" = builder-heavy ] \
    || fail "F182-R1: --frontend claude did not escalate on the round trigger (round 3 > after_rejections 2)"
  [ "$(rc complex 1 --config "$_f" --frontend claude)" = 0 ] \
    || fail "F182-R1: the escalating key path did not exit 0"
  [ -z "$(err complex 1 --config "$_f" --frontend claude)" ] \
    || fail "F182-R1: the escalating key path wrote to stderr: $(err complex 1 --config "$_f" --frontend claude)"
  # Control: the SAME file without a key stays shut, so the key — not the file — opened it.
  [ "$(role complex 1 --config "$_f")" = builder ] \
    || fail "F182-R1 control: the blocked file escalated with no key — the first-line rule broke"
  pass "--frontend claude escalates on this repo's own blocked/claude=raise file, both triggers (F182-R1)"
}

F182_R1_key_raise_opens_on_armed_first_line() {
  _f="$(mkfix f182-r1a 2 armed claude=raise)"
  [ "$(role complex 1 --config "$_f" --frontend claude)" = builder-heavy ] \
    || fail "F182-R1: --frontend claude on an armed/claude=raise file did not escalate"
  pass "--frontend claude escalates on an armed/claude=raise file (F182-R1)"
}

F182_R1_key_raise_opens_on_blocked_first_line
F182_R1_key_raise_opens_on_armed_first_line

# ── F182-R2: a non-raise line for the key shuts the gate, and says what was recorded ──
# Branch guard: the advisory must be branch (i) — "this front-end" — and NOT branch (ii)
# ("no verdict is recorded") or the no-key "blocked by:" text, so each shut path is pinned
# to its own message rather than to whichever advisory happens to mention the key.
F182_R2_key_non_raise_shuts() {
  for _first in blocked armed; do
    for _cell in none same neither unstamped bogus; do
      _f="$(mkfix "f182-r2-$_first-$_cell" 2 "$_first" "claude=$_cell" codex=raise)"
      _got="$(role complex 1 --config "$_f" --frontend claude)"
      [ "$_got" = builder ] \
        || fail "F182-R2: $_first/claude=$_cell with --frontend claude printed '$_got', not builder"
      [ "$(rc complex 1 --config "$_f" --frontend claude)" = 0 ] \
        || fail "F182-R2: $_first/claude=$_cell with --frontend claude did not exit 0"
      _e="$(err complex 1 --config "$_f" --frontend claude)"
      [ "$(printf '%s\n' "$_e" | grep -c .)" = 1 ] \
        || fail "F182-R2: $_first/claude=$_cell wrote not exactly one advisory line: $_e"
      printf '%s' "$_e" | grep -qF "claude=$_cell" \
        || fail "F182-R2: the $_first/claude=$_cell advisory does not carry the literal claude=$_cell: $_e"
      printf '%s' "$_e" | grep -qF 'on this front-end (claude)' \
        || fail "F182-R2: the $_first/claude=$_cell advisory is not the this-front-end branch: $_e"
      printf '%s' "$_e" | grep -qF 'no verdict is recorded' \
        && fail "F182-R2: the $_first/claude=$_cell advisory took the no-verdict branch: $_e"
      printf '%s' "$_e" | grep -qF 'blocked by:' \
        && fail "F182-R2: the $_first/claude=$_cell advisory took the no-key blocked-by branch: $_e"
    done
  done
  pass "a non-raise line for the key shuts the gate on armed and blocked, naming <key>=<cell> (F182-R2)"
}
F182_R2_key_non_raise_shuts

# ── F182-R3: no line for the key shuts the gate — never a fallback to the first line ──
# The decoys prove a WHOLE-key match: `codexx=raise`, `xcodex=raise` and `xclaude=raise`
# each contain the key as a substring and none of them is that key's line.
F182_R3_key_missing_line_shuts() {
  for _first in armed blocked; do
    for _decoy in claude=raise codexx=raise xcodex=raise; do
      _f="$(mkfix "f182-r3-$_first-$_decoy" 2 "$_first" claude=raise "$_decoy")"
      _got="$(role complex 1 --config "$_f" --frontend codex)"
      [ "$_got" = builder ] \
        || fail "F182-R3: $_first file with no codex= line (decoy $_decoy) printed '$_got' for --frontend codex"
      [ "$(rc complex 1 --config "$_f" --frontend codex)" = 0 ] \
        || fail "F182-R3: the missing-line path did not exit 0"
      _e="$(err complex 1 --config "$_f" --frontend codex)"
      [ "$(printf '%s\n' "$_e" | grep -c .)" = 1 ] \
        || fail "F182-R3: the missing-line path wrote not exactly one advisory line: $_e"
      printf '%s' "$_e" | grep -qF "no verdict is recorded for front-end 'codex'" \
        || fail "F182-R3: $_first file (decoy $_decoy) lacks the no-verdict advisory for codex: $_e"
      printf '%s' "$_e" | grep -qF 'blocked by:' \
        && fail "F182-R3: the missing-line advisory took the no-key blocked-by branch: $_e"
    done
  done
  _f="$(mkfix f182-r3-xclaude 2 blocked xclaude=raise)"
  [ "$(role complex 1 --config "$_f" --frontend claude)" = builder ] \
    || fail "F182-R3: an xclaude=raise line opened the gate for --frontend claude (substring match)"
  err complex 1 --config "$_f" --frontend claude | grep -qF "no verdict is recorded for front-end 'claude'" \
    || fail "F182-R3: blocked/xclaude=raise did not report a missing claude verdict"
  # Boundary: an EMPTY verdict (`claude=`) is a recorded line, so it takes R2's branch.
  _f="$(mkfix f182-r3-empty 2 blocked claude=)"
  _e="$(err complex 1 --config "$_f" --frontend claude)"
  printf '%s' "$_e" | grep -qF 'on this front-end (claude) the installer recorded claude= ' \
    || fail "F182-R3: an empty claude= verdict was not reported as the recorded line: $_e"
  pass "a key with no line of its own shuts the gate on armed and blocked, whole-key match (F182-R3)"
}
F182_R3_key_missing_line_shuts

# ── F182-R4: no key, or an empty key, is today's rule byte for byte ──────────────
# Every fixture shape the pre-feature rule distinguishes, both triggers. stdout AND stderr
# of `… --frontend ''` must equal the no-flag run, and stdout must equal the pre-feature
# expectation (`armed` ⇒ heavy, everything else ⇒ builder) — so an empty key that leaked
# into the key path, or a no-key path that started reading detail lines, both red.
F182_R4_no_key_unchanged() {
  _armed_f="$(mkfix f182-r4-armed 2 armed claude=raise)"
  _blk_f="$(mkfix f182-r4-blocked 2 blocked claude=raise codex=none)"
  _abs_f="$(mkfix f182-r4-absent 2 '')"
  _veto_f="$(mkfix f182-r4-veto 0 armed claude=raise)"
  for _case in "armed:$_armed_f:" "blocked:$_blk_f:" "absent:$_abs_f:" "veto:$_veto_f:" "delegate:$_armed_f:delegate"; do
    _name="${_case%%:*}"; _rest="${_case#*:}"; _cfg="${_rest%:*}"; _be="${_rest##*:}"
    [ -n "$_be" ] || _be=in-session
    for _trig in "complex 1" "standard 3"; do
      # shellcheck disable=SC2086  # the trigger pair is two positional arguments
      set -- $_trig
      sh "$TOOL" "$1" "$2" --config "$_cfg" --backend "$_be" >"$T/r4-nokey.out" 2>"$T/r4-nokey.err" \
        || fail "F182-R4: $_name/$_trig with no key exited non-zero"
      sh "$TOOL" "$1" "$2" --config "$_cfg" --backend "$_be" --frontend '' >"$T/r4-empty.out" 2>"$T/r4-empty.err" \
        || fail "F182-R4: $_name/$_trig with --frontend '' exited non-zero"
      cmp -s "$T/r4-nokey.out" "$T/r4-empty.out" \
        || fail "F182-R4: $_name/$_trig stdout differs between no key and --frontend ''"
      cmp -s "$T/r4-nokey.err" "$T/r4-empty.err" \
        || fail "F182-R4: $_name/$_trig stderr differs between no key and --frontend ''"
      if [ "$_name" = armed ]; then _want=builder-heavy; else _want=builder; fi
      [ "$(cat "$T/r4-empty.out")" = "$_want" ] \
        || fail "F182-R4: $_name/$_trig with an empty key printed '$(cat "$T/r4-empty.out")', expected the pre-feature '$_want'"
    done
  done
  pass "no key and an empty key decide from the first line exactly as before, stdout and stderr (F182-R4)"
}
F182_R4_no_key_unchanged

# ── F182-R5: garbage never opens the gate, with or without a key ─────────────────
# f182_raw <name> <printf-%b body> — a fixture whose arming file is written byte-exact,
# for shapes mkfix cannot express (an empty first line, a trailing CR). Prints the config.
f182_raw() {
  _fr_c="$(mkfix "$1" 2 '')"
  printf '%b' "$2" > "$(dirname "$_fr_c")/.escalation-arming"
  printf '%s\n' "$_fr_c"
}
# f182_shut <label> <config> — builder and exit 0 with AND without --frontend claude.
f182_shut() {
  [ "$(role complex 1 --config "$2" --frontend claude)" = builder ] \
    || fail "F182-R5: $1 opened the gate with --frontend claude"
  [ "$(rc complex 1 --config "$2" --frontend claude)" = 0 ] \
    || fail "F182-R5: $1 with --frontend claude did not exit 0"
  [ "$(role complex 1 --config "$2")" = builder ] \
    || fail "F182-R5: $1 opened the gate with no key"
  [ "$(rc complex 1 --config "$2")" = 0 ] \
    || fail "F182-R5: $1 with no key did not exit 0"
}
F182_R5_garbage_never_opens() {
  f182_shut "an absent arming file" "$(mkfix f182-r5-absent 2 '')"

  # A symlink to a file that WOULD open both paths: the shared outer guard must refuse it.
  _real="$(mkfix f182-r5-real 2 armed claude=raise)"
  [ "$(role complex 1 --config "$_real" --frontend claude)" = builder-heavy ] \
    || fail "F182-R5 setup: the symlink's target does not open the gate on its own"
  _ln="$(mkfix f182-r5-link 2 '')"
  ln -s "$(dirname "$_real")/.escalation-arming" "$(dirname "$_ln")/.escalation-arming"
  f182_shut "a symlinked arming file" "$_ln"

  _ur="$(mkfix f182-r5-unreadable 2 armed claude=raise)"
  chmod 000 "$(dirname "$_ur")/.escalation-arming"
  if [ -r "$(dirname "$_ur")/.escalation-arming" ]; then
    echo "skip - F182-R5 unreadable case: this host does not enforce file modes (running as root?)"
  else
    f182_shut "an unreadable arming file" "$_ur"
  fi
  chmod 600 "$(dirname "$_ur")/.escalation-arming"

  # First lines the installer cannot have written: no detail line may then be trusted.
  _i=0
  for _first in 'Armed' 'armed ' ' armed' 'ARMED' '' 'claude=raise' 'blocked '; do
    _i=$((_i + 1))
    f182_shut "first line '$_first'" "$(f182_raw "f182-r5-first$_i" "$_first\nclaude=raise\n")"
  done

  # Whitespace / CR variants of the key line are not the key line.
  _i=0
  for _kl in 'claude=raise ' ' claude=raise' 'claude = raise' 'claude=raise\r' 'claude =raise' 'claude= raise'; do
    _i=$((_i + 1))
    f182_shut "detail line '$_kl'" "$(f182_raw "f182-r5-ws$_i" "blocked\n$_kl\n")"
  done

  # Duplicate key: the FIRST `claude=` line decides — asserted in both orders, so the row
  # proves order rather than "duplicates shut".
  _dup="$(mkfix f182-r5-dup 2 blocked claude=none claude=raise)"
  f182_shut "duplicate claude=none then claude=raise" "$_dup"
  err complex 1 --config "$_dup" --frontend claude | grep -qF 'recorded claude=none ' \
    || fail "F182-R5: the duplicate-key advisory does not name the FIRST line, claude=none"
  _rev="$(mkfix f182-r5-rev 2 blocked claude=raise claude=none)"
  [ "$(role complex 1 --config "$_rev" --frontend claude)" = builder-heavy ] \
    || fail "F182-R5: duplicate claude=raise then claude=none did not open — the first line must win"

  # The one positive: a ~3000-line file with the key line LAST must still open, so the
  # search is whole-file (not line 2 only) and the negatives above are not vacuous.
  _big="$(mkfix f182-r5-big 2 '')"
  awk 'BEGIN { print "blocked"; for (i = 1; i <= 3000; i++) print "k" i "=neither"; print "claude=raise" }' \
    > "$(dirname "$_big")/.escalation-arming"
  [ "$(role complex 1 --config "$_big" --frontend claude)" = builder-heavy ] \
    || fail "F182-R5: a ~3000-line file with claude=raise last did not open for --frontend claude"
  [ "$(role complex 1 --config "$_big")" = builder ] \
    || fail "F182-R5: the ~3000-line blocked file opened with no key"
  pass "absent / symlink / unreadable / bad first line / whitespace / duplicate-order never open; a large file still does (F182-R5)"
}
F182_R5_garbage_never_opens

# ── F182-R6: a missing or malformed key is a broken CALLER — usage, exit 4 ───────
# The specific message is asserted, not just `--frontend`: the generic usage line also
# names `[--frontend <key>]`, so a bare `--frontend` grep would pass on any usage error.
F182_R6_usage() {
  [ "$(rc complex 1 --frontend)" = 4 ] || fail "F182-R6: --frontend with no value did not exit 4"
  [ -z "$(role complex 1 --frontend)" ] || fail "F182-R6: --frontend with no value printed a role"
  for _v in Claude 'cl aude' claude=raise ../claude -claude 1claude 'claude
codex'; do
    [ "$(rc complex 1 --frontend "$_v")" = 4 ] \
      || fail "F182-R6: --frontend '$_v' did not exit 4"
    [ -z "$(role complex 1 --frontend "$_v")" ] \
      || fail "F182-R6: --frontend '$_v' printed a role on stdout"
    err complex 1 --frontend "$_v" | grep -qF -- "--frontend must be a bare front-end key, got '" \
      || fail "F182-R6: --frontend '$_v' did not name the malformed key on stderr: $(err complex 1 --frontend "$_v")"
  done
  # The accepted shapes: a hyphenated / digit-bearing token, and the empty string (R4).
  [ "$(rc complex 1 --frontend open-code2)" = 0 ] || fail "F182-R6: a valid token open-code2 was rejected"
  [ "$(rc complex 1 --frontend '')" = 0 ] || fail "F182-R6: --frontend '' was rejected (it is the R4 no-key path)"
  pass "--frontend with no value or a non-token value exits 4 with an empty stdout (F182-R6)"
}
F182_R6_usage

# ── F182-R9: the INSTALLED orchestrator passes the produced key, never a typed one ──
# Slice = `### Which Builder` up to the next `### ` heading (a `###` sibling ends it; the
# fenced call block has no `###` line, so the call stays inside the slice). Every anchor runs
# on the slice — never the whole file — so the sentences cannot drift into another section
# (M9c moves them below `### The pre-PR change-size handoff` and must red).
# f182_which_builder <orchestrator.md> — the folded `### Which Builder` slice.
f182_which_builder() {
  awk 'f && /^### /{exit} /^### Which Builder/{f=1} f' "$1" | tr '\n' ' ' | tr -s ' '
}
F182_R9_orchestrator_prose() {
  _t="$T/f182-r9"; install_to "$_t" "$T/ch-f182-r9" --agents=claude
  _o="$_t/.harness/agents/orchestrator.md"
  [ -f "$_o" ] || fail "F182-R9 setup: no installed orchestrator.md"
  _raw="$(awk 'f && /^### /{exit} /^### Which Builder/{f=1} f' "$_o")"
  _sl="$(f182_which_builder "$_o")"
  [ -n "$_sl" ] || fail "F182-R9 setup: the '### Which Builder' section did not extract — the heading moved"
  printf '%s\n' "$_raw" | grep -qF -- '--frontend "$(sh "$HARNESS_DIR/tools/host-frontend.sh")"' \
    || fail "F182-R9: the Which Builder call does not pass --frontend \"\$(sh \"\$HARNESS_DIR/tools/host-frontend.sh\")\""
  printf '%s' "$_sl" | grep -qE 'An empty key means the host could not be identified[^.]{0,120}all-front-ends rule' \
    || fail "F182-R9: the Which Builder section does not say an empty key applies the all-front-ends rule"
  printf '%s' "$_sl" | grep -qF 'You never supply the key by hand' \
    || fail "F182-R9: the Which Builder section does not forbid supplying the key by hand"
  printf '%s' "$_sl" | grep -qE "your host's own[^.]{0,40}=raise[^.]{0,40}ADR-0011" \
    || fail "F182-R9: the TWO-yeses clause does not name your host's own <key>=raise line (ADR-0011)"
  printf '%s' "$_sl" | grep -qE "That file decides[^.]{0,120}your host's own line when it is" \
    || fail "F182-R9: 'That file decides' does not say the host's own line decides when the host is known"
  # The superseded wording is gone from the slice.
  printf '%s' "$_sl" | grep -qF 'That file decides. Do not read' \
    && fail "F182-R9: the slice still says 'That file decides.' with no per-front-end qualifier"
  printf '%s' "$_sl" | grep -qF '`.harness/.escalation-arming`. When either gate' \
    && fail "F182-R9: the TWO-yeses clause still names only an armed verdict, no host line"
  # Pre-existing anchors still hold, and the call block lost nothing.
  for _a in 'builder-role.sh' 'builder-heavy round 3' 'never override the answer' '"phase":"builder","role":"builder-heavy"'; do
    printf '%s' "$_sl" | grep -qF -- "$_a" || fail "F182-R9: the Which Builder section lost its pre-existing anchor: $_a"
  done
  printf '%s\n' "$_raw" | grep -qE '^[[:space:]]+--backend "<execution\.builder\.backend>"' \
    || fail "F182-R9: the fenced call lost its --backend line"
  printf '%s\n' "$_raw" | grep -qE '^[[:space:]]+--config "\$HARNESS_DIR/harness\.config\.yaml"' \
    || fail "F182-R9: the fenced call lost its --config line"
  pass "the installed orchestrator pipes host-frontend.sh into --frontend and never types a key (F182-R9)"
}
F182_R9_orchestrator_prose

# ── F182-R10: init.sh names the per-front-end state when the AND is blocked ───────
# Run through the installed init.sh's own shebang (bash), so `set -euo pipefail` is in force —
# the large-file case is what pins "no pipeline that can take SIGPIPE". Every case's exit
# status must equal the absent-file run's: this block is warn-only and never changes it.
F182_R10_init_per_frontend_line() {
  _t="$T/f182-r10"; install_to "$_t" "$T/ch-f182-r10" --agents=claude
  _cfg="$_t/.harness/harness.config.yaml"
  if grep -q '^  after_rejections:' "$_cfg"; then
    awk '/^  after_rejections:/ { print "  after_rejections: 2"; next } { print }' "$_cfg" > "$_cfg.t" && mv "$_cfg.t" "$_cfg"
  else
    printf 'escalation:\n  after_rejections: 2\n' >> "$_cfg"
  fi
  _arm="$_t/.harness/.escalation-arming"
  _armed_line='ℹ️  escalation: ARMED (builder-heavy after 2 rejections)'
  _dis_line="⚠️  escalation: configured (after_rejections: 2) but DISARMED — .escalation-arming is absent or not 'armed', so builder-heavy will never fire. Configure models.builder-heavy and re-run the installer. (warn-only)"
  _pf() { printf '%s' "ℹ️  escalation: ARMED per front-end on: $1 (builder-heavy after 2 rejections); not on: $2 — the Orchestrator escalates only where its host's line reads raise (E99-F182)"; }
  # _run — init.sh's escalation line(s) → $T/r10.esc, exit status → $T/r10.rc
  _run() {
    _s=0; ( cd "$_t" && ./.harness/init.sh ) > "$T/r10.out" 2>&1 || _s=$?
    printf '%s\n' "$_s" > "$T/r10.rc"
    grep 'escalation: ' "$T/r10.out" > "$T/r10.esc" || true
  }
  _one() {  # _one <label> <exact line>
    [ "$(grep -c . "$T/r10.esc")" = 1 ] || fail "F182-R10: $1 — not exactly one escalation line: $(cat "$T/r10.esc")"
    grep -qxF -- "$2" "$T/r10.esc" || fail "F182-R10: $1 — expected the line '$2', got: $(cat "$T/r10.esc")"
    [ "$(cat "$T/r10.rc")" = "$_rc0" ] || fail "F182-R10: $1 — init.sh exited $(cat "$T/r10.rc"), the absent-file run exited $_rc0"
  }

  rm -f "$_arm"; _run; _rc0="$(cat "$T/r10.rc")"
  _one "absent file" "$_dis_line"

  printf 'blocked\nclaude=raise\ncodex=neither\npi=none\n' > "$_arm"; _run
  _one "blocked + claude=raise" "$(_pf claude 'codex pi')"
  grep -q DISARMED "$T/r10.out" && fail "F182-R10: blocked + claude=raise still printed DISARMED"

  printf 'blocked\nclaude=raise\ncodex=raise\npi=none\n' > "$_arm"; _run
  _one "blocked + claude,codex=raise" "$(_pf 'claude codex' pi)"

  printf 'armed\nclaude=raise\n' > "$_arm"; _run
  _one "armed" "$_armed_line"
  grep -q 'per front-end' "$T/r10.out" && fail "F182-R10: an armed file printed the per-front-end line"

  printf 'blocked\nclaude=none\n' > "$_arm"; _run
  _one "blocked, nothing raise" "$_dis_line"

  # A first line that is neither armed nor blocked: no detail line is trusted.
  printf 'Blocked\nclaude=raise\n' > "$_arm"; _run
  _one "garbage first line + claude=raise" "$_dis_line"

  # Symlinks read as absent — to a blocked+raise file AND to an armed one.
  for _body in 'blocked\nclaude=raise\ncodex=raise\n' 'armed\nclaude=raise\n'; do
    rm -f "$_arm"; printf "$_body" > "$T/r10-target"; ln -s "$T/r10-target" "$_arm"; _run
    _one "symlink" "$_dis_line"
  done
  rm -f "$_arm"

  # ~3000 lines (~200 KB — far past any pipe buffer, so a `producer | head` read WOULD take
  # SIGPIPE under pipefail), the raise line last: printed, and the exit status is unchanged.
  awk 'BEGIN { p = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; print "blocked"
               for (i = 1; i <= 2999; i++) print "k" i "-" p "=neither"; print "claude=raise" }' > "$_arm"
  [ "$(wc -c < "$_arm")" -gt 150000 ] || fail "F182-R10 setup: the large arming file is under 150 KB"
  _run
  [ "$(grep -c . "$T/r10.esc")" = 1 ] || fail "F182-R10: the ~3000-line file did not print exactly one escalation line"
  grep -qE '^ℹ️  escalation: ARMED per front-end on: claude \(builder-heavy after 2 rejections\); not on: k1-a+ k2-a+ ' "$T/r10.esc" \
    || fail "F182-R10: the ~3000-line file did not print the per-front-end line: $(cut -c1-200 "$T/r10.esc")"
  grep -qE ' k2999-a+ — the Orchestrator' "$T/r10.esc" || fail "F182-R10: the ~3000-line file's not-on list was truncated"
  [ "$(cat "$T/r10.rc")" = "$_rc0" ] || fail "F182-R10: the ~3000-line file changed init.sh's exit status to $(cat "$T/r10.rc")"

  # An invalid byte before the raise line, under a UTF-8 CALLER locale: the macOS system awk
  # aborts on it (`towc: multibyte conversion failure`) unless the read pins LC_ALL=C, which
  # would lose the raise key and print DISARMED (progress/lessons.md 2026-10-26).
  printf 'blocked\n\377x=none\nclaude=raise\n' > "$_arm"
  _s=0; ( cd "$_t" && LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 ./.harness/init.sh ) > "$T/r10.out" 2>&1 || _s=$?
  printf '%s\n' "$_s" > "$T/r10.rc"; grep 'escalation: ' "$T/r10.out" > "$T/r10.esc" || true
  _one "invalid byte under a UTF-8 locale" "$(_pf claude '(none)')"

  # Hostile keys: never eval'd, never printed. Relative and absolute `touch` targets; cwd is
  # the target, so a relative X would land in it.
  printf 'blocked\na$(touch "%s/X")=raise\nb`touch Y`=raise\nc$(touch Z)=none\nclaude=raise\n' "$T" > "$_arm"; _run
  [ ! -e "$T/X" ] && [ ! -e "$_t/X" ] && [ ! -e "$_t/Y" ] && [ ! -e "$_t/Z" ] \
    || fail "F182-R10: a hostile arming line was executed (a touch target exists)"
  _one "hostile lines" "$(_pf claude '(none)')"
  pass "init.sh prints one per-front-end line for blocked+raise, unchanged ARMED/DISARMED otherwise, large and hostile files safe (F182-R10)"
}
F182_R10_init_per_frontend_line

# ── F182-R11: the installer's summary names the per-front-end state; the file is unchanged ──
# Three installs of one claude+codex target: all raise (armed ⇒ the existing `ok` line), no
# raise (the existing NOT-armed line), and claude raise + codex unstamped (the new per-front-end
# line). After each, the arming file must be exactly the pre-feature format — first line, then
# one `<key>=<verdict>` per selected key in $AGENT_KEYS order (claude, codex), no blank line —
# composed here independently of the file's own layout.
F182_R11_installer_summary_line() {
  _t="$T/f182-r11"; install_to "$_t" "$T/ch-f182-r11" --agents=claude,codex
  _c="$_t/.harness/harness.config.yaml"
  _pf_msg='escalation armed per front-end on: claude; not on: codex — the Orchestrator escalates where its host'"'"'s line reads raise (ADR-0011); see .harness/.escalation-arming'
  _inst() { CODEX_HOME="$T/ch-f182-r11" sh "$SRC/harness-install.sh" --agents=claude,codex "$_t" > "$T/r11.out" 2>&1 \
              || fail "F182-R11: install exited non-zero: $(tail -5 "$T/r11.out")"; }
  _shape() {  # _shape <label> — the frozen file format
    _vc="$(verdict_for "$_t" claude)"; _vx="$(verdict_for "$_t" codex)"
    if [ "$_vc" = raise ] && [ "$_vx" = raise ]; then _first=armed; else _first=blocked; fi
    printf '%s\n' "$_first" "claude=$_vc" "codex=$_vx" > "$T/r11.want"
    cmp -s "$T/r11.want" "$_t/.harness/.escalation-arming" \
      || fail "F182-R11: $1 — the arming file is not the pre-feature format: $(od -c "$_t/.harness/.escalation-arming" | head -5)"
  }

  set_models "$_c" builder standard
  set_models "$_c" builder-heavy reasoning
  _inst
  [ "$(verdict_for "$_t" claude)" = raise ] && [ "$(verdict_for "$_t" codex)" = raise ] \
    || fail "F182-R11 setup: standard/reasoning is not raise on both (claude=$(verdict_for "$_t" claude) codex=$(verdict_for "$_t" codex))"
  grep -qF 'escalation armed — builder-heavy resolves to a different stamp' "$T/r11.out" \
    || fail "F182-R11: an all-raise install did not print the existing armed line"
  grep -qF 'per front-end' "$T/r11.out" && fail "F182-R11: an all-raise install printed the per-front-end line"
  _shape "all raise"

  set_models "$_c" builder-heavy inherit
  _inst
  grep -qF 'escalation NOT armed — see .harness/.escalation-arming' "$T/r11.out" \
    || fail "F182-R11: a no-raise install did not print the existing NOT-armed line"
  grep -qF 'per front-end' "$T/r11.out" && fail "F182-R11: a no-raise install printed the per-front-end line"
  _shape "no raise"

  set_models "$_c" builder-heavy reasoning
  _inst
  printf 'name = "builder-heavy"\n# hand-edited by the operator\n' > "$_t/.codex/agents/builder-heavy.toml"
  _inst
  [ "$(verdict_for "$_t" claude)" = raise ] && [ "$(verdict_for "$_t" codex)" = unstamped ] \
    || fail "F182-R11 setup: expected claude=raise codex=unstamped, got claude=$(verdict_for "$_t" claude) codex=$(verdict_for "$_t" codex)"
  grep -qF -- "$_pf_msg" "$T/r11.out" \
    || fail "F182-R11: a mixed install did not print the per-front-end line: $(grep -i escalation "$T/r11.out")"
  grep -qF 'escalation NOT armed' "$T/r11.out" && fail "F182-R11: a mixed install still printed the NOT-armed line"
  _shape "claude raise, codex unstamped"
  pass "the installer summary names per-front-end arming when mixed; the file stays the pre-feature format (F182-R11)"
}
F182_R11_installer_summary_line

echo "test_escalation.sh: all cases passed"
