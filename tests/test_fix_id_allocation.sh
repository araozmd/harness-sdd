#!/bin/sh
# test_fix_id_allocation.sh — concurrent fix-id allocation (#253, E99-F174).
#
#   A1  add-feature allocates above the max F## on any LOCAL BRANCH's board
#   A2  ... on any REMOTE-TRACKING ref's board
#   A3  ... on HEAD's committed board (detached, reachable from no branch)
#   A4  it never fetches: an un-fetched remote's higher board is invisible
#   A5  a ref whose board is missing or unparsable is skipped WITH a stderr note
#   A6  the installed layout (`.harness/state/tasks.json`) resolves the in-repo path
#   A7  the ref scan is capped (MAX_REFS_SCANNED), newest first, and says so
#   B   validate-board.py rejects a duplicate feature or epic id (CLI, both validation
#       paths, and in-process so tasks-lock refuses to WRITE one)
#   C   `tasks-lock.py renumber`: the guards, the file moves, the duplicate-id selector,
#       and rollback when the board replace fails
#   D   agents/fixer.md and store/local.md document the recovery path
#
# Every board and repository is a throwaway under mktemp — never the live board, never a
# branch or ref in the real repository. Zero deps: POSIX sh + git + python3.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELPER="$ROOT/tools/tasks-lock.py"
VALIDATOR="$ROOT/tools/validate-board.py"
SCHEMA="$ROOT/store/tasks.schema.json"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

W="$(mktemp -d 2>/dev/null || mktemp -d -t harness-fixid)"
trap 'chmod -R u+rwx "$W" 2>/dev/null || true; rm -rf "$W"' EXIT INT TERM
# Stop git's repository discovery at $W: a TMPDIR inside some work tree must not turn the
# no-git fixture (or any "not a repo" expectation) into a repo. Fixture repos under $W/<n>
# are found directly and are unaffected. Pinned by the nested self-run at the end.
export GIT_CEILING_DIRECTORIES="$W"

# git identity/config hermetic: no global hooks, signing, or templates leak in.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# mkboard <out> <n>... — an E99 board whose features are E99-F<n>, in order.
cat > "$W/mkboard.py" <<'PY'
import json, sys
out, nums = sys.argv[1], [int(x) for x in sys.argv[2:]]
feats = [{"id": "E99-F%02d" % n, "title": "fix %d" % n, "status": "pending",
          "sdd": False, "autonomous": True, "depends_on": [],
          "spec_path": "specs/epics/E99-maintenance/F%02d-fix-%d/" % (n, n)} for n in nums]
json.dump({"project": "fx", "epics": [{"id": "E99", "title": "maintenance",
           "status": "planned", "features": feats}]}, open(out, "w"), indent=2)
PY

# mkrepo <dir> <layout:src|inst> <n>... — a git repo with ONE commit holding that board.
mkrepo() {
  _d="$1"; _l="$2"; shift 2
  mkdir -p "$_d"
  git -C "$_d" init -q
  if [ "$_l" = inst ]; then _h="$_d/.harness"; else _h="$_d"; fi
  mkdir -p "$_h/state" "$_h/store"
  cp "$SCHEMA" "$_h/store/tasks.schema.json"
  python3 "$W/mkboard.py" "$_h/state/tasks.json" "$@"
  git -C "$_d" add -A
  git -C "$_d" commit -q -m base
}

# commit_board <repo-root> <board-path> <n>... — rewrite the board and commit it.
commit_board() {
  _r="$1"; _b="$2"; shift 2
  python3 "$W/mkboard.py" "$_b" "$@"
  git -C "$_r" add -A
  git -C "$_r" commit -q -m "board $*"
}

# add_id <harness-dir> — run add-feature; stdout = id, stderr captured in $W/err.
add_id() {
  HARNESS_DIR="$1" python3 "$HELPER" add-feature --title "probe" 2>"$W/err"
}

# ── A1: a local branch's board raises the floor ──────────────────────────────
R="$W/a1"; mkrepo "$R" src 1 2
git -C "$R" checkout -q -b other
commit_board "$R" "$R/state/tasks.json" 1 2 5
git -C "$R" checkout -q -
[ "$(add_id "$R")" = "E99-F06" ] \
  || fail "A1: add-feature ignored the F05 board on a local branch (got '$(add_id "$R" || true)')"
pass "A1 local-branch board raises the allocation floor"

# ── A2: a remote-tracking ref's board raises the floor ───────────────────────
R="$W/a2"; mkrepo "$R" src 1 2
git -C "$R" checkout -q -b scratch
commit_board "$R" "$R/state/tasks.json" 1 2 7
git -C "$R" update-ref refs/remotes/origin/feat HEAD
git -C "$R" checkout -q -
git -C "$R" branch -q -D scratch
[ "$(git -C "$R" for-each-ref refs/heads | wc -l | tr -d ' ')" = "1" ] || fail "A2: fixture kept the branch"
[ "$(add_id "$R")" = "E99-F08" ] \
  || fail "A2: add-feature ignored the F07 board on a remote-tracking ref"
pass "A2 remote-tracking board raises the allocation floor"

