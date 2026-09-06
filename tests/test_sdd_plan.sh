#!/bin/sh
# test_sdd_plan.sh — static + fixture verification for E06-F02 (Planner role +
# /sdd-plan command + vision/architecture/ADR templates + docs).
# This feature ships PROSE (a portable role file, a Claude slash command, three
# templates, two doc edits), so verification is the house way: file-existence +
# required-phrase greps over the portable contract, one python fixture proving the
# canonical seeded shape (status:draft, features:[]) validates against the live
# schema, and one sandboxed ./init.sh exit-0 run. Zero deps: POSIX sh + grep + python3.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact
# VERSION literal (read it at runtime); never git-diff a DO-NOT-TOUCH file against
# main; never mutate the live state/tasks.json (fixtures use temp files).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

ROLE="agents/planner.md"
CMD=".claude/commands/sdd-plan.md"
VTPL="specs/_templates/vision.md"
ATPL="specs/_templates/architecture.md"
DTPL="specs/_templates/adr.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: portable Planner role file ───────────────────────────────────────────────
# R1_planner_role_exists
[ -f "$ROLE" ]                          || fail "R1: $ROLE missing"
tr '\n' ' ' < "$ROLE" | grep -qiE 'vision[.]md[^.]{0,15}north star' || fail "R1: role does not describe vision.md as the north star"
tr '\n' ' ' < "$ROLE" | grep -qiE 'architecture[.]md[^.]{0,15}system shape' || fail "R1: role does not describe architecture.md as the system shape"
grep -qi 'ADR\|adr'      "$ROLE"        || fail "R1: role does not mention ADRs"
tr '\n' ' ' < "$ROLE" | grep -qiE 'block[^.]{0,10}draft[^.]{0,10}epics' || fail "R1: role does not produce a block of draft epics"
grep -qi 'AGENTS.md-compatible\|portable' "$ROLE" || fail "R1: role not stated as portable"
pass "R1 planner_role_exists"

# ── R2: /sdd-plan command points at the role + reads $ARGUMENTS ───────────────────
# R2_sdd_plan_command
[ -f "$CMD" ]                           || fail "R2: $CMD missing"
grep -qF 'agents/planner.md' "$CMD"     || fail "R2: command does not point at agents/planner.md"
grep -qF '$ARGUMENTS' "$CMD"            || fail "R2: command does not read \$ARGUMENTS"
pass "R2 sdd_plan_command"

# ── R3: ≤3 text-only option mockups, never images — in BOTH role and command ──────
# R3_text_only_options
grep -qi 'text.*only\|markdown / ASCII\|markdown/ASCII' "$ROLE" || fail "R3: role does not state text-only options"
grep -qi 'at most 3\|at most three\|≤ *3\|<= *3' "$ROLE"        || fail "R3: role does not cap options at 3"
grep -qi 'never generate images\|not generate images\|never images' "$ROLE" || fail "R3: role does not forbid images"
grep -qi 'text.*only\|markdown / ASCII\|markdown/ASCII' "$CMD"  || fail "R3: command does not state text-only options"
grep -qi 'at most 3\|at most three\|≤ *3\|<= *3' "$CMD"         || fail "R3: command does not cap options at 3"
pass "R3 text_only_options"

# ── R4: vision template (problem/users/outcomes/non-goals) ────────────────────────
# R4_vision_template
[ -f "$VTPL" ]                          || fail "R4: $VTPL missing"
grep -qE '^## Problem' "$VTPL"          || fail "R4: vision template missing the Problem section heading"
grep -qi 'User\|Audience' "$VTPL"       || fail "R4: vision template missing Users/Audience"
grep -qE '^## Outcomes' "$VTPL"         || fail "R4: vision template missing the Outcomes section heading"
grep -qi 'Non-goal'     "$VTPL"         || fail "R4: vision template missing Non-goals"
pass "R4 vision_template"

# ── R5: architecture template (system shape + decisions + ADR index) ──────────────
# R5_arch_template
[ -f "$ATPL" ]                          || fail "R5: $ATPL missing"
tr '\n' ' ' < "$ATPL" | grep -qiE 'system shape[^.]{0,60}decisions' || fail "R5: arch template missing system shape + decisions"
tr '\n' ' ' < "$ATPL" | grep -qiE 'stable[^.]{0,40}decisions' || fail "R5: arch template missing the stable upfront decisions"
grep -qF 'ADR'      "$ATPL"             || fail "R5: arch template missing ADR index"
pass "R5 arch_template"

# ── R6: one-decision ADR template ─────────────────────────────────────────────────
# R6_adr_template
[ -f "$DTPL" ]                          || fail "R6: $DTPL missing"
tr '\n' ' ' < "$DTPL" | grep -qiE 'one architecture decision per ADR' || fail "R6: ADR template missing the one-decision-per-ADR rule"
grep -qi 'Context\|Consequence' "$DTPL" || fail "R6: ADR template missing Context/Consequences"
pass "R6 adr_template"

