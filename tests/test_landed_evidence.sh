#!/bin/sh
# test_landed_evidence.sh — E99-F102 (the record) + E99-F129 (the verdict).
#
# THE SUITE MIRRORS THE DECISION TABLE. Verification is one question asked of every ref —
# WHAT HAPPENS WHEN VERIFICATION IS IMPOSSIBLE? — and the predecessor answered it per input,
# as fixes accumulated, which is why five review rounds each found the same shape again. The
# answer is a table (`tools/tasks-lock.py` header, `store/local.md`, the CHANGELOG), and
# every row below is a row of it, each with a control:
#
#   row 1 `none:<why>` ⇒ declared .................................. R5, R12
#   row 2 resolves to no object anywhere ⇒ unchecked ............... R4
#   row 3 repo NOT in the manifest ⇒ REFUSE ........................ R20
#   row 4 declared but unreadable here ⇒ unchecked ................. R20
#   row 5 repo located, object unknown in it ⇒ unchecked ........... R4, R14
#   row 6 default branch undeterminable ⇒ unchecked ................ R13, R15
#   row 7 ancestry checkable and TRUE ⇒ ancestor ................... R3, R10, R11, R16, R21
#   row 8 ancestry FALSE, tip confirmed current ⇒ REFUSE ........... R2, R10, R11, R16
#   row 9 ancestry FALSE, tip NOT confirmed ⇒ unchecked ............ R16
#
# ⚠️ ONE CASE WAS DELIBERATELY RETIRED, not lost. The contract half carried an `R18` that
# ran a whole `done` transition with every child-process entry point booby-trapped, proving
# it performed NO I/O. That claim is FALSE here by design — this half exists to run git — so
# keeping it would have meant either a failing test or a weakened one. Its successor is
# **R17**: I/O is allowed, but never INSIDE the board lock, which is the property that
# actually protects concurrent writers. R18 is left unused so the numbering keeps meaning
# across the two halves.
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
#   R16 a STALE local tip never produces a FALSE REFUSAL — the branch name can be
#       right while its tip is old, and refusing merged work is what gets a guard
#       switched off; unconfirmable degrades to `unchecked`, never to a block
#   R17 evidence resolution (which talks to the NETWORK) runs OUTSIDE the board lock,
#       and R17b: the pre-lock resolution is re-validated in-lock, so moving it out
#       did not trade starvation for a TOCTOU
#   R17c the fingerprint covers what the MANIFEST told the plan, not just the slice names —
#       repointing a repo's `path` mid-probe aborts the write instead of recording a proof
#       computed against the old checkout
#   R19 the documented ORDER agrees with the mechanism: `done` is written after the work
#       LANDS, never on the approve verdict (prose contract, section-scoped)
#   R20 the MANIFEST says where a slice's repository is — an ALIASED `path` is followed,
#       an undeclared repo is REFUSED (row 3) and a declared-but-absent one degrades
#       (row 4); both readers of the manifest are held to the same answer
#   R21 GIT decides what an object id is — a branch, a tag and a 64-character SHA-256 id
#       all resolve, and the record names the IMMUTABLE id it was checked on
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
# R16 and R17 are review round 4, reproduced the same way. R17 in particular is
# DETERMINISTIC rather than a wall-clock race: a `git` shim earlier on PATH makes every
# `ls-remote` announce itself through a sentinel file and then sleep, so the test acts at a
# moment it KNOWS a network probe is in flight. Its rc plumbing is deliberate too — a
# background subshell under `set -e` dies AT the failing command, before it can record its
# exit code, and `$(cat <missing>)` then compares unequal to every expected value: that is
# how R17b passed vacuously once, and why `set +e` and `await_bg` exist below.
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

# `set -e` kills this script SILENTLY when a fixture step fails — no assertion runs, so the
# output ends after the last `ok` and the reader is left guessing. Measured while proving the
# fixture guard load-bearing: removing a bare remote's explicit HEAD aborted the run at a
# later `git remote set-head --auto` with no message at all. Name the most likely cause on
# the way out, so an aborted run says so instead of looking like a truncated pass.
_FAILED=""
_cleanup() {
  _rc=$?
  rm -rf "$T"
  if [ "$_rc" -ne 0 ] && [ -z "$_FAILED" ]; then
    echo "FAIL: the suite ABORTED at a fixture step (set -e), not at an assertion — the" >&2
    echo "      commonest cause is a git fixture whose branch was ASSUMED rather than set;" >&2
    echo "      re-run with 'sh -x tests/test_landed_evidence.sh' to locate the step." >&2
  fi
  exit "$_rc"
}
trap _cleanup EXIT

