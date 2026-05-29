#!/usr/bin/env bash
# init.sh — environment verification gate.
# The Orchestrator MUST run this before any work. Non-zero exit = STOP.
# It proves the harness is structurally healthy so agents don't hallucinate fixes.
#
# Adapt the project-specific section to the target repo (tests, deps, build).

set -euo pipefail

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

# 2. TaskStore presence (local backend).
if grep -q "tasks: local" harness.config.yaml 2>/dev/null; then
  [ -f state/tasks.json ] || fail "state/tasks.json missing (local TaskStore)"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; json.load(open('state/tasks.json'))" \
      || fail "state/tasks.json is not valid JSON"
  fi
  ok "TaskStore (local) valid"
fi

# 3. Project-specific checks — EDIT FOR THE TARGET REPO.
#    Example: verify the toolchain and run the test suite. Uncomment + adapt.
#
# command -v node >/dev/null 2>&1 || fail "node not installed"
# npm test --silent             || fail "tests are failing — do not start work"
#
echo "ℹ️  no project-specific checks configured (edit init.sh for the target repo)"

echo "──────────────────────────────────────────────────"
ok "environment ready — agents may proceed"
