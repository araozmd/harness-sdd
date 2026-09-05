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
#   R12sgd separate-git-dir linked worktree fails SAFE (loud) without HARNESS_DIR;
#          the F03 coordinator's explicit HARNESS_DIR override lands on the main board
#   R12sgdx a separate-git-dir PRIMARY self-locates — an unrelated board sitting
#          beside its metadata dir is never resolved as canonical, never written
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
# E99-F102: pass evidence that resolves cleanly, so the ACQUISITION is the only thing
# left that can fail. Without it this case would pass only because of where the refusal
# sits relative to the lock — and E99-F129 moved evidence resolution OUT of the locked
# section (it makes network calls; holding the sole write lock across them starves every
# concurrent writer), so that ordering has already changed once.
if HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 done \
     --evidence "none: lock-timeout fixture, no work to land" --timeout 1 2>"$T/terr.txt"; then
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
# and the helper must not itself INVOKE the on_write_command sync hook: it may
# name on_write_command in a comment explaining the after-release contract, but it
# must never shell out to RUN it. The helper legitimately shells out to `git` for
# canonical main-worktree path resolution (R12) — a read-only rev-parse, not a
# board mutation — so we forbid running a hook/sync command specifically rather
# than banning subprocess use outright. Prove the helper references neither the
# hook key nor a generic shell that could run it.
if grep -nE "os\.system|os\.popen|os\.exec" "$HELPER" >/dev/null 2>&1; then
  fail "R7: helper uses a generic shell (os.system/popen/exec) — the sync hook must be the caller's job (after release)"
fi
# Any subprocess use must be confined to read-only `git` invocations (path
# resolution), never a sync/hook command.
if grep -nE "subprocess" "$HELPER" | grep -vE "subprocess\.(run|PIPE|DEVNULL|SubprocessError)|import subprocess|# " >/dev/null 2>&1; then
  fail "R7: helper uses subprocess for something other than read-only git path resolution"
fi
if grep -nE 'subprocess\.run\(\s*\[\s*"[^g]' "$HELPER" >/dev/null 2>&1; then
  fail "R7: helper spawns a non-git subprocess (only read-only git path resolution is allowed)"
fi
rm -rf "$T"
pass "R7 lock is released before any post-write hook could run; helper runs no hook (git path-resolution only)"

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
# E99-F102: a `done` transition needs landing evidence. `none:<why>` is the honest value
# for a fixture board with no work to point at, and it keeps this case about flock(1).
HARNESS_DIR="$T" PATH="$_shadow:$PATH" python3 "$HELPER" set-status E01-F01 done \
  --evidence "none: flock-shadow fixture, no work to land" --timeout 3 \
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
( cd / && env -u HARNESS_DIR python3 "$T2/.harness/tools/tasks-lock.py" set-status E01-F02 done \
    --evidence "none: self-location fixture, no work to land" ) \
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
# E99-F102: a SLICED feature's evidence is bound per slice repository, so this fixture
# declares one per slice repo. Both are \`none:<why>\` — the point here is the slices
# invariant on the fallback path, and the fixture repos hold no work to point at.
sys.argv = ["tasks-lock.py", "set-status", "E01-F01", "done",
            "--evidence", "repo-a=none:fixture board, no work to land",
            "--evidence", "repo-b=none:fixture board, no work to land"]
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

# ── R12wt: canonical board+lock across git worktrees (Codex #46 r4 P1, id 3649274119) ─
# test_canonical_board_lock_across_worktrees
# The F02/F03 parallel-fix flow runs each fix in its OWN linked git worktree. If
# the helper resolved the board relative to whatever worktree it ran in, each
# worker would read/write a DIFFERENT worktree-local state/tasks.json and contend
# on a DIFFERENT lockfile inode — so flock would not serialize cross-worktree
# writers and R1's no-lost-update guarantee would be absent in exactly the scenario
# the epic targets. The helper must resolve BOTH the board and the lockfile to the
# SINGLE canonical location in the MAIN working tree (git rev-parse
# --git-common-dir → main worktree), regardless of which worktree invoked it.
if ! git --version >/dev/null 2>&1; then
  pass "R12wt (skipped: git unavailable)"
else
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
  MAIN="$T/main"
  # Build the MAIN worktree with an INSTALLED-layout harness (.harness/…) so we
  # also exercise the source-vs-installed subpath re-application.
  mkdir -p "$MAIN"
  make_fixture "$MAIN/.harness"
  mkdir -p "$MAIN/.harness/tools"
  cp "$HELPER" "$MAIN/.harness/tools/tasks-lock.py"
  cp "$VALIDATOR" "$MAIN/.harness/tools/validate-board.py"
  ( cd "$MAIN" \
      && git init -q \
      && git config user.email t@t.com \
      && git config user.name t \
      && git add -A \
      && git commit -qm init ) \
    || fail "R12wt: could not initialise the main git worktree fixture"
  # Attempt to add a LINKED worktree; skip cleanly if unsupported in this env.
  WT="$T/linked"
  if ! ( cd "$MAIN" && git worktree add -q "$WT" HEAD ) 2>/dev/null; then
    rm -rf "$T"
    pass "R12wt (skipped: no git worktree)"
  else
    # The linked worktree has its OWN checked-out copy of the helper + board.
    LINKED_HELPER="$WT/.harness/tools/tasks-lock.py"
    [ -f "$LINKED_HELPER" ] \
      || fail "R12wt: linked worktree did not check out the .harness/tools helper"
    # (a) invoke set-status from INSIDE the linked worktree, NO HARNESS_DIR set.
    ( cd "$WT" && env -u HARNESS_DIR python3 "$LINKED_HELPER" set-status E01-F01 in-review ) \
      || fail "R12wt: set-status from the linked worktree failed"
    # the MAIN worktree's board received the transition …
    [ "$(status_of "$MAIN/.harness/state/tasks.json" E01-F01)" = "in-review" ] \
      || fail "R12wt: transition did not land on the MAIN worktree board (per-worktree board bug)"
    # … and the linked worktree's own checked-out board was NOT written.
    if [ -f "$WT/.harness/state/tasks.json" ]; then
      [ "$(status_of "$WT/.harness/state/tasks.json" E01-F01)" = "pending" ] \
        || fail "R12wt: the LINKED worktree's board was mutated (should target only the canonical main board)"
    fi
    # (b) the lockfile is the MAIN worktree's canonical one (created there).
    [ -f "$MAIN/.harness/state/tasks.json.lock" ] \
      || fail "R12wt: canonical lockfile not created under the MAIN worktree"
    # invoking from the linked worktree and from the main worktree must resolve the
    # SAME lockfile path (same inode) — prove by resolving the helper's target from
    # both cwds and comparing.
    LOCK_FROM_LINKED="$( cd "$WT" && env -u HARNESS_DIR python3 - "$LINKED_HELPER" <<'PY'
