#!/bin/sh
# test_landed_evidence.sh — E99-F102: `done` must carry evidence the work LANDED.
#
# THIS IS THE CONTRACT HALF. It covers what `--evidence` PARSES, what it REFUSES, what it
# RECORDS, and that all three acceptance surfaces agree on the record's shape. It does NOT
# cover verification: nothing here runs git, resolves a repository, or checks ancestry,
# because the code under test does none of those things. Every ref lands as `unchecked`.
# Verification — and the cases that exercise it — arrive in the follow-up (E99-F102b).
#
# The numbering is deliberately SPARSE, so the two halves can be read against each other:
#   R1  a feature cannot reach `done` with no evidence; the board is untouched
#   R4  any reference is accepted and recorded `unchecked` — never as a proof
#   R5  `none:` needs a reason; `none:<why>` records `declared`
#   R6  a SLICED feature is NOT exempt, and its evidence is BOUND per slice repository
#   R7  --evidence is refused on a non-`done` transition (the record means one thing)
#   R8  an unrecognised `verified` (and a bad `repo`/`base`/`slices` shape) is an error in
#       ALL THREE validators, on the jsonschema AND the zero-dependency path
#   R9  additive: a board with no `landed` still validates everywhere — asserted on BOTH
#       validator paths, incl. this repo's own live board
#   R12 REGRESSION, E09-F02 verbatim: a sliced feature, every slice hand-marked
#       `merged: true`, whose first slice's own `pr` is a CLOSED UNMERGED PR
#   R14 the BINDING contract: bare ref on a sliced feature, unknown repo, duplicate
#       binding, missing coverage, per-slice `none:`, and the unsliced path unchanged
#   R18 THE SEAM ITSELF: this half performs no I/O and can produce no proof
#   R19 the documented ORDER agrees with the mechanism: `done` is written after the work
#       LANDS, never on the approve verdict (prose contract, section-scoped)
# Absent on purpose (they belong to the verification half): R2, R3, R10, R11, R13, R15,
# R16, R17 and the "checked in THAT repository" half of R14.
#
# THE CONTROL IS THE POINT (same discipline as test_owner_gate.sh / test_feature_park.sh).
# "the transition was refused" is the easy outcome to produce — a broken helper refuses
# everything — so every refusal here is paired with the SAME transition, on the SAME
# fixture, differing only in the one thing under test, and that pair must SUCCEED. Without
# the pairing the whole suite would pass against a `set-status` that simply exits 1.
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-landed)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v node >/dev/null 2>&1 || fail "node is absent — next-task.mjs cannot run"
command -v python3 >/dev/null 2>&1 || fail "python3 is absent"
# NOTE: no `git` precondition. This half never invokes it, and R18 proves that by running
# the whole transition with every child-process entry point booby-trapped.

LOCK="$SRC/tools/tasks-lock.py"
VALIDATE="$SRC/tools/validate-board.py"
SCHEMA="$SRC/store/tasks.schema.json"

# ── Fixture ───────────────────────────────────────────────────────────────────────────
# Just a harness dir. The contract half reads the board text it is handed and nothing
# else, so there is no repository to build — which is itself part of what is under test.
HD="$T/hd"
mkdir -p "$HD/state" "$HD/store" "$HD/tools"
cp "$SCHEMA" "$HD/store/"
cp "$VALIDATE" "$HD/tools/"
BOARD="$HD/state/tasks.json"

# mkboard <harness-dir> [slices-json]
mkboard() {
  _hd="$1"; _slices="${2:-}"
  cat > "$_hd/state/tasks.json" <<EOF
{
  "project": "landed-fixture",
  "epics": [
    {
      "id": "E01", "title": "fixture epic", "status": "in-progress",
      "features": [
        {
          "id": "E01-F01",
          "title": "subject",
          "status": "in-review",
          "sdd": true,
          "spec_path": "specs/e01f01/"$_slices
        }
      ]
    }
  ]
}
EOF
}

# set_status <harness-dir> <id> <status> [flags...] -> SS_OUT / SS_RC
set_status() {
  _hd="$1"; shift
  SS_OUT="$(HARNESS_DIR="$_hd" python3 "$LOCK" set-status "$@" 2>&1)" && SS_RC=0 || SS_RC=$?
}
field() { python3 -c "import json,sys;d=json.load(open('$1'))['epics'][0]['features'][0];print($2)"; }

# A reference that LOOKS like a commit id. This half must treat it exactly like any other
# string — it does not classify refs, because "is this a commit id?" is a question only the
# code that resolves objects can answer (and the 40-hex assumption that question invites
# misses SHA-256's 64-char ids entirely).
SHAISH="4f3c2b1a9e8d7c6b5a4938271605f4e3d2c1b0a9"

# ── R1: no evidence ⇒ no `done`. Two controls, because two things could produce it ─────
mkboard "$HD"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done
[ "$SS_RC" = "0" ] && fail "R1: a feature reached 'done' with NO evidence — this is the state E99-F58/E99-F59/E09-F02/E99-F29 sat in: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R1: the board was modified despite the refusal"
case "$SS_OUT" in
  *evidence*) ;;
  *) fail "R1: the refusal does not say what is missing: $SS_OUT" ;;
esac

# CONTROL 1 — the same helper, same board, a NON-done transition: must succeed. Rules out
# "set-status is simply broken here", which would satisfy the assertion above.
set_status "$HD" E01-F01 in-progress
[ "$SS_RC" = "0" ] || fail "R1 control-1: an ordinary transition ALSO failed (rc=$SS_RC), so the refusal above is not attributable to \`done\`: $SS_OUT"
[ "$(field "$BOARD" "d['status']")" = "in-progress" ] || fail "R1 control-1: the ordinary transition did not land"