fail() { _FAILED=1; echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v git >/dev/null 2>&1 || fail "git is absent — ancestry cannot be checked"
command -v node >/dev/null 2>&1 || fail "node is absent — next-task.mjs cannot run"
command -v python3 >/dev/null 2>&1 || fail "python3 is absent"

# ── HERMETIC FIXTURES: no fixture may inherit the host's default branch ───────────────
# A suite that depends on the developer's global git config is a suite whose green means
# "on this machine". This one did: two bare remotes were created with `git init --bare` and
# never had their HEAD set, so on a host with `init.defaultBranch=main` they published
# `main` and R10/R16 passed — while on git's historical default they publish an unborn
# `master`, `_default_ref` (which deliberately never guesses a branch NAME) finds nothing to
# compare against, and a local-only commit was recorded `unchecked` instead of REFUSED.
# Measured: `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch
# GIT_CONFIG_VALUE_0=master sh tests/test_landed_evidence.sh` exited 1 at R10.
#
# So the host's value is overridden with a SENTINEL that is neither `main` nor `master`.
# Every fixture must now name its own branch explicitly; any that forgets gets a branch
# nobody looks for and fails immediately, on THIS machine, instead of only on someone
# else's. The sentinel is the guard: it makes the dependency impossible to reintroduce
# silently, because inheriting it is never accidentally correct.
FIXTURE_BRANCH_SENTINEL="fixture-forgot-to-set-head"
GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=init.defaultBranch
GIT_CONFIG_VALUE_0="$FIXTURE_BRANCH_SENTINEL"
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
# ...and PROVE the override reached git. `GIT_CONFIG_*` needs git >= 2.31; on an older git
# it is silently ignored, which would put the suite straight back to host-dependence with
# no symptom. Assert at SETUP, where the message names the real cause.
( cd "$T" && git init -q sentinel-probe )
[ "$(cd "$T/sentinel-probe" && git symbolic-ref HEAD)" = "refs/heads/$FIXTURE_BRANCH_SENTINEL" ] \
  || fail "the init.defaultBranch override did not take effect (git $(git --version | awk '{print $3}') may predate GIT_CONFIG_*) — every fixture below would silently inherit the host's default branch, so a green run here would only mean 'on this machine'"
rm -rf "$T/sentinel-probe"

# mkbare <name> [branch] — a bare remote whose published HEAD is EXPLICIT, then ASSERTED.
# `git init --bare` does not set HEAD to anything a later push changes: pushing `main` into
# a bare repo whose HEAD names an unborn `master` leaves HEAD on `master`, and that symref
# is exactly what `ls-remote --symref` reports as the remote's default branch.
mkbare() {
  _b="${2:-main}"
  ( cd "$T" && git init -q --bare "$1" )
  ( cd "$T/$1" && git symbolic-ref HEAD "refs/heads/$_b" )
  [ "$(cd "$T/$1" && git symbolic-ref HEAD)" = "refs/heads/$_b" ] \
    || fail "fixture $1: the bare remote publishes $(cd "$T/$1" && git symbolic-ref HEAD), not refs/heads/$_b — the remote's default branch is what every ancestry check here compares against"
}

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
# E99-F129: a proof names the IMMUTABLE id it was computed on. `ref` may be a branch (which
# moves); `commit` is what a re-audit re-checks, and the validators require it wherever
# `verified` is a proof.
[ "$(field "$BOARD" "d['landed'].get('commit','')")" = "$BASE" ] \
  || fail "R3: the proof does not carry the immutable commit id it was checked on"
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
# exactly as they do on the outer one. The last cases are E99-F129's: a proof must name the
# IMMUTABLE id it was checked on (`ref` may be a branch, which moves), `commit` must be a
# non-empty string when present, and the rollup rule — the feature-level record can never
# claim more than its slices proved, which is the false attestation re-entered by hand.
for _bad in \
  '{ "ref": "a", "verified": "ancestor", "slices": [] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "web", "verified": "ancestor" } ] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "verified": "probably" } ] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "", "ref": "b", "verified": "ancestor" } ] }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "commit": "c1", "verified": "ancestor", "base": 17 } ] }' \
  '{ "ref": "a", "commit": 17, "verified": "unchecked" }' \
  '{ "ref": "a", "commit": "", "verified": "unchecked" }' \
  '{ "ref": "a", "verified": "ancestor", "repo": "web", "base": "main" }' \
  '{ "ref": "a", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "verified": "ancestor" } ] }' \
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
mkbad '{ "ref": "web=b; api=c", "verified": "unchecked", "slices": [ { "repo": "web", "ref": "b", "commit": "9f1e2d3", "verified": "ancestor", "base": "main" }, { "repo": "api", "ref": "c", "verified": "unchecked" } ] }'
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
mkbad '{ "ref": "abc1234", "commit": "abc1234def5678", "verified": "ancestor", "repo": "viernes-web", "base": "origin/main" }'
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
mkbare remote.git
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
mkbare trunkremote.git trunk
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

# (g) the single-repo path. It still takes one bare value — and, since E99-F129, it also
#     ACCEPTS the bound form: with the repository name resolved and CHECKED rather than
#     merely transcribed, a binding is the operator's way to say WHICH repository an
#     otherwise-ambiguous ref belongs to (identity contract I1). The contract half refused
#     it precisely because nothing verified the name; that reason is gone.
mkboard "$HDV"
set_status "$HDV" E01-F01 done --evidence "alpha=$ALPHA_MAIN"
[ "$SS_RC" = "0" ] || fail "R14g: the bound form was refused on a single-repo feature — it is the only way to disambiguate a ref that resolves in several nearby repositories: $SS_OUT"
[ "$(field "$BOARDV" "d['landed']['repo']")" = "alpha" ] \
  || fail "R14g: a bound single-repo landing did not record the repository it was checked in"
[ "$(field "$BOARDV" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R14g: the bound single-repo landing was not verified in the repository it named"
# ...and a binding naming a repository that cannot be found degrades honestly (row 4)
# rather than silently attesting against something else.
mkboard "$HDV"
set_status "$HDV" E01-F01 done --evidence "nosuchrepo=$ALPHA_MAIN"
[ "$SS_RC" = "0" ] || fail "R14g: a binding to an unlocatable repository BLOCKED the write: $SS_OUT"
[ "$(field "$BOARDV" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R14g: a binding to a repository that cannot be found must degrade, not claim a proof"
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

# ── R16: a stale local TIP must not produce a FALSE REFUSAL ───────────────────────────
# Review round 4, REPRODUCED against the shipped code first. Distinct from R13's stale
# NAME: here `origin/HEAD` names `main` and main really IS the default — what is stale is
# the local tracking ref's TIP. The PR merged on the remote, this clone has not fetched
# since, so `refs/remotes/origin/main` still points at an older commit and
# `merge-base --is-ancestor` reported "the work is not merged" about a commit that was
# LITERALLY the remote's main tip — the same message, and the same rc=1, as a commit that
# had never left the laptop. That is the mirror of the false attestation and the more
# corrosive direction: a guard that rejects legitimate merged work is one people route
# around or switch off.
mkdir -p "$T/staleclone/hd/state" "$T/staleclone/hd/store" "$T/staleclone/hd/tools"
cp "$SCHEMA" "$T/staleclone/hd/store/"; cp "$VALIDATE" "$T/staleclone/hd/tools/"
mkbare staleremote.git
( cd "$T/staleclone" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$T/staleclone/seed.txt"; ( cd "$T/staleclone" && git_q add -A && git_q commit -m base )
( cd "$T/staleclone" && git_q remote add origin "$T/staleremote.git" && git_q push origin main )
( cd "$T/staleclone" && git_q remote set-head origin --auto )
STALE_AT="$(cd "$T/staleclone" && git rev-parse origin/main)"
# the work: committed here, then MERGED on the remote…
( cd "$T/staleclone" && : > feature.txt && git_q add -A && git_q commit -m "the feature" )
SC_MERGED="$(cd "$T/staleclone" && git rev-parse HEAD)"
( cd "$T/staleclone" && git_q push origin main )
# …and a clone that has not fetched since: rewind the tracking ref to where it was.
( cd "$T/staleclone" && git_q update-ref refs/remotes/origin/main "$STALE_AT" )
# …plus a commit that genuinely never merged, for the control.
( cd "$T/staleclone" && git_q checkout --detach main && : > wip.txt && git_q add -A && git_q commit -m "never merged" )
SC_UNMERGED="$(cd "$T/staleclone" && git rev-parse HEAD)"
( cd "$T/staleclone" && git_q update-ref refs/evidence/wip "$SC_UNMERGED" && git_q checkout main )
# Assert the fixture is the state INTENDED — including what must still be PRESENT.
[ "$(cd "$T/staleclone" && git rev-parse origin/main)" = "$STALE_AT" ] \
  || fail "R16 setup: the tracking ref is not stale, so nothing here is exercised"
[ "$(cd "$T/staleremote.git" && git rev-parse main)" = "$SC_MERGED" ] \
  || fail "R16 setup: the remote's main is not the merged commit"
[ "$(cd "$T/staleclone" && git symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/main" ] \
  || fail "R16 setup: origin/HEAD is absent or wrong — this case is about a stale TIP, not a stale NAME"
( cd "$T/staleclone" && git merge-base --is-ancestor "$SC_MERGED" origin/main ) \
  && fail "R16 setup: the merged commit IS reachable from the stale ref, so the false refusal cannot arise"
HDS="$T/staleclone/hd"
BOARDS="$HDS/state/tasks.json"

mkboard "$HDS"
set_status "$HDS" E01-F01 done --evidence "$SC_MERGED"
[ "$SS_RC" = "0" ] || fail "R16: work that IS the remote default branch's tip was REFUSED because the local tracking ref had not been fetched — a false refusal is what gets a guard switched off: $SS_OUT"
[ "$(field "$BOARDS" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R16: the remotely-merged commit was recorded $(field "$BOARDS" "d['landed']['verified']"), not ancestor"

# CONTROL 1 — the SAME repository in the SAME stale state, differing only in the commit: a
# commit that genuinely never reached the remote is STILL REFUSED. Without this, R16 would
# pass against an implementation that simply stopped refusing.
mkboard "$HDS"
BEFORE="$(cat "$BOARDS")"
set_status "$HDS" E01-F01 done --evidence "$SC_UNMERGED"
[ "$SS_RC" = "0" ] && fail "R16 control-1: an unmerged commit was accepted — confirming the tip against the remote must not turn the refusal off: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDS")" ] || fail "R16 control-1: the board moved despite the refusal"
case "$SS_OUT" in
  *"NOT an ancestor"*) ;;
  *) fail "R16 control-1: the refusal does not say the work is unmerged: $SS_OUT" ;;
esac

# CONTROL 2 — the remote has moved somewhere this checkout does NOT have. Then neither
# answer is provable here, so BOTH degrade to `unchecked`: never a false attestation, and
# never a false refusal. This is the narrowness, and it is what makes the fix safe offline.
( cd "$T" && git clone -q "$T/staleremote.git" other )
( cd "$T/other" && : > later.txt && git_q add -A && git_q commit -m "someone else's later merge" && git_q push origin main )
AHEAD_TIP="$(cd "$T/staleremote.git" && git rev-parse main)"
( cd "$T/staleclone" && git cat-file -e "$AHEAD_TIP^{commit}" 2>/dev/null ) \
  && fail "R16 control-2: the stale clone already has the newer remote tip, so it is not the unfetched state"
mkboard "$HDS"
set_status "$HDS" E01-F01 done --evidence "$SC_UNMERGED"
[ "$SS_RC" = "0" ] || fail "R16 control-2: an unprovable refusal BLOCKED the write — inability to confirm must degrade, never block: $SS_OUT"
[ "$(field "$BOARDS" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R16 control-2: expected 'unchecked' when the remote has moved beyond this checkout, got $(field "$BOARDS" "d['landed']['verified']")"
case "$SS_OUT" in
  *fetch*) ;;
  *) fail "R16 control-2: the warning does not tell the operator how to get a definitive answer: $SS_OUT" ;;
esac

# CONTROL 3 — fetch, and the definitive answers come back in BOTH directions. This rules
# out "the repository became permanently unverifiable" as the explanation for control 2.
( cd "$T/staleclone" && git_q fetch origin )
mkboard "$HDS"
set_status "$HDS" E01-F01 done --evidence "$SC_MERGED"
[ "$SS_RC" = "0" ] || fail "R16 control-3: after fetching, the merged commit was refused (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARDS" "d['landed']['verified']")" = "ancestor" ] || fail "R16 control-3: the merged commit is not ancestor after a fetch"
mkboard "$HDS"
BEFORE="$(cat "$BOARDS")"
set_status "$HDS" E01-F01 done --evidence "$SC_UNMERGED"
[ "$SS_RC" = "0" ] && fail "R16 control-3: after fetching, an unmerged commit was still accepted: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDS")" ] || fail "R16 control-3: the board moved despite the refusal"

# CONTROL 4 — an UNREACHABLE remote degrades too (it must never block), and this is the
# only reason the fix cannot simply refuse whenever the tip cannot be confirmed.
( cd "$T/staleclone" && git_q update-ref refs/remotes/origin/main "$STALE_AT" )
( cd "$T/staleclone" && git_q remote set-url origin "$T/does-not-exist-either.git" )
mkboard "$HDS"
set_status "$HDS" E01-F01 done --evidence "$SC_UNMERGED"
[ "$SS_RC" = "0" ] || fail "R16 control-4: an unreachable remote BLOCKED the write (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARDS" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R16 control-4: expected 'unchecked' with an unreachable remote, got $(field "$BOARDS" "d['landed']['verified']")"
pass "E99-F102 R16 a_stale_local_tip_never_produces_a_false_refusal"

