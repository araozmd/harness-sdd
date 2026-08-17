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
#   R6  a SLICED feature is NOT exempt — the slice flags are hand-typed, so it needs BOTH
#       invariants, and its evidence is BOUND per slice repository (`<repo>=<ref>`)
#   R7  --evidence is refused on a non-`done` transition (the record means one thing)
#   R8  an unrecognised `verified` (and a bad `repo`/`base` type) is an error in ALL THREE
#       validators, on the jsonschema AND the zero-dependency path
#   R9  additive: a board with no `landed` still validates everywhere — asserted on BOTH
#       validator paths, incl. this repo's own live board
#   R10 with an origin remote, "merged" means the REMOTE default branch (mark-before-push
#       is refused), and the umbrella case (no remote at all) still verifies against local
#   R11 an UMBRELLA board (`.harness/` in one repo) verifies a sha in a CHILD repo
#   R12 REGRESSION, E09-F02 verbatim: a sliced feature, every slice hand-marked
#       `merged: true`, whose first slice's own `pr` is a CLOSED UNMERGED PR
#   R13 the remote's default branch is DISCOVERED, never guessed by name
#   R14 a SLICED feature's evidence is bound to, and verified IN, each slice's OWN
#       repository — one slice's merge commit can never attest another slice's work
#   R15 a REMOTELESS repository resolves an AUTHORITATIVE local default or none at
#       all; existence of a branch called `main` is not authority
#
# R14 and R15 are review round 3, and both were REPRODUCED against the shipped code before
# they were written: R14 as a two-child umbrella where alpha's merge sha carried the whole
# feature to `done` (`{"verified": "ancestor", "repo": "alpha"}`) while beta's work sat on an
# unmerged branch under a hand-typed `merged: true`; R15 as a remoteless repository whose
# real default is `trunk` and which also has a `main`, where a commit present only on `main`
# was recorded `{"verified": "ancestor", "base": "main"}`. Both are FALSE attestations — the
# one failure mode this feature must never produce, because the record then carries the
# authority of a check that never happened.
#
# Seven of these exist because a mutation survived without them. R6/R12 (review round 1: the
# first draft EXEMPTED sliced features on the theory that `slice.merged` attested the
# landing — E09-F02 replayed through it exited 0 with no record at all). R8's zero-dependency
# and repo/base assertions (M6, and the Reviewer's H2/H3 — the schema was answering for the
# fallback). R9's import-blocked assertions (the Reviewer's H1: a fallback that REQUIRED
# `landed` on every `done` would have taken down all 148 live rows undetected). R11 (M8 —
# every other case resolved the sha in the harness dir's own parent, so the umbrella layout
# the viernes board actually uses went unexercised).
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
#   $SIDE  a commit NOT on main        → NOT an ancestor (the E99-F58 shape)
#
# The repo is left in the REMOTELESS UMBRELLA SHAPE — no remote, exactly ONE local branch —
# because that is the only local configuration whose default branch is authoritative (R15),
# and it is the shape the viernes umbrella root actually has (measured: no remote, one
# branch `main`). So $SIDE is committed on a DETACHED head and kept alive by a ref outside
# refs/heads/: it stays a real, resolvable, unmerged commit without adding a second branch
# that would make "which branch is the default?" undecidable. The name is lower-case
# because a slice `repo` must match `[a-z0-9-]+`, and R6 binds evidence to this repo by name.
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
  ( cd "$R" && git_q checkout --detach main && : > "$R/side.txt" && git_q add -A && git_q commit -m side )
  SIDE="$(cd "$R" && git rev-parse HEAD)"
  ( cd "$R" && git_q update-ref refs/evidence/side "$SIDE" && git_q checkout main )
  # Assert the state INTENDED, including what must still be PRESENT: a fixture that
  # quietly lost the unmerged object, or grew a second branch, would make the refusal
  # assertions below pass for the wrong reason.
  [ "$(cd "$R" && git for-each-ref --format='%(refname:short)' refs/heads/ | wc -l | tr -d ' ')" = "1" ] \
    || fail "mkrepo $1: expected exactly ONE local branch (the remoteless umbrella shape)"
  ( cd "$R" && git cat-file -e "$SIDE^{commit}" ) \
    || fail "mkrepo $1: the unmerged commit \$SIDE is gone — it must stay resolvable"
  ( cd "$R" && git merge-base --is-ancestor "$SIDE" main ) \
    && fail "mkrepo $1: \$SIDE is ON main, so it cannot exercise the refusal"
  ( cd "$R" && git remote | grep -q . ) && fail "mkrepo $1: unexpected remote"
  :
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

