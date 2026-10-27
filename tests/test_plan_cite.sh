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

# A UTF-8 BOM (U+FEFF, bytes EF BB BF) before line 1 is stripped — ONE of them — before any
# file is parsed (review round 1, A1): a BOM'd plan whose line 1 is `## Deferred` keeps that
# heading. Two BOMs are not one BOM: the second stays, so line 1 is no heading.
fresh r1bom
_bom="$(printf '\357\273\277')"
BOMP="$S/epics/E01-x/F01-good/bom.plan.md"
printf '%s\n' "${_bom}## Deferred" '' 'Deferred: none — x' > "$BOMP"
[ "$(head -c 3 "$BOMP" | od -An -tx1 | tr -d ' \n')" = efbbbf ] || fail "R1_bom_plan_line1_heading: precondition: the plan does not start with a BOM"
run_tool "$BOMP" --spec "$GS"; expect_ok R1_bom_plan_line1_heading
grep -qE '^plan-cite-check: ok .*: 0 row\(s\) cited, deferred: none, spec: 4 R-ids$' "$T/out" \
  || fail "R1_bom_plan_line1_heading: the ok line does not read the BOM'd line-1 '## Deferred' none form ($(both))"
printf '%s\n' "${_bom}${_bom}## Deferred" '' 'Deferred: none — x' > "$BOMP"
run_tool "$BOMP" --spec "$GS"; expect_fail R1_bom_plan_line1_heading
grep -qxF "plan-cite-check: deferred-section-missing $BOMP" "$T/out" \
  || fail "R1_bom_plan_line1_heading: with TWO BOMs the second was stripped too — only one leading BOM is stripped ($(both))"
pass "R1_bom_plan_line1_heading"

F04D="$ROOT/specs/epics/E36-emergent-slices/F04-plan-citation-gate"
run_tool "$F04D/E36-F04.plan.md" --spec "$F04D/E36-F04.spec.md"; expect_ok R1_dogfood_own_plan
pass "R1_dogfood_own_plan"
F03D="$ROOT/specs/epics/E36-emergent-slices/F03-stage-deferred-adrs"
run_tool "$F03D/E36-F03.plan.md" --spec "$F03D/E36-F03.spec.md"; expect_ok R1_dogfood_f03_plan
pass "R1_dogfood_f03_plan"

# The whole stdout of the negative plan, byte for byte: every format, every code, file order
# (the deferred-form line sorts at its `## Deferred` heading, between lines 16 and 22).
fresh r1golden
run_tool "$BP" --spec "$BS"
{ printf '%s\n' "plan-cite-check: uncited-row $BP:8 Data model" "plan-cite-check: unknown-rid $BP:14 R9" \
    "plan-cite-check: unresolved-adr $BP:15 ADR-0042 not-in-any-namespace" \
    "plan-cite-check: unresolved-adr $BP:16 bookings/ADR-0002 not-in-namespace bookings" \
    "plan-cite-check: deferred-form $BP both" \
    "plan-cite-check: deferred-by-not-deferred $BP:22 ADR-0001 $S/adr/0001-accepted.md" \
    "plan-cite-check: deferred-adr-no-trigger $BP:23 ADR-0003 $S/adr/0003-deferred-no-trigger.md" \
    "plan-cite-check: FAIL 7 violation(s)"; } > "$T/golden"
[ "$rc" -eq 1 ] && cmp -s "$T/golden" "$T/out" || fail "R1_negative_plan_golden: stdout differs: $(diff "$T/golden" "$T/out" | tr '\n' '|')"
pass "R1_negative_plan_golden"
# File order across sections: a `## Deferred` placed BEFORE `## Files to change` reports first.
OP="$S/epics/E01-x/F01-good/order.plan.md"
printf '%s\n' '# p' '' '## Deferred' '' 'nothing here' '' '## Files to change' '' '| File | Change |' '|---|---|' '| `a.py` | uncited |' > "$OP"
run_tool "$OP" --spec "$GS"
printf '%s\n' "plan-cite-check: deferred-form $OP neither" "plan-cite-check: uncited-row $OP:11 Files to change" \
  'plan-cite-check: FAIL 2 violation(s)' > "$T/golden"
cmp -s "$T/golden" "$T/out" || fail "R1_findings_in_file_order: findings are not in file order: $(diff "$T/golden" "$T/out" | tr '\n' '|')"
pass "R1_findings_in_file_order"

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

# GFM accepts a one-dash delimiter cell: `|-|` and `|:-|-:|` are separators too, so the
# header above them (no R-id) and the separator itself stay exempt (N14: `-{3,}`).
fresh r2dash
sed -e 's/^| Entity | Field | Type | Notes | R-id |$/| Entity | Field | Type | Notes | Ref |/' \
    -e '/^| Entity | Field /{n;s/^|---|---|---|---|---|$/|:-|-:|-|-|-|/;}' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
grep -qxF '| Entity | Field | Type | Notes | Ref |' "$GP" && grep -qxF '|:-|-:|-|-|-|' "$GP" \
  || fail "R2_one_dash_separator_exempt: precondition: the one-dash separator rewrite did not apply"
run_tool "$GP" --spec "$GS"; expect_ok R2_one_dash_separator_exempt
pass "R2_one_dash_separator_exempt"

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

fresh r2lvl1
printf '%s\n' '# Appendix (a level-1 heading closes the checked section)' '' '| Note | Text |' '|---|---|' '| uncited | after a level-1 heading |' '' > "$T/lvl1.md"
insert_before "$GP" '## Deferred' "$T/lvl1.md"
run_tool "$GP" --spec "$GS"; expect_ok R2_level1_heading_closes_section
pass "R2_level1_heading_closes_section"

fresh r2empty
printf '%s\n' '|  |  |  |' > "$T/row.md"
awk -v f="$T/row.md" '{ print } index($0, "| `e.py` |") == 1 { while ((getline l < f) > 0) print l }' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
_ln="$(grep -n '^|  |  |  |$' "$GP" | cut -d: -f1)"
run_tool "$GP" --spec "$GS"; expect_fail R2_empty_row_is_uncited
grep -qxF "plan-cite-check: uncited-row $GP:$_ln Files to change" "$T/out" \
  || fail "R2_empty_row_is_uncited: a row of empty cells was read as a separator ($(both))"
pass "R2_empty_row_is_uncited"

fresh r2after
printf '%s\n' 'Prose straight after the table, with no blank line between.' > "$T/row.md"
awk -v f="$T/row.md" '{ print } index($0, "| Booking | ref |") == 1 { while ((getline l < f) > 0) print l }' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
run_tool "$GP" --spec "$GS"; expect_ok R2_prose_after_table_not_a_row
pass "R2_prose_after_table_not_a_row"

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
# A BOM'd spec whose line 1 is an R-id line still yields that R-id (review round 1, A1).
fresh r3bom
printf '%s\n' "$(printf '\357\273\277')- **R1** — The system shall do one." '- **R2** — The system shall do two.' > "$T/r3bom.spec.md"
printf '%s\n' '# p' '' '## Files to change' '' '| File | Change | R-id |' '|---|---|---|' '| `a.py` | create | R1 |' \
  '' '## Deferred' '' 'Deferred: none — x' > "$S/epics/E01-x/F01-good/bomspec.plan.md"
run_tool "$S/epics/E01-x/F01-good/bomspec.plan.md" --spec "$T/r3bom.spec.md"; expect_ok R3_bom_spec_line1_rid
grep -qE ', spec: 2 R-ids$' "$T/out" || fail "R3_bom_spec_line1_rid: the BOM'd spec's line-1 R1 was not read ($(both))"
pass "R3_bom_spec_line1_rid"

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

fresh r3fence
printf '\n```\n- **R9** — a fenced decoy, not a declared R-id\n```\n' >> "$BS"
run_tool "$BP" --spec "$BS"; expect_fail R3_spec_fenced_rid_not_declared
grep -qxF "plan-cite-check: unknown-rid $BP:14 R9" "$T/out" || fail "R3_spec_fenced_rid_not_declared: an R-id inside the spec's fenced code was read as declared ($(both))"
pass "R3_spec_fenced_rid_not_declared"
# RID_RE is a deliberate copy of tasks-pair-check's: the two read spec R-ids identically.
python3 - "$TOOL" "$ROOT/tools/tasks-pair-check.py" <<'PY' || fail "R3_rid_re_parity: plan-cite-check's RID_RE differs from tasks-pair-check's"
import importlib.util, sys
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod
a, b = load("pcc", sys.argv[1]), load("tpc", sys.argv[2])
sys.exit(0 if a.RID_RE.pattern == b.RID_RE.pattern else 1)
PY
pass "R3_rid_re_parity"

