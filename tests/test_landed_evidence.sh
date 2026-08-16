#!/bin/sh
# test_landed_evidence.sh — E99-F102: `done` must carry evidence the work LANDED.
#
# THE CONTROL IS THE POINT (same discipline as test_owner_gate.sh / test_feature_park.sh).
# "the transition was refused" is the easy outcome to produce — a broken helper refuses
# everything — so every refusal here is paired with the SAME transition, on the SAME
# fixture, differing only in the one thing under test, and that pair must SUCCEED. Without
# the pairing the whole suite would pass against a `set-status` that simply exits 1.
#
# What is under test is BEHAVIOUR, not the presence of a field:
#   R1  a single-repo feature cannot reach `done` with no evidence; the board is untouched
#   R2  a sha that is provably NOT an ancestor of the default branch is REFUSED
#   R3  an ancestor sha is accepted and recorded as `ancestor` (with the repo + base)
#   R4  an unresolvable ref is accepted but recorded `unchecked` — never `ancestor`
#   R5  `none:` needs a reason; `none:<why>` records `declared`
#   R6  a SLICED feature needs no flag — its per-slice `merged` flags are the attestation
#   R7  --evidence is refused on a non-`done` transition (the record means one thing)
#   R8  an unrecognised `verified` is a validation error in BOTH validators
#   R9  additive: a board with no `landed` still validates everywhere, incl. the live one
#   R10 with an origin remote, "merged" means the REMOTE default branch (mark-before-push
#       is refused), and the umbrella case (no remote at all) still verifies against local
#   R11 an UMBRELLA board (`.harness/` in one repo) verifies a sha in a CHILD repo
#
# Two of these cases exist because a mutation survived without them: R8's zero-dependency
# assertions (M6 — the schema was answering for the fallback) and R11 (M8 — every other
# case resolved the sha in the harness dir's own parent, so the umbrella layout the viernes
# board actually uses was never exercised). One mutation SURVIVES and is disclosed in
# tools/tasks-lock.py beside `sliced =` (M5, an outcome-equivalent loosening).
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-landed)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v git >/dev/null 2>&1 || fail "git is absent — ancestry cannot be checked"
command -v node >/dev/null 2>&1 || fail "node is absent — next-task.mjs cannot run"
command -v python3 >/dev/null 2>&1 || fail "python3 is absent"

LOCK="$SRC/tools/tasks-lock.py"
VALIDATE="$SRC/tools/validate-board.py"
SCHEMA="$SRC/store/tasks.schema.json"

git_q() { git -c user.email=t@example.com -c user.name=tester "$@" >/dev/null 2>&1; }

# ── Fixture ───────────────────────────────────────────────────────────────────────────
# A REAL git repository (ancestry is the deliverable; a mocked git would test nothing)
# holding a harness dir at <repo>/hd. `main` is set via symbolic-ref on the unborn HEAD so
# the fixture does not depend on the host's init.defaultBranch.
#
#   $BASE  a commit on main            → an ancestor
#   $SIDE  a commit on a side branch   → NOT an ancestor (the E99-F58 shape)
mkrepo() {
  R="$T/repo$1"
  mkdir -p "$R"
  ( cd "$R" && git init -q . && git symbolic-ref HEAD refs/heads/main )
  mkdir -p "$R/hd/state" "$R/hd/store" "$R/hd/tools"
  cp "$SCHEMA" "$R/hd/store/"
  cp "$VALIDATE" "$R/hd/tools/"
  : > "$R/seed.txt"
  ( cd "$R" && git_q add -A && git_q commit -m base )
  BASE="$(cd "$R" && git rev-parse HEAD)"
  ( cd "$R" && git_q checkout -b side && : > "$R/side.txt" && git_q add -A && git_q commit -m side )
  SIDE="$(cd "$R" && git rev-parse HEAD)"
  ( cd "$R" && git_q checkout main )
}

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

mkrepo A
HD="$T/repoA/hd"
BOARD="$HD/state/tasks.json"

