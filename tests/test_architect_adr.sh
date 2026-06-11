#!/bin/sh
# test_architect_adr.sh — static + fixture verification for E06-F04 (Architect ADR-
# citation contract: architecture.md mandatory-when-present input, every spec cites the
# ADRs it touches in a `## Architecture alignment` section; one additive Reviewer clause;
# a template section; three doc edits).
#
# This feature ships PROSE + a template section + docs (no application code), so
# verification is the house way (cf. test_sdd_plan.sh, test_sdd_drill.sh): file-existence +
# required-phrase greps over the portable contract, one temp-dir markdown fixture proving
# the `## Architecture alignment` shape is internally consistent, one temp JSON store
# fixture proving no schema change is needed, and one sandboxed ./init.sh exit-0 run.
# Zero deps: POSIX sh + grep + python3.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact VERSION
# literal (read it at runtime); never git-diff a DO-NOT-TOUCH file against main; never
# mutate the live state/tasks.json or any live spec (fixtures use temp files / dirs).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

ARCH="agents/architect.md"
REV="agents/reviewer.md"
TPL="specs/_templates/feature.spec.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: architecture.md + adr/* as a mandatory-when-present Architect input ───────
# R1_mandatory_input
[ -f "$ARCH" ]                                   || fail "R1: $ARCH missing"
grep -qF 'specs/architecture.md' "$ARCH"         || fail "R1: role does not name specs/architecture.md"
grep -qF 'specs/adr/' "$ARCH"                     || fail "R1: role does not name specs/adr/"
grep -qi 'mandatory\|required' "$ARCH"           || fail "R1: role does not state mandatory/required input"
grep -qi 'present\|when.*exist\|whenever' "$ARCH" || fail "R1: role does not gate on present/exist"
pass "R1 mandatory_input"

# ── R2: reuses the F03-D7 brief hook for the touched ADR ids ──────────────────────
# R2_brief_hook
grep -qi 'inbox brief\|brief' "$ARCH"            || fail "R2: role does not reference the inbox brief"
grep -qi 'ADR-\|ADR ids' "$ARCH"                 || fail "R2: role does not reference ADR ids"
grep -qi 'record\|touch\|F03' "$ARCH"            || fail "R2: role does not state the brief records touched ids"
pass "R2 brief_hook"

# ── R3: every spec cites touched ADR-NNNN in `## Architecture alignment` + how-honored
# R3_cite_section
grep -qF '## Architecture alignment' "$ARCH"     || fail "R3: role does not name the ## Architecture alignment section"
grep -qi 'ADR-NNNN\|ADR-' "$ARCH"                || fail "R3: role does not reference ADR-NNNN"
grep -qi 'touch' "$ARCH"                         || fail "R3: role does not state the feature touches ADRs"
grep -qi 'honor\|how' "$ARCH"                    || fail "R3: role does not require a 'how honored' line"
pass "R3 cite_section"

# ── R4: present-but-nothing-touched ⇒ explicit `ADRs touched: none` ───────────────
# R4_explicit_none
grep -qF 'ADRs touched: none' "$ARCH"            || fail "R4: role does not state the explicit 'ADRs touched: none'"
grep -qi 'explicit\|legitimate\|not.*silent' "$ARCH" || fail "R4: role does not frame 'none' as explicit/legitimate"
pass "R4 explicit_none"

# ── R5: divergence stated in-spec; never authors an ADR delta / invokes /sdd-drill ─
# R5_divergence
grep -qi 'diverg\|depart' "$ARCH"                || fail "R5: role does not address divergence"
grep -qi 'state.*divergence\|in.*section\|in.*spec' "$ARCH" || fail "R5: role does not state divergence in-spec"
grep -qi 'not.*ADR delta\|not.*author.*delta\|not.*sdd-drill\|F03' "$ARCH" \
  || fail "R5: role does not forbid authoring a delta / invoking /sdd-drill"
pass "R5 divergence"

# ── R6: feature.spec.md template gains the section + `none` fallback ──────────────
# R6_template_section
[ -f "$TPL" ]                                     || fail "R6: $TPL missing"
grep -qF '## Architecture alignment' "$TPL"      || fail "R6: template lacks the ## Architecture alignment section"
grep -qi 'ADR-NNNN\|ADR-' "$TPL"                 || fail "R6: template does not reference ADR-NNNN"
grep -qF 'ADRs touched: none' "$TPL"             || fail "R6: template does not document the 'none' fallback"
pass "R6 template_section"