# ── R4: ADR citations resolve under the namespace rule (init.sh 2c / agents/reviewer.md) ─
# add_row <file> <row> — append a data row right after the positive plan's `d.py` row (inside
# `## Files to change`); prints the new row's line number into $_ln.
add_row() {
  printf '%s\n' "$2" > "$T/row.md"
  awk -v f="$T/row.md" '{ print } index($0, "| `d.py` |") == 1 { while ((getline l < f) > 0) print l }' "$1" > "$1.new"; mv "$1.new" "$1"
  _ln="$(grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1)"
  [ -n "$_ln" ] || fail "add_row: precondition: row '$2' not inserted"
}
# Known limit (review round 1, A5; the tool docstring's "Known limits"): the spec reads an R
# token from any non-alphanumeric left boundary, and `:` is one, so a cross-feature
# `E36-F03:R1` counts as THIS spec's R1. Under --spec an id the spec does not declare still
# surfaces as unknown-rid; one it does declare is a silent pass. Pinned so a change is deliberate.
fresh r3xf
add_row "$GP" '| `xf.py` | modify | per E36-F03:R9 |'
run_tool "$GP" --spec "$GS"; expect_fail R3_cross_feature_id_reads_as_local
grep -qxF "plan-cite-check: unknown-rid $GP:$_ln R9" "$T/out" || fail "R3_cross_feature_id_reads_as_local: E36-F03:R9 is not read as this spec's R9 ($(both))"
[ "$(count '^plan-cite-check: ')" -eq 2 ] || fail "R3_cross_feature_id_reads_as_local: expected exactly one finding ($(both))"
fresh r3xf2
add_row "$GP" '| `xf.py` | modify | per E36-F03:R1 |'
run_tool "$GP" --spec "$GS"; expect_ok R3_cross_feature_id_reads_as_local
pass "R3_cross_feature_id_reads_as_local"

fresh r4
run_tool "$BP" --spec "$BS"; expect_fail R4_bare_unresolved
grep -qxF "plan-cite-check: unresolved-adr $BP:15 ADR-0042 not-in-any-namespace" "$T/out" \
  || fail "R4_bare_unresolved: no 'unresolved-adr <plan>:15 ADR-0042 not-in-any-namespace' ($(both))"
pass "R4_bare_unresolved"
grep -qxF "plan-cite-check: unresolved-adr $BP:16 bookings/ADR-0002 not-in-namespace bookings" "$T/out" \
  || fail "R4_qualified_cross_namespace: bookings/ADR-0002 resolved outside the bookings namespace ($(both))"
[ "$(count '^plan-cite-check: unresolved-adr ')" -eq 2 ] || fail "R4_qualified_cross_namespace: expected exactly two unresolved-adr lines on the negative plan ($(both))"
pass "R4_qualified_cross_namespace"

# `_` is legal in a namespace token (init.sh 2c: `my_product/`): the qualifier is the whole
# `my_product`, never its `product` tail (N18). 0007 lives in my_product only, so a bare read
# cannot resolve it either; the control proves the citation is looked up as qualified.
fresh r4us
mkdir -p "$S/my_product/adr"; printf '# ADR-0007\n\n- **Status:** accepted\n' > "$S/my_product/adr/0007-us.md"
add_row "$GP" '| `us.py` | modify | my_product/ADR-0007 |'
run_tool "$GP" --spec "$GS"; expect_ok R4_underscore_namespace_resolves
add_row "$GP" '| `us2.py` | modify | my_product/ADR-0001 |'
run_tool "$GP" --spec "$GS"; expect_fail R4_underscore_namespace_resolves
grep -qxF "plan-cite-check: unresolved-adr $GP:$_ln my_product/ADR-0001 not-in-namespace my_product" "$T/out" \
  || fail "R4_underscore_namespace_resolves: my_product/ADR-0001 was not looked up in the my_product namespace only ($(both))"
pass "R4_underscore_namespace_resolves"

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

# each wrapper character on its own: a wrapped known token still qualifies the citation
for _w in '"' "'" '`'; do
  fresh r4wrap1
  add_row "$GP" "| \`wq.py\` | modify | ${_w}bookings${_w} ADR-0002 |"
  run_tool "$GP" --spec "$GS"; expect_fail "R4_wrapper_stripped[$_w]"
  grep -qxF "plan-cite-check: unresolved-adr $GP:$_ln bookings/ADR-0002 not-in-namespace bookings" "$T/out" \
    || fail "R4_wrapper_stripped[$_w]: '${_w}bookings${_w} ADR-0002' was read as a bare id ($(both))"
  pass "R4_wrapper_stripped[$_w]"
done

# the index holds only regular *.md files directly in an adr/ dir, numbered by ALL leading digits
fresh r4bounds
printf 'x\n' > "$S/adr/0042-notes.txt"; ln -s "$S/nowhere" "$S/adr/0042-dangling.md"
printf '# not an ADR\n' > "$S/epics/E01-x/0042-not-in-adr.md"; printf '# five digits\n' > "$S/adr/00043-five.md"
add_row "$GP" '| `n.py` | modify | ADR-0042 |'; add_row "$GP" '| `o.py` | modify | ADR-0004 |'
_l1="$(grep -n '^| `n.py` |' "$GP" | cut -d: -f1)"; _l2="$(grep -n '^| `o.py` |' "$GP" | cut -d: -f1)"
run_tool "$GP" --spec "$GS"; expect_fail R4_namespace_index_bounds
[ "$(count '^plan-cite-check: unresolved-adr ')" -eq 2 ] || fail "R4_namespace_index_bounds: expected two unresolved-adr ($(both))"
grep -qxF "plan-cite-check: unresolved-adr $GP:$_l1 ADR-0042 not-in-any-namespace" "$T/out" \
  || fail "R4_namespace_index_bounds: a non-.md file, a non-regular (dangling) entry or a file outside adr/ was indexed as ADR-0042 ($(both))"
grep -qxF "plan-cite-check: unresolved-adr $GP:$_l2 ADR-0004 not-in-any-namespace" "$T/out" \
  || fail "R4_namespace_index_bounds: 00043-five.md was indexed as number 0004 ($(both))"
pass "R4_namespace_index_bounds"

fresh r4dup
add_row "$GP" '| `p.py` | modify | ADR-0042, again ADR-0042 |'
run_tool "$GP" --spec "$GS"; expect_fail R4_duplicate_cite_one_finding
[ "$(count "^plan-cite-check: unresolved-adr .*:$_ln ")" -eq 1 ] || fail "R4_duplicate_cite_one_finding: one id cited twice in a row gave more than one finding ($(both))"
pass "R4_duplicate_cite_one_finding"

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

fresh r5indent
printf '%s\n' '' '  Deferred: none — indented, so not the grammar line' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_fail R5_indented_none_is_neither
one_deferred R5_indented_none_is_neither "plan-cite-check: deferred-form $GP neither"
pass "R5_indented_none_is_neither"

fresh r5pipe
printf '%s\n' '' '| Bolt-on | Deferred by | Trigger |' '|---|---|---|' '| WAF \| edge proxy | ADR-0002 | first regulated customer signs |' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_ok R5_escaped_pipe_in_cell
pass "R5_escaped_pipe_in_cell"

# a bare id is satisfied when ANY namespace holding it has a deferred-with-trigger ADR
fresh r5anyc
printf '%s\n' '# ADR-0001 — bookings cache deferred (fixture)' '' '- **Status:** deferred' '- **Trigger:** the first 1000 bookings' > "$S/bookings/adr/0001-other.md"
printf '%s\n' '' '| Bolt-on | Deferred by | Trigger |' '|---|---|---|' '| caching | ADR-0001 | the first 1000 bookings |' '' > "$T/body.md"; set_deferred "$GP" "$T/body.md"
run_tool "$GP" --spec "$GS"; expect_ok R5_bare_any_namespace_deferred
pass "R5_bare_any_namespace_deferred"

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