# ── A3: HEAD's committed board counts even when no branch holds it ───────────
R="$W/a3"; mkrepo "$R" src 1 2
git -C "$R" checkout -q --detach
commit_board "$R" "$R/state/tasks.json" 1 2 9
python3 "$W/mkboard.py" "$R/state/tasks.json" 1 2      # working board lags HEAD
[ "$(add_id "$R")" = "E99-F10" ] \
  || fail "A3: add-feature ignored the board at a detached HEAD"
pass "A3 HEAD's board raises the allocation floor"

# ── A4: it never fetches ─────────────────────────────────────────────────────
R="$W/a4"; mkrepo "$R" src 1 2
RM="$W/a4-remote"; mkrepo "$RM" src 1 2
commit_board "$RM" "$RM/state/tasks.json" 1 2 20
git -C "$R" remote add origin "$RM"
[ "$(add_id "$R")" = "E99-F03" ] \
  || fail "A4: add-feature saw an UN-FETCHED remote's board — it must never fetch"
[ -z "$(git -C "$R" for-each-ref refs/remotes)" ] \
  || fail "A4: add-feature fetched (refs/remotes is no longer empty)"
pass "A4 an un-fetched remote is invisible and nothing is fetched"

# ── A5: missing / unparsable board on a ref is skipped, with a note ──────────
R="$W/a5"; mkrepo "$R" src 1 2
_base="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b noboard
git -C "$R" rm -q -r state
git -C "$R" commit -q -m "no board"
git -C "$R" checkout -q -b garbage "$_base"
printf '{ not json' > "$R/state/tasks.json"
git -C "$R" commit -q -am garbage
git -C "$R" checkout -q -b good "$_base"
commit_board "$R" "$R/state/tasks.json" 1 2 4
git -C "$R" checkout -q "$_base" 2>/dev/null
_got="$(add_id "$R")" || fail "A5: a bad ref board aborted the allocation"
[ "$_got" = "E99-F05" ] || fail "A5: expected E99-F05 around the bad refs, got '$_got'"
grep -q 'refs/heads/noboard.*skipped' "$W/err" \
  || fail "A5: no stderr note naming the ref with a missing board"
grep -q 'refs/heads/garbage.*skipped' "$W/err" \
  || fail "A5: no stderr note naming the ref with an unparsable board"
pass "A5 refs with a missing or unparsable board are skipped with a stderr note"

# ── A5b: the LOCAL board must still parse (fail closed) ──────────────────────
R="$W/a5b"; mkrepo "$R" src 1 2
printf '{ not json' > "$R/state/tasks.json"
HARNESS_DIR="$R" python3 "$HELPER" add-feature --title x >/dev/null 2>&1 \
  && fail "A5b: add-feature succeeded on an unparsable LOCAL board"
[ "$(cat "$R/state/tasks.json")" = "{ not json" ] || fail "A5b: a refused seed rewrote the board"
pass "A5b an unparsable local board still fails closed"

# ── A5c: a ref board of the wrong SHAPE is skipped or tolerated, never a crash ──
R="$W/a5c"; mkrepo "$R" src 1 2
_base="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b shape-epics "$_base"
printf '{"epics": 5}' > "$R/state/tasks.json"; git -C "$R" commit -q -am s1
git -C "$R" checkout -q -b shape-odd "$_base"
printf '%s' '{"epics": [3, {"id": "E99", "features": 7}, {"id": "E99", "features": [1, null, {"id": 5}, {"id": "E99-F11"}]}]}' \
  > "$R/state/tasks.json"
git -C "$R" commit -q -am s2
git -C "$R" checkout -q "$_base" 2>/dev/null
_got="$(add_id "$R")" || fail "A5c: a wrong-shaped ref board crashed the allocation: $(cat "$W/err")"
[ "$_got" = "E99-F12" ] || fail "A5c: expected E99-F12 (F11 read through the junk), got '$_got'"
grep -q 'refs/heads/shape-epics.*skipped' "$W/err" \
  || fail "A5c: a ref whose epics is not a list was not skipped with a note"
pass "A5c wrong-shaped ref boards are skipped or read tolerantly, never a crash"

# ── A8: a board that resolves outside the repo root is local-only, with a note ──
R="$W/a8"; mkrepo "$R" src 1 2
mkdir -p "$W/a8-elsewhere"; mv "$R/state" "$W/a8-elsewhere/state"; ln -s "$W/a8-elsewhere/state" "$R/state"
_got="$(add_id "$R")" || fail "A8: a board outside the repo root aborted the allocation: $(cat "$W/err")"
[ "$_got" = "E99-F03" ] || fail "A8: expected local-only E99-F03, got '$_got'"
grep -q 'outside the git repository root' "$W/err" || fail "A8: no note that the ref scan was skipped"
pass "A8 a board outside the repository root degrades to local-only with a note"

# ── A6: installed layout — the board path is relative to the repo root ───────
R="$W/a6"; mkrepo "$R" inst 1 2
git -C "$R" checkout -q -b other
commit_board "$R" "$R/.harness/state/tasks.json" 1 2 5
git -C "$R" checkout -q -
[ "$(add_id "$R/.harness")" = "E99-F06" ] \
  || fail "A6: add-feature missed a ref's board in the installed .harness/ layout"
pass "A6 installed layout resolves .harness/state/tasks.json inside the repo"

