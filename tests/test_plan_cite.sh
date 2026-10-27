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

# ── R4: ADR citations resolve under the namespace rule (init.sh 2c / agents/reviewer.md) ─
# add_row <file> <row> — append a data row right after the positive plan's `d.py` row (inside
# `## Files to change`); prints the new row's line number into $_ln.
add_row() {
  printf '%s\n' "$2" > "$T/row.md"
  awk -v f="$T/row.md" '{ print } index($0, "| `d.py` |") == 1 { while ((getline l < f) > 0) print l }' "$1" > "$1.new"; mv "$1.new" "$1"
  _ln="$(grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1)"
  [ -n "$_ln" ] || fail "add_row: precondition: row '$2' not inserted"
}
fresh r4
run_tool "$BP" --spec "$BS"; expect_fail R4_bare_unresolved
grep -qxF "plan-cite-check: unresolved-adr $BP:15 ADR-0042 not-in-any-namespace" "$T/out" \
  || fail "R4_bare_unresolved: no 'unresolved-adr <plan>:15 ADR-0042 not-in-any-namespace' ($(both))"
pass "R4_bare_unresolved"
grep -qxF "plan-cite-check: unresolved-adr $BP:16 bookings/ADR-0002 not-in-namespace bookings" "$T/out" \
  || fail "R4_qualified_cross_namespace: bookings/ADR-0002 resolved outside the bookings namespace ($(both))"
[ "$(count '^plan-cite-check: unresolved-adr ')" -eq 2 ] || fail "R4_qualified_cross_namespace: expected exactly two unresolved-adr lines on the negative plan ($(both))"
pass "R4_qualified_cross_namespace"

fresh r4unk
add_row "$GP" '| `u.py` | modify | nowhere/ADR-0001 |'
run_tool "$GP" --spec "$GS"; expect_fail R4_unknown_namespace
grep -qxF "plan-cite-check: unresolved-adr $GP:$_ln nowhere/ADR-0001 unknown-namespace nowhere" "$T/out" \
  || fail "R4_unknown_namespace: an unknown '<ns>/' qualifier resolved ($(both))"
pass "R4_unknown_namespace"

fresh r4qual
run_tool "$GP" --spec "$GS"; expect_ok R4_qualified_resolves
# each qualified citation resolves in ITS namespace: remove the number from that space only
_bl="$(grep -n '| platform/ADR-0001 |' "$GP" | cut -d: -f1)"; _cl="$(grep -n '| bookings/ADR-0001 |' "$GP" | cut -d: -f1)"
rm "$S/adr/0001-accepted.md"
sed 's/| ADR-0002 ADR-0001 |$/| ADR-0002 |/' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
run_tool "$GP" --spec "$GS"; expect_fail R4_qualified_resolves
[ "$(count '^plan-cite-check: unresolved-adr ')" -eq 1 ] || fail "R4_qualified_resolves: expected one unresolved-adr with platform 0001 gone ($(both))"
grep -qxF "plan-cite-check: unresolved-adr $GP:$_bl platform/ADR-0001 not-in-namespace platform" "$T/out" \
  || fail "R4_qualified_resolves: platform/ADR-0001 did not resolve against specs/adr/ only ($(both))"
fresh r4qual2
rm "$S/bookings/adr/0001-other.md"
run_tool "$GP" --spec "$GS"; expect_fail R4_qualified_resolves
[ "$(count '^plan-cite-check: unresolved-adr ')" -eq 1 ] || fail "R4_qualified_resolves: expected one unresolved-adr with bookings 0001 gone ($(both))"
grep -qxF "plan-cite-check: unresolved-adr $GP:$_cl bookings/ADR-0001 not-in-namespace bookings" "$T/out" \
  || fail "R4_qualified_resolves: bookings/ADR-0001 did not resolve against specs/bookings/adr/ only ($(both))"
pass "R4_qualified_resolves"

fresh r4bare
rm "$S/adr/0001-accepted.md"
sed 's/| platform\/ADR-0001 |$/| ADR-0001 |/' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
grep -qF 'platform/ADR-0001' "$GP" && fail "R4_bare_resolves_other_namespace: precondition: the platform qualifier survived"
run_tool "$GP" --spec "$GS"; expect_ok R4_bare_resolves_other_namespace
pass "R4_bare_resolves_other_namespace"