run_tool --sweep "$S" --grandfathered "$GP"; chk_exit2 R6_two_modes_exit2 'separate modes'
run_tool --sweep "$S" "$S"; chk_exit2 R6_sweep_two_dirs_exit2 '--sweep expects exactly one <specs-dir>'
run_tool --grandfathered "$GP" "$GP"; chk_exit2 R6_grandfathered_two_plans_exit2 '--grandfathered expects exactly one <feature.plan.md>'
cp "$GP" "$T/perm.plan.md"; chmod 000 "$T/perm.plan.md"
run_tool "$T/perm.plan.md" --spec "$GS" --specs-dir "$S"; chmod 644 "$T/perm.plan.md"; chk_exit2 R6_plan_unreadable_perm 'Permission denied'
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
# An unexpected exception is "the check did not run" (exit 2), never exit 1 — which reads as a
# violation or a grandfather reject (review round 1, A3). A real input reaches one: a clean
# plan under a non-ASCII path, printed to an ASCII-only stdout (PYTHONIOENCODING=ascii), makes
# the ok line's print raise UnicodeEncodeError.
rm -rf "$T/r6int-$(printf '\303\261')"; mkdir -p "$T/r6int-$(printf '\303\261')"
cp -R "$FX/specs" "$T/r6int-$(printf '\303\261')/specs"
_ip="$T/r6int-$(printf '\303\261')/specs/epics/E01-x/F01-good"
set +e; PYTHONIOENCODING=ascii python3 "$TOOL" "$_ip/E01-F01.plan.md" --spec "$_ip/E01-F01.spec.md" >"$T/out" 2>"$T/err"; rc=$?; set -e
[ "$rc" -eq 2 ] || fail "R6_internal_error_exit2: an uncaught exception exited $rc, not 2 ($(both))"
head -n 1 "$T/err" | grep -q '^plan-cite-check: error: internal: UnicodeEncodeError: ' \
  || fail "R6_internal_error_exit2: stderr's first line is not 'plan-cite-check: error: internal: <type>: <msg>' ($(both))"
grep -q 'Traceback' "$T/err" && fail "R6_internal_error_exit2: a traceback reached stderr instead of the error line ($(both))"
[ ! -s "$T/out" ] || fail "R6_internal_error_exit2: stdout is not empty ($(both))"
pass "R6_internal_error_exit2"

# ── R7: --sweep (deferred-no-trigger, stage-unrecognized) and init.sh 2d, warn-only ──────
expect_sweep_fail() {
  [ "$rc" -eq 1 ] || fail "$1: expected rc 1, got $rc ($(both))"
  tail -n 1 "$T/out" | grep -qE '^plan-cite-check: FAIL [0-9]+ finding\(s\)$' || fail "$1: no 'FAIL <n> finding(s)' last line ($(both))"
  [ ! -s "$T/err" ] || fail "$1: stderr is not empty ($(both))"
}
fresh r7
run_tool --sweep "$S"; expect_sweep_fail R7_sweep_deferred_no_trigger
[ "$(count '^plan-cite-check: deferred-no-trigger ')" -eq 1 ] || fail "R7_sweep_deferred_no_trigger: expected exactly one deferred-no-trigger ($(both))"
grep -qxF "plan-cite-check: deferred-no-trigger $S/adr/0003-deferred-no-trigger.md" "$T/out" \
  || fail "R7_sweep_deferred_no_trigger: the deferred ADR with no Trigger: line was not reported ($(both))"
[ "$(wc -l < "$T/out" | tr -d ' ')" -eq 2 ] || fail "R7_sweep_deferred_no_trigger: expected one finding and the FAIL line ($(both))"
pass "R7_sweep_deferred_no_trigger"

fresh r7stage
rm "$S/adr/0003-deferred-no-trigger.md"
printf '%s\n' '---' 'stage: pilot   # why' '---' '# Product' > "$S/product.md"
run_tool --sweep "$S"; expect_sweep_fail R7_sweep_stage_unrecognized
[ "$(count '^plan-cite-check: ')" -eq 2 ] || fail "R7_sweep_stage_unrecognized: expected one finding and the FAIL line ($(both))"
grep -qxF "plan-cite-check: stage-unrecognized $S/product.md:2 stage: pilot   # why" "$T/out" \
  || fail "R7_sweep_stage_unrecognized: an inline comment on the stage line was not reported ($(both))"
printf '%s\n' '---' 'status: draft' 'stage: Pilot' '---' > "$S/product.md"
run_tool --sweep "$S"; expect_sweep_fail R7_sweep_stage_unrecognized
grep -qxF "plan-cite-check: stage-unrecognized $S/product.md:3 stage: Pilot" "$T/out" || fail "R7_sweep_stage_unrecognized: 'stage: Pilot' was not reported ($(both))"
pass "R7_sweep_stage_unrecognized"

fresh r7absent
rm "$S/adr/0003-deferred-no-trigger.md"
printf '%s\n' '---' 'status: draft' '---' '# Product' '' 'stage: bogus — outside the frontmatter, not a stage line' > "$S/product.md"
run_tool --sweep "$S"; expect_ok R7_sweep_stage_absent_ok
grep -qxF 'plan-cite-check: ok sweep 3 ADR(s), stage: absent' "$T/out" || fail "R7_sweep_stage_absent_ok: ok line ($(both))"
rm "$S/product.md"
run_tool --sweep "$S"; expect_ok R7_sweep_stage_absent_ok
printf '%s\n' '# Product with no frontmatter' 'stage: bogus' > "$S/product.md"
run_tool --sweep "$S"; expect_ok R7_sweep_stage_absent_ok
pass "R7_sweep_stage_absent_ok"
# Frontmatter is the `---` block that starts on LINE 1 (review round 1, A2; docs/SPEC-FORMAT.md
# grammar item 1): a `---` block after a preamble, or a second block after line 1's, is not
# frontmatter, so its `stage: pilot` is absent (production) and its `stage: Pilot` is no
# stage-unrecognized. The documented sed reader is run on the same shapes by
# tests/test_stage_nfrs.sh R1_stage_read_command_line1.
fresh r7line1
rm "$S/adr/0003-deferred-no-trigger.md"
printf '%s\n' '# Product' '' '---' 'stage: pilot' '---' > "$S/product.md"
run_tool --sweep "$S"; expect_ok R7_sweep_stage_block_not_on_line1
grep -qxF 'plan-cite-check: ok sweep 3 ADR(s), stage: absent' "$T/out" \
  || fail "R7_sweep_stage_block_not_on_line1: a --- block after a preamble was read as frontmatter ($(both))"
printf '%s\n' '---' 'status: draft' '---' '' '---' 'stage: pilot' '---' > "$S/product.md"
run_tool --sweep "$S"; expect_ok R7_sweep_stage_block_not_on_line1
grep -qxF 'plan-cite-check: ok sweep 3 ADR(s), stage: absent' "$T/out" \
  || fail "R7_sweep_stage_block_not_on_line1: a second --- block after line 1's was read as frontmatter ($(both))"
printf '%s\n' '# Product' '---' 'stage: Pilot' '---' > "$S/product.md"
run_tool --sweep "$S"; expect_ok R7_sweep_stage_block_not_on_line1
pass "R7_sweep_stage_block_not_on_line1"

fresh r7clean
rm "$S/adr/0003-deferred-no-trigger.md"
run_tool --sweep "$S"; expect_ok R7_sweep_clean
grep -qxF 'plan-cite-check: ok sweep 3 ADR(s), stage: pilot' "$T/out" || fail "R7_sweep_clean: ok line does not count 3 ADRs and stage pilot ($(both))"
pass "R7_sweep_clean"
# A BOM'd product.md still opens with its `---` frontmatter (review round 1, A1).
fresh r7bom
rm "$S/adr/0003-deferred-no-trigger.md"
printf '%s\n' "$(printf '\357\273\277')---" 'stage: discovery' '---' '# Product' > "$S/product.md"
run_tool --sweep "$S"; expect_ok R7_sweep_bom_product
grep -qxF 'plan-cite-check: ok sweep 3 ADR(s), stage: discovery' "$T/out" \
  || fail "R7_sweep_bom_product: a BOM before line 1's '---' hid the frontmatter's stage: discovery ($(both))"
pass "R7_sweep_bom_product"

fresh r7empty
rm "$S/adr/0003-deferred-no-trigger.md"; : > "$S/product.md"
run_tool --sweep "$S"; expect_ok R7_sweep_empty_product
grep -qxF 'plan-cite-check: ok sweep 3 ADR(s), stage: absent' "$T/out" || fail "R7_sweep_empty_product: ok line ($(both))"
pass "R7_sweep_empty_product"
fresh r7pdir
rm "$S/product.md"; mkdir "$S/product.md"
run_tool --sweep "$S"; chk_exit2 R7_sweep_product_not_regular 'not a regular file'

run_tool --sweep "$T/nope-specs"; chk_exit2 R7_sweep_dir_unreadable_exit2 'not a directory'
run_tool --sweep; chk_exit2 R7_sweep_dir_unreadable_exit2 '--sweep expects exactly one <specs-dir>'
fresh r7lock
mkdir "$S/locked"; chmod 000 "$S/locked"
run_tool --sweep "$S"; chmod 755 "$S/locked"; chk_exit2 R7_sweep_dir_unreadable_exit2 'cannot read specs dir'
fresh r7bad8
printf '\377\n' >> "$S/adr/0001-accepted.md"
run_tool --sweep "$S"; chk_exit2 R7_sweep_dir_unreadable_exit2 "$S/adr/0001-accepted.md"

