#!/bin/sh
# test_feature_park.sh — E06-F07: a feature-level park.
#
# THE CONTROL IS THE POINT. "A parked feature is not selected" is the default outcome for
# most boards, so every park case here first asserts the SAME feature IS selected while
# unparked, with a known route, and only then parks it. Without that pairing the whole
# suite would pass against an implementation that does nothing at all.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-park)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v node >/dev/null 2>&1 || fail "node is absent — next-task.mjs cannot run"
command -v python3 >/dev/null 2>&1 || fail "python3 is absent"

# ── Fixture: a minimal board + config, written fresh per case ─────────────────────────
# `mkboard <parked-json-for-F01> <depends_on-for-F02>` — F01 is the subject, F02 the
# dependent used by R5. Keeping both in one board lets a single selector run observe the
# park and the chain that stalls behind it.
mkboard() {
  _park="$1"; _dep="$2"
  cat > "$T/tasks.json" <<EOF
{
  "project": "park-fixture",
  "epics": [
    {
      "id": "E01", "title": "fixture epic", "status": "in-progress", "owner": "tester",
      "features": [
        { "id": "E01-F01", "title": "subject", "status": "pending", "sdd": true,
          "autonomous": false, "depends_on": [], "spec_path": "specs/e01f01/"$_park },
        { "id": "E01-F02", "title": "dependent", "status": "pending", "sdd": true,
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

PARK=', "parked": { "reason": "blocked on a Meta review cycle" }'
PARK_UB=', "parked": { "reason": "blocked on a Meta review", "unblocked_by": "review closes" }'

# ── R2 / R9 (and the control for R1): unparked selects; parked blocks; unparked again ──
# Run as ONE sequence on the same fixture, because the claim is a round trip.
mkboard "" '"E01-F01"'
next
[ "$NX_RC" = "0" ] || fail "R2 control: the selector failed on a clean board (rc=$NX_RC): $NX_OUT"
_kind="$(jqx "d['outcome']")"; _route="$(jqx "d['selected']['route'] if d.get('selected') else 'none'")"
[ "$_kind" = "selected" ] || fail "R2 control: an UNPARKED sdd feature was not selected (kind=$_kind) — every park assertion below would be vacuous: $NX_OUT"
[ "$_route" = "architect" ] || fail "R2 control: expected route architect, got $_route"
_before_route="$_route"

mkboard "$PARK" '"E01-F01"'
next
[ "$(jqx "d['outcome']")" = "blocked" ] \
  || fail "R1: a PARKED feature was still selected: $NX_OUT"
_codes="$(jqx "','.join(b['code'] for b in d.get('blocked',[]))")"
case "$_codes" in *parked*) ;; *) fail "R1: no 'parked' blocker record (codes=$_codes): $NX_OUT" ;; esac
_detail="$(jqx "[b['detail'] for b in d['blocked'] if b['code']=='parked'][0]")"
case "$_detail" in *"blocked on a Meta review cycle"*) ;; *) fail "R1: the park detail does not carry the reason: [$_detail]" ;; esac
# R2, made OBSERVABLE. featureRoute is called with the park in place and must still return
# the real route. Nulling the route when parked yields identical selection behaviour, so
# without this assertion the "blocker, not route" rule is unfalsifiable — a mutation that
# nulled it survived the whole suite. `architect` is the route this feature has UNPARKED,
# asserted as the control above.
case "$_detail" in
  *"route when unparked: architect"*) ;;
  *) fail "R2: the park suppressed the underlying route — a park must be a BLOCKER, not a route: [$_detail]" ;;
esac
pass "E06-F07 R1 parked_feature_is_blocked"

mkboard "" '"E01-F01"'
next
[ "$(jqx "d['outcome']")" = "selected" ] || fail "R9: unparking did not restore selection: $NX_OUT"
[ "$(jqx "d['selected']['route']")" = "$_before_route" ] \
  || fail "R9/R2: the route changed across the park round trip (was $_before_route, now $(jqx "d['selected']['route']"))"
[ "$(jqx "d['selected']['status']")" = "pending" ] \
  || fail "R2: the status changed across the park round trip"
