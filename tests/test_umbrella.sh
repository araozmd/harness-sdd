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
# `chmod -R u+w` before the sweep: the R2 shape fixture deliberately creates a 0555
# directory holding a 0444 file, and `rm -rf` cannot unlink through it. Without this the
# suite leaves temp trees behind and prints permission errors from the trap.
trap 'chmod -R u+w "$AU" 2>/dev/null; rm -rf "$AU"' EXIT

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
# No file ANYWHERE in the tree may be a stub — a per-file probe is only ever as complete
# as the last bug report. The predicate is "line 1 IS the sentinel", not "contains it":
# `init.sh` legitimately carries the literal string in its own layout detection, and a
# substring scan reads that as a stub. Being a stub was always a line-1 property; the
# loose form only looked equivalent until init.sh learned to detect one.
_f03_stubs=0
for _f in $(find "$TF/.harness" -type f); do
  is_stub "$_f" && { echo "   unexpected stub: $_f" >&2; _f03_stubs=$((_f03_stubs + 1)); }
done
[ "$_f03_stubs" = "0" ] \
  || fail "R5: a single-repo install wrote $_f03_stubs stub(s) in .harness/"
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
grep -qiF 'run the harness installer against this repository with `--standalone`' "$KA/agents/builder.md" \
  || fail "R3: stub does not name the recovery step WITH the flag that performs it — an unflagged re-install of a thin child is maintained thin, so the bare instruction cannot materialise the full local copy it promises"
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

# ── R2 (shape fidelity): nested dirs and dotfiles inside a prose tier are mirrored ─────
# The thin layout must produce the same SHAPE as `cp -R` does on the full path. An
# immediate-files-only loop silently drops any nested subtree a prose directory grows
# later — the child ends up missing a file the full install has, with no error anywhere.
# Fixtures go in a PRIVATE source copy so the shared checkout is never mutated.
# (Codex r2 P2 #3705758419.)
SC2="$AU/f03-shape-src"
mkdir -p "$SC2"
for _sd in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
           harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
  [ -e "$SRC/$_sd" ] && cp -R "$SRC/$_sd" "$SC2/"
done
mkdir -p "$SC2/docs/nested/deeper"
echo "nested body" > "$SC2/docs/nested/deep.md"
echo "deeper body" > "$SC2/docs/nested/deeper/x.md"
echo "hidden body" > "$SC2/agents/.hidden.md"
# `zzz.md` sorts AFTER the nested directory ON PURPOSE. POSIX sh has no locals, so a
# recursion that clobbers its parent's frame writes every sibling processed after a nested
# directory beneath it — `docs/zzz.md` became `docs/aaa/zzz.md` and vanished from its own
# path. A fixture whose only nested dir sorts last cannot see that. (Codex r4 P2 #3705960408.)
echo "sibling body" > "$SC2/docs/zzz.md"
# Dotfile NAME SHAPES are a matrix, not one case: `*` skips every dot name, `.[!.]*` skips
# every `..name`, and `.??*` skips every two-character dot name. Each pattern alone leaves a
# file that `cp -R` copies and the thin child drops. `..dd/` is a DIRECTORY on purpose — an
# unmatched dir is never recursed into, so its whole subtree vanishes, not just one entry.
# `.q` is the two-character case that fails the moment `.[!.]*` is "simplified" to `.??*`.
# (Codex r5 P2 #3706053982.)
echo "dotdot body" > "$SC2/docs/..draft.md"
mkdir -p "$SC2/docs/..dd"
echo "dotdot dir body" > "$SC2/docs/..dd/inner.md"
echo "short dot body" > "$SC2/docs/.q"
# SYMLINKS. `cp -R` preserves a link as a link, so the thin child must too. A walk that
# tests `[ -d ]` before `[ -L ]` dereferences instead and descends: `docs/self -> .`
# expanded into `docs/self/self/...` up to the OS resolution limit — 264 entries under the
# child's docs/ against 8 in a control — and the cascade still reported its ordinary
# status, so nothing surfaced the corruption. `dangling` is here because a broken link is
# the case where `[ -e ]` is false while `[ -L ]` is true. (Codex r6 P2 #3710311338.)
ln -s . "$SC2/docs/self"
ln -s nested "$SC2/docs/link-to-dir"
ln -s zzz.md "$SC2/docs/link-to-file"
ln -s no-such-target "$SC2/docs/dangling"
# READ-ONLY MODES. `cp -R` carries the source's modes across, so a 0555 directory holding a
# 0444 file arrives in the child unwritable and the thinning cannot overwrite it — the child
# kept `SECRET REAL BODY` while the cascade printed `install complete`. Note this is a
# regression the copy-then-thin inversion INTRODUCED: the earlier source-walk built the
# destination fresh and so never reproduced these modes. Verified by running this very
# fixture against both implementations. (Codex r7 P2 #3711176789.)
mkdir -p "$SC2/docs/rodir"
echo "SECRET REAL BODY" > "$SC2/docs/rodir/locked.md"
chmod 0444 "$SC2/docs/rodir/locked.md"
chmod 0555 "$SC2/docs/rodir"
mk_umb "$AU/f03c" kid-d
AU_OUT="$(CODEX_HOME="$AU/f03c/.ch" HOME="$AU/f03c/.home" sh "$SC2/harness-install.sh" \
  --umbrella "$AU/f03c" --agents=claude 2>&1)" || true
KD="$AU/f03c/kid-d/.harness"
# Precondition: this really is a thin child, or "the nested file is a stub" is vacuous.
is_stub "$KD/AGENTS.md" || fail "R2-shape setup: the child is not thin"
for _p in docs/nested/deep.md docs/nested/deeper/x.md agents/.hidden.md docs/zzz.md \
          docs/..draft.md docs/..dd/inner.md docs/.q docs/rodir/locked.md; do
  [ -f "$KD/$_p" ] || fail "R2-shape: $_p is missing from a thin child but present in a full install"
  is_stub "$KD/$_p" || fail "R2-shape: $_p was mirrored but is not a stub"
done
# ...and it must not have been written INSIDE the nested directory instead.
[ -e "$KD/docs/nested/zzz.md" ] \
  && fail "R2-shape: a sibling after a nested dir was written beneath it — recursion clobbered the parent frame"
grep -qF '../../.harness/docs/nested/deeper/x.md' "$KD/docs/nested/deeper/x.md" \
  || fail "R2-shape: a nested stub does not name its own resolved path"
# Every symlink survives AS A LINK, pointing where it pointed — never stubbed (the write
# would land on the target) and never descended into.
for _l in self:. link-to-dir:nested link-to-file:zzz.md dangling:no-such-target; do
  _ln="${_l%%:*}"; _lt="${_l#*:}"
  [ -L "$KD/docs/$_ln" ] \
    || fail "R2-shape: docs/$_ln is not a symlink in the thin child — cp -R keeps it one"
  [ "$(readlink "$KD/docs/$_ln")" = "$_lt" ] \
    || fail "R2-shape: docs/$_ln points at '$(readlink "$KD/docs/$_ln")', want '$_lt'"
done
# `is_stub docs/link-to-file` is deliberately NOT asserted either way: it reads THROUGH the
# link to `zzz.md`, which is itself correctly stubbed, so it is true for a reason that has
# nothing to do with the link. `dangling` is the clean probe instead — had the stub write
# followed it, its target would have been created.
[ -e "$KD/docs/no-such-target" ] \
  && fail "R2-shape: stubbing followed docs/dangling and created its target"
# The runaway CANNOT be probed by path existence. `[ -e docs/self/self ]` is true on a
# perfectly correct tree — and so is `docs/self/self/self/self` — because `-e` resolves the
# path THROUGH the preserved link. Verified against a directory holding exactly one link and
# one file. The honest probes are the two below, which use `find`: it does not follow
# symlinks, so it reports the tree as stored rather than as traversable.
_thin_n="$(find "$KD/docs" | wc -l | tr -d ' ')"
# The control: the SAME source, installed standalone, keeps those files as real bodies —
# which is what makes "missing from the thin child" a divergence rather than a source quirk.
mkdir -p "$AU/f03c-full"   # the installer requires an EXISTING target directory
CODEX_HOME="$AU/f03c/.ch2" HOME="$AU/f03c/.home2" sh "$SC2/harness-install.sh" \
  --agents=claude "$AU/f03c-full" >/dev/null 2>&1 || fail "R2-shape control: standalone install failed"
grep -qF 'deeper body' "$AU/f03c-full/.harness/docs/nested/deeper/x.md" \
  || fail "R2-shape control: the full install did not preserve the nested file either"
# Same control for each dot-name shape. Without this, "the thin child has docs/..draft.md"
# could be satisfied by a source that never had it — and the divergence it exists to catch
# is defined against what the FULL install produces, so the full side must be asserted too.
for _c in '..draft.md:dotdot body' '..dd/inner.md:dotdot dir body' '.q:short dot body'; do
  _cp="${_c%%:*}"; _cb="${_c#*:}"
  grep -qF "$_cb" "$AU/f03c-full/.harness/docs/$_cp" \
    || fail "R2-shape control: the full install did not preserve docs/$_cp — the thin-child assertion for it proves nothing"
done
# The read-only file's REAL CONTENT must appear nowhere in the thin child — the symptom of
# the silent-thinning bug was the body surviving, not the stub being absent. Stated over the
# whole tree rather than one path, since a partially-thinned child is the actual hazard.
grep -rqF 'SECRET REAL BODY' "$KD" \
  && fail "R2-shape: real body content survived into a thin child — thinning failed silently"
# ...and the full install MUST still contain it, or the grep above passes vacuously.
grep -qF 'SECRET REAL BODY' "$AU/f03c-full/.harness/docs/rodir/locked.md" \
  || fail "R2-shape control: the full install did not keep the read-only file's body — the absence assertion above proves nothing"
# Symlink control: the full path keeps these as links, which is what makes "the thin child
# keeps them as links" a fidelity claim rather than an arbitrary choice.
for _l in self:. link-to-dir:nested link-to-file:zzz.md dangling:no-such-target; do
  _ln="${_l%%:*}"; _lt="${_l#*:}"
  [ -L "$AU/f03c-full/.harness/docs/$_ln" ] \
    || fail "R2-shape control: the full install did not keep docs/$_ln a symlink — the thin-child link assertion proves nothing"
  [ "$(readlink "$AU/f03c-full/.harness/docs/$_ln")" = "$_lt" ] \
    || fail "R2-shape control: the full install's docs/$_ln points somewhere unexpected"
done
# THE WHOLE REQUIREMENT, stated once: thin and full must contain the SAME SET OF PATHS.
# Every individual assertion above is a sample of this; the set comparison is the property
# itself, and it catches shapes nobody thought to enumerate — which is exactly how this
# function accumulated four blocking findings. `find` does not follow symlinks, so a
# self-referencing link cannot loop here.
( cd "$KD" && find docs | sort ) > "$AU/f03c-thin.paths"
( cd "$AU/f03c-full/.harness" && find docs | sort ) > "$AU/f03c-full.paths"
diff "$AU/f03c-full.paths" "$AU/f03c-thin.paths" >/dev/null \
  || fail "R2-shape: thin and full installs disagree on docs/ paths:
$(diff "$AU/f03c-full.paths" "$AU/f03c-thin.paths" | head -20)"
# Precondition on that comparison: it is only meaningful if the fixture actually reached
# both installs. An empty-vs-empty diff would pass while proving nothing.
[ "$_thin_n" -ge 12 ] \
  || fail "R2-shape: only $_thin_n entries under the thin child's docs/ — the fixture did not land, so the path-set comparison is vacuous"
pass "R2 nested dirs, dot-name shapes and symlinks keep their shape in a thin child"

# ── R1/R2: a SYMLINKED child resolves its umbrella too ─────────────────────────────────
# The cascade deliberately accepts a symlinked child. `..` from such a child's .harness/ is
# resolved by the kernel against the LINK TARGET, so a hard-coded `../../` lands outside the
# umbrella: the child installed a full body AND persisted an unreachable umbrella.root.
# The value is derived from the physical path, with the absolute umbrella as the fallback.
# (Codex r3 P2 #3705849222.)
ELS="$AU/f03d-elsewhere"
mkdir -p "$ELS/realrepo" "$AU/f03d"
git -C "$ELS/realrepo" init -q .
git -C "$ELS/realrepo" config user.email "test@harness.local"
git -C "$ELS/realrepo" config user.name  "harness test"
echo seed > "$ELS/realrepo/README.md"
git -C "$ELS/realrepo" add -A
git -C "$ELS/realrepo" commit -q -m init
ln -s "$ELS/realrepo" "$AU/f03d/kid-link"
# A real sibling in the SAME umbrella, so the relative form is asserted in the same run —
# a fix that switched everything to absolute paths would pass the symlink case alone.
mk_umb "$AU/f03d" kid-real
cascade "$AU/f03d"
is_stub "$ELS/realrepo/.harness/AGENTS.md" \
  || fail "R2-symlink: a symlinked child got a full body — its umbrella.root did not resolve"
_symroot="$(sed -n 's/^  root: "\(.*\)"$/\1/p' "$ELS/realrepo/.harness/harness.config.yaml")"
[ -n "$_symroot" ] || fail "R1-symlink: no umbrella.root recorded for the symlinked child"
[ -f "$_symroot/.harness/.harness-version" ] \
  || fail "R1-symlink: the recorded umbrella.root ($_symroot) does not resolve to an installed body"
grep -q '^  root: "\.\./\.\./"' "$AU/f03d/kid-real/.harness/harness.config.yaml" \
  || fail "R1-symlink: an ORDINARY child stopped getting the relative form"
is_stub "$AU/f03d/kid-real/.harness/AGENTS.md" \
  || fail "R2-symlink: the ordinary sibling stopped being thinned"
pass "R1/R2 a symlinked child resolves its umbrella; an ordinary sibling keeps the relative form"

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

