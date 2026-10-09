#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

# ── R2/R8: cleanup unlinks a destination symlink BEFORE widening modes ────────────────
# cleanup_unlinks_destination_symlink_before_chmod
# `chmod -R u+w symlink-to-directory` follows a command-line symlink on GNU systems even
# though it ignores links encountered during recursive traversal. The eventual `rm -rf`
# removes only the link, but the chmod has already mutated user-owned bytes outside the
# target. A chmod shim makes that platform behavior deterministic on every host: it changes
# the external probe only if the installer hands it the live destination symlink.
F04S="$AU/f04s"
f04_fullchild "$F04S" kid
KS4="$F04S/kid/.harness"
F04S_EXT="$F04S/external-user-tree"
F04S_PROBE="$F04S_EXT/private.txt"
F04S_HARD_PROBE="$F04S_EXT/hardlink-private.txt"
mkdir -p "$F04S_EXT"
printf 'external operator bytes\n' > "$F04S_PROBE"
printf 'external hard-link operator bytes\n' > "$F04S_HARD_PROBE"
chmod 0400 "$F04S_PROBE"
chmod 0400 "$F04S_HARD_PROBE"
F04S_MODE_BEFORE="$(python3 -c 'import os,stat,sys; print("%o" % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$F04S_PROBE")"
F04S_HARD_MODE_BEFORE="$(python3 -c 'import os,stat,sys; print("%o" % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$F04S_HARD_PROBE")"
rm -rf "$KS4/tools"
ln -s "$F04S_EXT" "$KS4/tools"
rm -f "$KS4/init.sh"
ln "$F04S_HARD_PROBE" "$KS4/init.sh"
[ -L "$KS4/tools" ] && [ "$(readlink "$KS4/tools")" = "$F04S_EXT" ] \
  || fail "R2 cleanup-symlink control: .harness/tools is not the external destination symlink"
python3 -c 'import os,sys; sys.exit(0 if os.path.samefile(sys.argv[1], sys.argv[2]) else 1)' \
  "$KS4/init.sh" "$F04S_HARD_PROBE" \
  || fail "R2 cleanup-hardlink control: .harness/init.sh does not share the external probe inode"

F04S_SHIM="$F04S/chmod-shim"
mkdir -p "$F04S_SHIM"
F04S_REAL_CHMOD="$(command -v chmod)"
export F04S_REAL_CHMOD F04S_PROBE KS4
cat > "$F04S_SHIM/chmod" <<'SH'
#!/bin/sh
for _cs_arg do
  if [ "$_cs_arg" = "$KS4/tools" ]; then
    "$F04S_REAL_CHMOD" u+w "$F04S_PROBE"
  fi
done
exec "$F04S_REAL_CHMOD" "$@"
SH
chmod +x "$F04S_SHIM/chmod"
F04S_OUT="$(CODEX_HOME="$F04S/.ch" HOME="$F04S/.home" PATH="$F04S_SHIM:$PATH" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04S/kid" 2>&1)" && F04S_RC=0 || F04S_RC=$?
[ "$F04S_RC" = "0" ] \
  || fail "R2 cleanup-symlink fixture: reinstall exited $F04S_RC: $F04S_OUT"
F04S_MODE_AFTER="$(python3 -c 'import os,stat,sys; print("%o" % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$F04S_PROBE")"
F04S_HARD_MODE_AFTER="$(python3 -c 'import os,stat,sys; print("%o" % stat.S_IMODE(os.stat(sys.argv[1]).st_mode))' "$F04S_HARD_PROBE")"
[ "$F04S_MODE_AFTER" = "$F04S_MODE_BEFORE" ] \
  || fail "R2: cleanup followed .harness/tools outside the target and changed external mode $F04S_MODE_BEFORE to $F04S_MODE_AFTER"
[ "$F04S_HARD_MODE_AFTER" = "$F04S_HARD_MODE_BEFORE" ] \
  || fail "R2: cleanup chmodded a hard-linked .harness/init.sh and changed the external inode mode $F04S_HARD_MODE_BEFORE to $F04S_HARD_MODE_AFTER"
