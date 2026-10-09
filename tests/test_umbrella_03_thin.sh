#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"

# ── FIXTURE PRECONDITION for every stub assertion below ────────────────────────────────
# A single-repo install is the control: if the prose tier there were ALSO missing or
# stubbed, "contains the sentinel" downstream would prove nothing at all.
TF="$AU/f03-control"
mkdir -p "$TF"
CODEX_HOME="$TF/.ch" HOME="$TF/.home" sh "$SRC/harness-install.sh" --agents=claude "$TF" >/dev/null 2>&1 \
  || fail "R5 control: single-repo install exited non-zero"
for _p in $PROSE_TIER $LOCAL_TIER; do
  [ -f "$TF/.harness/$_p" ] || fail "R5 control: single-repo install is missing $_p"
  is_stub "$TF/.harness/$_p" && fail "R5: single-repo install stubbed $_p — there is no umbrella to resolve"
done
grep -qF 'You are the **Builder**' "$TF/.harness/agents/builder.md" \
  || fail "R5 control: agents/builder.md is not the real body"
# No file ANYWHERE in the tree may be a stub — a per-file probe is only ever as complete
# as the last bug report. The predicate is "line 1 IS the sentinel", not "contains it":
# `init.sh` legitimately carries the literal string in its own layout detection, and a
# substring scan reads that as a stub. Being a stub was always a line-1 property; the
# loose form only looked equivalent until init.sh learned to detect one.
_f03_stubs=0
for _f in $(find "$TF/.harness" -type f); do
  is_stub "$_f" && { echo "   unexpected stub: $_f" >&2; _f03_stubs=$((_f03_stubs + 1)); }
done
[ "$_f03_stubs" = "0" ] \
  || fail "R5: a single-repo install wrote $_f03_stubs stub(s) in .harness/"
pass "R5 single_repo_body_is_complete — no umbrella.root ⇒ full body, no sentinel anywhere"

# ── R1/R2/R3/R4: a fresh cascade child is thin ─────────────────────────────────────────
mk_umb "$AU/f03" kid-a kid-b
cascade "$AU/f03"
KA="$AU/f03/kid-a/.harness"
[ -d "$KA" ] || fail "R2 setup: the cascade did not install into kid-a"

grep -q '^  root: "\.\./\.\./"' "$KA/harness.config.yaml" \
  || fail "R1: the cascade did not record umbrella.root in the child config"
pass "R1 cascade_records_umbrella_root"

for _p in $PROSE_TIER; do
  is_stub "$KA/$_p" || fail "R2: prose-tier $_p is not a stub in a fresh cascade child"
done
pass "R2 thin_child_prose_tier_is_stubbed"

for _p in $LOCAL_TIER; do
  [ -f "$KA/$_p" ] || fail "R4: program-tier $_p missing from a thin child"
  is_stub "$KA/$_p" && fail "R4: program-tier $_p was stubbed — init.sh execs/parses it"
done
grep -q 'tasks.schema.json\|"\$schema"\|properties' "$KA/store/tasks.schema.json" \
  || fail "R4: store/tasks.schema.json is not a real schema in a thin child"
pass "R4 thin_child_standalone_tier_is_local"

# The stub is a contract: sentinel, the resolved path, and the recovery instruction. And
# the path it names must actually resolve from the child's own harness dir.
is_stub "$KA/agents/builder.md" || fail "R3: stub has no sentinel on line 1"
grep -qF '../../.harness/agents/builder.md' "$KA/agents/builder.md" \
  || fail "R3: stub does not name the resolved path of its authoritative copy"
grep -qiF 'run the harness installer against this repository with `--standalone`' "$KA/agents/builder.md" \
  || fail "R3: stub does not name the recovery step WITH the flag that performs it — an unflagged re-install of a thin child is maintained thin, so the bare instruction cannot materialise the full local copy it promises"
( cd "$KA" && grep -qF 'You are the **Builder**' ../../.harness/agents/builder.md ) \
  || fail "R3: the path the stub names does not resolve to the real body"
pass "R3 stub_contract"

grep -q 'This target holds the thin body layout' "$KA/manifest.txt" \
  || fail "R8: a thin child's manifest does not record the thin layout"