# ── R1: no evidence ⇒ no `done`. Two controls, because two things could produce it ─────
mkboard "$HD"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done
[ "$SS_RC" = "0" ] && fail "R1: a single-repo feature reached 'done' with NO evidence — this is the state E99-F58/F59/E09-F02 sat in: $SS_OUT"
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

# CONTROL 2 — the SAME `done`, differing only by the flag: must succeed.
set_status "$HD" E01-F01 done --evidence "$BASE"
[ "$SS_RC" = "0" ] || fail "R1 control-2: 'done' WITH evidence was refused too (rc=$SS_RC), so the guard is refusing 'done' unconditionally: $SS_OUT"
[ "$(field "$BOARD" "d['status']")" = "done" ] || fail "R1 control-2: the attested transition did not land"
pass "E99-F102 R1 done_without_evidence_is_refused"

# ── R2: checkable AND FALSE ⇒ refused. This is the whole feature ───────────────────────
mkboard "$HD"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done --evidence "$SIDE"
[ "$SS_RC" = "0" ] && fail "R2: a commit that is NOT an ancestor of the default branch was accepted as a landing — this is exactly E99-F58 (2 commits, never merged, board says done): $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R2: the board moved despite the refusal (a half-applied write)"
case "$SS_OUT" in
  *"not merged"*|*"NOT an ancestor"*) ;;
  *) fail "R2: the refusal does not say the work is unmerged: $SS_OUT" ;;
esac

# CONTROL — the identical command with an ANCESTOR sha, on the identical board.
set_status "$HD" E01-F01 done --evidence "$BASE"
[ "$SS_RC" = "0" ] || fail "R2 control: an ANCESTOR sha was refused too (rc=$SS_RC) — the check is not discriminating ancestry: $SS_OUT"
pass "E99-F102 R2 a_non_ancestor_commit_is_refused"

# ── R3: what gets RECORDED (the audit's whole payload) ────────────────────────────────
[ "$(field "$BOARD" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R3: an ancestor sha was not recorded as verified=ancestor (got $(field "$BOARD" "d['landed']['verified']"))"
[ "$(field "$BOARD" "d['landed']['ref']")" = "$BASE" ] || fail "R3: the recorded ref is not the sha that was checked"
[ "$(field "$BOARD" "d['landed'].get('base','')")" = "main" ] \
  || fail "R3: the record does not name the base it was checked against (got $(field "$BOARD" "d['landed'].get('base','')"))"
[ "$(field "$BOARD" "d['landed'].get('repo','')")" = "repoA" ] \
  || fail "R3: the record does not name the repository the check ran in"
# The write is a minimal-diff text patch, not a re-serialize: everything else is byte-identical.
python3 - "$BOARD" <<'PY' || fail "R3: recording the evidence reformatted unrelated board bytes"
import json, sys
text = open(sys.argv[1]).read()
assert '"project": "landed-fixture"' in text, text
assert text.count('"landed"') == 1, text
PY
pass "E99-F102 R3 an_ancestor_is_recorded_with_its_repo_and_base"

# ── R4: unresolvable ⇒ accepted, but NEVER as `ancestor` ──────────────────────────────
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "https://github.com/example/repo/pull/42"
[ "$SS_RC" = "0" ] || fail "R4: an unverifiable reference was REFUSED — an offline/foreign-repo landing must not be blocked, or the guard gets routed around: $SS_OUT"
[ "$(field "$BOARD" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R4: an unverifiable reference was recorded as $(field "$BOARD" "d['landed']['verified']") — a claim nobody checked must not read as a proof"
case "$SS_OUT" in
  *warning*) ;;
  *) fail "R4: nothing warned that the reference was not checked: $SS_OUT" ;;
esac
# CONTROL: a well-formed sha that exists NOWHERE is likewise unchecked, not accepted-as-proof
# and not refused (the repo simply has no opinion). deadbeef… is not a commit in any fixture.
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
[ "$SS_RC" = "0" ] || fail "R4 control: an unknown sha was refused — 'we could not check' is not 'it did not merge': $SS_OUT"
[ "$(field "$BOARD" "d['landed']['verified']")" = "unchecked" ] || fail "R4 control: an unknown sha was not recorded unchecked"
pass "E99-F102 R4 an_unresolvable_reference_is_unchecked_never_ancestor"

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

