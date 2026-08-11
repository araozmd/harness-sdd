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
# So each rule that is expected to STAY SILENT (R3, R4, R7, R8, R10, R11, R16, R18, R19,
# R20c, R25, R26) is paired with a fixture that differs in exactly ONE variable and DOES
# fire. Silence on a fixture that could never have fired proves nothing.
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
# Every fixture feature below is `E1-F1`, so the spec declares that id: since R19 a spec
# must prove it belongs to the board entry, and a placeholder id would make every fixture
# fail ownership rather than test the rule it was written for.
mkspec() {  # mkspec <root> <relative spec file path> <status line body>
  mkdir -p "$(dirname "$1/$2")"
  {
    echo "---"
    echo "id: E1-F1"
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

# ══ R20 — a spec_path may not escape the harness root ════════════════════════════════
# (Codex #3731166711.) `os.path.join(root, spec_path)` DISCARDS root for an absolute path
# and walks out of it for one containing `..`. With a matching spec at the far end, the gate
# would certify the board as consistent while the Reviewer reads a spec that is not in this
# repository. The escape is reported for every feature, not only authored ones: it is not
# "no spec yet", it is a malformed pointer.
#
# Containment is to the ROOT, deliberately NOT to `<root>/specs` — see case (c). Leaving the
# repository is the defect; sitting outside `specs/` is a convention the schema has never
# stated, and enforcing it here would fail-stop schema-valid boards at a MANDATORY gate.
Y2="$T/r20"; mkdir -p "$Y2"
OUTSIDE="$T/r20-outside/F1-a"; mkdir -p "$OUTSIDE"
printf -- '---\nid: E1-F1\nstatus: done\n---\n\n# outside\n' >"$OUTSIDE/E1-F1.spec.md"
# (a) `..` escape — pointed at a real directory holding a real, matching, correctly-owned
#     spec, so every OTHER rule in this file would pass it.
board "$T/r20a.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"../r20-outside/F1-a/"}'
run_root "$T/r20a.json" "$Y2"
[ "$RC" -ne 0 ] || fail "R20: a spec_path containing .. escaped the tree undetected"
saw "escapes the harness root" || fail "R20: the .. escape was not reported as an escape"
# (b) absolute path — os.path.join discards the root entirely.
cat >"$T/r20b.json" <<JSON
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"$OUTSIDE/"}]}]}
JSON
run_root "$T/r20b.json" "$Y2"
[ "$RC" -ne 0 ] || fail "R20: an absolute spec_path escaped the tree undetected"
saw "escapes the harness root" || fail "R20: the absolute path was not reported as an escape"
# (c) a sibling of specs/ under the same root is NOT an escape, and must stay green.
#     It is still inside the repository, still has to declare this feature's id and still
#     has to agree with the board — nothing is certified sight-unseen. Rejecting it would
#     impose a layout the schema never required (`spec_path` is only `"type": "string"`),
#     and would halt every agent in a target whose board predates the convention.
mkdir -p "$Y2/elsewhere/F1-a"
printf -- '---\nid: E1-F1\nstatus: done\n---\n' >"$Y2/elsewhere/F1-a/E1-F1.spec.md"
board "$T/r20c.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"elsewhere/F1-a/"}'
run_root "$T/r20c.json" "$Y2"
[ "$RC" -eq 0 ] || fail "R20: an in-repo path outside specs/ was rejected: $(cat "$T/err")"
# ...and it is not exempt from the other rules either: change ONLY its declared status and
# it fires, so (c)'s green is coverage, not a bypass.
printf -- '---\nid: E1-F1\nstatus: in-review\n---\n' >"$Y2/elsewhere/F1-a/E1-F1.spec.md"
run_root "$T/r20c.json" "$Y2"
[ "$RC" -ne 0 ] || fail "R20: a path outside specs/ escaped the status rule as well"
# (c2) a SYMLINK out of the tree is an escape too (Codex #3731306972). It is in-root by
#      spelling and outside the repository in fact, which a lexical comparison accepts —
#      what matters is where the read actually lands, not how the path is written.
mkdir -p "$Y2/specs/epics/E1-sym"
ln -s "$OUTSIDE" "$Y2/specs/epics/E1-sym/F1-a"
board "$T/r20f.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-sym/F1-a/"}'
run_root "$T/r20f.json" "$Y2"
[ "$RC" -ne 0 ] || fail "R20: a symlink pointing outside the repository was accepted"
saw "escapes the harness root" || fail "R20: the symlink escape was not reported as an escape"
# ...and a symlink that stays INSIDE the repository is not an escape, so the rule tests
# where the path lands rather than merely rejecting symlinks.
mkdir -p "$Y2/specs/real/F1-a"
printf -- '---\nid: E1-F1\nstatus: done\n---\n' >"$Y2/specs/real/F1-a/E1-F1.spec.md"
mkdir -p "$Y2/specs/epics/E1-in"
ln -s "$Y2/specs/real/F1-a" "$Y2/specs/epics/E1-in/F1-a"
board "$T/r20g.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-in/F1-a/"}'
run_root "$T/r20g.json" "$Y2"
[ "$RC" -eq 0 ] || fail "R20: an in-repo symlink was rejected: $(cat "$T/err")"
# (d) an sdd:false entry is NOT exempt — an escaping pointer is malformed regardless.
board "$T/r20d.json" '{"id":"E1-F1","title":"a","status":"done","sdd":false,"depends_on":[],"spec_path":"../r20-outside/F1-a/"}'
run_root "$T/r20d.json" "$Y2"
[ "$RC" -ne 0 ] || fail "R20: an escaping spec_path was excused because sdd was false"
# Control: the SAME spec content, relocated under specs/, is clean — so R20 fires on the
# containment and not on the spec it finds there.
mkspec "$Y2" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "done"
board "$T/r20e.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r20e.json" "$Y2"
[ "$RC" -eq 0 ] || fail "R20: control — an in-tree spec_path failed: $(cat "$T/err")"
pass "R20 absolute and .. paths escape the root; an in-repo path outside specs/ does not"

