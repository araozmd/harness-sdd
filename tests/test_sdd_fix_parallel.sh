#!/bin/sh
# test_sdd_fix_parallel.sh — E15-F03 permanent contract + disposable fixtures.
# The production coordinator is a portable role/command contract executed by the
# host agent. Fixtures exercise its deterministic pure decisions and the real F01
# locked apply seam without touching the live board, branches, worktrees, or PRs.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

FIXER="agents/fixer.md"
ORCH="agents/orchestrator.md"
CMD=".claude/commands/sdd-fix-parallel.md"
SERIAL=".claude/commands/sdd-fix.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
need() { grep -qF "$2" "$1" || fail "$3"; }

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t sdd-fix-parallel)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# Named traceability cases exercised by the combined decision fixture:
# test_eligibility_fenced_to_ready_e99_fixes
# test_order_cap_and_default
# test_invalid_config_is_preflight_fail_stop
# test_shared_path_defaults_and_extensions
# test_brief_path_classification_fails_safe
# test_manifest_has_no_silent_deferrals_or_serialization
# test_schema_and_scope_unchanged
# test_no_ready_candidates_is_clean_noop
# R1/R2/R3/R5/R6/R10/R15/R19: exercise selection, cap/config validation,
# path guarding, manifest completeness, and no-ready behavior in one disposable
# oracle. This is coordinator input/output behavior, not prose-only coverage.
if ! python3 - "$ROOT/harness.config.yaml" "$TMP" <<'PY'
import copy, json, pathlib, re, sys

config_path, tmp = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

def validate_config(cfg):
    backend = cfg.get("execution", {}).get("builder", {}).get("backend", "in-session")
    if backend == "delegate":
        raise ValueError(
            "execution.builder.backend=delegate; use serial /sdd-fix"
        )
    if backend != "in-session":
        raise ValueError("execution.builder.backend")
    lane = cfg.get("fix_lane", {})
    cap = lane.get("max_parallel", 3)
    if type(cap) is not int or cap <= 0:
        raise ValueError("fix_lane.max_parallel")
    patterns = lane.get("shared_paths", [])
    if not isinstance(patterns, list):
        raise ValueError("fix_lane.shared_paths")
    for p in patterns:
        if not isinstance(p, str) or not p or not canonical_pattern(p):
            raise ValueError("fix_lane.shared_paths:" + repr(p))
    return cap, ["harness-install.sh", "tests/test_install.sh", "tools/*"] + patterns

def canonical_pattern(p):
    if p.startswith("/") or p.startswith("./") or p.endswith("/"):
        return False
    if any(ord(c) < 32 or ord(c) == 127 for c in p):
        return False
    base = p[:-2] if p.endswith("/*") else p
    if "*" in base or "\\" in p:
        return False
    parts = base.split("/")
    return bool(base) and all(x not in ("", ".", "..") for x in parts)

def normalized_declared(p):
    if p.startswith("./"):
        p = p[2:]
    if (not p or p.startswith("/") or "*" in p or "\\" in p or
        any(ord(c) < 32 or ord(c) == 127 for c in p)):
        return None
    parts = p.split("/")
    return p if all(x not in ("", ".", "..") for x in parts) else None

def classify(paths, patterns, missing=False):
    if missing or not paths:
        return "guarded", "missing expected-path declaration"
    for raw in paths:
        p = normalized_declared(raw)
        if p is None:
            return "guarded", "unsafe or ambiguous expected path"
        for pat in patterns:
            if pat.endswith("/*") and p.startswith(pat[:-1]):
                return "guarded", "shared path " + pat
            if p == pat:
                return "guarded", "shared path " + pat
    return "parallel", ""

def ready(board):
    all_features = {
        f["id"]: f for e in board["epics"] for f in e.get("features", [])
    }
    e99 = next((e for e in board["epics"] if e["id"] == "E99"), None)
    if not e99 or e99.get("status") == "draft":
        return []
    result = []
    for f in e99.get("features", []):
        if not (f.get("status") == "pending" and f.get("sdd") is False
                and f.get("autonomous") is True):
            continue
        if all(d in all_features and all_features[d].get("status") == "done"
               for d in f.get("depends_on", [])):
            result.append(f)
    return sorted(result, key=lambda f: int(f["id"].split("-F", 1)[1]))