fresh r4wrap
add_row "$GP" '| `w1.py` | modify | **platform** ADR-0001 |'
add_row "$GP" '| `w2.py` | modify | `ADR-0002` |'
run_tool "$GP" --spec "$GS"; expect_ok R4_wrapper_stripped
add_row "$GP" '| `w3.py` | modify | **bookings** ADR-0002 |'
run_tool "$GP" --spec "$GS"; expect_fail R4_wrapper_stripped
[ "$(count '^plan-cite-check: unresolved-adr ')" -eq 1 ] || fail "R4_wrapper_stripped: expected exactly one unresolved-adr ($(both))"
grep -qxF "plan-cite-check: unresolved-adr $GP:$_ln bookings/ADR-0002 not-in-namespace bookings" "$T/out" \
  || fail "R4_wrapper_stripped: '**bookings** ADR-0002' was read as a bare id — the emphasis wrapper was not stripped ($(both))"
pass "R4_wrapper_stripped"

fresh r4space
add_row "$GP" '| `s1.py` | modify | the ADR-0001 |'
run_tool "$GP" --spec "$GS"; expect_ok R4_space_qualifier_known_token
add_row "$GP" '| `s2.py` | modify | bookings ADR-0002 |'
run_tool "$GP" --spec "$GS"; expect_fail R4_space_qualifier_known_token
[ "$(count '^plan-cite-check: unresolved-adr ')" -eq 1 ] || fail "R4_space_qualifier_known_token: expected exactly one unresolved-adr ($(both))"
grep -qxF "plan-cite-check: unresolved-adr $GP:$_ln bookings/ADR-0002 not-in-namespace bookings" "$T/out" \
  || fail "R4_space_qualifier_known_token: 'bookings ADR-0002' (a known token, then a space) was not read as qualified ($(both))"
pass "R4_space_qualifier_known_token"

fresh r4case
add_row "$GP" '| `k.py` | modify | Bookings/ADR-0001 |'
run_tool "$GP" --spec "$GS"; expect_ok R4_qualifier_case_folded
pass "R4_qualifier_case_folded"

fresh r4none
rm -rf "$S/adr" "$S/bookings"
printf '%s\n' '# p' '' '## Files to change' '' '| File | Change | R-id |' '|---|---|---|' '| `a.py` | create | ADR-0001 |' \
  '' '## Deferred' '' 'Deferred: none — x' > "$S/epics/E01-x/F01-good/adr.plan.md"
run_tool "$S/epics/E01-x/F01-good/adr.plan.md" --spec "$GS"; expect_fail R4_no_namespaces_all_unresolved
grep -qxF "plan-cite-check: unresolved-adr $S/epics/E01-x/F01-good/adr.plan.md:7 ADR-0001 not-in-any-namespace" "$T/out" \
  || fail "R4_no_namespaces_all_unresolved: a bare id resolved with no adr/ namespace at all ($(both))"
sed 's/| ADR-0001 |$/| R1 |/' "$S/epics/E01-x/F01-good/adr.plan.md" > "$S/epics/E01-x/F01-good/rid.plan.md"
run_tool "$S/epics/E01-x/F01-good/rid.plan.md" --spec "$GS"; expect_ok R4_no_namespaces_all_unresolved
pass "R4_no_namespaces_all_unresolved"

fresh r4two
_dl="$(grep -n '| ADR-0002 ADR-0001 |' "$GP" | cut -d: -f1)"
run_tool "$GP" --spec "$GS"; expect_ok R4_two_cites_one_row
rm "$S/adr/0002-deferred-waf.md"
run_tool "$GP" --spec "$GS"; expect_fail R4_two_cites_one_row
[ "$(count "^plan-cite-check: unresolved-adr .*:$_dl ")" -eq 1 ] || fail "R4_two_cites_one_row: expected exactly one unresolved-adr on the two-id row ($(both))"
grep -qxF "plan-cite-check: unresolved-adr $GP:$_dl ADR-0002 not-in-any-namespace" "$T/out" \
  || fail "R4_two_cites_one_row: the first of two back-to-back ids was never looked up on its own ($(both))"
pass "R4_two_cites_one_row"

