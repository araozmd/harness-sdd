#!/bin/sh
# test_board_lock.sh — behavioural suite for the board write lock (E15-F01).
#
# Exercises tools/tasks-lock.py against TEMP-DIR fixtures (never the live
# state/tasks.json), proving the LOCKING BEHAVIOUR the spec requires:
#   R1 two concurrent writers both survive (no lost update)
#   R2 the held lock re-reads from disk (applies on top of the other's write)
#   R3 sibling lockfile acquired/held/released for the critical section
#   R4 an invalid mutation fails stop, releases the lock, leaves the file intact
#   R5 a held lock past the timeout aborts non-zero with a clear, bounded error
#   R6 a serial write is byte-equivalent to a plain read-modify-write
#   R7 the on_write_command hook is observable only AFTER the lock is released
#   R8 no schema/status change; a serial write validates and adds no new status
#   R9 the lock uses stdlib fcntl.flock (python3), not the flock(1) binary
#   R11 VERSION advanced (a MINOR bump, compared not frozen) + CHANGELOG entry
#
# Constraints (permanent-suite anti-pattern): never freeze the exact VERSION
# literal, never diff DO-NOT-TOUCH files against main, never touch the live
# state/tasks.json — every case uses a temp dir with HARNESS_DIR pointed at it.
#
# Zero deps: POSIX sh + grep + python3.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELPER="$ROOT/tools/tasks-lock.py"
# tasks-lock.py imports the SHARED validator from its sibling validate-board.py,
# so any temp tools/ layout the tests build must copy BOTH files.
VALIDATOR="$ROOT/tools/validate-board.py"
SCHEMA="$ROOT/store/tasks.schema.json"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

[ -f "$HELPER" ] || fail "tools/tasks-lock.py missing"
[ -f "$VALIDATOR" ] || fail "tools/validate-board.py (shared validator) missing"

# ── shared fixture builder ────────────────────────────────────────────────────
# make_fixture <dir> — seed a valid two-feature board + schema under <dir>.
make_fixture() {
  _d="$1"
  mkdir -p "$_d/state" "$_d/store"
  cp "$SCHEMA" "$_d/store/tasks.schema.json"
  cat > "$_d/state/tasks.json" <<'EOF'
{
  "project": "fixture",
  "epics": [
    {
      "id": "E01",
      "title": "epic one",
      "status": "planned",
      "features": [
        { "id": "E01-F01", "title": "feature one", "status": "pending", "sdd": true, "spec_path": "a" },
        { "id": "E01-F02", "title": "feature two", "status": "pending", "sdd": true, "spec_path": "b" }
      ]
    }
  ]
}
EOF
}

# status_of <board.json> <feature-id> — print a feature's status.
status_of() {
  python3 -c "import json,sys
d=json.load(open(sys.argv[1]))
for e in d['epics']:
  for f in e['features']:
    if f['id']==sys.argv[2]: print(f['status'])" "$1" "$2"
}

# ── R1/R2: two concurrent writers both survive (no lost update) ───────────────
# test_concurrent_writers_no_lost_update / test_reread_inside_lock_sees_prior_write
# Each writer sleeps INSIDE its mutation to force the critical sections to overlap;
# if the re-read did NOT happen inside the lock, one transition would be clobbered.
# Repeated in a small loop to shake out timing.
concurrent_case() {
  _i="$1"
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
  make_fixture "$T"

  cat > "$T/mut1.py" <<'EOF'
import time
def mutate(data):
    time.sleep(0.2)
    for e in data['epics']:
        for f in e['features']:
            if f['id'] == 'E01-F01': f['status'] = 'in-progress'
    return data
EOF
  cat > "$T/mut2.py" <<'EOF'
import time
def mutate(data):
    time.sleep(0.2)
    for e in data['epics']:
        for f in e['features']:
            if f['id'] == 'E01-F02': f['status'] = 'in-review'
    return data
EOF

  HARNESS_DIR="$T" python3 "$HELPER" apply --mutator "$T/mut1.py" --timeout 10 &
  _p1=$!
  HARNESS_DIR="$T" python3 "$HELPER" apply --mutator "$T/mut2.py" --timeout 10 &
  _p2=$!
  wait "$_p1" || fail "R1: concurrent writer 1 exited non-zero (iter $_i)"
  wait "$_p2" || fail "R1: concurrent writer 2 exited non-zero (iter $_i)"

  [ "$(status_of "$T/state/tasks.json" E01-F01)" = "in-progress" ] \
    || fail "R1/R2: E01-F01 transition lost under contention (iter $_i) — last-writer-wins clobber"
  [ "$(status_of "$T/state/tasks.json" E01-F02)" = "in-review" ] \
    || fail "R1/R2: E01-F02 transition lost under contention (iter $_i) — last-writer-wins clobber"
  # the file must still parse (never torn)
  python3 -c "import json;json.load(open('$T/state/tasks.json'))" \
    || fail "R1: board unparsable after concurrent writes (iter $_i)"
  rm -rf "$T"
}
_i=1
while [ "$_i" -le 5 ]; do concurrent_case "$_i"; _i=$((_i + 1)); done
pass "R1/R2 concurrent writers both survive; re-read inside lock (no lost update)"

