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

# lno <file> <fixed-string> — the line number of the first line holding the string (a
# precondition: the fixture README states each planted defect's line).
lno() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }
# readme_says <file-basename:line> — the fixture README documents the planted defect there.
readme_says() { grep -qF "| $1 |" "$FX/README.md" || fail "setup: the fixture README does not document $1"; }

# clean_tasks — drop the positive tasks' ignored-shapes item (T4 to the end), so each R4
# case plants exactly one token on an otherwise clean copy.
clean_tasks() { awk '/^- \[ \] \*\*T4\*\*/ { exit } { print }' "$GT" > "$GT.new"; mv "$GT.new" "$GT"; }
# set_cell <plan> <first-cell-fixed-string> <new-change-cell> — rewrite one row's Change cell.
set_cell() {
  awk -v k="| \`$2\` |" -v f="$2" -v c="$3" 'index($0, k) == 1 && !d { split($0, a, "|"); printf "| `%s` | %s |%s|\n", f, c, a[4]; d = 1; next } { print }' "$1" > "$1.new"
  mv "$1.new" "$1"
}
# chk_exit2 <row> <stderr-fixed-string> — each row's argv is the minimal one ONLY that branch
# rejects; the string names the branch so a second producer cannot pass it.
chk_exit2() {
  [ "$rc" -eq 2 ] || fail "$1: expected rc 2, got $rc ($(both))"
  head -n 1 "$T/err" | grep -q '^readiness-check: error: ' || fail "$1: stderr's first line is not 'readiness-check: error: ...' ($(both))"
  grep -q 'usage:' "$T/err" || fail "$1: no usage on stderr ($(both))"
  [ ! -s "$T/out" ] || fail "$1: stdout is not empty on an error ($(both))"
  grep -qF -- "$2" "$T/err" || fail "$1: the error does not name '$2' ($(both))"
  pass "$1"
}
# setup_target — ONE fresh install (CODEX_HOME/HOME sandboxed) into $T/tgt, a git work tree
# (hostile-config-proof git, lesson 2026-10-19) whose ROOT holds the fixture's project files.
# R7 plants features under the installed .harness/specs; the prose rows read the installed copy.
setup_target() {
  mkdir -p "$T/tgt" "$T/ch" "$T/home"
  CODEX_HOME="$T/ch" HOME="$T/home" sh "$ROOT/harness-install.sh" --agents=claude "$T/tgt" \
    >"$T/install.out" 2>"$T/install.err" || fail "setup: fresh install exited non-zero: $(cat "$T/install.err")"
  I="$T/tgt/.harness"
  hgit() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TEMPLATE_DIR='' git "$@"; }
  hgit init -q "$T/tgt" || fail "setup: git init of the target failed"
  cp -R "$FX/repo/tools" "$FX/repo/docs" "$FX/repo/tests" "$FX/repo/README.md" "$T/tgt/"
}
# init_case <feature-id> <status> <sdd> <feature-dir> — plant board + feature.
init_case() {
  rm -rf "$I/specs/epics/E01-x" "$T/tgt/src"; mkdir -p "$I/specs/epics"
  cp -R "$FX/repo/specs/epics/E01-x" "$I/specs/epics/"
  printf '{"$schema": "../store/tasks.schema.json", "project": "fx", "epics": [{"id": "E01", "title": "Fixture", "status": "in-progress", "features": [{"id": "%s", "title": "Fixture feature", "status": "%s", "sdd": %s, "autonomous": false, "depends_on": [], "spec_path": "specs/epics/E01-x/%s/"}]}]}\n' \
    "$1" "$2" "$3" "$4" > "$I/state/tasks.json"
  IGP="$I/specs/epics/E01-x/F01-good/E01-F01.plan.md"; IGT="$I/specs/epics/E01-x/F01-good/E01-F01.tasks.md"
  IBP="$I/specs/epics/E01-x/F02-bad/E01-F02.plan.md"
}
init_run() { set +e; (cd "$T/tgt" && bash "$I/init.sh") >"$T/out" 2>"$T/err"; rc=$?; set -e; }
init_ok() {
  [ "$rc" -eq 0 ] || fail "$1: init.sh exited $rc — the 2e block must never fail the gate ($(both))"
  grep -qF '✅ environment ready' "$T/out" || fail "$1: init.sh did not reach its final ok line ($(both))"
}

GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_NOSYSTEM=1; GIT_TEMPLATE_DIR=''
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM GIT_TEMPLATE_DIR
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
# prose helpers: fence-aware heading slicer (tests/lib/fence.awk), folded anchors, spans.
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
# hasre <row> <text-file> <ERE> — the folded text matches the anchored pattern (case-insensitive).
hasre() { folded "$2" | grep -qiE -- "$3" || fail "$1: no match for /$3/"; }
lineno() { awk -v s="$2" 'index($0,s)==1{print NR; f=1; exit} END{if(!f) print 0}' "$1"; }
span() {
  _sa="$(lineno "$1" "$2")"; _sb="$(lineno "$1" "$3")"
  [ "$_sa" -gt 0 ] && [ "$_sb" -gt "$_sa" ] || fail "span: '$2' .. '$3' not found in order in $1"
  sed -n "${_sa},${_sb}p" "$1" > "$4"
}


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
# A fenced example ABOVE the table: if a CRLF closer (```\r) did not close it, every row
# after it — the create rows included — would vanish and the tasks' created references fail.
printf '%s\n' '```text' '| `tools/decoy.py` | modify: a fenced example | R1 |' '```' '' > "$T/fenced.md"
insert_before "$GP" '| File | Change | R-id |' "$T/fenced.md"
for _f in "$GP" "$GT" "$GX" "$GD/E01-F01.spec.md"; do crlf "$_f"; done
grep -q "$(printf '\r')\$" "$GT" || fail "R1_ok_crlf: precondition: the tasks copy is not CRLF"
lint "$GD"; expect_ok R1_ok_crlf
grep -qF ", 3 created, " "$T/out" || fail "R1_ok_crlf: the CRLF create rows were not all read ($(both))"
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
grep -qE '^readiness-check: ok .*: 5 reference\(s\) resolved, 3 created, tasks: absent, tests: absent$' "$T/out" \
  || fail "R1_ok_siblings_absent: the ok line does not say '5 reference(s) resolved, 3 created, tasks: absent, tests: absent' (the plan's five non-creating first-cell paths) ($(both))"
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

# The create verb is matched case-insensitively (`**Create**`, `CREATE`): the row still
# declares tools/new.py (review round 1, V11).
for _v in '**Create**' 'CREATE'; do
  fresh r2case
  set_cell "$GP" 'tools/new.py' "$_v the new tool"
  grep -qF "| \`tools/new.py\` | $_v the new tool |" "$GP" || fail "R2_create_verb_case_insensitive[$_v]: precondition: the cell rewrite did not apply"
  lint "$GD"; expect_ok "R2_create_verb_case_insensitive[$_v]"
  grep -qF ", 3 created, " "$T/out" || fail "R2_create_verb_case_insensitive[$_v]: the row no longer counts as created ($(both))"
done
pass "R2_create_verb_case_insensitive"

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

fresh r3dup
add_item "$GT" '- [ ] **T9** — Call `tools/nope.py`, then `tools/nope.py` again.'
lint "$GD"; expect_fail R3_duplicate_on_one_line_collapsed
[ "$(count '^readiness-check: unresolved-path ')" -eq 1 ] && tail -n 1 "$T/out" | grep -qxF 'readiness-check: FAIL 1 finding(s)' \
  || fail "R3_duplicate_on_one_line_collapsed: one missing path named twice on a line is not one finding ($(both))"
pass "R3_duplicate_on_one_line_collapsed"

fresh r3prose
printf '%s\n' '' '> A blockquote naming `tools/nope.py`.' '' 'A paragraph naming `tools/nope.py`.' >> "$GT"
lint "$GD"; expect_ok R3_blockquote_and_prose_unscanned
add_item "$GT" '- a list item naming `tools/nope.py`'
lint "$GD"; expect_fail "R3_blockquote_and_prose_unscanned control"
[ "$(count ' tools/nope\.py$')" -eq 1 ] || fail "R3_blockquote_and_prose_unscanned control: the list item was not scanned ($(both))"
pass "R3_blockquote_and_prose_unscanned"

