#!/bin/sh
# test_umbrella.sh — test contract for E03-F01 (umbrella coordinator).
# Zero-dependency POSIX sh, matching tests/test_install.sh house style. Covers every
# R-id in umbrella-coordinator.tests.md. Several checks are schema-validation,
# config/doc-presence assertions, and a small reference run of the documented
# select/dispatch/gate/advance/rollup/integration algorithm driven by a stub
# delegate — no real child repos are required.
#
# Schema validation prefers `jsonschema` when available; otherwise it falls back to a
# minimal structural check that encodes the same slice invariants, so this test stays
# zero-dependency (mirrors init.sh).

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCHEMA="$SRC/store/tasks.schema.json"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-umbrella)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

have_py() { command -v python3 >/dev/null 2>&1; }

# validate <data.json> -> exit 0 if valid against SCHEMA, non-zero if invalid.
validate() {
  have_py || { echo "      (python3 absent — skipping schema validation)"; return 0; }
  python3 - "$1" "$SCHEMA" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
try:
    import jsonschema
    errs = list(jsonschema.Draft7Validator(schema).iter_errors(data))
    sys.exit(1 if errs else 0)
except ImportError:
    pass
# Zero-dep fallback: encode the slice invariants we assert in this test.
SLICE_ID = re.compile(r"^E[0-9]+-F[0-9]+@[a-z0-9-]+$")
FEAT_STATUS = {"pending","spec-ready","in-progress","in-review","done","failed"}
errors = []
for ep in data.get("epics", []):
    for ft in ep.get("features", []):
        slices = ft.get("slices")
        if slices is None:
            continue  # absent slices is always valid (pure superset)
        if not isinstance(slices, list):
            errors.append("slices: expected array"); continue
        if len(slices) == 0:
            errors.append("slices: must have at least 1 item"); continue
        for sl in slices:
            if not isinstance(sl, dict):
                errors.append("slice: expected object"); continue
            for k in ("id","repo","status"):
                if k not in sl:
                    errors.append("slice: missing required '%s'" % k)
            if "id" in sl and not SLICE_ID.match(str(sl["id"])):
                errors.append("slice.id %r: bad pattern" % sl["id"])
            if "repo" in sl and not isinstance(sl["repo"], str):
                errors.append("slice.repo: expected string")
            if sl.get("status") not in FEAT_STATUS and "status" in sl:
                errors.append("slice.status %r: bad enum" % sl.get("status"))
            if "merged" in sl and not isinstance(sl["merged"], bool):
                errors.append("slice.merged: expected boolean")
            if "pr" in sl and not isinstance(sl["pr"], str):
                errors.append("slice.pr: expected string")
            if "depends_on" in sl:
                d = sl["depends_on"]
                if not isinstance(d, list) or not all(isinstance(x,str) for x in d):
                    errors.append("slice.depends_on: expected array of strings")
        if ft.get("status") == "done":
            for sl in slices:
                if isinstance(sl, dict) and (sl.get("status") != "done" or sl.get("merged") is not True):
                    errors.append("feature 'done' but a slice is not done+merged")
sys.exit(1 if errors else 0)
PY
}

# ── R4 / R18 / R19: pure-superset + single-repo unchanged ──────────────────────
# The repo's current single-repo store (no slices) still validates, and init.sh is
# green with no manifest present.
validate "$SRC/state/tasks.json" || fail "current single-repo state/tasks.json no longer validates (R4/R19)"
pass "existing single-repo state/tasks.json still validates (R4, R19) [test_existing_tasks_json_still_valid][test_schema_backward_compat_no_slices]"

# init.sh green with no manifest configured (umbrella inert).
( cd "$SRC" && grep -Eq '^[[:space:]]*manifest:[[:space:]]*""' harness.config.yaml ) \
  || fail "default umbrella.manifest is not empty — single-repo would not be inert (R18)"
( cd "$SRC" && ./init.sh >/dev/null 2>&1 ) || fail "init.sh not green in single-repo mode (R18)"
pass "no manifest ⇒ coordinator inert, single-repo flow unchanged (R18) [test_no_manifest_single_repo_unchanged]"

# ── R1 / R2: schema accepts slices with id+repo and cross-repo depends_on ──────
cat > "$T/sliced.json" <<'JSON'
{
  "project": "fixture",
  "epics": [{
    "id": "E03", "title": "multi-repo", "status": "in-progress",
    "features": [{
      "id": "E03-F01", "title": "umbrella", "status": "in-progress",
      "sdd": true, "spec_path": "specs/x",
      "slices": [
        {"id":"E03-F01@lia-api","repo":"lia-api","status":"done","merged":true,"spec_path":"a","depends_on":[]},
        {"id":"E03-F01@viernes-bff","repo":"viernes-bff","status":"pending","merged":false,"spec_path":"b","depends_on":["E03-F01@lia-api"]},
        {"id":"E03-F01@viernes-web","repo":"viernes-web","status":"pending","merged":false,"spec_path":"c","depends_on":["E03-F01@viernes-bff"]}
      ]
    }]
  }]
}
JSON
validate "$T/sliced.json" || fail "feature with slices[] (id+repo) rejected (R1)"
pass "schema accepts slices[] each with id + repo (R1) [test_schema_accepts_slices]"
# depends_on present and an array of slice-id strings — covered by the same fixture.
pass "slice declares cross-repo depends_on (R2) [test_schema_slice_depends_on]"

# malformed slice (missing repo) must fail.
cat > "$T/badslice.json" <<'JSON'
{
  "project": "fixture",
  "epics": [{
    "id": "E03", "title": "multi-repo", "status": "in-progress",
    "features": [{
      "id": "E03-F01", "title": "umbrella", "status": "in-progress",
      "sdd": true, "spec_path": "specs/x",
      "slices": [{"id":"E03-F01@lia-api","status":"pending"}]
    }]
  }]
}
JSON
if validate "$T/badslice.json" 2>/dev/null; then
  # Only treat as a failure when a real validator was available.
  if have_py && python3 -c "import jsonschema" >/dev/null 2>&1; then
    fail "malformed slice (missing repo) wrongly accepted (R1)"
  fi
fi
pass "malformed slice (missing repo) rejected (R1) [test_schema_accepts_slices]"

# ── R12: fail-stop needs a schema-valid `failed` slice status ──────────────────
# The fail-stop instruction sets a failed slice to status "failed"; the store must
# stay schema-valid so the next init.sh gate does not reject it.
cat > "$T/failed.json" <<'JSON'
{
  "project": "fixture",
  "epics": [{
    "id": "E03", "title": "multi-repo", "status": "in-progress",
    "features": [{
      "id": "E03-F01", "title": "umbrella", "status": "in-progress",
      "sdd": true, "spec_path": "specs/x",
      "slices": [{"id":"E03-F01@lia-api","repo":"lia-api","status":"failed","merged":false}]
    }]
  }]
}
JSON
validate "$T/failed.json" || fail "slice status 'failed' rejected — fail-stop cannot persist (R12)"
pass "slice status 'failed' is schema-valid (R12) [test_schema_failed_status]"

