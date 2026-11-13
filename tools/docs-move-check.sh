#!/bin/sh
# docs-move-check.sh — prove a docs rewrite moved its contract text instead of losing it.
#
# A human doc (README.md and docs/*.md, not docs/agents/ and not docs/history/) is rewritten
# short; the exact contract text moves to docs/agents/ or docs/history/. This tool compares
# every human doc that changed between a base and a head and reports two things:
#   - a VANISHED-TOKEN: a backtick span (a flag, env var, path, command, exit code) that the
#     base doc held and that no README.md or docs/**/*.md holds at head. A token gone from the
#     whole doc set is a lost contract; if it was deprecated it still moves to docs/history/.
#   - a DROPPED-LINE: a removed line that holds a backtick span and whose normalised text is
#     found in no docs/agents/**/*.md or docs/history/**/*.md at head. Informational: a line
#     that was reworded for humans is fine when its tokens survive.
#
# Usage:
#   tools/docs-move-check.sh <base-ref> [<head-ref>]
#
#   <base-ref>   the BASE is `git merge-base <base-ref> <head>` (pass the default branch).
#   <head-ref>   omitted: the WORKING TREE (tracked + untracked non-ignored files, like
#                tools/test-drift-check.sh). Given: that commit only.
#
# Output (stdout): zero or more finding lines, then exactly one summary line.
#   VANISHED-TOKEN | <doc> | <token>
#   DROPPED-LINE | <doc>:<base-line> | <text>
#   docs-move-check: <V> vanished tokens, <D> dropped lines, <M> moved lines, <F> human docs examined (base <short-sha>)
# <M> counts removed backtick-bearing lines found under docs/agents/ or docs/history/; <F>
# counts human docs with any difference between base and head.
#
# Normalisation N(line): runs of whitespace collapse to one space, the line is trimmed, and the
# target of every Markdown link `](...)` is emptied, so a moved line whose only change is a
# retargeted link counts as moved.
#
# Exit codes:
#   0  no vanished token (dropped lines are informational)   1  at least one vanished token
#   2  usage error (missing base-ref, unknown flag, too many arguments)
#   3  cannot diff (not a git repo, ref does not resolve, no merge base; reason on stderr)
#
# Known limits (the prose must never over-claim): a token split across two lines is not a
# span; fenced code is skipped on both sides (a span in a fence is neither a token nor a
# dropped line); a paragraph re-wrapped while moving reads as DROPPED-LINE, not moved; a
# renamed human doc reads as one removed plus one added doc; a span written with double
# backticks is not read; pathnames containing whitespace are unsupported.

set -eu
LC_ALL=C
export LC_ALL

usage_err() { printf 'docs-move-check: %s\n' "$1" >&2; exit 2; }
cant_diff() { printf 'docs-move-check: %s\n' "$1" >&2; exit 3; }

usage() {
  printf 'usage: docs-move-check.sh <base-ref> [<head-ref>]\n'
}

base=""; head=""
for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
    -*) usage_err "unknown flag $a" ;;
    *)
      if [ -z "$base" ]; then base="$a"
      elif [ -z "$head" ]; then head="$a"
      else usage_err "too many arguments"; fi ;;
  esac
done
[ -n "$base" ] || usage_err "usage: docs-move-check.sh <base-ref> [<head-ref>]"

top="$(git rev-parse --show-toplevel 2>/dev/null)" || cant_diff "not a git repository"
cd "$top"
headspec="${head:-HEAD}"
git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || cant_diff "ref does not resolve: $base"
git rev-parse --verify -q "$headspec^{commit}" >/dev/null 2>&1 || cant_diff "ref does not resolve: $headspec"
mb="$(git merge-base "$base" "$headspec" 2>/dev/null)" || cant_diff "no merge base between $base and $headspec"
short="$(git rev-parse --short "$mb")"

TD="$(mktemp -d 2>/dev/null || mktemp -d -t docsmove)"
trap 'rm -rf "$TD"' EXIT
trap 'exit 1' HUP INT TERM

# --- the awk programs -------------------------------------------------------------------------
# fence_delim($0): a copy of the CommonMark 4.5 fence rule (tests/lib/fence.awk is not shipped).
FENCE_FN='
function fence_delim(line,   ind, ch, run, tail) {
  ind = 0
  while (ind < 4 && substr(line, ind + 1, 1) == " ") ind++
  if (ind > 3) return 0
  ch = substr(line, ind + 1, 1)
  if (ch != "`" && ch != "~") return 0
  run = 0
  while (substr(line, ind + run + 1, 1) == ch) run++
  if (run < 3) return 0
  tail = substr(line, ind + run + 1)
  if (fence) {
    if (ch != fence_char || run < fence_len) return 0
    if (tail ~ /[^ \t]/) return 0
    fence = 0
    return 1
  }
  if (ch == "`" && index(tail, "`") > 0) return 0
  fence = 1; fence_char = ch; fence_len = run
  return 1
}'
# spans: every single-backtick span outside fences, one per line, trimmed, empty ones dropped.
SPANS_AWK="$FENCE_FN"'
fence_delim($0) { next }
!fence {
  line = $0
  while ((i = index(line, "`")) > 0) {
    rest = substr(line, i + 1); j = index(rest, "`")
    if (j == 0) break
    tok = substr(rest, 1, j - 1); line = substr(rest, j + 1)
    gsub(/^[ \t]+|[ \t]+$/, "", tok)
    if (tok != "") print tok
  }
}'
# fenced: the line numbers that are a fence delimiter or inside a fence.
FENCED_AWK="$FENCE_FN"'
{ d = fence_delim($0); if (d || fence) print NR }'
NORM_FN='
function norm(s) {
  gsub(/\]\([^)]*\)/, "]()", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
  return s
}'