# The created set resolves a created path exactly and a path UNDER a created DIRECTORY —
# never a path that merely begins with a created FILE's name (review round 1, V02).
fresh r3cfile
clean_tasks; add_item "$GT" '- [ ] **T9** — Keep `tools/new.py.bak` beside it.'
[ ! -e "$R/tools/new.py.bak" ] || fail "R3_created_file_is_no_prefix: precondition: the fixture has tools/new.py.bak"
lint "$GD"; expect_fail R3_created_file_is_no_prefix
[ "$(count '^readiness-check: unresolved-')" -eq 1 ] && [ "$(count '^readiness-check: unresolved-path .*E01-F01\.tasks\.md:[0-9]+ tools/new\.py\.bak$')" -eq 1 ] \
  || fail "R3_created_file_is_no_prefix: a path that starts with the created FILE tools/new.py resolved through it ($(both))"
pass "R3_created_file_is_no_prefix"

# The feature-directory fallback is for a bare basename only: a slash path that exists only
# under the feature directory does not resolve (review round 1, V17).
fresh r3fdir
clean_tasks; mkdir -p "$GD/docs"; : > "$GD/docs/x.md"
[ ! -e "$R/docs/x.md" ] || fail "R3_feature_dir_fallback_bare_only: precondition: the fixture has docs/x.md at the root"
add_item "$GT" '- [ ] **T9** — Read `docs/x.md`.'
lint "$GD"; expect_fail R3_feature_dir_fallback_bare_only
[ "$(count '^readiness-check: unresolved-')" -eq 1 ] && [ "$(count '^readiness-check: unresolved-path .*E01-F01\.tasks\.md:[0-9]+ docs/x\.md$')" -eq 1 ] \
  || fail "R3_feature_dir_fallback_bare_only: a slash path resolved through the feature directory ($(both))"
pass "R3_feature_dir_fallback_bare_only"

# A created DIRECTORY named without its trailing slash resolves through the declaration
# (review round 1, V01).
fresh r3cdir
clean_tasks; add_item "$GT" '- [ ] **T9** — Fill `tests/fixtures/new` with the cases.'
[ ! -e "$R/tests/fixtures" ] || fail "R3_created_dir_without_slash: precondition: the fixture has tests/fixtures/"
lint "$GD"; expect_ok R3_created_dir_without_slash
pass "R3_created_dir_without_slash"

# Unit grammar: an item ends at a fence (the next unfenced line is no continuation, however
# indented) and continues only on a line indented by at least two spaces; a tests table's
# header row is no data row. The control proves the token is a finding once it IS in a unit
# (review round 1, V06, V41, V07).
fresh r3unit
clean_tasks; printf '%s\n' '- [ ] **T9** — An item.' '```' 'fenced' '```' '  `tools/nope.py` after the fence' >> "$GT"
lint "$GD"; expect_ok R3_item_ends_at_fence
pass "R3_item_ends_at_fence"
fresh r3unit
clean_tasks; printf '%s\n' '- [ ] **T9** — An item.' ' `tools/nope.py` one space in' >> "$GT"
lint "$GD"; expect_ok R3_continuation_needs_two_spaces
fresh r3unit
clean_tasks; printf '%s\n' '- [ ] **T9** — An item.' '  `tools/nope.py` two spaces in' >> "$GT"
lint "$GD"; expect_fail "R3_continuation_needs_two_spaces control"
[ "$(count '^readiness-check: unresolved-')" -eq 1 ] && [ "$(count 'E01-F01\.tasks\.md:[0-9]+ tools/nope\.py$')" -eq 1 ] \
  || fail "R3_continuation_needs_two_spaces control: a two-space continuation was not scanned ($(both))"
pass "R3_continuation_needs_two_spaces"
fresh r3thdr
printf '%s\n' '' '| `tools/nope.py` | Test |' '|---|---|' '| R9 | `tests/test_real.sh` |' >> "$GX"
lint "$GD"; expect_ok R3_tests_header_row_exempt
printf '%s\n' '| R9 | `tools/nope.py` |' >> "$GX"
_l="$(wc -l < "$GX" | tr -d ' ')"
lint "$GD"; expect_fail "R3_tests_header_row_exempt control"
[ "$(count '^readiness-check: unresolved-')" -eq 1 ] && [ "$(count "E01-F01\\.tests\\.md:$_l tools/nope\\.py\$")" -eq 1 ] \
  || fail "R3_tests_header_row_exempt control: the data row's tools/nope.py is not the one finding ($(both))"
pass "R3_tests_header_row_exempt"

# ── R4: ignore rules (each under a KNOWN root), trailing /, ./, the .harness/ remap ──────
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

# A `.harness/`-prefixed path's known root is the segment AFTER the prefix: in the source
# layout (no .harness/ directory) `.harness/tools/nope.py` is a reference under the known
# `tools/`, and it does not resolve (review round 1, V40).
fresh r4hnope
clean_tasks; add_item "$GT" '- [ ] **T9** — Run `.harness/tools/nope.py`.'
[ ! -e "$R/.harness" ] && [ -d "$R/tools" ] || fail "R4_harness_prefix_known_root_after_prefix: precondition: the layout is not the source layout"
lint "$GD"; expect_fail R4_harness_prefix_known_root_after_prefix
[ "$(count '^readiness-check: unresolved-')" -eq 1 ] && [ "$(count '^readiness-check: unresolved-path .*E01-F01\.tasks\.md:[0-9]+ \.harness/tools/nope\.py$')" -eq 1 ] \
  || fail "R4_harness_prefix_known_root_after_prefix: .harness/tools/nope.py was ignored as an unknown root ($(both))"
pass "R4_harness_prefix_known_root_after_prefix"

# A bare basename is a candidate only with a 1-5 character extension: a plan first cell
# `x.abcdef` is not a candidate; `x.abcde` is, and resolves nowhere (review round 1, V14).
fresh r4ext
printf '%s\n' '| `x.abcdef` | modify the scratch output | R1 |' > "$T/row.md"
insert_before "$GP" '| `README.md` |' "$T/row.md"
lint "$GD"; expect_ok R4_extension_at_most_five
sed 's/^| `x\.abcdef` |/| `x.abcde` |/' "$GP" > "$GP.new"; mv "$GP.new" "$GP"
lint "$GD"; expect_fail "R4_extension_at_most_five control"
[ "$(count '^readiness-check: unresolved-')" -eq 1 ] && [ "$(count 'E01-F01\.plan\.md:[0-9]+ x\.abcde$')" -eq 1 ] \
  || fail "R4_extension_at_most_five control: a five-character extension is not a candidate ($(both))"
pass "R4_extension_at_most_five"

# ── R5: symbols — `name()` in a single-path modify row, `path:name` anywhere ─────────────
fresh r5
_l="$(lno "$BP" '`gone()`')"; readme_says "E01-F02.plan.md:$_l"
lint "$BD"; expect_fail R5_symbol_missing_in_row
[ "$(count "^readiness-check: unresolved-symbol .*E01-F02\\.plan\\.md:$_l docs/NOTES\\.md:gone\$")" -eq 1 ] \
  || fail "R5_symbol_missing_in_row: no unresolved-symbol for gone() on the NOTES row ($(both))"
pass "R5_symbol_missing_in_row"
_l="$(lno "$BP" '`tools/real.py:nothere`')"; readme_says "E01-F02.plan.md:$_l"
[ "$(count "^readiness-check: unresolved-symbol .*E01-F02\\.plan\\.md:$_l tools/real\\.py:nothere\$")" -eq 1 ] \
  || fail "R5_path_colon_name_in_plan_cell: no unresolved-symbol for the Change cell's path:name ($(both))"
pass "R5_path_colon_name_in_plan_cell"
_l="$(lno "$BT" '`tools/real.py:absent`')"; readme_says "E01-F02.tasks.md:$_l"
[ "$(count "^readiness-check: unresolved-symbol .*E01-F02\\.tasks\\.md:$_l tools/real\\.py:absent\$")" -eq 1 ] \
  || fail "R5_path_colon_name_in_tasks_item: no unresolved-symbol for the tasks item's path:name ($(both))"
# The whole negative feature, finding for finding: nine lines and the summary.
[ "$(count '^readiness-check: unresolved-')" -eq 9 ] || fail "R5_path_colon_name_in_tasks_item: the negative feature does not give exactly its nine planted findings ($(both))"
fresh r5pos
grep -qF '`tools/real.py:other`' "$GT" || fail "R5_path_colon_name_in_tasks_item: precondition: the positive tasks lost tools/real.py:other"
lint "$GD"; expect_ok R5_path_colon_name_in_tasks_item
pass "R5_path_colon_name_in_tasks_item"

