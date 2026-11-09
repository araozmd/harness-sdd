#!/bin/sh
# test_readiness_check.sh — E37-F01: the implementation-readiness lint
# (tools/readiness-check.py), its init.sh warn-only sweep (2e), Reviewer check 9, the
# Architect's pre-hand-off step and the doc-critic's advisory section.
#
# Behavioral rows drive the tool against tests/fixtures/readiness/repo (copied into a fresh
# $T/<row>/repo per row, each variant derived with sed/awk/printf so every row has exactly
# one cause) and pass --root "$T/<row>/repo". Prose rows grep the INSTALLED copy inside a
# BOUNDED slice — role sections and `## What you check` through the fence-aware slicer
# (tests/lib/fence.awk), doc sections by heading line numbers — and anchor whole sentences
# from their subject over folded newlines. Co-occurrence is not polarity: read the diff.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never git-diff a DO-NOT-TOUCH file against main; never write state/ or a live
# spec. Exit codes are asserted as `rc -eq N`, never a shell-dependent code.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/tools/readiness-check.py"
FX="$ROOT/tests/fixtures/readiness"
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
T="$(mktemp -d 2>/dev/null || mktemp -d -t readiness)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)
# Root discovery (the tool's .git walk) and every fixture git call stop at $T, so a TMPDIR
# that sits inside some work tree can never lend a row its .git (lesson 2026-10-17).
GIT_CEILING_DIRECTORIES="$T"; export GIT_CEILING_DIRECTORIES

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v python3 >/dev/null 2>&1 || fail "python3 is a hard harness dependency and is absent"
[ -d "$FX/repo/specs" ] || fail "setup: fixture tree $FX/repo is missing"

# fresh <row> — copy the fixture repo into $T/<row>/repo and name its files.
fresh() {
  rm -rf "$T/$1"; mkdir -p "$T/$1"
  cp -R "$FX/repo" "$T/$1/repo"
  R="$T/$1/repo"
  GD="$R/specs/epics/E01-x/F01-good"; BD="$R/specs/epics/E01-x/F02-bad"
  GP="$GD/E01-F01.plan.md"; GT="$GD/E01-F01.tasks.md"; GX="$GD/E01-F01.tests.md"
  BP="$BD/E01-F02.plan.md"; BT="$BD/E01-F02.tasks.md"; BX="$BD/E01-F02.tests.md"
}
# run_tool <args...> — stdout to $T/out, stderr to $T/err, exit code to $rc.
run_tool() { set +e; python3 "$TOOL" "$@" >"$T/out" 2>"$T/err"; rc=$?; set -e; }
# lint <feature-dir> — lint mode against the current fresh copy.
lint() { run_tool "$1" --root "$R"; }
both() { cat "$T/out" "$T/err" 2>/dev/null | tr '\n' '|'; }
# expect_ok <row> — exit 0, exactly one stdout line and it is the ok line, stderr empty.
expect_ok() {
  [ "$rc" -eq 0 ] || fail "$1: expected rc 0, got $rc ($(both))"
  [ "$(wc -l < "$T/out" | tr -d ' ')" -eq 1 ] || fail "$1: expected exactly one stdout line ($(both))"
  grep -q '^readiness-check: ok ' "$T/out" || fail "$1: stdout is not the ok line ($(both))"
  [ ! -s "$T/err" ] || fail "$1: stderr is not empty ($(both))"
}
# expect_fail <row> — exit 1 and the last stdout line is the FAIL summary.
expect_fail() {
  [ "$rc" -eq 1 ] || fail "$1: expected rc 1, got $rc ($(both))"
  tail -n 1 "$T/out" | grep -qE '^readiness-check: FAIL [0-9]+ finding\(s\)$' \
    || fail "$1: the last stdout line is not 'readiness-check: FAIL <n> finding(s)' ($(both))"
}
# count <regex> — how many stdout lines match.
count() { grep -cE "$1" "$T/out" || true; }
crlf() { awk '{ printf "%s\r\n", $0 }' "$1" > "$1.crlf"; mv "$1.crlf" "$1"; }
# insert_before <file> <line-prefix> <text-file> — insert the text file's lines before the
# first line starting with the prefix (in place).
insert_before() {
  awk -v p="$2" -v f="$3" 'index($0, p) == 1 && !d { while ((getline l < f) > 0) print l; d = 1 } { print }' "$1" > "$1.new"
  mv "$1.new" "$1"
}
# add_item <tasks-file> <text> — append one list item to a tasks file.
add_item() { printf '%s\n' "$2" >> "$1"; }

