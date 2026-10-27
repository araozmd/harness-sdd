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

# ── R2: an uncited data row under one of the four headings ⇒ exit 1 uncited-row ─────────
fresh r1fencectl
insert_before "$GP" '## Deferred' "$T/decoys.md"
# R1_ok_fenced_decoys control: the same decoys with their fence delimiters removed are live
# rows, so the row above is green because the fences hid them, not because nothing is checked.
grep -vE '^ *(```|~~~)' "$GP" > "$GP.live"
run_tool "$GP.live" --spec "$GS"; expect_fail "R1_ok_fenced_decoys control"
[ "$(count '^plan-cite-check: uncited-row ')" -eq 3 ] \
  || fail "R1_ok_fenced_decoys control: unfenced decoys did not each give an uncited-row ($(both))"
pass "R1_ok_fenced_decoys control"

fresh r2
run_tool "$BP" --spec "$BS"; expect_fail R2_uncited_row
[ "$(count '^plan-cite-check: uncited-row ')" -eq 1 ] || fail "R2_uncited_row: expected exactly one uncited-row line ($(both))"
grep -qxF "plan-cite-check: uncited-row $BP:8 Data model" "$T/out" \
  || fail "R2_uncited_row: no 'uncited-row <plan>:8 Data model' line for the planted row ($(both))"
pass "R2_uncited_row"

fresh r2hdr
# The header names no R-id at all, and the separator carries alignment colons: both stay
# exempt because the header is found by POSITION (the row before a separator), not by text.
sed -e 's/^| Entity | Field | Type | Notes | R-id |$/| Entity | Field | Type | Notes | Ref |/' \
    -e '/^| Entity | Field /{n;s/^|---|---|---|---|---|$/|:---|---:|:---:|---|---|/;}' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
grep -qxF '| Entity | Field | Type | Notes | Ref |' "$GP" && grep -qxF '|:---|---:|:---:|---|---|' "$GP" \
  || fail "R2_header_separator_exempt: precondition: the header/separator rewrite did not apply"
run_tool "$GP" --spec "$GS"; expect_ok R2_header_separator_exempt
pass "R2_header_separator_exempt"

fresh r2other
grep -qF '| `fx run` |' "$GP" && grep -qF '| a pipe row under DO NOT TOUCH |' "$GP" && grep -qF '| an uncited row under an unchecked heading |' "$GP" \
  || fail "R2_other_headings_ignored: precondition: the positive plan lost its unchecked-heading rows"
run_tool "$GP" --spec "$GS"; expect_ok R2_other_headings_ignored
# control: the same CLI row moved under a checked heading is a finding
sed 's/^## CLI \/ interface$/## API \/ interface/' "$GP" > "$GP.ctl"
run_tool "$GP.ctl" --spec "$GS"; expect_fail "R2_other_headings_ignored control"
grep -qE "^plan-cite-check: uncited-row .*:[0-9]+ API / interface$" "$T/out" || fail "R2_other_headings_ignored control: no uncited-row for the CLI row once under API / interface ($(both))"
pass "R2_other_headings_ignored"

fresh r2prose
printf '%s\n' 'no citation here, just prose under the heading' '' > "$T/prose.md"
insert_before "$GP" '| Entity | Field ' "$T/prose.md"
grep -qF 'no citation here' "$GP" || fail "R2_prose_ignored: precondition: prose not inserted"
run_tool "$GP" --spec "$GS"; expect_ok R2_prose_ignored
pass "R2_prose_ignored"

fresh r2serves
grep -qxF '## Data model  (serves: R1, R2)' "$GP" || fail "R2_serves_suffix_not_citation: precondition: heading suffix changed"
printf '%s\n' '| Booking | memo | text | free text |  |' > "$T/row.md"
insert_before "$GP" '| Booking | ref |' "$T/row.md"
_ln="$(grep -n '^| Booking | memo |' "$GP" | cut -d: -f1)"
run_tool "$GP" --spec "$GS"; expect_fail R2_serves_suffix_not_citation
[ "$(count '^plan-cite-check: uncited-row ')" -eq 1 ] || fail "R2_serves_suffix_not_citation: expected exactly one uncited-row ($(both))"
grep -qxF "plan-cite-check: uncited-row $GP:$_ln Data model" "$T/out" \
  || fail "R2_serves_suffix_not_citation: the '(serves: R1, R2)' heading suffix stood in for the row's citation ($(both))"
pass "R2_serves_suffix_not_citation"