# ── R17: network probes must NOT run inside the board lock ────────────────────────────
# Review round 4, P1, REPRODUCED against the shipped code first: evidence resolution ran
# inside the critical section, so a sliced `done` whose slice remotes are unreachable held
# `tasks.json.lock` through one bounded `ls-remote` PER SLICE REPO. Measured on two slices:
# a concurrent writer with a 1s bounded acquisition was refused the lock and ITS TRANSITION
# WAS LOST — the no-lost-update guarantee (R1) that the lock exists to provide, defeated by
# the guard built on top of it.
#
# Deterministic, not a wall-clock race: a `git` shim earlier on PATH makes every
# `ls-remote` touch a sentinel and then sleep, so the test knows EXACTLY when a network
# probe is in flight and can act while it is.
W="$T/lockprobe"
mkdir -p "$W/.harness/state" "$W/.harness/store" "$W/.harness/tools"
cp "$SCHEMA" "$W/.harness/store/"; cp "$VALIDATE" "$W/.harness/tools/"
( cd "$W" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$W/README.md"; ( cd "$W" && git_q add -A && git_q commit -m board )
for _r in alpha beta; do
  mkdir -p "$W/$_r"
  ( cd "$W/$_r" && git init -q . && git symbolic-ref HEAD refs/heads/main )
  : > "$W/$_r/src.txt"; ( cd "$W/$_r" && git_q add -A && git_q commit -m "$_r work" )
  # An origin that was never fetched: no refs/remotes/origin/HEAD is cached, so the
  # default branch has to be ASKED for — the probe this case is about.
  ( cd "$W/$_r" && git_q remote add origin "$T/nowhere-$_r.git" )
  ( cd "$W/$_r" && git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1 ) \
    && fail "R17 setup: $_r has a cached origin/HEAD, so no remote probe would run"
done
LP_ALPHA="$(cd "$W/alpha" && git rev-parse main)"
LP_BETA="$(cd "$W/beta" && git rev-parse main)"
REAL_GIT="$(command -v git)"
SENT="$T/probe-in-flight"
mkdir -p "$T/bin"
cat > "$T/bin/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = "ls-remote" ]; then
    : > "$SENT"
    sleep 3
    exit 1
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/bin/git"

lp_board() {
  cat > "$W/.harness/state/tasks.json" <<EOF
{
  "project": "lock-probe",
  "epics": [
    { "id": "E01", "title": "e", "status": "in-progress",
      "features": [
        { "id": "E01-F01", "title": "sliced", "status": "in-review", "sdd": true, "spec_path": "s/",
          "slices": [
            { "id": "E01-F01@alpha", "repo": "alpha", "status": "done", "merged": true },
            { "id": "E01-F01@beta", "repo": "beta", "status": "done", "merged": true }
          ] },
        { "id": "E01-F02", "title": "another writer's feature", "status": "pending",
          "sdd": true, "spec_path": "s2/" }
      ] }
  ]
}
EOF
}
# wait_probe: bounded poll for the sentinel. Never "sleep and hope" — if the probe never
# runs the case is VACUOUS, and that is a failure, not a pass.
wait_probe() {
  rm -f "$SENT"
  _i=0
  while [ ! -f "$SENT" ]; do
    _i=$((_i + 1))
    [ "$_i" -gt 150 ] && fail "R17: the ls-remote probe never ran — this case would be vacuous"
    sleep 0.1
  done
}
# await_bg <pid> <rc-file>: reap the background writer AND wait for its recorded exit code
# to exist. `$(cat <missing>)` yields the empty string, which compares unequal to every
# expected rc — so a background job that had not finished would make an `= "0"` assertion
# pass with nothing behind it. Absent rc ⇒ loud failure, never a silent green.
await_bg() {
  wait "$1" 2>/dev/null || true
  _i=0
  while [ ! -f "$2" ]; do
    _i=$((_i + 1))
    [ "$_i" -gt 150 ] && fail "R17: the background writer never recorded an exit code in $2 — any assertion on it would be vacuous"
    sleep 0.1
  done
}

lp_board
rm -f "$SENT"
( set +e   # `set -e` would kill this subshell AT the failing command, before it could
            # record the exit code — which is how R17b passed vacuously once already.
  PATH="$T/bin:$PATH" HARNESS_DIR="$W/.harness" python3 "$LOCK" set-status E01-F01 done \
    --evidence "alpha=$LP_ALPHA" --evidence "beta=$LP_BETA" >"$T/lp.out" 2>&1
  echo $? > "$T/lp.rc" ) &
LP_BG=$!
wait_probe
# THE ASSERTION: while a network probe is in flight, an unrelated writer still gets the
# lock, with a bounded timeout far shorter than the probe.
set_status "$W/.harness" E01-F02 in-progress --timeout 1
[ "$SS_RC" = "0" ] || fail "R17: a concurrent writer was starved out while evidence resolution ran a network probe (rc=$SS_RC) — the sole supported write path held the lock across ~2 bounded ls-remotes, so the other writer's transition was LOST: $SS_OUT"
await_bg "$LP_BG" "$T/lp.rc"
[ "$(cat "$T/lp.rc")" = "0" ] || fail "R17: the sliced transition itself failed (rc=$(cat "$T/lp.rc")): $(cat "$T/lp.out")"
[ "$(field "$W/.harness/state/tasks.json" "d['status']")" = "done" ] \
  || fail "R17: the sliced transition did not land"
[ "$(python3 -c "import json;print(json.load(open('$W/.harness/state/tasks.json'))['epics'][0]['features'][1]['status'])")" = "in-progress" ] \
  || fail "R17: the concurrent writer's transition was LOST — it reported success but the board does not carry it"

# CONTROL — the same command, same fixture, differing ONLY in whether something holds the
# lock: it MUST fail. Without this, the assertion above would pass against a helper that
# never locks at all, which is the opposite defect (R1: lost updates).
cat > "$T/holder.py" <<'PY'
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(float(sys.argv[3]))
PY
rm -f "$T/held"
python3 "$T/holder.py" "$W/.harness/state/tasks.json.lock" "$T/held" 3 &
HOLD_BG=$!
_i=0
while [ ! -f "$T/held" ]; do
  _i=$((_i + 1))
  [ "$_i" -gt 100 ] && fail "R17 control: the lock holder never started"
  sleep 0.1
done
set_status "$W/.harness" E01-F01 in-review --timeout 1
[ "$SS_RC" = "0" ] && fail "R17 control: a writer acquired the lock while another process HELD it — the probe cannot detect lock contention, so the assertion above proves nothing"
case "$SS_OUT" in
  *"could not acquire advisory lock"*) ;;
  *) fail "R17 control: a blocked writer failed for some reason OTHER than the lock: $SS_OUT" ;;
esac
# …and, with the lock STILL held: a refusal that needs no lock does not queue for one.
# Evidence is resolved before the lock, so a missing-evidence `done` reports the EVIDENCE
# problem rather than a lock timeout — the same command as the control above, differing
# only in what is wrong with it.
set_status "$W/.harness" E01-F01 done --timeout 1
[ "$SS_RC" = "0" ] && fail "R17: a `done` with no evidence was accepted: $SS_OUT"
case "$SS_OUT" in
  *"needs evidence"*) ;;
  *) fail "R17: a refusal that needs no lock reported a LOCK failure instead — evidence is not being resolved before the lock is taken: $SS_OUT" ;;
esac
wait "$HOLD_BG" 2>/dev/null || true

# ── R17b: resolving before the lock must not become a TOCTOU ──────────────────────────
# The set of slice repositories to probe is read from the board, and the board is what the
# lock protects. So the pre-lock resolution is fingerprinted and re-validated against the
# authoritative in-lock re-read: if this feature's slice set changed underneath, the write
# ABORTS rather than recording evidence resolved for a different set of repositories.
lp_board
rm -f "$SENT"
( set +e   # `set -e` would kill this subshell AT the failing command, before it could
            # record the exit code — which is how R17b passed vacuously once already.
  PATH="$T/bin:$PATH" HARNESS_DIR="$W/.harness" python3 "$LOCK" set-status E01-F01 done \
    --evidence "alpha=$LP_ALPHA" --evidence "beta=$LP_BETA" >"$T/lp2.out" 2>&1
  echo $? > "$T/lp2.rc" ) &
LP_BG=$!
wait_probe
# While the probe is in flight (and the lock is free), change the feature's slice set.
python3 - "$W/.harness/state/tasks.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
f = d['epics'][0]['features'][0]
f['slices'] = [ { "id": "E01-F01@alpha", "repo": "alpha", "status": "done", "merged": True },
                { "id": "E01-F01@gamma", "repo": "gamma", "status": "done", "merged": True } ]
open(p, 'w').write(json.dumps(d, indent=2) + "\n")
PY
await_bg "$LP_BG" "$T/lp2.rc"
[ "$(cat "$T/lp2.rc")" = "0" ] && fail "R17b: evidence resolved for {alpha, beta} was written onto a feature now sliced across {alpha, gamma} — the pre-lock resolution traded starvation for a TOCTOU: $(cat "$T/lp2.out")"
grep -q "changed between the evidence check and the write" "$T/lp2.out" \
  || fail "R17b: the abort does not say the board changed under the resolution: $(cat "$T/lp2.out")"
[ "$(field "$W/.harness/state/tasks.json" "d['status']")" = "in-review" ] \
  || fail "R17b: the feature moved despite the abort"
[ "$(field "$W/.harness/state/tasks.json" "'landed' in d")" = "False" ] \
  || fail "R17b: a landing record resolved for the OLD slice set was written anyway"

# CONTROL — the identical run with NO concurrent change must succeed, so R17b is about the
# change and not about the pre-lock path being broken.
lp_board
rm -f "$SENT"
( set +e   # `set -e` would kill this subshell AT the failing command, before it could
            # record the exit code — which is how R17b passed vacuously once already.
  PATH="$T/bin:$PATH" HARNESS_DIR="$W/.harness" python3 "$LOCK" set-status E01-F01 done \
    --evidence "alpha=$LP_ALPHA" --evidence "beta=$LP_BETA" >"$T/lp3.out" 2>&1
  echo $? > "$T/lp3.rc" ) &
LP_BG=$!
wait_probe
await_bg "$LP_BG" "$T/lp3.rc"
[ "$(cat "$T/lp3.rc")" = "0" ] || fail "R17b control: the same run without a concurrent change FAILED (rc=$(cat "$T/lp3.rc")): $(cat "$T/lp3.out")"
[ "$(field "$W/.harness/state/tasks.json" "d['status']")" = "done" ] || fail "R17b control: the transition did not land"
# ...and a change that does NOT touch the slice set must not abort — the fingerprint is the
# resolution's own inputs, not "the board must be frozen".
lp_board
rm -f "$SENT"
( set +e   # `set -e` would kill this subshell AT the failing command, before it could
            # record the exit code — which is how R17b passed vacuously once already.
  PATH="$T/bin:$PATH" HARNESS_DIR="$W/.harness" python3 "$LOCK" set-status E01-F01 done \
    --evidence "alpha=$LP_ALPHA" --evidence "beta=$LP_BETA" >"$T/lp4.out" 2>&1
  echo $? > "$T/lp4.rc" ) &
LP_BG=$!
wait_probe
set_status "$W/.harness" E01-F02 in-progress --timeout 1
[ "$SS_RC" = "0" ] || fail "R17b control: the unrelated concurrent write was refused: $SS_OUT"
await_bg "$LP_BG" "$T/lp4.rc"
[ "$(cat "$T/lp4.rc")" = "0" ] \
  || fail "R17b control: an unrelated concurrent write aborted the sliced transition (rc=$(cat "$T/lp4.rc")) — the fingerprint is over-broad: $(cat "$T/lp4.out")"
