#!/bin/sh
# test_next_task.sh — E16-F03 deterministic next-task selection contract
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TOOL="$ROOT/tools/next-task.mjs"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-next-task.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); echo "PASS: $*"; }
STATE_BEFORE=$(cksum "$ROOT/state/tasks.json")

write_config() {
  approval=$1 identity=${2-} manifest=${3-}
  cat >"$TMP/config.yaml" <<EOF
workflow:
  require_spec_approval: $approval
  identity: "$identity"
umbrella:
  manifest: "$manifest"
EOF
}

write_board() {
  cat >"$TMP/tasks.json"
}

run_tool() {
  node "$TOOL" --tasks "$TMP/tasks.json" --config "$TMP/config.yaml" "$@"
}

json_field() {
  python3 -c 'import json,sys; x=json.load(sys.stdin); print(eval(sys.argv[1], {"x":x}))' "$1"
}

# test_cli_contract_and_default_json (RED before tools/next-task.mjs exists)
write_config true
write_board <<'JSON'
{"project":"fixture","epics":[{"id":"E1","title":"one","status":"planned","features":[
  {"id":"E1-F1","title":"first","status":"pending","sdd":true,"spec_path":"specs/f1/"}
]}]}
JSON
out=$(run_tool) || fail "valid invocation failed"
[ "$(printf '%s' "$out" | json_field 'x["schema_version"]')" = 1 ] ||
  fail "schema_version is not 1"
[ "$(printf '%s' "$out" | json_field 'x["selected"]["feature_id"]')" = E1-F1 ] ||
  fail "pending SDD feature was not selected"
[ "$(printf '%s' "$out" | json_field 'x["selected"]["route"]')" = architect ] ||
  fail "pending SDD feature did not route to architect"
[ "$out" = "$(run_tool --json)" ] || fail "--json is not an exact no-op"
if run_tool stray >"$TMP/bad.out" 2>"$TMP/bad.err"; then
  fail "positional token was accepted"
fi
[ "$(json_field 'x["outcome"]' <"$TMP/bad.out")" = error ] ||
  fail "usage failure did not emit JSON error envelope"
[ -s "$TMP/bad.err" ] || fail "usage failure did not diagnose on stderr"
pass "R1 strict CLI and default JSON envelope"

# test_source_and_installed_path_resolution (source half): defaults follow script,
# never caller cwd. Installed half lives in tests/test_install.sh.
source_here=$(node "$TOOL" --json) || fail "source default-path invocation failed"
source_elsewhere=$(cd / && node "$TOOL" --json) ||
  fail "source default paths depend on caller cwd"
[ "$source_here" = "$source_elsewhere" ] ||
  fail "source default output differs by caller cwd"
pass "R2 source defaults resolve from the selector path"

# Direct malformed JSON/unreadable-path cases cannot be represented by the Python
# object's table below.
printf '{bad json\n' >"$TMP/invalid.json"
if node "$TOOL" --tasks "$TMP/invalid.json" --config "$TMP/config.yaml" \
  >"$TMP/invalid.out" 2>"$TMP/invalid.err"
then
  fail "invalid TaskStore JSON succeeded"
fi
[ "$(json_field 'x["outcome"]' <"$TMP/invalid.out")" = error ] ||
  fail "invalid JSON lacks error envelope"
grep -qF 'invalid TaskStore JSON' "$TMP/invalid.err" ||
  fail "invalid JSON diagnostic is not actionable"
if node "$TOOL" --tasks "$TMP/does-not-exist.json" --config "$TMP/config.yaml" \
  >"$TMP/unreadable.out" 2>"$TMP/unreadable.err"
then
  fail "unreadable TaskStore path succeeded"
fi
grep -qF 'cannot read TaskStore' "$TMP/unreadable.err" ||
  fail "unreadable TaskStore diagnostic is not actionable"
pass "R13 malformed and unreadable direct inputs fail closed"

python3 - "$TOOL" "$TMP" "$ROOT" <<'PY'
import copy, hashlib, json, os, pathlib, subprocess, sys, time

tool, tmp, root = sys.argv[1:]
tmp = pathlib.Path(tmp)
manifest = tmp / "umbrella.yaml"
manifest.write_text("repos:\n  api:\n    path: ../api\n  web:\n    path: ../web\n")

