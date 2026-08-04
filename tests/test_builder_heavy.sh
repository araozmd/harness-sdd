#!/bin/sh
# test_builder_heavy.sh — E17-F02 the `builder-heavy` role.
#
# Covers R1, R3, R4, R5, R5a, R6, R7, R9. R2, R8 and R10 are asserted where their subject
# already lives: tests/test_install.sh (config seeding, the all-inherit `diff -r`) and
# tests/test_model_routing.sh (the role-set counts, each now paired with a by-name check).
#
# The R5/R6 cases install from a `git archive` of the merge-base FIRST, so the "previous
# release" fixture is a file the shipped installer actually produced rather than one this
# suite hand-wrote to look right. Zero dependencies; self-cleaning temp dir.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT

# Sandbox CODEX_HOME for the WHOLE suite — no assertion may reach the developer's ~/.codex.
export CODEX_HOME="$T/codex-home"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

ALL=claude,gemini,opencode,antigravity,codex

mk() { _d="$T/$1"; mkdir -p "$_d"; printf '%s\n' "$_d"; }
cfg() { printf '%s\n' "$1/.harness/harness.config.yaml"; }
run() { CODEX_HOME="$1/ch" sh "$SRC/harness-install.sh" --agents="$2" "$1" >/dev/null 2>&1; }
run_err() { CODEX_HOME="$1/ch" sh "$SRC/harness-install.sh" --agents="$2" "$1" 2>&1 >/dev/null; }

set_tier() {
  _c="$(cfg "$1")"
  sed "s/^  $2: .*/  $2: $3/" "$_c" > "$_c.t" && mv "$_c.t" "$_c"
}
set_pin() {
  _c="$(cfg "$1")"
  printf '  pin.%s.%s: "%s"\n' "$2" "$3" "$4" >> "$_c"
}
# n_agents <opencode.json> — number of keys under `agent:` (python3-free: count the members).
n_agents() { grep -cE '^    "[a-z-]+":? *\{' "$1"; }

# ── the previous-release source tree, built ONCE and shared ──────────────────────
# `git archive` of the merge-base with origin/main: the bytes that shipped, not a
# reconstruction. Every "previous release" fixture below is installed from here.
PREV="$T/prev-src"
mkdir -p "$PREV"
PREV_REF="$(cd "$SRC" && git merge-base HEAD origin/main 2>/dev/null || true)"
[ -n "$PREV_REF" ] || fail "setup: could not resolve the merge-base with origin/main"
(cd "$SRC" && git archive "$PREV_REF") | tar -x -C "$PREV" \
  || fail "setup: git archive of $PREV_REF failed"
[ -f "$PREV/harness-install.sh" ] || fail "setup: the merge-base archive has no harness-install.sh"
run_prev() { CODEX_HOME="$1/ch" sh "$PREV/harness-install.sh" --agents="$2" "$1" >/dev/null 2>&1; }

# ── R1: the pointer body duplicates nothing ─────────────────────────────────────
pointer_body_duplicates_nothing() {
  _p="$SRC/agents/builder-heavy.md"
  [ -f "$_p" ] || fail "R1: agents/builder-heavy.md does not exist"
  # Positive half: it NAMES the canonical body.
  grep -qF 'builder.md' "$_p" || fail "R1: the pointer does not name agents/builder.md"
  grep -qF 'ADR-0002' "$_p"   || fail "R1: the pointer does not cite ADR-0002"
  # Negative half, computed against the REAL Builder body in this same run rather than a
  # hardcoded string that would quietly stop matching as builder.md evolves. Any substantial
  # line (>40 chars, not blank, not a heading) appearing in BOTH files is duplicated body.
  _dup="$(awk 'length($0)>40 && $0 !~ /^#/' "$SRC/agents/builder.md" \
          | while IFS= read -r _l; do
              grep -qF -- "$_l" "$_p" && printf '%s\n' "$_l"
            done || true)"
  [ -z "$_dup" ] || fail "R1: builder-heavy.md duplicates Builder body text: $_dup"
  pass "agents/builder-heavy.md points at builder.md and duplicates no instruction text (R1)"
}

