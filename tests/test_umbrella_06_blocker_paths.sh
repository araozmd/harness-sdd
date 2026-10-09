#!/bin/sh
set -eu
. "$(dirname "$0")/lib/umbrella/common.sh"
. "$SRC/tests/lib/umbrella/audit.sh"
. "$SRC/tests/lib/umbrella/thin.sh"
. "$SRC/tests/lib/umbrella/migration.sh"

# ── R3: blocker paths do not depend on delimiters in the absolute parent path ─────────
# thin_blocker_paths_ignore_parent_delimiters
#
# `diff -q` describes changes as human prose. Both separators it uses (` and ` for a
# two-sided difference, `: ` for an Only-in difference) and its record newline are legal
# pathname bytes. The fixture exercises a one-sided file, a two-sided differing file and a
# two-sided symlink with literal newlines, so encoding only one producer cannot satisfy it.
# It also puts the same FIFO on both sides: `diff` opens matching named pipes and waits for a
# writer, so the bounded subprocess proves special nodes are named without being read. Exact
# names must be derived while each pathname is still one quoted shell value.
F04P="$AU/f04p parent and pair: marker"
f04_fullchild "$F04P" kid
KP4="$F04P/kid/.harness"
printf '\na two-sided edit below a delimiter-bearing parent\n' >> "$KP4/agents/builder.md"
mkdir -p "$KP4/docs/sub"
mkdir -p "$F04P/.harness/docs/sub"
printf 'a child-only file whose own name carries diff syntax\n' > "$KP4/docs/sub/note: local.md"
F04P_NL_ONE_REL="$(printf 'docs/sub/one-sided-line\nbreak.md')"
F04P_NL_ONE_SHOW='docs/sub/one-sided-line\nbreak.md'
F04P_NL_TWO_REL="$(printf 'docs/sub/two-sided-line\nbreak.md')"
F04P_NL_TWO_SHOW='docs/sub/two-sided-line\nbreak.md'
F04P_NL_LINK_REL="$(printf 'docs/sub/link-line\nbreak.md')"
F04P_NL_LINK_SHOW='docs/sub/link-line\nbreak.md'
printf 'a child-only file whose name contains a literal newline\n' > "$KP4/$F04P_NL_ONE_REL"
printf 'child bytes under a two-sided literal-newline name\n' > "$KP4/$F04P_NL_TWO_REL"
printf 'umbrella bytes under a two-sided literal-newline name\n' > "$F04P/.harness/$F04P_NL_TWO_REL"
printf 'same link target bytes\n' > "$KP4/docs/sub/link-target.md"
cp "$KP4/docs/sub/link-target.md" "$F04P/.harness/docs/sub/link-target.md"
ln -s link-target.md "$KP4/$F04P_NL_LINK_REL"
ln -s link-target.md "$F04P/.harness/$F04P_NL_LINK_REL"
mkfifo "$KP4/docs/sub/review-fifo" "$F04P/.harness/docs/sub/review-fifo"
printf 'a file where the umbrella holds a directory\n' > "$KP4/docs/type-clash"
mkdir -p "$F04P/.harness/docs/type-clash"
[ -d "$KP4/docs/sub" ] && [ -d "$F04P/.harness/docs/sub" ] \
  || fail "R3 delimiter-parent control: docs/sub must exist on both sides so the filename, not its parent directory, is the one-sided path"
[ ! -e "$F04P/.harness/docs/sub/note: local.md" ] \
  || fail "R3 delimiter-parent control: note: local.md exists on both sides, so the Only-in filename parser is not exercised"
[ -f "$KP4/$F04P_NL_ONE_REL" ] && [ ! -e "$F04P/.harness/$F04P_NL_ONE_REL" ] \
  || fail "R3 newline control: the literal-newline path must exist only in the child"
[ -f "$KP4/$F04P_NL_TWO_REL" ] && [ -f "$F04P/.harness/$F04P_NL_TWO_REL" ] \
  && ! diff -q "$KP4/$F04P_NL_TWO_REL" "$F04P/.harness/$F04P_NL_TWO_REL" >/dev/null 2>&1 \
  || fail "R3 newline control: the two-sided literal-newline files must both exist and differ"
[ -L "$KP4/$F04P_NL_LINK_REL" ] && [ -L "$F04P/.harness/$F04P_NL_LINK_REL" ] \
  || fail "R3 newline control: the literal-newline symlink must exist on both sides"
[ -p "$KP4/docs/sub/review-fifo" ] && [ -p "$F04P/.harness/docs/sub/review-fifo" ] \
  || fail "R2 special-node control: review-fifo must be a named pipe on both sides"
[ -f "$KP4/docs/type-clash" ] && [ -d "$F04P/.harness/docs/type-clash" ] \
  || fail "R3 type-clash control: docs/type-clash must be a child file and an umbrella directory"
