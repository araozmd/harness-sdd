#!/bin/sh
# test_epic_lifecycle.sh — verification for E06-F01 (epic draft/planned states +
# next() draft gate). The feature is schema + prose + one warn-only init.sh check,
# so verification is: python fixtures validated against store/tasks.schema.json
# (jsonschema if installed, else a fallback mirroring init.sh's invariants),
# required-phrase greps on the portable contract files, and one sandboxed init.sh
# run for the warn-only invariant. Zero deps: POSIX sh + grep + python3.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact
# VERSION literal (read the file at runtime); never diff DO-NOT-TOUCH files
# against main.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

SCHEMA="store/tasks.schema.json"
LOCAL="store/local.md"
ORCH="agents/orchestrator.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

# Shared validator: real jsonschema when available, else a structural fallback
# that mirrors init.sh's enums (subset sufficient for these fixtures).
cat > "$TMP/validate.py" <<'PY'
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
# Fallback structural check mirroring init.sh (required fields + status enums + ids).
errors = []
EPIC = {"draft", "planned", "pending", "in-progress", "done"}
FEAT = {"pending", "spec-ready", "in-progress", "in-review", "done"}
for ei, ep in enumerate(data.get("epics", [])):
    if not re.match(r"^E[0-9]+$", ep.get("id", "")): errors.append("epic[%d].id" % ei)
    if ep.get("status") not in EPIC: errors.append("epic[%d].status '%s'" % (ei, ep.get("status")))
    for fi, ft in enumerate(ep.get("features", [])):
        for k in ("id", "title", "status", "sdd", "spec_path"):
            if k not in ft: errors.append("epic[%d].feat[%d] missing %s" % (ei, fi, k))
        if not re.match(r"^E[0-9]+-F[0-9]+$", ft.get("id", "")): errors.append("epic[%d].feat[%d].id" % (ei, fi))
        if ft.get("status") not in FEAT: errors.append("epic[%d].feat[%d].status '%s'" % (ei, fi, ft.get("status")))
for e in errors: print("  " + e, file=sys.stderr)
sys.exit(1 if errors else 0)
PY

# ── R1: schema accepts epic statuses draft + planned (additive enum) ─────────────
# R1_epic_enum_additive
cat > "$TMP/r1.json" <<'JSON'
{
  "project": "fixture",
  "epics": [
    { "id": "E90", "title": "sketch", "status": "draft",
      "features": [
        { "id": "E90-F01", "title": "f", "status": "pending", "sdd": true,
          "spec_path": "specs/epics/E90/F01/" }
      ] },
    { "id": "E91", "title": "approved", "status": "planned",
      "features": [
        { "id": "E91-F01", "title": "f", "status": "pending", "sdd": true,
          "spec_path": "specs/epics/E91/F01/" }
      ] }
  ]
}
JSON
python3 "$TMP/validate.py" "$TMP/r1.json" "$SCHEMA" \
  || fail "R1: store with draft + planned epics did not validate"
# The epic enum line carries all five values (membership, not order).
grep -qF '"enum": ["draft", "planned", "pending", "in-progress", "done"]' "$SCHEMA" \
  || fail "R1: epic status enum in schema missing draft/planned (or lost an existing value)"
pass "R1 epic_enum_additive"

# ── R2: feature/slice enums unchanged — feature status draft is rejected ─────────
# R2_feature_enum_unchanged
cat > "$TMP/r2.json" <<'JSON'
{
  "project": "fixture",
  "epics": [
    { "id": "E90", "title": "e", "status": "pending",
      "features": [
        { "id": "E90-F01", "title": "f", "status": "draft", "sdd": true,
          "spec_path": "specs/epics/E90/F01/" }
      ] }
  ]
}
JSON
if python3 "$TMP/validate.py" "$TMP/r2.json" "$SCHEMA" 2>/dev/null; then
  fail "R2: feature with status 'draft' was accepted (feature enum must be unchanged)"
fi
# Feature + slice enum lines are byte-identical to the pre-feature values.
grep -qF '"enum": ["pending", "spec-ready", "in-progress", "in-review", "done"]' "$SCHEMA" \
  || fail "R2: feature status enum changed"
grep -qF '"enum": ["pending", "spec-ready", "in-progress", "in-review", "done", "failed"]' "$SCHEMA" \
  || fail "R2: slice status enum changed"
pass "R2 feature_enum_unchanged"

