#!/bin/sh
# test_adr_citation.sh — verification for E99-F02 (ADR-citation id validation:
# Reviewer soft-flags a cited-but-nonexistent ADR id; init.sh gains a warn-only
# sweep that resolves each `ADR-NNNN` cited in a spec's `## Architecture alignment`
# section against specs/adr/NNNN-*.md).
#
# House way (cf. test_architect_adr.sh, test_drift_check.sh): required-phrase greps
# over the portable reviewer contract, plus SANDBOXED init.sh fixture runs (the
# minimal-layout pattern from test_umbrella.sh) proving the sweep end to end:
# nonexistent citation ⇒ warning + exit 0; valid citation ⇒ silent; specs/adr/
# absent ⇒ no-op. Zero deps: POSIX sh + grep + awk.
#
# Suite-wide constraints (permanent-suite anti-pattern): never assert the exact
# VERSION literal, never git-diff a harness body file against main, never mutate
# live specs or state/tasks.json (all fixtures live in a temp sandbox).

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

REV="agents/reviewer.md"

T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-adrcite)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── R1: Reviewer requires cited ids to RESOLVE to specs/adr/NNNN-*.md ─────────────
# R1_reviewer_resolution_rule
[ -f "$REV" ]                                     || fail "R1: $REV missing"
grep -qF 'specs/adr/NNNN-*.md' "$REV"             || fail "R1: reviewer does not name the specs/adr/NNNN-*.md resolution target"
# Two-token co-occurrence over folded newlines (E99-F75): a bare single-word grep
# ('resolve') passes on any stale revision of the file; the pair pins the actual rule.
tr '\n' ' ' < "$REV" | grep -qiE 'cited id[^.]{0,40}resolve to an existing' \
                                                  || fail "R1: reviewer does not state cited ids must resolve to an existing ADR file"
pass "R1 reviewer_resolution_rule"

# ── R2: cited-but-nonexistent id is a SOFT FLAG (same verdict rule), not a reject ─
# R2_reviewer_soft_flag
grep -qi 'cited-but-nonexistent' "$REV"           || fail "R2: reviewer does not name the cited-but-nonexistent case"
# E99-F75: 'flag' and 'renamed\|removed' alone are satisfied by unrelated prose; anchor
# the soft-flag verb to its object and the rationale to its qualifier.
tr '\n' ' ' < "$REV" | grep -qiE 'flagged[^.]{0,40}investigate' \
                                                  || fail "R2: reviewer does not soft-flag it for investigation"
grep -qi 'not a hard reject\|not.*hard reject' "$REV" || fail "R2: reviewer does not say 'not a hard reject'"
tr '\n' ' ' < "$REV" | grep -qiE 'legitimately renamed/removed' \
                                                  || fail "R2: reviewer does not give the renamed/removed-legitimately rationale"
pass "R2 reviewer_soft_flag"

# ── Sandbox builder: the minimal layout init.sh's structural checks require ───────
# (test_umbrella.sh pattern). The config deliberately OMITS `tasks: local` so the
# TaskStore block is skipped — this suite exercises the ADR sweep, not the store.
mk_sandbox() {
  H="$T/$1"
  mkdir -p "$H/agents" "$H/specs/epics/E01-demo/F01-thing" "$H/progress"
  : > "$H/AGENTS.md"
  printf '# fixture config (no local TaskStore, no umbrella manifest)\n' > "$H/harness.config.yaml"
  for r in orchestrator architect builder reviewer scout; do : > "$H/agents/$r.md"; done
  cp "$ROOT/init.sh" "$H/init.sh"; chmod +x "$H/init.sh"
}

# ── R3: nonexistent citation ⇒ init.sh WARNS on exactly that id and still exits 0 ─
# R3_sweep_warns_exit0  (also proves section scoping: ids OUTSIDE the section are
# ignored, per the brief's open question)
mk_sandbox miss
mkdir -p "$T/miss/specs/adr"
cat > "$T/miss/specs/adr/0001-event-store.md" <<'MD'
# ADR-0001 — Event-sourced store
MD
cat > "$T/miss/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec
Incidental mention outside the section: ADR-9999 must NOT be scanned.

