#!/bin/sh
# E16-F02 — offline contracts for the rationale, deletion ledger, and navigation.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DOC="$ROOT/docs/RATIONALE.md"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }
has() { grep -qF "$1" "$2" || fail "$3"; }

cold_reader_rationale() {
  [ -f "$DOC" ] || fail "docs/RATIONALE.md is absent"
  has '## Why a harness' "$DOC" "missing cold-reader why section"
  has 'An agent harness is' "$DOC" "missing plain-language harness definition"
  has 'newcomers' "$DOC" "missing newcomer audience"
  has 'maintainers' "$DOC" "missing maintainer audience"
  has 'prompting alone' "$DOC" "missing prompt-only boundary"
  has 'as models improve' "$DOC" "missing model-improvement scope"
  has 'specification, verification, and trust' "$DOC" "missing shifting-value thesis"
  _sections="$(grep '^## ' "$DOC" | paste -sd '|' -)"
  [ "$_sections" = '## Why a harness|## Two layers, one decision rule|## Deletion ledger|## How to use the ledger|## Evidence and limits' ] ||
    fail "rationale sections are missing, duplicated, or out of order"
  pass "cold_reader_rationale"
}

two_layer_decision_rule() {
  has '## Two layers, one decision rule' "$DOC" "missing two-layer section"
  has '**Capability compensation**' "$DOC" "missing compensation definition"
  has '**Durable trust and intent**' "$DOC" "missing durable definition"
  has 'primary purpose' "$DOC" "missing mixed-mechanism classification rule"
  has 'Neither label means immutable' "$DOC" "labels incorrectly imply immutability"
  has 'retain it' "$DOC" "missing retain-by-default posture"
  pass "two_layer_decision_rule"
}

ledger_shape() {
  has '## Deletion ledger' "$DOC" "missing deletion ledger section"
  has '| Mechanism | Layer | Why it exists now | Evidence to reconsider or remove | Repository pointers |' \
    "$DOC" "ledger header differs from contract"
  _rows="$(awk '
    /^## Deletion ledger$/ { ledger=1; next }
    ledger && /^## / { exit }
    ledger && /^\| (C[1-8]|D([1-9]|1[0-3])) / { count++ }
    END { print count+0 }
  ' "$DOC")"
  [ "$_rows" -eq 21 ] || fail "ledger must contain exactly 21 C/D rows (found $_rows)"
  [ ! -e "$ROOT/docs/DELETION-LEDGER.md" ] || fail "sibling deletion ledger is forbidden"
  [ ! -e "$ROOT/docs/deletion-ledger.yaml" ] || fail "machine-readable YAML ledger is forbidden"
  [ ! -e "$ROOT/docs/deletion-ledger.json" ] || fail "machine-readable JSON ledger is forbidden"
  pass "ledger_shape"
}

compensation_inventory() {
  for _label in \
    'C1 — `init.sh` structural preflight' \
    'C2 — Curated clean contexts, `context_reset_threshold`, and file handoffs' \
    'C3 — Role-scoped `DO NOT TOUCH` and minimal-tool instructions' \
    'C4 — Read-only Scout discovery' \
    'C5 — Doc-critic advisory checkpoint' \
    'C6 — Reviewer cross-file consistency audit' \
    'C7 — Multi-round Builder↔Reviewer correction' \
    'C8 — Model interpretation of prose `next()` routing'
  do
    has "$_label" "$DOC" "missing compensation row: $_label"
  done
  [ "$(grep -Ec '^\| C[1-8] — .+ \| Capability compensation \|' "$DOC")" -eq 8 ] ||
    fail "every C1-C8 row must use the capability-compensation layer"
  pass "compensation_inventory"
}

durable_inventory() {
  for _label in \
    'D1 — EARS specs and R-id traceability' \
    'D2 — File-backed TaskStore, specs, progress, and history' \
    'D3 — Role separation and independent review' \
    'D4 — Human approval and autonomous gates' \
    'D5 — Deterministic tests, lint/type checks, and behavioral evidence' \
    'D6 — Board write locking and isolated Git worktrees' \
    'D7 — Dependency diagnostics and deterministic selection' \
    'D8 — Architecture/ADR alignment and epic drift checks' \
    'D9 — Telemetry' \
    'D10 — Ownership and scoped selection' \
    'D11 — Umbrella contracts, slice rollups, and integration gates' \
    'D12 — Store/execution/mirror seams with local truth' \
    'D13 — Repository portability, config layering, and versioned install'
  do
    has "$_label" "$DOC" "missing durable row: $_label"
  done
  [ "$(grep -Ec '^\| D([1-9]|1[0-3]) — .+ \| Durable trust and intent \|' "$DOC")" -eq 13 ] ||
    fail "every D1-D13 row must use the durable trust-and-intent layer"
  pass "durable_inventory"
}