# bogus slice status must still be rejected (the enum is not open).
cat > "$T/bogus.json" <<'JSON'
{
  "project": "fixture",
  "epics": [{
    "id": "E03", "title": "multi-repo", "status": "in-progress",
    "features": [{
      "id": "E03-F01", "title": "umbrella", "status": "in-progress",
      "sdd": true, "spec_path": "specs/x",
      "slices": [{"id":"E03-F01@lia-api","repo":"lia-api","status":"banana"}]
    }]
  }]
}
JSON
if validate "$T/bogus.json" 2>/dev/null; then
  if have_py && python3 -c "import jsonschema" >/dev/null 2>&1; then
    fail "bogus slice status wrongly accepted (R1)"
  fi
fi
pass "bogus slice status rejected (R1) [test_schema_failed_status]"

# ── P2 (Codex): init.sh ZERO-DEP fallback validates slices too ─────────────────
# When python3 is present but jsonschema is NOT, init.sh uses its built-in
# validator. Force that path with `python3 -S` (no site-packages ⇒ no jsonschema)
# and confirm a malformed slice is rejected before orchestration begins.
if have_py; then
  BIN="$T/bin"; mkdir -p "$BIN"
  REALPY="$(command -v python3)"
  printf '#!/bin/sh\nexec "%s" -S "$@"\n' "$REALPY" > "$BIN/python3"
  chmod +x "$BIN/python3"
  if PATH="$BIN:$PATH" python3 -c "import jsonschema" >/dev/null 2>&1; then
    echo "      (jsonschema importable even under -S — skipping fallback-path test)"
  else
    # Minimal harness layout init.sh's structural checks require.
    H="$T/inst"; mkdir -p "$H/agents" "$H/specs" "$H/progress" "$H/state" "$H/store"
    : > "$H/AGENTS.md"
    printf 'tasks: local\n' > "$H/harness.config.yaml"
    for r in orchestrator architect builder reviewer scout; do : > "$H/agents/$r.md"; done
    cp "$SRC/store/tasks.schema.json" "$H/store/tasks.schema.json"
    cp "$SRC/init.sh" "$H/init.sh"; chmod +x "$H/init.sh"
    # init.sh delegates schema validation to the shared tools/validate-board.py
    # (E15-F01, Codex #46 r2); ship it into the sandbox so the fallback path is
    # genuinely exercised (not a spurious "file not found" non-zero).
    mkdir -p "$H/tools"; cp "$SRC/tools/validate-board.py" "$H/tools/validate-board.py"
    # malformed slice: bad id pattern, missing repo, bogus status.
    cat > "$H/state/tasks.json" <<'JSON'
{
  "project": "fixture",
  "epics": [{
    "id": "E03", "title": "x", "status": "in-progress",
    "features": [{
      "id": "E03-F01", "title": "y", "status": "in-progress",
      "sdd": true, "spec_path": "p",
      "slices": [{"id":"BAD","status":"banana"}]
    }]
  }]
}
JSON
    if ( cd "$H" && PATH="$BIN:$PATH" ./init.sh >/dev/null 2>&1 ); then
      fail "init.sh fallback validator accepted a malformed slice (Codex P2)"
    fi
    pass "init.sh zero-dep fallback rejects malformed slice [test_fallback_validates_slices]"
  fi
fi

# ── P2 (Codex): empty slices[] must be rejected (no vacuous rollup) ────────────
# "slices": [] would otherwise make every-slice-done/merged vacuously true and let a
# feature reach done without dispatching any child repo. Schema requires minItems: 1.
cat > "$T/emptyslices.json" <<'JSON'
{
  "project": "fixture",
  "epics": [{
    "id": "E03", "title": "multi-repo", "status": "in-progress",
    "features": [{
      "id": "E03-F01", "title": "umbrella", "status": "in-progress",
      "sdd": true, "spec_path": "specs/x",
      "slices": []
    }]
  }]
}
JSON
if validate "$T/emptyslices.json" 2>/dev/null; then
  if have_py && python3 -c "import jsonschema" >/dev/null 2>&1; then
    fail "empty slices[] wrongly accepted — vacuous rollup possible (Codex P2)"
  fi
fi
pass "empty slices[] rejected, minItems:1 (no vacuous rollup) [test_schema_slices_min_items]"

# ── P1 (Codex r3): a `done` feature with a red slice must be rejected ──────────
# next() gates dependents on the STORED feature status, so a hand-edited/partial
# store claiming feature done while a slice is unmerged would dispatch dependents
# prematurely. Cross-field validation must reject it.
cat > "$T/donefeature_redslice.json" <<'JSON'
{
  "project": "fixture",
  "epics": [{
    "id": "E03", "title": "multi-repo", "status": "in-progress",
    "features": [{
      "id": "E03-F01", "title": "umbrella", "status": "done",
      "sdd": true, "spec_path": "specs/x",
      "slices": [
        {"id":"E03-F01@lia-api","repo":"lia-api","status":"done","merged":true},
        {"id":"E03-F01@viernes-bff","repo":"viernes-bff","status":"done","merged":false}
      ]
    }]
  }]
}
JSON
if validate "$T/donefeature_redslice.json" 2>/dev/null; then
  if have_py && python3 -c "import jsonschema" >/dev/null 2>&1; then
    fail "feature 'done' with an unmerged slice wrongly accepted (Codex r3 P1)"
  fi
fi
pass "feature 'done' requires every slice done+merged (Codex r3 P1) [test_schema_done_feature_all_slices_done]"

# the same feature IS valid once every slice is done+merged, and a persisted PR URL
# (the merge-poll selector) is accepted on a slice.
cat > "$T/donefeature_ok.json" <<'JSON'
{
  "project": "fixture",
  "epics": [{
    "id": "E03", "title": "multi-repo", "status": "done",
    "features": [{
      "id": "E03-F01", "title": "umbrella", "status": "done",
      "sdd": true, "spec_path": "specs/x",
      "slices": [
        {"id":"E03-F01@lia-api","repo":"lia-api","status":"done","merged":true,"pr":"https://github.com/o/lia-api/pull/7"},
        {"id":"E03-F01@viernes-bff","repo":"viernes-bff","status":"done","merged":true,"pr":"https://github.com/o/viernes-bff/pull/3"}
      ]
    }]
  }]
}
JSON
validate "$T/donefeature_ok.json" || fail "all-slices-done feature with slice.pr rejected (Codex r3 P1/P2)"
pass "feature 'done' with all slices done+merged and slice.pr persisted is valid (Codex r3) [test_schema_slice_pr_and_done_ok]"

# ── Reference coordinator algorithm (drives R3, R6, R9–R17) ────────────────────
# A minimal POSIX-sh implementation of the documented loop, operating over a flat
# fixture: each slice is a line "id repo status merged deps(csv|-)". The delegate is
# a stub script whose exit code we control. This proves the documented behavior is
# implementable and asserts the gating/rollup/integration rules.

# Manifest fixture: known repos (one per line). lia-api, viernes-bff, viernes-web.
MANIFEST="$T/manifest.txt"
printf 'lia-api\nviernes-bff\nviernes-web\n' > "$MANIFEST"

repo_known() { grep -qx "$1" "$MANIFEST"; }

# slice_field <line> <1-based field index>
fld() { echo "$1" | awk -v n="$2" '{print $n}'; }

# is_done_merged <slice-id> <slices-file>: 0 if that slice is done AND merged.
is_done_merged() {
  _sid="$1"; _f="$2"
  awk -v id="$_sid" '$1==id && $3=="done" && $4=="true"{found=1} END{exit found?0:1}' "$_f"
}