board = {
    "project": "fixture",
    "epics": [
        {"id":"E01","title":"lower non-E99","status":"done","features":[
            {"id":"E01-F01","title":"dep","status":"done","sdd":True,
             "autonomous":True,"depends_on":[],"spec_path":"x/"},
            {"id":"E01-F02","title":"blocked","status":"pending","sdd":True,
             "autonomous":True,"depends_on":[],"spec_path":"x/"}]},
        {"id":"E99","title":"maintenance","status":"planned","features":[
            {"id":"E99-F10","status":"pending","sdd":False,"autonomous":True,
             "depends_on":[]},
            {"id":"E99-F02","status":"pending","sdd":False,"autonomous":True,
             "depends_on":["E01-F01"]},
            {"id":"E99-F01","status":"pending","sdd":False,"autonomous":True,
             "depends_on":[]},
            {"id":"E99-F03","status":"pending","sdd":False,"autonomous":False,
             "depends_on":[]},
            {"id":"E99-F04","status":"pending","sdd":True,"autonomous":True,
             "depends_on":[]},
            {"id":"E99-F05","status":"done","sdd":False,"autonomous":True,
             "depends_on":[]},
            {"id":"E99-F06","status":"pending","sdd":False,"autonomous":True,
             "depends_on":["E01-F02"]}]}
    ]
}
assert [f["id"] for f in ready(board)] == ["E99-F01","E99-F02","E99-F10"]

assert validate_config({})[0] == 3
delegate_before = json.dumps(board, sort_keys=True)
try:
    validate_config({"execution":{"builder":{"backend":"delegate"}}})
except ValueError as e:
    assert "delegate" in str(e) and "serial /sdd-fix" in str(e)
else:
    raise AssertionError("accepted delegate builder backend")
assert json.dumps(board, sort_keys=True) == delegate_before
assert not list(tmp.glob("E99-fix-parallel-*"))
for cap, expected in [(1,["E99-F01"]),(2,["E99-F01","E99-F02"])]:
    assert [f["id"] for f in ready(board)[:validate_config(
        {"fix_lane":{"max_parallel":cap,"shared_paths":[]}})[0]]] == expected
for bad in [0,-1,1.5,"2",""]:
    snap = json.dumps(board, sort_keys=True)
    try: validate_config({"fix_lane":{"max_parallel":bad}})
    except ValueError as e: assert "max_parallel" in str(e)
    else: raise AssertionError("accepted cap " + repr(bad))
    assert json.dumps(board, sort_keys=True) == snap

valid = ["docs/generated/*","README.md","a/b/*"]
for p in valid:
    validate_config({"fix_lane":{"shared_paths":[p]}})
bad_patterns = [
    "", "/x", ".", "./x", "../x", "a/../b", "a//b", "a/", "*",
    "a/**", "a/*.sh", "a\nb"
]
for bad in bad_patterns:
    snap = json.dumps(board, sort_keys=True)
    try: validate_config({"fix_lane":{"shared_paths":[bad]}})
    except ValueError as e: assert "shared_paths" in str(e)
    else: raise AssertionError("accepted pattern " + repr(bad))
    assert json.dumps(board, sort_keys=True) == snap
for bad in ["scalar", {"x":"y"}, [1]]:
    try: validate_config({"fix_lane":{"shared_paths":bad}})
    except ValueError: pass
    else: raise AssertionError("accepted shared_paths " + repr(bad))

_, pats = validate_config({"fix_lane":{"shared_paths":["docs/generated/*"]}})
assert classify(["src/a.sh"], pats)[0] == "parallel"
for paths in [["harness-install.sh"],["tests/test_install.sh"],["tools/new.sh"],
              ["docs/generated/a.md"]]:
    assert classify(paths, pats)[0] == "guarded"
