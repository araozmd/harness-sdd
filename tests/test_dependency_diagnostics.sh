#!/bin/sh
# test_dependency_diagnostics.sh — E16-F01 dependency diagnostics contract
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/tools/task-diagnostics.py"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/harness-dependency-diagnostics.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

PASS=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { PASS=$((PASS + 1)); echo "PASS: $*"; }

run_cycles() {
  python3 "$HELPER" cycles "$1"
}

# test_feature_cycle_full_path
cat >"$TMP/feature.json" <<'JSON'
{"project":"fixture","epics":[
  {"id":"E16","title":"x","status":"planned","features":[
    {"id":"E16-F03","depends_on":["E16-F01"]},
    {"id":"E16-F01","depends_on":["E16-F02"]},
    {"id":"E16-F02","depends_on":["E16-F03"]}
  ]}
]}
JSON
expected=$(printf 'dependency-cycle\tfeature\tE16-F01 -> E16-F02 -> E16-F03 -> E16-F01')
actual=$(run_cycles "$TMP/feature.json") || fail "feature-cycle helper invocation failed"
[ "$actual" = "$expected" ] || fail "feature witness differs: $actual"
pass "R1 feature cycle emits the canonical closed full witness"

# test_slice_cycle_full_path
cat >"$TMP/slice.json" <<'JSON'
{"project":"fixture","epics":[{"id":"E20","features":[
  {"id":"E20-F01","depends_on":[],"slices":[
    {"id":"E20-F01@worker","depends_on":["E20-F01@api"]},
    {"id":"E20-F01@api","depends_on":["E20-F01@web"]},
    {"id":"E20-F01@web","depends_on":["E20-F01@worker"]}
  ]}
]}]}
JSON
expected=$(printf 'dependency-cycle\tslice\tE20-F01@api -> E20-F01@web -> E20-F01@worker -> E20-F01@api')
actual=$(run_cycles "$TMP/slice.json") || fail "slice-cycle helper invocation failed"
[ "$actual" = "$expected" ] || fail "slice witness differs: $actual"
pass "R2 slice cycle emits canonical slice ids and full witness"

# test_self_cycles
cat >"$TMP/self.json" <<'JSON'
{"project":"fixture","epics":[
  {"id":"E2","features":[
    {"id":"E2-F10","depends_on":["E2-F10"],"slices":[
      {"id":"E2-F10@api","depends_on":["E2-F10@api"]}
    ]}
  ]}
]}
JSON
expected=$(printf 'dependency-cycle\tfeature\tE2-F10 -> E2-F10\ndependency-cycle\tslice\tE2-F10@api -> E2-F10@api')
actual=$(run_cycles "$TMP/self.json") || fail "self-cycle helper invocation failed"
[ "$actual" = "$expected" ] || fail "self witnesses differ: $actual"
pass "R3 feature and slice self-cycles emit two-id paths"

# test_deterministic_order_and_missing_dependency_treatment
cat >"$TMP/multi-a.json" <<'JSON'
{"project":"fixture","epics":[
 {"id":"E10","features":[
  {"id":"E10-F1","depends_on":["E10-F2","E99-F99","E10-F1@api"]},
  {"id":"E10-F2","depends_on":["E10-F1"]}
 ]},
 {"id":"E2","features":[
  {"id":"E2-F1","depends_on":["E2-F2"]},
  {"id":"E2-F2","depends_on":["E2-F1"],"slices":[
   {"id":"E2-F2@web","depends_on":["E2-F2@api","E2-F2"]},
   {"id":"E2-F2@api","depends_on":["E2-F2@web"]}
  ]}
 ]}
]}
JSON
cat >"$TMP/multi-b.json" <<'JSON'
{"epics":[
 {"features":[
  {"depends_on":["E2-F1"],"id":"E2-F2","slices":[
   {"depends_on":["E2-F2@web"],"id":"E2-F2@api"},
   {"depends_on":["E2-F2","E2-F2@api"],"id":"E2-F2@web"}
  ]},
  {"depends_on":["E2-F2"],"id":"E2-F1"}
 ],"id":"E2"},
 {"features":[
  {"depends_on":["E10-F1"],"id":"E10-F2"},
  {"depends_on":["E10-F1@api","E99-F99","E10-F2"],"id":"E10-F1"}
 ],"id":"E10"}
],"project":"fixture"}
JSON
out_a=$(run_cycles "$TMP/multi-a.json") || fail "multi-cycle fixture A failed"
out_b=$(run_cycles "$TMP/multi-b.json") || fail "multi-cycle fixture B failed"
[ "$out_a" = "$out_b" ] || fail "equivalent boards were not byte-identical"
expected=$(printf '%s\n%s\n%s' \
  "$(printf 'dependency-cycle\tfeature\tE2-F1 -> E2-F2 -> E2-F1')" \
  "$(printf 'dependency-cycle\tfeature\tE10-F1 -> E10-F2 -> E10-F1')" \
  "$(printf 'dependency-cycle\tslice\tE2-F2@api -> E2-F2@web -> E2-F2@api')")
