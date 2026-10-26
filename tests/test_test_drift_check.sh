#!/bin/sh
# test_test_drift_check.sh — E36-F06: the Reviewer's test-assertion drift check.
#
# Behavioral: every case builds its OWN throwaway git repo under mktemp (never a copy of this
# repo) and drives tools/test-drift-check.sh against a known diff. Each fixture changes ONE
# thing, so only the code path under test can produce the expected line: a weakened-assertion
# fixture keeps every test name intact (else test-removed alone would redden it) and a
# deleted-test fixture deletes a body with no assertion-pattern line (else assert-removed
# alone would). Exit codes 0/1/2/3 are the tool's own documented contract and are asserted
# exactly. Exit-2 fixtures always pass a VALID base ref so only the flag under test can
# produce the 2.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never diff a DO-NOT-TOUCH file against main; never mutate the live state/.
# Any case that runs harness-install.sh sandboxes HOME and CODEX_HOME.
#
# Zero deps: POSIX sh + git + awk.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/tools/test-drift-check.sh"
CS="$ROOT/tools/change-size.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t tdrift)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)
# A "not inside a git repo" fixture is only hermetic if git discovery is bounded.
GIT_CEILING_DIRECTORIES="$T"; export GIT_CEILING_DIRECTORIES
unset HARNESS_DIR 2>/dev/null || true

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v git >/dev/null 2>&1 || { echo "skip - git unavailable"; exit 0; }

# ── fixtures ─────────────────────────────────────────────────────────────────────
# newrepo <name> — sets R: a repo on `main` with a seed commit. Callers write base files,
# `basecommit`, then `feature` (branch) and make the change under test.
newrepo() {
  R="$T/$1"; mkdir -p "$R"
  git -C "$R" init -q
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name T
  git -C "$R" checkout -q -b main
  printf 'seed\n' > "$R/seed.txt"
  git -C "$R" add -A && git -C "$R" commit -qm seed
}
basecommit() { git -C "$R" add -A && git -C "$R" commit -qm base; }
feature()    { git -C "$R" checkout -q -b feature; }
featcommit() { git -C "$R" add -A && git -C "$R" commit -qm feat; }

# put <path> — write stdin to $R/<path>
put() { mkdir -p "$(dirname "$R/$1")"; cat > "$R/$1"; }
# subst <path> <exact old line> <new line> — replace one whole line
subst() {
  OLD="$2" NEW="$3" awk '$0 == ENVIRON["OLD"] { print ENVIRON["NEW"]; next } { print }' "$R/$1" > "$R/$1.new" \
    && mv "$R/$1.new" "$R/$1"
}
# delline <path> <exact line> — delete one whole line
delline() {
  OLD="$2" awk '$0 == ENVIRON["OLD"] { next } { print }' "$R/$1" > "$R/$1.new" && mv "$R/$1.new" "$R/$1"
}

js_app() { # the standard JS fixture
  put "$1" <<'EOF'
const run = require('./run');
it('keeps name', () => {
  expect(run(1)).toBe(1);
  run(2);
});
it('other', () => {
  run(3);
});
EOF
}