F04P_OUT="$(F04P_CODEX_HOME="$F04P/.ch" F04P_HOME="$F04P/.home" \
  python3 - "$SRC/harness-install.sh" "$F04P/kid" <<'PY'
import os, subprocess, sys
env = os.environ.copy()
env["CODEX_HOME"] = env.pop("F04P_CODEX_HOME")
env["HOME"] = env.pop("F04P_HOME")
try:
    result = subprocess.run(
        ["sh", sys.argv[1], "--agents=claude", "--thin", sys.argv[2]],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        sys.stdout.buffer.write(exc.stdout)
    print("TIMEOUT: installer blocked while comparing a named pipe")
    sys.exit(124)
sys.stdout.buffer.write(result.stdout)
sys.exit(result.returncode)
PY
)" && F04P_RC=0 || F04P_RC=$?
[ "$F04P_RC" = "0" ] || fail "R3 delimiter-parent: single-target --thin exited $F04P_RC: $F04P_OUT"
for _p in agents/builder.md 'docs/sub/note: local.md' docs/sub/review-fifo docs/type-clash; do
  printf '%s\n' 2>/dev/null "$F04P_OUT" | grep -qF "differs: $_p" \
    || fail "R3: the blocker was reduced to its tier instead of naming the exact path $_p: $F04P_OUT"
done
for _p in "$F04P_NL_ONE_SHOW" "$F04P_NL_TWO_SHOW" "$F04P_NL_LINK_SHOW"; do
  printf '%s\n' 2>/dev/null "$F04P_OUT" | grep -qF "differs: $_p" \
    || fail "R3: the literal-newline blocker was split across output records instead of being named once as $_p: $F04P_OUT"
done
f04_no_stub_in_tier "$KP4" "R3 (delimiter-bearing absolute parents must not weaken blocker reporting)"
pass "R3 thin_blocker_paths_ignore_parent_delimiters — exact paths are derived independently of diff's prose separators"

# RACE DEFENCE, deterministically: mutate the initial unsafe-node sweep so that, on `docs`, it
# creates the same FIFO on both sides immediately AFTER its observation point and then reports
# nothing. The exact walk must signal that it observed the new FIFO and force the authoritative
# recursive comparison onto private sanitised copies. Naming it at the leaf is not enough: the
# later `diff -rq` over the originals opens the matching pipes and hangs. Keep this bounded
# independently of the stable-node control above.
F04P_RACESRC="$AU/f04p-race-src"
mkdir -p "$F04P_RACESRC"
for _md in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
           harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
  [ -e "$SRC/$_md" ] && cp -R "$SRC/$_md" "$F04P_RACESRC/"
done
awk '
  /^_ptb_unsafe_walk\(\) \($/ {
    print "_ptb_unsafe_walk() ("
    print "  # mutation: introduce a matching FIFO immediately after the sweep"
    print "  case \"$1\" in"
    print "    */docs)"
    print "      mkdir -p \"$1/sub\" \"$2/sub\" || exit 1"
    print "      rm -f \"$1/sub/post-sweep-fifo\" \"$2/sub/post-sweep-fifo\" || exit 1"
    print "      mkfifo \"$1/sub/post-sweep-fifo\" \"$2/sub/post-sweep-fifo\" || exit 1"
    print "      ;;"
    print "  esac"
    print "  return 0"
    skip = 1
    next
  }
  skip && /^\)$/ { print; skip = 0; next }
  !skip { print }
' "$F04P_RACESRC/harness-install.sh" > "$F04P_RACESRC/harness-install.mut"
mv "$F04P_RACESRC/harness-install.mut" "$F04P_RACESRC/harness-install.sh"
[ "$(grep -c 'mutation: introduce a matching FIFO immediately after the sweep' "$F04P_RACESRC/harness-install.sh")" = "1" ] \
  || fail "R2 race control: unsafe-sweep mutation did not apply exactly once"
# BSD `diff -r` may reject a FIFO without opening it while GNU diff can open it. Make the
# forbidden call deterministic across hosts: the shim records only an authoritative recursive
# comparison that can still see the post-sweep FIFO, then returns trouble. A correct repair
# hands it sanitised copies and falls through to the real implementation.
F04P_RACE_BIN="$AU/f04p-race-bin"
F04P_RACE_MARKER="$AU/f04p-unsafe-recursive-diff"
F04P_REAL_DIFF="$(command -v diff)"
mkdir -p "$F04P_RACE_BIN"
cat > "$F04P_RACE_BIN/diff" <<'SH'
#!/bin/sh
if [ "$1" = "-rq" ] \
  && { [ -p "$2/sub/post-sweep-fifo" ] || [ -p "$3/sub/post-sweep-fifo" ]; }; then
  : > "$F04P_RACE_MARKER"
  exit 97