grep -q 'This target holds the full body layout' "$AU/f03/.harness/manifest.txt" \
  || fail "R8: the coordinator's manifest does not record the full layout"
is_stub "$AU/f03/.harness/agents/builder.md" \
  && fail "R8/R2: the COORDINATOR was thinned — it holds the authoritative body"
pass "R8 manifest_records_layout"

# ── R7: an umbrella upgrade leaves child stubs byte-identical ──────────────────────────
# Positive control in the SAME run: without it this passes on a re-run that did nothing.
cp "$KA/agents/builder.md" "$AU/f03-stub.ref"
cp "$KA/.harness-version" "$AU/f03-ver.ref"
# The bumped installer is a PRIVATE COPY of the source, never the shared checkout.
# `tools/run-tests.sh` runs suites concurrently (--jobs 8) and its own header warns that a
# suite writing to a shared path fails intermittently under it: other suites invoke
# harness-install.sh (stamping VERSION into their fixtures) and test_pr_loop.sh R54 asserts
# CHANGELOG carries a heading for exactly the current VERSION. Writing 99.99.99 into
# $SRC/VERSION would make BOTH of those flaky, for a window this test does not control.
# (Codex r1 P1 #3705599506.)
SRCCOPY="$AU/f03-src"
mkdir -p "$SRCCOPY"
# Copy the installer and every path it reads. `.git` and the round cache are excluded:
# they are large and irrelevant, and the installer never reads them.
for _sd in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
           harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
  [ -e "$SRC/$_sd" ] && cp -R "$SRC/$_sd" "$SRCCOPY/"
done
printf '99.99.99\n' > "$SRCCOPY/VERSION"
AU_OUT="$(CODEX_HOME="$AU/f03/.ch" HOME="$AU/f03/.home" sh "$SRCCOPY/harness-install.sh" \
  --umbrella "$AU/f03" --agents=claude 2>&1)" || true
# The point of the private copy: the shared checkout must be untouched, so a suite running
# concurrently can never observe 99.99.99. Guard it, or the isolation silently regresses.
grep -qx '99.99.99' "$SRC/VERSION" \
  && fail "R7: the synthetic bump leaked into the shared checkout's VERSION — concurrent suites will flake"
cmp -s "$AU/f03-stub.ref" "$KA/agents/builder.md" \
  || fail "R7: a VERSION bump rewrote a thin child's stub"
cmp -s "$AU/f03-ver.ref" "$KA/.harness-version" \
  && fail "R7 control: the version stamp did NOT change — the re-run did nothing, so the stub comparison proves nothing"
pass "R7 stubs_survive_version_bump (with a positive control on the standalone tier)"

# ── R2 (shape fidelity): nested dirs and dotfiles inside a prose tier are mirrored ─────
# The thin layout must produce the same SHAPE as `cp -R` does on the full path. An
# immediate-files-only loop silently drops any nested subtree a prose directory grows
# later — the child ends up missing a file the full install has, with no error anywhere.
# Fixtures go in a PRIVATE source copy so the shared checkout is never mutated.
# (Codex r2 P2 #3705758419.)
SC2="$AU/f03-shape-src"
mkdir -p "$SC2"
for _sd in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
           harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
  [ -e "$SRC/$_sd" ] && cp -R "$SRC/$_sd" "$SC2/"