def config(approval=True, identity="", manifest_path=""):
    return (
        "workflow:\n"
        f"  require_spec_approval: {'true' if approval else 'false'}\n"
        f'  identity: "{identity}"\n'
        "umbrella:\n"
        f'  manifest: "{manifest_path}"\n'
    )

def feature(fid, status="pending", sdd=True, **kw):
    out = {"id": fid, "title": fid, "status": status, "sdd": sdd,
           "spec_path": f"specs/{fid}/"}
    out.update(kw)
    return out

def epic(eid, features, status="planned", **kw):
    out = {"id": eid, "title": eid, "status": status, "features": features}
    out.update(kw)
    return out

def board(epics):
    return {"project": "fixture", "epics": epics}

def expected(mode, outcome, selected, code, detail, blocked=None, summary=None):
    return {"schema_version": 1, "mode": mode, "outcome": outcome,
            "selected": selected, "reason": {"code": code, "detail": detail},
            "blocked": blocked or [], "summary": summary}

def selected(fid, status, route, sid=None):
    return {"feature_id": fid, "slice_id": sid,
            "kind": "slice" if sid else "feature", "status": status, "route": route}

def call(data, cfg=None, args=(), env=None, expect_rc=0):
    tasks = tmp / "matrix.json"
    cfg_path = tmp / "matrix.yaml"
    tasks.write_text(json.dumps(data, separators=(",", ":")))
    cfg_path.write_text(cfg if cfg is not None else config())
    before = (tasks.read_bytes(), cfg_path.read_bytes(),
              manifest.read_bytes() if manifest.exists() else b"")
    cmd = ["node", tool, "--tasks", str(tasks), "--config", str(cfg_path), *args]
    run = subprocess.run(cmd, text=True, capture_output=True, env=env)
    if run.returncode != expect_rc:
        raise AssertionError(f"{cmd}: rc={run.returncode}, stderr={run.stderr}, stdout={run.stdout}")
    try:
        value = json.loads(run.stdout)
    except Exception as error:
        raise AssertionError(f"non-JSON stdout {run.stdout!r}: {error}")
    if run.stdout != json.dumps(value, separators=(",", ":")) + "\n":
        raise AssertionError(f"output is not one compact newline-terminated JSON object: {run.stdout!r}")
    after = (tasks.read_bytes(), cfg_path.read_bytes(),
             manifest.read_bytes() if manifest.exists() else b"")
    if before != after:
        raise AssertionError("selector mutated an input")
    if expect_rc == 0 and run.stderr:
        raise AssertionError(f"successful result wrote stderr: {run.stderr!r}")
    if expect_rc != 0 and not run.stderr.startswith("next-task: "):
        raise AssertionError(f"error lacks actionable stderr: {run.stderr!r}")
    return value, run

def assert_eq(actual, want, label):
    if actual != want:
        raise AssertionError(f"{label}\nwant={json.dumps(want, sort_keys=True)}\n got={json.dumps(actual, sort_keys=True)}")

# Independent route oracle: expected values are generated solely from the prose table.
route_cases = [
    ("pending-sdd", feature("E1-F1", "pending", True), True, "architect"),
    ("pending-quick-auto", feature("E1-F1", "pending", False, autonomous=True), True, "builder"),
    ("spec-ready-auto", feature("E1-F1", "spec-ready", True, autonomous=True), True, "builder"),
    ("spec-ready-approval-off", feature("E1-F1", "spec-ready", True), False, "builder"),
    ("in-progress", feature("E1-F1", "in-progress"), True, "builder"),
    ("in-review", feature("E1-F1", "in-review"), True, "reviewer"),
]
for label, item, approval, route in route_cases:
    got, _ = call(board([epic("E1", [item])]), config(approval))
    assert_eq(got, expected("board", "selected", selected("E1-F1", item["status"], route),
                           "feature-actionable", f"route {route} for E1-F1 at status {item['status']}"),
              f"feature route oracle: {label}")
for epic_status in ("pending", "planned", "in-progress", "done"):
    value, _ = call(board([epic("E1", [feature("E1-F1")], status=epic_status)]))
    assert value["selected"]["route"] == "architect", f"epic alias {epic_status}"

