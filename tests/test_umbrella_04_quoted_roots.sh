#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"

# ══ E99-F13 — a `#` inside a QUOTED umbrella.root is data, not a comment ═══════════════
# `set_umbrella_root` writes this value double-quoted, every time. Both readers stripped
# `#.*$` BEFORE stripping quotes, so `root: "/tmp/umb#root"` parsed as `/tmp/umb` — the
# harness truncating a value it had produced itself. Split out of PR #109 round 7.
#
# Exercised END-TO-END through both real readers, never by re-running a copy of the awk
# here: a parser reimplemented in this file would agree with itself and prove nothing.
#   installer  `_cfg_umbrella_root_value`  — reached by a STANDALONE re-run, the only path
#                                            that reads the config instead of the env var.
#   init.sh    the inline awk               — reached by its umbrella report.
#
# The value under test is never hand-written: the cascade derives and records it. A
# SYMLINKED child is used because that is the layout whose recorded root is ABSOLUTE —
# the relative `../../` an ordinary child gets cannot carry the umbrella path at all.
# BOTH metacharacters in ONE fixture, because the first fix traded one for the other:
# matching to the FIRST closing quote kept the `#` and truncated `/tmp/a"b` to `/tmp/a`
# (Codex #3712741520). A fixture carrying only `#` cannot tell those two apart.
F13E="$AU/f13-elsewhere"
F13U="$AU/f13#hash\"q"              # `#` AND `"` land verbatim in the recorded root
mkdir -p "$F13E/realrepo"
git -C "$F13E/realrepo" init -q .
git -C "$F13E/realrepo" config user.email "test@harness.local"
git -C "$F13E/realrepo" config user.name  "harness test"
echo seed > "$F13E/realrepo/README.md"
git -C "$F13E/realrepo" add -A
git -C "$F13E/realrepo" commit -q -m init
mk_umb "$F13U"
ln -s "$F13E/realrepo" "$F13U/kid-link"
cascade "$F13U"
F13H="$F13E/realrepo/.harness"

# ── FIXTURE PRECONDITIONS ──────────────────────────────────────────────────────────────
# Each one guards an assertion below against passing vacuously.
[ -d "$F13H" ] || fail "E99-F13 setup: the cascade did not install into the symlinked child: $AU_OUT"
F13ROOT="$(sed -n 's/^  root: "\(.*\)"$/\1/p' "$F13H/harness.config.yaml")"
case "$F13ROOT" in
  *'#'*) ;;
  *) fail "E99-F13 precondition: the recorded umbrella.root [$F13ROOT] carries no '#', so nothing below exercises the comment truncation" ;;
esac
case "$F13ROOT" in
  *'"'*) ;;
  *) fail "E99-F13 precondition: the recorded umbrella.root [$F13ROOT] carries no '\"', so nothing below exercises the closing-quote truncation" ;;
esac
[ -f "$F13ROOT/.harness/.harness-version" ] \
  || fail "E99-F13 precondition: the recorded root [$F13ROOT] does not resolve to an installed umbrella body"
is_stub "$F13H/agents/builder.md" \
  || fail "E99-F13 precondition: the cascade left the symlinked child full-copy — the stub assertions below would be vacuous"

# ── READER A: the installer, via a standalone re-run (no HARNESS_UMBRELLA_ROOT) ────────
F13RERUN="$(CODEX_HOME="$AU/f13.ch" HOME="$AU/f13.home" sh "$SRC/harness-install.sh" --agents=claude "$F13E/realrepo" 2>&1)" || true
is_stub "$F13H/agents/builder.md" \
  || fail "E99-F13/installer: a standalone re-run replaced the child's stubs with a full body — _cfg_umbrella_root_value truncated the recorded root at its '#': $F13RERUN"
F13_INST="$(printf '%s\n' "$F13RERUN" | sed -n 's/.*prose body resolved from the umbrella at \(.*\) (stubs.*/\1/p')"
[ "$F13_INST" = "$F13ROOT" ] \
  || fail "E99-F13/installer: reported the umbrella root as [$F13_INST], want [$F13ROOT]: $F13RERUN"