# ══ R19 — a resolvable spec_path must also BELONG to the board entry ═════════════════
# (Codex #3731050919.) The sibling-directory case: the path resolves, a *.spec.md is there,
# and the statuses agree — so every other rule passes — while the spec is a DIFFERENT
# feature's, which a Reviewer would open and implement. Resolving is not belonging.
W="$T/r19"
mkspec "$W" "specs/epics/E1-one/F2-b/E1-F2.spec.md" "done"
python3 - "$W/specs/epics/E1-one/F2-b/E1-F2.spec.md" <<'PY'
import io, sys
p = sys.argv[1]
t = io.open(p, encoding="utf-8").read().replace("id: E1-F1", "id: E1-F2")
io.open(p, "w", encoding="utf-8").write(t)
PY
# E1-F1's spec_path points at E1-F2's directory, and the two statuses MATCH — so the
# status rule alone can never catch this.
board "$T/r19.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F2-b/"}'
run_root "$T/r19.json" "$W"
[ "$RC" -ne 0 ] || fail "R19: a spec_path pointing at a sibling feature's spec passed"
saw "declares id 'E1-F2'" || fail "R19: the error did not name the id the spec actually declares"
# Control: the SAME directory, with the spec's id corrected to this feature, is clean —
# proving R19 failed on ownership and not on the fixture's shape.
python3 - "$W/specs/epics/E1-one/F2-b/E1-F2.spec.md" <<'PY'
import io, sys
p = sys.argv[1]
t = io.open(p, encoding="utf-8").read().replace("id: E1-F2", "id: E1-F1")
io.open(p, "w", encoding="utf-8").write(t)
PY
run_root "$T/r19.json" "$W"
[ "$RC" -eq 0 ] || fail "R19: control — a correctly-owned spec at the same path failed: $(cat "$T/err")"
# A spec that declares NO id cannot prove ownership either, for an authored feature.
X2="$T/r19b"
mkspec "$X2" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "done"
python3 - "$X2/specs/epics/E1-one/F1-a/E1-F1.spec.md" <<'PY'
import io, sys
p = sys.argv[1]
t = io.open(p, encoding="utf-8").read().replace("id: E1-F1\n", "")
io.open(p, "w", encoding="utf-8").write(t)
PY
board "$T/r19b.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r19b.json" "$X2"
[ "$RC" -ne 0 ] || fail "R19: an authored feature whose spec declares no id passed"
saw "not proven to belong" || fail "R19: the error did not say ownership was unproven"
# ...but the same undeclared id under a NON-authored feature stays silent, exactly as an
# undeclared status does.
board "$T/r19c.json" '{"id":"E1-F1","title":"a","status":"done","sdd":false,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r19c.json" "$X2"
[ "$RC" -eq 0 ] || fail "R19: ownership was demanded of an sdd:false feature: $(cat "$T/err")"
pass "R19 a spec must declare the feature's id; a sibling's spec and an unproven one both fire"