# run <dir> args... — sets rc, and captures stdout to $T/out and stderr to $T/err
run() {
  _rd="$1"; shift
  ( cd "$_rd" && sh "$TOOL" "$@" ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
}
cnt() { grep -Ec "$1" "$T/out" || true; }          # count stdout lines matching an ERE
nlines() { wc -l < "$T/out" | tr -d ' '; }
expect_rc() { # expect_rc <want> <label>
  [ "$rc" = "$1" ] || { echo "--- stdout" >&2; cat "$T/out" >&2; echo "--- stderr" >&2; cat "$T/err" >&2; fail "$2: exit $rc, want $1"; }
}
expect_ndrift() { # expect_ndrift <n> <label> — exactly n DRIFT lines
  [ "$(cnt '^DRIFT ')" = "$1" ] || { cat "$T/out" >&2; fail "$2: want $1 DRIFT lines, got $(cnt '^DRIFT ')"; }
}
expect_line() { # expect_line <ERE> <label>
  grep -Eq "$1" "$T/out" || { cat "$T/out" >&2; fail "$2: no stdout line matches $1"; }
}

# ── R2: the sibling change-size.sh answers the classifier / list queries ─────────
newrepo r2a
mkdir -p "$R/.harness"
printf 'change_size:\n  test_paths:\n    - "(^|/)checks/"\n' > "$R/.harness/harness.config.yaml"
( cd "$T" && sh "$CS" --print-test-re --repo "$R" ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
expect_rc 0 "R2a"
[ "$(nlines)" = 1 ] || fail "R2a: --print-test-re must print exactly one line"
grep -qF '(^|/)tests?/' "$T/out" || fail "R2a: built-in TEST_RE missing from --print-test-re"
grep -qF '(^|/)checks/' "$T/out" || fail "R2a: configured test_paths entry missing from --print-test-re"
pass "R2a_print_test_re"

newrepo r2b
mkdir -p "$R/.harness"
printf 'change_size:\n  assert_patterns:\n    - "verify[(]"\n    - "custom check[(]"\n' > "$R/.harness/harness.config.yaml"
( cd "$T" && sh "$CS" --print-list assert_patterns --repo "$R" ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
expect_rc 0 "R2b"
printf 'verify[(]\ncustom check[(]\n' > "$T/want"
cmp -s "$T/out" "$T/want" || { cat "$T/out" >&2; fail "R2b: --print-list must print exactly the two configured entries, one per line"; }
printf 'change_size:\n  assert_patterns: []      # nothing\n' > "$R/.harness/harness.config.yaml"
( cd "$T" && sh "$CS" --print-list assert_patterns --repo "$R" ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
expect_rc 0 "R2b empty list"; [ ! -s "$T/out" ] || fail "R2b: an empty list must print nothing"
printf 'models:\n  x: 1\n' > "$R/.harness/harness.config.yaml"
( cd "$T" && sh "$CS" --print-list assert_patterns --repo "$R" ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
expect_rc 0 "R2b absent block"; [ ! -s "$T/out" ] || fail "R2b: an absent change_size block must print nothing"
( cd "$T" && sh "$CS" --print-test-re --base main --repo "$R" ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
expect_rc 4 "R2b print mode combined with --base is a usage error"
pass "R2b_print_list"

# ── R9: exit codes ───────────────────────────────────────────────────────────────
newrepo r9; js_app tests/app.test.js; basecommit; feature
run "$R"
expect_rc 2 "R9a no args"; [ -s "$T/err" ] || fail "R9a: exit 2 needs a stderr reason"
run "$R" main --tests-md x
expect_rc 2 "R9a --tests-md is not a flag"; [ -s "$T/err" ] || fail "R9a: unknown flag needs a stderr reason"
grep -qF 'unknown flag: --tests-md' "$T/err" || fail "R9a: --tests-md x must be rejected as an unknown flag"
# Each usage branch gets the minimal argv only IT can reject (round 3, N15/N14): with no value
# after it, a dropped unknown-flag case would read the flag as a head ref (exit 3), and a
# third positional reaches only the too-many-arguments branch.
for _flag in --bogus --tests-md; do
  run "$R" main "$_flag"
  expect_rc 2 "R9a main $_flag"
  grep -qF "unknown flag: $_flag" "$T/err" || fail "R9a: main $_flag must be rejected as an unknown flag"
done
run "$R" main feature extra
expect_rc 2 "R9a a third positional argument"
grep -qF 'too many arguments: extra' "$T/err" || fail "R9a: a third positional must be rejected as too many arguments"
run "$R" main --tasks-md /nonexistent/tasks.md
expect_rc 2 "R9a --tasks-md without a readable file"; [ -s "$T/err" ] || fail "R9a: missing tasks file needs a stderr reason"
[ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] || fail "R9a: the stderr reason must be one line"
grep -qF 'not a readable file' "$T/err" || fail "R9a: a missing --tasks-md file is named as not readable"
# Every remaining usage branch, each pinned by the REASON only it prints (round 3): exit 2
# alone has several producers (dash's own unbound-parameter error among them).
run "$R" main --tasks-md
expect_rc 2 "R9a --tasks-md without a value"
grep -qF -- '--tasks-md needs a file' "$T/err" || fail "R9a: --tasks-md with no value must say it needs a file"
for _flag in -h --help; do
  run "$R" main "$_flag"
  expect_rc 2 "R9a $_flag"
  grep -qF 'usage: test-drift-check.sh <base-ref>' "$T/err" || fail "R9a: $_flag must print the usage line"
done
mkdir -p "$T/adir"
run "$R" main --tasks-md "$T/adir"
expect_rc 2 "R9a --tasks-md names a directory"
grep -qF 'not a readable file' "$T/err" || fail "R9a: a directory is not a readable --tasks-md file"
printf 'x\n' > "$T/unreadable.md"; chmod 000 "$T/unreadable.md"
if [ ! -r "$T/unreadable.md" ]; then  # running as root reads anything; the row needs a non-root user
  run "$R" main --tasks-md "$T/unreadable.md"
  expect_rc 2 "R9a --tasks-md not readable"
  grep -qF 'not a readable file' "$T/err" || fail "R9a: an unreadable --tasks-md file is rejected by name"
fi
chmod 644 "$T/unreadable.md"
pass "R9a_exit2_usage"

run "$R" no-such-ref
expect_rc 3 "R9b unresolvable base"; [ -s "$T/err" ] || fail "R9b: exit 3 needs a stderr reason"
grep -qF 'base ref does not resolve: no-such-ref' "$T/err" || fail "R9b: an unresolvable base is named"
run "$R" main no-such-head
expect_rc 3 "R9b unresolvable head"
grep -qF 'head ref does not resolve: no-such-head' "$T/err" || fail "R9b: an unresolvable head is named"
mkdir -p "$T/notrepo"
run "$T/notrepo" main
expect_rc 3 "R9b not a git repository"; [ -s "$T/err" ] || fail "R9b: exit 3 needs a stderr reason"
grep -qF 'not a git repository' "$T/err" || fail "R9b: outside a repository the reason says so"
git -C "$R" checkout -q --orphan island
run "$R" main
expect_rc 3 "R9b unborn HEAD"
grep -qF 'HEAD does not resolve' "$T/err" || fail "R9b: an unborn HEAD in working-tree mode is named"
git -C "$R" rm -rfq . 2>/dev/null || true
git -C "$R" commit -q --allow-empty -m island
run "$R" main island
expect_rc 3 "R9b no merge base"; [ -s "$T/err" ] || fail "R9b: exit 3 needs a stderr reason"
pass "R9b_exit3_cannot_diff"

# ── R8: a clean run is one summary line and nothing on stderr ────────────────────
newrepo r8a; put src/app.js <<'EOF'
function f() { return 1; }
EOF
js_app tests/app.test.js; basecommit; feature
put src/app.js <<'EOF'
function f() { return 2; }
EOF
featcommit
run "$R" main
expect_rc 0 "R8a"; [ "$(nlines)" = 1 ] || { cat "$T/out" >&2; fail "R8a: want exactly one stdout line"; }
expect_line '^test-drift-check: 0 findings, 0 waived, 0 test files examined \(base [0-9a-f]+\)$' "R8a summary"
[ ! -s "$T/err" ] || fail "R8a: stderr must be empty"
# The summary names the merge base by its SHORT sha, and the run leaves no temp dir behind.
expect_line "\\(base $(git -C "$R" rev-parse --short main)\\)\$" "R8a summary names the short merge-base sha"
# Location-free leak check: the macOS mktemp -d here ignores TMPDIR, so look in the root mktemp
# really uses for the copy of a waiver whose token only this process wrote (concurrency-safe).
_probe="$(mktemp -d)"; _troot="$(dirname "$_probe")"; rmdir "$_probe"
printf 'waive-test-drift: tmpprobe-%s \342\200\224 cleanup probe\n' "$$" > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 0 "R8a cleanup probe run"
[ -z "$(grep -l "tmpprobe-$$" "$_troot"/*/waivers 2>/dev/null || true)" ] \
  || fail "R8a: the tool must remove its temp dir on exit (a waivers copy survived under $_troot)"
pass "R8a_no_test_change"

newrepo r8b; js_app tests/app.test.js; basecommit; feature
put tests/new.test.js <<'EOF'
it('brand new', () => {
  expect(1).toBe(1);
});
EOF
put tests/app.test.js <<'EOF'
const run = require('./run');
it('keeps name', () => {
  expect(run(1)).toBe(1);
  expect(run(2)).toBe(2);
  run(2);
});
it('other', () => {
  run(3);
});
it('added later', () => {
  expect(run(4)).toBe(4);
});
EOF
featcommit
run "$R" main
expect_rc 0 "R8b"; [ "$(nlines)" = 1 ] || { cat "$T/out" >&2; fail "R8b: pure additions must print only the summary"; }
expect_line '^test-drift-check: 0 findings, 0 waived, 2 test files examined ' "R8b summary"
pass "R8b_pure_additions"

# A touched BINARY test file yields no finding but still counts in F (the only file touched).
newrepo r8c; mkdir -p "$R/tests"
printf 'a\000b\001\n' > "$R/tests/blob.bin"
basecommit; feature
printf 'a\000c\002\n' > "$R/tests/blob.bin"
featcommit
run "$R" main
expect_rc 0 "R8c"; [ "$(nlines)" = 1 ] || { cat "$T/out" >&2; fail "R8c: a binary file yields no finding"; }
expect_line '^test-drift-check: 0 findings, 0 waived, 1 test files examined ' "R8c: a binary test file is counted in F"
pass "R8c_binary_counted"

# ── R1: scope and baseline ───────────────────────────────────────────────────────
newrepo r1a; put src/app.js <<'EOF'
function f(x) {
  assert(x);
  return 1;
}
EOF
basecommit; feature; delline src/app.js '  assert(x);'; featcommit
run "$R" main
expect_rc 0 "R1a"; [ "$(nlines)" = 1 ] || fail "R1a: a non-test file must produce no finding"
pass "R1a_non_test_file_ignored"

newrepo r1b; js_app tests/app.test.js; basecommit; feature
subst tests/app.test.js '  expect(run(1)).toBe(1);' '  expect(run(1)).toBeTruthy();'
run "$R" main
expect_rc 1 "R1b uncommitted weakening is seen"; expect_line '^DRIFT assert-modified \| tests/app\.test\.js:' "R1b"
git -C "$R" stash -q
run "$R" main
expect_rc 0 "R1b after stash"
pass "R1b_working_tree_default"

newrepo r1c; js_app tests/app.test.js; basecommit; feature
subst tests/app.test.js '  expect(run(1)).toBe(1);' '  expect(run(1)).toBeTruthy();'; featcommit
run "$R" main feature
expect_rc 1 "R1c main feature"
run "$R" main main
expect_rc 0 "R1c main main"
pass "R1c_head_ref"

# The classifier comes from the SIBLING change-size.sh: a stub that prints a different ERE
# changes which files are examined.
newrepo r1d
put tests/x.sh <<'EOF'
#!/bin/sh
t_one() {
  ok "one"
}
EOF
put zzz/x.sh <<'EOF'
#!/bin/sh
t_one() {
  ok "one"
}
EOF
basecommit; feature
subst tests/x.sh '  ok "one"' '  ok "uno"'
subst zzz/x.sh '  ok "one"' '  ok "uno"'
featcommit
mkdir -p "$T/stubtools"
cp "$TOOL" "$T/stubtools/test-drift-check.sh"
cat > "$T/stubtools/change-size.sh" <<'EOF'
#!/bin/sh
case "$1" in
  --print-test-re) echo '(^|/)zzz/' ;;
esac
exit 0
EOF
( cd "$R" && sh "$T/stubtools/test-drift-check.sh" main ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
expect_rc 1 "R1d"
expect_ndrift 1 "R1d"
expect_line '^DRIFT assert-modified \| zzz/x\.sh:' "R1d must name zzz/x.sh"
[ "$(cnt 'tests/x\.sh')" = 0 ] || fail "R1d: tests/x.sh must not be examined under the stub classifier"
# A sibling that fails, or answers with an empty classifier, stops the check (exit 3): it never
# examines every path, or none, on a half-read configuration (round 3).
cat > "$T/stubtools/change-size.sh" <<'EOF'
#!/bin/sh
case "$1:$STUB" in
  --print-test-re:re-fails)   echo '(^|/)zzz/'; exit 1 ;;
  --print-test-re:re-empty)   echo '' ;;
  --print-test-re:*)          echo '(^|/)zzz/' ;;
  --print-list:list-fails)    exit 1 ;;
esac
exit 0
EOF
for _stub in re-fails:'cannot read the test classifier' re-empty:'empty test classifier' list-fails:'cannot read change_size.assert_patterns'; do
  ( cd "$R" && STUB="${_stub%%:*}" sh "$T/stubtools/test-drift-check.sh" main ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
  expect_rc 3 "R1d stub ${_stub%%:*}"
  grep -qF "${_stub#*:}" "$T/err" || { cat "$T/err" >&2; fail "R1d: stub ${_stub%%:*} must stop with '${_stub#*:}'"; }
done
pass "R1d_stub_classifier"

# Known limit, documented in the tool header and the Reviewer section: the shared classifier
# counts a feature's own `*.spec.md` as a test file, and a prose line there has no extractable
# test name, so its finding carries the PATH as the name (the only name a waiver can use).
newrepo r1e; put specs/f/F.spec.md <<'EOF'
# Spec
The tool shall expect(a) to hold.
EOF
basecommit; feature
subst specs/f/F.spec.md 'The tool shall expect(a) to hold.' 'The tool shall expect(b) to hold.'; featcommit
run "$R" main
expect_rc 1 "R1e"; expect_ndrift 1 "R1e"
expect_line '^DRIFT assert-modified \| specs/f/F\.spec\.md:2 \| specs/f/F\.spec\.md \| ' "R1e: a spec prose line is a finding named by its path"
pass "R1e_spec_md_is_a_test_file"

# Untracked files belong to the WORKING-TREE head only, and only when not ignored (round 3,
# N04/N05). Both files carry an `.only(` so listing either one is a visible finding.
newrepo r1f; js_app tests/app.test.js
printf 'tests/ign.test.js\n' > "$R/.gitignore"
basecommit; feature
put tests/u.test.js <<'EOF'
it.only('untracked', () => {
  run();
});
EOF
put tests/ign.test.js <<'EOF'
it.only('ignored', () => {
  run();
});
EOF
run "$R" main
expect_rc 1 "R1f working tree"; expect_ndrift 1 "R1f working tree"
expect_line '^DRIFT skip-added \| tests/u\.test\.js:1 \| untracked \| ' "R1f: an untracked test file is in the working tree"
[ "$(cnt 'ign\.test\.js')" = 0 ] || { cat "$T/out" >&2; fail "R1f: a .gitignored test file must not be examined"; }
expect_line '^test-drift-check: 1 findings, 0 waived, 1 test files examined ' "R1f: F counts the untracked file only"
run "$R" main feature
expect_rc 0 "R1f head-ref mode"
expect_line '^test-drift-check: 0 findings, 0 waived, 0 test files examined ' "R1f: <head-ref> mode never lists untracked files"
pass "R1f_untracked_scope"

# ── R3: assertion findings ───────────────────────────────────────────────────────
newrepo r3a; js_app tests/app.test.js; basecommit; feature
subst tests/app.test.js '  expect(run(1)).toBe(1);' '  expect(run(1)).toBeTruthy();'; featcommit
run "$R" main
expect_rc 1 "R3a"; expect_ndrift 1 "R3a"
expect_line '^DRIFT assert-modified \| tests/app\.test\.js:[0-9]+ \| keeps name \| .*expect\(.* -> .*expect\(' "R3a"
[ "$(cnt 'assert-removed|test-removed')" = 0 ] || fail "R3a: only an assert-modified finding is expected"
pass "R3a_modified_exact"

newrepo r3b; js_app tests/app.test.js; basecommit; feature
delline tests/app.test.js '  expect(run(1)).toBe(1);'; featcommit
run "$R" main
expect_rc 1 "R3b"; expect_ndrift 1 "R3b"
grep -Fxq 'DRIFT assert-removed | tests/app.test.js:3 | keeps name | expect(run(1)).toBe(1);' "$T/out" \
  || { cat "$T/out" >&2; fail "R3b: want the removed text as the detail"; }
pass "R3b_removed_only"

newrepo r3c; put tests/m.test.js <<'EOF'
it('multi', () => {
  expect(a).toBe(1);
  expect(b).toBe(2);
});
EOF
basecommit; feature
delline tests/m.test.js '  expect(b).toBe(2);'
subst tests/m.test.js '  expect(a).toBe(1);' '  expect(c).toBe(3);'
featcommit
run "$R" main
expect_rc 1 "R3c"; expect_ndrift 2 "R3c"
[ "$(cnt '^DRIFT assert-modified .*expect\(a\)\.toBe\(1\); -> expect\(c\)\.toBe\(3\);$')" = 1 ] || { cat "$T/out" >&2; fail "R3c: first - pairs with the + as assert-modified"; }
[ "$(cnt '^DRIFT assert-removed .*\| expect\(b\)\.toBe\(2\);$')" = 1 ] || { cat "$T/out" >&2; fail "R3c: the unpaired - is assert-removed"; }
pass "R3c_pairing"

newrepo r3d; js_app tests/app.test.js; basecommit; feature
put tests/app.test.js <<'EOF'
const run = require('./run');
it('keeps name', () => {
  expect(run(1)).toBe(1);
  expect(run(9)).toBe(9);
  run(2);
});
it('other', () => {
  run(3);
});
EOF
featcommit
run "$R" main
expect_rc 0 "R3d"
pass "R3d_added_assertion_no_finding"

# Pairing is per hunk: a `+` assertion in one -U0 hunk must never pair with a `-` in another.
# Two scopes, and the first leaves residue (an unpaired `+`) for the second to misuse.
newrepo r3e; put tests/h.test.js <<'EOF'
it('first', () => {
  run(1);
});
it('second', () => {
  run(2);
  expect(b).toBe(2);
});
EOF
basecommit; feature
put tests/h.test.js <<'EOF'
it('first', () => {
  run(1);
  expect(a).toBe(1);
});
it('second', () => {
  run(2);
});
EOF
featcommit
run "$R" main
expect_rc 1 "R3e"; expect_ndrift 1 "R3e"
[ "$(cnt '^DRIFT assert-modified ')" = 0 ] || { cat "$T/out" >&2; fail "R3e: a + in hunk 1 paired with a - in hunk 2"; }
grep -Fxq 'DRIFT assert-removed | tests/h.test.js:6 | second | expect(b).toBe(2);' "$T/out" \
  || { cat "$T/out" >&2; fail "R3e: want exactly the hunk-2 removal as assert-removed"; }
pass "R3e_pairing_is_per_hunk"

# The tool pins LC_ALL=C itself, so the CALLER's locale cannot change a verdict (round 3, N18).
# Observable on hosts whose awk decodes UTF-8 (the macOS system awk): under a UTF-8 locale it
# aborts on an invalid byte in a test file, and the tool exits 2 instead of reporting.
_u8="$(locale -a 2>/dev/null | grep -Ei '^c\.utf-?8$' | head -n 1)"
[ -n "$_u8" ] || _u8="$(locale -a 2>/dev/null | grep -Ei '^en_us\.utf-?8$' | head -n 1)"
if [ -n "$_u8" ]; then
  newrepo r3f; mkdir -p "$R/tests"
  printf "it('l', () => {\n  \377 assert(z);\n  run();\n});\n" > "$R/tests/l.test.js"
  basecommit; feature
  printf "it('l', () => {\n  run();\n});\n" > "$R/tests/l.test.js"; featcommit
  ( cd "$R" && LC_ALL="$_u8" LANG="$_u8" sh "$TOOL" main ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
  expect_rc 1 "R3f under $_u8"; expect_ndrift 1 "R3f under $_u8"
  expect_line '^DRIFT assert-removed \| tests/l\.test\.js:2 \| l \| ' "R3f: an invalid byte under a UTF-8 caller locale"
  [ ! -s "$T/err" ] || { cat "$T/err" >&2; fail "R3f: stderr must stay empty under $_u8"; }
  pass "R3f_caller_utf8_locale"
else
  echo "note - R3f_caller_utf8_locale not run: no C.UTF-8 / en_US.UTF-8 locale on this host"
fi

# ── R4: built-in assertion patterns ──────────────────────────────────────────────
newrepo r4a
fam() { # fam <n> <ext> <kind> <line> — a fixture file whose only changed line is <line>
  case "$3" in
    py) printf 'def test_f%s():\n    x = 1\n%s\n    return x\n' "$1" "$4" ;;
    sh) printf '#!/bin/sh\nt_f%s() {\n  :\n%s\n}\n' "$1" "$4" ;;
    js) printf "it('f%s', () => {\n%s\n  run();\n});\n" "$1" "$4" ;;
    rs) printf 'fn t() {\n%s\n}\n' "$4" ;;
  esac > "$R/tests/fam$1.$2"
}
mkdir -p "$R/tests"
i=0
while IFS='|' read -r ext kind line; do
  i=$((i + 1)); fam "$i" "$ext" "$kind" "$line"
  printf '%s|%s\n' "$ext" "$line" >> "$T/famlist"