# ── R1: a clean feature ⇒ exit 0 and one ok line ────────────────────────────────────────
fresh r1
lint "$GD"; expect_ok R1_ok_positive
grep -qE '^readiness-check: ok .*tasks: read, tests: read$' "$T/out" \
  || fail "R1_ok_positive: the ok line does not end 'tasks: read, tests: read' ($(both))"
grep -qF ", 3 created, " "$T/out" || fail "R1_ok_positive: the ok line does not count the 3 created paths ($(both))"
pass "R1_ok_positive"

lint "$GD"; cp "$T/out" "$T/ok-dir"
lint "$GP"; expect_ok R1_ok_plan_path_input
cmp -s "$T/ok-dir" "$T/out" || fail "R1_ok_plan_path_input: the plan-path input does not give the dir input's ok line ($(both))"
grep -qF "readiness-check: ok $GP: " "$T/out" || fail "R1_ok_plan_path_input: the ok line does not name the plan path ($(both))"
pass "R1_ok_plan_path_input"

fresh r1crlf
for _f in "$GP" "$GT" "$GX" "$GD/E01-F01.spec.md"; do crlf "$_f"; done
grep -q "$(printf '\r')\$" "$GT" || fail "R1_ok_crlf: precondition: the tasks copy is not CRLF"
lint "$GD"; expect_ok R1_ok_crlf
pass "R1_ok_crlf"

# A BOM'd plan whose line 1 is `## Files to change`: if the BOM stayed, line 1 is no heading,
# no row is read, the created set is empty and the tasks' created references go unresolved.
fresh r1bom
{ printf '\357\273\277'; sed -n '/^## Files to change/,$p' "$GP"; } > "$GP.bom"; mv "$GP.bom" "$GP"
[ "$(head -c 3 "$GP" | od -An -tx1 | tr -d ' \n')" = efbbbf ] || fail "R1_ok_bom: precondition: the plan does not start with a BOM"
[ "$(sed -n '1p' "$GP" | cut -c4-)" = '## Files to change' ] || fail "R1_ok_bom: precondition: line 1 is not the heading"
lint "$GD"; expect_ok R1_ok_bom
grep -qF ", 3 created, " "$T/out" || fail "R1_ok_bom: the BOM'd line-1 heading was not read ($(both))"
pass "R1_ok_bom"

# A tilde fence and a 3-space-indented backtick fence, each hiding a row naming a missing
# file, inserted INSIDE `## Files to change`; and a fenced tasks item naming a missing suite.
fresh r1fence
printf '%s\n' '~~~markdown' '| `tools/decoy.py` | modify: a row in a tilde fence | R1 |' '~~~' '' \
  '   ```' '| `tools/decoy.py` | modify: a row in an indented backtick fence | R1 |' '   ```' '' > "$T/decoys.md"
insert_before "$GP" '## Deferred' "$T/decoys.md"
printf '%s\n' '' '```' '- [ ] **T9** — Run `tests/test_decoy.sh`.' '```' >> "$GT"
grep -qF '~~~markdown' "$GP" && grep -qF 'test_decoy.sh' "$GT" || fail "R1_ok_fenced_decoys: precondition: the decoys were not inserted"
lint "$GD"; expect_ok R1_ok_fenced_decoys
pass "R1_ok_fenced_decoys"

fresh r1abs
rm "$GT" "$GX"
lint "$GD"; expect_ok R1_ok_siblings_absent
grep -qE '^readiness-check: ok .*tasks: absent, tests: absent$' "$T/out" \
  || fail "R1_ok_siblings_absent: the ok line does not say 'tasks: absent, tests: absent' ($(both))"