# ── R3: sibling lockfile acquired/held/released for the critical section ──────
# test_lockfile_is_sibling_and_released
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
[ -e "$T/state/tasks.json.lock" ] && fail "R3: lockfile pre-exists before any call"
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-progress \
  || fail "R3: first call failed"
[ -f "$T/state/tasks.json.lock" ] \
  || fail "R3: sibling lockfile state/tasks.json.lock not created next to tasks.json"
# released: an immediate subsequent call in the same dir succeeds without timeout.
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F02 in-review --timeout 2 \
  || fail "R3: lock not released — a subsequent immediate call timed out"
[ "$(status_of "$T/state/tasks.json" E01-F02)" = "in-review" ] \
  || fail "R3: subsequent call did not apply"
rm -rf "$T"
pass "R3 lockfile is a released sibling of tasks.json (cwd = HARNESS_DIR)"

# ── R4: invalid mutation → fail-stop, lock released, original intact ──────────
# test_invalid_mutation_fail_stop_original_intact
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
cp "$T/state/tasks.json" "$T/before.json"
cat > "$T/badmut.py" <<'EOF'
def mutate(data):
    data['epics'][0]['features'][0]['status'] = 'NOT-A-STATUS'
    return data
EOF
if HARNESS_DIR="$T" python3 "$HELPER" apply --mutator "$T/badmut.py" 2>"$T/err.txt"; then
  fail "R4: invalid mutation did not exit non-zero"
fi
cmp -s "$T/before.json" "$T/state/tasks.json" \
  || fail "R4: original state/tasks.json was modified/torn on a failed validation"
# lock released after the abort: a following VALID call must succeed.
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-progress --timeout 2 \
  || fail "R4: lock not released after fail-stop — following valid call timed out"
rm -rf "$T"
pass "R4 invalid mutation fails stop, releases lock, leaves original intact"

# also: corrupt-JSON producing mutator is caught (parse check)
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
cp "$T/state/tasks.json" "$T/before.json"
cat > "$T/dropmut.py" <<'EOF'
def mutate(data):
    del data['epics']            # schema-invalid: 'epics' is required
    return data
EOF
if HARNESS_DIR="$T" python3 "$HELPER" apply --mutator "$T/dropmut.py" 2>/dev/null; then
  fail "R4: structurally-invalid mutation did not exit non-zero"
fi
cmp -s "$T/before.json" "$T/state/tasks.json" \
  || fail "R4: original board changed on a structurally-invalid mutation"
rm -rf "$T"
pass "R4 structurally-invalid mutation also fails stop (parse+schema)"