# ── A7: the ref scan is capped, newest first, and says so ────────────────────
cap_repo() { # <dir> <extra-branches>
  mkrepo "$1" src 1 2
  git -C "$1" checkout -q -b a-old-high
  python3 "$W/mkboard.py" "$1/state/tasks.json" 1 2 30
  git -C "$1" add -A
  GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" \
    git -C "$1" commit -q -m old-high
  git -C "$1" checkout -q -
  python3 "$W/mkboard.py" "$1/state/tasks.json" 1 2
  git -C "$1" add -A
  GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" \
    git -C "$1" commit -q -m new --allow-empty
  _i=0
  while [ "$_i" -lt "$2" ]; do
    printf 'create refs/heads/b%03d HEAD\n' "$_i"
    _i=$((_i + 1))
  done | git -C "$1" update-ref --stdin
}
R="$W/a7-over"; cap_repo "$R" 205
git -C "$R" rev-parse --verify -q refs/heads/a-old-high >/dev/null || fail "A7: fixture lost a-old-high"
[ "$(git -C "$R" show a-old-high:state/tasks.json | grep -c 'E99-F30')" -ge 1 ] || fail "A7: fixture board missing F30"
_got="$(add_id "$R")" || fail "A7: over-cap allocation failed"
[ "$_got" = "E99-F03" ] \
  || fail "A7: the cap did not cut the OLDEST ref (a-old-high's F30 was read; got '$_got')"
grep -q 'NOT checked' "$W/err" || fail "A7: the cut was silent — no stderr note"
R="$W/a7-under"; cap_repo "$R" 150
_got="$(add_id "$R")"
[ "$_got" = "E99-F31" ] \
  || fail "A7: under the cap, a-old-high's F30 must still be read (got '$_got')"
if grep -q 'NOT checked' "$W/err"; then fail "A7: a note claimed a cut under the cap"; fi
pass "A7 the ref scan is capped at the newest MAX_REFS_SCANNED and reports the cut"

# ── B: validate-board rejects duplicate ids ──────────────────────────────────
cat > "$W/dupboard.py" <<'PY'
import json, sys
kind, out = sys.argv[1], sys.argv[2]
def feat(i, t="t"):
    return {"id": i, "title": t, "status": "pending", "sdd": False, "spec_path": "p/"}
def epic(i, feats):
    return {"id": i, "title": "e", "status": "planned", "features": feats}
if kind == "same-epic":
    eps = [epic("E99", [feat("E99-F05", "a"), feat("E99-F05", "b")])]
elif kind == "cross-epic":
    eps = [epic("E01", [feat("E01-F01")]), epic("E02", [feat("E01-F01")])]
elif kind == "epic":
    eps = [epic("E01", [feat("E01-F01")]), epic("E01", [feat("E01-F02")])]
else:  # ok: same F number in DIFFERENT epics is a different id
    eps = [epic("E01", [feat("E01-F01")]), epic("E02", [feat("E02-F01")])]
json.dump({"project": "p", "epics": eps}, open(out, "w"))
PY
# A stub `jsonschema` that accepts everything forces the schema-validator path, so the
# duplicate check is proven on BOTH paths (this host has no real jsonschema).
mkdir -p "$W/stub"
cat > "$W/stub/jsonschema.py" <<'PY'
class Draft7Validator(object):
    def __init__(self, schema): pass
    def iter_errors(self, data): return iter(())
PY
for _k in same-epic cross-epic epic; do
  python3 "$W/dupboard.py" "$_k" "$W/dup-$_k.json"
  for _path in fallback stub; do
    if [ "$_path" = stub ]; then _pp="$W/stub"; else _pp=""; fi
    PYTHONPATH="$_pp" python3 "$VALIDATOR" "$W/dup-$_k.json" "$SCHEMA" 2>"$W/verr" \
      && fail "B: a $_k duplicate id passed validation on the $_path path"
    grep -q 'duplicate' "$W/verr" \
      || fail "B: the $_k/$_path rejection does not say 'duplicate': $(cat "$W/verr")"
  done
done
python3 "$W/dupboard.py" ok "$W/dup-ok.json"
for _pp in "" "$W/stub"; do
  PYTHONPATH="$_pp" python3 "$VALIDATOR" "$W/dup-ok.json" "$SCHEMA" \
    || fail "B: distinct ids (same F## in different epics) were rejected"
done
# Malformed shapes are the SCHEMA's to report: the duplicate check must tolerate them
# (no traceback) on both paths, and the CLI still exits 1.
python3 - "$W/dup-malformed.json" <<'PY'
import json, sys
json.dump({"project": "p", "epics": [
    5, {"id": [], "features": [{"id": []}, 7, {"id": "E1-F1"}]},
    {"id": "E1", "title": "e", "status": "planned", "features": 9}]}, open(sys.argv[1], "w"))
PY
# `epics` not a list: the unit itself must not raise (the CLI's pre-existing draft-warning
# pass is not this check's to fix).
python3 -c 'import importlib.util as u,sys
sp = u.spec_from_file_location("vb", sys.argv[1]); m = u.module_from_spec(sp); sp.loader.exec_module(m)
assert m.duplicate_id_errors({"epics": 5}) == [] and m.duplicate_id_errors([]) == []' "$VALIDATOR" \
  || fail "B: duplicate_id_errors raised on a non-list epics / non-object board"