# ── R17c: the fingerprint must cover the MANIFEST, not just the slice NAMES ───────────
# Review round 1 on this PR. The manifest is the authority for row 3 and the locator for
# row 4, so it is part of what a resolution ASSUMED — and therefore part of what has to be
# re-validated. It was not: the fingerprint pinned only the slice names, so repointing a
# repo's `path` while the probe was in flight left the names matching and the write went
# ahead. Reproduced before the fix: `verified: "ancestor"`, computed against the old
# checkout, was written while the manifest named a checkout that had never seen the commit.
Y="$T/mtoc"
mkdir -p "$Y/.harness/state" "$Y/.harness/store" "$Y/.harness/tools" "$T/real-alpha" "$T/decoy-alpha"
cp "$SCHEMA" "$Y/.harness/store/"; cp "$VALIDATE" "$Y/.harness/tools/"
( cd "$Y" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$Y/README.md"; ( cd "$Y" && git_q add -A && git_q commit -m board )
( cd "$T/real-alpha" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$T/real-alpha/src.txt"; ( cd "$T/real-alpha" && git_q add -A && git_q commit -m "the work" )
Y_LANDED="$(cd "$T/real-alpha" && git rev-parse main)"
( cd "$T/decoy-alpha" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$T/decoy-alpha/other.txt"; ( cd "$T/decoy-alpha" && git_q add -A && git_q commit -m unrelated )
( cd "$T/decoy-alpha" && git cat-file -e "$Y_LANDED^{commit}" 2>/dev/null ) \
  && fail "R17c setup: the decoy already has the evidence commit, so a swap would prove nothing"
cat > "$Y/.harness/harness.config.yaml" <<'EOF'
store:
  backend: local
umbrella:
  manifest: ../umbrella.manifest.yaml
EOF
ymanifest() {  # ymanifest <dir-under-T> [extra]
  cat > "$Y/umbrella.manifest.yaml" <<EOF
repos:
  alpha:
    path: ../$1
    init: ./init.sh
    test_command: "true"${2:-}
EOF
}
yboard() {
  cat > "$Y/.harness/state/tasks.json" <<'EOF'
{ "project": "mtoc", "epics": [ { "id": "E01", "title": "e", "status": "in-progress",
  "features": [ { "id": "E01-F01", "title": "f", "status": "in-review", "sdd": true,
    "spec_path": "s/",
    "slices": [ { "id": "E01-F01@alpha", "repo": "alpha", "status": "done", "merged": true } ] } ] } ] }
EOF
}
# A second shim: sleep on `for-each-ref` and then DELEGATE to the real git, so the probe is
# slow but its verdict is genuine (R17's shim fails the call, which would answer row 6).
YSENT="$T/mtoc-probe"
mkdir -p "$T/bin2"
cat > "$T/bin2/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  if [ "\$a" = "for-each-ref" ]; then : > "$YSENT"; sleep 3; break; fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/bin2/git"
ywait() {
  rm -f "$YSENT"
  _i=0
  while [ ! -f "$YSENT" ]; do
    _i=$((_i + 1))
    [ "$_i" -gt 150 ] && fail "R17c: the probe never ran — this case would be vacuous"
    sleep 0.1
  done
}
ystart() {
  ( set +e
    PATH="$T/bin2:$PATH" HARNESS_DIR="$Y/.harness" python3 "$LOCK" set-status E01-F01 done \
      --evidence "alpha=$Y_LANDED" >"$T/y.out" 2>&1
    echo $? > "$T/y.rc" ) &
  Y_BG=$!
}

# THE KILL: repoint `alpha` at a checkout that has never seen the commit, mid-probe.
ymanifest real-alpha; yboard; rm -f "$T/y.rc"
ystart; ywait
ymanifest decoy-alpha
await_bg "$Y_BG" "$T/y.rc"
[ "$(cat "$T/y.rc")" = "0" ] && fail "R17c: a proof resolved against one checkout was written after the manifest repointed that repository at another — the fingerprint covers the slice NAMES but not what the manifest said they were: $(cat "$T/y.out")"
grep -q "changed between the evidence check and the write" "$T/y.out" \
  || fail "R17c: the abort does not say the resolution no longer applies: $(cat "$T/y.out")"
grep -q "decoy-alpha" "$T/y.out" \
  || fail "R17c: the abort does not name WHERE the repository moved to — the witness is a hash or a bare flag, and the operator cannot see what changed: $(cat "$T/y.out")"
[ "$(field "$Y/.harness/state/tasks.json" "d['status']")" = "in-review" ] \
  || fail "R17c: the feature moved despite the abort"
[ "$(field "$Y/.harness/state/tasks.json" "'landed' in d")" = "False" ] \
  || fail "R17c: a record justified by the OLD checkout was written anyway"

# CONTROL 1 — the identical run with NO swap must SUCCEED, so R17c is about the swap and
# not about the manifest path being unusable.
ymanifest real-alpha; yboard; rm -f "$T/y.rc"
ystart; ywait
await_bg "$Y_BG" "$T/y.rc"
[ "$(cat "$T/y.rc")" = "0" ] || fail "R17c control-1: the same run without a swap FAILED (rc=$(cat "$T/y.rc")): $(cat "$T/y.out")"
[ "$(field "$Y/.harness/state/tasks.json" "d['landed']['slices'][0]['verified']")" = "ancestor" ] \
  || fail "R17c control-1: the unswapped run did not verify"

# CONTROL 2 — an UNRELATED manifest edit (a repository this feature has no slice in) must
# NOT abort. The witness pins the inputs this resolution used, not the whole file; pinning
# the file would abort ordinary concurrent edits and teach operators to re-run blindly.
ymanifest real-alpha; yboard; rm -f "$T/y.rc"
ystart; ywait
ymanifest real-alpha '
  unrelated-repo:
    path: ../somewhere-else
    init: ./init.sh
    test_command: "true"'
await_bg "$Y_BG" "$T/y.rc"
[ "$(cat "$T/y.rc")" = "0" ] \
  || fail "R17c control-2: adding an UNRELATED repository to the manifest aborted the write (rc=$(cat "$T/y.rc")) — the witness is over-broad: $(cat "$T/y.out")"
[ "$(field "$Y/.harness/state/tasks.json" "d['landed']['slices'][0]['verified']")" = "ancestor" ] \
  || fail "R17c control-2: the transition did not land"

# CONTROL 3 — the manifest DISAPPEARING mid-probe aborts too. A record resolved under an
# authority that no longer exists must not be written; the abort costs one re-run, and the
# re-run converges because it both plans and re-validates under the new state.
ymanifest real-alpha; yboard; rm -f "$T/y.rc"
ystart; ywait
rm -f "$Y/umbrella.manifest.yaml"
await_bg "$Y_BG" "$T/y.rc"
[ "$(cat "$T/y.rc")" = "0" ] \
  && fail "R17c control-3: the manifest vanished mid-probe and the proof it authorised was written anyway: $(cat "$T/y.out")"
[ "$(field "$Y/.harness/state/tasks.json" "'landed' in d")" = "False" ] \
  || fail "R17c control-3: a record was written after its authority disappeared"
# ...and the re-run CONVERGES rather than aborting forever: with no manifest there is no
# authority, so the same command now degrades to row 4 and completes.
yboard
set_status "$Y/.harness" E01-F01 done --evidence "alpha=$Y_LANDED"
[ "$SS_RC" = "0" ] || fail "R17c control-3: the re-run after the manifest vanished ALSO aborted (rc=$SS_RC) — the abort must converge, not livelock: $SS_OUT"
pass "E99-F102 R17c the_fingerprint_covers_what_the_manifest_told_the_plan"

pass "E99-F102 R17 evidence_resolution_runs_outside_the_lock_and_is_revalidated_inside_it"

# ── R22: WHICH repository is the claim about? (identity contract I1) ──────────────────
# Round 2. The nine rows decide a verdict for a (ref, repository) pair and presume the pair
# is settled; it was not. An unbound ref was resolved by SEARCH and the first hit won — and
# `_repo_candidates()` tries the harness dir and its parent BEFORE the children, so the
# first hit is the umbrella's own bookkeeping repository, the one repository that never
# holds feature work. Measured on an umbrella whose board repo and child both have `main`:
# `--evidence main` recorded {"verified": "ancestor", "repo": "umb"} — an attestation about
# a board-keeping commit, standing in for the feature's work.
AMB="$T/ambig"
mkdir -p "$AMB/.harness/state" "$AMB/.harness/store" "$AMB/.harness/tools"
cp "$SCHEMA" "$AMB/.harness/store/"; cp "$VALIDATE" "$AMB/.harness/tools/"
( cd "$AMB" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$AMB/board-note.txt"; ( cd "$AMB" && git_q add -A && git_q commit -m "umbrella bookkeeping" )
AMB_UMB="$(cd "$AMB" && git rev-parse main)"
mkdir -p "$AMB/child"
( cd "$AMB/child" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$AMB/child/src.txt"; ( cd "$AMB/child" && git_q add -A && git_q commit -m "the actual work" )
AMB_CHILD="$(cd "$AMB/child" && git rev-parse main)"
[ "$AMB_UMB" = "$AMB_CHILD" ] && fail "R22 setup: the two repositories share a commit id, so 'which one' would be undetectable"
( cd "$AMB/child" && git cat-file -e "$AMB_UMB^{commit}" 2>/dev/null ) \
  && fail "R22 setup: the child can see the umbrella's commit, so the case is not testing ambiguity"
HDA="$AMB/.harness"
BOARDA="$HDA/state/tasks.json"

# `main` exists in BOTH: the claim does not say which, and no ordering can settle it.
mkboard "$HDA"
BEFORE="$(cat "$BOARDA")"
set_status "$HDA" E01-F01 done --evidence "main"
[ "$SS_RC" = "0" ] && fail "R22: an ambiguous ref was resolved by taking the first candidate — with the harness dir searched first that attests the umbrella's own bookkeeping commit for this feature: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDA")" ] || fail "R22: the board moved despite the refusal"
case "$SS_OUT" in
  *"resolves in"*) ;;
  *) fail "R22: the refusal does not say the claim is ambiguous: $SS_OUT" ;;
esac

# CONTROL 1 — the FIRST remedy the refusal names: an immutable commit id normally exists in
# only one of them, so it is unambiguous and verifies. This is also the control that rules
# out "the guard now refuses every unbound ref".
mkboard "$HDA"
set_status "$HDA" E01-F01 done --evidence "$AMB_CHILD"
[ "$SS_RC" = "0" ] || fail "R22 control-1: an UNAMBIGUOUS commit id was refused (rc=$SS_RC) — the guard is refusing unbound refs wholesale: $SS_OUT"
[ "$(field "$BOARDA" "d['landed']['repo']")" = "child" ] \
  || fail "R22 control-1: the record names $(field "$BOARDA" "d['landed']['repo']"), not the repository the commit actually lives in"

# CONTROL 2 — the SECOND remedy: bind the claim. The same ambiguous ref, now saying which.
mkboard "$HDA"
set_status "$HDA" E01-F01 done --evidence "child=main"
[ "$SS_RC" = "0" ] || fail "R22 control-2: binding the ambiguous ref to a repository was still refused (rc=$SS_RC) — the refusal names a remedy that does not work: $SS_OUT"
[ "$(field "$BOARDA" "d['landed']['commit']")" = "$AMB_CHILD" ] \
  || fail "R22 control-2: the bound claim resolved to $(field "$BOARDA" "d['landed']['commit']"), not the child's commit"

# CONTROL 3 — ambiguity is about REPOSITORIES, not directories: two linked worktrees of ONE
# repository must not read as ambiguous, or the guard would refuse ordinary layouts.
( cd "$AMB/child" && git_q worktree add "$AMB/child-wt" -b wt-branch )
[ -e "$AMB/child-wt/.git" ] || fail "R22 setup: the linked worktree was not created"
mkboard "$HDA"
set_status "$HDA" E01-F01 done --evidence "$AMB_CHILD"
[ "$SS_RC" = "0" ] || fail "R22 control-3: a commit visible through a repository AND its own linked worktree was refused as ambiguous — two directories, one repository: $SS_OUT"
( cd "$AMB/child" && git_q worktree remove --force "$AMB/child-wt" )
# CONTROL 4 — I3: the SINGLE-REPO path needs the same identity stability the sliced path
# has. The candidate set is what made an unbound ref unambiguous, so a repository appearing
# beside the board between the plan and the write changes what the claim is ABOUT and must
# abort — not quietly re-decide. Same plan→write window: hold the lock.
symboard_amb() { mkboard "$HDA"; }
symboard_amb; rm -f "$T/amb.rc" "$T/held3"
cat > "$T/holder.py" <<'PY2'
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(float(sys.argv[3]))
PY2
python3 "$T/holder.py" "$HDA/state/tasks.json.lock" "$T/held3" 4 &
AMB_HOLD=$!
_i=0; while [ ! -f "$T/held3" ]; do _i=$((_i+1)); [ "$_i" -gt 100 ] && fail "R22 control-4: the lock holder never started"; sleep 0.1; done
( set +e
  HARNESS_DIR="$HDA" python3 "$LOCK" set-status E01-F01 done --evidence "$AMB_CHILD"     >"$T/amb.out" 2>&1
  echo $? > "$T/amb.rc" ) &
AMB_BG=$!
sleep 1.5                      # the plan has chosen a repository; the write is queued
mkdir -p "$AMB/newcomer" && ( cd "$AMB/newcomer" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$AMB/newcomer/x.txt"; ( cd "$AMB/newcomer" && git_q add -A && git_q commit -m "appeared mid-write" )
wait "$AMB_HOLD" 2>/dev/null || true
await_bg "$AMB_BG" "$T/amb.rc"
[ "$(cat "$T/amb.rc")" = "0" ]   && fail "R22 control-4: a repository appeared beside the board between the plan and the write, changing what an unbound ref could mean, and the verdict was written anyway — the single-repo path carries no identity witness: $(cat "$T/amb.out")"
[ "$(field "$BOARDA" "'landed' in d")" = "False" ] || fail "R22 control-4: a record was written despite the abort"
rm -rf "$AMB/newcomer"
# ...and with the search space unchanged, the identical run SUCCEEDS — so control-4 is about
# the newcomer, not about the single-repo path being unwritable while the lock is contended.
symboard_amb; rm -f "$T/amb.rc" "$T/held3"
python3 "$T/holder.py" "$HDA/state/tasks.json.lock" "$T/held3" 3 &
AMB_HOLD=$!
_i=0; while [ ! -f "$T/held3" ]; do _i=$((_i+1)); [ "$_i" -gt 100 ] && fail "R22 control-4: the lock holder never started"; sleep 0.1; done
( set +e
  HARNESS_DIR="$HDA" python3 "$LOCK" set-status E01-F01 done --evidence "$AMB_CHILD"     >"$T/amb2.out" 2>&1
  echo $? > "$T/amb.rc" ) &
AMB_BG=$!
wait "$AMB_HOLD" 2>/dev/null || true
await_bg "$AMB_BG" "$T/amb.rc"
[ "$(cat "$T/amb.rc")" = "0" ]   || fail "R22 control-4 control: the same queued write FAILED with no newcomer (rc=$(cat "$T/amb.rc")): $(cat "$T/amb2.out")"
pass "E99-F102 R22 an_ambiguous_ref_is_refused_and_both_remedies_work"

# ── R23: a repository's identity is its REALPATH, not its spelling (I2/I3) ────────────
# Round 2. The witness stored the lexical path, so retargeting a symlink between the plan
# and the write left the fingerprint matching while the repository underneath changed. The
# window is the plan→write boundary, so it is opened by HOLDING THE LOCK rather than by
# slowing the probe — that is where the guard is supposed to look.
SYM="$T/symid"
mkdir -p "$SYM/.harness/state" "$SYM/.harness/store" "$SYM/.harness/tools" "$T/id-real" "$T/id-decoy"
cp "$SCHEMA" "$SYM/.harness/store/"; cp "$VALIDATE" "$SYM/.harness/tools/"
( cd "$SYM" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$SYM/r.txt"; ( cd "$SYM" && git_q add -A && git_q commit -m board )
( cd "$T/id-real" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$T/id-real/src.txt"; ( cd "$T/id-real" && git_q add -A && git_q commit -m work )
ID_LANDED="$(cd "$T/id-real" && git rev-parse main)"
( cd "$T/id-decoy" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$T/id-decoy/o.txt"; ( cd "$T/id-decoy" && git_q add -A && git_q commit -m unrelated )
( cd "$T/id-decoy" && git cat-file -e "$ID_LANDED^{commit}" 2>/dev/null ) \
  && fail "R23 setup: the decoy already has the commit, so the swap would prove nothing"
ln -sfn "$T/id-real" "$T/id-link"
cat > "$SYM/.harness/harness.config.yaml" <<'EOF'
store:
  backend: local
umbrella:
  manifest: ../umbrella.manifest.yaml
EOF
cat > "$SYM/umbrella.manifest.yaml" <<'EOF'
repos:
  alpha:
    path: ../id-link
    init: ./init.sh
    test_command: "true"
EOF
symboard() {
  cat > "$SYM/.harness/state/tasks.json" <<'EOF'
{ "project": "symid", "epics": [ { "id": "E01", "title": "e", "status": "in-progress",
  "features": [ { "id": "E01-F01", "title": "f", "status": "in-review", "sdd": true,
    "spec_path": "s/",
    "slices": [ { "id": "E01-F01@alpha", "repo": "alpha", "status": "done", "merged": true } ] } ] } ] }
EOF
}
# hold the lock, so the plan completes and the WRITE waits — the exact boundary at issue
symrun() {  # symrun <retarget-to|"">
  symboard; rm -f "$T/sym.rc" "$T/held2"
  python3 "$T/holder.py" "$SYM/.harness/state/tasks.json.lock" "$T/held2" 4 &
  SYM_HOLD=$!
  _i=0; while [ ! -f "$T/held2" ]; do _i=$((_i+1)); [ "$_i" -gt 100 ] && fail "R23: the lock holder never started"; sleep 0.1; done
  ( set +e
    HARNESS_DIR="$SYM/.harness" python3 "$LOCK" set-status E01-F01 done \
      --evidence "alpha=$ID_LANDED" >"$T/sym.out" 2>&1
    echo $? > "$T/sym.rc" ) &
  SYM_BG=$!
  sleep 1.5                      # the plan has finished; the write is queued on the lock
  [ -n "$1" ] && ln -sfn "$1" "$T/id-link"
  wait "$SYM_HOLD" 2>/dev/null || true
  await_bg "$SYM_BG" "$T/sym.rc"
}

symrun "$T/id-decoy"
[ "$(cat "$T/sym.rc")" = "0" ] && fail "R23: the symlink was retargeted between the plan and the write and the verdict computed against the OLD checkout was written anyway — a lexical path is not an identity: $(cat "$T/sym.out")"
grep -q "changed between the evidence check and the write" "$T/sym.out" \
  || fail "R23: the abort does not say the resolution no longer applies: $(cat "$T/sym.out")"
[ "$(field "$SYM/.harness/state/tasks.json" "'landed' in d")" = "False" ] \
  || fail "R23: a record computed against the pre-swap checkout was written"

# CONTROL — the identical run with NO retarget must SUCCEED, so R23 is about the swap and
# not about holding the lock or about symlinked paths being unusable.
ln -sfn "$T/id-real" "$T/id-link"
symrun ""
[ "$(cat "$T/sym.rc")" = "0" ] || fail "R23 control: the same run without a retarget FAILED (rc=$(cat "$T/sym.rc")) — a symlinked manifest path must work: $(cat "$T/sym.out")"
[ "$(field "$SYM/.harness/state/tasks.json" "d['landed']['slices'][0]['verified']")" = "ancestor" ] \
  || fail "R23 control: the unswapped run did not verify through the symlink"
pass "E99-F102 R23 identity_is_the_realpath_not_the_spelling"

# ── R24: an unreachable `origin` makes a LOCAL base unconfirmable — row 9, not row 8 ──
# Round 2. A declared local default was treated as definitive even when an `origin` was
# configured but unreachable. But `_default_ref` only falls back to a local signal AFTER
# `ls-remote` fails, so in that state what "merged" means was never established: refusing
# there rejects work that is already on the remote's default branch. Measured: a commit
# that WAS on the remote's `main` was refused in an offline clone.
OFF="$T/offline"
mkdir -p "$OFF/hd/state" "$OFF/hd/store" "$OFF/hd/tools"
cp "$SCHEMA" "$OFF/hd/store/"; cp "$VALIDATE" "$OFF/hd/tools/"
( cd "$OFF" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$OFF/seed.txt"; ( cd "$OFF" && git_q add -A && git_q commit -m base )
( cd "$OFF" && : > merged.txt && git_q add -A && git_q commit -m "merged on the remote" )
OFF_MERGED="$(cd "$OFF" && git rev-parse HEAD)"
( cd "$OFF" && git_q checkout --detach HEAD~1 && git_q branch -f main HEAD && git_q checkout main )
( cd "$OFF" && git_q update-ref refs/evidence/merged "$OFF_MERGED" )
( cd "$OFF" && git_q config harness.defaultBranch main )
( cd "$OFF" && git merge-base --is-ancestor "$OFF_MERGED" main ) \
  && fail "R24 setup: the commit is already on the local main, so nothing would be refused"
mkboard "$OFF/hd"
# no origin yet: the local base IS the whole truth here, so the refusal is definitive (row 8)
set_status "$OFF/hd" E01-F01 done --evidence "$OFF_MERGED"
[ "$SS_RC" = "0" ] && fail "R24 baseline: with NO remote at all, a commit absent from the only branch must still be REFUSED (row 8): $SS_OUT"
# now configure an UNREACHABLE origin — the same local base can no longer be confirmed
( cd "$OFF" && git_q remote add origin "$T/not-a-real-remote.git" )
mkboard "$OFF/hd"
set_status "$OFF/hd" E01-F01 done --evidence "$OFF_MERGED"
[ "$SS_RC" = "0" ] || fail "R24: an `origin` is configured but unreachable, so the declared LOCAL base may not be what the remote calls its default — refusing there rejects work that is already merged (row 8 applied where row 9 belongs): $SS_OUT"
[ "$(field "$OFF/hd/state/tasks.json" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R24: expected unchecked when the base could not be confirmed, got $(field "$OFF/hd/state/tasks.json" "d['landed']['verified']")"
case "$SS_OUT" in
  *origin*) ;;
  *) fail "R24: the warning does not say WHY the base could not be confirmed: $SS_OUT" ;;
esac
pass "E99-F102 R24 an_unreachable_origin_makes_a_local_base_unconfirmable"

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
printf '%s\n' "$_done_sec" | grep -qi 'full decision table' \
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

# ── R20: the MANIFEST says where a repository is — rows 3 and 4 ───────────────────────
# Review round 5, P1. The predecessor located a slice's repository by scanning the harness
# dir's PARENT for a child directory whose basename equalled the manifest key. The shipped
# `umbrella.manifest.example.yaml` uses siblings (`../viernes-bff`) and nothing requires a
# key to equal its basename, so an ALIASED or relocated repository resolved NOWHERE — and a
# ref that never merged there was accepted as `unchecked`, reaching `done` with no ancestry
# check at all. The manifest is what says where a repository lives; that is what it is for.
#
# The fixture is deliberately the shape that broke: the key `alpha` maps to
# `../elsewhere/alpha-checkout`, which is NOT a child of the umbrella and does NOT share the
# key's name. Nothing here can pass by accident of directory layout.
M="$T/manifested"
ALPHA_AT="$T/elsewhere/alpha-checkout"     # a SIBLING of the umbrella, like the shipped example
mkdir -p "$M/.harness/state" "$M/.harness/store" "$M/.harness/tools" "$ALPHA_AT"
cp "$SCHEMA" "$M/.harness/store/"; cp "$VALIDATE" "$M/.harness/tools/"
( cd "$M" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$M/README.md"; ( cd "$M" && git_q add -A && git_q commit -m board )
( cd "$ALPHA_AT" && git init -q . && git symbolic-ref HEAD refs/heads/main )
: > "$ALPHA_AT/src.txt"
( cd "$ALPHA_AT" && git_q add -A && git_q commit -m "alpha landed" )
MA_MAIN="$(cd "$ALPHA_AT" && git rev-parse main)"
( cd "$ALPHA_AT" && git_q checkout --detach main && : > wip.txt && git_q add -A && git_q commit -m "never merged" )
MA_ORPHAN="$(cd "$ALPHA_AT" && git rev-parse HEAD)"
( cd "$ALPHA_AT" && git_q update-ref refs/evidence/wip "$MA_ORPHAN" && git_q checkout main )
[ -d "$M/alpha" ] && fail "R20 setup: an 'alpha' directory exists beside the board, so a basename scan could still find it and the alias would prove nothing"
[ -d "$M/elsewhere" ] && fail "R20 setup: the aliased repo must NOT be a child of the umbrella, or the fallback scan could reach it"
cat > "$M/.harness/harness.config.yaml" <<'EOF'
store:
  backend: local
umbrella:
  manifest: ../umbrella.manifest.yaml
EOF
mkmanifest() {  # mkmanifest [extra-repo-block]
  cat > "$M/umbrella.manifest.yaml" <<EOF
repos:
  alpha:
    path: ../elsewhere/alpha-checkout   # ALIASED: the key is not the directory name
    init: ./init.sh
    test_command: "true"
  ghost:
    path: ../nowhere-at-all             # declared, but not present in this checkout
    init: ./init.sh
    test_command: "true"${1:-}
EOF
}
mkmanifest
# `path:` is resolved against the MANIFEST's own directory. Assert the fixture agrees with
# that contract, so a mis-placed fixture fails as a SETUP error rather than masquerading as
# a wrong verdict — which is exactly how it first failed.
[ -d "$(cd "$M" && cd ../elsewhere/alpha-checkout 2>/dev/null && pwd)/.git" ] \
  || fail "R20 setup: '../elsewhere/alpha-checkout' relative to the manifest's dir is not the repository this case built"
HDM="$M/.harness"
BOARDM="$HDM/state/tasks.json"
mkslice() {  # mkslice <repo>
  cat > "$BOARDM" <<EOF
{ "project": "manifested", "epics": [ { "id": "E01", "title": "e", "status": "in-progress",
  "features": [ { "id": "E01-F01", "title": "f", "status": "in-review", "sdd": true,
    "spec_path": "s/",
    "slices": [ { "id": "E01-F01@$1", "repo": "$1", "status": "done", "merged": true } ] } ] } ] }
EOF
}

# ROW 7 THROUGH AN ALIAS — the fix. The predecessor recorded this `unchecked`.
mkslice alpha
set_status "$HDM" E01-F01 done --evidence "alpha=$MA_MAIN"
[ "$SS_RC" = "0" ] || fail "R20: a landed commit in an ALIASED manifest path was refused: $SS_OUT"
[ "$(field "$BOARDM" "d['landed']['slices'][0]['verified']")" = "ancestor" ] \
  || fail "R20: a repository reachable only through its manifest \`path\` was recorded $(field "$BOARDM" "d['landed']['slices'][0]['verified']") — the manifest is being ignored and the repo located by directory basename, so an aliased repo's UNMERGED work would sail through"
# CONTROL: the same aliased repository REFUSES an unmerged commit — so R20 is not passing
# because the alias made everything acceptable; ancestry is really being computed there.
mkslice alpha
BEFORE="$(cat "$BOARDM")"
set_status "$HDM" E01-F01 done --evidence "alpha=$MA_ORPHAN"
[ "$SS_RC" = "0" ] && fail "R20 control: an UNMERGED commit in the aliased repository was accepted: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDM")" ] || fail "R20 control: the board moved despite the refusal"

# ROW 3 — a repository the manifest does not declare is a MALFORMED CLAIM, and refused.
mkslice undeclared
BEFORE="$(cat "$BOARDM")"
set_status "$HDM" E01-F01 done --evidence "undeclared=$MA_MAIN"
[ "$SS_RC" = "0" ] && fail "R20 row 3: evidence bound to a repository the manifest does not declare was accepted — the claim is malformed and that IS checkable, with no I/O at all: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDM")" ] || fail "R20 row 3: the board moved despite the refusal"
case "$SS_OUT" in
  *manifest*) ;;
  *) fail "R20 row 3: the refusal does not tell the operator the manifest is what decides: $SS_OUT" ;;
esac
# CONTROL: declare it, and the SAME command succeeds — so row 3 is about the declaration,
# not about that repository being unusable. (It cannot be located, so it lands as row 4.)
mkmanifest '
  undeclared:
    path: ../nowhere-either
    init: ./init.sh
    test_command: "true"'
mkslice undeclared
set_status "$HDM" E01-F01 done --evidence "undeclared=$MA_MAIN"
[ "$SS_RC" = "0" ] || fail "R20 row 3 control: the same binding was still refused after the manifest declared the repository (rc=$SS_RC) — the refusal is not attributable to the declaration: $SS_OUT"
[ "$(field "$BOARDM" "d['landed']['slices'][0]['verified']")" = "unchecked" ] \
  || fail "R20 row 3 control: a declared-but-absent repository should degrade to unchecked, not claim $(field "$BOARDM" "d['landed']['slices'][0]['verified']")"
mkmanifest

# ROW 4 — declared, but not present in this checkout: "I cannot see it from here" is not
# the operator's fault, so it degrades. This is the pair that row 3 exists against.
mkslice ghost
set_status "$HDM" E01-F01 done --evidence "ghost=$MA_MAIN"
[ "$SS_RC" = "0" ] || fail "R20 row 4: a DECLARED repository that is simply absent here BLOCKED the write — that is this checkout's limitation, not a malformed claim: $SS_OUT"
[ "$(field "$BOARDM" "d['landed']['slices'][0]['verified']")" = "unchecked" ] \
  || fail "R20 row 4: expected unchecked for a declared-but-absent repository, got $(field "$BOARDM" "d['landed']['slices'][0]['verified']")"
case "$SS_OUT" in
  *declared*) ;;
  *) fail "R20 row 4: the warning does not distinguish 'declared but unreadable here' from 'not declared': $SS_OUT" ;;
esac

# NO MANIFEST ⇒ NO AUTHORITY. Row 3 must not fire on a board that never declared one:
# umbrella mode is off, so nothing can call the claim malformed and every miss degrades.
cat > "$HDM/harness.config.yaml" <<'EOF'
store:
  backend: local
umbrella:
  manifest: ""
EOF
mkslice undeclared
set_status "$HDM" E01-F01 done --evidence "undeclared=$MA_MAIN"
[ "$SS_RC" = "0" ] || fail "R20: with NO manifest configured, a slice repo that cannot be found was REFUSED — there is no authority to call the claim malformed, so it must degrade: $SS_OUT"
[ "$(field "$BOARDM" "d['landed']['slices'][0]['verified']")" = "unchecked" ] \
  || fail "R20: expected unchecked with no manifest, got $(field "$BOARDM" "d['landed']['slices'][0]['verified']")"
# BOTH readers of this file must agree. `tools/next-task.mjs` parses the manifest with its
# own JS reader and already halts on a slice naming a repository the manifest does not
# contain (`manifest-error`); tasks-lock now refuses the same board (row 3). Two parsers
# over one file is exactly where acceptance surfaces drift apart, so assert they agree —
# and in BOTH directions, or the assertion would hold against a selector that rejects every
# board.
cp "$SRC/tools/next-task.mjs" "$HDM/tools/next-task.mjs"
cat > "$HDM/harness.config.yaml" <<'EOF'
store:
  backend: local
workflow:
  require_approval: true
umbrella:
  manifest: ../umbrella.manifest.yaml
EOF
# Each tool checks the same FACT at its own moment: the selector when it dispatches slices
# (route builder + in-progress), tasks-lock when it records a landing. So drive each with
# the board state that reaches its check.
mkslice_at() {  # mkslice_at <repo> <status>
  cat > "$BOARDM" <<EOF
{ "project": "manifested", "epics": [ { "id": "E01", "title": "e", "status": "in-progress",
  "features": [ { "id": "E01-F01", "title": "f", "status": "$2", "sdd": true,
    "spec_path": "s/", "autonomous": true,
    "slices": [ { "id": "E01-F01@$1", "repo": "$1", "status": "in-progress" } ] } ] } ] }
EOF
}
mkslice_at undeclared in-progress
( cd "$HDM" && node tools/next-task.mjs --tasks "$BOARDM" --config "$HDM/harness.config.yaml" >"$T/nt.out" 2>&1 ) \
  && { head -3 "$T/nt.out" >&2; fail "R20 cross-check: the SELECTOR accepted a slice naming a repository the manifest does not declare, while tasks-lock refuses it — the two readers of one manifest disagree"; }
grep -q 'manifest' "$T/nt.out" \
  || fail "R20 cross-check: the selector rejected the board for some reason OTHER than the manifest: $(head -2 "$T/nt.out")"
mkslice_at alpha in-progress
( cd "$HDM" && node tools/next-task.mjs --tasks "$BOARDM" --config "$HDM/harness.config.yaml" >"$T/nt2.out" 2>&1 ) \
  || { head -3 "$T/nt2.out" >&2; fail "R20 cross-check control: the selector rejected a board whose slice repo IS declared, so the assertion above proves nothing"; }
pass "E99-F102 R20 the_manifest_locates_a_slice_repository_and_row3_refuses_row4_degrades"

# ── R21: git decides what an object id is — never a regex ─────────────────────────────
# Review round 5, P2. The predecessor gated resolution behind `^[0-9a-fA-F]{7,40}$`, which
# silently excluded SHA-256's 64-character ids: they fell through to "not a commit id" and
# were recorded unchecked, so an unmerged sha256 commit reached `done` unexamined. Nothing
# pattern-matches an object id now — every non-`none:` value is handed to
# `git rev-parse --verify <ref>^{commit}` and git decides.
#
# Two consequences handled deliberately: a BRANCH NAME resolves too, and a branch MOVES —
# so the record keeps `ref` (what was claimed, verbatim) AND `commit` (the immutable id it
# resolved to, which is what ancestry was computed on and what a re-audit must re-check).
mkrepo d
HDD="$T/repod/hd"
BOARDD="$HDD/state/tasks.json"
D_BASE="$BASE"; D_SIDE="$SIDE"
( cd "$T/repod" && git_q tag -a v1 -m "release" "$D_BASE" )
( cd "$T/repod" && git_q branch feature-x "$D_SIDE" )
[ "$(cd "$T/repod" && git for-each-ref --format='%(refname:short)' refs/heads/ | wc -l | tr -d ' ')" = "2" ] \
  || fail "R21 setup: expected exactly two local branches after adding feature-x"
( cd "$T/repod" && git_q config harness.defaultBranch main )

# a BRANCH name resolves, and what is RECORDED is both what was typed and what it resolved to
mkboard "$HDD"
set_status "$HDD" E01-F01 done --evidence "main"
[ "$SS_RC" = "0" ] || fail "R21: a branch name that git resolves was not accepted: $SS_OUT"
[ "$(field "$BOARDD" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R21: a branch name pointing at the default branch tip was recorded $(field "$BOARDD" "d['landed']['verified']")"
[ "$(field "$BOARDD" "d['landed']['ref']")" = "main" ] \
  || fail "R21: the ref was not recorded as the operator typed it"
[ "$(field "$BOARDD" "d['landed']['commit']")" = "$D_BASE" ] \
  || fail "R21: the record does not carry the IMMUTABLE id the branch resolved to — a branch moves, so a record naming only it decays into an attestation nobody can re-check"
# CONTROL: a branch whose tip never merged is REFUSED — resolution is not acceptance.
mkboard "$HDD"
BEFORE="$(cat "$BOARDD")"
set_status "$HDD" E01-F01 done --evidence "feature-x"
[ "$SS_RC" = "0" ] && fail "R21 control: a branch name resolving to an UNMERGED commit was accepted — git resolving a ref is not the same as the work having landed: $SS_OUT"
[ "$BEFORE" = "$(cat "$BOARDD")" ] || fail "R21 control: the board moved despite the refusal"

# an annotated TAG peels to its commit (`^{commit}`), so tags work without special-casing
mkboard "$HDD"
set_status "$HDD" E01-F01 done --evidence "v1"
[ "$SS_RC" = "0" ] || fail "R21: an annotated tag was not resolved: $SS_OUT"
[ "$(field "$BOARDD" "d['landed']['commit']")" = "$D_BASE" ] \
  || fail "R21: the annotated tag did not peel to its commit"

# SHA-256: the exact id width the regex excluded. A real sha256 repository, not a synthetic
# 64-char string — the point is that git resolves it and the harness never inspects its shape.
if ( cd "$T" && git init -q --object-format=sha256 sha256repo ) >/dev/null 2>&1; then
  mkdir -p "$T/sha256repo/hd/state" "$T/sha256repo/hd/store" "$T/sha256repo/hd/tools"
  cp "$SCHEMA" "$T/sha256repo/hd/store/"; cp "$VALIDATE" "$T/sha256repo/hd/tools/"
  ( cd "$T/sha256repo" && git symbolic-ref HEAD refs/heads/main )
  : > "$T/sha256repo/seed.txt"; ( cd "$T/sha256repo" && git_q add -A && git_q commit -m base )
  S256_BASE="$(cd "$T/sha256repo" && git rev-parse HEAD)"
  ( cd "$T/sha256repo" && git_q checkout --detach main && : > side.txt && git_q add -A && git_q commit -m side )
  S256_SIDE="$(cd "$T/sha256repo" && git rev-parse HEAD)"
  ( cd "$T/sha256repo" && git_q update-ref refs/evidence/side "$S256_SIDE" && git_q checkout main )
  [ "$(printf '%s' "$S256_BASE" | wc -c | tr -d ' ')" = "64" ] \
    || fail "R21 setup: the sha256 fixture did not produce 64-character ids"
  HD256="$T/sha256repo/hd"
  mkboard "$HD256"
  set_status "$HD256" E01-F01 done --evidence "$S256_BASE"
  [ "$SS_RC" = "0" ] || fail "R21 sha256: a 64-character commit id was refused: $SS_OUT"
  [ "$(field "$HD256/state/tasks.json" "d['landed']['verified']")" = "ancestor" ] \
    || fail "R21 sha256: a 64-character commit id on the default branch was recorded $(field "$HD256/state/tasks.json" "d['landed']['verified']") — this is the id width the 40-hex regex silently skipped, so an UNMERGED sha256 commit would reach done unexamined"
  # CONTROL: the unmerged sha256 commit is REFUSED — the width is not what decides.
  mkboard "$HD256"
  BEFORE="$(cat "$HD256/state/tasks.json")"
  set_status "$HD256" E01-F01 done --evidence "$S256_SIDE"
  [ "$SS_RC" = "0" ] && fail "R21 sha256 control: an unmerged 64-character commit id was accepted: $SS_OUT"
  [ "$BEFORE" = "$(cat "$HD256/state/tasks.json")" ] || fail "R21 sha256 control: the board moved despite the refusal"
else
  echo "note - R21: this git cannot create SHA-256 repositories; the 64-char case was NOT exercised" >&2
fi
pass "E99-F102 R21 git_resolves_the_ref_and_the_record_names_the_immutable_id"

# ── R25: an `ancestor` names the FULL proof set, on all three surfaces ────────────────
# Review round 5. `commit` was required wherever `verified` is `ancestor`; `repo` and `base`
# were not. MEASURED on the shipped validators, with an otherwise-valid board:
#
#   {"ref":"x","commit":"deadbeef","verified":"ancestor"}                            ACCEPTED
#   {"ref":"x","verified":"ancestor"}                                                rejected
#   {"ref":"x","commit":"deadbeef","repo":"r","base":"origin/main",...:"ancestor"}   ACCEPTED
#
# The first line is the defect. `deadbeef` alone is an id with no repository to look it up
# in and no second operand to be an ancestor OF, so `git merge-base --is-ancestor` cannot be
# re-run on it by anyone — and this feature's whole thesis is that an attestation nobody can
# re-check is the defect, not a weaker form of a proof. A proof therefore names all three:
# WHAT was checked (`commit` — `ref` may be a branch, which moves), WHERE (`repo`), and
# AGAINST WHAT (`base`).
#
# Every case runs against ALL THREE acceptance surfaces, because a board one accepts and
# another refuses is the drift these mirrors exist to prevent — and the schema and the
# fallback are DIFFERENT CODE, so a rule added to one is not a rule.
#
# The refusals are asserted PER KEY and the message is grepped for that key. "the board was
# rejected" is producible by any validation error at all, including one this fixture
# introduced by accident, and an assertion satisfiable by a path other than the one its
# message names is worse than no assertion — it stops the next maintainer looking.

# refuse3 <label> <landed-json> <missing-key> — refused by schema, fallback AND selector.
refuse3() {
  _lbl="$1"; _json="$2"; _key="$3"
  mkbad "$_json"
  _o="$(python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" 2>&1)" \
    && fail "R25: the SCHEMA path ACCEPTED $_lbl — a proof naming no $_key cannot be re-checked: $_json"
  case "$_o" in *"$_key"*) ;; *) fail "R25: the schema path rejected $_lbl, but not over the missing '$_key' — the case passes for the wrong reason: $_o" ;; esac
  _o="$(python3 "$T/nojs.py" 2>&1)" \
    && fail "R25: the ZERO-DEPENDENCY validator ACCEPTED $_lbl — a machine without jsonschema would take a board the schema refuses: $_json"
  case "$_o" in *"$_key"*) ;; *) fail "R25: the fallback rejected $_lbl, but not over the missing '$_key': $_o" ;; esac
  _o="$( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" 2>&1 )" \
    && fail "R25: the SELECTOR ACCEPTED $_lbl — a board arriving through --tasks never passes the shared validator: $_json"
  case "$_o" in *"$_key"*) ;; *) fail "R25: the selector rejected $_lbl, but not over the missing '$_key': $_o" ;; esac
}