# init.sh 2d — one fresh install (CODEX_HOME/HOME sandboxed); each case plants a one-feature
# board and the fixture tree under the installed .harness/specs, then runs the installed init.sh.
mkdir -p "$T/tgt" "$T/ch" "$T/home"
CODEX_HOME="$T/ch" HOME="$T/home" sh "$ROOT/harness-install.sh" --agents=claude "$T/tgt" \
  >"$T/install.out" 2>"$T/install.err" || fail "setup: fresh install exited non-zero: $(cat "$T/install.err")"
I="$T/tgt/.harness"
# init_case <feature-id> <status> <sdd> <feature-dir> — plant board + specs, run init.sh.
init_case() {
  rm -rf "$I/specs/adr" "$I/specs/bookings" "$I/specs/epics/E01-x"
  cp -R "$FX/specs/adr" "$FX/specs/bookings" "$I/specs/"; cp -R "$FX/specs/epics/E01-x" "$I/specs/epics/"
  printf '{"$schema": "../store/tasks.schema.json", "project": "fx", "epics": [{"id": "E01", "title": "Fixture", "status": "in-progress", "features": [{"id": "%s", "title": "Fixture feature", "status": "%s", "sdd": %s, "autonomous": false, "depends_on": [], "spec_path": "specs/epics/E01-x/%s/"}]}]}\n' \
    "$1" "$2" "$3" "$4" > "$I/state/tasks.json"
}
init_run() { set +e; (cd "$T/tgt" && bash "$I/init.sh") >"$T/out" 2>"$T/err"; rc=$?; set -e; }
init_ok() {
  [ "$rc" -eq 0 ] || fail "$1: init.sh exited $rc — the 2d block must never fail the gate ($(both))"
  grep -qF '✅ environment ready' "$T/out" || fail "$1: init.sh did not reach its final ok line ($(both))"
}
init_case E01-F02 spec-ready true F02-bad; init_run; init_ok R7_init_warns_on_bad_plan
grep -qF "⚠️  plan-cite: E01-F02 uncited-row specs/epics/E01-x/F02-bad/E01-F02.plan.md:8 Data model (+6 more; warn-only — Reviewer check 8 rejects)" "$T/out" \
  || fail "R7_init_warns_on_bad_plan: no warn line naming E01-F02 and its first finding ($(both))"
grep -qF '✅ plan citations' "$T/out" && fail "R7_init_warns_on_bad_plan: the clean line printed beside a warning ($(both))"
grep -qF 'plan-cite: FAIL' "$T/out" && fail "R7_init_warns_on_bad_plan: the tool's FAIL summary leaked as a warning ($(both))"
pass "R7_init_warns_on_bad_plan"
grep -qxF "⚠️  plan-cite: deferred-no-trigger specs/adr/0003-deferred-no-trigger.md (warn-only)" "$T/out" \
  || fail "R7_init_sweep_warns_deferred_no_trigger: no sweep warn line for the trigger-less deferred ADR ($(both))"
pass "R7_init_sweep_warns_deferred_no_trigger"

init_case E01-F01 spec-ready true F01-good; rm "$I/specs/adr/0003-deferred-no-trigger.md"; init_run; init_ok R7_init_ok_on_good_plan
grep -qxF '✅ plan citations and deferred ADRs clean (1 plan(s) checked)' "$T/out" \
  || fail "R7_init_ok_on_good_plan: no clean line counting 1 plan ($(both))"
grep -qF 'plan-cite:' "$T/out" && fail "R7_init_ok_on_good_plan: a warn line on a clean plan ($(both))"
pass "R7_init_ok_on_good_plan"

# The spec must stay on disk (init.sh section 2 rejects an sdd feature with no spec before
# 2d runs), so the exit-2 cause is a spec that declares no R-id. The trigger-less ADR is
# removed so the sweep is clean: the no-clean-line negative below then has ONE producer, the
# exit-2 branch's own count (N10).
init_case E01-F02 spec-ready true F02-bad; rm "$I/specs/adr/0003-deferred-no-trigger.md"
grep -v '^- \*\*R' "$I/specs/epics/E01-x/F02-bad/E01-F02.spec.md" > "$T/zero.md"; mv "$T/zero.md" "$I/specs/epics/E01-x/F02-bad/E01-F02.spec.md"
init_run; init_ok R7_init_exit2_reported_as_did_not_run
# ONE line, start to end (R7 "a ⚠️ line"): a multi-line extraction (R2M2) splits it, so no single
# line carries both the prefix and the closing (warn-only) tag.
grep -qE '^⚠️  plan-cite: E01-F02 check did not run: error: no R-ids found in specs/epics/E01-x/F02-bad/E01-F02\.spec\.md.* \(warn-only\)$' "$T/out" \
  || fail "R7_init_exit2_reported_as_did_not_run: an exit-2 lint is not reported as ONE 'check did not run' line ending (warn-only) ($(both))"
grep -qF '✅ plan citations' "$T/out" && fail "R7_init_exit2_reported_as_did_not_run: the clean line printed though a plan's lint did not run ($(both))"
pass "R7_init_exit2_reported_as_did_not_run"

for _st in in-review in-progress; do
  init_case E01-F02 "$_st" true F02-bad; init_run; init_ok "R7_init_in_review_swept[$_st]"
  grep -qF '⚠️  plan-cite: E01-F02 uncited-row ' "$T/out" || fail "R7_init_in_review_swept: a '$_st' feature's plan was not linted ($(both))"
done
for _st in done pending; do
  init_case E01-F02 "$_st" true F02-bad; init_run; init_ok "R7_init_in_review_swept[$_st]"
  grep -qF 'plan-cite: E01-F02' "$T/out" && fail "R7_init_in_review_swept: a '$_st' feature's plan was linted ($(both))"
done
init_case E01-F02 spec-ready false F02-bad; init_run; init_ok R7_init_sdd_false_exempt
grep -qF 'plan-cite: E01-F02' "$T/out" && fail "R7_init_sdd_false_exempt: an sdd: false feature was linted ($(both))"
pass "R7_init_in_review_swept"
pass "R7_init_sdd_false_exempt"

init_case E01-F02 spec-ready true F02-bad; rm "$I/tools/plan-cite-check.py"; init_run; init_ok R7_init_silent_without_tool
grep -qF 'plan-cite' "$T/out" && fail "R7_init_silent_without_tool: 2d printed without the tool ($(both))"
pass "R7_init_silent_without_tool"
cp "$TOOL" "$I/tools/plan-cite-check.py"

init_case E01-F01 spec-ready true F01-good; rm "$I/specs/adr/0003-deferred-no-trigger.md"
printf '\377\n' >> "$I/specs/bookings/adr/0001-other.md"; init_run; init_ok R7_init_sweep_exit2_did_not_run
grep -qE '^⚠️  plan-cite: sweep did not run: error: cannot read specs/bookings/adr/0001-other\.md.* \(warn-only\)$' "$T/out" \
  || fail "R7_init_sweep_exit2_did_not_run: a sweep that exited 2 is not reported as ONE 'did not run' line ending (warn-only) ($(both))"
grep -qF '✅ plan citations' "$T/out" && fail "R7_init_sweep_exit2_did_not_run: clean line printed though the sweep did not run ($(both))"
pass "R7_init_sweep_exit2_did_not_run"

init_case E01-F02 spec-ready true F02-bad; rm "$I/specs/epics/E01-x/F02-bad/E01-F02.plan.md" "$I/specs/adr/0003-deferred-no-trigger.md"
init_run; init_ok R7_init_no_plan_did_not_run
grep -qxF '⚠️  plan-cite: E01-F02 check did not run: no *.plan.md in specs/epics/E01-x/F02-bad/ (warn-only)' "$T/out" \
  || fail "R7_init_no_plan_did_not_run: a feature with no plan is not reported ($(both))"
grep -qF '✅ plan citations' "$T/out" && fail "R7_init_no_plan_did_not_run: the clean line printed though a feature's plan was never linted ($(both))"
pass "R7_init_no_plan_did_not_run"

# A warn-only lint never fails the gate, however much it prints: 2000 generated uncited rows
# (~180 KB of findings, past any pipe buffer) must not let a `printf | head` pipeline take
# SIGPIPE under `set -euo pipefail` and kill init.sh with 141 (review round 1, F1). The
# fixture is generated here, never committed.
init_case E01-F01 spec-ready true F01-good
awk 'BEGIN { for (i = 1; i <= 2000; i++) printf "| `big%d.py` | an uncited generated row |\n", i }' > "$T/big.md"
insert_before "$I/specs/epics/E01-x/F01-good/E01-F01.plan.md" '## Deferred' "$T/big.md"
[ "$(grep -c '^| `big[0-9]*\.py` |' "$I/specs/epics/E01-x/F01-good/E01-F01.plan.md")" -eq 2000 ] \
  || fail "R7_init_large_output_never_fails: precondition: the 2000 generated rows were not inserted"
