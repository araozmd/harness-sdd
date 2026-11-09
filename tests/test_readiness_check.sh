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

echo "all readiness-check checks passed"
