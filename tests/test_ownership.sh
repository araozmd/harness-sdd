#!/bin/sh
# test_ownership.sh — E10-F01 ownership primitive: optional `owner` field in the
# TaskStore schema + scoped `/sdd-next --mine` selection contract.
#
# Behavioral / contract assertions only. Per the harness test ethos we assert BEHAVIOR
# and the SHAPE of the VERSION bump — we NEVER pin the exact VERSION string and NEVER
# diff DO-NOT-TOUCH files against `main` (recurring permanent-suite anti-pattern).
#
# Coverage (R-id → assertion):
#   R1  owner_present_validates          — string owner on epic + feature ⇒ valid
#   R2  owner_absent_validates           — owner-free doc ⇒ valid (backward compat)
#   R3  owner_type_enforced              — non-string owner ⇒ invalid
#   R4  unscoped_is_boardwide_regression — bare next() ignores owner (contract text)
#   R5  mine_filters_to_owned            — --mine filters to effective-owner==identity
#   R6  effective_owner_rule_documented  — feature owner else epic owner else unowned
#   R7  scoped_owned_only_no_claim       — never selects unowned, never writes owner
#   R8  identity_resolution_documented   — @me/self → gh api user; else literal
#   R9  unresolved_identity_fails_closed — unresolved identity ⇒ fail closed, no widen
#   R10 no_owned_work_no_widen           — empty scoped result ⇒ report, no widen
#   R11 scoping_contract_is_portable     — scoping lives in orchestrator contract
#   R14 docs_describe_ownership          — WORKFLOW.md + local.md describe ownership
#   R15 version_bumped_minor             — VERSION is valid SemVer + matching CHANGELOG entry
# (R12/R13 installer wiring live in tests/test_install.sh.)

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCHEMA="$ROOT/store/tasks.schema.json"
ORCH="$ROOT/agents/orchestrator.md"
CFG="$ROOT/harness.config.yaml"
WORKFLOW="$ROOT/docs/WORKFLOW.md"
LOCAL="$ROOT/store/local.md"
VERSION_FILE="$ROOT/VERSION"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harnessowner)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -f "$SCHEMA" ] || fail "store/tasks.schema.json missing"
[ -f "$ORCH" ]   || fail "agents/orchestrator.md missing"

# ── Schema fixtures (R1/R2/R3) ─────────────────────────────────────────────────
# owner-free (R2): a pre-feature doc must still validate byte-for-byte-behaviorally.
cat > "$T/absent.json" <<'EOF'
{"project":"demo","epics":[{"id":"E01","title":"Demo","status":"pending",
"features":[{"id":"E01-F01","title":"X","status":"pending","sdd":true,"spec_path":"s"}]}]}
EOF
# owner-present (R1): a string owner on an epic AND on a feature ⇒ valid.
cat > "$T/present.json" <<'EOF'
{"project":"demo","epics":[{"id":"E01","title":"Demo","status":"pending","owner":"alice",
"features":[{"id":"E01-F01","title":"X","status":"pending","sdd":true,"spec_path":"s","owner":"bob"}]}]}
EOF
# non-string owner (R3): owner:5 on a feature ⇒ invalid.
cat > "$T/badtype.json" <<'EOF'
{"project":"demo","epics":[{"id":"E01","title":"Demo","status":"pending",
"features":[{"id":"E01-F01","title":"X","status":"pending","sdd":true,"spec_path":"s","owner":5}]}]}
EOF
# non-string owner on an EPIC (R3): owner:5 on the epic ⇒ invalid. Exercises the
# other object so the zero-dependency path is enforced on both, matching the schema.
cat > "$T/badtype_epic.json" <<'EOF'
{"project":"demo","epics":[{"id":"E01","title":"Demo","status":"pending","owner":5,
"features":[{"id":"E01-F01","title":"X","status":"pending","sdd":true,"spec_path":"s"}]}]}
EOF

# Validate <doc> against the schema; echo "VALID"/"INVALID"/"SKIP" on stdout.
validate() {
  python3 - "$1" "$SCHEMA" <<'PY' 2>/dev/null
import json, sys
try:
    import jsonschema
except ImportError:
    print("SKIP"); sys.exit(0)
data = json.load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
errs = list(jsonschema.Draft7Validator(schema).iter_errors(data))
print("INVALID" if errs else "VALID")
PY
}