done <<'EOF'
py|py|    assert x == 1
js|js|  assertEqual(a, b);
js|js|  assert.ok(v);
rs|rs|  assert_eq!(a, b);
js|js|  expect(v).toBe(1);
js|js|  t.is(a, b);
js|js|  t.ok(v);
js|js|  fail('x');
py|py|    with pytest.raises(ValueError):
sh|sh|  [ -f x ] || fail "m"
sh|sh|  ok "m"
EOF
basecommit; feature
i=0
while IFS='|' read -r ext line; do
  i=$((i + 1)); delline "tests/fam$i.$ext" "$line"
done < "$T/famlist"
featcommit
run "$R" main
expect_rc 1 "R4a"
expect_ndrift 11 "R4a"
[ "$(cnt '^DRIFT assert-removed ')" = 11 ] || { cat "$T/out" >&2; fail "R4a: every family yields assert-removed"; }
[ "$(cnt 'test-removed')" = 0 ] || { cat "$T/out" >&2; fail "R4a: no family removal may read as a removed test (ok is not a name)"; }
i=0
while IFS='|' read -r ext line; do
  i=$((i + 1))
  [ "$(cnt "^DRIFT assert-removed \\| tests/fam$i\\.$ext:")" = 1 ] || { cat "$T/out" >&2; fail "R4a: family $i ($line) must give exactly one finding"; }