fi
exec "$F04P_REAL_DIFF" "$@"
SH
chmod +x "$F04P_RACE_BIN/diff"
F04P_RACE_OUT="$(F04P_CODEX_HOME="$F04P/.ch" F04P_HOME="$F04P/.home" \
  F04P_RACE_PATH="$F04P_RACE_BIN:$PATH" F04P_RACE_MARKER="$F04P_RACE_MARKER" \
  F04P_REAL_DIFF="$F04P_REAL_DIFF" \
  python3 - "$F04P_RACESRC/harness-install.sh" "$F04P/kid" <<'PY'
import os, subprocess, sys
env = os.environ.copy()
env["CODEX_HOME"] = env.pop("F04P_CODEX_HOME")
env["HOME"] = env.pop("F04P_HOME")
env["PATH"] = env.pop("F04P_RACE_PATH")
try:
    result = subprocess.run(
        ["sh", sys.argv[1], "--agents=claude", "--thin", sys.argv[2]],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
except subprocess.TimeoutExpired as exc:
    if exc.stdout:
        sys.stdout.buffer.write(exc.stdout)
    print("TIMEOUT: recursive diff opened a FIFO first observed by the exact walk")
    sys.exit(124)
sys.stdout.buffer.write(result.stdout)
sys.exit(result.returncode)
PY
)" && F04P_RACE_RC=0 || F04P_RACE_RC=$?
[ "$F04P_RACE_RC" = "0" ] \
  || fail "R2 race defence: single-target --thin exited $F04P_RACE_RC: $F04P_RACE_OUT"
[ ! -e "$F04P_RACE_MARKER" ] \
  || fail "R2 race defence: authoritative recursive diff still received originals containing a FIFO first observed by the exact walk: $F04P_RACE_OUT"
printf '%s\n' 2>/dev/null "$F04P_RACE_OUT" | grep -qF 'differs: docs/sub/post-sweep-fifo' \
  || fail "R2/R3 race defence: an unsafe node missed by the initial sweep was not named exactly: $F04P_RACE_OUT"
f04_no_stub_in_tier "$KP4" "R2 race defence (a special node first observed later must block without being opened)"
pass "R2 thin_post_sweep_special_node_is_sanitised — an exact-walk special-node signal moves recursive diff to private safe copies"

# The independent name walk is NOT the safety decision. Neutralise it in a real installer
# source: `diff` still exits non-zero, and the conversion must remain blocked even though the
# best available diagnostic falls back to the tier root. This pins the non-empty check on the
# Only-in arm; without it, the line is skipped, no blocker is emitted, and the child converts.
F04P_MUTSRC="$AU/f04p-mut-src"
mkdir -p "$F04P_MUTSRC"
for _md in harness-install.sh VERSION AGENTS.md init.sh agents docs store tools specs \
           harness.config.yaml umbrella.manifest.example.yaml umbrella.gitignore.example; do
  [ -e "$SRC/$_md" ] && cp -R "$SRC/$_md" "$F04P_MUTSRC/"
done
awk '
  { print }
  $0 == "_ptb_exact_walk() (" { print "  exit 0 # mutation: exact one-sided name producer neutralised" }
' "$F04P_MUTSRC/harness-install.sh" > "$F04P_MUTSRC/harness-install.mut"
mv "$F04P_MUTSRC/harness-install.mut" "$F04P_MUTSRC/harness-install.sh"
[ "$(grep -c 'mutation: exact one-sided name producer neutralised' "$F04P_MUTSRC/harness-install.sh")" = "1" ] \
  || fail "R2 one-sided fail-closed control: the doctored installer did not neutralise exactly one helper"
mkdir -p "$KP4/docs/sub" "$F04P/.harness/docs/sub"
printf 'reseeded for the fail-closed mutation\n' > "$KP4/docs/sub/note: local.md"
[ -f "$KP4/docs/sub/note: local.md" ] \
  || fail "R2 one-sided fail-closed control: the one-sided file disappeared before the mutation run"
[ ! -e "$F04P/.harness/docs/sub/note: local.md" ] \
  || fail "R2 one-sided fail-closed control: the mutation path is not one-sided"
F04P_MUT_OUT="$(CODEX_HOME="$F04P/.ch" HOME="$F04P/.home" \
  sh "$F04P_MUTSRC/harness-install.sh" --agents=claude --thin "$F04P/kid" 2>&1)" && F04P_MUT_RC=0 || F04P_MUT_RC=$?
[ "$F04P_MUT_RC" = "0" ] || fail "R2 one-sided fail-closed mutation exited $F04P_MUT_RC: $F04P_MUT_OUT"
printf '%s\n' 2>/dev/null "$F04P_MUT_OUT" | grep -q 'CONVERTED to the thin layout' \
  && fail "R2: neutralising the one-sided name producer let a diff-confirmed one-sided child convert: $F04P_MUT_OUT"
f04_no_stub_in_tier "$KP4" "R2 (a silent one-sided name producer must fall back closed, never permit conversion)"
pass "R2 thin_one_sided_name_failure_stays_closed — a silent exact-name producer falls back to the tier root and never converts"

# A final negative probe is not a suite failure.
exit 0
