#!/bin/sh
# test_grep_probe.sh — E99-F12: tools/run-tests.sh warns, ONCE and WARN-ONLY, when the
# `grep` it is about to run the suites under drops lines containing invalid UTF-8.
#
# THIS SUITE MAKES NO ASSERTION WITH `grep`. Every check below is a shell `case` pattern
# or an `awk` count. That is not fussiness: the whole point of the feature is that the
# suites run under the same `grep` they would otherwise have to be testing, so an assertion
# written with `grep` would be exactly the blind spot being closed.
#
# The two controls differ in ONE variable — `SHIM_DROP_INVALID` — and the shim is a real
# (if minimal) grep in both settings, asserted as a fixture precondition. A double that
# were simply broken would make "warned" and "did not warn" equally meaningless.

set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t harness-grep-probe)"
trap 'rm -rf "$T"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok - $1"; }

WARN='drops lines containing invalid UTF-8'

command -v python3 >/dev/null 2>&1 \
  || fail "python3 is absent — init.sh hard-fails without it, so this suite does not skip"

# ── Resolve a REAL interpreter BEFORE anything shadows PATH (Codex #3713371931) ────────
# `python3` is very often a pyenv/asdf/rbenv-style shim: a shell script that re-execs
# through a version manager. If the grep double below launched `python3` by NAME, it would
# resolve through the PATH this suite has just shadowed — and any shell script in that
# chain that calls `grep` lands straight back in the double, which launches `python3`
# again. That is an unbounded process chain, and because `tools/run-tests.sh` auto-
# discovers every `tests/test_*.sh`, it would hang the whole gate rather than one suite.
#
# `sys.executable` is the escape hatch: run ONCE here, under the pristine ambient PATH, it
# reports the interpreter binary the shim ultimately exec's. The double then calls that
# absolute path and never consults PATH for an interpreter at all.
PY_REAL="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null || true)"
[ -n "$PY_REAL" ] && [ -x "$PY_REAL" ] \
  || fail "could not resolve a real python3 interpreter (sys.executable=[$PY_REAL])"

# ── The test double: a minimal but REAL grep ──────────────────────────────────────────
# It supports the `-c <pattern>` form the probe uses plus plain matching, reads stdin or
# files, and differs between the two controls ONLY in whether it silently discards lines
# that are not valid UTF-8 — which is precisely what the replacement that motivated this
# feature (ugrep 7.5.0) does under every locale, `LC_ALL=C` included.
mkdir -p "$T/bin"
cat > "$T/bin/grep.py" <<'PY'
import os, re, sys

args = sys.argv[1:]
if "--version" in args:
    if os.environ.get("SHIM_VERSION_FAILS") == "1":
        sys.stderr.write("shimgrep: --version unavailable\n")
        sys.exit(2)
    sys.stdout.write("shimgrep 1.0 (test double)\n")
    sys.exit(0)

count = False
pat = None
files = []
for a in args:
    if a == "-c":
        count = True
    elif a.startswith("-") and len(a) > 1:
        continue
    elif pat is None:
        pat = a
    else:
        files.append(a)

if files:
    data = b"".join(open(f, "rb").read() for f in files)
else:
    data = sys.stdin.buffer.read()

lines = data.split(b"\n")
if lines and lines[-1] == b"":
    lines.pop()

if os.environ.get("SHIM_DROP_INVALID") == "1":
    kept = []
    for line in lines:
        try:
            line.decode("utf-8")
        except UnicodeDecodeError:
            continue
        kept.append(line)
    lines = kept

rx = re.compile((pat or "").encode())
matched = [line for line in lines if rx.search(line)]

if count:
    sys.stdout.write("%d\n" % len(matched))
else:
    for line in matched:
        sys.stdout.buffer.write(line + b"\n")
sys.exit(0 if matched else 1)
PY
# The interpreter is named by ABSOLUTE PATH, and PATH is reset for the child, so nothing
# this double runs can resolve back through the shadowed PATH into the double itself.
cat > "$T/bin/grep" <<EOF
#!/bin/sh
PATH=/usr/bin:/bin
export PATH
exec "$PY_REAL" "$T/bin/grep.py" "\$@"
EOF
chmod +x "$T/bin/grep"