done < "$T/famlist"
pass "R4a_builtins_each"

newrepo r4b; put tests/t.sh <<'EOF'
#!/bin/sh
t_one() {
  [ -f "$x" ] && cp "$x" "$y"
  # this should run first
  reassert(x)
  my_assert_ok y
  :
}
EOF
basecommit; feature
subst tests/t.sh '  [ -f "$x" ] && cp "$x" "$y"' '  [ -f "$x" ] && cp "$x" "$z"'
subst tests/t.sh '  # this should run first' '  # this should run second'
featcommit
run "$R" main
expect_rc 0 "R4b"; [ "$(nlines)" = 1 ] || { cat "$T/out" >&2; fail "R4b: bare [ ], should and comments are not assertions"; }
# `assert` is word-bounded: an identifier that merely CONTAINS it is not an assertion.
subst tests/t.sh '  reassert(x)' '  reassert(y)'
subst tests/t.sh '  my_assert_ok y' '  my_assert_ok z'
featcommit
run "$R" main
expect_rc 0 "R4b word-bounded assert"; [ "$(nlines)" = 1 ] || { cat "$T/out" >&2; fail "R4b: reassert( / my_assert_ok are not the assert family"; }
pass "R4b_negatives"

# ── R5: configured assertion patterns ────────────────────────────────────────────
r5fixture() { # r5fixture <name> <config text|-> — a JS test with a verify( and an expect( line
  newrepo "$1"
  put tests/t.js <<'EOF'
it('checks', () => {
  verify(thing);
  expect(thing).toBe(1);
});
EOF
  if [ "$2" != "-" ]; then mkdir -p "$R/.harness"; printf '%s\n' "$2" > "$R/.harness/harness.config.yaml"; fi
  basecommit; feature
}
r5fixture r5a 'change_size:
  assert_patterns:
    - "(^|[^A-Za-z0-9_])verify[(]"'
