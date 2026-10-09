#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

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
# A TWO-HOP alias whose first hop stays inside the tier but whose eventual target escapes it.
# Keeping `alias` while stubbing `escaped` changes what `alias` reads from authoritative bytes
# to pointer text, so validating only the direct target's parent is insufficient.
printf 'authoritative bytes beyond the moved tree\n' > "$F04M/outside.md"
ln -s ../../outside.md "$UM4/docs/escaped"
ln -s escaped "$UM4/docs/alias"
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
[ -L "$UM4/docs/alias" ] && [ -L "$UM4/docs/escaped" ] \
  || fail "R5 alias-chain control: docs/alias -> escaped -> ../../outside.md was not created"
[ "$(cat "$UM4/docs/alias")" = 'authoritative bytes beyond the moved tree' ] \
  || fail "R5 alias-chain control: the umbrella alias does not resolve to the external authoritative bytes before maintenance"
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
[ -L "$KM4/docs/alias" ] \
  && fail "R5: docs/alias was retained even though its direct target is an escaping symlink; in the child that alias reads the replacement stub instead of the external bytes it names at the umbrella"
is_stub "$KM4/docs/alias" \
  || fail "R5: docs/alias is neither a link nor a stub after the chained-target maintenance run"
grep -qF '../../.harness/docs/alias' "$KM4/docs/alias" \
  || fail "R5: the stub that replaced docs/alias does not name the authoritative umbrella path"
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

# A final negative probe is not a suite failure.
exit 0