# ── R7: legacy detection: present = exists AND non-empty/non-template ─────────────
# R7_present_detection
grep -qi 'present' "$ARCH"                       || fail "R7: role does not define 'present'"
grep -qi 'non-empty\|not empty\|real content' "$ARCH" || fail "R7: role does not require non-empty content"
grep -qi 'template\|stub' "$ARCH"                || fail "R7: role does not treat a template stub as absent"
pass "R7 present_detection"

# ── R8: absent ⇒ note + proceed, no fabricated citation, no failure, section optional
# R8_graceful_absent
grep -qi 'absent\|no.*architecture' "$ARCH"      || fail "R8: role does not address the absent case"
grep -qi 'proceed' "$ARCH"                       || fail "R8: role does not say proceed when absent"
grep -qi 'not.*fail\|no failure\|never.*fail' "$ARCH" || fail "R8: role does not state it never fails for lack of architecture"
grep -qi 'not.*fabricat\|no.*fabricat\|no.*invented' "$ARCH" || fail "R8: role does not forbid fabricating a citation"
pass "R8 graceful_absent"

# ── R9: pre-F04 specs without the section stay valid (no retro-fit) ───────────────
# R9_no_retrofit
grep -qi 'after\|written after' "$ARCH"          || fail "R9: role does not scope the rule to specs written after"
grep -qi 'existing\|pre-\|already' "$ARCH"       || fail "R9: role does not address existing/pre-existing specs"
grep -qi 'valid\|no retro-fit\|not.*retro' "$ARCH" || fail "R9: role does not state existing specs stay valid / no retro-fit"
pass "R9 no_retrofit"

# ── R10: umbrella shared specs cite ADRs too, orthogonal to the contract artifact ─
# R10_umbrella
grep -qi 'umbrella\|shared' "$ARCH"              || fail "R10: role does not address umbrella/shared specs"
grep -qi 'slice\|contract' "$ARCH"               || fail "R10: role does not relate to slices/contract artifact"
grep -qi 'ADR\|architecture alignment' "$ARCH"   || fail "R10: role does not apply the ADR rule to umbrella specs"
pass "R10 umbrella"

# ── R11: Reviewer clause fires only where architecture + sdd:true; confirms section ─
# R11_reviewer_fires
[ -f "$REV" ]                                     || fail "R11: $REV missing"
grep -qi 'Architecture alignment\|ADR' "$REV"    || fail "R11: reviewer does not reference the alignment/ADR check"
grep -qi 'specs/architecture.md\|architecture' "$REV" || fail "R11: reviewer clause does not gate on architecture presence"
grep -qi 'sdd: true\|four-file spec' "$REV"      || fail "R11: reviewer clause does not gate on sdd:true / four-file spec"
grep -qi 'ADR-\|ADRs touched: none\|cite' "$REV" || fail "R11: reviewer does not require cite ≥1 ADR or 'none'"
pass "R11 reviewer_fires"

# ── R12: missing section ⇒ soft flag not hard reject; carve-outs ──────────────────
# R12_reviewer_soft
grep -qi 'flag\|soft' "$REV"                     || fail "R12: reviewer does not use a soft flag"
grep -qi 'not.*hard reject\|not.*reject\|rather than blocking\|not a hard reject' "$REV" \
  || fail "R12: reviewer does not say 'not a hard reject'"
grep -qi 'does not fire\|legacy\|no.*architecture' "$REV" || fail "R12: reviewer does not carve out legacy/no-architecture"
grep -qi 'sdd: false\|brief-only' "$REV"         || fail "R12: reviewer does not carve out sdd:false brief-only items"
pass "R12 reviewer_soft"

# ── R13: docs/SPEC-FORMAT.md documents the section + cite-your-ADRs rule ──────────
# R13_spec_format_doc
grep -qF 'Architecture alignment' docs/SPEC-FORMAT.md || fail "R13: SPEC-FORMAT.md does not document the section"
grep -qF 'ADR' docs/SPEC-FORMAT.md               || fail "R13: SPEC-FORMAT.md does not mention ADRs"
grep -qi 'cite\|touch' docs/SPEC-FORMAT.md       || fail "R13: SPEC-FORMAT.md does not state cite/touch"
grep -qi 'ADRs touched: none\|none\|absent' docs/SPEC-FORMAT.md || fail "R13: SPEC-FORMAT.md does not document none/absent"
pass "R13 spec_format_doc"

