#!/bin/sh
# test_owner_gate.sh — E99-F77: a park may say the OWNER releases it (`parked.gate: "owner"`).
#
# THE CONTROL IS THE POINT (same discipline as test_feature_park.sh). "A gated feature is not
# selected" is the default outcome for most boards, so every case here first asserts the SAME
# board WITHOUT the gate behaves differently — selected, or blocked under the plain `parked`
# code — and only then adds the gate. Without that pairing the whole suite would pass against
# an implementation that does nothing at all.
#
# What is under test is BEHAVIOUR, not the presence of a field:
#   R1  the selector SKIPS a gated feature and emits code `gated-owner`
#   R2  the diagnostic carries the REASON (and never renders `undefined`)
#   R3  it names the release condition AND the route when released (the route is not suppressed)
#   R4  an unrecognised gate is REJECTED, never silently downgraded to a plain park
#   R5  `done` is not reachable: set-status refuses and names the owner gate; the board is untouched
#   R6  genuinely actionable work is NOT hidden — a sibling is still selected
#   R7  migration: a park with no `gate` is unchanged, and the repo's own live board still validates
#   R8  a dependent one hop away names the owner gate, not a generic wait

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-ownergate)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v node >/dev/null 2>&1 || fail "node is absent — next-task.mjs cannot run"
command -v python3 >/dev/null 2>&1 || fail "python3 is absent"

# ── Fixture: a minimal board + config, written fresh per case ─────────────────────────
# `mkboard <parked-json-for-F01> <depends_on-for-F02>` — F01 is the subject, F02 either the
# dependent (R8) or the independent sibling that must still be selectable (R6).
mkboard() {
  _park="$1"; _dep="$2"
  cat > "$T/tasks.json" <<EOF
{
  "project": "owner-gate-fixture",
  "epics": [
    {
      "id": "E01", "title": "fixture epic", "status": "in-progress", "owner": "tester",
      "features": [
        { "id": "E01-F01", "title": "subject", "status": "pending", "sdd": true,
          "autonomous": false, "depends_on": [], "spec_path": "specs/e01f01/"$_park },
        { "id": "E01-F02", "title": "sibling", "status": "pending", "sdd": true,
          "autonomous": false, "depends_on": [$_dep], "spec_path": "specs/e01f02/" }
      ]
    }
  ]
}
EOF
}
cat > "$T/harness.config.yaml" <<'EOF'
store:
  backend: local
workflow:
  require_approval: true
umbrella:
  manifest: ""
EOF

# next <args...> -> NX_OUT / NX_RC   (the REAL selector, never a reimplementation)
next() {
  NX_OUT="$(cd "$SRC" && node tools/next-task.mjs --tasks "$T/tasks.json" --config "$T/harness.config.yaml" "$@" 2>&1)" && NX_RC=0 || NX_RC=$?
}
jqx() { printf '%s' "$NX_OUT" | python3 -c "import json,sys;d=json.load(sys.stdin);print($1)"; }
codes() { jqx "','.join(b['code'] for b in d.get('blocked',[]))"; }
detail_for() { jqx "([b['detail'] for b in d.get('blocked',[]) if b['code']=='$1'] or ['<no $1 record>'])[0]"; }

REASON="R1/R8/R11 are console-only owner attestations"
GATE=", \"parked\": { \"gate\": \"owner\", \"reason\": \"$REASON\" }"
GATE_UB=", \"parked\": { \"gate\": \"owner\", \"reason\": \"$REASON\", \"unblocked_by\": \"the owner attests in the consoles\" }"
PARK=", \"parked\": { \"reason\": \"blocked on a Meta review cycle\" }"

# ── R1/R2/R3: the control, then the gate ─────────────────────────────────────────────
# One sequence on one fixture, because the claim is a difference between two boards.
mkboard "" '"E01-F01"'
next
[ "$NX_RC" = "0" ] || fail "R1 control: the selector failed on a clean board (rc=$NX_RC): $NX_OUT"
[ "$(jqx "d['outcome']")" = "selected" ] \
  || fail "R1 control: the UNGATED feature was not selected — every assertion below would be vacuous: $NX_OUT"
_route_ungated="$(jqx "d['selected']['route']")"
[ "$_route_ungated" = "architect" ] || fail "R1 control: expected route architect, got $_route_ungated"
_id_ungated="$(jqx "d['selected']['feature_id']")"
[ "$_id_ungated" = "E01-F01" ] || fail "R1 control: expected E01-F01 selected, got $_id_ungated"