mkrepo a
HD="$T/repoa/hd"
BOARD="$HD/state/tasks.json"
# `mkrepo` reassigns $BASE/$SIDE, and R10/R13 build more repositories, so keep repoa's own
# pair under names nothing else writes — R15's control-2 comes back to this repository.
A_BASE="$BASE"
A_SIDE="$SIDE"

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
[ "$(field "$BOARD" "d['landed'].get('repo','')")" = "repoa" ] \
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
# CONTROL: a URL carrying a QUERY STRING is still ONE ref, never a `<repo>=<ref>` binding.
# `?utm=1` contains `=`, and reading it as a binding would either bounce a legitimate URL or
# record the landing against a repository nobody checked. The bound form is recognised only
# when everything before the FIRST `=` is a bare repository name.
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "https://github.com/example/repo/pull/42?utm=1"
[ "$SS_RC" = "0" ] || fail "R4 control: a URL with a query string was refused — it was parsed as a malformed repo binding: $SS_OUT"
[ "$(field "$BOARD" "d['landed']['ref']")" = "https://github.com/example/repo/pull/42?utm=1" ] \
  || fail "R4 control: the recorded ref is not the URL that was passed (it was split on the '=')"
[ "$(field "$BOARD" "'repo' in d['landed']")" = "False" ] \
  || fail "R4 control: a query-string URL was recorded against a repository — nothing checked one"
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

# ── R6: a SLICED feature is NOT exempt ────────────────────────────────────────────────
# The first draft of this feature exempted sliced features, on the theory that their
# per-slice `merged` flags already attested the landing. They do not: NOTHING in the
# harness ever WRITES `slice.merged` — every occurrence in tools/ is a read or a type
# assertion — so it is hand-typed, i.e. the say-so `--evidence` replaces. Exempting the
# weaker mechanism from the stronger one shipped a hole documented as safe (see R12).
#
# Round 3 added the second half: the evidence a sliced feature carries is BOUND to a slice
# repository (`--evidence <repo>=<ref>`) and checked THERE. The slice here names `repoa`,
# which is this fixture's own repository, so the binding resolves and ancestry is real.
SLICES=',
          "slices": [
            { "id": "E01-F01@repoa", "repo": "repoa", "status": "done", "merged": true }
          ]'
mkboard "$HD" "$SLICES"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done
[ "$SS_RC" = "0" ] && fail "R6: a SLICED feature reached done with no evidence — its slice flags are hand-typed, and E09-F02 proves they can read \`merged: true\` against a closed unmerged PR: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R6: the board moved despite the refusal"

# CONTROL 1: the identical sliced board WITH bound evidence succeeds — so the refusal above
# is about the missing evidence, not about sliced features being unwritable.
set_status "$HD" E01-F01 done --evidence "repoa=$BASE"
[ "$SS_RC" = "0" ] || fail "R6 control-1: a sliced feature WITH bound evidence was refused too (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARD" "d['landed']['verified']")" = "ancestor" ] || fail "R6 control-1: the sliced landing was not recorded"
[ "$(field "$BOARD" "d['landed']['slices'][0]['repo']")" = "repoa" ] \
  || fail "R6 control-1: the record does not bind the landing to the slice repository"

# CONTROL 2: the two invariants are INDEPENDENT — evidence does not buy off an unmerged
# slice. Without this, satisfying one could silently satisfy the other.
SLICES_UNMERGED=',
          "slices": [
            { "id": "E01-F01@repoa", "repo": "repoa", "status": "done", "merged": false }
          ]'
mkboard "$HD" "$SLICES_UNMERGED"
BEFORE="$(cat "$BOARD")"
set_status "$HD" E01-F01 done --evidence "repoa=$BASE"
[ "$SS_RC" = "0" ] && fail "R6 control-2: an UNMERGED slice was waved through because the feature carried evidence — the slice invariant must hold independently: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARD")" ] || fail "R6 control-2: the board moved despite the refusal"
pass "E99-F102 R6 a_sliced_feature_needs_evidence_too"

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