# ══ E99-F13 — a `#` inside a QUOTED umbrella.root is data, not a comment ═══════════════
# `set_umbrella_root` writes this value double-quoted, every time. Both readers stripped
# `#.*$` BEFORE stripping quotes, so `root: "/tmp/umb#root"` parsed as `/tmp/umb` — the
# harness truncating a value it had produced itself. Split out of PR #109 round 7.
#
# Exercised END-TO-END through both real readers, never by re-running a copy of the awk
# here: a parser reimplemented in this file would agree with itself and prove nothing.
#   installer  `_cfg_umbrella_root_value`  — reached by a STANDALONE re-run, the only path
#                                            that reads the config instead of the env var.
#   init.sh    the inline awk               — reached by its umbrella report.
#
# The value under test is never hand-written: the cascade derives and records it. A
# SYMLINKED child is used because that is the layout whose recorded root is ABSOLUTE —
# the relative `../../` an ordinary child gets cannot carry the umbrella path at all.
# BOTH metacharacters in ONE fixture, because the first fix traded one for the other:
# matching to the FIRST closing quote kept the `#` and truncated `/tmp/a"b` to `/tmp/a`
# (Codex #3712741520). A fixture carrying only `#` cannot tell those two apart.
F13E="$AU/f13-elsewhere"
F13U="$AU/f13#hash\"q"              # `#` AND `"` land verbatim in the recorded root
mkdir -p "$F13E/realrepo"
git -C "$F13E/realrepo" init -q .
git -C "$F13E/realrepo" config user.email "test@harness.local"
git -C "$F13E/realrepo" config user.name  "harness test"
echo seed > "$F13E/realrepo/README.md"
git -C "$F13E/realrepo" add -A
git -C "$F13E/realrepo" commit -q -m init
mk_umb "$F13U"
ln -s "$F13E/realrepo" "$F13U/kid-link"
cascade "$F13U"
F13H="$F13E/realrepo/.harness"

# ── FIXTURE PRECONDITIONS ──────────────────────────────────────────────────────────────
# Each one guards an assertion below against passing vacuously.
[ -d "$F13H" ] || fail "E99-F13 setup: the cascade did not install into the symlinked child: $AU_OUT"
F13ROOT="$(sed -n 's/^  root: "\(.*\)"$/\1/p' "$F13H/harness.config.yaml")"
case "$F13ROOT" in
  *'#'*) ;;
  *) fail "E99-F13 precondition: the recorded umbrella.root [$F13ROOT] carries no '#', so nothing below exercises the comment truncation" ;;
esac
case "$F13ROOT" in
  *'"'*) ;;
  *) fail "E99-F13 precondition: the recorded umbrella.root [$F13ROOT] carries no '\"', so nothing below exercises the closing-quote truncation" ;;
esac
[ -f "$F13ROOT/.harness/.harness-version" ] \
  || fail "E99-F13 precondition: the recorded root [$F13ROOT] does not resolve to an installed umbrella body"
is_stub "$F13H/agents/builder.md" \
  || fail "E99-F13 precondition: the cascade left the symlinked child full-copy — the stub assertions below would be vacuous"

# ── READER A: the installer, via a standalone re-run (no HARNESS_UMBRELLA_ROOT) ────────
F13RERUN="$(CODEX_HOME="$AU/f13.ch" HOME="$AU/f13.home" sh "$SRC/harness-install.sh" --agents=claude "$F13E/realrepo" 2>&1)" || true
is_stub "$F13H/agents/builder.md" \
  || fail "E99-F13/installer: a standalone re-run replaced the child's stubs with a full body — _cfg_umbrella_root_value truncated the recorded root at its '#': $F13RERUN"
F13_INST="$(printf '%s\n' "$F13RERUN" | sed -n 's/.*prose body resolved from the umbrella at \(.*\) (stubs.*/\1/p')"
[ "$F13_INST" = "$F13ROOT" ] \
  || fail "E99-F13/installer: reported the umbrella root as [$F13_INST], want [$F13ROOT]: $F13RERUN"

# POSITIVE CONTROL for the assertion above, on a copy of the SAME child: an unresolvable
# root really does make a standalone re-run replace the stubs. Without this, "still a stub"
# would pass even if a re-run could never convert anything, whatever the parser did.
F13C="$AU/f13-control"
cp -R "$F13E/realrepo" "$F13C"
sed 's|^  root: .*|  root: "/nonexistent/umbrella#gone"|' "$F13C/.harness/harness.config.yaml" > "$F13C/.harness/hc.t" \
  && mv "$F13C/.harness/hc.t" "$F13C/.harness/harness.config.yaml"
CODEX_HOME="$AU/f13c.ch" HOME="$AU/f13c.home" sh "$SRC/harness-install.sh" --agents=claude "$F13C" >/dev/null 2>&1 || true
if is_stub "$F13C/.harness/agents/builder.md"; then
  fail "E99-F13 control: a re-run with an UNRESOLVABLE umbrella.root left the stubs in place — the installer assertion above cannot detect the truncation it targets"
fi

# ── READER B: init.sh, via its umbrella report ─────────────────────────────────────────
# `./init.sh`, never `sh ./init.sh`: it declares `#!/usr/bin/env bash` and uses
# `set -o pipefail`, which dash (Ubuntu CI /bin/sh) rejects at line 8.
F13_INIT_OUT="$(cd "$F13H" && ./init.sh 2>&1)" \
  || fail "E99-F13/init.sh: exited non-zero in the thin child: $F13_INIT_OUT"
if printf '%s' "$F13_INIT_OUT" | grep -q 'is not reachable'; then
  fail "E99-F13/init.sh: reported the umbrella unreachable — the recorded root was truncated at its '#': $F13_INIT_OUT"
fi
F13_INIT="$(printf '%s\n' "$F13_INIT_OUT" | sed -n 's/.*harness body resolves from the umbrella at \(.*\) (prose tier is stubs).*/\1/p')"
[ "$F13_INIT" = "$F13ROOT" ] \
  || fail "E99-F13/init.sh: reported the umbrella root as [$F13_INIT], want [$F13ROOT]: $F13_INIT_OUT"

# ── The two readers are duplicated on purpose; pin that they stay identical ────────────
# They have drifted apart once already by being edited separately.
[ "$F13_INST" = "$F13_INIT" ] \
  || fail "E99-F13: the two readers disagree on the SAME config — installer [$F13_INST] vs init.sh [$F13_INIT]"
pass "E99-F13 quoted_umbrella_root_keeps_metachars — both readers round-trip '#' AND '\"' in the recorded root"

# ── A QUOTED value with a TRAILING COMMENT keeps the `#` inside the quotes ─────────────
# Codex #3712898952. The machine never writes this form, so the value is hand-written onto
# a copy of the thin child — but it is pointed at the SAME resolvable umbrella, so both
# readers stay observable exactly as above rather than degrading to an unreachable message.
# Rewritten with awk, not sed: the replacement carries `#` and `"`.
F13T="$AU/f13-quoted-comment"
cp -R "$F13E/realrepo" "$F13T"
awk -v r="$F13ROOT" '/^  root: /{ print "  root: \"" r "\"   # a hand-written trailing comment"; next } { print }' \
  "$F13T/.harness/harness.config.yaml" > "$F13T/.harness/hc.t" \
  && mv "$F13T/.harness/hc.t" "$F13T/.harness/harness.config.yaml"
grep -q '# a hand-written trailing comment' "$F13T/.harness/harness.config.yaml" \
  || fail "E99-F13/quoted+comment precondition: the trailing comment was never written into the config"

F13T_RERUN="$(CODEX_HOME="$AU/f13t.ch" HOME="$AU/f13t.home" sh "$SRC/harness-install.sh" --agents=claude "$F13T" 2>&1)" || true
is_stub "$F13T/.harness/agents/builder.md" \
  || fail "E99-F13/quoted+comment installer: the re-run replaced the stubs — the trailing comment truncated the value at the '#' INSIDE the quotes: $F13T_RERUN"
F13T_INST="$(printf '%s\n' "$F13T_RERUN" | sed -n 's/.*prose body resolved from the umbrella at \(.*\) (stubs.*/\1/p')"
[ "$F13T_INST" = "$F13ROOT" ] \
  || fail "E99-F13/quoted+comment installer: reported [$F13T_INST], want [$F13ROOT]: $F13T_RERUN"

F13T_OUT="$(cd "$F13T/.harness" && ./init.sh 2>&1)" \
  || fail "E99-F13/quoted+comment init.sh: exited non-zero: $F13T_OUT"
F13T_INIT="$(printf '%s\n' "$F13T_OUT" | sed -n 's/.*harness body resolves from the umbrella at \(.*\) (prose tier is stubs).*/\1/p')"
[ "$F13T_INIT" = "$F13ROOT" ] \
  || fail "E99-F13/quoted+comment init.sh: reported [$F13T_INIT], want [$F13ROOT]: $F13T_OUT"
pass "E99-F13 quoted_root_with_trailing_comment — both readers keep the '#' inside the quotes"

# ── A comment containing BOTH `#` and `"` must not extend the value ────────────────────
# This pins the direction of the reader's second pass, which is load-bearing: on
# `root: "<v>" # a " # b` more than one quote qualifies as the closing one, and taking the
# LAST swallows ` # a ` into the value. Read through init.sh's UNREACHABLE message, which
# prints the parsed root verbatim and needs no resolvable path.
#
# Direction in the FIRST pass needs no test: a quote whose remainder is whitespace-only is
# unique by construction, since any earlier candidate has a quote in its remainder.
F13D="$AU/f13-comment-direction"
cp -R "$F13E/realrepo" "$F13D"
awk '/^  root: /{ print "  root: \"/nonexistent/keep#me\" # a \" # b"; next } { print }' \
  "$F13D/.harness/harness.config.yaml" > "$F13D/.harness/hc.t" \
  && mv "$F13D/.harness/hc.t" "$F13D/.harness/harness.config.yaml"
grep -qF 'root: "/nonexistent/keep#me" # a " # b' "$F13D/.harness/harness.config.yaml" \
  || fail "E99-F13/comment-direction precondition: the fixture line was not written as intended"
F13D_OUT="$(cd "$F13D/.harness" && ./init.sh 2>&1)" \
  || fail "E99-F13/comment-direction: init.sh exited non-zero: $F13D_OUT"
printf '%s' "$F13D_OUT" | grep -qF 'umbrella at /nonexistent/keep#me is not reachable' \
  || fail "E99-F13/comment-direction: a quote inside the comment was taken as the closing quote, extending the value: $F13D_OUT"
pass "E99-F13 comment_containing_a_quote_does_not_extend_the_value"

# ── An UNQUOTED value must still honour a trailing ` # comment` ────────────────────────
# The quoted-scalar branch must not have taken that path over, or a hand-edited config
# breaks. Read through init.sh's UNREACHABLE message, which also prints the parsed root —
# so this pins the unquoted branch without needing a second resolvable umbrella.
F13Q="$AU/f13-unquoted"
cp -R "$F13E/realrepo" "$F13Q"
sed 's|^  root: .*|  root: /nonexistent/plain   # a hand-written trailing comment|' \
  "$F13Q/.harness/harness.config.yaml" > "$F13Q/.harness/hc.t" \
  && mv "$F13Q/.harness/hc.t" "$F13Q/.harness/harness.config.yaml"
F13Q_OUT="$(cd "$F13Q/.harness" && ./init.sh 2>&1)" \
  || fail "E99-F13/unquoted: init.sh exited non-zero: $F13Q_OUT"
printf '%s' "$F13Q_OUT" | grep -qF 'umbrella at /nonexistent/plain is not reachable' \
  || fail "E99-F13/unquoted: an unquoted root stopped honouring its trailing comment: $F13Q_OUT"
pass "E99-F13 unquoted_root_still_strips_trailing_comment"

# NOTE ON `2>/dev/null` BELOW: every output assertion here is `printf … | grep -q …`, and
# `grep -q` exits at the first match while `printf` is still writing — which makes bash emit
# `printf: write error: Broken pipe` on the suite's stderr. The redirect silences exactly
# that; `printf`'s only other failure mode here would be the same EPIPE.
# ══ E24-F04 — migrate existing children to the thin layout (+ --standalone) ════════════
# The DESTRUCTIVE half of ADR-0004: replacing a prose tier with pointer stubs in a repo
# that already exists. Every case below builds a REAL full-copy child of a REAL reachable
# umbrella and reads what the installer did to it on disk.
#
# The whole prose tier, swept — never sampled. R2's claim is about the paths the operator
# did NOT edit, so "no path in the tier became a stub" has to be a sweep of the tree.
F04_TIER='AGENTS.md agents docs specs/_templates specs/glossary.md'

# f04_no_stub_in_tier <harness-dir> <context> — fail if ANY file under the prose tier is a
# stub. The predicate is "line 1 IS the sentinel" (is_stub), matching E24-F03's control.
f04_no_stub_in_tier() {
  _fn_h="$1"; _fn_ctx="$2"; _fn_n=0
  for _fn_rel in $F04_TIER; do
    [ -e "$_fn_h/$_fn_rel" ] || fail "$_fn_ctx: prose-tier path $_fn_rel is missing entirely"
    for _fn_f in $(find "$_fn_h/$_fn_rel" -type f); do
      is_stub "$_fn_f" && { echo "   unexpected stub: $_fn_f" >&2; _fn_n=$((_fn_n + 1)); }
    done
  done
  [ "$_fn_n" = "0" ] || fail "$_fn_ctx: $_fn_n prose-tier path(s) were converted to stubs"
}

# f04_all_stubs_in_tier <harness-dir> <context> — the converse sweep.
f04_all_stubs_in_tier() {
  _fa_h="$1"; _fa_ctx="$2"; _fa_n=0
  for _fa_rel in $F04_TIER; do
    [ -e "$_fa_h/$_fa_rel" ] || fail "$_fa_ctx: prose-tier path $_fa_rel is missing entirely"
    for _fa_f in $(find "$_fa_h/$_fa_rel" -type f); do
      is_stub "$_fa_f" || { echo "   not a stub: $_fa_f" >&2; _fa_n=$((_fa_n + 1)); }
    done
  done
  [ "$_fa_n" = "0" ] || fail "$_fa_ctx: $_fa_n prose-tier path(s) are still full body files"
}

# f04_phys <dir> — the PHYSICAL path of <dir>. The cascade resolves the umbrella with
# `pwd -P` before installing, so every path it prints is physical while `mktemp -d` hands
# this suite the symlinked form (/var/... vs /private/var/... on macOS). Matching the
# logical path against the installer's output silently matches nothing.
f04_phys() { ( CDPATH= cd -- "$1" && pwd -P ); }

# f04_seg <output> <target-path> — the slice of a cascade's output belonging to ONE target,
# from that target's `harness install … → <path>` banner up to the next banner.
#
# WITHOUT THIS, a per-child assertion in a multi-child cascade is satisfied by ANY child's
# line: "the preview line is present" would pass while it was printed for the wrong repo.
# The leading space in the match is what keeps `…/kid` from matching `…/freshkid`.
f04_seg() {
  _fs_t="$(f04_phys "$2")"
  printf '%s\n' 2>/dev/null "$1" | awk -v t=" $_fs_t" '
    index($0, "harness install v") > 0 { k = (index($0, t) > 0); next }
    k
  '
}

