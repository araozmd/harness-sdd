#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

# ── R9/R10/R11: --standalone, the documented way back ──────────────────────────────────
# standalone_materialises_body / standalone_clears_umbrella_root / standalone_is_idempotent
F04F="$AU/f04f"
mk_umb "$F04F" kid
cascade "$F04F"
SK="$F04F/kid/.harness"
f04_all_stubs_in_tier "$SK" "R9 fixture (a fresh cascade child must be thin)"
# WHAT THE STUB'S OWN RECOVERY TEXT PRESCRIBES, run as written. That text is stamped into
# EVERY stub in every child, so it is the instruction most operators will actually follow, and
# an unflagged re-install of a thin child lands on the MAINTENANCE arm and leaves it thin — the
# promised full local copy never appears. The flag is the reverse operation; the text has to
# name it. (Codex #3802057876.)
F04F_PLAIN="$(CODEX_HOME="$F04F/.ch" HOME="$F04F/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04F/kid" 2>&1)" && F04F_RC=0 || F04F_RC=$?
[ "$F04F_RC" = "0" ] || fail "R9: an unflagged re-install of a thin child exited $F04F_RC: $F04F_PLAIN"
f04_all_stubs_in_tier "$SK" "R9 (an UNFLAGGED re-install must leave a thin child THIN — if it materialised the body on its own, the stub's text would need no flag and the assertion below would be measuring nothing)"
grep -qiF 'with `--standalone`' "$SK/agents/builder.md" \
  || fail "R9/R3: the stub's recovery text does not name --standalone, and the unflagged run it prescribes has just left this target thin: $(grep -i 'installer against' "$SK/agents/builder.md")"
# R10's CONTROL: another key in the same section, plus a hand-editable value elsewhere in
# the file. A writer that "cleared" the key by truncating the umbrella: section, or by
# rewriting the config from the shipped template, would otherwise pass.
sed -e 's|^  manifest: .*|  manifest: "../umbrella.manifest.yaml"|' \
    -e 's|^  test_command: .*|  test_command: "echo f04-hand-edited"|' \
    "$SK/harness.config.yaml" > "$SK/hc.t" && mv "$SK/hc.t" "$SK/harness.config.yaml"
grep -q '^  manifest: "\.\./umbrella\.manifest\.yaml"' "$SK/harness.config.yaml" \
  || fail "R10 setup: the control key was not seeded"

F04F_OUT="$(CODEX_HOME="$F04F/.ch" HOME="$F04F/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --standalone "$F04F/kid" 2>&1)" && F04F_RC=0 || F04F_RC=$?
[ "$F04F_RC" = "0" ] || fail "R9: --standalone exited $F04F_RC: $F04F_OUT"
f04_no_stub_in_tier "$SK" "R9 (--standalone must replace every stub with the real body)"
grep -qF 'You are the **Builder**' "$SK/agents/builder.md" \
  || fail "R9: agents/builder.md was not materialised from the installer's own source"
grep -qF 'harness-sdd' "$SK/AGENTS.md" \
  || fail "R9: the regular-file tier entry AGENTS.md was not materialised"
grep -q 'This target holds the full body layout' "$SK/manifest.txt" \
  || fail "R9: a re-materialised target's manifest does not report the full layout"
pass "R9 standalone_materialises_body — every stub is replaced by the real body file"

grep -q '^  root: ""$' "$SK/harness.config.yaml" \
  || fail "R10: --standalone did not clear umbrella.root: $(grep '^  root:' "$SK/harness.config.yaml")"
grep -q '^  manifest: "\.\./umbrella\.manifest\.yaml"' "$SK/harness.config.yaml" \
  || fail "R10: clearing umbrella.root also rewrote umbrella.manifest — the writer is not section-scoped"
grep -q '^  test_command: "echo f04-hand-edited"' "$SK/harness.config.yaml" \
  || fail "R10: clearing umbrella.root discarded a hand-edited value elsewhere in the config"