# CONTROL 2 — the SAME `done`, differing ONLY by the flag: must succeed. In this half there
# is no ancestry to appeal to, so the control is simply "a reference was supplied": the one
# difference between the refusal above and the success here is the presence of --evidence.
set_status "$HD" E01-F01 done --evidence "$SHAISH"
[ "$SS_RC" = "0" ] || fail "R1 control-2: 'done' WITH evidence was refused too (rc=$SS_RC), so the guard is refusing 'done' unconditionally: $SS_OUT"
[ "$(field "$BOARD" "d['status']")" = "done" ] || fail "R1 control-2: the attested transition did not land"
[ "$(field "$BOARD" "d['landed']['ref']")" = "$SHAISH" ] || fail "R1 control-2: the reference was not recorded verbatim"
pass "E99-F102 R1 done_without_evidence_is_refused"

# ── R4: what gets RECORDED — a claim, explicitly not a proof ──────────────────────────
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "https://github.com/example/repo/pull/42"
[ "$SS_RC" = "0" ] || fail "R4: a reference was REFUSED — this half verifies nothing, so it has no grounds to refuse one: $SS_OUT"
[ "$(field "$BOARD" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R4: a reference nobody checked was recorded as $(field "$BOARD" "d['landed']['verified']") — that must not read as a proof"
case "$SS_OUT" in
  *warning*) ;;
  *) fail "R4: nothing warned that the reference was not checked: $SS_OUT" ;;
esac
# ...and a commit-shaped string is treated identically. This half does not classify refs.
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "$SHAISH"
[ "$(field "$BOARD" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R4: a commit-shaped ref was recorded $(field "$BOARD" "d['landed']['verified']") — nothing here can prove a landing, so nothing here may claim one"
[ "$(field "$BOARD" "'repo' in d['landed'] or 'base' in d['landed']")" = "False" ] \
  || fail "R4: the record names a repo/base although no repository was ever consulted"
# The write is a minimal-diff text patch, not a re-serialize: everything else is byte-identical.
python3 - "$BOARD" <<'PY' || fail "R4: recording the evidence reformatted unrelated board bytes"
import json, sys
text = open(sys.argv[1]).read()
assert '"project": "landed-fixture"' in text, text
assert text.count('"landed"') == 1, text
PY
# CONTROL: a URL carrying a QUERY STRING is still ONE ref, never a `<repo>=<ref>` binding.
# `?utm=1` contains `=`, and reading it as a binding would either bounce a legitimate URL or
# record the landing against a repository the feature does not have. The bound form is
# recognised only when everything before the FIRST `=` is a bare repository name.
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "https://github.com/example/repo/pull/42?utm=1"
[ "$SS_RC" = "0" ] || fail "R4 control: a URL with a query string was refused — it was parsed as a malformed repo binding: $SS_OUT"
[ "$(field "$BOARD" "d['landed']['ref']")" = "https://github.com/example/repo/pull/42?utm=1" ] \
  || fail "R4 control: the recorded ref is not the URL that was passed (it was split on the '=')"
[ "$(field "$BOARD" "'repo' in d['landed']")" = "False" ] \
  || fail "R4 control: a query-string URL was recorded against a repository"
pass "E99-F102 R4 a_reference_is_recorded_unchecked_never_as_a_proof"

# ── R5: the explicit no-commit declaration needs a reason ─────────────────────────────
mkboard "$HD"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done --evidence "none:"
[ "$SS_RC" = "0" ] && fail "R5: 'none:' with no reason was accepted — that is the bare say-so this feature replaces: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R5: the board moved despite the refusal"
set_status "$HD" E01-F01 done --evidence "none: AWS console teardown, no commit exists"
[ "$SS_RC" = "0" ] || fail "R5 control: a REASONED no-commit declaration was refused (rc=$SS_RC) — ops work would have no legal path and the guard would be routed around: $SS_OUT"
[ "$(field "$BOARD" "d['landed']['verified']")" = "declared" ] || fail "R5 control: a none:<why> was not recorded as declared"
pass "E99-F102 R5 a_no_commit_declaration_requires_its_reason"

# ── R6: a SLICED feature is NOT exempt, and its evidence is BOUND per repository ──────
# The first draft of this feature exempted sliced features, on the theory that their
# per-slice `merged` flags already attested the landing. They do not: NOTHING in the
# harness ever WRITES `slice.merged` — every occurrence in tools/ is a read or a type
# assertion — so it is hand-typed, i.e. the say-so `--evidence` replaces. Exempting the
# weaker mechanism from the stronger one shipped a hole documented as safe (see R12).
SLICES=',
          "slices": [
            { "id": "E01-F01@web", "repo": "web", "status": "done", "merged": true }
          ]'
mkboard "$HD" "$SLICES"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done
[ "$SS_RC" = "0" ] && fail "R6: a SLICED feature reached done with no evidence — its slice flags are hand-typed, and E09-F02 proves they can read \`merged: true\` against a closed unmerged PR: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R6: the board moved despite the refusal"

# CONTROL 1: the identical sliced board WITH bound evidence succeeds — so the refusal above
# is about the missing evidence, not about sliced features being unwritable.
set_status "$HD" E01-F01 done --evidence "web=$SHAISH"
[ "$SS_RC" = "0" ] || fail "R6 control-1: a sliced feature WITH bound evidence was refused too (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARD" "d['landed']['slices'][0]['repo']")" = "web" ] \
  || fail "R6 control-1: the record does not bind the landing to the slice repository"
