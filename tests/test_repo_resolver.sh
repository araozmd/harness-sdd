#!/bin/sh
# test_repo_resolver.sh — E99-F129c: WHICH repository is a claim about?
#
# `tools/repo-resolve.py` answers one question and nothing else: given a ref, an optional
# `<repo>=<ref>` binding and an optional manifest, which repository is this about, what is
# that repository's identity, what is its default branch, and how sure are we of each. It
# runs no ancestry check and writes no board, so this suite asserts a RESOLVER contract,
# not a verdict.
#
# Every case pairs the answer under test with a control that must come out DIFFERENTLY on
# the same fixture — "the resolver returned uncertainty" is the easy outcome to produce, and
# a suite without the pairing would pass against a resolver that is uncertain about
# everything.
#
#   C1 a BINDING names the repository; there is no search to be ambiguous about
#   C2 an unbound ref that resolves in several repositories is AMBIGUOUS, not "the first";
#      two worktrees of ONE repository are not an ambiguity
#   C3 the MANIFEST locates a repository — an aliased path is followed, an undeclared repo
#      is UNDECLARED and a declared-but-absent one is UNLOCATABLE (two different answers)
#   C4 identity is the realpath beside the lexical path, and `revalidate` sees a symlink
#      retarget that leaves the text identical
#   C5 the default branch, and HOW we know: a fresh `ls-remote` beats the stale
#      `origin/HEAD` CACHE, and `base_confirmed` is false for every unconfirmable source
#   C6 uncertainty is a VALUE: reading a repository or a base that was never resolved
#      raises, so "I could not tell" cannot be spent as "yes"
#   C7 the witness comes back WITH the resolution, so no call path can omit it
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-resolver)"
_FAILED=""
_cleanup() {
  _rc=$?
  rm -rf "$T"
  if [ "$_rc" -ne 0 ] && [ -z "$_FAILED" ]; then
    echo "FAIL: the suite ABORTED at a fixture step (set -e), not at an assertion —" >&2
    echo "      commonly a git fixture whose branch was ASSUMED rather than set." >&2
  fi
  exit "$_rc"
}
trap _cleanup EXIT
fail() { _FAILED=1; echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v git >/dev/null 2>&1 || fail "git is absent"
command -v python3 >/dev/null 2>&1 || fail "python3 is absent"

# Hermetic fixtures: no fixture may inherit the host's default branch. A suite that depends
# on the developer's git config is a suite whose green means "on this machine".
FIXTURE_BRANCH_SENTINEL="fixture-forgot-to-set-head"
GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=init.defaultBranch
GIT_CONFIG_VALUE_0="$FIXTURE_BRANCH_SENTINEL"
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
( cd "$T" && git init -q sentinel-probe )
[ "$(cd "$T/sentinel-probe" && git symbolic-ref HEAD)" = "refs/heads/$FIXTURE_BRANCH_SENTINEL" ] \
  || fail "the init.defaultBranch override did not take effect (GIT_CONFIG_* needs git >= 2.31) — every fixture below would inherit the host's default branch"
rm -rf "$T/sentinel-probe"

git_q() { git -c user.email=t@example.com -c user.name=tester "$@" >/dev/null 2>&1; }
mkrepo() {  # mkrepo <dir> [branch]
  mkdir -p "$1"
  ( cd "$1" && git init -q . && git symbolic-ref HEAD "refs/heads/${2:-main}" )
  : > "$1/src.txt"
  ( cd "$1" && git_q add -A && git_q commit -m "work in $(basename "$1")" )
}
mkbare() {  # mkbare <dir> [branch] — HEAD is explicit, then asserted
  _b="${2:-main}"
  ( cd "$T" && git init -q --bare "$1" )
  ( cd "$T/$1" && git symbolic-ref HEAD "refs/heads/$_b" )
  [ "$(cd "$T/$1" && git symbolic-ref HEAD)" = "refs/heads/$_b" ] \
    || fail "fixture $1: the bare remote does not publish refs/heads/$_b"
}

# A heredoc inside `$( ... )` is a parsing trap in POSIX sh, so the driver is a FILE that
# `ask` invokes with arguments: ask <ref> <repo|-> <hdir> <expression over `r`>.
cat > "$T/ask.py" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location(
    "rr", os.path.join(os.environ["SRC"], "tools/repo-resolve.py"))
rr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rr)
ref, repo, hdir, expr = sys.argv[1:5]
r = rr.resolve(ref, None if repo == "-" else repo, hdir)
print(eval(expr))
PY
export SRC
ask() {
  ASK_OUT="$(python3 "$T/ask.py" "$1" "$2" "$3" "$4" 2>&1)" && ASK_RC=0 || ASK_RC=$?
}

