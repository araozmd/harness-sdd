#!/bin/sh
# test_reviewer.sh — static verification for E05-F01 (Reviewer cross-file consistency
# + explicit build↔review rounds). This feature ships PROSE only (two role files plus
# a coherence pass), so verification is the role-content-assertion pattern: grep the
# role/doc files for the required clauses, and assert the DO-NOT-TOUCH invariant (the
# status enum in store/tasks.schema.json is unchanged). The one behavioral criterion
# (the Reviewer actually catching a planted contradiction) is the documented manual
# check in F01-reviewer-cross-file.tests.md. Zero deps: POSIX sh + grep.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

REVIEWER="agents/reviewer.md"
ORCH="agents/orchestrator.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: reviewer.md defines a "Cross-file consistency" check item ────────────────
[ -f "$REVIEWER" ] || fail "R1: $REVIEWER missing"
grep -qi 'cross-file consistency' "$REVIEWER" || fail "R1: no 'Cross-file consistency' check item"
pass "R1 cross_file_check_item"

# ── R2: check loads the collaborators the diff references ────────────────────────
grep -qi 'collaborators' "$REVIEWER" || fail "R2: does not mention loading collaborators"
grep -qi 'references\|invoke' "$REVIEWER" || fail "R2: does not tie collaborators to what the diff references/invokes"
pass "R2 loads_collaborators"

# ── R3: expansion scoped, curate-don't-dump ──────────────────────────────────────
grep -qi 'scoped' "$REVIEWER" || fail "R3: does not state expansion is scoped"
grep -qi 'curate' "$REVIEWER" || fail "R3: does not state curate-don't-dump"
grep -qi 'dump' "$REVIEWER" || fail "R3: does not warn against a whole-repo dump"
pass "R3 scoped_not_dump"

# ── R4: verifies preconditions not contradicted by invoked contracts ─────────────
grep -qi 'precondition' "$REVIEWER" || fail "R4: does not mention preconditions"
grep -qi 'contradict' "$REVIEWER" || fail "R4: does not require checking they do not contradict the contracts"
pass "R4 preconditions_not_contradicted"

# ── R5: provable violation ⇒ hard reject ─────────────────────────────────────────
grep -qi 'provably' "$REVIEWER" || fail "R5: does not state the 'provably violated' threshold"
grep -qi 'reject' "$REVIEWER" || fail "R5: does not state hard reject"
pass "R5 provable_hard_reject"

# ── R6: suspected-but-unproven ⇒ flag, not block ─────────────────────────────────
grep -qi 'flag' "$REVIEWER" || fail "R6: does not state the flag (not block) path"
grep -qi 'justify' "$REVIEWER" || fail "R6: does not ask the Builder to justify"
pass "R6 suspected_flag_not_block"

# ── R7: PR #10 worked example present ─────────────────────────────────────────────
grep -qi 'PR #10' "$REVIEWER" || fail "R7: missing the PR #10 worked example"
grep -qi 'never opens a PR\|open.*PR' "$REVIEWER" || fail "R7: worked example does not cite the 'Builder never opens a PR' contradiction"
pass "R7 pr10_worked_example"

# ── R8: reject ⇒ specific, actionable, file-based feedback ───────────────────────
grep -qi 'actionable' "$REVIEWER" || fail "R8: does not state actionable feedback"
grep -qF 'progress/<run>/review.md' "$REVIEWER" || fail "R8: does not name the progress/<run>/review.md feedback artifact"
pass "R8 actionable_file_based_feedback"

# ── R9: orchestrator.md states explicit multi-round build↔review until green ─────
[ -f "$ORCH" ] || fail "R9: $ORCH missing"
grep -qi 're-review\|until green' "$ORCH" || fail "R9: does not state re-review / until green"
grep -qi 'in-progress' "$ORCH" || fail "R9: does not route reject back to in-progress"
pass "R9 explicit_multi_round"

# ── R10: each round recorded ──────────────────────────────────────────────────────
grep -qi 'round' "$ORCH" || fail "R10: does not mention rounds"
grep -qi 'record' "$ORCH" || fail "R10: does not state each round is recorded"
pass "R10 round_recorded"

# ── R11: docs coherent with multi-round loop (no single-pass claim) ──────────────
# The review-phase wording in WORKFLOW.md must not present review as a single pass;
# it should reflect the reject→in-progress→re-review loop.
grep -qi 're-review\|repeats until green\|loop repeats' docs/WORKFLOW.md \
  || fail "R11: docs/WORKFLOW.md does not reflect the multi-round build↔review loop"
pass "R11 docs_coherent"

# ── R12: VERSION bumped + CHANGELOG entry ─────────────────────────────────────────
[ "$(tr -d ' \n\r\t' < VERSION)" = "0.6.0" ] || fail "R12: VERSION is not 0.6.0"
grep -qF '## [0.6.0]' CHANGELOG.md || fail "R12: CHANGELOG.md missing the ## [0.6.0] entry"
pass "R12 version_bumped"

# ── R13: DO NOT TOUCH — schema/status enum/builder/architect unchanged ───────────
grep -qF '"pending", "spec-ready", "in-progress", "in-review", "done"' store/tasks.schema.json \
  || fail "R13: feature status enum in schema changed"
if git -C "$ROOT" rev-parse --verify -q main >/dev/null 2>&1; then
  for f in store/tasks.schema.json agents/builder.md agents/architect.md; do
    if ! git -C "$ROOT" diff --quiet main -- "$f" 2>/dev/null; then
      fail "R13: DO-NOT-TOUCH file changed vs main: $f"
    fi
  done
fi
pass "R13 do_not_touch_clean"

echo "All reviewer tests passed."