[ "$(field "$BOARD" "d['landed']['slices'][0]['verified']")" = "unchecked" ] \
  || fail "R6 control-1: a bound reference was recorded as something other than unchecked"

# CONTROL 2: the two invariants are INDEPENDENT — evidence does not buy off an unmerged
# slice. Without this, satisfying one could silently satisfy the other.
SLICES_UNMERGED=',
          "slices": [
            { "id": "E01-F01@web", "repo": "web", "status": "done", "merged": false }
          ]'
mkboard "$HD" "$SLICES_UNMERGED"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done --evidence "web=$SHAISH"
[ "$SS_RC" = "0" ] && fail "R6 control-2: an UNMERGED slice was waved through because the feature carried evidence — the slice invariant must hold independently: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R6 control-2: the board moved despite the refusal"
pass "E99-F102 R6 a_sliced_feature_needs_evidence_too"

# ── R7: the record means ONE thing — it is not accepted on other transitions ──────────
mkboard "$HD"
set_status "$HD" E01-F01 in-progress --evidence "$SHAISH"
[ "$SS_RC" = "0" ] && fail "R7: --evidence was accepted on a non-done transition, so 'landed' would stop meaning 'this is the reference for the work that shipped': $SS_OUT"
set_status "$HD" E01-F01 in-progress
[ "$SS_RC" = "0" ] || fail "R7 control: the same transition WITHOUT the flag failed (rc=$SS_RC): $SS_OUT"
pass "E99-F102 R7 evidence_applies_only_to_done"

# ── R8: an unrecognised `verified` is an error in BOTH validators ─────────────────────
# (the shared zero-dep validator init.sh runs, and the selector's own — a board reaching
# next-task.mjs through --tasks never passes the shared one.)
mkbad() {
  cat > "$T/bad.json" <<EOF
{
  "project": "landed-fixture",
  "epics": [
    { "id": "E01", "title": "e", "status": "in-progress",
      "features": [
        { "id": "E01-F01", "title": "f", "status": "done", "sdd": true, "spec_path": "s/",
          "landed": $1 }
      ] }
  ]
}
EOF
}
cat > "$T/config.yaml" <<'EOF'
store:
  backend: local
workflow:
  require_approval: true
umbrella:
  manifest: ""
EOF
mkbad '{ "ref": "abc1234", "verified": "probably" }'
python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
  && fail "R8: the shared validator ACCEPTED verified='probably' — an unrecognised value reads as a check that nothing performs"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  && fail "R8: the SELECTOR accepted verified='probably' — a board arriving through --tasks never passes the shared validator"
mkbad '{ "verified": "ancestor" }'
python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
  && fail "R8: the shared validator accepted a landing record with NO ref — an attestation nobody can re-check is the defect this fixes"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  && fail "R8: the selector accepted a landing record with no ref"
# ...and specifically on the ZERO-DEPENDENCY path. Measured, not assumed: deleting the
# `verified` check from validate-board.py's fallback and leaving the schema alone leaves this
# suite entirely GREEN, because with jsonschema installed the schema rejects the board anyway
# and every assertion above is satisfied by the OTHER path. So block the import, exactly as
# test_board_lock.sh R10b does, and hold the fallback to the same acceptance surface.
cat > "$T/nojs.py" <<EOF
import runpy, sys, builtins
_real = builtins.__import__
def _imp(name, *a, **k):
    if name == "jsonschema":
        raise ImportError("blocked: simulate the zero-dependency install path")
    return _real(name, *a, **k)
builtins.__import__ = _imp
sys.argv = ["validate-board.py", "$T/bad.json", "$SCHEMA"]
runpy.run_path("$VALIDATE", run_name="__main__")
EOF
mkbad '{ "ref": "abc1234", "verified": "probably" }'
python3 "$T/nojs.py" >/dev/null 2>&1 \
  && fail "R8: the ZERO-DEPENDENCY validator accepted verified='probably' — a machine without jsonschema would take a board the schema rejects"
mkbad '{ "verified": "ancestor" }'
python3 "$T/nojs.py" >/dev/null 2>&1 \
  && fail "R8: the zero-dependency validator accepted a landing record with NO ref"