# H2/H3 (Reviewer): `repo` and `base` are typed in the schema, so the fallback and the
# selector must type them too, or "the fallback matches the schema's acceptance surface" is
# a claim with no test behind it. Both survived deletion until these three lines existed.
for _k in repo base; do
  mkbad "{ \"ref\": \"abc1234\", \"verified\": \"ancestor\", \"$_k\": 17 }"
  python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
    && fail "R8: the shared validator accepted a non-string landed.$_k"
  python3 "$T/nojs.py" >/dev/null 2>&1 \
    && fail "R8: the ZERO-DEPENDENCY validator accepted a non-string landed.$_k"
  ( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
    && fail "R8: the selector accepted a non-string landed.$_k"
done

# ...and EMPTY, not just mistyped (review round 2). The schema typed `repo`/`base` as plain
# strings and the fallback only checked `isinstance(..., str)`, while the selector's
# `assertString` has always rejected "". So a board carrying `"repo": ""` passed init.sh
# and validate-board.py and then made EVERY next-task.mjs run die with `input-error` — a
# board legal by two of the three acceptance surfaces and unusable by the third. The three
# now agree, on the non-empty side: an empty repo name or base ref names nothing, which is
# the same reason `ref` carries minLength 1.
for _k in repo base; do
  mkbad "{ \"ref\": \"abc1234\", \"verified\": \"ancestor\", \"$_k\": \"\" }"
  python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
    && fail "R8: the shared validator accepted an EMPTY landed.$_k — the selector rejects it, so this board validates and then breaks every selector run"
  python3 "$T/nojs.py" >/dev/null 2>&1 \
    && fail "R8: the ZERO-DEPENDENCY validator accepted an EMPTY landed.$_k"
  ( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
    && fail "R8: the selector accepted an EMPTY landed.$_k"
done

# ...and the PER-SLICE landing records (round 3). tasks-lock now WRITES `landed.slices` on
# every sliced feature, so a shape the selector rejects would take down every `next-task.mjs`
# run after the first sliced `done` — the three surfaces have to agree on this sub-record
# exactly as they do on the outer one. The last case is the rollup rule: the feature-level
# record can never claim more than its slices proved, which is the P1-A false attestation
# re-entered by hand.
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

# CONTROL: the same shape with a legal value passes BOTH — otherwise the assertions above
# would hold against a validator that rejects every `landed` record.
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

# ...on the ZERO-DEPENDENCY path too. Same two-path hazard R8 hit, and it survived a
# mutation until this existed (Reviewer H1: making _fallback_errors REQUIRE `landed` on
# every `done` left this suite green, because additivity was only ever asserted through
# jsonschema — so on a machine without it, a fallback that rejected un-attested boards
# would take down all 148 live rows and nothing here would notice).
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
# fallback is supposed to reject. (Re-seed bad.json: the last R8 case left a LEGAL one there.)
mkbad '{ "ref": "abc1234", "verified": "probably" }'
python3 "$T/nojs_arg.py" "$T/bad.json" >/dev/null 2>&1 \
  && fail "R9 control: the import-blocked probe accepted a KNOWN-BAD board, so its two green assertions above prove nothing"
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
# branch is the base — asserted by R2/R3 above on repoa, which has no origin:
( cd "$T/repoa" && git remote | grep -q . ) && fail "R10: repoa unexpectedly has a remote — R2/R3 were not exercising the remoteless path"
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
# Same shape as mkrepo: the unmerged commit is kept OUT of refs/heads/ so the child stays
# in the remoteless single-branch configuration whose default branch is authoritative (R15).
( cd "$U/child" && git_q checkout --detach main && : > "$U/child/wip.txt" && git_q add -A && git_q commit -m "child WIP, never merged" )
CHILD_ORPHAN="$(cd "$U/child" && git rev-parse HEAD)"
( cd "$U/child" && git_q update-ref refs/evidence/wip "$CHILD_ORPHAN" && git_q checkout main )
[ "$(cd "$U/child" && git for-each-ref --format='%(refname:short)' refs/heads/ | wc -l | tr -d ' ')" = "1" ] \
  || fail "R11 setup: the child repo has more than one branch, so its default is undecidable"
( cd "$U/child" && git cat-file -e "$CHILD_ORPHAN^{commit}" ) \
  || fail "R11 setup: the unmerged child commit is gone — it must stay resolvable"

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

# ── R12: REGRESSION — E09-F02, the instance the first draft waved through ─────────────
# Not a synthetic shape: this is the live viernes board entry, verbatim except the status,
# which is rewound so the transition can be replayed. Three slices, every one hand-marked
# `merged: true`, and the FIRST slice's own `pr` field points at a PR that was CLOSED
# UNMERGED on 2026-07-25. Through the exempting first draft this exited 0 and wrote no
# record at all. The datum that exposed it — the slice `pr` — is the one the exemption
# treated as sufficient.
cat > "$HD/state/tasks.json" <<'EOF'
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
BEFORE="$(cat "$HD/state/tasks.json")"
set_status "$HD" E09-F02 done
[ "$SS_RC" = "0" ] && fail "R12: E09-F02 reached done unattested — the exact board entry, and the exact hole, this feature was rejected for in review round 1: $SS_OUT"
[ "$BEFORE" = "$(cat "$HD/state/tasks.json")" ] || fail "R12: the board moved despite the refusal"

# ...and round 3's half of the same instance: ONE unbound declaration cannot answer for
# THREE repositories. E09-F02's three slices landed (or did not) independently — that is the
# whole reason its first slice's PR could be closed unmerged while the others were fine — so
# a single value that names no repository attests none of them.
set_status "$HD" E09-F02 done --evidence "none: superseded by E11; PR #24 closed unmerged"
[ "$SS_RC" = "0" ] && fail "R12: a single unbound --evidence attested a THREE-repository feature: $SS_OUT"
[ "$BEFORE" = "$(cat "$HD/state/tasks.json")" ] || fail "R12: the board moved despite the refusal"

# CONTROL: the same entry with one declaration PER SLICE REPOSITORY lands, and the record
# says what was proved — so R12 is not passing merely because a three-slice board is
# unwritable.
set_status "$HD" E09-F02 done \
  --evidence "viernes-infra=none: superseded by E11; PR #24 closed unmerged" \
  --evidence "viernes-bookings-api=none: superseded by E11" \
  --evidence "viernes-users=none: superseded by E11"
[ "$SS_RC" = "0" ] || fail "R12 control: E09-F02 could not be attested at all (rc=$SS_RC): $SS_OUT"
_v="$(python3 -c "import json;print(json.load(open('$HD/state/tasks.json'))['epics'][0]['features'][0]['landed']['verified'])")"
[ "$_v" = "declared" ] || fail "R12 control: the attestation recorded '$_v', not the honest 'declared'"
pass "E99-F102 R12 regression_e09f02_a_sliced_feature_over_a_closed_pr"


# ── R13: the remote's default branch is DISCOVERED, never guessed by name ─────────────
# Review round 2. The first draft fell back to a hard-coded `origin/main` whenever
# `refs/remotes/origin/HEAD` was missing. On a remote whose default is `trunk` that
# records a commit which never reached the default branch as `verified: "ancestor"` —
# this feature emitting a FALSE attestation, which is worse than the say-so it replaces,
# because the record now carries the authority of a check that never happened.
mkrepo C
HDC="$T/repoC/hd"
BOARDC="$HDC/state/tasks.json"
( cd "$T" && git init -q --bare trunkremote.git && cd trunkremote.git && git symbolic-ref HEAD refs/heads/trunk )
( cd "$T/repoC" && git_q remote add origin "$T/trunkremote.git" )
# `trunk` IS the default and carries the base commit; `main` exists on the remote too and
# carries a commit that is NOT on trunk — the decoy the name-guess would have selected.
( cd "$T/repoC" && git_q checkout -b trunk && git_q push origin trunk )
TRUNK_TIP="$(cd "$T/repoC" && git rev-parse HEAD)"
( cd "$T/repoC" && git_q checkout main && : > "$T/repoC/main-only.txt" && git_q add -A && git_q commit -m "on main, NOT on trunk" && git_q push origin main )
MAIN_ONLY="$(cd "$T/repoC" && git rev-parse HEAD)"
( cd "$T/repoC" && git_q fetch origin && git_q remote set-head origin --auto )
# Delete the published symref — and note WHICH command does that. `update-ref -d` follows
# the symref and deletes its TARGET, so it removes `origin/trunk` and leaves `origin/HEAD`
# dangling: a different state, which still satisfies a naive "is origin/HEAD gone?" check
# while exercising none of this. Written that way first and it passed vacuously. Hence
# `symbolic-ref -d`, plus an assertion that BOTH remote branches survived.
( cd "$T/repoC" && git symbolic-ref -d refs/remotes/origin/HEAD >/dev/null 2>&1 || true )
if ( cd "$T/repoC" && git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1 ); then
  fail "R13 setup: origin/HEAD is still present, so the discovery path is not being exercised"
fi
( cd "$T/repoC" && git rev-parse --verify --quiet 'origin/trunk^{commit}' >/dev/null ) \
  || fail "R13 setup: origin/trunk was deleted — the symref was dereferenced, so this fixture is the dangling-ref state, not the missing-HEAD state"
( cd "$T/repoC" && git rev-parse --verify --quiet 'origin/main^{commit}' >/dev/null ) \
  || fail "R13 setup: origin/main is absent, so the decoy the name-guess would pick does not exist"

mkboard "$HDC"
BEFORE="$(cat "$BOARDC")"
set_status "$HDC" E01-F01 done --evidence "$MAIN_ONLY"
# The exact false attestation, reproduced against the pre-fix helper before this was
# written: it recorded {"verified": "ancestor", "base": "origin/main"} for this commit.
if [ "$SS_RC" = "0" ]; then
  _v="$(field "$BOARDC" "d['landed']['verified']")"
  [ "$_v" = "ancestor" ] && fail "R13: a commit absent from the remote default branch (trunk) was attested as 'ancestor' — the default was guessed by NAME as $(field "$BOARDC" "d['landed']['base']")"
  fail "R13: the write was accepted as '$_v'; discovery can see trunk, so this commit is provably not merged and must be REFUSED"
fi
[ "$BEFORE" = "$(cat "$BOARDC")" ] || fail "R13: the board moved despite the refusal"

# CONTROL 1: a commit that IS on trunk is accepted, and the record NAMES trunk — so R13 is
# not passing merely because repoC became unverifiable when the symref went away.
mkboard "$HDC"
set_status "$HDC" E01-F01 done --evidence "$TRUNK_TIP"
[ "$SS_RC" = "0" ] || fail "R13 control 1: a commit on the REAL default branch was refused (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARDC" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R13 control 1: the trunk-tip landing recorded $(field "$BOARDC" "d['landed']['verified']"), not ancestor"
[ "$(field "$BOARDC" "d['landed']['base']")" = "origin/trunk" ] \
  || fail "R13 control 1: the check used $(field "$BOARDC" "d['landed']['base']"), not the discovered origin/trunk"

# CONTROL 2: an UNREACHABLE remote degrades to `unchecked` — it never blocks the write.
# This is the property the name-guess was protecting and the reason the fix cannot simply
# refuse whenever origin/HEAD is missing: an offline machine must still be able to record.
( cd "$T/repoC" && git_q remote set-url origin "$T/does-not-exist.git" )
mkboard "$HDC"
set_status "$HDC" E01-F01 done --evidence "$TRUNK_TIP"
[ "$SS_RC" = "0" ] || fail "R13 control 2: an unreachable remote BLOCKED the write (rc=$SS_RC) — undiscoverable must degrade, not block: $SS_OUT"
[ "$(field "$BOARDC" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R13 control 2: expected 'unchecked' with an unreachable remote, got $(field "$BOARDC" "d['landed']['verified']")"
pass "E99-F102 R13 the_remote_default_branch_is_discovered_not_guessed"

# ── R14: a SLICED feature's evidence is bound to, and checked in, EACH slice's repo ────
# Review round 3, REPRODUCED against the shipped code first: an umbrella with two children,
# `alpha` merged and `beta` sitting on a branch that never merged under a hand-typed
# `merged: true`. Passing alpha's sha as the single feature-level --evidence exited 0 and
# wrote {"verified": "ancestor", "repo": "alpha"} onto the FEATURE — the whole feature went
# `done` on one slice's merge commit, which is the unmerged-slice failure this feature
# exists to prevent, now stamped with the authority of a git check performed on somebody
# else's work. Evidence therefore names its repository and is verified THERE.
V="$T/multi"
mkdir -p "$V/.harness/state" "$V/.harness/store" "$V/.harness/tools"
cp "$SCHEMA" "$V/.harness/store/"
cp "$VALIDATE" "$V/.harness/tools/"
( cd "$V" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$V/README.md"; ( cd "$V" && git_q add -A && git_q commit -m "umbrella board only" )
for _r in alpha beta; do
  mkdir -p "$V/$_r"
  ( cd "$V/$_r" && git init -q . && git symbolic-ref HEAD refs/heads/main )
  : > "$V/$_r/src.txt"
  ( cd "$V/$_r" && git_q add -A && git_q commit -m "$_r landed" )
done
ALPHA_MAIN="$(cd "$V/alpha" && git rev-parse main)"
BETA_MAIN="$(cd "$V/beta" && git rev-parse main)"
( cd "$V/beta" && git_q checkout --detach main && : > "$V/beta/wip.txt" && git_q add -A && git_q commit -m "beta WIP, never merged" )
BETA_ORPHAN="$(cd "$V/beta" && git rev-parse HEAD)"
( cd "$V/beta" && git_q update-ref refs/evidence/wip "$BETA_ORPHAN" && git_q checkout main )
# Assert the fixture is the shape the case needs — including what must be PRESENT.
( cd "$V/beta" && git cat-file -e "$BETA_ORPHAN^{commit}" ) || fail "R14 setup: beta's unmerged commit is gone"
( cd "$V/beta" && git merge-base --is-ancestor "$BETA_ORPHAN" main ) && fail "R14 setup: beta's 'unmerged' commit is on main"
( cd "$V/alpha" && git cat-file -e "$BETA_MAIN^{commit}" 2>/dev/null ) && fail "R14 setup: beta's commit is visible in alpha, so the cross-repo case would prove nothing"
[ "$ALPHA_MAIN" = "$BETA_MAIN" ] && fail "R14 setup: the two children share a commit id"
HDV="$V/.harness"
BOARDV="$HDV/state/tasks.json"
TWO=',
          "slices": [
            { "id": "E01-F01@alpha", "repo": "alpha", "status": "done", "merged": true },
            { "id": "E01-F01@beta", "repo": "beta", "status": "done", "merged": true }
          ]'

# (a) the bare form is REFUSED on a sliced feature, and the refusal names the form and the
#     repositories that owe evidence — the operator must not have to guess the new shape.
mkboard "$HDV" "$TWO"
BEFORE="$(cat "$BOARDV")"
set_status "$HDV" E01-F01 done --evidence "$ALPHA_MAIN"
[ "$SS_RC" = "0" ] && fail "R14a: one slice's merge sha carried a TWO-repository feature to done — this is the reproduction: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDV")" ] || fail "R14a: the board moved despite the refusal"
case "$SS_OUT" in
  *"<repo>=<ref>"*) ;;
  *) fail "R14a: the refusal does not name the required form: $SS_OUT" ;;
esac
case "$SS_OUT" in
  *alpha*beta*) ;;
  *) fail "R14a: the refusal does not list the slice repositories: $SS_OUT" ;;
