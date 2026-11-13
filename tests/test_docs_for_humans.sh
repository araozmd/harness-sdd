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

# ---------------------------------------------------------------- R3 — the human README
README="$ROOT/README.md"
KEPT_TOKENS='/sdd-plan
/sdd-new
/sdd-drill
/sdd-next
/sdd-fix
/sdd-fix-parallel
/sdd-pr-loop
/sdd-report
$sdd-report
.agents/skills
Antigravity
pi
--agents=host
ADR
Codex GitHub App
opt-in
[why the harness exists](docs/RATIONALE.md)
[RATIONALE.md](docs/RATIONALE.md)
docs/INSTALL.md#bootstrap-first-run'

# budget_ok <file> <n> — the file has at most n lines.
budget_ok() { [ "$(nlines "$1")" -le "$2" ]; }

R3_h1_brand_token() {
  _l1="$(sed -n '1p' "$README")"
  printf '%s\n' "$_l1" | grep -qE '^<h1 align="center">.*</h1>$' || fail "R3: README line 1 is not the centered HTML <h1> (got: $_l1)"
  printf '%s\n' "$_l1" | grep -qF 'src="assets/logo-wordmark.svg"' || fail "R3: the README <h1> does not embed assets/logo-wordmark.svg"
  _alt="$(printf '%s\n' "$_l1" | sed -n 's/.*<img [^>]*alt="\([^"]*\)".*/\1/p')"
  [ "$_alt" = "harness-loop" ] || fail "R3: the README <h1> image alt is not exactly 'harness-loop' (got: $_alt)"
  [ "$(grep -c '<h1' "$README")" -eq 1 ] || fail "R3: README must hold exactly one <h1>"
  grep -q '^# ' "$README" && fail "R3: README also carries a Markdown H1; the wordmark is the heading"
  pass "R3_h1_brand_token"
}
R3_logo_and_tagline() {
  sed -n '1,12p' "$README" | grep -qF 'assets/logo' || fail "R3: README does not reference assets/logo* within its first 12 lines"
  sed -n '1,15p' "$README" | grep -qF 'docs/agents/README.md' || fail "R3: README does not link docs/agents/README.md within its first 15 lines"
  [ -f "$ROOT/docs/BRAND.md" ] || fail "R3: docs/BRAND.md does not exist (the tagline source)"
  _tag="$(sed -n 's/^\*\*Tagline\.\*\* //p' "$ROOT/docs/BRAND.md")"
  [ -n "$_tag" ] || fail "R3: docs/BRAND.md has no '**Tagline.** ' line"
  sed -n '2,8p' "$README" | grep -qxF "<p align=\"center\">$_tag</p>" || fail "R3: no centered README line within lines 2-8 wraps the BRAND.md tagline byte for byte"
  pass "R3_logo_and_tagline"
}
R3_how_it_works_diagram() {
  _s="$(slice "$README" "## How it works")"
  [ -n "$_s" ] || fail "R3: README has no ## How it works section"
  _n="$(printf '%s\n' "$_s" | grep -cE '^ {0,3}(```|~~~)[ 	]*mermaid[ 	]*$' || true)"
  [ "$_n" -eq 1 ] || fail "R3: ## How it works holds $_n mermaid blocks, expected exactly 1"
  _d="$(printf '%s\n' "$_s" | mermaid_blocks)"
  for _w in spec-ready in-progress in-review done approve Reviewer; do
    printf '%s\n' "$_d" | grep -qF -- "$_w" || fail "R3: the How it works diagram does not name '$_w'"
  done
  for _e in '-->|spec-ready|' '-->|in-progress|' '-->|in-review|' '-->|done|'; do
    printf '%s\n' "$_d" | grep -qF -- "$_e" || fail "R3: the diagram does not label a solid edge '$_e'"
  done
  printf '%s\n' "$_d" | grep -qF -- '-.' && fail "R3: the diagram still has dotted edges"
  _hero="$(printf '%s\n' "$_s" | grep -n 'assets/hero.svg' | head -n 1 | cut -d: -f1)"
  _fence="$(printf '%s\n' "$_s" | grep -n 'mermaid' | head -n 1 | cut -d: -f1)"
  [ -n "$_hero" ] && [ "$_hero" -lt "$_fence" ] || fail "R3: assets/hero.svg is not embedded in ## How it works above the diagram"
  pass "R3_how_it_works_diagram"
}
R3_quick_start_three_steps() {
  _s="$(slice "$README" "## Quick start")"
  [ -n "$_s" ] || fail "R3: README has no ## Quick start section"
  _n="$(printf '%s\n' "$_s" | grep -cE '^[0-9]+\. ' || true)"
  [ "$_n" -ge 1 ] && [ "$_n" -le 3 ] || fail "R3: ## Quick start has $_n numbered steps, expected 1 to 3"
  pass "R3_quick_start_three_steps"
}
R3_sections_and_links() {
  has_heading "$README" "## Supported CLIs" || fail "R3: README has no ## Supported CLIs"
  has_heading "$README" "## Documentation" || fail "R3: README has no ## Documentation"
  _s="$(slice "$README" "## Documentation")"
  for _l in docs/README.md docs/CONCEPTS.md docs/INSTALL.md docs/WORKFLOW.md docs/BRAND.md docs/agents/README.md; do
    printf '%s\n' "$_s" | grep -qF "]($_l)" || fail "R3: ## Documentation does not link $_l"
  done
  pass "R3_sections_and_links"
}
R3_kept_tokens() {
  while IFS= read -r _t; do
    grep -qF -- "$_t" "$README" || fail "R3: README lost the kept token '$_t'"
  done <<EOT
$KEPT_TOKENS
EOT
  pass "R3_kept_tokens"
}
R3_budget_150() {
  budget_ok "$README" 150 || fail "R3: README exceeds 150 lines"
  pass "R3_budget_150"
}

# ---------------------------------------------------------------- R5 — CONCEPTS
CONCEPTS="$ROOT/docs/CONCEPTS.md"
R5_concepts_sections() {
  [ -f "$CONCEPTS" ] || fail "R5: docs/CONCEPTS.md does not exist"
  for _h in "## The loop" "## Specs" "## Gates" "## Code over prose" \
            "## Review: the elephant and the goldfish" "## Further reading"; do
    has_heading "$CONCEPTS" "$_h" || fail "R5: CONCEPTS has no '$_h' section"
  done
  pass "R5_concepts_sections"
}
R5_concepts_state_diagram() {
  _s="$(slice "$CONCEPTS" "## The loop")"
  _n="$(printf '%s\n' "$_s" | grep -cE '^ {0,3}(```|~~~)[ 	]*mermaid[ 	]*$' || true)"
  [ "$_n" -eq 1 ] || fail "R5: ## The loop holds $_n mermaid blocks, expected exactly 1"
  _d="$(printf '%s\n' "$_s" | mermaid_blocks)"
  [ "$(printf '%s\n' "$_d" | sed -n '2p' | sed 's/^[[:space:]]*//')" = "stateDiagram-v2" ] ||
    fail "R5: the ## The loop diagram is not a stateDiagram-v2"
  for _w in pending spec-ready in-progress in-review done; do
    printf '%s\n' "$_d" | grep -qF -- "$_w" || fail "R5: the state diagram does not name '$_w'"
  done
  pass "R5_concepts_state_diagram"
}
R5_concepts_review_names_both_mechanisms() {
  _s="$(slice "$CONCEPTS" "## Review: the elephant and the goldfish" | folded)"
  printf '%s' "$_s" | grep -qiE 'paraphrase-back.{0,12}Doc-critic' ||
    fail "R5: the review section does not name the Doc-critic's paraphrase-back"
  printf '%s' "$_s" | grep -qiE 'drift report.{0,12}drift-report\.py|drift-report\.py.{0,200}drift report|Drift report' ||
    fail "R5: the review section does not name the drift report"
  pass "R5_concepts_review_names_both_mechanisms"
}
R5_concepts_links() {
  for _l in RATIONALE.md ABLATION.md SPEC-FORMAT.md WORKFLOW.md agents/README.md; do
    grep -qF "]($_l)" "$CONCEPTS" || fail "R5: CONCEPTS does not link $_l"
  done
  sed -n '1,15p' "$CONCEPTS" | grep -qF '](agents/README.md)' || fail "R5: CONCEPTS does not link agents/README.md within its first 15 lines"
  pass "R5_concepts_links"
}
R5_budget_220() {
  budget_ok "$CONCEPTS" 220 || fail "R5: CONCEPTS exceeds 220 lines"
  pass "R5_budget_220"
}

# ---------------------------------------------------------------- R11 — brand
BRAND="$ROOT/docs/BRAND.md"
R11_brand_doc_shape() {
  [ -f "$BRAND" ] || fail "R11: docs/BRAND.md does not exist"
  grep -qxF '**Name.** harness-loop' "$BRAND" || fail "R11: BRAND.md lacks the line '**Name.** harness-loop'"
  grep -q '^\*\*Tagline\.\*\* ' "$BRAND" || fail "R11: BRAND.md lacks a '**Tagline.** ' line"
  for _h in "## Positioning" "## Voice" "## Palette" "## Logo" "## Where the name appears"; do
    has_heading "$BRAND" "$_h" || fail "R11: BRAND.md has no '$_h' section"
  done
  for _a in assets/logo.svg assets/logo-wordmark.svg assets/social-preview.png; do
    grep -qF "\`$_a\`" "$BRAND" || fail "R11: BRAND.md does not name \`$_a\` in a code span"
  done
  pass "R11_brand_doc_shape"
}
R11_brand_embeds_art() {
  _u='https://raw.githubusercontent.com/araozmd/harness-loop/main/assets/'
  sed -n '1,6p' "$BRAND" | grep -qF "](${_u}logo-wordmark.svg)" || fail "R11: BRAND.md does not embed the light wordmark within its first 6 lines"
  slice "$BRAND" "## Logo" | sed -n '1,3p' | grep -qF "](${_u}brand-sheet.png)" || fail "R11: BRAND.md does not embed brand-sheet.png at the top of ## Logo"
  pass "R11_brand_embeds_art"
}
R11_brand_installed_names_sentence() {
  grep -qxF 'Installed names do not change: `.harness/`, `harness-install.sh`, `harness.config.yaml` and the `/sdd-*` commands keep their names.' "$BRAND" ||
    fail "R11: BRAND.md lacks the installed-names sentence, byte for byte"
  pass "R11_brand_installed_names_sentence"
}
R11_palette_tokens() {
  _p="$(slice "$BRAND" "## Palette")"
  printf '%s\n' "$_p" | grep -qF '#1D0658' || fail "R11: the palette lacks #1D0658"
  printf '%s\n' "$_p" | grep -qF '#FE5F4B' || fail "R11: the palette lacks #FE5F4B"
  pass "R11_palette_tokens"
}
# svg_names_brand <file> — parses as XML and carries "harness-loop" as element text, a <title>
# or an aria-label.
svg_names_brand() {
  python3 -I - "$1" <<'PY'
import sys, xml.etree.ElementTree as ET
t = ET.parse(sys.argv[1]).getroot()
hits = []
for e in t.iter():
    tag = e.tag.rsplit('}', 1)[-1]
    if tag == 'title': hits.append(''.join(e.itertext()))
    if e.get('aria-label'): hits.append(e.get('aria-label'))
    if tag == 'text': hits.append(''.join(e.itertext()))
sys.exit(0 if any(h.strip() == 'harness-loop' for h in hits) else 3)
PY
}
svg_parses() { python3 -I -c 'import sys, xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$1" 2>/dev/null; }
# png_size <file> — "<w> <h>" from the IHDR chunk.
png_size() {
  python3 -I -c '
import struct, sys
d = open(sys.argv[1], "rb").read()
assert d[:8] == b"\x89PNG\r\n\x1a\n" and d[12:16] == b"IHDR"
print(*struct.unpack(">II", d[16:24]))' "$1"
}
R11_svgs_parse_and_wordmark_names_brand() {
  [ -f "$ROOT/assets/logo.svg" ] || fail "R11: assets/logo.svg does not exist"
  [ -f "$ROOT/assets/logo-wordmark.svg" ] || fail "R11: assets/logo-wordmark.svg does not exist"
  svg_parses "$ROOT/assets/logo.svg" || fail "R11: assets/logo.svg is not well-formed XML"
  svg_parses "$ROOT/assets/logo-wordmark.svg" || fail "R11: assets/logo-wordmark.svg is not well-formed XML"
  svg_names_brand "$ROOT/assets/logo-wordmark.svg" || fail "R11: assets/logo-wordmark.svg does not carry 'harness-loop' as text, <title> or aria-label"
  # control: a wordmark stripped of its name is caught
  sed -e 's/aria-label="[^"]*"//' -e 's#<text[^>]*>.*</text>##' "$ROOT/assets/logo-wordmark.svg" > "$T/wm-stripped.svg"
  if svg_names_brand "$T/wm-stripped.svg" 2>/dev/null; then fail "R11: the name check passes on a wordmark with its name removed"; fi
  pass "R11_svgs_parse_and_wordmark_names_brand"
}
R11_social_preview_1280x640() {
  [ -f "$ROOT/assets/social-preview.png" ] || fail "R11: assets/social-preview.png does not exist"
  [ "$(png_size "$ROOT/assets/social-preview.png")" = "1280 640" ] || fail "R11: assets/social-preview.png is not 1280x640"
  pass "R11_social_preview_1280x640"
}
R11_budget_90() {
  budget_ok "$BRAND" 90 || fail "R11: BRAND.md exceeds 90 lines"
  pass "R11_budget_90"
}

# ---------------------------------------------------------------- R6 — the style lint
# Each check takes one file (and a budget / diagram flag) and returns 0 when clean, so a row
# can run it on the committed doc and on a mutated copy.
FILLER='it is important to note
it'"'"'s important to note
it is worth noting
it'"'"'s worth noting
note that
please note
this is important because
as mentioned above
as noted above
in other words
basically
simply put
needless to say
keep in mind'
lint_budget() { budget_ok "$1" "$2"; }
lint_filler() {
  unfenced "$1" > "$T/lint.txt"
  while IFS= read -r _p; do
    if grep -qiF -- "$_p" "$T/lint.txt"; then LINT_HIT="$_p"; return 1; fi
  done <<EOT
$FILLER
EOT
  return 0
}
lint_archaeology() {
  unfenced "$1" > "$T/lint.txt"
  if grep -qE 'E[0-9]{2}-F[0-9]{2,3}|#[0-9]{9,}|[Rr]ound [0-9]+|Codex (r[0-9]|round|#|P[0-3])' "$T/lint.txt"; then
    LINT_HIT="$(grep -oE 'E[0-9]{2}-F[0-9]{2,3}|#[0-9]{9,}|[Rr]ound [0-9]+|Codex (r[0-9]|round|#|P[0-3])' "$T/lint.txt" | head -n 1)"
    return 1
  fi
  return 0
}
lint_diagram() {
  _first="$(mermaid_blocks < "$1" | awk '/^@@MERMAID$/ { want = 1; next } want { print; want = 0 }' | sed 's/^[[:space:]]*//')"
  [ -n "$_first" ] || return 1
  printf '%s\n' "$_first" | grep -qE '^(flowchart|graph|stateDiagram-v2|sequenceDiagram|classDiagram|erDiagram)' || return 1
  return 0
}
# registry_each <fn> — call <fn> path budget diagram for every registry entry.
registry_each() {
  for _e in $HUMAN_DOCS; do
    _path="${_e%%:*}"; _rest="${_e#*:}"; _bud="${_rest%%:*}"; _dia="${_rest#*:}"
    "$1" "$_path" "$_bud" "$_dia"
  done
}
R6_budget() {
  _each() { [ -f "$ROOT/$1" ] || fail "R6: registry doc $1 does not exist"
            lint_budget "$ROOT/$1" "$2" || fail "R6: $1 exceeds its budget of $2 lines"; }
  registry_each _each
  # mutant: a copy one line over its budget is caught
  cp "$README" "$T/m-budget.md"; _n="$(nlines "$T/m-budget.md")"
  lint_budget "$T/m-budget.md" "$((_n - 1))" && fail "R6: the budget check passes a file over its budget"
  lint_budget "$T/m-budget.md" "$_n" || fail "R6: the budget check fails a file exactly at its budget"
  pass "R6_budget"
}
R6_filler_phrases() {
  _each() { lint_filler "$ROOT/$1" || fail "R6: $1 contains the filler phrase '$LINT_HIT'"; }
  registry_each _each
  cp "$CONCEPTS" "$T/m-filler.md"; printf '\nNote that this is fine.\n' >> "$T/m-filler.md"
  lint_filler "$T/m-filler.md" && fail "R6: the filler check misses an appended 'Note that'"
  cp "$CONCEPTS" "$T/m-filler2.md"; printf '\nIT IS WORTH NOTING the case does not matter.\n' >> "$T/m-filler2.md"
  lint_filler "$T/m-filler2.md" && fail "R6: the filler check is case-sensitive"
  cp "$CONCEPTS" "$T/m-filler3.md"; printf '\n```text\nNote that this is inside a fence.\n```\n' >> "$T/m-filler3.md"
  lint_filler "$T/m-filler3.md" || fail "R6: the filler check flags a phrase inside a fenced block"
  pass "R6_filler_phrases"
}
R6_archaeology() {
  _each() { lint_archaeology "$ROOT/$1" || fail "R6: $1 contains the archaeology pattern '$LINT_HIT'"; }
  registry_each _each
  for _m in '(E12-F34)' 'see #3802057859' 'Codex round 3' 'Codex r3' 'Codex #12' 'Codex P1' 'in Round 4'; do
    cp "$CONCEPTS" "$T/m-arch.md"; printf '\n%s\n' "$_m" >> "$T/m-arch.md"
    lint_archaeology "$T/m-arch.md" && fail "R6: the archaeology check misses '$_m'"
  done
  cp "$CONCEPTS" "$T/m-arch2.md"; printf '\nThe Codex GitHub App and the Codex CLI are fine.\n' >> "$T/m-arch2.md"
  lint_archaeology "$T/m-arch2.md" || fail "R6: the archaeology check flags the bare CLI name"
  pass "R6_archaeology"
}
R6_diagram_present_and_typed() {
  _each() { [ "$3" = "yes" ] || return 0
            lint_diagram "$ROOT/$1" || fail "R6: $1 has no typed mermaid block"; }
  registry_each _each
  sed 's/^stateDiagram-v2$/mindmap/' "$CONCEPTS" > "$T/m-dia.md"
  grep -qx 'mindmap' "$T/m-dia.md" || fail "R6: setup: the mindmap mutant did not apply"
  # CONCEPTS holds two diagrams; the mutant leaves the flowchart, so also test a one-diagram doc
  printf '# t\n\n```mermaid\nmindmap\n  root\n```\n' > "$T/m-dia1.md"
  lint_diagram "$T/m-dia1.md" && fail "R6: the diagram check accepts a mindmap block"
  printf '# t\n\n```text\nflowchart LR\n```\n' > "$T/m-dia2.md"
  lint_diagram "$T/m-dia2.md" && fail "R6: the diagram check accepts a non-mermaid fence"
  printf '# t\n\nno diagram\n' > "$T/m-dia3.md"
  lint_diagram "$T/m-dia3.md" && fail "R6: the diagram check accepts a doc with no diagram"
  printf '# t\n\n```mermaid\nflowchart LR\n  a --> b\n```\n' > "$T/m-dia4.md"
  lint_diagram "$T/m-dia4.md" || fail "R6: the diagram check rejects a typed flowchart"
  pass "R6_diagram_present_and_typed"
}

# ---------------------------------------------------------------- R2, R9 — shipping and navigation
# link_targets <file> — every Markdown link or image target on its own line (anchors kept).
link_targets() {
  unfenced "$1" | awk '{
    line = $0
    while (match(line, /\]\([^)]*\)/)) { print substr(line, RSTART + 2, RLENGTH - 3); line = substr(line, RSTART + RLENGTH) }
  }'
}
# links_into_assets <root> — print each docs/ link target that reaches assets/: a relative
# target that resolves under <root>/assets/, or an absolute one that names /assets/ unless it
# sits in docs/BRAND.md and starts with a canonical prefix.
links_into_assets() {
  find "$1/docs" -name '*.md' | sort | while IFS= read -r _f; do
    link_targets "$_f" | while IFS= read -r _t; do
      case "$_t" in ""|\#*|mailto:*) continue ;; esac
      printf '%s\t%s\n' "$_f" "${_t%%#*}"
    done
  done | python3 -I -c '
import os, sys
root = sys.argv[1]
assets = os.path.join(root, "assets")
ok = ("https://raw.githubusercontent.com/araozmd/harness-loop/main/assets/",
      "https://github.com/araozmd/harness-loop/blob/main/assets/")
for line in sys.stdin:
    f, t = line.rstrip("\n").split("\t")
    rel = os.path.relpath(f, root)
    if t.startswith(("http://", "https://")):
        if "/assets/" in t and not (rel == os.path.join("docs", "BRAND.md") and t.startswith(ok)):
            print(rel + " -> " + t)
        continue
    p = os.path.normpath(os.path.join(os.path.dirname(f), t))
    if p == assets or p.startswith(assets + os.sep):
        print(rel + " -> " + t)' "$1"
  # HTML attributes are not Markdown links; no doc may point one at a relative assets/ path
  grep -rEn '(src|href)="(\.\./|\./)*assets/' "$1/docs" 2>/dev/null || true
}
R2_no_assets_links_under_docs() {
  _bad="$(links_into_assets "$ROOT")"
  [ -z "$_bad" ] || fail "R2: a doc under docs/ links into assets/: $_bad"
  rm -rf "$T/r2"; mkdir -p "$T/r2"; cp -R "$ROOT/docs" "$T/r2/docs"
  printf '\n![logo](../assets/logo.svg)\n' >> "$T/r2/docs/BRAND.md"
  [ -n "$(links_into_assets "$T/r2")" ] || fail "R2: the assets-link check misses an image embed"
  rm -rf "$T/r2"; mkdir -p "$T/r2"; cp -R "$ROOT/docs" "$T/r2/docs"
  printf '\n[sheet](agents/../../assets/brand-sheet.png)\n' >> "$T/r2/docs/README.md"
  [ -n "$(links_into_assets "$T/r2")" ] || fail "R2: the assets-link check misses a link that reaches assets/ through a .. segment"
  _canon='https://raw.githubusercontent.com/araozmd/harness-loop/main/assets/logo.svg'
  rm -rf "$T/r2"; mkdir -p "$T/r2"; cp -R "$ROOT/docs" "$T/r2/docs"
  printf '\n![x](%s)\n' "$_canon" >> "$T/r2/docs/BRAND.md"
  [ -z "$(links_into_assets "$T/r2")" ] || fail "R2: a canonical absolute URL in docs/BRAND.md was flagged"
  printf '\n![x](%s)\n' "$_canon" >> "$T/r2/docs/README.md"
  [ -n "$(links_into_assets "$T/r2")" ] || fail "R2: a canonical absolute assets URL outside docs/BRAND.md was not flagged"
  rm -rf "$T/r2"; mkdir -p "$T/r2"; cp -R "$ROOT/docs" "$T/r2/docs"
  printf '\n![x](https://example.com/assets/logo.svg)\n' >> "$T/r2/docs/BRAND.md"
  [ -n "$(links_into_assets "$T/r2")" ] || fail "R2: a non-canonical absolute assets URL in docs/BRAND.md was not flagged"
  rm -rf "$T/r2"; mkdir -p "$T/r2"; cp -R "$ROOT/docs" "$T/r2/docs"
  printf '\n<img src="../assets/logo.svg">\n' >> "$T/r2/docs/BRAND.md"
  [ -n "$(links_into_assets "$T/r2")" ] || fail "R2: a relative HTML img into assets/ was not flagged"
  pass "R2_no_assets_links_under_docs"
}

