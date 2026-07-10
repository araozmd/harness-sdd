#!/bin/sh
# test_doc_critic.sh — contract assertions for the doc-critic advisory review pass.
# Static grep checks over the new role and the checkpoint wiring in the three
# generating-agent contracts. Zero dependencies; runs in the harness source tree.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ROLE="$SRC/agents/doc-critic.md"
PLANNER="$SRC/agents/planner.md"
DRILLER="$SRC/agents/driller.md"
ARCHITECT="$SRC/agents/architect.md"
WORKFLOW="$SRC/docs/WORKFLOW.md"
SCHEMA="$SRC/store/tasks.schema.json"
STATE="$SRC/state/tasks.json"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: portable doc-critic role exists ───────────────────────────────────────
test_doc_critic_role_exists() {
  [ -f "$ROLE" ] || fail "R1: agents/doc-critic.md missing"
  grep -qE '^# Agent: Doc-critic' "$ROLE" || fail "R1: role header missing"
  pass "R1: portable doc-critic role exists"
}

# ── R2: role accepts target-type argument ─────────────────────────────────────
test_target_type_argument() {
  grep -qF 'target-type' "$ROLE" || fail "R2: target-type argument not mentioned"
  grep -qF '## Invocation contract' "$ROLE" || fail "R2: invocation contract section missing"
  pass "R2: role accepts target-type argument"
}

# ── R3: three target-type scopes are defined ──────────────────────────────────
test_target_type_scopes() {
  grep -qF 'plan-output' "$ROLE" || fail "R3: plan-output scope missing"
  grep -qF 'epic-decomposition' "$ROLE" || fail "R3: epic-decomposition scope missing"
  grep -qF 'feature-spec' "$ROLE" || fail "R3: feature-spec scope missing"
  pass "R3: three target-type scopes defined"
}

# ── R4: critic flags only real downstream problems ────────────────────────────
test_calibration() {
  grep -qF 'Completeness' "$ROLE" || fail "R4: completeness dimension missing"
  grep -qF 'Consistency' "$ROLE" || fail "R4: consistency dimension missing"
  grep -qF 'Clarity' "$ROLE" || fail "R4: clarity dimension missing"
  grep -qF 'Scope' "$ROLE" || fail "R4: scope dimension missing"
  grep -qF 'YAGNI' "$ROLE" || fail "R4: YAGNI dimension missing"
  grep -qF 'only issues that would cause real downstream problems' "$ROLE" \
    || fail "R4: calibration rule missing"
  pass "R4: critic calibrated to real downstream problems"
}

# ── R5: recommendations are advisory, inline-fix-then-proceed ─────────────────
test_advisory_inline_fix() {
  grep -qF 'advisory' "$ROLE" || fail "R5: advisory keyword missing"
  grep -qF 'inline' "$ROLE" || fail "R5: inline-fix keyword missing"
  grep -qF 'proceed' "$ROLE" || fail "R5: proceed keyword missing"
  grep -qF 'never block' "$ROLE" || fail "R5: never-block rule missing"
  pass "R5: advisory-only inline-fix-then-proceed stated"
}

# ── R6: best-effort proceed on error/timeout with progress note ───────────────
test_best_effort_failure() {
  grep -qF 'best-effort' "$ROLE" || fail "R6: best-effort keyword missing"
  grep -qF 'timeout' "$ROLE" || fail "R6: timeout keyword missing"
  grep -qF 'errors' "$ROLE" || fail "R6: errors keyword missing"
  grep -qF 'proceed' "$ROLE" || fail "R6: proceed-on-failure keyword missing"
  pass "R6: best-effort failure posture stated"
}

# ── R7: critic writes a progress note summarizing changes ─────────────────────
test_progress_note() {
  grep -qF 'progress/<run>/' "$ROLE" || fail "R7: progress/<run>/ output not required"
  grep -qF 'issues found' "$ROLE" || fail "R7: issues-found summary missing"
  grep -qF 'fix' "$ROLE" || fail "R7: fix summary missing"
  pass "R7: progress-note output required"
}

