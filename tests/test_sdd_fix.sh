#!/bin/sh
# test_sdd_fix.sh — static + fixture verification for E06-F05 (Fixer role +
# /sdd-fix command + additive builder/reviewer sdd:false clauses + WORKFLOW/README
# doc edits).
# This feature ships PROSE + DOCS (a portable role file, a Claude slash-command
# wrapper, two additive role clauses, two doc edits), so verification is the house
# way (cf. test_sdd_drill.sh): file-existence + required-phrase greps over the portable
# contract, one python fixture proving the seeded fix shape (an sdd:false fix with
# autonomous:true inside a planned E99 maintenance epic) validates against the live
# schema, and one sandboxed ./init.sh exit-0 run. Zero deps: POSIX sh + grep + python3.
#
# Installer-generation assertions (R15/R16) live in tests/test_install.sh.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact
# VERSION literal (read it at runtime); never git-diff a DO-NOT-TOUCH file against
# main; never mutate the live state/tasks.json (fixtures use temp files).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

ROLE="agents/fixer.md"
CMD=".claude/commands/sdd-fix.md"
BUILDER="agents/builder.md"
REVIEWER="agents/reviewer.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: portable Fixer role file ─────────────────────────────────────────────────
# R1_fixer_role_exists
[ -f "$ROLE" ]                                || fail "R1: $ROLE missing"
grep -qi 'sdd: false\|sdd:false' "$ROLE"      || fail "R1: role does not name sdd:false intake"
grep -qi 'maintenance' "$ROLE"                || fail "R1: role does not mention the maintenance epic"
grep -qi 'brief' "$ROLE"                      || fail "R1: role does not mention brief-only intake"
grep -qi 'hand.*off\|loop' "$ROLE"            || fail "R1: role does not mention hand-off to the loop"
grep -qi 'AGENTS.md-compatible\|portable' "$ROLE" || fail "R1: role not stated as portable"
pass "R1 fixer_role_exists"

# ── R2: /sdd-fix command points at the role + reads $ARGUMENTS (STOP if empty) ────
# R2_sdd_fix_command
[ -f "$CMD" ]                                 || fail "R2: $CMD missing"
grep -qF 'agents/fixer.md' "$CMD"             || fail "R2: command does not point at agents/fixer.md"
grep -qF '$ARGUMENTS' "$CMD"                  || fail "R2: command does not read \$ARGUMENTS"
grep -qi 'empty\|ask\|STOP' "$CMD"            || fail "R2: command does not STOP/ask on empty arg"
pass "R2 sdd_fix_command"

# ── R3: ≤3 text-only options, never images — in BOTH role and command ─────────────
# R3_text_only_options
grep -qi 'text.*only\|markdown / ASCII\|markdown/ASCII' "$ROLE" || fail "R3: role does not state text-only options"
grep -qi 'at most 3\|at most three\|≤ *3\|<= *3' "$ROLE"        || fail "R3: role does not cap options at 3"
grep -qi 'never generate images\|not generate images\|never images' "$ROLE" || fail "R3: role does not forbid images"
grep -qi 'text.*only\|markdown / ASCII\|markdown/ASCII' "$CMD"  || fail "R3: command does not state text-only options"
grep -qi 'at most 3\|at most three\|≤ *3\|<= *3' "$CMD"         || fail "R3: command does not cap options at 3"
pass "R3 text_only_options"

# ── R4: role reuses existing sdd:false routing; no new routing/status/schema ──────
# R4_reuse_primitive
grep -qi 'sdd: false\|sdd:false' "$ROLE"      || fail "R4: role does not name sdd:false"
grep -qF 'Builder' "$ROLE"                    || fail "R4: role does not name the Builder"
grep -qF 'Reviewer' "$ROLE"                   || fail "R4: role does not name the Reviewer"
grep -qi 'reuse\|existing' "$ROLE"            || fail "R4: role does not say it reuses the existing primitive"
grep -qi 'no new' "$ROLE"                     || fail "R4: role does not state 'no new'"
grep -qi 'routing\|status\|schema' "$ROLE"    || fail "R4: role does not name routing/status/schema"
pass "R4 reuse_primitive"