# ── R5: `## Deferred` is a Bolt-on table citing deferred-with-trigger ADRs, or one none line ─
# set_deferred <plan> <body-file> — replace the body of the plan's `## Deferred` section (the
# heading kept) with the body file; `-` as the body file deletes the whole section.
set_deferred() {
  awk -v f="$2" "$FENCE_AWK"'
    fence_delim($0) { if (!skip) print; next }
    !fence && /^## / { if (skip) skip = 0
                       if (index($0, "## Deferred") == 1) { skip = 1; if (f != "-") { print; while ((getline l < f) > 0) print l } ; next } }
    !skip' "$1" > "$1.new"
  mv "$1.new" "$1"
}
# one_deferred <row> <exact-line> — the run printed exactly one deferred-* line, and it is this.
one_deferred() {
  [ "$(count '^plan-cite-check: deferred-')" -eq 1 ] || fail "$1: expected exactly one deferred-* line ($(both))"
  grep -qxF "$2" "$T/out" || fail "$1: expected '$2' ($(both))"
}
fresh r5miss
set_deferred "$GP" -
grep -qF '## Deferred' "$GP" && fail "R5_section_missing: precondition: the section survived"
grep -qF '## DO NOT TOUCH' "$GP" || fail "R5_section_missing: precondition: the next section was eaten"
run_tool "$GP" --spec "$GS"; expect_fail R5_section_missing
one_deferred R5_section_missing "plan-cite-check: deferred-section-missing $GP"
pass "R5_section_missing"

fresh r5both
run_tool "$BP" --spec "$BS"; expect_fail R5_form_both
[ "$(count '^plan-cite-check: deferred-form ')" -eq 1 ] || fail "R5_form_both: expected one deferred-form line ($(both))"
grep -qxF "plan-cite-check: deferred-form $BP both" "$T/out" || fail "R5_form_both: a table AND a none line is not 'both' ($(both))"
pass "R5_form_both"

fresh r5neither
printf '%s\n' '' 'Stage: pilot' '' 'Nothing to say here.' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_fail R5_form_neither
one_deferred R5_form_neither "plan-cite-check: deferred-form $GP neither"
pass "R5_form_neither"

fresh r5two
printf '%s\n' '' 'Deferred: none — one' 'Deferred: none — two' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_fail R5_two_none_lines
one_deferred R5_two_none_lines "plan-cite-check: deferred-form $GP 2-none-lines"
pass "R5_two_none_lines"

fresh r5empty
printf '%s\n' '' '| Bolt-on | Deferred by | Trigger |' '|---|---|---|' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
_ln="$(grep -n '^| Bolt-on | Deferred by | Trigger |$' "$GP" | cut -d: -f1)"
run_tool "$GP" --spec "$GS"; expect_fail R5_table_empty
one_deferred R5_table_empty "plan-cite-check: deferred-table-empty $GP:$_ln"
pass "R5_table_empty"

fresh r5noadr
printf '%s\n' '' '| Bolt-on | Deferred by | Trigger |' '|---|---|---|' '| WAF | none | R1 asks for it later |' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
_ln="$(grep -n '^| WAF | none |' "$GP" | cut -d: -f1)"
run_tool "$GP" --spec "$GS"; expect_fail R5_row_no_adr
one_deferred R5_row_no_adr "plan-cite-check: deferred-row-no-adr $GP:$_ln"
[ "$(count '^plan-cite-check: uncited-row ')" -eq 0 ] || fail "R5_row_no_adr: the row cites R1, so it is not also uncited ($(both))"
# the ADR id in the THIRD cell does not stand in for the Deferred-by (second) cell
printf '%s\n' '' '| Bolt-on | Deferred by | Trigger |' '|---|---|---|' '| WAF | none | see ADR-0002 |' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_fail R5_row_no_adr
one_deferred R5_row_no_adr "plan-cite-check: deferred-row-no-adr $GP:$_ln"
pass "R5_row_no_adr"

fresh r5notdef
run_tool "$BP" --spec "$BS"; expect_fail R5_by_not_deferred
[ "$(count '^plan-cite-check: deferred-by-not-deferred ')" -eq 1 ] || fail "R5_by_not_deferred: expected one deferred-by-not-deferred line ($(both))"
grep -qxF "plan-cite-check: deferred-by-not-deferred $BP:22 ADR-0001 $S/adr/0001-accepted.md" "$T/out" \
  || fail "R5_by_not_deferred: a Deferred-by cell citing an accepted ADR passed ($(both))"