# f04_fullchild <umbrella-dir> <child> — a FULL-COPY child of a REACHABLE umbrella, built
# the way the product builds one:
#   1. SINGLE-TARGET FIRST — no umbrella.root is ever written, so the child gets the
#      complete local body.
#   2. THEN the cascade — which records umbrella.root and, per E24-F03 R9, leaves the full
#      body alone.
#
# DO NOT INVERT THOSE TWO STEPS. Cascading first and re-installing single-target does NOT
# produce a full-copy child: umbrella_body_dir prefers HARNESS_UMBRELLA_ROOT but falls back
# to the CHILD'S OWN config, which §2a has already persisted — so the single-target run
# resolves the umbrella and re-stubs. And "fixing" that by hand-editing the child's config
# replaces the product's own state machine with a fixture.
f04_fullchild() {
  _fc_u="$1"; _fc_c="$2"
  mk_umb "$_fc_u" "$_fc_c"
  CODEX_HOME="$_fc_u/.ch" HOME="$_fc_u/.home" \
    sh "$SRC/harness-install.sh" --agents=claude "$_fc_u/$_fc_c" >/dev/null 2>&1 \
    || fail "F04 fixture: single-target install into $_fc_u/$_fc_c failed"
  cascade "$_fc_u"
  # PRECONDITION, re-asserted on every fixture: a conversion test whose fixture was never
  # full-copy proves nothing at all.
  f04_no_stub_in_tier "$_fc_u/$_fc_c/.harness" "F04 fixture ($_fc_c)"
  grep -qF 'You are the **Builder**' "$_fc_u/$_fc_c/.harness/agents/builder.md" \
    || fail "F04 fixture: $_fc_c/.harness/agents/builder.md is not the real body"
  grep -q '^  root: "\.\./\.\./"' "$_fc_u/$_fc_c/.harness/harness.config.yaml" \
    || fail "F04 fixture: umbrella.root was not recorded on $_fc_c"
  [ -f "$_fc_u/.harness/.harness-version" ] \
    || fail "F04 fixture: the umbrella body under $_fc_u is not installed"
}

# ── R1: --thin converts a pristine full-copy child ─────────────────────────────────────
# thin_converts_pristine_child / converted_equals_fresh_thin / thin_leaves_coordinator_full
F04A="$AU/f04a"
f04_fullchild "$F04A" kid
# A never-installed sibling in the SAME umbrella: the fresh-thin CONTROL R1's equality claim
# is measured against. "Contains the sentinel" is satisfiable by a body that was never
# written; "identical to what a fresh thin install produces" is not — and it is the
# requirement.
mk_umb "$F04A" freshkid
cascade "$F04A" --thin
KID="$F04A/kid/.harness"
FRESH="$F04A/freshkid/.harness"

f04_all_stubs_in_tier "$KID" "R1"
for _p in $LOCAL_TIER; do
  [ -f "$KID/$_p" ] || fail "R1: program-tier $_p vanished from the converted child"
  is_stub "$KID/$_p" && fail "R1: the conversion stubbed program-tier $_p — init.sh parses it"
done
printf '%s' 2>/dev/null "$(f04_seg "$AU_OUT" "$F04A/kid")" | grep -q 'CONVERTED to the thin layout' \
  || fail "R1: the converted child's own output slice never reported the conversion: $AU_OUT"
pass "R1 thin_converts_pristine_child — --thin converts a pristine full-copy child's whole prose tier"

for _p in $F04_TIER; do
  diff -r "$KID/$_p" "$FRESH/$_p" >/dev/null 2>&1 \
    || fail "R1: converted $_p differs from a FRESHLY cascaded thin child's — a converted child must be byte-indistinguishable from a fresh one"
done
# Control: the two children really are distinct installs, so the comparison is not a path
# compared with itself.
[ "$KID" != "$FRESH" ] || fail "R1 control: the fixture compared one child with itself"
is_stub "$FRESH/agents/builder.md" \
  || fail "R1 control: the fresh-thin comparand is not thin — the equality assertion is vacuous"
pass "R1 converted_equals_fresh_thin — the converted tier is byte-identical to a fresh thin child's"

f04_no_stub_in_tier "$F04A/.harness" "R1 coordinator"
grep -q 'This target holds the full body layout' "$F04A/.harness/manifest.txt" \
  || fail "R1: the coordinator's manifest stopped reporting the full layout under --thin"
pass "R1 thin_leaves_coordinator_full — --thin never converts the coordinator"

grep -q 'This target holds the thin body layout' "$KID/manifest.txt" \
  || fail "R8: a converted child's manifest does not record the thin layout"
pass "R8 converted_manifest_says_thin"

# ── R5: an already-thin child stays thin with NO flag ──────────────────────────────────
# thin_maintained_without_flag — the regression lock on E24-F03's maintenance branch. It
# fails loudly if --thin is implemented by gating that branch behind the flag.
cp "$KID/agents/builder.md" "$AU/f04a-stub.ref"
cascade "$F04A"
printf '%s\n' 2>/dev/null "$AU_OUT" | grep -F 2>/dev/null "harness install v" | grep -qF "$(f04_phys "$F04A/kid") " \
  || fail "R5 control: the unflagged cascade never ran install_one for the thin child — everything below would prove nothing: $AU_OUT"
f04_all_stubs_in_tier "$KID" "R5"
cmp -s "$AU/f04a-stub.ref" "$KID/agents/builder.md" \
  || fail "R5: an unflagged cascade rewrote an already-thin child's stub"
grep -q 'This target holds the thin body layout' "$KID/manifest.txt" \
  || fail "R5: an unflagged cascade moved an already-thin child out of the thin layout"
pass "R5 thin_maintained_without_flag — an already-thin child stays thin with no flag"

# ── R7: --thin on an already-thin child leaves every prose path byte-identical ──────────
# thin_is_idempotent — asserted on BYTES CAPTURED BEFORE THE RUN, never on "the run said
# nothing changed".
F04AREF="$AU/f04a-tier.ref"
mkdir -p "$F04AREF/specs"
for _p in $F04_TIER; do cp -R "$KID/$_p" "$F04AREF/$_p"; done
cascade "$F04A" --thin
printf '%s\n' 2>/dev/null "$AU_OUT" | grep -F 2>/dev/null "harness install v" | grep -qF "$(f04_phys "$F04A/kid") " \
  || fail "R7 control: the --thin cascade never ran install_one for the thin child: $AU_OUT"
for _p in $F04_TIER; do
  diff -r "$F04AREF/$_p" "$KID/$_p" >/dev/null 2>&1 \
    || fail "R7: --thin against an already-thin child rewrote $_p"
done
pass "R7 thin_is_idempotent — --thin on a thin child leaves every prose path byte-identical"

# ── R2/R3: one edited prose file blocks the WHOLE tier, and every blocker is named ──────
# thin_all_or_nothing_on_edit / thin_names_every_blocker
F04B="$AU/f04b"
f04_fullchild "$F04B" edited
# A PRISTINE sibling in the same umbrella and the same run. Without it, "nothing converted"
# is equally explained by a --thin that does not work at all.
f04_fullchild "$F04B" pristine
printf '\nlocal edit\n' >> "$F04B/edited/.harness/agents/builder.md"
printf '\nlocal edit\n' >> "$F04B/edited/.harness/docs/WORKFLOW.md"
cascade "$F04B" --thin
f04_no_stub_in_tier "$F04B/edited/.harness" "R2 (one edited file must block the WHOLE tier)"
grep -q 'This target holds the full body layout' "$F04B/edited/.harness/manifest.txt" \
  || fail "R2: a blocked child's manifest does not report the full layout"
f04_all_stubs_in_tier "$F04B/pristine/.harness" "R2 control (the pristine sibling must convert in the same run)"
pass "R2 thin_all_or_nothing_on_edit — one edited prose file leaves the whole tier unconverted"

F04B_SEG="$(f04_seg "$AU_OUT" "$F04B/edited")"
for _p in agents/builder.md docs/WORKFLOW.md; do
  printf '%s\n' 2>/dev/null "$F04B_SEG" | grep -qF "differs: $_p" \
    || fail "R3: the refusal did not name the differing path $_p: $F04B_SEG"
done
printf '%s\n' 2>/dev/null "$F04B_SEG" | grep -qF 'git diff' \
  || fail "R3: the refusal names paths without saying that this run re-installed them from source: $F04B_SEG"
# The pristine sibling must NOT be named as blocked — a report that fires for every child
# would satisfy the two assertions above without discriminating anything.
printf '%s\n' 2>/dev/null "$(f04_seg "$AU_OUT" "$F04B/pristine")" | grep -q 'differs: ' \
  && fail "R3: the pristine sibling was reported as blocked"
pass "R3 thin_names_every_blocker — both seeded differing paths are named, the pristine sibling is not"

# ── R2/R3: the shapes `diff` will not hand over ────────────────────────────────────────
# thin_extra_file_blocks / thin_blocker_paths_are_normalised
#
# FOUR shapes, one fixture, because each defeats a different naive implementation:
#   agents/extra-local.md   `Only in <dir>: <name>` — the JOINED path never appears in
#                           diff's output, so it has to be built
#   AGENTS.md               a REGULAR-FILE tier entry — `diff -r` on two files prints the
#                           hunks and NO filename, so `-q` is what makes it nameable
#   specs/_templates        a whole tier entry absent on one side — diff exits 2 with its
#                           message on STDERR, so a stdout-only capture names nothing
#   specs/glossary.md       a WHITESPACE-ONLY edit — the comparison is BYTE identity, and
#                           it is the one prose-tier entry no other fixture ever seeds
#                           (see thin_comparison_is_byte_identity below)
# TWO children, and the split is load-bearing. `extra` carries the child-only file as its
# ONLY difference, so R2's extra-file claim is independently falsifiable: putting all three
# shapes in one child would leave the tier blocked by the OTHER two even with the one-sided
# case ignored entirely, and the case would pass while being wrong.
F04C="$AU/f04c"
f04_fullchild "$F04C" extra
f04_fullchild "$F04C" shapes
KC4="$F04C/extra/.harness"
KS4="$F04C/shapes/.harness"
printf 'a child-local note the umbrella does not have\n' > "$KC4/agents/extra-local.md"
printf 'a child-local note the umbrella does not have\n' > "$KS4/agents/extra-local.md"
printf '\nlocally appended\n' >> "$KS4/AGENTS.md"
rm -rf "$KS4/specs/_templates"
# A TRAILING SPACE ON LINE 1 — a whitespace-only edit, and it must stay whitespace-only.
# New text on a new line would differ under `diff -w` too and would pin nothing.
awk 'NR == 1 { printf "%s \n", $0; next } { print }' "$KS4/specs/glossary.md" > "$AU/f04c-glossary.tmp"
cat "$AU/f04c-glossary.tmp" > "$KS4/specs/glossary.md"
# PRECONDITIONS for thin_comparison_is_byte_identity below. The edit must be a real BYTE
# difference and must NOT survive `-w`, or the case degenerates into the AGENTS.md shape
# and stops saying anything about byte identity. Measured against the umbrella's own copy,
# which is the reference the conversion uses.
cmp -s "$KS4/specs/glossary.md" "$F04C/.harness/specs/glossary.md" \
  && fail "R3 control: the seeded specs/glossary.md edit is not a byte difference at all — the byte-identity case below would be vacuous"
diff -qw "$KS4/specs/glossary.md" "$F04C/.harness/specs/glossary.md" >/dev/null 2>&1 \
  || fail "R3 control: the seeded specs/glossary.md edit is NOT whitespace-only, so it would also be caught by an identity-modulo-whitespace comparison and pins nothing about BYTE identity"
cascade "$F04C" --thin
f04_no_stub_in_tier "$KC4" "R2 (a child-only extra prose file must block the tier ON ITS OWN)"
grep -q 'This target holds the full body layout' "$KC4/manifest.txt" \
  || fail "R2: a child blocked by a one-sided path does not report the full layout"
printf '%s\n' 2>/dev/null "$(f04_seg "$AU_OUT" "$F04C/extra")" | grep -qF 'differs: agents/extra-local.md' \
  || fail "R2: the one-sided path was not reported as the blocker — the tier may have been blocked for another reason"
pass "R2 thin_extra_file_blocks — a path present on one side only blocks the conversion by itself"

F04C_SEG="$(f04_seg "$AU_OUT" "$F04C/shapes")"
for _p in agents/extra-local.md AGENTS.md specs/_templates; do
  printf '%s\n' 2>/dev/null "$F04C_SEG" | grep -qF "differs: $_p" \
    || fail "R3: the refusal did not name $_p as a tier-relative path — diff's own wording never contains it: $F04C_SEG"
done
# The blockers are TIER-RELATIVE, never diff's own absolute-path wording, and never diff's
# split `Only in <dir>: <name>` form.
printf '%s\n' 2>/dev/null "$F04C_SEG" | grep -q "differs: $(f04_phys "$KS4")" \
  && fail "R3: a blocker was emitted as an absolute path instead of a tier-relative one: $F04C_SEG"
printf '%s\n' 2>/dev/null "$F04C_SEG" | grep -q 'Only in ' \
  && fail "R3: diff's raw 'Only in <dir>: <name>' wording was emitted — that form never contains the joined path: $F04C_SEG"
f04_no_stub_in_tier "$KS4" "R3 (the three-shape child must not convert either)"
pass "R3 thin_blocker_paths_are_normalised — Only-in, regular-file and missing-entry shapes all name the joined path"

# ── R2/R3: the comparison is BYTE identity, never identity-modulo-whitespace ────────────
# thin_comparison_is_byte_identity — asserted SEPARATELY from the loop above, because the
# loop's failure message ("diff's own wording never contains it") is true of those three
# shapes and false of this one: `Files <a> and <b> differ` carries this path already. The
# predicate is the same; only the diagnosis differs, and a message that misdiagnoses is
# how the next maintainer stops looking.
#
# WHAT IT PINS. The whole safety argument of this feature is "a child's prose tier is
# deleted and stubbed ONLY when it is byte-identical to the umbrella's" — and `diff -rq`
# → `diff -rqw` is a one-character edit that relaxes that to identity-modulo-whitespace
# and converts this child. A CRLF round-trip through an editor is the realistic form.
# It is also the only difference this suite ever seeds on `specs/glossary.md`, so it is
# what stops the prose sweep from being written as a hardcoded tier list that drops that
# entry: dropped, the entry is never compared and the child converts on the strength of a
# comparison that never ran. Both mutations leave every other case in this suite green.
printf '%s\n' 2>/dev/null "$F04C_SEG" | grep -qF 'differs: specs/glossary.md' \
  || fail "R2/R3: a WHITESPACE-ONLY edit to specs/glossary.md was not reported as a blocker — either the comparison is identity-modulo-whitespace rather than BYTE identity, or the prose sweep never compared that entry at all; under either, a child whose ONLY difference is that edit CONVERTS and its prose tier is deleted: $F04C_SEG"
