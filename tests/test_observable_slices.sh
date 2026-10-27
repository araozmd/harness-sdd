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
# the body line IS the literal agents/doc-critic.md calls "the template placeholder" (R6 greps it there)
printf '%s' "$body" | grep -qxF '<HTTP / CLI / UI / file / exit code> — <what a user or client sees>' \
  || fail "R4: section body is not exactly the shared placeholder literal"
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
sec 'Every feature you seed names at least one behavior observable at the product boundary' \
  || fail "R1: section does not say EVERY seeded feature names a behavior observable at the product boundary"
sec 'product boundary[^.]{0,120}HTTP[^.]{0,40}CLI[^.]{0,40}UI[^.]{0,40}file[^.]{0,40}exit code' \
  || fail "R1: section does not name the product-boundary surfaces (HTTP, CLI, UI, file, exit code)"
sec 'a UI interaction, a file a user or client reads or an exit code' \
  || fail "R1: section counts an internal storage file as observable (must be 'a file a user or client reads')"
sec 'first feature of a fresh epic is the walking skeleton' || fail "R1: section does not make the first feature of a fresh epic the walking skeleton"
sec 'thinnest[^.]{0,40}end-to-end' || fail "R1: section does not define the skeleton as the thinnest end-to-end path"
sec 'lowest[^.]{0,20}F##' || fail "R1: section does not tie the skeleton to the lowest F##"
sec 'skeleton[^.]{0,200}no intra-epic .?depends_on' || fail "R1: section does not give the skeleton no intra-epic depends_on"
sec 'internal[^.]{0,80}merged[^.]{0,40}consum' || fail "R1: section does not merge an internal-only candidate into its consumer"
sec 'merged into the slice that consumes it' || fail "R1: section does not merge the internal-only candidate INTO the slice that consumes it (direction)"
sec 'max_requirements[^.]{0,60}size proxy' || fail "R1: section does not say max_requirements remains the size proxy"
pass "R1_driller_rule_section"

# ── R2: the recorded exemption, the cross-epic sentence, advisory / never blocks ─
grep -qF 'Observable-slice exemption:' "$DRILLER" || fail "R2: $DRILLER lacks the 'Observable-slice exemption:' token"
sec 'Observable-slice exemption:' || fail "R2: the token is not inside the observable-slice section"
sec '\*\*Record the exemption in `epic.md`\.\*\*' || fail "R2: exemption paragraph lead-in does not say where it is recorded (epic.md)"
sec 'one line per exempted feature under `## Notes` in the epic.s `epic.md`' || fail "R2: section does not place the one-line-per-exempted-feature record under ## Notes in the epic's epic.md"
sec 'beginning .?Observable-slice exemption:.{0,20}naming the feature id' || fail "R2: exemption line is not required to name the feature id"
sec 'only consumer is another epic' || fail "R2: section lacks the cross-epic-consumer exemption"
sec 'only consumer is another epic[^.]{0,200}thinnest path the consuming epic can exercise' \
  || fail "R2: cross-epic sentence does not make the skeleton the thinnest path the consuming epic can exercise"
sec 'only consumer is another epic[^.]{0,250}the exemption line names that consuming epic and the surface' \
  || fail "R2: cross-epic sentence does not have the exemption line name the consuming epic and the surface"
sec 'advisory[^.]{0,40}never blocks' || fail "R2: section does not say the rule is advisory and never blocks"
sec 'never[^.]{0,40}blocked[^.]{0,40}shape' || fail "R2: section does not forbid a blocked record on shape alone"
pass "R2_driller_exemption_record"

# ── R3: the Driller fills each brief's `## Observable behavior` ──────────────────
grep -qF '## Observable behavior' "$DRILLER" || fail "R3: $DRILLER never names '## Observable behavior'"
sec '## Observable behavior' || fail "R3: '## Observable behavior' is not inside the observable-slice section"
# one sentence: the fill instruction, the one-line shape, and the skeleton's end-to-end path.
# (a looser 'walking skeleton ... end-to-end path' anchor is satisfied by the R1 sentence)
sec 'In each per-feature brief you write, fill' || fail "R3: section does not apply the fill to EACH per-feature brief"
sec 'fill the `## Observable behavior` section with one line — the surface and what a user or client sees' \
  || fail "R3: section does not tell the Driller to fill the brief's Observable behavior with one line (surface + what a user or client sees)"