grep -qF 'external operator bytes' "$F04S_PROBE" \
  || fail "R2: cleanup damaged the external file reached through .harness/tools"
grep -qF 'external hard-link operator bytes' "$F04S_HARD_PROBE" \
  || fail "R2: cleanup damaged the external file hard-linked at .harness/init.sh"
[ -d "$KS4/tools" ] && [ ! -L "$KS4/tools" ] \
  || fail "R8: the destination symlink was not replaced by the installed local tools directory"
cmp -s "$KS4/init.sh" "$SRC/init.sh" \
  || fail "R8: the destination hard link was not replaced by the installed local init.sh"
pass "R2/R8 cleanup_unlinks_destination_symlink_before_chmod — external symlink/hard-link modes and bytes survive while both destinations are replaced"

# ── R2/R8: the cleanup after a SUCCEEDING conversion cannot wedge the child ─────────────
# thin_cleanup_removes_readonly_parked_tree
#
# The case above is about a write that FAILS. This one is about a write that SUCCEEDS and is
# then undone by its own housekeeping. `cp -R` carries the source's modes, so a prose tier
# holding a `0555` directory produces a PARKED ORIGINAL holding one, and the final
# `rm -rf` of that parked tree cannot unlink through it. Under `set -e` the run then dies
# AFTER the tier has been swapped — measured, and each of these is a separate wrong thing
# (Codex #3805383748):
#   exit 1, with `rm: … Directory not empty` as the only explanation
#   the tier CONVERTED on disk
#   `manifest.txt` still saying `full body layout`, because the run died before it
#   `.harness-prose-replaced.<pid>` left inside `.harness`
# The report also predicted that subsequent installs would fail on the same debris. They do
# NOT: `$_prose_old` carries the PID, so a later run creates its own and never touches it.
# Measured over two further `--thin` runs, both exit 0. The debris simply accumulates and
# `init.sh` still reports the child healthy, which makes the wedge silent rather than loud.
#
# THE MODE IS ON THE CHILD'S SIDE ONLY, which is what keeps the tier convertible: `diff -rq`
# compares content, not permission bits, so a `0555` directory is still byte-identical to the
# umbrella's and the conversion proceeds — reaching the cleanup, which is the point.
F04R_SKIPPED=0
if modes_bind_this_uid; then
  F04R="$AU/f04r"
  F04R_SRC="$AU/f04r-src"
  mkdir -p "$F04R_SRC"
  for _rd in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
             harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
    [ -e "$SRC/$_rd" ] && cp -R "$SRC/$_rd" "$F04R_SRC/"
  done
  # A NESTED directory under a prose entry, because the tier ROOT must stay writable: moving
  # `docs` aside needs write access to `docs` itself, so a read-only ROOT fails the SWAP and
  # never reaches the cleanup this case is about.
  #
  # THE MODE IS SET ON THE SOURCE, not on the installed child, and that is not a shortcut: it
  # is how the shape actually arises. `cp -R` carries the source's modes across, so every
  # install of such a source plants a read-only directory in the target — which is what makes
  # the second install below a real idempotence claim rather than a contrived one.
  mkdir -p "$F04R_SRC/docs/nested"
  echo "nested body" > "$F04R_SRC/docs/nested/deep.md"
  chmod 0555 "$F04R_SRC/docs/nested"
  mk_umb "$F04R" kid
  CODEX_HOME="$F04R/.ch" HOME="$F04R/.home" \
    sh "$F04R_SRC/harness-install.sh" --agents=claude "$F04R/kid" >/dev/null 2>&1 \
    || fail "R2 cleanup fixture: the FIRST install from a source holding a read-only directory failed"
  KR4="$F04R/kid/.harness"
  [ -d "$KR4/docs/nested" ] \
    || fail "R2 cleanup fixture: the doctored source did not put a nested directory under docs/"
  [ -w "$KR4/docs/nested" ] \
    && fail "R2 cleanup control: the installed docs/nested is writable, so cp -R did not carry the source's mode across and nothing below has anything to trip on"
  # THE ORDINARY COPY PATH FIRST, because it is where this rule bites hardest and it is NOT the
  # cited site: `copy` also `rm -rf`s a tree it laid down with `cp -R`, so a source carrying a
  # read-only directory made the installer NON-IDEMPOTENT — install 1 exit 0, install 2 exit 1,
  # measured. One helper rather than one more `chmod` at one more call site is what fixes both.
  F04R_OUT2="$(CODEX_HOME="$F04R/.ch" HOME="$F04R/.home" \
    sh "$F04R_SRC/harness-install.sh" --agents=claude "$F04R/kid" 2>&1)" && F04R_RC2=0 || F04R_RC2=$?
  [ "$F04R_RC2" = "0" ] \
    || fail "R2: re-installing over a target whose body holds a read-only directory exited $F04R_RC2 — the installer is not idempotent for such a source: $F04R_OUT2"
  CODEX_HOME="$F04R/.ch" HOME="$F04R/.home" \
    sh "$F04R_SRC/harness-install.sh" --umbrella "$F04R" --agents=claude >/dev/null 2>&1 || true
  f04_no_stub_in_tier "$KR4" "R2 cleanup fixture (the child must be a FULL COPY to convert)"
  # PRECONDITION: the tier is STILL convertible — without it the run refuses and never cleans up.
  diff -rq "$KR4/docs" "$F04R/.harness/docs" >/dev/null 2>&1 \
    || fail "R2 cleanup control: the child's docs/ already differs from the umbrella's BY CONTENT, so the run would refuse before reaching the cleanup"
  F04R_OUT="$(CODEX_HOME="$F04R/.ch" HOME="$F04R/.home" \
    sh "$F04R_SRC/harness-install.sh" --agents=claude --thin "$F04R/kid" 2>&1)" && F04R_RC=0 || F04R_RC=$?
  chmod -R u+w "$KR4" 2>/dev/null || :
  [ "$F04R_RC" = "0" ] \
    || fail "R2: a conversion whose parked original holds a read-only directory exited $F04R_RC — the tier is already swapped by then, so the run fails after changing the child: $F04R_OUT"
  # ALL FOUR CONSEQUENCES, not just the exit status: a run that merely stopped failing while
  # still leaving debris or a lying manifest would satisfy an exit-code-only assertion.
  f04_all_stubs_in_tier "$KR4" "R2 (the conversion must still convert the whole tier)"
  grep -q 'This target holds the thin body layout' "$KR4/manifest.txt" \
    || fail "R2/R8: the child converted but its manifest does not record the thin layout — the run died before writing it, so the manifest disagrees with the tier on disk: $(grep -o 'holds the [a-z]* body layout' "$KR4/manifest.txt" 2>/dev/null)"
  F04R_DEBRIS="$(ls -d "$KR4"/.harness-prose-* 2>/dev/null || true)"
  [ -z "$F04R_DEBRIS" ] \
    || fail "R2: the conversion left its parked originals inside .harness: $F04R_DEBRIS"
  chmod -R u+w "$F04R_SRC" 2>/dev/null || :
  pass "R2/R8 thin_cleanup_removes_readonly_parked_tree — a conversion whose parked original holds a read-only directory still exits 0, records the thin layout and leaves no debris, and an ordinary re-install over the same shape stays idempotent"
else
  F04R_SKIPPED=1
  echo "skip - R2/R8 thin_cleanup_removes_readonly_parked_tree: mode bits do not bind this user (uid $(id -u)), so \`rm -rf\` cannot fail on a 0555 directory and the wedge this pins cannot occur here" >&2
fi
[ "$F04R_SKIPPED" = "0" ] || [ "$(id -u)" = "0" ] \
  || fail "R2: the cleanup case was SKIPPED as uid $(id -u) — the probe told a constrained user their mode bits were bypassed, so the case ran nowhere"

# A final negative probe is not a suite failure.
exit 0