# ── R5: held lock past the timeout → bounded non-zero error naming lock+timeout ─
# test_acquire_timeout_bounded_clear_error
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
cat > "$T/holder.py" <<EOF
import fcntl, os, time
fd = os.open("$T/state/tasks.json.lock", os.O_RDWR | os.O_CREAT, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
open("$T/held.flag", "w").close()
time.sleep(8)
EOF
python3 "$T/holder.py" &
_hp=$!
# wait until the holder actually holds the lock
until [ -f "$T/held.flag" ]; do sleep 0.05; done
_start="$(python3 -c 'import time;print(time.time())')"
if HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 done --timeout 1 2>"$T/terr.txt"; then
  kill "$_hp" 2>/dev/null || true
  fail "R5: acquisition against a held lock did NOT exit non-zero (silent proceed?)"
fi
_end="$(python3 -c 'import time;print(time.time())')"
# bounded: must return within a small multiple of the timeout (not the 8s hold).
python3 -c "import sys; sys.exit(0 if ($_end - $_start) < 5 else 1)" \
  || fail "R5: acquisition blocked well past the timeout (not bounded)"
grep -qF "state/tasks.json.lock" "$T/terr.txt" \
  || fail "R5: timeout error does not name the lockfile"
grep -qiE 'within|timeout|1s' "$T/terr.txt" \
  || fail "R5: timeout error does not name the timeout"
kill "$_hp" 2>/dev/null || true
wait "$_hp" 2>/dev/null || true
rm -rf "$T"
pass "R5 held-lock acquisition aborts bounded + clear error (names lockfile+timeout)"

# ── R6: serial write is a MINIMAL-DIFF read-modify-write (formatting preserved) ─
# test_serial_caller_result_unchanged
# The write must change ONLY the addressed status VALUE and leave every other byte
# of the file untouched — the promised serial byte-equivalence. We assert this
# against a fixture whose feature objects are INLINE/COMPACT (not indent=2-expanded)
# so a naive parse→json.dumps(indent=2)→write would rewrite unrelated lines; the
# minimal-diff helper must not. The "plain read-modify-write" baseline here is a
# byte-preserving textual edit of just the target status.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
# Baseline: edit only the target status token in the ORIGINAL text (formatting
# preserved) — this is what a minimal-diff read-modify-write yields.
cp "$T/state/tasks.json" "$T/plain.json"
python3 - "$T/plain.json" <<'EOF'
import re, sys
p = sys.argv[1]
t = open(p).read()
m_id = re.search(r'"id"\s*:\s*"E01-F01"', t)
m_st = re.search(r'"status"\s*:\s*"([^"]*)"', t[m_id.end():])
s = m_id.end() + m_st.start(1); e = m_id.end() + m_st.end(1)
open(p, 'w').write(t[:s] + 'in-progress' + t[e:])
EOF
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-progress \
  || fail "R6: serial helper call failed"
cmp -s "$T/state/tasks.json" "$T/plain.json" \
  || fail "R6: helper output differs byte-for-byte from a minimal-diff read-modify-write"
rm -rf "$T"
pass "R6 serial (uncontended) write is a minimal-diff read-modify-write (formatting preserved)"

# ── R6b: a single set-status on a COMPACT board changes ONLY the target line ───
# test_minimal_diff_leaves_unrelated_inline_arrays_untouched  (Codex #46 r3 P2,
# id 3649236637): a board with inline/compact `depends_on` arrays (NOT indent=2-
# expanded) must, after one set-status, differ from the before-image by EXACTLY
# the one status delta — every unrelated inline array/line stays byte-identical.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
mkdir -p "$T/state" "$T/store"
cp "$SCHEMA" "$T/store/tasks.schema.json"
# Deliberately NON-canonical formatting: inline compact depends_on arrays and
# inline feature objects that json.dumps(indent=2) would reformat.
cat > "$T/state/tasks.json" <<'EOF'
{
  "project": "fixture",
  "epics": [
    {
      "id": "E15",
      "title": "epic",
      "status": "planned",
      "features": [
        { "id": "E15-F01", "title": "f one", "status": "in-progress", "sdd": true, "spec_path": "a" },
        { "id": "E15-F02", "title": "f two", "status": "pending", "sdd": true, "spec_path": "b", "depends_on": ["E15-F01"] },
        { "id": "E15-F03", "title": "f three", "status": "pending", "sdd": true, "spec_path": "c", "depends_on": ["E15-F01", "E15-F02"] }
      ]
    }
  ]
}
EOF
cp "$T/state/tasks.json" "$T/before.json"
# A no-op-shaped single transition: only E15-F01's status flips to in-review.
HARNESS_DIR="$T" python3 "$HELPER" set-status E15-F01 in-review \
  || fail "R6b: set-status on the compact board failed"
# Exactly ONE line differs, and it is precisely the status delta on the target.
_ndiff="$(diff "$T/before.json" "$T/state/tasks.json" | grep -cE '^[<>]')"
[ "$_ndiff" -eq 2 ] \
  || fail "R6b: expected exactly one changed line (2 diff sides), got $_ndiff — unrelated lines were reformatted"
diff "$T/before.json" "$T/state/tasks.json" | grep -qE '^> .*"E15-F01".*"status": "in-review"' \
  || fail "R6b: the changed line is not the target status delta"
# The unrelated F02/F03 inline depends_on arrays are byte-identical before/after.
grep -F '"depends_on": ["E15-F01"]' "$T/state/tasks.json" >/dev/null \
  || fail "R6b: F02 inline depends_on array was reformatted"
grep -F '"depends_on": ["E15-F01", "E15-F02"]' "$T/state/tasks.json" >/dev/null \
  || fail "R6b: F03 inline depends_on array was reformatted"
rm -rf "$T"
pass "R6b single set-status on a compact board changes only the target status line (inline arrays intact)"

# ── R7: on_write_command hook observable only AFTER the lock is released ───────
# test_hook_fires_after_release
# The helper never runs the hook; the caller runs it after the helper returns.
# Prove the critical section is CLOSED by the time a post-release step runs: a
# hook that itself acquires the lock must succeed without timing out.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-progress \
  || fail "R7: setup write failed"
# emulate the caller's post-release hook step: acquire the lock ourselves.
cat > "$T/hook.py" <<EOF
import fcntl, os, sys
fd = os.open("$T/state/tasks.json.lock", os.O_RDWR | os.O_CREAT, 0o644)
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)   # must succeed => lock free
except OSError:
    sys.exit(1)
