#!/bin/sh
# test_drift_check.sh — static + fixture verification for E06-F06 (Drift check on
# epic rollup: epic-done rollup formalization + Scout drift-check mode + Orchestrator
# planned/pending → draft demotion).
#
# This feature ships PROSE + DOCS (edits to two portable role files, the store
# contract, one workflow doc) plus one test suite, so verification is the house way
# (cf. test_sdd_drill.sh, test_architect_adr.sh): required-phrase greps over the
# portable contract, one python fixture proving the F06 state shapes (a `done` epic
# whose features are all `done`; a `draft` post-demotion epic) validate against the
# live store/tasks.schema.json with NO schema change, and one sandboxed ./init.sh
# exit-0 run. Zero deps: POSIX sh + grep + python3.
#
# Suite-wide constraints (permanent-suite anti-pattern, recurred 4×): never assert the
# exact VERSION literal (read it at runtime); never couple the feature's CHANGELOG
# mention to the current-top version (grep the marker across the WHOLE CHANGELOG); never
# git-diff a DO-NOT-TOUCH file against main; never mutate the live state/tasks.json
# (fixtures use a temp file carrying the required root `project` field).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

ORCH="agents/orchestrator.md"
SCOUT="agents/scout.md"
STORE="store/local.md"
WORKFLOW="docs/WORKFLOW.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: store/local.md formalizes the epic-done rollup (no new status/schema) ─────
# R1_epic_done_rollup_doc
grep -qi 'epic' "$STORE"                                   || fail "R1: store does not mention epic"
grep -qi 'all features\|every feature'  "$STORE"          || fail "R1: store does not state all/every feature"
grep -qi 'derive\|derived' "$STORE"                       || fail "R1: store does not state derive"
grep -qi 'persist\|persisted' "$STORE"                    || fail "R1: store does not state persist"
grep -qi 're-validate\|revalidate' "$STORE"               || fail "R1: store does not state re-validate"
grep -qi 'no new status\|no schema change' "$STORE"       || fail "R1: store does not state no new status/no schema change"
pass "R1 epic_done_rollup_doc"

# ── R2: orchestrator derives+persists epic done, re-validates, then drift before next
# R2_orch_rollup_then_drift
grep -qi 'all.*feature.*done\|every.*feature.*done' "$ORCH" || fail "R2: orch does not state all/every feature done"
grep -qF 'set_status' "$ORCH"                             || fail "R2: orch does not name set_status"
grep -qi 're-validate\|revalidate' "$ORCH"                || fail "R2: orch does not state re-validate"
grep -qi 'drift' "$ORCH"                                  || fail "R2: orch does not mention drift"
grep -qi 'before' "$ORCH"                                 || fail "R2: orch does not state before selecting next"
grep -qi 'next' "$ORCH"                                   || fail "R2: orch does not mention next"
pass "R2 orch_rollup_then_drift"

# ── R3: drift fires only on epic rollup to done; spawns read-only Scout drift mode ─
# R3_drift_trigger
grep -qi 'drift' "$ORCH"                                  || fail "R3: orch does not mention drift"
grep -qi 'only' "$ORCH"                                   || fail "R3: orch does not state only"
grep -qi 'roll\|rollup' "$ORCH"                           || fail "R3: orch does not mention rollup"
grep -qi 'done' "$ORCH"                                   || fail "R3: orch does not mention done"
grep -qi 'Scout' "$ORCH"                                  || fail "R3: orch does not mention Scout"
grep -qi 'read-only' "$ORCH"                              || fail "R3: orch does not state read-only Scout"
grep -qi 'draft\|planned\|pending' "$ORCH"                || fail "R3: orch does not name the re-validated set"
pass "R3 drift_trigger"

# ── R4: Scout drift-check mode: inputs + findings path + per-epic verdict + reason ─
# R4_scout_findings_shape
grep -qi 'drift' "$SCOUT"                                 || fail "R4: scout does not mention drift"
grep -qF 'progress/' "$SCOUT"                             || fail "R4: scout does not write to progress/"
grep -qF 'scout-drift' "$SCOUT"                           || fail "R4: scout does not name scout-drift findings file"
grep -qi 'per\|each' "$SCOUT"                             || fail "R4: scout does not state per/each epic"
grep -qi 'still-valid\|valid' "$SCOUT"                    || fail "R4: scout does not state still-valid"
grep -qi 'stale' "$SCOUT"                                 || fail "R4: scout does not state stale"
grep -qi 'reason\|why' "$SCOUT"                           || fail "R4: scout does not state reason/why"
grep -qi 'artifact' "$SCOUT"                              || fail "R4: scout does not state artifact"
pass "R4 scout_findings_shape"