mkboard "$GATE" '"E01-F01"'
next
[ "$(jqx "d['outcome']")" = "blocked" ] \
  || fail "R1: an OWNER-GATED feature was still selected — this is the mis-routing the feature exists to end: $NX_OUT"
case "$(codes)" in
  *gated-owner*) ;;
  *) fail "R1: no 'gated-owner' blocker record (codes=$(codes)) — the Orchestrator cannot tell an owner gate from an ordinary park: $NX_OUT" ;;
esac
# ...and NOT under the generic park code: telling them apart is the whole deliverable.
case "$(codes)" in
  *,parked*|parked*) fail "R1: an owner gate reported as the generic 'parked' code (codes=$(codes))" ;;
esac
_d="$(detail_for gated-owner)"
case "$_d" in
  *"$REASON"*) ;;
  *) fail "R2: the gated-owner detail does not carry the reason — 'blocked' without saying on what is the same tribal knowledge in a new field: [$_d]" ;;
esac
case "$_d" in
  *undefined*) fail "R2: the gated-owner detail rendered 'undefined' — the reason requirement is not being enforced: [$_d]" ;;
esac
pass "E99-F77 R1 owner_gated_feature_is_skipped_with_its_own_code"
pass "E99-F77 R2 gated_owner_detail_carries_the_reason"

# R3: the release condition is rendered, and the underlying route is NOT suppressed.
# `architect` is the route this feature has UNGATED, asserted as the control above — so a
# mutation that nulls featureRoute for a gated feature (which changes no selection outcome
# at all, and would therefore survive every other assertion here) dies right here.
mkboard "$GATE_UB" '"E01-F01"'
next
_d="$(detail_for gated-owner)"
case "$_d" in
  *"unblocked by: the owner attests in the consoles"*) ;;
  *) fail "R3: the release condition (unblocked_by) was not rendered: [$_d]" ;;
esac
case "$_d" in
  *"route when released: $_route_ungated"*) ;;
  *) fail "R3: the gate suppressed the underlying route (expected 'route when released: $_route_ungated') — a gate is a BLOCKER, not a route: [$_d]" ;;
esac
case "$_d" in
  *"a person must act, not an agent"*) ;;
  *) fail "R3: the diagnostic does not say a PERSON releases it, which is the one thing an Orchestrator must not re-derive from history.md: [$_d]" ;;
esac
pass "E99-F77 R3 detail_names_the_release_condition_and_the_route"

# ── R2 (enforcement): a gate with no usable reason is rejected by ALL THREE validators ──
# Paired with the SAME board plus a reason, asserted VALID in the same run, so each
# rejection is attributable to the missing reason and nothing else.
validate() {  # validate <board> [--no-jsonschema] -> V_OUT / V_RC
  _b="$1"; shift
  if [ "${1:-}" = "--no-jsonschema" ]; then
    V_OUT="$(cd "$SRC" && PYTHONPATH="$T/blocker" python3 tools/validate-board.py "$_b" store/tasks.schema.json 2>&1)" && V_RC=0 || V_RC=$?
  else
    V_OUT="$(cd "$SRC" && python3 tools/validate-board.py "$_b" store/tasks.schema.json 2>&1)" && V_RC=0 || V_RC=$?
  fi
}
mkdir -p "$T/blocker"
cat > "$T/blocker/jsonschema.py" <<'PY'
raise ImportError("forced absent by test_owner_gate.sh")
PY

for _mode in "" "--no-jsonschema"; do
  _label="jsonschema"; [ -n "$_mode" ] && _label="zero-dep fallback"
  if [ -n "$_mode" ]; then
    if (cd "$SRC" && PYTHONPATH="$T/blocker" python3 -c 'import jsonschema' 2>/dev/null); then
      fail "R2 precondition ($_label): jsonschema still imports, so this re-tests the path already covered"
    fi
  fi
  mkboard "$GATE" ''
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] || fail "R2 control ($_label): a well-formed owner gate was rejected (rc=$V_RC): $V_OUT"

  mkboard ', "parked": { "gate": "owner" }' ''
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] && fail "R2 ($_label): an owner gate with NO reason was accepted — a gate that does not say what it waits on is the defect, not the fix: $V_OUT"

  mkboard ', "parked": { "gate": "owner", "reason": "" }' ''
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] && fail "R2 ($_label): an owner gate with an EMPTY reason was accepted: $V_OUT"
done
# ...and the selector, which carries its OWN validator (a board reaching it through --tasks
# never passes the shared one).
for _bad in '{ "gate": "owner" }' '{ "gate": "owner", "reason": "" }'; do
  mkboard ", \"parked\": $_bad" ''
  next
  [ "$NX_RC" = "0" ] \
    && fail "R2/selector: an owner gate with no usable reason ($_bad) was accepted instead of input-error: $NX_OUT"
