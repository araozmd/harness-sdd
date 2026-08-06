#!/bin/sh
# test_board_spec_consistency.sh — E99-F14: the board and the specs on disk must agree,
# and `init.sh` is where the disagreement surfaces.
#
# Two contracts that store/local.md states and NOTHING verified until this feature:
#   1. a feature's `spec_path` was only TYPE-checked — never resolved. E17-F05 shipped
#      `in-review` with a `spec_path` naming a directory that did not exist, so a Reviewer
#      following the board could not open the spec, and init.sh stayed green.
#   2. a feature's `.spec.md` frontmatter `status` — and an epic's `epic.md` `status` —
#      was never compared against the board. Both drifted on `main` for months.
#
# WHAT THIS SUITE IS CAREFUL ABOUT
#
# A gate that fires is easy to write; a gate that fires ONLY when it should is the whole
# job, because `init.sh` is MANDATORY — a false positive halts every agent in the repo.
# So each rule that is expected to STAY SILENT (R3, R4, R7, R8, R10, R11) is paired with a
# fixture that differs in exactly ONE variable and DOES fire. Silence on a fixture that
# could never have fired proves nothing.
#
# R15 asserts the real repository is consistent. On its own that assertion is worthless —
# it would pass just as well against a validator that returned no errors ever. It is
# therefore paired with a vacuity control (R15b) that mutates a COPY of the real board and
# requires the same invocation to fail.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-board-spec)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

command -v python3 >/dev/null 2>&1 \
  || fail "python3 is absent — init.sh hard-fails without it, so this suite does not skip"

VALIDATOR="$SRC/tools/validate-board.py"
SCHEMA="$SRC/store/tasks.schema.json"
[ -f "$VALIDATOR" ] || fail "tools/validate-board.py missing"
[ -f "$SCHEMA" ]    || fail "store/tasks.schema.json missing"

# ── Helpers ───────────────────────────────────────────────────────────────────────────
# RC is captured directly, never through a pipeline: `cmd | tail` reports tail's status,
# which is how a failed command reads as success.
RC=0
run_root() {  # run_root <board.json> <spec-root>
  RC=0
  python3 "$VALIDATOR" "$1" "$SCHEMA" --spec-root "$2" >"$T/out" 2>"$T/err" || RC=$?
}
run_bare() {  # run_bare <board.json>   — no --spec-root
  RC=0
  python3 "$VALIDATOR" "$1" "$SCHEMA" >"$T/out" 2>"$T/err" || RC=$?
}
saw() { grep -F "$1" "$T/err" >/dev/null 2>&1; }

# Build a spec tree rooted at $1 with a spec file at $2 declaring frontmatter status $3.
mkspec() {  # mkspec <root> <relative spec file path> <status line body>
  mkdir -p "$(dirname "$1/$2")"
  {
    echo "---"
    echo "id: X"
    echo "status: $3"
    echo "---"
    echo
    echo "# body"
  } >"$1/$2"
}

board() {  # board <path> <features json fragment>  — one epic, id E1
  cat >"$1" <<JSON
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[$2]}]}
JSON
}

# ══ R1 — a resolvable spec_path is REQUIRED for an sdd feature past `pending` ═════════
A="$T/r1"; mkdir -p "$A"
board "$T/r1.json" '{"id":"E1-F1","title":"a","status":"in-review","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r1.json" "$A"
[ "$RC" -ne 0 ] || fail "R1: a dangling spec_path on an in-review sdd feature passed"
saw "E1-F1" || fail "R1: error did not name the feature id"
saw "specs/epics/E1-one/F1-a/" || fail "R1: error did not name the unresolved path"
pass "R1 dangling spec_path on an sdd feature past pending fails and names id + path"