import importlib.util, os, sys
p = sys.argv[1]
spec = importlib.util.spec_from_file_location("_tl", p)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(os.path.realpath(os.path.join(m._harness_dir(), m.LOCK_REL)))
PY
)"
    LOCK_FROM_MAIN="$( cd "$MAIN" && env -u HARNESS_DIR python3 - "$MAIN/.harness/tools/tasks-lock.py" <<'PY'
import importlib.util, os, sys
p = sys.argv[1]
spec = importlib.util.spec_from_file_location("_tl", p)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(os.path.realpath(os.path.join(m._harness_dir(), m.LOCK_REL)))
PY
)"
    [ "$LOCK_FROM_LINKED" = "$LOCK_FROM_MAIN" ] \
      || fail "R12wt: linked ($LOCK_FROM_LINKED) and main ($LOCK_FROM_MAIN) resolved DIFFERENT lockfiles"
    [ "$LOCK_FROM_MAIN" = "$(python3 -c "import os;print(os.path.realpath('$MAIN/.harness/state/tasks.json.lock'))")" ] \
      || fail "R12wt: canonical lockfile is not the MAIN worktree's state/tasks.json.lock"
    # (c) two concurrent writers launched from two DIFFERENT worktrees both survive.
    ( cd "$WT"   && env -u HARNESS_DIR python3 "$LINKED_HELPER" set-status E01-F01 in-progress --timeout 10 ) &
    _wa=$!
    ( cd "$MAIN" && env -u HARNESS_DIR python3 "$MAIN/.harness/tools/tasks-lock.py" set-status E01-F02 in-review --timeout 10 ) &
    _wb=$!
    wait "$_wa" || fail "R12wt: concurrent worktree writer A exited non-zero"
    wait "$_wb" || fail "R12wt: concurrent worktree writer B exited non-zero"
    [ "$(status_of "$MAIN/.harness/state/tasks.json" E01-F01)" = "in-progress" ] \
      || fail "R12wt: E01-F01 transition lost under cross-worktree contention"
    [ "$(status_of "$MAIN/.harness/state/tasks.json" E01-F02)" = "in-review" ] \
      || fail "R12wt: E01-F02 transition lost under cross-worktree contention"
    rm -rf "$T"
    pass "R12wt canonical board+lock resolved to the MAIN worktree from any linked worktree (no lost update)"
  fi
fi

# ── R12src: SOURCE-layout canonical board+lock across git worktrees ────────────
# test_canonical_board_lock_across_worktrees_source_layout (Codex #46 r5 P1, id 3649327432)
# The R12wt case above builds an INSTALLED-layout harness (.harness/…). In that
# layout the helper's self-located harness dir is <root>/.harness, whose PARENT
# (<root>) is STILL inside the repo — so a git-discovery cwd of dirname(self_dir)
# happens to work and never surfaced the bug. In the SOURCE layout the harness
# dir IS the worktree TOPLEVEL (board at <root>/state/tasks.json, helper at
# <root>/tools/tasks-lock.py), so dirname(self_dir) is the repo's PARENT — git
# runs OUTSIDE the worktree, --git-common-dir / --show-toplevel fail or resolve a
# DIFFERENT repo, and the helper falls back to the LINKED worktree's own board,
# defeating R12. This case reproduces that: set-status invoked from INSIDE the
# linked worktree must transition the MAIN worktree's board (NOT the linked copy)
# and contend on the MAIN worktree's state/tasks.json.lock. It FAILS against the
# old dirname(self_dir) cwd and PASSES once discovery runs from the tools/ dir.
if ! git --version >/dev/null 2>&1; then
  pass "R12src (skipped: git unavailable)"
else
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
  MAIN="$T/main"
  # SOURCE layout: the harness dir == the worktree toplevel. Board + helper live
  # directly under <root>/state and <root>/tools (NO .harness nesting).
  make_fixture "$MAIN"
  mkdir -p "$MAIN/tools"
  cp "$HELPER" "$MAIN/tools/tasks-lock.py"
  cp "$VALIDATOR" "$MAIN/tools/validate-board.py"
  ( cd "$MAIN" \
      && git init -q \
      && git config user.email t@t.com \
      && git config user.name t \
      && git add -A \
      && git commit -qm init ) \
    || fail "R12src: could not initialise the main git worktree fixture"
  WT="$T/linked"
  if ! ( cd "$MAIN" && git worktree add -q "$WT" HEAD ) 2>/dev/null; then
    rm -rf "$T"
    pass "R12src (skipped: no git worktree)"
  else
    LINKED_HELPER="$WT/tools/tasks-lock.py"
    [ -f "$LINKED_HELPER" ] \
      || fail "R12src: linked worktree did not check out the tools/ helper"
    # (a) invoke set-status from INSIDE the linked worktree, NO HARNESS_DIR set.
    ( cd "$WT" && env -u HARNESS_DIR python3 "$LINKED_HELPER" set-status E01-F01 in-review ) \
      || fail "R12src: set-status from the linked worktree failed"
    # the MAIN worktree's board received the transition …
    [ "$(status_of "$MAIN/state/tasks.json" E01-F01)" = "in-review" ] \
      || fail "R12src: transition did not land on the MAIN worktree board (source-layout per-worktree board bug — git ran outside the worktree)"
    # … and the linked worktree's own checked-out board was NOT written.
    if [ -f "$WT/state/tasks.json" ]; then
      [ "$(status_of "$WT/state/tasks.json" E01-F01)" = "pending" ] \
        || fail "R12src: the LINKED worktree's board was mutated (should target only the canonical main board)"
    fi
    # (b) the canonical lockfile is the MAIN worktree's one.
    [ -f "$MAIN/state/tasks.json.lock" ] \
      || fail "R12src: canonical lockfile not created under the MAIN worktree"
    LOCK_FROM_LINKED="$( cd "$WT" && env -u HARNESS_DIR python3 - "$LINKED_HELPER" <<'PY'
