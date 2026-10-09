#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

# ── R2: a failure PART-WAY THROUGH the write leaves the tier WHOLE ──────────────────────
# thin_partial_failure_leaves_tier_whole
#
# R2's all-or-nothing rule is about the tier, not only about the pristine check: a write
# that converted entries 1-3 and then died on entry 4 produced exactly the mixed layout the
# rule forbids. Measured on the sequential implementation with this fixture: 20 stubs and 10
# real files in one child. (Codex r2 P2 #3799616454.)
#
# ── the swap half, with a trigger that needs NO permissions ─────────────────────────────
# THE FAILURE IS STRUCTURAL, NOT A MODE BIT. `prose_swap_in` opens with
# `mkdir -p "$(dirname "$_pi_dst")"`, and for tier entry 4 of 5 that directory is
# `.harness/specs`. `mkdir -p` over a REGULAR FILE fails with EEXIST/ENOTDIR — which is not a
# permission check, so root cannot bypass it — while entries 1-3 have already been swapped.
# The previous trigger was a `0555` directory, and root moves straight through it: as root the
# write SUCCEEDED, the control below fired, and the suite failed. A skip would have fixed the
# gate while testing the rollback on no root box at all; this tests it on every box.
#
# IT RUNS ON THE MAINTENANCE ARM, which is what makes the trigger reachable: the conversion arm
# would first compare the tier against the umbrella and refuse outright, because a `specs` that
# is a file has no `specs/_templates` under it to be pristine.
#
# WHAT MAKES THE ROLLBACK OBSERVABLE ON A TIER THAT IS ALREADY STUBS: entries 1-3 are given a
# MARKER LINE first. A rolled-back run restores the operator's exact bytes, marker included; a
# run that left the swap in place would show freshly written stubs without it. The marker is
# APPENDED so line 1 stays the sentinel and the child still reads as thin — overwrite line 1
# and `child_is_full_copy` sends the run to the conversion arm instead.
F04Q="$AU/f04q"
mk_umb "$F04Q" kid
cascade "$F04Q" --thin
KQ4="$F04Q/kid/.harness"
f04_all_stubs_in_tier "$KQ4" "R2 swap-half fixture (the child must be thin, or this run takes another arm)"
F04Q_MARKED='AGENTS.md agents/builder.md docs/WORKFLOW.md'
for _q in $F04Q_MARKED; do
  printf 'OPERATOR-MARKER-DO-NOT-LOSE\n' >> "$KQ4/$_q"
  is_stub "$KQ4/$_q" \
    || fail "R2 swap-half control: marking $_q destroyed the stub sentinel on line 1, so the child no longer reads as thin and the run would take the conversion arm"
done
rm -rf "$KQ4/specs"
printf 'this is a regular file, not a directory\n' > "$KQ4/specs"
[ -f "$KQ4/specs" ] \
  || fail "R2 swap-half control: .harness/specs is not a regular file, so mkdir -p will succeed and the write will not fail"
F04Q_OUT="$(CODEX_HOME="$F04Q/.ch" HOME="$F04Q/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04Q/kid" 2>&1)" && F04Q_RC=0 || F04Q_RC=$?
[ "$F04Q_RC" = "0" ] \
  && fail "R2 swap-half control: the install SUCCEEDED with .harness/specs a regular file, so the swap never failed and nothing below discriminates: $F04Q_OUT"
printf '%s\n' 2>/dev/null "$F04Q_OUT" | grep -qF 'could not install the thin prose tier' \
  || fail "R2 swap-half control: the run failed somewhere other than the prose-tier SWAP, so no swap was ever rolled back: $F04Q_OUT"
# THE CLAIM: every entry already swapped is back, byte for byte, including content this run
# did not write and could not reconstruct.
for _q in $F04Q_MARKED; do
  grep -qF 'OPERATOR-MARKER-DO-NOT-LOSE' "$KQ4/$_q" \
    || fail "R2: after a swap that failed at entry 4 of 5, $_q lost the bytes it held before the run — the rollback did not restore it, so the tier is part-written: $F04Q_OUT"