fresh r5present
grep -qF '| `tools/real.py` | modify: call `helper()` |' "$GP" || fail "R5_symbol_present_ok: precondition: the helper() row changed"
lint "$GD"; expect_ok R5_symbol_present_ok
sed 's/helper/helpme/g' "$R/tools/real.py" > "$R/tools/real.py.new"; mv "$R/tools/real.py.new" "$R/tools/real.py"
lint "$GD"; expect_fail R5_symbol_present_ok
[ "$(count '^readiness-check: unresolved-symbol .*E01-F01\.plan\.md:[0-9]+ tools/real\.py:helper$')" -eq 1 ] \
  || fail "R5_symbol_present_ok: a renamed def does not make helper() a finding ($(both))"
pass "R5_symbol_present_ok"

# An add row (an existing file) and a create row each name symbols an existing file lacks —
# `gone()` and the Change-cell form `tools/real.py:gone` — and neither is searched. The
# Change-cell form is what the create verb alone exempts (its own first cell is created, so
# form 1 is masked by the created set).
fresh r5add
set_cell "$GP" 'docs/NOTES.md' 'add a note that calls `gone()` per `tools/real.py:gone`'
grep -qF '| `docs/NOTES.md` | add a note that calls `gone()` per `tools/real.py:gone` |' "$GP" || fail "R5_create_add_row_skips_symbols: precondition: the add cell rewrite did not apply"
lint "$GD"; expect_ok "R5_create_add_row_skips_symbols (add)"
fresh r5create
set_cell "$GP" 'tools/new.py' 'create it beside `tools/real.py:gone`'
grep -qF '| `tools/new.py` | create it beside `tools/real.py:gone` |' "$GP" || fail "R5_create_add_row_skips_symbols: precondition: the create cell rewrite did not apply"
lint "$GD"; expect_ok "R5_create_add_row_skips_symbols (create)"
pass "R5_create_add_row_skips_symbols"

# A line reference is stripped before the symbol form; `:1x` is not an identifier, so it is
# no symbol either — the whole token is a path that does not resolve.
fresh r5line
grep -qF '`tools/real.py:12`' "$GT" && grep -qF '`tools/real.py:12-20`' "$GT" || fail "R5_line_ref_not_symbol: precondition: the line refs are gone"
lint "$GD"; expect_ok R5_line_ref_not_symbol
add_item "$GT" '- [ ] **T9** — See `tools/real.py:1x`.'
lint "$GD"; expect_fail R5_line_ref_not_symbol
[ "$(count '^readiness-check: unresolved-path .*E01-F01\.tasks\.md:[0-9]+ tools/real\.py:1x$')" -eq 1 ] \
  && [ "$(count 'unresolved-symbol')" -eq 0 ] \
  || fail "R5_line_ref_not_symbol: ':1x' was read as a symbol name ($(both))"
pass "R5_line_ref_not_symbol"

fresh r5args
set_cell "$GP" 'tools/real.py' 'modify: call `helper()` and `fence_delim($0)`'
grep -qF 'and `fence_delim($0)` |' "$GP" || fail "R5_call_with_args_not_symbol: precondition: the cell rewrite did not apply"
lint "$GD"; expect_ok R5_call_with_args_not_symbol
pass "R5_call_with_args_not_symbol"

fresh r5multi
grep -qF '| `tools/real.py`, `tests/test_real.sh` | modify both; names `nothere()`' "$GP" || fail "R5_multi_path_row_skips_symbols: precondition: the two-path row changed"
lint "$GD"; expect_ok R5_multi_path_row_skips_symbols
pass "R5_multi_path_row_skips_symbols"

fresh r5bin
set_cell "$GP" 'tools/real.py' 'modify: call `gone()`'
printf '\377' >> "$R/tools/real.py"
lint "$GD"; expect_ok R5_non_utf8_target_not_searched
pass "R5_non_utf8_target_not_searched"

# A created path that already exists (mid-feature) is never searched.
fresh r5created
: > "$R/tools/new.py"
add_item "$GT" '- [ ] **T9** — Wire `tools/new.py:anything`.'
lint "$GD"; expect_ok R5_symbol_on_created_path_skipped
pass "R5_symbol_on_created_path_skipped"

fresh r5unres
set_cell "$GP" 'docs/NOTES.md' 'modify per `tools/nope.py:x`'
grep -qF '| `docs/NOTES.md` | modify per `tools/nope.py:x` |' "$GP" || fail "R5_unresolved_path_colon_name_in_change_cell: precondition: rewrite did not apply"
lint "$GD"; expect_ok R5_unresolved_path_colon_name_in_change_cell
pass "R5_unresolved_path_colon_name_in_change_cell"

fresh r5word
set_cell "$GP" 'tools/real.py' 'modify: call `help()`'
grep -q 'helper' "$R/tools/real.py" || fail "R5_whole_word_only: precondition: real.py lost helper"
lint "$GD"; expect_fail R5_whole_word_only
[ "$(count '^readiness-check: unresolved-symbol .*E01-F01\.plan\.md:[0-9]+ tools/real\.py:help$')" -eq 1 ] \
  || fail "R5_whole_word_only: help() matched inside helper ($(both))"
pass "R5_whole_word_only"

# The whole-word match has a LEADING boundary too: `elper` is not found inside `helper`
# (review round 1, V34).
fresh r5lead
grep -q 'helper' "$R/tools/real.py" && ! grep -qE '(^|[^A-Za-z0-9_])elper([^A-Za-z0-9_]|$)' "$R/tools/real.py" \
  || fail "R5_whole_word_leading_boundary: precondition: real.py does not hold helper alone"
add_item "$GT" '- [ ] **T9** — Call `tools/real.py:elper`.'
lint "$GD"; expect_fail R5_whole_word_leading_boundary
[ "$(count '^readiness-check: unresolved-')" -eq 1 ] && [ "$(count '^readiness-check: unresolved-symbol .*E01-F01\.tasks\.md:[0-9]+ tools/real\.py:elper$')" -eq 1 ] \
  || fail "R5_whole_word_leading_boundary: elper matched inside helper ($(both))"
pass "R5_whole_word_leading_boundary"

# `path:name` is searched anywhere, a bare-basename path included (review round 1, V21).
fresh r5bsym
[ -f "$R/README.md" ] && ! grep -q 'nosuchsym' "$R/README.md" || fail "R5_bare_path_colon_name: precondition: README.md"
add_item "$GT" '- [ ] **T9** — See `README.md:nosuchsym`.'
lint "$GD"; expect_fail R5_bare_path_colon_name
[ "$(count '^readiness-check: unresolved-')" -eq 1 ] && [ "$(count '^readiness-check: unresolved-symbol .*E01-F01\.tasks\.md:[0-9]+ README\.md:nosuchsym$')" -eq 1 ] \
  || fail "R5_bare_path_colon_name: the bare path's symbol was not searched ($(both))"
pass "R5_bare_path_colon_name"

# An ignored path in a Change cell's `path:name` is no reference, even when it names an
# existing file: a run-time root and an absolute path (review round 1, V22).
fresh r5ign
mkdir -p "$R/scratchpad/E01-F01-builder"; printf 'x\n' > "$R/scratchpad/E01-F01-builder/log.md"
case "$R" in *[!A-Za-z0-9/._-]*) fail "R5_ignored_path_colon_name: precondition: \$R has a character a span would not carry: $R" ;; esac
set_cell "$GP" 'docs/NOTES.md' "modify per \`scratchpad/E01-F01-builder/log.md:zzqnot\` and \`$R/tools/real.py:zzqnot\`"
grep -qF "\`$R/tools/real.py:zzqnot\` |" "$GP" || fail "R5_ignored_path_colon_name: precondition: the cell rewrite did not apply"
lint "$GD"; expect_ok R5_ignored_path_colon_name
pass "R5_ignored_path_colon_name"

