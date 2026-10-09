#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

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
#   docs/SPEC-FORMAT.md     a WHITESPACE-ONLY edit — the comparison is BYTE identity.
#                           specs/glossary.md used to carry this shape, but it left the
#                           prose tier entirely (E30-F01, project-owned in every layout —
#                           see glossary_never_stubbed_in_any_layout below), so this case
#                           is re-pointed at another prose-tier REGULAR FILE no other
#                           fixture in this suite touches (see thin_comparison_is_byte_identity
#                           below)
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
awk 'NR == 1 { printf "%s \n", $0; next } { print }' "$KS4/docs/SPEC-FORMAT.md" > "$AU/f04c-specformat.tmp"
cat "$AU/f04c-specformat.tmp" > "$KS4/docs/SPEC-FORMAT.md"
# PRECONDITIONS for thin_comparison_is_byte_identity below. The edit must be a real BYTE
# difference and must NOT survive `-w`, or the case degenerates into the AGENTS.md shape
# and stops saying anything about byte identity. Measured against the umbrella's own copy,
# which is the reference the conversion uses.
cmp -s "$KS4/docs/SPEC-FORMAT.md" "$F04C/.harness/docs/SPEC-FORMAT.md" \
  && fail "R3 control: the seeded docs/SPEC-FORMAT.md edit is not a byte difference at all — the byte-identity case below would be vacuous"
diff -qw "$KS4/docs/SPEC-FORMAT.md" "$F04C/.harness/docs/SPEC-FORMAT.md" >/dev/null 2>&1 \
  || fail "R3 control: the seeded docs/SPEC-FORMAT.md edit is NOT whitespace-only, so it would also be caught by an identity-modulo-whitespace comparison and pins nothing about BYTE identity"
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
# It is also the only difference this suite ever seeds on `docs/SPEC-FORMAT.md`, so it is
# what stops the prose sweep from being written as a hardcoded tier list that drops that
# entry: dropped, the entry is never compared and the child converts on the strength of a
# comparison that never ran. Both mutations leave every other case in this suite green.
printf '%s\n' 2>/dev/null "$F04C_SEG" | grep -qF 'differs: docs/SPEC-FORMAT.md' \
  || fail "R2/R3: a WHITESPACE-ONLY edit to docs/SPEC-FORMAT.md was not reported as a blocker — either the comparison is identity-modulo-whitespace rather than BYTE identity, or the prose sweep never compared that entry at all; under either, a child whose ONLY difference is that edit CONVERTS and its prose tier is deleted: $F04C_SEG"
pass "R2/R3 thin_comparison_is_byte_identity — a whitespace-only edit to docs/SPEC-FORMAT.md blocks the tier and is named"

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

# A final negative probe is not a suite failure.
exit 0
