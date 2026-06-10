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

# Warn-only draft-epic invariant (runs on BOTH validation paths, before the
# jsonschema branch below sys.exit()s): a `draft` epic is an inception sketch,
# so its features should still be `pending`. A violation is NOT a validation
# error — the next() draft gate already neutralizes it — so we warn and continue.
if isinstance(data, dict):
    for ep in data.get("epics") or []:
        if isinstance(ep, dict) and ep.get("status") == "draft":
            for ft in (ep.get("features") or []):
                if isinstance(ft, dict) and ft.get("status") != "pending":
                    print("⚠️  draft epic %s has feature %s with status '%s' (expected 'pending'; "
                          "the draft gate keeps it unselectable)"
                          % (ep.get("id"), ft.get("id"), ft.get("status")), file=sys.stderr)

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
EPIC_STATUS = {"draft", "planned", "pending", "in-progress", "done"}
FEAT_STATUS = {"pending", "spec-ready", "in-progress", "in-review", "done"}
SLICE_STATUS = {"pending", "spec-ready", "in-progress", "in-review", "done", "failed"}

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
                # Umbrella mode (optional): mirror the slice checks from the JSON
                # schema so corrupted cross-repo state is rejected even without
                # jsonschema installed. Absent `slices` ⇒ single-repo, unaffected.
                if "slices" in ft:
                    slices = ft["slices"]
                    if not isinstance(slices, list):
                        errors.append("%s.slices: expected array" % fw); slices = []
                    elif len(slices) == 0:
                        errors.append("%s.slices: must have at least 1 item (omit the field for single-repo)" % fw)
                    for si, sl in enumerate(slices):
                        sw = "%s.slices[%d]" % (fw, si)
                        if not isinstance(sl, dict):
                            errors.append("%s: expected object" % sw); continue
                        for k in ("id", "repo", "status"):
                            need(sl, k, sw)
                        if "id" in sl:
                            if not isinstance(sl["id"], str):
                                errors.append("%s.id: expected string" % sw)
                            elif not re.match(r"^E[0-9]+-F[0-9]+@[a-z0-9-]+$", sl["id"]):
                                errors.append("%s.id %r: must match ^E[0-9]+-F[0-9]+@[a-z0-9-]+$" % (sw, sl["id"]))
                        if "repo" in sl and not isinstance(sl["repo"], str):
                            errors.append("%s.repo: expected string" % sw)
                        if sl.get("status") not in SLICE_STATUS and "status" in sl:
                            errors.append("%s.status '%s': not one of %s" % (sw, sl["status"], sorted(SLICE_STATUS)))
                        if "merged" in sl and not isinstance(sl["merged"], bool):
                            errors.append("%s.merged: expected boolean" % sw)
                        if "spec_path" in sl and not isinstance(sl["spec_path"], str):
                            errors.append("%s.spec_path: expected string" % sw)
                        if "pr" in sl and not isinstance(sl["pr"], str):
                            errors.append("%s.pr: expected string" % sw)
                        if "depends_on" in sl:
                            sdep = sl["depends_on"]
                            if not isinstance(sdep, list) or not all(isinstance(x, str) for x in sdep):
                                errors.append("%s.depends_on: expected array of strings" % sw)
                    # Cross-field: a sliced feature may only be `done` when every slice
                    # is done AND merged. Guards a hand-edited/partial store from
                    # dispatching dependents (which gate on the stored feature status).
                    if ft.get("status") == "done":
                        for si, sl in enumerate(slices):
                            if not isinstance(sl, dict):
                                continue
                            if sl.get("status") != "done" or sl.get("merged") is not True:
                                errors.append("%s.slices[%d]: feature is 'done' but slice is not done+merged" % (fw, si))

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

# 2b. Umbrella mode (additive, opt-in). Engaged ONLY when harness.config.yaml has a
#     non-empty `umbrella.manifest` AND that file exists. Inert otherwise, so a
#     single-repo target is completely unaffected. The check is NON-FATAL: it warns
#     about manifest repos whose `path` is missing rather than blocking the gate.
UMBRELLA_MANIFEST="$(sed -n 's/^[[:space:]]*manifest:[[:space:]]*"\{0,1\}\([^"#]*\)"\{0,1\}.*/\1/p' harness.config.yaml 2>/dev/null | head -n1 | sed 's/[[:space:]]*$//')"
if [ -n "${UMBRELLA_MANIFEST:-}" ] && [ -f "$UMBRELLA_MANIFEST" ]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$UMBRELLA_MANIFEST" <<'PY' || true
import sys, os, re
path = sys.argv[1]
base = os.path.dirname(os.path.abspath(path))
repo = None
missing = []
try:
    with open(path) as f:
        lines = f.readlines()
except OSError as e:
    print("⚠️  umbrella manifest unreadable: %s" % e); sys.exit(0)
# Minimal YAML read (zero-dep): top-level `repos:` mapping, each repo a 2-space key
# with a `path:` under it. Good enough to flag missing child-repo paths.
in_repos = False
for ln in lines:
    if re.match(r"^repos:\s*$", ln):
        in_repos = True; continue
    if in_repos and re.match(r"^\S", ln):
        in_repos = False
    if not in_repos:
        continue
    # Repo keys must use the SAME grammar as the slice-id `@<repo>` segment
    # (^[a-z0-9-]+$). A key with an underscore/uppercase could not be represented
    # as a canonical slice id `E03-F01@<repo>`, so flag it rather than silently
    # accepting an undispatchable manifest entry.
    m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", ln)
    if m:
        repo = m.group(1)
        if not re.match(r"^[a-z0-9-]+$", repo):
            print("⚠️  umbrella manifest: repo key '%s' is not a valid slice-id segment "
                  "(use ^[a-z0-9-]+$ to match '<feature-id>@<repo>')" % repo, file=sys.stderr)
        continue
    m = re.match(r"^\s+path:\s*\"?([^\"#\n]+)\"?", ln)
    if m and repo:
        p = m.group(1).strip()
        full = p if os.path.isabs(p) else os.path.join(base, p)
        if not os.path.exists(full):
            missing.append((repo, p))
for r, p in missing:
    print("⚠️  umbrella manifest: repo '%s' path not found: %s" % (r, p))
PY
  fi
  echo "ℹ️  umbrella mode: manifest present ($UMBRELLA_MANIFEST)"
fi

# 3. Project-specific checks.
#    Project-authored gates live in `.harness/init.project.sh` — seeded once by
#    harness-install.sh and NEVER clobbered on upgrade, unlike THIS file (which is
#    harness BODY and gets overwritten). Put FAST structural/presence/build checks
#    here (the things that must hold for any agent to safely proceed) rather than
#    editing this file, or they vanish on the next upgrade.
#    KEEP IT FAST: init.sh runs before EVERY orchestrator step, so a slow suite here
#    taxes the whole loop (multiplied across slices in umbrella mode). The heavy test
#    suite belongs in `verification.test_command`, which the Reviewer runs once at the
#    `in-review` gate — not here. The hook is sourced from the PROJECT ROOT so
#    `npm test` / `pytest` resolve against the repo, and it inherits the `fail`/`ok`
#    helpers defined above.
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