sec 'fill[^.]{0,250}for the walking-skeleton feature that line describes the end-to-end path' \
  || fail "R3: section does not make the skeleton's line the end-to-end path"
pass "R3_driller_fills_brief"

# ── R6: the doc-critic's three findings and its scope signal ─────────────────────
H6='## Epic-decomposition checks — observable slices (ADR-0008)'
grep -qF "$H6" "$CRITIC" || fail "R6: $CRITIC lacks the heading '$H6'"
a="$(ln "$CRITIC" '## Review scope and calibration')"; b="$(ln "$CRITIC" '## Epic-decomposition checks')"
c="$(ln "$CRITIC" '## Advisory-only behavior')"
[ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] \
  || fail "R6: the section is not between Review scope and calibration and Advisory-only behavior"
range "$CRITIC" '## Epic-decomposition checks' '## Advisory-only behavior' > "$T/critic-raw.txt"
tr '\n' ' ' < "$T/critic-raw.txt" > "$T/critic-sec.txt"
CS="$T/critic-sec.txt"
csec() { grep -qiE -e "$1" "$CS"; }
csecF() { grep -qF -- "$1" "$CS"; }
csecF 'target-type=epic-decomposition' || fail "R6: section does not name target-type=epic-decomposition"
csecF '<HTTP / CLI / UI / file / exit code> — <what a user or client sees>' \
  || fail "R6: section does not name the template placeholder literal"
csec '- `observable-behavior-missing` — [^.]{0,40}no `## Observable behavior` section[^.]{0,60}empty[^.]{0,60}placeholder' \
  || fail "R6: observable-behavior-missing trigger (no section / empty / placeholder) missing"
csec '- `walking-skeleton-missing` — [^.]{0,40}fresh drill[^.]{0,40}lowest-numbered feature' \
  || fail "R6: walking-skeleton-missing trigger (fresh drill, lowest-numbered feature) missing"
csec '- `walking-skeleton-missing` — [^.]{0,120}names no product-boundary surface' \
  || fail "R6: walking-skeleton-missing trigger does not cover a brief whose observable behavior names no product-boundary surface"
csec '- `walking-skeleton-missing` — [^.]{0,230}internal artifact' \
  || fail "R6: walking-skeleton-missing trigger does not cover an outcome that stops at an internal artifact"
csec '- `walking-skeleton-missing` — [^.]{0,230}intra-epic `depends_on`' \
  || fail "R6: walking-skeleton-missing trigger does not cover an intra-epic depends_on"
csec '- `internal-only-outcome` — [^.]{0,60}Success outcome[^.]{0,60}only internal artifacts[^.]{0,60}user or client can exercise' \
  || fail "R6: internal-only-outcome trigger missing"
csec 'On the lowest-numbered feature of a fresh drill, `walking-skeleton-missing` subsumes `internal-only-outcome`[^.]{0,80}one finding, not both' \
  || fail "R6: section does not say walking-skeleton-missing subsumes internal-only-outcome on the lowest feature (one finding, not both)"
csec 'briefs under review are the brief paths the Driller passed' || fail "R6: scope signal (the passed paths) missing"
csec '\*\*fresh\*\* when the lowest-numbered feature[^.]{0,80}is among the passed paths' || fail "R6: fresh definition missing"
csec 'an \*\*amend\*\*: `walking-skeleton-missing` is not raised' || fail "R6: amend definition (walking-skeleton-missing not raised) missing"
csec 'briefs the Driller did not pass are never read' || fail "R6: unpassed briefs are not declared never read"
pass "R6_doc_critic_three_findings"

# ── R7: exemption downgrades a finding; advisory like every other finding ────────
csecF 'Observable-slice exemption:' || fail "R7: critic section does not name the Observable-slice exemption: line"
csec 'exemption:. line in the epic.s `## Notes` that names the feature id downgrades the matching finding to an `exemption-recorded` note that is reported but not raised' \
  || fail "R7: exemption line naming the feature id does not downgrade to an exemption-recorded note (reported, not raised)"