pass "R1_ok_siblings_absent"

# Root discovery: no --root; the copy's .git (a directory, then a FILE as in a linked worktree)
# makes the copy the root.
fresh r1git
mkdir "$R/.git"
run_tool "$GD"; expect_ok "R1_root_discovered_from_git (.git dir)"
rmdir "$R/.git"; echo 'gitdir: /nowhere' > "$R/.git"
run_tool "$GD"; expect_ok "R1_root_discovered_from_git (.git file)"
pass "R1_root_discovered_from_git"

run_tool "$ROOT/specs/epics/E37-goldfish-spec-review/F01-readiness-lint/"; expect_ok R1_dogfood_own_dir
grep -qE '^readiness-check: ok .*tasks: read, tests: read$' "$T/out" || fail "R1_dogfood_own_dir: not every sibling was read ($(both))"
pass "R1_dogfood_own_dir"

# ── R2: a `## Files to change` first-cell path that does not resolve ⇒ unresolved-path ──
# lno <file> <fixed-string> — the line number of the first line holding the string (a
# precondition: the fixture README states each planted defect's line).
lno() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }
# readme_says <file-basename:line> — the fixture README documents the planted defect there.
readme_says() { grep -qF "| $1 |" "$FX/README.md" || fail "setup: the fixture README does not document $1"; }

fresh r1fencectl
insert_before "$GP" '## Deferred' "$T/decoys.md"
grep -vE '^ *(```|~~~)' "$GP" > "$GP.live"; mv "$GP.live" "$GP"
lint "$GD"; expect_fail "R1_ok_fenced_decoys control"
[ "$(count '^readiness-check: unresolved-path .*E01-F01\.plan\.md:[0-9]+ tools/decoy\.py$')" -ge 2 ] \
  || fail "R1_ok_fenced_decoys control: the unfenced decoys did not each give a finding ($(both))"
pass "R1_ok_fenced_decoys control"

fresh r2
_l="$(lno "$BP" '`tools/missing.py`')"; readme_says "E01-F02.plan.md:$_l"
lint "$BD"; expect_fail R2_unresolved_path_plan_row
[ "$(count "^readiness-check: unresolved-path .*E01-F02\\.plan\\.md:$_l tools/missing\\.py\$")" -eq 1 ] \
  || fail "R2_unresolved_path_plan_row: expected exactly one 'unresolved-path <plan>:$_l tools/missing.py' ($(both))"
grep -qxF "readiness-check: unresolved-path $BD/E01-F02.plan.md:$_l tools/missing.py" "$T/out" \
  || fail "R2_unresolved_path_plan_row: the finding does not name the plan as derived from argv ($(both))"
pass "R2_unresolved_path_plan_row"

_l="$(lno "$BP" '`REDME.md`')"; readme_says "E01-F02.plan.md:$_l"
[ "$(count "^readiness-check: unresolved-path .*E01-F02\\.plan\\.md:$_l REDME\\.md\$")" -eq 1 ] \
  || fail "R2_bare_first_cell_checked: a bare first-cell basename that resolves nowhere is not a finding ($(both))"
fresh r2bare
grep -qF '| `README.md` | modify' "$GP" || fail "R2_bare_first_cell_checked: precondition: the positive plan lost its README.md row"
lint "$GD"; expect_ok R2_bare_first_cell_checked
pass "R2_bare_first_cell_checked"

fresh r2create
_l="$(lno "$GP" '| `tools/new.py` |')"
sed 's/^| `tools\/new.py` | \*\*create\*\* /| `tools\/new.py` | **modify** /' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
grep -qF '| `tools/new.py` | **modify** ' "$GP" || fail "R2_create_row_exempt: precondition: the verb rewrite did not apply"
lint "$GD"; expect_fail R2_create_row_exempt
[ "$(count "^readiness-check: unresolved-path .*E01-F01\\.plan\\.md:$_l tools/new\\.py\$")" -eq 1 ] \
  || fail "R2_create_row_exempt: a modify row on a file that does not exist is not a finding ($(both))"