init_run; init_ok R7_init_large_output_never_fails
grep -qF '⚠️  plan-cite: E01-F01 uncited-row specs/epics/E01-x/F01-good/E01-F01.plan.md:' "$T/out" \
  || fail "R7_init_large_output_never_fails: no warn line naming the first uncited row ($(both))"
grep -qF ' Files to change (+1999 more; warn-only — Reviewer check 8 rejects)' "$T/out" \
  || fail "R7_init_large_output_never_fails: the warn line does not count the other 1999 findings ($(both))"
pass "R7_init_large_output_never_fails"

# The lint resolves ADRs against the harness specs/ tree (--specs-dir specs), not against the
# nearest directory named specs above the plan.
init_case E01-F01 spec-ready true specs/F01-good; rm "$I/specs/adr/0003-deferred-no-trigger.md"
mkdir -p "$I/specs/epics/E01-x/specs"; cp -R "$FX/specs/epics/E01-x/F01-good" "$I/specs/epics/E01-x/specs/"
init_run; init_ok R7_init_specs_dir_is_harness_specs
grep -qxF '✅ plan citations and deferred ADRs clean (1 plan(s) checked)' "$T/out" \
  || fail "R7_init_specs_dir_is_harness_specs: ADRs were not resolved against the harness specs/ tree ($(both))"
pass "R7_init_specs_dir_is_harness_specs"

