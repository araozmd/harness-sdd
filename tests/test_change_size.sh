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
mkdir -p "$R/src" "$R/tests" "$R/specs" "$R/vendor" "$R/coverage"
n_lines 40  > "$R/src/app.js"        # production
n_lines 10  > "$R/src/util.js"       # production
n_lines 300 > "$R/tests/app.test.js" # test  — must NOT count as production
n_lines 200 > "$R/specs/design.md"   # doc   — must NOT count as production
n_lines 900 > "$R/vendor/lib.js"     # generated — excluded entirely
n_lines 100 > "$R/coverage/lcov.info"   # generated — coverage OUTPUT into a NON-ignored dir
n_lines 60  > "$R/src/app.js.mutbak"    # generated — mutation backup, deliberately NOT gitignored
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
[ "$(_get generated_lines)" = "1060" ] || fail "R1: generated_lines=$(_get generated_lines), expected 1060 (vendor 900 + coverage output 100 + .mutbak 60 — coverage OUTPUT and unignored mutation backups classify as generated)"
[ "$(_get total_lines)" = "1610" ]    || fail "R1: total_lines=$(_get total_lines), expected 1610"
pass "R1 classification: production excludes tests, docs and generated files (incl. coverage output + unignored .mutbak)"

# ── R1b: coverage/ is matched by OUTPUT SHAPE, never by bare directory name ──────────────
# A consumer whose real product lives under coverage/ (a coverage service or library) must
# never have its change zeroed out of the budget by a name collision (Codex #160 P2): only
# report files (.info/.html/.json/.xml/.txt directly under coverage/) and the lcov-report/
# + tmp/ subtrees are output; source under coverage/ counts as production.
RC1="$T/repo-coverage"; mkrepo "$RC1"
git -C "$RC1" checkout -q -b feature
mkdir -p "$RC1/coverage/lib" "$RC1/coverage/lcov-report"
n_lines 30 > "$RC1/coverage/service.js"          # production — source at coverage/ root
n_lines 25 > "$RC1/coverage/lib/parse.js"        # production — source in a coverage/ subdir
n_lines 15 > "$RC1/coverage/package.json"        # production — product JSON at coverage/ root
n_lines 5  > "$RC1/coverage/rules.json"          # production — product config JSON
n_lines 90 > "$RC1/coverage/lcov.info"           # generated — report file
n_lines 40 > "$RC1/coverage/lcov-report/i.html"  # generated — report subtree
n_lines 10 > "$RC1/coverage/coverage-final.json" # generated — conventional JSON report name
git -C "$RC1" add -A && git -C "$RC1" commit -qm work
_jc="$("$TOOL" --repo "$RC1" --base main --format json)"
[ "$(printf '%s' "$_jc" | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')" = "75" ] \
  || fail "R1b: production under coverage/ was misclassified (expected 75 incl. root JSON, got $(printf '%s' "$_jc" | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')) — a name collision zeroes a real product's budget"
[ "$(printf '%s' "$_jc" | sed -n 's/.*"generated_lines":\([0-9]*\).*/\1/p')" = "140" ] \
  || fail "R1b: coverage OUTPUT not classified generated (expected 140 incl. coverage-final.json, got $(printf '%s' "$_jc" | sed -n 's/.*"generated_lines":\([0-9]*\).*/\1/p'))"
pass "R1b coverage output (incl. conventional JSON report names) classifies as generated; source and product JSON under coverage/ stay production"

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