esac

# (b) THE KILL: bound evidence per repo, where beta's ref never merged IN BETA ⇒ REFUSED,
#     naming beta. Pre-fix there was no way to express this at all.
mkboard "$HDV" "$TWO"
BEFORE="$(cat "$BOARDV")"
set_status "$HDV" E01-F01 done --evidence "alpha=$ALPHA_MAIN" --evidence "beta=$BETA_ORPHAN"
[ "$SS_RC" = "0" ] && fail "R14b: a feature went done while its beta slice's commit was provably unmerged in beta: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDV")" ] || fail "R14b: the board moved despite the refusal"
case "$SS_OUT" in
  *beta*) ;;
  *) fail "R14b: the refusal does not name the slice repository that failed: $SS_OUT" ;;
esac

# CONTROL for (a) and (b) — the SAME command, differing only in beta's ref, must SUCCEED,
# and the record must carry one entry per repository with the base each was checked against.
set_status "$HDV" E01-F01 done --evidence "alpha=$ALPHA_MAIN" --evidence "beta=$BETA_MAIN"
[ "$SS_RC" = "0" ] || fail "R14 control: two genuinely landed slices were refused (rc=$SS_RC) — the guard is refusing sliced features unconditionally: $SS_OUT"
[ "$(field "$BOARDV" "d['status']")" = "done" ] || fail "R14 control: the attested sliced transition did not land"
[ "$(field "$BOARDV" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R14 control: two ancestor slices rolled up to $(field "$BOARDV" "d['landed']['verified']"), not ancestor"
[ "$(field "$BOARDV" "len(d['landed']['slices'])")" = "2" ] \
  || fail "R14 control: the record does not carry one entry per slice repository"
[ "$(field "$BOARDV" "[s['repo'] for s in d['landed']['slices']]")" = "['alpha', 'beta']" ] \
  || fail "R14 control: the per-slice records do not name their repositories"
[ "$(field "$BOARDV" "d['landed']['slices'][1]['ref']")" = "$BETA_MAIN" ] \
  || fail "R14 control: beta's record does not carry beta's own ref"
[ "$(field "$BOARDV" "[s['verified'] for s in d['landed']['slices']]")" = "['ancestor', 'ancestor']" ] \
  || fail "R14 control: a genuinely landed slice was not recorded as ancestor"
[ "$(field "$BOARDV" "d['landed']['slices'][0]['base']")" = "main" ] \
  || fail "R14 control: the per-slice record does not name the base it was checked against"
# What tasks-lock WRITES must pass the other two acceptance surfaces, or the first sliced
# `done` breaks every later init.sh / next-task.mjs run.
python3 "$VALIDATE" "$BOARDV" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R14 control: the shared validator REJECTS the record tasks-lock just wrote"
( cd "$SRC" && node tools/next-task.mjs --tasks "$BOARDV" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || fail "R14 control: the SELECTOR rejects the record tasks-lock just wrote — every /sdd-next after a sliced done would die"

# (c) each ref is checked in the repository its binding NAMES, not in whatever repository
#     happens to know the object. Give alpha a sha that exists ONLY in beta: it must come
#     back `unchecked` (alpha has never seen it), and the feature-level rollup must fall to
#     the weakest slice. Pre-fix that same sha, passed unbound, resolved in beta and was
#     recorded `ancestor` for the whole feature.
mkboard "$HDV" "$TWO"
set_status "$HDV" E01-F01 done --evidence "alpha=$BETA_MAIN" --evidence "beta=$BETA_MAIN"
[ "$SS_RC" = "0" ] || fail "R14c: an unresolvable-in-alpha ref BLOCKED the write — 'we could not check' is not 'it did not merge': $SS_OUT"
[ "$(field "$BOARDV" "d['landed']['slices'][0]['verified']")" = "unchecked" ] \
  || fail "R14c: a commit that exists only in BETA was recorded $(field "$BOARDV" "d['landed']['slices'][0]['verified']") for the ALPHA slice — evidence is being verified in whatever repo resolves it"
[ "$(field "$BOARDV" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R14c: the feature-level record reads $(field "$BOARDV" "d['landed']['verified']") while a slice was unproved — the rollup must never claim more than the weakest slice"

# (d) a MISSING binding is refused, naming the repository still owed. Control: adding it
#     (the R14 control above) succeeds, so this is about coverage, not about the flag.
mkboard "$HDV" "$TWO"
BEFORE="$(cat "$BOARDV")"
set_status "$HDV" E01-F01 done --evidence "alpha=$ALPHA_MAIN"
[ "$SS_RC" = "0" ] && fail "R14d: a two-repository feature went done with evidence for ONE repository: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDV")" ] || fail "R14d: the board moved despite the refusal"
case "$SS_OUT" in
  *beta*) ;;
  *) fail "R14d: the refusal does not name the repository whose evidence is missing: $SS_OUT" ;;