# ── ARM THE TRAP ──────────────────────────────────────────────────────────────────────
# A `python3` planted in the shim dir must be IGNORED by the double. This is not one extra
# case: it is armed for the whole file, so EVERY control and case below doubles as a
# regression test for the recursion above. If the double ever goes back to launching
# `python3` by name, this decoy answers and the suite fails loudly instead of hanging.
printf '#!/bin/sh\necho "the grep double resolved python3 through the shadowed PATH" >&2\nexit 97\n' \
  > "$T/bin/python3"
chmod +x "$T/bin/python3"
_decoy="$(PATH="$T/bin:$PATH" sh -c 'command -v python3' 2>/dev/null || true)"
[ "$_decoy" = "$T/bin/python3" ] \
  || fail "precondition: the decoy python3 does not shadow PATH (resolved [$_decoy]) — every case below would pass without proving the double avoids PATH"

printf '#!/bin/sh\nexit 0\n' > "$T/test_noop.sh"

# run_probe <drop> <version_fails> -> RP_OUT (stdout+stderr) / RP_RC
run_probe() {
  RP_OUT="$(PATH="$T/bin:$PATH" SHIM_DROP_INVALID="$1" SHIM_VERSION_FAILS="$2" \
    sh "$SRC/tools/run-tests.sh" "$T/test_noop.sh" 2>&1)" && RP_RC=0 || RP_RC=$?
}

# ── FIXTURE PRECONDITIONS ─────────────────────────────────────────────────────────────
# Assert the double is faithful in BOTH settings before trusting either control. Run under
# the SHADOWED PATH, exactly as the probe will run it, so these also exercise the decoy.
_keep="$(printf 'a\303(b\n' | PATH="$T/bin:$PATH" SHIM_DROP_INVALID=0 "$T/bin/grep" -c '' || true)"
[ "$_keep" = "1" ] \
  || fail "precondition: the non-dropping shim did not return the invalid-UTF-8 line (got [$_keep]) — it is not a faithful grep, so the negative control proves nothing"
_drop="$(printf 'a\303(b\n' | PATH="$T/bin:$PATH" SHIM_DROP_INVALID=1 "$T/bin/grep" -c '' || true)"
[ "$_drop" = "1" ] \
  && fail "precondition: the dropping shim RETURNED the invalid-UTF-8 line — the positive control cannot fire"
# ...and both settings must agree on an ordinary line, or the "dropping" shim is simply
# broken and every difference below is an artifact rather than the behaviour under test.
for _d in 0 1; do
  _clean="$(printf 'hello\n' | PATH="$T/bin:$PATH" SHIM_DROP_INVALID="$_d" "$T/bin/grep" -c '' || true)"
  [ "$_clean" = "1" ] \
    || fail "precondition: the shim (SHIM_DROP_INVALID=$_d) mishandles a CLEAN line (got [$_clean]) — it is not a grep, it is broken"
done

# ── R1: a grep that drops the line is reported, and the run still succeeds ─────────────
run_probe 1 0
[ "$RP_RC" = "0" ] \
  || fail "R1: a diverging grep FAILED the run (rc=$RP_RC) — the probe is warn-only; init.sh and the gate must never block on it: $RP_OUT"
case "$RP_OUT" in
  *"$WARN"*) ;;
  *) fail "R1: no warning for a grep that drops invalid UTF-8: $RP_OUT" ;;
esac
pass "E99-F12 R1 diverging_grep_is_reported_and_never_fails_the_run"

# ── R2: exactly one line, once per run ────────────────────────────────────────────────
# `run-tests.sh` is the hot path for the Reviewer, which reads its output every round.
_n="$(printf '%s\n' "$RP_OUT" | awk -v w="$WARN" 'index($0, w) { n++ } END { print n + 0 }')"
[ "$_n" = "1" ] \
  || fail "R2: the warning appeared $_n time(s), want exactly 1: $RP_OUT"
pass "E99-F12 R2 warning_is_emitted_once_per_run"