# ── R5d: GITIGNORED scratch never moves the count (E99-F71/F89) ──────────────────────────
# The counterpart to R5b, and the boundary between them is the whole fix. R5b requires that
# untracked Builder output IS measured; that same inclusion also swept in per-developer
# scaffolding and mutation-campaign backups, and the tier went wrong in BOTH directions:
# `.mutbak` copies reported production 1104 lines / 2 files against a true 42/1 (a 26x
# OVERSTATEMENT, E99-F71), and viernes-web's 78 untracked install artifacts reported
# ESCALATE 3965/87 for a branch that measured ADVISE 1811/9 (E99-F89).
#
# The fix is NOT to stop measuring the working tree — that reintroduces the exact defect R5b
# exists to prevent, trading a 26x overstatement for a 100% understatement on a check that
# runs before the Builder has committed. `ls-files --others --exclude-standard` already
# honours .gitignore, so the correct fix is that the noise be IGNORED at its source. This
# pins the mechanism so a future edit cannot quietly drop --exclude-standard.
RI="$T/repo-ignored"; mkrepo "$RI"
# The ignore rules land on MAIN, before the branch: they are pre-existing repo policy, not
# part of the change under measurement. Committing them on the feature branch would put the
# .gitignore edit itself into the diff and inflate the expected count by its own line total.
printf 'scratch/\n*.mutbak\n__pycache__/\n' >> "$RI/.gitignore"
git -C "$RI" add .gitignore && git -C "$RI" commit -qm "ignore scratch"
git -C "$RI" checkout -q -b feature
mkdir -p "$RI/src" "$RI/scratch" "$RI/__pycache__"
n_lines 42 > "$RI/src/real-feature.js"                 # untracked, real work — MUST count
n_lines 900 > "$RI/scratch/notes.js"                   # ignored dir       — must NOT count
n_lines 800 > "$RI/src/real-feature.js.mutbak"         # mutation backup   — must NOT count
n_lines 700 > "$RI/__pycache__/mod.cpython-313.pyc"    # bytecode cruft    — must NOT count
_pi="$("$TOOL" --repo "$RI" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')"
[ "$_pi" = "42" ] \
  || fail "R5d: production_lines=$_pi, expected 42 — gitignored scratch is inflating the tier (E99-F71/F89)"
_fi="$("$TOOL" --repo "$RI" --base main --format json | sed -n 's/.*"production_files":\([0-9]*\).*/\1/p')"
[ "$_fi" = "1" ] \
  || fail "R5d: production_files=$_fi, expected 1 — gitignored scratch is inflating the FILE budget"
pass "R5d gitignored scratch never moves the count, while untracked real work still does"

# ── R5e: TRACKED generated agent surfaces are classified, not counted (E99-F71/F89) ───────
# The other half of R5d, and the correction to its first revision. The harness body and the
# agent surfaces harness-install.sh writes are installer OUTPUT in every consumer, so they
# must not crowd a product budget — but they must also stay TRACKED, because the documented
# install workflow is committed-and-shared and a fresh clone needs them. Ignoring them (the
# first attempt) would have left every Codex skill, Antigravity rule and OpenCode command out
# of a clone; classifying them removes the distortion without hiding a single file.
RG="$T/repo-generated"; mkrepo "$RG"
# mkrepo seeds `.harness/` into .gitignore so its per-assertion config rewrites stay out of
# the measured diff. R5e is the one case that must NOT ignore it: the whole point is that the
# body is TRACKED and excluded by classification rather than by an ignore. R5e never calls
# cfgw, so it needs no config file and loses nothing by dropping that line.
: > "$RG/.gitignore"
git -C "$RG" add .gitignore && git -C "$RG" commit -qm "track .harness/ (R5e)"
git -C "$RG" checkout -q -b feature
mkdir -p "$RG/src" "$RG/.harness/agents" "$RG/.claude/commands" "$RG/.agents" "$RG/.codex" "$RG/.opencode/command"
n_lines 30   > "$RG/src/real-feature.js"                  # production — MUST count
n_lines 900  > "$RG/.harness/agents/builder.md"           # vendored body    — must NOT count
n_lines 400  > "$RG/.claude/commands/sdd-next.md"         # generated glue   — must NOT count
n_lines 300  > "$RG/.agents/builder.md"                   # generated glue   — must NOT count
n_lines 200  > "$RG/.codex/agents.md"                     # generated glue   — must NOT count
n_lines 100  > "$RG/.opencode/command/sdd-next.md"        # generated glue   — must NOT count
n_lines 50   > "$RG/CLAUDE.md"                            # HAND-authored    — MUST count
git -C "$RG" add -A && git -C "$RG" commit -qm "tracked, exactly as a real install commits it"
_pg="$("$TOOL" --repo "$RG" --base main --format json | sed -n 's/.*"production_lines":\([0-9]*\).*/\1/p')"
[ "$_pg" = "80" ] \
  || fail "R5e: production_lines=$_pg, expected 80 (30 src + 50 CLAUDE.md) — generated agent surfaces are being charged to the product budget"
# ...and they are TRACKED, not ignored: the files must really be in the index.
for _f in .harness/agents/builder.md .claude/commands/sdd-next.md .agents/builder.md; do
  git -C "$RG" ls-files --error-unmatch "$_f" >/dev/null 2>&1 \
    || fail "R5e: $_f is not tracked — a fresh clone would not receive it"
