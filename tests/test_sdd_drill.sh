#!/bin/sh
# test_sdd_drill.sh — static + fixture verification for E06-F03 (Driller role +
# /sdd-drill command + WORKFLOW/README doc edits).
# This feature ships PROSE + DOCS (a portable role file, a Claude slash-command
# wrapper, two doc edits), so verification is the house way (cf. test_sdd_plan.sh):
# file-existence + required-phrase greps over the portable contract, one python
# fixture proving the canonical decomposed shape (a pending feature inside a planned
# epic, stamped autonomous:true) validates against the live schema, and one sandboxed
# ./init.sh exit-0 run. Zero deps: POSIX sh + grep + python3.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact
# VERSION literal (read it at runtime); never git-diff a DO-NOT-TOUCH file against
# main; never mutate the live state/tasks.json (fixtures use temp files).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

ROLE="agents/driller.md"
CMD=".claude/commands/sdd-drill.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: portable Driller role file ───────────────────────────────────────────────
# R1_driller_role_exists
[ -f "$ROLE" ]                                || fail "R1: $ROLE missing"
grep -qi 'decompose'  "$ROLE"                 || fail "R1: role does not say it decomposes"
grep -qi 'draft'      "$ROLE"                 || fail "R1: role does not mention draft epic"
grep -qi 'feature'    "$ROLE"                 || fail "R1: role does not mention features"
grep -qi 'ADR\|adr'   "$ROLE"                 || fail "R1: role does not mention ADRs"
grep -qi 'AGENTS.md-compatible\|portable' "$ROLE" || fail "R1: role not stated as portable"
pass "R1 driller_role_exists"

# ── R2: /sdd-drill command points at the role + reads $ARGUMENTS ──────────────────
# R2_sdd_drill_command
[ -f "$CMD" ]                                 || fail "R2: $CMD missing"
grep -qF 'agents/driller.md' "$CMD"           || fail "R2: command does not point at agents/driller.md"
grep -qF '$ARGUMENTS' "$CMD"                  || fail "R2: command does not read \$ARGUMENTS"
pass "R2 sdd_drill_command"

# ── R3: ≤3 text-only option mockups, never images — in BOTH role and command ──────
# R3_text_only_options
grep -qi 'text.*only\|markdown / ASCII\|markdown/ASCII' "$ROLE" || fail "R3: role does not state text-only options"
grep -qi 'at most 3\|at most three\|≤ *3\|<= *3' "$ROLE"        || fail "R3: role does not cap options at 3"
grep -qi 'never generate images\|not generate images\|never images' "$ROLE" || fail "R3: role does not forbid images"
grep -qi 'text.*only\|markdown / ASCII\|markdown/ASCII' "$CMD"  || fail "R3: command does not state text-only options"
grep -qi 'at most 3\|at most three\|≤ *3\|<= *3' "$CMD"         || fail "R3: command does not cap options at 3"
pass "R3 text_only_options"

# ── R4: <epic-id> required; empty arg ⇒ STOP and ask — role AND command ───────────
# R4_epic_id_required
grep -qi '<epic-id>\|epic id\|epic-id' "$ROLE" || fail "R4: role does not name the epic-id arg"
grep -qi 'required'  "$ROLE"                  || fail "R4: role does not state epic-id required"
grep -qi 'empty\|ask' "$ROLE"                 || fail "R4: role does not handle empty arg"
grep -qF 'STOP' "$ROLE"                       || fail "R4: role does not STOP on empty arg"
grep -qi '<epic-id>\|epic id\|epic-id' "$CMD"  || fail "R4: command does not name the epic-id arg"
grep -qi 'required'  "$CMD"                    || fail "R4: command does not state epic-id required"
grep -qi 'empty\|ask' "$CMD"                   || fail "R4: command does not handle empty arg"
grep -qF 'STOP' "$CMD"                         || fail "R4: command does not STOP on empty arg"
pass "R4 epic_id_required"