# ══ R18 — a spec that cannot be READ is a failure, not "declares no status" ══════════
# (Codex #3731050923.) The glob has already satisfied the "an authored spec exists" rule by
# the time the file is opened, so an undecodable spec that reported the same "nothing
# declared" answer as R8's legitimate skip would sail through a contract whose entire
# content is "a Reviewer can open this".
U="$T/r18"; mkdir -p "$U/specs/epics/E1-one/F1-a"
# Invalid UTF-8: a lone 0x80 continuation byte, which cannot begin a UTF-8 sequence.
printf -- '---\nid: E1-F1\nstatus: \200\200done\n---\n' >"$U/specs/epics/E1-one/F1-a/E1-F1.spec.md"
board "$T/r18.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r18.json" "$U"
[ "$RC" -ne 0 ] || fail "R18: an undecodable spec passed as though it declared nothing"
saw "cannot be read or decoded" || fail "R18: the error did not say the file was unreadable"
# Control: the SAME board and path, with a decodable spec, is clean — so R18's failure is
# the decoding and not the fixture.
mkspec "$U" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "done"
run_root "$T/r18.json" "$U"
[ "$RC" -eq 0 ] || fail "R18: control — a readable spec at the same path failed: $(cat "$T/err")"
# An unreadable epic.md is held to the same rule. This block builds its OWN board rather
# than reusing a later R-id's — a fixture that depends on a file another block writes makes
# the suite order-sensitive, and the failure reads as a code defect rather than a test one.
V2="$T/r18b"; mkdir -p "$V2/specs/epics/E1-one"
printf -- '---\nid: E1\nstatus: \200\200draft\n---\n' >"$V2/specs/epics/E1-one/epic.md"
board "$T/r18b.json" '{"id":"E1-F1","title":"a","status":"pending","sdd":false,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r18b.json" "$V2"
[ "$RC" -ne 0 ] || fail "R18: an undecodable epic.md passed"
saw "cannot be read or decoded" || fail "R18: the epic.md error did not say it was unreadable"
pass "R18 an unreadable spec or epic.md fails; the same path with readable bytes is clean"

# ══ R17 — a spec_path naming a FILE is unresolved, not "a directory with no spec" ════
# Found by mutation: relaxing `isdir` to `exists` keeps every pass/fail verdict identical
# and changes only the diagnostic — a file-shaped spec_path would be reported as a
# directory that happens to hold no spec. At a mandatory gate the operator acts on the
# message, so the message is part of the contract.
B2="$T/r17"; mkdir -p "$B2/specs/epics/E1-one"
printf 'not a directory\n' >"$B2/specs/epics/E1-one/F1-a"
board "$T/r17.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a"}'
run_root "$T/r17.json" "$B2"
[ "$RC" -ne 0 ] || fail "R17: a spec_path naming a regular file passed"
saw "does not exist" || fail "R17: a file-shaped spec_path was not reported as unresolved"
if saw "no *.spec.md"; then
  fail "R17: a regular file was described as a directory holding no spec"
