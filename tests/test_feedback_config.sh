#!/bin/sh
# test_feedback_config.sh — test contract for E32-F01 (`feedback:` config block + the
# one-line install opt-out notice). Zero-dependency POSIX sh, matching the house style of
# tests/test_install.sh (self-cleaning mktemp tree, fail/pass helpers, dash-clean).
#
# R1-R11 map to E32-F01.tests.md. `_block_region`, `mapping_pairs`, `require_same_mapping`
# and `require_no_interior_blank` are COPIED from tests/test_install.sh — the plan notes
# there is no tests/lib/ to source shell helpers from.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL="$SRC/harness-install.sh"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-feedback)"
trap 'rm -rf "$T"' EXIT

# Sandbox Codex's GLOBAL prompts dir so no run touches the developer's real ~/.codex
# (same guard every installer-invoking suite uses).
export CODEX_HOME="$T/codex-home"
# E25-F01: non-Claude front-ends are parked by default on fresh targets; pin a single,
# fast, deterministic selection — none of these R-ids care which front-end is selected.
export HARNESS_AGENTS="claude"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

# ── copied verbatim from tests/test_install.sh (E99-F162 shape) ───────────────────────

# _block_region <anchor-literal> <file> — emit a duplicated block's captured text: from the
# column-0 anchor comment line, through the block's own top-level key and its indented
# mapping/comment lines, up to (but excluding) the next COLUMN-0 NON-COMMENT line or EOF;
# then drop the trailing run of blank / column-0 comment-only lines.
_block_region() {
  awk -v anchor="$1" '
    substr($0, 1, length(anchor)) == anchor { m = 1; b[++n] = $0; next }
    m && /^[A-Za-z0-9_.-]+:/ && !k { k = 1; b[++n] = $0; next }
    m && k && /^[^[:space:]#]/ { exit }
    m { b[++n] = $0 }
    END {
      while (n > 0 && (b[n] == "" || b[n] ~ /^#/)) n--
      for (i = 1; i <= n; i++) print b[i]
    }' "$2"
}

feedback_block() { _block_region '# Harness feedback (E32-F01)' "$1"; }

# mapping_pairs <capture> — the SEMANTIC view of a captured block: one `key=value` per
# indented mapping leaf, sorted. Comment-only lines, blank lines and inline comments are
# dropped.
mapping_pairs() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { next }
    {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      if (line !~ /^[[:space:]]+[A-Za-z0-9_.-]+:/) next
      key = line; sub(/^[[:space:]]+/, "", key); sub(/:.*/, "", key)
      val = line; sub(/^[[:space:]]+[A-Za-z0-9_.-]+:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
      print key "=" val
    }' "$1" | LC_ALL=C sort
}

# require_same_mapping <what> <seed-capture> <migrated-capture> <required-key>...
require_same_mapping() {
  _rsm_what="$1"; _rsm_seed="$2"; _rsm_migr="$3"; shift 3
  mapping_pairs "$_rsm_seed" > "$_rsm_seed.pairs"
  mapping_pairs "$_rsm_migr" > "$_rsm_migr.pairs"
  [ -s "$_rsm_seed.pairs" ] \
    || fail "$_rsm_what: no SEMANTIC key/value pairs parsed from the seeded copy — the extractor or its mapping anchor is stale (fail-closed)"
  [ -s "$_rsm_migr.pairs" ] \
    || fail "$_rsm_what: no SEMANTIC key/value pairs parsed from the migrated copy — the extractor or its mapping anchor is stale (fail-closed)"
  for _rsm_f in "$_rsm_seed.pairs" "$_rsm_migr.pairs"; do
    for _rsm_k in "$@"; do
      grep -q "^${_rsm_k}=" "$_rsm_f" \
        || fail "$_rsm_what: the parsed mapping from ${_rsm_f%.pairs} is missing required key '$_rsm_k' — the extractor did not reach the whole mapping, or a required key was deleted (fail-closed)"
    done
  done
  cmp -s "$_rsm_seed.pairs" "$_rsm_migr.pairs" \
    || fail "$_rsm_what: the two copies' SEMANTIC mapping differs — a real key/value was added, changed or removed on one side. Parsed diff: $(diff "$_rsm_seed.pairs" "$_rsm_migr.pairs" | head -n 8)"
}

# require_no_interior_blank <capture> <what>
require_no_interior_blank() {
  _nb_cap="$1"; _nb_what="$2"
  _nb_hit="$(grep -n '^$' "$_nb_cap" | head -n 1 || true)"
  [ -z "$_nb_hit" ] \
    || fail "$_nb_what: a BLANK line sits INSIDE the captured mapping (capture line ${_nb_hit%%:*})"
}

# notice_lines <stdout-capture> <repo> <config-path> — the lines that carry ALL THREE
# R5 tokens together (the resolved repo, the literal opt-out phrase, and the seeded
# config's own path) on the SAME line. Uses awk index() (no regex) so a config path
# containing shell/regex-special characters is matched literally.
notice_lines() {
  awk -v r="$2" -v o="feedback.enabled: false" -v c="$3" \
    'index($0,r) && index($0,o) && index($0,c)' "$1"
}

# strip_feedback_block <config> — delete the E32-F01 block (comment header through its
# last key) from a freshly seeded config, so a "does migration re-append it" fixture does
# not already carry the artifact under test (lesson 2026-09-05: a copied/pre-seeded
# fixture otherwise proves nothing).
strip_feedback_block() {
  awk '/^# Harness feedback \(E32-F01\)/ { skip = 1 } skip && /^  max_per_session:/ { skip = 0; next } !skip' \
    "$1" > "$1.stripped" && mv "$1.stripped" "$1"
  grep -Eq '^feedback:' "$1" && fail "setup failed — the feedback: block was not stripped from $1"
  return 0
}

# ── R1 ──────────────────────────────────────────────────────────────────────────────────
test_seed_template_block() {
  feedback_block "$SRC/harness.config.yaml" > "$T/tpl-block.txt"
  [ -s "$T/tpl-block.txt" ] \
    || fail "R1: could not capture the feedback: block from the seed template — its comment header anchor is missing"
  require_no_interior_blank "$T/tpl-block.txt" "R1: seed template feedback: block"
  grep -qxF 'feedback:' "$T/tpl-block.txt" \
    || fail "R1: seed template's feedback: block header is not a column-0 'feedback:' line"
  grep -qxF '  enabled: true' "$T/tpl-block.txt" \
    || fail "R1: seed template feedback.enabled is not 'true'"
  grep -qxF '  repo: github.com/araozmd/harness-sdd' "$T/tpl-block.txt" \
    || fail "R1: seed template feedback.repo is not the shipped default"
  grep -qxF '  max_per_session: 3' "$T/tpl-block.txt" \
    || fail "R1: seed template feedback.max_per_session is not 3"
  [ "$(grep -cE '^feedback:[[:space:]]*(#.*)?$' "$SRC/harness.config.yaml")" = "1" ] \
    || fail "R1: seed template carries more than one top-level feedback: header"
  _last_key="$(grep -E '^[A-Za-z0-9_.-]+:' "$SRC/harness.config.yaml" | tail -n 1)"
  [ "$_last_key" = "feedback:" ] \
    || fail "R1: feedback: is not the seed template's final top-level block (last key seen: $_last_key)"
  pass "seed template carries exactly one feedback: block with the shipped defaults, as the final block (R1) [test_seed_template_block]"
}

# ── R2 ──────────────────────────────────────────────────────────────────────────────────
test_fresh_install_seeds_block() {
  _t="$T/r2"; mkdir -p "$_t"
  sh "$INSTALL" "$_t" >/dev/null 2>&1 || fail "R2: fresh install failed"
  feedback_block "$_t/.harness/harness.config.yaml" > "$T/r2-block.txt"
  [ -s "$T/r2-block.txt" ] || fail "R2: fresh install did not seed a feedback: block"
  grep -qxF '  enabled: true' "$T/r2-block.txt" || fail "R2: fresh-seeded feedback.enabled is not 'true'"
  grep -qxF '  repo: github.com/araozmd/harness-sdd' "$T/r2-block.txt" \
    || fail "R2: fresh-seeded feedback.repo is not the shipped default"
  grep -qxF '  max_per_session: 3' "$T/r2-block.txt" \
    || fail "R2: fresh-seeded feedback.max_per_session is not 3"
  pass "fresh install seeds the feedback: block with the R1 defaults (R2) [test_fresh_install_seeds_block]"
}

# ── R3 ──────────────────────────────────────────────────────────────────────────────────
test_template_and_heredoc_converge() {
  feedback_block "$SRC/harness.config.yaml" > "$T/tpl.txt"
  feedback_block "$SRC/harness-install.sh" > "$T/heredoc.txt"
  [ -s "$T/tpl.txt" ] || fail "R3: could not capture the feedback: block from harness.config.yaml"
  [ -s "$T/heredoc.txt" ] || fail "R3: could not capture the feedback: block from harness-install.sh's heredoc"
  require_no_interior_blank "$T/tpl.txt" "R3: template feedback: block"
  require_no_interior_blank "$T/heredoc.txt" "R3: heredoc feedback: block"
  require_same_mapping "R3: template vs heredoc feedback: block" \
    "$T/tpl.txt" "$T/heredoc.txt" enabled repo max_per_session
  cmp -s "$T/tpl.txt" "$T/heredoc.txt" \
    || fail "R3: harness-install.sh's heredoc feedback: block is NOT byte-identical to harness.config.yaml's: $(diff "$T/tpl.txt" "$T/heredoc.txt" | head -n 8)"
  pass "the seed template and migrate_config's heredoc feedback: block converge (R3) [test_template_and_heredoc_converge]"
}

test_seeded_migrated_converge() {
  _wc="$T/r3-converge"; mkdir -p "$_wc"
  sh "$INSTALL" "$_wc" >/dev/null 2>&1 || fail "R3: seed install failed"
  _cfg="$_wc/.harness/harness.config.yaml"
  feedback_block "$_cfg" > "$_wc/blk-seeded.txt"
  [ -s "$_wc/blk-seeded.txt" ] || fail "R3: the SEEDED feedback: block could not be captured"
  require_no_interior_blank "$_wc/blk-seeded.txt" "R3: SEEDED feedback: block"

  strip_feedback_block "$_cfg"

  sh "$INSTALL" "$_wc" >/dev/null 2>&1 || fail "R3: migrate install failed"
  feedback_block "$_cfg" > "$_wc/blk-migrated.txt"
  [ -s "$_wc/blk-migrated.txt" ] \
    || fail "R3: migrate_config appended no feedback: block to a config that lacked one"
  require_no_interior_blank "$_wc/blk-migrated.txt" "R3: MIGRATED feedback: block"
  require_same_mapping "R3: seeded vs migrated feedback: block" \
    "$_wc/blk-seeded.txt" "$_wc/blk-migrated.txt" enabled repo max_per_session
  cmp -s "$_wc/blk-seeded.txt" "$_wc/blk-migrated.txt" \
    || fail "R3: the MIGRATED feedback: block is NOT byte-identical to the seeded one: $(diff "$_wc/blk-seeded.txt" "$_wc/blk-migrated.txt" | head -n 8)"

  # …and a further run must not append a second copy.
  sh "$INSTALL" "$_wc" >/dev/null 2>&1 || fail "R3: idempotence install failed"
  [ "$(grep -cE '^feedback:[[:space:]]*(#.*)?$' "$_cfg")" = "1" ] \
    || fail "R3: the config carries $(grep -cE '^feedback:' "$_cfg") top-level feedback: headers, expected exactly 1"
  pass "an upgrade of a config with no feedback: header appends a converged block, idempotently (R3) [test_seeded_migrated_converge]"
}

# ── R4 ──────────────────────────────────────────────────────────────────────────────────
test_existing_block_preserved() {
  # (a) block-style operator block: distinctive values, a missing key, a header comment.
  _a="$T/r4a"; mkdir -p "$_a"
  sh "$INSTALL" "$_a" >/dev/null 2>&1 || fail "R4a: seed install failed"
  _acfg="$_a/.harness/harness.config.yaml"
  strip_feedback_block "$_acfg"
  {
    printf '\n'
    printf 'feedback: # operator note\n'
    printf '  enabled: false\n'
    printf '  repo: ghe.example.com/acme/fork\n'
  } >> "$_acfg"
  cp "$_acfg" "$T/r4a-before.txt"

  sh "$INSTALL" "$_a" >/dev/null 2>&1 || fail "R4a: first upgrade run failed"
  sh "$INSTALL" "$_a" >/dev/null 2>&1 || fail "R4a: second upgrade run failed"
  cmp -s "$T/r4a-before.txt" "$_acfg" \
    || fail "R4a: the operator's block-style feedback: section changed across two upgrade runs: $(diff "$T/r4a-before.txt" "$_acfg" | head -n 8)"
  [ "$(grep -cE '^feedback:' "$_acfg")" = "1" ] \
    || fail "R4a: the config carries $(grep -cE '^feedback:' "$_acfg") column-0 feedback: lines, expected exactly 1"

  # (b) one-line flow form — the presence check must be WIDE enough to see it.
  _b="$T/r4b"; mkdir -p "$_b"
  sh "$INSTALL" "$_b" >/dev/null 2>&1 || fail "R4b: seed install failed"
  _bcfg="$_b/.harness/harness.config.yaml"
  strip_feedback_block "$_bcfg"
  printf '\nfeedback: { enabled: false }\n' >> "$_bcfg"
  cp "$_bcfg" "$T/r4b-before.txt"

  sh "$INSTALL" "$_b" >/dev/null 2>&1 || fail "R4b: first upgrade run failed"
  sh "$INSTALL" "$_b" >/dev/null 2>&1 || fail "R4b: second upgrade run failed"
  cmp -s "$T/r4b-before.txt" "$_bcfg" \
    || fail "R4b: the operator's one-line flow-form feedback: line changed across two upgrade runs: $(diff "$T/r4b-before.txt" "$_bcfg" | head -n 8)"
  [ "$(grep -cE '^feedback:' "$_bcfg")" = "1" ] \
    || fail "R4b: the config carries $(grep -cE '^feedback:' "$_bcfg") column-0 feedback: lines, expected exactly 1 — a narrowed presence check would append a second (defaults-ON) block behind the operator's opt-out"

  pass "an existing block-style or one-line-flow-form feedback: block survives two upgrade runs unchanged, with no duplicate header (R4) [test_existing_block_preserved]"
}

# ── R5 (+ positive control referenced by R6) ────────────────────────────────────────────
test_notice_on_seed() {
  # fresh install.
  _f="$T/r5-fresh"; mkdir -p "$_f"
  _fout="$T/r5-fresh.out"
  sh "$INSTALL" "$_f" >"$_fout" 2>/dev/null || fail "R5 fresh: install failed"
  _fcfg="$_f/.harness/harness.config.yaml"
  notice_lines "$_fout" "github.com/araozmd/harness-sdd" "$_fcfg" > "$T/r5-fresh-notice.txt"
  [ "$(wc -l < "$T/r5-fresh-notice.txt")" = "1" ] \
    || fail "R5 fresh: expected exactly 1 stdout line carrying the repo, 'feedback.enabled: false', and the config path together, got $(wc -l < "$T/r5-fresh-notice.txt")"

  # migrating upgrade.
  _m="$T/r5-migrate"; mkdir -p "$_m"
  sh "$INSTALL" "$_m" >/dev/null 2>&1 || fail "R5 migrate: setup install failed"
  _mcfg="$_m/.harness/harness.config.yaml"
  strip_feedback_block "$_mcfg"
  _mout="$T/r5-migrate.out"
  sh "$INSTALL" "$_m" >"$_mout" 2>/dev/null || fail "R5 migrate: install failed"
  notice_lines "$_mout" "github.com/araozmd/harness-sdd" "$_mcfg" > "$T/r5-migrate-notice.txt"
  [ "$(wc -l < "$T/r5-migrate-notice.txt")" = "1" ] \
    || fail "R5 migrate: expected exactly 1 stdout line carrying the repo, 'feedback.enabled: false', and the config path together, got $(wc -l < "$T/r5-migrate-notice.txt")"

  pass "fresh install and migrating upgrade each print exactly one feedback notice line, naming repo/opt-out/config path, on stdout (R5) [test_notice_on_seed]"
}

# ── R6 ──────────────────────────────────────────────────────────────────────────────────
test_no_notice_when_present() {
  _r="$T/r6"; mkdir -p "$_r"
  sh "$INSTALL" "$_r" >/dev/null 2>&1 || fail "R6: seed install failed"
  _rcfg="$_r/.harness/harness.config.yaml"
  grep -Eq '^feedback:' "$_rcfg" || fail "R6: setup failed — no feedback: block present after seed"
  _rout="$T/r6.out"
  sh "$INSTALL" "$_r" >"$_rout" 2>/dev/null || fail "R6: second install failed"
  notice_lines "$_rout" "github.com/araozmd/harness-sdd" "$_rcfg" > "$T/r6-notice.txt"
  [ ! -s "$T/r6-notice.txt" ] \
    || fail "R6: re-run on a config that already carries the feedback: block printed a notice: $(cat "$T/r6-notice.txt")"
  ! grep -qF 'feedback.enabled: false' "$_rout" \
    || fail "R6: re-run on a config that already carries the feedback: block printed the notice phrase somewhere on stdout"

  # One-line flow form (the operator's opt-out, `feedback: { enabled: false }`) must be
  # recognized as "already present" too — a presence-check regex narrowed to the block
  # form alone (reviewer round-1 M4) misses this shape and prints a spurious notice
  # telling an operator who already opted out to opt out, naming an empty repo.
  _rf="$T/r6-flow"; mkdir -p "$_rf"
  sh "$INSTALL" "$_rf" >/dev/null 2>&1 || fail "R6 flow-form: seed install failed"
  _rfcfg="$_rf/.harness/harness.config.yaml"
  strip_feedback_block "$_rfcfg"
  printf '\nfeedback: { enabled: false }\n' >> "$_rfcfg"
  grep -Eq '^feedback:' "$_rfcfg" \
    || fail "R6 flow-form: setup failed — no column-0 feedback: line present after fixture write"
  _rfout="$T/r6-flow.out"
  sh "$INSTALL" "$_rf" >"$_rfout" 2>/dev/null || fail "R6 flow-form: second install failed"
  notice_lines "$_rfout" "github.com/araozmd/harness-sdd" "$_rfcfg" > "$T/r6-flow-notice.txt"
  [ ! -s "$T/r6-flow-notice.txt" ] \
    || fail "R6 flow-form: re-run on a config carrying the one-line flow-form feedback: { enabled: false } printed a notice: $(cat "$T/r6-flow-notice.txt")"
  ! grep -qF 'feedback.enabled: false' "$_rfout" \
    || fail "R6 flow-form: re-run on a config carrying the one-line flow-form feedback: block printed the notice phrase somewhere on stdout"

  pass "re-run on a config that already carries the feedback: block, in either the block form or the one-line flow form, prints zero notice lines (R6) [test_no_notice_when_present]"
}

# ── R7 ──────────────────────────────────────────────────────────────────────────────────
# fixture <name> — a COPY of the source tree (never the working tree), matching
# tests/test_self_mode.sh's shape (lesson: --self must run against an isolated copy).
fixture() {
  _fx="$T/$1"
  mkdir -p "$_fx"
  for _e in "$SRC"/* "$SRC"/.claude "$SRC"/.codex "$SRC"/.agents "$SRC"/.escalation-arming; do
    [ -e "$_e" ] || continue
    case "$(basename "$_e")" in .git|node_modules) continue ;; esac
    cp -R "$_e" "$_fx/" 2>/dev/null || true
  done
  printf '%s\n' "$_fx"
}

test_self_mode_silent_and_config_untouched() {
  _fx="$(fixture r7-self)"
  cp "$_fx/harness.config.yaml" "$T/r7-before.txt"
  _out="$T/r7.out"
  sh "$_fx/harness-install.sh" --self >"$_out" 2>&1 \
    || { cat "$_out" >&2; fail "R7: --self exited non-zero"; }
  cmp -s "$T/r7-before.txt" "$_fx/harness.config.yaml" \
    || fail "R7: --self left the source harness.config.yaml NOT byte-identical: $(diff "$T/r7-before.txt" "$_fx/harness.config.yaml" | head -n 8)"
  ! grep -qF 'feedback.enabled: false' "$_out" \
    || fail "R7: --self printed a feedback notice line, expected none"
  pass "--self prints no feedback notice and leaves the source harness.config.yaml byte-identical (R7) [test_self_mode_silent_and_config_untouched]"
}

# ── R8 ──────────────────────────────────────────────────────────────────────────────────
test_cascade_per_target_seed_and_notice() {
  _u="$T/r8-umbrella"; mkdir -p "$_u"
  # child-a: a fresh git child, never installed before the cascade.
  mkdir -p "$_u/child-a/.git"
  # child-b: already carries the feedback: block (via a prior single-target install) —
  # the cascade must neither re-seed nor notice it.
  mkdir -p "$_u/child-b/.git"
  sh "$INSTALL" "$_u/child-b" >/dev/null 2>&1 || fail "R8: setup single-target install for child-b failed"
  grep -Eq '^feedback:' "$_u/child-b/.harness/harness.config.yaml" \
    || fail "R8: setup failed — child-b has no feedback: block before the cascade"

  _out="$T/r8.out"
  sh "$INSTALL" --umbrella "$_u" >"$_out" 2>/dev/null || fail "R8: umbrella cascade failed"

  for _t in "$_u" "$_u/child-a"; do
    _cfg="$_t/.harness/harness.config.yaml"
    grep -Eq '^feedback:' "$_cfg" || fail "R8: $_t was not seeded a feedback: block"
    notice_lines "$_out" "github.com/araozmd/harness-sdd" "$_cfg" > "$T/r8-notice-$(basename "$_t" | tr -c 'A-Za-z0-9' _).txt"
    [ "$(wc -l < "$T/r8-notice-$(basename "$_t" | tr -c 'A-Za-z0-9' _).txt")" = "1" ] \
      || fail "R8: expected exactly 1 notice line naming $_cfg"
  done

  notice_lines "$_out" "github.com/araozmd/harness-sdd" "$_u/child-b/.harness/harness.config.yaml" > "$T/r8-notice-child-b.txt"
  [ ! -s "$T/r8-notice-child-b.txt" ] \
    || fail "R8: child-b already carried a feedback: block but still got a notice line"

  [ "$(grep -cF 'feedback.enabled: false' "$_out")" = "2" ] \
    || fail "R8: expected exactly 2 notice lines total across the cascade (coordinator + child-a), got $(grep -cF 'feedback.enabled: false' "$_out")"

  pass "umbrella cascade seeds each un-seeded target's own feedback: block and notices per-target path, skipping an already-seeded child (R8) [test_cascade_per_target_seed_and_notice]"
}

# ── R9 / R10 (docs) ──────────────────────────────────────────────────────────────────────
# _section <heading-literal> <file> — from the column-0 heading through, but excluding,
# the next column-0 `## ` heading or EOF. Uses index()==1 (no regex) so backticks/parens/
# em-dashes in the heading need no escaping. FENCE-AWARE (tests/lib/fence.awk, E99-F131,
# enforced repo-wide by tests/test_change_size.sh R9d): docs/INSTALL.md's feedback section
# carries a fenced YAML example, so a bare heading-reset toggle would misread a column-0
# '#'-looking line inside a fence as the next heading and truncate the section.
FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"
_section() {
  awk -v h="$1" "$FENCE_AWK"'
    fence_delim($0) { if (k) print; next }
    !fence && index($0,h)==1 { k=1; print; next }
    !fence && k && /^## / { exit }
    k { print }
  ' "$2"
}

# folded_section <heading-literal> <file> — the extracted span, newlines folded to single
# spaces and whitespace runs squeezed, so a token pair that happens to wrap across a
# markdown line (indentation, list continuation) still matches without depending on
# today's exact wrap point (lesson 2026-09-17).
folded_section() {
  _section "$1" "$2" | tr '\n' ' ' | tr -s ' '
}

test_install_doc_contract() {
  _section '## Harness feedback (`feedback:`) — on by default' "$SRC/docs/INSTALL.md" > "$T/install-feedback-section.txt"
  [ -s "$T/install-feedback-section.txt" ] \
    || fail "R9: could not extract the '## Harness feedback' section from docs/INSTALL.md — heading anchor is stale"
  _isec="$(folded_section '## Harness feedback (`feedback:`) — on by default' "$SRC/docs/INSTALL.md")"

  printf '%s' "$_isec" | grep -qF 'only** the bare, unquoted, lower-case token `true` enables reporting' \
    || fail "R9: INSTALL.md feedback section does not state that only the bare token true enables"
  printf '%s' "$_isec" | grep -qF '[HOST/]OWNER/REPO' \
    || fail "R9: INSTALL.md feedback section is missing the [HOST/]OWNER/REPO grammar"
  printf '%s' "$_isec" | grep -qF '2 or 3 `/`-separated parts, each non-empty and matching `[A-Za-z0-9._-]+`' \
    || fail "R9: INSTALL.md feedback section does not state the 2-or-3-parts grammar"
  printf '%s' "$_isec" | grep -qF 'an omitted HOST always means `github.com`' \
    || fail "R9: INSTALL.md feedback section does not state that an omitted HOST means github.com"
  printf '%s' "$_isec" | grep -qF 'is malformed and turns reporting **off**' \
    || fail "R9: INSTALL.md feedback section does not state that a malformed repo turns reporting off"
  printf '%s' "$_isec" | grep -qF '`0` means nothing is filed upstream in that session' \
    || fail "R9: INSTALL.md feedback section does not state the max_per_session=0 semantics"
  printf '%s' "$_isec" | grep -qF 'resolves to `3`' \
    || fail "R9: INSTALL.md feedback section does not state that an invalid max_per_session resolves to 3"
  printf '%s' "$_isec" | grep -qF 'Opting out means `enabled: false`, not deleting the block' \
    || fail "R9: INSTALL.md feedback section does not state that the opt-out is enabled: false, not deleting the block"
  printf '%s' "$_isec" | grep -qF 'A missing block is **re-seeded on** (with a fresh notice) on the next upgrade' \
    || fail "R9: INSTALL.md feedback section does not state that a deleted block is re-seeded on the next upgrade"
  pass "docs/INSTALL.md feedback section states the full resolution contract (R9) [test_install_doc_contract]"
}

test_umbrella_resolution_docs() {
  _isec="$(folded_section '## Harness feedback (`feedback:`) — on by default' "$SRC/docs/INSTALL.md")"
  printf '%s' "$_isec" | grep -qF '`feedback:` block governs sessions rooted in that child' \
    || fail "R10: INSTALL.md feedback section does not state that the child's own block governs"
  printf '%s' "$_isec" | grep -qF 'no inheritance from the coordinator' \
    || fail "R10: INSTALL.md feedback section does not state there is no inheritance from the coordinator"
  printf '%s' "$_isec" | grep -qF 'under the governing harness dir' \
    || fail "R10: INSTALL.md feedback section does not name the fallback dir as under the governing harness dir"
  printf '%s' "$_isec" | grep -qF '`progress/feedback/`' \
    || fail "R10: INSTALL.md feedback section does not name progress/feedback/ as the fallback dir"

  _lsec="$(folded_section '## The three layers' "$SRC/docs/CONFIG-LAYERING.md")"
  [ -n "$_lsec" ] || fail "R10: could not extract '## The three layers' from docs/CONFIG-LAYERING.md — heading anchor is stale"
  printf '%s' "$_lsec" | grep -qF '`feedback:` block governs sessions rooted in that child' \
    || fail "R10: CONFIG-LAYERING.md does not state that the child's own block governs"
  printf '%s' "$_lsec" | grep -qF '**not inherited**' \
    || fail "R10: CONFIG-LAYERING.md does not state that feedback.* is not inherited in an umbrella"

  pass "docs/INSTALL.md and docs/CONFIG-LAYERING.md both state the child-governs umbrella rule; INSTALL.md names the fallback dir (R10) [test_umbrella_resolution_docs]"
}

# ── R11 ─────────────────────────────────────────────────────────────────────────────────
changelog_release_section() {
  awk '
    /^## \[0\.85\.0\]/ { k=1; print; next }
    k && /^## \[/ { exit }
    k { print }
  ' "$SRC/CHANGELOG.md"
}

test_version_and_changelog() {
  [ "$(cat "$SRC/VERSION")" = "0.85.0" ] || fail "R11: VERSION is not 0.85.0 (got $(cat "$SRC/VERSION"))"
  changelog_release_section > "$T/changelog-release.txt"
  [ -s "$T/changelog-release.txt" ] \
    || fail "R11: could not extract the ## [0.85.0] CHANGELOG section — heading anchor is stale"
  for _tok in 'feedback' 'enabled: true' 'github.com/araozmd/harness-sdd' 'notice' 'feedback.enabled: false'; do
    grep -qF "$_tok" "$T/changelog-release.txt" \
      || fail "R11: CHANGELOG.md's [0.85.0] section is missing '$_tok'"
  done
  pass "VERSION is 0.85.0 and CHANGELOG's [0.85.0] section names the block, its default-on enabled: true, the default repo, the notice, and the opt-out (R11) [test_version_and_changelog]"
}

# ── non-functional: suite itself is +x, POSIX sh (E32-F01 tests.md) ───────────────────
test_suite_is_executable() {
  [ -x "$SRC/tests/test_feedback_config.sh" ] \
    || fail "non-functional: tests/test_feedback_config.sh is not executable"
  pass "tests/test_feedback_config.sh is executable (non-functional) [test_suite_is_executable]"
}

# ── run ─────────────────────────────────────────────────────────────────────────────────
test_seed_template_block
test_fresh_install_seeds_block
test_template_and_heredoc_converge
test_seeded_migrated_converge
test_existing_block_preserved
test_notice_on_seed
test_no_notice_when_present
test_self_mode_silent_and_config_untouched
test_cascade_per_target_seed_and_notice
test_install_doc_contract
test_umbrella_resolution_docs
test_version_and_changelog
test_suite_is_executable

echo "all tests passed"