fcntl.flock(fd, fcntl.LOCK_UN)
EOF
python3 "$T/hook.py" \
  || fail "R7: lock still held after helper returned — hook would run inside the critical section"
# and the helper must not itself INVOKE any hook (no shell-out to a sync command):
# it may name on_write_command in a comment explaining the after-release contract,
# but it must never call subprocess/os.system to run it.
if grep -nE "subprocess|os\.system|os\.popen|os\.exec" "$HELPER" >/dev/null 2>&1; then
  fail "R7: helper shells out to a subprocess — the on_write_command hook must be the caller's job (after release)"
fi
rm -rf "$T"
pass "R7 lock is released before any post-write hook could run; helper runs no hook"

# ── R8: no schema/status change; serial write validates, adds no new status ───
# test_no_schema_or_status_change
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-review \
  || fail "R8: serial write failed"
# the serial output validates against the (unchanged) schema and carries only
# enum-legal statuses.
python3 - "$T/state/tasks.json" "$SCHEMA" <<'EOF'
import json, re, sys
d = json.load(open(sys.argv[1]))
s = json.load(open(sys.argv[2]))
feat_enum = set(s['properties']['epics']['items']['properties']['features']
                ['items']['properties']['status']['enum'])
epic_enum = set(s['properties']['epics']['items']['properties']['status']['enum'])
for e in d['epics']:
    assert e['status'] in epic_enum, "epic status %r not in schema enum" % e['status']
    for f in e['features']:
        assert f['status'] in feat_enum, "feature status %r not in schema enum" % f['status']
EOF
# and the schema shipped in the repo is unchanged by the feature: the helper
# reads it, never writes it (no write path to store/tasks.schema.json exists).
grep -q 'tasks.schema.json' "$HELPER" || fail "R8: helper does not consult the schema at all"
grep -qE "open\([^)]*schema[^)]*,\s*['\"]w" "$HELPER" \
  && fail "R8: helper opens the schema for writing (must be read-only)"
rm -rf "$T"
pass "R8 no new status/enum; serial write validates against the unchanged schema"