done
pass "R5e generated agent surfaces stay tracked and are classified out of the budget, while hand-authored CLAUDE.md still counts"

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

# ── R8d: --format json escapes EVERY C0 control character, not just tab ─────────────────
# E99-F07 moved the tracked path scan to `--numstat -z`, which stops git C-quoting special
# characters — so a raw control byte in a TRACKED pathname now reaches the JSON emitter
# unencoded. The emitter escaped `\`, `"` and tab only, so a tracked `a<CR>b.js` made
# --format json EXIT 0 while emitting JSON jq rejects with an invalid-control-character
# error — fail-silent on a machine interface. The fix escapes the CLASS (short escapes for
# `\b \t \n \f \r`, `\u00XX` for the rest of U+0000–U+001F), not a CR rule beside the tab
# rule. The fixture below exercises one short escape (CR) and one `\u00XX` escape (VT), so
# each branch of the class is asserted against a real byte.
# jq-free halves first (the R7f lesson): the emitter prints CR/VT for no other reason, so
# "no raw byte anywhere in the JSON" is exact, and the escaped form must be present verbatim.
RCR="$T/repo-cr"; mkrepo "$RCR"; git -C "$RCR" checkout -q -b feature
_CR="$(printf '\r')"; _VT="$(printf '\013')"
n_lines 3 > "$RCR/a${_CR}b.js"               # raw carriage return in a TRACKED pathname
n_lines 2 > "$RCR/v${_VT}b.js"               # raw vertical tab — the \u00XX branch
git -C "$RCR" add -A && git -C "$RCR" commit -qm "control characters in tracked pathnames"
_jcr="$("$TOOL" --repo "$RCR" --base main --format json)"
printf '%s' "$_jcr" | grep -q "$_CR" \
  && fail "R8d: --format json emitted a RAW carriage return; a control character inside a JSON string is invalid and the caller only finds out when jq dies" || :
printf '%s' "$_jcr" | grep -qF 'a\rb.js' \
  || fail "R8d: the CR-bearing pathname is not present in its escaped backslash-r form in the JSON — it was emitted raw, truncated, or dropped"
printf '%s' "$_jcr" | grep -q "$_VT" \
  && fail "R8d: --format json emitted a RAW vertical tab; the \u00XX branch of the C0 escape is missing" || :
_BS='\'; _VT_ESC="v${_BS}u000bb.js"    # the escaped form: v, one backslash, u000b, b.js
printf '%s' "$_jcr" | grep -qF "$_VT_ESC" \
  || fail "R8d: the VT-bearing pathname is not present in its escaped \\u000b form in the JSON"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$_jcr" | jq -e . >/dev/null 2>&1 \
    || fail "R8d: --format json emitted unparseable output for a pathname containing a control character"
  printf '%s' "$_jcr" | jq -r '.top_production_files[].file' | grep -qF "a${_CR}b.js" \
    || fail "R8d: the CR-bearing pathname did not round-trip through JSON intact"
  printf '%s' "$_jcr" | jq -r '.top_production_files[].file' | grep -qF "v${_VT}b.js" \
    || fail "R8d: the VT-bearing pathname did not round-trip through JSON intact"
  pass "R8d --format json escapes the C0 class (CR short escape + VT \u00XX form) and both pathnames round-trip intact"
else
  echo "skip - R8d jq round-trip (jq not installed); both escapes were still asserted jq-free"
fi