# accept3 <label> <landed-json> — accepted by all three. The control against over-reach.
accept3() {
  _lbl="$1"; _json="$2"
  mkbad "$_json"
  python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
    || fail "R25 control: the SCHEMA path rejected $_lbl — the new requirement has over-reached: $(python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" 2>&1 | head -3)"
  python3 "$T/nojs.py" >/dev/null 2>&1 \
    || fail "R25 control: the ZERO-DEPENDENCY validator rejected $_lbl: $(python3 "$T/nojs.py" 2>&1 | head -3)"
  ( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
    || fail "R25 control: the SELECTOR rejected $_lbl: $( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" 2>&1 | head -3 )"
}

# (a) the Codex case, verbatim: a proof that names NEITHER the repository NOR the base.
refuse3 "a proofless ancestor (no repo, no base)" \
  '{ "ref": "x", "commit": "deadbeef", "verified": "ancestor" }' repo
# ...and each half of it alone, so the rule is not satisfiable by supplying only one.
refuse3 "an ancestor naming no repository" \
  '{ "ref": "x", "commit": "deadbeef", "base": "origin/main", "verified": "ancestor" }' repo
refuse3 "an ancestor naming no base" \
  '{ "ref": "x", "commit": "deadbeef", "repo": "r", "verified": "ancestor" }' base
