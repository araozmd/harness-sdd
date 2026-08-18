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
    echo "FAIL: the suite ABORTED without reaching an assertion (set -e, or a PARSE" >&2
    echo "      error under a stricter shell than the one you ran it with)." >&2
    echo "      This message is a GUESS at the cause, not a diagnosis. Things that have" >&2
    echo "      actually caused it here: a git fixture whose branch was assumed rather" >&2
    echo "      than set; backticks inside a double-quoted string (command substitution" >&2
    echo "      in every POSIX shell — dash fails at parse time where bash only warns)." >&2
    echo "      Locate it with: sh -x \"$0\", and parse-check with: dash -n \"$0\"." >&2
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
# UNREADABLE IS NOT ABSENT. A configured manifest that cannot be parsed (a partial write,
# tab indentation) means the authority EXISTS and this checkout cannot read it — which does
# not license a basename search, because a search there can return a confident `resolved`
# for the WRONG repository. Only `absent` licenses a search.
cp "$U/umbrella.manifest.yaml" "$U/manifest.good"
printf 'repos:\n\talpha:\n\t\tpath: ../aliased-elsewhere\n' > "$U/umbrella.manifest.yaml"
ask "$ALIAS_MAIN" alpha "$HD" "r.outcome"
[ "$ASK_OUT" = "unreadable" ] \
  || fail "C3: a configured-but-unreadable manifest returned $ASK_OUT — treating it like 'absent' falls back to a basename search, which is the guess I1 forbids"
ask "$ALIAS_MAIN" alpha "$HD" "str(bool(r))"
[ "$ASK_OUT" = "False" ] || fail "C3: an unreadable authority produced a TRUTHY resolution"
# CONTROL: the same binding, same repositories, with the manifest READABLE again resolves —
# so the refusal is about the authority being unreadable, not about this fixture.
cp "$U/manifest.good" "$U/umbrella.manifest.yaml"
ask "$ALIAS_MAIN" alpha "$HD" "r.outcome"
[ "$ASK_OUT" = "resolved" ] || fail "C3 control: the same binding did not resolve once the manifest was readable again (got $ASK_OUT)"

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
# ...and `published` must confirm the TIP, not just the NAME. `ls-remote --symref` returns
# both in one call; reading only the symref line confirms which branch is the default and
# says nothing about whether our copy of it is current. With the name right and the
# tracking ref behind, an ancestry check runs against a stale tip and REFUSES work that is
# already merged — a false refusal, which the governing asymmetry ranks worse than a silent
# pass. Measured before the split: evidence `published`, confirmed True, tracking ref behind.
mkbare tipremote.git main
TC="$T/tipclone"
mkrepo "$TC"
( cd "$TC" && git_q remote add origin "$T/tipremote.git" && git_q push origin main )
TIP_OLD="$(cd "$TC" && git rev-parse main)"
( cd "$T" && git clone -q "$T/tipremote.git" tipother )
( cd "$T/tipother" && : > later.txt && git_q add -A && git_q commit -m "merged by someone else" && git_q push origin main )
TIP_NEW="$(cd "$T/tipother" && git rev-parse HEAD)"
[ "$TIP_OLD" = "$TIP_NEW" ] && fail "C5 setup: the remote did not advance, so there is no stale tip"
[ "$(cd "$TC" && git rev-parse origin/main)" = "$TIP_OLD" ] \
  || fail "C5 setup: the local tracking ref already followed the remote, so it is not stale"
mkdir -p "$TC/.harness"
ask "$TIP_OLD" - "$TC/.harness" "r.base + ' ' + r.base_evidence + ' ' + str(r.base_confirmed)"
[ "$ASK_OUT" = "origin/main published-stale-tip False" ] \
  || fail "C5: the remote NAMED this branch but our copy is behind its advertised tip, and the resolver answered '$ASK_OUT' — confirming the name while the tip is stale lets a caller refuse work that is already merged"
ask "$TIP_OLD" - "$TC/.harness" "r.base_tip"
[ "$ASK_OUT" = "$TIP_NEW" ] \
  || fail "C5: the advertised tip was not carried back (got $ASK_OUT) — it comes free in the same call, and a caller holding that object can answer against the REAL tip"