pass "R2/R3 thin_comparison_is_byte_identity — a whitespace-only edit to specs/glossary.md blocks the tier and is named"

# ── R2/R3: the pristine REFERENCE is the UMBRELLA'S copy, never the installer's $SRC ────
# thin_reference_is_the_umbrella_body
#
# EVERY OTHER CASE IN THIS SUITE INSTALLS THE UMBRELLA AND THE CHILD FROM THE SAME $SRC, so
# the two candidate references coincide and `prose_tier_blockers "$H" "$SRC"` passes all of
# them. This case is the one that separates them: the child stays byte-identical to $SRC and
# only the UMBRELLA's copy is made to differ — an umbrella ahead of a stale child, which is
# the ordinary state after an umbrella upgrade. Against the $SRC reference the tier looks
# pristine and the child is CONVERTED: its prose tier is deleted and its `agents/builder.md`
# redirected at umbrella content it never held. That is the data loss R2 exists to prevent.
F04H="$AU/f04h"
f04_fullchild "$F04H" kid
KH4="$F04H/kid/.harness"
# PRECONDITION — the two references must genuinely DISAGREE, or this case proves nothing.
cmp -s "$SRC/agents/builder.md" "$KH4/agents/builder.md" \
  || fail "R2 reference control: the child's agents/builder.md already differs from the installer's own \$SRC copy — the two candidate references are not distinguishable in this fixture, so nothing below discriminates between them"
printf '\nan umbrella-only line the child has never held\n' >> "$F04H/.harness/agents/builder.md"
cmp -s "$F04H/.harness/agents/builder.md" "$KH4/agents/builder.md" \
  && fail "R2 reference control: appending to the umbrella's copy did not make it differ from the child's"
# SINGLE-TARGET, NEVER A CASCADE: a cascade re-installs the coordinator first and would
# restore the umbrella-side difference this case seeds, collapsing it back onto $SRC.
F04H_OUT="$(CODEX_HOME="$F04H/.ch" HOME="$F04H/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$F04H/kid" 2>&1)" && F04H_RC=0 || F04H_RC=$?
[ "$F04H_RC" = "0" ] || fail "R2: single-target --thin exited $F04H_RC: $F04H_OUT"
printf '%s\n' 2>/dev/null "$F04H_OUT" | grep -qF 'differs: agents/builder.md' \
  || fail "R2: the child is byte-identical to the installer's \$SRC but NOT to the umbrella body, and --thin did not block on agents/builder.md — the conversion's pristine reference is \$SRC, not the umbrella's copy, so a child that is merely STALE is converted and redirected at content it never held: $F04H_OUT"
f04_no_stub_in_tier "$KH4" "R2 (a child differing from the UMBRELLA's copy must not convert — the reference is the umbrella body, not \$SRC)"
# EXACTLY ONE blocker. Without this, "the tier blocked" is equally explained by a reference
# that blocks every child, which would satisfy the assertion above while discriminating
# nothing — the pristine siblings elsewhere in this suite would then be the failing half.
F04H_N="$(printf '%s\n' 2>/dev/null "$F04H_OUT" | grep -o 'differs: [^ ]*' | wc -l | tr -d ' ')"
[ "$F04H_N" = "1" ] \
  || fail "R2: $F04H_N blocking path(s) were named, want exactly the one seeded on the umbrella side: $F04H_OUT"
cmp -s "$SRC/agents/builder.md" "$KH4/agents/builder.md" \
  || fail "R2: the refused run did not leave the child's own agents/builder.md in place"
pass "R2 thin_reference_is_the_umbrella_body — a child matching \$SRC but not the umbrella blocks, naming the umbrella-side path"

# ── R3: a path present on the UMBRELLA side only is named with its JOINED path ──────────
# thin_umbrella_side_path_is_named
#
# EVERY OTHER one-sided fixture in this suite seeds the extra file on the CHILD side
# (`extra`/`shapes`), which diff reports as `Only in <child>/…` and a DIFFERENT arm of the
# normalisation strips. The umbrella-side arm — an umbrella AHEAD of the child, which is
# Recorded decision E's state and the ordinary one after an umbrella upgrade — is the
# direction this feature exists for, and it is the one no fixture reached. Neutralised,
# that arm falls through to the fail-closed `*)` case: the tier still blocks (so this is
# naming precision, not data loss) but the refusal degrades from `differs:
# agents/newfile.md` to `differs: agents` and the operator is pointed at a directory
# instead of at the file R3 requires be named.
#
# ITS OWN UMBRELLA, deliberately. $F04C's umbrella serves BOTH `extra` and `shapes`, and
# `extra`'s whole value is that a child-local one-sided path is its ONLY difference — an
# umbrella-side file seeded there would block `extra` for a second reason and dissolve
# that case.
F04I="$AU/f04i"
f04_fullchild "$F04I" kid
KI4="$F04I/kid/.harness"
printf 'an umbrella-only note the child has never held\n' > "$F04I/.harness/agents/newfile.md"
# PRECONDITION — one-sided means one-sided. If the child holds the path too, this is an
# ordinary two-sided comparison and the umbrella arm is never reached.
[ -e "$KI4/agents/newfile.md" ] \
  && fail "R3 control: the umbrella-only path exists in the child as well, so nothing below exercises the umbrella side of the normalisation"
# SINGLE-TARGET, NEVER A CASCADE, for the same reason as the case above: a cascade
# re-installs the coordinator first, and the umbrella-side difference is seeded inside the
# coordinator's own prose tier.
F04I_OUT="$(CODEX_HOME="$F04I/.ch" HOME="$F04I/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$F04I/kid" 2>&1)" && F04I_RC=0 || F04I_RC=$?
[ "$F04I_RC" = "0" ] || fail "R3: single-target --thin exited $F04I_RC: $F04I_OUT"
printf '%s\n' 2>/dev/null "$F04I_OUT" | grep -qF 'differs: agents/newfile.md' \
  || fail "R3: a path the UMBRELLA holds and the child does not was not named as a tier-relative path — the refusal names the tier entry \`agents\`, pointing the operator at a directory instead of the file: $F04I_OUT"
f04_no_stub_in_tier "$KI4" "R3 (a one-sided path on the UMBRELLA side must block the tier too)"
# EXACTLY ONE blocker. Without this, "the umbrella-side path was named" is equally
# explained by a run that names every tier entry it walks.
F04I_N="$(printf '%s\n' 2>/dev/null "$F04I_OUT" | grep -o 'differs: [^ ]*' | wc -l | tr -d ' ')"
[ "$F04I_N" = "1" ] \
  || fail "R3: $F04I_N blocking path(s) were named, want exactly the one seeded on the umbrella side: $F04I_OUT"
pass "R3 thin_umbrella_side_path_is_named — a path the umbrella holds and the child does not is named with its joined path"

# ── R2/R3: a SYMLINK is compared as a PATH, never read through to its content ───────────
# thin_symlink_shapes_block
#
# `diff` DEREFERENCES. Two prose paths that differ STRUCTURALLY while resolving to the same
# bytes are reported IDENTICAL by `diff -rq`, so the tier is judged pristine, the conversion
# runs, and `cp -R` plants the UMBRELLA's link in the child — where its relative target
# resolves from the CHILD's directory instead and lands outside the tree or nowhere at all.
# Measured on this very fixture before the fix: every child printed `CONVERTED`, and the two
# with an umbrella-side link ended with `agents/builder.md` an unreadable dangling link,
# their real body gone. (Codex #3801551083.)
#
# THREE CHILDREN of ONE umbrella, and the third is not padding — it is what pins the sweep to
# BOTH SIDES. A sweep that looks only at the umbrella's copy catches the first two (the
# umbrella holds a link in both), so `plain` is the one direction that fails without the
# child side, and its harm is its own: the child's link is judged pristine, deleted and
# replaced by a stub while the run prints CONVERTED.
#   plain     the CHILD holds the link, the umbrella a regular file — run FIRST, while the
#             umbrella is still pristine
#   regular   a REGULAR FILE against an umbrella symlink
#   linked    its OWN symlink, to its OWN copy, with a DIFFERENT TARGET and the same bytes
#
# THE CONTENT-IDENTITY PRECONDITION IS THE WHOLE CASE. Every child is asserted
# `diff -rq`-identical to the umbrella's `agents/` BEFORE its run, so the only thing left for
# the refusal to be about is the shape of the paths. Without it, "the tier blocked" is
# explained by any ordinary edit and this case pins nothing.
#
# SINGLE-TARGET, NEVER A CASCADE — a cascade re-installs the coordinator first and would
# restore the umbrella's regular file, collapsing two of the three shapes.
#
# THE FOURTH CHILD, `mixed`, IS A DIFFERENT CLAIM and runs last, after the umbrella has been
# restored: an entry that holds a symlink AND an ordinary edit must name BOTH. The sweep used
# to short-circuit `diff` for the whole entry, so the edit went unnamed while the refusal told
# the operator these were all the differing paths (Codex #3802057859).
F04G="$AU/f04g"
f04_fullchild "$F04G" regular
f04_fullchild "$F04G" linked
f04_fullchild "$F04G" plain
f04_fullchild "$F04G" mixed
UG4="$F04G/.harness"
KG4R="$F04G/regular/.harness"
KG4L="$F04G/linked/.harness"
KG4P="$F04G/plain/.harness"
KG4M="$F04G/mixed/.harness"

# ── direction 1: the link is the CHILD's, and the umbrella is untouched ─────────────────
mkdir -p "$F04G/plain/ext-kid"
cp "$KG4P/agents/builder.md" "$F04G/plain/ext-kid/real.md"
rm -f "$KG4P/agents/builder.md"; ln -s ../../ext-kid/real.md "$KG4P/agents/builder.md"
[ -L "$KG4P/agents/builder.md" ] || fail "R2 symlink control: the 'plain' child's agents/builder.md is not a symlink"
[ -L "$UG4/agents/builder.md" ] \
  && fail "R2 symlink control: the umbrella's agents/builder.md is ALREADY a symlink — 'plain' is meant to run against a pristine umbrella, so it no longer isolates the CHILD side"
diff -rq "$KG4P/agents" "$UG4/agents" >/dev/null 2>&1 \
  || fail "R2 symlink control: 'plain' already differs from the umbrella's agents/ BY CONTENT — a refusal there would be explained by that difference"
F04G_P="$(CODEX_HOME="$F04G/.ch" HOME="$F04G/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$F04G/plain" 2>&1)" && F04G_RC=0 || F04G_RC=$?
[ "$F04G_RC" = "0" ] || fail "R2: single-target --thin on 'plain' exited $F04G_RC: $F04G_P"
printf '%s\n' 2>/dev/null "$F04G_P" | grep -qF 'differs: agents/builder.md' \
  || fail "R2/R3: the CHILD holds agents/builder.md as a symlink and the umbrella as a regular file, they resolve to the same bytes, and --thin did not block — the comparison only looks at the umbrella's side, so a child's own link is judged pristine and deleted: $F04G_P"
f04_no_stub_in_tier "$KG4P" "R2 ('plain': a child-side symlink must block the WHOLE tier)"
F04G_N="$(printf '%s\n' 2>/dev/null "$F04G_P" | grep -o 'differs: [^ ]*' | wc -l | tr -d ' ')"
[ "$F04G_N" = "1" ] \
  || fail "R3: $F04G_N blocking path(s) were named for 'plain', want exactly the one seeded symlink path: $F04G_P"

# ── directions 2 and 3: the link is the UMBRELLA's ─────────────────────────────────────
mkdir -p "$F04G/ext-umb" "$F04G/linked/ext-kid"
cp "$UG4/agents/builder.md" "$F04G/ext-umb/real.md"
cp "$KG4L/agents/builder.md" "$F04G/linked/ext-kid/real.md"
rm -f "$UG4/agents/builder.md";   ln -s ../../ext-umb/real.md "$UG4/agents/builder.md"
rm -f "$KG4L/agents/builder.md";  ln -s ../../ext-kid/real.md "$KG4L/agents/builder.md"
# PRECONDITIONS — the shapes are what they claim to be…
[ -L "$UG4/agents/builder.md" ] || fail "R2 symlink control: the umbrella's agents/builder.md is not a symlink"
[ -L "$KG4L/agents/builder.md" ] || fail "R2 symlink control: the 'linked' child's agents/builder.md is not a symlink"
[ -L "$KG4R/agents/builder.md" ] \
  && fail "R2 symlink control: the 'regular' child's agents/builder.md is a symlink too — the regular-vs-symlink direction is not in this fixture at all"
[ "$(readlink "$KG4L/agents/builder.md")" = "$(readlink "$UG4/agents/builder.md")" ] \
  && fail "R2 symlink control: both links point at the SAME target, so the differing-targets direction is not in this fixture"
# …both links RESOLVE where they stand, so neither child is broken going in…
[ -r "$KG4L/agents/builder.md" ] || fail "R2 symlink control: the 'linked' child's link is already dangling before the run"
# …and the content is IDENTICAL through the links, which is what makes `diff -rq` say yes.
for _g in regular linked; do
  diff -rq "$F04G/$_g/.harness/agents" "$UG4/agents" >/dev/null 2>&1 \
    || fail "R2 symlink control: '$_g' already differs from the umbrella's agents/ BY CONTENT — a refusal here would be explained by that difference and would say nothing about symlink identity"