# `repo` and `base` are typed in the schema, so the fallback and the selector must type them
# too, or "the fallback matches the schema's acceptance surface" is a claim with no test
# behind it.
for _k in repo base; do
  mkbad "{ \"ref\": \"abc1234\", \"verified\": \"ancestor\", \"$_k\": 17 }"
  python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
    && fail "R8: the shared validator accepted a non-string landed.$_k"
  python3 "$T/nojs.py" >/dev/null 2>&1 \
    && fail "R8: the ZERO-DEPENDENCY validator accepted a non-string landed.$_k"
  ( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
    && fail "R8: the selector accepted a non-string landed.$_k"
done

# ...and EMPTY, not just mistyped. A plain-string schema and an `isinstance(..., str)`
# fallback both accept "", while the selector's `assertString` has always rejected it — so a
# board carrying `"repo": ""` would pass init.sh and validate-board.py and then make EVERY
# next-task.mjs run die with `input-error`: legal by two of the three acceptance surfaces and
# unusable by the third.
for _k in repo base; do
  mkbad "{ \"ref\": \"abc1234\", \"verified\": \"ancestor\", \"$_k\": \"\" }"
  python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
    && fail "R8: the shared validator accepted an EMPTY landed.$_k — the selector rejects it, so this board validates and then breaks every selector run"
  python3 "$T/nojs.py" >/dev/null 2>&1 \
    && fail "R8: the ZERO-DEPENDENCY validator accepted an EMPTY landed.$_k"
  ( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
    && fail "R8: the selector accepted an EMPTY landed.$_k"
done

# ...and the PER-SLICE records. tasks-lock WRITES `landed.slices` on every sliced feature, so
# a shape the selector rejects would take down every `next-task.mjs` run after the first
# sliced `done`. The last case is the rollup rule: the feature-level record can never claim
# more than its slices carry — which is how a proof gets re-entered by hand.
for _bad in \
  '{ "ref": "a", "verified": "ancestor", "slices": [] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "web", "verified": "ancestor" } ] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "verified": "probably" } ] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "", "ref": "b", "verified": "ancestor" } ] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "verified": "ancestor", "base": 17 } ] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "verified": "unchecked" } ] }' \
; do
  mkbad "$_bad"
  python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
    && fail "R8: the shared validator accepted an illegal landed.slices record: $_bad"
  python3 "$T/nojs.py" >/dev/null 2>&1 \
    && fail "R8: the ZERO-DEPENDENCY validator accepted an illegal landed.slices record: $_bad"
  ( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
    && fail "R8: the selector accepted an illegal landed.slices record: $_bad"
done

# CONTROL: a LEGAL per-slice record — same shape, rollup honestly weakened to the weakest
# slice — passes all three. Without it the six refusals above would hold against a validator
# that simply rejects every `landed.slices`.
mkbad '{ "ref": "web=b; api=c", "verified": "unchecked", "slices": [ { "repo": "web", "ref": "b", "verified": "ancestor", "base": "main" }, { "repo": "api", "ref": "c", "verified": "unchecked" } ] }'
python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R8 control: the shared validator rejected a LEGAL per-slice landing record"
python3 "$T/nojs.py" >/dev/null 2>&1 \
  || fail "R8 control: the zero-dependency validator rejected a LEGAL per-slice landing record"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || fail "R8 control: the selector rejected a LEGAL per-slice landing record"

# CONTROL: the same shape with a legal value passes ALL THREE — otherwise the assertions
# above would hold against a validator that rejects every `landed` record. Note the schema
# still ACCEPTS `ancestor`: this half never writes it, but a board written by the
# verification follow-up, or by hand, must keep validating here.
mkbad '{ "ref": "abc1234", "verified": "unchecked" }'
python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R8 control: the shared validator rejected a LEGAL landing record"
python3 "$T/nojs.py" >/dev/null 2>&1 \
  || fail "R8 control: the zero-dependency validator rejected a LEGAL landing record"
mkbad '{ "ref": "abc1234", "verified": "ancestor", "repo": "viernes-web", "base": "origin/main" }'
python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R8 control: the shared validator rejected a legal repo/base pair"
python3 "$T/nojs.py" >/dev/null 2>&1 \
  || fail "R8 control: the zero-dependency validator rejected a legal repo/base pair"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || fail "R8 control: the selector rejected a legal repo/base pair"
pass "E99-F102 R8 an_unrecognised_verified_is_rejected_by_both_validators"

# ── R9: additive — boards that predate the field are untouched ────────────────────────
cat > "$T/old.json" <<'EOF'
{
  "project": "legacy",
  "epics": [
    { "id": "E01", "title": "e", "status": "done",
      "features": [
        { "id": "E01-F01", "title": "f", "status": "done", "sdd": true, "spec_path": "s/" }
      ] }
  ]
}
EOF
python3 "$VALIDATE" "$T/old.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R9: a legacy board with no landing record was REJECTED — the field must never be required by the schema, only by the write path"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/old.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || fail "R9: the selector rejected a legacy board with no landing record"
# ...and this repository's OWN live board, which is entirely un-attested, still validates.
python3 "$VALIDATE" "$SRC/state/tasks.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R9: the live board no longer validates — the change is not additive"

# ...on the ZERO-DEPENDENCY path too. Same two-path hazard R8 hit: making `_fallback_errors`
# REQUIRE `landed` on every `done` leaves this suite green if additivity is only ever
# asserted through jsonschema — so on a machine without it, a fallback that rejected
# un-attested boards would take down every already-`done` row and nothing would notice.
cat > "$T/nojs_arg.py" <<EOF
import runpy, sys, builtins
_real = builtins.__import__
def _imp(name, *a, **k):
    if name == "jsonschema":
        raise ImportError("blocked: simulate the zero-dependency install path")
    return _real(name, *a, **k)
builtins.__import__ = _imp
sys.argv = ["validate-board.py", sys.argv[1], "$SCHEMA"]
runpy.run_path("$VALIDATE", run_name="__main__")
EOF
python3 "$T/nojs_arg.py" "$T/old.json" >/dev/null 2>&1 \
  || fail "R9: the ZERO-DEPENDENCY validator rejected a legacy board with no landing record — on a machine without jsonschema this would reject every board written before the field existed"
python3 "$T/nojs_arg.py" "$SRC/state/tasks.json" >/dev/null 2>&1 \
  || fail "R9: the ZERO-DEPENDENCY validator rejected this repo's own live board"
# CONTROL: the import-blocked probe is not vacuously green — it still rejects a board the
# fallback is supposed to reject.
mkbad '{ "ref": "abc1234", "verified": "probably" }'
python3 "$T/nojs_arg.py" "$T/bad.json" >/dev/null 2>&1 \
  && fail "R9 control: the import-blocked probe accepted a KNOWN-BAD board, so its two green assertions above prove nothing"
pass "E99-F102 R9 the_field_is_additive_legacy_boards_still_validate"

# ── R12: REGRESSION — E09-F02, the instance the first draft waved through ─────────────
# Not a synthetic shape: this is the live viernes board entry, verbatim except the status,
# which is rewound so the transition can be replayed. Three slices, every one hand-marked
# `merged: true`, and the FIRST slice's own `pr` field points at a PR that was CLOSED
# UNMERGED on 2026-07-25. Through the exempting first draft this exited 0 and wrote no
# record at all. The datum that exposed it — the slice `pr` — is the one the exemption
# treated as sufficient.
cat > "$BOARD" <<'EOF'
{
  "project": "e09f02-regression",
  "epics": [
    {
      "id": "E09", "title": "Platform consolidation", "status": "in-progress",
      "features": [
        {
          "id": "E09-F02",
          "title": "Reconcile lia-infra into one shared viernes-infra",
          "status": "in-review",
          "sdd": true,
          "autonomous": true,
          "depends_on": [],
          "spec_path": "specs/epics/E09-platform-consolidation/F02-infra-reconciliation/",
          "slices": [
            { "id": "E09-F02@viernes-infra", "repo": "viernes-infra", "status": "done",
              "merged": true, "depends_on": [],
              "pr": "https://github.com/viernes-ai/viernes-infra/pull/24" },
            { "id": "E09-F02@viernes-bookings-api", "repo": "viernes-bookings-api",
              "status": "done", "merged": true, "depends_on": ["E09-F02@viernes-infra"] },
            { "id": "E09-F02@viernes-users", "repo": "viernes-users", "status": "done",
              "merged": true, "depends_on": ["E09-F02@viernes-infra"] }
          ]
        }
      ]
    }
  ]
}
EOF
BEFORE="$(cat "$BOARD")"
set_status "$HD" E09-F02 done
[ "$SS_RC" = "0" ] && fail "R12: E09-F02 reached done unattested — the exact board entry, and the exact hole, this feature was rejected for in review: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R12: the board moved despite the refusal"

# ...and ONE unbound declaration cannot answer for THREE repositories. E09-F02's three
# slices landed (or did not) independently — that is the whole reason its first slice's PR
# could be closed unmerged while the others were fine — so a single value that names no
# repository attests none of them.
set_status "$HD" E09-F02 done --evidence "none: superseded by E11; PR #24 closed unmerged"
[ "$SS_RC" = "0" ] && fail "R12: a single unbound --evidence attested a THREE-repository feature: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R12: the board moved despite the refusal"

# CONTROL: the same entry with one declaration PER SLICE REPOSITORY lands, and the record
# says what was claimed — so R12 is not passing merely because a three-slice board is
# unwritable.
set_status "$HD" E09-F02 done \
  --evidence "viernes-infra=none: superseded by E11; PR #24 closed unmerged" \
  --evidence "viernes-bookings-api=none: superseded by E11" \
  --evidence "viernes-users=none: superseded by E11"
[ "$SS_RC" = "0" ] || fail "R12 control: E09-F02 could not be attested at all (rc=$SS_RC): $SS_OUT"
_v="$(python3 -c "import json;print(json.load(open('$BOARD'))['epics'][0]['features'][0]['landed']['verified'])")"
[ "$_v" = "declared" ] || fail "R12 control: the attestation recorded '$_v', not the honest 'declared'"
pass "E99-F102 R12 regression_e09f02_a_sliced_feature_over_a_closed_pr"

# ── R14: the BINDING contract for a sliced feature ────────────────────────────────────
# A single feature-level value names no repository, so it attests no particular slice: one
# slice's merge commit would carry the whole feature to `done` while another slice sat
# unmerged. The binding is what makes a per-repository verdict expressible at all; here it
# is enforced as a shape, and the record keeps the repositories apart so the follow-up's
# verdict has somewhere to land.
TWO=',
          "slices": [
            { "id": "E01-F01@alpha", "repo": "alpha", "status": "done", "merged": true },
            { "id": "E01-F01@beta", "repo": "beta", "status": "done", "merged": true }
          ]'
REF_A="1111111111111111111111111111111111111111"
REF_B="2222222222222222222222222222222222222222"

# (a) the bare form is REFUSED on a sliced feature, and the refusal names the form and the
#     repositories that owe evidence — the operator must not have to guess the shape.
mkboard "$HD" "$TWO"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done --evidence "$REF_A"
[ "$SS_RC" = "0" ] && fail "R14a: one unbound ref carried a TWO-repository feature to done — it names no repository, so it attests neither slice: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R14a: the board moved despite the refusal"
case "$SS_OUT" in
  *"<repo>=<ref>"*) ;;
  *) fail "R14a: the refusal does not name the required form: $SS_OUT" ;;
esac
case "$SS_OUT" in
  *alpha*beta*) ;;
  *) fail "R14a: the refusal does not list the slice repositories: $SS_OUT" ;;