# ── R8e: a TRACKED pathname containing a literal NEWLINE round-trips intact ─────────────
# Codex on PR #89: `-z` stops git C-quoting, but the NUL-to-LF `tr` that framed the records
# made a content LF indistinguishable from a record separator — a tracked `a\nb.js` split
# mid-path, the counts landed on the first FRAGMENT (`a`), and `x\n_test.py` was charged to
# PRODUCTION because the classifier never saw the test suffix. Fail-silent budget corruption:
# the JSON stayed parseable and the number was wrong. The framing parse is now byte-exact
# (python3 splits real NULs, folds renames, encodes `\` then LF), the classifier decodes
# before matching, and the concentration list decodes only at emission.
# jq-free halves first (the R7f lesson). The discriminator for "no raw LF leaked into the
# JSON" is exact without jq: the emitter prints a single trailing newline and nothing else,
# so after command-substitution stripping the captured JSON must contain NO newline at all.
RLF="$T/repo-lf"; mkrepo "$RLF"
# NOT `_LF="$(printf '\n')"` — command substitution strips trailing newlines, leaving _LF
# EMPTY, and every pathname below would contain no newline at all: the fixture without the
# byte is the reachable-another-way defect this suite exists to kill. Decode with a sentinel
# and remove exactly that character.
_LF="$(printf '\n.')"; _LF=${_LF%.}
n_lines 5 > "$RLF/oldname.js"
git -C "$RLF" add -A && git -C "$RLF" commit -qm "rename base"
git -C "$RLF" checkout -q -b feature
mkdir -p "$RLF/src"
n_lines 3 > "$RLF/src/a${_LF}b.js"              # raw newline in a TRACKED pathname
n_lines 4 > "$RLF/evil${_LF}_test.py"           # newline before a test suffix — must stay TEST
git -C "$RLF" mv oldname.js "ren${_LF}amed.js"  # rename onto a newline-bearing path
git -C "$RLF" add -A && git -C "$RLF" commit -qm "newline-bearing pathnames"
n_lines 2 > "$RLF/un${_LF}tracked.js"           # raw newline in an UNTRACKED pathname
_jlf="$("$TOOL" --repo "$RLF" --base main --format json)"
# NOT grep: a newline PATTERN is an empty pattern (grep splits patterns on newlines) and
# matches every line — the reachable-another-way defect in miniature. case globbing matches
# the literal byte, and the emitter prints a single trailing newline and nothing else, so
# after command-substitution stripping ANY surviving newline is a leak.
case "$_jlf" in
  *"$_LF"*) fail "R8e: --format json emitted a RAW newline; the pathname was emitted unescaped (or split) and jq will reject it" ;;
esac
printf '%s' "$_jlf" | grep -qF 'src/a\nb.js' \
  || fail "R8e: the newline-bearing pathname is not present in its escaped backslash-n form in the JSON — it was split at the newline, or dropped"
_glf() { printf '%s' "$_jlf" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }
[ "$(_glf test_lines)" = "4" ] \
  || fail "R8e: test_lines=$(_glf test_lines), expected 4 — a newline-bearing TEST path was charged to production (the counts landed on the fragment before the newline)"
[ "$(_glf production_lines)" = "5" ] \
  || fail "R8e: production_lines=$(_glf production_lines), expected 5 (3 tracked + 0 pure rename + 2 untracked)"
[ "$(_glf production_files)" = "3" ] \
  || fail "R8e: production_files=$(_glf production_files), expected 3 (a<LF>b.js, ren<LF>amed.js, un<LF>tracked.js)"
[ "$(_glf total_files)" = "4" ] \
  || fail "R8e: total_files=$(_glf total_files), expected 4 — a rename onto a newline-bearing path must still fold to ONE record keyed on the destination"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$_jlf" | jq -e . >/dev/null 2>&1 \
    || fail "R8e: --format json emitted unparseable output for a pathname containing a newline"
  printf '%s' "$_jlf" | jq -e --arg w "src/a${_LF}b.js" '[.top_production_files[].file] | index($w) != null' >/dev/null \
    || fail "R8e: the tracked newline-bearing pathname did not round-trip through JSON byte-exact"
  printf '%s' "$_jlf" | jq -e --arg w "un${_LF}tracked.js" '[.top_production_files[].file] | index($w) != null' >/dev/null \
    || fail "R8e: the untracked newline-bearing pathname did not round-trip through JSON byte-exact"
  pass "R8e newline-bearing tracked/untracked/renamed pathnames classify correctly and round-trip through JSON byte-exact"
else
  echo "skip - R8e jq round-trip (jq not installed); classification and the escaped form were still asserted jq-free"
fi