# ── R6: usage / input / internal errors ⇒ exit 2, `error:` + usage on stderr, stdout empty ─
fresh r6
run_tool; chk_exit2 R6_no_arg 'expected exactly one <feature-dir | feature.plan.md>'
run_tool "$GD" "$BD" --root "$R"; chk_exit2 R6_two_args 'expected exactly one <feature-dir | feature.plan.md>'
run_tool "$GD" --bogus; chk_exit2 R6_unknown_flag 'unknown flag: --bogus'
run_tool "$GD" --root; chk_exit2 R6_root_flag_no_value '--root needs a directory'
run_tool --grandfathered "$GP" --base; chk_exit2 R6_base_flag_no_value '--base needs a ref'
run_tool "$R/docs" --root "$R"; chk_exit2 R6_dir_without_plan "no *.plan.md in $R/docs"
cp "$GP" "$GD/second.plan.md"
run_tool "$GD" --root "$R"; chk_exit2 R6_dir_two_plans "2 *.plan.md files in $GD"
rm "$GD/second.plan.md"
run_tool "$T/nope.plan.md" --root "$R"; chk_exit2 R6_plan_missing "cannot read $T/nope.plan.md: no such file"
mkdir -p "$T/r6dir/x.plan.md"
run_tool "$T/r6dir" --root "$R"; chk_exit2 R6_plan_is_dir "cannot read $T/r6dir/x.plan.md: not a regular file"
run_tool "$T/r6dir/x.plan.md" --root "$R"; chk_exit2 R6_plan_is_dir "cannot read $T/r6dir/x.plan.md: not a regular file"
run_tool "$T/nope-dir" --root "$R"; chk_exit2 R6_positional_neither_dir_nor_plan "expected a feature directory or a *.plan.md: $T/nope-dir"
mkdir -p "$T/r6lock"; chmod 000 "$T/r6lock"
run_tool "$T/r6lock" --root "$R"; chmod 755 "$T/r6lock"; chk_exit2 R6_dir_unreadable "cannot read $T/r6lock: "
fresh r6bad8
printf '\377\n' >> "$GP"
lint "$GD"; chk_exit2 R6_plan_invalid_utf8 "cannot read $GP: "
fresh r6bad8t
printf '\377\n' >> "$GT"
lint "$GD"; chk_exit2 R6_tasks_invalid_utf8 "cannot read $GT: "
fresh r6root
run_tool "$GD" --root "$T/nope-root"; chk_exit2 R6_root_not_a_dir "--root is not a directory: $T/nope-root"
: > "$T/root-file"
run_tool "$GD" --root "$T/root-file"; chk_exit2 R6_root_not_a_dir "--root is not a directory: $T/root-file"
# No .git below the ceiling: the walk never reads the .git that sits ABOVE it.
rm -rf "$T/r6ceil"; mkdir -p "$T/r6ceil/.git" "$T/r6ceil/c/x"
cp "$GD/E01-F01.plan.md" "$T/r6ceil/c/x/"
set +e; GIT_CEILING_DIRECTORIES="$T/r6ceil/c" python3 "$TOOL" "$T/r6ceil/c/x" >"$T/out" 2>"$T/err"; rc=$?; set -e
chk_exit2 R6_no_git_ancestor_no_root "no ancestor of $T/r6ceil/c/x/E01-F01.plan.md holds .git; pass --root"
fresh r6out
run_tool "$GD" --bogus; [ ! -s "$T/out" ] || fail "R6_stdout_empty_on_error: unknown flag wrote to stdout ($(both))"
run_tool "$R/docs" --root "$R"; [ ! -s "$T/out" ] || fail "R6_stdout_empty_on_error: a dir without a plan wrote to stdout ($(both))"
[ -s "$T/err" ] || fail "R6_stdout_empty_on_error: a dir without a plan wrote nothing to stderr"
pass "R6_stdout_empty_on_error"

# A PRESENT sibling that is not a regular file — a directory, a dangling symlink — is exit 2,
# never `absent` with exit 0 (review round 1, V23).
fresh r6tdir; rm "$GT"; mkdir "$GT"
lint "$GD"; chk_exit2 "R6_tasks_not_regular (directory)" "cannot read $GT: not a regular file"
fresh r6tlink; rm "$GT"; ln -s "$GD/nowhere.tasks.md" "$GT"
[ -L "$GT" ] && [ ! -e "$GT" ] || fail "R6_tasks_not_regular: precondition: the tasks file is not a dangling symlink"
lint "$GD"; chk_exit2 "R6_tasks_not_regular (dangling symlink)" "cannot read $GT: "
fresh r6xdir; rm "$GX"; mkdir "$GX"
lint "$GD"; chk_exit2 "R6_tasks_not_regular (tests directory)" "cannot read $GX: not a regular file"

rm -rf "$T/dir with space"; mkdir -p "$T/dir with space/it's"; cp -R "$FX/repo" "$T/dir with space/it's/repo"
_q="$T/dir with space/it's/repo/specs/epics/E01-x/F01-good"
run_tool "$_q" --root "$T/dir with space/it's/repo"; expect_ok R6_argv_path_verbatim
grep -qF "readiness-check: ok $_q/E01-F01.plan.md: " "$T/out" || fail "R6_argv_path_verbatim: the ok line does not print the argv path verbatim ($(both))"
pass "R6_argv_path_verbatim"
fresh r6eq
run_tool "$GD" "--root=$R"; expect_ok R6_flag_equals_form
pass "R6_flag_equals_form"

for _h in -h --help; do
  run_tool "$_h"
  [ "$rc" -eq 0 ] || fail "R6_help_exit0: '$_h' rc $rc ($(both))"
  grep -q '^usage: ' "$T/out" || fail "R6_help_exit0: '$_h' printed no usage on stdout ($(both))"
  [ ! -s "$T/err" ] || fail "R6_help_exit0: '$_h' wrote to stderr ($(both))"
done
pass "R6_help_exit0"
run_tool "$GD" --root --help; chk_exit2 R6_help_as_value_is_not_help '--root is not a directory: --help'
grep -q '^usage: ' "$T/out" && fail "R6_help_as_value_is_not_help: '--root --help' printed the usage on stdout ($(both))"
run_tool --grandfathered "$GP" --base --help; chk_exit2 R6_help_as_value_is_not_help 'is not inside a git work tree'

# An unexpected exception is "the check did not run" (exit 2), never 1. stdout is a pipe with
# no reader (a FIFO opened read-write on fd 4 so the write open on fd 5 does not block, then
# fd 4 closed); > 16 KB of findings overflow the 8 KB buffer, so the BrokenPipeError lands
# INSIDE main(), not at exit-time flush (lesson 2026-10-27).
fresh r6pipe
{ printf '%s\n' '# p' '' '## Files to change' '' '| File | Change | R-id |' '|---|---|---|'
  _i=0; while [ "$_i" -lt 300 ]; do printf '| `tools/missing%d.py` | modify it | R1 |\n' "$_i"; _i=$((_i + 1)); done
} > "$GP"
lint "$GD"
[ "$rc" -eq 1 ] && [ "$(wc -c < "$T/out" | tr -d ' ')" -gt 16384 ] \
  || fail "R6_internal_error_exit2: precondition: the 300-row plan does not give exit 1 with > 16 KB of findings ($rc)"
mkfifo "$T/r6pipe/fifo"
exec 4<>"$T/r6pipe/fifo"; exec 5>"$T/r6pipe/fifo"; exec 4<&-
set +e; python3 "$TOOL" "$GD" --root "$R" >&5 2>"$T/err"; rc=$?; set -e
exec 5>&-
[ "$rc" -eq 2 ] || fail "R6_internal_error_exit2: a BrokenPipeError exited $rc, not 2 ($(tr '\n' '|' < "$T/err"))"
head -n 1 "$T/err" | grep -q '^readiness-check: error: internal: BrokenPipeError: ' \
  || fail "R6_internal_error_exit2: stderr's first line is not 'readiness-check: error: internal: BrokenPipeError: …' ($(tr '\n' '|' < "$T/err"))"
grep -q 'Traceback' "$T/err" && fail "R6_internal_error_exit2: a traceback reached stderr ($(tr '\n' '|' < "$T/err"))"
pass "R6_internal_error_exit2"

# ── R7: init.sh 2e — warn-only sweep, resolving against the PROJECT root ────────────────
# One fresh install (CODEX_HOME/HOME sandboxed). The target is a git work tree (hostile-config-
# proof git, lesson 2026-10-19); the fixture's project files sit at the TARGET root and each
# case plants one feature under the installed .harness/specs plus a one-feature board.
[ -n "${I:-}" ] || setup_target
_RDOK='✅ implementation readiness clean (1 feature(s) checked)'