blocked_cases = [
    (feature("E1-F1", "pending", False), "human-gate", "gated quick fix requires approval"),
    (feature("E1-F1", "spec-ready", True), "human-gate", "spec-ready requires approval"),
]
for item, code, detail in blocked_cases:
    got, _ = call(board([epic("E1", [item])]))
    assert_eq(got["blocked"], [{"subject": "E1-F1", "code": code, "detail": detail}],
              f"human gate {item['status']}")
    assert got["summary"] == "no actionable work: selection blocked; see reasons above"

# Draft, missing/cross-kind/non-done dependencies, cycle + unmet together.
cycle_board = board([
    epic("E1", [
        feature("E1-F1", depends_on=["E1-F2", "E1-F1@api"]),
        feature("E1-F2", status="in-progress", depends_on=["E1-F1"]),
        feature("E1-F3", status="done"),
    ], status="draft"),
])
got, _ = call(cycle_board)
assert_eq(got["blocked"], [
    {"subject":"E1-F1","code":"dependency-cycle","detail":"dependency cycle (feature): E1-F1 -> E1-F2 -> E1-F1"},
    {"subject":"E1-F1","code":"gated-epic","detail":"epic E1 is draft"},
    {"subject":"E1-F1","code":"unmet-dependency","detail":"blocking dependencies: E1-F1@api=missing, E1-F2=in-progress"},
    {"subject":"E1-F2","code":"dependency-cycle","detail":"dependency cycle (feature): E1-F1 -> E1-F2 -> E1-F1"},
    {"subject":"E1-F2","code":"gated-epic","detail":"epic E1 is draft"},
    {"subject":"E1-F2","code":"unmet-dependency","detail":"blocking dependencies: E1-F1=pending"},
], "feature dependency diagnostics")
self_cycle, _ = call(board([epic("E1", [
    feature("E1-F1", depends_on=["E1-F1"])
])]))
assert self_cycle["blocked"][0]["detail"] == "dependency cycle (feature): E1-F1 -> E1-F1"

# Numeric order, input-order independence, and literal tie-break.
ordered_board = board([
    epic("E10", [feature("E10-F2")]),
    epic("E2", [feature("E2-F10")]),
    epic("E01", [feature("E01-F1")]),
    epic("E1", [feature("E1-F01")]),
])
got1, _ = call(ordered_board)
reversed_board = copy.deepcopy(ordered_board)
reversed_board["epics"].reverse()
got2, _ = call(reversed_board)
assert got1 == got2
assert got1["selected"]["feature_id"] == "E01-F1"

# Terminal and target precedence.
empty, _ = call(board([]), config(identity="@me"), args=("--mine",))
assert empty["summary"] == "no actionable work [no-candidates]: board has no features"
all_done, _ = call(board([epic("E1", [feature("E1-F1", "done")])]), config(identity="@me"), args=("--mine",))
assert all_done["summary"] == "no actionable work [no-candidates]: all features are done"
target_done_board = board([epic("E1", [feature("E1-F1"), feature("E1-F2", "done")])])
target_done, _ = call(target_done_board, args=("--feature", "E1-F2"))
assert target_done["outcome"] == "complete" and target_done["summary"] == "target E1-F2 is already done"
missing, _ = call(target_done_board, args=("--feature", "E1-F9"), expect_rc=1)
assert missing["outcome"] == "error" and missing["reason"]["code"] == "input-error"
target_block, _ = call(board([epic("E1", [feature("E1-F1"), feature("E1-F2", "spec-ready")])]),
                       args=("--feature", "E1-F2"))
assert [r["subject"] for r in target_block["blocked"]] == ["E1-F2"]

# Owner oracle, including feature-over-epic and no widening.
owner_board = board([
    epic("E1", [feature("E1-F1"), feature("E1-F2", owner="alice"),
                feature("E1-F3")], owner="alice"),
])
mine, _ = call(owner_board, config(identity="alice"), args=("--mine",))
assert mine["selected"]["feature_id"] == "E1-F1"
bare, _ = call(board([epic("E1", [feature("E1-F1", owner="other")])]), config(identity="alice"))
assert bare["selected"]["feature_id"] == "E1-F1"
target_owner, _ = call(board([epic("E1", [feature("E1-F1", owner="other")])]),
                       config(identity="alice"), args=("--feature", "E1-F1"))