[ "$out_a" = "$expected" ] || fail "record order/cross-kind handling differs: $out_a"
pass "R4 deterministic disjoint graphs exclude missing and cross-kind edges"

# One SCC has two possible root neighbors. Canonical neighbor and BFS path win.
cat >"$TMP/choice.json" <<'JSON'
{"project":"fixture","epics":[{"id":"E3","features":[
 {"id":"E3-F1","depends_on":["E3-F3","E3-F2"]},
 {"id":"E3-F2","depends_on":["E3-F4"]},
 {"id":"E3-F3","depends_on":["E3-F1"]},
 {"id":"E3-F4","depends_on":["E3-F3","E3-F1"]}
]}]}
JSON
expected=$(printf 'dependency-cycle\tfeature\tE3-F1 -> E3-F2 -> E3-F4 -> E3-F1')
actual=$(run_cycles "$TMP/choice.json") || fail "choice fixture failed"
[ "$actual" = "$expected" ] || fail "canonical root/neighbor/BFS witness differs: $actual"
pass "R4 canonical SCC witness follows lowest neighbor and sorted BFS"

# test_empty_and_no_dependency_graceful_noop
for body in \
  '{"project":"x","epics":[]}' \
  '{"project":"x","epics":[{"id":"E1","features":[]}]}' \
  '{"project":"x","epics":[{"id":"E1","features":[{"id":"E1-F1"}]}]}' \
  '{"project":"x","epics":[{"id":"E1","features":[{"id":"E1-F1","depends_on":[]}]}]}'
do
  printf '%s\n' "$body" >"$TMP/empty.json"
  actual=$(run_cycles "$TMP/empty.json") || fail "graceful empty fixture failed"
  [ -z "$actual" ] || fail "graceful empty fixture emitted output: $actual"
done
pass "R6 absent and empty dependency surfaces are silent no-ops"

# test_helper_input_errors_and_init_precedence (direct helper portion)
if run_cycles "$TMP/missing.json" >"$TMP/missing.out" 2>"$TMP/missing.err"; then
  fail "missing helper input unexpectedly succeeded"
fi
grep -F "$TMP/missing.json" "$TMP/missing.err" >/dev/null ||
  fail "missing-input error did not name requested path"
printf '{"project":' >"$TMP/malformed.json"
if run_cycles "$TMP/malformed.json" >"$TMP/malformed.out" 2>"$TMP/malformed.err"; then
  fail "malformed helper input unexpectedly succeeded"
fi
grep -F "$TMP/malformed.json" "$TMP/malformed.err" >/dev/null ||
  fail "malformed-input error did not name requested path"
pass "R7 direct input failures are actionable and non-zero"

# test_init_cycle_warning_is_nonfatal
INIT_FIXTURE="$TMP/source-harness"
mkdir -p "$INIT_FIXTURE"/agents "$INIT_FIXTURE"/specs "$INIT_FIXTURE"/progress \
  "$INIT_FIXTURE"/state "$INIT_FIXTURE"/store "$INIT_FIXTURE"/tools