done
for _g in regular linked; do
  F04G_OUT="$(CODEX_HOME="$F04G/.ch" HOME="$F04G/.home" \
    sh "$SRC/harness-install.sh" --agents=claude --thin "$F04G/$_g" 2>&1)" && F04G_RC=0 || F04G_RC=$?
  [ "$F04G_RC" = "0" ] || fail "R2: single-target --thin on '$_g' exited $F04G_RC: $F04G_OUT"
  printf '%s\n' 2>/dev/null "$F04G_OUT" | grep -qF 'differs: agents/builder.md' \
    || fail "R2/R3: '$_g' is byte-identical to the umbrella THROUGH the links but differs from it as a PATH, and --thin did not block on agents/builder.md — \`diff\` followed the link, so the tier converts and the umbrella's own symlink is planted in the child, where its relative target resolves from the child's directory and leaves the body unreadable: $F04G_OUT"
  f04_no_stub_in_tier "$F04G/$_g/.harness" "R2 ('$_g': a structural mismatch \`diff\` reads through must block the WHOLE tier)"
  # EXACTLY ONE blocker — otherwise "the tier blocked" is equally explained by a sweep that
  # refuses every entry it walks, which would disable the feature rather than guard it.
  F04G_N="$(printf '%s\n' 2>/dev/null "$F04G_OUT" | grep -o 'differs: [^ ]*' | wc -l | tr -d ' ')"
  [ "$F04G_N" = "1" ] \
    || fail "R3: $F04G_N blocking path(s) were named for '$_g', want exactly the one seeded symlink path: $F04G_OUT"
  # THE BODY, NOT JUST THE VERDICT. This is the damage the finding is actually about: before
  # the fix this path was a dangling link into the umbrella's tree and `grep` could not read
  # it at all.
  [ "$(readlink "$F04G/$_g/.harness/agents/builder.md" 2>/dev/null || echo '')" = "$(readlink "$UG4/agents/builder.md")" ] \
    && fail "R2: the run replaced agents/builder.md in '$_g' with the UMBRELLA's own symlink — that target is relative to the umbrella's directory, not this child's"
  grep -qF 'You are the **Builder**' "$F04G/$_g/.harness/agents/builder.md" \
    || fail "R2: '$_g': agents/builder.md is no longer a readable body after the refused run"
done
# THE POSITIVE CONTROL, and it is the same child, the same umbrella and the same tier — only
# the SHAPE of one path changes. Restore the umbrella's regular file (same bytes the link
# resolved to) and 'regular' converts, so the refusal above was caused by the symlink and
# by nothing else about this fixture.
rm -f "$UG4/agents/builder.md"
cp "$F04G/ext-umb/real.md" "$UG4/agents/builder.md"
F04G_CTL="$(CODEX_HOME="$F04G/.ch" HOME="$F04G/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$F04G/regular" 2>&1)" && F04G_RC=0 || F04G_RC=$?
[ "$F04G_RC" = "0" ] || fail "R2 symlink control: the restored-shape run exited $F04G_RC: $F04G_CTL"
printf '%s\n' 2>/dev/null "$F04G_CTL" | grep -q 'CONVERTED to the thin layout' \
  || fail "R2 symlink control: with the umbrella's agents/builder.md restored to a REGULAR file of the very same bytes, 'regular' STILL did not convert — the refusal above is not attributable to the symlink: $F04G_CTL"
f04_all_stubs_in_tier "$KG4R" "R2 symlink control (the restored-shape run must convert the whole tier)"

# ── direction 4 (`mixed`): a link AND an edit in the SAME entry — BOTH are named ────────
# TWO ENTRIES, each carrying one link and one ordinary difference, because the two link
# shapes stress different halves of the fix:
#   agents/  an ESCAPING umbrella-side link (agents/custom.md) + a child-side EDIT
#            (agents/orchestrator.md)
#   docs/    a CYCLIC link ON BOTH SIDES (docs/self -> .) + a child-side EDIT
#            (docs/WORKFLOW.md)
#
# `docs/self` IS ON BOTH SIDES DELIBERATELY, and the reason is measured rather than inherited.
# A one-sided cyclic link makes `diff -r` do nothing special at all — it reports `Only in` and
# never descends — so a fixture with the link on the umbrella alone cannot tell a
# cycle-protected comparison from an unprotected one. It is the two-sided shape that reaches
# the hazard: this box's `diff` then prints `Directory loop detected` per side, which this
# parser does not recognise, so the fail-closed arm collapses the whole entry to `docs` and
# R3's per-path naming degrades to entry granularity. That is what a fix which simply deleted
# the short-circuit would ship, and it is what the `exactly four` assertion below catches.
printf '%s\n' 'shared house prompt' > "$F04G/ext-umb/custom.md"
ln -s ../../ext-umb/custom.md "$UG4/agents/custom.md"
ln -s . "$UG4/docs/self"
ln -s . "$KG4M/docs/self"
printf '\nEDITED BY THE OPERATOR\n' >> "$KG4M/agents/orchestrator.md"
printf '\nEDITED BY THE OPERATOR\n' >> "$KG4M/docs/WORKFLOW.md"
# PRECONDITIONS: the shapes are what they claim, and the edits are REAL differences that a
# link-free comparison of those same entries would report on its own.
[ -L "$UG4/agents/custom.md" ] || fail "R3 mixed control: the umbrella's agents/custom.md is not a symlink"
for _mc in "$UG4/docs/self" "$KG4M/docs/self"; do
  [ -L "$_mc" ] || fail "R3 mixed control: $_mc is not a symlink"
  [ "$(readlink "$_mc")" = "." ] \
    || fail "R3 mixed control: $_mc does not point at its own directory, so it is not the cyclic shape this case is about"
done
# …and the link is on BOTH sides, which is the only arrangement `diff -r` descends into.
[ -L "$UG4/docs/self" ] && [ -L "$KG4M/docs/self" ] \
  || fail "R3 mixed control: docs/self is one-sided, so \`diff -r\` reports it as \`Only in\` and never reaches the loop — the cycle claim would be untested"
diff -q "$KG4M/agents/orchestrator.md" "$UG4/agents/orchestrator.md" >/dev/null 2>&1 \
  && fail "R3 mixed control: agents/orchestrator.md is still identical to the umbrella's — the second blocker is not in the fixture"
diff -q "$KG4M/docs/WORKFLOW.md" "$UG4/docs/WORKFLOW.md" >/dev/null 2>&1 \
  && fail "R3 mixed control: docs/WORKFLOW.md is still identical to the umbrella's — the second blocker is not in the fixture"
F04G_M="$(CODEX_HOME="$F04G/.ch" HOME="$F04G/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$F04G/mixed" 2>&1)" && F04G_RC=0 || F04G_RC=$?
[ "$F04G_RC" = "0" ] \
  || fail "R3: --thin on 'mixed' exited $F04G_RC — an entry holding a cyclic symlink on both sides must still be compared, without \`diff\` being walked into it: $F04G_M"
for _m in agents/custom.md agents/orchestrator.md docs/self docs/WORKFLOW.md; do
  printf '%s\n' 2>/dev/null "$F04G_M" | grep -qF "differs: $_m" \
    || fail "R3: 'mixed' did not name $_m — an entry holding a symlink must still have the REST of it compared, or the refusal names some of the differing paths while promising all of them: $F04G_M"
done
# EXACTLY FOUR, deduplicated — and this is the assertion that carries the cycle claim. Both
# producers can legitimately name the same path (`docs/self` is swept from BOTH sides and
# normalises to one), and naming it twice reads as two separate problems. It is also what a
# comparison walked into the loop fails: `diff` then emits `Directory loop detected`, the
# fail-closed arm synthesises the tier entry, and a FIFTH blocker `docs` appears — an entry
# named where a file was promised. A sweep that simply refused every path it walked would
# equally "name all four" and would disable the feature rather than guard it.
F04G_N="$(printf '%s\n' 2>/dev/null "$F04G_M" | grep -o 'differs: [^ ]*' | wc -l | tr -d ' ')"
[ "$F04G_N" = "4" ] \
  || fail "R3: $F04G_N blocking path(s) were named for 'mixed', want exactly the four seeded ones: $F04G_M"
f04_no_stub_in_tier "$KG4M" "R3 ('mixed': the tier must stay whole while anything in it blocks)"
# The cycle is not merely survivable, it is UNWALKED: the child's docs/ must not have grown
# `self/self/...`. `find` does not follow symlinks, so it reports the tree as stored.
F04G_D="$(find "$KG4M/docs" | wc -l | tr -d ' ')"
[ "$F04G_D" -lt 100 ] \
  || fail "R3: the child's docs/ holds $F04G_D entries after the run — something walked through the cyclic link"
pass "R2/R3 thin_symlink_shapes_block — a child-side link, an umbrella-side link and two links with different targets all block though \`diff\` reads through them (with a same-bytes positive control), and an entry holding a link plus an edit names both"

# ── R2/R5: the link rule holds on the arm that JUDGES NOTHING ──────────────────────────
# thin_maintained_link_does_not_travel
#
# The case above is about the CONVERSION, which refuses. This one is about MAINTENANCE, which
# has nothing to refuse: the child is already thin, the run carries no flag, and it never asks
# whether anything is pristine — it just rebuilds the tier from the umbrella. So a guard that
# lives in the pristine check does not run here at all, and the umbrella's link was `cp -R`'d
# straight into the child, where its relative target resolves from the CHILD's directory.
# Measured before the fix: an ordinary install printed its usual success line and left
# `agents/builder.md` a dangling link, i.e. the child's builder prompt unreadable.
# (Codex #3802057839.)
#
# TWO LINKS, ONE RUN, AND THE SECOND IS THE CONTROL. The rule is not "refuse symlinks" — E24-F03
# requires a thin child to keep the shapes a full copy would give it, `docs/self -> .` among
# them. It is "a link is reproduced only where it still means the same thing at the child's
# path". So this fixture seeds one link that CANNOT travel (escapes its entry) and one that
# CAN (resolves inside its own entry), and asserts opposite outcomes for them in the same run.
# Without the control, "the child holds no link" would be satisfied by a fix that stubbed every
# link and silently broke that E24-F03 shape guarantee.
F04M="$AU/f04m"
mk_umb "$F04M" kid
cascade "$F04M" --thin   # exit 3 is the landing audit on an uncommitted child, not a failure
UM4="$F04M/.harness"
KM4="$F04M/kid/.harness"
f04_all_stubs_in_tier "$KM4" "R5 fixture (the child must already be THIN, or this run would take the conversion arm and its guard)"

# The umbrella gains both links AFTER the child is thin — this is the umbrella-side change an
# ordinary maintenance run then has to carry.
cp "$UM4/agents/builder.md" "$F04M/shared-builder.md"
rm -f "$UM4/agents/builder.md"; ln -s ../../shared-builder.md "$UM4/agents/builder.md"
ln -s . "$UM4/docs/self"
# THE TWO TRAVERSAL-ONLY TARGETS, and they are a PAIR: one `..` apart, opposite answers.
#   docs/up   -> ..      the harness dir itself — the mirror root, so it means the same thing
#                        in the child and MUST survive as a link
#   docs/link -> ../..   one level further, the REPOSITORY root — the umbrella's at the
#                        umbrella, the child's in the child, so it must never be planted
# The second is the shape that resolving only `dirname(target)` got wrong: `dirname("../..")`
# is `..`, which still lands inside the staging root, so the escape lived entirely in the
# component that was thrown away. (Codex #3804812828.)
ln -s .. "$UM4/docs/up"
ln -s ../.. "$UM4/docs/link"
# PRECONDITIONS: both links RESOLVE where they stand, so nothing here is broken going in and
# any breakage after the run belongs to the run.
[ -L "$UM4/agents/builder.md" ] || fail "R5 control: the umbrella's agents/builder.md is not a symlink"
[ -r "$UM4/agents/builder.md" ] \
  || fail "R5 control: the umbrella's own link is already dangling AT THE UMBRELLA — the child's would then be broken for a reason that has nothing to do with the copy"
[ -L "$UM4/docs/self" ] || fail "R5 control: the umbrella's docs/self is not a symlink"
for _mu in up link; do
  [ -L "$UM4/docs/$_mu" ] || fail "R5 control: the umbrella's docs/$_mu is not a symlink"
  [ -d "$UM4/docs/$_mu" ] \
    || fail "R5 control: the umbrella's docs/$_mu does not resolve to a directory at the umbrella — it is broken going in, so anything the child ends up with says nothing"
done
# THE PRECONDITION THAT MAKES THIS A DEFECT AND NOT A STYLE CHOICE: `docs/link` names two
# DIFFERENT repositories depending on where the link sits. Computed, not asserted by eye.
F04M_LU="$( CDPATH= cd -- "$UM4/docs" && CDPATH= cd -- ../.. && pwd -P )"
F04M_LK="$( CDPATH= cd -- "$KM4/docs" && CDPATH= cd -- ../.. && pwd -P )"
[ "$F04M_LU" != "$F04M_LK" ] \
  || fail "R5 control: '../..' resolves to the same place ($F04M_LU) from the umbrella's docs/ and the child's, so this fixture cannot show position dependence at all"
# …while `docs/up` names the SAME THING in both places — the harness dir — which is what makes
# it a control for the rule rather than a second instance of the defect.
F04M_UU="$( CDPATH= cd -- "$UM4/docs" && CDPATH= cd -- .. && pwd -P )"
F04M_UK="$( CDPATH= cd -- "$KM4/docs" && CDPATH= cd -- .. && pwd -P )"
[ "$F04M_UU" = "$( f04_phys "$UM4" )" ] && [ "$F04M_UK" = "$( f04_phys "$KM4" )" ] \
  || fail "R5 control: '..' does not name each side's own harness dir ($F04M_UU / $F04M_UK), so the surviving-link control below is not the boundary case it claims to be"

# NO FLAG. --thin would prove less: an already-thin child lands on this same arm either way,
# and the unflagged run is the one an operator gets from every routine cascade.
F04M_OUT="$(CODEX_HOME="$F04M/.ch" HOME="$F04M/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04M/kid" 2>&1)" && F04M_RC=0 || F04M_RC=$?
[ "$F04M_RC" = "0" ] || fail "R5: the maintenance run exited $F04M_RC: $F04M_OUT"
printf '%s\n' 2>/dev/null "$F04M_OUT" | grep -q 'resolved from the umbrella' \
  || fail "R5: the run did not take the MAINTENANCE arm, so this case is measuring some other branch: $F04M_OUT"

# THE ESCAPING LINK: never planted, and what replaces it is the ordinary stub — readable, and
# naming the umbrella's own path, where the umbrella's link resolves correctly.
[ -L "$KM4/agents/builder.md" ] \
  && fail "R5: the maintenance run planted the UMBRELLA's symlink in the child — its target is relative to the umbrella's directory, so in the child it names $(cd "$KM4/agents" 2>/dev/null && pwd -P)/$(readlink "$KM4/agents/builder.md" 2>/dev/null)"
[ -r "$KM4/agents/builder.md" ] \
  || fail "R5: the child's agents/builder.md is not readable after an ordinary maintenance run"
is_stub "$KM4/agents/builder.md" \
  || fail "R5: the child's agents/builder.md is neither a link nor a stub after the run"
grep -qF '../../.harness/agents/builder.md' "$KM4/agents/builder.md" \
  || fail "R5: the stub that replaced the umbrella's link does not name the authoritative path"
