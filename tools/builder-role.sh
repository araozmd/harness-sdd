#!/bin/sh
# builder-role.sh — which Builder role should this build spawn? (E17-F03)
#
# E17-F02 gave the harness a second Builder role name, `builder-heavy`, differing from
# `builder` ONLY by the model tier it resolves to (ADR-0002). Nothing called it. This tool is
# the caller: it answers "standard or heavy?" from recorded state, so escalation is a rule
# rather than an agent's opinion that a task "looks hard" — which is the epic's own success
# criterion and the reason this is a tool at all.
#
# WHY A TOOL AND NOT PROSE IN agents/orchestrator.md. A rule that only a language model
# evaluates cannot be shown deterministic: two runs on identical recorded state may differ,
# and the repo's prose-verification pattern (see tests/test_reviewer.sh) can only grep role
# files for required clauses, leaving the behavioral criterion as a documented MANUAL check.
# Here the rule is executable, so it is testable and mutation-testable, and only the CALL
# SITE rests on prose. Same shape as pr-gate.sh / pr-stack-guard.sh / change-size.sh.
#
# Usage:
#   tools/builder-role.sh <complexity> <round> [--backend <in-session|delegate>]
#                                              [--config <harness.config.yaml>]
#
#   <complexity>  the feature spec's `complexity:` frontmatter value. EMPTY is legal and
#                 means `standard` — specs written before this feature carry no tag.
#   <round>       the EXISTING build<->review counter (agents/orchestrator.md): 1 on the
#                 first build, +1 on every in-review -> in-progress bounce. This tool
#                 introduces no second counter and no schema field.
#
# Output:
#   stdout  exactly one line: `builder` or `builder-heavy`
#   stderr  one advisory line when a value was coerced, or when escalation was inapplicable.
#           Advisories NEVER change the exit status — a malformed tag must not fail a build.
#
# Exit codes:
#   0  a role name was resolved (the normal case, including every coerced one)
#   4  usage error — wrong argument count, or a non-numeric round
#
# PURITY IS THE POINT. This reads its arguments and, at most, ONE scalar from the config. It
# never reads progress/history.md, never opens the spec body, never calls git, and keeps no
# state between runs. That is what makes "identical inputs, identical answer" testable; a
# tool that could consult prose could not be proven deterministic.

set -eu

usage() {
  echo "usage: builder-role.sh <complexity> <round> [--backend <in-session|delegate>] [--config <path>]" >&2
  exit 4
}

_complexity=""
_round=""
_backend="in-session"
_config=""
_positional=0

while [ $# -gt 0 ]; do
  case "$1" in
    --backend) [ $# -ge 2 ] || usage; _backend="$2"; shift 2 ;;
    --config)  [ $# -ge 2 ] || usage; _config="$2";  shift 2 ;;
    --help|-h) usage ;;
    --*) echo "builder-role.sh: unknown option '$1'" >&2; usage ;;
    *)
      _positional=$((_positional + 1))
      case "$_positional" in
        1) _complexity="$1" ;;
        2) _round="$1" ;;
        *) echo "builder-role.sh: unexpected argument '$1'" >&2; usage ;;
      esac
      shift ;;
  esac
done

[ "$_positional" -eq 2 ] || usage

# The round must be a non-negative integer. Unlike a bad complexity value — which is a typo in
# a human-written spec and must never fail a build — a non-numeric round means the CALLER is
# broken, and silently coercing it would hide that while quietly changing which model runs.
case "$_round" in
  ''|*[!0-9]*) echo "builder-role.sh: round must be a non-negative integer, got '$_round'" >&2; exit 4 ;;
esac

# ── 1. Backend, checked FIRST ────────────────────────────────────────────────────
# Under `delegate` the Builder writes no code: it invokes `<delegate_cmd> <feature-id>
# <abs-spec-path>` and the external executor chooses its own model. The harness resolves no
# model on that path, so "escalating" would change nothing while recording that it had.
# Checked before every other input so nothing downstream can produce a heavy answer that the
# executor would ignore.
if [ "$_backend" = delegate ]; then
  echo "ℹ️  execution.builder.backend is 'delegate' — escalation is inapplicable (the external executor chooses its own model); using 'builder'" >&2
  echo builder
  exit 0