# ── R6: a SLICED feature already carries the attestation (the mechanism this extends) ──
SLICES=',
          "slices": [
            { "id": "E01-F01@web", "repo": "web", "status": "done", "merged": true }
          ]'
mkboard "$HD" "$SLICES"
set_status "$HD" E01-F01 done
[ "$SS_RC" = "0" ] || fail "R6: a fully done+merged SLICED feature was refused for want of --evidence — the per-slice merged flags ARE the attestation, and duplicating it would be the second mechanism this deliberately avoids: $SS_OUT"

# CONTROL: the same sliced feature with an UNMERGED slice must still be refused — otherwise
# "slices need no evidence" would just be a hole.
SLICES_UNMERGED=',
          "slices": [
            { "id": "E01-F01@web", "repo": "web", "status": "done", "merged": false }
          ]'
mkboard "$HD" "$SLICES_UNMERGED"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done
[ "$SS_RC" = "0" ] && fail "R6 control: a sliced feature with an UNMERGED slice reached done — the slice invariant is not holding, so the R6 exemption is a hole: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R6 control: the board moved despite the refusal"
pass "E99-F102 R6 a_sliced_feature_is_attested_by_its_slices"

# ── R7: the record means ONE thing — it is not accepted on other transitions ──────────
mkboard "$HD"
set_status "$HD" E01-F01 in-progress --evidence "$BASE"
[ "$SS_RC" = "0" ] && fail "R7: --evidence was accepted on a non-done transition, so 'landed' would stop meaning 'this is on the default branch': $SS_OUT"
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
# `verified` check from validate-board.py's fallback and leaving the schema alone left this
# suite entirely GREEN (mutation M6), because with jsonschema installed the schema rejected
# the board anyway and every assertion above was satisfied by the OTHER path. So block the
# import, exactly as test_board_lock.sh R10b does, and hold the fallback to the same
# acceptance surface — the whole point of mirroring the rule into it.
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