init_case E01-F02 spec-ready true F02-bad; init_run; init_ok R7_init_warns_on_bad_feature
_l="$(lno "$IBP" '`tools/missing.py`')"
grep -qxF "⚠️  readiness: E01-F02 unresolved-path specs/epics/E01-x/F02-bad/E01-F02.plan.md:$_l tools/missing.py (+8 more; warn-only — Reviewer check 9 rejects)" "$T/out" \
  || fail "R7_init_warns_on_bad_feature: no whole warn line naming E01-F02, its first finding and the other 8 ($(both))"
grep -qF 'implementation readiness clean' "$T/out" && fail "R7_init_warns_on_bad_feature: the clean line printed beside a warning ($(both))"
grep -qF 'readiness: FAIL' "$T/out" && fail "R7_init_warns_on_bad_feature: the tool's FAIL summary leaked as a warning ($(both))"
pass "R7_init_warns_on_bad_feature"

init_case E01-F01 spec-ready true F01-good; init_run; init_ok R7_init_ok_on_good_feature
grep -qxF "$_RDOK" "$T/out" || fail "R7_init_ok_on_good_feature: no clean line counting 1 feature ($(both))"
grep -qF 'readiness:' "$T/out" && fail "R7_init_ok_on_good_feature: a warn line on a clean feature ($(both))"
pass "R7_init_ok_on_good_feature"
grep -qF '✅ plan citations and deferred ADRs clean (1 plan(s) checked)' "$T/out" \
  || fail "R7_init_2d_untouched: section 2d's clean line no longer prints ($(both))"
pass "R7_init_2d_untouched"

# The root is the TARGET (the plan's .git ancestor), not .harness/ (init.sh's cwd): a tasks
# item naming src/app.py resolves only against the project.
init_case E01-F01 spec-ready true F01-good
add_item "$IGT" '- [ ] **T9** — Wire `src/app.py`.'
mkdir -p "$T/tgt/src"; : > "$T/tgt/src/app.py"
init_run; init_ok R7_init_root_is_project_root
grep -qxF "$_RDOK" "$T/out" || fail "R7_init_root_is_project_root: src/app.py at the project root did not resolve ($(both))"
rm "$T/tgt/src/app.py"
init_run; init_ok R7_init_root_is_project_root
_l="$(lno "$IGT" '`src/app.py`')"
grep -qxF "⚠️  readiness: E01-F01 unresolved-path specs/epics/E01-x/F01-good/E01-F01.tasks.md:$_l src/app.py (+0 more; warn-only — Reviewer check 9 rejects)" "$T/out" \
  || fail "R7_init_root_is_project_root: a missing project file is not the warn line ($(both))"
pass "R7_init_root_is_project_root"

init_case E01-F01 spec-ready true F01-good
mv "$T/tgt/.git" "$T/tgt.git-away"
init_run; mv "$T/tgt.git-away" "$T/tgt/.git"; init_ok R7_init_no_git_did_not_run
grep -qxF '⚠️  readiness: E01-F01 check did not run: error: no ancestor of specs/epics/E01-x/F01-good/E01-F01.plan.md holds .git; pass --root (warn-only)' "$T/out" \
  || fail "R7_init_no_git_did_not_run: a target with no .git is not ONE whole 'did not run' line ($(both))"
grep -qF 'implementation readiness clean' "$T/out" && fail "R7_init_no_git_did_not_run: the clean line printed though the check did not run ($(both))"
pass "R7_init_no_git_did_not_run"

init_case E01-F02 spec-ready true F02-bad; rm "$IBP"; init_run; init_ok R7_init_exit2_reported_as_did_not_run
grep -qxF '⚠️  readiness: E01-F02 check did not run: error: no *.plan.md in specs/epics/E01-x/F02-bad/ (warn-only)' "$T/out" \
  || fail "R7_init_exit2_reported_as_did_not_run: an exit-2 lint is not ONE whole 'did not run' line ($(both))"
grep -qF 'implementation readiness clean' "$T/out" && fail "R7_init_exit2_reported_as_did_not_run: the clean line printed though the check did not run ($(both))"
pass "R7_init_exit2_reported_as_did_not_run"

for _st in in-review in-progress; do
  init_case E01-F02 "$_st" true F02-bad; init_run; init_ok "R7_init_in_review_swept[$_st]"
  grep -qF '⚠️  readiness: E01-F02 unresolved-path ' "$T/out" || fail "R7_init_in_review_swept: a '$_st' feature was not linted ($(both))"
done
for _st in done pending; do
  init_case E01-F02 "$_st" true F02-bad; init_run; init_ok "R7_init_in_review_swept[$_st]"
  grep -qF 'readiness: E01-F02' "$T/out" && fail "R7_init_in_review_swept: a '$_st' feature was linted ($(both))"
done
init_case E01-F02 spec-ready false F02-bad; init_run; init_ok R7_init_sdd_false_exempt
grep -qF 'readiness: E01-F02' "$T/out" && fail "R7_init_sdd_false_exempt: an sdd: false feature was linted ($(both))"
pass "R7_init_in_review_swept"
pass "R7_init_sdd_false_exempt"

init_case E01-F02 spec-ready true F02-bad; rm "$I/tools/readiness-check.py"; init_run; init_ok R7_init_silent_without_tool
grep -qF 'readiness' "$T/out" && fail "R7_init_silent_without_tool: 2e printed without the tool ($(both))"
pass "R7_init_silent_without_tool"
cp "$TOOL" "$I/tools/readiness-check.py"

# A warn-only lint never fails the gate, however much it prints: 2000 generated unresolved
# rows (past any pipe buffer) must not let a `printf | head` take SIGPIPE under pipefail.
init_case E01-F01 spec-ready true F01-good
awk 'BEGIN { for (i = 1; i <= 2000; i++) printf "| `tools/big%d.py` | modify it | R1 |\n", i }' > "$T/big.md"
insert_before "$IGP" '| `README.md` |' "$T/big.md"
[ "$(grep -c '^| `tools/big[0-9]*\.py` |' "$IGP")" -eq 2000 ] || fail "R7_init_large_output_never_fails: precondition: the 2000 rows were not inserted"
init_run; init_ok R7_init_large_output_never_fails
_l="$(lno "$IGP" '`tools/big1.py`')"
grep -qxF "⚠️  readiness: E01-F01 unresolved-path specs/epics/E01-x/F01-good/E01-F01.plan.md:$_l tools/big1.py (+1999 more; warn-only — Reviewer check 9 rejects)" "$T/out" \
  || fail "R7_init_large_output_never_fails: no whole warn line counting the other 1999 findings ($(both))"
pass "R7_init_large_output_never_fails"

