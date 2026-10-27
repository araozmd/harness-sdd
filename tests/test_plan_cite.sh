#!/bin/sh
# test_plan_cite.sh — E36-F04: the plan-row citation lint (tools/plan-cite-check.py), its
# init.sh warn-only sweep, Reviewer check 8 and the doc-critic's advisory flags (ADR-0009
# decision 4).
#
# Behavioral rows drive the tool against tests/fixtures/plan-cite/ (copied into a fresh
# $T/<row>/specs per row, each variant derived with sed/awk/printf so every row has exactly
# one cause). Prose rows grep the INSTALLED copy inside a BOUNDED slice — `## What you check`
# and the doc-critic section through the fence-aware slicer (tests/lib/fence.awk), the
# Stage/grammar sections by heading line numbers — and anchor whole sentences from their
# subject (`A[^.]{0,N}B` over folded newlines). Co-occurrence is not polarity: read the diff.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never git-diff a DO-NOT-TOUCH file against main; never write state/ or a live
# spec. Exit codes are asserted as `rc -eq N`, never a shell-dependent code.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/tools/plan-cite-check.py"
FX="$ROOT/tests/fixtures/plan-cite"
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
T="$(mktemp -d 2>/dev/null || mktemp -d -t plancite)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v python3 >/dev/null 2>&1 || fail "python3 is a hard harness dependency and is absent"
[ -d "$FX/specs" ] || fail "setup: fixture tree $FX/specs is missing"

# fresh <row> — copy the fixture specs tree into $T/<row>/specs and name its files.
fresh() {
  rm -rf "$T/$1"; mkdir -p "$T/$1"
  cp -R "$FX/specs" "$T/$1/specs"
  S="$T/$1/specs"
  GP="$S/epics/E01-x/F01-good/E01-F01.plan.md"; GS="$S/epics/E01-x/F01-good/E01-F01.spec.md"
  BP="$S/epics/E01-x/F02-bad/E01-F02.plan.md";  BS="$S/epics/E01-x/F02-bad/E01-F02.spec.md"
}
# run_tool <args...> — stdout to $T/out, stderr to $T/err, exit code to $rc.
run_tool() { set +e; python3 "$TOOL" "$@" >"$T/out" 2>"$T/err"; rc=$?; set -e; }
# both — stdout and stderr, for failure messages.
both() { cat "$T/out" "$T/err" 2>/dev/null | tr '\n' '|'; }
# expect_ok <row> — exit 0, exactly one stdout line and it is the ok line, stderr empty.
expect_ok() {
  [ "$rc" -eq 0 ] || fail "$1: expected rc 0, got $rc ($(both))"
  [ "$(wc -l < "$T/out" | tr -d ' ')" -eq 1 ] || fail "$1: expected exactly one stdout line ($(both))"
  grep -q '^plan-cite-check: ok ' "$T/out" || fail "$1: stdout is not the ok line ($(both))"
  [ ! -s "$T/err" ] || fail "$1: stderr is not empty ($(both))"
}
# expect_fail <row> — exit 1 and the last stdout line is the FAIL summary.
expect_fail() {
  [ "$rc" -eq 1 ] || fail "$1: expected rc 1, got $rc ($(both))"
  tail -n 1 "$T/out" | grep -qE '^plan-cite-check: FAIL [0-9]+ violation\(s\)$' \
    || fail "$1: the last stdout line is not 'plan-cite-check: FAIL <n> violation(s)' ($(both))"
}
# count <regex> — how many stdout lines match.
count() { grep -cE "$1" "$T/out" || true; }
# crlf <in> <out> — every line CRLF-terminated.
crlf() { awk '{ printf "%s\r\n", $0 }' "$1" > "$2"; }
# insert_before <file> <line-prefix> <text-file> — insert the text file's lines before the
# first line starting with the prefix (in place).
insert_before() {
  awk -v p="$2" -v f="$3" 'index($0, p) == 1 && !d { while ((getline l < f) > 0) print l; d = 1 } { print }' "$1" > "$1.new"
  mv "$1.new" "$1"
}

# ── R1: a clean plan ⇒ exit 0 and one ok line ───────────────────────────────────────────
fresh r1
run_tool "$GP" --spec "$GS"; expect_ok R1_ok_positive
pass "R1_ok_positive"

fresh r1crlf
crlf "$GP" "$GP.crlf"; mv "$GP.crlf" "$GP"; crlf "$GS" "$GS.crlf"; mv "$GS.crlf" "$GS"
grep -q "$(printf '\r')\$" "$GP" || fail "R1_ok_crlf: precondition: the plan copy is not CRLF"
run_tool "$GP" --spec "$GS"; expect_ok R1_ok_crlf
pass "R1_ok_crlf"

fresh r1fence
# A tilde fence and a 3-space-indented backtick fence, each hiding an uncited table under a
# fake `## Files to change`, inserted INSIDE the real `## Files to change` section (before
# `## Deferred`), so a mis-tracked fence turns their rows into live uncited rows.
printf '%s\n' '~~~markdown' '## Files to change' '' '| File | Change |' '|---|---|' \
  '| `tilde.py` | an uncited row in a tilde fence |' '~~~' '' \
  '   ```' '## Files to change' '| File | Change |' '|---|---|' \
  '| `indented.py` | an uncited row in an indented backtick fence |' '   ```' '' > "$T/decoys.md"
insert_before "$GP" '## Deferred' "$T/decoys.md"
grep -qF 'tilde.py' "$GP" || fail "R1_ok_fenced_decoys: precondition: the decoys were not inserted"
run_tool "$GP" --spec "$GS"; expect_ok R1_ok_fenced_decoys
pass "R1_ok_fenced_decoys"

fresh r1notables
NP="$S/epics/E01-x/F01-good/notables.plan.md"
printf '%s\n' '# No tables' '' '## Data model' '' 'No stored state.' '' '## API / interface' '' \
  'None.' '' '## Files to change' '' 'Prose only: a.py.' '' '## Deferred' '' 'Deferred: none — x' > "$NP"
run_tool "$NP" --spec "$GS"; expect_ok R1_ok_no_tables
pass "R1_ok_no_tables"

F04D="$ROOT/specs/epics/E36-emergent-slices/F04-plan-citation-gate"
run_tool "$F04D/E36-F04.plan.md" --spec "$F04D/E36-F04.spec.md"; expect_ok R1_dogfood_own_plan
pass "R1_dogfood_own_plan"
F03D="$ROOT/specs/epics/E36-emergent-slices/F03-stage-deferred-adrs"
run_tool "$F03D/E36-F03.plan.md" --spec "$F03D/E36-F03.spec.md"; expect_ok R1_dogfood_f03_plan
pass "R1_dogfood_f03_plan"

# @@R2@@

echo "all plan-cite checks passed"
