#!/bin/sh
# test-drift-check.sh — report test-assertion drift between a base ref and a head (E36-F06).
#
# The Reviewer catches a DELETED test because its R-id then has no passing test. It does not
# catch a test whose assertion was WEAKENED so it still passes. This tool turns that into a
# diff a human must look at: for every touched TEST file it lists every removed or modified
# assertion line, every newly added skip/only/xfail marker, and every test name present at
# base and absent at head. It REPORTS AND FAILS; it never judges whether an edit tightened or
# weakened an assertion — that look is the whole point. Diff-based and language-agnostic
# (POSIX sh + git + awk), not AST-based.
#
# Usage:
#   tools/test-drift-check.sh <base-ref> [<head-ref>] [--tasks-md <feature.tasks.md>]
#
#   <base-ref>   the BASE is `git merge-base <base-ref> <head>` (pass the default branch for
#                merge-base semantics, or a pair commit that is an ancestor of head).
#   <head-ref>   omitted: the WORKING TREE (committed + staged + unstaged + untracked,
#                non-ignored). Given: that commit only.
#   --tasks-md   read waivers from this file: lines of the form
#                  waive-test-drift: <exact test name> — <reason>      (— is U+2014)
#                optionally behind a `- ` list marker. A waiver covers every finding
#                attributed to that one test name, byte for byte, and nothing else.
#
# Output (stdout): zero or more finding lines, then exactly one summary line.
#   DRIFT <kind> | <path>:<line> | <test name> | <detail>      kind: assert-modified,
#   WAIVED <kind> | ...                                        assert-removed, skip-added,
#   test-drift-check: <N> findings, <W> waived, <F> test files examined (base <short-sha>)
#                                                              test-removed
#
# Exit codes:
#   0  clean, or every finding waived          1  at least one unwaived finding
#   2  usage error (also unknown flags and malformed waivers; reason on stderr)
#   3  cannot diff (not a git repo, ref does not resolve, no merge base; reason on stderr)
#
# Test files are whatever tools/change-size.sh calls test files: this tool asks its SIBLING
# `change-size.sh --print-test-re` (never a second copy of the classifier) and reads
# change_size.assert_patterns through `change-size.sh --print-list`.
#
# Known limits (the prose must never over-claim): a moved assertion is a `-` line and so a
# finding (waivable); multi-line assertions are detected only on the lines that match; a
# reworded label in an sh suite reads as test-removed; an inserted `exit 0` is not a marker;
# pathnames containing LF or TAB are unsupported; describe( blocks count as test names; the
# shared classifier matches `*.spec.md`, so a spec prose line naming an assertion pattern is a
# finding whose name is the spec's path (waive it by that path).
# Outside the spec, unpinned (round-3 mutation campaign): a JS/TS test name whose closing quote
# is on a later line is not extracted; symlinked test paths are not a supported shape (a dangling
# one reads as empty head text in working-tree mode).

set -eu
LC_ALL=C
export LC_ALL

TAB="$(printf '\t')"
DASH="$(printf '\342\200\224')"          # U+2014, matched byte-wise under LC_ALL=C

usage_err() { # usage_err <reason> — one line on stderr, exit 2
  printf 'test-drift-check: %s\n' "$1" >&2
  exit 2
}
cant_diff() { # cant_diff <reason> — one line on stderr, exit 3
  printf 'test-drift-check: %s\n' "$1" >&2
  exit 3
}

base=""; headref=""; tasks_md=""; npos=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tasks-md) [ $# -ge 2 ] || usage_err '--tasks-md needs a file'; tasks_md="$2"; shift 2 ;;
    -h|--help)  usage_err 'usage: test-drift-check.sh <base-ref> [<head-ref>] [--tasks-md <file>]' ;;
    -*)         usage_err "unknown flag: $1" ;;
    *)
      npos=$((npos + 1))
      case "$npos" in
        1) base="$1" ;;
        2) headref="$1" ;;
        *) usage_err "too many arguments: $1" ;;
      esac
      shift ;;
  esac
done
[ -n "$base" ] || usage_err 'usage: test-drift-check.sh <base-ref> [<head-ref>] [--tasks-md <file>]'

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t tdrift)"
trap 'rm -rf "$tmp"' EXIT