# ── R8: --grandfathered — flag a plan written before THIS tool merged, else reject class ─
# The tool's date is its MERGE: the committer time of the first first-parent commit on the
# default branch touching tools/readiness-check.py or .harness/tools/readiness-check.py. The
# plan's date is the AUTHOR time of the earliest commit on HEAD that added it. Hermetic git:
# bounded discovery (GIT_CEILING_DIRECTORIES above), no host config, fixed dates.
# G1: main: base @1000; old.plan.md @1100; the tool @1500; new.plan.md @1600; one uncommitted.
G="$T/g1"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p s; echo x > s/old.plan.md; gq add s; gci 1100 1100 old
gq tag pre-tool
mkdir -p tools; echo v1 > tools/readiness-check.py; gq add tools; gci 1500 1500 tool
echo x > s/new.plan.md; gq add s; gci 1600 1600 new
echo v2 > tools/readiness-check.py; gq add tools; gci 1800 1800 tool-v2
echo x > s/dirty.plan.md
cd "$ROOT"
gf_run "$G" s/old.plan.md; gf_expect R8_flag_plan_older_than_merge 0 '^readiness-check: grandfather flag: s/old\.plan\.md authored 1100, before tool merged into main at 1500$'
gf_run "$G" s/new.plan.md; gf_expect R8_reject_plan_after_merge 1 '^readiness-check: grandfather reject: s/new\.plan\.md authored 1600, not before tool merged into main at 1500$'
gf_run "$G" s/dirty.plan.md; gf_expect R8_reject_uncommitted_plan 1 '^readiness-check: grandfather reject: s/dirty\.plan\.md has no commit on HEAD'
gf_run "$G" s/new.plan.md --base main; gf_expect R8_base_flag_equals_form 1 '^readiness-check: grandfather reject: .* main at 1500$'
gf_run "$G" s/new.plan.md --base=main; gf_expect R8_base_flag_equals_form 1 '^readiness-check: grandfather reject: .* main at 1500$'
gf_run "$G" s/new.plan.md --base nope; [ "$rc" -eq 2 ] || fail "R8_exit2_bad_base: rc $rc ($(both))"
grep -qF 'readiness-check: error: --base does not resolve: nope' "$T/err" || fail "R8_exit2_bad_base: wrong error ($(both))"
[ ! -s "$T/out" ] || fail "R8_exit2_bad_base: stdout not empty"; pass R8_exit2_bad_base
# origin/HEAD is asked first: point it at a remote-tracking ref that never saw the tool.
gq -C "$G" update-ref refs/remotes/origin/trunk "$(git -C "$G" rev-parse pre-tool)"
gq -C "$G" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
gf_run "$G" s/new.plan.md; gf_expect R8_flag_tool_not_on_base 0 '^readiness-check: grandfather flag: tool not on default branch origin/trunk yet$'
# G2: the tool reaches main only through a --no-ff merge. Its branch commit (@1100) is OLDER
# than the plan (@1200); the merge (@1300) is newer: the first-parent merge is the tool's date.
G="$T/g2"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
gq checkout -q -b tool; mkdir -p tools; echo v1 > tools/readiness-check.py; gq add tools; gci 1100 1100 tool
gq checkout -q main; mkdir -p s; echo x > s/p.plan.md; gq add s; gci 1200 1200 plan
GIT_AUTHOR_DATE="@1150 +0000" GIT_COMMITTER_DATE="@1300 +0000" gq merge -q --no-ff -m merge-tool tool || fail "fixture merge failed"
cd "$ROOT"
gf_run "$G" s/p.plan.md; gf_expect R8_merge_time_not_branch_time 0 '^readiness-check: grandfather flag: s/p\.plan\.md authored 1200, before tool merged into main at 1300$'
# G7: the plan exists ONLY on a rebased feature branch, authored @1100 before the tool merged
# @1500, committed @1600: the plan's date is read on HEAD, never on the base branch.
G="$T/g7"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p tools; echo v1 > tools/readiness-check.py; gq add tools; gci 1500 1500 tool
gq checkout -q -b feat; mkdir -p s; echo x > s/sib.plan.md; gq add s; gci 1100 1600 sibling-rebased
cd "$ROOT"
git -C "$G" log --format=%H main -- s/sib.plan.md | grep -q . && fail "R8_flag_sibling_plan_only_on_head: precondition: the plan reached main"
gf_run "$G" s/sib.plan.md --base main; gf_expect R8_flag_sibling_plan_only_on_head 0 '^readiness-check: grandfather flag: s/sib\.plan\.md authored 1100, before tool merged into main at 1500$'
# G8: the tool merges @1500, the plan is ADDED @1600, a later edit carries an older author
# date @900: only the ADD commit's author time counts.
G="$T/g8"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p tools; echo v1 > tools/readiness-check.py; gq add tools; gci 1500 1500 tool
mkdir -p s; echo x > s/late.plan.md; gq add s; gci 1600 1600 plan-added
echo y >> s/late.plan.md; gq add s; gci 900 1700 edit-with-older-author-date
cd "$ROOT"
gf_run "$G" s/late.plan.md --base main; gf_expect R8_reject_edit_with_older_author_date 1 '^readiness-check: grandfather reject: s/late\.plan\.md authored 1600, not before tool merged into main at 1500$'
# G9: author time, not commit time — the plan's add commit is AUTHORED a day before the
# tool's merge and COMMITTED an hour after it (a rebase moves only the committer date).
G="$T/g9"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p tools; echo v1 > tools/readiness-check.py; gq add tools; gci 100000 100000 tool
mkdir -p s; echo x > s/r.plan.md; gq add s; gci 13600 103600 rebased-plan
cd "$ROOT"
gf_run "$G" s/r.plan.md --base main; gf_expect R8_author_time_not_commit_time 0 '^readiness-check: grandfather flag: s/r\.plan\.md authored 13600, before tool merged into main at 100000$'
# G10: only the SIBLING lint (plan-cite-check) is on main, merged before the plan: this tool
# is not on the default branch, so the plan is flagged — keying on the sibling would reject.
G="$T/g10"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p tools; echo v1 > tools/plan-cite-check.py; gq add tools; gci 1500 1500 sibling-tool
mkdir -p s; echo x > s/n.plan.md; gq add s; gci 1600 1600 n
cd "$ROOT"
gf_run "$G" s/n.plan.md --base main; gf_expect R8_tool_paths_are_this_tools 0 '^readiness-check: grandfather flag: tool not on default branch main yet$'
# G3: installed-target layout — the tool lives at .harness/tools/readiness-check.py.
G="$T/g3"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p .harness/tools s; echo v1 > .harness/tools/readiness-check.py; gq add .harness; gci 1100 1100 upgrade
echo x > s/n.plan.md; gq add s; gci 1200 1200 new
cd "$ROOT"
gf_run "$G" s/n.plan.md; gf_expect R8_consumer_layout_rejects 1 '^readiness-check: grandfather reject: s/n\.plan\.md authored 1200, not before tool merged into main at 1100$'
# G4: the only branch is `trunkless`, no origin: no default branch resolves.
G="$T/g4"; mkdir -p "$G"; cd "$G"; gq init -q -b trunkless .; echo x > a.plan.md; gq add a.plan.md; gci 1000 1000 a; cd "$ROOT"
gf_run "$G" a.plan.md; [ "$rc" -eq 2 ] || fail "R8_exit2_no_default_branch: rc $rc ($(both))"
grep -qF -- '--base' "$T/err" || fail "R8_exit2_no_default_branch: the error does not name --base ($(both))"; pass R8_exit2_no_default_branch
mkdir -p "$T/nogit"; echo x > "$T/nogit/a.plan.md"
gf_run "$T/nogit" a.plan.md; [ "$rc" -eq 2 ] || fail "R8_exit2_outside_repo: rc $rc ($(both))"
grep -qF 'is not inside a git work tree' "$T/err" || fail "R8_exit2_outside_repo: wrong reason ($(both))"; pass R8_exit2_outside_repo

# G11: the plan is authored at the tool's merge second: "strictly older" fails, so reject
# (review round 1, V19).
G="$T/g11"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p tools; echo v1 > tools/readiness-check.py; gq add tools; gci 1500 1500 tool
mkdir -p s; echo x > s/eq.plan.md; gq add s; gci 1500 1600 plan-same-second
cd "$ROOT"
gf_run "$G" s/eq.plan.md --base main; gf_expect R8_equal_time_is_not_before 1 '^readiness-check: grandfather reject: s/eq\.plan\.md authored 1500, not before tool merged into main at 1500$'
# G12: added @1100 (before the merge @1500), deleted @1550, re-added @1600: the EARLIEST
# add on HEAD is the plan's date (review round 1, V20).
G="$T/g12"; mkdir -p "$G"; cd "$G"; gq init -q -b main .
echo base > README; gq add README; gci 1000 1000 base
mkdir -p s; echo x > s/re.plan.md; gq add s; gci 1100 1100 plan-added
mkdir -p tools; echo v1 > tools/readiness-check.py; gq add tools; gci 1500 1500 tool
gq rm -q s/re.plan.md; gci 1550 1550 plan-deleted
mkdir -p s; echo y > s/re.plan.md; gq add s; gci 1600 1600 plan-re-added
cd "$ROOT"
[ "$(git -C "$G" log --diff-filter=A --format=%at HEAD -- s/re.plan.md | wc -l | tr -d ' ')" -eq 2 ] \
  || fail "R8_earliest_add_counts: precondition: the plan does not have two add commits"
gf_run "$G" s/re.plan.md --base main; gf_expect R8_earliest_add_counts 0 '^readiness-check: grandfather flag: s/re\.plan\.md authored 1100, before tool merged into main at 1500$'

# ── R9: the Architect's step, Reviewer check 9 (reject), the doc-critic's advisory section ─
[ -n "${I:-}" ] || setup_target
_ar="$I/agents/architect.md"
_ah='## Implementation readiness — every named path resolves (E37-F01)'
[ "$(grep -cxF "$_ah" "$_ar")" -eq 1 ] || fail "R9_architect_section: the installed architect.md does not carry exactly one '$_ah' heading"
_um="$(lineno "$_ar" '## Umbrella mode')"; _as="$(lineno "$_ar" "$_ah")"; _dc="$(lineno "$_ar" '## Doc-critic checkpoint')"
[ "$_um" -gt 0 ] && [ "$_as" -gt "$_um" ] && [ "$_dc" -gt "$_as" ] \
  || fail "R9_architect_section: the section is not between '## Umbrella mode' and '## Doc-critic checkpoint' (umbrella=$_um section=$_as critic=$_dc)"