for _f in dup-malformed; do
  for _pp in "" "$W/stub"; do
    PYTHONPATH="$_pp" python3 "$VALIDATOR" "$W/$_f.json" "$SCHEMA" >/dev/null 2>"$W/verr" && _rc=0 || _rc=$?
    if grep -q Traceback "$W/verr"; then fail "B: $_f crashed the validator: $(cat "$W/verr")"; fi
  done
  python3 "$VALIDATOR" "$W/$_f.json" "$SCHEMA" >/dev/null 2>&1 \
    && fail "B: the malformed board $_f passed on the fallback path"
done
# In-process: tasks-lock refuses a WRITE that would leave a duplicate, board untouched.
R="$W/b-inproc"; mkrepo "$R" src 1 2
cat > "$W/mkdup.py" <<'PY'
def mutate(data):
    data["epics"][0]["features"].append(dict(data["epics"][0]["features"][0]))
    return data
PY
_before="$(cat "$R/state/tasks.json")"
HARNESS_DIR="$R" python3 "$HELPER" apply --mutator "$W/mkdup.py" >/dev/null 2>"$W/err" \
  && fail "B: tasks-lock wrote a board with a duplicate feature id"
grep -q 'duplicate' "$W/err" || fail "B: the refused write did not name the duplicate"
[ "$_before" = "$(cat "$R/state/tasks.json")" ] || fail "B: a refused duplicate write changed the board"
pass "B validate-board rejects duplicate feature/epic ids on both paths and in-process"

# ── C: renumber ──────────────────────────────────────────────────────────────
# Fixture: board F01..F03 here; branch `other` already carries F05. Row F03 has an inbox
# brief and a progress dir.
mk_ren() { # <dir>
  mkrepo "$1" src 1 2 3
  mkdir -p "$1/progress/inbox" "$1/progress/E99-F03"
  printf -- '---\nfeature: E99-F03\nseeded_by: fixer\n---\n# Intent\nbody line\n' \
    > "$1/progress/inbox/E99-F03.md"
  printf 'note\n' > "$1/progress/E99-F03/note.txt"
  git -C "$1" add -A; git -C "$1" commit -q -m files
  git -C "$1" checkout -q -b other
  commit_board "$1" "$1/state/tasks.json" 1 2 3 5
  git -C "$1" checkout -q -
}
ren() { _rh="$1"; _ro="$2"; _rn="$3"; shift 3
  HARNESS_DIR="$_rh" python3 "$HELPER" renumber "$_ro" "$_rn" "$@" 2>"$W/err"; }
snap() { (cd "$1" && find state progress -type f 2>/dev/null | sort | xargs cat | cksum; find progress 2>/dev/null | sort); }
# refuses <repo> <msg-regex> <args...> — must exit non-zero, name the reason, change nothing.
refuses() {
  _rp="$1"; _re="$2"; shift 2
  _s0="$(snap "$_rp")"
  if HARNESS_DIR="$_rp" python3 "$HELPER" renumber "$@" >"$W/out" 2>"$W/err"; then
    fail "C: renumber $* succeeded; expected a refusal matching /$_re/"
  fi
  grep -Eq "$_re" "$W/err" || fail "C: renumber $* refused for the wrong reason (want /$_re/): $(cat "$W/err")"
  [ "$_s0" = "$(snap "$_rp")" ] || fail "C: refused renumber $* still changed the board or files"
}

R="$W/c-ok"; mk_ren "$R"
# Not above the max over visible refs (F05 sits on another branch) — F04 and F05 refuse
# even though the working board's own max is 3.
refuses "$R" 'not above' E99-F03 E99-F04
refuses "$R" 'not above' E99-F03 E99-F05
_new="$(ren "$R" E99-F03 E99-F06)" || fail "C: a valid renumber failed: $(cat "$W/err")"
[ "$_new" = "E99-F06" ] || fail "C: renumber must print the new id alone on stdout (got '$_new')"
python3 - "$R/state/tasks.json" <<'PY' || fail "C: the row was not rewritten as required"
import json, sys
fs = json.load(open(sys.argv[1]))["epics"][0]["features"]
assert [f["id"] for f in fs] == ["E99-F01", "E99-F02", "E99-F06"], [f["id"] for f in fs]
assert fs[2]["spec_path"] == "specs/epics/E99-maintenance/F06-fix-3/", fs[2]["spec_path"]
assert fs[2]["title"] == "fix 3", fs[2]
PY
[ ! -e "$R/progress/inbox/E99-F03.md" ] || fail "C: the old inbox brief was left behind"
[ "$(cat "$R/progress/inbox/E99-F06.md")" = "$(printf -- '---\nfeature: E99-F06\nseeded_by: fixer\n---\n# Intent\nbody line')" ] \
  || fail "C: the moved brief's frontmatter/body is wrong: $(cat "$R/progress/inbox/E99-F06.md")"
[ ! -e "$R/progress/E99-F03" ] && [ "$(cat "$R/progress/E99-F06/note.txt")" = "note" ] \
  || fail "C: the progress dir was not moved"
python3 "$VALIDATOR" "$R/state/tasks.json" "$SCHEMA" || fail "C: the renumbered board does not validate"
pass "C renumber rewrites id + spec_path, moves the brief (frontmatter updated) and the progress dir"