esac

# CONTROL for (a) — the SAME command with one binding per repository must SUCCEED, and the
# record must carry one entry per repository.
set_status "$HD" E01-F01 done --evidence "alpha=$REF_A" --evidence "beta=$REF_B"
[ "$SS_RC" = "0" ] || fail "R14 control: a fully bound sliced transition was refused (rc=$SS_RC) — the guard is refusing sliced features unconditionally: $SS_OUT"
[ "$(field "$BOARD" "d['status']")" = "done" ] || fail "R14 control: the attested sliced transition did not land"
[ "$(field "$BOARD" "len(d['landed']['slices'])")" = "2" ] \
  || fail "R14 control: the record does not carry one entry per slice repository"
[ "$(field "$BOARD" "[s['repo'] for s in d['landed']['slices']]")" = "['alpha', 'beta']" ] \
  || fail "R14 control: the per-slice records do not name their repositories"
[ "$(field "$BOARD" "d['landed']['slices'][1]['ref']")" = "$REF_B" ] \
  || fail "R14 control: beta's record does not carry beta's own ref"
[ "$(field "$BOARD" "[s['verified'] for s in d['landed']['slices']]")" = "['unchecked', 'unchecked']" ] \
  || fail "R14 control: a slice was recorded as something this half cannot prove"