slice "$_ar" "$_ah" > "$T/ar.txt"
has R9_architect_section "$T/ar.txt" 'Run `python3 "$HARNESS_DIR/tools/readiness-check.py" <feature-dir>` before the doc-critic checkpoint; it must exit 0 — the Reviewer rejects on exit 1 (check 9).'
has R9_architect_section "$T/ar.txt" 'Declare every file the feature creates with `create` as the first word of its `## Files to change` Change cell; tasks and tests references to a created path, or to a path under a created directory, resolve through that declaration.'
has R9_architect_section "$T/ar.txt" 'Exit 2 means the check did not run: fix the invocation and run it again.'
has R9_architect_section "$T/ar.txt" 'Write a path that is not in this repository (a fixture-internal path, a consumer'"'"'s file) with a placeholder prefix (`<repo>/tools/x.py`) or inside fenced code.'
pass "R9_architect_section"

slice "$I/agents/reviewer.md" '## What you check' > "$T/rv.txt"
[ -s "$T/rv.txt" ] || fail "R9_reviewer_check9: '## What you check' not found in the installed reviewer.md"
item "$T/rv.txt" 9 > "$T/rv9.txt"
[ -s "$T/rv9.txt" ] || fail "R9_reviewer_check9: no numbered item 9 inside '## What you check'"
_l8="$(grep -n '^8\. ' "$T/rv.txt" | cut -d: -f1)"; _l9="$(grep -n '^9\. ' "$T/rv.txt" | cut -d: -f1)"
[ -n "$_l8" ] && [ -n "$_l9" ] && [ "$_l9" -gt "$_l8" ] || fail "R9_reviewer_check9: item 9 does not follow item 8"
has R9_reviewer_check9 "$T/rv9.txt" '9. **Implementation readiness (E37-F01).** For an `sdd: true` feature, run `python3 "$HARNESS_DIR/tools/readiness-check.py" "<dir>"`'
has R9_reviewer_check9 "$T/rv9.txt" '`.harness/tools/readiness-check.py` in an installed target'
hasre R9_reviewer_check9 "$T/rv9.txt" 'Exit 1 \(an `unresolved-path` or `unresolved-symbol` finding\)[^.]{0,80}reject, quoting'
hasre R9_reviewer_check9 "$T/rv9.txt" 'Exit 2 means the check did not run[^.]{0,100}never approve on an unrun check'
hasre R9_reviewer_check9 "$T/rv9.txt" 'the `--grandfathered` mode decides: exit 0 → flag[^.]{0,200}exit 1 → reject, exit 2 → flag'
has R9_reviewer_check9 "$T/rv9.txt" 'Run it as `python3 "$HARNESS_DIR/tools/readiness-check.py" --grandfathered "<dir>/<feature>.plan.md"` after `git fetch origin`.'
has R9_reviewer_check9 "$T/rv9.txt" 'A plan written before this tool merged is flagged, not rejected.'
has R9_reviewer_check9 "$T/rv9.txt" 'This check judges resolution only — whether a resolving path is the right one stays check 5 and the doc-critic'"'"'s judgment.'
has R9_reviewer_check9 "$T/rv9.txt" '`sdd: false` items are exempt (they have no `.plan.md`).'
has R9_reviewer_check9 "$T/rv9.txt" 'Checks 2, 7 and 8 are unchanged.'
folded "$T/rv9.txt" | grep -qiE 'exit 2[^.]{0,30}(→|⇒|=) ?(approve|approval|pass)' \
  && fail "R9_reviewer_check9: item 9 lets an exit 2 (a check that did not run) approve"
pass "R9_reviewer_check9"

item "$T/rv.txt" 8 > "$T/rv8.txt"
has R9_reviewer_item8_intact "$T/rv8.txt" '`python3 "$HARNESS_DIR/tools/plan-cite-check.py" "<dir>/<feature>.plan.md" --spec "<dir>/<feature>.spec.md"`'
has R9_reviewer_item8_intact "$T/rv8.txt" 'Checks 2 and 7 are unchanged.'
grep -qF 'readiness-check' "$T/rv8.txt" && fail "R9_reviewer_item8_intact: item 8 names readiness-check — item 9 was merged into it"
pass "R9_reviewer_item8_intact"
# Structure: items 1-9 each exactly once and in order inside `## What you check`, and every
# `## ` heading of the installed reviewer.md exactly once — an insertion that duplicates a
# span (item 9 twice, a stray `## ADR-citation check` fragment) passes every slice above,
# because a slice reads the first occurrence only.
[ "$(grep -E '^[0-9]+\. ' "$T/rv.txt" | cut -d. -f1 | tr '\n' ' ')" = '1 2 3 4 5 6 7 8 9 ' ] \
  || fail "R9_reviewer_structure: '## What you check' does not number its items 1-9 once each, in order ($(grep -E '^[0-9]+\. ' "$T/rv.txt" | cut -d. -f1 | tr '\n' ' '))"
_dup="$(grep '^## ' "$I/agents/reviewer.md" | sort | uniq -d)"
[ -z "$_dup" ] || fail "R9_reviewer_structure: duplicated headings in the installed reviewer.md: $_dup"
[ "$(grep -c '^## ADR-citation check' "$I/agents/reviewer.md")" -eq 1 ] \
  || fail "R9_reviewer_structure: more than one heading starts '## ADR-citation check' in the installed reviewer.md"
pass "R9_reviewer_structure"

_dcf="$I/agents/doc-critic.md"
_dh='## Implementation readiness (E37-F01)'
[ "$(grep -cxF "$_dh" "$_dcf")" -eq 1 ] || fail "R9_doc_critic_section: the installed doc-critic.md does not carry exactly one '$_dh' heading"
_e4="$(lineno "$_dcf" '## Plan-row citations and stage-aware NFRs (E36-F04)')"; _ds="$(lineno "$_dcf" "$_dh")"; _ed="$(lineno "$_dcf" '## Epic-decomposition checks')"
[ "$_e4" -gt 0 ] && [ "$_ds" -gt "$_e4" ] && [ "$_ed" -gt "$_ds" ] \
  || fail "R9_doc_critic_section: the section is not after the E36-F04 section and before '## Epic-decomposition checks' (e36f04=$_e4 section=$_ds epic=$_ed)"
slice "$_dcf" "$_dh" > "$T/dcr.txt"
has R9_doc_critic_section "$T/dcr.txt" 'At `target-type=feature-spec`, also run the implementation-readiness lint on the feature directory: `python3 "$HARNESS_DIR/tools/readiness-check.py" <feature-dir>`'
hasre R9_doc_critic_section "$T/dcr.txt" 'readiness-check\.py[^.]{0,120}report each line it prints as an advisory finding'
has R9_doc_critic_section "$T/dcr.txt" 'an exit 2 is recorded as the finding "readiness lint did not run: <stderr>".'
has R9_doc_critic_section "$T/dcr.txt" 'These findings are advisory like every other finding: you never block the Architect'
grep -qF 'never block' "$_dcf" || fail "R9_doc_critic_section: the role's never-block rule is gone"
pass "R9_doc_critic_section"
has R9_doc_critic_no_shell_fallback "$T/dcr.txt" 'If your host gives you no shell tool, the lint does not run: record the finding "implementation-readiness lint did not run: no shell tool" in your note, and never judge the plan'"'"'s references resolved by reading them — the Reviewer'"'"'s check 9 stays the gate.'
folded "$T/dcr.txt" | grep -qiE '(may|can|should|free to)[^.]{0,80}(reference|path|plan)[^.]{0,60}resolve' \
  && fail "R9_doc_critic_no_shell_fallback: the section lets the critic declare the references resolved without the lint"
pass "R9_doc_critic_no_shell_fallback"