if command -v python3 >/dev/null 2>&1; then
  R_ABSENT="$(validate "$T/absent.json")"
  R_PRESENT="$(validate "$T/present.json")"
  R_BAD="$(validate "$T/badtype.json")"
  if [ "$R_ABSENT" = "SKIP" ]; then
    pass "schema cases skipped (python jsonschema unavailable) [owner_absent_validates]"
    pass "schema cases skipped (python jsonschema unavailable) [owner_present_validates]"
    pass "schema cases skipped (python jsonschema unavailable) [owner_type_enforced]"
  else
    [ "$R_ABSENT" = "VALID" ]  || fail "owner-free doc must still validate (backward compat) [owner_absent_validates]"
    pass "owner-free state/tasks.json validates unchanged [owner_absent_validates]"
    [ "$R_PRESENT" = "VALID" ] || fail "string owner on epic+feature must validate [owner_present_validates]"
    pass "string owner on epic + feature validates [owner_present_validates]"
    [ "$R_BAD" = "INVALID" ]   || fail "non-string owner (owner:5) must be rejected [owner_type_enforced]"
    pass "non-string owner rejected; string owner valid [owner_type_enforced]"
  fi
else
  pass "schema cases skipped (python3 unavailable) [owner_absent_validates]"
  pass "schema cases skipped (python3 unavailable) [owner_present_validates]"
  pass "schema cases skipped (python3 unavailable) [owner_type_enforced]"
fi

# ── R3 on the ZERO-DEPENDENCY path (shared fallback validator) ─────────────────
# The jsonschema block above SKIPS in installs without jsonschema, so R3 was
# silently untested on the built-in fallback that init.sh actually uses there.
# Drive owner:5 through the SHARED validator init.sh runs (tools/validate-board.py,
# E15-F01 Codex #46 r2) with jsonschema forced unavailable, and assert it is
# REJECTED on BOTH the epic and the feature — while owner-absent and string-owner
# docs still pass. We run the REAL production validator (the exact file init.sh
# invokes and tasks-lock.py imports), never a re-implementation, so it can never
# drift from prod.
VALIDATOR="$ROOT/tools/validate-board.py"
[ -f "$VALIDATOR" ] || fail "tools/validate-board.py missing (cannot test zero-dependency validator)"
# init.sh must actually invoke it (guards the extraction↔prod link this test asserts).
grep -qF 'tools/validate-board.py' "$ROOT/init.sh" \
  || fail "init.sh does not invoke tools/validate-board.py [owner_type_enforced]"
if command -v python3 >/dev/null 2>&1; then
  # Run the production validator with jsonschema import blocked, forcing the
  # built-in structural branch regardless of what is installed locally.
  fb_validate() {
    python3 - "$1" "$SCHEMA" "$VALIDATOR" <<'PY' 2>/dev/null
import sys, importlib.abc, importlib.machinery
class _Block(importlib.abc.MetaPathFinder):
    def find_spec(self, name, path, target=None):
        if name == "jsonschema" or name.startswith("jsonschema."):
            raise ImportError("jsonschema blocked for zero-dep test")
        return None
sys.meta_path.insert(0, _Block())
data_path, schema_path, code_path = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = [sys.argv[0], data_path, schema_path]
code = open(code_path).read()
try:
    exec(compile(code, code_path, "exec"), {"__name__": "__main__"})
    raise SystemExit(0)
except SystemExit as e:
    raise SystemExit(e.code if e.code is not None else 0)
PY
  }

  if ! fb_validate "$T/absent.json"; then
    fail "zero-dep validator must accept owner-free doc [owner_absent_validates]"
  fi
  pass "zero-dep (init.sh fallback) accepts owner-free state/tasks.json [owner_absent_validates]"
  if ! fb_validate "$T/present.json"; then
    fail "zero-dep validator must accept string owner [owner_present_validates]"
  fi
  pass "zero-dep (init.sh fallback) accepts string owner on epic + feature [owner_present_validates]"
  if fb_validate "$T/badtype.json"; then
    fail "zero-dep validator accepted feature owner:5 (must reject) [owner_type_enforced]"
  fi
  if fb_validate "$T/badtype_epic.json"; then
    fail "zero-dep validator accepted epic owner:5 (must reject) [owner_type_enforced]"
  fi
  pass "zero-dep (init.sh fallback) rejects non-string owner on epic AND feature [owner_type_enforced]"
else
  pass "zero-dep validator R3 skipped (python3 unavailable) [owner_type_enforced]"
fi