for paths, missing in [([],False),([],True),(["/x"],False),
                       (["../x"],False),(["ambiguous prose *"],False)]:
    mode, reason = classify(paths, pats, missing)
    assert mode == "guarded" and reason

selected = ready(board)[:2]
manifest = []
for f in ready(board):
    if f in selected:
        mode, reason = classify(["src/" + f["id"] + ".txt"], pats)
        manifest.append((f["id"], mode + "-selected", reason))
    else:
        manifest.append((f["id"], "cap-deferred", ""))
assert [x[0] for x in manifest] == ["E99-F01","E99-F02","E99-F10"]
assert len(manifest) == len(ready(board))

no_ready = copy.deepcopy(board)
for f in no_ready["epics"][1]["features"]: f["status"] = "done"
before = json.dumps(no_ready, sort_keys=True)
assert ready(no_ready) == []
assert json.dumps(no_ready, sort_keys=True) == before
assert not list(tmp.glob("E99-fix-parallel-*"))
PY
then
  fail "fixture behavior failed"
fi
pass "R1/R2/R3/R5/R6/R10/R15/R19 deterministic fixture behavior"

# test_atomic_rechecked_batch_claim
# R4: exercise the actual F01 apply helper with explicit HARNESS_DIR. One
# mutator claims three ids atomically; a stale predicate on the second run leaves
# every member of that batch unchanged.
mkdir -p "$TMP/harness/state" "$TMP/harness/store" "$TMP/harness/tools"
cp store/tasks.schema.json "$TMP/harness/store/"
cp tools/tasks-lock.py tools/validate-board.py "$TMP/harness/tools/"
cat > "$TMP/harness/state/tasks.json" <<'JSON'
{"project":"fixture","epics":[
{"id":"E01","title":"Dependency","status":"done","features":[
{"id":"E01-F01","title":"dependency","status":"done","sdd":true,"autonomous":true,"depends_on":[],"spec_path":"x/"}]},
{"id":"E99","title":"Maintenance","status":"planned","features":[
{"id":"E99-F01","title":"one","status":"pending","sdd":false,"autonomous":true,"depends_on":[],"spec_path":"x/"},
{"id":"E99-F02","title":"two","status":"pending","sdd":false,"autonomous":true,"depends_on":[],"spec_path":"x/"},
{"id":"E99-F03","title":"three","status":"pending","sdd":false,"autonomous":true,"depends_on":[],"spec_path":"x/"},
{"id":"E99-F04","title":"four","status":"pending","sdd":false,"autonomous":true,"depends_on":["E01-F01"],"spec_path":"x/"},
{"id":"E99-F05","title":"five","status":"pending","sdd":false,"autonomous":true,"depends_on":[],"spec_path":"x/"}]}]}
JSON
cat > "$TMP/claim.py" <<'PY'
IDS = ["E99-F01", "E99-F02", "E99-F03"]
def mutate(data):
    epic = next(e for e in data["epics"] if e["id"] == "E99")
    found = {f["id"]: f for f in epic["features"]}
    for ident in IDS:
        f = found[ident]
        assert f["status"] == "pending" and f["sdd"] is False
        assert f["autonomous"] is True
        assert not f.get("depends_on")
    for ident in IDS: found[ident]["status"] = "in-progress"
    return data
PY
HARNESS_DIR="$TMP/harness" python3 "$TMP/harness/tools/tasks-lock.py" apply --mutator "$TMP/claim.py" >/dev/null
python3 - "$TMP/harness/state/tasks.json" <<'PY' || fail "R4: valid batch did not claim atomically"
import json,sys
d=json.load(open(sys.argv[1]))
fs=next(e for e in d["epics"] if e["id"] == "E99")["features"]
assert [f["status"] for f in fs[:3]] == ["in-progress"]*3
PY
cat > "$TMP/stale.py" <<'PY'
IDS = ["E99-F04", "E99-F05"]
def mutate(data):
    epic = next(e for e in data["epics"] if e["id"] == "E99")
    found = {f["id"]: f for f in epic["features"]}
    all_features = {
        f["id"]: f for e in data["epics"] for f in e.get("features", [])
    }
    for ident in IDS:
        f = found[ident]
        assert f["status"] == "pending" and f["sdd"] is False
        assert f["autonomous"] is True
        assert all(
            dep in all_features and all_features[dep]["status"] == "done"
            for dep in f.get("depends_on", [])
        )
    for ident in IDS: found[ident]["status"] = "in-progress"
    return data