pass "E06-F07 R2 park_does_not_alter_route"
pass "E06-F07 R9 unpark_restores_selection"

# ── R1 detail: `unblocked_by` is rendered when present ───────────────────────────────
mkboard "$PARK_UB" '"E01-F01"'
next
_detail="$(jqx "[b['detail'] for b in d['blocked'] if b['code']=='parked'][0]")"
case "$_detail" in *"unblocked by: review closes"*) ;; *) fail "R1: unblocked_by was not rendered: [$_detail]" ;; esac
pass "E06-F07 R1 park_detail_renders_unblocked_by"

# ── R4: targeting a parked feature explicitly is blocked, not selected ───────────────
mkboard "$PARK" ""
next --feature E01-F01
[ "$(jqx "d['outcome']")" = "blocked" ] || fail "R4: targeting a parked feature selected it: $NX_OUT"
_codes="$(jqx "','.join(b['code'] for b in d.get('blocked',[]))")"
case "$_codes" in *parked*) ;; *) fail "R4: no parked record when targeted (codes=$_codes)" ;; esac
# control, same fixture shape: targeting it UNPARKED does select it
mkboard "" ""
next --feature E01-F01
[ "$(jqx "d['outcome']")" = "selected" ] \
  || fail "R4 control: targeting the UNPARKED feature did not select it, so the block above proves nothing: $NX_OUT"
pass "E06-F07 R4 targeting_a_parked_feature_is_blocked"

# ── R5: a dependent names the park and its reason ────────────────────────────────────
mkboard "$PARK" '"E01-F01"'
next --feature E01-F02
_dep_detail="$(jqx "[b['detail'] for b in d['blocked'] if b['code']=='unmet-dependency'][0]")"
case "$_dep_detail" in
  *"parked: blocked on a Meta review cycle"*) ;;
  *) fail "R5: the dependent's unmet-dependency detail does not name the park: [$_dep_detail]" ;;
esac
# control: with F01 UNPARKED the dependent still reports unmet-dependency, WITHOUT the marker
mkboard "" '"E01-F01"'
next --feature E01-F02
_dep_detail="$(jqx "[b['detail'] for b in d['blocked'] if b['code']=='unmet-dependency'][0]")"
case "$_dep_detail" in
  *parked*) fail "R5 control: the parked marker appears for an UNPARKED dependency — the assertion above is not attributable to the park: [$_dep_detail]" ;;
esac
case "$_dep_detail" in
  *"E01-F01=pending"*) ;;
  *) fail "R5 control: the dependent stopped reporting its unmet dependency at all: [$_dep_detail]" ;;
esac
pass "E06-F07 R5 dependent_reports_the_park"

# ── R6: the park composes with a LATER status, and leaves status untouched ───────────
# A park arriving after speccing is the case a `parked` STATUS value could not express.
mkboard "$PARK" ""
python3 - "$T/tasks.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["epics"][0]["features"][0]["status"] = "spec-ready"
json.dump(d, open(p, "w"), indent=2)
PY
next --feature E01-F01
[ "$(jqx "d['outcome']")" = "blocked" ] || fail "R6: a park at spec-ready did not hold: $NX_OUT"
_codes="$(jqx "','.join(b['code'] for b in d.get('blocked',[]))")"
case "$_codes" in *parked*) ;; *) fail "R6: no parked record at spec-ready (codes=$_codes)" ;; esac
_status_now="$(python3 -c "import json;print(json.load(open('$T/tasks.json'))['epics'][0]['features'][0]['status'])")"
[ "$_status_now" = "spec-ready" ] || fail "R6: the park changed the feature's status to $_status_now"
pass "E06-F07 R6 park_composes_with_every_status"