# Also assert the schema does NOT list owner as required on either object (R1) and
# that the additive property exists — a structural, non-snapshot check.
grep -q '"owner"' "$SCHEMA" || fail "schema does not define an owner property [owner_present_validates]"
python3 - "$SCHEMA" <<'PY' || fail "owner must not be in any required array (additive) [owner_absent_validates]"
import json, sys
s = json.load(open(sys.argv[1]))
def walk(o):
    if isinstance(o, dict):
        if "owner" in (o.get("required") or []):
            sys.exit(1)
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(s)
PY
pass "owner property is additive (present, never required) [owner_present_validates]"

# ── Orchestrator contract wording (R4–R11) ────────────────────────────────────
grep -qi 'effective owner' "$ORCH" \
  || fail "orchestrator contract lacks the effective-owner rule [effective_owner_rule_documented]"
# feature-wins fallback wording (R6).
grep -qiE 'otherwise its parent epic|else .*parent epic|feature.?level (value )?.?wins' "$ORCH" \
  || fail "orchestrator contract lacks the feature-owner-else-epic-owner fallback [effective_owner_rule_documented]"
tr '\n' ' ' < "$ORCH" | grep -qiE 'otherwise the feature is[^.]{0,10}unowned' \
  || fail "orchestrator contract does not define the unowned case [effective_owner_rule_documented]"
pass "effective-owner rule (feature else epic else unowned) documented [effective_owner_rule_documented]"

grep -q -- '--mine' "$ORCH" \
  || fail "orchestrator contract does not describe the --mine scope [mine_filters_to_owned]"
grep -qiE 'layered on top|filter .*on top of|never .*relax|never loosen' "$ORCH" \
  || fail "orchestrator contract does not state scoping is layered on next() without relaxing gates [mine_filters_to_owned]"
pass "--mine is a filter layered on next(), never relaxing a gate [mine_filters_to_owned]"

grep -qiE 'never (write|claim)|no claim-on-select|never .*(claim|mutate).* owner' "$ORCH" \
  || fail "orchestrator contract does not forbid claim-on-select in scoped mode [scoped_owned_only_no_claim]"
grep -qiE 'never[[:space:]]+select[[:space:]]+an[[:space:]]+unowned|owned-only' "$ORCH" \
  || fail "orchestrator contract does not state scoped mode is owned-only [scoped_owned_only_no_claim]"
pass "scoped mode is owned-only + never claims/writes an owner [scoped_owned_only_no_claim]"

grep -qi 'workflow.identity' "$ORCH" \
  || fail "orchestrator contract does not name workflow.identity [identity_resolution_documented]"
grep -qi 'gh api user' "$ORCH" \
  || fail "orchestrator contract does not resolve @me/self via gh api user [identity_resolution_documented]"
grep -qiE '@me|self' "$ORCH" \
  || fail "orchestrator contract does not mention @me/self identity [identity_resolution_documented]"
grep -qi 'verbatim\|literal' "$ORCH" \
  || fail "orchestrator contract does not describe literal identity resolution [identity_resolution_documented]"
pass "identity resolution (@me/self→gh api user; else literal) documented [identity_resolution_documented]"

grep -qi 'fail closed' "$ORCH" \
  || fail "orchestrator contract lacks fail-closed on unresolved identity [unresolved_identity_fails_closed]"
tr '\n' ' ' < "$ORCH" | grep -qiE 'unresolved[^.]{0,20}change[^.]{0,15}state' \
  || fail "orchestrator contract does not fail closed (no state change) on an unresolved identity [unresolved_identity_fails_closed]"
pass "unresolved identity under --mine fails closed (no widen, no state change) [unresolved_identity_fails_closed]"

grep -qi 'no owned actionable' "$ORCH" \
  || fail "orchestrator contract lacks the 'no owned actionable work' report [no_owned_work_no_widen]"
grep -qiE 'not[^a-z]*widen|never[^a-z]*widen|do not .*widen' "$ORCH" \
  || fail "orchestrator contract does not forbid widening to board-wide [no_owned_work_no_widen]"
pass "empty scoped result reports + never widens to board-wide [no_owned_work_no_widen]"

# R4 — bare /sdd-next is unchanged board-wide behavior (owner ignored).
grep -qiE 'bare .*sdd-next|no .*--mine|behaves exactly as today|today.?s board-wide' "$ORCH" \
  || fail "orchestrator contract does not preserve today's board-wide behavior for bare /sdd-next [unscoped_is_boardwide_regression]"