fi

# _cfg_scalar <section> <key> — print the scalar at <section>.<key>, or empty. Scoped to the
# TOP-LEVEL section so a same-named key elsewhere in the file cannot be mistaken for it.
# Strips a trailing comment and either quote style. Same shape tools/harness-owned-paths.sh
# uses for telemetry.log.
_cfg_scalar() {
  [ -n "$_config" ] && [ -f "$_config" ] || return 0
  awk -v sect="$1" -v key="$2" '
    $0 ~ "^" sect ":[[:space:]]*(#.*)?$" { s=1; next }
    s && /^[^[:space:]#]/ { s=0 }
    s && $0 ~ "^[[:space:]]+" key ":" {
      sub("^[[:space:]]+" key ":[[:space:]]*", ""); sub(/[[:space:]]*#.*$/, "")
      print; exit
    }
  ' "$_config" 2>/dev/null | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

# ── 2. Is escalation ARMED? ──────────────────────────────────────────────────────
# Escalating to a role with NO configured tier does not make the build heavier — it makes it
# resolve to the session model. On a target that set `models.builder: standard` and left
# `models.builder-heavy: inherit` (the shipped default), that is a DOWNGRADE: the build would
# abandon the operator's configured Builder model precisely when it was struggling. Verified
# on an installed Claude target — builder got `model: sonnet`, builder-heavy got no model key.
# (Codex #3716706727.)
#
# So escalation fires only when the heavy role has an effective tier that is not `inherit`:
# `models.builder-heavy`, else `models.default`, else `inherit`. This is what makes "inert
# until you configure it" literally true rather than true-only-for-a-fully-unconfigured-target,
# which is what the first version of this feature claimed.
_heavy_tier="$(_cfg_scalar models builder-heavy)"
[ -n "$_heavy_tier" ] || _heavy_tier="$(_cfg_scalar models default)"
_armed=1
case "$_heavy_tier" in
  ''|inherit) _armed=0 ;;
esac

# _escalate <trigger> — honour an escalation trigger, or decline it because no heavy tier is
# configured. Declining is reported: the operator expressed intent (a tag, or a threshold they
# left in place) and needs to know why nothing happened.
_escalate() {
  if [ "$_armed" = 1 ]; then
    echo builder-heavy
  else
    echo "ℹ️  $1 would escalate, but models.builder-heavy has no tier (it resolves to 'inherit') — escalating would drop to the session model, so using 'builder'. Set models.builder-heavy to enable escalation." >&2
    echo builder
  fi
  exit 0
}

# ── 3. Complexity ────────────────────────────────────────────────────────────────
# Closed vocabulary. ABSENT is silent (R7: a pre-existing spec must produce no warning), but
# a value that is neither `standard` nor `complex` is a typo the operator should see — so it
# resolves the SAFE direction (standard, i.e. no escalation) and says so, without failing.
case "$_complexity" in
  complex)
    _escalate "spec complexity=complex" ;;
  ''|standard)
    : ;;
  *)
    echo "⚠️  unrecognized complexity '$_complexity' — treating it as 'standard' (known values: standard complex)" >&2
    : ;;
esac

# ── 4. Round vs threshold ────────────────────────────────────────────────────────
# `round` is ALREADY one more than the number of rejections: round 1 is the first build,
# round 3 is the first build after two rejections. So "after N rejections" is `round > N`.
# Stated once here so it is never re-derived at a call site.
_threshold=2
_cfgval="$(_cfg_scalar escalation after_rejections)"
case "$_cfgval" in
  '') : ;;                         # absent block or absent key ⇒ the default, silently (R7)
  *[!0-9]*)
    echo "⚠️  escalation.after_rejections = '$_cfgval' is not a non-negative integer — using the default 2" >&2 ;;
  *) _threshold="$_cfgval" ;;
esac

# 0 DISABLES the round arm. It does not mean "escalate on every round" — which is exactly what
# a bare `round > 0` comparison would do, turning an operator's off-switch into
# always-escalate. The guard is the whole point of the key's `0` semantics.
if [ "$_threshold" -gt 0 ] && [ "$_round" -gt "$_threshold" ]; then
  _escalate "round $_round > escalation.after_rejections=$_threshold"
fi

echo builder
exit 0