# CONTROL: fetch, and the SAME repository on the SAME remote confirms — so the answer above
# is about the tip being stale, not about this fixture being unconfirmable.
( cd "$TC" && git_q fetch origin )
ask "$TIP_NEW" - "$TC/.harness" "r.base + ' ' + r.base_evidence + ' ' + str(r.base_confirmed)"
[ "$ASK_OUT" = "origin/main published True" ] \
  || fail "C5 control: after fetching, the name AND tip agree with the remote and the base must be confirmed (got $ASK_OUT)"
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
# ...including the cheapest question of all. `resolve()` ALWAYS returns an object, so a
# default-truthy value makes `if r:` read as success for `ambiguous` and `unknown` alike —
# the exact slide from "I could not tell" to "yes" this module exists to prevent.
ask "main" - "$HD" "str(bool(r))"
[ "$ASK_OUT" = "False" ] || fail 'C6: an AMBIGUOUS resolution is truthy, so "if r:" reads uncertainty as success'
ask "nonesuch" child "$HD" "str(bool(r))"
[ "$ASK_OUT" = "False" ] || fail 'C6: an UNKNOWN resolution is truthy, so "if r:" reads uncertainty as success'
# CONTROL: a resolution that DID resolve is truthy — otherwise the two assertions above
# would hold against an object that is simply always falsy.
ask "$CHILD_MAIN" - "$HD" "str(bool(r))"
[ "$ASK_OUT" = "True" ] || fail "C6 control: a RESOLVED resolution is falsy, so truthiness tracks nothing"
pass "E99-F129c C6 uncertainty_is_a_value_you_cannot_spend"

# ── C7: the witness comes back WITH the resolution ────────────────────────────────────
# The defect this closes structurally: a witness assembled beside a resolution can be
# forgotten by the next call path — and was, by the very path added to fix an earlier
# identity defect. A witness that IS the resolution's own value cannot be.
ask "$ALIAS_MAIN" alpha "$HD" "str(r.witness().manifest_state)"
[ "$ASK_OUT" = "present" ] \
  || fail "C7: a BOUND resolution's witness does not carry the manifest state (got $ASK_OUT) — this is the omission that let a bound claim skip the manifest fingerprint entirely"
ask "$CHILD_MAIN" - "$HD" "str(len(r.witness().candidates) > 0)"
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
wa, wb = a.witness(), b.witness()
key = lambda w: (w.outcome, w.repo, w.binding,
                 w.identity.as_tuple() if w.identity else None,
                 w.manifest_state, w.manifest_entry, w.candidates, w.others)
print("same" if key(wa) == key(wb) else "different")
PY
grep -q "^different" "$T/c7.out" || fail "C7 control: two resolutions of DIFFERENT repositories share a witness, so comparing witnesses would detect nothing: $(cat "$T/c7.out")"
pass "E99-F129c C7 the_witness_comes_back_with_the_resolution"

# ── C8: what `revalidate()` asserts — the contract, not an intuition ──────────────────
# It promises: a fresh resolve() with the same inputs would give the same OUTCOME, the same
# REPOSITORY and the same CERTAINTY. Both round-3 findings were answers to that unstated
# sentence — one compared the wrong thing, one compared too few things — so each case below
# is a clause of it, and the last is what it deliberately does NOT promise.
REV="$T/rev"
mkdir -p "$REV/.harness"
mkrepo "$REV"
mkrepo "$REV/child"
REV_CHILD="$(cd "$REV/child" && git rev-parse main)"
mkrepo "$T/rev-sidecar-real"
mkrepo "$T/rev-sidecar-decoy"
ln -sfn "$T/rev-sidecar-real" "$REV/sidecar"
cat > "$REV/.harness/harness.config.yaml" <<'EOF'
store:
  backend: local
umbrella:
  manifest: ../umbrella.manifest.yaml
EOF
# The manifest key is ALIASED: `alpha` is not the directory name. An unbound resolution
# picks `child` by search, so its `repo` is a BASENAME — reading that as a manifest key is
# what made this case never revalidate.
cat > "$REV/umbrella.manifest.yaml" <<'EOF'
repos:
  alpha:
    path: child
    init: ./init.sh
    test_command: "true"
EOF
cat > "$T/rev.py" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location(
    "rr", os.path.join(os.environ["SRC"], "tools/repo-resolve.py"))
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
ref, repo, hdir, action = sys.argv[1:5]
r = rr.resolve(ref, None if repo == "-" else repo, hdir)
if action == "retarget-sidecar":
    link = os.path.join(os.environ["REV"], "sidecar")
    os.remove(link); os.symlink(os.environ["DECOY"], link)