esac

# (e) a binding naming a repository the feature has no slice in is refused (a typo must not
#     silently satisfy coverage), and a repeated binding for one repository is refused (the
#     second value would otherwise decide, silently discarding the first).
set_status "$HDV" E01-F01 done --evidence "alpha=$ALPHA_MAIN" --evidence "gamma=$BETA_MAIN"
[ "$SS_RC" = "0" ] && fail "R14e: evidence bound to a repository the feature has no slice in was accepted: $SS_OUT"
case "$SS_OUT" in
  *gamma*) ;;
  *) fail "R14e: the refusal does not name the unknown repository: $SS_OUT" ;;
esac
set_status "$HDV" E01-F01 done --evidence "alpha=$ALPHA_MAIN" --evidence "alpha=$BETA_MAIN" --evidence "beta=$BETA_MAIN"
[ "$SS_RC" = "0" ] && fail "R14e: two --evidence values for the SAME repository were accepted, so one silently won: $SS_OUT"

# (f) `none:<why>` stays expressible PER SLICE — ops work with no commit must have a legal
#     path in a sliced feature too, or the guard gets routed around. The rollup weakens.
mkboard "$HDV" "$TWO"
set_status "$HDV" E01-F01 done --evidence "alpha=none: AWS console action, no commit" --evidence "beta=$BETA_MAIN"
[ "$SS_RC" = "0" ] || fail "R14f: a per-slice no-commit declaration was refused (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARDV" "d['landed']['slices'][0]['verified']")" = "declared" ] \
  || fail "R14f: a per-slice none:<why> was not recorded as declared"