done
mkdir -p "$SC2/docs/nested/deeper"
echo "nested body" > "$SC2/docs/nested/deep.md"
echo "deeper body" > "$SC2/docs/nested/deeper/x.md"
echo "hidden body" > "$SC2/agents/.hidden.md"
# `zzz.md` sorts AFTER the nested directory ON PURPOSE. POSIX sh has no locals, so a
# recursion that clobbers its parent's frame writes every sibling processed after a nested
# directory beneath it — `docs/zzz.md` became `docs/aaa/zzz.md` and vanished from its own
# path. A fixture whose only nested dir sorts last cannot see that. (Codex r4 P2 #3705960408.)
echo "sibling body" > "$SC2/docs/zzz.md"
# Dotfile NAME SHAPES are a matrix, not one case: `*` skips every dot name, `.[!.]*` skips
# every `..name`, and `.??*` skips every two-character dot name. Each pattern alone leaves a
# file that `cp -R` copies and the thin child drops. `..dd/` is a DIRECTORY on purpose — an
# unmatched dir is never recursed into, so its whole subtree vanishes, not just one entry.
# `.q` is the two-character case that fails the moment `.[!.]*` is "simplified" to `.??*`.
# (Codex r5 P2 #3706053982.)
echo "dotdot body" > "$SC2/docs/..draft.md"
mkdir -p "$SC2/docs/..dd"
echo "dotdot dir body" > "$SC2/docs/..dd/inner.md"
echo "short dot body" > "$SC2/docs/.q"
# SYMLINKS. `cp -R` preserves a link as a link, so the thin child must too. A walk that
# tests `[ -d ]` before `[ -L ]` dereferences instead and descends: `docs/self -> .`
# expanded into `docs/self/self/...` up to the OS resolution limit — 264 entries under the
# child's docs/ against 8 in a control — and the cascade still reported its ordinary
# status, so nothing surfaced the corruption. `dangling` is here because a broken link is
# the case where `[ -e ]` is false while `[ -L ]` is true. (Codex r6 P2 #3710311338.)
ln -s . "$SC2/docs/self"
ln -s nested "$SC2/docs/link-to-dir"
ln -s zzz.md "$SC2/docs/link-to-file"
ln -s no-such-target "$SC2/docs/dangling"
# READ-ONLY MODES. `cp -R` carries the source's modes across, so a 0555 directory holding a
# 0444 file arrives in the child unwritable and the thinning cannot overwrite it — the child
# kept `SECRET REAL BODY` while the cascade printed `install complete`. Note this is a
# regression the copy-then-thin inversion INTRODUCED: the earlier source-walk built the
# destination fresh and so never reproduced these modes. Verified by running this very
# fixture against both implementations. (Codex r7 P2 #3711176789.)
mkdir -p "$SC2/docs/rodir"
echo "SECRET REAL BODY" > "$SC2/docs/rodir/locked.md"
chmod 0444 "$SC2/docs/rodir/locked.md"
chmod 0555 "$SC2/docs/rodir"
mk_umb "$AU/f03c" kid-d
AU_OUT="$(CODEX_HOME="$AU/f03c/.ch" HOME="$AU/f03c/.home" sh "$SC2/harness-install.sh" \
  --umbrella "$AU/f03c" --agents=claude 2>&1)" || true
KD="$AU/f03c/kid-d/.harness"
# Precondition: this really is a thin child, or "the nested file is a stub" is vacuous.
is_stub "$KD/AGENTS.md" || fail "R2-shape setup: the child is not thin"
for _p in docs/nested/deep.md docs/nested/deeper/x.md agents/.hidden.md docs/zzz.md \
          docs/..draft.md docs/..dd/inner.md docs/.q docs/rodir/locked.md; do
  [ -f "$KD/$_p" ] || fail "R2-shape: $_p is missing from a thin child but present in a full install"
  is_stub "$KD/$_p" || fail "R2-shape: $_p was mirrored but is not a stub"
done
# ...and it must not have been written INSIDE the nested directory instead.
[ -e "$KD/docs/nested/zzz.md" ] \
  && fail "R2-shape: a sibling after a nested dir was written beneath it — recursion clobbered the parent frame"
grep -qF '../../.harness/docs/nested/deeper/x.md' "$KD/docs/nested/deeper/x.md" \
  || fail "R2-shape: a nested stub does not name its own resolved path"
# Every symlink survives AS A LINK, pointing where it pointed — never stubbed (the write
# would land on the target) and never descended into.
for _l in self:. link-to-dir:nested link-to-file:zzz.md dangling:no-such-target; do
  _ln="${_l%%:*}"; _lt="${_l#*:}"
  [ -L "$KD/docs/$_ln" ] \
    || fail "R2-shape: docs/$_ln is not a symlink in the thin child — cp -R keeps it one"
  [ "$(readlink "$KD/docs/$_ln")" = "$_lt" ] \
    || fail "R2-shape: docs/$_ln points at '$(readlink "$KD/docs/$_ln")', want '$_lt'"