# POSITIVE CONTROL for the assertion above, on a copy of the SAME child: an unresolvable
# root really does make a standalone re-run replace the stubs. Without this, "still a stub"
# would pass even if a re-run could never convert anything, whatever the parser did.
F13C="$AU/f13-control"
cp -R "$F13E/realrepo" "$F13C"
sed 's|^  root: .*|  root: "/nonexistent/umbrella#gone"|' "$F13C/.harness/harness.config.yaml" > "$F13C/.harness/hc.t" \
  && mv "$F13C/.harness/hc.t" "$F13C/.harness/harness.config.yaml"
CODEX_HOME="$AU/f13c.ch" HOME="$AU/f13c.home" sh "$SRC/harness-install.sh" --agents=claude "$F13C" >/dev/null 2>&1 || true
if is_stub "$F13C/.harness/agents/builder.md"; then
  fail "E99-F13 control: a re-run with an UNRESOLVABLE umbrella.root left the stubs in place — the installer assertion above cannot detect the truncation it targets"
fi

# ── READER B: init.sh, via its umbrella report ─────────────────────────────────────────
# `./init.sh`, never `sh ./init.sh`: it declares `#!/usr/bin/env bash` and uses
# `set -o pipefail`, which dash (Ubuntu CI /bin/sh) rejects at line 8.
F13_INIT_OUT="$(cd "$F13H" && ./init.sh 2>&1)" \
  || fail "E99-F13/init.sh: exited non-zero in the thin child: $F13_INIT_OUT"
if printf '%s' "$F13_INIT_OUT" | grep -q 'is not reachable'; then
  fail "E99-F13/init.sh: reported the umbrella unreachable — the recorded root was truncated at its '#': $F13_INIT_OUT"
fi
F13_INIT="$(printf '%s\n' "$F13_INIT_OUT" | sed -n 's/.*harness body resolves from the umbrella at \(.*\) (prose tier is stubs).*/\1/p')"
[ "$F13_INIT" = "$F13ROOT" ] \
  || fail "E99-F13/init.sh: reported the umbrella root as [$F13_INIT], want [$F13ROOT]: $F13_INIT_OUT"

# ── The two readers are duplicated on purpose; pin that they stay identical ────────────
# They have drifted apart once already by being edited separately.
[ "$F13_INST" = "$F13_INIT" ] \
  || fail "E99-F13: the two readers disagree on the SAME config — installer [$F13_INST] vs init.sh [$F13_INIT]"
pass "E99-F13 quoted_umbrella_root_keeps_metachars — both readers round-trip '#' AND '\"' in the recorded root"

# ── A QUOTED value with a TRAILING COMMENT keeps the `#` inside the quotes ─────────────
# Codex #3712898952. The machine never writes this form, so the value is hand-written onto
# a copy of the thin child — but it is pointed at the SAME resolvable umbrella, so both
# readers stay observable exactly as above rather than degrading to an unreachable message.
# Rewritten with awk, not sed: the replacement carries `#` and `"`.
F13T="$AU/f13-quoted-comment"
cp -R "$F13E/realrepo" "$F13T"
awk -v r="$F13ROOT" '/^  root: /{ print "  root: \"" r "\"   # a hand-written trailing comment"; next } { print }' \
  "$F13T/.harness/harness.config.yaml" > "$F13T/.harness/hc.t" \
  && mv "$F13T/.harness/hc.t" "$F13T/.harness/harness.config.yaml"
grep -q '# a hand-written trailing comment' "$F13T/.harness/harness.config.yaml" \
  || fail "E99-F13/quoted+comment precondition: the trailing comment was never written into the config"

F13T_RERUN="$(CODEX_HOME="$AU/f13t.ch" HOME="$AU/f13t.home" sh "$SRC/harness-install.sh" --agents=claude "$F13T" 2>&1)" || true
is_stub "$F13T/.harness/agents/builder.md" \
  || fail "E99-F13/quoted+comment installer: the re-run replaced the stubs — the trailing comment truncated the value at the '#' INSIDE the quotes: $F13T_RERUN"