done
[ "$(head -n 1 "$KQ4/specs")" = 'this is a regular file, not a directory' ] \
  || fail "R2: the failed run modified .harness/specs, which it never successfully swapped"
F04Q_DEBRIS="$(ls -d "$KQ4"/.harness-prose-* 2>/dev/null || true)"
[ -z "$F04Q_DEBRIS" ] \
  || fail "R2: the rolled-back run left staging directories inside .harness: $F04Q_DEBRIS"

# ── a failed restore of the CURRENT entry preserves both recovery trees ────────────────
# prose_swap_in normally restores the entry it just parked before returning failure; the
# caller's undo list therefore contains only EARLIER successful swaps. If that current-entry
# restore also fails, treating it like an ordinary failure and deleting both temp trees
# destroys the only surviving original. A doctored installer deterministically makes `docs`
# the current entry: its live original is parked, the staged move is refused, and the restore
# is refused. No permissions or uid assumptions are involved.
F04T="$AU/f04t"
mk_umb "$F04T" kid
cascade "$F04T" --thin
KT4="$F04T/kid/.harness"
f04_all_stubs_in_tier "$KT4" "R2 current-restore fixture (the child must start thin)"
printf 'EARLIER-ROLLBACK-MARKER\n' >> "$KT4/AGENTS.md"
printf 'EARLIER-ROLLBACK-MARKER\n' >> "$KT4/agents/builder.md"
printf 'CURRENT-ORIGINAL-MARKER\n' >> "$KT4/docs/WORKFLOW.md"

F04T_SRC="$AU/f04t-mut-src"
mkdir -p "$F04T_SRC"
for _md in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
           harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
  [ -e "$SRC/$_md" ] && cp -R "$SRC/$_md" "$F04T_SRC/"
done
awk '
  $0 == "    if mv \"$_prose_stg/$_pi_rel\" \"$_pi_dst\"; then" {
    print "    if [ \"$_pi_rel\" != \"docs\" ] && mv \"$_prose_stg/$_pi_rel\" \"$_pi_dst\"; then # mutation: staged docs move fails"
    next
  }
  $0 ~ /^      mv "\$_pi_old" "\$_pi_dst" \|\| return 2$/ {
    print "      [ \"$_pi_rel\" != \"docs\" ] && mv \"$_pi_old\" \"$_pi_dst\" || return 2 # mutation: current docs restore fails"
    next
  }
  { print }
' "$F04T_SRC/harness-install.sh" > "$F04T_SRC/harness-install.mut"
mv "$F04T_SRC/harness-install.mut" "$F04T_SRC/harness-install.sh"
[ "$(grep -c 'mutation: staged docs move fails' "$F04T_SRC/harness-install.sh")" = "1" ] \
  && [ "$(grep -c 'mutation: current docs restore fails' "$F04T_SRC/harness-install.sh")" = "1" ] \
  || fail "R2 current-restore control: the doctored installer did not inject both failures exactly once"

F04T_OUT="$(CODEX_HOME="$F04T/.ch" HOME="$F04T/.home" \
  sh "$F04T_SRC/harness-install.sh" --agents=claude "$F04T/kid" 2>&1)" && F04T_RC=0 || F04T_RC=$?
[ "$F04T_RC" != "0" ] || fail "R2 current-restore control: the doctored install succeeded, so neither injected failure was observed"
printf '%s\n' 2>/dev/null "$F04T_OUT" | grep -qF 'current entry docs could not be restored' \
  || fail "R2: a failed restore of the current entry was reported as an ordinary rolled-back failure: $F04T_OUT"
for _p in AGENTS.md agents/builder.md; do
  grep -qF 'EARLIER-ROLLBACK-MARKER' "$KT4/$_p" \
    || fail "R2: current-entry restore failed and the caller did not roll back the earlier entry $_p"
done
[ ! -e "$KT4/docs" ] \
  || fail "R2 current-restore control: docs still exists live, so the original was not left parked and the destructive cleanup path was not reached"