cp "$ROOT/init.sh" "$ROOT/harness.config.yaml" "$ROOT/AGENTS.md" "$INIT_FIXTURE/"
cp "$ROOT"/agents/orchestrator.md "$ROOT"/agents/architect.md \
  "$ROOT"/agents/builder.md "$ROOT"/agents/reviewer.md \
  "$ROOT"/agents/scout.md "$INIT_FIXTURE/agents/"
cp "$ROOT/store/tasks.schema.json" "$INIT_FIXTURE/store/"
cp "$ROOT/tools/validate-board.py" "$HELPER" "$INIT_FIXTURE/tools/"
cat >"$INIT_FIXTURE/state/tasks.json" <<'JSON'
{"project":"fixture","epics":[
 {"id":"E2","title":"two","status":"planned","features":[
  {"id":"E2-F1","title":"a","status":"pending","sdd":true,"autonomous":true,
   "depends_on":["E2-F2"],"spec_path":"a/"},
  {"id":"E2-F2","title":"b","status":"pending","sdd":true,"autonomous":true,
   "depends_on":["E2-F1"],"spec_path":"b/"}
 ]},
 {"id":"E10","title":"ten","status":"planned","features":[
  {"id":"E10-F1","title":"c","status":"pending","sdd":true,"autonomous":true,
   "depends_on":["E10-F1"],"spec_path":"c/","slices":[
    {"id":"E10-F1@api","repo":"api","status":"pending","merged":false,
     "depends_on":["E10-F1@web"],"spec_path":"api/"},
    {"id":"E10-F1@web","repo":"web","status":"pending","merged":false,
     "depends_on":["E10-F1@api"],"spec_path":"web/"}
   ]}
 ]}
]}
JSON
if ! "$INIT_FIXTURE/init.sh" >"$TMP/init.out" 2>"$TMP/init.err"; then
  fail "valid cyclic board made init fail: $(cat "$TMP/init.err")"
fi
cat "$TMP/init.out" "$TMP/init.err" >"$TMP/init.all"
expected_warnings=$(cat <<'EOF'
⚠️  TaskStore dependency-cycle [feature]: E2-F1 -> E2-F2 -> E2-F1 (warn-only)
⚠️  TaskStore dependency-cycle [feature]: E10-F1 -> E10-F1 (warn-only)
⚠️  TaskStore dependency-cycle [slice]: E10-F1@api -> E10-F1@web -> E10-F1@api (warn-only)
EOF
)
actual_warnings=$(grep 'TaskStore dependency-cycle' "$TMP/init.all" || true)
[ "$actual_warnings" = "$expected_warnings" ] ||
  fail "init warnings missing or noncanonical: $actual_warnings"
pass "R5 source init emits deterministic full-path cycle warnings and remains zero"

# Acyclic init stays silent, and an unexpected helper failure remains warn-only.
cat >"$INIT_FIXTURE/state/tasks.json" <<'JSON'
{"project":"fixture","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"pending","sdd":true,"autonomous":true,
  "depends_on":[],"spec_path":"a/"}
]}]}
JSON
"$INIT_FIXTURE/init.sh" >"$TMP/acyclic-init.out" 2>"$TMP/acyclic-init.err" ||
  fail "acyclic source init failed"
if grep -F 'TaskStore dependency-cycle' "$TMP/acyclic-init.out" "$TMP/acyclic-init.err" >/dev/null; then
  fail "acyclic source init emitted a cycle warning"
fi
mv "$INIT_FIXTURE/tools/task-diagnostics.py" "$INIT_FIXTURE/tools/task-diagnostics.py.off"
"$INIT_FIXTURE/init.sh" >"$TMP/helper-fail.out" 2>"$TMP/helper-fail.err" ||
  fail "post-validator helper failure changed init exit semantics"
grep -F 'TaskStore dependency diagnostics unavailable:' "$TMP/helper-fail.err" >/dev/null ||
  fail "post-validator helper failure did not emit warn-only diagnostic"
mv "$INIT_FIXTURE/tools/task-diagnostics.py.off" "$INIT_FIXTURE/tools/task-diagnostics.py"
pass "R6/R7 acyclic init is silent and helper failure remains warn-only"