# ── R9: portable stdlib fcntl.flock, no flock(1) binary dependency ────────────
# test_no_flock1_binary_dependency
grep -qF 'import fcntl' "$HELPER" \
  || fail "R9: helper does not import stdlib fcntl (portable advisory lock)"
grep -qF 'fcntl.flock' "$HELPER" \
  || fail "R9: helper does not call fcntl.flock"
# it must NOT shell out to the Linux-only flock(1) binary. A prose mention of
# "flock(1)" in a comment is fine; an actual INVOCATION (subprocess/os.system of a
# 'flock' command, or exec'ing a bare "flock" string) is not.
if grep -nE "subprocess[^\n]*['\"]flock['\"]|os\.(system|popen)\([^)]*flock|os\.exec[a-z]*\([^)]*['\"]flock['\"]" "$HELPER" >/dev/null 2>&1; then
  fail "R9: helper invokes the flock(1) CLI binary (must use stdlib fcntl.flock only)"
fi
# and it genuinely runs where flock(1) is absent (the macOS dev box): prove
# python3 fcntl is importable — the only lock dependency.
python3 -c "import fcntl" || fail "R9: python3 fcntl not importable on this platform"
# Prove the helper never calls flock(1): SHADOW a `flock` binary that always fails
# at the front of PATH. If the helper depended on the CLI, the write would abort;
# because it uses stdlib fcntl.flock, the write still succeeds.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
_shadow="$T/shadowbin"
mkdir -p "$_shadow"
cat > "$_shadow/flock" <<'EOF'
#!/bin/sh
echo "flock(1) must never be invoked by the board lock helper" >&2
exit 97
EOF
chmod +x "$_shadow/flock"
HARNESS_DIR="$T" PATH="$_shadow:$PATH" python3 "$HELPER" set-status E01-F01 done --timeout 3 \
  || fail "R9: helper failed when a poisoned flock(1) shadowed PATH (it must not call flock(1))"
[ "$(status_of "$T/state/tasks.json" E01-F01)" = "done" ] \
  || fail "R9: helper did not apply the write (poisoned flock(1) on PATH)"
rm -rf "$T"
pass "R9 portable stdlib fcntl.flock; ignores a poisoned flock(1) on PATH"

# ── R10a: helper resolves its board from ITS OWN path (self-location), any cwd ──
# test_helper_self_locates_board_both_layouts
# Codex #46 P1 (id 3649152686): the documented invocation must work from any cwd
# in BOTH the source layout (tools/tasks-lock.py) and the installed layout
# (.harness/tools/tasks-lock.py) WITHOUT a HARNESS_DIR override. Prove it by
# copying the helper into a <root>/tools/ layout under a temp dir and invoking it
# from an unrelated cwd (/) with NO HARNESS_DIR set: it must find <root>/state.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
mkdir -p "$T/tools"
cp "$HELPER" "$T/tools/tasks-lock.py"
cp "$VALIDATOR" "$T/tools/validate-board.py"   # shared validator sibling
# invoke from an unrelated cwd, env HARNESS_DIR explicitly UNSET
( cd / && env -u HARNESS_DIR python3 "$T/tools/tasks-lock.py" set-status E01-F01 in-review ) \
  || fail "R10a: helper failed to self-locate its board from an arbitrary cwd (no HARNESS_DIR)"
[ "$(status_of "$T/state/tasks.json" E01-F01)" = "in-review" ] \
  || fail "R10a: self-located write did not apply to <root>/state/tasks.json"
# and the installed layout: helper at <root2>/.harness/tools/, board at <root2>/.harness/state/
T2="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T2/.harness"
mkdir -p "$T2/.harness/tools"
cp "$HELPER" "$T2/.harness/tools/tasks-lock.py"
cp "$VALIDATOR" "$T2/.harness/tools/validate-board.py"   # shared validator sibling
( cd / && env -u HARNESS_DIR python3 "$T2/.harness/tools/tasks-lock.py" set-status E01-F02 done ) \
  || fail "R10a: helper failed to self-locate the .harness/ installed-layout board"
[ "$(status_of "$T2/.harness/state/tasks.json" E01-F02)" = "done" ] \
  || fail "R10a: installed-layout self-located write did not apply to .harness/state/tasks.json"