# ══ R2 — the rule is "a Reviewer can READ the spec", not "the path stats" ═════════════
# A directory that exists but holds no spec satisfies any existence check and still leaves
# the Reviewer with nothing to open. Verifying the OUTCOME, not the site.
B="$T/r2"; mkdir -p "$B/specs/epics/E1-one/F1-a"
board "$T/r2.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r2.json" "$B"
[ "$RC" -ne 0 ] || fail "R2: an sdd feature whose spec dir exists but holds no *.spec.md passed"
saw "no *.spec.md" || fail "R2: error did not say the directory holds no spec"
pass "R2 an existing but spec-less directory fails — existence is not the contract, readability is"

# ══ R3 — `sdd: false` is the quick-fix lane and has no spec BY CONSTRUCTION ═══════════
C="$T/r3"; mkdir -p "$C"
board "$T/r3.json" '{"id":"E1-F1","title":"a","status":"done","sdd":false,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r3.json" "$C"
[ "$RC" -eq 0 ] || fail "R3: a done sdd:false feature with no spec dir failed: $(cat "$T/err")"
# Control: the ONLY difference is the sdd flag, and it fires.
board "$T/r3b.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r3b.json" "$C"
[ "$RC" -ne 0 ] || fail "R3: control failed to fire — the sdd:false pass is vacuous"
pass "R3 sdd:false needs no spec; flipping ONLY sdd to true fires"

# ══ R4 — an sdd feature still at `pending` has not been authored yet ══════════════════
D="$T/r4"; mkdir -p "$D"
board "$T/r4.json" '{"id":"E1-F1","title":"a","status":"pending","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r4.json" "$D"
[ "$RC" -eq 0 ] || fail "R4: a pending sdd feature with no spec dir failed: $(cat "$T/err")"
# Control: the ONLY difference is the status, and it fires.
board "$T/r4b.json" '{"id":"E1-F1","title":"a","status":"spec-ready","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r4b.json" "$D"
[ "$RC" -ne 0 ] || fail "R4: control failed to fire — the pending pass is vacuous"
pass "R4 pending needs no spec; advancing ONLY the status to spec-ready fires"

# ══ R16 — a DRAFT epic's features are exempt from the existence rule ═════════════════
# The harness already treats a non-pending feature inside a draft epic as WARN-ONLY (the
# next() draft gate keeps it unselectable). Demanding an authored spec for one would
# hard-fail, through a side door, the very board state the harness has decided to tolerate
# — and test_epic_lifecycle R12 requires init.sh to exit 0 on exactly that shape.
D2="$T/r16"; mkdir -p "$D2"
cat >"$T/r16.json" <<'JSON'
{"project":"fx","epics":[{"id":"E1","title":"sketch","status":"draft","features":[
 {"id":"E1-F1","title":"a","status":"in-progress","sdd":true,"depends_on":[],
  "spec_path":"specs/epics/E1-one/F1-a/"}]}]}
JSON
run_root "$T/r16.json" "$D2"
[ "$RC" -eq 0 ] || fail "R16: a draft epic's unauthored feature hard-failed: $(cat "$T/err")"
# Control: flip ONLY the epic status draft -> planned, and it fires.
sed 's/"status":"draft"/"status":"planned"/' "$T/r16.json" >"$T/r16b.json"
run_root "$T/r16b.json" "$D2"
[ "$RC" -ne 0 ] || fail "R16: control failed to fire — the draft exemption is vacuous"
# The exemption is scoped to EXISTENCE only: a spec that does exist and disagrees still
# fires, even under a draft epic.
mkspec "$D2" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "done"
run_root "$T/r16.json" "$D2"
[ "$RC" -ne 0 ] || fail "R16: a draft epic's spec was allowed to disagree with the board"
saw "disagrees with board status" || fail "R16: failed for a reason other than disagreement"
pass "R16 draft epics are exempt from the existence rule ONLY — disagreement still fires"