# Validator failure remains primary; the helper is not consulted first.
printf '{"project":' >"$INIT_FIXTURE/state/tasks.json"
if "$INIT_FIXTURE/init.sh" >"$TMP/bad-init.out" 2>"$TMP/bad-init.err"; then
  fail "malformed board unexpectedly passed init"
fi
grep -F 'state/tasks.json failed schema validation' "$TMP/bad-init.err" >/dev/null ||
  fail "malformed board did not retain canonical validator failure"
if grep -F 'TaskStore dependency-cycle' "$TMP/bad-init.out" "$TMP/bad-init.err" >/dev/null; then
  fail "cycle helper ran before malformed board fail-stop"
fi
pass "R7 init structural validation remains primary"

# test_no_selection_record_contract and reason-class contracts
require_text() {
  file=$1
  text=$2
  grep -F "$text" "$file" >/dev/null ||
    fail "$file missing contract text: $text"
}

for contract in "$ROOT/agents/orchestrator.md" "$ROOT/store/local.md"; do
  require_text "$contract" 'blocked <id> [<reason-code>]: <human text>'
  require_text "$contract" 'no actionable work: selection blocked; see reasons above'
  require_text "$contract" 'dependency-cycle'
  require_text "$contract" 'gated-epic'
  require_text "$contract" 'unmet-dependency'
  require_text "$contract" 'human-gate'
  require_text "$contract" 'owner-excluded'
  require_text "$contract" 'owner-unresolved'
  require_text "$contract" 'no-candidates'
  require_text "$contract" 'epic <id> is draft'
  require_text "$contract" 'blocking dependencies: <id>=missing'
  require_text "$contract" '<id>=done-but-unmerged'
  require_text "$contract" 'spec-ready requires approval'
  require_text "$contract" 'gated quick fix requires approval'
  require_text "$contract" 'effective owner=<literal>'
  require_text "$contract" 'effective owner=unowned'
  require_text "$contract" 'workflow.identity=<empty>'
  require_text "$contract" 'workflow.identity=@me lookup failed'
  require_text "$contract" 'workflow.identity=self lookup failed'
  require_text "$contract" 'no actionable work [no-candidates]: board has no features'
  require_text "$contract" 'no actionable work [no-candidates]: all features are done'
  require_text "$contract" 'E16-F03'
  require_text "$contract" 'verbatim'
done
pass "R8-R13 portable contracts pin every reason, detail, and summary"

require_text "$ROOT/agents/orchestrator.md" 'feature before slice'
require_text "$ROOT/agents/orchestrator.md" 'all applicable'
require_text "$ROOT/agents/orchestrator.md" 'otherwise actionable'
require_text "$ROOT/agents/orchestrator.md" 'Bare `/sdd-next`'
require_text "$ROOT/agents/orchestrator.md" 'changes no state'
require_text "$ROOT/agents/orchestrator.md" 'informational'
pass "R8-R12 Orchestrator pins ordering, scope, no-mutation, and informational semantics"

# test_selected_sliced_parent_no_result_diagnostics
for contract in "$ROOT/agents/orchestrator.md" "$ROOT/store/local.md"; do
  require_text "$contract" 'top-level selection returns a sliced feature'
  require_text "$contract" '`next_slice(feature)` returns no slice'
  require_text "$contract" 'selected parent feature'
  require_text "$contract" 'whole-board top-level diagnostics'
done

cat >"$TMP/selected-sliced-parent.json" <<'JSON'
{"project":"fixture","epics":[{"id":"E16","status":"planned","features":[
  {"id":"E16-F20","status":"in-progress","slices":[
    {"id":"E16-F20@web","status":"pending","merged":false,
     "depends_on":["E16-F20@api"]},
    {"id":"E16-F20@worker","status":"pending","merged":false,
     "depends_on":["E16-F20@missing"]},
    {"id":"E16-F20@api","status":"pending","merged":false,
     "depends_on":["E16-F20@web"]}
  ]},
  {"id":"E16-F21","status":"spec-ready","sdd":true,"autonomous":false}
]}]}
JSON
python3 - "$HELPER" "$TMP/selected-sliced-parent.json" <<'PY'
import hashlib
import importlib.util
import json
import pathlib
import sys