F13T_INST="$(printf '%s\n' "$F13T_RERUN" | sed -n 's/.*prose body resolved from the umbrella at \(.*\) (stubs.*/\1/p')"
[ "$F13T_INST" = "$F13ROOT" ] \
  || fail "E99-F13/quoted+comment installer: reported [$F13T_INST], want [$F13ROOT]: $F13T_RERUN"

F13T_OUT="$(cd "$F13T/.harness" && ./init.sh 2>&1)" \
  || fail "E99-F13/quoted+comment init.sh: exited non-zero: $F13T_OUT"
F13T_INIT="$(printf '%s\n' "$F13T_OUT" | sed -n 's/.*harness body resolves from the umbrella at \(.*\) (prose tier is stubs).*/\1/p')"
[ "$F13T_INIT" = "$F13ROOT" ] \
  || fail "E99-F13/quoted+comment init.sh: reported [$F13T_INIT], want [$F13ROOT]: $F13T_OUT"
pass "E99-F13 quoted_root_with_trailing_comment — both readers keep the '#' inside the quotes"

# ── A comment containing BOTH `#` and `"` must not extend the value ────────────────────
# This pins the direction of the reader's second pass, which is load-bearing: on
# `root: "<v>" # a " # b` more than one quote qualifies as the closing one, and taking the
# LAST swallows ` # a ` into the value. Read through init.sh's UNREACHABLE message, which
# prints the parsed root verbatim and needs no resolvable path.
#
# Direction in the FIRST pass needs no test: a quote whose remainder is whitespace-only is
# unique by construction, since any earlier candidate has a quote in its remainder.
F13D="$AU/f13-comment-direction"
cp -R "$F13E/realrepo" "$F13D"
awk '/^  root: /{ print "  root: \"/nonexistent/keep#me\" # a \" # b"; next } { print }' \
  "$F13D/.harness/harness.config.yaml" > "$F13D/.harness/hc.t" \
  && mv "$F13D/.harness/hc.t" "$F13D/.harness/harness.config.yaml"
grep -qF 'root: "/nonexistent/keep#me" # a " # b' "$F13D/.harness/harness.config.yaml" \
  || fail "E99-F13/comment-direction precondition: the fixture line was not written as intended"
F13D_OUT="$(cd "$F13D/.harness" && ./init.sh 2>&1)" \
  || fail "E99-F13/comment-direction: init.sh exited non-zero: $F13D_OUT"
printf '%s' "$F13D_OUT" | grep -qF 'umbrella at /nonexistent/keep#me is not reachable' \
  || fail "E99-F13/comment-direction: a quote inside the comment was taken as the closing quote, extending the value: $F13D_OUT"
pass "E99-F13 comment_containing_a_quote_does_not_extend_the_value"

# ── An UNQUOTED value must still honour a trailing ` # comment` ────────────────────────
# The quoted-scalar branch must not have taken that path over, or a hand-edited config
# breaks. Read through init.sh's UNREACHABLE message, which also prints the parsed root —
# so this pins the unquoted branch without needing a second resolvable umbrella.
F13Q="$AU/f13-unquoted"
cp -R "$F13E/realrepo" "$F13Q"
sed 's|^  root: .*|  root: /nonexistent/plain   # a hand-written trailing comment|' \
  "$F13Q/.harness/harness.config.yaml" > "$F13Q/.harness/hc.t" \
  && mv "$F13Q/.harness/hc.t" "$F13Q/.harness/harness.config.yaml"
F13Q_OUT="$(cd "$F13Q/.harness" && ./init.sh 2>&1)" \
  || fail "E99-F13/unquoted: init.sh exited non-zero: $F13Q_OUT"
printf '%s' "$F13Q_OUT" | grep -qF 'umbrella at /nonexistent/plain is not reachable' \
  || fail "E99-F13/unquoted: an unquoted root stopped honouring its trailing comment: $F13Q_OUT"
pass "E99-F13 unquoted_root_still_strips_trailing_comment"

# NOTE ON `2>/dev/null` BELOW: every output assertion here is `printf … | grep -q …`, and
# `grep -q` exits at the first match while `printf` is still writing — which makes bash emit
# `printf: write error: Broken pipe` on the suite's stderr. The redirect silences exactly

# A final negative probe is not a suite failure.
exit 0