( cd "$KM4" && grep -qF 'You are the **Builder**' ../../.harness/agents/builder.md ) \
  || fail "R5: the path that stub names does not resolve to the real body THROUGH the umbrella's own link — the redirect only works if the umbrella's link resolves at the umbrella"
# THE CONTROL, same run, same tier: a link that resolves inside its own entry still travels,
# so it survives as a link exactly as E24-F03 requires and a full copy would produce.
[ -L "$KM4/docs/self" ] \
  || fail "R5: docs/self is no longer a symlink in the child — the rule is 'a link that cannot travel', not 'every link', and stubbing this one breaks the E24-F03 shape guarantee"
[ "$(readlink "$KM4/docs/self")" = "." ] \
  || fail "R5: docs/self points at '$(readlink "$KM4/docs/self")' in the child, want '.'"
# THE TRAVERSAL PAIR, and it is one assertion about a boundary rather than two about links.
[ -L "$KM4/docs/link" ] \
  && fail "R5: the run kept docs/link -> ../.. in the child, where it names $F04M_LK; at the umbrella the same link names $F04M_LU — a different repository, which is the whole reason a link is not allowed to travel"
is_stub "$KM4/docs/link" \
  || fail "R5: docs/link is neither a link nor a stub after the run"
grep -qF '../../.harness/docs/link' "$KM4/docs/link" \
  || fail "R5: the stub that replaced docs/link does not name the authoritative path"
[ -L "$KM4/docs/up" ] \
  || fail "R5: docs/up -> .. was stubbed too — it resolves to each side's OWN harness dir, so it means the same thing in the child and must survive; refusing it as well would make the rule 'refuse traversal' rather than 'refuse position dependence', and one `..` is the whole difference between these two paths"
[ "$(readlink "$KM4/docs/up")" = ".." ] \
  || fail "R5: docs/up points at '$(readlink "$KM4/docs/up")' in the child, want '..'"
# NOTHING IN THE TIER DANGLES — stated over the tree rather than the one seeded path, since a
# partially reproduced link set is the actual hazard.
for _ml in $(find "$KM4/AGENTS.md" "$KM4/agents" "$KM4/docs" "$KM4/specs" -type l 2>/dev/null); do
  [ -e "$_ml" ] || fail "R5: the maintenance run left a dangling link in the child's prose tier: $_ml -> $(readlink "$_ml")"
done

# ── the same rule, on the FRESH arm ─────────────────────────────────────────────────────
# Everything above is arm (2). The predicate lives in the tier WRITER, below every arm, so a
# child that has NEVER been installed must answer identically — and it is a different code
# path to get there: a fresh cascade child is thinned on first contact, with no existing tier
# to maintain. It needs a DOCTORED INSTALLER SOURCE rather than a doctored umbrella, because a
# cascade re-installs the coordinator from source first and would wipe a link added by hand.
F04M_SRC="$AU/f04m-src"
mkdir -p "$F04M_SRC"
for _md in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
           harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
  [ -e "$SRC/$_md" ] && cp -R "$SRC/$_md" "$F04M_SRC/"
done
ln -s ../.. "$F04M_SRC/docs/link"
ln -s .. "$F04M_SRC/docs/up"
F04N="$AU/f04n"
mk_umb "$F04N" kid
F04N_OUT="$(CODEX_HOME="$F04N/.ch" HOME="$F04N/.home" \
  sh "$F04M_SRC/harness-install.sh" --umbrella "$F04N" --agents=claude --thin 2>&1)" || true
KN4="$F04N/kid/.harness"
# Precondition: the doctored source really did carry the link through to the umbrella body,
# or the fresh child has nothing to have got wrong.
[ -L "$F04N/.harness/docs/link" ] \
  || fail "R5 fresh control: the umbrella body has no docs/link, so the fresh child was never offered the shape: $F04N_OUT"
is_stub "$KN4/AGENTS.md" || fail "R5 fresh control: the cascade child is not thin: $F04N_OUT"
[ -L "$KN4/docs/link" ] \
  && fail "R5: a FRESH thin child kept docs/link -> ../.., which names the child's own repository root instead of the umbrella's — the rule has to hold on the arm that materialises a tier as much as on the one that maintains it"
is_stub "$KN4/docs/link" || fail "R5: a fresh child's docs/link is neither a link nor a stub"
[ -L "$KN4/docs/up" ] \
  || fail "R5: a fresh child stubbed docs/up -> .. as well — the boundary control fails on the fresh arm"
pass "R2/R5 thin_maintained_link_does_not_travel — an umbrella link that escapes its entry is stubbed, not planted, on the arm that judges nothing (with an in-entry link kept as a link)"

# ── R1/R2: the CONVERTED TREE is built from the umbrella body, never from $SRC ──────────
# thin_converted_tree_comes_from_the_umbrella
#
# The case above pins the reference the pristine COMPARISON uses. This one pins the
# reference the WRITE uses, and they have to be ONE tree: `prose_tier_blockers` judged the
# child against the umbrella body while `stub_tree` rebuilt the tier with `rm -rf` + `cp -R`
# from `$SRC`. Wherever those two trees disagree — and a shared umbrella exists precisely so
# that they CAN — a conversion that reports success is wrong in BOTH directions:
#   agents/shared-extra.md   held by the child AND the umbrella, absent from `$SRC` — a
#                            shared house addition, the thing an umbrella is for. Pristine
#                            by the comparison, DELETED by a copy from `$SRC`, and the run
#                            still prints CONVERTED. Silent: the "re-installed from source
#                            by this run" disclosure belongs to the REFUSAL branch and is
#                            never printed on this one.
#   agents/pr-fixer.md       held by `$SRC`, absent from the umbrella AND the child.
#                            Recreated as a stub naming `../../.harness/agents/pr-fixer.md`,
#                            which the umbrella cannot supply — and that stub's own text
#                            then misreads the dangling target as "a checkout separated
#                            from its umbrella".
#
# ONE child carries both directions, and it has to: each seeded difference is SHARED by the
# child and the umbrella, so neither blocks, and the two assertions name disjoint paths. A
# second child in this umbrella is impossible — direction 2 is seeded by REMOVING a path
# from the umbrella, which would block any sibling that still holds it.
#
# THE CONVERSION IS ASSERTED FIRST, and that is load-bearing: "agents/shared-extra.md
# survived" is satisfied for free by any change that simply refuses to convert.
F04J="$AU/f04j"
f04_fullchild "$F04J" kid
KJ4="$F04J/kid/.harness"
F04J_ADD=agents/shared-extra.md
F04J_DROP=agents/pr-fixer.md
printf 'a shared house note, held by the umbrella and the child alike\n' > "$F04J/.harness/$F04J_ADD"
cp "$F04J/.harness/$F04J_ADD" "$KJ4/$F04J_ADD"
rm -f "$F04J/.harness/$F04J_DROP" "$KJ4/$F04J_DROP"
# PRECONDITIONS. Each seeded path must be one-sided against `$SRC` and IDENTICAL between the
# child and the umbrella — otherwise it blocks the tier and neither direction is reached.
[ -e "$SRC/$F04J_ADD" ] \
  && fail "R1/R2 control: the installer's own \$SRC holds $F04J_ADD, so this fixture no longer separates the two candidate write references"
cmp -s "$F04J/.harness/$F04J_ADD" "$KJ4/$F04J_ADD" \
  || fail "R1/R2 control: the shared addition is not byte-identical on the two sides, so it would block the conversion for an unrelated reason"
[ -e "$SRC/$F04J_DROP" ] \
  || fail "R1/R2 control: \$SRC does not hold $F04J_DROP, so a converted tree built from \$SRC would have nothing to recreate and the second direction is vacuous"
[ -e "$F04J/.harness/$F04J_DROP" ] \
  && fail "R1/R2 control: $F04J_DROP is still in the umbrella body — the second direction needs the umbrella to lack it"
[ -e "$KJ4/$F04J_DROP" ] \
  && fail "R1/R2 control: $F04J_DROP is still in the child — one-sided against \$SRC means absent from BOTH sides of the comparison"
# SINGLE-TARGET, NEVER A CASCADE, for the same reason as the two cases above: both
# differences live in the COORDINATOR's own prose tier, and a cascade re-installs the
# coordinator from $SRC first, erasing both.
F04J_OUT="$(CODEX_HOME="$F04J/.ch" HOME="$F04J/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$F04J/kid" 2>&1)" && F04J_RC=0 || F04J_RC=$?
[ "$F04J_RC" = "0" ] || fail "R1: single-target --thin exited $F04J_RC: $F04J_OUT"
printf '%s\n' 2>/dev/null "$F04J_OUT" | grep -q 'CONVERTED to the thin layout' \
  || fail "R1 control: the child did not convert at all, so nothing below discriminates — a refusal leaves every prose path in place and satisfies the survival assertion for free: $F04J_OUT"
is_stub "$KJ4/agents/builder.md" \
  || fail "R1 control: the run reported a conversion but agents/builder.md is not a stub: $F04J_OUT"
is_stub "$KJ4/$F04J_ADD" \
  || fail "R2: the conversion did not leave $F04J_ADD as a stub — the child and the umbrella both held it byte-identically and \$SRC does not, so it was judged pristine and then destroyed by a converted tree rebuilt from \$SRC, while the run reported CONVERTED and named nothing"
[ -e "$KJ4/$F04J_DROP" ] \
  && fail "R2: the conversion created $F04J_DROP, which \$SRC holds and the umbrella does not — the stub names ../../.harness/$F04J_DROP, a file the umbrella cannot supply, and its own text misreads that dangling target as a checkout separated from its umbrella"
pass "R1/R2 thin_converted_tree_comes_from_the_umbrella — the converted tree's shape comes from the umbrella body: a shared path \$SRC lacks survives as a stub, a \$SRC path the umbrella lacks is not recreated"

# ── R1/R2/R7: the MAINTENANCE arm answers to the SAME authority as the conversion ───────
# thin_maintenance_tree_comes_from_the_umbrella
#
# The case above pins the tree the CONVERSION writes from. It leaves the child in a state no
# earlier case could reach: an already-thin tier holding a stub for a path only the UMBRELLA
# has. The very next install — ordinary OR --thin — takes the already-thin MAINTENANCE arm,
# which rebuilt the tier from `$SRC`, so it undid the conversion in both directions at once:
# `agents/shared-extra.md` deleted, `agents/pr-fixer.md` recreated as a stub the umbrella
# cannot resolve, and the run printing its ordinary success line either way. Measured on this
# fixture before the fix. (Codex r3 P1 #3800164980.)
#
# SAME CHILD, DELIBERATELY. The claim is about what happens to a tier the CONVERSION built,
# so the fixture has to be that tier — rebuilding an equivalent child by hand would test the
# same code against a state the product never produces.
#
# BOTH RUNS, because both reach this arm and only one of them mentions the flag: an
# implementation that fixed `--thin` alone would still lose the shared path on the next
# unflagged cascade, which is the run that happens by itself.
#
# THIS IS ALSO R7's REAL IDEMPOTENCE CASE. `thin_is_idempotent` above uses a CASCADE, and a
# cascade re-installs the coordinator from `$SRC` before every child — so its umbrella body
# and `$SRC` can never disagree, and it cannot tell the two references apart no matter what
# it asserts. Byte-equality is therefore re-asserted here, on the one fixture where they do
# disagree.
F04J_REF="$AU/f04j-tier.ref"
mkdir -p "$F04J_REF/specs"
for _p in $F04_TIER; do cp -R "$KJ4/$_p" "$F04J_REF/$_p"; done
is_stub "$F04J_REF/$F04J_ADD" \
  || fail "R1/R2/R7 control: the reference tier captured before the maintenance runs does not hold the shared path as a stub — there is nothing for a maintenance run to lose"
# f04j_maintenance <label> [installer flags...] — one maintenance run over the converted
# child, with every claim re-checked. A function, so the unflagged and the --thin run cannot
# drift into asserting different things.
f04j_maintenance() {
  _fm_l="$1"; shift
  _fm_out="$(CODEX_HOME="$F04J/.ch" HOME="$F04J/.home" \
    sh "$SRC/harness-install.sh" --agents=claude "$@" "$F04J/kid" 2>&1)" && _fm_rc=0 || _fm_rc=$?
  [ "$_fm_rc" = "0" ] || fail "R1/R2/R7 ($_fm_l): the maintenance run exited $_fm_rc: $_fm_out"
  # CONTROL: the run must have taken the already-thin MAINTENANCE arm. That line is printed
  # by branch (2) alone — a run that converted, refused, or skipped the child entirely would
  # satisfy every survival assertion below for free.
  printf '%s\n' 2>/dev/null "$_fm_out" | grep -q 'prose body resolved from the umbrella' \
    || fail "R1/R2/R7 ($_fm_l) control: the run did not take the already-thin maintenance arm, so nothing below is about that arm: $_fm_out"
  is_stub "$KJ4/$F04J_ADD" \
    || fail "R1/R2/R7 ($_fm_l): the maintenance run destroyed $F04J_ADD — the child and the umbrella both hold it and \$SRC does not, so a tier rebuilt from \$SRC deletes the stub the conversion had just written, while the run reports its ordinary success and names nothing: $_fm_out"
  if [ -e "$KJ4/$F04J_DROP" ]; then
    fail "R1/R2/R7 ($_fm_l): the maintenance run created $F04J_DROP, which \$SRC holds and the umbrella does not — the stub names ../../.harness/$F04J_DROP, a file the umbrella cannot supply: $_fm_out"
  fi
  for _fm_p in $F04_TIER; do
    diff -r "$F04J_REF/$_fm_p" "$KJ4/$_fm_p" >/dev/null 2>&1 \
      || fail "R7 ($_fm_l): the maintenance run rewrote $_fm_p — a thin tier under an unchanged umbrella must come out byte-identical: $_fm_out"
  done
}
f04j_maintenance ordinary
f04j_maintenance thin --thin
pass "R1/R2/R7 thin_maintenance_tree_comes_from_the_umbrella — an ordinary and a --thin run over a converted child both rebuild its tier from the umbrella, byte for byte"

