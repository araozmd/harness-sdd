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
  # python3 is a HARD prerequisite for the local backend, not optional. Since
  # E15-F01 the ONLY supported `set_status` write path is the flock-guarded
  # `python3 tools/tasks-lock.py`, and schema validation runs the same
  # `python3 tools/validate-board.py`. A python3-less install would look "ready"
  # here yet fail on the very first Orchestrator transition with
  # `python3: not found`, so we fail-stop now with a clear message rather than
  # warn-and-continue.
  command -v python3 >/dev/null 2>&1 \
    || fail "python3 not found — REQUIRED for TaskStore schema validation and the mandatory board write lock (tools/tasks-lock.py). Install python3 and re-run."
  # The lock helper depends on stdlib fcntl.flock; it is stdlib on every Unix
  # target but verify it is importable so a broken/stripped interpreter fails
  # clearly HERE, not mid-transition.
  python3 -c "import fcntl" 2>/dev/null \
    || fail "python3 lacks the stdlib 'fcntl' module — REQUIRED for the board write lock (tools/tasks-lock.py). Use a Unix python3 with fcntl support."
  # The validation logic lives in ONE canonical place — tools/validate-board.py —
  # shared verbatim with the guarded write path (tasks-lock.py imports its
  # validate()). It prefers jsonschema.Draft7Validator when importable and
  # otherwise runs the complete zero-dependency structural check, so init.sh
  # stays zero-dependency while accepting/rejecting exactly what the write lock
  # does. Same stderr contract as before (draft warning, then two-space-prefixed
  # errors) and non-zero on invalid.
  python3 tools/validate-board.py state/tasks.json store/tasks.schema.json \
    || fail "state/tasks.json failed schema validation (see errors above)"
  ok "TaskStore (local) valid against schema"
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

# 2c. ADR-citation sweep (WARN-ONLY, additive). Feature specs cite the ADRs they
#     honor in a `## Architecture alignment` section (agents/architect.md); the
#     Reviewer soft-flags a cited-but-nonexistent id at review time. This sweep
#     surfaces the same typo at session start instead: for each
#     specs/epics/**/*.spec.md carrying the section, every `ADR-NNNN` cited INSIDE
#     that section (only there — incidental ADR-NNNN mentions elsewhere don't count)
#     must resolve to an existing specs/adr/NNNN-*.md. A miss WARNS and NEVER fails
#     the gate (the ADR may have been renamed/removed legitimately — the Reviewer's
#     soft flag owns the verdict). No-op when specs/adr/ is absent (graceful
#     degradation, mirroring the Reviewer check's precondition). Zero-dep + fast:
#     one grep -rl over specs/epics plus a tiny awk per matching spec.
if [ -d specs/adr ]; then
  ADR_MISS=0
  for spec in $(grep -rl '^## Architecture alignment' specs/epics --include='*.spec.md' 2>/dev/null || true); do
    for id in $(awk '/^## Architecture alignment/{f=1;next} /^## /{f=0} f' "$spec" \
                | grep -oE 'ADR-[0-9]{4}' | sort -u || true); do
      n="${id#ADR-}"
      if ! ls "specs/adr/${n}-"*.md >/dev/null 2>&1; then
        echo "⚠️  ADR citation: $spec cites $id but no specs/adr/${n}-*.md exists"
        ADR_MISS=$((ADR_MISS+1))
      fi
    done
  done
  if [ "$ADR_MISS" -eq 0 ]; then
    ok "ADR citations resolve (specs/adr/ present)"
  else
    echo "⚠️  $ADR_MISS unresolved ADR citation(s) — warn-only, never blocks the gate (fix the typo or update the spec)"
  fi
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