import importlib.util, os, sys
p = sys.argv[1]
spec = importlib.util.spec_from_file_location("_tl", p)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(os.path.realpath(os.path.join(m._harness_dir(), m.LOCK_REL)))
PY
)"
    [ "$LOCK_FROM_LINKED" = "$(python3 -c "import os;print(os.path.realpath('$MAIN/state/tasks.json.lock'))")" ] \
      || fail "R12src: linked worktree resolved lockfile $LOCK_FROM_LINKED, not the MAIN worktree's state/tasks.json.lock"
    # (c) two concurrent writers from two DIFFERENT worktrees both survive.
    ( cd "$WT"   && env -u HARNESS_DIR python3 "$LINKED_HELPER" set-status E01-F01 in-progress --timeout 10 ) &
    _wa=$!
    ( cd "$MAIN" && env -u HARNESS_DIR python3 "$MAIN/tools/tasks-lock.py" set-status E01-F02 in-review --timeout 10 ) &
    _wb=$!
    wait "$_wa" || fail "R12src: concurrent worktree writer A exited non-zero"
    wait "$_wb" || fail "R12src: concurrent worktree writer B exited non-zero"
    [ "$(status_of "$MAIN/state/tasks.json" E01-F01)" = "in-progress" ] \
      || fail "R12src: E01-F01 transition lost under cross-worktree contention"
    [ "$(status_of "$MAIN/state/tasks.json" E01-F02)" = "in-review" ] \
      || fail "R12src: E01-F02 transition lost under cross-worktree contention"
    rm -rf "$T"
    pass "R12src source-layout canonical board+lock resolved to the MAIN worktree from any linked worktree (no lost update)"
  fi
fi

# ── R12sgd: separate-git-dir linked worktree FAILS SAFE (loud) w/o override ─────
# test_separate_git_dir_linked_worktree_fails_safe  (Codex #46 r6 P1, id 3649368478)
# Under `git init --separate-git-dir` (and submodules) the MAIN worktree path is
# PROVABLY unrecoverable from a LINKED worktree: `git rev-parse --git-common-dir`
# reports the SEPARATE metadata dir, whose parent is NOT the main worktree, so
# auto-discovery cannot yield the canonical board. The helper must then NEITHER
# resolve to the boardless metadata dir NOR silently fall back to the linked
# worktree's OWN board (a wrong-board write defeating the shared-board guarantee):
# it must FAIL LOUDLY (non-zero + actionable message) demanding an explicit
# HARNESS_DIR — and WITH that override (the F03 coordinator path) the write must
# land on the MAIN board. Attempt the git feature; skip cleanly if unavailable.
if ! git --version >/dev/null 2>&1; then
  pass "R12sgd (skipped: git unavailable)"
else
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
  MAIN="$T/main"
  GITDIR="$T/gitdir"
  # SOURCE layout under a SEPARATE git dir: main worktree's `.git` is a gitlink
  # FILE pointing at $GITDIR (not an in-tree .git directory).
  make_fixture "$MAIN"
  mkdir -p "$MAIN/tools"
  cp "$HELPER" "$MAIN/tools/tasks-lock.py"
  cp "$VALIDATOR" "$MAIN/tools/validate-board.py"
  if ! git init -q --separate-git-dir="$GITDIR" "$MAIN" 2>/dev/null; then
    rm -rf "$T"
    pass "R12sgd (skipped: git init --separate-git-dir unsupported here)"
  else
    ( cd "$MAIN" \
        && git config user.email t@t.com \
        && git config user.name t \
        && git add -A \
        && git commit -qm init ) \
      || fail "R12sgd: could not commit the separate-git-dir main fixture"
    WT="$T/linked"
    if ! ( cd "$MAIN" && git worktree add -q "$WT" HEAD ) 2>/dev/null; then
      rm -rf "$T"
      pass "R12sgd (skipped: no git worktree under separate-git-dir)"
    else
      LINKED_HELPER="$WT/tools/tasks-lock.py"
      [ -f "$LINKED_HELPER" ] \
        || fail "R12sgd: linked worktree did not check out the tools/ helper"
      cp "$MAIN/state/tasks.json" "$T/main-before.json"
      # Capture the linked worktree's own checked-out board (if any) BEFORE.
      if [ -f "$WT/state/tasks.json" ]; then
        cp "$WT/state/tasks.json" "$T/linked-before.json"
      fi
      # (a) NO HARNESS_DIR → LOUD non-zero fail with the actionable message.
      if ( cd "$WT" && env -u HARNESS_DIR python3 "$LINKED_HELPER" \
            set-status E01-F01 in-review ) 2>"$T/sgderr.txt"; then
        fail "R12sgd: set-status from a separate-git-dir linked worktree did NOT fail (silent wrong-board write?)"
      fi
      grep -qiE 'linked git worktree|HARNESS_DIR' "$T/sgderr.txt" \
        || fail "R12sgd: fail message does not demand an explicit HARNESS_DIR"
      grep -qiF 'HARNESS_DIR' "$T/sgderr.txt" \
        || fail "R12sgd: fail message does not name HARNESS_DIR"
      # the MAIN board is byte-unchanged …
      cmp -s "$T/main-before.json" "$MAIN/state/tasks.json" \
        || fail "R12sgd: the MAIN board was modified despite the loud fail"
      # … and the linked worktree's OWN board was NOT silently written.
      if [ -f "$T/linked-before.json" ]; then
        cmp -s "$T/linked-before.json" "$WT/state/tasks.json" \
          || fail "R12sgd: the LINKED worktree's own board was silently written (wrong-board write)"
      fi
      # (b) WITH HARNESS_DIR override (the F03 coordinator path) → lands on MAIN.
      ( cd "$WT" && HARNESS_DIR="$MAIN" python3 "$LINKED_HELPER" \
          set-status E01-F01 in-review ) \
        || fail "R12sgd: set-status with HARNESS_DIR override failed"
      [ "$(status_of "$MAIN/state/tasks.json" E01-F01)" = "in-review" ] \
        || fail "R12sgd: HARNESS_DIR override did not land the write on the MAIN board"
      # and the linked worktree's own board still was not touched by the override run.
      if [ -f "$T/linked-before.json" ]; then
        cmp -s "$T/linked-before.json" "$WT/state/tasks.json" \
          || fail "R12sgd: the LINKED board changed under the HARNESS_DIR override run"
      fi
      rm -rf "$T"
      pass "R12sgd separate-git-dir linked worktree fails SAFE without HARNESS_DIR (main untouched); override lands on the main board"
    fi
  fi