[ "$(field "$BOARD" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R14 control: the feature-level rollup is not the weakest of its slices"
# What tasks-lock WRITES must pass the other two acceptance surfaces, or the first sliced
# `done` breaks every later init.sh / next-task.mjs run.
python3 "$VALIDATE" "$BOARD" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R14 control: the shared validator REJECTS the record tasks-lock just wrote"
( cd "$SRC" && node tools/next-task.mjs --tasks "$BOARD" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || fail "R14 control: the SELECTOR rejects the record tasks-lock just wrote — every /sdd-next after a sliced done would die"

# (d) a MISSING binding is refused, naming the repository still owed — and refused by the
#     coverage check, not by some later crash that happens to mention the same word.
mkboard "$HD" "$TWO"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done --evidence "alpha=$REF_A"
[ "$SS_RC" = "0" ] && fail "R14d: a two-repository feature went done with evidence for ONE repository: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R14d: the board moved despite the refusal"
case "$SS_OUT" in
  *"no landing evidence for beta"*) ;;
  *) fail "R14d: the refusal is not the coverage check naming the repository still owed: $SS_OUT" ;;
esac

# (e) a binding naming a repository the feature has no slice in is refused (a typo must not
#     silently satisfy coverage), and a repeated binding for one repository is refused (the
#     second value would otherwise decide, silently discarding the first).
set_status "$HD" E01-F01 done --evidence "alpha=$REF_A" --evidence "gamma=$REF_B"
[ "$SS_RC" = "0" ] && fail "R14e: evidence bound to a repository the feature has no slice in was accepted: $SS_OUT"
case "$SS_OUT" in
  *"no slice in repository 'gamma'"*) ;;
  *) fail "R14e: the refusal does not name the unknown repository: $SS_OUT" ;;
esac
set_status "$HD" E01-F01 done --evidence "alpha=$REF_A" --evidence "alpha=$REF_B" --evidence "beta=$REF_B"
[ "$SS_RC" = "0" ] && fail "R14e: two --evidence values for the SAME repository were accepted, so one silently won: $SS_OUT"
case "$SS_OUT" in
  *"bind repository 'alpha'"*) ;;
  *) fail "R14e: the refusal does not name the doubly-bound repository: $SS_OUT" ;;
esac

# (f) `none:<why>` stays expressible PER SLICE — ops work with no commit must have a legal
#     path in a sliced feature too, or the guard gets routed around. The rollup weakens.
mkboard "$HD" "$TWO"
set_status "$HD" E01-F01 done --evidence "alpha=none: AWS console action, no commit" --evidence "beta=$REF_B"
[ "$SS_RC" = "0" ] || fail "R14f: a per-slice no-commit declaration was refused (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARD" "d['landed']['slices'][0]['verified']")" = "declared" ] \
  || fail "R14f: a per-slice none:<why> was not recorded as declared"
[ "$(field "$BOARD" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R14f: the rollup reads $(field "$BOARD" "d['landed']['verified']") with one unchecked slice — it must never read stronger than its weakest slice"

# (g) the single-repo path is UNCHANGED, in both directions: an unsliced feature still takes
#     one bare value, and it REFUSES the bound form rather than silently ignoring the repo
#     name (which would record a repository the feature does not have).
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "alpha=$REF_A"
[ "$SS_RC" = "0" ] && fail "R14g: a repo-bound value was accepted on a feature with NO slices: $SS_OUT"
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "$REF_A" --evidence "$REF_B"
[ "$SS_RC" = "0" ] && fail "R14g: two --evidence values were accepted on a feature with NO slices: $SS_OUT"
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "$REF_A"
[ "$SS_RC" = "0" ] || fail "R14g control: the single-repo path stopped working (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARD" "d['landed']['verified']")" = "unchecked" ] || fail "R14g control: the single-repo landing was not recorded"
[ "$(field "$BOARD" "'slices' in d['landed']")" = "False" ] || fail "R14g control: an unsliced feature grew a per-slice record"
pass "E99-F102 R14 sliced_evidence_is_bound_per_slice_repository"

# ── R18: THE SEAM — this half performs no I/O, and can produce no proof ───────────────
# The whole reason to ship the contract before the verification is that a half which never
# issues a verdict cannot issue a WRONG one. That is only true while it stays I/O-free, and
# "I/O-free" is exactly the property that erodes silently when someone adds "just one" git
# call. So it is asserted three ways, and the first is behavioural.
#
# (i) run a complete `done` transition with every child-process entry point booby-trapped.
cat > "$T/nospawn.py" <<EOF
import runpy, subprocess, sys, os