# ── R2/R6: a tier entry the UMBRELLA does not hold is left alone — not invented, not fatal ─
# thin_umbrella_missing_entry_is_left_alone
#
# The price of making the umbrella body the ONE authority is that it may be OLDER than this
# installer and simply not have a tier entry `$HARNESS_BODY_PROSE` lists yet. Two wrong
# answers were available and each was measured on this fixture:
#   re-source from `$SRC`   what shipped: the child silently gets a stub naming
#                           `../../.harness/specs/glossary.md`, a file the umbrella cannot
#                           supply, and that stub's own text misreads the dangling target as
#                           "a checkout separated from its umbrella". No warning at all.
#   die                     an installer that simply passed the umbrella body down: exit 1,
#                           `source missing: specs/glossary.md`, on an ORDINARY maintenance
#                           run. Every cascade against that umbrella is wedged — including
#                           the ones that would upgrade it — for a path nothing had asked to
#                           be rewritten.
# The rule is SKIP: the entry is left exactly as found, the path is named on stderr, exit 0.
# Both directions are asserted, because "left as found" means different things on each side
# and only both together forbid the two wrong answers.
F04N="$AU/f04n"
mk_umb "$F04N" thinkid
cascade "$F04N"
KN4="$F04N/thinkid/.harness"
f04_all_stubs_in_tier "$KN4" "R2/R6 fixture (a fresh cascade child must be thin)"
cp "$KN4/specs/glossary.md" "$AU/f04n-glossary.ref"
# AN UMBRELLA OLDER THAN THIS INSTALLER, seeded the only way a fixture can: remove from the
# installed umbrella body a tier entry the installer still lists.
rm -f "$F04N/.harness/specs/glossary.md"
if [ -e "$F04N/.harness/specs/glossary.md" ]; then
  fail "R2/R6 control: the umbrella body still holds specs/glossary.md, so nothing below exercises a missing entry"
fi
[ -e "$SRC/specs/glossary.md" ] \
  || fail "R2/R6 control: the installer's own \$SRC does not hold specs/glossary.md either, so this fixture cannot tell the umbrella apart from \$SRC"

# (a) AN ALREADY-THIN CHILD that HOLDS the stub. "Left as found" here means the stub survives
# byte for byte — this is the destructive half, and the one the shipped `$SRC` reference
# passed for the wrong reason.
F04N_OUT="$(CODEX_HOME="$F04N/.ch" HOME="$F04N/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04N/thinkid" 2>&1)" && F04N_RC=0 || F04N_RC=$?
[ "$F04N_RC" = "0" ] \
  || fail "R6: a routine maintenance run against an umbrella that lacks one tier entry exited $F04N_RC — an umbrella older than the installer must not wedge the runs that would upgrade it: $F04N_OUT"
printf '%s\n' 2>/dev/null "$F04N_OUT" | grep -qF "does not hold the prose-tier path 'specs/glossary.md'" \
  || fail "R3/R6: the run skipped a tier entry without naming it, so the operator has no way to learn why that path stopped being maintained: $F04N_OUT"
printf '%s\n' 2>/dev/null "$F04N_OUT" | grep -qF "does not hold the prose-tier path 'agents'" \
  && fail "R6: the run reported 'agents' as missing from the umbrella too — the skip is firing on entries the umbrella does hold, so the message discriminates nothing: $F04N_OUT"
cmp -s "$AU/f04n-glossary.ref" "$KN4/specs/glossary.md" \
  || fail "R2: the maintenance run rewrote or deleted specs/glossary.md, which the umbrella no longer holds — the entry must be left exactly as it was found"
f04_all_stubs_in_tier "$KN4" "R2/R6 (skipping one entry must not disturb the rest of the tier)"

# (b) A FRESH child, which has never held the path. "Left as found" here means ABSENT — the
# direction that forbids inventing a stub the umbrella cannot resolve. The other four entries
# must still be stubbed, or "no dangling stub" is satisfied by a run that wrote nothing.
mk_umb "$F04N" newkid
# `HARNESS_UMBRELLA_ROOT` rather than a cascade: a cascade re-installs the COORDINATOR's own
# prose tier from `$SRC` first, which would restore the entry this fixture just removed.
F04N2_OUT="$(HARNESS_UMBRELLA_ROOT='../../' CODEX_HOME="$F04N/.ch" HOME="$F04N/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04N/newkid" 2>&1)" && F04N2_RC=0 || F04N2_RC=$?
KN5="$F04N/newkid/.harness"
[ "$F04N2_RC" = "0" ] \
  || fail "R6: a fresh child under an umbrella that lacks one tier entry exited $F04N2_RC: $F04N2_OUT"
if [ -e "$KN5/specs/glossary.md" ]; then
  fail "R2: the umbrella does not hold specs/glossary.md and the run created one anyway — the stub names ../../.harness/specs/glossary.md, which the umbrella cannot supply, and its own text then misreads that dangling target as a checkout separated from its umbrella: $F04N2_OUT"
fi
for _p in AGENTS.md agents docs specs/_templates; do
  [ -e "$KN5/$_p" ] \
    || fail "R2/R6 control: the fresh child's $_p was not materialised at all, so 'specs/glossary.md is absent' is explained by a run that wrote no tier: $F04N2_OUT"
done
is_stub "$KN5/agents/builder.md" \
  || fail "R2/R6 control: the fresh child's agents/builder.md is not a stub, so this run did not take the thin arm: $F04N2_OUT"
pass "R2/R6 thin_umbrella_missing_entry_is_left_alone — an entry the umbrella lacks keeps its existing stub, is never invented, is named, and never fails the run"

# ── R4: no --thin converts nothing, and says it would ──────────────────────────────────
# unflagged_previews_only — the on-disk half is TRIVIALLY TRUE (it is today's shipped
# behavior), so it is asserted for the record and the discriminating proof is the preview
# line, in this child's OWN output slice, plus the mutation row.
F04D="$AU/f04d"
f04_fullchild "$F04D" kid
mk_umb "$F04D" freshkid
cascade "$F04D"
f04_no_stub_in_tier "$F04D/kid/.harness" "R4 (an unflagged run must convert nothing)"
F04D_SEG="$(f04_seg "$AU_OUT" "$F04D/kid")"
printf '%s\n' 2>/dev/null "$F04D_SEG" | grep -q 'WOULD convert to the thin layout' \
  || fail "R4: an unflagged run against a convertible full-copy child did not report that it would convert: $F04D_SEG"
printf '%s\n' 2>/dev/null "$F04D_SEG" | grep -q '\-\-thin' \
  || fail "R4: the preview does not name the flag that would perform the conversion: $F04D_SEG"
# The fresh sibling is thin, not full-copy, so it must NOT carry the preview — otherwise
# "the line is present" is reachable without the full-copy branch running at all.
printf '%s\n' 2>/dev/null "$(f04_seg "$AU_OUT" "$F04D/freshkid")" | grep -q 'WOULD convert to the thin layout' \
  && fail "R4: the preview fired for a child that is already thin"
pass "R4 unflagged_previews_only — an unflagged run converts nothing and reports what it would convert"

# ── R4: an unflagged run on a BLOCKED child names the same paths R3 names ──────────────
# unflagged_preview_names_blockers — one code path, so the preview cannot drift from the
# action it previews.
printf '\nlocal edit\n' >> "$F04D/kid/.harness/agents/orchestrator.md"
printf 'child-only\n' > "$F04D/kid/.harness/docs/LOCAL-NOTE.md"
cascade "$F04D"
F04D_SEG2="$(f04_seg "$AU_OUT" "$F04D/kid")"
for _p in agents/orchestrator.md docs/LOCAL-NOTE.md; do
  printf '%s\n' 2>/dev/null "$F04D_SEG2" | grep -qF "differs: $_p" \
    || fail "R4: the UNFLAGGED preview did not name the blocking path $_p: $F04D_SEG2"
done
printf '%s\n' 2>/dev/null "$F04D_SEG2" | grep -q 'WOULD convert to the thin layout' \
  && fail "R4: a blocked child was reported as convertible"
f04_no_stub_in_tier "$F04D/kid/.harness" "R4 (blocked, unflagged)"
pass "R4 unflagged_preview_names_blockers — the unflagged report names exactly the paths the flagged refusal does"

# ── R6: --thin against an unreachable umbrella warns, converts nothing, exits 0 ─────────
# thin_unreachable_umbrella_is_not_fatal
#
# "MOVE THE UMBRELLA" DOES NOT PRODUCE AN UNREACHABLE UMBRELLA: the cascade records a
# RELATIVE root (`../../`), so renaming the umbrella dir moves the child with it and the
# root still resolves — the case would quietly exercise the ordinary path. What actually
# breaks resolution while leaving a non-empty umbrella.root is removing the umbrella's
# installed-body marker.
#
# The fixture starts as a FULL-COPY child of a REACHABLE umbrella. Starting from an
# already-thin child is the trap: the copy branch re-materialises a full body, so "the body
# is still full-copy" would pass with R6 unimplemented.
F04E="$AU/f04e"
f04_fullchild "$F04E" kid
rm -f "$F04E/.harness/.harness-version"
# Single-target, NOT a cascade: a cascade would re-install the coordinator and restore the
# very marker this case removes.
F04E_OUT="$(CODEX_HOME="$F04E/.ch" HOME="$F04E/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$F04E/kid" 2>&1)" && F04E_RC=0 || F04E_RC=$?
[ "$F04E_RC" = "0" ] \
  || fail "R6: --thin with an unreachable umbrella exited $F04E_RC — refusing to convert is a warning, never an install failure: $F04E_OUT"
printf '%s\n' 2>/dev/null "$F04E_OUT" | grep -q 'umbrella.root is recorded' \
  || fail "R6: the unreachable umbrella was not reported: $F04E_OUT"
f04_no_stub_in_tier "$F04E/kid/.harness" "R6 (nothing may convert with the umbrella unreachable)"
grep -qF 'You are the **Builder**' "$F04E/kid/.harness/agents/builder.md" \
  || fail "R6: the child's full local body was not kept in place"
grep -q '^  root: "\.\./\.\./"' "$F04E/kid/.harness/harness.config.yaml" \
  || fail "R6: umbrella.root was cleared by a run that only refused to convert"
pass "R6 thin_unreachable_umbrella_is_not_fatal — warns, converts nothing, keeps the full copy, exits 0"

# ── R2/R6: a SELF-REFERENTIAL umbrella.root is refused, in every spelling ───────────────
# thin_refuses_self_referential_umbrella_root
#
# `umbrella.root: "../"` on a target that is not a child resolves to that target's OWN
# `.harness`, and that path passed every strictness rule umbrella_body_dir had: a directory,
# not a symlink, holding `.harness-version`. prose_tier_blockers then compared the tier with
# ITSELF, found no blocker, and --thin reported CONVERTED while replacing every prose file
# with a stub whose authoritative path is `../.harness/<rel>` — i.e. each stub named ITSELF.
# Measured on a plain single-target install plus that one edit: 30 stubs, 0 real prose files
# left, exit 0, and a ✅ line saying it had converted. (Codex r2 P1 #3799616443.)
#
# NO UMBRELLA IS INSTALLED ABOVE THE TARGET, deliberately. The resolved body IS the target's
# own, so an ordinary single-target install plus one hand edit is the whole fixture — and a
# hand edit is exactly how this key gets a bad value, since the product only ever writes the
# cascade's own `../../`.
#
# FOUR SPELLINGS, because the refusal must compare RESOLVED PHYSICAL paths and not the
# configured string: `../`, `./../`, the absolute path, and a route through a symlink. Only
# the first is killed by a string comparison against `../`; the other three are what make
# `pwd -P` on both sides load-bearing.
F04K="$AU/f04k"
mk_umb "$F04K" tgt
CODEX_HOME="$F04K/.ch" HOME="$F04K/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04K/tgt" >/dev/null 2>&1 \
  || fail "R2 self-ref fixture: the single-target install failed"
KK4="$F04K/tgt/.harness"
f04_no_stub_in_tier "$KK4" "R2 self-ref fixture (the target must start full-copy)"
# PRECONDITIONS. The root about to be written must resolve to an INSTALLED body — otherwise
# this is R6's unreachable-umbrella case wearing a different config value, and it would pass
# with the self-reference refusal absent entirely.
[ -f "$KK4/.harness-version" ] \
  || fail "R2 self-ref control: the target carries no installed-body marker, so a self-referential root would be refused as UNREACHABLE and this case would prove nothing"
[ -e "$F04K/.harness" ] \
  && fail "R2 self-ref control: a real umbrella body exists above the target, so the root under test could resolve to something other than the target itself"
ln -sfn . "$F04K/tgt/f04k-self"
for _s in '../' './../' "$(f04_phys "$F04K/tgt")" '../f04k-self/'; do
  sed "s|^  root: .*|  root: \"$_s\"|" "$KK4/harness.config.yaml" > "$KK4/hc.t" \
    && mv "$KK4/hc.t" "$KK4/harness.config.yaml"
  grep -qF "root: \"$_s\"" "$KK4/harness.config.yaml" \
    || fail "R2 self-ref setup: the root spelling $_s was not written to the config"
  F04K_OUT="$(CODEX_HOME="$F04K/.ch" HOME="$F04K/.home" \
    sh "$SRC/harness-install.sh" --agents=claude --thin "$F04K/tgt" 2>&1)" && F04K_RC=0 || F04K_RC=$?
  [ "$F04K_RC" = "0" ] \
    || fail "R2: --thin with a self-referential umbrella.root ($_s) exited $F04K_RC — a nonsense root is a warning, never an install failure: $F04K_OUT"
  printf '%s\n' 2>/dev/null "$F04K_OUT" | grep -q 'CONVERTED to the thin layout' \
    && fail "R2: umbrella.root ($_s) resolves to the target's OWN .harness and --thin CONVERTED it — every prose file is now a stub naming itself, so the child has no readable prose body at all: $F04K_OUT"
  f04_no_stub_in_tier "$KK4" "R2 (self-referential umbrella.root: $_s)"
  # The refusal must come from the ROOT, not from blocking paths. Compared against itself
  # the tier is pristine by construction, so a `differs:` line here would mean the fixture
  # stopped being convertible and the guard was never the reason anything survived.
  printf '%s\n' 2>/dev/null "$F04K_OUT" | grep -q 'differs: ' \
    && fail "R2 self-ref control: the run refused by naming blocking paths instead of refusing the root — this tier is byte-identical to itself, so it would convert if the root were honoured: $F04K_OUT"
  printf '%s\n' 2>/dev/null "$F04K_OUT" | grep -qF 'cannot be its own umbrella' \
    || fail "R2: the self-referential root ($_s) was not reported — an operator who hand-wrote it is told nothing: $F04K_OUT"
done
grep -qF 'You are the **Builder**' "$KK4/agents/builder.md" \
  || fail "R2: the target's real prose body did not survive a self-referential umbrella.root"
pass "R2 thin_refuses_self_referential_umbrella_root — a root resolving to the target's own .harness is refused in all four spellings, and the full body survives"