delline tests/t.js '  verify(thing);'; featcommit
run "$R" main
expect_rc 1 "R5a"; expect_ndrift 1 "R5a"
expect_line '^DRIFT assert-removed \| tests/t\.js:2 \| checks \| verify\(thing\);$' "R5a"
delline tests/t.js '  expect(thing).toBe(1);'; featcommit
run "$R" main
expect_ndrift 2 "R5a configured entries ADD to the built-ins"
pass "R5a_extended"

r5fixture r5b 'change_size:
  assert_patterns: []'
delline tests/t.js '  verify(thing);'; featcommit
run "$R" main
expect_rc 0 "R5b"
pass "R5b_empty_list"

r5fixture r5c 'models:
  x: 1'
delline tests/t.js '  verify(thing);'; delline tests/t.js '  expect(thing).toBe(1);'; featcommit
run "$R" main
expect_ndrift 1 "R5c"
expect_line '^DRIFT assert-removed \| tests/t\.js:[0-9]+ \| checks \| expect\(thing\)' "R5c: built-ins still apply"
pass "R5c_absent_key"

newrepo r5d; put tests/t.js <<'EOF'
it('checks', () => {
  custom check(x);
  custom
  run();
});
EOF
mkdir -p "$R/.harness"
printf 'change_size:\n  assert_patterns:\n    - "custom check[(]"\n' > "$R/.harness/harness.config.yaml"
basecommit; feature
delline tests/t.js '  custom check(x);'; delline tests/t.js '  custom'; featcommit
run "$R" main
expect_ndrift 1 "R5d"
expect_line '^DRIFT assert-removed \| tests/t\.js:2 \| checks \| custom check\(x\);$' "R5d: only the whole-pattern line is a finding"
pass "R5d_space_in_entry"

# ── R6: skip markers ─────────────────────────────────────────────────────────────
newrepo r6a; js_app tests/app.test.js; basecommit; feature
subst tests/app.test.js "it('keeps name', () => {" "it.skip('keeps name', () => {"; featcommit
run "$R" main
expect_rc 1 "R6a"; expect_ndrift 1 "R6a"
expect_line '^DRIFT skip-added \| tests/app\.test\.js:2 \| keeps name \| ' "R6a"
[ "$(cnt 'test-removed')" = 0 ] || fail "R6a: the name string is unchanged, so no test-removed"
pass "R6a_skip_added"

newrepo r6b; js_app tests/app.test.js; basecommit; feature
put tests/new.test.js <<'EOF'
it.only('focused', () => {
  run();
});
EOF
run "$R" main
expect_rc 1 "R6b"; expect_ndrift 1 "R6b"
expect_line '^DRIFT skip-added \| tests/new\.test\.js:1 \| focused \| ' "R6b"
pass "R6b_only_in_new_file"

newrepo r6c; mkdir -p "$R/tests"
printf "it('a', () => {\n  run();\n});\n"        > "$R/tests/m1.test.js"
printf "it('a', () => {\n  run();\n});\n"        > "$R/tests/m2.test.js"
printf 'def test_a():\n    pass\n'                > "$R/tests/test_m3.py"
printf 'def test_decorated():\n    pass\n'        > "$R/tests/test_m4.py"
printf 'def test_a():\n    pass\n'                > "$R/tests/test_m5.py"
printf 'def test_a():\n    pass\n'                > "$R/tests/test_m6.py"
printf 'func TestA(t *testing.T) {\n}\n'          > "$R/pkg_z_test.go"
printf 'fn t() {\n}\n'                            > "$R/tests/m8.rs"
printf 'class FooTest {\n}\n'                     > "$R/tests/FooTest.java"
printf '#!/bin/sh\nt_one() {\n  :\n}\n'           > "$R/tests/s.sh"
basecommit; feature
printf "it('a', () => {\n  run();\n});\ntest.todo('later');\n"  > "$R/tests/m1.test.js"
printf "it('a', () => {\n  run();\n});\nxit('x', () => {});\n"  > "$R/tests/m2.test.js"
printf 'def test_a():\n    pass\n@pytest.mark.skip\n'            > "$R/tests/test_m3.py"
printf '@pytest.mark.xfail\ndef test_decorated():\n    pass\n'  > "$R/tests/test_m4.py"
printf 'def test_a():\n    pytest.skip("no")\n    pass\n'        > "$R/tests/test_m5.py"
printf 'def test_a():\n    pass\n@unittest.skip("x")\n'          > "$R/tests/test_m6.py"
printf 'func TestA(t *testing.T) {\n\tt.Skip("no")\n}\n'        > "$R/pkg_z_test.go"
printf 'fn t() {\n#[ignore]\n}\n'                                 > "$R/tests/m8.rs"
printf 'class FooTest {\n  @Disabled\n}\n'                        > "$R/tests/FooTest.java"
printf '#!/bin/sh\nt_one() {\n  echo "skip - no node"\n  :\n}\n' > "$R/tests/s.sh"
featcommit
run "$R" main
expect_rc 1 "R6c"; expect_ndrift 10 "R6c"
[ "$(cnt '^DRIFT skip-added ')" = 10 ] || { cat "$T/out" >&2; fail "R6c: each family yields exactly one skip-added"; }
for f in tests/m1.test.js tests/m2.test.js tests/test_m3.py tests/test_m4.py tests/test_m5.py tests/test_m6.py \
         pkg_z_test.go tests/m8.rs tests/FooTest.java tests/s.sh; do
  [ "$(cnt "^DRIFT skip-added \\| $f:")" = 1 ] || { cat "$T/out" >&2; fail "R6c: $f must give exactly one skip-added"; }