refuse3 "an ancestor naming no commit" \
  '{ "ref": "x", "repo": "r", "base": "origin/main", "verified": "ancestor" }' commit

# CONTROL: the FULLY-PROVED record is still accepted everywhere. Without it the four
# refusals above would hold just as well against a validator that rejects every `ancestor`.
accept3 "a fully-proved ancestor" \
  '{ "ref": "x", "commit": "deadbeef", "repo": "r", "base": "origin/main", "verified": "ancestor" }'
# CONTROL: the weaker verdicts are untouched — `unchecked`/`declared` never claimed a proof,
# so they owe none. A rule that also demanded repo/base of them would refuse rows 1-6 and 9
# of the decision table, i.e. every degraded record the write path produces.
accept3 "an unchecked record with no repo or base" '{ "ref": "x", "verified": "unchecked" }'
accept3 "a declared record with no repo or base" '{ "ref": "none:console", "verified": "declared" }'

# (b) the PER-SLICE records carry the same set. `repo` is already required of every slice
# record, proved or not, so what was missing there is `base`.
refuse3 "a slice-level ancestor naming no base" \
  '{ "ref": "web=b", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "commit": "c0ffee", "verified": "ancestor" } ] }' base
refuse3 "a slice-level ancestor naming no commit" \
  '{ "ref": "web=b", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "base": "main", "verified": "ancestor" } ] }' commit