# CONTROL: the same shape with a legal value passes BOTH — otherwise the assertions above
# would hold against a validator that rejects every `landed` record.
mkbad '{ "ref": "abc1234", "verified": "unchecked" }'
python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R8 control: the shared validator rejected a LEGAL landing record"
python3 "$T/nojs.py" >/dev/null 2>&1 \
  || fail "R8 control: the zero-dependency validator rejected a LEGAL landing record"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || { ( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" ) 2>&1 | head -3 >&2; fail "R8 control: the selector rejected a LEGAL landing record"; }
pass "E99-F102 R8 an_unrecognised_verified_is_rejected_by_both_validators"

# ── R9: additive — boards that predate the field are untouched ────────────────────────
mkbad_none() {
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
}
mkbad_none
python3 "$VALIDATE" "$T/old.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R9: a legacy board with no landing record was REJECTED — the field must never be required by the schema, only by the write path"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/old.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || fail "R9: the selector rejected a legacy board with no landing record"
# ...and this repository's OWN live board, which is entirely un-attested, still validates.
python3 "$VALIDATE" "$SRC/state/tasks.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R9: the live board no longer validates — the change is not additive"
pass "E99-F102 R9 the_field_is_additive_legacy_boards_still_validate"

# ── R10: what "merged" means with, and without, a remote ──────────────────────────────
# WITH a remote, the default branch is the REMOTE's: a commit sitting on local main that
# was never pushed is NOT merged, and is refused. That is the E99-F58 shape verbatim.
mkrepo B
HDB="$T/repoB/hd"
BOARDB="$HDB/state/tasks.json"
( cd "$T" && git init -q --bare remote.git )
( cd "$T/repoB" && git_q remote add origin "$T/remote.git" && git_q push origin main )
UNPUSHED_PARENT="$(cd "$T/repoB" && git rev-parse HEAD)"
( cd "$T/repoB" && : > local-only.txt && git_q add -A && git_q commit -m "local only, never pushed" )
UNPUSHED="$(cd "$T/repoB" && git rev-parse HEAD)"
mkboard "$HDB"
set_status "$HDB" E01-F01 done --evidence "$UNPUSHED"
[ "$SS_RC" = "0" ] && fail "R10: a commit that exists ONLY in the local clone was accepted as merged — with a remote configured, 'merged' has to mean the remote's default branch: $SS_OUT"
# CONTROL: its parent, which IS on origin/main, is accepted — so the refusal is about
# reachability from the remote, not about repoB being unverifiable in general.
set_status "$HDB" E01-F01 done --evidence "$UNPUSHED_PARENT"
[ "$SS_RC" = "0" ] || fail "R10 control: a commit that IS on origin/main was refused (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARDB" "d['landed']['base']")" = "origin/main" ] \
  || fail "R10 control: the check did not use the remote default branch (base=$(field "$BOARDB" "d['landed']['base']"))"
# ...and WITHOUT a remote (an umbrella board's own repo usually has none) the local default
# branch is the base — asserted by R2/R3 above on repoA, which has no origin:
( cd "$T/repoA" && git remote | grep -q . ) && fail "R10: repoA unexpectedly has a remote — R2/R3 were not exercising the remoteless path"
pass "E99-F102 R10 merged_means_the_remote_default_branch_when_there_is_one"

# ── R11: the UMBRELLA layout — the board is in one repo, the work lands in another ────
# Measured, not assumed: deleting the child-repository scan from _repo_candidates left the
# suite entirely GREEN (mutation M8), because every case above resolves the sha in the
# harness dir's own parent. That is not the layout the viernes board actually uses — its
# umbrella root holds `.harness/` while every commit lands in a child repo beside it — so
# without this case the one configuration that matters most was unexercised.
U="$T/umbrella"
mkdir -p "$U/.harness/state" "$U/.harness/store" "$U/child"
cp "$SCHEMA" "$U/.harness/store/"
cp "$VALIDATE" "$U/.harness/tools/validate-board.py" 2>/dev/null || { mkdir -p "$U/.harness/tools"; cp "$VALIDATE" "$U/.harness/tools/"; }
( cd "$U" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$U/README.md"
( cd "$U" && git_q add -A && git_q commit -m "umbrella board only" )
( cd "$U/child" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$U/child/src.txt"
( cd "$U/child" && git_q add -A && git_q commit -m "child work" )
CHILD_MAIN="$(cd "$U/child" && git rev-parse HEAD)"
( cd "$U/child" && git_q checkout -b feature && : > "$U/child/wip.txt" && git_q add -A && git_q commit -m "child WIP, never merged" )
CHILD_ORPHAN="$(cd "$U/child" && git rev-parse HEAD)"
( cd "$U/child" && git_q checkout main )

mkboard "$U/.harness"
set_status "$U/.harness" E01-F01 done --evidence "$CHILD_MAIN"
[ "$SS_RC" = "0" ] || fail "R11: a commit on the CHILD repo's default branch was not verifiable from an umbrella board — this is the viernes layout, so the guard would degrade to 'unchecked' on the board it exists for: $SS_OUT"
[ "$(field "$U/.harness/state/tasks.json" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R11: the child-repo landing was recorded $(field "$U/.harness/state/tasks.json" "d['landed']['verified']"), not ancestor"
[ "$(field "$U/.harness/state/tasks.json" "d['landed']['repo']")" = "child" ] \
  || fail "R11: the record does not name the CHILD repository the check ran in"

# CONTROL: an unmerged commit in the same child repo is REFUSED — otherwise R11 would pass
# against an implementation that reaches child repos but never checks ancestry in them.
mkboard "$U/.harness"
BEFORE="$(cat "$U/.harness/state/tasks.json")"
set_status "$U/.harness" E01-F01 done --evidence "$CHILD_ORPHAN"
[ "$SS_RC" = "0" ] && fail "R11 control: an UNMERGED child-repo commit was accepted from the umbrella board: $SS_OUT"
[ "$BEFORE" = "$(cat "$U/.harness/state/tasks.json")" ] || fail "R11 control: the board moved despite the refusal"
pass "E99-F102 R11 an_umbrella_board_verifies_a_child_repository"

echo "All landing-evidence tests passed."