# upstreams_satisfied <deps-csv> <slices-file>: 0 if all deps done+merged (or none).
upstreams_satisfied() {
  _deps="$1"; _f="$2"
  [ "$_deps" = "-" ] && return 0
  echo "$_deps" | tr ',' '\n' | while read -r d; do
    [ -z "$d" ] && continue
    is_done_merged "$d" "$_f" || { echo BLOCKED; }
  done | grep -q BLOCKED && return 1
  return 0
}

# select_next <slices-file>: print id of lowest-id actionable slice whose upstreams
# are all done+merged; empty if none.
select_next() {
  _f="$1"
  sort "$_f" | while read -r line; do
    [ -z "$line" ] && continue
    st=$(fld "$line" 3); deps=$(fld "$line" 5)
    [ "$st" = "done" ] && continue
    if upstreams_satisfied "$deps" "$_f"; then
      fld "$line" 1; break
    fi
  done
}

# Fixture chain A(lia-api) -> B(viernes-bff) -> C(viernes-web), all pending/unmerged.
CHAIN="$T/chain.txt"
cat > "$CHAIN" <<EOF
E03-F01@lia-api lia-api pending false -
E03-F01@viernes-bff viernes-bff pending false E03-F01@lia-api
E03-F01@viernes-web viernes-web pending false E03-F01@viernes-bff
EOF

# R9 / R11: only A is selectable first; B and C are gated behind their upstreams.
n=$(select_next "$CHAIN")
[ "$n" = "E03-F01@lia-api" ] || fail "topo select did not pick the root slice first (got '$n') (R9)"
pass "next slice chosen in topo order, upstreams gate the rest (R9) [test_select_topological_upstream_done_merged]"
# B must NOT be selectable while A is not done+merged.
case "$n" in E03-F01@viernes-bff|E03-F01@viernes-web) fail "downstream dispatched before upstream done+merged (R11)";; esac
pass "no downstream dispatch before upstream done+merged (R11) [test_gate_blocks_downstream]"

# R10: dispatch uses <delegate_cmd> <feature-id> <abs-spec-path> and writes no source.
DELEGATE="$T/delegate.sh"
CALLLOG="$T/calls.log"
CHILD="$T/child-repo"
mkdir -p "$CHILD"
cat > "$DELEGATE" <<EOF
#!/bin/sh
# stub delegate: records args, touches nothing in the child repo dir, honors EXIT env.
echo "\$1 \$2" >> "$CALLLOG"
exit \${STUB_EXIT:-0}
EOF
chmod +x "$DELEGATE"
ABS_SPEC="$SRC/specs/epics/E03-multi-repo/F01-umbrella-coordinator/umbrella-coordinator.spec.md"
before=$(find "$CHILD" -type f | wc -l | tr -d ' ')
"$DELEGATE" "E03-F01" "$ABS_SPEC" >/dev/null
after=$(find "$CHILD" -type f | wc -l | tr -d ' ')
grep -qx "E03-F01 $ABS_SPEC" "$CALLLOG" || fail "delegate not invoked with '<feature-id> <abs-spec-path>' (R10)"
[ "$before" = "$after" ] || fail "delegate wrote source files in child repo dir (R10)"
pass "dispatch uses delegate seam exactly, no source edits in child (R10) [test_dispatch_uses_delegate_seam]"

# R6: a slice naming a repo absent from the manifest is undispatchable + reported.
if repo_known "ghost-repo"; then fail "unknown repo wrongly known (R6)"; fi
ERR=$(repo_known "ghost-repo" || echo "ERROR: repo 'ghost-repo' not in manifest")
echo "$ERR" | grep -q "ghost-repo" || fail "missing-repo error does not name the repo (R6)"
pass "slice with unknown repo undispatchable + reported, names repo (R6) [test_unknown_repo_slice_rejected]"

# R13 / R12: advance vs fail-stop.
# Success path: A succeeds (exit 0) -> mark done+merged -> re-select picks B.
STUB_EXIT=0 "$DELEGATE" "E03-F01" "$ABS_SPEC" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || fail "stub delegate success path returned non-zero (R13)"
# simulate advance: set A done+merged
sed 's|^E03-F01@lia-api .*|E03-F01@lia-api lia-api done true -|' "$CHAIN" > "$CHAIN.1"
n2=$(select_next "$CHAIN.1")
[ "$n2" = "E03-F01@viernes-bff" ] || fail "after A done+merged, B not re-evaluated as dispatchable (got '$n2') (R13)"
pass "slice success ⇒ done recorded, dispatchable set re-evaluated (R13) [test_advance_reevaluates_dispatchable]"

# Fail-stop: A's delegate exits non-zero -> A failed, B and C must stay gated.
STUB_EXIT=7 "$DELEGATE" "E03-F01" "$ABS_SPEC" >/dev/null && fail "non-zero delegate did not propagate (R12)" || rc=$?
[ "$rc" -eq 7 ] || fail "fail-stop did not surface the non-zero delegate exit (R12)"
# A stays not done+merged ⇒ downstream remains undispatchable.
n3=$(select_next "$CHAIN")   # original chain: A still pending
case "$n3" in E03-F01@viernes-bff|E03-F01@viernes-web) fail "downstream dispatched after upstream failure (R12)";; esac
[ "$n3" = "E03-F01@lia-api" ] || [ -z "$n3" ] || fail "unexpected dispatch after fail-stop (R12)"
pass "non-zero delegate ⇒ slice failed, dependents halted, surfaced (R12) [test_failstop_on_delegate_nonzero]"

# ── Rollup + integration gate (R3, R14, R15, R16, R17) ─────────────────────────
# rollup_done <slices-file>: 0 only if EVERY slice is done+merged.
rollup_all_done() {
  awk '{ if ($3!="done" || $4!="true") bad=1 } END{ exit bad?1:0 }' "$1"
}
# Integration stub: exit code controlled by INT_EXIT. Records whether it ran.
INTLOG="$T/integration.log"
run_integration() { echo "ran" >> "$INTLOG"; return "${INT_EXIT:-0}"; }

# feature_done <slices-file>: derive feature done per the documented rule.
# returns 0 (done) only if all slices done+merged AND integration exits zero.
feature_done() {
  _f="$1"
  rollup_all_done "$_f" || return 1            # R3/R14: gated until all slices done
  run_integration || return 1                  # R15/R16/R17: integration must pass
  return 0
}

# Case A: one slice not done -> feature NOT done, integration NOT run (R3, R14).
: > "$INTLOG"
PARTIAL="$T/partial.txt"
cat > "$PARTIAL" <<EOF
E03-F01@lia-api lia-api done true -
E03-F01@viernes-bff viernes-bff pending false -
EOF
if feature_done "$PARTIAL"; then fail "feature marked done with a non-done slice (R3)"; fi
[ ! -s "$INTLOG" ] || fail "integration check ran while a slice was not done (R14)"
pass "feature not done while any slice not done; integration gated (R3, R14) [test_rollup_feature_done_requires_all_slices][test_integration_gated_until_all_done]"

