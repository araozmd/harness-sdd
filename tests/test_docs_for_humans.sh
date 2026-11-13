#!/bin/sh
# test_docs_for_humans.sh — E39-F01: the human-doc style lint, the docs/agents/ machine layer,
# the brand assets and the two doc tools (tools/doc-cite-check.py, tools/docs-move-check.sh).
#
# Prose rows slice a doc by heading through the fence-aware slicer (tests/lib/fence.awk) and
# anchor whole phrases inside the slice. Rows that mutate a doc copy it under $T first and
# never touch $ROOT. The R8 rows build a throwaway two-commit git repo under $T, so the suite
# never diffs this repository against main. Co-occurrence is not polarity: read the diff.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal; never git-diff a DO-NOT-TOUCH file against main. Exit codes are asserted as
# `rc -eq N`, never a shell-dependent code.
#
# Registry: HUMAN_DOCS lists <path>:<line-budget>:<diagram yes|no>. A later slice appends an
# entry; an override above the default 300 carries a `# why:` comment on the line above it.

set -eu
LC_ALL=C; export LC_ALL

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FX="$ROOT/tests/fixtures/doc-cite"
CITE="$ROOT/tools/doc-cite-check.py"
MOVE="$ROOT/tools/docs-move-check.sh"
FENCE_AWK="$(cat "$ROOT/tests/lib/fence.awk")"
T="$(mktemp -d 2>/dev/null || mktemp -d -t docsforhumans)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)
GIT_CEILING_DIRECTORIES="$T"; export GIT_CEILING_DIRECTORIES

HUMAN_DOCS="README.md:150:yes docs/README.md:60:no docs/CONCEPTS.md:220:yes docs/BRAND.md:90:no"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; echo "$1" >> "$T/passed"; }
# row <name> — run one row and require that it passed under its own name.
row() { "$1"; grep -qE "^$1( |\$)" "$T/passed" || fail "$1: the row returned without passing"; }

command -v python3 >/dev/null 2>&1 || fail "python3 is a hard harness dependency and is absent"