helper_path, fixture_path = sys.argv[1:]
spec = importlib.util.spec_from_file_location("task_diagnostics", helper_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

path = pathlib.Path(fixture_path)
before = path.read_bytes()
board = json.loads(before)
selected = board["epics"][0]["features"][0]
assert selected["id"] == "E16-F20"

slices = {item["id"]: item for item in selected["slices"]}
actionable = []
for item in slices.values():
    dependencies_ready = all(
        dep in slices
        and slices[dep].get("status") == "done"
        and slices[dep].get("merged") is True
        for dep in item.get("depends_on", [])
    )
    if item.get("status") in {"pending", "in-progress", "in-review"} and dependencies_ready:
        actionable.append(item["id"])
assert actionable == [], "fixture must make next_slice(feature) return no slice"

cycle = next(
    record for record in module.find_dependency_cycles(board)
    if record["kind"] == "slice" and record["path"][0].startswith("E16-F20@")
)
witness = " -> ".join(cycle["path"])
cyclic_ids = set(cycle["path"][:-1])
records = []
for slice_id in sorted(slices, key=module.node_sort_key):
    item = slices[slice_id]
    if slice_id in cyclic_ids:
        records.append(
            f"blocked {slice_id} [dependency-cycle]: "
            f"dependency cycle (slice): {witness}"
        )
    blockers = []
    for dependency in sorted(item.get("depends_on", []), key=module.node_sort_key):
        upstream = slices.get(dependency)
        if upstream is None:
            blockers.append(f"{dependency}=missing")
        elif upstream.get("status") != "done":
            blockers.append(f"{dependency}={upstream.get('status')}")
        elif upstream.get("merged") is not True:
            blockers.append(f"{dependency}=done-but-unmerged")
    if blockers:
        records.append(
            f"blocked {slice_id} [unmet-dependency]: "
            f"blocking dependencies: {', '.join(blockers)}"
        )
records.append("no actionable work: selection blocked; see reasons above")

expected = [
    "blocked E16-F20@api [dependency-cycle]: dependency cycle (slice): "
    "E16-F20@api -> E16-F20@web -> E16-F20@api",
    "blocked E16-F20@api [unmet-dependency]: "
    "blocking dependencies: E16-F20@web=pending",
    "blocked E16-F20@web [dependency-cycle]: dependency cycle (slice): "
    "E16-F20@api -> E16-F20@web -> E16-F20@api",
    "blocked E16-F20@web [unmet-dependency]: "
    "blocking dependencies: E16-F20@api=pending",
    "blocked E16-F20@worker [unmet-dependency]: "
    "blocking dependencies: E16-F20@missing=missing",
    "no actionable work: selection blocked; see reasons above",
]
assert records == expected, records
assert all("E16-F21" not in record for record in records)
assert hashlib.sha256(path.read_bytes()).digest() == hashlib.sha256(before).digest()
PY
pass "R8/R10 selected sliced parent no-result is scoped, stable, and read-only"

# test_scale_dependencies_schema_docs_and_version (executable helper portion)
SCHEMA_BEFORE=$(cksum "$ROOT/store/tasks.schema.json")
python3 - "$HELPER" "$TMP/scale.json" <<'PY'
import copy
import importlib.util
import json
import pathlib
import sys
import time

helper_path, fixture_path = sys.argv[1:]
spec = importlib.util.spec_from_file_location("task_diagnostics", helper_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

expected_codes = {
    "dependency-cycle", "gated-epic", "unmet-dependency", "human-gate",
    "owner-excluded", "owner-unresolved", "no-candidates",
}
assert set(module.REASON_TEXT) == expected_codes
assert module.HUMAN_GATE_TEXT == (
    "spec-ready requires approval", "gated quick fix requires approval",
)
assert module.OWNER_UNRESOLVED_TEXT == (
    "workflow.identity=<empty>",
    "workflow.identity=@me lookup failed",
    "workflow.identity=self lookup failed",
)
assert module.NO_CANDIDATES_TEXT == (
    "no actionable work [no-candidates]: board has no features",
    "no actionable work [no-candidates]: all features are done",
)

board = {"project": "scale", "epics": [{"id": "E40", "features": []}]}
for index in range(1, 2001):
    board["epics"][0]["features"].append({
        "id": "E40-F%d" % index,
        "depends_on": [] if index == 1 else ["E40-F%d" % (index - 1)],
    })
pathlib.Path(fixture_path).write_text(json.dumps(board), encoding="utf-8")
before = copy.deepcopy(board)
start = time.monotonic()
assert module.find_dependency_cycles(board) == []
elapsed = time.monotonic() - start
assert elapsed < 5, elapsed
assert board == before

mixed = {"epics": [{"features": [
    {"id": "E1-F1", "depends_on": ["E9-F9", "E1-F1@api"]},
    {"id": "E1-F2", "slices": [
        {"id": "E1-F2@api", "depends_on": ["E1-F1"]}
    ]},
]}]}
feature_graph, feature_missing = module.build_dependency_graph(mixed, "feature")
slice_graph, slice_missing = module.build_dependency_graph(mixed, "slice")
assert feature_graph["E1-F1"] == []
assert feature_missing["E1-F1"] == ["E1-F1@api", "E9-F9"]
assert slice_graph["E1-F2@api"] == []
assert slice_missing["E1-F2@api"] == ["E1-F1"]
PY
[ "$(cksum "$ROOT/store/tasks.schema.json")" = "$SCHEMA_BEFORE" ] ||
  fail "schema changed during read-only diagnostics"
[ -z "$(run_cycles "$TMP/scale.json")" ] || fail "acyclic scale board emitted a cycle"
if grep -Eq '^[[:space:]]*(from|import)[[:space:]]+(jsonschema|networkx|yaml|numpy|pandas)' "$HELPER"; then
  fail "helper imports a third-party package"
fi
pass "R4/R6/R14 import API, missing blockers, 2,000 nodes, and read-only behavior execute"

for doc in "$ROOT/docs/WORKFLOW.md" "$ROOT/README.md"; do
  require_text "$doc" 'dependency-cycle'
  require_text "$doc" 'no actionable work'
  require_text "$doc" 'warn-only'
done
pass "R5/R8-R13 operator documentation names warnings and blocked output"

require_text "$ROOT/harness.config.yaml" 'sh tests/test_dependency_diagnostics.sh'
require_text "$ROOT/harness.config.yaml" 'dependency diagnostics'
python3 - "$ROOT/VERSION" "$ROOT/CHANGELOG.md" <<'PY'
import pathlib
import re
import sys

version = pathlib.Path(sys.argv[1]).read_text().strip()
changelog = pathlib.Path(sys.argv[2]).read_text()
match = re.search(
    r"^## \[(\d+)\.(\d+)\.(\d+)\].*?"
    r"(?=^## \[|\Z)",
    changelog,
    re.MULTILINE | re.DOTALL,
)
sections = list(re.finditer(
    r"^## \[(\d+)\.(\d+)\.(\d+)\].*?(?=^## \[|\Z)",
    changelog,
    re.MULTILINE | re.DOTALL,
))
feature = next((m for m in sections if "E16-F01" in m.group(0)), None)
assert feature is not None, "E16-F01 changelog section missing"
feature_version = tuple(map(int, feature.groups()))
feature_index = sections.index(feature)
assert feature_index + 1 < len(sections), "older changelog version missing"
older_version = tuple(map(int, sections[feature_index + 1].groups()))
assert feature_version == (older_version[0], older_version[1] + 1, 0), (
    feature_version, older_version
)
current_version = tuple(map(int, version.split(".")))
assert current_version >= feature_version, (current_version, feature_version)
PY
pass "R14 verification wiring and future-safe MINOR/changelog policy hold"

python3 - "$ROOT/store/tasks.schema.json" <<'PY'
import json
import sys
schema = json.load(open(sys.argv[1]))
text = json.dumps(schema, sort_keys=True)
for value in ("pending", "spec-ready", "in-progress", "in-review", "done"):
    assert value in text
assert "dependency-cycle" not in text
assert "no-candidates" not in text
PY
pass "R14 TaskStore schema/status surface remains diagnostic-free"

echo "All dependency-diagnostics tests passed ($PASS checks)."