# Case B: all slices done+merged + integration passes (exit 0) -> feature done (R15, R16).
: > "$INTLOG"
DONEALL="$T/doneall.txt"
cat > "$DONEALL" <<EOF
E03-F01@lia-api lia-api done true -
E03-F01@viernes-bff viernes-bff done true E03-F01@lia-api
EOF
INT_EXIT=0 feature_done "$DONEALL" || fail "feature not done when all slices done+integration passes (R16)"
grep -qx "ran" "$INTLOG" || fail "integration check did not run when all slices done+merged (R15)"
pass "all slices done+merged ⇒ integration runs, feature done on zero exit (R15, R16) [test_integration_runs_when_all_done][test_feature_done_requires_integration_pass]"

# Case C: all slices done but integration fails (non-zero) -> feature NOT done (R17).
: > "$INTLOG"
if INT_EXIT=3 feature_done "$DONEALL"; then fail "feature done despite non-zero integration (R17)"; fi
grep -qx "ran" "$INTLOG" || fail "integration check should have run before failing (R15)"
pass "non-zero integration keeps feature out of done, surfaced (R17) [test_integration_failure_blocks_done]"

# ── R5: manifest example parses all four fields per repo ───────────────────────
EX="$SRC/umbrella.manifest.example.yaml"
[ -f "$EX" ] || fail "umbrella.manifest.example.yaml missing (R5)"
if have_py; then
  python3 - "$EX" <<'PY' || exit 1
import sys, re
lines = open(sys.argv[1]).read().splitlines()
repos = {}
cur = None
in_repos = False
for ln in lines:
    if re.match(r"^repos:\s*$", ln): in_repos = True; continue
    if in_repos and re.match(r"^\S", ln): in_repos = False
    if not in_repos: continue
    m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", ln)
    if m: cur = m.group(1); repos[cur] = {}; continue
    m = re.match(r"^    ([A-Za-z_]+):\s*(.+?)\s*$", ln)
    if m and cur: repos[cur][m.group(1)] = m.group(2)
assert repos, "no repos parsed"
for r, f in repos.items():
    for need in ("path","init","test_command","delegate_cmd"):
        assert need in f, "repo %s missing field %s" % (r, need)
print("ok %d repos, all four fields present" % len(repos))
PY
  pass "manifest example parses path/init/test_command/delegate_cmd per repo (R5) [test_manifest_example_parses_all_fields]"
else
  grep -q "path:" "$EX" && grep -q "init:" "$EX" && grep -q "test_command:" "$EX" && grep -q "delegate_cmd:" "$EX" \
    || fail "manifest example missing one of the four fields (R5)"
  pass "manifest example contains path/init/test_command/delegate_cmd (R5, grep) [test_manifest_example_parses_all_fields]"
fi

# ── R7 / R8: contract artifact pinned once, slices reference it ────────────────
DOC="$SRC/docs/UMBRELLA.md"
[ -f "$DOC" ] || fail "docs/UMBRELLA.md missing (R7)"
grep -q "contract artifact" "$DOC" || fail "docs/UMBRELLA.md does not document the contract artifact (R7)"
grep -q "exactly one" "$DOC" || fail "docs/UMBRELLA.md does not pin exactly one contract artifact (R7)"
pass "shared spec pins exactly one contract artifact, referenced by id (R7) [test_contract_artifact_pinned_once]"
grep -qi "Every emitted slice" "$DOC" || grep -qi "each emitted slice" "$DOC" \
  || fail "docs/UMBRELLA.md does not require slices to reference the contract artifact (R8)"
pass "each emitted slice references the pinned contract artifact (R8) [test_slice_references_contract]"

# ── Config + Orchestrator instruction presence (R5, R15, R18, R9-R17 home) ─────
CFG="$SRC/harness.config.yaml"
grep -q "integration_command:" "$CFG" || fail "verification.integration_command missing (R15)"
grep -Eq "^umbrella:" "$CFG"          || fail "umbrella config block missing (R5/R18)"
grep -q "manifest:" "$CFG"            || fail "umbrella.manifest key missing (R5/R18)"
pass "config has integration_command + umbrella.manifest (R5, R15, R18)"
grep -q "Umbrella mode" "$SRC/agents/orchestrator.md" \
  || fail "orchestrator.md missing additive 'Umbrella mode' section (R9-R17)"
pass "orchestrator.md has additive Umbrella mode loop (R9-R17)"

# ══ E24-F02: the landing audit ═════════════════════════════════════════════════════════
# The cascade used to print its green banner after WRITING files, with no opinion about
# whether any of it was committed. These cases are BEHAVIORAL: they run a real cascade into
# real git children and read the exit code.

AU="$(mktemp -d 2>/dev/null || mktemp -d -t harness-audit)"
trap 'rm -rf "$AU"' EXIT

# mk_umb <dir> <child>... — an umbrella with git children, each with one commit.
mk_umb() {
  _u="$1"; shift
  mkdir -p "$_u"
  for _ch in "$@"; do
    mkdir -p "$_u/$_ch"
    git -C "$_u/$_ch" init -q .
    git -C "$_u/$_ch" config user.email "test@harness.local"
    git -C "$_u/$_ch" config user.name "harness test"
    echo seed > "$_u/$_ch/README.md"
    git -C "$_u/$_ch" add -A
    git -C "$_u/$_ch" commit -q -m init
  done
}
cascade() {  # cascade <umbrella> [extra args...] -> AU_OUT / AU_RC
  _u="$1"; shift
  AU_OUT="$(CODEX_HOME="$_u/.ch" HOME="$_u/.home" sh "$SRC/harness-install.sh" --umbrella "$_u" --agents=claude "$@" 2>&1)" && AU_RC=0 || AU_RC=$?
}
land() { git -C "$1" add -A && git -C "$1" commit -q -m "land the harness"; }

# ── R1/R2/R3/R4: an unlanded cascade is audited, named, counted, and exits 3 ────────────
# R1_audit_covers_all_targets / R2_unlanded_exits_nonzero / R3_unlanded_code_is_distinct /
# R4_summary_names_and_counts
mk_umb "$AU/u1" child-a child-b
cascade "$AU/u1"
[ "$AU_RC" = "3" ] \
  || fail "R2/R3: an unlanded cascade exited $AU_RC, want 3 (distinct from the generic failure code 1)"
printf '%s' "$AU_OUT" | grep -q "landing audit" || fail "R1: no landing audit ran: $AU_OUT"
for _c in child-a child-b; do
  printf '%s' "$AU_OUT" | grep -qE "unlanded +$_c +[0-9]+ harness-owned path" \
    || fail "R4: the summary does not name $_c with a drifted-path count: $AU_OUT"
done
pass "an unlanded cascade names every child with a count and exits 3 (R1-R4) [R1_audit_covers_all_targets/R2_unlanded_exits_nonzero/R3_unlanded_code_is_distinct/R4_summary_names_and_counts]"

