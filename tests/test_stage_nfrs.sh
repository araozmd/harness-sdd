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

# lineno <file> <fixed-string> — first line number whose line STARTS with the string (0 if none).
lineno() {
  awk -v s="$2" 'index($0,s)==1{print NR; f=1; exit} END{if(!f) print 0}' "$1"
}

# R4 — the ADR template carries `deferred` and the mandatory-when-deferred Trigger: line.
R4_adr_template_deferred_trigger() {
  _a="$I/specs/_templates/adr.md"
  [ -f "$_a" ] || fail "R4: installed specs/_templates/adr.md missing"
  grep -qF -- '- **Status:** <proposed | accepted | deferred>' "$_a" \
    || fail "R4: ADR template Status line does not list 'proposed | accepted | deferred'"
  grep -qE '^- \*\*Trigger:\*\* ' "$_a" \
    || fail "R4: ADR template has no '- **Trigger:** ' header line"
  fold "$_a" | grep -qE 'Trigger:\*\*[^.]{0,120}mandatory when Status is deferred; omit otherwise' \
    || fail "R4: the Trigger: header line does not state it is mandatory when Status is deferred and omitted otherwise"
  _d="$(lineno "$_a" '- **Date:**')"; _t="$(lineno "$_a" '- **Trigger:**')"; _c="$(lineno "$_a" '## Context')"
  [ "$_d" -gt 0 ] && [ "$_t" -eq $((_d + 1)) ] && [ "$_c" -gt "$_t" ] \
    || fail "R4: the Trigger: line is not the header line directly after Date: (date=$_d trigger=$_t context=$_c)"
  grep -qiE 'one architecture decision per ADR' "$_a" \
    || fail "R4: the ADR template lost its 'One architecture decision per ADR' sentence"
  pass "ADR template lists deferred and carries a mandatory-when-deferred Trigger: header line (R4) [R4_adr_template_deferred_trigger]"
}
R4_adr_template_deferred_trigger

# R5 — the ADR template names the sticky list (never deferred) and the bolt-on examples.
R5_adr_template_sticky_boltons() {
  _a="$I/specs/_templates/adr.md"
  for _k in 'tenant isolation' 'auth boundary' 'secrets out of the repo' 'validation at the system edge'; do
    grep -qiF "$_k" "$_a" || fail "R5: ADR template guidance does not name the sticky NFR '$_k'"
  done
  grep -qF 'never deferred at any stage' "$_a" \
    || fail "R5: ADR template guidance does not say sticky NFRs are 'never deferred at any stage'"
  for _k in 'encryption at rest' 'WAF' 'rate limits' 'backups' 'caching'; do
    grep -qiF "$_k" "$_a" || fail "R5: ADR template guidance does not name the bolt-on example '$_k'"
  done
  fold "$_a" | grep -qE 'ADR-0009[^.]{0,40}extending[^.]{0,80}spec change' \
    || fail "R5: ADR template guidance does not say extending the sticky list is a change to ADR-0009 (a spec change)"
  _t="$(lineno "$_a" '- **Trigger:**')"; _g="$(lineno "$_a" '> ## Stage-aware NFRs (ADR-0009)')"; _c="$(lineno "$_a" '## Context')"
  [ "$_g" -gt "$_t" ] && [ "$_c" -gt "$_g" ] \
    || fail "R5: the '> ## Stage-aware NFRs (ADR-0009)' guidance block is not between the header list and ## Context (trigger=$_t guidance=$_g context=$_c)"
  pass "ADR template names the 4 sticky NFRs (never deferred at any stage), the 5 bolt-on examples and the spec-change rule (R5) [R5_adr_template_sticky_boltons]"
}
R5_adr_template_sticky_boltons

echo "All stage/NFR tests passed."