fi

# ── R12sgdp: separate-git-dir PRIMARY (NOT linked) → serial works w/o override ──
# test_separate_git_dir_primary_not_linked  (Codex #46 r7 P2, id 3649430729)
# A PRIMARY checkout created with `git init --separate-git-dir` (like a submodule
# primary) has its common `.git` dir OUTSIDE the working tree — so the OLD
# `_in_linked_worktree()` discriminant (common dir's PARENT != worktree toplevel)
# misclassified this PRIMARY as a LINKED worktree. Combined with a failed
# canonical board-existence check, ordinary serial `set-status` then exited
# demanding HARNESS_DIR, breaking serial orchestration in this layout. The correct
# discriminant is `git rev-parse --git-dir` vs `--git-common-dir`: EQUAL for any
# primary, DISTINCT only for a genuine linked worktree. This primary is NOT linked,
# so set-status with NO HARNESS_DIR must SUCCEED and transition the board. FAILS on
# the old parent-comparison logic; PASSES on the git-dir-vs-common-dir logic.
if ! git --version >/dev/null 2>&1; then
  pass "R12sgdp (skipped: git unavailable)"
else
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
  MAIN="$T/main"
  GITDIR="$T/gitdir"
  # SOURCE layout under a SEPARATE git dir: the PRIMARY checkout's `.git` is a
  # gitlink FILE pointing at $GITDIR (outside the working tree). No linked worktree.
  make_fixture "$MAIN"
  mkdir -p "$MAIN/tools"
  cp "$HELPER" "$MAIN/tools/tasks-lock.py"
  cp "$VALIDATOR" "$MAIN/tools/validate-board.py"
  if ! git init -q --separate-git-dir="$GITDIR" "$MAIN" 2>/dev/null; then
    rm -rf "$T"
    pass "R12sgdp (skipped: git init --separate-git-dir unsupported here)"
  else
    ( cd "$MAIN" \
        && git config user.email t@t.com \
        && git config user.name t \
        && git add -A \
        && git commit -qm init ) \
      || fail "R12sgdp: could not commit the separate-git-dir primary fixture"
    # Sanity: confirm this really is a separate-git-dir primary (common dir OUTSIDE
    # the toplevel), i.e. the exact layout that tripped the old logic.
    _cmn="$( cd "$MAIN/tools" && python3 -c "import os,subprocess as s;print(os.path.realpath(os.path.join(os.getcwd(),s.run(['git','rev-parse','--git-common-dir'],stdout=s.PIPE).stdout.decode().strip())))" )"
    _top="$( cd "$MAIN" && python3 -c "import os;print(os.path.realpath(os.getcwd()))" )"
    [ "$(dirname "$_cmn")" != "$_top" ] \
      || fail "R12sgdp: fixture did NOT produce a common dir outside the toplevel (not exercising the bug)"
    # Serial set-status from the PRIMARY checkout, NO HARNESS_DIR → must SUCCEED
    # (must NOT demand HARNESS_DIR) and transition the primary's own board.
    ( cd "$MAIN" && env -u HARNESS_DIR python3 "$MAIN/tools/tasks-lock.py" \
        set-status E01-F01 in-review ) 2>"$T/sgdperr.txt" \
      || { cat "$T/sgdperr.txt" >&2; fail "R12sgdp: serial set-status from a separate-git-dir PRIMARY was rejected (misclassified as a linked worktree)"; }
    [ "$(status_of "$MAIN/state/tasks.json" E01-F01)" = "in-review" ] \
      || fail "R12sgdp: transition did not land on the separate-git-dir primary's own board"
    # Also prove serial works from an unrelated cwd (self-location path), still no override.
    ( cd / && env -u HARNESS_DIR python3 "$MAIN/tools/tasks-lock.py" \
        set-status E01-F02 done --evidence "none: worktree-layout fixture, no work to land" ) \
      || fail "R12sgdp: serial set-status from an arbitrary cwd was rejected under separate-git-dir primary"
    [ "$(status_of "$MAIN/state/tasks.json" E01-F02)" = "done" ] \
      || fail "R12sgdp: second serial transition did not persist on the primary board"
    rm -rf "$T"
    pass "R12sgdp separate-git-dir PRIMARY is NOT a linked worktree → serial set-status works with no HARNESS_DIR"
  fi
fi