pass "R5_by_not_deferred"
[ "$(count '^plan-cite-check: deferred-adr-no-trigger ')" -eq 1 ] || fail "R5_adr_no_trigger: expected one deferred-adr-no-trigger line ($(both))"
grep -qxF "plan-cite-check: deferred-adr-no-trigger $BP:23 ADR-0003 $S/adr/0003-deferred-no-trigger.md" "$T/out" \
  || fail "R5_adr_no_trigger: a Deferred-by cell citing a deferred ADR with no Trigger: line passed ($(both))"
pass "R5_adr_no_trigger"

fresh r5ok
run_tool "$GP" --spec "$GS"; expect_ok R5_table_ok
grep -qE ', deferred: table, ' "$T/out" || fail "R5_table_ok: the ok line does not say 'deferred: table' ($(both))"
pass "R5_table_ok"

fresh r5prose
printf '%s\n' '' 'Stage: pilot' '' 'Deferred: none — stage is pilot and nothing applies' '' 'More prose beside it.' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_ok R5_none_with_prose_ok
grep -qE ', deferred: none, ' "$T/out" || fail "R5_none_with_prose_ok: the ok line does not say 'deferred: none' ($(both))"
pass "R5_none_with_prose_ok"

fresh r5hyph
printf '%s\n' '' 'Deferred: none - x' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_fail R5_hyphen_is_neither
one_deferred R5_hyphen_is_neither "plan-cite-check: deferred-form $GP neither"
pass "R5_hyphen_is_neither"

fresh r5four
printf '%s\n' '' '| Bolt-on | Deferred by | Trigger | Note |' '|---|---|---|---|' '| WAF | ADR-0002 | first regulated customer signs | n |' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_fail R5_four_cell_header_is_neither
one_deferred R5_four_cell_header_is_neither "plan-cite-check: deferred-form $GP neither"
pass "R5_four_cell_header_is_neither"

fresh r5trig
sed 's/^- \*\*Trigger:\*\* first regulated customer signs$/- **Trigger:** /' "$S/adr/0002-deferred-waf.md" > "$T/adr.new"; mv "$T/adr.new" "$S/adr/0002-deferred-waf.md"
grep -qx -- '- \*\*Trigger:\*\* ' "$S/adr/0002-deferred-waf.md" || fail "R5_trigger_empty_is_no_trigger: precondition: the Trigger: value was not emptied"
_ln="$(grep -n '^| WAF | ADR-0002 |' "$GP" | cut -d: -f1)"
run_tool "$GP" --spec "$GS"; expect_fail R5_trigger_empty_is_no_trigger
one_deferred R5_trigger_empty_is_no_trigger "plan-cite-check: deferred-adr-no-trigger $GP:$_ln ADR-0002 $S/adr/0002-deferred-waf.md"
pass "R5_trigger_empty_is_no_trigger"