# ── R3: the version is quoted when readable ───────────────────────────────────────────
# This is ALSO the positive control for R4's absence assertion below: without it, "no
# version bracket" would pass even if the probe never printed one under any condition.
case "$RP_OUT" in
  *"[reports: shimgrep 1.0 (test double)]"*) ;;
  *) fail "R3: the readable version was not quoted in the warning, so R4's absence check would prove nothing: $RP_OUT" ;;
esac
pass "E99-F12 R3 readable_version_is_quoted"

# ── R4: an UNREADABLE --version still warns, silently omitting the version ────────────
# Detection must not depend on `--version` succeeding — some builds print it to stderr,
# some exit non-zero — and must not become a second failure mode of its own.
run_probe 1 1
[ "$RP_RC" = "0" ] || fail "R4: rc=$RP_RC with an unreadable --version: $RP_OUT"
case "$RP_OUT" in
  *"$WARN"*) ;;
  *) fail "R4: a failing --version suppressed the warning — detection must not depend on it: $RP_OUT" ;;
esac
case "$RP_OUT" in
  *"[reports:"*) fail "R4: printed a version bracket although --version exited non-zero: $RP_OUT" ;;
esac
pass "E99-F12 R4 unreadable_version_still_warns_without_a_version"

# ── R5: a CORRECT grep is never warned about ─────────────────────────────────────────
# GNU and BSD grep are the assumed flavours and the overwhelming majority. A warning
# everybody sees is a warning nobody reads.
run_probe 0 0
[ "$RP_RC" = "0" ] || fail "R5: rc=$RP_RC on a correct grep: $RP_OUT"
case "$RP_OUT" in
  *"$WARN"*) fail "R5: warned about a grep that handles invalid UTF-8 correctly: $RP_OUT" ;;
esac
pass "E99-F12 R5 correct_grep_is_never_warned_about"

# ── R6: the warning goes to stderr, so a green run's stdout stays one line ────────────
_stdout="$(PATH="$T/bin:$PATH" SHIM_DROP_INVALID=1 SHIM_VERSION_FAILS=0 \
  sh "$SRC/tools/run-tests.sh" "$T/test_noop.sh" 2>/dev/null)"
case "$_stdout" in
  *"$WARN"*) fail "R6: the warning was written to stdout, which a green run keeps to one summary line: $_stdout" ;;
esac
case "$_stdout" in
  *"suites passed"*) ;;
  *) fail "R6 precondition: stdout carried no summary line at all, so the absence check above is vacuous: $_stdout" ;;
esac
pass "E99-F12 R6 warning_goes_to_stderr"

# ── R7: no grep at all is silent, not a false report ──────────────────────────────────
# "Your grep drops lines" would be a lie about a grep that is not there, and the suites
# fail loudly on their own. Fail-safe in the same direction as every other ambiguous case.
mkdir -p "$T/nogrep"
_missing=""
for _t in sh mktemp xargs basename cat rm dirname sed awk; do
  _p="$(command -v "$_t" 2>/dev/null)" || _p=""
  if [ -n "$_p" ]; then ln -sf "$_p" "$T/nogrep/$_t"; else _missing="$_missing $_t"; fi
done
if [ -n "$_missing" ]; then
  echo "ok - SKIPPED E99-F12 R7 (cannot build a grep-less PATH; missing:$_missing)"
elif PATH="$T/nogrep" sh -c 'command -v grep >/dev/null 2>&1'; then
  echo "ok - SKIPPED E99-F12 R7 (grep is still resolvable in the constructed PATH)"
else
  NG_OUT="$(PATH="$T/nogrep" sh "$SRC/tools/run-tests.sh" "$T/test_noop.sh" 2>&1)" && NG_RC=0 || NG_RC=$?
  [ "$NG_RC" = "0" ] \
    || fail "R7: an absent grep failed the run (rc=$NG_RC) — the probe must stay warn-only: $NG_OUT"
  case "$NG_OUT" in
    *"$WARN"*) fail "R7: reported that an ABSENT grep drops lines: $NG_OUT" ;;
  esac
  pass "E99-F12 R7 absent_grep_is_silent"
fi

echo "All grep-probe tests passed."