F04T_OLD="$(find "$KT4" -maxdepth 1 -type d -name '.harness-prose-replaced.*' -print | head -n 1)"
F04T_STG="$(find "$KT4" -maxdepth 1 -type d -name '.harness-prose-staging.*' -print | head -n 1)"
[ -n "$F04T_OLD" ] && [ -n "$F04T_STG" ] \
  || fail "R2: current-entry restore failed but one or both recovery trees were deleted: $F04T_OUT"
grep -qF 'CURRENT-ORIGINAL-MARKER' "$F04T_OLD/docs/WORKFLOW.md" \
  || fail "R2: the preserved originals tree does not contain the current entry's operator bytes"
is_stub "$F04T_STG/docs/WORKFLOW.md" \
  || fail "R2: the preserved staging tree does not contain the replacement for the current entry"
pass "R2 thin_current_restore_failure_preserves_recovery — earlier swaps roll back and both current-entry recovery trees survive"

# ── the same half again, on a PRISTINE FULL COPY — richer, but mode-dependent ───────────
# This is the product's actual claim (R2 is about CONVERSIONS): a full-copy child that fails
# part-way must still be byte-identical to the umbrella afterwards. No permission-free trigger
# reaches it — the conversion arm requires a pristine tier, which forecloses every structural
# shape — so it runs only where mode bits bind, and the deterministic half above is what
# carries the rollback on the boxes where they do not.
F04L_SKIPPED=0
if modes_bind_this_uid; then
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
else
  F04L_SKIPPED=1
  echo "skip - R2 full-copy swap half: mode bits do not bind this user (uid $(id -u)), so a 0555 directory cannot make the write fail and the rows would assert a refusal that never happens; the structural swap half above covers the rollback here" >&2
fi

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
#
# AND IT IS MODE-DEPENDENT TOO, which the swap half's finding did not mention: root reads a
# `0000` file, so as root `cp -R` succeeds, the build never fails, and the control below fires.
# Unlike the swap half there is no structural substitute — `stage_tree` can only be made to
# fail through the umbrella body's contents, and every shape that survives the entry-set's
# `[ -e ]` filter is one `cp -R` copies happily (a socket would do it on BSD, but I cannot
# verify GNU `cp` here and trading a root dependence for an untested libc dependence is not a
# fix). So this half announces a skip where modes do not bind, and says so.
F04N_SKIPPED=0
if modes_bind_this_uid; then
F04M="$AU/f04m2"
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
else
  F04N_SKIPPED=1
  echo "skip - R2 build half: mode bits do not bind this user (uid $(id -u)), so an unreadable file cannot make \`cp -R\` fail and the rows would assert a failure that never happens" >&2
fi
# THE SKIPS ARE PINNED, because the announcements above cannot be relied on to surface: the
# configured verification.test_command captures each suite's stderr and prints it only on
# failure, so on a green run these lines are discarded. Unpinned, a skip that became
# always-taken would leave the suite green while both mode-dependent halves ran nowhere.
# These re-read `id -u`, so they are controls rather than independent oracles — they cannot
# catch a wholesale rewrite of the probe, but they do kill the single-point mutation (forcing
# the branch always-true) that is the realistic way this rots. The probe itself asks the
# filesystem, which is the stronger question; this only asks that its answer was plausible.
for _sk in "F04L_SKIPPED=$F04L_SKIPPED" "F04N_SKIPPED=$F04N_SKIPPED"; do
  [ "${_sk#*=}" = "0" ] || [ "$(id -u)" = "0" ] \
    || fail "R2: ${_sk%%=*} fired as uid $(id -u) — a user whose mode bits are NOT bypassed was told they were, so a half that could have run was skipped instead"
done
pass "R2 thin_partial_failure_leaves_tier_whole — a write that fails part-way leaves the tier whole in both halves: a failed swap rolls the earlier swaps back (on a permission-free structural trigger, plus a richer full-copy variant where modes bind), and a failed build writes nothing at all"

# A final negative probe is not a suite failure.
exit 0