# Row-level refusals. Each fixture is fresh so a leftover cannot mask another guard.
mutate_row() { # <repo> <python statement using f = the F03 row>
  cat > "$W/m.py" <<PY
def mutate(data):
    f = [x for x in data["epics"][0]["features"] if x["id"] == "E99-F03"][0]
    $2
    return data
PY
  HARNESS_DIR="$1" python3 "$HELPER" apply --mutator "$W/m.py" >/dev/null 2>&1 \
    || fail "C: fixture mutation failed: $2"
}
R="$W/c-done"; mk_ren "$R"
mutate_row "$R" 'f["status"]="done"; f["landed"]={"ref":"none:x","verified":"declared"}'
refuses "$R" 'done' E99-F03 E99-F06
R="$W/c-landed"; mk_ren "$R"
mutate_row "$R" 'f["landed"]={"ref":"none:x","verified":"declared"}'
refuses "$R" 'landed' E99-F03 E99-F06
R="$W/c-badpath"; mk_ren "$R"
mutate_row "$R" 'f["spec_path"]="specs/epics/E99-maintenance/F09-other/"'
refuses "$R" 'spec_path' E99-F03 E99-F06
R="$W/c-pathexists"; mk_ren "$R"
mkdir -p "$R/specs/epics/E99-maintenance/F03-fix-3"
refuses "$R" 'exists on disk' E99-F03 E99-F06
R="$W/c-parked"; mk_ren "$R"
mutate_row "$R" 'f["status"]="in-review"; f["parked"]={"gate":"merge","reason":"awaiting","unblocked_by":"set-status E99-F03 done"}'
refuses "$R" 'parked.*unpark' E99-F03 E99-F06
R="$W/c-dep"; mk_ren "$R"
mutate_row "$R" 'data["epics"][0]["features"][0]["depends_on"]=["E99-F03"]'
refuses "$R" 'depends_on' E99-F03 E99-F06
R="$W/c-sdd"; mk_ren "$R"
mutate_row "$R" 'f["sdd"]=True'
refuses "$R" 'not an sdd: false' E99-F03 E99-F06
R="$W/c-sliced"; mk_ren "$R"
mutate_row "$R" 'f["slices"]=[{"id":"E99-F03@app","repo":"app","status":"pending"}]'
refuses "$R" 'carries slices' E99-F03 E99-F06

R="$W/c-ids"; mk_ren "$R"
refuses "$R" 'epic E98 not found' E98-F01 E98-F02
refuses "$R" 'not found' E99-F04 E99-F06
refuses "$R" 'different epics' E99-F03 E98-F06
refuses "$R" 'canonical' E99-F03 E99-F006
refuses "$R" 'E<nn>-F<nn>' E99-F03 E99-F7x
refuses "$R" 'E<nn>-F<nn>' E99-F03 not-an-id
refuses "$R" 'not above' E99-F03 E99-F03
refuses "$R" 'not above' E99-F03 E99-F02
# Outside git there are no refs: the WORKING board's own max still binds the new id.
R="$W/c-nogit"; mkdir -p "$R/state" "$R/store"; cp "$SCHEMA" "$R/store/"
python3 "$W/mkboard.py" "$R/state/tasks.json" 1 2 3
(cd "$R" && git rev-parse --is-inside-work-tree >/dev/null 2>&1) \
  && fail "C: the no-git fixture sits inside a work tree (TMPDIR under a repo?)"
refuses "$R" 'not above' E99-F03 E99-F02
refuses "$R" 'not above' E99-F02 E99-F03
pass "C renumber refuses done, landed, sdd:true, sliced, a bad or occupied spec_path, an inbound depends_on, unknown/foreign/non-canonical/non-higher ids"