elif action == "retarget-chosen":
    link = os.path.join(os.environ["REV"], "child")
    os.rename(link, link + "-moved"); os.symlink(os.environ["DECOY"], link)
elif action == "repoint-manifest":
    open(os.path.join(os.environ["REV"], "umbrella.manifest.yaml"), "w").write(
        "repos:\n  alpha:\n    path: %s\n" % os.environ["DECOY"])
elif action == "repoint-other-key":
    open(os.path.join(os.environ["REV"], "umbrella.manifest.yaml"), "a").write(
        "  unrelated:\n    path: %s\n" % os.environ["DECOY"])
elif action == "advance-base":
    d = r.directory
    open(os.path.join(d, "more.txt"), "w").close()
    for c in (["add", "-A"], ["commit", "-m", "someone else's merge"]):
        __import__("subprocess").run(
            ["git", "-c", "user.email=t@e", "-c", "user.name=t"] + c,
            cwd=d, stdout=-3, stderr=-3)
ok, why = rr.revalidate(r, hdir)
print("%s %s" % (ok, why))
PY
rev() { SRC="$SRC" REV="$REV" DECOY="${2:-$T/rev-sidecar-decoy}" python3 "$T/rev.py" "$REV_CHILD" "${3:--}" "$REV/.harness" "$1"; }

# CLAUSE: an UNCHANGED world revalidates. Without this the three refusals below would all
# hold against a revalidate that simply always says no — which is exactly what it did.
[ "$(rev none)" = "True None" ] \
  || fail "C8: an UNCHANGED world did not revalidate ($(rev none)) — an unbound resolution's \`repo\` is the chosen directory's BASENAME, and reading it as a manifest key makes the guard useless on the aliased layout the manifest exists for"
# CLAUSE: same REPOSITORY — the chosen one moving is detected.
case "$(rev retarget-chosen)" in
  False*) ;;
  *) fail "C8: retargeting the CHOSEN repository was not detected: $(rev retarget-chosen)" ;;
esac
( cd "$REV" && rm -f child && mv child-moved child ) 2>/dev/null || true
# CLAUSE: same CERTAINTY — a NON-SELECTED candidate becoming a different repository can
# turn a unique answer ambiguous, so it must be detected even though the chosen repo, the
# manifest and the candidate PATHS are all unchanged.
case "$(rev retarget-sidecar)" in
  False*) ;;
  *) fail "C8: retargeting a NON-SELECTED candidate went undetected — uniqueness is what made this answer certain, and a fresh resolve could now be ambiguous" ;;
esac
ln -sfn "$T/rev-sidecar-real" "$REV/sidecar"
# CLAUSE: same AUTHORITY, for a BOUND request — and scoped to the key that was asked for.
case "$(rev repoint-manifest "$T/rev-sidecar-decoy" alpha)" in
  False*) ;;
  *) fail "C8: repointing the BOUND key in the manifest went undetected" ;;
esac
cat > "$REV/umbrella.manifest.yaml" <<'EOF'
repos:
  alpha:
    path: child
    init: ./init.sh
    test_command: "true"
EOF
[ "$(rev repoint-other-key "$T/rev-sidecar-decoy" alpha)" = "True None" ] \
  || fail "C8: adding an UNRELATED manifest key aborted a bound resolution ($(rev repoint-other-key "$T/rev-sidecar-decoy" alpha)) — the witness must cover what this resolution used, or ordinary edits abort unrelated writes"
cat > "$REV/umbrella.manifest.yaml" <<'EOF'
repos:
  alpha:
    path: child
    init: ./init.sh
    test_command: "true"
EOF
# ...and what it does NOT promise: the default branch ADVANCING. That is somebody else's
# merge, it happens constantly, and ancestry is monotone under fast-forward — aborting on
# it would make the guard fire so often it would be switched off.
[ "$(rev advance-base)" = "True None" ] \
  || fail "C8: the default branch advancing aborted the resolution ($(rev advance-base)) — that is an ordinary merge by someone else, not a change of WHICH repository this is about"
pass "E99-F129c C8 revalidate_asserts_the_same_answer_not_an_unchanged_world"