# ── R5: Scout defines concrete S1/S2/S3 signals; stale only when ≥1 fires ─────────
# R5_concrete_signals
grep -qi 'contradict' "$SCOUT"                            || fail "R5: scout does not define S1 contradiction"
grep -qi 'removed\|renamed' "$SCOUT"                      || fail "R5: scout does not define S2 removed/renamed"
grep -qi 'supersedes\|obsoletes' "$SCOUT"                 || fail "R5: scout does not define S3 supersedes/obsoletes"
grep -qi 'at least one\|≥ *1\|one of\|only when' "$SCOUT"  || fail "R5: scout does not state the stale gate (≥1 fires)"
pass "R5 concrete_signals"

# ── R6: Scout read-only preserved: writes only progress/, never state/tasks.json ──
# R6_scout_read_only
grep -qi 'read-only' "$SCOUT"                             || fail "R6: scout does not state read-only"
grep -qF 'progress/' "$SCOUT"                             || fail "R6: scout does not write only to progress/"
grep -qi 'never\|not' "$SCOUT"                            || fail "R6: scout does not state never/not"
grep -qi 'state/tasks.json\|set_status\|state change' "$SCOUT" || fail "R6: scout does not name the forbidden state write"
pass "R6 scout_read_only"

# ── R7: orchestrator demotes stale planned/pending → draft + re-validates ─────────
# R7_demote_to_draft  (static + fixture)
grep -qi 'demote\|demotion' "$ORCH"                       || fail "R7: orch does not state demote"
grep -qi 'planned' "$ORCH"                                || fail "R7: orch does not mention planned"
grep -qi 'draft' "$ORCH"                                  || fail "R7: orch does not mention draft"
grep -qi 'pending' "$ORCH"                                || fail "R7: orch does not mention pending"
grep -qF 'set_status' "$ORCH"                             || fail "R7: orch does not name set_status"
grep -qi 're-validate\|revalidate' "$ORCH"                || fail "R7: orch does not state re-validate"
# Fixture (R7 + R16): a TEMP store carrying the required root `project` field, holding
# (a) a `done` epic whose every feature is `done` (the epic-done rollup target) and
# (b) a `draft` epic with one pending feature (the post-demotion shape), validates
# against store/tasks.schema.json (jsonschema if present, else the structural fallback
# that mirrors init.sh). NEVER mutates the live state/tasks.json.
TMPSTORE="$(mktemp)"
trap 'rm -f "$TMPSTORE"' EXIT
cat > "$TMPSTORE" <<'JSON'
{"project":"fixture","epics":[
 {"id":"E98","title":"Completed epic","status":"done",
  "features":[{"id":"E98-F01","title":"Done feature","status":"done","sdd":true,
   "depends_on":[],"spec_path":"specs/epics/E98-x/F01-y/"}]},
 {"id":"E99","title":"Demoted epic","status":"draft",
  "features":[{"id":"E99-F01","title":"Re-gated feature","status":"pending","sdd":true,
   "depends_on":[],"spec_path":"specs/epics/E99-x/F01-y/"}]}]}