[ "$(field "$BOARDV" "d['landed']['verified']")" = "declared" ] \
  || fail "R14f: the rollup reads $(field "$BOARDV" "d['landed']['verified']") with one declared slice — it must never read stronger than its weakest slice"

# (g) the single-repo path is UNCHANGED, in both directions: an unsliced feature still takes
#     one bare value, and it REFUSES the bound form rather than silently ignoring the repo
#     name (which would attest against a repository nobody checked).
mkboard "$HDV"
set_status "$HDV" E01-F01 done --evidence "alpha=$ALPHA_MAIN"
[ "$SS_RC" = "0" ] && fail "R14g: a repo-bound value was accepted on a feature with NO slices: $SS_OUT"
mkboard "$HDV"
set_status "$HDV" E01-F01 done --evidence "$ALPHA_MAIN" --evidence "$BETA_MAIN"
[ "$SS_RC" = "0" ] && fail "R14g: two --evidence values were accepted on a feature with NO slices: $SS_OUT"
mkboard "$HDV"
set_status "$HDV" E01-F01 done --evidence "$ALPHA_MAIN"
[ "$SS_RC" = "0" ] || fail "R14g control: the single-repo path stopped working (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARDV" "d['landed']['verified']")" = "ancestor" ] || fail "R14g control: the single-repo landing was not recorded as ancestor"
[ "$(field "$BOARDV" "'slices' in d['landed']")" = "False" ] || fail "R14g control: an unsliced feature grew a per-slice record"
pass "E99-F102 R14 sliced_evidence_is_bound_and_verified_per_slice_repository"