# File refusals: nothing moves when ANY file move is unsafe, and the board stays put.
R="$W/c-dstbrief"; mk_ren "$R"; : > "$R/progress/inbox/E99-F06.md"
refuses "$R" 'already exists' E99-F03 E99-F06
R="$W/c-dstdir"; mk_ren "$R"; mkdir "$R/progress/E99-F06"
refuses "$R" 'already exists' E99-F03 E99-F06
R="$W/c-nofm"; mk_ren "$R"; printf 'no frontmatter\n' > "$R/progress/inbox/E99-F03.md"
refuses "$R" 'no frontmatter block' E99-F03 E99-F06
R="$W/c-lateborder"; mk_ren "$R"
printf 'preamble\n---\nfeature: E99-F03\n---\nx\n' > "$R/progress/inbox/E99-F03.md"
refuses "$R" 'no frontmatter block' E99-F03 E99-F06
R="$W/c-unclosed"; mk_ren "$R"; printf -- '---\nfeature: E99-F03\nx\n' > "$R/progress/inbox/E99-F03.md"
refuses "$R" 'not closed' E99-F03 E99-F06
R="$W/c-bodyfeature"; mk_ren "$R"
printf -- '---\ntitle: x\n---\nfeature: E99-F03\n' > "$R/progress/inbox/E99-F03.md"
refuses "$R" 'exactly one `feature: E99-F03`' E99-F03 E99-F06
R="$W/c-wrongfm"; mk_ren "$R"; printf -- '---\nfeature: E99-F04\n---\nx\n' > "$R/progress/inbox/E99-F03.md"
refuses "$R" 'exactly one `feature: E99-F03`' E99-F03 E99-F06
R="$W/c-twofeature"; mk_ren "$R"
printf -- '---\nfeature: E99-F03\nfeature: E99-F03\n---\nx\n' > "$R/progress/inbox/E99-F03.md"
refuses "$R" 'exactly one `feature: E99-F03`' E99-F03 E99-F06
R="$W/c-prefixid"; mk_ren "$R"
printf -- '---\nfeature: E99-F030\n---\nx\n' > "$R/progress/inbox/E99-F03.md"
refuses "$R" 'exactly one `feature: E99-F03`' E99-F03 E99-F06
R="$W/c-linkbrief"; mk_ren "$R"; rm "$R/progress/inbox/E99-F03.md"
printf 'victim\n' > "$W/victim.md"; ln -s "$W/victim.md" "$R/progress/inbox/E99-F03.md"
refuses "$R" 'not a regular file' E99-F03 E99-F06
[ "$(cat "$W/victim.md")" = victim ] || fail "C: a symlinked brief's target was modified"
R="$W/c-linkdir"; mk_ren "$R"; rm -rf "$R/progress/E99-F03"
mkdir "$W/victimdir"; printf 'v\n' > "$W/victimdir/f"; ln -s "$W/victimdir" "$R/progress/E99-F03"
refuses "$R" 'not a real directory' E99-F03 E99-F06
[ -f "$W/victimdir/f" ] || fail "C: a symlinked progress dir's target was moved"
R="$W/c-linkparent"; mk_ren "$R"
mkdir -p "$W/realinbox"; cp "$R/progress/inbox/E99-F03.md" "$W/realinbox/"
rm -rf "$R/progress/inbox"; ln -s "$W/realinbox" "$R/progress/inbox"
refuses "$R" 'symlinked parent' E99-F03 E99-F06
[ -f "$W/realinbox/E99-F03.md" ] || fail "C: a brief behind a symlinked inbox dir was moved"
pass "C renumber refuses unsafe file moves (occupied target, bad frontmatter, symlinked file/dir/parent) before touching anything"

# The moved brief keeps its permission bits.
R="$W/c-mode"; mk_ren "$R"; chmod 600 "$R/progress/inbox/E99-F03.md"
ren "$R" E99-F03 E99-F06 >/dev/null || fail "C: renumber with a 0600 brief failed"
[ "$(python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$R/progress/inbox/E99-F06.md")" = "0o600" ] \
  || fail "C: the moved brief lost its permission bits"
# The forward move never creates the new brief wider than 0600 (no world-readable window).
R="$W/c-mode-open"; mk_ren "$R"; chmod 600 "$R/progress/inbox/E99-F03.md"
HARNESS_DIR="$R" python3 -c 'import os, runpy, sys
real, log = os.open, sys.argv[1]
def o(p, flags, mode=0o777, *a, **k):
    if str(p).endswith("E99-F06.md") and flags & os.O_CREAT:
        with open(log, "a") as fh: fh.write(oct(mode) + "\n")
    return real(p, flags, mode, *a, **k)
os.open = o
sys.argv = sys.argv[2:]
runpy.run_path(sys.argv[0], run_name="__main__")' "$W/openmodes" "$HELPER" renumber E99-F03 E99-F06 >/dev/null 2>"$W/err" \
  || fail "C: renumber under the os.open probe failed: $(cat "$W/err")"
[ "$(cat "$W/openmodes")" = "0o600" ] \
  || fail "C: the forward move created the brief with mode $(cat "$W/openmodes"), not 0600"
[ "$(python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$R/progress/inbox/E99-F06.md")" = "0o600" ] \
  || fail "C: the probed forward move lost the brief's 0600 mode"
pass "C renumber preserves the brief's mode"

# A row with no inbox brief and no progress dir renumbers cleanly (both are optional).
R="$W/c-bare"; mkrepo "$R" src 1 2 3
ren "$R" E99-F03 E99-F04 >/dev/null || fail "C: renumber of a row with no files failed: $(cat "$W/err")"
pass "C renumber works when the row has no brief or progress dir"

# Rollback — (1) the board replace fails; (2) the second file move fails after the first.
if [ "$(id -u)" != 0 ]; then
  R="$W/c-rb1"; mk_ren "$R"; _s0="$(snap "$R")"
  chmod 555 "$R/state"
  if HARNESS_DIR="$R" python3 "$HELPER" renumber E99-F03 E99-F06 >/dev/null 2>&1; then
    chmod 755 "$R/state"; fail "C: renumber succeeded with an unwritable state dir"
  fi
  chmod 755 "$R/state"
  [ "$_s0" = "$(snap "$R")" ] || fail "C: a failed board replace left the files moved (no rollback)"
  R="$W/c-rb2"; mk_ren "$R"; _s0="$(snap "$R")"
  chmod 555 "$R/progress"   # the dir rename needs write on progress/; the brief move does not
  if HARNESS_DIR="$R" python3 "$HELPER" renumber E99-F03 E99-F06 >/dev/null 2>&1; then
    chmod 755 "$R/progress"; fail "C: renumber succeeded though the dir move cannot"
  fi
  chmod 755 "$R/progress"
  [ "$_s0" = "$(snap "$R")" ] || fail "C: a mid-way move failure left the brief moved (no rollback)"
  [ -f "$R/progress/inbox/E99-F03.md" ] && [ ! -e "$R/progress/inbox/E99-F06.md" ] \
    || fail "C: rollback did not restore the brief exactly"
  pass "C renumber rolls the file moves back when the board replace or a later move fails"