# ── R8f: the concentration list EXCLUDES on the decoded path, like the totals ───────────
# Codex PR #89 round 3: the totals classify the DECODED pathname but `top` applied the same
# exclusion regexes to the transit-ENCODED form. For the built-ins the two agree, but a
# CONFIGURED generated_paths/test_paths regex can tell them apart: `^foo\\nbar[.]js$` (one
# literal backslash) matches the ENCODED form of `foo<LF>bar.js`, excluding from the list a
# file the totals charge to production; and a real-backslash `foo\nbar.js` goes the other
# way — generated in the totals, yet listed as production. Both directions are asserted
# against jq, byte-exact; the count assertions stay jq-free.
RGF="$T/repo-genre"; mkrepo "$RGF"; git -C "$RGF" checkout -q -b feature
mkdir -p "$RGF/.harness"
cat > "$RGF/.harness/harness.config.yaml" <<'EOF'
change_size:
  generated_paths:
    - "^foo\\nbar[.]js$"
EOF
n_lines 7  > "$RGF/foo${_LF}bar.js"      # real newline: decoded form does NOT match the regex
n_lines 11 > "$RGF/foo\nbar.js"          # real backslash-n: decoded form DOES match (generated)
git -C "$RGF" add -A && git -C "$RGF" commit -qm "encoded-vs-decoded classifier gap"
_jgf="$("$TOOL" --repo "$RGF" --base main --format json)"
_ggf() { printf '%s' "$_jgf" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }
[ "$(_ggf production_lines)" = "7" ] \
  || fail "R8f: production_lines=$(_ggf production_lines), expected 7 — the real-newline path belongs to production"
[ "$(_ggf generated_lines)" = "11" ] \
  || fail "R8f: generated_lines=$(_ggf generated_lines), expected 11 — the real-backslash path matches the configured regex only AFTER decoding"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$_jgf" | jq -e --arg w "foo${_LF}bar.js" '[.top_production_files[].file] | index($w) != null' >/dev/null \
    || fail "R8f: a PRODUCTION file (real newline) was excluded from top_production_files — the list matched the ENCODED form against the configured regex"
  printf '%s' "$_jgf" | jq -e --arg w 'foo\nbar.js' '[.top_production_files[].file] | index($w) == null' >/dev/null \
    || fail "R8f: a GENERATED file (real backslash-n) was listed as production — the list matched the ENCODED form, which the regex does not hit"
  pass "R8f the concentration list excludes on the decoded pathname, exactly like the totals"
else
  echo "skip - R8f jq list membership (jq not installed); both counts were still asserted jq-free"
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
# ⚠️ EVERY heading-driven extractor below is FENCE-AWARE, and that is not decoration.
# A naive `/^#+ /` (or `/^## /`) test also matches a shell COMMENT inside a fenced block —
# orchestrator.md already carries one (`# a SLICED feature: …`, in the `Writing \`done\``
# section) — and the slice then ENDS THERE. The result is worse than extracting nothing: a
# truncated section is still NON-EMPTY, so the emptiness guard below passes while every
# assertion under it runs against a prefix. That exact failure was measured during E99-F102
# part A (a 37-line prefix, green suite, assertions enforcing a third of what they named), so
# each extractor is paired with an ANTI-TRUNCATION CONTROL keyed on a marker from the END of
# its section — an emptiness check alone cannot tell a whole section from its first paragraph.
# The fence DELIMITER lines are still printed when they fall inside the kept region; only
# their heading-ness is suppressed.
#
# `fence_delim()` comes from tests/lib/fence.awk — ONE copy, shared by every suite that
# slices markdown, because "is this line a fence?" is exactly the question the harness has
# now got wrong twice. It implements the real CommonMark rule (tilde as well as backtick,
# 0-3 spaces of indent, an opener longer than three closed only by a run at least as long),
# which `/^```/ { fence = !fence }` does not: orchestrator.md carries three INDENTED
# ```` ```json ```` fences that the naive toggle mis-tracks today. That is latent rather than
# live — those blocks are properly paired and hold no column-0 `#` — but "green by luck of
# current content" is the precise condition this whole check exists to remove, so it is fixed
# on the same argument. R9d below exercises each delimiter form.
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
_outside="$(awk "$FENCE_AWK"'
  fence_delim($0) { if (!skip) print; next }
  !fence && /^## Targeted parallel-fix worker mode/ { skip = 1; next }
  !fence && /^## / { skip = 0 }
  !skip
' "$_ORCH")"
# CONTROL (excision): `$_outside` is only a meaningful scope if the worker-mode section was
# actually REMOVED from it. Without this, a mis-scoped extractor that returned the whole file
# would satisfy the fix-lane-only question below no matter where the instruction lived — the
# assertion would pass and its failure message would name a guarantee it cannot detect.
printf '%s\n' "$_outside" | grep -qF 'worker board transitions remain lock-safe' \
  && fail "R9b control: the parallel-fix worker mode was NOT excised from the whole-file scope — the fix-lane-only assertion below would pass no matter where the change-size instruction lives"