# ── waivers (R10) ────────────────────────────────────────────────────────────────
: > "$tmp/waivers"
if [ -n "$tasks_md" ]; then
  { [ -f "$tasks_md" ] && [ -r "$tasks_md" ]; } || usage_err "--tasks-md is not a readable file: $tasks_md"
  # A line is a waiver only when it STARTS (after an optional list marker) with the prefix, so
  # prose that merely mentions the syntax never parses. Split on the FIRST em dash that has
  # whitespace on both sides; an empty name or reason, or no separator, is malformed (exit 2).
  DT_DASH="$DASH" awk '
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
    BEGIN { dash = ENVIRON["DT_DASH"]; bad = 0 }
    {
      line = $0
      sub(/^[ \t]*(-[ \t]+)?/, "", line)
      if (index(line, "waive-test-drift:") != 1) next
      rest = substr(line, length("waive-test-drift:") + 1)
      name = ""; reason = ""; ok = 0; from = 1
      while ((p = index(substr(rest, from), dash)) > 0) {
        at = from + p - 1
        before = (at > 1) ? substr(rest, at - 1, 1) : ""
        after = substr(rest, at + length(dash), 1)
        if ((before == " " || before == "\t") && (after == " " || after == "\t")) {
          name = trim(substr(rest, 1, at - 1)); reason = trim(substr(rest, at + length(dash)))
          ok = 1; break
        }
        from = at + length(dash)
      }
      if (!ok || name == "" || reason == "") {
        printf "test-drift-check: malformed waiver (expected %swaive-test-drift: <test name> %s <reason>%s): %s\n", "\047", dash, "\047", $0 > "/dev/stderr"
        bad = 1; exit
      }
      printf "%s\t%s\n", name, reason
    }
    END { if (bad) exit 2 }
  ' "$tasks_md" > "$tmp/waivers" || exit 2
fi

# ── repository, refs, merge base (exit 3) ────────────────────────────────────────
# Resolve this script's directory BEFORE changing to the repo root: `$0` may be relative to the
# caller's cwd (`cd tests && sh ../tools/test-drift-check.sh main`).
self="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)" || cant_diff "cannot resolve the tool directory from $0"
top="$(git rev-parse --show-toplevel 2>/dev/null)" || cant_diff 'not a git repository'
cd "$top"
basec="$(git rev-parse --verify --quiet "$base^{commit}" 2>/dev/null)" || cant_diff "base ref does not resolve: $base"
headc=""
if [ -n "$headref" ]; then
  headc="$(git rev-parse --verify --quiet "$headref^{commit}" 2>/dev/null)" || cant_diff "head ref does not resolve: $headref"
  mb="$(git merge-base "$basec" "$headc" 2>/dev/null)" || mb=""
else
  git rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null 2>&1 || cant_diff 'HEAD does not resolve'
  mb="$(git merge-base "$basec" HEAD 2>/dev/null)" || mb=""
fi
[ -n "$mb" ] || cant_diff "no merge base between $base and ${headref:-HEAD}"
short="$(git rev-parse --short "$mb")"
if [ -n "$headc" ]; then range="$mb $headc"; else range="$mb"; fi

# ── classifier + configured patterns, from the SIBLING change-size.sh (R2, R5) ───
TEST_RE="$(sh "$self/change-size.sh" --print-test-re --repo "$top" 2>/dev/null)" \
  || cant_diff "cannot read the test classifier from $self/change-size.sh"
[ -n "$TEST_RE" ] || cant_diff "empty test classifier from $self/change-size.sh"
extra="$(sh "$self/change-size.sh" --print-list assert_patterns --repo "$top" 2>/dev/null)" \
  || cant_diff "cannot read change_size.assert_patterns from $self/change-size.sh"

