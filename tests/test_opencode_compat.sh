#!/bin/sh
# E31-F03 R9-R12: the OpenCode 2.x-safe model helper (hermetic, stub `opencode`), its parse
# parity with 1.x, the INSTALL.md 2.x material, and the 0.97.0 release contract.
# No real opencode binary is ever run here: every call goes through a stub on PATH.
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok - $*"; }

HELPER="$SRC/tools/opencode-model-helper.sh"
FIXTURE="$SRC/tests/fixtures/opencode-2.0.32/models.txt"
[ -f "$HELPER" ] && [ -s "$FIXTURE" ] || fail "helper or 2.0.32 models fixture missing"

# Stub `opencode`: logs every call as [arg][arg]... (so an EMPTY argument is visible), prints
# $STUB_VERSION for --version (exit $STUB_VERSION_RC) and the $STUB_MODELS_FILE for `models`.
# Like the real 1.x, it rejects --standalone with usage text on stdout and rc=1.
BIN="$T/bin"; mkdir -p "$BIN"
cat > "$BIN/opencode" <<'STUB'
#!/bin/sh
{ for a in "$@"; do printf '[%s]' "$a"; done; echo; } >> "$STUB_LOG"
case "${1:-}" in
  --version) printf '%s\n' "$STUB_VERSION"; exit "${STUB_VERSION_RC:-0}" ;;
  models)
    if [ "${STUB_REJECT_STANDALONE:-0}" = 1 ]; then
      for a in "$@"; do
        if [ "$a" = --standalone ]; then
          echo "opencode models [provider]"; echo "list all available models"; exit 1
        fi
      done
    fi
    cat "$STUB_MODELS_FILE" ;;
  *) echo "unexpected verb: $*" >&2; exit 9 ;;
esac
STUB
chmod +x "$BIN/opencode"

H="$T/home"; mkdir -p "$H"
CFG="$T/harness.config.yaml"; printf 'models:\n  orchestrator: reasoning\n' > "$CFG"
CFG_BEFORE="$(cat "$CFG")"

# run_helper <version> <version-rc> -> stdout in $T/out, argv log in $T/log
run_helper() {
  : > "$T/log"
  case "$1" in 1.*|0.*) _rej=1 ;; *) _rej=0 ;; esac   # only a 1.x/0.x binary rejects --standalone
  HOME="$H" PATH="$BIN:$PATH" STUB_LOG="$T/log" STUB_VERSION="$1" STUB_VERSION_RC="$2" \
    STUB_REJECT_STANDALONE="$_rej" STUB_MODELS_FILE="$FIXTURE" \
    sh "$HELPER" "$CFG" > "$T/out" 2>"$T/err" || true
}

# ── R9: --standalone iff the major is >= 2 ───────────────────────────────────────────────
# The rows reuse the version strings of tests/test_codex_native.sh's `ocgate` table, so the
# two parsers (Python gate, sh helper) are driven by one table. Where they differ it is on
# purpose: the gate SKIPS an unsupported major, the helper only needs "is it >= 2".
#   version                rc  expected models argv
helper_flag_by_major() {
  while IFS='|' read -r ver rc want; do
    run_helper "$ver" "$rc"
    got="$(grep '^\[models\]' "$T/log" || true)"
    [ "$got" = "$want" ] || fail "R9: --version '$ver' (rc $rc) ran '$got', expected '$want'"
    n="$(grep -c '^\[models\]' "$T/log" || true)"
    [ "$n" = 1 ] || fail "R9: '$ver' made $n models calls, expected exactly 1"
    grep -qx '\[--version\]' "$T/log" || fail "R9: '$ver': the helper never asked for --version"
  done <<'TABLE'
1.18.35|0|[models]
1.18.31|0|[models]
opencode v2.0.32|0|[models][--standalone]
10.1.2|0|[models][--standalone]
3.0.0|0|[models][--standalone]
0.9.1|0|[models]
garbage|0|[models]
|0|[models]
1.2.3|3|[models]
opencode v2.0.32|3|[models]
opencode v2.0.32|1|[models]
TABLE
  ok "helper_flag_by_major (R9)"
}
helper_flag_by_major

# A line of noise before the version must not change the major (first X.Y.Z wins, as in ocgate).
run_helper 'build 1 of opencode v2.0.32' 0
[ "$(grep '^\[models\]' "$T/log")" = '[models][--standalone]' ] \
  || fail "R9: the first X.Y.Z must decide the major even after other digits"
ok "helper_major_is_first_semver (R9)"