# CONTROL (no over-drop): the excision must end at the section, not run to EOF.
printf '%s\n' "$_outside" | grep -qF 'exits 0 with a "no telemetry yet" notice' \
  || fail "R9b control: the whole-file-minus-worker-mode scope does not reach the end of orchestrator.md — the excision swallowed everything after the section, so the assertion below is measuring a prefix"
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
_main_cs="$(awk "$FENCE_AWK"'
  BEGIN { h = ENVIRON["CS_ORCH_SECTION"] }
  fence_delim($0) { if (keep) print; next }
  !fence && /^#+ / { keep = (index($0, h) > 0); next }
  keep
' "$_ORCH")"
[ -n "$(printf '%s' "$_main_cs" | tr -d '[:space:]')" ] \
  || fail "R9b: could not extract the '$_ORCH_SECTION' section from orchestrator.md — the heading was renamed or removed, so every assertion below it would pass vacuously"
# ANTI-TRUNCATION: the emptiness guard above cannot distinguish the whole section from its
# first two lines. This section's LAST sentence hands the tier to the PR body and cites the
# Reviewer's half — the very half `_rev_cs` below cross-checks — so if the extraction does not
# reach it, the `_rev_cs` citation assertions are being paired against a section nobody read.
printf '%s\n' "$_main_cs" | grep -qF 'your PR body carries it forward' \
  || fail "R9b: the '$_ORCH_SECTION' extraction does not reach its final sentence — it was TRUNCATED, so every assertion below runs against a prefix (a truncated section is still non-empty, so the guard above cannot catch this)"
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
_inside="$(awk "$FENCE_AWK"'
  fence_delim($0) { if (keep) print; next }
  !fence && /^## Targeted parallel-fix worker mode/ { keep = 1; next }
  !fence && /^## / { keep = 0 }
  keep
' "$_ORCH")"
[ -n "$(printf '%s' "$_inside" | tr -d '[:space:]')" ] \
  || fail "R9b: could not extract the 'Targeted parallel-fix worker mode' section from orchestrator.md — the heading was renamed or removed, so every assertion below it would pass vacuously"
# ANTI-TRUNCATION, same reasoning as `_main_cs`: key on the section's CLOSING sentence.
printf '%s\n' "$_inside" | grep -qF 'worker board transitions remain lock-safe' \
  || fail "R9b: the 'Targeted parallel-fix worker mode' extraction does not reach its final sentence — it was TRUNCATED, so the --repo caveat assertions below run against a prefix"
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
_rev_cs="$(awk "$FENCE_AWK"'
  fence_delim($0) { if (keep) print; next }
  !fence && /^## Change-size check before the PR handoff/ { keep = 1; next }
  !fence && /^## / { keep = 0 }
  keep
' "$ROOT/agents/reviewer.md")"
[ -n "$(printf '%s' "$_rev_cs" | tr -d '[:space:]')" ] \
  || fail "R9b: could not extract the 'Change-size check before the PR handoff' section from reviewer.md — the heading was renamed or removed, so every assertion below it would pass vacuously"
# ANTI-TRUNCATION: this section's last paragraph IS the cross-file half being asserted (it
# names the Orchestrator and cites its section), and it sits after a fenced `sh` block. An
# extraction that stops at the fence is non-empty and would make both greps below vacuous.
printf '%s\n' "$_rev_cs" | grep -qF 'on the assumption the Orchestrator will re-derive it' \
  || fail "R9b: the reviewer.md change-size section extraction does not reach its final sentence — it was TRUNCATED, so the cross-file citation assertions below run against a prefix"
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