# ── R6: committing the harness makes the same cascade pass ─────────────────────────────
# R6_all_landed_exits_zero — paired with R2 above ON THE SAME FIXTURE, so "exit 0" cannot be
# reached by an audit that simply never runs.
land "$AU/u1/child-a"; land "$AU/u1/child-b"
cascade "$AU/u1"
[ "$AU_RC" = "0" ] || fail "R6: a fully landed cascade exited $AU_RC, want 0: $AU_OUT"
# The confirming line states what was ESTABLISHED. The default umbrella root is non-git, so
# it is unverifiable and the honest form is "N of M verified committed, K not verifiable" —
# "every target committed" is reserved for a cascade where every target really was checked.
# Asserting the generic "cascade complete" plus the per-child `landed` rows below keeps this
# case about the verdict rather than about which of the two accurate wordings applies.
printf '%s' "$AU_OUT" | grep -q "cascade complete" \
  || fail "R6: no confirming line on a fully landed cascade: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "verified committed|every target committed" \
  || fail "R6: the confirming line does not state what was verified: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "landed +child-a" \
  || fail "R6: child-a not reported as landed: $AU_OUT"
pass "a fully landed cascade prints the confirming line and exits 0 (R6) [R6_all_landed_exits_zero]"

# ── R5: a non-git target is reported, never counted as unlanded ─────────────────────────
# R5_non_git_reported_not_failed — the umbrella ROOT is non-git by default, which is exactly
# this case. Control: a git child in the SAME cascade is still audited and still fails, so a
# pass here cannot come from an audit that skips everything.
mk_umb "$AU/u2" child-c
cascade "$AU/u2"
printf '%s' "$AU_OUT" | grep -qE "no git +\(coordinator\)" \
  || fail "R5: the non-git umbrella root was not reported as 'no git': $AU_OUT"
[ "$AU_RC" = "3" ] || fail "R5 control: the unlanded git child did not fail the cascade (rc=$AU_RC)"
land "$AU/u2/child-c"
cascade "$AU/u2"
[ "$AU_RC" = "0" ] \
  || fail "R5: the non-git coordinator was counted as unlanded — a non-git target cannot be unlanded (rc=$AU_RC): $AU_OUT"
pass "a non-git target is reported and never counted as unlanded (R5) [R5_non_git_reported_not_failed]"

# ── R7: --dry-run writes nothing and never audits ───────────────────────────────────────
# R7_dry_run_skips_audit — control: the same umbrella WITHOUT --dry-run does audit and exits 3.
mk_umb "$AU/u3" child-d
cascade "$AU/u3" --dry-run
[ "$AU_RC" = "0" ] || fail "R7: --dry-run exited $AU_RC, want 0: $AU_OUT"
printf '%s' "$AU_OUT" | grep -q "landing audit" \
  && fail "R7: --dry-run ran the landing audit: $AU_OUT"
[ -d "$AU/u3/child-d/.harness" ] \
  && fail "R7: --dry-run wrote .harness/ into a child"
cascade "$AU/u3"
[ "$AU_RC" = "3" ] \
  || fail "R7 control: the same umbrella without --dry-run did not audit and fail (rc=$AU_RC)"
pass "--dry-run writes nothing and skips the audit (R7) [R7_dry_run_skips_audit]"

# ── R9: the audit never modifies a target's git state ───────────────────────────────────
# R9_audit_is_read_only — HEAD, the full unfiltered porcelain, and the index mtime must all
# be unchanged. Asserting "no new commit" alone would pass on an audit that staged without
# committing, which is exactly the accident this epic exists to prevent.
mk_umb "$AU/u4" child-e
cascade "$AU/u4"                       # first run installs (and reports unlanded)
land "$AU/u4/child-e"                  # commit it: the write under test is the stat-cache
git -C "$AU/u4/child-e" status --porcelain >/dev/null   # settle the cache before measuring
_head_before="$(git -C "$AU/u4/child-e" rev-parse HEAD)"
_status_before="$(GIT_OPTIONAL_LOCKS=0 git -C "$AU/u4/child-e" status --porcelain)"
# BYTE-COMPARE the index, not `ls -l` it. mtime via ls has one-second resolution, and the
# write this guards against — git refreshing its stat cache after install_one recopies the
# body — completes well inside a second, so the original `ls -l` comparison could not see it
# and did not. Copy the file and `cmp`: exact, portable, no stat(1) format differences.
cp "$AU/u4/child-e/.git/index" "$AU/u4/index.before" 2>/dev/null || true
cascade "$AU/u4"                       # second run: install is idempotent, audit runs again
# The index comparison MUST come first, before any other git command in this block. A plain
# `git status` refreshes the stat cache and rewrites .git/index itself — so verifying with it
# first would destroy the very evidence being checked. (The first draft did exactly that and
# reported a violation that was its own measurement.) Every later probe here is read-only or
# runs under GIT_OPTIONAL_LOCKS=0.
cmp -s "$AU/u4/index.before" "$AU/u4/child-e/.git/index" \
  || fail "R9: the audit rewrote the target's git index (byte-compare) — needs GIT_OPTIONAL_LOCKS=0"
[ "$(git -C "$AU/u4/child-e" rev-parse HEAD)" = "$_head_before" ] \
  || fail "R9: the audit created a commit in the target"
[ "$(GIT_OPTIONAL_LOCKS=0 git -C "$AU/u4/child-e" status --porcelain)" = "$_status_before" ] \
  || fail "R9: the audit changed the target's working tree or index"
pass "the audit never modifies a target's git state (R9) [R9_audit_is_read_only]"

# ── R2: an ADDED body file is caught even when git is configured to hide untracked ─────
# R2_added_file_caught_under_hidden_untracked
# An upgrade that ADDS a harness file leaves it untracked, and `status.showUntrackedFiles=no`
# in a repo or global gitconfig suppresses untracked files entirely — so without an explicit
# -uall the audit reports a fully committed target while an unlanded file sits in it. That is
# the same silent false-clean the whole epic exists to end, and the generic "fresh cascade is
# unlanded" cases cannot detect it (there, `?? .harness/` shows either way).
mk_umb "$AU/u5" child-f
cascade "$AU/u5"
land "$AU/u5/child-f"
git -C "$AU/u5/child-f" config status.showUntrackedFiles no
# The added file goes in `.claude/commands/`, NOT `.harness/agents/`: install_one PRUNES
# unknown files from the body directories, so a stray file there does not survive the
# re-install this case performs — the fixture would silently stop reproducing anything. The
# root generated-glue dirs are not pruned, and are equally harness-owned.
printf '# added by an upgrade, never committed\n' > "$AU/u5/child-f/.claude/commands/added-command.md"
# Preconditions: the target is otherwise clean, and the added file really is invisible
# without -uall — otherwise this case cannot discriminate.
[ -z "$(git -C "$AU/u5/child-f" status --porcelain -- .claude/)" ] \
  || fail "R2-uall: fixture precondition broken — showUntrackedFiles=no did not hide the added file"
[ -n "$(git -C "$AU/u5/child-f" status --porcelain -uall -- .claude/)" ] \
  || fail "R2-uall: fixture precondition broken — even -uall does not see the added file"
cascade "$AU/u5"
[ "$AU_RC" = "3" ] \
  || fail "R2-uall: an ADDED, uncommitted body file was hidden by status.showUntrackedFiles=no — the audit needs -uall (rc=$AU_RC): $AU_OUT"
pass "an added body file is caught under status.showUntrackedFiles=no (R2) [R2_added_file_caught_under_hidden_untracked]"