# ══ R5 — frontmatter disagreement names the file and BOTH values ══════════════════════
E="$T/r5"
mkspec "$E" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "in-review"
board "$T/r5.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r5.json" "$E"
[ "$RC" -ne 0 ] || fail "R5: a spec declaring in-review against a done board passed"
saw "'in-review'" || fail "R5: error did not quote the frontmatter value"
saw "'done'"      || fail "R5: error did not quote the board value"
saw "E1-F1.spec.md" || fail "R5: error did not name the spec file"
pass "R5 status disagreement fails and reports file + frontmatter value + board value"

# ══ R6 — legacy `<slug>.spec.md` is checked, not just `<ID>.spec.md` ══════════════════
# 18 feature directories in this repo predate the ID convention. Matching on `<ID>.spec.md`
# would have reported nothing for any of them while looking perfectly green.
F="$T/r6"
mkspec "$F" "specs/epics/E1-one/F1-a/umbrella-coordinator.spec.md" "pending"
board "$T/r6.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r6.json" "$F"
[ "$RC" -ne 0 ] || fail "R6: a legacy <slug>.spec.md was not checked at all"
saw "umbrella-coordinator.spec.md" || fail "R6: error did not name the legacy-named spec"
pass "R6 a spec named <slug>.spec.md is checked — the match is *.spec.md, not <ID>.spec.md"

# ══ R7 — a trailing YAML comment is NOT part of the value ═════════════════════════════
# Every epic.md in this repo writes `status: done   # draft → planned → …`. Comparing the
# raw line reports drift on nearly every epic — a false positive that halts all work.
G="$T/r7"
mkspec "$G" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "done             # pending -> in-review -> done"
board "$T/r7.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r7.json" "$G"
[ "$RC" -eq 0 ] || fail "R7: an inline YAML comment was read as part of the status: $(cat "$T/err")"
# Control: same comment, genuinely different value — still fires.
mkspec "$G" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "pending          # pending -> in-review -> done"
run_root "$T/r7.json" "$G"
[ "$RC" -ne 0 ] || fail "R7: control failed to fire — comment stripping swallows real drift"
pass "R7 inline comments are stripped, and a real mismatch behind one still fires"

# ══ R8 — nothing to compare is not a violation ════════════════════════════════════════
H="$T/r8"; mkdir -p "$H/specs/epics/E1-one/F1-a"
printf '# no frontmatter at all\n' >"$H/specs/epics/E1-one/F1-a/E1-F1.spec.md"
board "$T/r8.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r8.json" "$H"
[ "$RC" -eq 0 ] || fail "R8: a spec with no frontmatter was treated as drift: $(cat "$T/err")"
printf -- '---\nid: X\ntitle: t\n---\n\n# no status key\n' >"$H/specs/epics/E1-one/F1-a/E1-F1.spec.md"
run_root "$T/r8.json" "$H"
[ "$RC" -eq 0 ] || fail "R8: frontmatter without a status key was treated as drift: $(cat "$T/err")"
# Control: add ONLY a disagreeing status key — it fires.
mkspec "$H" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "pending"
run_root "$T/r8.json" "$H"
[ "$RC" -ne 0 ] || fail "R8: control failed to fire — the no-status pass is vacuous"
pass "R8 an undeclared status is a skip, not a violation; declaring a wrong one fires"

# ══ R14 — a quoted frontmatter value is unwrapped ═════════════════════════════════════
I="$T/r14"
mkspec "$I" "specs/epics/E1-one/F1-a/E1-F1.spec.md" '"done"'
board "$T/r14.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r14.json" "$I"
[ "$RC" -eq 0 ] || fail "R14: a quoted matching status was read as drift: $(cat "$T/err")"
mkspec "$I" "specs/epics/E1-one/F1-a/E1-F1.spec.md" '"pending"'
run_root "$T/r14.json" "$I"
[ "$RC" -ne 0 ] || fail "R14: a quoted mismatching status did not fire"
saw "'pending'" || fail "R14: error reported the quotes rather than the value"
pass "R14 quoted frontmatter values compare by their contents"