pass "R10 standalone_clears_umbrella_root — the key is cleared, its neighbours are untouched"

# R11 is NOT "the bytes did not change": --standalone takes the ordinary copy branch, so a
# stale or edited target legitimately comes out re-installed from source. The claim is the
# LAYOUT, the cleared key and exit 0.
F04G_OUT="$(CODEX_HOME="$F04F/.ch" HOME="$F04F/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --standalone "$F04F/kid" 2>&1)" && F04G_RC=0 || F04G_RC=$?
[ "$F04G_RC" = "0" ] || fail "R11: --standalone on an already-full-copy target exited $F04G_RC: $F04G_OUT"
f04_no_stub_in_tier "$SK" "R11 (--standalone on a full-copy target keeps it full-copy)"
grep -q '^  root: ""$' "$SK/harness.config.yaml" \
  || fail "R11: umbrella.root is no longer cleared after a second --standalone run"
grep -q 'This target holds the full body layout' "$SK/manifest.txt" \
  || fail "R11: the target left the full-copy layout on a repeat --standalone run"
pass "R11 standalone_is_idempotent — a full-copy target stays full-copy, key stays cleared, exit 0"

# ── R7: the glossary is never stubbed, in any body-copy arm ─────────────────────────────
# glossary_never_stubbed_in_any_layout (E30-F01)
#
# specs/glossary.md left HARNESS_BODY_PROSE entirely (D1): it is project-owned content,
# like specs/product.md, in every layout — full copy, thin child, or standalone. This is
# the umbrella-side half of R7; the single-repo/coordinator arm (arm 4) is covered by
# tests/test_install.sh::test_glossary_edit_preserved_on_upgrade — a single `file::name`
# exercising all four arms would overstate its own coverage (see .tests.md).
#
# arm 2 — THIN MAINTENANCE: a fresh cascade child is thin by default; edit its glossary
# and run the ORDINARY (unflagged) maintenance install again.
F04GLA="$AU/f04gl-a"
mk_umb "$F04GLA" thin1
cascade "$F04GLA"
KGLA="$F04GLA/thin1/.harness"
is_stub "$KGLA/agents/builder.md" \
  || fail "R7 fixture (arm 2): the fresh cascade child is not thin — arm 2 is not reached"
printf 'PROJECT TERM — arm2 marker (E30-F01)\n' >> "$KGLA/specs/glossary.md"
GLA_REF="$(cat "$KGLA/specs/glossary.md")"
CODEX_HOME="$F04GLA/.ch" HOME="$F04GLA/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04GLA/thin1" >/dev/null 2>&1 \
  || fail "R7 (arm 2 thin maintenance): the ordinary maintenance run on a thin child failed"
[ "$(cat "$KGLA/specs/glossary.md")" = "$GLA_REF" ] \
  || fail "R7 (arm 2 thin maintenance): the ordinary maintenance run overwrote the child's edited glossary"
is_stub "$KGLA/specs/glossary.md" \
  && fail "R7 (arm 2 thin maintenance): the glossary was stubbed"

# arm 3 — FULL-COPY CHILD of a reachable umbrella, unflagged run.
F04GLC="$AU/f04gl-c"
f04_fullchild "$F04GLC" full1
KGLC="$F04GLC/full1/.harness"
printf 'PROJECT TERM — arm3 marker (E30-F01)\n' >> "$KGLC/specs/glossary.md"
GLC_REF="$(cat "$KGLC/specs/glossary.md")"
CODEX_HOME="$F04GLC/.ch" HOME="$F04GLC/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04GLC/full1" >/dev/null 2>&1 \
  || fail "R7 (arm 3 full-copy child): the ordinary maintenance run on a full-copy child failed"
[ "$(cat "$KGLC/specs/glossary.md")" = "$GLC_REF" ] \
  || fail "R7 (arm 3 full-copy child): the ordinary maintenance run overwrote the child's edited glossary"