# ── R12sgdx: separate-git-dir PRIMARY never writes a board beside its git dir ──
# test_separate_git_dir_primary_ignores_metadata_parent_board (Codex #46 r8 P1, id 3649460575)
# For a PRIMARY checkout created with `git init --separate-git-dir`, the parent of
# the common `.git` (metadata) dir is NOT the main worktree — it is an unrelated
# directory. If auto-discovery remaps onto it and that directory HAPPENS to hold
# another harness board, the board-existence check accepts it and `set-status`
# silently mutates the WRONG board while the real checkout stays stale. A primary
# checkout must SELF-LOCATE; common-dir remapping is reserved for genuine linked
# worktrees. Fixture: put the separate git dir INSIDE a decoy harness dir that has
# its own state/tasks.json, then assert the write lands on the checkout's board and
# the decoy is byte-unchanged. FAILS on unconditional remapping; PASSES once
# _canonical_harness_dir() is gated on _in_linked_worktree().
if ! git --version >/dev/null 2>&1; then
  pass "R12sgdx (skipped: git unavailable)"
else
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
  MAIN="$T/main"
  DECOY="$T/decoy"
  GITDIR="$DECOY/gitdir"   # ⇒ dirname(common dir) == $DECOY, which owns a board
  make_fixture "$MAIN"
  mkdir -p "$MAIN/tools"
  cp "$HELPER" "$MAIN/tools/tasks-lock.py"
  cp "$VALIDATOR" "$MAIN/tools/validate-board.py"
  # The DECOY is a complete, valid harness dir sitting beside the metadata dir —
  # exactly what makes the existence check wrongly accept it.
  make_fixture "$DECOY"
  if ! git init -q --separate-git-dir="$GITDIR" "$MAIN" 2>/dev/null; then
    rm -rf "$T"
    pass "R12sgdx (skipped: git init --separate-git-dir unsupported here)"
  else
    ( cd "$MAIN" \
        && git config user.email t@t.com \
        && git config user.name t \
        && git add -A \
        && git commit -qm init ) \
      || fail "R12sgdx: could not commit the separate-git-dir primary fixture"
    # Sanity: the metadata dir's parent really is the decoy board dir (the trap).
    _cmn="$( cd "$MAIN/tools" && python3 -c "import os,subprocess as s;print(os.path.realpath(os.path.join(os.getcwd(),s.run(['git','rev-parse','--git-common-dir'],stdout=s.PIPE).stdout.decode().strip())))" )"
    [ -f "$(dirname "$_cmn")/state/tasks.json" ] \
      || fail "R12sgdx: fixture did not place a decoy board beside the separate git dir (not exercising the bug)"
    cp "$DECOY/state/tasks.json" "$T/decoy-before.json"
    ( cd "$MAIN" && env -u HARNESS_DIR python3 "$MAIN/tools/tasks-lock.py" \
        set-status E01-F01 in-progress ) 2>"$T/sgdxerr.txt" \
      || { cat "$T/sgdxerr.txt" >&2; fail "R12sgdx: serial set-status from a separate-git-dir PRIMARY failed"; }
    # the checkout's OWN board transitioned …
    [ "$(status_of "$MAIN/state/tasks.json" E01-F01)" = "in-progress" ] \
      || fail "R12sgdx: the primary checkout's own board was NOT transitioned (write went elsewhere)"
    # … and the unrelated board beside the metadata dir is byte-unchanged.
    cmp -s "$T/decoy-before.json" "$DECOY/state/tasks.json" \
      || fail "R12sgdx: the UNRELATED board beside the separate git dir was mutated (metadata-parent remap bug)"
    # No lockfile was created in the decoy either (proves it was never the target).
    [ ! -f "$DECOY/state/tasks.json.lock" ] \
      || fail "R12sgdx: the lock was taken on the unrelated board beside the separate git dir"
    rm -rf "$T"
    pass "R12sgdx separate-git-dir PRIMARY self-locates (unrelated board beside the metadata dir untouched)"
  fi
fi

# ── R13struct: locate status STRUCTURALLY by id, not by textual key order ──────
# test_status_before_id_targets_correct_object  (Codex #46 r4 P2, id 3649274120)
# JSON imposes no key order. If the minimal-diff writer finds the target's status
# as the first "status" at-or-after the "id" match, a board that orders "status"
# BEFORE "id" makes the patch land on the NEXT object's status — silently
# transitioning the WRONG task while validation still passes. The helper must
# resolve the addressed object structurally by id and change only THAT object's
# status token.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
mkdir -p "$T/state" "$T/store"
cp "$SCHEMA" "$T/store/tasks.schema.json"
# The TARGET (E01-F01) orders "status" BEFORE "id"; a FOLLOWING object (E01-F02)
# whose status must remain untouched.
cat > "$T/state/tasks.json" <<'EOF'
{
  "project": "fixture",
  "epics": [
    {
      "id": "E01",
      "title": "epic one",
      "status": "planned",
      "features": [
        { "status": "pending", "id": "E01-F01", "title": "feature one", "sdd": true, "spec_path": "a" },
        { "status": "pending", "id": "E01-F02", "title": "feature two", "sdd": true, "spec_path": "b" }
      ]
    }
  ]
}
EOF
cp "$T/state/tasks.json" "$T/before.json"
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-review \
  || fail "R13struct: set-status on a status-before-id board failed"
# The CORRECT object transitioned …
[ "$(status_of "$T/state/tasks.json" E01-F01)" = "in-review" ] \
  || fail "R13struct: target E01-F01 was NOT transitioned (structural id resolution failed)"
# … and the FOLLOWING object's status is untouched (the naive first-status-after-id
# bug would have flipped THIS one instead).
[ "$(status_of "$T/state/tasks.json" E01-F02)" = "pending" ] \
  || fail "R13struct: the FOLLOWING object E01-F02 was wrongly transitioned (textual key-order bug)"
# Minimal-diff preserved: exactly one status token changed.
_ndiff="$(diff "$T/before.json" "$T/state/tasks.json" | grep -cE '^[<>]')"
[ "$_ndiff" -eq 2 ] \
  || fail "R13struct: expected exactly one changed line (2 diff sides), got $_ndiff"