# broken_links <root> — print every relative link target under README.md and docs/**/*.md
# that does not resolve.
broken_links() {
  { echo "$1/README.md"; find "$1/docs" -name '*.md' | sort; } | while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    link_targets "$_f" | while IFS= read -r _t; do
      case "$_t" in ""|\#*|http://*|https://*|mailto:*) continue ;; esac
      _t="${_t%%#*}"
      [ -e "$(dirname "$_f")/$_t" ] || echo "${_f#"$1/"} -> $_t"
    done
  done
}
# mirror <dir> — a private copy of README.md and docs/ under $T/<dir>.
mirror() { rm -rf "$T/$1"; mkdir -p "$T/$1"; cp "$ROOT/README.md" "$T/$1/"; cp -R "$ROOT/docs" "$T/$1/docs"; }

R9_relative_links_resolve() {
  _bad="$(broken_links "$ROOT")"
  [ -z "$_bad" ] || fail "R9: unresolved relative links: $_bad"
  mirror m9
  printf '\n[x](../nowhere.md)\n' >> "$T/m9/docs/README.md"
  [ -n "$(broken_links "$T/m9")" ] || fail "R9: the link check misses a broken link"
  pass "R9_relative_links_resolve"
}
# counterpart_problems <root> — human docs with a counterpart that do not link it early.
counterpart_problems() {
  for _a in "$1"/docs/agents/*.md; do
    _n="$(basename "$_a")"
    if [ "$_n" = "README.md" ]; then
      sed -n '1,15p' "$1/README.md" | grep -qF 'docs/agents/README.md' || echo "README.md"
      sed -n '1,15p' "$1/docs/README.md" | grep -qF 'agents/README.md' || echo "docs/README.md"
    else
      [ -f "$1/docs/$_n" ] && { sed -n '1,15p' "$1/docs/$_n" | grep -qF "agents/$_n" || echo "docs/$_n"; }
    fi
  done
}
R9_counterpart_links() {
  _bad="$(counterpart_problems "$ROOT")"
  [ -z "$_bad" ] || fail "R9: a human doc does not link its counterpart in the first 15 lines: $_bad"
  mirror m9b
  sed "s#docs/agents/README.md#docs/AGENTS-MOVED.md#g" "$T/m9b/README.md" > "$T/m9b/r.new" && mv "$T/m9b/r.new" "$T/m9b/README.md"
  [ -n "$(counterpart_problems "$T/m9b")" ] || fail "R9: the counterpart check misses a README without the link"
  pass "R9_counterpart_links"
}
# index_problems <root> — orphan counterparts, missing rows, rows naming absent paths.
index_problems() {
  for _a in "$1"/docs/agents/*.md; do
    _n="$(basename "$_a")"
    index_rows "$1/docs/agents/README.md" | awk -v b="docs/agents/$_n" '$2 == b { f = 1 } END { exit !f }' || echo "no index row for docs/agents/$_n"
    [ "$_n" = "README.md" ] || [ -f "$1/docs/$_n" ] || echo "no human counterpart docs/$_n"
  done
  index_rows "$1/docs/agents/README.md" | while read -r _h _m; do
    [ -f "$1/$_h" ] || echo "index row names a missing path $_h"
    [ -f "$1/$_m" ] || echo "index row names a missing path $_m"
  done
}
R9_index_complete() {
  _bad="$(index_problems "$ROOT")"
  [ -z "$_bad" ] || fail "R9: $_bad"
  mirror m9c; : > "$T/m9c/docs/agents/ORPHAN.md"
  index_problems "$T/m9c" | grep 'ORPHAN' >/dev/null || fail "R9: the index check misses an orphan machine file"
  pass "R9_index_complete"
}
R9_index_rows_exist() {
  mirror m9d
  printf '| `README.md` | `docs/agents/GONE.md` | nothing |\n' > "$T/row.txt"
  awk -v r="$(cat "$T/row.txt")" '{ print } /^\|---\|---\|---\|$/ { print r }' "$T/m9d/docs/agents/README.md" > "$T/m9d/new.md"
  mv "$T/m9d/new.md" "$T/m9d/docs/agents/README.md"
  index_problems "$T/m9d" | grep 'GONE.md' >/dev/null || fail "R9: the index check misses a row naming an absent path"
  _bad="$(index_problems "$ROOT")"
  [ -z "$_bad" ] || fail "R9: the committed index names absent paths: $_bad"
  pass "R9_index_rows_exist"
}

# ---------------------------------------------------------------- R10 — the entrypoint map
R10_agents_md_rows() {
  grep -qF '| `docs/CONCEPTS.md` |' "$ROOT/AGENTS.md" || fail "R10: AGENTS.md lacks the docs/CONCEPTS.md row"
  grep -qF '| `docs/agents/README.md` |' "$ROOT/AGENTS.md" || fail "R10: AGENTS.md lacks the docs/agents/README.md row"
  pass "R10_agents_md_rows"
}

R10_repo_citations_resolve() {
  run_cite --root "$ROOT"
  [ "$rc" -eq 0 ] || fail "R10: doc-cite-check found unresolved citations: $(tr '\n' '|' < "$T/cout")"
  tail -n 1 "$T/cout" | grep -qE '^doc-cite-check: 0 findings, [0-9]+ files scanned$' || fail "R10: the summary is not '0 findings'"
  # control: with a cited doc missing from a mirror the same tool exits 1 and names the citing file
  rm -rf "$T/m10"; mkdir -p "$T/m10"; cp -R "$ROOT/agents" "$ROOT/docs" "$T/m10/"
  rm "$T/m10/docs/SPEC-FORMAT.md"
  run_cite --root "$T/m10" agents/architect.md
  [ "$rc" -eq 1 ] || fail "R10: a mirror without docs/SPEC-FORMAT.md exited $rc, expected 1"
  grep -q '^CITE agents/architect.md:[0-9]* docs/SPEC-FORMAT.md ' "$T/cout" || fail "R10: the missing doc is not reported against agents/architect.md"
  pass "R10_repo_citations_resolve"
}

# ---------------------------------------------------------------- R12 — release
R12_version_minor_and_changelog() {
  _cur="$(cat "$ROOT/VERSION")"
  grep -qF "## [$_cur]" "$ROOT/CHANGELOG.md" || fail "R12: CHANGELOG has no '## [$_cur]' section for the runtime VERSION"
  # _chk <changelog> — the FIRST section that names all five tokens must sit exactly one MINOR
  # (patch 0) above the section directly below it. Returns 1 with a reason on stderr.
  _chk() {
    _v="$(awk '
      function flush() {
        if (sec != "" && f == "" && body ~ /E39-F01/ && body ~ /docs\/agents\// && body ~ /harness-loop/ \
            && body ~ /tools\/doc-cite-check\.py/ && body ~ /tools\/docs-move-check\.sh/) f = sec
        else if (f != "" && o == "" && sec != "") o = sec
      }
      /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ { flush(); v = $2; gsub(/[][]/, "", v); sec = v; body = ""; next }
      { body = body "\n" $0 }
      END { flush(); print f; print o }' "$1")"
    _f="$(printf '%s\n' "$_v" | sed -n '1p')"; _o="$(printf '%s\n' "$_v" | sed -n '2p')"
    [ -n "$_f" ] || { echo "no section names E39-F01, docs/agents/, harness-loop and both tools" >&2; return 1; }
    [ -n "$_o" ] || { echo "the section $_f has no older section below it" >&2; return 1; }
    IFS=. read -r _fa _fb _fc <<EOV
$_f
EOV
    IFS=. read -r _oa _ob _oc <<EOV
$_o
EOV
    [ "$_fa" -eq "$_oa" ] && [ "$_fb" -eq $((_ob + 1)) ] && [ "$_fc" -eq 0 ] ||
      { echo "$_f is not one MINOR above $_o with patch 0" >&2; return 1; }
    return 0
  }
  _chk "$ROOT/CHANGELOG.md" 2>"$T/err" || fail "R12: $(cat "$T/err")"
  sed 's#tools/docs-move-check\.sh#tools/removed#g' "$ROOT/CHANGELOG.md" > "$T/cl-1.md"
  _chk "$T/cl-1.md" 2>/dev/null && fail "R12: the changelog check misses a section without docs-move-check.sh"
  _fv="$(awk '/^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ { v = $2; gsub(/[][]/, "", v); sec = v } /E39-F01/ { print sec; exit }' "$ROOT/CHANGELOG.md")"
  [ -n "$_fv" ] || fail "R12: no CHANGELOG section names E39-F01"
  sed "s/^## \[$_fv\]/## [${_fv%.*}.1]/" "$ROOT/CHANGELOG.md" > "$T/cl-3.md"
  grep -qF "## [${_fv%.*}.1]" "$T/cl-3.md" || fail "R12: setup: the PATCH mutant did not apply"
  _chk "$T/cl-3.md" 2>/dev/null && fail "R12: the changelog check misses a PATCH-step E39-F01 section"
  pass "R12_version_minor_and_changelog"
}

# ---------------------------------------------------------------- R7 — doc-cite-check
# run_cite <args...> — stdout to $T/cout, stderr to $T/cerr, exit code to $rc.
run_cite() { set +e; python3 "${CITE_TOOL:-$CITE}" "$@" >"$T/cout" 2>"$T/cerr"; rc=$?; set -e; }
D14="$(printf '\342\200\224')"   # U+2014, the dash in a CITE line
fresh_fx() { rm -rf "$T/$1"; mkdir -p "$T/$1"; cp -R "$FX/repo" "$T/$1/repo"; }

R7_cite_fixture_findings() {
  [ -f "$CITE" ] || fail "R7: tools/doc-cite-check.py does not exist"
  run_cite --root "$FX/repo"
  [ "$rc" -eq 1 ] || fail "R7: expected exit 1 on the fixture, got $rc"
  _want="CITE agents/role.md:12 docs/MISSING.md $D14 no such file
CITE agents/role.md:13 docs/GOOD.md#no-such-slug $D14 no heading matches #no-such-slug
CITE agents/role.md:14 docs/GOOD.md $D14 no heading matches \"Retired section\"
doc-cite-check: 3 findings, 3 files scanned"
  [ "$(cat "$T/cout")" = "$_want" ] || fail "R7: the fixture output is not exactly the three planted findings and the summary: $(tr '\n' '|' < "$T/cout")"
  pass "R7_cite_fixture_findings"
}
R7_cite_ignores_external_and_fenced() {
  run_cite --root "$FX/repo"
  grep -qE 'security|NOPE' "$T/cout" && fail "R7: a lowercase external doc or a fenced citation produced a finding"
  fresh_fx c7; sed 's/^```text$//; s/^```$//' "$T/c7/repo/agents/role.md" > "$T/c7/role.new"
  grep -qF 'docs/NOPE.md' "$T/c7/role.new" || fail "R7: setup: the un-fence mutant lost the NOPE line"
  mv "$T/c7/role.new" "$T/c7/repo/agents/role.md"
  run_cite --root "$T/c7/repo"
  grep -qF 'docs/NOPE.md' "$T/cout" || fail "R7: an un-fenced docs/NOPE.md citation is not reported (the skip is not the fence)"
  fresh_fx c7b; sed 's#docs/security.md#docs/SECURITY.md#' "$T/c7b/repo/agents/role.md" > "$T/c7b/role.new"; mv "$T/c7b/role.new" "$T/c7b/repo/agents/role.md"
  run_cite --root "$T/c7b/repo"
  grep -qF 'docs/SECURITY.md#project-trust' "$T/cout" || fail "R7: an upper-case docs/SECURITY.md is not treated as a harness doc"
  pass "R7_cite_ignores_external_and_fenced"
}
R7_cite_slug_and_prefix_match() {
  run_cite --root "$FX/repo"
  grep -qE 'role.md:(3|4|5) ' "$T/cout" && fail "R7: the em-dash slug, the § prefix or the .harness/ title citation was flagged"
  fresh_fx c8; sed 's/^## Per-role model routing.*/## Model routing per role/' "$T/c8/repo/docs/GOOD.md" > "$T/c8/g.new"; mv "$T/c8/g.new" "$T/c8/repo/docs/GOOD.md"
  run_cite --root "$T/c8/repo"
  grep -qE 'role.md:4 ' "$T/cout" || fail "R7: a renamed heading did not turn the § citation into a finding"
  fresh_fx c8b; sed 's/^## Staying current.*/## Staying current/' "$T/c8b/repo/docs/GOOD.md" > "$T/c8b/g.new"; mv "$T/c8b/g.new" "$T/c8b/repo/docs/GOOD.md"
  run_cite --root "$T/c8b/repo"
  grep -qE 'role.md:3 ' "$T/cout" || fail "R7: a changed heading did not turn the slug citation into a finding"
  grep -qE 'role.md:5 ' "$T/cout" && fail "R7: a title that is a heading prefix was flagged"
  pass "R7_cite_slug_and_prefix_match"
}
R7_cite_exit2_usage() {
  run_cite --root "$T/no-such-dir"
  [ "$rc" -eq 2 ] || fail "R7: --root not a directory exited $rc, expected 2"
  grep -qF 'doc-cite-check: error:' "$T/cerr" || fail "R7: no 'doc-cite-check: error:' on stderr for a bad --root"
  run_cite --bogus; [ "$rc" -eq 2 ] || fail "R7: an unknown flag exited $rc, expected 2"
  run_cite --root "$FX/repo" agents/absent.md; [ "$rc" -eq 2 ] || fail "R7: a missing named file exited $rc, expected 2"
  run_cite --root; [ "$rc" -eq 2 ] || fail "R7: --root without a value exited $rc, expected 2"
  [ ! -s "$T/cout" ] || fail "R7: stdout is not empty on a usage error"
  pass "R7_cite_exit2_usage"
}
R7_cite_help() {
  run_cite -h
  [ "$rc" -eq 0 ] || fail "R7: -h exited $rc, expected 0"
  grep -q '^usage: doc-cite-check.py' "$T/cout" || fail "R7: -h did not print usage on stdout"
  [ ! -s "$T/cerr" ] || fail "R7: -h wrote to stderr"
  pass "R7_cite_help"
}