# ── R7: role mandates writing specs/vision.md from the vision template ────────────
# R7_writes_vision
grep -qF 'specs/vision.md'           "$ROLE" || fail "R7: role does not mandate specs/vision.md"
grep -qF 'specs/_templates/vision.md' "$ROLE" || fail "R7: role does not cite the vision template"
pass "R7 writes_vision"

# ── R8: role mandates writing specs/architecture.md referencing ADRs by id ────────
# R8_writes_architecture
grep -qF 'specs/architecture.md'           "$ROLE" || fail "R8: role does not mandate specs/architecture.md"
grep -qF 'specs/_templates/architecture.md' "$ROLE" || fail "R8: role does not cite the architecture template"
grep -qF 'ADR-' "$ROLE"                            || fail "R8: role does not reference ADRs by id"
pass "R8 writes_architecture"

# ── R9: ADR path/numbering — above-max, 4-digit, no reuse ─────────────────────────
# R9_adr_location_numbering
grep -qF 'specs/adr/' "$ROLE"                       || fail "R9: role does not pin ADR path"
grep -qi 'NNNN\|4-digit\|zero-pad' "$ROLE"          || fail "R9: role does not state 4-digit numbering"
tr '\n' ' ' < "$ROLE" | grep -qiE 'above[^.]{0,15}max[^.]{0,20}ADR number' || fail "R9: role does not state above-max ADR numbering"
grep -qi 'no reuse\|never reuse' "$ROLE"            || fail "R9: role does not state no-reuse"
pass "R9 adr_location_numbering"

# ── R10: depth boundary — stable upfront only; defer deltas to F03; no feature design
# R10_depth_boundary
grep -qi 'upfront\|stable\|whole-system' "$ROLE"    || fail "R10: role does not scope to stable upfront decisions"
tr '\n' ' ' < "$ROLE" | grep -qiE 'per-epic ADR deltas[^.]{0,15}F03' || fail "R10: role does not defer per-epic ADR deltas to F03"
grep -qi '/sdd-drill\|F03' "$ROLE"                  || fail "R10: role does not defer to F03/sdd-drill"
grep -qi 'feature-level' "$ROLE"                    || fail "R10: role does not forbid feature-level design"
pass "R10 depth_boundary"

# ── R11: draft epics, features: [], next-sequential block, no reuse + fixture ──────
# R11_draft_features_empty
grep -qi 'status: "draft"\|draft' "$ROLE"           || fail "R11: role does not state status draft"
grep -qi 'features: \[\]\|empty' "$ROLE"            || fail "R11: role does not state features: []"
grep -qi 'next-sequential\|above' "$ROLE"           || fail "R11: role does not state next-sequential block"
grep -qi 'no reuse\|never reuse' "$ROLE"            || fail "R11: role does not state no-reuse"
# Fixture: a synthetic draft epic with features: [] written to a TEMP store validates
# against store/tasks.schema.json (jsonschema if present, else structural fallback that
# mirrors init.sh). NEVER mutates the live state/tasks.json.
TMPSTORE="$(mktemp)"
trap 'rm -f "$TMPSTORE"' EXIT
cat > "$TMPSTORE" <<'JSON'
{"project":"fixture","epics":[{"id":"E99","title":"Synthetic draft epic","status":"draft","features":[]}]}
JSON
python3 - "$TMPSTORE" store/tasks.schema.json <<'PY' || fail "R11: features:[] draft epic failed schema validation"
import json, re, sys
data = json.load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
try:
    import jsonschema
    errs = sorted(jsonschema.Draft7Validator(schema).iter_errors(data),
                  key=lambda e: list(e.path))
    for e in errs:
        print("  %s: %s" % ("/".join(str(p) for p in e.path) or "(root)", e.message), file=sys.stderr)
    sys.exit(1 if errs else 0)
except ImportError:
    pass
# Structural fallback (subset mirroring init.sh): required fields + status enums +
# id patterns. features: [] is valid (required array, no minItems).
errors = []
EPIC = {"draft","planned","pending","in-progress","done"}
FEAT = {"pending","spec-ready","in-progress","in-review","done"}
for ei, ep in enumerate(data.get("epics", [])):
    if not re.match(r"^E[0-9]+$", ep.get("id","")): errors.append("epic[%d].id" % ei)
    if ep.get("status") not in EPIC: errors.append("epic[%d].status" % ei)
    if not isinstance(ep.get("features"), list): errors.append("epic[%d].features not a list" % ei)
    for fi, ft in enumerate(ep.get("features", [])):
        if not re.match(r"^E[0-9]+-F[0-9]+$", ft.get("id","")): errors.append("epic[%d].feat[%d].id" % (ei,fi))
        if ft.get("status") not in FEAT: errors.append("epic[%d].feat[%d].status" % (ei,fi))