pass "R2_create_row_exempt"

fresh r2under
printf '%s\n' '| `tests/fixtures/new/deep/x.md` | modify the fixture | R2 |' > "$T/row.md"
insert_before "$GP" '| `README.md` |' "$T/row.md"
lint "$GD"; expect_ok R2_under_created_dir
grep -v '^| `tests/fixtures/new/` |' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
lint "$GD"; expect_fail R2_under_created_dir
[ "$(count '^readiness-check: unresolved-path .*E01-F01\.plan\.md:[0-9]+ tests/fixtures/new/deep/x\.md$')" -eq 1 ] \
  || fail "R2_under_created_dir: with the create row gone the deep path is not a finding ($(both))"
pass "R2_under_created_dir"

fresh r2add
_l="$(lno "$BP" '`tests/test_gone.sh`')"; readme_says "E01-F02.plan.md:$_l"
grep -qF '| `tests/test_gone.sh` | add a case, then create the fixture |' "$BP" || fail "R2_add_row_path_checked: precondition: the add row changed"
lint "$BD"; expect_fail R2_add_row_path_checked
[ "$(count "^readiness-check: unresolved-path .*E01-F02\\.plan\\.md:$_l tests/test_gone\\.sh\$")" -eq 1 ] \
  || fail "R2_add_row_path_checked: an add row whose cell names create later was exempted ($(both))"
sed 's/^| `tests\/test_gone.sh` | add a case/| `tests\/test_gone.sh` | create a case/' "$BP" > "$BP.new"; mv "$BP.new" "$BP"
lint "$BD"
[ "$(count 'tests/test_gone\.sh')" -eq 0 ] || fail "R2_add_row_path_checked: a create row's path was checked ($(both))"
pass "R2_add_row_path_checked"

fresh r2hdr
# The header names a missing path under a known root and the separator carries alignment
# colons: both stay exempt because the header is found by POSITION, not by text.
sed -e 's/^| File | Change | R-id |$/| `tools\/nope-a.md` | `tools\/nope-b.md` | R |/' \
    -e '/^| `tools\/nope-a.md` /{n;s/^|---|---|---|$/|:---|---:|---|/;}' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
grep -qxF '| `tools/nope-a.md` | `tools/nope-b.md` | R |' "$GP" && grep -qxF '|:---|---:|---|' "$GP" \
  || fail "R2_header_separator_exempt: precondition: the header/separator rewrite did not apply"
lint "$GD"; expect_ok R2_header_separator_exempt
pass "R2_header_separator_exempt"

fresh r2other
grep -qxF '| `tools/nowhere.md` | a row in an unscanned section | R1 |' "$GP" \
  && grep -qxF '| `tools/nowhere.md` | a pipe row under DO NOT TOUCH |' "$GP" \
  || fail "R2_other_sections_unscanned: precondition: the positive plan lost its Data model / DO NOT TOUCH rows"
lint "$GD"; expect_ok R2_other_sections_unscanned
pass "R2_other_sections_unscanned"

fresh r2multi
printf '%s\n' '| `tools/real.py`, `tools/nope.py` | modify both | R1 |' > "$T/row.md"
insert_before "$GP" '| `README.md` |' "$T/row.md"
lint "$GD"; expect_fail R2_multi_span_first_cell
[ "$(count '^readiness-check: unresolved-path ')" -eq 1 ] && [ "$(count ' tools/nope\.py$')" -eq 1 ] \
  || fail "R2_multi_span_first_cell: expected exactly one finding, naming tools/nope.py ($(both))"
pass "R2_multi_span_first_cell"

# ── R3: tasks list items, tests rows and items ⇒ unresolved-path at the physical line ───
fresh r3
lint "$BD"; expect_fail R3_tasks_item_unresolved
_l="$(lno "$BT" '`tests/test_missing.sh`')"; readme_says "E01-F02.tasks.md:$_l"
[ "$(count "^readiness-check: unresolved-path .*E01-F02\\.tasks\\.md:$_l tests/test_missing\\.sh\$")" -eq 1 ] \
  || fail "R3_tasks_item_unresolved: no finding for the tasks item's missing suite ($(both))"