# ══ R9 — epics carry the SAME contract, so epic.md is checked too ═════════════════════
# store/local.md states it in the same sentence pair as the feature rule; this was verified
# by reading the contract, not assumed from the feature case.
J="$T/r9"; mkdir -p "$J/specs/epics/E1-one"
printf -- '---\nid: E1\nstatus: draft\n---\n\n# epic\n' >"$J/specs/epics/E1-one/epic.md"
board "$T/r9.json" '{"id":"E1-F1","title":"a","status":"pending","sdd":false,"depends_on":[],"spec_path":"x/"}'
run_root "$T/r9.json" "$J"
[ "$RC" -ne 0 ] || fail "R9: an epic.md declaring draft against a planned board passed"
saw "epic.md" || fail "R9: error did not name epic.md"
saw "'draft'" || fail "R9: error did not quote the epic.md value"
pass "R9 epic.md frontmatter is held to the same contract as a feature spec"

# ══ R10 — the epic directory is resolved by convention, and only when unambiguous ═════
# (a) two directories match the id → skipped: guessing which one is canonical is not a
#     contract the board records.
K="$T/r10"; mkdir -p "$K/specs/epics/E1-alpha" "$K/specs/epics/E1-beta"
printf -- '---\nid: E1\nstatus: draft\n---\n' >"$K/specs/epics/E1-alpha/epic.md"
printf -- '---\nid: E1\nstatus: draft\n---\n' >"$K/specs/epics/E1-beta/epic.md"
run_root "$T/r9.json" "$K"
[ "$RC" -eq 0 ] || fail "R10: an ambiguous epic directory was guessed at: $(cat "$T/err")"
# Control: remove ONE of the two so the match is unique — it fires.
rm -rf "$K/specs/epics/E1-beta"
run_root "$T/r9.json" "$K"
[ "$RC" -ne 0 ] || fail "R10: control failed to fire — the ambiguity pass is vacuous"
# (b) the id boundary is respected: epic `E1` must not match directory `E10-...`.
L="$T/r10b"; mkdir -p "$L/specs/epics/E10-ten"
printf -- '---\nid: E10\nstatus: draft\n---\n' >"$L/specs/epics/E10-ten/epic.md"
run_root "$T/r9.json" "$L"
[ "$RC" -eq 0 ] || fail "R10: epic E1 matched directory E10-ten — id prefixes bleed"
pass "R10 epic directories resolve only when unique, and E1 never matches E10-*"

# ══ R11 — without --spec-root the pass does not run AT ALL ════════════════════════════
# Every existing fixture caller validates a throwaway board from the repo root. Defaulting
# the root to the cwd would resolve those boards' spec_paths against THIS repository and
# report drift that does not exist. Opt-in, with no cwd fallback.
run_root "$T/r1.json" "$A"
[ "$RC" -ne 0 ] || fail "R11: precondition — the r1 board must be inconsistent"
run_bare "$T/r1.json"
[ "$RC" -eq 0 ] || fail "R11: the spec pass ran without --spec-root: $(cat "$T/err")"
pass "R11 the spec-consistency pass is opt-in — omitting --spec-root restores prior behaviour"

# ══ R13 — a schema failure stays primary and is reported ALONE ════════════════════════
# When the board's SHAPE is wrong, any disagreement with disk is downstream noise.
M="$T/r13"
mkspec "$M" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "in-review"
board "$T/r13.json" '{"id":"E1-F1","title":"a","status":"not-a-status","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r13.json" "$M"
[ "$RC" -ne 0 ] || fail "R13: an invalid status enum passed validation"
saw "not-a-status" || fail "R13: the schema error was not reported"
if saw "disagrees with board status"; then
  fail "R13: a spec-consistency error was reported alongside a schema failure"
fi
pass "R13 schema errors remain primary and suppress the spec pass"