done
expect_line '^DRIFT skip-added \| tests/test_m4\.py:1 \| test_decorated \| @pytest\.mark\.xfail$' "R6c: a decorator attributes FORWARD"
pass "R6c_other_markers"

newrepo r6d; put tests/app.test.js <<'EOF'
it.skip('later', () => {
  run();
});
EOF
basecommit; feature
subst tests/app.test.js "it.skip('later', () => {" "it('later', () => {"; featcommit
run "$R" main
expect_rc 0 "R6d"; [ "$(nlines)" = 1 ] || fail "R6d: a removed marker is no finding"
pass "R6d_removed_marker_ok"

# An INDENTED decorator (a class method) still attributes forward to the def it decorates,
# not backward to the previous method.
newrepo r6e; put tests/test_k.py <<'EOF'
class TestK:
    def test_a(self):
        pass

    def test_m(self):
        pass
EOF
basecommit; feature
subst tests/test_k.py '    def test_m(self):' '    @pytest.mark.skip
    def test_m(self):'
featcommit
run "$R" main
expect_rc 1 "R6e"; expect_ndrift 1 "R6e"
expect_line '^DRIFT skip-added \| tests/test_k\.py:5 \| test_m \| @pytest\.mark\.skip$' "R6e: an indented decorator attributes FORWARD"
pass "R6e_indented_decorator_forward"

# ── R7: test names and test-removed ──────────────────────────────────────────────
r7sh() { # the shared sh fixture: two assertion-free functions, one deleted on the branch
  newrepo "$1"
  put tests/t.sh <<'EOF'
#!/bin/sh
test_kept() { :; }
test_gone() { :; }
EOF
  basecommit; feature
  delline tests/t.sh 'test_gone() { :; }'; featcommit
}
r7sh r7a
run "$R" main
expect_rc 1 "R7a"; expect_ndrift 1 "R7a"
expect_line '^DRIFT test-removed \| tests/t\.sh:[0-9—]+ \| test_gone \| test_gone$' "R7a"
pass "R7a_sh_function_removed"

newrepo r7b; put tests/app.test.js <<'EOF'
it('stays', () => { run(); });
it('goes away', () => { run(); });
EOF
basecommit; feature
delline tests/app.test.js "it('goes away', () => { run(); });"; featcommit
run "$R" main
expect_ndrift 1 "R7b"; expect_line '^DRIFT test-removed \| tests/app\.test\.js:[0-9—]+ \| goes away \| goes away$' "R7b"
pass "R7b_js_it_removed"

newrepo r7c; put tests/test_z.py <<'EOF'
def test_y(): pass
def test_z(): pass
EOF
basecommit; feature
delline tests/test_z.py 'def test_z(): pass'; featcommit
run "$R" main
expect_ndrift 1 "R7c"; expect_line '^DRIFT test-removed \| tests/test_z\.py:[0-9—]+ \| test_z \| test_z$' "R7c"
pass "R7c_py_def_removed"

newrepo r7d; put tests/z_test.go <<'EOF'
func TestY(t *testing.T) {}
func TestZ(t *testing.T) {}
EOF
basecommit; feature
delline tests/z_test.go 'func TestZ(t *testing.T) {}'; featcommit
run "$R" main
expect_ndrift 1 "R7d"; expect_line '^DRIFT test-removed \| tests/z_test\.go:[0-9—]+ \| TestZ \| TestZ$' "R7d"
pass "R7d_go_func_removed"

newrepo r7e; put tests/t.sh <<'EOF'
#!/bin/sh
pass "R1 old"
EOF
basecommit; feature
subst tests/t.sh 'pass "R1 old"' 'pass "R1 new"'; featcommit
run "$R" main
expect_ndrift 1 "R7e"; expect_line '^DRIFT test-removed \| tests/t\.sh:[0-9—]+ \| R1 old \| R1 old$' "R7e"
pass "R7e_label_reworded"

newrepo r7f; js_app tests/a.test.js; basecommit; feature
git -C "$R" mv tests/a.test.js tests/b.test.js; featcommit
run "$R" main
expect_rc 0 "R7f"
expect_line '^test-drift-check: 0 findings, 0 waived, 1 test files examined ' "R7f counts the renamed file as examined"
# The same rename read in <head-ref> mode: the head text comes from the NEW path at that commit.
run "$R" main feature
expect_rc 0 "R7f main feature"
expect_line '^test-drift-check: 0 findings, 0 waived, 1 test files examined ' "R7f head-ref mode reads the new path"
pass "R7f_rename_no_change"

# The D and R statuses each carry their own fixture (round 3, N17/N16): a DELETED test file
# yields findings for everything it held, and a rename that also weakens an assertion is
# diffed old path -> new path (diffing only the new path reads every line as an addition).
newrepo r7j; put tests/del.sh <<'EOF'
#!/bin/sh
t_x() { ok "y"; }
EOF
put tests/a.test.js <<'EOF'
it('renamed', () => {
  expect(run(1)).toBe(1);
  run(2);
  run(3);
  run(4);
  run(5);
});
EOF
basecommit; feature
git -C "$R" rm -q tests/del.sh
git -C "$R" mv tests/a.test.js tests/b.test.js
subst tests/b.test.js '  expect(run(1)).toBe(1);' '  expect(run(1)).toBeTruthy();'
featcommit
for _mode in wt ref; do
  if [ "$_mode" = wt ]; then run "$R" main; else run "$R" main feature; fi
  expect_rc 1 "R7j ($_mode)"; expect_ndrift 3 "R7j ($_mode)"
  for _want in 'DRIFT test-removed | tests/del.sh:— | t_x | t_x' \
               'DRIFT assert-removed | tests/del.sh:2 | t_x | t_x() { ok "y"; }' \
               'DRIFT assert-modified | tests/b.test.js:2 | renamed | expect(run(1)).toBe(1); -> expect(run(1)).toBeTruthy();'; do
    grep -Fxq "$_want" "$T/out" || { cat "$T/out" >&2; fail "R7j ($_mode): want the line: $_want"; }
  done
  expect_line '^test-drift-check: 3 findings, 0 waived, 2 test files examined ' "R7j ($_mode): the deleted file counts in F"