## Architecture alignment
- ADR-0001 — Event-sourced store: honored by appending events.
- ADR-0042 — cited-but-nonexistent id (the typo this sweep catches).

## Requirements
More prose; ADR-8888 down here must not count either.
MD
OUT="$(cd "$T/miss" && ./init.sh 2>&1)" || fail "R3: init.sh exited non-zero on a nonexistent citation (must be warn-only)"
echo "$OUT" | grep -q 'ADR citation:'             || fail "R3: init.sh emitted no ADR-citation warning"
echo "$OUT" | grep -q 'ADR-0042'                  || fail "R3: warning does not name the unresolved id ADR-0042"
echo "$OUT" | grep -q 'ADR-9999' && fail "R3: sweep scanned an ADR id OUTSIDE the Architecture alignment section (ADR-9999)"
echo "$OUT" | grep -q 'ADR-8888' && fail "R3: sweep scanned an ADR id AFTER the section ended (ADR-8888)"
# NOTE: the `NNNN-*.md exists` substring below is LOAD-BEARING — it is how this
# negative assertion distinguishes "warned about 0001" from any other mention of the
# id. Every miss message in init.sh section 2c must keep it or this goes vacuous.
echo "$OUT" | grep -q '0001-\*\.md'.*'exists' && fail "R3: sweep wrongly warned on the RESOLVING id ADR-0001"
echo "$OUT" | grep -q 'environment ready'         || fail "R3: init.sh did not reach the final ready gate"
pass "R3 sweep_warns_exit0"

# ── R4: valid citation ⇒ silent (no warning), exit 0 ──────────────────────────────
# R4_sweep_silent_when_valid
mk_sandbox valid
mkdir -p "$T/valid/specs/adr"
cat > "$T/valid/specs/adr/0001-event-store.md" <<'MD'
# ADR-0001 — Event-sourced store
MD
cat > "$T/valid/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec

## Architecture alignment
- ADR-0001 — Event-sourced store: honored by appending events.
MD
OUT="$(cd "$T/valid" && ./init.sh 2>&1)" || fail "R4: init.sh exited non-zero on a valid citation"
echo "$OUT" | grep -q 'ADR citation:' && fail "R4: init.sh warned on a citation that resolves"
echo "$OUT" | grep -q 'ADR citations resolve'     || fail "R4: init.sh did not confirm the sweep ran clean"
pass "R4 sweep_silent_when_valid"

# ── R5: specs/adr/ absent ⇒ complete no-op (graceful degradation), exit 0 ─────────
# R5_noop_without_adr_dir
mk_sandbox noadr
cat > "$T/noadr/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec

## Architecture alignment
- ADR-0042 — cites an id, but this repo records no ADRs at all.
MD
OUT="$(cd "$T/noadr" && ./init.sh 2>&1)" || fail "R5: init.sh exited non-zero with specs/adr/ absent"
echo "$OUT" | grep -qi 'ADR' && fail "R5: sweep emitted ADR output despite specs/adr/ being absent (must be a no-op)"
pass "R5 noop_without_adr_dir"

# ── R7: a citation resolving in a SECOND ADR namespace (specs/<product>/adr/) is ──
#       NOT a miss; only the genuinely unresolvable id warns (E99-F50).
# R7_multi_namespace_resolution
mk_sandbox multins
mkdir -p "$T/multins/specs/adr" "$T/multins/specs/bookings/adr"
cat > "$T/multins/specs/adr/0001-platform-decision.md" <<'MD'
# ADR-0001 — platform-space decision
MD
cat > "$T/multins/specs/bookings/adr/0026-product-decision.md" <<'MD'
# ADR-0026 — product-space decision (separate numbering space)
MD
cat > "$T/multins/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec

## Architecture alignment
- ADR-0001 — resolves in the platform namespace specs/adr/.
- ADR-0026 — resolves in the product namespace specs/bookings/adr/.
- ADR-0042 — resolves in NEITHER namespace: this is the only real miss.
MD
OUT="$(cd "$T/multins" && ./init.sh 2>&1)" || fail "R7: init.sh exited non-zero with two ADR namespaces (must stay warn-only)"
echo "$OUT" | grep -q 'ADR-0001' && fail "R7: warned on an id that resolves in specs/adr/"
echo "$OUT" | grep -q 'ADR-0026' && fail "R7: warned on an id that resolves in the second namespace specs/bookings/adr/ (false positive)"
echo "$OUT" | grep -q 'ADR citation:.*ADR-0042' || fail "R7: did not warn on the id that resolves in NO namespace (check went blind)"
[ "$(echo "$OUT" | grep -c 'ADR citation:')" -eq 1 ] || fail "R7: expected exactly 1 unresolved-citation warning"
echo "$OUT" | grep -q '1 unresolved ADR citation' || fail "R7: trailing count line wrong or missing"
pass "R7 multi_namespace_resolution"

# ── R8: ONLY the product namespace exists (no specs/adr/) ⇒ sweep still runs and ──
#       resolves against it, instead of no-op'ing or warning on everything.
# R8_product_namespace_only
mk_sandbox prodns
mkdir -p "$T/prodns/specs/bookings/adr"
cat > "$T/prodns/specs/bookings/adr/0030-only-space.md" <<'MD'
# ADR-0030 — the only ADR namespace in this project
MD
cat > "$T/prodns/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec

## Architecture alignment
- ADR-0030 — resolves in the sole (product) namespace.
MD
OUT="$(cd "$T/prodns" && ./init.sh 2>&1)" || fail "R8: init.sh exited non-zero with only a product ADR namespace"
echo "$OUT" | grep -q 'ADR citation:' && fail "R8: warned although the citation resolves in specs/bookings/adr/"
echo "$OUT" | grep -q 'ADR citations resolve' || fail "R8: success line missing (sweep did not run against the product namespace)"
pass "R8 product_namespace_only"

# ── R9: a QUALIFIED citation (`<ns>/ADR-NNNN`, or `<ns> ADR-NNNN` for a known ns) ──
#       resolves in THAT namespace ONLY — cross-namespace ids and unknown namespaces
#       still warn even though the number exists somewhere (E99-F50 round 2).
#       The two spaces deliberately COLLIDE (0001 platform-only, 0023/0026 bookings-only).
# R9_qualified_is_namespace_scoped
mk_sandbox qualns
mkdir -p "$T/qualns/specs/adr" "$T/qualns/specs/bookings/adr"
cat > "$T/qualns/specs/adr/0001-platform-only.md" <<'MD'
# ADR-0001 — exists ONLY in the platform namespace
MD
cat > "$T/qualns/specs/bookings/adr/0023-product-only.md" <<'MD'
# ADR-0023 — exists ONLY in the product namespace
MD
cat > "$T/qualns/specs/bookings/adr/0026-product-only.md" <<'MD'
# ADR-0026 — exists ONLY in the product namespace
MD
cat > "$T/qualns/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec

## Architecture alignment
- bookings/ADR-0023 — qualified, resolves in its own namespace: silent.
- bookings/ADR-0026 — qualified, resolves in its own namespace: silent.
- platform ADR-0001 — qualified prose form, resolves in specs/adr/: silent.
- platform ADR-0023 — MISS: 0023 is product-only, so this is a cross-namespace typo.
- bookings/ADR-0001 — MISS: 0001 is platform-only (the other direction).
- fictional/ADR-0001 — MISS: 'fictional' is not an ADR namespace in this project.
MD
OUT="$(cd "$T/qualns" && ./init.sh 2>&1)" || fail "R9: init.sh exited non-zero on qualified citations (must stay warn-only)"
echo "$OUT" | grep -q 'platform/ADR-0023' || fail "R9: a qualified platform id silently resolved against the product namespace (cross-namespace typo went undetected)"
echo "$OUT" | grep -q 'bookings/ADR-0001' || fail "R9: a qualified product id silently resolved against the platform namespace"
echo "$OUT" | grep -q 'fictional/ADR-0001' || fail "R9: a citation qualified with an unknown namespace did not warn"
echo "$OUT" | grep -q 'ADR-0026' && fail "R9: warned on bookings/ADR-0026, which resolves in the namespace it names (false positive)"
echo "$OUT" | grep -q 'ADR citation:.*cites ADR-' && fail "R9: a qualified citation was treated as bare (qualifier discarded)"
[ "$(echo "$OUT" | grep -c 'ADR citation:')" -eq 3 ] || fail "R9: expected exactly 3 unresolved-citation warnings, got $(echo "$OUT" | grep -c 'ADR citation:')"
pass "R9 qualified_is_namespace_scoped"