# ── R3: legacy stores (no draft/planned epics) validate unchanged ────────────────
# R3_legacy_store_valid
cat > "$TMP/r3.json" <<'JSON'
{
  "project": "fixture",
  "epics": [
    { "id": "E90", "title": "a", "status": "pending",
      "features": [
        { "id": "E90-F01", "title": "f", "status": "done", "sdd": true,
          "spec_path": "specs/epics/E90/F01/" }
      ] },
    { "id": "E91", "title": "b", "status": "in-progress",
      "features": [
        { "id": "E91-F01", "title": "f", "status": "in-review", "sdd": false,
          "spec_path": "specs/epics/E91/F01/" }
      ] },
    { "id": "E92", "title": "c", "status": "done",
      "features": [
        { "id": "E92-F01", "title": "f", "status": "done", "sdd": true,
          "spec_path": "specs/epics/E92/F01/" }
      ] }
  ]
}
JSON
python3 "$TMP/validate.py" "$TMP/r3.json" "$SCHEMA" \
  || fail "R3: legacy store (pending/in-progress/done epics only) did not validate"
python3 "$TMP/validate.py" "state/tasks.json" "$SCHEMA" \
  || fail "R3: live state/tasks.json did not validate against the edited schema"
pass "R3 legacy_store_valid"

# ── R4: init.sh fallback validator parity + green run on the untouched repo ──────
# R4_init_parity
# The zero-dependency fallback enum set now lives in the SHARED validator
# tools/validate-board.py (E15-F01, Codex #46 r2): init.sh calls it as a CLI
# rather than embedding a duplicate. Assert the enum parity on the shared file
# AND that init.sh actually invokes it (so the parity chain still reaches init.sh).
VALIDATOR="tools/validate-board.py"
[ -f "$VALIDATOR" ] || fail "R4: shared validator tools/validate-board.py missing"
grep 'EPIC_STATUS' "$VALIDATOR" | grep -qF '"draft"' \
  || fail "R4: shared validator EPIC_STATUS set missing \"draft\""
grep 'EPIC_STATUS' "$VALIDATOR" | grep -qF '"planned"' \
  || fail "R4: shared validator EPIC_STATUS set missing \"planned\""
grep -qF 'tools/validate-board.py' init.sh \
  || fail "R4: init.sh does not invoke the shared validator tools/validate-board.py"
./init.sh >/dev/null 2>&1 || fail "R4: ./init.sh failed on the untouched repo"
pass "R4 init_parity"

# ── R5: draft gate is normative in BOTH portable contract files ───────────────────
# R5_draft_gate_normative
grep -qi 'never actionable\|never selects' "$LOCAL" || fail "R5: $LOCAL lacks never-actionable/never-selects phrasing"
tr '\n' ' ' < "$LOCAL" | grep -qiE 'draft[^.]{0,30}never actionable' || fail "R5: $LOCAL does not state a draft epic's features are never actionable"
grep -qi 'never select' "$ORCH"                     || fail "R5: $ORCH lacks never-select phrasing"
tr '\n' ' ' < "$ORCH" | grep -qiE 'never select[^.]{0,60}draft' || fail "R5: $ORCH does not forbid selecting a feature of a draft epic"
# autonomous: true does NOT override the epic gate — stated in both files.
grep -qi 'autonomous: true.*\(not\|never\)\|\(not\|never\).*override' "$LOCAL" \
  || fail "R5: $LOCAL does not state autonomous does not override the gate"
grep -qi 'autonomous: true.*skips the \*human' "$ORCH" \
  || fail "R5: $ORCH does not state autonomous skips only the human gate"
pass "R5 draft_gate_normative"

# ── R6: planned epics' features selectable exactly as pending epics' features ────
# R6_planned_equals_pending
grep -qi 'planned.*\(no new gate\|treated exactly\|identically\)\|\(pending\|planned\).*gating-equivalent' "$LOCAL" \
  || fail "R6: $LOCAL does not state planned features are selected like pending epics' features"
pass "R6 planned_equals_pending"

# ── R7: store/local.md documents the epic gate inside the next() contract ────────
# R7_local_contract — the gate text lives in the next() bullet itself.
sed -n '/\*\*next()\*\*/,/\*\*get(/p' "$LOCAL" | grep -qi 'epic gate' \
  || fail "R7: $LOCAL next() contract does not carry the epic gate"
pass "R7 local_contract"

# ── R8: rule lives in the portable role file (agents/orchestrator.md) ────────────
# R8_portable_role_file — presence in the portable file is the contract.
grep -qi 'epic gate' "$ORCH" || fail "R8: $ORCH does not carry the epic gate rule"
pass "R8 portable_role_file"

# ── R9: WORKFLOW.md documents the lifecycle + legacy alias ───────────────────────
# R9_workflow_lifecycle
grep -qF 'draft → planned → in-progress → done' docs/WORKFLOW.md \
  || fail "R9: docs/WORKFLOW.md missing the lifecycle chain"