done
# `is_stub docs/link-to-file` is deliberately NOT asserted either way: it reads THROUGH the
# link to `zzz.md`, which is itself correctly stubbed, so it is true for a reason that has
# nothing to do with the link. `dangling` is the clean probe instead — had the stub write
# followed it, its target would have been created.
[ -e "$KD/docs/no-such-target" ] \
  && fail "R2-shape: stubbing followed docs/dangling and created its target"
# The runaway CANNOT be probed by path existence. `[ -e docs/self/self ]` is true on a
# perfectly correct tree — and so is `docs/self/self/self/self` — because `-e` resolves the
# path THROUGH the preserved link. Verified against a directory holding exactly one link and
# one file. The honest probes are the two below, which use `find`: it does not follow
# symlinks, so it reports the tree as stored rather than as traversable.
_thin_n="$(find "$KD/docs" | wc -l | tr -d ' ')"
# The control: the SAME source, installed standalone, keeps those files as real bodies —
# which is what makes "missing from the thin child" a divergence rather than a source quirk.
mkdir -p "$AU/f03c-full"   # the installer requires an EXISTING target directory
CODEX_HOME="$AU/f03c/.ch2" HOME="$AU/f03c/.home2" sh "$SC2/harness-install.sh" \
  --agents=claude "$AU/f03c-full" >/dev/null 2>&1 || fail "R2-shape control: standalone install failed"
grep -qF 'deeper body' "$AU/f03c-full/.harness/docs/nested/deeper/x.md" \
  || fail "R2-shape control: the full install did not preserve the nested file either"
# Same control for each dot-name shape. Without this, "the thin child has docs/..draft.md"
# could be satisfied by a source that never had it — and the divergence it exists to catch
# is defined against what the FULL install produces, so the full side must be asserted too.
for _c in '..draft.md:dotdot body' '..dd/inner.md:dotdot dir body' '.q:short dot body'; do
  _cp="${_c%%:*}"; _cb="${_c#*:}"
  grep -qF "$_cb" "$AU/f03c-full/.harness/docs/$_cp" \
    || fail "R2-shape control: the full install did not preserve docs/$_cp — the thin-child assertion for it proves nothing"
done
# The read-only file's REAL CONTENT must appear nowhere in the thin child — the symptom of
# the silent-thinning bug was the body surviving, not the stub being absent. Stated over the
# whole tree rather than one path, since a partially-thinned child is the actual hazard.
grep -rqF 'SECRET REAL BODY' "$KD" \
  && fail "R2-shape: real body content survived into a thin child — thinning failed silently"
# ...and the full install MUST still contain it, or the grep above passes vacuously.
grep -qF 'SECRET REAL BODY' "$AU/f03c-full/.harness/docs/rodir/locked.md" \
  || fail "R2-shape control: the full install did not keep the read-only file's body — the absence assertion above proves nothing"
# Symlink control: the full path keeps these as links, which is what makes "the thin child
# keeps them as links" a fidelity claim rather than an arbitrary choice.
for _l in self:. link-to-dir:nested link-to-file:zzz.md dangling:no-such-target; do
  _ln="${_l%%:*}"; _lt="${_l#*:}"
  [ -L "$AU/f03c-full/.harness/docs/$_ln" ] \
    || fail "R2-shape control: the full install did not keep docs/$_ln a symlink — the thin-child link assertion proves nothing"
  [ "$(readlink "$AU/f03c-full/.harness/docs/$_ln")" = "$_lt" ] \
    || fail "R2-shape control: the full install's docs/$_ln points somewhere unexpected"
done
# THE WHOLE REQUIREMENT, stated once: thin and full must contain the SAME SET OF PATHS.
# Every individual assertion above is a sample of this; the set comparison is the property
# itself, and it catches shapes nobody thought to enumerate — which is exactly how this
# function accumulated four blocking findings. `find` does not follow symlinks, so a
# self-referencing link cannot loop here.
( cd "$KD" && find docs | sort ) > "$AU/f03c-thin.paths"
( cd "$AU/f03c-full/.harness" && find docs | sort ) > "$AU/f03c-full.paths"
diff "$AU/f03c-full.paths" "$AU/f03c-thin.paths" >/dev/null \
  || fail "R2-shape: thin and full installs disagree on docs/ paths:
$(diff "$AU/f03c-full.paths" "$AU/f03c-thin.paths" | head -20)"
# Precondition on that comparison: it is only meaningful if the fixture actually reached
# both installs. An empty-vs-empty diff would pass while proving nothing.
[ "$_thin_n" -ge 12 ] \
  || fail "R2-shape: only $_thin_n entries under the thin child's docs/ — the fixture did not land, so the path-set comparison is vacuous"
pass "R2 nested dirs, dot-name shapes and symlinks keep their shape in a thin child"

# ── R1/R2: a SYMLINKED child resolves its umbrella too ─────────────────────────────────
# The cascade deliberately accepts a symlinked child. `..` from such a child's .harness/ is
# resolved by the kernel against the LINK TARGET, so a hard-coded `../../` lands outside the
# umbrella: the child installed a full body AND persisted an unreachable umbrella.root.
# The value is derived from the physical path, with the absolute umbrella as the fallback.
# (Codex r3 P2 #3705849222.)
ELS="$AU/f03d-elsewhere"
mkdir -p "$ELS/realrepo" "$AU/f03d"
git -C "$ELS/realrepo" init -q .
git -C "$ELS/realrepo" config user.email "test@harness.local"
git -C "$ELS/realrepo" config user.name  "harness test"
echo seed > "$ELS/realrepo/README.md"
git -C "$ELS/realrepo" add -A
git -C "$ELS/realrepo" commit -q -m init
ln -s "$ELS/realrepo" "$AU/f03d/kid-link"
# A real sibling in the SAME umbrella, so the relative form is asserted in the same run —
# a fix that switched everything to absolute paths would pass the symlink case alone.
mk_umb "$AU/f03d" kid-real
cascade "$AU/f03d"
is_stub "$ELS/realrepo/.harness/AGENTS.md" \
  || fail "R2-symlink: a symlinked child got a full body — its umbrella.root did not resolve"
_symroot="$(sed -n 's/^  root: "\(.*\)"$/\1/p' "$ELS/realrepo/.harness/harness.config.yaml")"
[ -n "$_symroot" ] || fail "R1-symlink: no umbrella.root recorded for the symlinked child"
[ -f "$_symroot/.harness/.harness-version" ] \
  || fail "R1-symlink: the recorded umbrella.root ($_symroot) does not resolve to an installed body"
grep -q '^  root: "\.\./\.\./"' "$AU/f03d/kid-real/.harness/harness.config.yaml" \
  || fail "R1-symlink: an ORDINARY child stopped getting the relative form"
is_stub "$AU/f03d/kid-real/.harness/AGENTS.md" \
  || fail "R2-symlink: the ordinary sibling stopped being thinned"
pass "R1/R2 a symlinked child resolves its umbrella; an ordinary sibling keeps the relative form"

# ── R9: an existing full-copy child is left alone ──────────────────────────────────────
# Converting one is destructive, needs a pristine check, and is E24-F04 — never a side
# effect of a routine cascade. Asserted on BYTES: a swap to stubs leaves every path present.
mk_umb "$AU/f03b" kid-c
KC="$AU/f03b/kid-c"
CODEX_HOME="$AU/f03b/.ch" HOME="$AU/f03b/.home" sh "$SRC/harness-install.sh" --agents=claude "$KC" >/dev/null 2>&1 \
  || fail "R9 setup: standalone install into kid-c failed"
is_stub "$KC/.harness/agents/builder.md" && fail "R9 setup: the standalone install already wrote a stub"
cp "$KC/.harness/agents/builder.md" "$AU/f03b-full.ref"
cascade "$AU/f03b"
cmp -s "$AU/f03b-full.ref" "$KC/.harness/agents/builder.md" \
  || fail "R9: the cascade converted an existing full-copy child's body to stubs"
grep -q 'This target holds the full body layout' "$KC/.harness/manifest.txt" \
  || fail "R9: an unconverted child's manifest does not report the full layout"
printf '%s' "$AU_OUT" | grep -qi 'already holds a full body' \
  || fail "R9: the cascade did not report that it left an existing full body alone"
pass "R9 existing_full_copy_child_untouched"

# A final negative probe is not a suite failure.
exit 0