fi
pass "R17 a spec_path naming a file reports as unresolved, not as an empty spec directory"

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
# sdd:false: R8's claim is about the STATUS comparison. Ownership (R19) is a separate
# rule that a spec with no frontmatter legitimately fails, and leaving it in scope here
# would make R8 pass or fail for the wrong reason.
board "$T/r8.json" '{"id":"E1-F1","title":"a","status":"done","sdd":false,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r8.json" "$H"
[ "$RC" -eq 0 ] || fail "R8: a spec with no frontmatter was treated as drift: $(cat "$T/err")"
printf -- '---\nid: E1-F1\ntitle: t\n---\n\n# no status key\n' >"$H/specs/epics/E1-one/F1-a/E1-F1.spec.md"
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
board "$T/r9.json" '{"id":"E1-F1","title":"a","status":"pending","sdd":false,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
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

# ══ R21–R24 — the WRITER half: set-status carries the frontmatter ════════════════════
# (Codex #3731306966, P1.) Arming the gate above without this would have made every
# SANCTIONED transition fail the next mandatory init.sh: `set-status` wrote only the board,
# so `/sdd-drill`'s `set-status <epic> planned` and every Orchestrator feature move left the
# document behind and halted all agent work until an undocumented second edit.
#
# These live here rather than in test_board_lock.sh on purpose: the gate and the writer are
# two halves of ONE contract, and splitting them is how the contract went unenforced for
# months in the first place.
FX="$T/writer"
mkdir -p "$FX/state" "$FX/store" "$FX/tools" "$FX/specs/epics/E1-one/F1-a"
cp "$SRC/tools/tasks-lock.py" "$SRC/tools/validate-board.py" "$FX/tools/"
cp "$SRC/store/tasks.schema.json" "$FX/store/"
cat >"$FX/state/tasks.json" <<'JSON'
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"in-progress","sdd":true,"autonomous":true,
  "depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}]}]}
JSON
printf -- '---\nid: E1-F1\nstatus: in-progress    # pending -> in-review -> done\n---\n\n# spec\n' \
  >"$FX/specs/epics/E1-one/F1-a/E1-F1.spec.md"
printf -- '---\nid: E1\nstatus: planned          # draft -> planned -> done\n---\n\n# epic\n' \
  >"$FX/specs/epics/E1-one/epic.md"

set_status() { HARNESS_DIR="$FX" python3 "$FX/tools/tasks-lock.py" set-status "$1" "$2" >"$T/sl.out" 2>"$T/sl.err"; }
fx_status() { sed -n 's/^status:[ \t]*\([^ \t#]*\).*$/\1/p' "$1" | head -1; }
board_status() {  # board_status <board.json> — the first feature's status, parsed not grepped
  python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['epics'][0]['features'][0]['status'])" "$1"
}

# R21 — a feature transition moves both records, and the gate stays green.
set_status E1-F1 in-review || fail "R21: set-status failed: $(cat "$T/sl.err")"
[ "$(fx_status "$FX/specs/epics/E1-one/F1-a/E1-F1.spec.md")" = "in-review" ] \
  || fail "R21: the spec frontmatter did not follow the board"
run_root "$FX/state/tasks.json" "$FX"
[ "$RC" -eq 0 ] || fail "R21: the gate failed after a sanctioned transition: $(cat "$T/err")"
# The inline comment survives — a status write must not reflow the block.
grep -F 'pending -> in-review -> done' "$FX/specs/epics/E1-one/F1-a/E1-F1.spec.md" >/dev/null \
  || fail "R21: the inline comment was destroyed by the sync"