# explicit HARNESS_DIR still wins as the highest-precedence escape hatch.
T3="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T3"
HARNESS_DIR="$T3" python3 "$T/tools/tasks-lock.py" set-status E01-F01 in-progress \
  || fail "R10a: explicit HARNESS_DIR override no longer works"
[ "$(status_of "$T3/state/tasks.json" E01-F01)" = "in-progress" ] \
  || fail "R10a: HARNESS_DIR override did not target the overridden dir"
rm -rf "$T" "$T2" "$T3"
pass "R10a helper self-locates its board from __file__ (both layouts, any cwd); HARNESS_DIR still overrides"

# ── R10b: fallback validator (jsonschema absent) enforces the slices invariant ──
# test_fallback_validator_enforces_slices_invariant
# Codex #46 P1 (id 3649152689): on the zero-dependency install path (no jsonschema)
# the fallback validator must mirror the schema's cross-field rule — a sliced
# feature may be `done` ONLY when every slice is done AND merged. Simulate
# jsonschema being absent by blocking its import, then attempt an illegal
# `set-status <sliced-feature> done` while a slice is unfinished: it must fail
# non-zero and leave the board intact.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
mkdir -p "$T/state" "$T/store"
cp "$SCHEMA" "$T/store/tasks.schema.json"
cat > "$T/state/tasks.json" <<'EOF'
{
  "project": "fixture",
  "epics": [
    {
      "id": "E01",
      "title": "epic one",
      "status": "planned",
      "features": [
        { "id": "E01-F01", "title": "sliced", "status": "in-review", "sdd": true, "spec_path": "a",
          "slices": [
            { "id": "E01-F01@repo-a", "repo": "repo-a", "status": "done", "merged": true },
            { "id": "E01-F01@repo-b", "repo": "repo-b", "status": "in-progress" }
          ]
        }
      ]
    }
  ]
}
EOF
cp "$T/state/tasks.json" "$T/before.json"
# Runner that blocks `import jsonschema`, then drives the helper as __main__ with
# the illegal transition; captures the SystemExit code.
cat > "$T/run_nojs.py" <<EOF
import runpy, sys, builtins
_real = builtins.__import__
def _imp(name, *a, **k):
    if name == "jsonschema":
        raise ImportError("blocked: simulate zero-dep install path")
    return _real(name, *a, **k)
builtins.__import__ = _imp
sys.argv = ["tasks-lock.py", "set-status", "E01-F01", "done"]
try:
    runpy.run_path("$HELPER", run_name="__main__")
    sys.exit(0)
except SystemExit as e:
    sys.exit(0 if e.code in (None, 0) else 2)
EOF
if HARNESS_DIR="$T" python3 "$T/run_nojs.py" 2>"$T/nerr.txt"; then
  fail "R10b: fallback validator ALLOWED sliced feature 'done' with an unfinished slice (jsonschema absent)"
fi
grep -qiE 'slice|done and merged' "$T/nerr.txt" \
  || fail "R10b: fallback rejection did not name the slices invariant"
cmp -s "$T/before.json" "$T/state/tasks.json" \
  || fail "R10b: original board was modified/torn on the rejected sliced-done transition"
# and the LEGAL transition (all slices done+merged) still succeeds on the fallback path.
python3 - "$T/state/tasks.json" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for e in d['epics']:
    for f in e['features']:
        for s in f.get('slices', []):
            s['status'] = 'done'; s['merged'] = True
open(p, 'w').write(json.dumps(d, indent=2) + "\n")
EOF
HARNESS_DIR="$T" python3 "$T/run_nojs.py" \
  || fail "R10b: fallback validator REJECTED a legal sliced 'done' (all slices done+merged)"
[ "$(status_of "$T/state/tasks.json" E01-F01)" = "done" ] \
  || fail "R10b: legal sliced 'done' did not persist on the fallback path"
rm -rf "$T"
pass "R10b fallback validator (no jsonschema) enforces slices done+merged before feature 'done'"