# ── R3: an absent key falls through to models.default ───────────────────────────
absent_key_falls_through_to_default() {
  _t="$(mk r3)"; run "$_t" claude
  # NOT `_c`: POSIX sh has no locals, and set_tier below assigns `_c` for its own target —
  # a shared name here would silently repoint every later assertion at the wrong config.
  _r3cfg="$(cfg "$_t")"
  # Strip the key entirely — the shape an UPGRADED target has, since migrate_config seeds
  # the whole block only when it is absent and never adds individual keys.
  grep -v '^  builder-heavy:' "$_r3cfg" | grep -v '^ *# .*escalation tier\|^ *# .*NOT heavier' \
    > "$_r3cfg.t" && mv "$_r3cfg.t" "$_r3cfg"
  grep -q '^  builder-heavy:' "$_r3cfg" && fail "R3: setup — the key was not removed"
  # Positive control FIRST: with default: cheap the absent role must resolve to the cheap
  # alias. Without this, "no model key" below would be satisfied by nothing resolving at all.
  set_tier "$_t" default cheap
  run "$_t" claude
  grep -q '^model:' "$_t/.claude/agents/builder-heavy.md" \
    || fail "R3: an absent builder-heavy key did not fall through to models.default"
  _got="$(grep '^model:' "$_t/.claude/agents/builder-heavy.md")"
  # The reference is the SAME role pinned EXPLICITLY to the same tier on a separate target.
  # Comparing against another role would prove nothing here: every other role carries its
  # own explicit key, so none of them exercises the fall-through at all.
  _tx="$(mk r3x)"; run "$_tx" claude
  set_tier "$_tx" builder-heavy cheap
  run "$_tx" claude
  _want="$(grep '^model:' "$_tx/.claude/agents/builder-heavy.md")"
  [ -n "$_want" ] || fail "R3: setup — an explicit builder-heavy: cheap stamped no model"
  [ "$_got" = "$_want" ] \
    || fail "R3: fall-through resolved '$_got' where an explicit cheap tier gives '$_want'"
  # And the re-run did not silently add the key back to a config the operator owns.
  grep -q '^  builder-heavy:' "$_r3cfg" \
    && fail "R3: the installer added a builder-heavy key to an existing models: block"
  # Back to default: inherit ⇒ omission, on the same target.
  set_tier "$_t" default inherit
  run "$_t" claude
  grep -q '^model:' "$_t/.claude/agents/builder-heavy.md" \
    && fail "R3: default: inherit still stamped a model key on builder-heavy"
  pass "an absent builder-heavy key resolves through models.default and is never seeded (R3)"
}

# ── R4: every selected front-end emits builder-heavy, BY NAME ───────────────────
every_front_end_emits_builder_heavy() {
  _t="$(mk r4)"; run "$_t" "$ALL"
  [ -f "$_t/.harness/agents/builder-heavy.md" ] \
    || fail "R4: the installed body has no agents/builder-heavy.md"
  [ -f "$_t/.claude/agents/builder-heavy.md" ] \
    || fail "R4: claude emitted no builder-heavy shim"
  [ -f "$_t/.codex/agents/builder-heavy.toml" ] \
    || fail "R4: codex emitted no builder-heavy role definition"
  [ -f "$_t/.agents/agents/builder-heavy.md" ] \
    || fail "R4: antigravity emitted no builder-heavy persona"
  grep -q '"builder-heavy"' "$_t/opencode.json" \
    || fail "R4: opencode.json has no builder-heavy member"
  # Claude's shim must carry the SAME tool list as builder — ADR-0002 forbids a behavioral
  # difference, and a different tool list is one.
  _bt="$(grep '^tools:' "$_t/.claude/agents/builder.md")"
  _ht="$(grep '^tools:' "$_t/.claude/agents/builder-heavy.md")"
  [ "$_bt" = "$_ht" ] || fail "R4/ADR-0002: builder-heavy tools ($_ht) differ from builder ($_bt)"
  # Gemini is conditional on a concrete model — assert it appears once one resolves.
  [ -d "$_t/.gemini/agents" ] && fail "R4: all-inherit created .gemini/agents/"
  set_tier "$_t" builder-heavy cheap
  run "$_t" "$ALL"
  [ -f "$_t/.gemini/agents/builder-heavy.md" ] \
    || fail "R4: gemini emitted no builder-heavy definition once a tier resolved"
  pass "all five front-ends emit builder-heavy by name; claude's tool list matches builder (R4)"
}