# ── R15: a REMOTELESS repo resolves an AUTHORITATIVE default, or none at all ───────────
# Review round 3, REPRODUCED against the shipped code first: with no `origin`, the helper
# took the first of ("main", "master") that EXISTED. In a remoteless repository whose real
# default is `trunk` and which ALSO has a `main`, it selected `main` merely because it was
# there, and a commit present only on `main` — never on trunk — was recorded
# {"verified": "ancestor", "base": "main"}. Existence is not authority. Note what CANNOT be
# used instead: this repo's own HEAD is on `trunk` here, so HEAD would answer correctly in
# this fixture and disastrously in the common one — standing on the feature branch you just
# finished would make that branch "the default" and attest your unmerged commit as landed.
mkdir -p "$T/trunkless/hd/state" "$T/trunkless/hd/store" "$T/trunkless/hd/tools"
cp "$SCHEMA" "$T/trunkless/hd/store/"; cp "$VALIDATE" "$T/trunkless/hd/tools/"
( cd "$T/trunkless" && git init -q . && git symbolic-ref HEAD refs/heads/trunk )
: > "$T/trunkless/seed.txt"; ( cd "$T/trunkless" && git_q add -A && git_q commit -m "trunk base" )
TL_TRUNK="$(cd "$T/trunkless" && git rev-parse trunk)"
( cd "$T/trunkless" && git_q checkout -b main && : > "$T/trunkless/main-only.txt" && git_q add -A && git_q commit -m "on main, NOT on trunk" && git_q checkout trunk )
TL_MAIN_ONLY="$(cd "$T/trunkless" && git rev-parse main)"
( cd "$T/trunkless" && git remote | grep -q . ) && fail "R15 setup: the fixture has a remote, so it is not exercising the remoteless path"
( cd "$T/trunkless" && git merge-base --is-ancestor "$TL_MAIN_ONLY" trunk ) \
  && fail "R15 setup: the main-only commit IS on trunk, so the decoy proves nothing"