accept3 "a fully-proved slice-level ancestor" \
  '{ "ref": "web=b", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "commit": "c0ffee", "base": "main", "verified": "ancestor" } ] }'

# (c) THE CARVE-OUT, and the control that stops this fix over-reaching. A SLICED feature's
# feature-level `ref` is a JOINED SUMMARY across repositories — there is no single commit,
# repository or base for it, and each slice carries its own — so the feature-level record
# must still validate with none of the three. The schema `$comment` says exactly this, and
# it is still true; requiring them there would make every sliced `done` the tool writes
# unvalidatable. Asserted with the rollup at its STRONGEST (`ancestor`), which is the only
# case in which the requirement could have been applied by mistake.
accept3 "a SLICED feature-level ancestor with no commit/repo/base of its own" \
  '{ "ref": "web=b; api=c", "verified": "ancestor", "slices": [ { "repo": "web", "ref": "b", "commit": "c0ffee", "base": "main", "verified": "ancestor" }, { "repo": "api", "ref": "c", "commit": "dec0de", "base": "main", "verified": "ancestor" } ] }'

# (d) THE RECORD THE WRITE PATH ACTUALLY PRODUCES still validates — measured, not assumed.
# A schema stricter than its own tool's output is the worst outcome available here: every
# future `done` would write a board that fails its own validation, and the failure would
# surface at the atomic replace, long after the operator believed the record was accepted.
# So a REAL `set-status ... done --evidence` is run and its board is put through all three.
mkrepo r25
HD25="$T/repor25/hd"
BOARD25="$HD25/state/tasks.json"
R25_BASE="$BASE"
mkboard "$HD25"
set_status "$HD25" E01-F01 done --evidence "$R25_BASE"
[ "$SS_RC" = "0" ] || fail "R25: the write path could not record a REAL ancestor landing (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARD25" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R25: the fixture did not produce an 'ancestor' record, so it cannot test the rule: $(field "$BOARD25" "d['landed']")"
cp "$BOARD25" "$T/bad.json"
python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R25: the SCHEMA rejects the record tasks-lock itself writes — every future \`done\` would fail its own validation: $(python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" 2>&1 | head -3)"
python3 "$T/nojs.py" >/dev/null 2>&1 \
  || fail "R25: the ZERO-DEPENDENCY validator rejects the record tasks-lock itself writes: $(python3 "$T/nojs.py" 2>&1 | head -3)"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || fail "R25: the SELECTOR rejects the record tasks-lock itself writes: $( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" 2>&1 | head -3 )"

# ...and the SLICED write path too, which produces the other record shape entirely (a joined
# `ref`, no feature-level commit/repo/base, one proved entry per slice repository).
mkboard "$HD25" ',
          "slices": [
            { "id": "E01-F01@repor25", "repo": "repor25", "status": "done", "merged": true }
          ]'
set_status "$HD25" E01-F01 done --evidence "repor25=$R25_BASE"
[ "$SS_RC" = "0" ] || fail "R25: the SLICED write path could not record a real landing (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARD25" "d['landed']['slices'][0]['verified']")" = "ancestor" ] \
  || fail "R25: the sliced fixture did not produce a proved slice record: $(field "$BOARD25" "d['landed']")"
[ -n "$(field "$BOARD25" "d['landed']['slices'][0].get('base','')")" ] \
  || fail "R25: the write path emits a proved slice record with NO base, so the schema requirement is stricter than the tool's own output"
cp "$BOARD25" "$T/bad.json"
python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" >/dev/null 2>&1 \
  || fail "R25: the SCHEMA rejects the SLICED record tasks-lock itself writes: $(python3 "$VALIDATE" "$T/bad.json" "$SCHEMA" 2>&1 | head -3)"
python3 "$T/nojs.py" >/dev/null 2>&1 \
  || fail "R25: the ZERO-DEPENDENCY validator rejects the SLICED record tasks-lock itself writes: $(python3 "$T/nojs.py" 2>&1 | head -3)"
( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" >/dev/null 2>&1 ) \
  || fail "R25: the SELECTOR rejects the SLICED record tasks-lock itself writes: $( cd "$SRC" && node tools/next-task.mjs --tasks "$T/bad.json" --config "$T/config.yaml" 2>&1 | head -3 )"
pass "E99-F102 R25 an_ancestor_names_the_full_proof_set_on_all_three_surfaces"


# ── R26: an ACCEPT against an UNCONFIRMED base is not a proof (round 6, P1) ───────────
# The predecessor confirmed the tip only on the REFUSAL side, on the stated grounds that
# "for a stale local tip to produce a wrong `ancestor` the remote would have to have been
# REWRITTEN". That is false, and the counter-example is ordinary rather than adversarial:
# a project RENAMES its default branch and leaves the old one in place. The cached
# `refs/remotes/origin/HEAD` still names the old branch, work merged only there is
# trivially reachable from it, and `done` is recorded for a feature that never landed on
# the current default. No force-push, no adversary — just a rename.
T="$(mktemp -d)"
( cd "$T" && git init -q --bare renamed.git )
mkdir -p "$T/work"
( cd "$T/work" && git init -q . && git symbolic-ref HEAD refs/heads/main \
    && : > seed.txt && git_q add -A && git_q commit -m base \
    && git_q remote add origin "$T/renamed.git" && git_q push -q origin main )
# The OLD default branch diverges from that shared base and gets work of its own.
( cd "$T/work" && git_q checkout -q -b master && : > a.txt && git_q add -A \
    && git_q commit -m "on the OLD default branch" && git_q push -q origin master )
OLD_ONLY="$(cd "$T/work" && git rev-parse HEAD)"
# The project migrates: `main` is the default now, and `master` is LEFT IN PLACE.
( cd "$T/work" && git_q checkout -q main && : > b.txt && git_q add -A \
    && git_q commit -m "the real default branch moves on" && git_q push -q origin main )
( cd "$T/renamed.git" && git symbolic-ref HEAD refs/heads/main )
# A clone whose cached origin/HEAD still points at the OLD default, and which cannot
# reach the remote to learn otherwise.
( cd "$T" && git clone -q "$T/renamed.git" stale )
HDR="$T/stale/hd"; BOARDR="$HDR/state/tasks.json"
mkdir -p "$HDR/state" "$HDR/store" "$HDR/tools"
cp "$SCHEMA" "$HDR/store/"; cp "$VALIDATE" "$HDR/tools/"
( cd "$T/stale" && git_q fetch -q origin && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master )
( cd "$T/stale" && git_q remote set-url origin "$T/gone.git" )
( cd "$T/stale" && git merge-base --is-ancestor "$OLD_ONLY" refs/remotes/origin/master ) \
  || fail "R26 setup: the commit is not reachable from the stale cached default — the fixture proves nothing"
( cd "$T/stale" && git merge-base --is-ancestor "$OLD_ONLY" refs/remotes/origin/main ) \
  && fail "R26 setup: the commit IS on the real default branch — the fixture proves nothing"
mkboard "$HDR"
set_status "$HDR" E01-F01 done --evidence "$OLD_ONLY"
[ "$SS_RC" = "0" ] \
  || fail "R26: an unconfirmable base BLOCKED the write (rc=$SS_RC) — inability to confirm must degrade, never refuse: $SS_OUT"
[ "$(field "$BOARDR" "d['landed']['verified']")" = "unchecked" ] \
  || fail "R26: recorded '$(field "$BOARDR" "d['landed']['verified']")' for a commit reachable ONLY from a cached, unconfirmed default branch — reachability from a branch that may no longer BE the default proves nothing about where the work landed"
case "$SS_OUT" in
  *"cannot confirm"*) ;;
  *) fail "R26: the warning does not say the default branch could not be confirmed: $SS_OUT" ;;
esac
# CONTROL — with the remote REACHABLE, the same repository answers definitively in both
# directions, so R26 is about confirmability and not about the fixture being broken.
( cd "$T/stale" && git_q remote set-url origin "$T/renamed.git" )
mkboard "$HDR"
set_status "$HDR" E01-F01 done --evidence "$OLD_ONLY"
[ "$SS_RC" = "0" ] && fail "R26 control: a commit absent from the REAL default was accepted once the remote was reachable: $SS_OUT"
REAL_TIP="$(cd "$T/work" && git rev-parse main)"
mkboard "$HDR"
set_status "$HDR" E01-F01 done --evidence "$REAL_TIP"
[ "$SS_RC" = "0" ] || fail "R26 control: a commit ON the real default was refused (rc=$SS_RC): $SS_OUT"
[ "$(field "$BOARDR" "d['landed']['verified']")" = "ancestor" ] \
  || fail "R26 control: a commit on the confirmed default is not 'ancestor'"
rm -rf "$T"
pass "E99-F102 R26 an_accept_against_an_unconfirmed_base_is_not_a_proof"

echo "All landing-evidence tests passed."