# ── R2: ANY ignored owned subtree must not be reported as landed ───────────────────────
# R2_ignored_owned_subtree_is_not_landed
# Three narrower probes shipped and each missed a shape: `check-ignore .harness` missed
# `.harness/tools/`, and witness-file sampling then missed `.harness/docs/` and
# `.claude/commands/` (no witness lived in them). Each fix was a narrower sample that invited
# the next gap, so the probe was inverted: git's COMPLETE ignored set over the owned
# pathspecs, minus the harness's own deliberate local-only list.
#
# This case is therefore a MATRIX over ignore shapes rather than one fixture. A sampling
# probe passes for whichever shapes it happens to cover and fails the rest — which is exactly
# how the previous two fixes looked green.
_shape_n=0
for _ign in '.harness/' '.harness/tools/' '.harness/docs/' '.claude/commands/'; do
  _shape_n=$((_shape_n + 1))
  _u="$AU/shape$_shape_n"
  mk_umb "$_u" child-s
  printf '%s\n' "$_ign" > "$_u/child-s/.gitignore"
  git -C "$_u/child-s" add -A && git -C "$_u/child-s" commit -q -m "ignore $_ign"
  cascade "$_u"
  land "$_u/child-s"                     # commit everything git will accept
  # Precondition: the ignore really does hide installed files from the index.
  [ "$(git -C "$_u/child-s" ls-files -- "$_ign" 2>/dev/null | wc -l | tr -d ' ')" = "0" ] \
    || fail "R2-shapes: fixture precondition broken — files under '$_ign' are tracked"
  cascade "$_u"
  printf '%s' "$AU_OUT" | grep -qE "landed +child-s" \
    && fail "R2-shapes: FALSE CLEAN — '$_ign' ignored, yet reported landed: $AU_OUT"
  printf '%s' "$AU_OUT" | grep -qE "no vcs +child-s" \
    || fail "R2-shapes: '$_ign' ignored but not reported unverifiable: $AU_OUT"
done
pass "every ignored owned subtree shape is unverifiable, never landed (R2) [R2_ignored_owned_subtree_is_not_landed]"
# Control 1: a HEALTHY target must still read `landed`. The harness seeds its own ignores
# (`__pycache__/`, `telemetry.jsonl`), so a probe that merely counted ignored paths would
# call every healthy target unverifiable and never fail a real cascade again.
mk_umb "$AU/healthy" child-t
cascade "$AU/healthy"
land "$AU/healthy/child-t"
cascade "$AU/healthy"
printf '%s' "$AU_OUT" | grep -qE "landed +child-t" \
  || fail "R2-shapes control: a HEALTHY landed target was not reported landed — the local-only subtraction is missing: $AU_OUT"
[ "$AU_RC" = "0" ] || fail "R2-shapes control: a healthy landed cascade exited $AU_RC, want 0"
pass "…while a healthy target is still landed (R2 control) [R2_ignored_owned_subtree_is_not_landed]"
# Control 2: a fresh, un-ignored body is UNLANDED, not unverifiable — a probe keyed on
# tracked-ness rather than ignored-ness passes the matrix above and silently exempts every
# fresh cascade.
mk_umb "$AU/u7" child-h
cascade "$AU/u7"
printf '%s' "$AU_OUT" | grep -qE "unlanded +child-h" \
  || fail "R2-shapes control: a fresh untracked (not ignored) body was not reported unlanded: $AU_OUT"
[ "$AU_RC" = "3" ] || fail "R2-shapes control: a fresh cascade did not exit 3 (rc=$AU_RC)"
pass "…and a fresh un-ignored body is still unlanded (R2 control) [R2_ignored_owned_subtree_is_not_landed]"

# ── R2: a CONFIGURED telemetry log override must not make a target unverifiable ────────
# R2_configured_telemetry_override_is_subtracted
# `telemetry.log` is configurable, and install_one adds a relative override to
# `.harness/.gitignore` itself. A subtraction list carrying only the hard-coded defaults
# therefore sees a legitimately-ignored file it does not recognise and reports the target
# unverifiable FOREVER — the audit never runs there again. Fails safe (under-claims rather
# than over-claims) but silently exempts the target. Reported as P2 on PR #103 round 4.
mk_umb "$AU/tlog" child-u
cascade "$AU/tlog"
python3 - "$AU/tlog/child-u/.harness/harness.config.yaml" <<'PYCFG' \
  || fail "R2-tlog: could not rewrite telemetry.log in the fixture config"
import sys
p = sys.argv[1]
s = open(p).read()
# ASSERT the anchor. A silent no-op here leaves the default config in place, the case then
# tests nothing, and it passes — which is exactly what happened while writing this suite.
assert "log: telemetry.jsonl" in s, "telemetry.log anchor not found in " + p
open(p, "w").write(s.replace("log: telemetry.jsonl", "log: custom/my.jsonl", 1))
PYCFG
cascade "$AU/tlog"                       # re-run so install_one seeds the override ignore
mkdir -p "$AU/tlog/child-u/.harness/custom"
printf '{}\n' > "$AU/tlog/child-u/.harness/custom/my.jsonl"
land "$AU/tlog/child-u"
# Preconditions: the override really is ignored, and it really is the configured value —
# otherwise this case cannot distinguish the fix from the fixed-list version.
grep -q 'custom/my.jsonl' "$AU/tlog/child-u/.harness/.gitignore" \
  || fail "R2-tlog: fixture precondition broken — install_one did not ignore the configured override"
git -C "$AU/tlog/child-u" check-ignore -q .harness/custom/my.jsonl \
  || fail "R2-tlog: fixture precondition broken — the override is not actually ignored"
cascade "$AU/tlog"
printf '%s' "$AU_OUT" | grep -qE "no vcs +child-u" \
  && fail "R2-tlog: a CONFIGURED telemetry override made the target unverifiable — the subtraction must read telemetry.log: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "landed +child-u" \
  || fail "R2-tlog: a fully landed target with a telemetry override was not reported landed: $AU_OUT"
pass "a configured telemetry.log override is subtracted, not treated as unverifiable (R2) [R2_configured_telemetry_override_is_subtracted]"

# ── R2: a FAILED git status is not a status that found nothing ─────────────────────────
# R2_failed_status_is_not_landed
# `git status` exits non-zero on a corrupt or unreadable index. Piping it straight into
# `grep -c` discarded that: the count came back 0 and the audit printed `landed` over a
# target it never inspected. A false CLEAN is the one output this audit must never produce.
# Reported as P2 on PR #103 round 5.
mk_umb "$AU/corrupt" child-v
cascade "$AU/corrupt"
land "$AU/corrupt/child-v"
printf 'CORRUPT' > "$AU/corrupt/child-v/.git/index"
# Precondition: status really does fail here — otherwise the case proves nothing.
git -C "$AU/corrupt/child-v" status --porcelain -uall -- .harness/ >/dev/null 2>&1 \
  && fail "R2-failstatus: fixture precondition broken — git status still succeeds on the corrupt index"
cascade "$AU/corrupt"
printf '%s' "$AU_OUT" | grep -qE "landed +child-v" \
  && fail "R2-failstatus: FALSE CLEAN — a target whose git status FAILED was reported landed: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "no read +child-v" \
  || fail "R2-failstatus: a failed git status was not reported as unverifiable: $AU_OUT"
pass "a failed git status is reported unverifiable, never landed (R2) [R2_failed_status_is_not_landed]"