assert target_owner["selected"]["feature_id"] == "E1-F1"
excluded, _ = call(board([epic("E1", [feature("E1-F1", owner="other"), feature("E1-F2")])]),
                   config(identity="alice"), args=("--mine",))
assert_eq(excluded["blocked"], [
    {"subject":"E1-F1","code":"owner-excluded","detail":"effective owner=other"},
    {"subject":"E1-F2","code":"owner-excluded","detail":"effective owner=unowned"},
], "owner excluded records")
unresolved, _ = call(owner_board, config(identity=""), args=("--mine",))
assert_eq(unresolved["blocked"], [{"subject":"--mine","code":"owner-unresolved","detail":"workflow.identity=<empty>"}],
          "empty identity")

ghdir = tmp / "bin"; ghdir.mkdir(exist_ok=True)
gh = ghdir / "gh"
gh.write_text("#!/bin/sh\nprintf 'alice\\n'\n"); gh.chmod(0o755)
stub_env = dict(os.environ, PATH=f"{ghdir}:{os.environ['PATH']}")
for dynamic in ("@me", "self"):
    dynamic_result, _ = call(owner_board, config(identity=dynamic), args=("--mine",), env=stub_env)
    assert dynamic_result["selected"]["feature_id"] == "E1-F1"
gh.write_text("#!/bin/sh\nexit 9\n")
for dynamic in ("@me", "self"):
    failed_gh, _ = call(owner_board, config(identity=dynamic), args=("--mine",), env=stub_env)
    assert failed_gh["blocked"][0]["detail"] == f"workflow.identity={dynamic} lookup failed"

# Umbrella switch and complete slice precedence/oracle.
slices = [
    {"id":"E1-F1@web","repo":"web","status":"in-progress","depends_on":["E1-F1@api"]},
    {"id":"E1-F1@api","repo":"api","status":"pending"},
]
sliced_board = board([epic("E1", [feature("E1-F1", "in-progress", slices=slices)])])
inert, _ = call(sliced_board, config(manifest_path=str(tmp / "absent.yaml")))
assert inert["selected"]["kind"] == "feature"
active, _ = call(sliced_board, config(manifest_path=str(manifest)))
assert active["selected"]["slice_id"] == "E1-F1@api" and active["selected"]["route"] == "slice-loop"

status_routes = [
    ("pending", "slice-loop"), ("spec-ready", "slice-loop"),
    ("in-progress", "slice-loop"), ("in-review", "slice-review"),
]
for status, route in status_routes:
    data = board([epic("E1", [feature("E1-F1", "in-progress", slices=[
        {"id":"E1-F1@api","repo":"api","status":status}
    ])])])
    value, _ = call(data, config(manifest_path=str(manifest)))
    assert value["selected"]["route"] == route and value["selected"]["status"] == status

failed_data = board([epic("E1", [feature("E1-F1", "in-progress", slices=[
    {"id":"E1-F1@web","repo":"web","status":"pending"},
    {"id":"E1-F1@api","repo":"api","status":"failed"},
])])])
halted, _ = call(failed_data, config(manifest_path=str(manifest)))
assert halted["outcome"] == "halted" and halted["reason"] == {"code":"slice-failed","detail":"slice E1-F1@api is failed"}

merge_data = board([epic("E1", [feature("E1-F1", "in-progress", slices=[
    {"id":"E1-F1@web","repo":"web","status":"pending"},
    {"id":"E1-F1@api","repo":"api","status":"done","merged":False},
])])])
observe, _ = call(merge_data, config(manifest_path=str(manifest)))
assert observe["selected"]["route"] == "observe-merge" and observe["selected"]["slice_id"] == "E1-F1@api"

complete_data = board([epic("E1", [feature("E1-F1", "in-progress", slices=[
    {"id":"E1-F1@web","repo":"web","status":"done","merged":True},
    {"id":"E1-F1@api","repo":"api","status":"done","merged":True},
])])])
integration, _ = call(complete_data, config(manifest_path=str(manifest)))
assert integration["selected"] == selected("E1-F1", "in-progress", "integration")