# ── R5: missing/non-draft ⇒ default refuse; amend appends above max, no re-flip ───
# R5_precondition_guard
grep -qi 'not.*draft\|must be .*draft\|not-`draft`\|not `draft`' "$ROLE" || fail "R5: role does not require draft target"
grep -qi 'STOP\|refuse' "$ROLE"               || fail "R5: role does not STOP/refuse by default"
grep -qi 'amend'  "$ROLE"                     || fail "R5: role does not mention amend opt-in"
grep -qi 'append' "$ROLE"                     || fail "R5: role does not state amend appends"
grep -qi 'above\|max' "$ROLE"                 || fail "R5: role does not state append above max"
grep -qi 'without renumber\|not re-flip\|renumber\|re-flip' "$ROLE" || fail "R5: role does not forbid renumber/re-flip"
pass "R5 precondition_guard"

# ── R6: role reads the draft epic + vision/architecture/ADRs as input ─────────────
# R6_reads_inputs
grep -qF 'epic.md' "$ROLE"                    || fail "R6: role does not read epic.md"
grep -qF 'specs/vision.md' "$ROLE"            || fail "R6: role does not read specs/vision.md"
grep -qF 'specs/architecture.md' "$ROLE"      || fail "R6: role does not read specs/architecture.md"
grep -qi 'specs/adr/\|ADR' "$ROLE"            || fail "R6: role does not read the ADRs"
grep -qi 'input' "$ROLE"                      || fail "R6: role does not state these are inputs"
pass "R6 reads_inputs"

# ── R7: role seeds pending features, sdd, intra-epic ids/depends_on, no reuse + fixture
# R7_seed_features
grep -qi 'status: "pending"\|pending' "$ROLE" || fail "R7: role does not seed pending features"
grep -qi 'sdd' "$ROLE"                        || fail "R7: role does not state sdd"
grep -qF 'depends_on' "$ROLE"                 || fail "R7: role does not state depends_on"
grep -qF 'spec_path' "$ROLE"                  || fail "R7: role does not state spec_path"
grep -qi 'next-sequential\|above' "$ROLE"     || fail "R7: role does not state next-sequential/above"
grep -qi 'no reuse\|never reuse' "$ROLE"      || fail "R7: role does not state no-reuse"
# Fixture: a pending feature inside a planned epic, stamped autonomous:true, written
# to a TEMP store carrying the required root project field, validates against
# store/tasks.schema.json (jsonschema if present, else structural fallback that
# mirrors init.sh). NEVER mutates the live state/tasks.json.
TMPSTORE="$(mktemp)"
trap 'rm -f "$TMPSTORE"' EXIT
cat > "$TMPSTORE" <<'JSON'
{"project":"fixture","epics":[{"id":"E99","title":"Drilled epic","status":"planned","features":[{"id":"E99-F01","title":"Seeded feature","status":"pending","sdd":true,"autonomous":true,"depends_on":[],"spec_path":"specs/epics/E99-x/F01-y/"}]}]}
JSON
python3 - "$TMPSTORE" store/tasks.schema.json <<'PY' || fail "R7: decomposed pending-feature shape failed schema validation"
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
# id patterns. A pending feature inside a planned epic, stamped autonomous, is valid.
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
pass "R7 seed_features"

# ── R8: role fills the epic.md feature table with one row per seeded feature ──────
# R8_epic_table
grep -qF 'epic.md' "$ROLE"                    || fail "R8: role does not mention epic.md"
grep -qi 'feature table\|features table\|table' "$ROLE" || fail "R8: role does not mention the feature table"
grep -qi 'row\|one row per' "$ROLE"           || fail "R8: role does not state one row per feature"
pass "R8 epic_table"

# ── R9: role writes per-feature inbox brief recording touched ADR ids ─────────────
# R9_inbox_brief
grep -qF 'progress/inbox/' "$ROLE"            || fail "R9: role does not write to progress/inbox/"
grep -qF 'specs/_templates/inbox-brief.md' "$ROLE" || fail "R9: role does not cite the inbox-brief template"
grep -qi 'ADR-\|ADR ids\|touch' "$ROLE"       || fail "R9: role does not record touched ADR ids"
pass "R9 inbox_brief"

# ── R10: role re-validates after seeding and fail-stops on validation failure ─────
# R10_revalidate_fail_stop
grep -qF 'store/tasks.schema.json' "$ROLE"    || fail "R10: role does not name the schema for re-validation"
grep -qi 're-validate\|revalidate' "$ROLE"    || fail "R10: role does not state re-validation"
grep -qi 'not.*claim.*success\|do not claim a successful drill\|report the failure' "$ROLE" \
  || fail "R10: role does not state the fail-stop"
