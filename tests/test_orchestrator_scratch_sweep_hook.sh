#!/bin/sh
# test_orchestrator_scratch_sweep_hook.sh — E34-F01 R9: pin the Orchestrator's
# "Writing `done`" scratch-sweep hook in agents/orchestrator.md.
#
# Same technique as tests/test_scratch_and_disk_preconditions.sh and
# tests/test_landed_evidence.sh: section-scope by heading (fence-aware, via the one
# shared tests/lib/fence.awk), assert an anti-truncation marker from the section's
# END as well as its start (a truncated extraction is non-empty, so an emptiness
# check alone would let every assertion below run against a prefix), then
# sentence-anchor each obligation with a bounded `[^.]{0,N}` window rather than a
# bare keyword grep, so the tokens have to co-occur in ONE sentence.
#
# WHAT THIS DOES NOT PIN: whether the Orchestrator actually RUNS the sweep at
# runtime — that is behavior a prose file cannot demonstrate; only that the step is
# documented, in the right place, with the right contract. Same bound
# tests/test_scratch_and_disk_preconditions.sh already states about its own checks.

set -eu
LC_ALL=C; export LC_ALL

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$SRC"

ORCH="agents/orchestrator.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -f "$ORCH" ] || fail "R9: $ORCH is missing"

_FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"
section() {  # section <heading-substring> <file>
  awk -v h="$1" "$_FENCE_AWK"'
    fence_delim($0) { if (k) print; next }
    !fence && /^#+ / { k = (index($0, h) > 0); next }
    k
  ' "$2"
}

flat() { sed 's/[*`]//g' | tr '\n' ' ' | sed 's/[[:blank:]][[:blank:]]*/ /g'; }

DONE_SEC="$(section 'Writing `done`' "$ORCH" | flat)"
[ -n "$DONE_SEC" ] \
  || fail "R9: orchestrator.md has no 'Writing \`done\`' section — the heading was renamed or removed"

# ANTI-TRUNCATION, same marker tests/test_landed_evidence.sh R19 already anchors at
# this section's true end.
printf '%s\n' "$DONE_SEC" | grep -qi 'full decision table' \
  || fail "R9: the 'Writing \`done\`' section extraction is TRUNCATED — it does not reach its final paragraph, so every assertion below would run against a prefix"

# ── the sweep step is placed immediately after the done write ────────────────────
printf '%s\n' "$DONE_SEC" | grep -qiE 'immediately after[^.]{0,80}set-status[^.]{0,20}done' \
  || fail "R9: the section does not say the sweep runs IMMEDIATELY AFTER the set-status ... done write, in one sentence"

# ── the exact invocation: scoped to the feature id, with --apply ─────────────────
printf '%s\n' "$DONE_SEC" | grep -qF 'sweep-scratch.sh <id> --apply' \
  || fail "R9: the section does not name the exact invocation 'sweep-scratch.sh <id> --apply'"
printf '%s\n' "$DONE_SEC" | grep -qi '.harness/tools/sweep-scratch.sh <id> --apply' \
  || fail "R9: the section does not also name the installed-layout equivalent invocation"
printf '%s\n' "$DONE_SEC" | grep -qiF 'scoped to that feature id' \
  || fail "R9: the section does not state the sweep is SCOPED to the just-landed feature id"

# ── best-effort / non-blocking / never reverts the done write ────────────────────
printf '%s\n' "$DONE_SEC" | grep -qiE 'best-effort' \
  || fail "R9: the section does not call the sweep invocation best-effort"
# NOTE: '.{0,N}' rather than the repo's usual '[^.]{0,N}' sentence-boundary window —
# the sentence itself contains "(e.g. ...)", whose periods would otherwise break the
# window before it ever reaches the rest of the clause. Each sub-window below is
# still tight enough to stay inside this one sentence (measured, not guessed).
printf '%s\n' "$DONE_SEC" | grep -qiE 'non-zero sweep exit is recorded.{0,90}never blocks' \
  || fail "R9: the section does not say a non-zero sweep exit is RECORDED and never BLOCKS the loop, in one sentence"
printf '%s\n' "$DONE_SEC" | grep -qiE 'never blocks.{0,60}never reverts or reopens' \
  || fail "R9: the section does not say the sweep never blocks AND never reverts/reopens, in one sentence"
printf '%s\n' "$DONE_SEC" | grep -qiE 'never reverts or reopens.{0,40}done' \
  || fail "R9: the section does not say the sweep never reverts or reopens the done write"

pass "R9 orchestrator_writing_done_sweep_hook_documented"
echo "All orchestrator scratch-sweep-hook tests passed."