# Parent-only slice diagnostics: cycle, failed/non-done/done-unmerged/missing.
slice_blocked_data = board([
    epic("E1", [feature("E1-F1", "in-progress", slices=[
        {"id":"E1-F1@api","repo":"api","status":"pending","depends_on":["E1-F1@web"]},
        {"id":"E1-F1@web","repo":"web","status":"pending","depends_on":["E1-F1@api","E1-F1@ghost"]},
    ]), feature("E1-F2")]),
])
slice_blocked, _ = call(slice_blocked_data, config(manifest_path=str(manifest)))
assert [r["subject"] for r in slice_blocked["blocked"]] == [
    "E1-F1@api", "E1-F1@api", "E1-F1@web", "E1-F1@web"
]
assert all(r["subject"] != "E1-F2" for r in slice_blocked["blocked"])
assert "E1-F1@ghost=missing" in slice_blocked["blocked"][-1]["detail"]
self_slice_data = board([epic("E1", [feature("E1-F1", "in-progress", slices=[
    {"id":"E1-F1@api","repo":"api","status":"pending","depends_on":["E1-F1@api"]}
])])])
self_slice, _ = call(self_slice_data, config(manifest_path=str(manifest)))
assert self_slice["blocked"][0]["detail"] == "dependency cycle (slice): E1-F1@api -> E1-F1@api"

done_unmerged_data = board([epic("E1", [feature("E1-F1", "in-progress", slices=[
    {"id":"E1-F1@api","repo":"api","status":"done","merged":False},
    {"id":"E1-F1@web","repo":"web","status":"pending","depends_on":["E1-F1@api"]},
])])])
# Observation wins before dependent diagnostics.
done_unmerged, _ = call(done_unmerged_data, config(manifest_path=str(manifest)))
assert done_unmerged["selected"]["route"] == "observe-merge"

missing_repo_data = board([epic("E1", [feature("E1-F1", "in-progress", slices=[
    {"id":"E1-F1@ghost","repo":"ghost","status":"pending"}
])])])
missing_repo, run = call(missing_repo_data, config(manifest_path=str(manifest)), expect_rc=1)
assert missing_repo["reason"]["code"] == "manifest-error" and "ghost" in run.stderr

# Fail-closed CLI, JSON, shape, containment, duplicates, statuses, config, manifest.
bad_argv = [
    ("--json", "--json"), ("--mine", "--feature", "E1-F1"),
    ("--mine", "--mine"), ("--feature", "E1-F1", "--feature", "E1-F1"),
    ("--tasks",), ("--config",), ("--wat",),
]
valid = board([epic("E1", [feature("E1-F1")])])
for argv in bad_argv:
    value, _ = call(valid, args=argv, expect_rc=2)
    assert value["outcome"] == "error" and value["reason"]["code"] == "usage-error"

bad_boards = [
    [],
    {"project":"x","epics":"bad"},
    board([epic("E1", [{"id":"E1-F1"}])]),
    board([epic("E1", [feature("E2-F1")])]),
    board([epic("E1", [feature("E1-F1"), feature("E1-F1")])]),
    board([epic("E1", [feature("E1-F1", status="bogus")])]),
    board([epic("E1", [feature("E1-F1", depends_on=[3])])]),
    board([epic("E1", [feature("E1-F1", "in-progress", slices=[
        {"id":"E01-F1@api","repo":"api","status":"pending"}
    ])])]),
    board([epic("E1", [feature("E1-F1", "done", slices=[
        {"id":"E1-F1@api","repo":"api","status":"pending","merged":False}
    ])])]),
]
for index, bad in enumerate(bad_boards):
    value, _ = call(bad, expect_rc=1)
    assert value["outcome"] == "error", f"bad board {index}"