PY
python3 - "$TMP/harness/state/tasks.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["epics"][0]["features"][0]["status"]="pending"
open(p,"w").write(json.dumps(d,separators=(",",":"))+"\n")
PY
cp "$TMP/harness/state/tasks.json" "$TMP/before.json"
if HARNESS_DIR="$TMP/harness" python3 "$TMP/harness/tools/tasks-lock.py" apply --mutator "$TMP/stale.py" >/dev/null 2>&1; then
  fail "R4: stale batch claim unexpectedly succeeded"
fi
cmp -s "$TMP/before.json" "$TMP/harness/state/tasks.json" ||
  fail "R4: failed batch claim partially changed the board"
pass "R4 atomic fresh-board batch claim including stale dependency race"

# test_real_bookkeeping_merge_and_exact_teardown_lifecycle
# R11/R14: exercise the real F02 helper and F01 lock helper in a disposable
# source-layout repository. The one provisioned fix worktree is retained through
# claim/code merge/final done persistence. A coordinator bookkeeping branch is
# merged through a simulated PR, the canonical base is fast-forwarded, and only
# then does exact non-forced F02 teardown run. An unrelated branch/worktree must
# survive byte-for-byte and registration-for-registration.
LIFE="$TMP/lifecycle"
REMOTE="$TMP/lifecycle.git"
INTEGRATOR="$TMP/integrator"
mkdir -p "$LIFE/tools" "$LIFE/store" "$LIFE/state" "$LIFE/src"
cp tools/fix-worktree.sh tools/tasks-lock.py tools/validate-board.py "$LIFE/tools/"
cp store/tasks.schema.json "$LIFE/store/"
cat > "$LIFE/init.sh" <<'SH'
#!/bin/sh
set -eu
export PYTHONDONTWRITEBYTECODE=1
python3 tools/validate-board.py state/tasks.json store/tasks.schema.json >/dev/null
SH
chmod +x "$LIFE/init.sh" "$LIFE/tools/fix-worktree.sh" "$LIFE/tools/tasks-lock.py"
cat > "$LIFE/.gitignore" <<'EOF'
/.claude/worktrees/
/state/tasks.json.lock
**/__pycache__/
EOF
cat > "$LIFE/state/tasks.json" <<'JSON'
{"project":"fixture","epics":[
{"id":"E01","title":"Unrelated","status":"planned","features":[
{"id":"E01-F01","title":"keep","status":"pending","sdd":true,"autonomous":false,"depends_on":[],"spec_path":"x/"}]},
{"id":"E99","title":"Maintenance","status":"planned","features":[
{"id":"E99-F900","title":"fix","status":"pending","sdd":false,"autonomous":true,"depends_on":[],"spec_path":"x/"}]}]}
JSON
echo base > "$LIFE/src/base.txt"
git -C "$LIFE" init -q -b main
git -C "$LIFE" config user.name fixture
git -C "$LIFE" config user.email fixture@example.invalid
git -C "$LIFE" add .
git -C "$LIFE" commit -qm base
git init -q --bare "$REMOTE"
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git -C "$LIFE" remote add origin "$REMOTE"
git -C "$LIFE" push -q -u origin main

git -C "$LIFE" branch unrelated
git -C "$LIFE" worktree add -q "$TMP/unrelated-wt" unrelated
UNRELATED_WT="$(CDPATH= cd -- "$TMP/unrelated-wt" && pwd -P)"
UNRELATED_HEAD="$(git -C "$UNRELATED_WT" rev-parse HEAD)"
UNRELATED_FILE="$(cat "$UNRELATED_WT/src/base.txt")"