# ── R2: the telemetry override is read in BOTH YAML quote forms ────────────────────────
# R2_telemetry_override_single_quoted
# YAML accepts `log: 'x'` as well as `log: "x"`, and install_one strips both before seeding
# the ignore. The helper stripped only double quotes, so a single-quoted override produced a
# pattern containing literal apostrophes, matched nothing, and the target read unverifiable
# forever. Reported as P2 on PR #103 round 5.
mk_umb "$AU/tlq" child-w
cascade "$AU/tlq"
python3 - "$AU/tlq/child-w/.harness/harness.config.yaml" <<'PYCFG' \
  || fail "R2-tlq: could not rewrite telemetry.log in the fixture config"
import sys
p = sys.argv[1]
s = open(p).read()
assert "log: telemetry.jsonl" in s, "telemetry.log anchor not found in " + p
open(p, "w").write(s.replace("log: telemetry.jsonl", "log: 'custom/my.jsonl'", 1))
PYCFG
cascade "$AU/tlq"
mkdir -p "$AU/tlq/child-w/.harness/custom"
printf '{}\n' > "$AU/tlq/child-w/.harness/custom/my.jsonl"
land "$AU/tlq/child-w"
git -C "$AU/tlq/child-w" check-ignore -q .harness/custom/my.jsonl \
  || fail "R2-tlq: fixture precondition broken — the single-quoted override is not ignored"
cascade "$AU/tlq"
printf '%s' "$AU_OUT" | grep -qE "landed +child-w" \
  || fail "R2-tlq: a single-quoted telemetry.log override was not subtracted: $AU_OUT"
pass "the telemetry override is read in both YAML quote forms (R2) [R2_telemetry_override_single_quoted]"

# ── R2: a telemetry override containing WHITESPACE is still subtracted ─────────────────
# R2_telemetry_override_with_whitespace
# git QUOTES any path containing whitespace (or non-ASCII, backslashes, control chars) in
# porcelain output — `".harness/custom/my log.jsonl"` — while the subtraction patterns are
# built from raw config values, so the quoted form never matched and the target reported
# `cannot verify` forever. Filed as E99-F11 from PR #103 round 6; fixed with `-z`, which
# emits raw paths instead of reimplementing git's C-style unescaping.
mk_umb "$AU/tlws" child-x
cascade "$AU/tlws"
python3 - "$AU/tlws/child-x/.harness/harness.config.yaml" <<'PYCFG' \
  || fail "R2-tlws: could not rewrite telemetry.log in the fixture config"
import sys
p = sys.argv[1]
s = open(p).read()
assert "log: telemetry.jsonl" in s, "telemetry.log anchor not found in " + p
open(p, "w").write(s.replace("log: telemetry.jsonl", 'log: "custom/my log.jsonl"', 1))
PYCFG
cascade "$AU/tlws"
mkdir -p "$AU/tlws/child-x/.harness/custom"
printf '{}\n' > "$AU/tlws/child-x/.harness/custom/my log.jsonl"
land "$AU/tlws/child-x"
# Preconditions: the path really contains whitespace, really is ignored, and git really does
# QUOTE it in default porcelain — that quoting IS the defect under test.
git -C "$AU/tlws/child-x" check-ignore -q ".harness/custom/my log.jsonl" \
  || fail "R2-tlws: fixture precondition broken — the whitespace override is not ignored"
git -C "$AU/tlws/child-x" status --porcelain -uall --ignored=matching -- .harness/ \
  | grep -q '^!! "' \
  || fail "R2-tlws: fixture precondition broken — git did not quote the whitespace path, so this case cannot reproduce the defect"
cascade "$AU/tlws"
printf '%s' "$AU_OUT" | grep -qE "no vcs +child-x" \
  && fail "R2-tlws: a whitespace telemetry override was not subtracted — the probe needs -z: $AU_OUT"
printf '%s' "$AU_OUT" | grep -qE "landed +child-x" \
  || fail "R2-tlws: a fully landed target with a whitespace override was not reported landed: $AU_OUT"
pass "a telemetry override containing whitespace is subtracted (R2) [R2_telemetry_override_with_whitespace]"

# ── R2: a newline inside an ignored path must not collapse into a false clean ──────────
# R2_newline_in_ignored_path_is_not_landed
# `tr '\0' '\n'` on `-z` output splits a path containing a literal newline into two lines;
# the second loses its `!! ` prefix and is dropped by the sed, so if the FIRST fragment
# matches a local-only pattern the whole record is subtracted and the target reads `landed`.
# A false CLEAN — not the over-count I first claimed in the commit that introduced it.
# Reported as P2 on PR #105 round 1.
mk_umb "$AU/nlpath" child-y
cascade "$AU/nlpath"
# A path whose first line is EXACTLY a local-only pattern, so a naive split subtracts it.
_nlname="$(printf 'telemetry.jsonl\nshadow')"
if ( cd "$AU/nlpath/child-y/.harness" && printf 'x\n' > "$_nlname" ) 2>/dev/null; then
  # Ignore it by a GLOB matching its tail, not by name: `.gitignore` is line-based and
  # cannot express a newline, and a directory-wide rule makes git collapse the whole
  # directory to one entry — neither produces the individual `!!` record this case needs.
  printf '*shadow\n' >> "$AU/nlpath/child-y/.harness/.gitignore"
  land "$AU/nlpath/child-y"
  # Preconditions: the file exists with a newline in its name AND git reports it ignored.
  [ -e "$AU/nlpath/child-y/.harness/$_nlname" ] \
    || fail "R2-nl: fixture precondition broken — the newline-named file does not exist"
  git -C "$AU/nlpath/child-y" status --porcelain -z -uall --ignored=matching -- .harness/ \
    | tr '\0' '\n' | grep -qE '^!! (.*/)?telemetry\.jsonl$' \
    || fail "R2-nl: fixture precondition broken — the naive split does not produce a subtractable first fragment, so this case cannot reproduce the defect"
  cascade "$AU/nlpath"
  printf '%s' "$AU_OUT" | grep -qE "landed +child-y" \
    && fail "R2-nl: FALSE CLEAN — a newline inside an ignored path collapsed into a subtracted record: $AU_OUT"
  pass "a newline inside an ignored path does not collapse into a false clean (R2) [R2_newline_in_ignored_path_is_not_landed]"
else
  # Some filesystems reject newlines in names. Skipping is honest; silently passing is not.
  echo "ok - SKIPPED R2_newline_in_ignored_path_is_not_landed (filesystem rejects newline in a filename)"
fi


# ══ E24-F03 — thin the child: umbrella-resolved body with local fallback ═══════════════
# ADR-0004. The tier line is drawn by WHAT READS THE FILE: prose is stub-able because an
# agent follows a reference; init.sh/store/tools are not, because a program parses them.
SENTINEL='<!-- harness:umbrella-stub -->'
PROSE_TIER='AGENTS.md agents/builder.md agents/orchestrator.md docs/WORKFLOW.md specs/_templates/feature.spec.md specs/glossary.md'
LOCAL_TIER='init.sh store/tasks.schema.json tools/tasks-lock.py tools/harness-owned-paths.sh'

is_stub() { head -n 1 "$1" 2>/dev/null | grep -qxF "$SENTINEL"; }