bad_configs = [
    "workflow:\n  require_spec_approval: maybe\n",
    "workflow:\n  identity: a\n  identity: b\n",
    "workflow:\n  require_spec_approval: [true]\n",
    "workflow: invalid-inline\numbrella:\n  manifest: \"\"\n",
    "workflow:\n  require_spec_approval: true\nworkflow:\n  identity: alice\n",
    "umbrella: invalid-inline\n",
    "umbrella:\n  manifest: \"\"\numbrella:\n",
    "workflow:\n  require_spec_approval false\numbrella:\n  manifest: \"\"\n",
    "workflow:\n  identity alice\numbrella:\n  manifest: \"\"\n",
    "workflow:\n  - identity: alice\numbrella:\n  manifest: \"\"\n",
    "workflow:\n  require_spec_approval: true\numbrella:\n  manifest \"\"\n",
    "workflow:\n  require_spec_approval: true\numbrella:\n  - manifest: \"\"\n",
    "workflow:\n  require_spec_approval: true\n   identity: alice\numbrella:\n  manifest: \"\"\n",
    "workflow:\n  require_spec_approval: true\n    identity: alice\numbrella:\n  manifest: \"\"\n",
    "workflow:\n  metadata:\n    note: ignored\n   identity: alice\numbrella:\n  manifest: \"\"\n",
    "workflow:\n  require_spec_approval: true\numbrella:\n  manifest: \"\"\n   metadata: invalid\n",
    "workflow:\n  require_spec_approval: true\numbrella:\n  manifest: \"\"\n    metadata: invalid\n",
    "workflow:\n  require_spec_approval: true\numbrella:\n  metadata:\n    note: ignored\n   manifest: \"\"\n",
]
for bad in bad_configs:
    value, run = call(valid, cfg=bad, expect_rc=1)
    assert value["reason"]["code"] == "input-error"
    assert "config" in run.stderr or "workflow" in run.stderr or "umbrella" in run.stderr

valid_nested_config = (
    "workflow:\n"
    "  metadata:\n"
    "    note: ignored\n"
    "  require_spec_approval: true\n"
    "  identity: \"\"\n"
    "umbrella:\n"
    "  metadata:\n"
    "    note: ignored\n"
    "  manifest: \"\"\n"
)
value, _ = call(valid, cfg=valid_nested_config)
assert value["selected"]["feature_id"] == "E1-F1"

unrelated_malformed_config = (
    "unrelated malformed syntax\n"
    "workflow:\n"
    "  require_spec_approval: true\n"
    "  identity: \"\"\n"
    "umbrella:\n"
    "  manifest: \"\"\n"
    "another unrelated malformed line\n"
)
value, _ = call(valid, cfg=unrelated_malformed_config)
assert value["selected"]["feature_id"] == "E1-F1"

bad_manifest = tmp / "bad-manifest.yaml"
bad_manifest.write_text("repos:\n  api: inline\n")
value, _ = call(sliced_board, config(manifest_path=str(bad_manifest)), expect_rc=1)
assert value["reason"]["code"] == "manifest-error"
bad_manifest.write_text("repos:\n  api:\n    path: a\n  api:\n    path: b\n")
value, _ = call(sliced_board, config(manifest_path=str(bad_manifest)), expect_rc=1)
assert value["reason"]["code"] == "manifest-error"
for duplicate_repos in (
    "repos:\n  api:\n    path: a\nrepos:\n  web:\n    path: b\n",
    "repos:\n  api:\n    path: a\nmetadata:\n  name: fixture\nrepos:\n  web:\n    path: b\n",
):
    bad_manifest.write_text(duplicate_repos)
    value, run = call(sliced_board, config(manifest_path=str(bad_manifest)), expect_rc=1)
    assert value["reason"]["code"] == "manifest-error"
    assert "repos" in run.stderr

# Exact-key schema, repeated bytes, and reversed dependency order.
det_board = board([epic("E1", [
    feature("E1-F1", status="done"),
    feature("E1-F2", depends_on=["E1-F9", "E1-F8"]),
])])
one, run1 = call(det_board)
two, run2 = call(det_board)
assert list(one) == ["schema_version","mode","outcome","selected","reason","blocked","summary"]
assert run1.stdout == run2.stdout
reordered = copy.deepcopy(det_board)
reordered["epics"][0]["features"][1]["depends_on"].reverse()
three, run3 = call(reordered)
assert one == three and run1.stdout == run3.stdout

# Scale contract: 2,000 acyclic features in under five seconds.
large = board([epic("E1", [
    feature(f"E1-F{i}", status="done" if i < 2000 else "in-progress",
            depends_on=([f"E1-F{i-1}"] if i > 1 else []))
    for i in range(1, 2001)
])])
start = time.monotonic()
large_result, _ = call(large)
elapsed = time.monotonic() - start
assert large_result["selected"]["feature_id"] == "E1-F2000"
assert elapsed < 5, f"2,000-feature selector took {elapsed:.3f}s"