def _boom(*a, **k):
    sys.stderr.write("SPAWNED: %r\n" % (a[0] if a else k,))
    raise SystemExit(97)

subprocess.run = _boom
subprocess.Popen = _boom
subprocess.call = _boom
subprocess.check_output = _boom
os.system = _boom
sys.argv = ["tasks-lock.py", "set-status", "E01-F01", "done", "--evidence", "$SHAISH"]
runpy.run_path("$LOCK", run_name="__main__")
EOF
mkboard "$HD"
HARNESS_DIR="$HD" python3 "$T/nospawn.py" >"$T/nospawn.out" 2>&1 && NS_RC=0 || NS_RC=$?
[ "$NS_RC" = "97" ] && fail "R18: the contract half SPAWNED A CHILD PROCESS during a done transition — it is meant to be pure; verification belongs in the follow-up, before the lock: $(cat "$T/nospawn.out")"
[ "$NS_RC" = "0" ] || fail "R18: the transition failed under the no-spawn probe for some other reason (rc=$NS_RC): $(cat "$T/nospawn.out")"
[ "$(field "$BOARD" "d['status']")" = "done" ] || fail "R18: the transition did not actually land under the probe, so it proves nothing"

# CONTROL — the probe must be ARMED. The same harness, running something that DOES spawn,
# has to trip it; otherwise the assertion above passes against a probe that patches nothing.
cat > "$T/spawner.py" <<EOF
import runpy, subprocess, sys, os

def _boom(*a, **k):
    sys.stderr.write("SPAWNED: %r\n" % (a[0] if a else k,))
    raise SystemExit(97)

subprocess.run = _boom
subprocess.Popen = _boom
subprocess.call = _boom
subprocess.check_output = _boom
os.system = _boom
subprocess.run(["true"])
EOF
python3 "$T/spawner.py" >/dev/null 2>&1 && SP_RC=0 || SP_RC=$?
[ "$SP_RC" = "97" ] || fail "R18 control: the no-spawn probe did not trip on a program that spawns (rc=$SP_RC) — it detects nothing, so the assertion above is vacuous"

# (ii) structurally: the helper carries no ancestry machinery. Whole-line comments are
#      stripped first — the module legitimately DESCRIBES what the follow-up will do, and a
#      raw grep would fail on its own documentation.
_CODE="$T/lock-code.py"
sed -e 's/^[[:space:]]*#.*$//' "$LOCK" > "$_CODE"
for _tok in 'merge-base' 'ls-remote' 'cat-file' 'for-each-ref' '"ancestor"'; do
  grep -qF -- "$_tok" "$_CODE" \
    && fail "R18: tools/tasks-lock.py contains $_tok — verification has leaked into the contract half, which is the boundary this split exists to hold"
done
# CONTROL: the token probe is not vacuously green — a token that IS present must be found,
# or the five assertions above would pass against a broken grep or an empty file.
grep -qF -- '_BINDING_RE' "$_CODE" \
  || fail "R18 control: the stripped-code probe cannot find a token that is definitely present, so its negative results mean nothing"

# (iii) behaviourally: no input this half accepts produces the proved value. Each of the
#       three shapes a ref can take, checked against the one value nothing here may write.
for _ev in "$SHAISH" "https://github.com/example/repo/pull/1" "none: no commit at all"; do
  mkboard "$HD"
  set_status "$HD" E01-F01 done --evidence "$_ev"
  [ "$SS_RC" = "0" ] || fail "R18: a legal reference was refused: $SS_OUT"
  case "$(field "$BOARD" "d['landed']['verified']")" in
    unchecked|declared) ;;
    *) fail "R18: --evidence '$_ev' recorded '$(field "$BOARD" "d['landed']['verified']")' — this half proves nothing, so it may claim nothing" ;;
  esac
done
pass "E99-F102 R18 the_contract_half_performs_no_io_and_claims_no_proof"