# VACUITY CONTROL: move ONLY the board, exactly as set-status used to, and the gate fires.
# Without this, R21's green would be indistinguishable from a gate that never checks.
python3 - "$FX/state/tasks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["epics"][0]["features"][0]["status"] = "done"
json.dump(d, open(sys.argv[1], "w"))
PY
run_root "$FX/state/tasks.json" "$FX"
[ "$RC" -ne 0 ] || fail "R21: control — a board-only move did not fail the gate"
set_status E1-F1 in-review || fail "R21: could not restore: $(cat "$T/sl.err")"
pass "R21 a feature transition carries its spec, keeps the gate green, and preserves comments"

# R22 — the epic path, which is what /sdd-drill drives.
set_status E1 in-progress || fail "R22: epic set-status failed: $(cat "$T/sl.err")"
[ "$(fx_status "$FX/specs/epics/E1-one/epic.md")" = "in-progress" ] \
  || fail "R22: epic.md did not follow the board"
run_root "$FX/state/tasks.json" "$FX"
[ "$RC" -eq 0 ] || fail "R22: the gate failed after an epic transition: $(cat "$T/err")"
pass "R22 an epic transition carries epic.md — the /sdd-drill path"

# R23 — the writer's scope is narrow: it syncs a status that is ALREADY declared, and never
# adopts a document that is not its own.
OTHER="$FX/specs/epics/E1-one/F1-a/E1-F2.spec.md"
printf -- '---\nid: E1-F2\nstatus: pending\n---\n' >"$OTHER"
NOFM="$FX/specs/epics/E1-one/F1-a/plain.spec.md"
printf -- '# no frontmatter\n' >"$NOFM"
set_status E1-F1 done || fail "R23: set-status failed: $(cat "$T/sl.err")"
[ "$(fx_status "$OTHER")" = "pending" ] \
  || fail "R23: the writer rewrote a spec declaring ANOTHER feature's id"
grep -qF -- '---' "$NOFM" && fail "R23: the writer invented a frontmatter block"
[ ! -f "$FX/specs/epics/E1-one/F1-a/E1-F1.spec.md.tmp" ] || fail "R23: left a temp file behind"
pass "R23 the writer syncs only a declared status, never another feature's spec or a new block"

# R24 — transactional: if a document cannot be read, the BOARD is not moved either.
# A board that advanced without its document is precisely the divergence the gate
# fail-stops on, so the write must abort before it, not after.
rm -f "$OTHER" "$NOFM"
printf -- '---\nid: E1-F1\nstatus: \200\200done\n---\n' >"$FX/specs/epics/E1-one/F1-a/E1-F1.spec.md"
BEFORE="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['epics'][0]['features'][0]['status'])" "$FX/state/tasks.json")"
if set_status E1-F1 in-progress; then
  fail "R24: set-status succeeded despite an unreadable spec"
fi
AFTER="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['epics'][0]['features'][0]['status'])" "$FX/state/tasks.json")"
[ "$BEFORE" = "$AFTER" ] \
  || fail "R24: the board moved ($BEFORE -> $AFTER) while its spec could not be synced"
grep -F "sync" "$T/sl.err" >/dev/null || fail "R24: the failure did not mention the sync"
pass "R24 an unsyncable document aborts the write — the board never moves alone"