# ── R5: role creates E99 on first use (planned, features: []) + epic.md ───────────
# R5_epic_create
grep -qF 'E99' "$ROLE"                        || fail "R5: role does not name E99"
grep -qi 'maintenance' "$ROLE"                || fail "R5: role does not name the maintenance slug"
grep -qi 'Maintenance (hotfixes\|title' "$ROLE" || fail "R5: role does not state the maintenance title"
grep -qi 'status: "planned"\|planned' "$ROLE" || fail "R5: role does not state planned status"
grep -qi 'features: \[\]\|empty' "$ROLE"      || fail "R5: role does not state empty features on create"
grep -qF 'epic.md' "$ROLE"                    || fail "R5: role does not create epic.md"
grep -qi 'if absent\|first use\|create' "$ROLE" || fail "R5: role does not state create-on-first-use"
pass "R5 epic_create"

# ── R6: role reuses the same epic by id E99 thereafter; no second bucket, no renumber
# R6_epic_reuse
grep -qF 'E99' "$ROLE"                        || fail "R6: role does not name E99"
grep -qi 'reuse' "$ROLE"                      || fail "R6: role does not state reuse"
grep -qi 'by id\|identify' "$ROLE"            || fail "R6: role does not state identify-by-id"
grep -qi 'not.*second\|never.*second\|one' "$ROLE" || fail "R6: role does not forbid a second bucket"
grep -qi 'not.*renumber\|never.*renumber\|append-only' "$ROLE" || fail "R6: role does not forbid renumbering"
pass "R6 epic_reuse"

# ── R7: maintenance epic is non-draft selectable (planned); never seed draft ──────
# R7_non_draft
grep -qi 'planned' "$ROLE"                    || fail "R7: role does not state planned"
grep -qi 'selectable\|next()' "$ROLE"         || fail "R7: role does not state selectable/next()"
grep -qi 'not.*draft\|never.*draft' "$ROLE"   || fail "R7: role does not forbid draft"
pass "R7 non_draft"

# ── R8: role appends fix sdd:false/pending/spec_path/next-F##-above-max, no reuse + fixture
# R8_fix_seed
grep -qi 'sdd: false\|sdd:false' "$ROLE"      || fail "R8: role does not seed sdd:false fix"
grep -qi 'status: "pending"\|pending' "$ROLE" || fail "R8: role does not seed pending"
grep -qF 'spec_path' "$ROLE"                  || fail "R8: role does not state spec_path"
grep -qi 'above\|max' "$ROLE"                 || fail "R8: role does not state above-max"
grep -qi 'F##\|next-sequential' "$ROLE"       || fail "R8: role does not state next-sequential F##"
grep -qi 'append-only\|no reuse' "$ROLE"      || fail "R8: role does not state append-only/no-reuse"
# Fixture: an sdd:false fix stamped autonomous:true inside a planned E99 maintenance
# epic, written to a TEMP store carrying the required root project field, validates
# against store/tasks.schema.json (jsonschema if present, else structural fallback that
# mirrors init.sh). NEVER mutates the live state/tasks.json.
TMPSTORE="$(mktemp)"
trap 'rm -f "$TMPSTORE"' EXIT
cat > "$TMPSTORE" <<'JSON'
{"project":"fixture","epics":[{"id":"E99","title":"Maintenance (hotfixes & minor fixes)","status":"planned","features":[{"id":"E99-F01","title":"Fix a typo","status":"pending","sdd":false,"autonomous":true,"depends_on":[],"spec_path":"specs/epics/E99-maintenance/F01-fix-a-typo/"}]}]}
JSON
python3 - "$TMPSTORE" store/tasks.schema.json <<'PY' || fail "R8: seeded sdd:false fix shape failed schema validation"
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
# id patterns. An sdd:false fix stamped autonomous inside a planned E99 epic is valid.
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
        if "sdd" in ft and not isinstance(ft["sdd"], bool):
            errors.append("epic[%d].feat[%d].sdd not bool" % (ei,fi))
        if "autonomous" in ft and not isinstance(ft["autonomous"], bool):
            errors.append("epic[%d].feat[%d].autonomous not bool" % (ei,fi))