# ── R10: a BARE `ADR-NNNN` asserts no namespace, so it stays permissive-any (the ────
#        deliberate ruling: never infer a namespace the author did not write), and an
#        ordinary prose word before an id is NOT a qualifier (E99-F50 round 2).
# R10_bare_is_namespace_agnostic
mk_sandbox barens
mkdir -p "$T/barens/specs/adr" "$T/barens/specs/bookings/adr"
cat > "$T/barens/specs/adr/0001-platform-only.md" <<'MD'
# ADR-0001 — exists ONLY in the platform namespace
MD
cat > "$T/barens/specs/bookings/adr/0026-product-only.md" <<'MD'
# ADR-0026 — exists ONLY in the product namespace
MD
cat > "$T/barens/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec

## Architecture alignment
- ADR-0001 — bare, resolves in the platform namespace: silent.
- ADR-0026 — bare, resolves in the product namespace: silent (bare = any namespace).
- the availability ADR-0026 rule — an ordinary prose word is NOT a namespace qualifier.
- ADR-0042 — resolves in NO namespace: the only real miss.
MD
OUT="$(cd "$T/barens" && ./init.sh 2>&1)" || fail "R10: init.sh exited non-zero on bare citations (must stay warn-only)"
# Ordered first on purpose: it is the assertion that dies under the "any preceding word
# is a namespace qualifier" mutant, and the ADR-0026 check below would shadow it.
echo "$OUT" | grep -q 'availability/' && fail "R10: promoted an ordinary prose word to an ADR namespace qualifier"
echo "$OUT" | grep -q 'ADR-0026' && fail "R10: warned on a bare id that resolves in the product namespace (bare must stay permissive-any)"
echo "$OUT" | grep -q 'ADR citation:.*cites ADR-0042' || fail "R10: did not warn on the bare id that resolves in NO namespace (check went blind)"
[ "$(echo "$OUT" | grep -c 'ADR citation:')" -eq 1 ] || fail "R10: expected exactly 1 unresolved-citation warning, got $(echo "$OUT" | grep -c 'ADR citation:')"
pass "R10 bare_is_namespace_agnostic"

# ── R12: TWO ids on one line — the extractor must check BOTH. The optional qualifier ─
#        group `[A-Za-z0-9_-]+` also matches a citation, so without a delimiter
#        `ADR-0042 ADR-0001` collapses into ONE match whose "qualifier" (`adr-0042`) is
#        then discarded — the first id is never looked up (E99-F50 round 3, blocker).
#        Every bracket/bullet/indent/slash form is pinned: the dash-bullet form escaped
#        the defect only by accident (`-` was eaten as the word), which is precisely why
#        it must not be the only case in the suite.
# R12_adjacent_ids_both_checked
mk_sandbox adjacent
mkdir -p "$T/adjacent/specs/adr" "$T/adjacent/specs/bookings/adr"
cat > "$T/adjacent/specs/adr/0001-platform-only.md" <<'MD'
# ADR-0001 — exists ONLY in the platform namespace
MD
cat > "$T/adjacent/specs/bookings/adr/0026-product-only.md" <<'MD'
# ADR-0026 — exists ONLY in the product namespace
MD
cat > "$T/adjacent/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec

## Architecture alignment
(ADR-0042 ADR-0001) — parens: BOTH ids are citations; 0042 resolves nowhere.
* ADR-0043 ADR-0001 — star bullet.
  ADR-0044 ADR-0001 — indented, no bullet marker.