# ── C9: uniqueness depends on REF MEMBERSHIP, which the witness must capture ──────────
# Round 4. A neighbouring repository that ACQUIRES the same commit between resolve() and
# the locked re-check leaves every path and every identity identical — nothing the earlier
# checks looked at moves — while a fresh resolve would now answer `ambiguous`. It is the
# third "witnessed too few things" finding, which is why the capture moved INTO resolve():
# a dimension it consults and forgets to witness is now a dimension it did not consult.
MEM="$T/member"
mkdir -p "$MEM/.harness"
mkrepo "$MEM"
mkrepo "$MEM/owner"
mkrepo "$MEM/bystander"
# Distinct content per repository: identical empty commits made in the same second collide
# on one sha, which would make every repo "hold" the ref and mask what this case measures.
echo owner > "$MEM/owner/who.txt"; ( cd "$MEM/owner" && git_q add -A && git_q commit -m owner-work )
echo bystander > "$MEM/bystander/who.txt"; ( cd "$MEM/bystander" && git_q add -A && git_q commit -m bystander-work )
MEM_REF="$(cd "$MEM/owner" && git rev-parse HEAD)"
( cd "$MEM/bystander" && git cat-file -e "$MEM_REF^{commit}" 2>/dev/null ) \
  && fail "C9 setup: the bystander already holds the ref, so acquiring it would prove nothing"
cat > "$T/mem.py" <<'PY'
import importlib.util, os, subprocess, sys
spec = importlib.util.spec_from_file_location(
    "rr", os.path.join(os.environ["SRC"], "tools/repo-resolve.py"))
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
hd, ref, action = sys.argv[1:4]
r = rr.resolve(ref, None, hd)
if r.outcome != "resolved":
    print("SETUP-NOT-RESOLVED %s" % r.outcome); raise SystemExit(0)
if action == "acquire":
    subprocess.run(["git", "fetch", "-q", os.environ["OWNER"], "main"],
                   cwd=os.environ["BYSTANDER"], stdout=-3, stderr=-3)
    subprocess.run(["git", "update-ref", "refs/heads/copied", ref],
                   cwd=os.environ["BYSTANDER"], stdout=-3, stderr=-3)
elif action == "advance-chosen":
    d = r.directory
    open(os.path.join(d, "more.txt"), "w").close()
    for c in (["add", "-A"], ["commit", "-m", "someone else's merge"]):
        subprocess.run(["git", "-c", "user.email=t@e", "-c", "user.name=t"] + c,
                       cwd=d, stdout=-3, stderr=-3)
ok, why = rr.revalidate(r, hd)
print("%s %s" % (ok, why))
PY
mem() { SRC="$SRC" OWNER="$MEM/owner" BYSTANDER="$MEM/bystander" python3 "$T/mem.py" "$MEM/.harness" "$MEM_REF" "$1"; }
# CONTROL FIRST: an unchanged world holds — without it the refusal below could hold against
# a witness that always says no.
[ "$(mem none)" = "True None" ] || fail "C9 control: an unchanged world did not hold ($(mem none))"
# The clause it must NOT break, checked BEFORE the destructive case: the CHOSEN
# repository's own branch advancing is somebody else's merge, not a change of which
# repository this answer is about. (Order matters — a fetched OBJECT survives deleting the
# ref that brought it, so once the bystander has acquired the commit it holds it for good
# and every later case would start from an `ambiguous` fixture.)
[ "$(mem advance-chosen)" = "True None" ] \
  || fail "C9: the CHOSEN repository's branch advancing aborted the re-check ($(mem advance-chosen)) — that is an ordinary merge, and aborting on it would make the guard fire constantly"
case "$(mem acquire)" in
  False*) ;;
  *) fail "C9: a neighbouring repository ACQUIRED the ref between resolve and the re-check and the witness still said 'unchanged' — every path and identity is identical, but a fresh resolve would now be ambiguous: $(mem acquire)" ;;
esac
pass "E99-F129c C9 uniqueness_depends_on_ref_membership_and_the_witness_captures_it"