# ── R12: shared validator (init.sh + tasks-lock) enforces the FULL schema ──────
# test_shared_validator_full_schema_on_fallback  (Codex #46 r2 P1, id 3649182844)
# The write path validates through the SAME tools/validate-board.py that init.sh
# runs — so a constraint the old partial fallback omitted (e.g. `sdd` must be a
# boolean) is now rejected even on the zero-dependency install path (jsonschema
# absent). Prove: with `import jsonschema` blocked, a mutator setting `sdd` to a
# non-boolean ("yes") is REJECTED non-zero and the board is left byte-identical.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
cp "$T/state/tasks.json" "$T/before.json"
cat > "$T/sddmut.py" <<'EOF'
def mutate(data):
    # non-boolean sdd — schema requires a boolean; the OLD partial fallback in
    # tasks-lock.py never checked this and would have let it through.
    data['epics'][0]['features'][0]['sdd'] = "yes"
    return data
EOF
# Drive the helper as __main__ with jsonschema import blocked (zero-dep path).
cat > "$T/run_nojs.py" <<EOF
import runpy, sys, builtins
_real = builtins.__import__
def _imp(name, *a, **k):
    if name == "jsonschema":
        raise ImportError("blocked: simulate zero-dep install path")
    return _real(name, *a, **k)
builtins.__import__ = _imp
sys.argv = ["tasks-lock.py", "apply", "--mutator", "$T/sddmut.py"]
try:
    runpy.run_path("$HELPER", run_name="__main__")
    sys.exit(0)
except SystemExit as e:
    sys.exit(0 if e.code in (None, 0) else 2)
EOF
if HARNESS_DIR="$T" python3 "$T/run_nojs.py" 2>"$T/serr.txt"; then
  fail "R12: shared validator ALLOWED a non-boolean sdd on the fallback path (partial validator regression)"
fi
grep -qiE 'sdd|boolean' "$T/serr.txt" \
  || fail "R12: fallback rejection did not name the sdd/boolean constraint"
cmp -s "$T/before.json" "$T/state/tasks.json" \
  || fail "R12: original board was modified/torn on the rejected non-boolean-sdd write"
# and a VALID serial write still passes through the shared validator.
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-progress --timeout 3 \
  || fail "R12: a valid write was rejected by the shared validator"
[ "$(status_of "$T/state/tasks.json" E01-F01)" = "in-progress" ] \
  || fail "R12: valid write did not persist through the shared validator"
rm -rf "$T"
pass "R12 write path uses the shared validator; full-schema fallback rejects non-boolean sdd (board byte-identical)"

# ── R12b: the shared validator is the ACTUAL code init.sh runs (one source) ────
# Prove tools/validate-board.py exists, exposes a CLI with the init.sh contract
# (non-zero + stderr on invalid), and that init.sh calls it rather than embedding
# a duplicate validator heredoc (the root cause of the drift Codex flagged).
VALIDATOR="$ROOT/tools/validate-board.py"
[ -f "$VALIDATOR" ] || fail "R12b: tools/validate-board.py (shared validator) missing"
grep -qF 'tools/validate-board.py' "$ROOT/init.sh" \
  || fail "R12b: init.sh no longer calls the shared tools/validate-board.py"
# init.sh must NOT still carry the old embedded fallback validator (dedup).
grep -qF 'def need(obj, key, where)' "$ROOT/init.sh" \
  && fail "R12b: init.sh still embeds a duplicate validator body (extraction incomplete)"
# CLI contract: invalid board → non-zero with a stderr message; valid → zero.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
python3 "$VALIDATOR" "$T/state/tasks.json" "$SCHEMA" \
  || fail "R12b: shared validator CLI rejected a valid fixture board"
# corrupt the board (drop required 'epics') → must fail non-zero.
python3 -c "import json,sys
d=json.load(open(sys.argv[1])); d.pop('epics'); open(sys.argv[1],'w').write(json.dumps(d))" \
  "$T/state/tasks.json"
if python3 "$VALIDATOR" "$T/state/tasks.json" "$SCHEMA" 2>"$T/verr.txt"; then
  fail "R12b: shared validator CLI accepted a board missing required 'epics'"