- ADR-0045 ADR-0001 — dash bullet (escaped the defect by accident).
ADR-0046/ADR-0001 — slash-adjacent: 0046 must warn as BARE, not invent a namespace.
- ADR-0001 ADR-0026 — two RESOLVING ids adjacent: still silent.
MD
OUT="$(cd "$T/adjacent" && ./init.sh 2>&1)" || fail "R12: init.sh exited non-zero on adjacent ids (must stay warn-only)"
for n in 0042 0043 0044 0045 0046; do
  echo "$OUT" | grep -q "ADR citation:.*cites ADR-$n " \
    || fail "R12: ADR-$n was swallowed as a 'qualifier' of the id next to it and never looked up"
done
echo "$OUT" | grep -q 'adr-00' && fail "R12: an id was promoted to a bogus namespace token (e.g. 'adr-0046/ADR-0001')"
echo "$OUT" | grep -q 'ADR-0001' && fail "R12: warned on ADR-0001, which resolves in the platform namespace"
echo "$OUT" | grep -q 'ADR-0026' && fail "R12: warned on ADR-0026, which resolves in the product namespace"
[ "$(echo "$OUT" | grep -c 'ADR citation:')" -eq 5 ] || fail "R12: expected exactly 5 unresolved-citation warnings, got $(echo "$OUT" | grep -c 'ADR citation:')"
pass "R12 adjacent_ids_both_checked"

# ── R13: a REAL qualifier wrapped in markdown emphasis/quotes stays qualified ──────
#        (`**platform** ADR-NNNN`). The wrapper sits between the token and the space,
#        outside the qualifier group's char class, so without the strip the citation is
#        demoted to bare and a cross-namespace typo goes silent (E99-F50 round 3).
#        `_`-italics are NOT strippable (underscore is legal in a namespace token) —
#        that boundary stays documented in init.sh, not pinned here.
# R13_wrapped_qualifier_survives
mk_sandbox wrapped
mkdir -p "$T/wrapped/specs/adr" "$T/wrapped/specs/bookings/adr"
cat > "$T/wrapped/specs/adr/0001-platform-only.md" <<'MD'
# ADR-0001 — exists ONLY in the platform namespace
MD
for n in 0027 0028 0029; do
  printf '# ADR-%s — exists ONLY in the product namespace\n' "$n" \
    > "$T/wrapped/specs/bookings/adr/$n-product-only.md"
done
cat > "$T/wrapped/specs/epics/E01-demo/F01-thing/E01-F01.spec.md" <<'MD'
# E01-F01 — fixture spec

## Architecture alignment
- **platform** ADR-0027 — emphasized qualifier: a platform-space typo, must warn.
- "platform" ADR-0028 — quoted qualifier: same.
- 'platform' ADR-0029 — single-quoted qualifier: same.
- `bookings/ADR-0027` — code-spanned, qualified correctly: silent.
- ADR-0001 — bare control: silent.
MD
OUT="$(cd "$T/wrapped" && ./init.sh 2>&1)" || fail "R13: init.sh exited non-zero on wrapped qualifiers (must stay warn-only)"
for n in 0027 0028 0029; do
  echo "$OUT" | grep -q "cites platform/ADR-$n" \
    || fail "R13: a qualifier wrapped in emphasis/quotes was demoted to bare, so the platform-space typo ADR-$n resolved silently against the product namespace"
  echo "$OUT" | grep -q "cites ADR-$n " && fail "R13: ADR-$n was treated as bare (wrapper not stripped from the qualifier)"
done
echo "$OUT" | grep -q 'ADR-0001' && fail "R13: warned on the bare control ADR-0001, which resolves in the platform namespace"
[ "$(echo "$OUT" | grep -c 'ADR citation:')" -eq 3 ] || fail "R13: expected exactly 3 unresolved-citation warnings, got $(echo "$OUT" | grep -c 'ADR citation:')"
pass "R13 wrapped_qualifier_survives"