done
mkboard "$GATE" ''
next
[ "$NX_RC" = "0" ] \
  || fail "R2/selector control: a well-formed owner gate was rejected too, so the rejections above are not attributable to the missing reason: $NX_OUT"
pass "E99-F77 R2 a_gate_without_a_reason_is_invalid_everywhere"

# ── R4: an unrecognised gate is an ERROR, never a silent downgrade to a plain park ────
# The reason code IS the deliverable. A typo that quietly reads as `parked` reports the
# wrong one — worse than no gate, because it stops anyone looking.
for _bad in '"ownr"' '"vendor"' 'true' '""'; do
  mkboard ", \"parked\": { \"gate\": $_bad, \"reason\": \"$REASON\" }" ''
  next
  if [ "$NX_RC" = "0" ]; then
    fail "R4/selector: an unrecognised gate ($_bad) was accepted (codes=$(codes)) instead of input-error: $NX_OUT"
  fi
  case "$NX_OUT" in
    *gate*) ;;
    *) fail "R4/selector: the rejection of gate=$_bad does not name the gate, so it failed for some unrelated reason: $NX_OUT" ;;
  esac
  for _mode in "" "--no-jsonschema"; do
    _label="jsonschema"; [ -n "$_mode" ] && _label="zero-dep fallback"
    validate "$T/tasks.json" $_mode
    [ "$V_RC" = "0" ] && fail "R4 ($_label): an unrecognised gate ($_bad) was accepted by the board validator: $V_OUT"
  done
done
pass "E99-F77 R4 an_unrecognised_gate_is_rejected_not_downgraded"

# ── R5: `done` is not reachable by accident — set-status refuses and names the gate ───
mkdir -p "$T/hd/state" "$T/hd/store" "$T/hd/tools"
cp "$SRC/store/tasks.schema.json" "$T/hd/store/"
cp "$SRC/tools/validate-board.py" "$T/hd/tools/"
mkboard "$GATE" ''
cp "$T/tasks.json" "$T/hd/state/tasks.json"
_before="$(cat "$T/hd/state/tasks.json")"
SS_OUT="$(HARNESS_DIR="$T/hd" python3 "$SRC/tools/tasks-lock.py" set-status E01-F01 done 2>&1)" && SS_RC=0 || SS_RC=$?
[ "$SS_RC" = "0" ] && fail "R5: set-status walked an OWNER-GATED feature to done: $SS_OUT"
case "$SS_OUT" in
  *"$REASON"*) ;;
  *) fail "R5: the refusal does not name the gate reason: $SS_OUT" ;;
esac
case "$SS_OUT" in
  *owner-gated*) ;;
  *) fail "R5: the refusal does not distinguish an owner gate from an ordinary park, so it reads as 'unpark and carry on' — which is how the attestations get skipped: $SS_OUT" ;;
esac
case "$SS_OUT" in
  *unpark*) ;;
  *) fail "R5: the refusal does not say how to proceed (no 'unpark'): $SS_OUT" ;;
esac
[ "$_before" = "$(cat "$T/hd/state/tasks.json")" ] || fail "R5: the board was modified despite the refusal"
# control, SAME harness dir: the identical transition succeeds once the gate is removed
mkboard '' ''
cp "$T/tasks.json" "$T/hd/state/tasks.json"
SS_OUT="$(HARNESS_DIR="$T/hd" python3 "$SRC/tools/tasks-lock.py" set-status E01-F01 done 2>&1)" && SS_RC=0 || SS_RC=$?
[ "$SS_RC" = "0" ] \
  || fail "R5 control: the same transition failed on an UNGATED feature (rc=$SS_RC), so the refusal above is not attributable to the gate: $SS_OUT"
_status_now="$(python3 -c "import json;print(json.load(open('$T/hd/state/tasks.json'))['epics'][0]['features'][0]['status'])")"
[ "$_status_now" = "done" ] || fail "R5 control: the ungated transition did not land (status=$_status_now)"
pass "E99-F77 R5 set_status_refuses_an_owner_gated_feature"