rm -rf "$T"
pass "R13struct status located structurally by id (status-before-id board transitions the CORRECT object)"

# ── R13ext: an EXTENSION object with a colliding id is not addressable ─────────
# test_extension_object_with_colliding_id_ignored  (Codex #46 r9 P2, id 3649498027)
# The board schema permits additional properties, so a board may carry an
# extension object (mirror record, cache entry) whose "id" equals a real feature
# or epic id. A document-wide first-textual-match id lookup selects that earlier
# occurrence: `set-status` then silently updates the EXTENSION's status while the
# addressed feature stays unchanged — and the result still validates, so nothing
# surfaces the wrong write. Only members of epics[] / epics[].features[] may be
# addressed. Fixture puts the decoy BEFORE epics (so first-match picks it) and
# also nests one INSIDE the epic (so "restrict to the epics array" is not enough).
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
mkdir -p "$T/state" "$T/store"
cp "$SCHEMA" "$T/store/tasks.schema.json"
cat > "$T/state/tasks.json" <<'EOF'
{
  "project": "fixture",
  "mirror_cache": [
    { "id": "E01-F01", "status": "synced" },
    { "id": "E01", "status": "synced" }
  ],
  "epics": [
    {
      "id": "E01",
      "title": "epic one",
      "status": "planned",
      "integrations": [
        { "id": "E01-F01", "status": "synced" }
      ],
      "features": [
        { "id": "E01-F01", "title": "feature one", "status": "pending", "sdd": true, "spec_path": "a" },
        { "id": "E01-F02", "title": "feature two", "status": "pending", "sdd": true, "spec_path": "b" }
      ]
    }
  ]
}
EOF
cp "$T/state/tasks.json" "$T/before.json"
HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-review \
  || fail "R13ext: set-status on a board with a colliding extension id failed"
# The real FEATURE transitioned …
[ "$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['epics'][0]['features'][0]['status'])" "$T/state/tasks.json")" = "in-review" ] \
  || fail "R13ext: the addressed FEATURE E01-F01 was NOT transitioned (write landed on a colliding extension object)"
# … and NEITHER decoy was touched (top-level cache nor the epic-nested one).
[ "$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['mirror_cache'][0]['status'])" "$T/state/tasks.json")" = "synced" ] \
  || fail "R13ext: the top-level extension object with a colliding id was mutated"
[ "$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['epics'][0]['integrations'][0]['status'])" "$T/state/tasks.json")" = "synced" ] \
  || fail "R13ext: the epic-nested extension object with a colliding id was mutated"
# Minimal-diff still holds: exactly one status token changed.
_ndiff="$(diff "$T/before.json" "$T/state/tasks.json" | grep -cE '^[<>]')"
[ "$_ndiff" -eq 2 ] \
  || fail "R13ext: expected exactly one changed line (2 diff sides), got $_ndiff"
# The EPIC id is likewise resolved in epics[], not from the colliding cache entry.
HARNESS_DIR="$T" python3 "$HELPER" set-status E01 in-progress \
  || fail "R13ext: set-status on the epic id failed"
[ "$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['epics'][0]['status'])" "$T/state/tasks.json")" = "in-progress" ] \
  || fail "R13ext: the addressed EPIC was NOT transitioned (write landed on the colliding cache entry)"
[ "$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d['mirror_cache'][1]['status'])" "$T/state/tasks.json")" = "synced" ] \
  || fail "R13ext: the extension object with a colliding EPIC id was mutated"
rm -rf "$T"
pass "R13ext colliding extension ids are unaddressable (only epics[]/features[] members resolve)"

# ── R13dup: a duplicated `status` member fails STOP, never a silent no-op ──────
# test_duplicate_status_member_fails_stop  (Codex #46 r10 P2, id 3649544829)
# JSON permits duplicate members; `json.loads` keeps the LAST. A first-match text
# patch rewrites the FIRST, so the helper would exit 0 having written a board
# whose EFFECTIVE status never changed — the sole supported write path silently
# no-opping the requested transition (and validation still passes, so nothing
# surfaces it). The helper must refuse to patch an ambiguous object instead.
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
        { "id": "E01-F01", "title": "feature one", "status": "pending", "sdd": true, "spec_path": "a", "status": "pending" }
      ]
    }
  ]
}
EOF
cp "$T/state/tasks.json" "$T/before.json"
if HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-review 2>"$T/duperr.txt"; then
  fail "R13dup: set-status on a duplicate-status object SUCCEEDED (silent no-op — parsed status is the LAST member, the patch rewrote the FIRST)"
fi
grep -qiE 'duplicat|status' "$T/duperr.txt" \
  || { cat "$T/duperr.txt" >&2; fail "R13dup: failure message does not explain the duplicate status member"; }
# Fail-stop: the board is byte-for-byte untouched (R4 semantics).
cmp -s "$T/before.json" "$T/state/tasks.json" \
  || fail "R13dup: the board was modified despite the fail-stop"
rm -rf "$T"
pass "R13dup duplicate status member fails stop with a clear message (board untouched, never a silent no-op)"

# ── R14py3: init.sh HARD-fails (non-zero, clear msg) when python3 is absent ────
# test_init_requires_python3  (Codex #46 r6 P1, id 3649368481)
# Since E15-F01 the ONLY supported set_status write path is
# `python3 tools/tasks-lock.py`, so a python3-less install must NOT report
# "environment ready" (it would fail on the first Orchestrator transition with
# `python3: not found`). init.sh's old warn-and-continue is now a hard fail.
# We build a sandboxed harness copy and run init.sh under a PATH that provides
# the ordinary shell tools but OMITS python3 (a shim dir that symlinks the
# needed binaries and deliberately does not expose python3).
SBX="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
for p in init.sh AGENTS.md harness.config.yaml agents specs progress store tools; do
  cp -R "$ROOT/$p" "$SBX/" 2>/dev/null || true