# Re-validation must also cover the approval-branch mutation (state flip + autonomous
# stamp), not only seeding — the final post-mutation validation gates the report.
grep -qi 'after the approval mutation\|after.*approval.*mutat\|post-mutation\|after.*state flip.*stamp\|after.*flip/stamp' "$ROLE" \
  || fail "R10: role does not require re-validation AFTER the approval/state-flip mutation"
pass "R10 revalidate_fail_stop"

# ── R11: role appends per-epic ADR deltas, above-max, 4-digit, no F02-ADR rewrite ─
# R11_adr_delta
grep -qF 'specs/adr/' "$ROLE"                 || fail "R11: role does not pin the ADR path"
grep -qi 'NNNN\|4-digit\|zero-pad' "$ROLE"    || fail "R11: role does not state 4-digit numbering"
grep -qi 'above\|max' "$ROLE"                 || fail "R11: role does not state above-max"
grep -qi 'no reuse\|never reuse' "$ROLE"      || fail "R11: role does not state no-reuse"
grep -qi 'delta' "$ROLE"                      || fail "R11: role does not mention deltas"
grep -qi 'not rewrite\|not renumber\|existing ADR' "$ROLE" || fail "R11: role does not forbid rewriting F02 ADRs"
pass "R11 adr_delta"

# ── R12: role scopes deltas to per-epic decisions; never feature-level design ─────
# R12_adr_boundary
grep -qi 'per-epic' "$ROLE"                   || fail "R12: role does not scope deltas to per-epic"
grep -qi 'delta' "$ROLE"                      || fail "R12: role does not mention deltas"
grep -qi 'feature-level' "$ROLE"              || fail "R12: role does not name feature-level design"
grep -qi 'Architect\|F04' "$ROLE"             || fail "R12: role does not name the Architect/F04 boundary"
pass "R12 adr_boundary"

# ── R13: approve branch — epic draft → planned + stamp every feature autonomous:true
# R13_approve_branch
grep -qi 'approve' "$ROLE"                    || fail "R13: role does not mention approve"
grep -qi 'draft .* planned\|draft → planned\|draft -> planned' "$ROLE" || fail "R13: role does not name draft → planned"
grep -qi 'autonomous: true' "$ROLE"           || fail "R13: role does not stamp autonomous: true"
grep -qi 'every\|all\|all-or-nothing' "$ROLE" || fail "R13: role does not state all-or-nothing stamping"
pass "R13 approve_branch"

# ── R14: keep-gated branch — epic planned, every feature stays autonomous:false ───
# R14_keep_gated_branch
grep -qi 'keep gated\|gated' "$ROLE"          || fail "R14: role does not mention keep gated"
grep -qi 'planned' "$ROLE"                    || fail "R14: role does not mention planned"
grep -qi 'autonomous: false' "$ROLE"          || fail "R14: role does not leave features autonomous: false"
grep -qi 'not leave\|never leave\|drilled' "$ROLE" || fail "R14: role does not forbid leaving a drilled epic in draft"
pass "R14 keep_gated_branch"

# ── R15: single epic-level gate via existing autonomous flag — no new status/mech ─
# R15_single_gate
grep -qi 'one\|single' "$ROLE"                || fail "R15: role does not state one/single decision"
grep -qi 'epic\|epic-level' "$ROLE"           || fail "R15: role does not state epic-level granularity"
grep -qi 'autonomous' "$ROLE"                 || fail "R15: role does not realize the gate via autonomous"
grep -qi 'no new status' "$ROLE"              || fail "R15: role does not state no new status"
grep -qi 'no new approval mechanism\|no schema change' "$ROLE" || fail "R15: role does not state no new mechanism/schema change"
pass "R15 single_gate"