# ── R3: schema rejects a park with no usable reason, and the fallback agrees ─────────
# Each invalid fixture is paired with the SAME board minus the bad key, asserted VALID in
# the same run, so the rejection is attributable to the park and nothing else.
validate() {  # validate <board> [--no-jsonschema] -> V_OUT / V_RC
  _b="$1"; shift
  if [ "${1:-}" = "--no-jsonschema" ]; then
    V_OUT="$(cd "$SRC" && PYTHONPATH="$T/blocker" python3 tools/validate-board.py "$_b" store/tasks.schema.json 2>&1)" && V_RC=0 || V_RC=$?
  else
    V_OUT="$(cd "$SRC" && python3 tools/validate-board.py "$_b" store/tasks.schema.json 2>&1)" && V_RC=0 || V_RC=$?
  fi
}
# A stub package that makes `import jsonschema` raise ImportError, forcing the fallback.
mkdir -p "$T/blocker"
cat > "$T/blocker/jsonschema.py" <<'PY'
raise ImportError("forced absent by test_feature_park.sh")
PY

for _mode in "" "--no-jsonschema"; do
  _label="jsonschema"; [ -n "$_mode" ] && _label="zero-dep fallback"
  # precondition: in fallback mode the forced path must actually be the one taken
  if [ -n "$_mode" ]; then
    if (cd "$SRC" && PYTHONPATH="$T/blocker" python3 -c 'import jsonschema' 2>/dev/null); then
      fail "R3 precondition ($_label): jsonschema still imports, so this re-tests the path already covered"
    fi
  fi
  mkboard '' ''
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] || fail "R3 control ($_label): the clean board was rejected (rc=$V_RC): $V_OUT"

  mkboard ', "parked": { "reason": "" }' ''
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] && fail "R3 ($_label): an EMPTY parked.reason was accepted: $V_OUT"

  mkboard ', "parked": { "unblocked_by": "x" }' ''
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] && fail "R3 ($_label): a parked object with NO reason was accepted: $V_OUT"

  mkboard ', "parked": "just a string"' ''
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] && fail "R3 ($_label): a non-object parked was accepted: $V_OUT"
done
# ── R3 (Codex #3713988129/#3713988137): the SELECTOR's own validator agrees ─────────
# next-task.mjs carries a validator independent of the shared one init.sh runs, so a board
# reaching it through --tasks was consumed unvalidated. Consequences were concrete:
# `"parked": null` is falsy, so the park was silently IGNORED and the feature SELECTED;
# a string or {} produced a blocker whose detail read "undefined".
for _bad in 'null' '"a string"' '{}' '{ "reason": "" }' '{ "unblocked_by": "x" }'; do
  mkboard ", \"parked\": $_bad" ''
  next
  [ "$NX_RC" = "0" ] \
    && fail "R3/selector: a malformed park ($_bad) was accepted by next-task.mjs instead of input-error: $NX_OUT"
  case "$NX_OUT" in
    *input-error*|*parked*) ;;
    *) fail "R3/selector: a malformed park ($_bad) failed for some unrelated reason: $NX_OUT" ;;
  esac
done
# control, same shape: a WELL-FORMED park is still accepted and still blocks
mkboard "$PARK" '"E01-F01"'
next
[ "$NX_RC" = "0" ] \
  || fail "R3/selector control: a well-formed park was rejected too, so the rejections above are not attributable to malformedness: $NX_OUT"
pass "E06-F07 R3 selector_validator_rejects_a_malformed_park"

# ── R3: a `done` feature cannot be parked (all three validators) ────────────────────
# A park means "not yet workable"; done means finished. Left legal it also defeats R4:
# select() short-circuits a done TARGET to `target-complete` before any blocker exists,
# so the park would never be reported.
mkboard "$PARK" ''
python3 - "$T/tasks.json" <<'PYX'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["epics"][0]["features"][0]["status"] = "done"
json.dump(d, open(p, "w"), indent=2)
PYX
next --feature E01-F01
[ "$NX_RC" = "0" ] && fail "R3/done: the selector accepted a done+parked feature: $NX_OUT"
case "$NX_OUT" in *"cannot be parked"*) ;; *) fail "R3/done: selector rejection does not name the rule: $NX_OUT" ;; esac
for _mode in "" "--no-jsonschema"; do
  _label="jsonschema"; [ -n "$_mode" ] && _label="zero-dep fallback"
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] && fail "R3/done ($_label): a done+parked board was accepted: $V_OUT"
done
# control: the SAME board, done but UNPARKED, is valid everywhere
mkboard '' ''
python3 - "$T/tasks.json" <<'PYX'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["epics"][0]["features"][0]["status"] = "done"
json.dump(d, open(p, "w"), indent=2)
PYX
for _mode in "" "--no-jsonschema"; do
  validate "$T/tasks.json" $_mode
  [ "$V_RC" = "0" ] || fail "R3/done control: a done UNPARKED board was rejected, so the rejections above are not attributable to the park: $V_OUT"