( cd "$T/trunkless" && git rev-parse --verify --quiet 'main^{commit}' >/dev/null ) \
  || fail "R15 setup: there is no 'main' branch, so the name-guess would have had nothing to pick"
HDT="$T/trunkless/hd"
BOARDT="$HDT/state/tasks.json"

mkboard "$HDT"
set_status "$HDT" E01-F01 done --evidence "$TL_MAIN_ONLY"
[ "$SS_RC" = "0" ] || fail "R15: an undecidable default BLOCKED the write (rc=$SS_RC) — unchecked must degrade, never block: $SS_OUT"
_v="$(field "$BOARDT" "d['landed']['verified']")"
[ "$_v" = "ancestor" ] && fail "R15: a commit absent from the real default branch (trunk) was attested as 'ancestor' with base $(field "$BOARDT" "d['landed'].get('base','')") — the default was guessed by NAME"
[ "$_v" = "unchecked" ] || fail "R15: expected 'unchecked' where no default branch is authoritative, got '$_v'"
[ "$(field "$BOARDT" "'base' in d['landed']")" = "False" ] \
  || fail "R15: the record names a base although nothing was checked against one"
case "$SS_OUT" in
  *harness.defaultBranch*) ;;
  *) fail "R15: the warning does not tell the operator how to declare the default branch: $SS_OUT" ;;
esac
# ...and it is not that `trunk` was silently preferred instead: with two branches and no
# declaration NOTHING is decidable here, so the trunk tip is equally unchecked.
mkboard "$HDT"
set_status "$HDT" E01-F01 done --evidence "$TL_TRUNK"
[ "$(field "$BOARDT" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R15: the trunk tip was attested although no default branch is decidable — a second name is still a name"

# CONTROL 1 — the SAME repository, the SAME commits, differing only by an EXPLICIT
# declaration of the default branch: the check becomes real again in BOTH directions. This
# is what rules out "repo is simply unverifiable" as the explanation for the two results
# above, and it is the escape hatch the warning names.
( cd "$T/trunkless" && git_q config harness.defaultBranch trunk )
mkboard "$HDT"
BEFORE="$(cat "$BOARDT")"
set_status "$HDT" E01-F01 done --evidence "$TL_MAIN_ONLY"
[ "$SS_RC" = "0" ] && fail "R15 control-1: with the default branch DECLARED as trunk, a commit that never reached trunk was still accepted: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDT")" ] || fail "R15 control-1: the board moved despite the refusal"
mkboard "$HDT"
set_status "$HDT" E01-F01 done --evidence "$TL_TRUNK"
[ "$SS_RC" = "0" ] || fail "R15 control-1: a commit ON the declared default branch was refused (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARDT" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R15 control-1: a commit on the declared default recorded $(field "$BOARDT" "d['landed']['verified']"), not ancestor"
[ "$(field "$BOARDT" "d['landed']['base']")" = "trunk" ] \
  || fail "R15 control-1: the record names $(field "$BOARDT" "d['landed']['base']"), not the DECLARED trunk"

# CONTROL 2 — the shape the viernes umbrella root actually has (measured: no remote, exactly
# ONE local branch): there the default is authoritative by exhaustion, so the guard keeps its
# teeth with no declaration at all. Both directions, in the same repository.
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "$A_SIDE"
[ "$SS_RC" = "0" ] && fail "R15 control-2: an unmerged commit was accepted in a remoteless single-branch repo — the umbrella shape lost its teeth: $SS_OUT"
mkboard "$HD"
set_status "$HD" E01-F01 done --evidence "$A_BASE"
[ "$SS_RC" = "0" ] || fail "R15 control-2: a merged commit was refused in a remoteless single-branch repo (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARD" "d['landed']['base']")" = "main" ] \
  || fail "R15 control-2: the single-branch default was not used as the base (got $(field "$BOARD" "d['landed'].get('base','')"))"
pass "E99-F102 R15 a_remoteless_default_is_resolved_authoritatively_or_not_at_all"

echo "All landing-evidence tests passed."