# --- gather ---------------------------------------------------------------------------------------
all_re='^(README\.md|docs/.*\.md)$'
human_re='^(README\.md|docs/[^/]*\.md)$'
machine_re='^docs/(agents|history)/.*\.md$'

head_paths() {
  if [ -n "$head" ]; then
    git ls-tree -r --name-only "$head"
  else
    git ls-files -c -o --exclude-standard | sort -u | while IFS= read -r _p; do
      if [ -f "$_p" ]; then printf '%s\n' "$_p"; fi
    done
  fi
}
head_cat() { # head_cat <path> — the head content of one path
  if [ -n "$head" ]; then git show "$head:$1" 2>/dev/null; else cat "$1"; fi
}

head_paths > "$TD/head.paths" || cant_diff "git could not list the head tree"
grep -E "$all_re" "$TD/head.paths" > "$TD/head.docs" || true
git ls-tree -r --name-only "$mb" > "$TD/base.paths" 2>/dev/null || cant_diff "git could not list the base tree"
{ grep -E "$human_re" "$TD/base.paths" || true; grep -E "$human_re" "$TD/head.paths" || true; } | sort -u > "$TD/human.docs"

: > "$TD/headall.md"
while IFS= read -r p; do head_cat "$p" >> "$TD/headall.md"; printf '\n' >> "$TD/headall.md"; done < "$TD/head.docs"
awk "$SPANS_AWK" "$TD/headall.md" | sort -u > "$TD/head.tok"

: > "$TD/moved.norm"
grep -E "$machine_re" "$TD/head.docs" | while IFS= read -r p; do
  head_cat "$p" | awk "$NORM_FN"'{ n = norm($0); if (n != "") print n }' >> "$TD/moved.norm"
done || true

: > "$TD/findings"; V=0; D=0; M=0; F=0
while IFS= read -r p; do
  git show "$mb:$p" > "$TD/b" 2>/dev/null || : > "$TD/b"
  head_cat "$p" > "$TD/h" 2>/dev/null || : > "$TD/h"
  cmp -s "$TD/b" "$TD/h" && continue
  F=$((F + 1))
  awk "$SPANS_AWK" "$TD/b" | sort -u > "$TD/b.tok"
  comm -23 "$TD/b.tok" "$TD/head.tok" > "$TD/vanished" || true
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    printf 'VANISHED-TOKEN | %s | %s\n' "$p" "$t" >> "$TD/findings"
    V=$((V + 1))
  done < "$TD/vanished"
  awk "$FENCED_AWK" "$TD/b" > "$TD/b.fence"
  diff -U0 "$TD/b" "$TD/h" > "$TD/d" 2>/dev/null || true
  awk -v doc="$p" "$NORM_FN"'
    FILENAME == ARGV[1] { moved[$0] = 1; next }
    FILENAME == ARGV[2] { fenced[$1] = 1; next }
    /^@@ / {
      split($2, a, ","); ln = substr(a[1], 2) + 0; started = 1; next
    }
    !started { next }
    /^-/ {
      text = substr($0, 2)
      cur = ln; ln++
      if (text ~ /^[ \t]*$/ || (cur in fenced)) next
      if (text !~ /`[^`]+`/) next
      if (norm(text) in moved) print "@@MOVED"
      else printf "DROPPED-LINE | %s:%d | %s\n", doc, cur, text
      next
    }
    { }
  ' "$TD/moved.norm" "$TD/b.fence" "$TD/d" > "$TD/res"
  _m="$(grep -c '^@@MOVED' "$TD/res" || true)"; M=$((M + _m))
  _d="$(grep -vc '^@@MOVED' "$TD/res" || true)"; D=$((D + _d))
  grep -v '^@@MOVED' "$TD/res" >> "$TD/findings" || true
done < "$TD/human.docs"

cat "$TD/findings"
printf 'docs-move-check: %d vanished tokens, %d dropped lines, %d moved lines, %d human docs examined (base %s)\n' \
  "$V" "$D" "$M" "$F" "$short"
[ "$V" -eq 0 ]