fi
[ -s "$T/verr.txt" ] || fail "R12b: shared validator CLI printed no error on an invalid board"
rm -rf "$T"
pass "R12b init.sh + tasks-lock share ONE validator (tools/validate-board.py); no embedded duplicate"

# ── R13: reject non-finite / negative lock timeouts (bounded acquisition) ──────
# test_reject_non_finite_timeout  (Codex #46 r2 P2, id 3649182846)
# argparse's float() happily parses `nan`/`inf`; a NaN deadline makes the
# `monotonic() >= deadline` comparison ALWAYS False (unbounded wait), and +inf is
# an infinite bound. Both must be rejected non-zero BEFORE the poll loop — i.e.
# quickly, even against a HELD lock (proving no blocking occurred).
for bad in nan inf -inf -1; do
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
  make_fixture "$T"
  # Hold the lock so that, if the guard were missing, the call would BLOCK.
  cat > "$T/holder.py" <<EOF
import fcntl, os, time
fd = os.open("$T/state/tasks.json.lock", os.O_RDWR | os.O_CREAT, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
open("$T/held.flag", "w").close()
time.sleep(6)
EOF
  python3 "$T/holder.py" &
  _hp=$!
  until [ -f "$T/held.flag" ]; do sleep 0.05; done
  _start="$(python3 -c 'import time;print(time.time())')"
  if HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 done --timeout "$bad" 2>"$T/gerr.txt"; then
    kill "$_hp" 2>/dev/null || true
    fail "R13: --timeout $bad was accepted (should be rejected before the poll loop)"
  fi
  _end="$(python3 -c 'import time;print(time.time())')"
  # rejected up front ⇒ returns near-instantly, NOT after blocking on the held lock.
  python3 -c "import sys; sys.exit(0 if ($_end - $_start) < 3 else 1)" \
    || fail "R13: --timeout $bad blocked on the held lock instead of failing fast"
  grep -qiE 'timeout|finite|non-negative' "$T/gerr.txt" \
    || fail "R13: --timeout $bad rejection message does not explain the constraint"
  # board untouched.
  [ "$(status_of "$T/state/tasks.json" E01-F01)" = "pending" ] \
    || fail "R13: --timeout $bad mutated the board despite being rejected"
  kill "$_hp" 2>/dev/null || true
  wait "$_hp" 2>/dev/null || true
  rm -rf "$T"
done
pass "R13 non-finite/negative --timeout (nan/inf/-inf/-1) rejected fast, before blocking (bounded R5)"

# ── R11: VERSION advanced (a MINOR bump) + CHANGELOG entry (compared, not frozen) ─
# test_version_advanced_not_frozen
[ -f "$ROOT/VERSION" ] || fail "R11: VERSION file missing"
# VERSION parses as SemVer.
python3 -c "import re,sys; sys.exit(0 if re.match(r'^\d+\.\d+\.\d+', open('$ROOT/VERSION').read().strip()) else 1)" \
  || fail "R11: VERSION is not valid SemVer"
# Advanced past the pre-feature 0.30.0 baseline (compare, do NOT freeze the literal),
# and it is a MINOR (or greater) advance — not merely a PATCH — over that baseline.
python3 - "$ROOT/VERSION" <<'EOF'
import sys
cur = tuple(int(x) for x in open(sys.argv[1]).read().strip().split('.')[:3])
base = (0, 30, 0)   # the pre-E15-F01 baseline; assert ADVANCED past it, not a frozen value
assert cur > base, "VERSION %s did not advance past pre-feature baseline %s" % (cur, base)
assert cur[:2] > base[:2], "VERSION %s is only a PATCH bump; E15-F01 requires a MINOR advance" % (cur,)
EOF
[ $? -eq 0 ] || fail "R11: VERSION did not advance as a MINOR bump"
grep -qiF 'E15-F01' "$ROOT/CHANGELOG.md" \
  || fail "R11: CHANGELOG.md gained no E15-F01 entry"
pass "R11 VERSION advanced (MINOR) + CHANGELOG entry present (compared, not frozen)"

echo "PASS: test_board_lock.sh (R1-R9, R10a/R10b, R11, R12/R12b, R13)"