else
  echo "skip - rollback rows need a non-root user (permission bits do not bind root)"
fi

# Rollback WITHOUT permission tricks (so it runs as root too): run the helper under a wrapper
# that makes os.replace (the board write) or os.rename (the dir move) raise.
inject() { # <repo> <os-function> <args...>
  _ih="$1"; _if="$2"; shift 2
  HARNESS_DIR="$_ih" python3 -c 'import os, runpy, sys
fn = sys.argv[1]
def boom(*a, **k): raise OSError("injected " + fn)
setattr(os, fn, boom)
sys.argv = sys.argv[2:]
runpy.run_path(sys.argv[0], run_name="__main__")' "$_if" "$HELPER" "$@" >/dev/null 2>"$W/err"
}
for _fn in replace rename; do
  R="$W/c-inj-$_fn"; mk_ren "$R"; _s0="$(snap "$R")"
  if inject "$R" "$_fn" renumber E99-F03 E99-F06; then fail "C: renumber survived an injected os.$_fn failure"; fi
  grep -q "injected $_fn" "$W/err" || fail "C: os.$_fn was never reached: $(cat "$W/err")"
  [ "$_s0" = "$(snap "$R")" ] || fail "C: an injected os.$_fn failure left the board or files changed"
  [ -f "$R/progress/inbox/E99-F03.md" ] && [ ! -e "$R/progress/inbox/E99-F06.md" ] \
    && [ -d "$R/progress/E99-F03" ] || fail "C: rollback after os.$_fn failed to restore the layout"
done
# The restored brief keeps its original mode: a 0600 brief must not come back world-readable.
R="$W/c-inj-mode"; mk_ren "$R"; chmod 600 "$R/progress/inbox/E99-F03.md"
if inject "$R" replace renumber E99-F03 E99-F06; then fail "C: renumber survived an injected os.replace failure"; fi
[ "$(python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$R/progress/inbox/E99-F03.md")" = "0o600" ] \
  || fail "C: rollback did not restore the brief's 0600 mode"
# A mode restore that fails during rollback is reported loudly.
R="$W/c-inj-fchmod"; mk_ren "$R"
HARNESS_DIR="$R" python3 -c 'import os, runpy, sys
real, calls = os.fchmod, []
def f(*a, **k):  # the forward move'"'"'s fchmod succeeds; the rollback'"'"'s one fails
    calls.append(1)
    if len(calls) > 1: raise OSError("cannot fchmod")
    return real(*a, **k)
def boom(*a, **k): raise OSError("injected replace")
os.fchmod = f; os.replace = boom
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")' "$HELPER" renumber E99-F03 E99-F06 >/dev/null 2>"$W/err" \
  && fail "C: renumber survived the injected failures"
grep -q 'ROLLBACK FAILED.*cannot fchmod' "$W/err" || fail "C: a failed mode restore was not reported: $(cat "$W/err")"
# A rollback step that cannot be undone is reported loudly, never swallowed.
R="$W/c-inj-loud"; mk_ren "$R"
HARNESS_DIR="$R" python3 -c 'import os, runpy, sys
real = os.unlink
def u(p, *a, **k):
    if str(p).endswith("E99-F06.md"): raise OSError("cannot unlink dst")
    return real(p, *a, **k)
def boom(*a, **k): raise OSError("injected replace")
os.unlink = u; os.replace = boom
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name="__main__")' "$HELPER" renumber E99-F03 E99-F06 >/dev/null 2>"$W/err" \
  && fail "C: renumber survived the injected failures"
grep -q 'ROLLBACK FAILED' "$W/err" || fail "C: a failed rollback step was not reported: $(cat "$W/err")"
pass "C rollback is pinned without permission tricks, and a failed restore is loud"

# Duplicate id: two rows share E99-F05 (a bad union). Write the board raw — the guarded
# path refuses to create it.
mk_dup() { # <dir>
  mkrepo "$1" src 1 2 5
  python3 - "$1/state/tasks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
fs = d["epics"][0]["features"]
other = dict(fs[2]); other["title"] = "the other session's fix"
other["spec_path"] = "specs/epics/E99-maintenance/F05-other/"
fs.append(other)
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
  mkdir -p "$1/progress/inbox"
  printf -- '---\nfeature: E99-F05\n---\nx\n' > "$1/progress/inbox/E99-F05.md"
}
R="$W/c-dup0"; mk_dup "$R"
refuses "$R" 'appears 2 times.*--title-match' E99-F05 E99-F06
grep -q -- '--index 1 = .the other session' "$W/err" || fail "C: the ambiguity message does not list the candidates"
refuses "$R" 'selects 0 rows' E99-F05 E99-F06 --title-match 'no such title'
refuses "$R" 'selects 0 rows' E99-F05 E99-F06 --title-match 'fix'          # exact, not substring
refuses "$R" 'out of range' E99-F05 E99-F06 --index 2
refuses "$R" 'out of range' E99-F05 E99-F06 --index -1
refuses "$R" 'mutually exclusive' E99-F05 E99-F06 --index 0 --title-match 'fix 5'
R="$W/c-dupsame"; mk_dup "$R"
python3 - "$R/state/tasks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); fs = d["epics"][0]["features"]
fs[3]["title"] = fs[2]["title"]
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
refuses "$R" 'selects 2 rows' E99-F05 E99-F06 --title-match 'fix 5'
R="$W/c-dup1"; mk_dup "$R"
_new="$(ren "$R" E99-F05 E99-F06 --title-match "the other session's fix")" \
  || fail "C: --title-match could not resolve the duplicate: $(cat "$W/err")"