JSON
python3 - "$TMPSTORE" store/tasks.schema.json <<'PY' || fail "R7/R16: F06 state shapes failed schema validation"
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
# Structural fallback (subset mirroring init.sh): required fields + status enums + ids.
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
for e in errors: print("  "+e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY
rm -f "$TMPSTORE"; trap - EXIT
pass "R7 demote_to_draft"

# ── R8: Scout never writes state/tasks.json; Orchestrator alone applies demotion ──
# R8_scout_flags_orch_acts
grep -qi 'Scout' "$ORCH"                                  || fail "R8: orch does not mention Scout"
grep -qi 'never\|not' "$ORCH"                             || fail "R8: orch does not state never/not"
grep -qi 'state/tasks.json\|write' "$ORCH"                || fail "R8: orch does not name the Scout's forbidden write"
grep -qi 'Orchestrator\|set_status' "$ORCH"               || fail "R8: orch does not name the actor"
grep -qi 'demote\|apply' "$ORCH"                          || fail "R8: orch does not state the Orchestrator acts"
pass "R8 scout_flags_orch_acts"

# ── R9: considers planned/pending/draft; in-progress/done never demoted (orch+store)
# R9_status_scope
for f in "$ORCH" "$STORE"; do
  grep -qi 'planned' "$f"      || fail "R9: $f does not mention planned"
  grep -qi 'pending' "$f"      || fail "R9: $f does not mention pending"
  grep -qi 'draft'   "$f"      || fail "R9: $f does not mention draft"
  grep -qi 'never\|not' "$f"   || fail "R9: $f does not state never/not"
  grep -qi 'in-progress\|done' "$f" || fail "R9: $f does not exclude in-progress/done"
done
pass "R9 status_scope"

# ── R10: backward-only invariant; re-drill stays manual /sdd-drill ────────────────
# R10_backward_only
grep -qi 'backward' "$ORCH"                               || fail "R10: orch does not state backward"
grep -qi 'never\|not' "$ORCH"                             || fail "R10: orch does not state never/not"
grep -qi 'forward\|advance' "$ORCH"                       || fail "R10: orch does not state forward/advance"
grep -qi 'in-progress\|done' "$ORCH"                      || fail "R10: orch does not exclude in-progress/done"
grep -qF '/sdd-drill' "$ORCH"                             || fail "R10: orch does not name /sdd-drill"
grep -qi 'manual' "$ORCH"                                 || fail "R10: orch does not state re-drill is manual"
pass "R10 backward_only"

# ── R11: reports re-drill pointer + optional flag-only epic.md note, never rewrite ─
# R11_redrill_pointer_flag
grep -qF '/sdd-drill' "$ORCH"                             || fail "R11: orch does not name /sdd-drill pointer"
grep -qi 'demoted on drift' "$ORCH"                       || fail "R11: orch does not name the 'demoted on drift' flag"
grep -qi 'flag' "$ORCH"                                   || fail "R11: orch does not state flag-only"
grep -qi 'not\|never' "$ORCH"                             || fail "R11: orch does not state never"
grep -qi 'rewrite\|content' "$ORCH"                       || fail "R11: orch does not forbid content rewrite"
pass "R11 redrill_pointer_flag"

# ── R12: no remaining draft/planned/pending epics ⇒ "nothing to re-validate" no-op ─
# R12_noop_no_epics
for f in "$ORCH" "$SCOUT"; do
  grep -qi 'nothing to re-validate' "$f" || fail "R12: $f does not emit 'nothing to re-validate'"
  grep -qi 'no\|none\|empty' "$f"        || fail "R12: $f does not state no/none/empty"
  grep -qi 'remaining\|draft\|planned' "$f" || fail "R12: $f does not name remaining planning-state epics"
done
pass "R12 noop_no_epics"

# ── R13: no architecture/ADRs ⇒ "nothing to re-validate" no-op ─────────────────────
# R13_noop_no_arch
grep -qi 'nothing to re-validate' "$SCOUT" || fail "R13: scout does not emit 'nothing to re-validate'"
grep -qi 'no architecture\|specs/architecture.md\|absent' "$SCOUT" || fail "R13: scout does not state the no-architecture reason"
pass "R13 noop_no_arch"

# ── R14: store documents both the epic-done rollup and the drift check ────────────
# R14_store_doc
grep -qi 'drift' "$STORE"                                 || fail "R14: store does not mention drift"
grep -qi 'demote\|demotion' "$STORE"                      || fail "R14: store does not state demote"
grep -qi 'Scout' "$STORE"                                 || fail "R14: store does not mention Scout"
grep -qi 'planned' "$STORE"                               || fail "R14: store does not mention planned"
grep -qi 'draft' "$STORE"                                 || fail "R14: store does not mention draft"
grep -qi 're-validate\|re-check\|re-validates' "$STORE"   || fail "R14: store does not state re-validate remaining epics"
pass "R14 store_doc"

# ── R15: WORKFLOW.md adds a distinct drift-check section ───────────────────────────
# R15_workflow_doc
grep -qi 'drift' "$WORKFLOW"                              || fail "R15: WORKFLOW does not mention drift"
grep -qi 'Scout' "$WORKFLOW"                              || fail "R15: WORKFLOW does not mention Scout"
grep -qi 'demote\|demotion\|demoted' "$WORKFLOW"          || fail "R15: WORKFLOW does not state demote"
grep -qi 'draft' "$WORKFLOW"                              || fail "R15: WORKFLOW does not mention draft"
grep -qF '/sdd-drill' "$WORKFLOW"                         || fail "R15: WORKFLOW does not name /sdd-drill"
grep -qi 'backward' "$WORKFLOW"                           || fail "R15: WORKFLOW does not state backward"
pass "R15 workflow_doc"

# ── R16: schema unchanged; admits draft/planned/pending/done; ./init.sh exits 0 ───
# R16_no_schema_change  (fixture proved above; assert enum unchanged + init.sh)
python3 - store/tasks.schema.json <<'PY' || fail "R16: epic-status enum changed from the F01 set"
import json, sys
schema = json.load(open(sys.argv[1]))
enum = schema["properties"]["epics"]["items"]["properties"]["status"]["enum"]
expected = {"draft","planned","pending","in-progress","done"}
assert set(enum) == expected, "epic status enum changed: %r" % enum
PY
./init.sh >/dev/null 2>&1 || fail "R16: ./init.sh did not exit 0"
pass "R16 no_schema_change"

# ── R17: feature rollup + roles + all /sdd-* behaviorally unchanged; no-planning no-op
# R17_backward_compatible
for f in .claude/commands/sdd-new.md .claude/commands/sdd-plan.md \
         .claude/commands/sdd-drill.md .claude/commands/sdd-next.md \
         .claude/commands/sdd-fix.md agents/planner.md agents/driller.md \
         agents/architect.md agents/builder.md agents/reviewer.md; do
  [ -f "$f" ] || fail "R17: $f missing"
done
# the feature-level (sliced) rollup is still present in the store contract
grep -qi 'Rollup rule' "$STORE"                          || fail "R17: store lost the feature-level Rollup rule"
grep -qi 'slice' "$STORE"                                || fail "R17: store lost the sliced-feature rollup"
./init.sh >/dev/null 2>&1 || fail "R17: ./init.sh did not exit 0"
pass "R17 backward_compatible"

# ── R18: contract lives in portable files; no new slash command, no installer wiring
# R18_portable_no_glue
grep -qi 'drift' "$ORCH"                                  || fail "R18: drift rule not in the portable orchestrator role"
grep -qi 'demote' "$ORCH"                                 || fail "R18: demote rule not in the portable orchestrator role"
grep -qi 'read-only' "$SCOUT"                            || fail "R18: read-only Scout rule not in the portable scout role"
grep -qi 'nothing to re-validate' "$SCOUT"               || fail "R18: no-op note not in the portable scout role"
grep -qi 'drift' "$STORE"                                || fail "R18: drift rule not in the portable store contract"
# F06 adds NO new sdd-drift slash command
if ls .claude/commands/sdd-drift*.md >/dev/null 2>&1; then
  fail "R18: F06 added a .claude/commands/sdd-drift*.md slash command"
fi
# F06 does not newly wire the installer for the drift check
grep -qi 'drift' harness-install.sh && fail "R18: harness-install.sh newly references drift"
pass "R18 portable_no_glue"

# ── R19: one MINOR bump recorded in CHANGELOG (no literal frozen; marker across file)
# R19_version_changelog
V="$(cat VERSION)"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "R19: VERSION '$V' not semver"
grep -qF "## [$V]" CHANGELOG.md                 || fail "R19: CHANGELOG.md has no '## [$V]' heading"
# the drift-check MARKER appears SOMEWHERE in the whole CHANGELOG (NOT coupled to the
# current-top-version section) — guards against the permanent-suite anti-pattern.
grep -qiE 'drift check|drift-check' CHANGELOG.md || fail "R19: CHANGELOG.md has no drift-check marker anywhere"
pass "R19 version_changelog"

echo "All drift-check tests passed."