# Built-in assertion EREs, one per line. Deliberately absent: a bare `[`, `should`, `must`,
# `test `, `pass "` (that is a NAME). Configured entries are appended VERBATIM below.
cat > "$tmp/assert.re" <<'DT_ASSERT'
(^|[^A-Za-z0-9_])assert[A-Za-z_]*[[:space:](!.]
(^|[^A-Za-z0-9_])expect\(
(^|[^A-Za-z0-9_])t\.(is|ok|not|true|false|truthy|falsy|deepEqual|notDeepEqual|equal|notEqual|like|throws|notThrows|regex|snapshot|pass|fail|Error|Errorf|Fatal|Fatalf|Fail|FailNow)\(
(^|[^A-Za-z0-9_])fail\(
(^|[^A-Za-z0-9_])(ok|fail)[[:space:]]+["']
(^|[^A-Za-z0-9_])(pytest\.)?raises\(
DT_ASSERT
ASSERT_RE="$(awk 'NF { printf "%s%s", (n++ ? "|" : ""), $0 } END { print "" }' "$tmp/assert.re")"
if [ -n "$extra" ]; then
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    ASSERT_RE="$ASSERT_RE|$_p"
  done <<DT_EXTRA
$extra
DT_EXTRA
fi
cat > "$tmp/skip.re" <<'DT_SKIP'
\.(skip|only|todo)\(
(^|[^A-Za-z0-9_])x(it|test|describe)\(
@pytest\.mark\.(skip|skipif|xfail)
(^|[^A-Za-z0-9_])pytest\.skip\(
@unittest\.(skip|skipIf|skipUnless|expectedFailure)
(^|[^A-Za-z0-9_])t\.(Skip|Skipf|SkipNow)\(
#\[ignore
@(Disabled|Ignore)([^A-Za-z0-9_]|$)
["']skip[ ]-[ ]
DT_SKIP
SKIP_RE="$(awk 'NF { printf "%s%s", (n++ ? "|" : ""), $0 } END { print "" }' "$tmp/skip.re")"

# ── touched test files ───────────────────────────────────────────────────────────
# Normalised to `<status><TAB><old><TAB><new>` (A, M, D, R, or U for untracked); only paths
# matching the effective test ERE survive (new path; old path for a deletion).
# `-z`: `core.quotePath=false` does NOT stop git C-quoting a tracked path that contains `"`,
# a backslash or a tab (it governs non-ASCII bytes only), so `tests/a".test.js` would arrive as
# `"tests/a\".test.js"` and miss the classifier. NUL framing is never encoded. NUL -> LF is safe
# here because pathnames containing LF are a documented non-goal (Known limits).
# --name-status -z framing: `<status> NUL <path> NUL`, or for R/C `<status> NUL <old> NUL <new> NUL`.
# shellcheck disable=SC2086
git -c core.quotePath=false diff --name-status -z -M $range 2>/dev/null | tr '\000' '\n' \
  | DT_RE="$TEST_RE" awk '
      BEGIN { re = ENVIRON["DT_RE"]; want = 0 }
      want == 0 {
        s = substr($0, 1, 1)
        if (s == "R" || s == "C") { want = 2; s = "R" } else { want = 1; if (s == "T") s = "M" }
        np = 0; next
      }
      {
        path[++np] = $0
        if (np < want) next
        old = path[1]; new = (want == 2) ? path[2] : path[1]; want = 0
        chk = (s == "D") ? old : new
        if (chk ~ re) printf "%s\t%s\t%s\n", s, old, new
      }' > "$tmp/files"
if [ -z "$headc" ]; then
  git -c core.quotePath=false ls-files -z --others --exclude-standard 2>/dev/null | tr '\000' '\n' \
    | DT_RE="$TEST_RE" awk '
        BEGIN { re = ENVIRON["DT_RE"] }
        $0 ~ re { printf "U\t%s\t%s\n", $0, $0 }' >> "$tmp/files"
fi

# Extract test names: `<line><TAB><dir><TAB><name>`; dir B = a definition (attributes
# BACKWARD), F = an sh pass label (attributes FORWARD). Language from the file name.
extract_names() { # extract_names <textfile> <pathname>
  _ex_lang=""
  case "$2" in
    *.sh)                               _ex_lang=sh ;;
    *.py)                               _ex_lang=py ;;
    *.js|*.mjs|*.cjs|*.ts|*.tsx|*.jsx)  _ex_lang=js ;;
    *.go)                               _ex_lang=go ;;
    *)
      case "${2##*/}" in
        *.*) : ;;
        *)
          _ex_first="$(head -n 1 "$1" 2>/dev/null || true)"
          case "$_ex_first" in
            '#!'*[/\ ]sh|'#!'*[/\ ]sh\ *|'#!'*[/\ ]bash|'#!'*[/\ ]bash\ *) _ex_lang=sh ;;
          esac ;;
      esac ;;
  esac
  [ -n "$_ex_lang" ] || return 0
  awk -v lang="$_ex_lang" '
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
    BEGIN {
      sq = "\047"; dq = "\042"; bq = "\140"
      re_shdef = "^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\\(\\)"
      re_pass  = "^[ \t]*pass[ \t]+(" dq "[^" dq "]*" dq "|" sq "[^" sq "]*" sq ")"
      re_pydef = "^[ \t]*(async[ \t]+)?def[ \t]+test_[A-Za-z0-9_]*"
      re_js    = "^[ \t]*(it|test|describe)(\\.(only|skip|todo|each))?[ \t]*\\([ \t]*[" dq sq bq "]"
      re_go    = "^func[ \t]+Test[A-Za-z0-9_]*[ \t]*\\("
    }
    {
      line = $0
      if (lang == "sh") {
        if (match(line, re_shdef)) {
          s = substr(line, RSTART, RLENGTH); sub(/^[ \t]*/, "", s); sub(/[ \t]*\(\)$/, "", s)
          printf "%d\tB\t%s\n", NR, s
        }
        if (match(line, re_pass)) {
          s = substr(line, RSTART, RLENGTH); sub(/^[ \t]*pass[ \t]+/, "", s)
          printf "%d\tF\t%s\n", NR, substr(s, 2, length(s) - 2)
        }
      } else if (lang == "py") {
        if (match(line, re_pydef)) {
          s = substr(line, RSTART, RLENGTH); sub(/^.*def[ \t]+/, "", s)
          printf "%d\tB\t%s\n", NR, s
        }
      } else if (lang == "js") {
        if (match(line, re_js)) {
          q = substr(line, RSTART + RLENGTH - 1, 1)
          rest = substr(line, RSTART + RLENGTH)
          i = index(rest, q)
          if (i > 0) printf "%d\tB\t%s\n", NR, substr(rest, 1, i - 1)
        }
      } else if (lang == "go") {
        if (match(line, re_go)) {
          s = substr(line, RSTART, RLENGTH); sub(/^func[ \t]+/, "", s); sub(/[ \t]*\($/, "", s)
          printf "%d\tB\t%s\n", NR, s
        }
      }
    }
  ' "$1"
}

: > "$tmp/findings"
nfiles=0
while IFS="$TAB" read -r st old new; do
  [ -n "$st" ] || continue
  nfiles=$((nfiles + 1))
  # Base and head text, for name extraction. A missing side is empty.
  : > "$tmp/base.txt"; : > "$tmp/head.txt"
  case "$st" in
    A|U) : ;;
    *) git show "$mb:$old" > "$tmp/base.txt" 2>/dev/null || : > "$tmp/base.txt" ;;
  esac
  case "$st" in
    D) : ;;
    *)
      if [ -n "$headc" ]; then
        git show "$headc:$new" > "$tmp/head.txt" 2>/dev/null || : > "$tmp/head.txt"
      elif [ -f "$new" ]; then
        cat "$new" > "$tmp/head.txt"
      fi ;;
  esac
  # The -U0 diff for this one file (both paths for a rename).
  case "$st" in
    U) git diff --no-index --no-color --no-ext-diff -U0 -- /dev/null "$new" > "$tmp/diff.txt" 2>/dev/null || true ;;
    R)
      # shellcheck disable=SC2086
      git diff -U0 --no-color --no-ext-diff -M $range -- "$old" "$new" > "$tmp/diff.txt" 2>/dev/null || true ;;
    *)
      # shellcheck disable=SC2086
      git diff -U0 --no-color --no-ext-diff -M $range -- "$new" > "$tmp/diff.txt" 2>/dev/null || true ;;
  esac
  # Binary files are skipped silently (still counted as examined).
  if grep -Eq '^(Binary files|GIT binary patch)' "$tmp/diff.txt" 2>/dev/null; then continue; fi
  extract_names "$tmp/base.txt" "$old" > "$tmp/base.names"
  extract_names "$tmp/head.txt" "$new" > "$tmp/head.names"
  # The path printed is the head path (the old path for a deleted file; both equal here).
  DT_ASSERT="$ASSERT_RE" DT_SKIP="$SKIP_RE" DT_PATH="$new" DT_DASH="$DASH" \
  DT_BN="$tmp/base.names" DT_HN="$tmp/head.names" \
  awk '
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
    function load(file, side,   ln, i1, i2, rest, n) {
      n = 0
      while ((getline ln < file) > 0) {
        i1 = index(ln, "\t"); rest = substr(ln, i1 + 1); i2 = index(rest, "\t")
        n++
        nl[side, n] = substr(ln, 1, i1 - 1) + 0
        nd[side, n] = substr(rest, 1, i2 - 1)
        nn[side, n] = substr(rest, i2 + 1)
      }
      close(file)
      cnt[side] = n
    }
    # The enclosing test name for line L of one side. Definitions attribute BACKWARD, sh
    # labels FORWARD, a decorator line forward to the next definition; nearest wins, a tie
    # goes to the backward definition; no name at all falls back to the path.
    function attr(side, L, text,   i, bl, bn, fl, fn, dl, dn, db, df) {
      bl = -1; bn = ""; fl = -1; fn = ""; dl = -1; dn = ""
      for (i = 1; i <= cnt[side]; i++) {
        if (nd[side, i] == "B") {
          if (nl[side, i] <= L && nl[side, i] >= bl) { bl = nl[side, i]; bn = nn[side, i] }
          if (nl[side, i] > L && (dl < 0 || nl[side, i] < dl)) { dl = nl[side, i]; dn = nn[side, i] }
        } else if (nd[side, i] == "F") {
          if (nl[side, i] >= L && (fl < 0 || nl[side, i] < fl)) { fl = nl[side, i]; fn = nn[side, i] }
        }
      }
      if (text ~ /^[ \t]*@/ && dl >= 0) return dn
      if (bl >= 0 && fl >= 0) { db = L - bl; df = fl - L; return (db <= df) ? bn : fn }
      if (bl >= 0) return bn
      if (fl >= 0) return fn
      return path
    }
    function emit(kind, line, name, detail) {
      printf "%s\t%s\t%s\t%s\t%s\n", path, kind, line, name, detail
    }
    function flush(   k) {
      for (k = 1; k <= nm; k++) {
        if (k <= np) emit("assert-modified", mline[k], attr("b", mline[k], mtext[k]), trim(mtext[k]) " -> " trim(ptext[k]))
        else         emit("assert-removed",  mline[k], attr("b", mline[k], mtext[k]), trim(mtext[k]))
      }
      nm = 0; np = 0
    }
    BEGIN {
      are = ENVIRON["DT_ASSERT"]; sre = ENVIRON["DT_SKIP"]
      path = ENVIRON["DT_PATH"]; dash = ENVIRON["DT_DASH"]
      load(ENVIRON["DT_BN"], "b"); load(ENVIRON["DT_HN"], "h")
      in_hunk = 0; nm = 0; np = 0
    }
    /^diff --git / { flush(); in_hunk = 0; next }
    /^@@ / {
      flush(); in_hunk = 1
      h = $0; sub(/^@@ -/, "", h)
      split(h, parts, " ")
      split(parts[1], oa, ","); split(substr(parts[2], 2), na, ",")
      ol = oa[1] + 0; nl2 = na[1] + 0
      next
    }
    !in_hunk { next }
    /^-/ {
      t = substr($0, 2)
      if (t ~ are) { nm++; mline[nm] = ol; mtext[nm] = t }
      ol++; next
    }
    /^\+/ {
      t = substr($0, 2)
      if (t ~ are) { np++; ptext[np] = t }
      if (t ~ sre) emit("skip-added", nl2, attr("h", nl2, t), trim(t))
      nl2++; next
    }
    END {
      flush()
      for (i = 1; i <= cnt["h"]; i++) inhead[nn["h", i]] = 1
      for (i = 1; i <= cnt["b"]; i++) {
        nm2 = nn["b", i]
        if (nm2 in inhead || nm2 in done) continue
        done[nm2] = 1
        emit("test-removed", dash, nm2, nm2)
      }
    }
  ' "$tmp/diff.txt" >> "$tmp/findings"
done < "$tmp/files"

# ── waive, print, summarise (R9, R10) ────────────────────────────────────────────
DT_W="$tmp/waivers" awk -F'\t' '
  BEGIN {
    f = ENVIRON["DT_W"]
    while ((getline ln < f) > 0) { i = index(ln, "\t"); waive[substr(ln, 1, i - 1)] = substr(ln, i + 1) }
    close(f)
  }
  {
    path = $1; kind = $2; line = $3; name = $4
    detail = $5; for (i = 6; i <= NF; i++) detail = detail "\t" $i
    n++
    if (name in waive) { w++; printf "WAIVED %s | %s:%s | %s | %s\n", kind, path, line, name, waive[name] }
    else { u++; printf "DRIFT %s | %s:%s | %s | %s\n", kind, path, line, name, detail }
  }
  END { printf "%d %d\n", n + 0, w + 0 > "/dev/stderr" }
' "$tmp/findings" 2> "$tmp/counts"
read -r nfind nwaived < "$tmp/counts"
printf 'test-drift-check: %s findings, %s waived, %s test files examined (base %s)\n' \
  "$nfind" "$nwaived" "$nfiles" "$short"
[ "$nfind" -eq "$nwaived" ] || exit 1
exit 0