CREATE_COUNT="$TMP/create-count"
printf '0\n' > "$CREATE_COUNT"
counted_create() {
  _n="$(cat "$CREATE_COUNT")"
  printf '%s\n' "$((_n + 1))" > "$CREATE_COUNT"
  "$LIFE/tools/fix-worktree.sh" create E99-F900 lifecycle --base main
}
FIX_WT="$(cd "$LIFE" && counted_create)"
[ "$(cat "$CREATE_COUNT")" -eq 1 ] ||
  fail "R11: F02 create did not occur exactly once before claim"

git -C "$LIFE" switch -qc bookkeeping/E99-fix-parallel
cat > "$TMP/lifecycle-claim.py" <<'PY'
def mutate(data):
    fs = next(e for e in data["epics"] if e["id"] == "E99")["features"]
    f = next(f for f in fs if f["id"] == "E99-F900")
    assert f["status"] == "pending" and f["sdd"] is False
    assert f["autonomous"] is True
    f["status"] = "in-progress"
    return data
PY
HARNESS_DIR="$LIFE" python3 "$LIFE/tools/tasks-lock.py" apply \
  --mutator "$TMP/lifecycle-claim.py" >/dev/null
git -C "$LIFE" add state/tasks.json
git -C "$LIFE" commit -qm "claim E99-F900"

echo fixed > "$FIX_WT/src/fix.txt"
git -C "$FIX_WT" add src/fix.txt
git -C "$FIX_WT" commit -qm "fix E99-F900"
git -C "$FIX_WT" push -q origin feat/E99-F900-lifecycle
git clone -q "$REMOTE" "$INTEGRATOR"
git -C "$INTEGRATOR" config user.name fixture
git -C "$INTEGRATOR" config user.email fixture@example.invalid
git -C "$INTEGRATOR" fetch -q origin feat/E99-F900-lifecycle
git -C "$INTEGRATOR" merge -q --no-ff origin/feat/E99-F900-lifecycle \
  -m "merge code PR"
git -C "$INTEGRATOR" push -q origin main

cat > "$TMP/lifecycle-done.py" <<'PY'
def mutate(data):
    fs = next(e for e in data["epics"] if e["id"] == "E99")["features"]
    f = next(f for f in fs if f["id"] == "E99-F900")
    assert f["status"] == "in-progress"
    f["status"] = "done"
    return data
PY
HARNESS_DIR="$LIFE" python3 "$LIFE/tools/tasks-lock.py" apply \
  --mutator "$TMP/lifecycle-done.py" >/dev/null
git -C "$LIFE" add state/tasks.json
git -C "$LIFE" commit -qm "persist final done state"
git -C "$LIFE" push -q origin bookkeeping/E99-fix-parallel
git -C "$INTEGRATOR" fetch -q origin bookkeeping/E99-fix-parallel
git -C "$INTEGRATOR" merge -q --no-ff \
  origin/bookkeeping/E99-fix-parallel -m "merge bookkeeping PR"
git -C "$INTEGRATOR" push -q origin main

git -C "$LIFE" fetch -q origin main
git -C "$LIFE" switch -q main
git -C "$LIFE" merge -q --ff-only origin/main
[ -z "$(git -C "$LIFE" status --porcelain --untracked-files=all)" ] ||
  fail "R14: canonical primary not clean after bookkeeping reconciliation"
[ "$(git -C "$LIFE" rev-parse HEAD)" = "$(git -C "$LIFE" rev-parse origin/main)" ] ||
  fail "R14: canonical primary not on updated captured base"
[ "$(cat "$CREATE_COUNT")" -eq 1 ] ||
  fail "R11: targeted lifecycle repeated F02 create"
(cd "$LIFE" && "$LIFE/tools/fix-worktree.sh" teardown \
  E99-F900 lifecycle --base main)
[ ! -e "$FIX_WT" ] ||
  fail "R14: exact merged fix worktree survived teardown"
if git -C "$LIFE" show-ref --verify --quiet refs/heads/feat/E99-F900-lifecycle; then
  fail "R14: exact merged fix branch survived teardown"
fi
[ "$(git -C "$UNRELATED_WT" rev-parse HEAD)" = "$UNRELATED_HEAD" ] ||
  fail "R14: unrelated worktree HEAD changed"