# ── C10: the fingerprint observes where git actually WRITES ───────────────────────────
# Round 5. `_storage_fingerprint` stat'd five PARENT paths (.git, refs, packed-refs,
# objects, objects/pack) while its comment claimed "a repository cannot gain a commit
# without writing to its object store or its refs, so stat-ing those is sound". The
# reasoning was right and the paths did not implement it: a loose ref is written inside
# refs/heads/ and a loose object inside objects/<xx>/, and neither moves the stat'd parent.
# Measured: rewriting a loose ref left the fingerprint byte-identical. A comment asserting a
# guarantee the code lacks is worse than none — it invites the next reader to trust it.
cat > "$T/fp.py" <<'PY'
import importlib.util, os, subprocess, sys
spec = importlib.util.spec_from_file_location(
    "rr", os.path.join(os.environ["SRC"], "tools/repo-resolve.py"))
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
d, action = sys.argv[1:3]
before = rr._storage_fingerprint(d)
if before is None:
    print("NO-FINGERPRINT"); raise SystemExit(0)
def git(*a):
    subprocess.run(["git", "-c", "user.email=t@e", "-c", "user.name=t"] + list(a),
                   cwd=d, stdout=-3, stderr=-3)
if action == "loose-ref":
    head = os.path.join(rr._git_storage_root(d)[1], "refs", "heads", "main")
    sha = open(head).read().strip()
    open(head, "w").write(sha + "\n")
elif action == "loose-object":
    # `hash-object -w` writes a loose object and touches NO ref. A commit would also move
    # refs/heads, so the ref walk would catch it and this case would pass while the object
    # dimension did nothing — measured: deleting the fan-out stats left it green.
    subprocess.run(["git", "hash-object", "-w", "--stdin"], cwd=d,
                   input=os.urandom(16), stdout=-3, stderr=-3)
elif action == "new-ref":
    # A UNIQUE name each time: this action runs against more than one fixture, and a
    # second `git branch another` fails silently as "already exists", which would leave
    # the store untouched and read as a fingerprint that missed the write.
    git("branch", "b-" + os.urandom(4).hex())
print("CHANGED" if rr._storage_fingerprint(d) != before else "IDENTICAL")
PY
fp() { SRC="$SRC" python3 "$T/fp.py" "$1" "$2"; }
FPR="$T/fprepo"
mkrepo "$FPR"
# CONTROL FIRST: an untouched repository fingerprints identically — without this, every
# "CHANGED" below would hold against a fingerprint that is simply never stable.
[ "$(fp "$FPR" none)" = "IDENTICAL" ] \
  || fail "C10 control: an untouched repository did not fingerprint identically ($(fp "$FPR" none)) — a detector that never matches detects nothing"
[ "$(fp "$FPR" loose-ref)" = "CHANGED" ] \
  || fail "C10: rewriting a LOOSE REF went unseen — it is written inside refs/heads/, which the parent refs/ mtime does not follow"
[ "$(fp "$FPR" new-ref)" = "CHANGED" ] || fail "C10: creating a branch went unseen"
# Written with `hash-object -w`, which moves NO ref: this case must be carried by the
# object dimension alone, or it passes on the ref walk and the fan-out stats are dead code.
[ "$(fp "$FPR" loose-object)" = "CHANGED" ] \
  || fail "C10: a new LOOSE OBJECT written without touching any ref went unseen — it lands in objects/<xx>/, which the parent objects/ mtime does not follow"
# GITFILE / LINKED WORKTREE: `.git` is a FILE there, and the shared refs live in the common
# dir. `same_repository()` reasons about common git dirs via git; this must reach the same
# place by reading `commondir`, or the two disagree about where a repository's refs are.
( cd "$FPR" && git_q worktree add "$T/fp-wt" -b fp-branch )
[ -f "$T/fp-wt/.git" ] || fail "C10 setup: the linked worktree has no gitfile, so the layout is not being exercised"
[ "$(fp "$T/fp-wt" none)" = "IDENTICAL" ] \
  || fail "C10: a linked worktree could not be fingerprinted at all ($(fp "$T/fp-wt" none)) — `.git` is a FILE there, and a fingerprint that returns nothing sees nothing"
[ "$(fp "$T/fp-wt" new-ref)" = "CHANGED" ] \
  || fail "C10: a ref written through a linked worktree went unseen — its shared refs live in the COMMON dir, which is where the fingerprint must look"
( cd "$FPR" && git_q worktree remove --force "$T/fp-wt" )
pass "E99-F129c C10 the_fingerprint_observes_where_git_actually_writes"

echo "All repository-resolver tests passed."