# slice <file> <heading line> — the fence-aware body under one heading (heading excluded),
# up to the next heading of any level. Fence delimiters inside the slice are kept.
slice() {
  awk -v h="$2" "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^#+ / { keep = ($0 == h); next }
    keep' "$1"
}
# folded — collapse a stream to one line with single spaces (anchors span folded newlines).
folded() { tr '\n' ' ' | tr -s ' '; }
# unfenced <file> — every line outside a fenced block (delimiters dropped).
unfenced() {
  awk "$FENCE_AWK"'
    fence_delim($0) { next }
    !fence' "$1"
}
# mermaid_blocks — read a markdown stream; print "@@MERMAID" then the content of each
# mermaid fenced block.
mermaid_blocks() {
  awk "$FENCE_AWK"'
    fence_delim($0) {
      if (fence) { m = ($0 ~ /^ {0,3}(```|~~~)[ \t]*mermaid[ \t]*$/); if (m) print "@@MERMAID" }
      else m = 0
      next
    }
    fence && m { print }'
}
nlines() { wc -l < "$1" | tr -d ' '; }
has_heading() { unfenced "$1" | grep -qxF "$2"; }

# ---------------------------------------------------------------- R1 — the scaffold
AGENTS_README="$ROOT/docs/agents/README.md"
HUMAN_INDEX="$ROOT/docs/README.md"

R1_announcement() {
  [ -f "$AGENTS_README" ] || fail "R1: docs/agents/README.md does not exist"
  [ "$(sed -n '1p' "$AGENTS_README")" = "# harness-loop docs for agents" ] ||
    fail "R1: line 1 of docs/agents/README.md is not the H1 '# harness-loop docs for agents'"
  _first="$(sed -n '2,$p' "$AGENTS_README" | grep -v '^[[:space:]]*$' | sed -n '1p')"
  [ "$_first" = "> For agents — exact contracts; humans start at docs/." ] ||
    fail "R1: the first non-empty line after the H1 is not the announcement (got: $_first)"
  pass "R1_announcement"
}
# index_rows <file> — "<human> <machine>" per index row, backticks stripped.
index_rows() {
  slice "$1" "## Index" | awk -F'|' '{
    a=$2; b=$3; gsub(/[ `]/, "", a); gsub(/[ `]/, "", b)
    if (a ~ /\.md$/) print a " " b }'
}
R1_index_table() {
  slice "$AGENTS_README" "## Index" | grep -qxF '| Human doc | Machine counterpart | What moved |' ||
    fail "R1: ## Index lacks the pinned header row"
  for _f in "$ROOT"/docs/agents/*.md; do
    _b="docs/agents/$(basename "$_f")"
    index_rows "$AGENTS_README" | awk -v b="$_b" '$2 == b { f = 1 } END { exit !f }' ||
      fail "R1: ## Index has no row whose machine counterpart is $_b"
  done
  pass "R1_index_table"
}
R1_conventions_named() {
  _s="$(slice "$AGENTS_README" "## Conventions")"
  [ -n "$_s" ] || fail "R1: no ## Conventions section"
  for _c in "C1 Layout" "C2 Move verbatim" "C3 Path-only re-point" "C4 Prove it before the PR" \
            "C5 Human style" "C6 Navigation" "C7 Shipping" "C8 Brand"; do
    printf '%s\n' "$_s" | grep -qF -- "- **$_c** " || fail "R1: ## Conventions lacks the list item '**$_c**'"
  done
  pass "R1_conventions_named"
}
R1_human_index() {
  [ -f "$HUMAN_INDEX" ] || fail "R1: docs/README.md does not exist"
  [ "$(nlines "$HUMAN_INDEX")" -le 60 ] || fail "R1: docs/README.md exceeds 60 lines"
  sed -n '1,15p' "$HUMAN_INDEX" | grep -qF '](agents/README.md)' ||
    fail "R1: docs/README.md does not link agents/README.md within its first 15 lines"
  for _f in "$ROOT"/docs/*.md; do
    _b="$(basename "$_f")"
    [ "$_b" = "README.md" ] && continue
    grep -qF "]($_b" "$HUMAN_INDEX" || fail "R1: docs/README.md does not link $_b"
  done
  pass "R1_human_index"
}

# ---------------------------------------------------------------- R4 — moved, not lost
R4_moved_headings_in_order() {
  _h="$(unfenced "$AGENTS_README" | grep -n '^#')"
  _expect='## Conventions
## Moved from the README (0.109)
## How it works
## Quick start in this source checkout (Claude Code)
## Supported CLIs
## Configuring the knowledge base / state
## Delegating implementation (execution backend)
## Observability (telemetry)
## Project board mirror
## Source checkout layout
### Codex PR review loop
### Parallel maintenance fixes
### Harness defect reporting
### Source-only feedback triage
### Scratch-dir cleanup
## Installing into an existing project
## Adapting to a real project
### Running the tests'
  _got="$(printf '%s\n' "$_h" | sed 's/^[0-9]*://' | awk '
    /^## Conventions$/ { on = 1 }
    on { print }')"
  [ "$_got" = "$_expect" ] ||
    fail "R4: the headings after ## Conventions are not the moved README sections in base order"
  # the baseline paragraph sits directly under ## Moved from the README (0.109)
  slice "$AGENTS_README" "## Moved from the README (0.109)" | folded |
    grep -qF 'preserves the historical five-front-end inventory and its validation limits' ||
    fail "R4: the baseline paragraph is not under ## Moved from the README (0.109)"
  pass "R4_moved_headings_in_order"
}
R4_pinned_sentences_present() {
  _all="$(folded < "$AGENTS_README")"
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    printf '%s' "$_all" | grep -qF -- "$_s" || fail "R4: pinned sentence missing from docs/agents/README.md: $_s"
  done <<'SENTENCES'
each exits 0/1/2 and the Reviewer rejects on exit 1.
the Doc-critic also paraphrases it back from the four files alone
On demand — suggested once per release — `tools/drift-report.py` compares the living documents
Claude Code sessions still escalate on their own `claude=raise` line
Review `progress/triage/<run>/proposal.md`, then explicitly approve the whole plan or
`tools/pi-dispatch.sh <role> <task-file>`, which starts the role as a separate `pi -p` process.
finish with a `no actionable work` summary.
uncertain legacy global prompt ownership is preserved.
preserves the historical five-front-end inventory and its validation limits
SENTENCES
  pass "R4_pinned_sentences_present"
}

# DISPATCH
if [ -n "${ONLY:-}" ]; then for _r in $ONLY; do row "$_r"; done; exit 0; fi
row R1_announcement; row R1_index_table; row R1_conventions_named; row R1_human_index
row R4_moved_headings_in_order; row R4_pinned_sentences_present
# Dispatch completeness: sees a defined-but-undispatched R*() row.
for f in $(sed -n 's/^\(R[0-9][0-9]*_[A-Za-z0-9_]*\)() *{.*/\1/p' "$ROOT/tests/test_docs_for_humans.sh"); do
  grep -qE "^$f( |\$)" "$T/passed" || fail "$f: defined but not dispatched from the row list"
done
echo "test_docs_for_humans.sh: all rows passed"