# ---------------------------------------------------------------- R8 — docs-move-check
# mkrepo <name> — a fresh git repo at $T/<name> with one commit on `main` holding the base docs.
mkrepo() {
  R="$T/$1"; rm -rf "$R"; mkdir -p "$R/docs/agents"; cd "$R"
  git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main 2>/dev/null || true; }
  git config user.name t; git config user.email t@example.invalid
  cat > docs/WORKFLOW.md <<'EOD'
# Workflow

Run `--flag-one` before `init.sh`.
See [the guide](../store/x.md) for `exit-code-7` details.
A sentence about `kept-token` that will be reworded.
Plain prose line.
EOD
  git add -A; git commit -q -m base
  cd "$ROOT"
}
run_move() { # run_move <repo> <args...>
  _r="$1"; shift
  set +e; ( cd "$_r" && sh "$MOVE" "$@" ) >"$T/mout" 2>"$T/merr"; rc=$?; set -e
}
R8_move_clean_exit0() {
  [ -f "$MOVE" ] || fail "R8: tools/docs-move-check.sh does not exist"
  mkrepo r8a; cd "$R"
  cat > docs/WORKFLOW.md <<'EOD'
# Workflow

Plain prose line.
EOD
  cat > docs/agents/WORKFLOW.md <<'EOD'
# Workflow, machine layer

Run   `--flag-one`  before `init.sh`.
See [the guide](../../store/x.md) for `exit-code-7` details.
A sentence about `kept-token` that will be reworded.
EOD
  cd "$ROOT"
  run_move "$R" main
  [ "$rc" -eq 0 ] || fail "R8: a clean move exited $rc: $(tr '\n' '|' < "$T/mout")"
  grep -q ' 0 vanished tokens, 0 dropped lines, 3 moved lines, 1 human docs examined (base ' "$T/mout" ||
    fail "R8: a clean move did not report 0 vanished, 0 dropped, 3 moved: $(tr '\n' '|' < "$T/mout")"
  pass "R8_move_clean_exit0"
}
R8_move_vanished_token_exit1() {
  mkrepo r8b; cd "$R"
  printf '# Workflow\n\nRun `init.sh` first.\nSee `exit-code-7` details.\nA sentence about `kept-token` stays.\n' > docs/WORKFLOW.md
  cd "$ROOT"
  run_move "$R" main
  [ "$rc" -eq 1 ] || fail "R8: a vanished token exited $rc, expected 1"
  [ "$(grep -c '^VANISHED-TOKEN' "$T/mout")" -eq 1 ] || fail "R8: expected exactly one VANISHED-TOKEN line: $(tr '\n' '|' < "$T/mout")"
  grep -qxF 'VANISHED-TOKEN | docs/WORKFLOW.md | --flag-one' "$T/mout" || fail "R8: the VANISHED-TOKEN line is not for --flag-one"
  # control: a token kept in a human doc is not vanished, one kept only under docs/agents/ is not either
  cd "$R"; printf '# Workflow\n\nRun `init.sh` first.\nA sentence about `kept-token` stays.\n' > docs/WORKFLOW.md
  printf '# W\n\n`--flag-one` and `exit-code-7`\n' > docs/agents/WORKFLOW.md; cd "$ROOT"
  run_move "$R" main
  [ "$rc" -eq 0 ] || fail "R8: a token kept under docs/agents/ was reported vanished: $(tr '\n' '|' < "$T/mout")"
  cd "$R"; printf '# Workflow\n\nRun `init.sh` first.\n`--flag-one` `exit-code-7` `kept-token`\n' > docs/WORKFLOW.md; rm docs/agents/WORKFLOW.md; cd "$ROOT"
  run_move "$R" main
  [ "$rc" -eq 0 ] || fail "R8: a token kept in the human doc itself was reported vanished: $(tr '\n' '|' < "$T/mout")"
  pass "R8_move_vanished_token_exit1"
}
R8_move_dropped_line_informational() {
  mkrepo r8c; cd "$R"
  printf '# Workflow\n\nRun `--flag-one` before `init.sh`.\nSee [the guide](../store/x.md) for `exit-code-7` details.\nThe `kept-token` was reworded for people.\n' > docs/WORKFLOW.md
  cd "$ROOT"
  run_move "$R" main
  [ "$rc" -eq 0 ] || fail "R8: dropped lines made the exit nonzero ($rc)"
  grep -q '^DROPPED-LINE | docs/WORKFLOW.md:5 | A sentence about `kept-token` that will be reworded.$' "$T/mout" ||
    fail "R8: the reworded line is not reported as DROPPED-LINE at base line 5: $(tr '\n' '|' < "$T/mout")"
  grep -q ' 0 vanished tokens, 1 dropped lines, 0 moved lines' "$T/mout" || fail "R8: wrong counts: $(tr '\n' '|' < "$T/mout")"
  pass "R8_move_dropped_line_informational"
}
R8_move_link_retarget_counts_as_moved() {
  mkrepo r8d; cd "$R"
  printf '# Workflow\n\nPlain.\n' > docs/WORKFLOW.md
  printf '# W\n\nRun `--flag-one` before `init.sh`.\nSee [the guide](../../elsewhere/y.md) for `exit-code-7` details.\nA sentence about `kept-token` that will be reworded.\n' > docs/agents/WORKFLOW.md
  cd "$ROOT"
  run_move "$R" main
  grep -q ' 0 dropped lines, 3 moved lines' "$T/mout" || fail "R8: a retargeted link line was not counted as moved: $(tr '\n' '|' < "$T/mout")"
  pass "R8_move_link_retarget_counts_as_moved"
}
R8_move_exit2_usage() {
  mkrepo r8e
  run_move "$R"; [ "$rc" -eq 2 ] || fail "R8: a missing base-ref exited $rc, expected 2"
  run_move "$R" --bogus main; [ "$rc" -eq 2 ] || fail "R8: an unknown flag exited $rc, expected 2"
  run_move "$R" main HEAD extra; [ "$rc" -eq 2 ] || fail "R8: a third argument exited $rc, expected 2"
  pass "R8_move_exit2_usage"
}
R8_move_exit3_not_a_repo() {
  rm -rf "$T/norepo"; mkdir -p "$T/norepo"
  run_move "$T/norepo" main
  [ "$rc" -eq 3 ] || fail "R8: outside a git repo exited $rc, expected 3"
  [ -s "$T/merr" ] || fail "R8: no reason on stderr outside a git repo"
  mkrepo r8f
  run_move "$R" no-such-ref
  [ "$rc" -eq 3 ] || fail "R8: an unresolvable ref exited $rc, expected 3"
  [ -s "$T/merr" ] || fail "R8: no reason on stderr for an unresolvable ref"
  pass "R8_move_exit3_not_a_repo"
}
R8_summary_last_line() {
  mkrepo r8g; cd "$R"
  printf '# Workflow\n\nPlain.\n' > docs/WORKFLOW.md; cd "$ROOT"
  run_move "$R" main
  [ "$(grep -c '^docs-move-check: ' "$T/mout")" -eq 1 ] || fail "R8: expected exactly one summary line"
  tail -n 1 "$T/mout" | grep -qE '^docs-move-check: [0-9]+ vanished tokens, [0-9]+ dropped lines, [0-9]+ moved lines, [0-9]+ human docs examined \(base [0-9a-f]+\)$' ||
    fail "R8: the last stdout line is not the summary in the pinned grammar: $(tail -n 1 "$T/mout")"
  pass "R8_summary_last_line"
}