# ── R19: the documented ORDER must not defeat the mechanism ───────────────────────────
# The harness used to instruct *approve → set-status done → open the PR*. At `done` time the
# only ref that exists is an unmerged branch tip, so the record was unverifiable by
# construction — and a PR later closed or abandoned left the feature `done` and unselectable
# with work that never shipped, which is the failure this whole feature exists to prevent.
# A mechanism and a process that contradict each other is worse than either alone, so the
# contract is asserted here beside the code it constrains.
#
# These are PROSE assertions, so each one greps the SECTION it names, extracted by heading —
# a whole-file grep is satisfied by any unrelated occurrence elsewhere in the file (including
# one this very change added), and its failure message would then name a guarantee it cannot
# detect. Every extraction is checked non-empty FIRST, because a renamed heading would
# otherwise make every assertion below it pass against an empty string.
ORCH="$SRC/agents/orchestrator.md"
section() {  # section <file> <heading-substring>
  # FENCE-AWARE on purpose. A naive `/^#+ /` heading test also matches a shell COMMENT
  # inside a fenced block — `# a SLICED feature: …` in this very section — and silently
  # TRUNCATES the extraction there. That is worse than extracting nothing: the section is
  # still non-empty, so an emptiness guard passes while every assertion below runs against
  # the first few paragraphs only. Measured while writing this case: the section came back
  # 37 lines long and the `none:<why>` assertion failed against text that was present.
  SECTION_HEADING="$2" awk '
    BEGIN { h = ENVIRON["SECTION_HEADING"] }
    /^```/ { fence = !fence; if (keep) print; next }
    !fence && /^#+ / { keep = (index($0, h) > 0); next }
    keep
  ' "$1"
}

_done_sec="$(section "$ORCH" 'Writing `done`')"
[ -n "$(printf '%s' "$_done_sec" | tr -d '[:space:]')" ] \
  || fail "R19: orchestrator.md has no 'Writing \`done\`' section — the heading was renamed or removed, so every assertion below it would pass vacuously"
# ANTI-TRUNCATION: assert a marker from the END of the section as well as its start. A
# truncated extraction is non-empty, so an emptiness check alone would let every assertion
# below run against a prefix — which is exactly what happened while this case was written.
printf '%s\n' "$_done_sec" | grep -qi 'recorded, not verified' \
  || fail "R19: the 'Writing \`done\`' section extraction does not reach its final paragraph — it was TRUNCATED, so every assertion below it would run against a prefix"
printf '%s\n' "$_done_sec" | grep -qi 'merge' \
  || fail "R19: the 'Writing \`done\`' section never mentions the merge — it is supposed to say that \`done\` waits for it"
printf '%s\n' "$_done_sec" | grep -qiE 'after the (PR )?merge|after the work lands|only once the work is' \
  || fail "R19: the 'Writing \`done\`' section does not say \`done\` is written AFTER the work lands — an approval-time ref is an unmerged branch tip, so the record it produces can never be re-checked"
# Key on a phrase that occurs ONLY in the prose claim. `none:<why>` itself also appears in
# this section's code fence (`--evidence <repo-b>=none:<why>`), so a token grep survives the
# deletion of the sentence that gives it meaning — measured: that mutation SURVIVED.
printf '%s\n' "$_done_sec" | grep -qi 'nothing to merge' \
  || fail "R19: the 'Writing \`done\`' section no longer distinguishes 'nothing to merge' (the legitimate none:<why> case) from 'has not merged yet' — without that line none:<why> becomes the escape hatch that closes unmerged work
# The interim state is named, WITH the consequence measured from the shipped selector: an
# `in-review` feature is re-offered to a Reviewer, so telling an operator to leave it there
# without saying so would hand them a loop.
printf '%s\n' "$_done_sec" | grep -qi 'in-review' \
  || fail "R19: the section does not say what the feature's status is between approval and merge"
# Likewise: 'park' alone is too weak — it survives deleting the paragraph's first line.
# `awaiting merge` and `unpark` occur only in the interim-state paragraph itself.
printf '%s\n' "$_done_sec" | grep -qi 'awaiting merge' \
  || fail "R19: the section does not name the interim state (approved, awaiting merge) — the documented order leaves the feature somewhere, and not saying where is how an operator invents the old shortcut"
printf '%s\n' "$_done_sec" | grep -qi 'unpark' \
  || fail "R19: the section names no hold for the open-PR window — without it the documented order leaves an approved feature being re-offered for review every session, since the selector routes in-review to a Reviewer"

# ...and the two places that ROUTE on the approval must agree with it. This is the assertion
# that would have caught the original defect: the loop said 'Approve → `done`' while the PR
# handoff below it opened the PR afterwards.
_loop_sec="$(section "$ORCH" 'Build↔review rounds')"
[ -n "$(printf '%s' "$_loop_sec" | tr -d '[:space:]')" ] \
  || fail "R19: could not extract the 'Build↔review rounds' section from orchestrator.md"
printf '%s\n' "$_loop_sec" | grep -qi 'approve' \
  || fail "R19: the extracted 'Build↔review rounds' section does not mention an approve verdict — the extraction is wrong, so the assertion below proves nothing"
printf '%s\n' "$_loop_sec" | grep -qE '\*\*Approve\*\* → `done`' \
  && fail "R19: the build↔review loop still promises \`done\` on the approve verdict, while the PR is opened afterwards — so the ref recorded at that moment is an unmerged branch tip, and an abandoned PR leaves the feature done and unselectable"
grep -qE '^ *\| `in-review` \|.*approves → `done`' "$ORCH" \
  && fail "R19: the route table still sends an approve verdict straight to \`done\`"
# CONTROL: the route table row EXISTS and still routes in-review to the Reviewer — otherwise
# the negative assertion above would pass against a file that lost the row entirely.
grep -qE '^ *\| `in-review` \|.*Reviewer' "$ORCH" \
  || fail "R19 control: the route table has no in-review row routing to the Reviewer, so the assertion above proves nothing"

# The same order in the other two contracts, each scoped to its own section.
_wf_sec="$(section "$SRC/docs/WORKFLOW.md" 'needs a landing record')"
[ -n "$(printf '%s' "$_wf_sec" | tr -d '[:space:]')" ] \
  || fail "R19: could not extract the landing-record section from docs/WORKFLOW.md"
printf '%s\n' "$_wf_sec" | grep -qiE 'after the (PR )?merge|after the work lands|observe the merge' \
  || fail "R19: docs/WORKFLOW.md's landing-record section does not state that \`done\` is written after the work lands"
# The state diagram is the part a reader trusts fastest, so it must not still draw the
# approve edge onto `done`.
grep -qF 'in_review --> done: Reviewer approves' "$SRC/docs/WORKFLOW.md" \
  && fail "R19: the state diagram still draws 'in-review --> done: Reviewer approves' — the diagram would contradict the prose beside it"
grep -qE 'in_review --> done' "$SRC/docs/WORKFLOW.md" \
  || fail "R19 control: the state diagram has no in-review → done edge at all, so the assertion above proves nothing"
pass "E99-F102 R19 done_is_documented_as_written_after_the_work_lands"

echo "All landing-evidence tests passed."