# ── R9d: the shared fence rule is CommonMark's, per DELIMITER FORM ────────────────────────
# The first fix for this defect tracked fences with a column-0 three-backtick toggle. That is
# not the rule: a fence may be TILDE, may be INDENTED up to three spaces, and an opener longer
# than three is closed only by a run of the same character at least as long — so a shorter run
# inside it is content, not a delimiter. Under any of those the block is mis-tracked and a `#`
# line inside it is read as a heading again, which is the same truncation (silent green) or
# over-inclusion (vacuous scope) the extractors above exist to prevent.
#
# LATENT, NOT LIVE, at the time this was written, and worth saying plainly: orchestrator.md's
# three indented ```` ```json ```` fences and docs/WORKFLOW.md's one are properly paired and
# contain no column-0 `#`, so the naive toggle's mis-tracking changed no result. But "correct
# only because of what the files happen to contain today" is precisely the condition R9/R9b
# were in before this feature, and fixing one while declining the other would be incoherent.
#
# Each form is asserted BEHAVIOURALLY — the fixture is sliced by the real extraction program —
# and each is PAIRED WITH A CONTROL that runs the same program against the superseded toggle.
# The control is the load-bearing half: a fixture that both implementations extract whole does
# not exercise the form it is named for, and the assertion above it would prove nothing.
_fx="$T/fence-forms"
mkdir -p "$_fx"
_NAIVE_AWK="$(cat "$ROOT/tests/lib/fence-naive.awk")"

# ONE extraction program, two preludes. Both fence.awk and fence-naive.awk expose the same
# `fence_delim(line)` interface, so the only variable between the two runs is the fence rule.
_slice() {  # _slice <awk-prelude> <file>
  awk "$1"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^#+ / { keep = (index($0, "Target section") > 0); next }
    keep
  ' "$2"
}

cat > "$_fx/tilde.md" <<'FIXEOF'
### Target section

~~~sh
# a column-0 shell comment inside a TILDE fence
echo INSIDE-tilde
~~~

END-MARKER-tilde

### Next section

DECOY-tilde
FIXEOF

cat > "$_fx/indent.md" <<'FIXEOF'
### Target section

   ```sh
# a column-0 shell comment inside a 3-space-INDENTED fence
echo INSIDE-indent
   ```

END-MARKER-indent

### Next section

DECOY-indent
FIXEOF

cat > "$_fx/long.md" <<'FIXEOF'
### Target section

````sh
```
# a column-0 shell comment after a SHORTER run inside a longer fence
echo INSIDE-long
````

END-MARKER-long

### Next section

DECOY-long
FIXEOF

for _form in tilde indent long; do
  _got="$(_slice "$FENCE_AWK" "$_fx/$_form.md")"
  _naive="$(_slice "$_NAIVE_AWK" "$_fx/$_form.md")"
  printf '%s\n' "$_got" | grep -qF "END-MARKER-$_form" \
    || fail "R9d ($_form): the shared fence rule TRUNCATED the section — the $_form delimiter was mis-tracked, so the column-0 '#' inside the block was read as a heading and every assertion below such a slice would run against a prefix"
  printf '%s\n' "$_got" | grep -qF "DECOY-$_form" \
    && fail "R9d ($_form): the shared fence rule OVER-INCLUDED past the section's end — a scope this wide makes the assertions using it unable to fail"
  printf '%s\n' "$_got" | grep -qF "INSIDE-$_form" \
    || fail "R9d ($_form): the fenced block's own content was swallowed — the rule must suppress a delimiter's heading-ness, not delete the block"
  printf '%s\n' "$_naive" | grep -qF "END-MARKER-$_form" \
    && fail "R9d ($_form) CONTROL: the superseded toggle extracts this fixture whole too, so the fixture does not exercise the $_form delimiter form and the assertion above it proves nothing"
done

# STRUCTURAL: one copy of the rule, loaded — not five hand-rolled toggles that drift apart.
# A second copy is how this defect reached six extractors before anyone noticed.
#
# Checked POSITIVELY (each slicing suite loads the shared file), not as a ban on the naive
# spelling. A ban was written first and rejected on measurement: matching a fence delimiter is
# a legitimate operation in its own right — tests/test_pr_loop.sh's `/^```bash$/` pulls a block
# out of markdown IT generated, where the delimiter spelling is fixed and known — so the ban
# flagged a correct suite, and it also matched prose ABOUT the wrong idiom, including the
# comment a few lines above. A check that reds on correct code is what teaches the next
# maintainer to relax it.
for _s in test_change_size test_source_shims test_scratch_and_disk_preconditions \
          test_landed_evidence test_pr_loop; do
  grep -qF 'tests/lib/fence.awk' "$ROOT/tests/$_s.sh" \
    || fail "R9d: tests/$_s.sh slices markdown by heading but no longer loads tests/lib/fence.awk — it has grown its own fence rule, which is the drift this check exists to prevent"
  # …and LOADING it is not USING it. Checking only for the path made the one-copy invariant
  # unpinned: revert a slicer to the superseded `/^```/{f=!f}` toggle while leaving the
  # FENCE_AWK assignment in place and this loop still passed. Measured — the check said `ok`
  # over a suite that had grown its own rule back. So require the CALL, which is the thing
  # that actually makes the shared rule govern the extraction. Spelled as the exact call form
  # rather than the bare name so a mention in prose or in this very assertion cannot satisfy it.
  grep -qF 'fence_delim($0)' "$ROOT/tests/$_s.sh" \
    || fail "R9d: tests/$_s.sh loads tests/lib/fence.awk but never CALLS fence_delim(\$0) — the shared rule is referenced and not used, so its slicer is running some other fence logic. That is the same second copy the path check was meant to prevent, wearing the path as a disguise"