is_stub "$KGLC/specs/glossary.md" \
  && fail "R7 (arm 3 full-copy child): the glossary was stubbed"

# arm 1 — `--standalone`: detach a thin child; the glossary must survive while
# agents/builder.md is re-materialised as real prose (the control that proves the run
# really took the standalone arm, matching R9 standalone_materialises_body above).
F04GLB="$AU/f04gl-b"
mk_umb "$F04GLB" standalone1
cascade "$F04GLB"
KGLB="$F04GLB/standalone1/.harness"
is_stub "$KGLB/agents/builder.md" \
  || fail "R7 fixture (arm 1): the fresh cascade child is not thin — --standalone has nothing to detach"
printf 'PROJECT TERM — arm1 marker (E30-F01)\n' >> "$KGLB/specs/glossary.md"
GLB_REF="$(cat "$KGLB/specs/glossary.md")"
CODEX_HOME="$F04GLB/.ch" HOME="$F04GLB/.home" \
  sh "$SRC/harness-install.sh" --agents=claude --standalone "$F04GLB/standalone1" >/dev/null 2>&1 \
  || fail "R7 (arm 1 --standalone): the detach run failed"
[ "$(cat "$KGLB/specs/glossary.md")" = "$GLB_REF" ] \
  || fail "R7 (arm 1 --standalone): --standalone overwrote the child's edited glossary"
is_stub "$KGLB/specs/glossary.md" \
  && fail "R7 (arm 1 --standalone): the glossary was stubbed"
grep -qF 'You are the **Builder**' "$KGLB/agents/builder.md" \
  || fail "R7 (arm 1 --standalone) control: agents/builder.md was not re-materialised as real prose — the run did not take the standalone arm"

# SWEEP, not sample: specs/glossary.md itself, in each of the three children, is never a
# stub. (specs/_templates/ IS legitimately stubbed in the still-thin children — arm 2's
# child never converted — so the sweep is scoped to the one path this feature governs,
# not the whole specs/ tree.)
for _glf in "$KGLA" "$KGLC" "$KGLB"; do
  is_stub "$_glf/specs/glossary.md" && fail "R7 sweep: $_glf/specs/glossary.md became a stub"
done
pass "R7 glossary_never_stubbed_in_any_layout — arms 1-3 leave an edited glossary real and unchanged"

# ── R8: a thin child owns a REAL glossary; a legacy stub is re-materialised ─────────────
# glossary_stub_rematerialised_in_thin_child (E30-F01, decision D1)
F04GLD="$AU/f04gl-d"
mk_umb "$F04GLD" freshkid
cascade "$F04GLD"
KGLD="$F04GLD/freshkid/.harness"
is_stub "$KGLD/agents/builder.md" \
  || fail "R8 control: the fresh cascade child is not thin — the case is vacuous"
is_stub "$KGLD/specs/glossary.md" \
  && fail "R8: a FRESH thin child's glossary is a stub — the glossary must never be stubbed, even on first cascade"
cmp -s "$KGLD/specs/glossary.md" "$SRC/specs/glossary.md" \
  || fail "R8: a fresh thin child's glossary is not byte-identical to the shipped example"
pass "R8 glossary_stub_rematerialised_in_thin_child (fresh child) — a fresh thin child's glossary is real, not stubbed"

# Legacy migration: hand-write a stub at that path, exactly as a pre-E30-F01 installer
# would have left one, and re-run.
printf '%s\n' "$SENTINEL" > "$KGLD/specs/glossary.md"
printf 'this repo used to route glossary lookups through the umbrella\n' >> "$KGLD/specs/glossary.md"
F04GLD_OUT="$(CODEX_HOME="$F04GLD/.ch" HOME="$F04GLD/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04GLD/freshkid" 2>&1)" && F04GLD_RC=0 || F04GLD_RC=$?
[ "$F04GLD_RC" = "0" ] || fail "R8 (legacy migration): the maintenance run exited $F04GLD_RC: $F04GLD_OUT"
is_stub "$KGLD/specs/glossary.md" \
  && fail "R8 (legacy migration): the pre-existing umbrella-stub sentinel survived — the glossary was not re-materialised"