# ── R16: role states F03 is the only path past draft; advances only the epic ──────
# R16_only_path
grep -qi 'only\|only path' "$ROLE"            || fail "R16: role does not state it is the only path"
grep -qi 'past .draft.\|out of .draft.\|out of `draft`\|past `draft`' "$ROLE" || fail "R16: role does not state past/out of draft"
grep -qi 'never past draft\|planner' "$ROLE"  || fail "R16: role does not cite the planner never-past-draft invariant"
grep -qi 'only the epic\|never a feature\|never another epic' "$ROLE" || fail "R16: role does not state it advances only the epic"
pass "R16 only_path"

# ── R17: role states decomposes-never-specs (no spec files, no EARS/plan, no spawn) ─
# R17_decompose_never_specs
for ext in '.spec' '.plan' '.tasks' '.tests'; do
  grep -qF "$ext" "$ROLE" || fail "R17: role does not name $ext as forbidden"
done
grep -qi 'never.*spec\|decompose.*never spec\|never spec' "$ROLE" || fail "R17: role does not state never-spec"
grep -qi 'not.*spawn\|never.*spawn' "$ROLE"   || fail "R17: role does not forbid spawning the Architect"
pass "R17 decompose_never_specs"

# ── R18: sdd-new/sdd-plan/sdd-next/Inception/Planner unchanged; untouched repo green
# R18_backward_compatible
[ -f ".claude/commands/sdd-new.md" ]  || fail "R18: sdd-new.md missing"
[ -f ".claude/commands/sdd-plan.md" ] || fail "R18: sdd-plan.md missing"
[ -f ".claude/commands/sdd-next.md" ] || fail "R18: sdd-next.md missing"
[ -f "agents/inception.md" ]          || fail "R18: agents/inception.md missing"
[ -f "agents/planner.md" ]            || fail "R18: agents/planner.md missing"
grep -qF 'agents/planner.md' ".claude/commands/sdd-plan.md" \
  || fail "R18: sdd-plan.md no longer points at agents/planner.md"
./init.sh >/dev/null 2>&1 || fail "R18: ./init.sh did not exit 0"
pass "R18 backward_compatible"

# ── R19: contract lives in the portable role file (not solely .claude/ glue) ──────
# R19_portable_contract — consumer rules present in agents/driller.md itself.
grep -qi 'decompose' "$ROLE"                  || fail "R19: consumer rule 'decompose' not in the portable role"
grep -qi 'draft .* planned\|draft → planned\|draft -> planned' "$ROLE" || fail "R19: 'draft → planned' not in the portable role"
grep -qi 'autonomous' "$ROLE"                 || fail "R19: 'autonomous' not in the portable role"
grep -qi 'never.*spec\|decompose.*never spec' "$ROLE" || fail "R19: 'decomposes-never-specs' not in the portable role"
pass "R19 portable_contract"

# ── R20: WORKFLOW.md places /sdd-drill between /sdd-plan + /sdd-next, only flip ────
# R20_workflow_doc
grep -qF '/sdd-drill' docs/WORKFLOW.md        || fail "R20: WORKFLOW.md does not mention /sdd-drill"
grep -qi 'draft' docs/WORKFLOW.md             || fail "R20: WORKFLOW.md does not mention draft"
grep -qi 'planned' docs/WORKFLOW.md           || fail "R20: WORKFLOW.md does not mention planned"
grep -qi 'autonomous' docs/WORKFLOW.md        || fail "R20: WORKFLOW.md does not mention autonomous"
grep -qF '/sdd-plan' docs/WORKFLOW.md         || fail "R20: WORKFLOW.md does not mention /sdd-plan"
grep -qF '/sdd-next' docs/WORKFLOW.md         || fail "R20: WORKFLOW.md does not mention /sdd-next"
grep -qi 'only step that flips\|only.*flip' docs/WORKFLOW.md || fail "R20: WORKFLOW.md does not state the only-flip step"
grep -qi 'feature spec\|no feature' docs/WORKFLOW.md || fail "R20: WORKFLOW.md does not state it never writes feature specs"
pass "R20 workflow_doc"

# ── R21: README one-liner for /sdd-drill ──────────────────────────────────────────
# R21_readme_oneliner
grep -qF '/sdd-drill' README.md               || fail "R21: README.md does not mention /sdd-drill"
pass "R21 readme_oneliner"