# ── the umbrella fixture: a board repo, a child, and an aliased sibling ───────────────
U="$T/umb"
mkdir -p "$U/.harness"
mkrepo "$U"                      # the harness dir's own repository (searched FIRST)
UMB_MAIN="$(cd "$U" && git rev-parse main)"
mkrepo "$U/child"
CHILD_MAIN="$(cd "$U/child" && git rev-parse main)"
mkrepo "$T/aliased-elsewhere"
ALIAS_MAIN="$(cd "$T/aliased-elsewhere" && git rev-parse main)"
HD="$U/.harness"
[ "$UMB_MAIN" = "$CHILD_MAIN" ] && fail "setup: the umbrella and the child share a commit id"

# ── C1: a binding names the repository ────────────────────────────────────────────────
ask "$CHILD_MAIN" child "$HD" "r.outcome"
[ "$ASK_OUT" = "resolved" ] || fail "C1: a bound claim did not resolve: $ASK_OUT"
ask "$CHILD_MAIN" child "$HD" "os.path.basename(os.path.realpath(r.directory))"
[ "$ASK_OUT" = "child" ] || fail "C1: the binding did not select the repository it names (got $ASK_OUT)"
# CONTROL: the SAME binding with a ref that repository has never seen is UNKNOWN, not
# resolved — a binding says where to look, never that the thing was found.
ask "$UMB_MAIN" child "$HD" "r.outcome"
[ "$ASK_OUT" = "unknown" ] || fail "C1 control: a bound ref absent from that repository returned $ASK_OUT, so the binding is being treated as an answer rather than a place to look"
pass "E99-F129c C1 a_binding_names_the_repository"

# ── C2: ambiguity is an outcome, never "the first candidate" ──────────────────────────
# `main` exists in the harness dir's OWN repository and in the child. The search order puts
# the harness dir first, so "take the first" is at its most wrong here.
ask "main" - "$HD" "r.outcome"
[ "$ASK_OUT" = "ambiguous" ] || fail "C2: an unbound ref resolving in several repositories returned $ASK_OUT — taking the first would attest the harness dir's own bookkeeping repository"
ask "main" - "$HD" "r.detail"
case "$ASK_OUT" in
  *"resolves in"*) ;;
  *) fail "C2: the ambiguous outcome does not say what is ambiguous: $ASK_OUT" ;;