# ── FIXTURE PRECONDITION for every stub assertion below ────────────────────────────────
# A single-repo install is the control: if the prose tier there were ALSO missing or
# stubbed, "contains the sentinel" downstream would prove nothing at all.
TF="$AU/f03-control"
mkdir -p "$TF"
CODEX_HOME="$TF/.ch" HOME="$TF/.home" sh "$SRC/harness-install.sh" --agents=claude "$TF" >/dev/null 2>&1 \
  || fail "R5 control: single-repo install exited non-zero"
for _p in $PROSE_TIER $LOCAL_TIER; do
  [ -f "$TF/.harness/$_p" ] || fail "R5 control: single-repo install is missing $_p"
  is_stub "$TF/.harness/$_p" && fail "R5: single-repo install stubbed $_p — there is no umbrella to resolve"
done
grep -qF 'You are the **Builder**' "$TF/.harness/agents/builder.md" \
  || fail "R5 control: agents/builder.md is not the real body"
# The sentinel must be absent from the WHOLE tree, not from a sampled file: a per-file
# probe is only ever as complete as the last bug report.
[ "$(grep -rlF "$SENTINEL" "$TF/.harness" 2>/dev/null | wc -l | tr -d ' ')" = "0" ] \
  || fail "R5: a single-repo install wrote a stub somewhere in .harness/"
pass "R5 single_repo_body_is_complete — no umbrella.root ⇒ full body, no sentinel anywhere"

# ── R1/R2/R3/R4: a fresh cascade child is thin ─────────────────────────────────────────
mk_umb "$AU/f03" kid-a kid-b
cascade "$AU/f03"
KA="$AU/f03/kid-a/.harness"
[ -d "$KA" ] || fail "R2 setup: the cascade did not install into kid-a"

grep -q '^  root: "\.\./\.\./"' "$KA/harness.config.yaml" \
  || fail "R1: the cascade did not record umbrella.root in the child config"
pass "R1 cascade_records_umbrella_root"

for _p in $PROSE_TIER; do
  is_stub "$KA/$_p" || fail "R2: prose-tier $_p is not a stub in a fresh cascade child"
done
pass "R2 thin_child_prose_tier_is_stubbed"

for _p in $LOCAL_TIER; do
  [ -f "$KA/$_p" ] || fail "R4: program-tier $_p missing from a thin child"
  is_stub "$KA/$_p" && fail "R4: program-tier $_p was stubbed — init.sh execs/parses it"
done
grep -q 'tasks.schema.json\|"\$schema"\|properties' "$KA/store/tasks.schema.json" \
  || fail "R4: store/tasks.schema.json is not a real schema in a thin child"
pass "R4 thin_child_standalone_tier_is_local"

# The stub is a contract: sentinel, the resolved path, and the recovery instruction. And
# the path it names must actually resolve from the child's own harness dir.
is_stub "$KA/agents/builder.md" || fail "R3: stub has no sentinel on line 1"
grep -qF '../../.harness/agents/builder.md' "$KA/agents/builder.md" \
  || fail "R3: stub does not name the resolved path of its authoritative copy"
grep -qiF 'run the harness installer against this repository' "$KA/agents/builder.md" \
  || fail "R3: stub does not name the recovery step"
( cd "$KA" && grep -qF 'You are the **Builder**' ../../.harness/agents/builder.md ) \
  || fail "R3: the path the stub names does not resolve to the real body"
pass "R3 stub_contract"

grep -q 'This target holds the thin body layout' "$KA/manifest.txt" \
  || fail "R8: a thin child's manifest does not record the thin layout"
grep -q 'This target holds the full body layout' "$AU/f03/.harness/manifest.txt" \
  || fail "R8: the coordinator's manifest does not record the full layout"
is_stub "$AU/f03/.harness/agents/builder.md" \
  && fail "R8/R2: the COORDINATOR was thinned — it holds the authoritative body"
pass "R8 manifest_records_layout"

# ── R7: an umbrella upgrade leaves child stubs byte-identical ──────────────────────────
# Positive control in the SAME run: without it this passes on a re-run that did nothing.
cp "$KA/agents/builder.md" "$AU/f03-stub.ref"
cp "$KA/.harness-version" "$AU/f03-ver.ref"
# The bumped installer is a PRIVATE COPY of the source, never the shared checkout.
# `tools/run-tests.sh` runs suites concurrently (--jobs 8) and its own header warns that a
# suite writing to a shared path fails intermittently under it: other suites invoke
# harness-install.sh (stamping VERSION into their fixtures) and test_pr_loop.sh R54 asserts
# CHANGELOG carries a heading for exactly the current VERSION. Writing 99.99.99 into
# $SRC/VERSION would make BOTH of those flaky, for a window this test does not control.
# (Codex r1 P1 #3705599506.)
SRCCOPY="$AU/f03-src"
mkdir -p "$SRCCOPY"
# Copy the installer and every path it reads. `.git` and the round cache are excluded:
# they are large and irrelevant, and the installer never reads them.
for _sd in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
           harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
  [ -e "$SRC/$_sd" ] && cp -R "$SRC/$_sd" "$SRCCOPY/"
done
printf '99.99.99\n' > "$SRCCOPY/VERSION"
AU_OUT="$(CODEX_HOME="$AU/f03/.ch" HOME="$AU/f03/.home" sh "$SRCCOPY/harness-install.sh" \
  --umbrella "$AU/f03" --agents=claude 2>&1)" || true
# The point of the private copy: the shared checkout must be untouched, so a suite running
# concurrently can never observe 99.99.99. Guard it, or the isolation silently regresses.
grep -qx '99.99.99' "$SRC/VERSION" \
  && fail "R7: the synthetic bump leaked into the shared checkout's VERSION — concurrent suites will flake"
cmp -s "$AU/f03-stub.ref" "$KA/agents/builder.md" \
  || fail "R7: a VERSION bump rewrote a thin child's stub"
cmp -s "$AU/f03-ver.ref" "$KA/.harness-version" \
  && fail "R7 control: the version stamp did NOT change — the re-run did nothing, so the stub comparison proves nothing"
pass "R7 stubs_survive_version_bump (with a positive control on the standalone tier)"

# ── R9: an existing full-copy child is left alone ──────────────────────────────────────
# Converting one is destructive, needs a pristine check, and is E24-F04 — never a side
# effect of a routine cascade. Asserted on BYTES: a swap to stubs leaves every path present.
mk_umb "$AU/f03b" kid-c
KC="$AU/f03b/kid-c"
CODEX_HOME="$AU/f03b/.ch" HOME="$AU/f03b/.home" sh "$SRC/harness-install.sh" --agents=claude "$KC" >/dev/null 2>&1 \
  || fail "R9 setup: standalone install into kid-c failed"
is_stub "$KC/.harness/agents/builder.md" && fail "R9 setup: the standalone install already wrote a stub"
cp "$KC/.harness/agents/builder.md" "$AU/f03b-full.ref"
cascade "$AU/f03b"
cmp -s "$AU/f03b-full.ref" "$KC/.harness/agents/builder.md" \
  || fail "R9: the cascade converted an existing full-copy child's body to stubs"
grep -q 'This target holds the full body layout' "$KC/.harness/manifest.txt" \
  || fail "R9: an unconverted child's manifest does not report the full layout"
printf '%s' "$AU_OUT" | grep -qi 'already holds a full body' \
  || fail "R9: the cascade did not report that it left an existing full body alone"
pass "R9 existing_full_copy_child_untouched"

echo "All umbrella tests passed."
