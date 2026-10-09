#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

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
#                           `../../.harness/AGENTS.md`, a file the umbrella cannot
#                           supply, and that stub's own text misreads the dangling target as
#                           "a checkout separated from its umbrella". No warning at all.
#   die                     an installer that simply passed the umbrella body down: exit 1,
#                           `source missing: AGENTS.md`, on an ORDINARY maintenance
#                           run. Every cascade against that umbrella is wedged — including
#                           the ones that would upgrade it — for a path nothing had asked to
#                           be rewritten.
# The rule is SKIP: the entry is left exactly as found, the path is named on stderr, exit 0.
# Both directions are asserted, because "left as found" means different things on each side
# and only both together forbid the two wrong answers.
#
# THE REMOVED ENTRY IS `AGENTS.md`, not `specs/glossary.md`. The glossary left the prose
# tier entirely (E30-F01) — it is project-owned in every layout and is never a candidate
# for "the umbrella does not hold this entry" — so this fixture is re-pointed at the one
# other REGULAR-FILE (non-directory) top-level tier entry, matching the shape of the case
# it replaces.
F04N="$AU/f04n"
mk_umb "$F04N" thinkid
cascade "$F04N"
KN4="$F04N/thinkid/.harness"
f04_all_stubs_in_tier "$KN4" "R2/R6 fixture (a fresh cascade child must be thin)"
cp "$KN4/AGENTS.md" "$AU/f04n-agentsmd.ref"
# AN UMBRELLA OLDER THAN THIS INSTALLER, seeded the only way a fixture can: remove from the
# installed umbrella body a tier entry the installer still lists.
rm -f "$F04N/.harness/AGENTS.md"
if [ -e "$F04N/.harness/AGENTS.md" ]; then
  fail "R2/R6 control: the umbrella body still holds AGENTS.md, so nothing below exercises a missing entry"
fi
[ -e "$SRC/AGENTS.md" ] \
  || fail "R2/R6 control: the installer's own \$SRC does not hold AGENTS.md either, so this fixture cannot tell the umbrella apart from \$SRC"

# (a) AN ALREADY-THIN CHILD that HOLDS the stub. "Left as found" here means the stub survives
# byte for byte — this is the destructive half, and the one the shipped `$SRC` reference
# passed for the wrong reason.
F04N_OUT="$(CODEX_HOME="$F04N/.ch" HOME="$F04N/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04N/thinkid" 2>&1)" && F04N_RC=0 || F04N_RC=$?
[ "$F04N_RC" = "0" ] \
  || fail "R6: a routine maintenance run against an umbrella that lacks one tier entry exited $F04N_RC — an umbrella older than the installer must not wedge the runs that would upgrade it: $F04N_OUT"
printf '%s\n' 2>/dev/null "$F04N_OUT" | grep -qF "does not hold the prose-tier path 'AGENTS.md'" \
  || fail "R3/R6: the run skipped a tier entry without naming it, so the operator has no way to learn why that path stopped being maintained: $F04N_OUT"
printf '%s\n' 2>/dev/null "$F04N_OUT" | grep -qF "does not hold the prose-tier path 'agents'" \
  && fail "R6: the run reported 'agents' as missing from the umbrella too — the skip is firing on entries the umbrella does hold, so the message discriminates nothing: $F04N_OUT"
cmp -s "$AU/f04n-agentsmd.ref" "$KN4/AGENTS.md" \
  || fail "R2: the maintenance run rewrote or deleted AGENTS.md, which the umbrella no longer holds — the entry must be left exactly as it was found"
f04_all_stubs_in_tier "$KN4" "R2/R6 (skipping one entry must not disturb the rest of the tier)"

# (b) A FRESH child, which has never held the path. "Left as found" here means ABSENT — the
# direction that forbids inventing a stub the umbrella cannot resolve. The other three entries
# must still be stubbed, or "no dangling stub" is satisfied by a run that wrote nothing.
mk_umb "$F04N" newkid
# `HARNESS_UMBRELLA_ROOT` rather than a cascade: a cascade re-installs the COORDINATOR's own
# prose tier from `$SRC` first, which would restore the entry this fixture just removed.
F04N2_OUT="$(HARNESS_UMBRELLA_ROOT='../../' CODEX_HOME="$F04N/.ch" HOME="$F04N/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04N/newkid" 2>&1)" && F04N2_RC=0 || F04N2_RC=$?
KN5="$F04N/newkid/.harness"
[ "$F04N2_RC" = "0" ] \
  || fail "R6: a fresh child under an umbrella that lacks one tier entry exited $F04N2_RC: $F04N2_OUT"
if [ -e "$KN5/AGENTS.md" ]; then
  fail "R2: the umbrella does not hold AGENTS.md and the run created one anyway — the stub names ../../.harness/AGENTS.md, which the umbrella cannot supply, and its own text then misreads that dangling target as a checkout separated from its umbrella: $F04N2_OUT"
fi
for _p in agents docs specs/_templates; do
  [ -e "$KN5/$_p" ] \
    || fail "R2/R6 control: the fresh child's $_p was not materialised at all, so 'AGENTS.md is absent' is explained by a run that wrote no tier: $F04N2_OUT"
done
is_stub "$KN5/agents/builder.md" \
  || fail "R2/R6 control: the fresh child's agents/builder.md is not a stub, so this run did not take the thin arm: $F04N2_OUT"
pass "R2/R6 thin_umbrella_missing_entry_is_left_alone — an entry the umbrella lacks keeps its existing stub, is never invented, is named, and never fails the run"

# A final negative probe is not a suite failure.
exit 0