esac
# CONTROL 1: an UNAMBIGUOUS ref on the same fixture resolves — so C2 is about ambiguity,
# not about the resolver refusing every unbound ref.
ask "$CHILD_MAIN" - "$HD" "r.outcome + ' ' + os.path.basename(os.path.realpath(r.directory))"
[ "$ASK_OUT" = "resolved child" ] || fail "C2 control-1: an unambiguous commit id did not resolve to its own repository (got $ASK_OUT)"
# CONTROL 2: two linked worktrees of ONE repository are one repository, not an ambiguity.
( cd "$U/child" && git_q worktree add "$U/child-wt" -b wt-branch )
[ -e "$U/child-wt/.git" ] || fail "C2 setup: the linked worktree was not created"
ask "$CHILD_MAIN" - "$HD" "r.outcome"
[ "$ASK_OUT" = "resolved" ] || fail "C2 control-2: a commit visible through a repository AND its own linked worktree returned $ASK_OUT — two directories, one repository"
( cd "$U/child" && git_q worktree remove --force "$U/child-wt" )
# `worktree remove` leaves the branch it created behind, which would silently give `child`
# a SECOND branch and change what C5 measures three cases later. Remove it and assert.
( cd "$U/child" && git_q branch -D wt-branch )
[ "$(cd "$U/child" && git for-each-ref --format='%(refname:short)' refs/heads/ | wc -l | tr -d ' ')" = "1" ] \
  || fail "C2 cleanup: the child repository is left with more than one branch, which would change what later cases measure"
pass "E99-F129c C2 ambiguity_is_an_outcome_not_the_first_candidate"

# ── C3: the manifest locates a repository, and says so in two different ways ──────────
cat > "$HD/harness.config.yaml" <<'EOF'
store:
  backend: local
umbrella:
  manifest: ../umbrella.manifest.yaml
EOF
cat > "$U/umbrella.manifest.yaml" <<'EOF'
repos:
  alpha:
    path: ../aliased-elsewhere      # the key is NOT the directory name
    init: ./init.sh
    test_command: "true"
  ghost:
    path: ../nowhere-at-all
    init: ./init.sh
    test_command: "true"
EOF
[ -d "$U/alpha" ] && fail "C3 setup: an 'alpha' directory exists beside the board, so a basename scan could still find it"
ask "$ALIAS_MAIN" alpha "$HD" "r.outcome + ' ' + os.path.basename(os.path.realpath(r.directory))"
[ "$ASK_OUT" = "resolved aliased-elsewhere" ] || fail "C3: a repository reachable ONLY through its manifest \`path\` did not resolve (got $ASK_OUT) — the manifest is being ignored and the repo located by basename"
# The two failure modes are DIFFERENT answers, which is the whole point of the pair.
ask "$ALIAS_MAIN" undeclared "$HD" "r.outcome"
[ "$ASK_OUT" = "undeclared" ] || fail "C3: a repository the manifest does not contain returned $ASK_OUT, not 'undeclared' — a malformed claim and an unreadable checkout must not be the same answer"
ask "$ALIAS_MAIN" ghost "$HD" "r.outcome"
[ "$ASK_OUT" = "unlocatable" ] || fail "C3: a DECLARED but absent repository returned $ASK_OUT, not 'unlocatable'"
# CONTROL: with no manifest configured there is no authority, so nothing is 'undeclared'.
mv "$U/umbrella.manifest.yaml" "$U/manifest.parked"
ask "$ALIAS_MAIN" undeclared "$HD" "r.outcome"
[ "$ASK_OUT" = "unlocatable" ] || fail "C3 control: with NO manifest the resolver still called a claim malformed ($ASK_OUT) — with no authority it can only say it cannot see the repository"
mv "$U/manifest.parked" "$U/umbrella.manifest.yaml"
pass "E99-F129c C3 the_manifest_locates_a_repository"

# ── C4: identity is the realpath, and revalidate sees a retarget ──────────────────────
ln -sfn "$T/aliased-elsewhere" "$T/alpha-link"
cat > "$U/umbrella.manifest.yaml" <<'EOF'
repos:
  alpha:
    path: ../alpha-link
    init: ./init.sh
    test_command: "true"