done
pass "R7j_deleted_and_renamed_files"

# Extractor variants and decorator binding, one repo (round 3, N08/N07/N11): an `async def`
# test, an extensionless `#!/bin/sh` file (sh by shebang), and a decorator added above the
# FIRST of two defs, which must name the NEXT def, not the last one in the file.
newrepo r7k
put tests/test_async.py <<'EOF'
async def test_y():
    pass
def test_keep():
    pass
EOF
put tests/run <<'EOF'
#!/bin/sh
t_run() { :; }
t_keep() { :; }
EOF
put tests/test_dec.py <<'EOF'
def test_m():
    pass
def test_n():
    pass
EOF
basecommit; feature
put tests/test_async.py <<'EOF'
def test_keep():
    pass
EOF
delline tests/run 't_run() { :; }'
put tests/test_dec.py <<'EOF'
@pytest.mark.skip
def test_m():
    pass
def test_n():
    pass
EOF
featcommit
run "$R" main
expect_rc 1 "R7k"; expect_ndrift 3 "R7k"
grep -Fxq 'DRIFT test-removed | tests/test_async.py:— | test_y | test_y' "$T/out" \
  || { cat "$T/out" >&2; fail "R7k: a removed async def test_y is test-removed"; }
grep -Fxq 'DRIFT test-removed | tests/run:— | t_run | t_run' "$T/out" \
  || { cat "$T/out" >&2; fail "R7k: an extensionless #!/bin/sh file is read as sh"; }
pass "R7k_async_def_and_shebang_sh"
grep -Fxq 'DRIFT skip-added | tests/test_dec.py:1 | test_m | @pytest.mark.skip' "$T/out" \
  || { cat "$T/out" >&2; fail "R6f: a decorator names the NEXT def (test_m), not a later one"; }
pass "R6f_decorator_names_next_def"

r7g() { # label-style sh suite; the assertion line above `pass "R9 label"` is removed
  newrepo "$1"
  put tests/t.sh <<'EOF'
#!/bin/sh
fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
a=1
b=2
[ "$a" = 1 ] || fail "x"
pass "R9 label"
EOF
  basecommit; feature
  delline tests/t.sh '[ "$a" = 1 ] || fail "x"'; featcommit
}
r7g r7g
run "$R" main
expect_rc 1 "R7g"; expect_ndrift 1 "R7g"
expect_line '^DRIFT assert-removed \| tests/t\.sh:6 \| R9 label \| ' "R7g: a sh label attributes FORWARD"
pass "R7g_attribution_forward_label"

# A tie: the removed line (4) is 2 lines below the def (2) and 2 lines above the label (6).
# The backward definition wins.
newrepo r7h; put tests/t.sh <<'EOF'
#!/bin/sh
t_def() {
  :
  [ "$a" = 1 ] || fail "x"
}
pass "tie label"
EOF
basecommit; feature
delline tests/t.sh '  [ "$a" = 1 ] || fail "x"'; featcommit
run "$R" main
expect_rc 1 "R7h"; expect_ndrift 1 "R7h"
expect_line '^DRIFT assert-removed \| tests/t\.sh:4 \| t_def \| ' "R7h: on a tie the backward definition wins"
pass "R7h_attribution_tie_goes_backward"

# One finding per NAME: a label present twice at base, both copies removed, is one test-removed.
newrepo r7i; put tests/t.sh <<'EOF'
#!/bin/sh
pass "dup"
pass "dup"
pass "keep"
EOF
basecommit; feature
delline tests/t.sh 'pass "dup"'; featcommit
run "$R" main
expect_rc 1 "R7i"; expect_ndrift 1 "R7i"
[ "$(cnt '^DRIFT test-removed \| tests/t\.sh:[0-9—]+ \| dup \| dup$')" = 1 ] || { cat "$T/out" >&2; fail "R7i: a duplicated name is reported once"; }
pass "R7i_duplicate_name_one_finding"

# ── R9c: finding line shape ──────────────────────────────────────────────────────
run "$R" main
expect_rc 1 "R9c"
grep '^DRIFT ' "$T/out" | grep -Evq '^DRIFT (assert-modified|assert-removed|skip-added|test-removed) \| [^|]+:[0-9—]+ \| [^|]* \| ' \
  && fail "R9c: a DRIFT line does not match the documented shape"
[ "$(tail -n 1 "$T/out" | grep -c '^test-drift-check: [0-9]* findings, [0-9]* waived, [0-9]* test files examined (base [0-9a-f]*)$')" = 1 ] \
  || fail "R9c: the summary line must be the last stdout line"
pass "R9c_finding_line_shape"

# ── R10: waivers ─────────────────────────────────────────────────────────────────
r7sh r10a
printf '## Waivers\nwaive-test-drift: test_gone — replaced by test_kept (T4)\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 0 "R10a"
[ "$(cnt '^WAIVED test-removed \| .* \| test_gone \| replaced by test_kept \(T4\)$')" = 1 ] || { cat "$T/out" >&2; fail "R10a: want one WAIVED line"; }
expect_line '^test-drift-check: 1 findings, 1 waived, ' "R10a"
pass "R10a_exact_match_waives"

# The split is on the FIRST spaced em dash, so a reason may itself carry one; and the spacing
# around the separator is any blank, a tab included (round 3, N03/N20).
printf 'waive-test-drift: test_gone \342\200\224 a \342\200\224 b\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 0 "R10g first separator"
grep -Fxq 'WAIVED test-removed | tests/t.sh:— | test_gone | a — b' "$T/out" \
  || { cat "$T/out" >&2; fail "R10g: split on the FIRST spaced em dash (reason 'a — b')"; }
printf 'waive-test-drift: test_gone\t\342\200\224\tx\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 0 "R10g tab separator"
grep -Fxq 'WAIVED test-removed | tests/t.sh:— | test_gone | x' "$T/out" \
  || { cat "$T/out" >&2; fail "R10g: a tab on each side of the em dash is a valid separator"; }
pass "R10g_first_separator_and_tab"

for nm in test_gone_v2 test_gon Test_gone; do
  printf 'waive-test-drift: %s — not the same name\n' "$nm" > "$T/tasks.md"
  run "$R" main --tasks-md "$T/tasks.md"
  expect_rc 1 "R10b waiver naming $nm"
  expect_line '^DRIFT test-removed \| ' "R10b DRIFT line still printed for $nm"
  expect_line ', 0 waived, ' "R10b"
done
pass "R10b_non_match"

