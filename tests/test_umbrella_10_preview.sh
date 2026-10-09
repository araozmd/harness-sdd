#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

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

# A final negative probe is not a suite failure.
exit 0