row_evidence_completeness() {
  awk '
    /^## Deletion ledger$/ { ledger=1; next }
    ledger && /^## / { exit }
    ledger && /^\| (C[1-8]|D([1-9]|1[0-3])) / {
      n=split($0, cell, "|")
      if (n != 7) {
        print "malformed five-cell ledger row: " $0 > "/dev/stderr"
        bad=1
      }
      for (i=2; i<=6; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell[i])
        if (cell[i] == "") {
          print "empty ledger cell: " $0 > "/dev/stderr"
          bad=1
        }
      }
      if (cell[5] !~ /(Repeated|runs|rates|data|checks|evidence|reviewed|replacement|decision|cannot|preserves|stop|unsupported|ceases|no longer)/) {
        print "non-observable evidence criterion: " $0 > "/dev/stderr"
        bad=1
      }
    }
    END { exit bad }
  ' "$DOC" || fail "ledger rows need mechanism-specific purpose/evidence/pointers"
  has 'evidence is absent, retain the mechanism' "$DOC" "missing global retain-by-default rule"
  pass "row_evidence_completeness"
}

prose_routing_boundary() {
  _row="$(grep '^| C8 ' "$DOC" || true)"
  [ -n "$_row" ] || fail "missing C8 prose-routing row"
  printf '%s\n' "$_row" | grep -qF '[ADR-0001]' || fail "C8 must link ADR-0001"
  printf '%s\n' "$_row" | grep -qF 'E16-F03' || fail "C8 must name E16-F03"
  printf '%s\n' "$_row" | grep -qF 'reviewed and shipped' ||
    fail "C8 must retain prose routing until replacement is reviewed and shipped"
  printf '%s\n' "$_row" | grep -qF 'human-readable gate policy' ||
    fail "C8 must preserve human-readable gate policy"
  pass "prose_routing_boundary"
}

source_attribution_and_limits() {
  has '## Evidence and limits' "$DOC" "missing evidence-and-limits section"
  for _source in \
    '[Anthropic: effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)' \
    '[Anthropic: harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)' \
    '[OpenAI: harness engineering in an agent-first repository](https://openai.com/index/harness-engineering/)' \
    '[LangChain: improving Deep Agents with harness engineering](https://www.langchain.com/blog/improving-deep-agents-with-harness-engineering)' \
    '[Thoughtworks: feedback sensors for coding agents](https://www.thoughtworks.com/en-us/radar/techniques/feedback-sensors-for-coding-agents)' \
    '[METR: early-2025 AI and experienced open-source developer productivity](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/)'
  do
    has "$_source" "$DOC" "missing descriptive primary-source link: $_source"
  done
  has 'bounded reports, not evidence of universal consensus' "$DOC" "missing source-boundary statement"
  has 'early-2025 randomized controlled trial snapshot' "$DOC" "missing METR time/method scope"
  has 'experienced open-source developers working in repositories they knew well' "$DOC" \
    "missing METR population/repository scope"
  has 'does not show that AI universally slows developers' "$DOC" "missing METR non-generalization"
  pass "source_attribution_and_limits"
}

readme_navigation() {
  has '[why the harness exists](docs/RATIONALE.md)' "$ROOT/README.md" \
    "README introductory why path does not link rationale"
  has '[RATIONALE.md](docs/RATIONALE.md)' "$ROOT/README.md" \
    "README docs layout does not list rationale"
  pass "readme_navigation"
}

agents_and_harness_navigation() {
  has '| `docs/RATIONALE.md` |' "$ROOT/AGENTS.md" "AGENTS docs map lacks concise rationale row"
  has '[rationale and deletion ledger](RATIONALE.md)' "$ROOT/docs/HARNESS.md" \
    "HARNESS introduction lacks descriptive rationale link"
  [ "$(grep -c '^| C[1-8] ' "$ROOT/AGENTS.md" || true)" -eq 0 ] ||
    fail "AGENTS must not duplicate compensation ledger"
  [ "$(grep -c '^| D[0-9]' "$ROOT/docs/HARNESS.md" || true)" -eq 0 ] ||
    fail "HARNESS must not duplicate durable ledger"
  pass "agents_and_harness_navigation"
}