csec 'an exemption line that names no feature id is itself reported' \
  || fail "R7: an exemption line naming no feature id is not itself reported"
csec 'advisory[^.]{0,80}never block[^.]{0,80}no gate[^.]{0,40}no (new )?status[^.]{0,40}no schema change' \
  || fail "R7: advisory / never block / no gate / no status / no schema change sentence missing"
csec 'All three findings are advisory' || fail "R7: advisory sentence does not cover all three findings"
if csec 'reject'; then fail "R7: critic section must not tell anyone to reject"; fi
if csec 'fail the drill'; then fail "R7: critic section must not fail the drill"; fi
# any 'block' other than the permitted 'never block' is a blocking claim (A3)
if sed 's/never block//Ig' "$CS" | grep -qiE 'block'; then fail "R7: critic section makes a finding block (only 'never block' is allowed)"; fi
pass "R7_doc_critic_exemption_and_advisory"

# ── R9: docs/WORKFLOW.md section ──────────────────────────────────────────────────
H9='## Observable slices and the walking skeleton (ADR-0008)'
grep -qF "$H9" "$WORKFLOW" || fail "R9: $WORKFLOW lacks the heading '$H9'"
a="$(ln "$WORKFLOW" '## Change-size discipline')"; b="$(ln "$WORKFLOW" '## Observable slices')"
c="$(ln "$WORKFLOW" '## Architecture-aligned specs')"
[ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] \
  || fail "R9: the section is not between Change-size discipline and Architecture-aligned specs"
range "$WORKFLOW" '## Observable slices' '## Architecture-aligned specs' | tr '\n' ' ' > "$T/wf-sec.txt"
WS="$T/wf-sec.txt"
wsec() { grep -qiE -e "$1" "$WS"; }
wsecF() { grep -qF -- "$1" "$WS"; }
wsec 'product boundary[^.]{0,120}HTTP[^.]{0,40}CLI[^.]{0,40}UI[^.]{0,40}file[^.]{0,40}exit code' \
  || fail "R9: section does not state the product-boundary clause"
wsec 'a UI interaction, a file a user or client reads or an exit code' \
  || fail "R9: section counts an internal storage file as observable (must be 'a file a user or client reads')"
wsec 'first feature of a fresh epic is the walking skeleton' || fail "R9: section does not state the walking-skeleton clause"
wsec 'internal[^.]{0,80}merged[^.]{0,40}consum' || fail "R9: section does not state the merge-into-consumer clause"
wsec 'beginning `Observable-slice exemption:`' || fail "R9: section does not state the Observable-slice exemption: Notes line"
wsec 'only consumer is another epic' || fail "R9: section does not carry the cross-epic exemption"
for id in observable-behavior-missing walking-skeleton-missing internal-only-outcome exemption-recorded; do
  wsecF "$id" || fail "R9: section does not name finding $id"
done
wsecF 'agents/driller.md' || fail "R9: section does not point at agents/driller.md"
wsecF 'agents/doc-critic.md' || fail "R9: section does not point at agents/doc-critic.md"
wsec 'advisory[^.]{0,40}never blocks' || fail "R9: section does not say the rule is advisory and never blocks"
pass "R9_workflow_section"

# ── R10: VERSION / CHANGELOG paired at run time (never a frozen literal) ──────────
v="$(tr -d '[:space:]' < VERSION)"
newest="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' CHANGELOG.md | head -1)"
[ -n "$v" ] && [ "$newest" = "$v" ] || fail "R10: newest CHANGELOG heading ($newest) != VERSION ($v)"
# some section body (up to the next '## [' heading) names the feature and the exemption token
awk '/^## \[/{if(sec ~ /E36-F02/ && sec ~ /Observable-slice exemption/){ok=1} sec=""; next} {sec=sec $0 "\n"}
     END{if(sec ~ /E36-F02/ && sec ~ /Observable-slice exemption/){ok=1} exit ok?0:1}' CHANGELOG.md \
  || fail "R10: no CHANGELOG section names both E36-F02 and Observable-slice exemption"
pass "R10_version_changelog_paired"