pass "R3_tasks_item_unresolved"
# The continuation line is reported at ITS number, not the bullet's.
_b="$(lno "$BT" '**T1**')"
[ "$_l" -eq $((_b + 1)) ] || fail "R3_continuation_line_physical_number: precondition: the reference is not on the item's second line"
grep -qF "E01-F02.tasks.md:$_b " "$T/out" && fail "R3_continuation_line_physical_number: a finding names the bullet's line $_b ($(both))"
pass "R3_continuation_line_physical_number"

_l="$(lno "$BX" '`tests/test_missing2.sh::R1`')"; readme_says "E01-F02.tests.md:$_l"
[ "$(count "^readiness-check: unresolved-path .*E01-F02\\.tests\\.md:$_l tests/test_missing2\\.sh\$")" -eq 1 ] \
  || fail "R3_tests_row_unresolved: no finding (printed without its ::R1 tail) for the tests row ($(both))"
pass "R3_tests_row_unresolved"
_l="$(lno "$BX" '`docs/gone.md`')"; readme_says "E01-F02.tests.md:$_l"
[ "$(count "^readiness-check: unresolved-path .*E01-F02\\.tests\\.md:$_l docs/gone\\.md\$")" -eq 1 ] \
  || fail "R3_tests_list_item_unresolved: no finding for the tests bullet ($(both))"
pass "R3_tests_list_item_unresolved"