grep -qi 'legacy alias' docs/WORKFLOW.md \
  || fail "R9: docs/WORKFLOW.md missing the pending legacy-alias note"
pass "R9 workflow_lifecycle"

# ── R10: epic template status comment shows the new lifecycle ────────────────────
# R10_epic_template
grep -q 'status:.*draft → planned → in-progress → done' specs/_templates/epic.md \
  || fail "R10: epic template status comment missing the lifecycle"
grep -qi 'legacy alias' specs/_templates/epic.md \
  || fail "R10: epic template missing the pending legacy-alias note"
pass "R10 epic_template"

# ── R11: local.md states pending ≡ planned for gating ────────────────────────────
# R11_alias_equivalence
grep -qi 'legacy alias' "$LOCAL"        || fail "R11: $LOCAL missing the legacy-alias statement"
grep -qi 'gating-equivalent\|treats them identically' "$LOCAL" \
  || fail "R11: $LOCAL missing the gating-equivalence statement"
pass "R11 alias_equivalence"

# ── R12: draft epic w/ non-pending feature ⇒ init.sh warns AND exits 0 ───────────
# R12_warn_only_invariant — sandboxed harness copy (no .git), warn-only behavior.
cat > "$TMP/r12.json" <<'JSON'
{
  "project": "fixture",
  "epics": [
    { "id": "E90", "title": "sketch", "status": "draft",
      "features": [
        { "id": "E90-F01", "title": "f", "status": "in-progress", "sdd": true,
          "spec_path": "specs/epics/E90/F01/" }
      ] }
  ]
}
JSON
# The same store must PASS schema validation (the invariant is warn-only, not schema).
python3 "$TMP/validate.py" "$TMP/r12.json" "$SCHEMA" \
  || fail "R12: schema rejected a draft epic with an in-progress feature (must be warn-only)"
SBX="$TMP/sandbox"
mkdir -p "$SBX/state"
# init.sh now delegates schema validation to the shared tools/validate-board.py
# (E15-F01, Codex #46 r2), so the sandbox must include tools/ too.
for p in init.sh AGENTS.md harness.config.yaml agents specs progress store tools; do
  cp -R "$ROOT/$p" "$SBX/"
done
cp "$TMP/r12.json" "$SBX/state/tasks.json"
OUT="$TMP/r12.out"
if ! (cd "$SBX" && ./init.sh) >"$OUT" 2>&1; then
  cat "$OUT" >&2
  fail "R12: init.sh exited non-zero on a draft epic with a non-pending feature (must warn only)"
fi
grep -q '⚠️' "$OUT"      || fail "R12: init.sh printed no ⚠️ warning"
grep -q 'E90' "$OUT"     || fail "R12: warning does not name the draft epic (E90)"
grep -q 'E90-F01' "$OUT" || fail "R12: warning does not name the offending feature (E90-F01)"
pass "R12 warn_only_invariant"

# ── R13: board-mirror.md notes epic statuses never map to columns ────────────────
# R13_mirror_note
grep -qi 'epic.*statuses never map\|never map to columns' store/board-mirror.md \
  || fail "R13: store/board-mirror.md missing the epic-statuses-never-map note"
grep -q 'draft' store/board-mirror.md   || fail "R13: store/board-mirror.md note does not mention draft"
grep -q 'planned' store/board-mirror.md || fail "R13: store/board-mirror.md note does not mention planned"
pass "R13 mirror_note"

# ── R14: one MINOR bump recorded in CHANGELOG (version read at runtime) ──────────
# R14_version_changelog — never hard-code the version literal.
V="$(cat VERSION)"
echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "R14: VERSION '$V' is not SemVer"
grep -qF "## [$V]" CHANGELOG.md || fail "R14: CHANGELOG.md has no '## [$V]' heading for the current VERSION"
# The epic-lifecycle change must be recorded in CHANGELOG — but at the version that
# SHIPPED it, NOT the live VERSION. Extracting the CURRENT release's section and
# demanding it mention draft/planned freezes this permanent suite to one release, so
# every later unrelated bump (e.g. a telemetry-formatting release) fails it. That is
# the freeze-the-moving-value anti-pattern. Assert the lifecycle is documented
# SOMEWHERE in the log instead, decoupled from $V.
tr '\n' ' ' < CHANGELOG.md | grep -qiE 'draft[^.]{0,15}planned' \
  || fail "R14: CHANGELOG.md never records the draft-to-planned epic lifecycle"
pass "R14 version_changelog"

echo "All epic-lifecycle tests passed."