# ── R8: --grandfathered — flag a plan written before THIS tool merged, else reject class ─
# The tool's date is its MERGE: the committer time of the first first-parent commit on the
# default branch touching tools/plan-cite-check.py or .harness/tools/plan-cite-check.py. The
# plan's date is the AUTHOR time of the earliest commit on HEAD that added it. Hermetic git:
# bounded discovery, no host config, fixed dates (lessons 2026-10-17/19).
GIT_CEILING_DIRECTORIES="$T"; export GIT_CEILING_DIRECTORIES
GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
gq() { git -c user.name=fx -c user.email=fx@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
gci() { # gci <author-epoch> <committer-epoch> <msg>  (stage first)
  GIT_AUTHOR_DATE="@$1 +0000" GIT_COMMITTER_DATE="@$2 +0000" gq commit -q -m "$3" || fail "fixture commit '$3' failed"
}
gf_run() { # gf_run <cwd> <plan-path> [args...]
  _r="$1"; _f="$2"; shift 2
  set +e; (cd "$_r" && python3 "$TOOL" --grandfathered "$_f" "$@") >"$T/out" 2>"$T/err"; rc=$?; set -e
}
gf_expect() { # gf_expect <row> <rc> <stdout-regex>
  [ "$rc" -eq "$2" ] || fail "$1: expected rc $2, got $rc ($(both))"
  grep -qE "$3" "$T/out" || fail "$1: stdout does not match '$3' ($(both))"
  pass "$1"
}
# G1: main: base @1000; old.plan.md authored @1100 but COMMITTED @1900 (a rebase moved its
# committer time past the tool, never its author time); the tool @1500; new.plan.md @1600;
# re.plan.md added @1200, deleted @1210, re-added @1700 (the earliest add wins); a literal
# `it*s.plan.md` @1600 beside an `itXs.plan.md` @1100 that a glob pathspec would also match.
G="$T/g1"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p s; echo x > s/old.plan.md; gq add s; gci 1100 1900 old
echo x > s/itXs.plan.md; gq add s; gci 1100 1100 itx
echo x > s/re.plan.md; gq add s; gci 1200 1200 re-add-1
gq rm -q s/re.plan.md; gci 1210 1210 re-del
gq tag pre-tool
mkdir -p tools; echo v1 > tools/plan-cite-check.py; gq add tools; gci 1500 1500 tool
echo x > s/same.plan.md; gq add s; gci 1500 1550 same-second
echo x > s/new.plan.md; gq add s; gci 1600 1600 new
echo x > 's/it*s.plan.md'; gq add s; gci 1600 1600 star
echo x > s/re.plan.md; gq add s; gci 1700 1700 re-add-2
echo v2 > tools/plan-cite-check.py; gq add tools; gci 1800 1800 tool-v2
echo x > s/dirty.plan.md
cd "$ROOT"
gf_run "$G" s/old.plan.md; gf_expect R8_flag_plan_older_than_merge 0 '^plan-cite-check: grandfather flag: s/old\.plan\.md authored 1100, before tool merged into main at 1500$'
gf_run "$G" s/new.plan.md; gf_expect R8_reject_plan_after_merge 1 '^plan-cite-check: grandfather reject: s/new\.plan\.md authored 1600, not before tool merged into main at 1500$'
gf_run "$G" s/dirty.plan.md; gf_expect R8_reject_uncommitted_plan 1 '^plan-cite-check: grandfather reject: s/dirty\.plan\.md has no commit on HEAD'
gf_run "$G" s/re.plan.md; gf_expect R8_earliest_add_wins 0 '^plan-cite-check: grandfather flag: s/re\.plan\.md authored 1200'
gf_run "$G" s/same.plan.md; gf_expect R8_same_second_rejects 1 '^plan-cite-check: grandfather reject: s/same\.plan\.md authored 1500, not before tool merged into main at 1500$'
gf_run "$G" s; [ "$rc" -eq 2 ] || fail "R8_dir_path_exit2: a directory path gave rc $rc ($(both))"
grep -qF 'not a regular file' "$T/err" || fail "R8_dir_path_exit2: wrong error ($(both))"; pass R8_dir_path_exit2
gf_run "$G" 's/it*s.plan.md'; gf_expect R8_literal_pathspec 1 '^plan-cite-check: grandfather reject: s/it\*s\.plan\.md authored 1600'
# An absolute path from another cwd must reach the same verdict — a FLAG case on purpose: a
# path the tool cannot map into the repo finds no commit, which reads as reject (lesson 2026-10-25).
gf_run "$T" "$G/s/old.plan.md"; gf_expect R8_absolute_path_flags 0 '^plan-cite-check: grandfather flag: s/old\.plan\.md authored 1100'
# origin/HEAD is asked first: point it at a remote-tracking ref that never saw the tool.
gq -C "$G" update-ref refs/remotes/origin/trunk "$(git -C "$G" rev-parse pre-tool)"
gq -C "$G" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
gf_run "$G" s/new.plan.md; gf_expect R8_flag_tool_not_on_base 0 '^plan-cite-check: grandfather flag: tool not on default branch origin/trunk yet$'
gf_run "$G" s/new.plan.md --base main; gf_expect R8_base_flag_equals_form 1 '^plan-cite-check: grandfather reject: .* main at 1500$'
gf_run "$G" s/new.plan.md --base=main; gf_expect R8_base_flag_equals_form 1 '^plan-cite-check: grandfather reject: .* main at 1500$'
gf_run "$G" s/new.plan.md --base nope; [ "$rc" -eq 2 ] || fail "R8_exit2_bad_base: rc $rc ($(both))"
grep -qF 'plan-cite-check: error: --base does not resolve: nope' "$T/err" || fail "R8_exit2_bad_base: wrong error ($(both))"
[ ! -s "$T/out" ] || fail "R8_exit2_bad_base: stdout not empty"; pass R8_exit2_bad_base
gf_run "$G" s/new.plan.md --spec x; [ "$rc" -eq 2 ] || fail "R8_lint_flag_in_grandfather_mode_exit2: rc $rc ($(both))"; pass R8_lint_flag_in_grandfather_mode_exit2
# A failing git call is exit 2, never a verdict: a stub git that fails one `log` call, keyed
# on that call's distinct --format (the tool-merge log asks %ct, the plan-add log %at) so a
# mutant that drops --first-parent or --diff-filter still meets the stub.
mkdir -p "$T/stub"
for _which in 'format=%ct' 'format=%at'; do
  printf '#!/bin/sh\ncase " $* " in *" --%s "*) echo "stub: git log failed" >&2; exit 128 ;; esac\nexec %s "$@"\n' "$_which" "$(command -v git)" > "$T/stub/git"
  chmod +x "$T/stub/git"
  set +e; (cd "$G" && PATH="$T/stub:$PATH" python3 "$TOOL" --grandfathered s/new.plan.md --base main) >"$T/out" 2>"$T/err"; rc=$?; set -e
  [ "$rc" -eq 2 ] || fail "R8_git_failure_exit2[$_which]: a failed git log gave rc $rc instead of 2 ($(both))"
  grep -qF 'stub: git log failed' "$T/err" || fail "R8_git_failure_exit2[$_which]: git's stderr is not surfaced ($(both))"
  pass "R8_git_failure_exit2[$_which]"
done
# G2: the tool reaches main only through a --no-ff merge. Its branch commit (@1100) is OLDER
# than the plan (@1200); the merge (@1300) is newer: the first-parent merge is the tool's date.
G="$T/g2"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
gq checkout -q -b tool; mkdir -p tools; echo v1 > tools/plan-cite-check.py; gq add tools; gci 1100 1100 tool
gq checkout -q main; mkdir -p s; echo x > s/p.plan.md; gq add s; gci 1200 1200 plan
GIT_AUTHOR_DATE="@1150 +0000" GIT_COMMITTER_DATE="@1300 +0000" gq merge -q --no-ff -m merge-tool tool || fail "fixture merge failed"
cd "$ROOT"
gf_run "$G" s/p.plan.md; gf_expect R8_merge_time_not_branch_time 0 '^plan-cite-check: grandfather flag: s/p\.plan\.md authored 1200, before tool merged into main at 1300$'
# G7: an in-flight sibling (review round 1, F3). The plan exists ONLY on the feature branch,
# authored @1100 before the tool merged into main @1500; the branch was rebased onto main, so
# its commit carries committer @1600 but keeps author @1100. The plan's date is read on HEAD:
# reading it on the base branch finds no commit and rejects the sibling the rule protects (N21).
G="$T/g7"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p tools; echo v1 > tools/plan-cite-check.py; gq add tools; gci 1500 1500 tool
gq checkout -q -b feat; mkdir -p s; echo x > s/sib.plan.md; gq add s; gci 1100 1600 sibling-rebased
cd "$ROOT"
git -C "$G" log --format=%H main -- s/sib.plan.md | grep -q . && fail "R8_flag_sibling_plan_only_on_head: precondition: the plan reached main"
gf_run "$G" s/sib.plan.md --base main; gf_expect R8_flag_sibling_plan_only_on_head 0 '^plan-cite-check: grandfather flag: s/sib\.plan\.md authored 1100, before tool merged into main at 1500$'
# G8: author times are not ordered by topology (review round 1, F4). The tool merges @1500,
# the plan is ADDED @1600, and a later edit carries an older author date @900 (cherry-pick,
# --date). The plan's date is its first ADD, so the edit's date never grandfathers it (M8).
G="$T/g8"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p tools; echo v1 > tools/plan-cite-check.py; gq add tools; gci 1500 1500 tool
mkdir -p s; echo x > s/late.plan.md; gq add s; gci 1600 1600 plan-added
echo y >> s/late.plan.md; gq add s; gci 900 1700 edit-with-older-author-date
cd "$ROOT"
[ "$(git -C "$G" log --format=%at -- s/late.plan.md | sort -n | head -n 1)" = 900 ] \
  || fail "R8_reject_edit_with_older_author_date: precondition: the edit does not carry author time 900"
gf_run "$G" s/late.plan.md --base main; gf_expect R8_reject_edit_with_older_author_date 1 '^plan-cite-check: grandfather reject: s/late\.plan\.md authored 1600, not before tool merged into main at 1500$'
# G3: installed-target layout — the tool lives at .harness/tools/plan-cite-check.py.
G="$T/g3"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p .harness/tools s; echo v1 > .harness/tools/plan-cite-check.py; gq add .harness; gci 1100 1100 upgrade
echo x > s/n.plan.md; gq add s; gci 1200 1200 new
cd "$ROOT"
gf_run "$G" s/n.plan.md; gf_expect R8_consumer_layout_rejects 1 '^plan-cite-check: grandfather reject: s/n\.plan\.md authored 1200, not before tool merged into main at 1100$'
# Every fallback default-branch name resolves (no origin/HEAD): the tool on it, a later plan.
for _b in origin/main main origin/master master origin/trunk trunk; do
  G="$T/g5-$(printf '%s' "$_b" | tr / -)"; mkdir -p "$G"; cd "$G"; gq init -q -b work .
  mkdir -p tools s; echo v1 > tools/plan-cite-check.py; gq add tools; gci 1100 1100 tool
  echo x > s/n.plan.md; gq add s; gci 1200 1200 n
  case "$_b" in origin/*) gq update-ref "refs/remotes/$_b" HEAD ;; *) gq branch "$_b" ;; esac
  cd "$ROOT"
  gf_run "$G" s/n.plan.md; gf_expect "R8_fallback_branch[$_b]" 1 "^plan-cite-check: grandfather reject: .* $_b at 1100\$"
done
# The fallback ORDER is origin/main before main: with both present and only main carrying the
# tool, the default branch is origin/main and the plan is flagged.
G="$T/g6"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
gq update-ref refs/remotes/origin/main HEAD
mkdir -p tools s; echo v1 > tools/plan-cite-check.py; gq add tools; gci 1100 1100 tool
echo x > s/n.plan.md; gq add s; gci 1200 1200 n
cd "$ROOT"
gf_run "$G" s/n.plan.md; gf_expect R8_fallback_order 0 '^plan-cite-check: grandfather flag: tool not on default branch origin/main yet$'
# G4: the only branch is `trunkless`, no origin: no default branch resolves.
G="$T/g4"; mkdir -p "$G"; cd "$G"; gq init -q -b trunkless .; echo x > a.plan.md; gq add a.plan.md; gci 1000 1000 a; cd "$ROOT"
gf_run "$G" a.plan.md; [ "$rc" -eq 2 ] || fail "R8_exit2_no_default_branch: rc $rc ($(both))"
grep -qF -- '--base' "$T/err" || fail "R8_exit2_no_default_branch: the error does not name --base ($(both))"; pass R8_exit2_no_default_branch
mkdir -p "$T/nogit"; echo x > "$T/nogit/a.plan.md"
gf_run "$T/nogit" a.plan.md; [ "$rc" -eq 2 ] || fail "R8_exit2_outside_repo: rc $rc ($(both))"
grep -qF 'is not inside a git work tree' "$T/err" || fail "R8_exit2_outside_repo: wrong reason ($(both))"; pass R8_exit2_outside_repo

# ── prose helpers: fence-aware heading slicer (tests/lib/fence.awk), folded anchors ──────
# slice <file> <heading-prefix> — one `## ` section (to the next `## ` heading outside fences).
slice() {
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^## / { keep = (index($0, h) == 1); next }
    keep' "$1"
}
# item <slice-file> <n> — numbered item n of a slice, up to the next `<digits>. ` item line.
item() { awk -v n="$2" 'index($0, n ". ") == 1 { k = 1; print; next } k && /^[0-9]+\. / { k = 0 } k' "$1"; }
folded() { tr '\n' ' ' < "$1" | tr -s ' '; }
# has <row> <text-file> <exact-substring> — the folded text holds the exact sentence part.
has() { folded "$2" | grep -qF -- "$3" || fail "$1: missing: $3"; }

# ── R9: Reviewer check 8 (reject) and the doc-critic's advisory section ─────────────────
slice "$I/agents/reviewer.md" '## What you check' > "$T/rv.txt"
[ -s "$T/rv.txt" ] || fail "R9_reviewer_check8: '## What you check' not found in the installed reviewer.md"
item "$T/rv.txt" 8 > "$T/rv8.txt"
[ -s "$T/rv8.txt" ] || fail "R9_reviewer_check8: no numbered item 8 inside '## What you check'"
_l7="$(grep -n '^7\. ' "$T/rv.txt" | cut -d: -f1)"; _l8="$(grep -n '^8\. ' "$T/rv.txt" | cut -d: -f1)"
[ -n "$_l7" ] && [ "$_l8" -gt "$_l7" ] || fail "R9_reviewer_check8: item 8 does not follow item 7"
has R9_reviewer_check8 "$T/rv8.txt" '8. **Plan-row citations (E36-F04, ADR-0009 decision 4).** For an `sdd: true` feature, run `python3 "$HARNESS_DIR/tools/plan-cite-check.py" "<dir>/<feature>.plan.md" --spec "<dir>/<feature>.spec.md"`'
has R9_reviewer_check8 "$T/rv8.txt" 'the tool is `tools/plan-cite-check.py` in the harness source repo and `.harness/tools/plan-cite-check.py` in an installed target'
has R9_reviewer_check8 "$T/rv8.txt" 'Exit 1 (an `uncited-row`, `unknown-rid`, `unresolved-adr` or `deferred-*` violation) → reject, quoting the tool'"'"'s output in `progress/<run>/review.md`.'
has R9_reviewer_check8 "$T/rv8.txt" 'Exit 2 means the check did not run (a usage or input error): fix the invocation and run it again — never approve on an unrun check.'
has R9_reviewer_check8 "$T/rv8.txt" 'A plan-row `unresolved-adr` is a **reject**, because the citation is the row'"'"'s justification (ADR-0009 decision 4); the `## ADR-citation check` below keeps its soft-flag posture for `.spec.md` citations, and both resolve ids with the same namespace rule.'
has R9_reviewer_check8 "$T/rv8.txt" 'on an exit-1 lint, run `python3 "$HARNESS_DIR/tools/plan-cite-check.py" --grandfathered "<dir>/<feature>.plan.md"` after `git fetch origin`: exit 0 → flag ("add `## Deferred` and cite each row, or justify"), exit 1 → reject, exit 2 → flag with "grandfather check did not run: <stderr>".'
has R9_reviewer_check8 "$T/rv8.txt" 'a plan written before this tool merged is flagged, not rejected.'
has R9_reviewer_check8 "$T/rv8.txt" 'This check judges citation presence and resolution only — whether a cited row is justified stays the doc-critic'"'"'s YAGNI finding.'
has R9_reviewer_check8 "$T/rv8.txt" '`sdd: false` items are exempt (they have no `.plan.md`).'
has R9_reviewer_check8 "$T/rv8.txt" 'Checks 2 and 7 are unchanged.'
pass "R9_reviewer_check8"

item "$T/rv.txt" 2 > "$T/rv2.txt"; item "$T/rv.txt" 7 > "$T/rv7.txt"
has R9_reviewer_checks_2_and_7_intact "$T/rv2.txt" 'A requirement without a passing test = reject.'
has R9_reviewer_checks_2_and_7_intact "$T/rv7.txt" 'run `python3 "$HARNESS_DIR/tools/tasks-pair-check.py" --grandfathered "<dir>/<feature>.tasks.md"`: exit 0 → flag, exit 1 → reject'
grep -qF 'plan-cite-check' "$T/rv7.txt" && fail "R9_reviewer_checks_2_and_7_intact: item 7 now names plan-cite-check — item 8 was merged into it"
pass "R9_reviewer_checks_2_and_7_intact"

_dc="$I/agents/doc-critic.md"
_h='## Plan-row citations and stage-aware NFRs (E36-F04)'
grep -qxF "$_h" "$_dc" || fail "R9_doc_critic_section: no '$_h' heading in the installed doc-critic.md"
_hs="$(grep -nxF "$_h" "$_dc" | cut -d: -f1)"
_rs="$(grep -n '^## Review scope and calibration' "$_dc" | cut -d: -f1)"
_ab="$(grep -n '^## Advisory-only behavior' "$_dc" | cut -d: -f1)"
[ -n "$_rs" ] && [ -n "$_ab" ] && [ "$_hs" -gt "$_rs" ] && [ "$_ab" -gt "$_hs" ] \
  || fail "R9_doc_critic_section: the section is not between '## Review scope and calibration' and '## Advisory-only behavior' (scope=$_rs section=$_hs advisory=$_ab)"
slice "$_dc" "$_h" > "$T/dc.txt"
has R9_doc_critic_section "$T/dc.txt" 'At `target-type=feature-spec`, also run the plan-row citation lint on the feature'"'"'s plan: `python3 "$HARNESS_DIR/tools/plan-cite-check.py" <feature>.plan.md --spec <feature>.spec.md`'
has R9_doc_critic_section "$T/dc.txt" 'Report each line it prints as an advisory finding; an exit 2 is recorded as the finding "lint did not run: <stderr>".'
has R9_doc_critic_section "$T/dc.txt" '**Sticky NFR omitted** — the plan omits a sticky NFR the feature'"'"'s scope touches: tenant isolation, the auth boundary, secrets out of the repo, validation at the system edge'
has R9_doc_critic_section "$T/dc.txt" '**Uncited bolt-on** — the plan adds a bolt-on row (encryption at rest, WAF, rate limits, backups, caching) that cites no `R-id` and is not deferred in `## Deferred`.'
has R9_doc_critic_section "$T/dc.txt" 'These findings are advisory like every other finding: you never block the Architect.'
grep -qF 'never block' "$_dc" || fail "R9_doc_critic_section: the role's never-block rule is gone"
pass "R9_doc_critic_section"
# The doc-critic's Claude and pi shims grant no shell tool, so it may be unable to run the
# lint at all (review round 1, F2). Subject-to-object: the no-shell case is recorded as a
# did-not-run finding and never as clean citations. The negative fails on any sentence of the
# section that lets the critic declare the citations clean without the tool.
has R9_doc_critic_no_shell_fallback "$T/dc.txt" 'If your host gives you no shell tool, the lint does not run: record the finding "plan-row citation lint did not run: no shell tool" in your note, and never judge the plan'"'"'s citations clean by reading it — the Reviewer'"'"'s check 8 stays the gate.'
folded "$T/dc.txt" | grep -qiE '(may|can|should|free to)[^.]{0,80}(citation|plan)[^.]{0,60}clean' \
  && fail "R9_doc_critic_no_shell_fallback: the section lets the critic declare the plan's citations clean without running the lint"
pass "R9_doc_critic_no_shell_fallback"

# ── R10: the template's Data-model R-id column; the three enforcement sentences, present tense ─
slice "$I/specs/_templates/feature.plan.md" '## Data model' > "$T/tdm.txt"
grep -qxF '| Entity | Field | Type | Notes | R-id |' "$T/tdm.txt" \
  || fail "R10_template_data_model_rid_column: the installed template's ## Data model header has no R-id column"
grep -qxF '|---|---|---|---|---|' "$T/tdm.txt" || fail "R10_template_data_model_rid_column: the separator does not have five cells"
grep -qxF '| <Table> | <field> | <type> | <constraint> | R# |' "$T/tdm.txt" \
  || fail "R10_template_data_model_rid_column: the placeholder row does not end in an R# cell"
grep -qxF '| Entity | Field | Type | Notes |' "$I/specs/_templates/feature.plan.md" \
  && fail "R10_template_data_model_rid_column: the four-cell header survives"
pass "R10_template_data_model_rid_column"

# span <file> <start-heading> <end-heading> <out> — by line number (fence-proof), as
# tests/test_stage_nfrs.sh bounds the same sections.
lineno() { awk -v s="$2" 'index($0,s)==1{print NR; f=1; exit} END{if(!f) print 0}' "$1"; }
span() {
  _sa="$(lineno "$1" "$2")"; _sb="$(lineno "$1" "$3")"
  [ "$_sa" -gt 0 ] && [ "$_sb" -gt "$_sa" ] || fail "span: '$2' .. '$3' not found in order in $1"
  sed -n "${_sa},${_sb}p" "$1" > "$4"
}
span "$I/agents/architect.md" '## Stage and NFRs (ADR-0009)' '## Principles' "$T/a.sec"
has R10_prose_present_tense "$T/a.sec" '`tools/plan-cite-check.py` enforces it (E36-F04).'
has R10_prose_present_tense "$T/a.sec" 'Run `python3 "$HARNESS_DIR/tools/plan-cite-check.py" <feature>.plan.md --spec <feature>.spec.md` before hand-off; it must exit 0 — the Reviewer rejects on exit 1 (check 8).'
grep -qF 'not yet enforced' "$T/a.sec" && fail "R10_prose_present_tense: architect.md's Stage section still says 'not yet enforced'"
span "$I/docs/SPEC-FORMAT.md" '## Plan rows cite an R-id or an ADR' '## Architecture alignment' "$T/s.sec"
has R10_prose_present_tense "$T/s.sec" '`tools/plan-cite-check.py <plan> --spec <spec>` (E36-F04) turns this grammar into an exit code (0 ok, 1 violation, 2 usage/input error); `--sweep <specs-dir>` is the trigger sweep `init.sh` runs warn-only'
has R10_prose_present_tense "$T/s.sec" "the Reviewer's check 8 rejects on exit 1. This section is the schema it lints."
grep -qF 'not yet enforced' "$T/s.sec" && fail "R10_prose_present_tense: SPEC-FORMAT's grammar section still says 'not yet enforced'"
span "$I/docs/WORKFLOW.md" '## Stage and NFRs (ADR-0009)' '## Doc-critic checkpoints' "$T/w.sec"
has R10_prose_present_tense "$T/w.sec" 'Enforcement is `E36-F04`: `tools/plan-cite-check.py` turns the grammar into an exit code, `init.sh` runs it and the deferred-ADR trigger sweep warn-only at session start, the doc-critic reports it at the `feature-spec` checkpoint, and the Reviewer rejects on exit 1 (check 8)'
grep -qF 'not yet enforced' "$T/w.sec" && fail "R10_prose_present_tense: WORKFLOW's Stage section still says 'not yet enforced'"
grep -qF 'This section declares and records only.' "$T/w.sec" && fail "R10_prose_present_tense: WORKFLOW still says the section only declares and records"
grep -qF 'enforces it (E36-F04)' "$ROOT/tests/test_stage_nfrs.sh" || fail "R10_prose_present_tense: test_stage_nfrs.sh R7 does not pin the present-tense sentence"
grep -qF 'will enforce it' "$ROOT/tests/test_stage_nfrs.sh" && fail "R10_prose_present_tense: test_stage_nfrs.sh still pins the future tense"
pass "R10_prose_present_tense"

# ── R11: fence parity — iter_unfenced() reads the edge corpus exactly as fence.awk does ──
# The corpus is tests/test_tasks_pairs.sh's R5 corpus, verbatim: each segment exists for one
# clause (closer length · closer char · closer info string · backtick-in-info opener · run
# >= 3 · indent 0-3 · trailing blanks on a closer).
{ printf '%s\n' 'P0 outside' \
    '````md' 'P1 in: a 3-run cannot close a 4-run' '```' 'P2 in' '````' 'P3 out' \
    '```' 'P4 in: a tilde run cannot close a backtick fence' '~~~' 'P5 in' '```' 'P6 out' \
    '```' 'P7 in: a closer carries no info string' '```sh' 'P8 in' '```' 'P9 out' \
    '```a`b' 'P10 out: backtick in a backtick info string is not an opener' \
    '~~~a`b' 'P11 in: a tilde opener may carry a backtick' '~~~' 'P12 out' \
    '``' 'P13 out: a 2-run is not a fence' '~~' 'P14 out' \
    '    ```' 'P15 out: 4-space indent is not a fence' \
    '   ~~~' 'P16 in: 3-space indent is' '~~~  ' 'P17 out: closer with trailing blanks' \
    '~~~' 'P18 in' "$(printf '~~~\t')" 'P19 out: closer with a trailing tab'
} > "$T/fence-corpus.md"
awk "$FENCE_AWK"'fence_delim($0) { next } !fence' "$T/fence-corpus.md" > "$T/fence-awk.out"
python3 - "$TOOL" "$T/fence-corpus.md" > "$T/fence-py.out" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("plan_cite_check", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
lines = mod._read(sys.argv[2])
plain = list(mod.iter_unfenced(lines))
numbered = list(mod.iter_unfenced(lines, numbered=True))
assert [t for _n, t in numbered] == plain, "numbered and plain iter_unfenced disagree"
assert all(lines[n - 1] == t for n, t in numbered), "a numbered line points at the wrong source line"
for line in plain:
    print(line)
PY
printf '%s\n' 'P0 outside' 'P3 out' 'P6 out' 'P9 out' '```a`b' \
  'P10 out: backtick in a backtick info string is not an opener' 'P12 out' '``' \
  'P13 out: a 2-run is not a fence' '~~' 'P14 out' '    ```' 'P15 out: 4-space indent is not a fence' \
  'P17 out: closer with trailing blanks' 'P19 out: closer with a trailing tab' > "$T/fence-want.out"
cmp -s "$T/fence-want.out" "$T/fence-awk.out" \
  || fail "R11_fence_parity: fence.awk reads the corpus differently than the suite expects: $(diff "$T/fence-want.out" "$T/fence-awk.out" | tr '\n' '|')"
cmp -s "$T/fence-awk.out" "$T/fence-py.out" \
  || fail "R11_fence_parity: plan-cite-check's iter_unfenced() diverges from tests/lib/fence.awk: $(diff "$T/fence-awk.out" "$T/fence-py.out" | tr '\n' '|')"
pass "R11_fence_parity"
_mode="$(git -C "$ROOT" ls-files -s tools/plan-cite-check.py | cut -c1-6)"
[ "$_mode" = "100755" ] || fail "R11_source_mode_100755: git mode of tools/plan-cite-check.py is '$_mode'"
pass "R11_source_mode_100755"

# ── grammar in step: the tool's patterns ARE the bytes docs/SPEC-FORMAT.md states ────────
# The grammar section (its heading .. `## Architecture alignment`, by line number) is the
# source of truth. Each string is extracted from the sentence that states it and compared
# with the tool's compiled pattern, so an edit to EITHER side reds this row — the
# validator-vs-schema divergence the harness has paid for (lessons 2026-09-05, 2026-09-16).
python3 - "$TOOL" "$ROOT/docs/SPEC-FORMAT.md" <<'PY' || fail "R1_grammar_in_step_with_spec_format: see the message above"
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("plan_cite_check", sys.argv[1])
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
lines = open(sys.argv[2], encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("## Plan rows cite an R-id or an ADR"))
end = next(i for i, l in enumerate(lines) if i > start and l.startswith("## Architecture alignment"))
text = " ".join(" ".join(lines[start:end]).split())  # folded: one space between words
def grab(rx, what):
    m = re.search(rx, text)
    if not m:
        sys.exit("SPEC-FORMAT's grammar section no longer states %s (pattern %s)" % (what, rx))
    return m.groups()
checks = []
(stage,) = grab(r"matching `(\^stage: [^`]+)`", "the stage line")
checks.append(("STAGE_RE", mod.STAGE_RE.pattern, stage))
status, trigger = grab(r"\(regex `([^`]+)`\) \*\*and\*\* a line `- \*\*Trigger:\*\*` followed by a non-empty observable condition \(regex `([^`]+)`\)", "the deferred-ADR header regexes")
checks.append(("STATUS_DEFERRED_RE", mod.STATUS_DEFERRED_RE.pattern, status))
checks.append(("TRIGGER_RE", mod.TRIGGER_RE.pattern, trigger))
heads = grab(r"under a `\.plan\.md`'s `## ([^`]+)`, `## ([^`]+)`, `## ([^`]+)` and `## ([^`]+)` headings carries an `([^`]+)` token or an `([^`]+)` token", "the plan-row rule")
checks.append(("CHECKED_RE", mod.CHECKED_RE.pattern, r"^## (" + "|".join(heads[:4]) + r")(\s|$)"))
checks.append(("RID_TOKEN_RE", mod.RID_TOKEN_RE.pattern, r"(?<![A-Za-z0-9])" + heads[4]))
checks.append(("ADR_TOKEN_RE", mod.ADR_TOKEN_RE.pattern, heads[5]))
(bolt,) = grab(r"a table headed `(\|[^`]+\|)`", "the Bolt-on table header")
checks.append(("BOLT_ON_HEADER", "| " + " | ".join(mod.BOLT_ON_HEADER) + " |", bolt))
(none,) = grab(r"the single line `(Deferred: none — )<why>`", "the none line")
checks.append(("NONE_LINE_RE", mod.NONE_LINE_RE.pattern, "^" + none + r"\S"))
bad = [(n, got, want) for n, got, want in checks if got != want]
for n, got, want in bad:
    sys.stderr.write("  %s is %r but SPEC-FORMAT states %r\n" % (n, got, want))
sys.exit(1 if bad else 0)
PY
pass "R1_grammar_in_step_with_spec_format"

# ── R12: VERSION ↔ newest CHANGELOG heading (read at runtime, no literal); ledger row C10 ─
_v="$(cat "$ROOT/VERSION")"
[ -n "$_v" ] || fail "R12_version_changelog_ledger: VERSION is empty"
_head="$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" || true)"
case "$_head" in "## [$_v]"*) ;; *) fail "R12_version_changelog_ledger: newest CHANGELOG heading '$_head' != VERSION '$_v'" ;; esac
# historical anchor: SOME release section names E36-F04 and plan-cite-check and says the
# enforcement is now real, so a later release prepended above stays green
awk '/^## \[/ { if (sec ~ /E36-F04/ && sec ~ /plan-cite-check/ && sec ~ /is now real/) ok = 1; sec = ""; next } { sec = sec "\n" $0 }
     END { if (sec ~ /E36-F04/ && sec ~ /plan-cite-check/ && sec ~ /is now real/) ok = 1; exit ok ? 0 : 1 }' "$ROOT/CHANGELOG.md" \
  || fail "R12_version_changelog_ledger: no CHANGELOG section names E36-F04 and plan-cite-check and says enforcement is now real"
slice "$ROOT/docs/RATIONALE.md" '## Deletion ledger' > "$T/led.txt"
_c10="$(grep -E '^\| C10 — Plan-row citation lint \| Capability compensation \|' "$T/led.txt" || true)"
[ -n "$_c10" ] || fail "R12_version_changelog_ledger: no '| C10 — Plan-row citation lint | Capability compensation |' row in the Deletion ledger"
# the evidence cell (the 4th) states the ablation condition, not just a token
printf '%s\n' "$_c10" | awk -F'|' '{ print $5 }' | grep -qE 'Ablation[^|]*uncited-row[^|]*Retain while' \
  || fail "R12_version_changelog_ledger: the C10 evidence cell does not state the ablation condition (Ablation … uncited-row … Retain while)"
printf '%s\n' "$_c10" | grep -qF '[`tools/plan-cite-check.py`](../tools/plan-cite-check.py)' \
  || fail "R12_version_changelog_ledger: the C10 row does not point at tools/plan-cite-check.py"
pass "R12_version_changelog_ledger"


echo "all plan-cite checks passed"