# Order: plan findings, then tasks, then tests; ascending line within each.
awk -v bd="$BD/" '
  /^readiness-check: unresolved-/ {
    loc = $3; sub(/^.*\//, "", loc); split(loc, a, ":"); f = a[1]; n = a[2] + 0
    r = (f ~ /\.plan\.md$/) ? 0 : (f ~ /\.tasks\.md$/) ? 1 : 2
    seen[r] = 1
    if (r < pr || (r == pr && n < pn)) bad = 1
    pr = r; pn = n
  }
  END { exit (bad || !seen[0] || !seen[1] || !seen[2]) ? 1 : 0 }' "$T/out" \
  || fail "R3_finding_order_plan_tasks_tests: findings are not plan → tasks → tests by line ($(both))"
pass "R3_finding_order_plan_tasks_tests"

fresh r3created
lint "$GD"; expect_ok R3_created_set_resolves_tasks
grep -vE '^\| `(tools/new\.py|tests/fixtures/new/)` \|' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
lint "$GD"; expect_fail R3_created_set_resolves_tasks
[ "$(count '^readiness-check: unresolved-path .*E01-F01\.tasks\.md:')" -eq 2 ] \
  && [ "$(count 'E01-F01\.tasks\.md:[0-9]+ tools/new\.py$')" -eq 1 ] \
  && [ "$(count 'E01-F01\.tasks\.md:[0-9]+ tests/fixtures/new/a\.md$')" -eq 1 ] \
  || fail "R3_created_set_resolves_tasks: without the create rows the two tasks references are not exactly the findings ($(both))"
pass "R3_created_set_resolves_tasks"

fresh r3dc
add_item "$GT" '- [ ] **T9** — Extend `tests/test_real.sh::does_not_exist_yet`.'
lint "$GD"; expect_ok R3_test_ref_double_colon_file_only
pass "R3_test_ref_double_colon_file_only"

# The create exemption: every inflection exempts the unit; Recreate / created_x do not.
for _w in Create creates created creating; do
  fresh r3cr
  add_item "$GT" "- [ ] **T9** — $_w \`docs/fresh.md\` for the notes."
  lint "$GD"; expect_ok "R3_create_item_exempt[$_w]"
done
for _w in Recreate created_x; do
  fresh r3cr
  add_item "$GT" "- [ ] **T9** — $_w \`docs/fresh.md\` for the notes."
  lint "$GD"; expect_fail "R3_create_item_exempt[$_w]"
  [ "$(count 'E01-F01\.tasks\.md:[0-9]+ docs/fresh\.md$')" -eq 1 ] \
    || fail "R3_create_item_exempt[$_w]: '$_w' exempted the unit ($(both))"
done
pass "R3_create_item_exempt"

fresh r3bare
add_item "$GT" '- [ ] **T9** — Read `E01-F09.tests.md` and `fence.awk`.'
lint "$GD"; expect_ok R3_bare_basename_rule
printf '%s\n' '| `fence.awk` | modify the fence rule | R1 |' > "$T/row.md"
insert_before "$GP" '| `README.md` |' "$T/row.md"
lint "$GD"; expect_fail R3_bare_basename_rule
[ "$(count '^readiness-check: unresolved-path .*E01-F01\.plan\.md:[0-9]+ fence\.awk$')" -eq 1 ] \
  || fail "R3_bare_basename_rule: a bare first-cell basename found nowhere is not a finding ($(both))"
pass "R3_bare_basename_rule"

fresh r3prose
printf '%s\n' '' '> A blockquote naming `tools/nope.py`.' '' 'A paragraph naming `tools/nope.py`.' >> "$GT"
lint "$GD"; expect_ok R3_blockquote_and_prose_unscanned
add_item "$GT" '- a list item naming `tools/nope.py`'
lint "$GD"; expect_fail "R3_blockquote_and_prose_unscanned control"
[ "$(count ' tools/nope\.py$')" -eq 1 ] || fail "R3_blockquote_and_prose_unscanned control: the list item was not scanned ($(both))"
pass "R3_blockquote_and_prose_unscanned"

# ── R4: ignore rules (each under a KNOWN root), trailing /, ./, the .harness/ remap ──────
# clean_tasks — drop the positive tasks' ignored-shapes item (T4 to the end), so each R4
# case plants exactly one token on an otherwise clean copy.
clean_tasks() { awk '/^- \[ \] \*\*T4\*\*/ { exit } { print }' "$GT" > "$GT.new"; mv "$GT.new" "$GT"; }
_n=0
for _tok in 'tools/<x>.py' 'tools/<x.py' 'tools/x>.py' 'tools/a*.py' 'tools/a?.py' 'docs/a[1].md' \
    'docs/a[1.md' 'docs/a1].md' 'tools/{a,b}.py' 'tools/{a.py' 'tools/a}.py' 'docs/$X.md' \
    'tools/~x.py' 'tools/a|b.py' 'tools/…/x.md' 'http://x/tools/y.md' '/var/tmp/x' '--root' \
    '.mutbak' '.plan.md' 'scratchpad/E01-F01-builder/' 'progress/E01-F01/builder.md' 'VERSION' \
    'check 8' 'origin/main' 'tols/x.py' '.harness/'; do
  fresh r4tok; clean_tasks
  # `http:` made a known root, so only the `://` rule can ignore the URL token
  case "$_tok" in http://*) mkdir "$R/http:" ;; esac
  [ -d "$R/scratchpad" ] && [ -d "$R/progress" ] && [ -d "$R/tools" ] && [ -d "$R/docs" ] \
    || fail "R4_ignored_tokens: precondition: the fixture's known roots are missing"
  grep -qF -- "\`$_tok\`" "$GT" && fail "R4_ignored_tokens: precondition: the clean copy still names '$_tok'"
  add_item "$GT" "- [ ] **T9** — Mention \`$_tok\` in prose."
  lint "$GD"; expect_ok "R4_ignored_tokens[$_tok]"
  _n=$((_n + 1))
done
[ "$_n" -ge 20 ] || fail "R4_ignored_tokens: only $_n tokens were exercised"
pass "R4_ignored_tokens ($_n tokens)"

# The shapes a plan FIRST cell would otherwise check (a bare basename there is a reference):
# a bare extension, a flag-like name and an absolute path stay ignored by their own rule.
fresh r4first
printf '%s\n' '| `.plan.md`, `--out.md`, `/var/tmp/x.md` | modify the scratch outputs | R1 |' > "$T/row.md"
insert_before "$GP" '| `README.md` |' "$T/row.md"
lint "$GD"; expect_ok R4_plan_first_cell_shapes
pass "R4_plan_first_cell_shapes"

fresh r4dir
clean_tasks; add_item "$GT" '- [ ] **T9** — Under `tools/`.'
lint "$GD"; expect_ok R4_dir_trailing_slash
for _tok in 'tools/nowhere/' 'tools/real.py/'; do
  fresh r4dir; clean_tasks; add_item "$GT" "- [ ] **T9** — Under \`$_tok\`."
  lint "$GD"; expect_fail "R4_dir_trailing_slash[$_tok]"
  [ "$(count "^readiness-check: unresolved-path .*E01-F01\\.tasks\\.md:[0-9]+ $_tok\$")" -eq 1 ] \
    || fail "R4_dir_trailing_slash[$_tok]: a directory reference that is not a directory is not a finding ($(both))"
done
pass "R4_dir_trailing_slash"

# ./ is stripped before resolution: `./tools/new.py` is the created `tools/new.py`.
fresh r4dot
clean_tasks; add_item "$GT" '- [ ] **T9** — Call `./tools/new.py` and `./tools/real.py`.'
lint "$GD"; expect_ok R4_leading_dot_slash_stripped
add_item "$GT" '- [ ] **T10** — Call `./tools/nope.py`.'
lint "$GD"; expect_fail R4_leading_dot_slash_stripped
[ "$(count '^readiness-check: unresolved-path .*E01-F01\.tasks\.md:[0-9]+ \./tools/nope\.py$')" -eq 1 ] \
  || fail "R4_leading_dot_slash_stripped: './tools/nope.py' is not one finding printed as written ($(both))"
pass "R4_leading_dot_slash_stripped"

fresh r4remap
grep -qF '`.harness/tools/real.py`' "$GT" || fail "R4_harness_remap_both_ways: precondition: the positive tasks lost .harness/tools/real.py"
[ ! -e "$R/.harness" ] || fail "R4_harness_remap_both_ways: precondition: the fixture has a .harness/"
lint "$GD"; expect_ok "R4_harness_remap_both_ways (.harness/ → bare)"
mkdir "$R/.harness"; mv "$R/tools" "$R/tests" "$R/docs" "$R/.harness/"
lint "$GD"; expect_ok "R4_harness_remap_both_ways (bare → .harness/)"
# docs/ has no created path, so only the `.harness/<first>` known-root clause makes it known.
add_item "$GT" '- [ ] **T9** — Call `tools/nope.py` and read `docs/nope.md`.'
lint "$GD"; expect_fail R4_harness_remap_both_ways
[ "$(count '^readiness-check: unresolved-path ')" -eq 2 ] && [ "$(count 'E01-F01\.tasks\.md:[0-9]+ tools/nope\.py$')" -eq 1 ] \
  && [ "$(count 'E01-F01\.tasks\.md:[0-9]+ docs/nope\.md$')" -eq 1 ] \
  || fail "R4_harness_remap_both_ways: under the installed layout tools/nope.py and docs/nope.md are not the two findings ($(both))"
pass "R4_harness_remap_both_ways"

fresh r4croot
[ ! -e "$R/contract" ] || fail "R4_created_root_is_known: precondition: the fixture has contract/"
printf '%s\n' '| `contract/api.yaml` | create the API contract | R2 |' > "$T/row.md"
insert_before "$GP" '| `README.md` |' "$T/row.md"
clean_tasks; add_item "$GT" '- [ ] **T9** — Validate against `contract/missing.yaml`.'
lint "$GD"; expect_fail R4_created_root_is_known
[ "$(count '^readiness-check: unresolved-path ')" -eq 1 ] && [ "$(count 'E01-F01\.tasks\.md:[0-9]+ contract/missing\.yaml$')" -eq 1 ] \
  || fail "R4_created_root_is_known: a created first segment did not make contract/missing.yaml a reference ($(both))"
grep -v '^| `contract/api.yaml` |' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
lint "$GD"; expect_ok "R4_created_root_is_known (no create row ⇒ unknown root, ignored)"
pass "R4_created_root_is_known"

echo "all readiness-check checks passed"
