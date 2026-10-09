#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

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

# A final negative probe is not a suite failure.
exit 0
