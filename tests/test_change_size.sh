#!/bin/sh
# test_change_size.sh — E21-F02: the advisory pre-PR change-size check.
#
# Behavioral, not textual: every assertion drives tools/change-size.sh against a REAL
# throwaway git repo with a known diff, because the whole value of this tool is the number
# it produces. A grep over the script would prove nothing about whether a test file is
# counted as production — which is the failure mode that makes the number meaningless.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never git-diff a DO-NOT-TOUCH file against main; never mutate the live
# state/tasks.json.
#
# Zero deps: POSIX sh + git + awk.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TOOL="$ROOT/tools/change-size.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t chgsize)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v git >/dev/null 2>&1 || { echo "skip - git unavailable"; exit 0; }

# ── fixture: a repo with main + a feature branch carrying a known, classified diff ──────
mkrepo() { # mkrepo <dir>
  _r="$1"; mkdir -p "$_r"
  git -C "$_r" init -q
  git -C "$_r" config user.email t@example.com
  git -C "$_r" config user.name  T
  git -C "$_r" checkout -q -b main
  printf 'seed\n' > "$_r/seed.txt"
  # The fixture rewrites .harness/harness.config.yaml between assertions to vary the budget.
  # Ignore it here so those rewrites never land IN the measured diff — otherwise the tool
  # would (correctly) count the config as production and every expected count would drift.
  printf '.harness/\n' > "$_r/.gitignore"
  git -C "$_r" add -A && git -C "$_r" commit -qm seed
}

# n_lines <count> — emit <count> distinct lines
n_lines() { i=1; while [ "$i" -le "$1" ]; do printf 'line %d\n' "$i"; i=$((i+1)); done; }

R="$T/repo"; mkrepo "$R"
git -C "$R" checkout -q -b feature
mkdir -p "$R/src" "$R/tests" "$R/specs" "$R/vendor"
n_lines 40  > "$R/src/app.js"        # production
n_lines 10  > "$R/src/util.js"       # production
n_lines 300 > "$R/tests/app.test.js" # test  — must NOT count as production
n_lines 200 > "$R/specs/design.md"   # doc   — must NOT count as production
n_lines 900 > "$R/vendor/lib.js"     # generated — excluded entirely
git -C "$R" add -A && git -C "$R" commit -qm work

# ── R1: classification — tests/docs/generated never inflate the production number ────────
out="$("$TOOL" --repo "$R" --base main --format json)"
_get() { printf '%s' "$out" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }
[ "$(_get production_lines)" = "50" ] \
  || fail "R1: production_lines=$(_get production_lines), expected 50 (tests/docs/generated must not count)"
[ "$(_get production_files)" = "2" ] \
  || fail "R1: production_files=$(_get production_files), expected 2"
[ "$(_get test_lines)" = "300" ]      || fail "R1: test_lines=$(_get test_lines), expected 300"
[ "$(_get doc_lines)" = "200" ]       || fail "R1: doc_lines=$(_get doc_lines), expected 200"
[ "$(_get generated_lines)" = "900" ] || fail "R1: generated_lines=$(_get generated_lines), expected 900"
[ "$(_get total_lines)" = "1450" ]    || fail "R1: total_lines=$(_get total_lines), expected 1450"
pass "R1 classification: production excludes tests, docs and generated files"