# ══ R25 — containment is re-checked per FILE, not inherited from the directory ═══════
# (Codex #3733506521.) R20 resolves the spec DIRECTORY; a matched `*.spec.md` inside a
# perfectly legitimate directory can still be a symlink whose target is outside the
# repository — in-repo by listing, external in fact.
Z3="$T/r25"; mkdir -p "$Z3/specs/epics/E1-one/F1-a"
OUT3="$T/r25-outside"; mkdir -p "$OUT3"
printf -- '---\nid: E1-F1\nstatus: done\n---\n' >"$OUT3/E1-F1.spec.md"
ln -s "$OUT3/E1-F1.spec.md" "$Z3/specs/epics/E1-one/F1-a/E1-F1.spec.md"
board "$T/r25.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r25.json" "$Z3"
[ "$RC" -ne 0 ] || fail "R25: a spec FILE symlinked out of the repository was accepted"
saw "spec file escapes the harness root" || fail "R25: the file escape was not reported"
# The message must name the path as the BOARD spells it, not as ../../../private/var/…:
# a gate's diagnostic is what the operator acts on (see R17).
saw "specs/epics/E1-one/F1-a/E1-F1.spec.md" \
  || fail "R25: the escape was reported with an unreadable resolved path"
# Control: replace ONLY the symlink with a real file — clean.
rm "$Z3/specs/epics/E1-one/F1-a/E1-F1.spec.md"
mkspec "$Z3" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "done"
run_root "$T/r25.json" "$Z3"
[ "$RC" -eq 0 ] || fail "R25: control — a real in-repo spec file failed: $(cat "$T/err")"
pass "R25 a spec FILE symlinked out of the repo is an escape; a real file at the same path is not"

# ══ R26 — a duplicate `status:`/`id:` is ambiguous, and NEITHER side guesses ══════════
# (Codex #3733506524.) The parser keeps the LAST occurrence; the writer rewrote the FIRST
# and stopped. A sanctioned transition therefore advanced the board while the gate still
# read the old value — a divergence manufactured by the two halves meant to prevent it.
A4="$T/r26"; mkdir -p "$A4/specs/epics/E1-one/F1-a"
printf -- '---\nid: E1-F1\nstatus: done\nstatus: done\n---\n' \
  >"$A4/specs/epics/E1-one/F1-a/E1-F1.spec.md"
board "$T/r26.json" '{"id":"E1-F1","title":"a","status":"done","sdd":true,"depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}'
run_root "$T/r26.json" "$A4"
[ "$RC" -ne 0 ] || fail "R26: a duplicate status: declaration was accepted"
saw "more than once" || fail "R26: the ambiguity was not reported as such"
# Control: drop ONE of the two identical lines — clean. The values never disagreed, so a
# rule that fired on the VALUES rather than the duplication would stay silent here.
mkspec "$A4" "specs/epics/E1-one/F1-a/E1-F1.spec.md" "done"
run_root "$T/r26.json" "$A4"
[ "$RC" -eq 0 ] || fail "R26: control — a single status declaration failed: $(cat "$T/err")"
# The WRITER refuses it too, and the board does not move.
FX2="$T/r26w"
mkdir -p "$FX2/state" "$FX2/store" "$FX2/tools" "$FX2/specs/epics/E1-one/F1-a"
cp "$SRC/tools/tasks-lock.py" "$SRC/tools/validate-board.py" "$FX2/tools/"
cp "$SRC/store/tasks.schema.json" "$FX2/store/"
cat >"$FX2/state/tasks.json" <<'JSON'
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"in-progress","sdd":true,"autonomous":true,
  "depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}]}]}
JSON
printf -- '---\nid: E1-F1\nstatus: in-progress\nstatus: in-progress\n---\n' \
  >"$FX2/specs/epics/E1-one/F1-a/E1-F1.spec.md"
if HARNESS_DIR="$FX2" python3 "$FX2/tools/tasks-lock.py" set-status E1-F1 in-review \
     >"$T/w.out" 2>"$T/w.err"; then
  fail "R26: set-status rewrote a file whose effective status is ambiguous"
fi
[ "$(board_status "$FX2/state/tasks.json")" = "in-progress" ] \
  || fail "R26: the board moved despite the writer refusing the document"
pass "R26 a duplicated status/id is ambiguous — the gate reports it and the writer refuses"

