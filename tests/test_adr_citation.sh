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
grep -qi 'resolve' "$REV"                         || fail "R1: reviewer does not state cited ids must resolve"
pass "R1 reviewer_resolution_rule"

# ── R2: cited-but-nonexistent id is a SOFT FLAG (same verdict rule), not a reject ─
# R2_reviewer_soft_flag
grep -qi 'cited-but-nonexistent' "$REV"           || fail "R2: reviewer does not name the cited-but-nonexistent case"
grep -qi 'flag' "$REV"                            || fail "R2: reviewer does not soft-flag it"
grep -qi 'not a hard reject\|not.*hard reject' "$REV" || fail "R2: reviewer does not say 'not a hard reject'"
grep -qi 'renamed\|removed' "$REV"                || fail "R2: reviewer does not give the renamed/removed-legitimately rationale"
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

# ── R6: the live repo's ./init.sh still exits 0 (sweep is additive, never gates) ──
# R6_live_init_green
./init.sh >/dev/null 2>&1 || fail "R6: ./init.sh did not exit 0 in the live repo"
pass "R6 live_init_green"

echo "All adr-citation tests passed."