# ══ R12 — init.sh is WIRED to it: the gate, not just the library ══════════════════════
# Asserting that validate-board.py can fail proves nothing about init.sh. This drives the
# real init.sh in a fixture harness and checks the gate's own exit status — the outcome a
# `grep` for `--spec-root` in init.sh would only approximate.
N="$T/r12"
mkdir -p "$N"/agents "$N"/specs/epics "$N"/progress "$N"/state "$N"/store "$N"/tools
cp "$SRC/init.sh" "$SRC/harness.config.yaml" "$SRC/AGENTS.md" "$N/"
cp "$SRC"/agents/orchestrator.md "$SRC"/agents/architect.md "$SRC"/agents/builder.md \
   "$SRC"/agents/reviewer.md "$SRC"/agents/scout.md "$N/agents/"
cp "$SRC/store/tasks.schema.json" "$N/store/"
cp "$SRC/tools/validate-board.py" "$SRC/tools/task-diagnostics.py" "$N/tools/"

mkdir -p "$N/specs/epics/E1-one/F1-a"
cat >"$N/state/tasks.json" <<'JSON'
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"done","sdd":true,"autonomous":true,
  "depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}]}]}
JSON
# Consistent first — the gate must be GREEN, or a later red proves nothing.
printf -- '---\nid: E1-F1\nstatus: done\n---\n\n# spec\n' >"$N/specs/epics/E1-one/F1-a/E1-F1.spec.md"
RC=0
(cd "$N" && ./init.sh) >"$T/i-ok.out" 2>"$T/i-ok.err" || RC=$?
[ "$RC" -eq 0 ] || fail "R12: init.sh failed on a CONSISTENT fixture: $(cat "$T/i-ok.err")"

# Now change exactly ONE thing: the spec's declared status.
printf -- '---\nid: E1-F1\nstatus: in-review\n---\n\n# spec\n' >"$N/specs/epics/E1-one/F1-a/E1-F1.spec.md"
RC=0
(cd "$N" && ./init.sh) >"$T/i-bad.out" 2>"$T/i-bad.err" || RC=$?
[ "$RC" -ne 0 ] || fail "R12: init.sh stayed green with a spec that disagrees with the board"
cat "$T/i-bad.out" "$T/i-bad.err" >"$T/i-bad.all"
grep -F "E1-F1" "$T/i-bad.all" >/dev/null || fail "R12: init.sh did not name the diverging feature"
pass "R12 init.sh is green on a consistent tree and fail-stops when one spec disagrees"

# ══ R15 — this repository's own board agrees with its specs ═══════════════════════════
RC=0
(cd "$SRC" && python3 tools/validate-board.py state/tasks.json store/tasks.schema.json \
   --spec-root .) >"$T/live.out" 2>"$T/live.err" || RC=$?
[ "$RC" -eq 0 ] || fail "R15: this repo's board disagrees with its specs: $(cat "$T/live.err")"

# R15b — VACUITY CONTROL. R15 alone would pass against a validator that never reports
# anything. Mutate a COPY of the real board and require the same invocation to fail.
python3 - "$SRC/state/tasks.json" "$T/live-mutated.json" >"$T/flipped.id" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
flipped = None
for ep in data["epics"]:
    for ft in ep.get("features", []):
        if ft.get("sdd") is True and ft.get("status") == "done":
            ft["status"] = "in-review"      # its spec still declares `done`
            flipped = ft["id"]
            break
    if flipped:
        break
if not flipped:
    raise SystemExit("no done sdd feature to mutate — control cannot be built")
json.dump(data, open(sys.argv[2], "w"))
print(flipped)
PY
RC=0
(cd "$SRC" && python3 tools/validate-board.py "$T/live-mutated.json" store/tasks.schema.json \
   --spec-root .) >"$T/mut.out" 2>"$T/mut.err" || RC=$?
[ "$RC" -ne 0 ] || fail "R15b: a mutated real board passed — R15's green is vacuous"
grep -F "disagrees with board status" "$T/mut.err" >/dev/null \
  || fail "R15b: the mutated board failed for some other reason: $(cat "$T/mut.err")"
pass "R15 the live board agrees with the live specs, and a mutated copy of it fails"

echo "all board/spec consistency checks passed"