done
# …and nothing may define the function inline: copying the body in would satisfy the loop
# above only if the path string were left behind as a comment, and defeat it silently
# otherwise. This is the general form of the same question. Spelled as a regex with an
# explicit whitespace class so this line does not match itself — the technique R10 of
# tests/test_scratch_and_disk_preconditions.sh established, and the first draft of this
# assertion needed it: `-qF` on the literal declaration flagged THIS suite.
for _s in "$ROOT"/tests/test_*.sh; do
  grep -qE 'function[[:space:]]+fence_delim' "$_s" \
    && fail "R9d: $(basename "$_s") defines fence_delim() inline instead of loading tests/lib/fence.awk — that is a second copy of the rule, which is exactly the drift this check exists to prevent"
done
# …and per-SLICER, not per-file, and NOT by banning spellings. The call check above proves
# only that SOME slicer in the suite calls the shared rule, and a ban on one toggle spelling
# is a treadmill: `{f=!f}` was banned, `{f=1-f}` is the same toggle and slips straight past.
# Both were measured on this repo's own sect()/span() pair. That is four spellings of one
# defect on this item — a PATH STRING for the call, ONE call for all of them, then one banned
# idiom for every idiom — and each was a proxy standing in for the property.
#
# The property is: every heading slicer calls the shared rule. So assert exactly that, per
# awk PROGRAM. Both the heading reset and the `fence_delim(...)` call live inside the same
# single-quoted awk program in every slicer here, so a program that resets on a heading and
# does not call it is a slicer running its own fence logic — whatever that logic is spelled
# like. python3 does the scan because the suite already depends on it (see `field()`), and a
# spelling-agnostic structural check is worth more than a regex that must be extended each
# time someone writes the same bug differently.
python3 - "$ROOT" <<'PYEOF' || fail "R9d: a heading slicer does not call fence_delim() from tests/lib/fence.awk (see the message above) — it is running its own fence logic, which is the second copy this check exists to prevent"
import glob, os, re, sys
root = sys.argv[1]
# A MARKDOWN heading reset is GENERIC — `/^#+ /` or `/^## /` with nothing after the space.
# A literal banner slices a YAML comment instead, where `#` at column 0 IS the intended
# sentinel and there are no fenced blocks; three suites do that legitimately and must not
# be dragged in. That distinction came out of this PR's eight-suite audit.
HEADING_RESETS = ("/^#+ /", "/^## /")
bad = []
for path in sorted(glob.glob(os.path.join(root, "tests", "test_*.sh"))):
    src = open(path, encoding="utf-8").read()
    # every single-quoted segment; in this codebase an awk program is exactly one of these
    for m in re.finditer(r"'([^']*)'", src, re.S):
        prog = m.group(1)
        # only a segment that is actually an awk PROGRAM — the same quoting shape is used by
        # python heredocs and by ordinary quoted prose, and neither slices markdown.
        if "awk" not in src[max(0, m.start() - 120):m.start()]:
            continue
        if any(h in prog for h in HEADING_RESETS) and "fence_delim(" not in prog:
            bad.append((os.path.basename(path), " ".join(prog.split())[:90]))
for name, snippet in bad:
    sys.stderr.write("  %s: slicer resets on a heading without calling fence_delim(): %s\n" % (name, snippet))
sys.exit(1 if bad else 0)
PYEOF
pass "R9d the shared fence rule handles tilde / indented / long-run delimiters, each proven against the superseded toggle"

echo "All change-size tests passed."