newrepo r10c; put tests/t.sh <<'EOF'
#!/bin/sh
test_a() { :; }
test_b() { :; }
test_c() { :; }
EOF
basecommit; feature
delline tests/t.sh 'test_a() { :; }'; delline tests/t.sh 'test_b() { :; }'; featcommit
printf 'waive-test-drift: test_a — gone on purpose\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 1 "R10c"
[ "$(cnt '^WAIVED ')" = 1 ] && [ "$(cnt '^DRIFT ')" = 1 ] || { cat "$T/out" >&2; fail "R10c: one WAIVED and one DRIFT"; }
expect_line '^WAIVED test-removed \| .* \| test_a \| ' "R10c"
pass "R10c_one_per_test"

r7sh r10d
printf '  - waive-test-drift: test_gone — reason in list form\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 0 "R10d"; expect_line '^WAIVED test-removed ' "R10d"
pass "R10d_list_marker_form"

printf 'waive-test-drift: test_gone\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 2 "R10e"; grep -q 'malformed waiver' "$T/err" || fail "R10e: stderr must name the malformed waiver"
printf 'waive-test-drift: test_gone — \n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 2 "R10e empty reason"
# The separator is an em dash with whitespace on BOTH sides; an unspaced one is no separator.
printf 'waive-test-drift: a\342\200\224b\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 2 "R10e unspaced em dash"; grep -q 'malformed waiver' "$T/err" || fail "R10e: an unspaced em dash must be reported as a malformed waiver"
printf 'The prose form is: waive-test-drift: <name> — <reason> (mid-line is not a waiver)\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 1 "R10e: a mid-line mention is not a waiver"
# A mid-line mention that names the REAL finding with a valid separator still waives nothing:
# the prefix must start the line (after an optional list marker).
printf '> see waive-test-drift: test_gone — x\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 1 "R10e: a mid-line waiver for the real name is not a waiver"
expect_line '^DRIFT test-removed \| .* \| test_gone \| ' "R10e: test_gone stays unwaived"
pass "R10e_malformed"

r7g r10f
printf 'waive-test-drift: R9 label — assertion moved into the helper\n' > "$T/tasks.md"
run "$R" main --tasks-md "$T/tasks.md"
expect_rc 0 "R10f"; expect_line '^WAIVED assert-removed \| tests/t\.sh:6 \| R9 label \| assertion moved into the helper$' "R10f"
pass "R10f_assert_finding_waived"

# ── R11: the Reviewer section ────────────────────────────────────────────────────
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
_rv="$ROOT/agents/reviewer.md"
_sec="$(awk "$FENCE_AWK"'
  fence_delim($0) { if (keep) print; next }
  !fence && /^## / { keep = (index($0, "## Test-drift check before the verdict (E36-F06)") == 1); next }
  keep
' "$_rv")"
[ -n "$_sec" ] || fail "R11a: reviewer.md has no '## Test-drift check before the verdict (E36-F06)' section"
_ln() { grep -nxF "$1" "$_rv" | head -n 1 | cut -d: -f1; }
_l_cs="$(_ln '## Change-size check before the PR handoff (E21-F02)')"
_l_td="$(_ln '## Test-drift check before the verdict (E36-F06)')"
_l_vd="$(_ln '## Verdict')"
[ -n "$_l_cs" ] && [ -n "$_l_vd" ] && [ "$_l_cs" -lt "$_l_td" ] && [ "$_l_td" -lt "$_l_vd" ] \
  || fail "R11a: the section must sit after the change-size section and before ## Verdict"
for _tok in 'tools/test-drift-check.sh' 'merge-base' '--tasks-md' 'waive-test-drift:' 'pair commit' \
            'REJECT' 'did not run' 'run-tests.sh' 'primary'; do
  printf '%s\n' "$_sec" | grep -qF -- "$_tok" || fail "R11a: the Reviewer section must carry '$_tok'"
done
# The per-pair-commit command carries the same --tasks-md, or a waived finding is a false REJECT.
printf '%s\n' "$_sec" | tr '\n' ' ' | grep -qF 'test-drift-check.sh" <pair-sha> --tasks-md' \
  || fail "R11a: the per-pair-commit command must pass --tasks-md"
# The *.spec.md-is-a-test-file limit is stated where the Reviewer reads the findings.
printf '%s\n' "$_sec" | tr '\n' ' ' | grep -qE "\*\.spec\.md[^.]{0,120}named by the spec's path" \
  || fail "R11a: the Reviewer section must state that *.spec.md findings are named by the spec's path"
# The exit-0 bullet states exactly what exit 0 covers, and names what it does not check.
_fold="$(printf '%s\n' "$_sec" | tr '\n' ' ')"
printf '%s' "$_fold" | grep -qE 'assertion-pattern line[^.]{0,120}skip/only marker[^.]{0,80}test name was removed' \
  || fail "R11a: the exit-0 bullet must name the three kinds of finding it covers"
printf '%s' "$_fold" | grep -qE 'are not checked[^.]{0,40}still read the test diff' \
  || fail "R11a: the exit-0 bullet must say other changed lines are not checked and the diff is still read"
printf '%s' "$_fold" | grep -qF 'nothing removed, modified or skipped' \
  && fail "R11a: the exit-0 bullet must not claim nothing was removed, modified or skipped"
pass "R11a_reviewer_section"

# ── R12: the shipped body ────────────────────────────────────────────────────────
TGT="$T/target"; mkdir -p "$TGT" "$T/home" "$T/ch"
git -C "$TGT" init -q
git -C "$TGT" config user.email t@example.com; git -C "$TGT" config user.name T
env -i PATH="$PATH" HOME="$T/home" CODEX_HOME="$T/ch" sh "$ROOT/harness-install.sh" --agents=claude "$TGT" >/dev/null 2>&1 \
  || fail "R12a: the sandboxed installer run failed"
[ -x "$TGT/.harness/tools/test-drift-check.sh" ] || fail "R12a: tools/test-drift-check.sh not installed executable"
git -C "$TGT" checkout -q -b main 2>/dev/null || true
printf '.harness/\n' > "$TGT/.gitignore"
mkdir -p "$TGT/tests"
printf "it('a', () => {\n  expect(run(1)).toBe(1);\n});\n" > "$TGT/tests/a.test.js"
git -C "$TGT" add tests .gitignore && git -C "$TGT" commit -qm base
printf "it('a', () => {\n  expect(run(1)).toBeTruthy();\n});\n" > "$TGT/tests/a.test.js"
git -C "$TGT" commit -qam weaken
( cd "$TGT" && sh .harness/tools/test-drift-check.sh HEAD~1 HEAD ) > "$T/out" 2> "$T/err" && rc=0 || rc=$?
expect_rc 1 "R12a: the installed tool finds its sibling change-size.sh"
expect_line '^DRIFT assert-modified \| tests/a\.test\.js:' "R12a"
pass "R12a_installed_tool_runs"

grep -qF 'E36-F06' "$ROOT/CHANGELOG.md" || fail "R12b: CHANGELOG.md must name E36-F06"
pass "R12b_changelog_names_feature"

echo "All test-drift-check tests passed."