# ── R14: docs/WORKFLOW.md adds a distinct ADR-citation section vs /sdd-plan + /sdd-drill
# R14_workflow_doc
grep -qi 'Architecture-aligned\|cites ADRs\|Architecture alignment' docs/WORKFLOW.md \
  || fail "R14: WORKFLOW.md does not add the architecture-aligned section"
grep -qF '/sdd-plan' docs/WORKFLOW.md            || fail "R14: WORKFLOW.md section does not place it vs /sdd-plan"
grep -qF '/sdd-drill' docs/WORKFLOW.md           || fail "R14: WORKFLOW.md section does not place it vs /sdd-drill"
grep -qF 'ADR' docs/WORKFLOW.md                  || fail "R14: WORKFLOW.md does not mention ADRs"
# Distinct from F05's fix-lane heading: our ADR-citation section has its own dedicated
# heading whose text is neither 'Lightweight fix lane' nor '/sdd-fix' (no section overlap).
grep -qF '## Architecture-aligned specs (the Architect cites ADRs)' docs/WORKFLOW.md \
  || fail "R14: WORKFLOW.md lacks the distinct '## Architecture-aligned specs' heading"
# The harness's own markdown headings (lines beginning with '#') must not name F05's
# fix-lane in the SAME heading line as our ADR-citation section — they are distinct
# sections. (Prose may reference /sdd-fix; only headings must stay disjoint.)
grep -E '^#' docs/WORKFLOW.md | grep -i 'Architecture-aligned' | grep -qi 'fix lane\|sdd-fix' \
  && fail "R14: the ADR-citation heading overlaps F05's fix-lane heading" || true
pass "R14 workflow_doc"

# ── R15: README.md carries a one-line "specs cite ADRs" note ──────────────────────
# R15_readme
grep -qF 'ADR' README.md                         || fail "R15: README.md does not mention ADRs"
grep -qi 'cite\|architecture decision\|touch' README.md || fail "R15: README.md does not state specs cite the ADRs they touch"
pass "R15 readme"

# ── R16: no schema change — a feature row with no citation field validates; init.sh exit 0
# R16_no_schema_change
# A TEMP store carrying the required root `project` field + an ordinary feature row (NO new
# citation field) validates against the live store/tasks.schema.json (jsonschema if present,
# else the structural fallback mirroring init.sh). NEVER mutates the live state/tasks.json.
TMPSTORE="$(mktemp)"
trap 'rm -f "$TMPSTORE"' EXIT
cat > "$TMPSTORE" <<'JSON'
{"project":"fixture","epics":[{"id":"E99","title":"Aligned epic","status":"planned","features":[{"id":"E99-F01","title":"Cited feature","status":"spec-ready","sdd":true,"autonomous":false,"depends_on":[],"spec_path":"specs/epics/E99-x/F01-y/"}]}]}
JSON
python3 - "$TMPSTORE" store/tasks.schema.json <<'PY' || fail "R16: ordinary (no-citation) feature row failed schema validation"
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
# Structural fallback (subset mirroring init.sh): required fields + status enums + id patterns.
errors = []
if "project" not in data: errors.append("root.project missing")
EPIC = {"draft","planned","pending","in-progress","done"}
FEAT = {"pending","spec-ready","in-progress","in-review","done"}
for ei, ep in enumerate(data.get("epics", [])):
    if not re.match(r"^E[0-9]+$", ep.get("id","")): errors.append("epic[%d].id" % ei)
    if ep.get("status") not in EPIC: errors.append("epic[%d].status" % ei)
    if not isinstance(ep.get("features"), list): errors.append("epic[%d].features not a list" % ei)
    for fi, ft in enumerate(ep.get("features", [])):
        if not re.match(r"^E[0-9]+-F[0-9]+$", ft.get("id","")): errors.append("epic[%d].feat[%d].id" % (ei,fi))
        if ft.get("status") not in FEAT: errors.append("epic[%d].feat[%d].status" % (ei,fi))
        if "autonomous" in ft and not isinstance(ft["autonomous"], bool):
            errors.append("epic[%d].feat[%d].autonomous not bool" % (ei,fi))