cmp -s "$KGLD/specs/glossary.md" "$SRC/specs/glossary.md" \
  || fail "R8 (legacy migration): the re-materialised glossary is not byte-identical to the shipped example"
printf '%s\n' 2>/dev/null "$F04GLD_OUT" | grep -qF 'specs/glossary.md re-materialised' \
  || fail "R8 (legacy migration): the run did not report the re-materialised verdict: $F04GLD_OUT"
pass "R8 glossary_stub_rematerialised_in_thin_child (legacy stub) — a pre-existing umbrella-stub sentinel is replaced by the shipped example"

# Negative control: ordinary project prose at that path (first line is NOT the sentinel)
# is preserved exactly — the sentinel, never "looks short", is the ownership signal. The
# sentinel text also appears LATER in the body (documenting the convention itself), not
# just absent — this is what distinguishes "first line IS the sentinel" from "the FILE
# CONTAINS the sentinel somewhere": a `grep` over the whole file rather than `head -n 1`
# would misread this fixture as a stub and re-materialise it, dropping the project's prose.
printf 'Domain glossary\n\nThis project defines its own terms here. For the record, this\nrepo never uses the harness stub sentinel <!-- harness:umbrella-stub --> as real content.\n' > "$KGLD/specs/glossary.md"
GLD_PROSE_REF="$(cat "$KGLD/specs/glossary.md")"
CODEX_HOME="$F04GLD/.ch" HOME="$F04GLD/.home" \
  sh "$SRC/harness-install.sh" --agents=claude "$F04GLD/freshkid" >/dev/null 2>&1 \
  || fail "R8 (negative control): the maintenance run failed"
[ "$(cat "$KGLD/specs/glossary.md")" = "$GLD_PROSE_REF" ] \
  || fail "R8 (negative control): ordinary project prose (sentinel text appears mid-file, not on line 1) at specs/glossary.md was NOT preserved — the ownership signal is 'first line IS the sentinel', not 'the file contains it somewhere'"
pass "R8 glossary_stub_rematerialised_in_thin_child (negative control) — ordinary project prose is preserved, never mistaken for a stub even when it quotes the sentinel text"

# ── R9: an edited glossary is not a --thin blocker, and survives the conversion ─────────
# glossary_edit_does_not_block_thin_conversion (E30-F01)
#
# The suite's existing blocked-child cases (thin_all_or_nothing_on_edit,
# thin_blocker_paths_are_normalised) are the positive control that the blocker machinery
# still works — referenced, not re-seeded, here.
F04GLE="$AU/f04gl-e"
f04_fullchild "$F04GLE" onlyglossary
KGLE="$F04GLE/onlyglossary/.harness"
printf 'PROJECT TERM — the only divergence in this child (E30-F01 R9)\n' >> "$KGLE/specs/glossary.md"
GLE_REF="$(cat "$KGLE/specs/glossary.md")"
cascade "$F04GLE" --thin
F04GLE_SEG="$(f04_seg "$AU_OUT" "$F04GLE/onlyglossary")"
printf '%s\n' 2>/dev/null "$F04GLE_SEG" | grep -qF 'differs: specs/glossary.md' \
  && fail "R9: an edited glossary was named as a --thin blocker — it left the prose tier and must never block a conversion: $F04GLE_SEG"
printf '%s\n' 2>/dev/null "$F04GLE_SEG" | grep -qi 'CONVERTED' \
  || fail "R9: the child whose only divergence is its glossary did not report a conversion: $F04GLE_SEG"