# ── R1b: literal-dot escapes in the classifiers survive into awk ─────────────────────────
# `awk -v re='...\.'` runs the value through awk's string-escape decoding, so `\.` arrives as
# a bare `.` — a wildcard. `src/foo-testXjs` then matches the TEST classifier and vanishes from
# the production budget, understating the tier. Passing the regexes via ENVIRON avoids the
# decoding. This fixture has no dot before the extension precisely so it can only match if the
# escape was eaten.
# Its OWN repo: adding this file to $R would shift every downstream fixture's expected
# counts, which is how a regression test quietly becomes a maintenance tax on unrelated ones.
RB="$T/repo-esc"; mkrepo "$RB"
git -C "$RB" checkout -q -b feature
mkdir -p "$RB/src"
n_lines 25 > "$RB/src/foo-testXjs"
git -C "$RB" add -A && git -C "$RB" commit -qm "a production file a wildcard would swallow"
[ "$("$TOOL" --repo "$RB" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "25" ] \
  || fail "R1b: src/foo-testXjs was not counted as production — a literal-dot escape was decoded away, so the classifier matched on a wildcard"
pass "R1b classifier escapes survive: a dotless near-miss filename stays in the production budget"

# ── R2: tiers come from config, and the tool NEVER blocks ────────────────────────────────
# 50 production lines against a tiny budget must reach every tier, and exit 0 every time.
mkdir -p "$R/.harness"
cfgw() { printf 'change_size:\n  advise_lines: %s\n  escalate_lines: %s\n  advise_files: %s\n  escalate_files: %s\n' \
           "$1" "$2" "$3" "$4" > "$R/.harness/harness.config.yaml"; }
tier_of() { "$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"tier":"\([a-z]*\)".*/\1/p'; }

cfgw 1000 2000 50 100
"$TOOL" --repo "$R" --base main >/dev/null || fail "R2: exit non-zero at tier ok — the check must never block"
[ "$(tier_of)" = "ok" ]       || fail "R2: expected tier ok under a generous budget, got $(tier_of)"
cfgw 20 2000 50 100
"$TOOL" --repo "$R" --base main >/dev/null || fail "R2: exit non-zero at tier advise — the check must never block"
[ "$(tier_of)" = "advise" ]   || fail "R2: expected tier advise (50 > advise_lines 20), got $(tier_of)"
cfgw 20 30 50 100
"$TOOL" --repo "$R" --base main >/dev/null || fail "R2: exit non-zero at tier escalate — the check must never block"
[ "$(tier_of)" = "escalate" ] || fail "R2: expected tier escalate (50 > escalate_lines 30), got $(tier_of)"
pass "R2 tiers read from config; exit 0 at ok, advise AND escalate (never blocks)"

# ── R3: the FILE budget trips independently of the line budget ───────────────────────────
# 60 one-line edits is a different review object than one 600-line file; a lines-only budget
# would wave the first one through.
cfgw 100000 200000 1 2
[ "$(tier_of)" = "advise" ] \
  || fail "R3: file budget did not trip on its own (2 production files > advise_files 1), got $(tier_of)"
pass "R3 file budget trips independently of the line budget"

# ── R3b: BINARY files occupy the file budget ─────────────────────────────────────────────
# git --numstat reports "-" for both counts on a binary. Discarding the record defeated the
# very budget that exists to fire independently of lines: 30 production images reported
# production_files: 0 and tier ok.
RB2="$T/repo-bin"; mkrepo "$RB2"; git -C "$RB2" checkout -q -b feature
mkdir -p "$RB2/img"; _i=1
while [ "$_i" -le 30 ]; do printf '\211PNG\r\n\032\n\000\001\002\003' > "$RB2/img/p$_i.png"; _i=$((_i+1)); done
git -C "$RB2" add -A && git -C "$RB2" commit -qm binaries
_jb="$("$TOOL" --repo "$RB2" --base main --format json)"
[ "$(printf '%s' "$_jb" | sed -n 's/.*"production_files":\([0-9]*\).*/\1/p')" = "30" ] \
  || fail "R3b: 30 binary production files were not counted toward the file budget"
[ "$(printf '%s' "$_jb" | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "0" ] \
  || fail "R3b: binary files contributed phantom LINES; they have no line count"
[ "$(printf '%s' "$_jb" | sed -n 's/.*"tier":"\([a-z]*\)".*/\1/p')" = "advise" ] \
  || fail "R3b: 30 files did not trip advise_files (default 25) — the file budget is defeated by binaries"
pass "R3b binary files occupy the file budget and contribute no lines"

# ── R4: an ABSENT change_size block falls back to the documented defaults ────────────────
rm -f "$R/.harness/harness.config.yaml"
out="$("$TOOL" --repo "$R" --base main --format json)"
printf '%s' "$out" | grep -qF '"advise_lines":1500'   || fail "R4: absent block did not default advise_lines to 1500"
printf '%s' "$out" | grep -qF '"escalate_lines":3000' || fail "R4: absent block did not default escalate_lines to 3000"
printf '%s' "$out" | grep -qF '"advise_files":25'     || fail "R4: absent block did not default advise_files to 25"
printf '%s' "$out" | grep -qF '"escalate_files":50'   || fail "R4: absent block did not default escalate_files to 50"
[ "$(tier_of)" = "ok" ] || fail "R4: 50 production lines should be ok under the defaults"
pass "R4 absent change_size block ⇒ documented defaults (1500/3000/25/50)"

# ── R5: measured against the MERGE BASE, not the base tip ────────────────────────────────
# Advance main after branching. A `git diff main...HEAD` (merge base) sees only the branch's
# own work; a `git diff main HEAD` would also report main's new commit as a deletion.
git -C "$R" checkout -q main
n_lines 500 > "$R/unrelated.js"        # repo root: src/ exists only on the feature branch
git -C "$R" add -A && git -C "$R" commit -qm "main moves on"
git -C "$R" checkout -q feature
[ "$("$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "50" ] \
  || fail "R5: production count changed after main advanced — not measuring from the merge base"
pass "R5 measures from the merge base, so an advanced base ref does not distort the count"

# ── R5b: UNCOMMITTED and UNTRACKED work is measured ──────────────────────────────────────
# The default in-session agents/builder.md has no commit step — it edits, tests, and hands
# the feature to the Reviewer. So at the moment this check runs the implementation is
# routinely staged or unstaged, and a `<mb>...HEAD` diff would omit the whole feature and
# report tier `ok` with zero production lines: the check reporting green on precisely the
# branch it exists to measure. New FILES matter most and are invisible to `git diff` at any
# range, so they are counted separately.
RU="$T/repo-dirty"; mkrepo "$RU"
git -C "$RU" checkout -q -b feature
mkdir -p "$RU/src"
n_lines 120 > "$RU/src/new-feature.js"   # untracked — never added, never committed
n_lines 30 >> "$RU/seed.txt"             # tracked, modified, unstaged
_pl="$("$TOOL" --repo "$RU" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')"
[ "$_pl" = "150" ] \
  || fail "R5b: production_lines=$_pl, expected 150 — uncommitted/untracked Builder output is not being measured"
git -C "$RU" add -A && git -C "$RU" commit -qm "same content, now committed"
_pl2="$("$TOOL" --repo "$RU" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')"
[ "$_pl2" = "150" ] \
  || fail "R5b: committing the same content changed the count from 150 to $_pl2 — the measurement must not depend on whether the Builder committed"
pass "R5b uncommitted + untracked work counts, and committing it changes nothing"

# ── R5c: the default branch is resolved, not assumed to be main ───────────────────────────
# A hard-coded origin/main exits 4 on a repo whose default is `develop`, and the Reviewer is
# told to carry on without measuring anything — the check silently vanishing on exactly the
# repos nobody tested it on.
RD="$T/repo-develop"; mkdir -p "$RD"
git -C "$RD" init -q; git -C "$RD" config user.email t@example.com; git -C "$RD" config user.name T
git -C "$RD" checkout -q -b develop
printf 'seed\n' > "$RD/seed.txt"; git -C "$RD" add -A && git -C "$RD" commit -qm seed
git -C "$RD" checkout -q -b feature; n_lines 42 > "$RD/app.js"
git -C "$RD" add -A && git -C "$RD" commit -qm work
git -C "$RD" symbolic-ref refs/remotes/origin/HEAD refs/heads/develop 2>/dev/null || true
"$TOOL" --repo "$RD" >/dev/null 2>&1 \
  || fail "R5c: no --base on a repo whose default is develop exited non-zero — the check would silently disappear there"
[ "$("$TOOL" --repo "$RD" --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "42" ] \
  || fail "R5c: default-branch resolution measured the wrong range on a non-main repo"
pass "R5c resolves the repo's real default branch instead of assuming origin/main"

# ── R6: concentration is reported when over budget (where to cut, not just how big) ──────
cfgw 20 30 50 100
txt="$("$TOOL" --repo "$R" --base main)"
printf '%s' "$txt" | grep -q 'src/app.js'  || fail "R6: over-budget report does not name the top production file"
printf '%s' "$txt" | grep -qi 'escalate'   || fail "R6: over-budget report does not name the tier"
printf '%s' "$txt" | grep -qi 'advisory'   || fail "R6: report does not state that the check is advisory"
cfgw 1000 2000 50 100
printf '%s' "$("$TOOL" --repo "$R" --base main)" | grep -q 'src/app.js' \
  && fail "R6: in-budget report should not print the concentration list" || :
pass "R6 concentration list printed only when over budget, and names the heaviest file"

# ── R7: extra classifier patterns are ADDITIVE to the built-ins ──────────────────────────
mkdir -p "$R/spec"
# Deliberately NOT `thing_spec.rb` — that already matches the built-in `[._-]spec.<ext>`
# pattern, so it would prove nothing about the config hook. `spec/thing.rb` is a real shape
# (a Ruby/RSpec tree keyed on the DIRECTORY) that the built-ins miss by design.
n_lines 70 > "$R/spec/thing.rb"
git -C "$R" add -A && git -C "$R" commit -qm "ruby-style specs"
[ "$("$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "120" ] \
  || fail "R7 fixture: an unclassified spec/ dir should count as production before configuring"
{ printf 'change_size:\n  advise_lines: 1000\n  escalate_lines: 2000\n  advise_files: 50\n  escalate_files: 100\n'
  printf '  test_paths:\n    - "(^|/)spec/"\n'; } > "$R/.harness/harness.config.yaml"
[ "$("$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "50" ] \
  || fail "R7: change_size.test_paths did not reclassify spec/ out of the production count"
[ "$("$TOOL" --repo "$R" --base main --format json | sed -n 's/.*"test_lines":\([0-9]*\).*/\1/p')" = "370" ] \
  || fail "R7: extra test_paths REPLACED the built-ins instead of extending them (tests/app.test.js lost)"
pass "R7 change_size.test_paths extends the built-in classifiers, never replaces them"

# ── R7b: a configured regex containing whitespace stays ONE alternative ──────────────────
# `for _p in $(...)` word-splits on IFS, so `(^|/)integration tests/` would be appended as two
# alternatives — `(^|/)integration|tests/` — and every production path merely STARTING with
# `integration` would silently drop out of the budget. That understates the tier while looking
# like it worked, which is the failure mode the whole classifier contract exists to prevent.
RW="$T/repo-ws"; mkrepo "$RW"; git -C "$RW" checkout -q -b feature
mkdir -p "$RW/.harness" "$RW/integrationX" "$RW/integration tests"
n_lines 20 > "$RW/integrationX/prod.js"          # production — must NOT be swallowed
n_lines 60 > "$RW/integration tests/spec.js"     # test — matched by the configured regex
git -C "$RW" add -A && git -C "$RW" commit -qm work
printf 'change_size:\n  test_paths:\n    - "(^|/)integration tests/"\n' > "$RW/.harness/harness.config.yaml"
_j="$("$TOOL" --repo "$RW" --base main --format json)"
[ "$(printf '%s' "$_j" | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "20" ] \
  || fail "R7b: a whitespace-containing test_paths regex was word-split — integrationX/prod.js left the production budget"
[ "$(printf '%s' "$_j" | sed -n 's/.*"test_lines":\([0-9]*\).*/\1/p')" = "60" ] \
  || fail "R7b: the whitespace-containing regex did not classify its own directory as tests"
pass "R7b a configured regex containing whitespace is one alternative, not two"

# ── R7c: an untracked file whose last line is unterminated is not undercounted ────────────
# `wc -l` counts NEWLINES, so a one-line file with no trailing newline reports ZERO additions.
# git --numstat counts it correctly once committed, so `wc` would make the tier depend on
# whether the Builder had committed yet — the exact coupling R5b exists to remove.
RN="$T/repo-nonl"; mkrepo "$RN"; git -C "$RN" checkout -q -b feature
mkdir -p "$RN/src"; printf 'one line and no trailing newline' > "$RN/src/a.js"   # untracked
[ "$("$TOOL" --repo "$RN" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "1" ] \
  || fail "R7c: an untracked file with no trailing newline was counted as zero additions"
git -C "$RN" add -A && git -C "$RN" commit -qm committed
[ "$("$TOOL" --repo "$RN" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "1" ] \
  || fail "R7c: committing the unterminated file changed its count — the measurement must not depend on that"
pass "R7c unterminated last lines count, committed or not"

# ── R7d: an untracked path git would C-quote is still measured ───────────────────────────
# `ls-files` C-quotes a path containing `"`, a backslash or a tab even under
# core.quotePath=false, returning `a"b.js` as `"a\"b.js"`. That encoded text was used as the
# pathname, `[ -f ]` failed, and the file vanished from the measurement — whole untracked
# Builder output disappearing silently. NUL framing is the only form git never encodes.
RQ2="$T/repo-uq"; mkrepo "$RQ2"; git -C "$RQ2" checkout -q -b feature
n_lines 3 > "$RQ2/q\"uote.js"                       # untracked, never added
_ju="$("$TOOL" --repo "$RQ2" --base main --format json)"
[ "$(printf '%s' "$_ju" | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "3" ] \
  || fail "R7d: an untracked filename git C-quotes was skipped entirely by the measurement"
[ "$(printf '%s' "$_ju" | sed -n 's/.*"production_files":\([0-9]*\).*/\1/p')" = "1" ] \
  || fail "R7d: the C-quoted untracked file was not counted toward the file budget"
pass "R7d untracked paths git would C-quote are measured, not skipped"

# ── R7e: a TRACKED path git would C-quote is classified on its real name ─────────────────
# The untracked side was fixed by R7d; the tracked side still parsed plain `--numstat`.
# `core.quotePath=false` governs non-ASCII bytes only — it does NOT stop git C-quoting a path
# containing `"`, a backslash or a tab. `src/foo".spec.js` arrived as `"src/foo\".spec.js"`,
# whose trailing quote defeats the `[._-](test|spec)\.[a-z]+$` suffix rule, so a TEST file was
# charged to the PRODUCTION budget: the tier silently overstated. `--numstat -z` never encodes.
#
# The same fixture pins the two things `-z` changes on the way in:
#   * a literal TAB now reaches the parser instead of arriving as the two characters `\t`, so
#     the pathname spans awk fields 3..NF and `$3` alone would truncate it; and
#   * `-z` reframes RENAMES as an empty path field followed by TWO extra fields, which parsed
#     naively becomes two or three phantom records instead of one.
RT="$T/repo-tracked-q"; mkrepo "$RT"
# Pin rename detection on, or a host with diff.renames off measures a different shape entirely.
git -C "$RT" config diff.renames true
mkdir -p "$RT/src"
_TAB="$(printf '\t')"
# The rename baseline lives on MAIN, so the branch carries a real rename rather than an add.
# It must satisfy THREE conditions at once or it cannot detect a broken fold:
#   (a) similar enough that git calls it a rename at all (60 of 66 lines survive);
#   (b) carrying ADDED lines, so the folded record contributes a non-zero count; and
#   (c) a destination whose CLASSIFICATION differs from the source's (production → test).
# A 0-line rename between two production paths — the obvious fixture, and the one this test
# shipped with in round 1 — proves nothing: the unfolded header record has an EMPTY pathname,
# which also classifies as production and also contributes 0 lines, while the two bare path
# records are eaten by `NF < 3 { next }`. Every number came out identical with the fold deleted.
n_lines 60 > "$RT/src/zmoved.js"                # production on main…
git -C "$RT" add -A && git -C "$RT" commit -qm "pre-rename baseline"
git -C "$RT" checkout -q -b feature
# The two C-quoted/tab TEST files are the other discriminators: each is classified ONLY if its
# full pathname survives intact. `src/foo".spec.js` needs git's C-quoting gone (the trailing `"`
# breaks the suffix rule); `src/tab<TAB>bed.spec.js` needs the awk pass to rejoin fields 3..NF
# (bare `$3` truncates it to `src/tab`, which matches nothing and lands in production).
n_lines 7 > "$RT/src/foo\".spec.js"             # TEST — quote must not defeat the suffix rule
n_lines 5 > "$RT/src/tab${_TAB}bed.spec.js"    # TEST — tab must not truncate the suffix away
n_lines 4 > "$RT/src/tab${_TAB}prod.js"        # production, pathname contains a literal tab
n_lines 3 > "$RT/src/plain.js"                 # production, ordinary name
git -C "$RT" mv src/zmoved.js src/zmoved.spec.js # …renamed onto a TEST path on the branch
n_lines 6 >> "$RT/src/zmoved.spec.js"           # + modification, so the fold carries real lines
git -C "$RT" add -A && git -C "$RT" commit -qm "paths git would C-quote"
_jt="$("$TOOL" --repo "$RT" --base main --format json)"
_gt() { printf '%s' "$_jt" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }
# test_lines is the assertion that discriminates the rename fold. Drop the fold, or key it on
# the SOURCE instead of the destination, and the renamed file's 6 added lines are charged to
# production (empty pathname, or `src/zmoved.js`) instead of to tests: 12, not 18.
[ "$(_gt test_lines)" = "18" ] \
  || fail "R7e: test_lines=$(_gt test_lines), expected 18 — a C-quoted, tab-bearing or RENAMED-ONTO TRACKED test path was charged to production"
[ "$(_gt production_lines)" = "7" ] \
  || fail "R7e: production_lines=$(_gt production_lines), expected 7 (4 tab-named + 3 plain); a rename onto a test path must contribute NONE of its added lines here"
[ "$(_gt production_files)" = "2" ] \
  || fail "R7e: production_files=$(_gt production_files), expected 2"
# total_files is kept, but its message now names only what it can actually detect. It does NOT
# detect a missing fold: with the fold deleted the rename still yields exactly one counted record
# (the header, whose empty pathname classifies as production), and the two bare path records are
# dropped by `NF < 3 { next }` — so 5 either way. What it does catch is a fold that emits BOTH
# halves of the rename, which is 6. Saying more than that here would be a failure message naming
# a guarantee it cannot detect, which is the defect this whole assertion block was rewritten for.
[ "$(_gt total_files)" = "5" ] \
  || fail "R7e: total_files=$(_gt total_files), expected 5 — a -z rename must contribute ONE record, not both its source and its destination"
pass "R7e tracked C-quoted / tab-bearing / renamed paths are classified on their real names"

# ── R7f: --format json survives a TRACKED pathname containing a literal tab ───────────────
# `-z` removes git's C-quoting, so a real control character now reaches the emitter. A raw tab
# inside a JSON string is invalid, and the caller only finds out when jq dies — the same
# machine-interface failure shape R8c exists to prevent, arriving through a new door.
# The escape itself is asserted WITHOUT jq, so this coverage does not silently vanish on a
# jq-less host — which is what the `skip` below would otherwise mean. The emitter never prints a
# tab for any other reason, so "no raw tab anywhere in the JSON" is exact rather than incidental.
printf '%s' "$_jt" | grep -q "$_TAB" \
  && fail "R7f: --format json emitted a RAW tab; a control character inside a JSON string is invalid and no parser will accept it" || :
printf '%s' "$_jt" | grep -qF 'src/tab\tprod.js' \
  || fail "R7f: the tab-bearing pathname is not present in its escaped backslash-t form in the JSON — it was truncated at the tab, or dropped"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$_jt" | jq -e . >/dev/null 2>&1 \
    || fail "R7f: --format json emitted unparseable output for a pathname containing a literal tab"
  printf '%s' "$_jt" | jq -r '.top_production_files[].file' | grep -qF "src/tab${_TAB}prod.js" \
    || fail "R7f: the tab-bearing pathname did not round-trip through JSON intact (truncated at the tab, or mis-escaped)"
  pass "R7f --format json escapes a literal tab and the pathname round-trips intact"
else
  echo "skip - R7f jq round-trip (jq not installed); the escape itself was still asserted"
fi

# ── R7g: an untracked SYMLINK counts as its link value, not its target's contents ─────────
# `[ -f ]` FOLLOWS a symlink, so a link to a regular file passed the guard and the line count
# read the TARGET. git stores a symlink as a blob holding the link value — exactly one line.
# A link to a 2,000-line file therefore contributed 2,000 lines before commit and 1 after,
# reintroducing precisely the commit-coupling R5b exists to remove. Broken links and links to
# directories are counted 1 by git too, and `[ -f ]` dropped both to 0.
RL="$T/repo-symlink"; mkrepo "$RL"; git -C "$RL" checkout -q -b feature
n_lines 2000 > "$RL/big.txt"                    # untracked regular file
(cd "$RL" && ln -s big.txt link.txt)            # untracked link to a 2,000-line file
(cd "$RL" && ln -s nowhere.txt broken.txt)      # untracked broken link
mkdir "$RL/d"; (cd "$RL" && ln -s d dirlink)    # untracked link to a directory
_pls="$("$TOOL" --repo "$RL" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')"
[ "$_pls" = "2003" ] \
  || fail "R7g: production_lines=$_pls, expected 2003 (2000 + one line per symlink) — a symlink was read THROUGH to its target"
git -C "$RL" add -A && git -C "$RL" commit -qm "same content, now committed"
_pls2="$("$TOOL" --repo "$RL" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')"
[ "$_pls2" = "$_pls" ] \
  || fail "R7g: committing changed the count from $_pls to $_pls2 — symlink handling still couples the measurement to whether the Builder committed"
pass "R7g untracked symlinks count one line each, committed or not"

# ── R8: usage errors are the ONLY non-zero exit, and they measure nothing ────────────────
if "$TOOL" --repo "$T/definitely-not-a-repo" --base main >/dev/null 2>&1; then
  fail "R8: a non-git directory should exit 4"
fi
"$TOOL" --repo "$T/definitely-not-a-repo" --base main >/dev/null 2>&1 || _rc=$?
[ "${_rc:-0}" = "4" ] || fail "R8: non-git directory exited ${_rc:-0}, expected 4"
"$TOOL" --repo "$R" --base no/such/ref >/dev/null 2>&1 || _rc2=$?
[ "${_rc2:-0}" = "4" ] || fail "R8: unresolvable base ref exited ${_rc2:-0}, expected 4"
"$TOOL" --format bogus --repo "$R" >/dev/null 2>&1 || _rc3=$?
[ "${_rc3:-0}" = "4" ] || fail "R8: bad --format exited ${_rc3:-0}, expected 4"
pass "R8 exit 4 for not-a-repo / unresolvable base / bad --format; never for a large diff"

# ── R8b: a clean tree reports ZERO files, not a phantom one ──────────────────────────────
# An empty $stats still reaches awk as one blank record. Counted as a production file, a
# clean tree reports production_files: 1 — and a branch sitting on exactly advise_files or
# escalate_files gets pushed into the next tier by a file that does not exist.
RC="$T/repo-clean"; mkrepo "$RC"; git -C "$RC" checkout -q -b feature
_j="$("$TOOL" --repo "$RC" --base main --format json)"
[ "$(printf '%s' "$_j" | sed -n 's/.*"production_files":\([0-9]*\).*/\1/p')" = "0" ] \
  || fail "R8b: a clean tree reported a phantom production file"
[ "$(printf '%s' "$_j" | sed -n 's/.*"total_files":\([0-9]*\).*/\1/p')" = "0" ] \
  || fail "R8b: a clean tree reported a phantom changed file"
pass "R8b a clean tree reports zero files, not one phantom record"

# ── R8c: --format json stays parseable for a filename containing a quote ─────────────────
# A path with `"` interpolated raw produces output that EXITS 0 and is unparseable — the
# worst shape for a machine interface, because the caller only finds out when jq dies.
if command -v jq >/dev/null 2>&1; then
  RQ="$T/repo-quote"; mkrepo "$RQ"; git -C "$RQ" checkout -q -b feature
  n_lines 3 > "$RQ/a\"b.js"
  git -C "$RQ" add -A && git -C "$RQ" commit -qm "a filename with a quote in it"
  "$TOOL" --repo "$RQ" --base main --format json | jq -e . >/dev/null 2>&1 \
    || fail "R8c: --format json emitted unparseable output for a filename containing a quote"
  pass "R8c --format json survives a filename containing a quote"
else
  echo "skip - R8c (jq not installed)"
fi

# ── R9: the Reviewer and Orchestrator carry the handoff rule ─────────────────────────────
grep -qF 'tools/change-size.sh' "$ROOT/agents/reviewer.md" \
  || fail "R9: reviewer.md does not run the change-size check before the PR handoff"
grep -qF 'tools/change-size.sh' "$ROOT/agents/orchestrator.md" \
  || fail "R9: orchestrator.md does not run the change-size check before opening the PR"
grep -qi 'never blocks' "$ROOT/agents/reviewer.md" \
  || fail "R9: reviewer.md does not state that the change-size check never blocks"
grep -qi 'recorded decision\|record one line\|split plan' "$ROOT/agents/reviewer.md" \
  || fail "R9: reviewer.md does not require a recorded decision at advise/escalate"
pass "R9 reviewer + orchestrator carry the advisory handoff rule"

# ── R9b: the Orchestrator's pre-PR handoff is on the MAIN path, not only the fix lane ─────
# R9 above greps the whole file, so it stayed green while the only copy of the instruction sat
# inside the fenced "## Targeted parallel-fix worker mode" section — which is entered only for a
# /sdd-fix-parallel E99 worker. Ordinary features routed through the main `in-review` flow, and
# umbrella child PRs, never reached it, so the tier never reached those PR bodies at all. Assert
# against the file with that fenced section REMOVED, which is the only form of this check that
# can fail when the instruction is fix-lane-only.
_ORCH="$ROOT/agents/orchestrator.md"
_ORCH_SECTION='The pre-PR change-size handoff'
_outside="$(awk '
  /^## Targeted parallel-fix worker mode/ { skip = 1; next }
  /^## / { skip = 0 }
  !skip
' "$_ORCH")"
printf '%s\n' "$_outside" | grep -qF 'tools/change-size.sh' \
  || fail "R9b: orchestrator.md runs the change-size check ONLY inside the parallel-fix worker mode — the main in-review → PR path never reaches it"
# Everything about WHAT the main-path handoff must say is asserted against the SECTION, not
# against `$_outside`. `$_outside` is the whole file minus the fenced worker mode, and it is the
# right scope for exactly one question — "is the instruction fix-lane-only?" — because that
# question is about the file as a whole. It is the wrong scope for every other question here: a
# phrase like "PR body" occurs elsewhere in the file for unrelated reasons (this feature's own
# umbrella child-PR sub-step is one), so a `$_outside` grep is satisfied no matter what the
# section says, and the failure message ends up naming a guarantee it cannot detect.
# `index()` on a heading line, not a regex, so the heading text needs no escaping.
# Resets on `/^#+ /` — ANY heading level — whereas `_rev_cs` below resets on `^## `. That is not
# an oversight: this target is a `###` section, so the next `###` sibling ends it, while
# `_rev_cs`'s target is a `##` section, which may legitimately contain `###` subsections that
# belong to it. Each extractor stops at the first heading that could not be part of its own
# section, which is why the two differ.
export CS_ORCH_SECTION="$_ORCH_SECTION"
_main_cs="$(awk '
  BEGIN { h = ENVIRON["CS_ORCH_SECTION"] }
  /^#+ / { keep = (index($0, h) > 0); next }
  keep
' "$_ORCH")"
[ -n "$(printf '%s' "$_main_cs" | tr -d '[:space:]')" ] \
  || fail "R9b: could not extract the '$_ORCH_SECTION' section from orchestrator.md — the heading was renamed or removed, so every assertion below it would pass vacuously"
printf '%s\n' "$_main_cs" | grep -qF 'tools/change-size.sh' \
  || fail "R9b: the main-path handoff section does not actually invoke tools/change-size.sh — it only talks about it"
# Deliberately NOT narrowed to a single fixed phrase. "PR body" occurs three times in this
# section, all three stating the same contract in different words — so a survivor here is
# evidence the contract is still stated, which is the opposite of B2 (a match in an unrelated
# part of the file) and B3 (a match in arbitrary English). Pinning one exact sentence would trade
# a real guarantee for brittleness against legitimate rewording of that same guarantee, in the
# same section, and lose that distinction. Within-section paraphrase is signal, not noise.
printf '%s\n' "$_main_cs" | grep -qi 'PR body' \
  || fail "R9b: the main-path handoff does not say to carry the tier into the PR body (E21-F02)"
printf '%s\n' "$_main_cs" | grep -qi 'never blocks\|advisory' \
  || fail "R9b: the main-path handoff does not state that the check is advisory and never blocks"
# The parallel-fix section must NOT be weakened on the way: its --repo caveat is load-bearing
# because HARNESS_DIR locates the script, not the tree under measurement.
_inside="$(awk '
  /^## Targeted parallel-fix worker mode/ { keep = 1; next }
  /^## / { keep = 0 }
  keep
' "$_ORCH")"
printf '%s\n' "$_inside" | grep -qF -- '--repo' \
  || fail "R9b: the parallel-fix worker mode lost its --repo caveat — a worker spawned from the canonical primary would measure the coordinator's bookkeeping branch"
# …and the REASON, not just the flag. `--repo` appears several times in that section, so the flag
# alone is satisfied by the bare invocation even after the explanation is deleted — the caveat is
# the load-bearing part, because a reader who does not know WHY will drop the flag the first time
# it looks redundant. Match the distinctive CLAUSE, not `HARNESS_DIR`: that token appears four
# times in this section for unrelated worker-setup reasons, so keying on it would be satisfied by
# any of them — the same reachable-another-way defect this assertion exists to close.
printf '%s\n' "$_inside" | grep -qF 'not the tree under measurement' \
  || fail "R9b: the parallel-fix worker mode still names --repo but no longer explains WHY (HARNESS_DIR locates the script, not the tree under measurement) — a reader who does not know why drops the flag the first time it looks redundant"
# Cross-file consistency: the Reviewer holds the other half of this handoff, so its OWN
# change-size section must agree that the Orchestrator repeats the check on every PR it opens.
# Scope the grep to that section — reviewer.md says "slice PR" and "child repo" elsewhere for
# unrelated reasons, and a whole-file grep would pass no matter what the section said. (This is
# the same reasoning `_main_cs` above now applies to orchestrator.md; it was written here first
# and simply never carried across.)
_rev_cs="$(awk '
  /^## Change-size check before the PR handoff/ { keep = 1; next }
  /^## / { keep = 0 }
  keep
' "$ROOT/agents/reviewer.md")"
printf '%s\n' "$_rev_cs" | grep -qi 'orchestrator' \
  || fail "R9b: reviewer.md's change-size section never mentions the Orchestrator's half of the handoff"
printf '%s\n' "$_rev_cs" | grep -qF "$_ORCH_SECTION" \
  || fail "R9b: reviewer.md does not cite orchestrator.md's '$_ORCH_SECTION' section — the two copies of the rule can drift apart unnoticed"
# …and the cited section must actually exist as a heading, or the citation is a dead reference.
grep -qE "^#+ .*$_ORCH_SECTION" "$_ORCH" \
  || fail "R9b: reviewer.md cites an orchestrator.md section '$_ORCH_SECTION' that has no matching heading"
pass "R9b the pre-PR change-size handoff fires on the main path, with the fix lane's --repo caveat intact"

# ── R9c: the harness records the rule that five assertions in this feature broke ──────────
# Five assertions added by E99-F07 passed while the guarantee they named was absent — three of
# them a whole-file grep over a prose contract, and the fifth was the first version of the LAST
# assertion in this very block. That is a rule gap, not five accidents, so the rule lives in the
# installed body rather than only in a review thread. Asserted here, beside the assertions that
# motivated it, because there is no builder-prose suite; move it if one appears.
_BUILDER="$ROOT/agents/builder.md"
grep -qi 'section it names\|grep the SECTION' "$_BUILDER" \
  || fail "R9c: builder.md does not carry the rule that a prose-contract test must grep the SECTION it names, not the whole file"
grep -qF 'index($0,h)' "$_BUILDER" \
  || fail "R9c: builder.md states the section-scoping rule but gives no extraction recipe — the rule is only followed when it is copy-pasteable"
# The lens itself, matched as DISTINCTIVE FIXED substrings — one per operative clause.
# The first version of this assertion was `grep -qi 'reachable\|other than the one'`, and it was
# the fifth instance of the very pattern it guards: those are ordinary English words, so replacing
# the whole bullet with an unrelated one about dead code left the suite green while the lens was
# gone from the installed body. Use `-qF` on a phrase only the intended sentence can produce,
# never `-qi` with alternation over common words. Each clause is asserted separately because
# deleting any one of them guts the rule a different way: the lens without its question is a
# slogan, and the question without the mutation step invites reasoning about the answer instead of
# running it — which is precisely how the abandoned `HARNESS_DIR` tightening got written.
grep -qF 'expected value being reachable ONE way' "$_BUILDER" \
  || fail "R9c: builder.md does not carry the underlying lens (is this expected value reachable by more than one path?)"
grep -qF 'path other than the one the failure message names' "$_BUILDER" \
  || fail "R9c: builder.md names the lens but not the question that operationalises it"
grep -qF 'the fix in place and confirming the test fails' "$_BUILDER" \
  || fail "R9c: builder.md poses the question but no longer requires PROVING the answer by mutation — the lens is not reliable as a reasoning exercise"
pass "R9c builder.md carries the section-scoping rule and the reachable-another-way lens"

echo "All change-size tests passed."