# ── R10: the 2.0.32 `models` output yields the same suggestions as 1.x ────────────────────
# The tier mapping and the pin snippet, from "Suggested harness tier mapping" to the end.
tail_block() { awk '/^Suggested harness tier mapping/{k=1} k' "$1"; }
run_helper 'opencode v2.0.32' 0; cp "$T/out" "$T/out2"; tail_block "$T/out2" > "$T/b2"
run_helper '1.18.35' 0;          cp "$T/out" "$T/out1"; tail_block "$T/out1" > "$T/b1"
[ -s "$T/b1" ] && [ -s "$T/b2" ] || fail "R10: a suggestion block is empty (the helper printed no mapping)"
cmp -s "$T/b1" "$T/b2" || { diff "$T/b1" "$T/b2" >&2 || true; fail "R10: the 2.x and 1.x runs suggest different pins for the same model list"; }
for pin in 'reasoning → openrouter/~anthropic/claude-opus-latest' \
           'standard  → openrouter/~anthropic/claude-fable-latest' \
           'cheap     → opencode/deepseek-v4.1-flash-free' \
           'pin.opencode.reasoning: "openrouter/~anthropic/claude-opus-latest"' \
           'pin.opencode.standard:  "openrouter/~anthropic/claude-fable-latest"' \
           'pin.opencode.cheap:     "opencode/deepseek-v4.1-flash-free"'; do
  grep -qF "$pin" "$T/b2" || fail "R10: expected suggestion missing from the 2.x run: $pin"
done
# The listing itself is passed through untouched (no prefix stripping, no --verbose reshaping).
head -n 24 "$T/out2" | grep -qxF 'opencode/big-pickle' || fail "R10: the 2.x model listing was reshaped"
grep -qxF 'openrouter/openai/gpt-5-mini' "$T/out2" || fail "R10: the last fixture model is missing from the listing"
# The helper must not write the config on a dry run, and leaves $HOME untouched.
[ "$(cat "$CFG")" = "$CFG_BEFORE" ] || fail "R10: the dry run modified the config file"
[ -z "$(ls -A "$H")" ] || fail "R10: the helper wrote into HOME"
ok "helper_parse_parity (R10)"

# ── R11: INSTALL.md states the 2.x facts, each in the section that owns it ────────────────
INSTALL="$SRC/docs/INSTALL.md"
FENCE_AWK="$(cat "$SRC/tests/lib/fence.awk")"
section() {  # section <heading text> : the body of that heading, fence-aware
  awk "$FENCE_AWK"'
    fence_delim($0) { if (keep) print; next }
    !fence && /^#+ / { keep = (index($0, h) > 0); next }
    keep' h="$1" "$INSTALL" | tr '\n' ' '
}
SUP="$(section 'Supported OpenCode versions')"
HLP="$(section 'OpenCode model helper')"
[ -n "$SUP" ] && [ -n "$HLP" ] || fail "R11: a section heading is missing from docs/INSTALL.md"
for v in 1.18.31 1.18.35 2.0.32; do
  printf '%s' "$SUP" | grep -qF "$v" || fail "R11: Supported OpenCode versions does not name $v"
done
printf '%s' "$SUP" | grep -qF 'one layout serves both' || fail "R11: 'one layout serves both' missing"
printf '%s' "$SUP" | grep -qiE 'no flag selects it' || fail "R11: 'no flag selects it' missing"
printf '%s' "$SUP" | grep -qE 'serve --service.{0,200}opencode service stop' \
  || fail "R11: the 2.x background service is not paired with 'opencode service stop'"
printf '%s' "$SUP" | grep -qE 'first query may be empty' || fail "R11: the cold first query is not stated"
printf '%s' "$HLP" | grep -qE '2\.x[^.]{0,60}opencode models --standalone' \
  || fail "R11: the model helper section does not say 2.x gets 'opencode models --standalone'"
ok "install_doc_opencode_2x (R11)"

# ── R12: 0.97.0 MINOR release ─────────────────────────────────────────────────────────────
VER="$(tr -d '[:space:]' < "$SRC/VERSION")"
NEWEST="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "$SRC/CHANGELOG.md" | head -n 1)"
[ "$VER" = "$NEWEST" ] || fail "R12: VERSION ($VER) is not the newest CHANGELOG heading ($NEWEST)"
# Not pinned to the current top value: any later release keeps this green (progress/lessons.md
# 2026-09-16). The entry below is a historical anchor and the floor is the semver compare.
printf '%s' "$VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "R12: VERSION is not semver: $VER"
[ "$(printf '%s\n0.97.0\n' "$VER" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = 0.97.0 ] \
  || fail "R12: VERSION $VER is below 0.97.0 (the MINOR bump for E31-F03)"
ENTRY="$(awk '/^## \[0\.97\.0\]/{k=1;next} /^## \[/{k=0} k' "$SRC/CHANGELOG.md")"
[ -n "$ENTRY" ] || fail "R12: no '## [0.97.0]' CHANGELOG entry"
for tok in 'OpenCode' '2.x' '--standalone' 'opencode-model-helper' 'live probe'; do
  printf '%s' "$ENTRY" | grep -qF -- "$tok" || fail "R12: the 0.97.0 entry does not mention '$tok'"
done
ok "release_0_97_0 (R12)"