[ "$(cat "$UNRELATED_WT/src/base.txt")" = "$UNRELATED_FILE" ] ||
  fail "R14: unrelated worktree contents changed"
git -C "$LIFE" show-ref --verify --quiet refs/heads/unrelated ||
  fail "R14: unrelated branch was removed"
git -C "$LIFE" worktree list --porcelain |
  grep -qF "worktree $UNRELATED_WT" ||
  fail "R14: unrelated worktree registration was removed"
pass "R11/R14 real bookkeeping PR reconciliation and exact teardown lifecycle"

# test_installed_manifest_waits_for_all_provisioning
# Codex P1 #3651111576: in an installed consumer, .harness/progress is durable
# tracked state. Exercise the real installed-layout F02 helper and prove every
# selected create sees a clean canonical checkout. Only after all creates have
# settled may the coordinator write the complete pre-dispatch manifest; that
# manifest must precede claim/dispatch and retain guarded, failed, and deferred
# classifications.
INSTALLED="$TMP/installed-manifest-order"
mkdir -p "$INSTALLED/.harness/tools" "$INSTALLED/.harness/progress"
cp tools/fix-worktree.sh "$INSTALLED/.harness/tools/"
chmod +x "$INSTALLED/.harness/tools/fix-worktree.sh"
cat > "$INSTALLED/.harness/init.sh" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$INSTALLED/.harness/init.sh"
printf '.claude/worktrees/\n' > "$INSTALLED/.gitignore"
git -C "$INSTALLED" init -q -b main
git -C "$INSTALLED" config user.email test@example.com
git -C "$INSTALLED" config user.name "Test User"
git -C "$INSTALLED" add .
git -C "$INSTALLED" commit -qm "installed fixture"

ORDER="$TMP/installed-manifest-order.log"
MANIFEST="$INSTALLED/.harness/progress/E99-fix-parallel-20260101T000000Z/summary.md"
for _case in \
  "E99-F701 parallel" \
  "E99-F702 guarded" \
  "E99-F703 fails"; do
  set -- $_case
  _id=$1
  _slug=$2
  [ ! -e "$MANIFEST" ] ||
    fail "P1: installed manifest dirtied primary before all F02 creates settled"
  [ -z "$(git -C "$INSTALLED" status --porcelain --untracked-files=all)" ] ||
    fail "P1: installed canonical primary was dirty before F02 create $_id"
  printf 'provision:%s\n' "$_id" >> "$ORDER"
  if [ "$_id" = "E99-F703" ]; then
    git -C "$INSTALLED" branch "feat/$_id-$_slug" main
    if (cd "$INSTALLED" && .harness/tools/fix-worktree.sh create "$_id" "$_slug" >/dev/null 2>&1); then
      fail "P1: installed provisioning-failure fixture unexpectedly succeeded"
    fi
  else
    (cd "$INSTALLED" && .harness/tools/fix-worktree.sh create "$_id" "$_slug" >/dev/null) ||
      fail "P1: installed F02 create failed for $_id"
  fi
done