# ── R6: a gate must not hide genuinely actionable work ───────────────────────────────
# F02 is independent here, so the board still HAS work. A "fix" that halted the whole
# board on encountering a gate would pass R1 and fail here.
mkboard "$GATE" ''
next
[ "$NX_RC" = "0" ] || fail "R6: the selector failed on a board with one gated and one free feature: $NX_OUT"
[ "$(jqx "d['outcome']")" = "selected" ] \
  || fail "R6: an owner gate on E01-F01 suppressed the actionable sibling E01-F02 — a gate must skip ONE item, not stop the board: $NX_OUT"
[ "$(jqx "d['selected']['feature_id']")" = "E01-F02" ] \
  || fail "R6: expected the sibling E01-F02, got $(jqx "d['selected']['feature_id']"): $NX_OUT"
pass "E99-F77 R6 a_gate_does_not_hide_actionable_work"

# ── R7 (migration): a park with NO gate is unchanged, and existing boards still validate ─
mkboard "$PARK" '"E01-F01"'
next
[ "$(jqx "d['outcome']")" = "blocked" ] || fail "R7: an ordinary park stopped blocking: $NX_OUT"
case "$(codes)" in
  *gated-owner*) fail "R7: an ungated park reported as gated-owner (codes=$(codes)) — the discriminator fires on every park: $NX_OUT" ;;
esac
case "$(codes)" in
  *parked*) ;;
  *) fail "R7: an ordinary park lost its 'parked' record (codes=$(codes)): $NX_OUT" ;;
esac
_d="$(detail_for parked)"
case "$_d" in
  *"route when unparked: architect"*) ;;
  *) fail "R7: the ordinary park's detail changed shape: [$_d]" ;;
esac
case "$_d" in
  *"owner gate"*) fail "R7: owner-gate wording leaked into an ordinary park: [$_d]" ;;
esac
# The REAL migration question: does every EXISTING board still validate? Answered against
# the repo's own live board, under both validator paths, rather than assumed.
[ -f "$SRC/state/tasks.json" ] || fail "R7 precondition: the repo board is missing"
for _mode in "" "--no-jsonschema"; do
  _label="jsonschema"; [ -n "$_mode" ] && _label="zero-dep fallback"
  validate "$SRC/state/tasks.json" $_mode
  [ "$V_RC" = "0" ] \
    || fail "R7 ($_label): the repo's own pre-existing board no longer validates — the gate is not additive: $V_OUT"
done
LIVE="$(cd "$SRC" && node tools/next-task.mjs --tasks "$SRC/state/tasks.json" 2>&1)" && LIVE_RC=0 || LIVE_RC=$?
[ "$LIVE_RC" = "0" ] || fail "R7: the selector failed on the repo's own board (rc=$LIVE_RC): $LIVE"
pass "E99-F77 R7 the_gate_is_additive_existing_boards_are_untouched"

# ── R8: a dependent one hop away names the OWNER gate, not a generic wait ────────────
mkboard "$GATE" '"E01-F01"'
next --feature E01-F02
_dep_detail="$(detail_for unmet-dependency)"
case "$_dep_detail" in
  *"owner gate: $REASON"*) ;;
  *) fail "R8: the dependent's unmet-dependency detail does not name the owner gate — 'parked' tells a reader to wait, and waiting will never clear this: [$_dep_detail]" ;;
esac
# control, same fixture shape: with an ORDINARY park the dependent says 'parked', not 'owner gate'
mkboard "$PARK" '"E01-F01"'
next --feature E01-F02
_dep_detail="$(detail_for unmet-dependency)"
case "$_dep_detail" in
  *"owner gate"*) fail "R8 control: the owner-gate marker appears for an ordinary park — the assertion above is not attributable to the gate: [$_dep_detail]" ;;
esac
case "$_dep_detail" in
  *"parked: blocked on a Meta review cycle"*) ;;
  *) fail "R8 control: the dependent stopped naming the ordinary park at all: [$_dep_detail]" ;;
esac
pass "E99-F77 R8 a_dependent_names_the_owner_gate"

# ── R1 (targeting): targeting a gated feature explicitly is blocked, not selected ─────
mkboard "$GATE" ''
next --feature E01-F01
[ "$(jqx "d['outcome']")" = "blocked" ] || fail "R1/target: targeting an owner-gated feature selected it: $NX_OUT"
case "$(codes)" in *gated-owner*) ;; *) fail "R1/target: no gated-owner record when targeted (codes=$(codes))" ;; esac
mkboard "" ''
next --feature E01-F01
[ "$(jqx "d['outcome']")" = "selected" ] \
  || fail "R1/target control: targeting the UNGATED feature did not select it, so the block above proves nothing: $NX_OUT"
pass "E99-F77 R1 targeting_an_owner_gated_feature_is_blocked"

echo "All owner-gate tests passed."