# ── R22: one MINOR bump recorded in CHANGELOG (no literal version frozen) ─────────
# R22_version_changelog
V="$(cat VERSION)"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "R22: VERSION '$V' not semver"
grep -qF "## [$V]" CHANGELOG.md                 || fail "R22: CHANGELOG.md has no '## [$V]' heading"
# The /sdd-drill marker must appear SOMEWHERE in the CHANGELOG — grepped across the WHOLE
# file, NOT coupled to the current-top `## [$V]` section. Coupling this to the top version
# is the permanent-suite anti-pattern (a later, unrelated MINOR bump that adds a new top
# section would otherwise break this suite).
grep -qF '/sdd-drill' CHANGELOG.md || fail "R22: CHANGELOG.md has no /sdd-drill marker anywhere"
pass "R22 version_changelog"

# ── E21-F01: feature-size budget carried by the Driller + Architect ───────────────
# The Driller is the ONLY role that decides feature size and nothing downstream revisits
# it, so the rule has to live in its prompt. Asserted as required phrases (the house way
# for a prose contract, cf. R1/R20 above), plus the two boundaries that make it safe:
# it must be advisory (never `blocked` on size) and it must leave the diff-measuring keys
# alone (those govern a measured diff, which does not exist at decomposition time).

# R4/R5/R6_driller_carries_size_budget
grep -qF 'change_size.max_requirements' "$ROLE" \
  || fail "E21-F01 R4: driller does not read change_size.max_requirements"
grep -qF 'depends_on' "$ROLE" \
  || fail "E21-F01 R4: driller does not sequence a split on the depends_on graph"
grep -qi 'epic.md' "$ROLE" \
  || fail "E21-F01 R5: driller does not record the size decision in epic.md"
grep -qi 'never blocks\|never.*`blocked`.*on size\|not.*emit a `blocked` record on size' "$ROLE" \
  || fail "E21-F01 R6: driller does not state the budget never produces a blocked record"
pass "E21-F01 R4/R5/R6 driller_carries_size_budget"

# R7/R8_architect_carries_size_budget
ARCH="agents/architect.md"
grep -qF 'change_size.max_requirements' "$ARCH" \
  || fail "E21-F01 R7: architect does not read change_size.max_requirements"
grep -qi 'stop before writing the four files' "$ARCH" \
  || fail "E21-F01 R7: architect does not stop before writing the four spec files when over budget"
grep -qi 'override line' "$ARCH" \
  || fail "E21-F01 R8: architect does not require a recorded override line when told to proceed"
pass "E21-F01 R7/R8 architect_carries_size_budget"

# R1/R2_change_size_defaults_in_source_config
# The DEFAULTS are documented in exactly one place — the config — and an absent block must
# behave as if they were written. Assert each key with its default value so a silent
# retune of a shipped default cannot pass unnoticed.
CFG="harness.config.yaml"
grep -Eq '^change_size:[[:space:]]*(#.*)?$' "$CFG" \
  || fail "E21-F01 R1: harness.config.yaml has no top-level change_size: block"
for _kv in 'advise_lines: 1500' 'escalate_lines: 3000' 'advise_files: 25' \
           'escalate_files: 50' 'max_requirements: 12'; do
  grep -qF "$_kv" "$CFG" || fail "E21-F01 R1/R2: change_size default missing or retuned: $_kv"
done
pass "E21-F01 R1/R2 change_size_defaults_in_source_config"

# R9_change_size_documented
# Both tiers named, and the non-blocking property stated — the property most likely to be
# lost when someone later "tightens" the rule.
grep -qF 'change_size' docs/WORKFLOW.md   || fail "E21-F01 R9: WORKFLOW.md does not document change_size"
grep -qi 'advise'   docs/WORKFLOW.md      || fail "E21-F01 R9: WORKFLOW.md does not name the advise tier"
grep -qi 'escalate' docs/WORKFLOW.md      || fail "E21-F01 R9: WORKFLOW.md does not name the escalate tier"
grep -qi 'Neither tier blocks\|neither blocks\|never a hard' docs/WORKFLOW.md \
  || fail "E21-F01 R9: WORKFLOW.md does not state that the budget never blocks"
pass "E21-F01 R9 change_size_documented"

echo "All sdd-drill tests passed."
