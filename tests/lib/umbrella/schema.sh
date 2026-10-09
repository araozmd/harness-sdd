validate() {
  have_py || { echo "      (python3 absent — skipping schema validation)"; return 0; }
  python3 - "$1" "$SCHEMA" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
try:
    import jsonschema
    errs = list(jsonschema.Draft7Validator(schema).iter_errors(data))
    sys.exit(1 if errs else 0)
except ImportError:
    pass
# Zero-dep fallback: encode the slice invariants we assert in this test.
SLICE_ID = re.compile(r"^E[0-9]+-F[0-9]+@[a-z0-9-]+$")
FEAT_STATUS = {"pending","spec-ready","in-progress","in-review","done","failed"}
errors = []
for ep in data.get("epics", []):
    for ft in ep.get("features", []):
        slices = ft.get("slices")
        if slices is None:
            continue  # absent slices is always valid (pure superset)
        if not isinstance(slices, list):
            errors.append("slices: expected array"); continue
        if len(slices) == 0:
            errors.append("slices: must have at least 1 item"); continue
        for sl in slices:
            if not isinstance(sl, dict):
                errors.append("slice: expected object"); continue
            for k in ("id","repo","status"):
                if k not in sl:
                    errors.append("slice: missing required '%s'" % k)
            if "id" in sl and not SLICE_ID.match(str(sl["id"])):
                errors.append("slice.id %r: bad pattern" % sl["id"])
            if "repo" in sl and not isinstance(sl["repo"], str):
                errors.append("slice.repo: expected string")
            if sl.get("status") not in FEAT_STATUS and "status" in sl:
                errors.append("slice.status %r: bad enum" % sl.get("status"))
            if "merged" in sl and not isinstance(sl["merged"], bool):
                errors.append("slice.merged: expected boolean")
            if "pr" in sl and not isinstance(sl["pr"], str):
                errors.append("slice.pr: expected string")
            if "depends_on" in sl:
                d = sl["depends_on"]
                if not isinstance(d, list) or not all(isinstance(x,str) for x in d):
                    errors.append("slice.depends_on: expected array of strings")
        if ft.get("status") == "done":
            for sl in slices:
                if isinstance(sl, dict) and (sl.get("status") != "done" or sl.get("merged") is not True):
                    errors.append("feature 'done' but a slice is not done+merged")
sys.exit(1 if errors else 0)
PY
}