for e in errors: print("  "+e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
rm -f "$TMPSTORE"; trap - EXIT
pass "R11 draft_features_empty"

# ── R12: per-epic epic.md = title + one-paragraph brief only (no F01/specs) ───────
# R12_epic_md_brief_only
grep -qF 'epic.md' "$ROLE"                          || fail "R12: role does not mention epic.md"
grep -qi 'one-paragraph\|business brief' "$ROLE"    || fail "R12: role does not state one-paragraph brief"
grep -qi 'no .*F01\|no `F01`\|no feature spec\|no feature specs' "$ROLE" || fail "R12: role does not forbid F01/feature specs in epic.md"
pass "R12 epic_md_brief_only"

# ── R13: re-validate after seeding + fail-stop ────────────────────────────────────
# R13_revalidate_fail_stop
grep -qF 'store/tasks.schema.json' "$ROLE"          || fail "R13: role does not name the schema for re-validation"
grep -qi 're-validate\|revalidate' "$ROLE"          || fail "R13: role does not state re-validation"
grep -qi 'not.*claim.*success\|must not claim a successful plan\|report the failure' "$ROLE" \
  || fail "R13: role does not state the fail-stop"
pass "R13 revalidate_fail_stop"

# ── R14: seeds-never-specs (no spec files, no EARS/plan, no Architect spawn) ───────
# R14_seeds_never_specs
for ext in '.spec' '.plan' '.tasks' '.tests'; do
  grep -qF "$ext" "$ROLE" || fail "R14: role does not name $ext as forbidden"
done
grep -qi 'never.*spec\|produce.*never spec\|never spec' "$ROLE" || fail "R14: role does not state never-spec"
grep -qi 'not.*spawn\|never.*spawn' "$ROLE"         || fail "R14: role does not forbid spawning the Architect"
pass "R14 seeds_never_specs"

# ── R15: never past draft; names F03 as the draft → planned step ──────────────────
# R15_never_past_draft
grep -qi 'every epic .*seed .*draft\|every epic you seed is .*draft' "$ROLE" \
  || fail "R15: role does not state every seeded epic is draft"
for st in 'planned' 'in-progress' 'in-review' 'done'; do
  grep -qF "$st" "$ROLE" || fail "R15: role does not forbid advancing to '$st'"
done
grep -qi 'autonomous: true\|autonomous' "$ROLE"     || fail "R15: role does not forbid stamping autonomous: true"
grep -qi '/sdd-drill\|F03' "$ROLE"                  || fail "R15: role does not name F03/sdd-drill as the flip step"
grep -qi 'draft .* planned\|draft → planned\|draft -> planned' "$ROLE" \
  || fail "R15: role does not name the draft → planned transition"
pass "R15 never_past_draft"

# ── R16: reuse F01 draft state/gate — no new status, inert ────────────────────────
# R16_reuse_f01_gate
grep -qi 'next()\|draft gate\|`next()`' "$ROLE"     || fail "R16: role does not reference the next() draft gate"
grep -qi 'no new status' "$ROLE"                    || fail "R16: role does not state no new status"
grep -qi 'inert\|never select\|prevents.*select\|gate' "$ROLE" || fail "R16: role does not state seeded epics are inert/gated"
pass "R16 reuse_f01_gate"

# ── R17: existing vision/arch ⇒ default refuse + amend appends only ───────────────
# R17_rerun_behavior
grep -qi 'already exists\|already has a plan' "$ROLE" || fail "R17: role does not handle existing plan"
grep -qi 'STOP\|refuse' "$ROLE"                     || fail "R17: role does not STOP/refuse by default"
grep -qi '/sdd-drill\|amend' "$ROLE"                || fail "R17: role does not point at sdd-drill/amend"
tr '\n' ' ' < "$ROLE" | grep -qiE 'append[^.]{0,10}new epics' || fail "R17: role does not state amend appends new epics"
grep -qi 'without rewriting\|renumber' "$ROLE"      || fail "R17: role does not state no rewrite/renumber"
pass "R17 rerun_behavior"

# ── R18: vision.md complements product.md/glossary.md — role AND vision template ───
# R18_complements_product
tr '\n' ' ' < "$ROLE" | grep -qiE 'complements[^.]{0,60}product' || fail "R18: role does not state vision complements product/glossary"
grep -qF 'product.md' "$ROLE"                       || fail "R18: role does not reference product.md"
grep -qi 'not rewrite or delete\|not.*rewrite.*delete\|never rewrite\|does not rewrite' "$ROLE" \
  || fail "R18: role does not state it does not rewrite/delete product.md/glossary.md"
tr '\n' ' ' < "$VTPL" | grep -qiE 'complements[^.]{0,60}product' || fail "R18: vision template does not state it complements product/glossary"
grep -qF 'product.md' "$VTPL"                       || fail "R18: vision template does not reference product.md"
pass "R18 complements_product"

# ── R19: backward compatible — sdd-new/sdd-next/inception unchanged; init.sh exit 0
# R19_backward_compatible
[ -f ".claude/commands/sdd-new.md" ]  || fail "R19: sdd-new.md missing"
[ -f ".claude/commands/sdd-next.md" ] || fail "R19: sdd-next.md missing"
[ -f "agents/inception.md" ]          || fail "R19: agents/inception.md missing"
grep -qF 'agents/inception.md' ".claude/commands/sdd-new.md" \
  || fail "R19: sdd-new.md no longer points at agents/inception.md"
./init.sh >/dev/null 2>&1 || fail "R19: ./init.sh did not exit 0"
pass "R19 backward_compatible"

# ── R20: contract lives in the portable role file (not solely .claude/ glue) ──────
# R20_portable_contract — producer rules present in agents/planner.md itself.
tr '\n' ' ' < "$ROLE" | grep -qiE 'block[^.]{0,10}draft[^.]{0,10}epics' || fail "R20: producer rule 'block of draft epics' not in the portable role"
grep -qi 'features: \[\]\|empty' "$ROLE"            || fail "R20: producer rule 'features: []' not in the portable role"
grep -qi 'never.*spec\|produce.*never spec' "$ROLE" || fail "R20: producer rule 'seeds-never-specs' not in the portable role"
pass "R20 portable_contract"

# ── R21: WORKFLOW.md places /sdd-plan upstream of /sdd-drill + /sdd-next, producer ─
# R21_workflow_doc
grep -qF '/sdd-plan' docs/WORKFLOW.md               || fail "R21: WORKFLOW.md does not mention /sdd-plan"
tr '\n' ' ' < docs/WORKFLOW.md | grep -qiE 'roadmap[^.]{0,10}draft[^.]{0,10}epics' || fail "R21: WORKFLOW.md does not place the roadmap of draft epics"
grep -qi '/sdd-drill\|drill' docs/WORKFLOW.md       || fail "R21: WORKFLOW.md does not mention /sdd-drill"
tr '\n' ' ' < docs/WORKFLOW.md | grep -qiE 'producer that never specs' || fail "R21: WORKFLOW.md does not state the producer-that-never-specs rule"
grep -qi 'never.*feature spec\|no feature\|never specs' docs/WORKFLOW.md \
  || fail "R21: WORKFLOW.md does not state never feature specs"
grep -qi 'never advance.*past .*draft\|never advances an epic past\|past .draft.' docs/WORKFLOW.md \
  || fail "R21: WORKFLOW.md does not state never past draft"
# The WORKFLOW draft definition must stay coherent with planner.md's drillable-minimum
# contract (not the stale "brief only" wording) — a draft carries the drillable minimum.
grep -qi 'drillable-minimum\|drillable minimum' docs/WORKFLOW.md \
  || fail "R21: WORKFLOW.md draft definition drifted from planner.md drillable-minimum contract"
grep -qi 'business brief only\|brief only' docs/WORKFLOW.md \
  && fail "R21: WORKFLOW.md still uses stale 'brief only' draft definition (contradicts planner.md)"
pass "R21 workflow_doc"

# ── R22: README one-liner for /sdd-plan ───────────────────────────────────────────
# R22_readme_oneliner
grep -qF '/sdd-plan' README.md                      || fail "R22: README.md does not mention /sdd-plan"
pass "R22 readme_oneliner"

# ── R23: one MINOR bump recorded in CHANGELOG (no literal version frozen) ─────────
# R23_version_changelog
V="$(cat VERSION)"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "R23: VERSION '$V' not semver"
grep -qF "## [$V]" CHANGELOG.md                 || fail "R23: CHANGELOG.md has no '## [$V]' heading"
# The /sdd-plan marker must appear SOMEWHERE in the CHANGELOG — grepped across the WHOLE
# file, NOT coupled to the current-top `## [$V]` section. Coupling this to the top version
# is the permanent-suite anti-pattern (a later, unrelated MINOR bump that adds a new top
# section would otherwise break this suite — exactly what happened on the E06-F06 bump).
grep -qF '/sdd-plan' CHANGELOG.md || fail "R23: CHANGELOG.md has no /sdd-plan marker anywhere"
pass "R23 version_changelog"

echo "All sdd-plan tests passed."