EOF
mkrepo "$T/decoy-elsewhere"
RES_REF="$ALIAS_MAIN" RES_REPO=alpha RES_HDIR="$HD" python3 - <<'PY' > "$T/c4.out" 2>&1 || fail "C4: the probe failed: $(cat "$T/c4.out")"
import importlib.util, os
spec = importlib.util.spec_from_file_location("rr", os.path.join(os.environ["SRC"], "tools/repo-resolve.py"))
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
hd = os.environ["RES_HDIR"]
r = rr.resolve(os.environ["RES_REF"], "alpha", hd)
print("outcome", r.outcome)
print("before", rr.revalidate(r, hd)[0])
link = os.path.join(os.path.dirname(os.path.dirname(hd)), "alpha-link")
os.remove(link); os.symlink(os.path.join(os.path.dirname(link), "decoy-elsewhere"), link)
print("after", rr.revalidate(r, hd)[0])
PY
grep -q "^outcome resolved" "$T/c4.out" || fail "C4: the symlinked manifest path did not resolve: $(cat "$T/c4.out")"
grep -q "^before True" "$T/c4.out" || fail "C4 control: a resolution failed to revalidate against an UNCHANGED world — every 'False' below would then be meaningless: $(cat "$T/c4.out")"
grep -q "^after False" "$T/c4.out" || fail "C4: retargeting the symlink left the resolution valid — the identity is the lexical path, which reads identically before and after: $(cat "$T/c4.out")"
ln -sfn "$T/aliased-elsewhere" "$T/alpha-link"
pass "E99-F129c C4 identity_is_the_realpath_not_the_spelling"

# ── C5: the default branch, and how sure we are ───────────────────────────────────────
# A remote that MOVES its default while the old branch still exists leaves
# refs/remotes/origin/HEAD pointing at the former one. Trusting that cache attested a
# commit reachable only from the OLD default as being on the default branch.
mkbare cacheremote.git main
CR="$T/cacheclone"
mkrepo "$CR"
( cd "$CR" && git_q remote add origin "$T/cacheremote.git" && git_q push origin main )
( cd "$CR" && git_q remote set-head origin --auto )              # caches origin/HEAD -> main
[ "$(cd "$CR" && git symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/main" ] \
  || fail "C5 setup: origin/HEAD was not cached, so there is no stale cache to be fooled by"
( cd "$CR" && : > later.txt && git_q add -A && git_q commit -m "only on the old default" && git_q push origin main )
OLD_ONLY="$(cd "$CR" && git rev-parse main)"
( cd "$CR" && git_q branch trunk "$OLD_ONLY~1" && git_q push origin trunk )
( cd "$T/cacheremote.git" && git symbolic-ref HEAD refs/heads/trunk )   # the remote MOVES
( cd "$CR" && git_q fetch origin )
[ "$(cd "$CR" && git symbolic-ref refs/remotes/origin/HEAD)" = "refs/remotes/origin/main" ] \
  || fail "C5 setup: the cached symref followed the remote, so it is not stale and proves nothing"
mkdir -p "$CR/.harness"
ask "$OLD_ONLY" - "$CR/.harness" "r.base + ' ' + r.base_evidence"
[ "$ASK_OUT" = "origin/trunk published" ] \
  || fail "C5: the resolver answered '$ASK_OUT' — refs/remotes/origin/HEAD is a CACHE of a FORMER answer, and a reachable remote must be asked rather than believed"
ask "$OLD_ONLY" - "$CR/.harness" "str(r.base_confirmed)"
[ "$ASK_OUT" = "True" ] || fail "C5: a base the remote published just now is not marked confirmed"
# CONTROL: make the remote UNREACHABLE. The cache is all that is left, so the resolver must
# still answer — but must mark the answer UNCONFIRMED rather than silently trusting it.
( cd "$CR" && git_q remote set-url origin "$T/gone.git" )
ask "$OLD_ONLY" - "$CR/.harness" "r.base + ' ' + r.base_evidence + ' ' + str(r.base_confirmed)"
[ "$ASK_OUT" = "origin/main cached False" ] \
  || fail "C5 control: with the remote unreachable the resolver answered '$ASK_OUT' — it must fall back to the cache AND mark it unconfirmed, so a caller cannot refuse on a stale view"