# ── R2: a failure PART-WAY THROUGH the write leaves the tier WHOLE ──────────────────────
# thin_partial_failure_leaves_tier_whole
#
# R2's all-or-nothing rule is about the tier, not only about the pristine check: a write
# that converted entries 1-3 and then died on entry 4 produced exactly the mixed layout the
# rule forbids. Measured on the sequential implementation with this fixture: 20 stubs and 10
# real files in one child. (Codex r2 P2 #3799616454.)
#
# THE ONLY PORTABLE MID-WRITE FAILURE this suite can build is a read-only directory INSIDE
# the child's prose tier. `.harness/specs` holds tier entries 4 and 5 of 5, so entries 1-3
# have already been swapped by the time the write reaches it, and moving `specs/_templates`
# out of a 0555 directory is refused. It needs no root and no platform tricks.
F04L="$AU/f04l"
f04_fullchild "$F04L" kid
KL4="$F04L/kid/.harness"
chmod 0555 "$KL4/specs"
F04L_OUT="$(CODEX_HOME="$F04L/.ch" HOME="$F04L/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --thin "$F04L/kid" 2>&1)" && F04L_RC=0 || F04L_RC=$?
chmod -R u+w "$KL4/specs"
[ "$F04L_RC" = "0" ] \
  && fail "R2 control: --thin SUCCEEDED with a read-only specs/ directory, so the write never failed and nothing below discriminates: $F04L_OUT"
# The failure has to be the PROSE-TIER WRITE's, reached with earlier entries already
# swapped. An abort before the write would leave the tier whole for free and satisfy every
# assertion below while proving nothing about all-or-nothing.
printf '%s\n' 2>/dev/null "$F04L_OUT" | grep -qF 'could not install the thin prose tier' \
  || fail "R2 control: the run failed somewhere other than the prose-tier write, so no swap was ever rolled back: $F04L_OUT"
f04_no_stub_in_tier "$KL4" "R2 (a write that fails part-way must convert NOTHING)"
# BYTES, not presence. The child was byte-identical to the umbrella's copy before the run —
# that is what made it convertible — so it must still be, entry for entry, in both
# directions. This is what catches a rollback that restores a path but not its contents,
# and a partial write that left one entry stubbed.
for _p in $F04_TIER; do
  diff -r "$F04L/.harness/$_p" "$KL4/$_p" >/dev/null 2>&1 \
    || fail "R2: after a write that failed part-way, the child's $_p no longer matches the umbrella's copy it was byte-identical to — the tier was left changed"
done
# A rolled-back run leaves `.harness` as it found it: no staging debris for the operator to
# find, and nothing for the landing audit or the drift guard to trip over.
F04L_DEBRIS="$(ls -d "$KL4"/.harness-prose-* 2>/dev/null || true)"
[ -z "$F04L_DEBRIS" ] \
  || fail "R2: the rolled-back run left staging directories inside .harness: $F04L_DEBRIS"

# THE OTHER HALF OF THE WRITE, and it needs its own trigger. The check above fails while
# entries are being SWAPPED IN; this one fails while they are still being BUILT. They are
# different arms and only one mechanism covers each: the swap is undone by the rollback, the
# build is a no-op on the child because nothing is swapped until ALL of it has been built.
# Collapse the two phases back into one loop — build entry N, swap entry N, then start
# N+1 — and the rollback does not cover the build at all: four entries land and the fifth
# does not, while the run still says nothing was replaced. Verified against exactly that
# mutant, which every other case in this suite survives.
#
# THE TRIGGER IS SEEDED IN THE UMBRELLA BODY, and it has to be: the umbrella body is the
# ONLY tree a thin tier is ever built from, so a doctored `$SRC` no longer reaches this code
# path at all. And it is seeded as an UNREADABLE REGULAR FILE, not as a missing entry: an
# entry the umbrella does not hold is deliberately SKIPPED now (see
# thin_umbrella_missing_entry_is_left_alone), so absence cannot fail a build. An unreadable
# file inside `specs/_templates` — tier entry 4 of 5 — makes `cp -R` fail with entries 1-3
# already staged, needs no root, and leaves a staging tree `rm -rf` can still remove, which a
# 0000 DIRECTORY would not.
F04M="$AU/f04m"
mk_umb "$F04M" kid
cascade "$F04M"
[ -f "$F04M/.harness/.harness-version" ] \
  || fail "R2 build-half fixture: the umbrella body was not installed"
F04M_VICTIM="$(find "$F04M/.harness/specs/_templates" -type f | head -n 1)"
[ -n "$F04M_VICTIM" ] \
  || fail "R2 build-half control: the umbrella body's specs/_templates holds no regular file to make unreadable, so the build cannot be made to fail"
chmod 0000 "$F04M_VICTIM"
# A FRESH child, so "the tier was not written" is observable as ABSENCE. An already-thin
# child cannot serve: the stubs a partial re-run would write are byte-identical to the ones
# already there, so the two outcomes are indistinguishable on disk.
#
# `HARNESS_UMBRELLA_ROOT` rather than `--umbrella`: it is the cascade's own interface to
# install_one, and a real cascade cannot be used here because it re-installs the COORDINATOR
# first — the full-copy branch replaces the umbrella's own prose tier from `$SRC` and heals
# the unreadable file before any child is reached.
mk_umb "$F04M" fresh
F04M_OUT="$(HARNESS_UMBRELLA_ROOT='../../' CODEX_HOME="$F04M/.ch" HOME="$F04M/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04M/fresh" 2>&1)" && F04M_RC=0 || F04M_RC=$?
chmod 0644 "$F04M_VICTIM"
[ "$F04M_RC" = "0" ] \
  && fail "R2 build-half control: the install SUCCEEDED with an unreadable file in the umbrella's prose tier, so the build never failed: $F04M_OUT"
printf '%s\n' 2>/dev/null "$F04M_OUT" | grep -qF 'could not build the thin prose tier' \
  || fail "R2 build-half control: the run failed somewhere other than building the prose tier: $F04M_OUT"
for _p in $F04_TIER; do
  [ -e "$F04M/fresh/.harness/$_p" ] \
    && fail "R2: the thin prose tier failed to BUILD and yet $_p was written — the tier is part-written while the run reports that nothing was replaced: $F04M_OUT"
done
pass "R2 thin_partial_failure_leaves_tier_whole — a write that fails part-way leaves the tier whole in both halves: a failed swap rolls the earlier swaps back, and a failed build writes nothing at all"

# ── R9/R10/R11: --standalone, the documented way back ──────────────────────────────────
# standalone_materialises_body / standalone_clears_umbrella_root / standalone_is_idempotent
F04F="$AU/f04f"
mk_umb "$F04F" kid
cascade "$F04F"
SK="$F04F/kid/.harness"
f04_all_stubs_in_tier "$SK" "R9 fixture (a fresh cascade child must be thin)"
# WHAT THE STUB'S OWN RECOVERY TEXT PRESCRIBES, run as written. That text is stamped into
# EVERY stub in every child, so it is the instruction most operators will actually follow, and
# an unflagged re-install of a thin child lands on the MAINTENANCE arm and leaves it thin — the
# promised full local copy never appears. The flag is the reverse operation; the text has to
# name it. (Codex #3802057876.)
F04F_PLAIN="$(CODEX_HOME="$F04F/.ch" HOME="$F04F/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04F/kid" 2>&1)" && F04F_RC=0 || F04F_RC=$?
[ "$F04F_RC" = "0" ] || fail "R9: an unflagged re-install of a thin child exited $F04F_RC: $F04F_PLAIN"
f04_all_stubs_in_tier "$SK" "R9 (an UNFLAGGED re-install must leave a thin child THIN — if it materialised the body on its own, the stub's text would need no flag and the assertion below would be measuring nothing)"
grep -qiF 'with `--standalone`' "$SK/agents/builder.md" \
  || fail "R9/R3: the stub's recovery text does not name --standalone, and the unflagged run it prescribes has just left this target thin: $(grep -i 'installer against' "$SK/agents/builder.md")"
# R10's CONTROL: another key in the same section, plus a hand-editable value elsewhere in
# the file. A writer that "cleared" the key by truncating the umbrella: section, or by
# rewriting the config from the shipped template, would otherwise pass.
sed -e 's|^  manifest: .*|  manifest: "../umbrella.manifest.yaml"|' \
    -e 's|^  test_command: .*|  test_command: "echo f04-hand-edited"|' \
    "$SK/harness.config.yaml" > "$SK/hc.t" && mv "$SK/hc.t" "$SK/harness.config.yaml"
grep -q '^  manifest: "\.\./umbrella\.manifest\.yaml"' "$SK/harness.config.yaml" \
  || fail "R10 setup: the control key was not seeded"

F04F_OUT="$(CODEX_HOME="$F04F/.ch" HOME="$F04F/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --standalone "$F04F/kid" 2>&1)" && F04F_RC=0 || F04F_RC=$?
[ "$F04F_RC" = "0" ] || fail "R9: --standalone exited $F04F_RC: $F04F_OUT"
f04_no_stub_in_tier "$SK" "R9 (--standalone must replace every stub with the real body)"
grep -qF 'You are the **Builder**' "$SK/agents/builder.md" \
  || fail "R9: agents/builder.md was not materialised from the installer's own source"
grep -qF 'harness-sdd' "$SK/AGENTS.md" \
  || fail "R9: the regular-file tier entry AGENTS.md was not materialised"
grep -q 'This target holds the full body layout' "$SK/manifest.txt" \
  || fail "R9: a re-materialised target's manifest does not report the full layout"
pass "R9 standalone_materialises_body — every stub is replaced by the real body file"

grep -q '^  root: ""$' "$SK/harness.config.yaml" \
  || fail "R10: --standalone did not clear umbrella.root: $(grep '^  root:' "$SK/harness.config.yaml")"
grep -q '^  manifest: "\.\./umbrella\.manifest\.yaml"' "$SK/harness.config.yaml" \
  || fail "R10: clearing umbrella.root also rewrote umbrella.manifest — the writer is not section-scoped"
grep -q '^  test_command: "echo f04-hand-edited"' "$SK/harness.config.yaml" \
  || fail "R10: clearing umbrella.root discarded a hand-edited value elsewhere in the config"
pass "R10 standalone_clears_umbrella_root — the key is cleared, its neighbours are untouched"

# R11 is NOT "the bytes did not change": --standalone takes the ordinary copy branch, so a
# stale or edited target legitimately comes out re-installed from source. The claim is the
# LAYOUT, the cleared key and exit 0.
F04G_OUT="$(CODEX_HOME="$F04F/.ch" HOME="$F04F/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --standalone "$F04F/kid" 2>&1)" && F04G_RC=0 || F04G_RC=$?
[ "$F04G_RC" = "0" ] || fail "R11: --standalone on an already-full-copy target exited $F04G_RC: $F04G_OUT"
f04_no_stub_in_tier "$SK" "R11 (--standalone on a full-copy target keeps it full-copy)"
grep -q '^  root: ""$' "$SK/harness.config.yaml" \
  || fail "R11: umbrella.root is no longer cleared after a second --standalone run"
grep -q 'This target holds the full body layout' "$SK/manifest.txt" \
  || fail "R11: the target left the full-copy layout on a repeat --standalone run"
pass "R11 standalone_is_idempotent — a full-copy target stays full-copy, key stays cleared, exit 0"

# ── docs contract: docs/UMBRELLA.md documents the migration and the reverse ─────────────
# f04_docs_contract. FENCE-AWARE extraction: the bare house awk idiom stops at the first
# `#` inside a fenced block, and T12 adds new fences to this very file — a `#` comment in
# one would truncate the span and make every assertion below pass over text it never read.
F04DOC="$SRC/docs/UMBRELLA.md"
f04_span() { awk -v h="$2" '/^```/{f=!f} !f && /^## /{k=(index($0,h)>0);next} k' "$1"; }

F04MIG="$(f04_span "$F04DOC" 'Migrating an existing child')"
[ -n "$F04MIG" ] || fail "f04_docs_contract: docs/UMBRELLA.md has no 'Migrating an existing child' section"
# The migration COMMAND, and the absence assertion that matters: EVERY cascade invocation
# in that section carries --thin. An unflagged cascade presented as step one is the wrong
# doc a reviewer is most likely to write, and it destroys the differences it reports.
F04N_ALL="$(printf '%s\n' 2>/dev/null "$F04MIG" | grep -o 'harness-install\.sh --umbrella' | wc -l | tr -d ' ')"
F04N_THIN="$(printf '%s\n' 2>/dev/null "$F04MIG" | grep -o 'harness-install\.sh --umbrella [^ ]* --thin' | wc -l | tr -d ' ')"
[ "$F04N_ALL" -ge 1 ] \
  || fail "f04_docs_contract: the migration section never names 'harness-install.sh --umbrella … --thin'"
[ "$F04N_ALL" = "$F04N_THIN" ] \
  || fail "f04_docs_contract: $F04N_ALL cascade invocation(s) in the migration section, only $F04N_THIN carry --thin — an unflagged cascade is being presented as a migration step, and that branch overwrites the prose tier from source"
printf '%s\n' 2>/dev/null "$F04MIG" | grep -qi 'until it converges' \
  || fail "f04_docs_contract: the migration procedure does not say to re-run until it converges"
printf '%s\n' 2>/dev/null "$F04MIG" | grep -qi 'whole or not at all' \
  || fail "f04_docs_contract: the all-or-nothing rule is not stated in the migration section"
printf '%s\n' 2>/dev/null "$F04MIG" | grep -qi 'does not resolve to an installed harness body' \
  || fail "f04_docs_contract: the unreachable-umbrella behavior is not documented in the migration section"

F04STA="$(f04_span "$F04DOC" 'the way back')"
[ -n "$F04STA" ] || fail "f04_docs_contract: docs/UMBRELLA.md has no '--standalone — the way back' section"
printf '%s\n' 2>/dev/null "$F04STA" | grep -q 'harness-install\.sh --standalone' \
  || fail "f04_docs_contract: the --standalone section never shows the command"
printf '%s\n' 2>/dev/null "$F04STA" | grep -qi 'cleared' \
  || fail "f04_docs_contract: the --standalone section does not say umbrella.root is cleared"
printf '%s\n' 2>/dev/null "$F04STA" | grep -qi 'not a permanent opt-out' \
  || fail "f04_docs_contract: the --standalone section oversells the flag — clearing the key is not a permanent opt-out"
pass "f04_docs_contract — docs/UMBRELLA.md documents the migration command, the all-or-nothing rule and the reverse"

echo "All umbrella tests passed."