grep -qi 'no .*owner. anywhere' "$ORCH" \
  || grep -qi "no .owner. anywhere" "$ORCH" \
  || grep -qi 'owner. values are ignored\|owner values are ignored' "$ORCH" \
  || fail "orchestrator contract does not state unscoped selection ignores owner [unscoped_is_boardwide_regression]"
pass "bare /sdd-next unchanged board-wide, owner ignored (backward compat) [unscoped_is_boardwide_regression]"

# R11 — the scoping lives in the portable Orchestrator contract, not CLI-specific glue.
grep -qi 'tool-agnostic\|AGENTS.md-compatible\|no Claude-Code-specific\|portable' "$ORCH" \
  || fail "orchestrator contract does not state the scoping is tool-agnostic/portable [scoping_contract_is_portable]"
# board-mirror one-way invariant intact (DO NOT TOUCH).
grep -qiE 'one-way|single source of truth|never read.* the board' "$ORCH" \
  || fail "orchestrator contract lost the board-mirror one-way invariant [scoping_contract_is_portable]"
pass "scoping is portable (in the contract) + mirror stays one-way [scoping_contract_is_portable]"

# R5 — a concrete scoped-select walk-through phrasing: only effective-owner==identity is kept.
grep -qiE 'only .*(features|candidates) .*effective owner .*(equal|==|matches)|keep only .*effective owner' "$ORCH" \
  || fail "orchestrator contract does not state --mine keeps only effective-owner==identity [mine_filters_to_owned]"
pass "--mine keeps only features whose effective owner == resolved identity [mine_filters_to_owned]"

# ── Config carries workflow.identity (R8) ─────────────────────────────────────
grep -qE '^[[:space:]]+identity:' "$CFG" \
  || fail "harness.config.yaml has no workflow.identity key"
pass "harness.config.yaml carries workflow.identity [identity_resolution_documented]"

# ── Docs describe ownership (R14) ─────────────────────────────────────────────
for doc in "$WORKFLOW" "$LOCAL"; do
  [ -f "$doc" ] || fail "$doc missing"
  tr '\n' ' ' < "$doc" | grep -qiE 'optional[^.]{0,15}owner' || fail "$doc does not describe the optional owner field [docs_describe_ownership]"
  grep -qi 'effective owner' "$doc"   || fail "$doc does not describe the effective-owner rule [docs_describe_ownership]"
  grep -qi 'workflow.identity' "$doc" || fail "$doc does not describe workflow.identity [docs_describe_ownership]"
  grep -q -- '--mine' "$doc"          || fail "$doc does not describe /sdd-next --mine [docs_describe_ownership]"
done
# The "no owner anywhere ⇒ today's behavior" guarantee (R14) — WORKFLOW.md at least.
grep -qiE "no .owner. anywhere|today.?s board-wide|exactly today" "$WORKFLOW" \
  || fail "docs/WORKFLOW.md lacks the 'no owner ⇒ today's behavior' guarantee [docs_describe_ownership]"
pass "docs/WORKFLOW.md + store/local.md describe owner, effective owner, identity, --mine [docs_describe_ownership]"

# ── VERSION bump accompanied by a CHANGELOG entry (R15 — shape, never a git delta) ─
# Assert the SHAPE of the bump, never a git delta and never a hardcoded literal:
#   (a) VERSION parses as valid SemVer (MAJOR.MINOR.PATCH, numeric segments);
#   (b) CHANGELOG.md carries a matching entry for that VERSION.
# This mirrors tests/test_doc_critic.sh R15 / test_epic_lifecycle.sh R14 / test_sdd_plan.sh
# R23 — a stable form that stays green post-commit, because it never compares the
# working tree against HEAD or main (the recurring permanent-suite anti-pattern).
CHANGELOG_FILE="$ROOT/CHANGELOG.md"
VER="$(tr -d ' \n' < "$VERSION_FILE")"
echo "$VER" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "VERSION is not valid SemVer (MAJOR.MINOR.PATCH): '$VER' [version_bumped_minor]"
[ -f "$CHANGELOG_FILE" ] || fail "CHANGELOG.md missing [version_bumped_minor]"
grep -qF "[$VER]" "$CHANGELOG_FILE" \
  || fail "CHANGELOG.md has no entry for VERSION $VER [version_bumped_minor]"
pass "VERSION is valid SemVer ($VER) with a matching CHANGELOG entry [version_bumped_minor]"

echo "All ownership tests passed."
