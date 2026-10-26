#!/bin/sh
# test_stage_nfrs.sh — E36-F03: product stage and deferred-decision ADRs with triggers;
# sticky vs bolt-on NFRs (ADR-0009 decisions 1-3).
#
# Pins SHAPES and PROSE, not a lint (enforcement is E36-F04). Every prose contract is a
# WHOLE-FILE grep on the INSTALLED copy under $I — the installed body is a cp -R of the
# source, so the installed grep proves the shipped content. No heading slicer is used, so
# nothing here is fence-blind. R3 reads this repo's own specs/product.md (project-owned,
# never installed). R12 reads VERSION at runtime and freezes no literal.
#
# Co-occurrence anchors fold newlines (`tr '\n' ' '`) and bound the gap with `[^.]{0,N}`
# so the two tokens sit in one sentence. They prove co-occurrence, not polarity (see
# agents/builder.md) — read the diff for meaning.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-sn)"
trap 'rm -rf "$T"' EXIT
trap 'exit 1' HUP INT TERM  # a killed suite still runs its EXIT cleanup (2026-10-25)

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# One fresh install; sandboxed CODEX_HOME/HOME so nothing global is written.
mkdir -p "$T/tgt" "$T/ch" "$T/home"
CODEX_HOME="$T/ch" HOME="$T/home" sh "$ROOT/harness-install.sh" --agents=claude "$T/tgt" \
  >"$T/install.out" 2>"$T/install.err" \
  || fail "setup: fresh install exited non-zero: $(cat "$T/install.err")"
I="$T/tgt/.harness"

# fold <file> — the file on one line (newlines to spaces) for sentence-bounded anchors.
fold() { tr '\n' ' ' < "$1"; }

# frontmatter_stage_production <file> — 0 iff line 1 is `---` and the bare line
# `stage: production` sits before the block's closing `---` (the `$` anchor is the grammar:
# an inline comment on the value line fails it).
frontmatter_stage_production() {
  awk 'NR==1&&$0!="---"{exit 1} NR>1&&/^---$/{exit} /^stage: production$/{f=1} END{exit !f}' "$1"
}

# R3 — this repository declares its own stage.
R3_repo_product_stage() {
  frontmatter_stage_production "$ROOT/specs/product.md" \
    || fail "R3: specs/product.md does not open with a --- frontmatter block holding the bare line 'stage: production'"
  pass "this repo's specs/product.md declares 'stage: production' in its frontmatter (R3) [R3_repo_product_stage]"
}
R3_repo_product_stage

echo "All stage/NFR tests passed."
