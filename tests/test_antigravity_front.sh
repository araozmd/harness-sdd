#!/bin/sh
# test_antigravity_front.sh — E33-F01: Antigravity skill invocation adapters,
# dynamic subagent dispatch, and canonical documentation.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

test_skills_invocation_adapter() {
  _skills="sdd-drill sdd-fix sdd-fix-parallel sdd-new sdd-next sdd-plan sdd-pr-loop"
  for s in $_skills; do
    _f="$ROOT/.agents/skills/$s/SKILL.md"
    [ -f "$_f" ] || fail "Missing skill file: $_f"
    grep -q "In Antigravity or OpenCode, invoke \`/$s\`" "$_f" || \
      fail "Skill $s does not document Antigravity slash-command invocation in ## Invocation adapter"
    grep -q "in Codex, invoke \`\$$s\`" "$_f" || \
      fail "Skill $s does not preserve Codex invocation adapter"
  done
  pass "test_skills_invocation_adapter"
}

test_orchestrator_antigravity_guidance() {
  _orch="$ROOT/agents/orchestrator.md"
  [ -f "$_orch" ] || fail "Missing orchestrator.md"
  grep -qi "Antigravity" "$_orch" || fail "orchestrator.md does not mention Antigravity"
  grep -q "define_subagent" "$_orch" || fail "orchestrator.md does not describe define_subagent"
  grep -q "invoke_subagent" "$_orch" || fail "orchestrator.md does not describe invoke_subagent"
  pass "test_orchestrator_antigravity_guidance"
}

test_reviewer_isolation_guidance() {
  _next="$ROOT/.agents/skills/sdd-next/SKILL.md"
  [ -f "$_next" ] || fail "Missing sdd-next/SKILL.md"
  grep -q "define_subagent" "$_next" || fail "sdd-next/SKILL.md missing define_subagent dispatch guidance"
  grep -q "invoke_subagent" "$_next" || fail "sdd-next/SKILL.md missing invoke_subagent dispatch guidance"
  pass "test_reviewer_isolation_guidance"
}

test_docs_antigravity_presence() {
  grep -q "Antigravity" "$ROOT/AGENTS.md" || fail "AGENTS.md missing Antigravity support mention"
  grep -q "Antigravity" "$ROOT/README.md" || fail "README.md missing Antigravity support mention"
  grep -q "Antigravity" "$ROOT/docs/WORKFLOW.md" || fail "docs/WORKFLOW.md missing Antigravity support mention"
  pass "test_docs_antigravity_presence"
}

test_init_sh_exit() {
  "$ROOT/init.sh" >/dev/null 2>&1 || fail "init.sh failed"
  pass "test_init_sh_exit"
}

test_skills_invocation_adapter
test_orchestrator_antigravity_guidance
test_reviewer_isolation_guidance
test_docs_antigravity_presence
test_init_sh_exit

echo "All Antigravity front-end tests passed."