for label in (
    "R3 feature route oracle",
    "R4 canonical feature ordering",
    "R5 feature dependency diagnostics",
    "R6 owner scope oracle",
    "R7 top-level no-result contract",
    "R8 no-candidates and target-complete contract",
    "R9 umbrella manifest switch and repository gate",
    "R10 slice state and topology oracle",
    "R11 slice no-result scope and reasons",
    "R12 result schema and byte determinism",
    "R13 fail-closed input errors",
    "R16 differential oracle matrix and scale budget",
):
    print(f"PASS: {label}")
PY

# Contract/distribution checks are kept independent from runtime implementation.
grep -qF 'tools/next-task.mjs --json' "$ROOT/agents/orchestrator.md" ||
  fail "orchestrator does not invoke the selector"
grep -qi 'behavioral oracle' "$ROOT/agents/orchestrator.md" ||
  fail "orchestrator does not label its preserved prose as the behavioral oracle"
grep -qiE 'node.*unavailable|node.*missing' "$ROOT/agents/orchestrator.md" ||
  fail "orchestrator lacks missing-Node fallback"
grep -qiE 'invalid JSON|unsupported schema version' "$ROOT/agents/orchestrator.md" ||
  fail "orchestrator lacks malformed-output fallback"
grep -qiE 'trust.*route|authoritative' "$ROOT/agents/orchestrator.md" ||
  fail "orchestrator does not trust successful selector output"
grep -qF -- '--feature E##-F##' "$ROOT/.claude/commands/sdd-next.md" ||
  fail "/sdd-next positional target is not mapped to --feature"
pass "R14 orchestrator authority, oracle, fallback, and command mapping"

[ -x "$TOOL" ] || fail "source selector is not executable"
grep -qF 'tools/next-task.mjs' "$ROOT/harness-install.sh" ||
  fail "installer does not carry the selector"
# verification.test_command now delegates to tools/run-tests.sh, which DISCOVERS every
# tests/test_*.sh. The intent of this check is "this suite is not orphaned", so accept
# either spelling: an explicit mention, or the discovering runner plus the file existing.
_tc_value() {  # echo the test_command scalar only — never the surrounding comments
  sed -n 's/^[[:space:]]*test_command:[[:space:]]*"\([^"]*\)".*$/\1/p' "$1"
}
_tc="$(_tc_value "$ROOT/harness.config.yaml")"
{ printf '%s\n' "$_tc" | grep -qF 'tests/test_next_task.sh' \
    || { printf '%s\n' "$_tc" | grep -qF 'tools/run-tests.sh' \
         && [ -f "$ROOT/tests/test_next_task.sh" ]; }; } ||
  fail "selector suite is absent from full verification"
python3 - "$ROOT/CHANGELOG.md" "$ROOT/VERSION" <<'PY' ||
import re, sys
text = open(sys.argv[1]).read()
sections = list(re.finditer(r"(?m)^## \[(\d+)\.(\d+)\.(\d+)\].*$", text))
for index, match in enumerate(sections):
    end = sections[index + 1].start() if index + 1 < len(sections) else len(text)
    if "E16-F03" not in text[match.start():end]:
        continue
    if index + 1 >= len(sections):
        raise SystemExit("E16-F03 changelog has no immediately older version")
    feature = tuple(map(int, match.groups()))
    older = tuple(map(int, sections[index + 1].groups()))
    current = tuple(map(int, open(sys.argv[2]).read().strip().split(".")))
    assert feature == (older[0], older[1] + 1, 0), (feature, older)
    assert current >= feature, (current, feature)
    break
else:
    raise SystemExit("E16-F03 changelog section missing")
PY
  fail "E16-F03 future-safe MINOR version policy failed"
pass "R15 distribution wiring"

# Protected invariants: implementation tests must not replace these files/contracts.
git diff --quiet -- "$ROOT/store/tasks.schema.json" \
  "$ROOT/tools/task-diagnostics.py" "$ROOT/init.sh" ||
  fail "selector changed a protected schema/helper/init file"
[ "$(cksum "$ROOT/state/tasks.json")" = "$STATE_BEFORE" ] ||
  fail "selector suite changed the shared TaskStore"
pass "R17 schema, state, diagnostic helper, and init invariants"

echo "All next-task selector checks passed."