for e in errors: print("  "+e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
rm -f "$TMPSTORE"; trap - EXIT
./init.sh >/dev/null 2>&1 || fail "R16: ./init.sh did not exit 0"
pass "R16 no_schema_change"

# ── R17: producers/commands/templates unchanged; no-architecture repo behaves as today
# R17_backward_compatible
[ -f "agents/planner.md" ]                        || fail "R17: agents/planner.md missing"
[ -f "agents/driller.md" ]                        || fail "R17: agents/driller.md missing"
[ -f "agents/inception.md" ]                       || fail "R17: agents/inception.md missing"
[ -f ".claude/commands/sdd-new.md" ]              || fail "R17: sdd-new.md missing"
[ -f ".claude/commands/sdd-plan.md" ]             || fail "R17: sdd-plan.md missing"
[ -f ".claude/commands/sdd-drill.md" ]            || fail "R17: sdd-drill.md missing"
[ -f ".claude/commands/sdd-next.md" ]             || fail "R17: sdd-next.md missing"
[ -f "specs/_templates/architecture.md" ]         || fail "R17: specs/_templates/architecture.md missing"
[ -f "specs/_templates/adr.md" ]                  || fail "R17: specs/_templates/adr.md missing"
grep -qF 'agents/planner.md' ".claude/commands/sdd-plan.md"  || fail "R17: sdd-plan.md no longer points at agents/planner.md"
grep -qF 'agents/driller.md' ".claude/commands/sdd-drill.md" || fail "R17: sdd-drill.md no longer points at agents/driller.md"
./init.sh >/dev/null 2>&1                         || fail "R17: ./init.sh did not exit 0"
pass "R17 backward_compatible"

# ── R18: contract lives in the portable role files + template + docs, not solely glue
# R18_portable_contract — the citation rule is present in agents/architect.md AND the
# verification clause in agents/reviewer.md themselves (no assertion about .claude/ glue).
grep -qF '## Architecture alignment' "$ARCH"     || fail "R18: alignment rule not in the portable architect role"
grep -qF 'ADR' "$ARCH"                            || fail "R18: ADR rule not in the portable architect role"
grep -qi 'mandatory\|present' "$ARCH"            || fail "R18: mandatory/present rule not in the portable architect role"
grep -qi 'Architecture alignment\|ADR' "$REV"    || fail "R18: verification clause not in the portable reviewer role"
pass "R18 portable_contract"

# ── R19: one MINOR bump recorded in CHANGELOG (no literal version frozen) ──────────
# R19_version_changelog
V="$(cat VERSION)"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "R19: VERSION '$V' not semver"
grep -qF "## [$V]" CHANGELOG.md                  || fail "R19: CHANGELOG.md has no '## [$V]' heading"
awk -v ver="## [$V]" '
  index($0, ver)==1 {found=1; next}
  found && /^## \[/ {exit}
  found {print}
' CHANGELOG.md | grep -qi 'Architecture alignment\|ADR\|cite' \
  || fail "R19: CHANGELOG '## [$V]' section does not mention the ADR-citation contract"
pass "R19 version_changelog"

# ── Markdown fixture (R3/R4/R6): the `## Architecture alignment` shape is consistent ─
# Build a synthetic feature .spec.md in a TEMP dir carrying the section in BOTH documented
# forms; assert each is detectable by the same greps the contract/template prescribe.
# It never edits a live spec.
FIXDIR="$(mktemp -d)"
trap 'rm -rf "$FIXDIR"' EXIT
cat > "$FIXDIR/cited.spec.md" <<'MD'
## Architecture alignment
- ADR-0001 — Event-sourced store: this feature appends events, honoring the decision.
MD
cat > "$FIXDIR/none.spec.md" <<'MD'
## Architecture alignment
ADRs touched: none — this feature is presentation-only and constrains no recorded decision.
MD
grep -qF '## Architecture alignment' "$FIXDIR/cited.spec.md" || fail "fixture: cited form missing the section heading"
grep -qF 'ADR-0001' "$FIXDIR/cited.spec.md"                  || fail "fixture: cited form missing ADR-0001"
grep -qF '## Architecture alignment' "$FIXDIR/none.spec.md"  || fail "fixture: none form missing the section heading"
grep -qF 'ADRs touched: none' "$FIXDIR/none.spec.md"         || fail "fixture: none form missing 'ADRs touched: none'"
rm -rf "$FIXDIR"; trap - EXIT
pass "fixture architecture_alignment_shape"

echo "All architect-adr tests passed."