# CONTROL: a repository with no remote at all — its sole branch IS the default, confirmed.
# Asked UNBOUND on purpose: C4 rewrote the manifest to declare only `alpha`, so a binding
# to `child` would (correctly) come back `undeclared` and this control would be measuring
# the manifest rather than the base.
ask "$CHILD_MAIN" - "$HD" "r.base + ' ' + r.base_evidence + ' ' + str(r.base_confirmed)"
[ "$ASK_OUT" = "main sole-branch True" ] \
  || fail "C5 control: a remoteless single-branch repository answered '$ASK_OUT' — with no remote to disagree, its only branch is confirmed"
pass "E99-F129c C5 the_default_branch_carries_its_own_evidence"

# ── C6: uncertainty is a value you cannot spend ───────────────────────────────────────
ask "main" - "$HD" "'raised' if not r.certain else 'readable'"
[ "$ASK_OUT" = "raised" ] || fail "C6: an ambiguous resolution reports itself as certain"
RES_HDIR="$HD" python3 - <<'PY' > "$T/c6.out" 2>&1
import importlib.util, os
spec = importlib.util.spec_from_file_location("rr", os.path.join(os.environ["SRC"], "tools/repo-resolve.py"))
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
r = rr.resolve("main", None, os.environ["RES_HDIR"])
try:
    r.directory
    print("directory: READABLE")
except rr.Uncertain:
    print("directory: raised")
r2 = rr.resolve("nonesuch", "child", os.environ["RES_HDIR"])
try:
    r2.base
    print("base: READABLE")
except rr.Uncertain:
    print("base: raised")
PY
grep -q "^directory: raised" "$T/c6.out" || fail "C6: a caller could read a repository off a resolution that never found one — 'I could not tell' must not be spendable as 'yes': $(cat "$T/c6.out")"
grep -q "^base: raised" "$T/c6.out" || fail "C6: a caller could read a base that was never determined: $(cat "$T/c6.out")"
pass "E99-F129c C6 uncertainty_is_a_value_you_cannot_spend"

# ── C7: the witness comes back WITH the resolution ────────────────────────────────────
# The defect this closes structurally: a witness assembled beside a resolution can be
# forgotten by the next call path — and was, by the very path added to fix an earlier
# identity defect. A witness that IS the resolution's own value cannot be.
ask "$ALIAS_MAIN" alpha "$HD" "str(r.witness()[3])"
[ "$ASK_OUT" = "present" ] \
  || fail "C7: a BOUND resolution's witness does not carry the manifest state (got $ASK_OUT) — this is the omission that let a bound claim skip the manifest fingerprint entirely"
ask "$CHILD_MAIN" - "$HD" "str(len(r.witness()[4]) > 0)"
[ "$ASK_OUT" = "True" ] \
  || fail "C7: an UNBOUND resolution's witness does not carry the candidate set that made the choice unambiguous"
# CONTROL: the witness actually DISCRIMINATES — two different resolutions must not share
# a witness, or comparing them would detect nothing.
ALIAS="$ALIAS_MAIN" CHILD="$CHILD_MAIN" RES_HDIR="$HD" python3 - <<'PY' > "$T/c7.out" 2>&1
import importlib.util, os
spec = importlib.util.spec_from_file_location("rr", os.path.join(os.environ["SRC"], "tools/repo-resolve.py"))
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
hd = os.environ["RES_HDIR"]
a = rr.resolve(os.environ["ALIAS"], "alpha", hd)
b = rr.resolve(os.environ["CHILD"], "child", hd)
print("same" if a.witness() == b.witness() else "different")
PY
grep -q "^different" "$T/c7.out" || fail "C7 control: two resolutions of DIFFERENT repositories share a witness, so comparing witnesses would detect nothing: $(cat "$T/c7.out")"
pass "E99-F129c C7 the_witness_comes_back_with_the_resolution"

echo "All repository-resolver tests passed."