for e in errors: print("  "+e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
rm -f "$TMPSTORE"; trap - EXIT
pass "R8 fix_seed"

# ── R9: role stamps autonomous:true default + --gated opt-out; existing flag, no new mech
# R9_autonomous_default
grep -qF 'autonomous: true' "$ROLE"           || fail "R9: role does not stamp autonomous: true"
grep -qi 'default' "$ROLE"                    || fail "R9: role does not state autonomous:true is the default"
grep -qi -- '--gated\|opt-out\|gated' "$ROLE" || fail "R9: role does not state the --gated opt-out"
grep -qF 'autonomous: false' "$ROLE"          || fail "R9: role does not state the autonomous: false opt-out"
grep -qi 'no new' "$ROLE"                     || fail "R9: role does not state 'no new'"
grep -qi 'approval mechanism\|mechanism' "$ROLE" || fail "R9: role does not state no new approval mechanism"
pass "R9 autonomous_default"

# ── R10: role writes one fix-oriented inbox brief; never a spec / spec_path dir / Architect
# R10_brief_only
grep -qF 'progress/inbox/' "$ROLE"            || fail "R10: role does not write to progress/inbox/"
grep -qF 'inbox-brief.md' "$ROLE"             || fail "R10: role does not cite the inbox-brief template"
for ext in '.spec' '.plan' '.tasks' '.tests'; do
  grep -qF "$ext" "$ROLE" || fail "R10: role does not name $ext as forbidden"
done
grep -qi 'spec_path.*director\|director.*spec_path\|not create.*director\|directory is not created' "$ROLE" \
  || fail "R10: role does not forbid creating the spec_path directory"
grep -qi 'not.*spawn\|never.*spawn' "$ROLE"   || fail "R10: role does not forbid spawning the Architect"
pass "R10 brief_only"

# ── R11: role re-validates after each write; fail-stop, never claim success on invalid
# R11_revalidate_fail_stop
grep -qF 'store/tasks.schema.json' "$ROLE"    || fail "R11: role does not name the schema for re-validation"
grep -qi 're-validate\|revalidate' "$ROLE"    || fail "R11: role does not state re-validation"
grep -qi 'not.*claim.*success\|do not claim a successful seed\|report the failure' "$ROLE" \
  || fail "R11: role does not state the fail-stop"
pass "R11 revalidate_fail_stop"

# ── R12: builder additive sdd:false clause; sdd:true path intact ──────────────────
# R12_builder_from_brief
grep -qi 'sdd: false\|sdd:false' "$BUILDER"   || fail "R12: builder does not mention sdd:false"
grep -qi 'progress/inbox/\|inbox brief' "$BUILDER" || fail "R12: builder does not reference the inbox brief"
grep -qi 'test' "$BUILDER"                    || fail "R12: builder does not require a test for the fix"
# sdd:true path still present (Loop A precondition + tasks.md worklist unchanged)
grep -qi 'Loop A' "$BUILDER"                  || fail "R12: builder sdd:true Loop A precondition removed"
grep -qF 'tasks.md' "$BUILDER"                || fail "R12: builder sdd:true tasks.md worklist removed"
pass "R12 builder_from_brief"

# ── R13: reviewer additive sdd:false clause; sdd:true traceability check intact ───
# R13_reviewer_behavioural
grep -qi 'sdd: false\|sdd:false' "$REVIEWER"  || fail "R13: reviewer does not mention sdd:false"
grep -qi 'behaviour\|behavioral\|behavioural' "$REVIEWER" || fail "R13: reviewer does not state behavioural verification"
grep -qi 'traceability' "$REVIEWER"           || fail "R13: reviewer does not mention traceability"
grep -qi 'not apply\|no R-id\|without R-id' "$REVIEWER" || fail "R13: reviewer does not state traceability N/A for no-R-id items"
# sdd:true traceability check (#2, R-id → test) still present
grep -qi 'R-id' "$REVIEWER"                   || fail "R13: reviewer sdd:true R-id traceability check removed"
grep -qi 'Traceability' "$REVIEWER"           || fail "R13: reviewer sdd:true traceability check #2 removed"
pass "R13 reviewer_behavioural"

# ── R14: role + command hand off to the existing loop in-session; Fixer writes no code
# R14_handoff
grep -qi 'hand.*off\|loop\|Builder' "$ROLE"   || fail "R14: role does not state hand-off to the loop"
grep -qi 'in-session\|session' "$ROLE"        || fail "R14: role does not state in-session hand-off"
grep -qi 'no production code\|writes no code\|write.*no production code' "$ROLE" || fail "R14: role does not state it writes no production code"
grep -qi 'reuse' "$ROLE"                      || fail "R14: role does not state the routing is reused"
grep -qi 'not.*re-implement\|do not re-implement\|reuse.*not.*re-implement' "$ROLE" || fail "R14: role does not state routing is not re-implemented"
grep -qi 'hand.*off\|loop\|Builder' "$CMD"    || fail "R14: command does not state hand-off to the loop"
grep -qi 'in-session\|session' "$CMD"         || fail "R14: command does not state in-session hand-off"
pass "R14 handoff"

# ── R17: sdd-new/sdd-plan/sdd-drill/sdd-next + sdd:true path unchanged; no maint epic
# R17_backward_compatible
[ -f ".claude/commands/sdd-new.md" ]   || fail "R17: sdd-new.md missing"
[ -f ".claude/commands/sdd-plan.md" ]  || fail "R17: sdd-plan.md missing"
[ -f ".claude/commands/sdd-drill.md" ] || fail "R17: sdd-drill.md missing"
[ -f ".claude/commands/sdd-next.md" ]  || fail "R17: sdd-next.md missing"
[ -f "agents/inception.md" ]           || fail "R17: agents/inception.md missing"
[ -f "agents/planner.md" ]             || fail "R17: agents/planner.md missing"
[ -f "agents/driller.md" ]             || fail "R17: agents/driller.md missing"
grep -qF 'agents/driller.md'   ".claude/commands/sdd-drill.md" || fail "R17: sdd-drill no longer points at agents/driller.md"
grep -qF 'agents/planner.md'   ".claude/commands/sdd-plan.md"  || fail "R17: sdd-plan no longer points at agents/planner.md"
grep -qF 'agents/inception.md' ".claude/commands/sdd-new.md"   || fail "R17: sdd-new no longer points at agents/inception.md"
# A freshly-installed store carries NO E99 maintenance epic (lazy-create only; the
# Fixer role creates E99 on first use — it is never pre-seeded by the installer
# template). Assert this against the installer's SEEDED store in a throwaway target,
# NOT the live state/tasks.json: this repo dogfoods its own /sdd-fix lane, so the
# live store legitimately carries E99 while a maintenance fix is in flight (the
# permanent-suite anti-pattern: never couple a permanent test to mutable live state).
TFIX="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
sh "$ROOT/harness-install.sh" --agents=claude "$TFIX" >/dev/null 2>&1 || fail "R17: seed install failed"
python3 - "$TFIX/.harness/state/tasks.json" <<'PY' || fail "R17: freshly-seeded tasks.json unexpectedly carries a pre-seeded E99 maintenance epic"
import json, sys
data = json.load(open(sys.argv[1]))
sys.exit(1 if any(ep.get("id") == "E99" for ep in data.get("epics", [])) else 0)
PY
rm -rf "$TFIX"
./init.sh >/dev/null 2>&1 || fail "R17: ./init.sh did not exit 0"
pass "R17 backward_compatible"

# ── R18: contract lives in the portable role file (not solely .claude/ glue) ──────
# R18_portable_contract — lane rules present in agents/fixer.md itself.
grep -qi 'sdd: false\|sdd:false' "$ROLE"      || fail "R18: 'sdd:false seed' rule not in the portable role"
grep -qF 'E99' "$ROLE"                        || fail "R18: reserved E99 maintenance epic not in the portable role"
grep -qF 'autonomous: true' "$ROLE"           || fail "R18: 'autonomous default' not in the portable role"
grep -qi 'never a spec\|brief-only\|never.*spec' "$ROLE" || fail "R18: 'brief-only-never-spec' not in the portable role"
grep -qi 'hand.*off\|loop' "$ROLE"            || fail "R18: 'hand off to the loop' not in the portable role"
pass "R18 portable_contract"

# ── R19: WORKFLOW.md documents the lightweight lane; adds no new status/routing ───
# R19_workflow_doc
grep -qF '/sdd-fix' docs/WORKFLOW.md          || fail "R19: WORKFLOW.md does not mention /sdd-fix"
grep -qi 'sdd: false\|sdd:false' docs/WORKFLOW.md || fail "R19: WORKFLOW.md does not mention sdd:false"
grep -qi 'maintenance' docs/WORKFLOW.md       || fail "R19: WORKFLOW.md does not mention the maintenance epic"
grep -qi 'inbox brief\|brief' docs/WORKFLOW.md || fail "R19: WORKFLOW.md does not mention the inbox brief"
grep -qF 'Builder' docs/WORKFLOW.md           || fail "R19: WORKFLOW.md does not mention the Builder"
grep -qF 'Reviewer' docs/WORKFLOW.md          || fail "R19: WORKFLOW.md does not mention the Reviewer"
grep -qi 'no 4-file spec\|no spec' docs/WORKFLOW.md || fail "R19: WORKFLOW.md does not state no 4-file spec"
grep -qi 'no new' docs/WORKFLOW.md            || fail "R19: WORKFLOW.md does not state 'no new'"
grep -qi 'status\|routing' docs/WORKFLOW.md   || fail "R19: WORKFLOW.md does not name status/routing"
pass "R19 workflow_doc"

# ── R20: README one-liner for /sdd-fix ────────────────────────────────────────────
# R20_readme_oneliner
grep -qF '/sdd-fix' README.md                 || fail "R20: README.md does not mention /sdd-fix"
pass "R20 readme_oneliner"

# ── R21: one MINOR bump recorded in CHANGELOG (no literal version frozen) ─────────
# R21_version_changelog
V="$(cat VERSION)"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "R21: VERSION '$V' not semver"
grep -qF "## [$V]" CHANGELOG.md                 || fail "R21: CHANGELOG.md has no '## [$V]' heading"
# /sdd-fix is recorded in the changelog under its own version section. Do NOT couple
# this to the current top VERSION — a later feature (e.g. F04) bumps VERSION past it,
# moving /sdd-fix out of the `## [$V]` section. Assert it is recorded somewhere.
grep -qF '/sdd-fix' CHANGELOG.md || fail "R21: CHANGELOG.md does not record /sdd-fix"
pass "R21 version_changelog"

# ── R22: sdd:false routing split by autonomous — in-progress→Builder vs gated park ─
# R22_routing_autonomous_split — the Orchestrator table must distinguish a
# pending+sdd:false+autonomous:true fix (set in-progress, then Builder) from an
# autonomous:false (--gated) fix (PAUSE/parked at the human gate). A single
# undistinguished "Spawn Builder directly" row would FAIL these.
ORCH="agents/orchestrator.md"
[ -f "$ORCH" ]                                || fail "R22: $ORCH missing"
# the table no longer routes EVERY pending+sdd:false straight to the Builder: it must
# now name autonomous in the sdd:false rows (non-tautological — fails if the split is absent)
grep -Eqi 'sdd: ?false.*autonomous: ?true|autonomous: ?true.*sdd: ?false' "$ORCH" \
  || fail "R22: orchestrator does not split sdd:false by autonomous:true"
grep -Eqi 'sdd: ?false.*autonomous: ?false|autonomous: ?false.*sdd: ?false' "$ORCH" \
  || fail "R22: orchestrator does not split sdd:false by autonomous:false"
# autonomous:true lane SETS in-progress before the Builder (satisfies Loop A precondition)
grep -qi 'in-progress' "$ORCH"                || fail "R22: orchestrator sdd:false route does not set in-progress"
# autonomous:false (--gated) lane PAUSES / parks at the human gate
grep -qi 'PAUSE\|park' "$ORCH"                || fail "R22: orchestrator does not PAUSE/park the gated sdd:false fix"
grep -qi 'gated\|--gated' "$ORCH"             || fail "R22: orchestrator does not name the gated opt-out"
# store/local.md actionability: gated sdd:false fix is NOT actionable; autonomous:true is
grep -qi 'sdd: false\|sdd:false' store/local.md || fail "R22: store/local.md does not mention sdd:false actionability"
grep -qi 'not.*actionable\|parked' store/local.md || fail "R22: store/local.md does not state the gated fix is not actionable"
pass "R22 routing_autonomous_split"

# ── R23: Builder sdd:false clause no longer contradicts the Loop A in-progress precondition
# R23_builder_precondition_coherent — the sdd:false clause must say the precondition is
# SATISFIED by the routing (Orchestrator sets in-progress first), not waived. The old
# "Orchestrator routes pending+sdd:false straight to you / everything else unchanged"
# wording (with a step-1 in-progress STOP) was the contradiction; assert the fix.
grep -qi 'in-progress' "$BUILDER"             || fail "R23: builder sdd:false clause does not mention the in-progress precondition"
grep -Eqi 'precondition.*(hold|satisf)|(hold|satisf).*precondition' "$BUILDER" \
  || fail "R23: builder sdd:false clause does not state the precondition holds/is satisfied by routing"
# it must NOT claim the Orchestrator routes pending+sdd:false STRAIGHT to the Builder
# (the contradiction with the in-progress precondition) — gated fixes park first.
grep -qi 'pending + sdd: *false.* straight to you\|sdd: false.* straight to you' "$BUILDER" \
  && fail "R23: builder still claims pending+sdd:false routes straight to the Builder (contradiction)"
pass "R23 builder_precondition_coherent"

# ── R24: Fixer documents --gated as PARKING at the human gate (not handed to Builder) ─
# R24_gated_parks — the role must describe a --gated/autonomous:false fix as parking at
# the human gate and NOT being handed straight to the Builder. Non-tautological: fails if
# the role still implies a gated fix runs immediately.
grep -qi -- '--gated\|gated' "$ROLE"          || fail "R24: role does not mention --gated"
grep -qi 'park' "$ROLE"                       || fail "R24: role does not state a gated fix parks at the human gate"
grep -qi 'human gate\|human must approve\|human must' "$ROLE" || fail "R24: role does not state a human must approve the gated fix"
# the gated fix must NOT be handed straight to the Builder — the role must say so
grep -qi 'not.*handed straight\|not.*straight to the Builder\|does not.*auto-run\|not auto-run' "$ROLE" \
  || fail "R24: role does not state the gated fix is not handed straight to the Builder"
pass "R24 gated_parks"

echo "All sdd-fix tests passed."