# ── R8: critic reviews documents only, not code ───────────────────────────────
test_no_code_review() {
  grep -qiF 'documents only' "$ROLE" || fail "R8: documents-only boundary missing"
  grep -qF 'production code' "$ROLE" || fail "R8: production-code exclusion missing"
  pass "R8: critic reviews documents only"
}

# ── R9: planner invokes critic after /sdd-plan ────────────────────────────────
test_planner_invokes_critic() {
  grep -qF 'Doc-critic' "$PLANNER" || fail "R9: planner does not name Doc-critic"
  grep -qF 'target-type=plan-output' "$PLANNER" || fail "R9: planner missing target-type=plan-output"
  grep -qF 'spawn' "$PLANNER" || fail "R9: planner missing spawn wording"
  pass "R9: planner invokes doc-critic after /sdd-plan"
}

# ── R10: planner checkpoint enforces drillable-minimum on epic.md ─────────────
test_drillable_minimum() {
  grep -qF 'Drillable-minimum checklist' "$PLANNER" || fail "R10: drillable-minimum checklist missing"
  grep -qF 'Business brief' "$PLANNER" || fail "R10: business brief element missing"
  grep -qF 'success criteria' "$PLANNER" || fail "R10: success-criteria element missing"
  grep -qF 'Technical considerations' "$PLANNER" || fail "R10: technical-considerations element missing"
  grep -qF 'Cross-epic dependencies' "$PLANNER" || fail "R10: cross-epic-dependencies element missing"
  grep -qF 'ADRs' "$PLANNER" || fail "R10: ADR-pointer element missing"
  pass "R10: planner enforces drillable-minimum on epic.md"
}

# ── R11: driller invokes critic after /sdd-drill ──────────────────────────────
test_driller_invokes_critic() {
  grep -qF 'Doc-critic' "$DRILLER" || fail "R11: driller does not name Doc-critic"
  grep -qF 'target-type=epic-decomposition' "$DRILLER" || fail "R11: driller missing target-type=epic-decomposition"
  grep -qF 'spawn' "$DRILLER" || fail "R11: driller missing spawn wording"
  pass "R11: driller invokes doc-critic after /sdd-drill"
}

# ── R12: architect invokes critic before spec-ready hand-off ──────────────────
test_architect_invokes_critic() {
  grep -qF 'Doc-critic' "$ARCHITECT" || fail "R12: architect does not name Doc-critic"
  grep -qF 'target-type=feature-spec' "$ARCHITECT" || fail "R12: architect missing target-type=feature-spec"
  grep -qF 'spawn' "$ARCHITECT" || fail "R12: architect missing spawn wording"
  pass "R12: architect invokes doc-critic before spec-ready hand-off"
}

# ── R15: VERSION bumped + CHANGELOG entry ─────────────────────────────────────
test_version_and_changelog() {
  [ -f "$SRC/VERSION" ] || fail "R15: VERSION file missing"
  _ver="$(cat "$SRC/VERSION")"
  case "$_ver" in
    *.*.*) : ;;
    *) fail "R15: VERSION '$_ver' is not SemVer-ish" ;;
  esac
  [ -f "$SRC/CHANGELOG.md" ] || fail "R15: CHANGELOG.md missing"
  grep -qF "[$_ver]" "$SRC/CHANGELOG.md" || fail "R15: CHANGELOG missing entry for $_ver"
  grep -qF 'doc-critic' "$SRC/CHANGELOG.md" || fail "R15: CHANGELOG does not mention doc-critic"
  pass "R15: VERSION ($_ver) bumped with CHANGELOG entry"
}