# ── R6: usage / input errors ⇒ exit 2, `error:` + usage on stderr, nothing on stdout ─────
# chk_exit2 <row> [<stderr-fixed-string>] — each row's argv is the minimal one ONLY that
# branch rejects; the optional string names the branch so a second producer cannot pass it.
chk_exit2() {
  [ "$rc" -eq 2 ] || fail "$1: expected rc 2, got $rc ($(both))"
  head -n 1 "$T/err" | grep -q '^plan-cite-check: error: ' || fail "$1: stderr's first line is not 'plan-cite-check: error: ...' ($(both))"
  grep -q 'usage:' "$T/err" || fail "$1: no usage on stderr ($(both))"
  [ ! -s "$T/out" ] || fail "$1: stdout is not empty on an error ($(both))"
  if [ "$#" -ge 2 ]; then grep -qF -- "$2" "$T/err" || fail "$1: the error does not name '$2' ($(both))"; fi
  pass "$1"
}
fresh r6
run_tool; chk_exit2 R6_no_plan_arg 'exactly one <feature.plan.md>'
run_tool "$GP" "$GP" --spec "$GS"; chk_exit2 R6_two_plan_args 'exactly one <feature.plan.md>'
run_tool --bogus; chk_exit2 R6_unknown_flag 'unknown flag: --bogus'
run_tool "$GP" --spec "$GS" --bogus; chk_exit2 R6_unknown_flag 'unknown flag: --bogus'
run_tool "$GP" --spec; chk_exit2 R6_spec_flag_no_value '--spec needs a path'
run_tool "$GP" --specs-dir; chk_exit2 R6_specs_dir_flag_no_value '--specs-dir needs a path'
run_tool --grandfathered "$GP" --base; chk_exit2 R6_base_flag_no_value '--base needs a ref'
run_tool "$T/nope.plan.md" --spec "$GS"; chk_exit2 R6_plan_missing "$T/nope.plan.md"
run_tool "$S" --spec "$GS"; chk_exit2 R6_plan_is_dir 'not a regular file'
# a character device opens and reads empty: only the regular-file check can reject it
run_tool /dev/null --spec "$GS" --specs-dir "$S"; chk_exit2 R6_plan_not_regular 'not a regular file'
cp "$GP" "$T/bad8.plan.md"; printf '\377\n' >> "$T/bad8.plan.md"
run_tool "$T/bad8.plan.md" --spec "$GS" --specs-dir "$S"; chk_exit2 R6_plan_invalid_utf8 'cannot read'
run_tool "$GP" --spec "$T/nope.spec.md"; chk_exit2 R6_spec_missing "$T/nope.spec.md"
printf '%s\n' '# spec with no R-ids' '' 'Prose only.' > "$T/zero.spec.md"
run_tool "$GP" --spec "$T/zero.spec.md"; chk_exit2 R6_spec_zero_rids 'no R-ids found'
mkdir -p "$T/x"; cp "$GP" "$T/x/y.plan.md"
run_tool "$T/x/y.plan.md" --spec "$GS"; chk_exit2 R6_no_specs_ancestor 'is named specs'
run_tool "$GP" --spec "$GS" --specs-dir "$T/nope-specs"; chk_exit2 R6_specs_dir_not_dir 'not a directory'
fresh r6lock
mkdir "$S/locked"; chmod 000 "$S/locked"
run_tool "$GP" --spec "$GS"; chmod 755 "$S/locked"; chk_exit2 R6_specs_subdir_unreadable 'cannot read specs dir'
fresh r6adr
printf '\377\n' >> "$S/adr/0002-deferred-waf.md"
run_tool "$GP" --spec "$GS"; chk_exit2 R6_cited_adr_unreadable "$S/adr/0002-deferred-waf.md"

fresh r6out
run_tool --bogus; [ ! -s "$T/out" ] || fail "R6_stdout_empty_on_error: unknown flag wrote to stdout ($(both))"
run_tool "$T/nope.plan.md" --spec "$GS"; [ ! -s "$T/out" ] || fail "R6_stdout_empty_on_error: missing plan wrote to stdout ($(both))"
[ -s "$T/err" ] || fail "R6_stdout_empty_on_error: missing plan wrote nothing to stderr"
pass "R6_stdout_empty_on_error"

rm -rf "$T/dir with space"; mkdir -p "$T/dir with space"; cp -R "$FX/specs" "$T/dir with space/specs"
_q="$T/dir with space/specs/epics/E01-x/F01-good/it's.plan.md"
mv "$T/dir with space/specs/epics/E01-x/F01-good/E01-F01.plan.md" "$_q"
run_tool "$_q" --spec "$T/dir with space/specs/epics/E01-x/F01-good/E01-F01.spec.md"; expect_ok R6_argv_path_verbatim
grep -qF "plan-cite-check: ok $_q: " "$T/out" || fail "R6_argv_path_verbatim: the ok line does not print the argv path verbatim ($(both))"
pass "R6_argv_path_verbatim"
run_tool "--spec=$GS" "$GP" "--specs-dir=$S"; expect_ok R6_flag_equals_form
pass "R6_flag_equals_form"

run_tool --help
[ "$rc" -eq 0 ] || fail "R6_help_exit0: rc $rc ($(both))"
grep -q '^usage: ' "$T/out" || fail "R6_help_exit0: no usage on stdout ($(both))"
[ ! -s "$T/err" ] || fail "R6_help_exit0: stderr not empty ($(both))"
pass "R6_help_exit0"

# @@R7@@

echo "all plan-cite checks passed"