# ── R9: the two builders resolve independently ──────────────────────────────────
the_two_builders_resolve_independently() {
  _t="$(mk r9)"; run "$_t" claude
  set_tier "$_t" builder cheap
  run "$_t" claude
  grep -q '^model:' "$_t/.claude/agents/builder.md" \
    || fail "R9: setup — pinning builder stamped no model on builder"
  grep -q '^model:' "$_t/.claude/agents/builder-heavy.md" \
    && fail "R9: pinning builder also moved builder-heavy"
  # And the converse, on a fresh target so neither result can be an artifact of the other.
  _t2="$(mk r9b)"; run "$_t2" claude
  set_tier "$_t2" builder-heavy reasoning
  run "$_t2" claude
  grep -q '^model:' "$_t2/.claude/agents/builder-heavy.md" \
    || fail "R9: pinning builder-heavy stamped no model on builder-heavy"
  grep -q '^model:' "$_t2/.claude/agents/builder.md" \
    && fail "R9: pinning builder-heavy also moved builder"
  # Both pinned to DIFFERENT tiers must produce different values — proving the resolver
  # keys off the role name and not off a shared "builder" prefix.
  set_tier "$_t2" builder cheap
  run "$_t2" claude
  [ "$(grep '^model:' "$_t2/.claude/agents/builder.md")" \
    != "$(grep '^model:' "$_t2/.claude/agents/builder-heavy.md")" ] \
    || fail "R9: builder and builder-heavy on different tiers resolved to the same model"
  pass "builder and builder-heavy resolve independently in both directions (R9)"
}

# ── R5: a previous-release target gains the role on upgrade ─────────────────────
opencode_upgrade_gains_the_new_role() {
  _t="$(mk r5)"; run_prev "$_t" opencode
  # Preconditions, asserted — if the fixture is not actually a previous-release file this
  # case must FAIL, not silently pass by testing nothing.
  [ -f "$_t/opencode.json" ] || fail "R5: setup — the previous release wrote no opencode.json"
  [ "$(n_agents "$_t/opencode.json")" = "6" ] \
    || fail "R5: setup — the previous-release opencode.json does not have exactly six agents"
  grep -q '"builder-heavy"' "$_t/opencode.json" \
    && fail "R5: setup — the previous-release opencode.json already has builder-heavy"
  cp "$_t/opencode.json" "$T/r5.prev"

  _e="$(run_err "$_t" opencode)"
  # POSITIVE outcome, not merely the absence of a warning. A legacy candidate that is not
  # byte-exact fails exactly like the bug — same warning, same stale role set — so absence
  # of output is not evidence the fix worked.
  grep -q '"builder-heavy"' "$_t/opencode.json" \
    || fail "R5: an upgraded previous-release opencode.json did not gain builder-heavy"
  [ "$(n_agents "$_t/opencode.json")" = "7" ] \
    || fail "R5: the upgraded opencode.json does not have exactly seven agents"
  [ -f "$_t/.harness/.opencode.stamp" ] \
    || fail "R5: the upgrade wrote no .opencode.stamp"
  cmp -s "$_t/opencode.json" "$_t/.harness/.opencode.stamp" \
    || fail "R5: .opencode.stamp is not a byte copy of the opencode.json written"
  printf '%s\n' "$_e" | grep -q 'differs from the generated stamp' \
    && fail "R5: a pristine previous-release opencode.json was reported as edited"
  pass "a previous-release opencode.json gains builder-heavy on upgrade and is stamped (R5)"
}

# ── R5: the upgrade is idempotent ───────────────────────────────────────────────
opencode_upgrade_is_idempotent() {
  _t="$(mk r5i)"; run_prev "$_t" opencode
  run "$_t" opencode
  cp "$_t/opencode.json" "$T/r5i.after1"
  _e="$(run_err "$_t" opencode)"
  cmp -s "$T/r5i.after1" "$_t/opencode.json" \
    || fail "R5: a second upgrade run changed opencode.json"
  printf '%s\n' "$_e" | grep -q 'differs from the generated stamp' \
    && fail "R5: the second run reported the file it just wrote as edited"
  pass "a second upgrade run is silent and byte-identical (R5, idempotence)"
}

# ── R5a: widening the pristine test did not defeat it ───────────────────────────
opencode_edited_file_is_still_refused() {
  _t="$(mk r5a)"; run_prev "$_t" opencode
  # A real user edit on top of a previous-release file: the case the widened test must
  # still refuse. Without this control, accepting ANYTHING would satisfy R5.
  printf '%s\n' '// my own note' >> "$_t/opencode.json"
  cp "$_t/opencode.json" "$T/r5a.before"
  _e="$(run_err "$_t" opencode)"
  cmp -s "$T/r5a.before" "$_t/opencode.json" \
    || fail "R5a: an edited opencode.json was overwritten"
  grep -q '"builder-heavy"' "$_t/opencode.json" \
    && fail "R5a: an edited opencode.json gained builder-heavy"
  printf '%s\n' "$_e" | grep -q 'differs from the generated stamp' \
    || fail "R5a: an edited opencode.json was not reported"
  pass "a genuinely edited opencode.json is still refused byte-identically (R5a)"
}