portable_text_only_markdown() {
  ! grep -Eq '!\[[^]]*\]\(|<img|<script|```mermaid|color[- ]only' "$DOC" ||
    fail "rationale requires an image, script, Mermaid, or color-only distinction"
  ! grep -Eq '(^|[[:space:]])https?://[^)>[:space:]]+' "$DOC" ||
    fail "rationale contains a bare external URL instead of descriptive link text"
  ! grep -Eiq 'machine[- ](enforced|readable)|automatically delete|deletion automation' "$DOC" ||
    fail "rationale implies a machine policy or deletion automation"
  pass "portable_text_only_markdown"
}

check_local_links_in() {
  _file="$1"
  _dir="$(dirname "$_file")"
  awk '{
    line=$0
    while (match(line, /\]\([^)]*\)/)) {
      print substr(line, RSTART+2, RLENGTH-3)
      line=substr(line, RSTART+RLENGTH)
    }
  }' "$_file" |
    while IFS= read -r _target
    do
      case "$_target" in
        ""|\#*|http://*|https://*|mailto:*) continue ;;
      esac
      _target="${_target%%#*}"
      [ -e "$_dir/$_target" ] ||
        fail "broken local Markdown link in ${_file#"$ROOT/"}: $_target"
    done
}

links_and_verification_wiring() {
  check_local_links_in "$DOC"
  check_local_links_in "$ROOT/README.md"
  check_local_links_in "$ROOT/AGENTS.md"
  check_local_links_in "$ROOT/docs/HARNESS.md"
  # verification.test_command now delegates to tools/run-tests.sh, which DISCOVERS every
  # tests/test_*.sh. The intent of this check is "this suite is not orphaned", so accept
  # either spelling: an explicit mention, or the discovering runner plus the file existing.
  _command="$(sed -n 's/^[[:space:]]*test_command: "\([^"]*\)".*$/\1/p' "$ROOT/harness.config.yaml")"
  { printf '%s\n' "$_command" | grep -qF 'sh tests/test_rationale_docs.sh'; } \
    || { printf '%s\n' "$_command" | grep -qF 'tools/run-tests.sh' \
         && [ -f "$ROOT/tests/test_rationale_docs.sh" ]; } ||
    fail "configured full verification does not reach the rationale suite"
  # The duplicate guard only means something for the explicit &&-chain spelling, where a
  # suite could be appended twice. Under the discovering runner the name appears zero times
  # by design, and a suite cannot be discovered twice.
  _named="$(printf '%s\n' "$_command" | grep -o 'sh tests/test_rationale_docs.sh' | wc -l | tr -d ' ')"
  if [ "$_named" -ne 0 ]; then
    [ "$_named" -eq 1 ] || fail "rationale suite must be appended exactly once"
  fi
  pass "links_and_verification_wiring"
}

version_policy() {
  _versions="$(awk '
    /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ {
      version=$2; gsub(/[][]/, "", version)
      if (feature != "" && older == "") { older=version; print feature; print older; exit }
      section=version
    }
    /E16-F02/ && feature == "" { feature=section }
  ' "$ROOT/CHANGELOG.md")"
  _feature="$(printf '%s\n' "$_versions" | sed -n '1p')"
  _older="$(printf '%s\n' "$_versions" | sed -n '2p')"
  [ -n "$_feature" ] && [ -n "$_older" ] ||
    fail "could not locate E16-F02 release and immediately older release"
  IFS=. read -r _fmaj _fmin _fpatch <<EOF
$_feature
EOF
  IFS=. read -r _omaj _omin _opatch <<EOF
$_older
EOF
  [ "$_fmaj" -eq "$_omaj" ] && [ "$_fmin" -eq $((_omin + 1)) ] && [ "$_fpatch" -eq 0 ] ||
    fail "E16-F02 release $_feature is not one MINOR above $_older with patch zero"
  _current="$(cat "$ROOT/VERSION")"
  [ "$(printf '%s\n%s\n' "$_feature" "$_current" | sort -V | tail -1)" = "$_current" ] ||
    fail "current VERSION $_current is older than E16-F02 release $_feature"
  pass "version_policy"
}

cold_reader_rationale
two_layer_decision_rule
ledger_shape
compensation_inventory
durable_inventory
row_evidence_completeness
prose_routing_boundary
source_attribution_and_limits
readme_navigation
agents_and_harness_navigation
portable_text_only_markdown
links_and_verification_wiring
version_policy

echo "PASS: rationale documentation contracts"