# ── R11: contract coherence — init.sh, the Reviewer, the Architect and the spec ────
#        template must state the SAME namespace rule. init.sh's sweep and the
#        Reviewer's soft flag are the same check at two altitudes; if the prose only
#        knows `specs/adr/`, a Reviewer following it literally re-flags every product-
#        namespace citation the sweep certifies clean (E99-F50 round 2, blocker 2).
# R11_contract_coherence
#        ALL FIVE contract files are pinned INDEPENDENTLY (round 3): docs/SPEC-FORMAT.md
#        and docs/WORKFLOW.md carried the identical stale claim and were fixed with the
#        rest, but nothing failed when either was reverted to the stale text.
ARC="agents/architect.md"; TPL="specs/_templates/feature.spec.md"
SPF="docs/SPEC-FORMAT.md"; WFL="docs/WORKFLOW.md"
for f in "$REV" "$ARC" "$TPL" "$SPF" "$WFL" init.sh; do
  [ -f "$f" ] || fail "R11: $f missing"
  # `<product>` in the illustrative form, `<ns>` in the normative one — either names a
  # second namespace; the stale single-namespace text has neither.
  grep -qE 'specs/<(product|ns)>/adr/' "$f" \
    || fail "R11: $f does not acknowledge a second ADR namespace (specs/<product>/adr/)"
  grep -qF '<ns>/ADR-NNNN' "$f" \
    || fail "R11: $f does not name the QUALIFIED citation form <ns>/ADR-NNNN"
  # E99-F75: `grep -qi 'bare'` was vacuous — every one of these files says 'bare'
  # somewhere unrelated (e.g. 'a bare scaffold', 'a bare remainder'). Anchor the rule:
  # bare … resolves/checked against … any (namespace/space).
  tr '\n' ' ' < "$f" | grep -qiE 'bare[^.]{0,60}against[^.]{0,20}any' \
    || fail "R11: $f does not state that a BARE citation resolves against ANY namespace"
done
# E99-F75: the Scout's drift-check Inputs line and the Doc-critic's plan-output scope
# row carried the stale single-namespace `specs/adr/NNNN-*.md` claim. Pin each file's
# CORRECTED line by TWO co-occurring tokens across folded newlines — the product
# namespace path and the space-separated qualified form. A bare single-word grep (e.g.
# 'bare', which scout.md satisfies with 'never a bare opinion') passes on the stale
# text; both pins below were verified to FAIL on the pre-change single-namespace lines.
for f in agents/scout.md agents/doc-critic.md; do
  [ -f "$f" ] || fail "R11: $f missing"
  tr '\n' ' ' < "$f" | grep -qiE 'specs/<product>/adr/[^.]{0,60}<ns> ADR-NNNN' \
    || fail "R11: $f does not acknowledge the product ADR namespace specs/<product>/adr/ with the qualified <ns> ADR-NNNN citation form"
done
tr '\n' ' ' < "$REV" | grep -qiE 'qualified[^.]{0,40}<ns> ADR-NNNN' \
                                 || fail "R11: reviewer.md does not state the qualified-citation rule (with the <ns> ADR-NNNN prose form)"
grep -qF '<ns>/ADR-NNNN' "$REV"  || fail "R11: reviewer.md does not name the <ns>/ADR-NNNN form"
grep -q 'ADR namespace holds a real' "$REV" \
  || fail "R11: reviewer.md's firing precondition still demands specs/adr/ specifically"
grep -qi 'qualify the namespace' "$ARC" || fail "R11: architect.md does not teach the qualifier convention"
grep -qi 'qualify the namespace' "$TPL" || fail "R11: the spec template does not teach the qualifier convention"
grep -qi 'RESIDUAL HOLE' init.sh || fail "R11: init.sh does not record the accepted bare-citation hole"
pass "R11 contract_coherence"

# ── R6: the live repo's ./init.sh still exits 0 (sweep is additive, never gates) ──
# R6_live_init_green
./init.sh >/dev/null 2>&1 || fail "R6: ./init.sh did not exit 0 in the live repo"
pass "R6 live_init_green"

echo "All adr-citation tests passed."
