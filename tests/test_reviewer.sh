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
grep -qiE 'references|invoke' "$REVIEWER" || fail "R2: does not tie collaborators to what the diff references/invokes"
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
grep -qiE 'never opens a PR|open.*PR' "$REVIEWER" || fail "R7: worked example does not cite the 'Builder never opens a PR' contradiction"
pass "R7 pr10_worked_example"

# ── R8: reject ⇒ specific, actionable, file-based feedback ───────────────────────
grep -qi 'actionable' "$REVIEWER" || fail "R8: does not state actionable feedback"
grep -qF 'progress/<run>/review.md' "$REVIEWER" || fail "R8: does not name the progress/<run>/review.md feedback artifact"
pass "R8 actionable_file_based_feedback"

# ── R9: orchestrator.md states explicit multi-round build↔review until green ─────
[ -f "$ORCH" ] || fail "R9: $ORCH missing"
grep -qiE 're-review|until green' "$ORCH" || fail "R9: does not state re-review / until green"
grep -qi 'in-progress' "$ORCH" || fail "R9: does not route reject back to in-progress"
pass "R9 explicit_multi_round"

# ── R10: each round recorded ──────────────────────────────────────────────────────
grep -qi 'round' "$ORCH" || fail "R10: does not mention rounds"
grep -qi 'record' "$ORCH" || fail "R10: does not state each round is recorded"
pass "R10 round_recorded"

# ── R11: docs coherent with multi-round loop (no single-pass claim) ──────────────
# The review-phase wording in WORKFLOW.md must not present review as a single pass;
# it should reflect the reject→in-progress→re-review loop.
grep -qiE 're-review|repeats until green|loop repeats' docs/WORKFLOW.md \
  || fail "R11: docs/WORKFLOW.md does not reflect the multi-round build↔review loop"
pass "R11 docs_coherent"

# ── R12: VERSION is valid semver AND CHANGELOG carries its entry ─────────────────
# Permanent-suite-safe: this runs on EVERY future harness review, so it must NOT pin
# one release (0.6.0). The durable invariant is "VERSION is semver and CHANGELOG has a
# matching entry" — which stays green across every legitimate future bump. Whether THIS
# PR bumped VERSION is a PR-review-time concern (Codex / the Reviewer), not a frozen
# assertion. (See the identical lesson applied to tests/test_inception.sh in PR #10.)
_VER="$(tr -d ' \n\r\t' < VERSION)"
printf '%s' "$_VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "R12: VERSION '$_VER' is not semver"
grep -qF "## [$_VER]" CHANGELOG.md || fail "R12: CHANGELOG.md missing the ## [$_VER] entry"
pass "R12 version_changelog_coupled"

# ── R13: DO NOT TOUCH — status enum invariant ────────────────────────────────────
# Permanent invariant only: the five-value status enum must never silently change.
# We deliberately do NOT diff agents/builder.md / agents/architect.md vs main here —
# that was E05-F01's per-feature DO-NOT-TOUCH boundary, not a permanent gate, and
# freezing it would wrongly fail any future feature that legitimately edits those
# files (the same leak fixed in tests/test_inception.sh, PR #10).
grep -qF '"pending", "spec-ready", "in-progress", "in-review", "done"' store/tasks.schema.json \
  || fail "R13: feature status enum in schema changed"
pass "R13 status_enum_intact"

# ── R16: the mutation-mandate suite still EXISTS and is still discoverable ───────
# (E99-F67. Numbered R16, not R14/R15: those two ids are already taken by the unmerged
# branch `fix/E99-F58-mutation-revert-discipline`, and reusing them would collide the
# day it lands. The gap is deliberate and this comment is the record of why.)
#
# This assertion lives HERE, in a different suite, on purpose. `tools/run-tests.sh`
# discovers `tests/test_*.sh` by glob, so renaming the mandate suite out of that glob
# removes it from the verification command AND from the run's suite count, and the
# runner reports "all N suites passed" — a green result that means the Reviewer's
# checks 3b/3c are no longer verified by anything. A self-check inside that file cannot
# catch its own absence: it is only ever evaluated in the world where it still runs.
_MM="tests/test_reviewer_mutation_mandate.sh"
[ -f "$_MM" ] \
  || fail "R16: $_MM is missing — the Reviewer's checks 3b/3c (agents/reviewer.md) are no longer pinned by anything"
case "$_MM" in
  tests/test_*.sh) : ;;
  *) fail "R16: $_MM is outside the tests/test_*.sh glob that tools/run-tests.sh discovers, so it no longer runs" ;;
esac
pass "R16 mutation_mandate_suite_present_and_discoverable"

# ── R17: the campaign-precondition suite still EXISTS and is still discoverable ──
# (E99-F73. Same construction and same reason as R16 one block up: `tools/run-tests.sh`
# discovers `tests/test_*.sh` by glob, so renaming that suite out of the glob removes it
# from the verification command AND from the run's suite count while the runner reports
# "all N suites passed" — a green result meaning the Reviewer's checks 3d/3e and the
# matching `agents/builder.md` section are no longer verified by anything. A self-check
# inside that file cannot catch its own absence.)
_CP="tests/test_scratch_and_disk_preconditions.sh"
[ -f "$_CP" ] \
  || fail "R17: $_CP is missing — the scratch-namespacing and free-disk preconditions (agents/reviewer.md 3d/3e, agents/builder.md) are no longer pinned by anything"
case "$_CP" in
  tests/test_*.sh) : ;;
  *) fail "R17: $_CP is outside the tests/test_*.sh glob that tools/run-tests.sh discovers, so it no longer runs" ;;
esac
pass "R17 campaign_precondition_suite_present_and_discoverable"

echo "All reviewer tests passed."
