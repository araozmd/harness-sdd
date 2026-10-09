# ══ E24-F04 — migrate existing children to the thin layout (+ --standalone) ════════════
# The DESTRUCTIVE half of ADR-0004: replacing a prose tier with pointer stubs in a repo
# that already exists. Every case below builds a REAL full-copy child of a REAL reachable
# umbrella and reads what the installer did to it on disk.
#
# The whole prose tier, swept — never sampled. R2's claim is about the paths the operator
# did NOT edit, so "no path in the tier became a stub" has to be a sweep of the tree.
#
# THIS IS A DERIVED EQUALITY, NOT A HAND-EDITED CONSTANT (E30-F01). E24-F04's tests
# contract recorded "the prose sweep iterates a hardcoded tier list instead of
# $HARNESS_BODY_PROSE" as a killed mutant, and the kill worked only because
# specs/glossary.md was the tier's differentiating entry. Now that the glossary has left
# the tier (it is project-owned in every layout — see glossary_never_stubbed_in_any_layout
# below), a hand-edited F04_TIER that happens to match today's HARNESS_BODY_PROSE would let
# that mutant survive silently. Assert equality against the shipped value instead of merely
# copying it by hand.
F04_TIER='AGENTS.md agents docs specs/_templates'
F04_TIER_SRC="$(sed -n "s/^HARNESS_BODY_PROSE='\(.*\)'\$/\1/p" "$SRC/harness-install.sh")"
[ -n "$F04_TIER_SRC" ] \
  || fail "F04_TIER control: could not extract HARNESS_BODY_PROSE from \$SRC/harness-install.sh — the anchor pattern is stale"
[ "$F04_TIER_SRC" = "$F04_TIER" ] \
  || fail "F04_TIER control: F04_TIER ('$F04_TIER') has drifted from the shipped HARNESS_BODY_PROSE ('$F04_TIER_SRC') — a hardcoded tier list here would let the prose sweep silently stop iterating \$HARNESS_BODY_PROSE (E24-F04's recorded mutation kill)"

# f04_no_stub_in_tier <harness-dir> <context> — fail if ANY file under the prose tier is a
# stub. The predicate is "line 1 IS the sentinel" (is_stub), matching E24-F03's control.
f04_no_stub_in_tier() {
  _fn_h="$1"; _fn_ctx="$2"; _fn_n=0
  for _fn_rel in $F04_TIER; do
    [ -e "$_fn_h/$_fn_rel" ] || fail "$_fn_ctx: prose-tier path $_fn_rel is missing entirely"
    for _fn_f in $(find "$_fn_h/$_fn_rel" -type f); do
      is_stub "$_fn_f" && { echo "   unexpected stub: $_fn_f" >&2; _fn_n=$((_fn_n + 1)); }
    done
  done
  [ "$_fn_n" = "0" ] || fail "$_fn_ctx: $_fn_n prose-tier path(s) were converted to stubs"
}

# f04_all_stubs_in_tier <harness-dir> <context> — the converse sweep.
f04_all_stubs_in_tier() {
  _fa_h="$1"; _fa_ctx="$2"; _fa_n=0
  for _fa_rel in $F04_TIER; do
    [ -e "$_fa_h/$_fa_rel" ] || fail "$_fa_ctx: prose-tier path $_fa_rel is missing entirely"
    for _fa_f in $(find "$_fa_h/$_fa_rel" -type f); do
      is_stub "$_fa_f" || { echo "   not a stub: $_fa_f" >&2; _fa_n=$((_fa_n + 1)); }
    done
  done
  [ "$_fa_n" = "0" ] || fail "$_fa_ctx: $_fa_n prose-tier path(s) are still full body files"
}