fresh r2sub
printf '%s\n' '| `f.py` | an uncited row after the level-3 heading |  |' > "$T/row.md"
awk -v f="$T/row.md" '{ print } index($0, "| `e.py` |") == 1 { while ((getline l < f) > 0) print l }' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
_ln="$(grep -n '^| `f.py` |' "$GP" | cut -d: -f1)"
[ -n "$_ln" ] || fail "R2_rows_after_subheading_checked: precondition: row not inserted"
run_tool "$GP" --spec "$GS"; expect_fail R2_rows_after_subheading_checked
grep -qxF "plan-cite-check: uncited-row $GP:$_ln Files to change" "$T/out" \
  || fail "R2_rows_after_subheading_checked: a '### sub-heading' closed the '## Files to change' section ($(both))"
pass "R2_rows_after_subheading_checked"

# ── R3: --spec given ⇒ an undeclared R<n> is unknown-rid; absent ⇒ not checked ──────────
fresh r3
run_tool "$BP" --spec "$BS"; expect_fail R3_unknown_rid
[ "$(count '^plan-cite-check: unknown-rid ')" -eq 1 ] || fail "R3_unknown_rid: expected exactly one unknown-rid line ($(both))"
grep -qxF "plan-cite-check: unknown-rid $BP:14 R9" "$T/out" || fail "R3_unknown_rid: no 'unknown-rid <plan>:14 R9' line ($(both))"
pass "R3_unknown_rid"

fresh r3nospec
run_tool "$BP"; expect_fail R3_no_spec_not_checked
[ "$(count '^plan-cite-check: unknown-rid ')" -eq 0 ] || fail "R3_no_spec_not_checked: R-id existence was checked without --spec ($(both))"
run_tool "$GP"; expect_ok R3_no_spec_not_checked
grep -qE '^plan-cite-check: ok .*, spec: not checked$' "$T/out" || fail "R3_no_spec_not_checked: the ok line does not say 'spec: not checked' ($(both))"
run_tool "$GP" --spec "$GS"; expect_ok R3_no_spec_not_checked
grep -qE '^plan-cite-check: ok .*, spec: 4 R-ids$' "$T/out" || fail "R3_no_spec_not_checked: with --spec the ok line does not count the spec's 4 R-ids ($(both))"
pass "R3_no_spec_not_checked"

fresh r3bold
printf '%s\n' '# Bold-title spec' '' '## Acceptance criteria' '' '- **R1 — Title.** The system shall do one.' \
  "- **R1's note** — prose, not an R-id." > "$T/r3bold.spec.md"
printf '%s\n' '# p' '' '## Files to change' '' '| File | Change | R-id |' '|---|---|---|' '| `a.py` | create | R1 |' \
  '' '## Deferred' '' 'Deferred: none — x' > "$S/epics/E01-x/F01-good/bold.plan.md"
run_tool "$S/epics/E01-x/F01-good/bold.plan.md" --spec "$T/r3bold.spec.md"; expect_ok R3_bold_title_rid_form
grep -qE ', spec: 1 R-ids$' "$T/out" || fail "R3_bold_title_rid_form: the bold-title form '- **R1 — Title.**' was not read as R1 ($(both))"
pass "R3_bold_title_rid_form"

fresh r3pr
grep -qF 'PR304 is a pull request' "$GP" || fail "R3_pr_number_not_a_citation: precondition: the PR304 row is gone"
run_tool "$GP" --spec "$GS"; expect_ok R3_pr_number_not_a_citation
grep -qF 'R304' "$T/out" && fail "R3_pr_number_not_a_citation: PR304 was read as the citation R304 ($(both))"
_ln="$(grep -n 'PR304 is a pull request' "$GP" | cut -d: -f1)"
sed 's/^\(| Booking | ref | text | boundary: PR304 is a pull request, not a citation | \)R2 |$/\1— |/' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
grep -qF 'not a citation | — |' "$GP" || fail "R3_pr_number_not_a_citation: precondition: R2 not removed from the PR304 row"
run_tool "$GP" --spec "$GS"; expect_fail R3_pr_number_not_a_citation
grep -qxF "plan-cite-check: uncited-row $GP:$_ln Data model" "$T/out" \
  || fail "R3_pr_number_not_a_citation: with R2 removed, the PR304 row is not uncited — PR304 counted as a citation ($(both))"
pass "R3_pr_number_not_a_citation"

# @@R4@@

echo "all plan-cite checks passed"