mkdir -p "$(dirname "$MANIFEST")"
cat > "$MANIFEST" <<'MD'
# Parallel fix batch
- E99-F701: parallel-selected; provisioned
- E99-F702: guarded-selected; provisioned; shared path tools/*
- E99-F703: parallel-selected; provisioning-failed; branch already exists
- E99-F704: cap-deferred
MD
printf 'manifest\nclaim\ndispatch\n' >> "$ORDER"
if ! python3 - "$ORDER" "$MANIFEST" <<'PY'
import pathlib, sys
order = pathlib.Path(sys.argv[1]).read_text().splitlines()
manifest = pathlib.Path(sys.argv[2]).read_text()
assert order == [
    "provision:E99-F701",
    "provision:E99-F702",
    "provision:E99-F703",
    "manifest",
    "claim",
    "dispatch",
]
for expected in (
    "E99-F701: parallel-selected; provisioned",
    "E99-F702: guarded-selected; provisioned; shared path tools/*",
    "E99-F703: parallel-selected; provisioning-failed; branch already exists",
    "E99-F704: cap-deferred",
):
    assert expected in manifest
PY
then
  fail "P1: installed provisioning/manifest/claim/dispatch ordering failed"
fi
pass "P1 installed manifest follows all F02 provisioning and precedes claim/dispatch"

# Named traceability cases exercised by the ordered durable-contract checks:
# test_native_safe_wave_fanout_contract
# test_guarded_wave_is_exclusive_and_ordered
# test_missing_concurrency_capability_fails_before_mutation
# test_worktree_provisioning_and_failure_contract
# test_worker_harness_dir_and_locked_writes
# test_targeted_worker_and_failure_isolation_contract
# test_pr_before_done_and_per_pr_loop_contract
# test_aggregate_exit_semantics
# Durable coordinator/worker contract. Exact phase anchors also make order
# mechanically checkable instead of relying on broad keyword presence.
[ -f "$CMD" ] || fail "R1: source parallel command missing"
need "$CMD" 'agents/fixer.md' "R1: command does not resolve Fixer"
need "$CMD" 'argument-free' "R1: command is not argument-free"
for anchor in \
  'P1 — capability and config preflight' \
  'P2 — provision selected worktrees while primary is clean' \
  'P3 — complete pre-dispatch manifest' \
  'P4 — atomic locked batch claim' \
  'P5 — parallel-safe fan-out before any wait' \
  'P6 — guarded exclusive wave' \
  'P7 — aggregate report and exit'; do
  need "$FIXER" "$anchor" "R7/R8/R10/R11/R20: missing phase anchor $anchor"
done
python3 - "$FIXER" <<'PY' || fail "phase anchors are out of order"
import sys
s=open(sys.argv[1]).read()
anchors=[
"P1 — capability and config preflight",
"P2 — provision selected worktrees while primary is clean",
"P3 — complete pre-dispatch manifest",
"P4 — atomic locked batch claim","P5 — parallel-safe fan-out before any wait",
"P6 — guarded exclusive wave","P7 — aggregate report and exit"]
assert [s.index(x) for x in anchors] == sorted(s.index(x) for x in anchors)
PY
need "$FIXER" 'Start every parallel-safe targeted worker before awaiting any one' "R7: fan-out-before-wait missing"
need "$FIXER" 'one-at-a-time in numeric feature-id order' "R8: guarded ordering missing"
need "$FIXER" 'no ready E99 fixes' "R19: no-ready message missing"
need "$FIXER" 'serial `/sdd-fix`' "R9: serial fallback missing"
need "$FIXER" '`execution.builder.backend: delegate`' "R9/R14: delegate preflight missing"
need "$FIXER" 'continue every sibling' "R13/R20: sibling continuation missing"
need "$FIXER" 'exit non-zero' "R20: aggregate non-zero missing"
need "$FIXER" 'cap-deferred' "R10/R20: cap deferral missing"
need "$FIXER" 'tools/fix-worktree.sh create' "R11: F02 create missing"
need "$FIXER" 'tools/tasks-lock.py' "R4/R12: F01 helper missing"
need "$FIXER" 'HARNESS_DIR="$HARNESS_MAIN"' "R12: canonical HARNESS_DIR missing"
pass "R7/R8/R9/R10/R11/R12/R13/R20 coordinator ordering contract"

need "$ORCH" 'Targeted parallel-fix worker mode' "R13: targeted worker mode missing"
need "$ORCH" 'never call global `next()`' "R13: targeted mode does not disable next()"
need "$ORCH" 'clean Builder context' "R13: clean Builder context missing"
need "$ORCH" 'clean Reviewer context' "R13: clean Reviewer context missing"
need "$ORCH" 'file-based feedback' "R13: feedback rounds missing"
need "$ORCH" 'pre-provisioned branch and worktree' "R11/R14: pre-provisioned identity missing"
need "$ORCH" 'must not call `tools/fix-worktree.sh create`' "R11: duplicate create prohibition missing"
need "$ORCH" 'create only its dedicated PR' "R14: post-review PR-only creation missing"
need "$ORCH" 'per-PR `/sdd-pr-loop`' "R14: per-PR review loop missing"
need "$ORCH" 'observed merged result' "R14: merge observation missing"
need "$ORCH" 'report `merge-observed`' "R14: merge handoff missing"
need "$ORCH" 'preserve its status, branch, worktree, and PR URL' "R13/R14: recoverability missing"
python3 - "$ORCH" <<'PY' || fail "R11: targeted worker repeats F02 creation"
import sys
s=open(sys.argv[1]).read()
section=s.split("## Targeted parallel-fix worker mode",1)[1].split("\n## ",1)[0]
assert section.count("tools/fix-worktree.sh create") == 1
assert "must not call `tools/fix-worktree.sh create`" in section
PY
pass "R13/R14 targeted per-fix lifecycle contract"

# test_serial_brief_expected_paths
# Serial intake and source/installed command bodies must carry expected paths.
need "$FIXER" '## Files expected to change' "R16: Fixer brief lacks expected paths"
need "$SERIAL" '## Files expected to change' "R16: source serial command lacks expected paths"
need "$SERIAL" 'normalized repo-relative' "R16: serial path normalization missing"
pass "R16 serial brief expected-path intake"

# Reject vendor-specific/background-process implementation instructions.
if grep -Eqi 'Claude Task API|Codex collaboration API|agent prompts?.*(shell &|background)' "$FIXER" "$ORCH" "$CMD"; then
  fail "R9: contract prescribes a vendor API or background agent prompt"
fi
pass "R9 portable native-concurrency contract"

# test_docs_config_and_version_policy
# R18: config/docs/version policy. Locate the stable E15-F03 changelog section,
# compare it with the immediately older heading, and permit later VERSION values.
grep -Eq '^fix_lane:' harness.config.yaml || fail "R2: fix_lane config missing"
grep -Eq '^[[:space:]]+max_parallel:[[:space:]]+3' harness.config.yaml || fail "R2: max_parallel default missing"
grep -Eq '^[[:space:]]+shared_paths:[[:space:]]+\[\]' harness.config.yaml || fail "R5: shared_paths default missing"
# verification.test_command now delegates to tools/run-tests.sh, which DISCOVERS every
# tests/test_*.sh. The intent of this check is "this suite is not orphaned", so accept
# either spelling: an explicit mention, or the discovering runner plus the file existing.
_tc_value() {  # echo the test_command scalar only — never the surrounding comments
  sed -n 's/^[[:space:]]*test_command:[[:space:]]*"\([^"]*\)".*$/\1/p' "$1"
}
_tc="$(_tc_value harness.config.yaml)"
{ printf '%s\n' "$_tc" | grep -qF 'sh tests/test_sdd_fix_parallel.sh' \
    || { printf '%s\n' "$_tc" | grep -qF 'tools/run-tests.sh' && [ -f tests/test_sdd_fix_parallel.sh ]; }; } \
  || fail "R18: suite not reachable from full verification"
for f in README.md docs/WORKFLOW.md docs/INSTALL.md; do
  need "$f" '/sdd-fix-parallel' "R18: $f does not document command"
done
python3 - VERSION CHANGELOG.md <<'PY' || fail "R18: E15-F03 MINOR version policy failed"
import re,sys
current=tuple(map(int,open(sys.argv[1]).read().strip().split(".")))
text=open(sys.argv[2]).read()
heads=[(m.start(),tuple(map(int,m.group(1).split("."))))
       for m in re.finditer(r"^## \[(\d+\.\d+\.\d+)\]",text,re.M)]
pos=text.index("E15-F03")
idx=next(i for i,(p,v) in enumerate(heads) if p < pos and (i+1==len(heads) or heads[i+1][0] > pos))
feature=heads[idx][1]
older=heads[idx+1][1]
assert feature[0] == older[0] and feature[1] == older[1]+1 and feature[2] == 0
assert current >= feature
PY
pass "R18 config docs and version policy"

echo "All sdd-fix-parallel tests passed."