# ── R16: WORKFLOW.md documents checkpoints ────────────────────────────────────
test_workflow_docs() {
  grep -qF '## Doc-critic checkpoints' "$WORKFLOW" || fail "R16: Doc-critic checkpoints section missing"
  grep -qF '/sdd-plan' "$WORKFLOW" || fail "R16: /sdd-plan checkpoint not documented"
  grep -qF '/sdd-drill' "$WORKFLOW" || fail "R16: /sdd-drill checkpoint not documented"
  grep -qF 'spec-ready' "$WORKFLOW" || fail "R16: spec-ready checkpoint not documented"
  grep -qF 'advisory' "$WORKFLOW" || fail "R16: advisory nature not documented"
  grep -qF 'inline' "$WORKFLOW" || fail "R16: inline-fix nature not documented"
  grep -qF 'best-effort' "$WORKFLOW" || fail "R16: best-effort nature not documented"
  pass "R16: WORKFLOW.md documents doc-critic checkpoints"
}

# ── R17: no schema change ─────────────────────────────────────────────────────
test_no_schema_change() {
  # The critic adds no TaskStore fields or status values. A cheap, additive check:
  # no mention of critic in the schema, and the feature status enum remains the
  # canonical five values.
  grep -qiF 'critic' "$SCHEMA" && fail "R17: schema mentions critic (should be unchanged)"
  # The feature status enum is the one that follows the feature id pattern
  # "^E[0-9]+-F[0-9]+$". Capture that enum only.
  _feature_statuses="$(awk '
    /"pattern": "\^E\[0-9\]\+-F\[0-9\]\+\$"/ { in_feature=1 }
    in_feature && /"status": \{/ { in_status=1 }
    in_status && /"enum": \[/ {
      gsub(/.*\[|].*/, ""); print; in_status=0; in_feature=0
    }
  ' "$SCHEMA")"
  printf '%s' "$_feature_statuses" | tr -d ' \n"' | grep -qx 'pending,spec-ready,in-progress,in-review,done' \
    || fail "R17: feature status enum changed ('$_feature_statuses')"
  pass "R17: no schema change for doc-critic"
}

# ── R18: no new human gate ────────────────────────────────────────────────────
test_no_new_gate() {
  # The role itself must be advisory/non-blocking.
  grep -qE 'advisory[- ]only' "$ROLE" || fail "R18: advisory-only rule missing"
  grep -qF 'never block' "$ROLE" || fail "R18: never-block rule missing"
  # The workflow docs must not introduce a new status or gate.
  grep -qF '## Doc-critic checkpoints' "$WORKFLOW" || fail "R18: workflow section missing"
  # No new status values beyond the canonical feature set.
  _statuses="$(awk '
    /"pattern": "\^E\[0-9\]\+-F\[0-9\]\+\$"/ { in_feature=1 }
    in_feature && /"status": \{/ { in_status=1 }
    in_status && /"enum": \[/ {
      gsub(/.*\[|].*/, ""); print; in_status=0; in_feature=0
    }
  ' "$SCHEMA")"
  printf '%s' "$_statuses" | tr -d ' \n"' | grep -qx 'pending,spec-ready,in-progress,in-review,done' \
    || fail "R18: feature status enum changed ('$_statuses')"
  pass "R18: no new human gate or status value"
}

# ── portability: no CLI-specific instructions ─────────────────────────────────
test_portability() {
  grep -qF 'AGENTS.md-compatible' "$ROLE" || fail "portability: role not marked AGENTS.md-compatible"
  grep -qiF 'Claude Code' "$ROLE" && fail "portability: role contains Claude-specific wording"
  pass "portability: doc-critic role is CLI-agnostic"
}

# ── run all tests ─────────────────────────────────────────────────────────────
test_doc_critic_role_exists
test_target_type_argument
test_target_type_scopes
test_calibration
test_advisory_inline_fix
test_best_effort_failure
test_progress_note
test_no_code_review
test_planner_invokes_critic
test_drillable_minimum
test_driller_invokes_critic
test_architect_invokes_critic
test_version_and_changelog
test_workflow_docs
test_no_schema_change
test_no_new_gate
test_portability

echo "All doc-critic contract tests passed."