# ══ R27 — a partial frontmatter write is rolled back, board included ══════════════════
# (Codex #3733506522.) With two eligible specs and the SECOND unwritable, the exception
# escaped before the written-list was returned, so nothing could be undone: the board
# stayed put while the first document advanced — the exact divergence the sync prevents,
# manufactured by the sync.
FX3="$T/r27"
mkdir -p "$FX3/state" "$FX3/store" "$FX3/tools" "$FX3/specs/epics/E1-one/F1-a"
cp "$SRC/tools/tasks-lock.py" "$SRC/tools/validate-board.py" "$FX3/tools/"
cp "$SRC/store/tasks.schema.json" "$FX3/store/"
cat >"$FX3/state/tasks.json" <<'JSON'
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"in-progress","sdd":true,"autonomous":true,
  "depends_on":[],"spec_path":"specs/epics/E1-one/F1-a/"}]}]}
JSON
FIRST="$FX3/specs/epics/E1-one/F1-a/a-E1-F1.spec.md"
SECOND="$FX3/specs/epics/E1-one/F1-a/z-E1-F1.spec.md"
printf -- '---\nid: E1-F1\nstatus: in-progress\n---\n' >"$FIRST"
printf -- '---\nid: E1-F1\nstatus: in-progress\n---\n' >"$SECOND"
chmod 444 "$SECOND"
if HARNESS_DIR="$FX3" python3 "$FX3/tools/tasks-lock.py" set-status E1-F1 in-review \
     >"$T/w2.out" 2>"$T/w2.err"; then
  chmod 644 "$SECOND"
  fail "R27: set-status succeeded with an unwritable spec in the directory"
fi
chmod 644 "$SECOND"
[ "$(fx_status "$FIRST")" = "in-progress" ] \
  || fail "R27: the first spec kept a write that the failed transition should have undone"
[ "$(board_status "$FX3/state/tasks.json")" = "in-progress" ] \
  || fail "R27: the board moved while a document could not be written"
pass "R27 a mid-way write failure rolls the earlier documents back and leaves the board put"

# ══ R28 — an EMPTY spec_path is unresolved, not exempt ═══════════════════════════════
# (Codex #3741652118.) `store/tasks.schema.json` declares `spec_path` as `"type": "string"`,
# and `""` satisfies that — so it is NOT a schema error, and skipping it here let an
# authored feature opt out of every rule in this file by naming nothing at all.
B4="$T/r28"; mkdir -p "$B4/specs/epics"
cat >"$T/r28.json" <<'JSON'
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"in-review","sdd":true,"depends_on":[],"spec_path":""}]}]}
JSON
run_root "$T/r28.json" "$B4"
[ "$RC" -ne 0 ] || fail "R28: an authored feature with an empty spec_path passed"
saw "spec_path is empty" || fail "R28: the empty path was not reported as empty"
# The board is schema-VALID: prove the empty string is accepted upstream, so this rule is
# the only thing standing between it and a green gate.
run_bare "$T/r28.json"
[ "$RC" -eq 0 ] || fail "R28: precondition — an empty spec_path must be schema-valid"
# Controls: the same empty path is silent for the two non-authored classes, exactly as a
# missing directory is (R3, R4).
cat >"$T/r28b.json" <<'JSON'
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"done","sdd":false,"depends_on":[],"spec_path":""}]}]}
JSON
run_root "$T/r28b.json" "$B4"
[ "$RC" -eq 0 ] || fail "R28: an empty spec_path was demanded of an sdd:false feature"
cat >"$T/r28c.json" <<'JSON'
{"project":"fx","epics":[{"id":"E1","title":"one","status":"planned","features":[
 {"id":"E1-F1","title":"a","status":"pending","sdd":true,"depends_on":[],"spec_path":""}]}]}
JSON
run_root "$T/r28c.json" "$B4"
[ "$RC" -eq 0 ] || fail "R28: an empty spec_path was demanded of a pending feature"
pass "R28 an empty spec_path fails for an authored feature and is silent for the rest"

echo "all board/spec consistency checks passed"
