#!/bin/sh
# test_observable_slices.sh — E36-F02 (ADR-0008 decision 1): the Driller's observable-slice
# rule and walking skeleton, the brief's `## Observable behavior` section, and the doc-critic's
# three findings. This feature ships PROSE, so verification is static: literals by whole-file or
# section-range `grep -qF`, co-occurrence by `tr '\n' ' ' | grep -qiE 'A[^.]{0,N}B'`, placement
# by heading line numbers. The house awk section extractor is fence-blind and is NOT used.
# Never reads VERSION as a literal; never diffs a DO-NOT-TOUCH file against main.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ln FILE HEADING-PREFIX -> first line number of a line starting with the prefix
ln() { grep -n "^$2" "$1" | head -1 | cut -d: -f1; }
# fold FILE -> the file on one line (newlines to spaces)
fold() { tr '\n' ' ' < "$1"; }
# range FILE START-PREFIX END-PREFIX -> the lines from START up to (not incl.) END
range() {
  _a="$(ln "$1" "$2")"; _b="$(ln "$1" "$3")"
  [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ] || return 1
  sed -n "${_a},$((_b - 1))p" "$1"
}

DRILLER="agents/driller.md"
CRITIC="agents/doc-critic.md"
INCEP="agents/inception.md"
TEMPLATE="specs/_templates/inbox-brief.md"
WORKFLOW="docs/WORKFLOW.md"

# ── R4: the brief template carries `## Observable behavior` ─────────────────────
r4_order() { # $1 = a brief file; success iff Success outcome < Observable behavior < Scope
  a="$(ln "$1" '## Success outcome')"; b="$(ln "$1" '## Observable behavior')"
  c="$(ln "$1" '## Scope / boundaries')"
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]
}
cp "$TEMPLATE" "$T/brief.md"
r4_order "$T/brief.md" || fail "R4: template lacks '## Observable behavior' between Success outcome and Scope / boundaries"
body="$(sed -n "$(( $(ln "$T/brief.md" '## Observable behavior') + 1 ))p" "$T/brief.md")"
printf '%s' "$body" | grep -qF 'user or client sees' || fail "R4: section body does not name what a user or client sees"
printf '%s' "$body" | grep -qF 'HTTP' || fail "R4: section body does not name a surface"
for k in 'feature:' 'seeded_by: inception' 'date:'; do
  grep -qF "$k" "$T/brief.md" || fail "R4: template lost frontmatter '$k'"
done
for s in 'Problem' 'Success outcome' 'Scope' 'Chosen options' 'Constraints' 'Open questions'; do
  grep -q "^## $s" "$T/brief.md" || fail "R4: template lost section '$s'"
done
# negative control: with the section sed-ed out the placement check must fail (check is live)
sed '/^## Observable behavior/,/^## Scope/{/^## Scope/!d;}' "$T/brief.md" > "$T/brief-no.md"
if r4_order "$T/brief-no.md"; then fail "R4: negative control — placement check passed with the section removed"; fi
pass "R4_template_section"

# ── R5: Inception lists Observable behavior between Success outcome and Scope ───
a="$(ln "$INCEP" '- \*\*Success outcome\*\*')"; b="$(ln "$INCEP" '- \*\*Observable behavior\*\*')"
c="$(ln "$INCEP" '- \*\*Scope / boundaries\*\*')"
[ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] \
  || fail "R5: $INCEP lacks the '**Observable behavior**' bullet between Success outcome and Scope / boundaries"
bullet="$(sed -n "${b}p" "$INCEP")"
printf '%s' "$bullet" | grep -qiE 'surface.{0,60}HTTP.{0,60}exit code' || fail "R5: bullet does not name the surface list"
printf '%s' "$bullet" | grep -qF 'what a user or client sees' || fail "R5: bullet does not say what a user or client sees"
pass "R5_inception_brief_sections"

# ── R1: the Driller's observable-slice section (the three clauses of decision 1) ─
H1='## Observable slice — the shape rule beside the size budget (ADR-0008)'
grep -qF "$H1" "$DRILLER" || fail "R1: $DRILLER lacks the heading '$H1'"
a="$(ln "$DRILLER" '## Feature-size budget')"; b="$(ln "$DRILLER" '## Observable slice')"
c="$(ln "$DRILLER" '## Seed the feature entries')"
[ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] \
  || fail "R1: observable-slice section is not between the size-budget and seed sections"
# every further anchor runs over the new section's line range only (whole-file greps for
# max_requirements / depends_on are green on main and could never be RED)
range "$DRILLER" '## Observable slice' '## Seed the feature entries' | tr '\n' ' ' > "$T/driller-sec.txt"
SEC="$T/driller-sec.txt"
sec() { grep -qiE "$1" "$SEC"; }
sec 'product boundary[^.]{0,120}HTTP[^.]{0,40}CLI[^.]{0,40}UI[^.]{0,40}file[^.]{0,40}exit code' \
  || fail "R1: section does not name the product-boundary surfaces (HTTP, CLI, UI, file, exit code)"
sec 'first feature of a fresh epic is the walking skeleton' || fail "R1: section does not make the first feature of a fresh epic the walking skeleton"
sec 'thinnest[^.]{0,40}end-to-end' || fail "R1: section does not define the skeleton as the thinnest end-to-end path"
sec 'lowest[^.]{0,20}F##' || fail "R1: section does not tie the skeleton to the lowest F##"
sec 'skeleton[^.]{0,200}no intra-epic .?depends_on' || fail "R1: section does not give the skeleton no intra-epic depends_on"
sec 'internal[^.]{0,80}merged[^.]{0,40}consum' || fail "R1: section does not merge an internal-only candidate into its consumer"
sec 'max_requirements[^.]{0,60}size proxy' || fail "R1: section does not say max_requirements remains the size proxy"
pass "R1_driller_rule_section"