done
next --feature E01-F01
[ "$NX_RC" = "0" ] || fail "R3/done control: the selector rejected a done unparked feature: $NX_OUT"
pass "E06-F07 R3 done_feature_cannot_be_parked"

pass "E06-F07 R3 empty_reason_is_invalid"
pass "E06-F07 R3 fallback_validator_agrees"

# ── R7: a board with no `parked` key anywhere behaves exactly as before ──────────────
# Compared against the REAL selector's output on the repo's own board, captured in the
# same run — not a hand-written expectation that could drift into agreeing with a bug.
[ -f "$SRC/state/tasks.json" ] || fail "R7 precondition: the repo board is missing"
python3 -c "
import json,sys
d=json.load(open('$SRC/state/tasks.json'))
n=sum(1 for e in d['epics'] for f in e.get('features',[]) if 'parked' in f)
sys.exit(0 if n==0 else 1)" \
  || fail "R7 precondition: the repo board already carries a parked key, so this is not a no-parks board"
LIVE="$(cd "$SRC" && node tools/next-task.mjs 2>&1)" && LIVE_RC=0 || LIVE_RC=$?
[ "$LIVE_RC" = "0" ] || fail "R7: the selector failed on the repo's own parkless board (rc=$LIVE_RC): $LIVE"
printf '%s' "$LIVE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert 'parked' not in json.dumps(d), 'a parked artifact leaked into a parkless board result'
print('ok')" >/dev/null || fail "R7: a parkless board produced park-related output: $LIVE"
pass "E06-F07 R7 absent_parked_key_is_a_pure_superset"

# ── R8: set-status refuses a parked feature, names the reason, writes nothing ────────
mkdir -p "$T/hd/state" "$T/hd/store" "$T/hd/tools"
cp "$SRC/store/tasks.schema.json" "$T/hd/store/"
cp "$SRC/tools/validate-board.py" "$T/hd/tools/"
mkboard "$PARK" ''
cp "$T/tasks.json" "$T/hd/state/tasks.json"
_before="$(cat "$T/hd/state/tasks.json")"
SS_OUT="$(HARNESS_DIR="$T/hd" python3 "$SRC/tools/tasks-lock.py" set-status E01-F01 in-progress 2>&1)" && SS_RC=0 || SS_RC=$?
[ "$SS_RC" = "0" ] && fail "R8: set-status ACCEPTED a transition on a parked feature: $SS_OUT"
case "$SS_OUT" in
  *"blocked on a Meta review cycle"*) ;;
  *) fail "R8: the refusal does not name the park reason: $SS_OUT" ;;
esac
case "$SS_OUT" in
  *unpark*) ;;
  *) fail "R8: the refusal does not say how to proceed (no 'unpark'): $SS_OUT" ;;
esac
[ "$_before" = "$(cat "$T/hd/state/tasks.json")" ] \
  || fail "R8: the board was modified despite the refusal"
# control, SAME harness dir: the identical transition succeeds once unparked
mkboard '' ''
cp "$T/tasks.json" "$T/hd/state/tasks.json"
SS_OUT="$(HARNESS_DIR="$T/hd" python3 "$SRC/tools/tasks-lock.py" set-status E01-F01 in-progress 2>&1)" && SS_RC=0 || SS_RC=$?
[ "$SS_RC" = "0" ] \
  || fail "R8 control: the same transition failed on an UNPARKED feature (rc=$SS_RC), so the refusal above is not attributable to the park: $SS_OUT"
_status_now="$(python3 -c "import json;print(json.load(open('$T/hd/state/tasks.json'))['epics'][0]['features'][0]['status'])")"
[ "$_status_now" = "in-progress" ] || fail "R8 control: the unparked transition did not land (status=$_status_now)"
pass "E06-F07 R8 set_status_refuses_a_parked_feature"

echo "All feature-park tests passed."
