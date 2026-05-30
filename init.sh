#!/usr/bin/env bash
# init.sh — environment verification gate.
# The Orchestrator MUST run this before any work. Non-zero exit = STOP.
# It proves the harness is structurally healthy so agents don't hallucinate fixes.
#
# Adapt the project-specific section to the target repo (tests, deps, build).

set -euo pipefail

# Resolve the harness root (this script's dir) and run structural checks from there,
# so an installed copy at <repo>/.harness/init.sh works when invoked from the repo
# root. PROJECT_ROOT is where project-specific checks (tests, build) must run: the
# parent when we're installed under `.harness/`, else the harness root itself.
HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
case "$HARNESS_DIR" in
  */.harness) PROJECT_ROOT="$(dirname "$HARNESS_DIR")" ;;
  *)          PROJECT_ROOT="$HARNESS_DIR" ;;
esac
cd "$HARNESS_DIR"

fail() { echo "❌ init: $1" >&2; exit 1; }
ok()   { echo "✅ $1"; }

echo "── harness-sdd init ──────────────────────────────"

# 1. Structural checks — the harness itself must be intact.
[ -f AGENTS.md ]            || fail "AGENTS.md missing (no entrypoint)"
[ -f harness.config.yaml ]  || fail "harness.config.yaml missing"
[ -d agents ]               || fail "agents/ missing (no role prompts)"
[ -d specs ]                || fail "specs/ missing"
[ -d progress ]             || fail "progress/ missing"
for role in orchestrator architect builder reviewer scout; do
  [ -f "agents/${role}.md" ] || fail "agents/${role}.md missing"
done
ok "harness structure intact"

# 2. TaskStore presence + schema validation (local backend).
#    Syntactically-valid JSON is not enough: an unsupported status or a missing
#    required field (e.g. spec_path) must halt here, not surface later as corrupt
#    routing state. We validate against store/tasks.schema.json.
if grep -q "tasks: local" harness.config.yaml 2>/dev/null; then
  [ -f state/tasks.json ]          || fail "state/tasks.json missing (local TaskStore)"
  [ -f store/tasks.schema.json ]   || fail "store/tasks.schema.json missing (cannot validate TaskStore)"
  if command -v python3 >/dev/null 2>&1; then
    python3 - state/tasks.json store/tasks.schema.json <<'PY' || fail "state/tasks.json failed schema validation (see errors above)"
import json, re, sys

data_path, schema_path = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(data_path))
except (ValueError, OSError) as e:
    print("  not valid JSON: %s" % e, file=sys.stderr); sys.exit(1)
try:
    schema = json.load(open(schema_path))
except (ValueError, OSError) as e:
    print("  schema not readable: %s" % e, file=sys.stderr); sys.exit(1)

# Prefer the real validator when available; fall back to a built-in structural
# check that encodes the same invariants so init.sh stays zero-dependency.
try:
    import jsonschema
    errs = sorted(jsonschema.Draft7Validator(schema).iter_errors(data),
                  key=lambda e: list(e.path))
    for e in errs:
        loc = "/".join(str(p) for p in e.path) or "(root)"
        print("  %s: %s" % (loc, e.message), file=sys.stderr)
    sys.exit(1 if errs else 0)
except ImportError:
    pass

errors = []
EPIC_STATUS = {"pending", "in-progress", "done"}
FEAT_STATUS = {"pending", "spec-ready", "in-progress", "in-review", "done"}

def need(obj, key, where):
    if key not in obj:
        errors.append("%s: missing required field '%s'" % (where, key)); return False
    return True

if not isinstance(data, dict):
    errors.append("(root): expected object")
else:
    if need(data, "project", "(root)") and not isinstance(data["project"], str):
        errors.append("project: expected string")
    if need(data, "epics", "(root)"):
        epics = data["epics"]
        if not isinstance(epics, list):
            errors.append("epics: expected array")
            epics = []
        for ei, ep in enumerate(epics):
            ew = "epics[%d]" % ei
            if not isinstance(ep, dict):
                errors.append("%s: expected object" % ew); continue
            for k in ("id", "title", "status", "features"):
                need(ep, k, ew)
            if "id" in ep:
                if not isinstance(ep["id"], str):
                    errors.append("%s.id: expected string" % ew)
                elif not re.match(r"^E[0-9]+$", ep["id"]):
                    errors.append("%s.id %r: must match ^E[0-9]+$" % (ew, ep["id"]))
            if "title" in ep and not isinstance(ep["title"], str):
                errors.append("%s.title: expected string" % ew)
            if ep.get("status") not in EPIC_STATUS and "status" in ep:
                errors.append("%s.status '%s': not one of %s" % (ew, ep["status"], sorted(EPIC_STATUS)))
            feats = ep.get("features", [])
            if not isinstance(feats, list):
                errors.append("%s.features: expected array" % ew); feats = []
            for fi, ft in enumerate(feats):
                fw = "%s.features[%d]" % (ew, fi)
                if not isinstance(ft, dict):
                    errors.append("%s: expected object" % fw); continue
                for k in ("id", "title", "status", "sdd", "spec_path"):
                    need(ft, k, fw)
                if "id" in ft:
                    if not isinstance(ft["id"], str):
                        errors.append("%s.id: expected string" % fw)
                    elif not re.match(r"^E[0-9]+-F[0-9]+$", ft["id"]):
                        errors.append("%s.id %r: must match ^E[0-9]+-F[0-9]+$" % (fw, ft["id"]))
                if "title" in ft and not isinstance(ft["title"], str):
                    errors.append("%s.title: expected string" % fw)
                if ft.get("status") not in FEAT_STATUS and "status" in ft:
                    errors.append("%s.status '%s': not one of %s" % (fw, ft["status"], sorted(FEAT_STATUS)))
                if "sdd" in ft and not isinstance(ft["sdd"], bool):
                    errors.append("%s.sdd: expected boolean" % fw)
                if "autonomous" in ft and not isinstance(ft["autonomous"], bool):
                    errors.append("%s.autonomous: expected boolean" % fw)
                if "spec_path" in ft and not isinstance(ft["spec_path"], str):
                    errors.append("%s.spec_path: expected string" % fw)
                if "depends_on" in ft:
                    dep = ft["depends_on"]
                    if not isinstance(dep, list) or not all(isinstance(x, str) for x in dep):
                        errors.append("%s.depends_on: expected array of strings" % fw)

for e in errors:
    print("  " + e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
    ok "TaskStore (local) valid against schema"
  else
    # The local backend is zero-dependency: a missing python3 must not block the
    # gate. We can't validate the schema here, so warn loudly and continue.
    echo "⚠️  python3 not found — skipping TaskStore schema validation (install python3 to enable it)" >&2
  fi
fi

# 3. Project-specific checks.
#    Project-authored gates live in `.harness/init.project.sh` — seeded once by
#    harness-install.sh and NEVER clobbered on upgrade, unlike THIS file (which is
#    harness BODY and gets overwritten). Put tests/build/lint/presence checks there
#    rather than editing this file, or they vanish on the next upgrade. The hook is
#    sourced from the PROJECT ROOT so `npm test` / `pytest` resolve against the repo,
#    and it inherits the `fail`/`ok` helpers defined above.
cd "$PROJECT_ROOT"
PROJECT_CHECKS="$HARNESS_DIR/init.project.sh"
if [ -f "$PROJECT_CHECKS" ]; then
  # shellcheck source=/dev/null
  . "$PROJECT_CHECKS"
else
  echo "ℹ️  no project-specific checks (.harness/init.project.sh absent)"
fi

echo "──────────────────────────────────────────────────"
ok "environment ready — agents may proceed"