python3 - "$R/state/tasks.json" <<'PY' || fail "C: --title-match renumbered the wrong row"
import json, sys
fs = json.load(open(sys.argv[1]))["epics"][0]["features"]
assert [(f["id"], f["title"]) for f in fs] == [
    ("E99-F01", "fix 1"), ("E99-F02", "fix 2"), ("E99-F05", "fix 5"),
    ("E99-F06", "the other session's fix")], fs
assert fs[3]["spec_path"] == "specs/epics/E99-maintenance/F06-other/", fs[3]
PY
grep -q 'NOT moved' "$W/err" || fail "C: the duplicate case did not warn that files are not moved"
[ -f "$R/progress/inbox/E99-F05.md" ] && [ ! -e "$R/progress/inbox/E99-F06.md" ] \
  || fail "C: the duplicate case moved a brief whose owner cannot be told"
R="$W/c-dup2"; mk_dup "$R"
ren "$R" E99-F05 E99-F06 --index 0 >/dev/null || fail "C: --index 0 failed"
python3 - "$R/state/tasks.json" <<'PY' || fail "C: --index 0 did not pick the first E99-F05 row"
import json, sys
fs = json.load(open(sys.argv[1]))["epics"][0]["features"]
assert [(f["id"], f["title"]) for f in fs] == [
    ("E99-F01", "fix 1"), ("E99-F02", "fix 2"), ("E99-F06", "fix 5"),
    ("E99-F05", "the other session's fix")], fs
PY
pass "C a duplicated id needs --title-match (exact) or --index; files are left for a human"

# A selector on a UNIQUE row is an assertion, not a hint.
R="$W/c-sel"; mk_ren "$R"
refuses "$R" 'selects 0 rows' E99-F03 E99-F06 --title-match 'wrong title'
refuses "$R" 'out of range' E99-F03 E99-F06 --index 1
pass "C a selector on a unique row must still hold"

# ── D: docs ──────────────────────────────────────────────────────────────────
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
section() { # <file> <heading-substring>
  awk "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^#+ / { keep = (index($0, h) > 0); next }
    keep
  ' h="$2" "$1"
}
_dup="$(section "$ROOT/agents/fixer.md" 'Duplicate fix id' | tr '\n' ' ')"
[ -n "$_dup" ] || fail "D: agents/fixer.md has no 'Duplicate fix id' section"
printf '%s' "$_dup" | grep -qiE 'lands? second[^.]{0,120}renumber' \
  || fail "D: fixer.md's rule must say the session whose board lands SECOND renumbers"
printf '%s' "$_dup" | grep -qE 'tasks-lock\.py renumber <old-id> <new-id>' \
  || fail "D: fixer.md's rule must show the renumber command"
printf '%s' "$_dup" | grep -qiE 'never[^.]{0,80}(landed|done)' \
  || fail "D: fixer.md's rule must keep never-renumber for landed/done rows"
printf '%s' "$_dup" | grep -qE -- '--title-match' \
  || fail "D: fixer.md's rule must document the duplicate disambiguator"
printf '%s' "$_dup" | grep -qiE 're-runs?[^.]{0,20}init\.sh' \
  || fail "D: fixer.md's rule must say to re-run init.sh"
_guard="$(section "$ROOT/agents/fixer.md" 'What you NEVER do' | tr '\n' ' ')"
printf '%s' "$_guard" | grep -qiE 'only exception[^.]{0,40}tasks-lock\.py renumber' \
  || fail "D: the never-renumber guardrail must point at the explicit exception"
_loc="$(section "$ROOT/store/local.md" 'Deterministic read-only selector' | tr '\n' ' ')"
printf '%s' "$_loc" | grep -qE 'tasks-lock\.py renumber' \
  || fail "D: store/local.md does not list the renumber command"
for _f in .claude/commands/sdd-fix.md .agents/skills/sdd-fix/SKILL.md .opencode/command/sdd-fix.md; do
  tr '\n' ' ' < "$ROOT/$_f" | grep -qiE 'never renumber its existing fixes[^.]{0,20}the one exception: renumber your OWN un-landed' \
    || fail "D: the emitted $_f does not point never-renumber at its exception"
done
pass "D fixer.md and store/local.md document the duplicate-id recovery path"

# The suite must pass with TMPDIR INSIDE a git work tree (the ceiling above is what makes
# the no-git fixture hermetic). Nested run guarded against recursion.
if [ -z "${FIXID_NESTED:-}" ]; then
  mkdir -p "$W/wt/tmp"; git -C "$W/wt" init -q
  FIXID_NESTED=1 TMPDIR="$W/wt/tmp" GIT_CEILING_DIRECTORIES= sh "$0" >"$W/nested.log" 2>&1 \
    || fail "TMPDIR inside a git work tree breaks the suite: $(grep FAIL "$W/nested.log" | head -1)"
  pass "the suite is hermetic with TMPDIR inside a git work tree"
fi

echo "PASS: test_fix_id_allocation.sh (A1-A7, B, C, D)"