done
mkdir -p "$SBX/state"
cp "$ROOT/state/tasks.json" "$SBX/state/tasks.json" 2>/dev/null \
  || make_fixture "$SBX"   # any valid board; the run must fail BEFORE validating it
# Build a PATH shim that has the usual tools but NO python3/python. Only symlink
# resolved ABSOLUTE paths (a `command -v` that resolves to a shell builtin/alias
# must not be symlinked as a bogus self-referential link).
SHIM="$SBX/shimbin"
mkdir -p "$SHIM"
for tool in sh bash dirname pwd grep sed cat command test head env true false mktemp; do
  _tp="$(command -v "$tool" 2>/dev/null || true)"
  case "$_tp" in
    /*) ln -sf "$_tp" "$SHIM/$tool" 2>/dev/null || true ;;
  esac
done
# Sanity: grep must still resolve (so the shim is usable) AND python3 must NOT be
# reachable via the shim-only PATH; otherwise we cannot construct the scenario.
# Probe in a FRESH subshell (`env -i sh -c`): the current shell may have HASHED
# python3's absolute path from earlier tests, so a same-shell `command -v` would
# report a false positive regardless of PATH. init.sh runs in its own subshell
# and thus sees the true (python3-less) resolution, which is what we assert here.
# `bash` must ALSO be reachable through the shim: init.sh is a BASH script
# (`#!/usr/bin/env bash` + `set -o pipefail`) and must be invoked with bash, so a
# shim without bash cannot run the scenario at all.
if ! env -i PATH="$SHIM" sh -c 'command -v grep' >/dev/null 2>&1 \
   || ! env -i PATH="$SHIM" sh -c 'command -v bash' >/dev/null 2>&1 \
   || env -i PATH="$SHIM" sh -c 'command -v python3' >/dev/null 2>&1; then
  # Some environments expose python3 from a builtins dir we can't exclude; skip.
  rm -rf "$SBX"
  pass "R14py3 (skipped: cannot construct a python3-less PATH in this environment)"
else
  _out="$SBX/init.out"
  # Run init.sh in a scrubbed environment (`env -i`) so NO inherited command hash
  # or leaked PATH lets it find a python3 the shim omits — it must resolve exactly
  # the python3-less PATH we hand it and hard-fail.
  # Invoke with `bash`, NOT `sh`: init.sh declares `#!/usr/bin/env bash` and uses
  # `set -o pipefail`. Where /bin/sh is dash (typical Ubuntu CI), `sh ./init.sh`
  # ignores the shebang and aborts at line 8 with "Illegal option -o pipefail",
  # NEVER reaching the python3 gate — the run still exits non-zero (so the
  # must-fail assertion below passes vacuously) but the output names no python3,
  # so the message greps fail and the whole suite goes red on CI while passing on
  # macOS, where /bin/sh is bash in POSIX mode and does support pipefail.
  if ( cd "$SBX" && env -i PATH="$SHIM" HOME="$SBX" bash ./init.sh ) >"$_out" 2>&1; then
    cat "$_out" >&2
    rm -rf "$SBX"
    fail "R14py3: init.sh reported success with python3 absent (must hard-fail — the mandatory lock helper needs python3)"
  fi
  grep -qi 'python3' "$_out" \
    || { cat "$_out" >&2; rm -rf "$SBX"; fail "R14py3: init.sh failure message does not name python3"; }
  grep -qiE 'requir|mandat|lock|validation' "$_out" \
    || { cat "$_out" >&2; rm -rf "$SBX"; fail "R14py3: init.sh failure message does not explain why python3 is required"; }
  rm -rf "$SBX"
  pass "R14py3 init.sh hard-fails with a clear message when python3 is absent (mandatory lock helper)"
fi

# ── R14mode: TaskStore file mode is preserved across the atomic replace ────────
# test_mode_preserved_across_replace  (Codex #46 r6 P2, id 3649368484)
# The write creates a temp file (per umask) then os.replace's it in. Without
# copying the original mode onto the temp file, a 0600 board silently becomes
# 0644 (exposing data) and a 0664 shared board narrows (breaking another
# account's writes). The helper must copy the original board's permission bits
# onto the temp file before the replace, inside the lock.
mode_of() { python3 -c "import os,stat,sys;print('%o' % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))" "$1"; }
for _m in 600 664; do
  T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
  make_fixture "$T"
  chmod "$_m" "$T/state/tasks.json"
  _before="$(mode_of "$T/state/tasks.json")"
  [ "$_before" = "$_m" ] || fail "R14mode: could not set fixture board to $_m (got $_before)"
  HARNESS_DIR="$T" python3 "$HELPER" set-status E01-F01 in-review \
    || fail "R14mode: set-status on a $_m board failed"
  _after="$(mode_of "$T/state/tasks.json")"
  [ "$_after" = "$_m" ] \
    || fail "R14mode: board mode changed across the atomic replace ($_m -> $_after) — temp-file mode not copied"
  [ "$(status_of "$T/state/tasks.json" E01-F01)" = "in-review" ] \
    || fail "R14mode: the transition did not apply on the $_m board"
  rm -rf "$T"
done
pass "R14mode board file mode (0600 / 0664) preserved across the atomic os.replace"

# ── R1 contracts: every documented board mutation uses the lock helper ───────
# test_role_and_store_contracts_route_all_board_writes_through_lock_helper
# These are static regression checks because the role files and local backend are
# executable contracts: agents follow the commands written there. A passing helper
# suite is insufficient if an invoked role still tells an agent to hand-edit the
# board and run the obsolete inline json.load validation afterward.
require_locked_apply_contract() {
  _contract="$1"
  grep -qF 'tasks-lock.py apply --mutator' "$ROOT/$_contract" \
    || fail "R1 contract: $_contract does not route structural board writes through apply --mutator"
  if grep -qF 'python3 -c "import json; json.load(open('\''state/tasks.json'\''))"' "$ROOT/$_contract"; then
    fail "R1 contract: $_contract still prescribes obsolete inline tasks.json validation"
  fi
}

for _contract in \
  agents/inception.md \
  agents/fixer.md \
  agents/planner.md \
  agents/driller.md
do
  require_locked_apply_contract "$_contract"
done

# ── add-feature: the Fixer's seeding contract (fixer.md R8/R9) as a guarded ───
# subcommand — append-only, next-sequential id strictly above max (never refill a
# gap), sdd:false/pending/autonomous default, --gated opt-out, missing epic refused.
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-lock)"
make_fixture "$T"
_id="$(HARNESS_DIR="$T" python3 "$HELPER" add-feature --epic E01 --title "Seeded fix one")" \
  || fail "add-feature: exited non-zero on a valid epic"
[ "$_id" = "E01-F03" ] || fail "add-feature: expected next-sequential E01-F03, got '$_id'"
python3 - "$T/state/tasks.json" <<'PY' || fail "add-feature: seeded row violates the R8 field table"
import json, sys
d = json.load(open(sys.argv[1]))
f = d["epics"][0]["features"][-1]
assert f["id"] == "E01-F03" and f["status"] == "pending", f
assert f["sdd"] is False and f["autonomous"] is True and f["depends_on"] == [], f
assert f["spec_path"].startswith("specs/epics/") and f["spec_path"].endswith("/"), f
PY
# --gated stamps autonomous: false; a vacated high id is never refilled (strictly above max).
cat > "$T/gapmut.py" <<'EOF'
def mutate(data):
    feats = data["epics"][0]["features"]
    feats[:] = [f for f in feats if f["id"] != "E01-F02"]  # vacate F02 — the gap
    return data
EOF
HARNESS_DIR="$T" python3 "$HELPER" apply --mutator "$T/gapmut.py" \
  || fail "add-feature: gap-mutator apply failed"
_id2="$(HARNESS_DIR="$T" python3 "$HELPER" add-feature --epic E01 --title "gated" --gated)" \
  || fail "add-feature: --gated run exited non-zero"
[ "$_id2" = "E01-F04" ] || fail "add-feature: refilled the vacated F02 instead of allocating above max (got '$_id2')"
python3 - "$T/state/tasks.json" <<'PY' || fail "add-feature: --gated did not stamp autonomous: false"
import json, sys
f = json.load(open(sys.argv[1]))["epics"][0]["features"][-1]
assert f["id"] == "E01-F04" and f["autonomous"] is False, f
PY
# A missing epic is refused with the board untouched — never invented.
_before="$(cat "$T/state/tasks.json")"
HARNESS_DIR="$T" python3 "$HELPER" add-feature --epic E77 --title "x" >/dev/null 2>&1 \
  && fail "add-feature: seeding under a missing epic must fail"
[ "$_before" = "$(cat "$T/state/tasks.json")" ] \
  || fail "add-feature: a refused seed still mutated the board"
# A slug is a single path component, never a path (Codex #160 P2): a traversal slug is
# sanitized to [a-z0-9-], so the persisted spec_path can never escape specs/epics/ —
# an escaped path would fail validate-board at the next mandatory init.sh and brick
# the board.
HARNESS_DIR="$T" python3 "$HELPER" add-feature --epic E01 --title "t" \
  --slug '../../../../tmp/owned' >/dev/null \
  || fail "add-feature: a traversal --slug must be sanitized, not refused into a broken board"
python3 - "$T/state/tasks.json" <<'PY' || fail "add-feature: a traversal --slug escaped into spec_path"
import json, sys
f = json.load(open(sys.argv[1]))["epics"][0]["features"][-1]
assert ".." not in f["spec_path"] and f["spec_path"].startswith("specs/epics/"), f
assert "/tmp/" not in f["spec_path"], f
PY
# Create-on-first-use (Codex #160 P2): an epic with NO rows and no disk dir must still
# use the Fixer contract's required default directory for E99 — never the bare id.
cat > "$T/freshmut.py" <<'EOF'
def mutate(data):
    data["epics"].append({"id": "E99", "title": "maintenance", "status": "pending",
                          "features": []})
    return data
EOF
HARNESS_DIR="$T" python3 "$HELPER" apply --mutator "$T/freshmut.py" \
  || fail "add-feature: could not seed a fresh empty E99"
HARNESS_DIR="$T" python3 "$HELPER" add-feature --title "first ever fix" >/dev/null \
  || fail "add-feature: first fix into a fresh E99 failed"
python3 - "$T/state/tasks.json" <<'PY' || fail "add-feature: first E99 fix did not use specs/epics/E99-maintenance/"
import json, sys
e99 = [e for e in json.load(open(sys.argv[1]))["epics"] if e["id"] == "E99"][0]
f = e99["features"][-1]
assert f["spec_path"].startswith("specs/epics/E99-maintenance/"), f["spec_path"]
PY
rm -rf "$T"
pass "add-feature seeds the R8/R9 row shape, allocates strictly above max, honors --gated, refuses a missing epic, sanitizes slugs, defaults fresh E99 to E99-maintenance"

grep -qF 'set_slice_status(feature, slice_id, status)' "$ROOT/store/local.md" \
  || fail "R1 contract: store/local.md lost the slice mutation contract"
grep -qF 'tasks-lock.py apply --mutator' "$ROOT/store/local.md" \
  || fail "R1 contract: store/local.md does not lock structural slice mutations"
grep -qF 'tasks-lock.py set-status <id> <status>' "$ROOT/store/local.md" \
  || fail "R1 contract: store/local.md no longer keeps status transitions on set-status"
if grep -qF 'edit the slice in place, then re-validate' "$ROOT/store/local.md"; then
  fail "R1 contract: store/local.md still prescribes an unlocked slice hand-edit"
fi
pass "R1 role/store contracts route structural board writes through apply --mutator and status writes through set-status"

echo "PASS: test_board_lock.sh (R1-R9, R10a/R10b, R11, R12/R12b, R13, R12wt, R12src, R12sgd, R13struct, R14py3, R14mode, role/store contracts)"