# ── R6: deselect reclaims a previous-release file ───────────────────────────────
opencode_deselect_reclaims_a_prior_release_file() {
  _t="$(mk r6)"; run_prev "$_t" opencode
  [ -f "$_t/opencode.json" ] || fail "R6: setup — no opencode.json to reclaim"
  [ "$(n_agents "$_t/opencode.json")" = "6" ] \
    || fail "R6: setup — the fixture is not a six-agent previous-release file"
  _e="$(run_err "$_t" claude)"
  [ -f "$_t/opencode.json" ] \
    && fail "R6: deselect left a pristine previous-release opencode.json behind"
  printf '%s\n' "$_e" | grep -q "removed deselected agent 'opencode' glue: opencode.json" \
    || fail "R6: deselect did not report removing opencode.json"
  # Control: an EDITED previous-release file must still survive the same deselect.
  _t2="$(mk r6b)"; run_prev "$_t2" opencode
  printf '%s\n' '// mine' >> "$_t2/opencode.json"
  cp "$_t2/opencode.json" "$T/r6b.before"
  run_err "$_t2" claude >/dev/null 2>&1 || true
  [ -f "$_t2/opencode.json" ] || fail "R6: deselect deleted an EDITED opencode.json"
  cmp -s "$T/r6b.before" "$_t2/opencode.json" \
    || fail "R6: deselect modified an edited opencode.json"
  pass "deselect reclaims a pristine previous-release opencode.json, preserves an edited one (R6)"
}

# ── R7: deselect reclaims the builder-heavy artifact on every front-end ─────────
deselect_reclaims_builder_heavy() {
  _t="$(mk r7)"; run "$_t" "$ALL"
  set_tier "$_t" builder-heavy cheap
  run "$_t" "$ALL"
  [ -f "$_t/.codex/agents/builder-heavy.toml" ] || fail "R7: setup — no codex artifact"
  [ -f "$_t/.gemini/agents/builder-heavy.md" ]  || fail "R7: setup — no gemini artifact"
  [ -f "$_t/.agents/agents/builder-heavy.md" ]  || fail "R7: setup — no antigravity persona"
  [ -f "$_t/.claude/agents/builder-heavy.md" ]  || fail "R7: setup — no claude shim"

  run_err "$_t" claude >/dev/null 2>&1 || true
  [ -f "$_t/.codex/agents/builder-heavy.toml" ] \
    && fail "R7: deselecting codex left builder-heavy.toml behind"
  [ -f "$_t/.gemini/agents/builder-heavy.md" ] \
    && fail "R7: deselecting gemini left builder-heavy.md behind"
  [ -f "$_t/.agents/agents/builder-heavy.md" ] \
    && fail "R7: deselecting antigravity left the builder-heavy persona behind"
  [ -f "$_t/.harness/.model-agents/codex/builder-heavy.toml" ] \
    && fail "R7: the codex builder-heavy ownership stamp outlived its artifact"

  # Now deselect claude too, and assert the shim goes with it.
  run_err "$_t" codex >/dev/null 2>&1 || true
  [ -f "$_t/.claude/agents/builder-heavy.md" ] \
    && fail "R7: deselecting claude left the builder-heavy shim behind"
  # By NAME, not by count: the codex tree must be back to the six standard roles, and
  # builder-heavy must be the one that left.
  [ -f "$_t/.codex/agents/builder.toml" ] \
    || fail "R7: reclaiming builder-heavy also removed builder"
  pass "every front-end reclaims builder-heavy and its stamp on deselect (R7)"
}

pointer_body_duplicates_nothing
absent_key_falls_through_to_default
every_front_end_emits_builder_heavy
the_two_builders_resolve_independently
opencode_upgrade_gains_the_new_role
opencode_upgrade_is_idempotent
opencode_edited_file_is_still_refused
opencode_deselect_reclaims_a_prior_release_file
deselect_reclaims_builder_heavy

echo "test_builder_heavy.sh: all cases passed"
