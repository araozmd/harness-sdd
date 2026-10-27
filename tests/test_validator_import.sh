#!/bin/sh
# test_validator_import.sh — tools/validate-board.py imports jsonschema without paying for the
# optional IRI-format grammar when the schema cannot use it (2026-10-27 follow-up).
#
# jsonschema's format module imports `rfc3987_syntax`, which compiles a lark grammar at import
# time (~0.65 s of each tasks-lock write and init.sh gate). The validator runs Draft7Validator
# with NO format checker, so the grammar is dead weight while the schema has no `format`
# keyword. Each claim below is paired with the case that must behave differently.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-validator-import)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

python3 -c 'import jsonschema' 2>/dev/null || { echo "skip - jsonschema not installed (fallback path only)"; exit 0; }

# R1 — the shipped board schema carries no `format` keyword: the shortcut's precondition. If a
# `format` is ever added, the validator stops hiding the dependency (R3) and this row says why.
python3 - "$SRC/store/tasks.schema.json" <<'PY' || fail "R1: store/tasks.schema.json carries a format keyword"
import json, sys
def walk(n):
    if isinstance(n, dict):
        if "format" in n: sys.exit(1)
        for v in n.values(): walk(v)
    elif isinstance(n, list):
        for v in n: walk(v)
walk(json.load(open(sys.argv[1])))
PY
pass "R1 the board schema has no format keyword"

# R2 — format-free schema: jsonschema is used (a schema error is reported in jsonschema's
# words), rfc3987_syntax is NOT imported, and afterwards it is importable again (no sentinel left).
python3 - "$SRC/tools/validate-board.py" "$SRC/store/tasks.schema.json" "$SRC/state/tasks.json" <<'PY' || fail "R2: format-free schema path"
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("vb", sys.argv[1]); vb = importlib.util.module_from_spec(spec); spec.loader.exec_module(vb)
schema = json.load(open(sys.argv[2])); board = json.load(open(sys.argv[3]))
assert vb.validate(board, schema) == [], "the real board must validate clean"
bad = json.loads(json.dumps(board)); bad["epics"][0]["status"] = 42
errs = vb.validate(bad, schema)
assert "jsonschema" in sys.modules, "jsonschema was not used"
assert any("42" in e for e in errs), "a bad board was not rejected through jsonschema: %r" % errs
assert "rfc3987_syntax" not in sys.modules, "rfc3987_syntax was imported for a format-free schema"
try:
    import rfc3987_syntax  # noqa: F401  (only meaningful where it is installed)
except ModuleNotFoundError:
    pass
except ImportError as e:
    raise AssertionError("a None sentinel was left in sys.modules: %r" % e)
PY
pass "R2 format-free schema: jsonschema validates, rfc3987_syntax not imported, no sentinel left"

# R3 — a schema WITH a format keyword: nothing is hidden. Where the optional package is
# installed, jsonschema's import pulls it in as usual.
python3 - "$SRC/tools/validate-board.py" <<'PY' || fail "R3: format-bearing schema must not hide the dependency"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("vb", sys.argv[1]); vb = importlib.util.module_from_spec(spec); spec.loader.exec_module(vb)
try:
    import importlib; importlib.util.find_spec("rfc3987_syntax") or sys.exit(0)  # not installed: nothing to prove
except Exception:
    sys.exit(0)
vb.validate({"x": "a"}, {"type": "object", "properties": {"x": {"type": "string", "format": "iri"}}})
assert "rfc3987_syntax" in sys.modules, "a format-bearing schema still hid rfc3987_syntax"
PY
pass "R3 format-bearing schema: the dependency is not hidden"

echo "All validator-import tests passed."