# modes_bind_this_uid — true when THIS user is actually constrained by directory mode bits.
#
# A BEHAVIOURAL PROBE, DELIBERATELY NOT `id -u`. Some fixtures below need a real filesystem
# REFUSAL as their trigger, and root never gets one: `0555` does not stop it unlinking or
# moving anything, so the run those fixtures require to FAIL succeeds instead and the suite
# fails as root. That is not a cosmetic problem — AGENTS.md rule 1 makes this suite the gate
# for all agent work, so a suite that cannot pass as root breaks the gate in every root
# container and many CI images. (Codex #3805383759.)
#
# Asking the FILESYSTEM beats asking for the uid on two counts: it is an INDEPENDENT oracle
# rather than a second reading of the same number, and it also covers the non-root user who
# is nonetheless unconstrained — a mount that ignores modes, an ACL that grants override.
# The probe reproduces the exact shape the fixtures rely on: a `0555` directory with a file
# inside it, which `rm -rf` must not be able to empty.
modes_bind_this_uid() {
  _mbu="$AU/.mode-probe.$$"
  chmod -R u+w "$_mbu" 2>/dev/null || :
  rm -rf "$_mbu" 2>/dev/null || :
  mkdir -p "$_mbu/ro" || return 1
  : > "$_mbu/ro/f" || return 1
  chmod 0555 "$_mbu/ro" || return 1
  if rm -rf "$_mbu" 2>/dev/null; then
    return 1
  fi
  chmod -R u+w "$_mbu" 2>/dev/null || :
  rm -rf "$_mbu" 2>/dev/null || :
  return 0
}

# f04_phys <dir> — the PHYSICAL path of <dir>. The cascade resolves the umbrella with
# `pwd -P` before installing, so every path it prints is physical while `mktemp -d` hands
# this suite the symlinked form (/var/... vs /private/var/... on macOS). Matching the
# logical path against the installer's output silently matches nothing.
f04_phys() { ( CDPATH= cd -- "$1" && pwd -P ); }

# f04_seg <output> <target-path> — the slice of a cascade's output belonging to ONE target,
# from that target's `harness install … → <path>` banner up to the next banner.
#
# WITHOUT THIS, a per-child assertion in a multi-child cascade is satisfied by ANY child's
# line: "the preview line is present" would pass while it was printed for the wrong repo.
# The leading space in the match is what keeps `…/kid` from matching `…/freshkid`.
f04_seg() {
  _fs_t="$(f04_phys "$2")"
  printf '%s\n' 2>/dev/null "$1" | awk -v t=" $_fs_t" '
    index($0, "harness install v") > 0 { k = (index($0, t) > 0); next }
    k
  '
}

# f04_fullchild <umbrella-dir> <child> — a FULL-COPY child of a REACHABLE umbrella, built
# the way the product builds one:
#   1. SINGLE-TARGET FIRST — no umbrella.root is ever written, so the child gets the
#      complete local body.
#   2. THEN the cascade — which records umbrella.root and, per E24-F03 R9, leaves the full
#      body alone.
#
# DO NOT INVERT THOSE TWO STEPS. Cascading first and re-installing single-target does NOT
# produce a full-copy child: umbrella_body_dir prefers HARNESS_UMBRELLA_ROOT but falls back
# to the CHILD'S OWN config, which §2a has already persisted — so the single-target run
# resolves the umbrella and re-stubs. And "fixing" that by hand-editing the child's config
# replaces the product's own state machine with a fixture.
f04_fullchild() {
  _fc_u="$1"; _fc_c="$2"
  mk_umb "$_fc_u" "$_fc_c"
  CODEX_HOME="$_fc_u/.ch" HOME="$_fc_u/.home" \
    sh "$SRC/harness-install.sh" --agents=claude "$_fc_u/$_fc_c" >/dev/null 2>&1 \
    || fail "F04 fixture: single-target install into $_fc_u/$_fc_c failed"
  cascade "$_fc_u"
  # PRECONDITION, re-asserted on every fixture: a conversion test whose fixture was never
  # full-copy proves nothing at all.
  f04_no_stub_in_tier "$_fc_u/$_fc_c/.harness" "F04 fixture ($_fc_c)"
  grep -qF 'You are the **Builder**' "$_fc_u/$_fc_c/.harness/agents/builder.md" \
    || fail "F04 fixture: $_fc_c/.harness/agents/builder.md is not the real body"
  grep -q '^  root: "\.\./\.\./"' "$_fc_u/$_fc_c/.harness/harness.config.yaml" \
    || fail "F04 fixture: umbrella.root was not recorded on $_fc_c"
  [ -f "$_fc_u/.harness/.harness-version" ] \
    || fail "F04 fixture: the umbrella body under $_fc_u is not installed"
}