# ── R10: the deliberate copies stay in step with their originals (parity, not trust) ────
# Fence parity: tests/test_tasks_pairs.sh's edge corpus, verbatim — each segment exists for
# one clause (closer length · closer char · closer info string · backtick-in-info opener ·
# run >= 3 · indent 0-3 · trailing blanks on a closer).
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
[ "$(grep -c '^P[0-9]* ' "$T/fence-corpus.md")" -eq 20 ] || fail "R10_fence_parity: precondition: the corpus does not hold its 20 segments"
awk "$FENCE_AWK"'fence_delim($0) { next } !fence' "$T/fence-corpus.md" > "$T/fence-awk.out"
python3 - "$TOOL" "$T/fence-corpus.md" > "$T/fence-py.out" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("readiness_check", sys.argv[1])
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
  || fail "R10_fence_parity: fence.awk reads the corpus differently than the suite expects: $(diff "$T/fence-want.out" "$T/fence-awk.out" | tr '\n' '|')"
cmp -s "$T/fence-awk.out" "$T/fence-py.out" \
  || fail "R10_fence_parity: readiness-check's iter_unfenced() diverges from tests/lib/fence.awk: $(diff "$T/fence-awk.out" "$T/fence-py.out" | tr '\n' '|')"
pass "R10_fence_parity"

# Table-grammar parity: both modules' parse_sections() on plan-cite's positive plan yield the
# same `## Files to change` data-row line numbers (its `### sub-heading` row included).
python3 - "$ROOT/tools/plan-cite-check.py" "$TOOL" "$ROOT/tests/fixtures/plan-cite/specs/epics/E01-x/F01-good/E01-F01.plan.md" <<'PY' \
  || fail "R10_table_grammar_parity: see the message above"
import importlib.util, sys
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod
def rows(mod, plan):
    return [n for sec in mod.parse_sections(mod._read(plan)) if sec["name"] == "Files to change"
            for table in sec["tables"] for n, _t, kind in table if kind == "data"]
pc, rc = load("plan_cite_check", sys.argv[1]), load("readiness_check", sys.argv[2])
a, b = rows(pc, sys.argv[3]), rows(rc, sys.argv[3])
if len(a) < 5:
    sys.exit("precondition: plan-cite's positive plan has only %d Files to change rows" % len(a))
if a != b:
    sys.exit("parse_sections() diverges: plan-cite-check %r, readiness-check %r" % (a, b))
PY
pass "R10_table_grammar_parity"

# ── R11: SPEC-FORMAT's schema section, WORKFLOW's paragraph, README's sentence ─────────
[ -n "${I:-}" ] || setup_target
_sf="$I/docs/SPEC-FORMAT.md"
_sh='## Implementation readiness — every named path resolves'
grep -qxF "$_sh" "$_sf" || fail "R11_spec_format_section: no '$_sh' heading in the installed SPEC-FORMAT.md"
_aa="$(lineno "$_sf" '## Architecture alignment')"; _ss="$(lineno "$_sf" "$_sh")"; _fm="$(lineno "$_sf" '## Frontmatter')"
[ "$_aa" -gt 0 ] && [ "$_ss" -gt "$_aa" ] && [ "$_fm" -gt "$_ss" ] \
  || fail "R11_spec_format_section: the section is not between '## Architecture alignment' and '## Frontmatter' (alignment=$_aa section=$_ss frontmatter=$_fm)"
span "$_sf" "$_sh" '## Frontmatter' "$T/sf.sec"
has R11_spec_format_section "$T/sf.sec" 'A reference is the text of a single-backtick span with no whitespace'
has R11_spec_format_section "$T/sf.sec" 'A file the feature creates is declared with `create` as the first word of the row'"'"'s Change cell'
has R11_spec_format_section "$T/sf.sec" 'An unrecognised token is ignored, never flagged'
has R11_spec_format_section "$T/sf.sec" 'Write a path that is not in this repository (a fixture-internal path, a consumer'"'"'s file) with a placeholder prefix'
has R11_spec_format_section "$T/sf.sec" '`tools/readiness-check.py <feature-dir>` (E37-F01) turns this into an exit code (0 ok, 1 finding, 2 usage/input error); the Reviewer'"'"'s check 9 rejects on exit 1. This section is the schema it lints.'
# The plan-row grammar section above is untouched: the installed copy of the span from its
# heading to `## Architecture alignment` equals the source's, and the new section is not in it.
span "$ROOT/docs/SPEC-FORMAT.md" '## Plan rows cite an R-id or an ADR' '## Architecture alignment' "$T/pr-src.sec"
span "$_sf" '## Plan rows cite an R-id or an ADR' '## Architecture alignment' "$T/pr-inst.sec"
[ "$(wc -l < "$T/pr-src.sec" | tr -d ' ')" -ge 40 ] || fail "R11_spec_format_section: precondition: the plan-row grammar span is implausibly short"
cmp -s "$T/pr-src.sec" "$T/pr-inst.sec" || fail "R11_spec_format_section: the installed plan-row grammar span differs from the source"
grep -qF 'readiness-check' "$T/pr-inst.sec" && fail "R11_spec_format_section: the plan-row grammar section now names readiness-check"
pass "R11_spec_format_section"

span "$I/docs/WORKFLOW.md" '## Doc-critic checkpoints' '## Drift check on epic rollup' "$T/wf.sec"
has R11_workflow_paragraph "$T/wf.sec" 'Beside the critic at the `feature-spec` checkpoint sits the implementation-readiness lint (E37-F01): the Architect runs `tools/readiness-check.py <feature-dir>` before hand-off and it must exit 0,'
has R11_workflow_paragraph "$T/wf.sec" 'the doc-critic reports its lines as advisory findings,'
has R11_workflow_paragraph "$T/wf.sec" 'the Reviewer rejects on exit 1 (check 9; a plan written before the tool merged is flagged, not rejected),'
has R11_workflow_paragraph "$T/wf.sec" 'and `init.sh` sweeps every in-flight feature warn-only at session start (section 2e).'
pass "R11_workflow_paragraph"

span "$ROOT/README.md" '## How it works' '## Quick start' "$T/rm.sec"
has R11_readme_sentence "$T/rm.sec" 'Three deterministic spec lints gate a feature before the Builder sees it — `tools/tasks-pair-check.py` (red/green pair shape, ADR-0008), `tools/plan-cite-check.py` (every plan row cites an R-id or an ADR, ADR-0009) and `tools/readiness-check.py` (every path and symbol the plan, tasks and tests name resolves or is declared created, E37-F01); each exits 0/1/2 and the Reviewer rejects on exit 1.'
pass "R11_readme_sentence"

# ── R12: VERSION ↔ newest CHANGELOG heading (read at runtime, no literal); ledger row C11 ─
_v="$(cat "$ROOT/VERSION")"
[ -n "$_v" ] || fail "R12_version_changelog_ledger: VERSION is empty"
_head="$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" || true)"
case "$_head" in "## [$_v]"*) ;; *) fail "R12_version_changelog_ledger: newest CHANGELOG heading '$_head' != VERSION '$_v'" ;; esac
# historical anchor: SOME release section names E37-F01 and readiness-check, so a later
# release prepended above stays green
awk '/^## \[/ { if (sec ~ /E37-F01/ && sec ~ /readiness-check/) ok = 1; sec = ""; next } { sec = sec "\n" $0 }
     END { if (sec ~ /E37-F01/ && sec ~ /readiness-check/) ok = 1; exit ok ? 0 : 1 }' "$ROOT/CHANGELOG.md" \
  || fail "R12_version_changelog_ledger: no CHANGELOG section names both E37-F01 and readiness-check"
slice "$ROOT/docs/RATIONALE.md" '## Deletion ledger' > "$T/led.txt"
_c11="$(grep -E '^\| C11 — Implementation-readiness lint \| Capability compensation \|' "$T/led.txt" || true)"
[ -n "$_c11" ] || fail "R12_version_changelog_ledger: no '| C11 — Implementation-readiness lint | Capability compensation |' row in the Deletion ledger"
# the evidence cell (the 4th) states the ablation condition, not just a token
printf '%s\n' "$_c11" | awk -F'|' '{ print $5 }' | grep -qE 'Ablation[^|]*unresolved-path[^|]*Retain while' \
  || fail "R12_version_changelog_ledger: the C11 evidence cell does not state the ablation condition (Ablation … unresolved-path … Retain while)"
printf '%s\n' "$_c11" | grep -qF '[`tools/readiness-check.py`](../tools/readiness-check.py)' \
  || fail "R12_version_changelog_ledger: the C11 row does not point at tools/readiness-check.py"
pass "R12_version_changelog_ledger"

echo "all readiness-check checks passed"