f04_all_stubs_in_tier "$KGLE" "R9 (the prose tier must convert to stubs — the glossary edit must not block it)"
is_stub "$KGLE/specs/glossary.md" \
  && fail "R9: the glossary itself was stubbed by the conversion — it is project-owned, never tier content"
[ "$(cat "$KGLE/specs/glossary.md")" = "$GLE_REF" ] \
  || fail "R9: the --thin conversion changed the child's edited glossary bytes"
pass "R9 glossary_edit_does_not_block_thin_conversion — an edited glossary is not named, the child converts, and the edit survives"

# ── docs contract: docs/UMBRELLA.md documents the migration and the reverse ─────────────
# f04_docs_contract. FENCE-AWARE extraction: the bare house awk idiom stops at the first
# `#` inside a fenced block, and T12 adds new fences to this very file — a `#` comment in
# one would truncate the span and make every assertion below pass over text it never read.
F04DOC="$SRC/docs/UMBRELLA.md"
F04_FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"
f04_span() {
  awk -v h="$2" "$F04_FENCE_AWK"'
    fence_delim($0) { if (k) print; next }
    !fence && /^## / { k = (index($0, h) > 0); next }
    k
  ' "$1"
}

F04MIG="$(f04_span "$F04DOC" 'Migrating an existing child')"
[ -n "$F04MIG" ] || fail "f04_docs_contract: docs/UMBRELLA.md has no 'Migrating an existing child' section"
# The migration COMMAND, and the absence assertion that matters: EVERY cascade invocation
# in that section carries --thin. An unflagged cascade presented as step one is the wrong
# doc a reviewer is most likely to write, and it destroys the differences it reports.
F04N_ALL="$(printf '%s\n' 2>/dev/null "$F04MIG" | grep -o 'harness-install\.sh --umbrella' | wc -l | tr -d ' ')"
F04N_THIN="$(printf '%s\n' 2>/dev/null "$F04MIG" | grep -o 'harness-install\.sh --umbrella [^ ]* --thin' | wc -l | tr -d ' ')"
[ "$F04N_ALL" -ge 1 ] \
  || fail "f04_docs_contract: the migration section never names 'harness-install.sh --umbrella … --thin'"
[ "$F04N_ALL" = "$F04N_THIN" ] \
  || fail "f04_docs_contract: $F04N_ALL cascade invocation(s) in the migration section, only $F04N_THIN carry --thin — an unflagged cascade is being presented as a migration step, and that branch overwrites the prose tier from source"
printf '%s\n' 2>/dev/null "$F04MIG" | grep -qi 'until it converges' \
  || fail "f04_docs_contract: the migration procedure does not say to re-run until it converges"
printf '%s\n' 2>/dev/null "$F04MIG" | grep -qi 'whole or not at all' \
  || fail "f04_docs_contract: the all-or-nothing rule is not stated in the migration section"
printf '%s\n' 2>/dev/null "$F04MIG" | grep -qi 'does not resolve to an installed harness body' \
  || fail "f04_docs_contract: the unreachable-umbrella behavior is not documented in the migration section"

F04STA="$(f04_span "$F04DOC" 'the way back')"
[ -n "$F04STA" ] || fail "f04_docs_contract: docs/UMBRELLA.md has no '--standalone — the way back' section"
printf '%s\n' 2>/dev/null "$F04STA" | grep -q 'harness-install\.sh --standalone' \
  || fail "f04_docs_contract: the --standalone section never shows the command"
printf '%s\n' 2>/dev/null "$F04STA" | grep -qi 'cleared' \
  || fail "f04_docs_contract: the --standalone section does not say umbrella.root is cleared"
printf '%s\n' 2>/dev/null "$F04STA" | grep -qi 'not a permanent opt-out' \
  || fail "f04_docs_contract: the --standalone section oversells the flag — clearing the key is not a permanent opt-out"
pass "f04_docs_contract — docs/UMBRELLA.md documents the migration command, the all-or-nothing rule and the reverse"

# A final negative probe is not a suite failure.
exit 0