# DISPATCH
if [ -n "${ONLY:-}" ]; then for _r in $ONLY; do row "$_r"; done; exit 0; fi
row R1_announcement; row R1_index_table; row R1_conventions_named; row R1_human_index
row R4_moved_headings_in_order; row R4_pinned_sentences_present
row R3_h1_brand_token; row R3_logo_and_tagline; row R3_how_it_works_diagram
row R3_quick_start_three_steps; row R3_sections_and_links; row R3_kept_tokens; row R3_budget_150
row R5_concepts_sections; row R5_concepts_state_diagram; row R5_concepts_review_names_both_mechanisms
row R5_concepts_links; row R5_budget_220
row R11_brand_doc_shape; row R11_brand_embeds_art; row R11_brand_installed_names_sentence; row R11_palette_tokens
row R11_svgs_parse_and_wordmark_names_brand; row R11_social_preview_1280x640; row R11_budget_90
row R6_budget; row R6_filler_phrases; row R6_archaeology; row R6_diagram_present_and_typed
row R2_no_assets_links_under_docs
row R9_relative_links_resolve; row R9_counterpart_links; row R9_index_complete; row R9_index_rows_exist
row R7_cite_fixture_findings; row R7_cite_ignores_external_and_fenced; row R7_cite_slug_and_prefix_match
row R7_cite_exit2_usage; row R7_cite_help
row R8_move_clean_exit0; row R8_move_vanished_token_exit1; row R8_move_dropped_line_informational
row R8_move_link_retarget_counts_as_moved; row R8_move_exit2_usage; row R8_move_exit3_not_a_repo; row R8_summary_last_line
row R10_agents_md_rows; row R10_repo_citations_resolve
row R12_version_minor_and_changelog
# Dispatch completeness: sees a defined-but-undispatched R*() row.
for f in $(sed -n 's/^\(R[0-9][0-9]*_[A-Za-z0-9_]*\)() *{.*/\1/p' "$ROOT/tests/test_docs_for_humans.sh"); do
  grep -qE "^$f( |\$)" "$T/passed" || fail "$f: defined but not dispatched from the row list"
done
echo "test_docs_for_humans.sh: all rows passed"
